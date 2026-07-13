// swiftlint:disable file_length
// SessionPreparer — Batch pre-analysis pipeline for playlist session preparation.
// Orchestrates: preview resolution → download → stem separation → MIR analysis
// → StemCache storage for every track before playback begins.
//
// Tracks whose previews are unavailable receive no cache entry; the real-time
// pipeline fills them during playback via the existing 5-second cadence.
//
// Pre-flight audit notes (U.4):
// - .analyzing(.mir) is NOT emitted as a separate transition. MIR runs inside the
//   nonisolated Task.detached block alongside stem separation; emitting mid-task
//   would require restructuring analyzePreview. TODO(U.4-followup): split detached block.
// - Download progress uses the -1 sentinel (indeterminate). URLSession progress
//   callback not wired. TODO(U.4-followup): wire URLSession download progress.
//
// LF.5 (D-132, 2026-05-27): adds `prepareLocalFiles(urls:placeholders:via:)` —
// the multi-file local-file twin of `prepare(tracks:)`. Walks an URL queue
// via a `LocalFilePreparing` delegate and publishes the same `trackStatuses`
// + `progress` SignalView the streaming path uses. The file_length disable
// above is the tracked acknowledgement that both pipelines own the same
// in-memory state machine; splitting requires widening property access
// across the engine module which leaks worse than the file_length warning.

import Audio
import Combine
import DSP
import Foundation
import ML
import Shared
import os.log

private let logger = Logger(subsystem: "com.phosphene", category: "SessionPreparer")

// MARK: - SessionPreparationResult

/// Summary of a completed batch pre-analysis pass.
public struct SessionPreparationResult: Sendable {

    /// Tracks successfully analyzed and stored in `cache`.
    public let cachedTracks: [TrackIdentity]

    /// Tracks that could not be analyzed (no preview or separation failure).
    public let failedTracks: [TrackIdentity]

    /// All walked tracks in **input order** — successes as their prepared
    /// identities, failures as their input/placeholder identities. This is
    /// the array a `SessionPlan` must be built from: on the LF path the plan
    /// index pairs positionally with the playback URL queue, so
    /// `cachedTracks + failedTracks` reorders the plan after any mid-queue
    /// failure and mispairs audio with identity/beat grid (BUG-068).
    public let orderedTracks: [TrackIdentity]

    /// The populated cache ready for the Orchestrator and VisualizerEngine.
    public let cache: StemCache

    public init(
        cachedTracks: [TrackIdentity],
        failedTracks: [TrackIdentity],
        orderedTracks: [TrackIdentity],
        cache: StemCache
    ) {
        self.cachedTracks = cachedTracks
        self.failedTracks = failedTracks
        self.orderedTracks = orderedTracks
        self.cache = cache
    }
}

// MARK: - PrepOutcomes

/// Accumulates per-track preparation outcomes while preserving input order
/// (BUG-068): every walked track lands in `ordered` exactly once — successes
/// as their prepared identities, failures as their input/placeholder
/// identities — so plans built from it stay index-aligned with the queue.
struct PrepOutcomes {
    private(set) var cached: [TrackIdentity] = []
    private(set) var failed: [TrackIdentity] = []
    private(set) var ordered: [TrackIdentity] = []

    var walkedCount: Int { ordered.count }

    mutating func success(_ track: TrackIdentity) {
        cached.append(track)
        ordered.append(track)
    }

    mutating func failure(_ track: TrackIdentity) {
        failed.append(track)
        ordered.append(track)
    }

    func result(cache: StemCache) -> SessionPreparationResult {
        SessionPreparationResult(
            cachedTracks: cached,
            failedTracks: failed,
            orderedTracks: ordered,
            cache: cache
        )
    }
}

// MARK: - SessionPreparationError

enum SessionPreparationError: Error, Sendable {
    case noPreviewURL(String)
    case downloadFailed(String)
    case analysisError(String)
}

// MARK: - SessionPreparer

/// Runs the full batch pre-analysis pipeline for a playlist.
///
/// Call `prepare(tracks:)` before playback to populate `StemCache`. The method
/// runs sequentially so the single `StemSeparator` is never called concurrently.
/// Progress updates are published on the main actor via `@Published var progress`
/// (legacy scalar) and `@Published var trackStatuses` (per-track, U.4).
@MainActor
public final class SessionPreparer: ObservableObject {

    // MARK: - Published State

    /// Current preparation progress as (completed, total). Legacy scalar; prefer `trackStatuses`.
    @Published public private(set) var progress: (completed: Int, total: Int) = (0, 0)

    /// Per-track preparation status. All tracks present from start of `prepare(tracks:)`.
    @Published public private(set) var trackStatuses: [TrackIdentity: TrackPreparationStatus] = [:]

    // MARK: - Dependencies

    private let resolver: any PreviewResolving
    private let downloader: any PreviewDownloading
    private let stemSeparator: any StemSeparating
    private let stemAnalyzer: any StemAnalyzing
    private let moodClassifier: any MoodClassifying
    private let beatGridAnalyzer: (any BeatGridAnalyzing)?
    /// Optional PANNs instrument-family analyzer (IFC.4 / D-177). When `nil`,
    /// `CachedTrackData.instrumentFamilySeries` is empty for every track.
    private let familyAnalyzer: (any InstrumentFamilyAnalyzing)?
    /// Optional metadata fetcher used to override ML-detected meter on
    /// odd time-signature tracks. Fetched in parallel with the preview
    /// PCM download during `prepareTrack`. When `nil` (e.g. tests, or no
    /// metadata sources configured), the cached `BeatGrid.beatsPerBar`
    /// carries the ML-detected value unchanged. Round 26 (2026-05-15).
    private let metadataFetcher: MetadataPreFetcher?

    /// Optional SessionRecorder for `WIRING:` instrumentation logs (BUG-006.1).
    /// `nil` in tests; wired through from `VisualizerEngine` in production so
    /// preparation-lifecycle log entries land in `session.log` for diagnosis.
    /// Optional SessionRecorder for `WIRING:` instrumentation logs (BUG-006.1).
    /// Visibility is `internal` so `SessionPreparer+WiringLogs.swift` can access it.
    let sessionRecorder: SessionRecorder?

    // MARK: - Cache

    /// Populated during `prepare(tracks:)`. Pass to VisualizerEngine before playback.
    public let cache: StemCache

    // MARK: - Cancellation

    private var preparationTask: Task<SessionPreparationResult, Never>?

    // MARK: - Network Failure Tracking

    /// Tracks tracks that failed specifically due to network-class errors (download or
    /// preview resolution failures). Used by `resumeFailedNetworkTracks()` to retry
    /// only the subset that can actually recover from a network change. D-061(d).
    private var networkFailedTracks: Set<TrackIdentity> = []

    /// PREPPERF.2 ②: set once the ML-graph warm-up has been launched, so a
    /// `resumeFailedNetworkTracks()` re-run doesn't warm an already-compiled graph.
    private var modelsWarmed = false

    /// PREPPERF.2 ②: gates the ML-graph warm-up (see init). Production: true.
    private let prewarmModels: Bool

    /// PREPPERF.2 ①: how many tracks' network fetch (resolve + download) may run
    /// ahead of the serial analysis cursor. Bounds concurrent downloads and stays
    /// within the resolver's rate limiter (D-011); matches `PreviewDownloader`'s
    /// default download concurrency.
    private static let prefetchWindow = 4

    // MARK: - Init

    /// Create a preparer with all injectable dependencies.
    ///
    /// - Parameters:
    ///   - resolver: Resolves preview URLs via iTunes Search API (injectable for testing).
    ///   - downloader: Downloads and decodes preview audio (injectable for testing).
    ///   - stemSeparator: MPSGraph-based stem separator (injectable for testing).
    ///   - stemAnalyzer: Per-stem energy analyzer (injectable for testing).
    ///   - moodClassifier: Valence/arousal classifier (injectable for testing).
    ///   - beatGridAnalyzer: Beat This! offline analyzer (optional). When `nil`,
    ///     `CachedTrackData.beatGrid` is `.empty` for every track — the live
    ///     beat-detection path remains the source of truth.
    ///   - cache: The StemCache to populate. Defaults to a fresh instance.
    ///   - prewarmModels: PREPPERF.2 ②. When `true` (production default), the first
    ///     `prepare` kicks a detached ML-graph warm-up. Tests that assert exact
    ///     `separate` / `analyzeBeatGrid` call counts pass `false` — the warm-up's
    ///     extra (and detached, hence non-deterministically-timed) model call would
    ///     otherwise pollute those counts.
    public init(
        resolver: any PreviewResolving,
        downloader: any PreviewDownloading,
        stemSeparator: any StemSeparating,
        stemAnalyzer: any StemAnalyzing,
        moodClassifier: any MoodClassifying,
        beatGridAnalyzer: (any BeatGridAnalyzing)? = nil,
        familyAnalyzer: (any InstrumentFamilyAnalyzing)? = nil,
        metadataFetcher: MetadataPreFetcher? = nil,
        cache: StemCache = StemCache(),
        sessionRecorder: SessionRecorder? = nil,
        prewarmModels: Bool = true
    ) {
        self.resolver = resolver
        self.downloader = downloader
        self.stemSeparator = stemSeparator
        self.stemAnalyzer = stemAnalyzer
        self.moodClassifier = moodClassifier
        self.beatGridAnalyzer = beatGridAnalyzer
        self.familyAnalyzer = familyAnalyzer
        self.metadataFetcher = metadataFetcher
        self.cache = cache
        self.sessionRecorder = sessionRecorder
        self.prewarmModels = prewarmModels
    }

    // MARK: - Prepare

    /// Analyze every track in the playlist and populate `cache`.
    ///
    /// Tracks are processed sequentially so the `StemSeparator` is never called
    /// concurrently. The work runs inside a stored `Task` so `cancelPreparation()`
    /// can interrupt it at stage boundaries.
    ///
    /// Status transitions for each track:
    ///   `.queued` → `.resolving` → `.downloading(-1)` → `.analyzing(.stemSeparation)`
    ///   → `.analyzing(.caching)` → `.ready` (success path)
    ///   → `.failed(reason:)` (no preview or download failure)
    ///   → `.partial(reason:)` (download OK but stem analysis failed)
    ///
    /// - Parameter tracks: Ordered list of tracks from the connected playlist.
    /// - Returns: Result with lists of cached/failed tracks and the populated cache.
    public func prepare(tracks: [TrackIdentity]) async -> SessionPreparationResult {
        // BUG-006.1 instrumentation: confirm preparation pipeline entry, including
        // whether the optional beat-grid analyzer is wired (hypothesis 3 discriminator).
        let firstTitle = tracks.first?.title ?? "<empty>"
        let bgPresent = beatGridAnalyzer == nil ? "nil" : "present"
        let enterMsg = "WIRING: SessionPreparer.prepare ENTER count=\(tracks.count) " +
            "firstTrack='\(firstTitle)' bgAnalyzer=\(bgPresent)"
        sessionRecorder?.log(enterMsg)
        logger.info("\(enterMsg, privacy: .public)")

        // Initialize all tracks to .queued at once before any async work begins.
        // BUG-030: a playlist can list the same track twice (identical
        // TrackIdentity); PlaylistConnecting promises duplicates preserve their
        // playlist order. `uniquingKeysWith` keeps the first .queued instead of
        // TRAPPING on the duplicate key (`uniqueKeysWithValues` did — audit §A2).
        // The per-identity status row collapses to one, but the loop below still
        // visits both occurrences (the second is a cheap cache hit), so a
        // twice-listed track yields two cachedTracks entries — two plan slots.
        trackStatuses = Dictionary(tracks.map { ($0, .queued) }, uniquingKeysWith: { first, _ in first })
        progress = (0, tracks.count)
        networkFailedTracks = []

        // Wrap the loop in a stored Task so cancelPreparation() can cancel it.
        // withTaskCancellationHandler propagates outer-task cancellation into the
        // inner unstructured task (which doesn't inherit it automatically).
        let task = Task { [self] in
            await self._runPreparation(tracks: tracks)
        }
        preparationTask = task
        let result = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        // LF.5.fix.3-B (extended at PUB.2): deliberately NO exit-nil — an
        // out-of-order return would drop a newer task's reference (e.g. a
        // resumeFailedNetworkTracks() loop started meanwhile would become
        // uncancellable). Explicit cancelPreparation() is the canonical clear.
        return result
    }

    // MARK: - LF.5 — Multi-file local-file preparation

    /// Run the LF.5 multi-file preparation pipeline against a `[URL]` queue.
    ///
    /// Sibling to `prepare(tracks:)` (streaming path) but driven by an URL list
    /// from the file picker / folder ingest / M3U parser instead of a
    /// connector. Walks the list sequentially via the `LocalFilePreparing`
    /// delegate (typically `VisualizerEngine` in the app layer), which owns
    /// the heavy ML deps + the persistent disk cache. Publishes per-track
    /// `TrackPreparationStatus` transitions keyed on the supplied placeholder
    /// identities so `PreparationProgressView` renders correctly for LF
    /// sessions just like it does for streaming sessions.
    ///
    /// Status transitions per file:
    ///   `.queued` → `.analyzing(.stemSeparation)` → `.analyzing(.caching)` → `.ready`   (cache hit / fresh analysis)
    ///   `.queued` → `.analyzing(.stemSeparation)` → `.partial(reason:)`                  (delegate returned `nil` — LF.1 fallthrough)
    ///
    /// Cancellation is honoured at file boundaries; the current in-flight
    /// per-file preparer call cannot itself be interrupted but unprocessed
    /// files are skipped immediately on the next iteration.
    ///
    /// - Parameters:
    ///   - urls: Ordered queue of local audio file URLs. Caller validates
    ///     readability + extension upstream.
    ///   - placeholders: One `TrackIdentity` per URL, in the same order. Used
    ///     as stable keys for `trackStatuses` (so UI rows track per-file
    ///     status without churn as real `local:sha256:` identities arrive).
    ///   - delegate: The `LocalFilePreparing` implementer that runs the
    ///     per-file hash + cache + analyze + persist work. When `nil`, every
    ///     file goes through the LF.1 no-cache fallthrough.
    /// - Returns: `SessionPreparationResult` with `cachedTracks` carrying the
    ///   real `local:sha256:<hash>` identities from successful preparation
    ///   and `failedTracks` carrying the placeholder identities for entries
    ///   the delegate could not prepare.
    public func prepareLocalFiles(
        urls: [URL],
        placeholders: [TrackIdentity],
        via delegate: (any LocalFilePreparing)?
    ) async -> SessionPreparationResult {
        precondition(urls.count == placeholders.count,
                     "prepareLocalFiles: urls and placeholders must align by index")

        // LF.5.fix.3-B: cancel any in-flight prep task before starting a new
        // one. The caller-side cancel() in SessionManager.startLocalFiles is
        // guarded on `state != .idle && state != .ended` — a user Stop between
        // picks moves state to .ended, bypassing cancellation and leaving the
        // previous prep running in parallel with the new one (see session
        // 2026-05-28T20-57-46Z: two `prepareLocalFile #1 of 5` log entries for
        // the same folder). Cancelling here closes that hole at the API
        // boundary instead of relying on every caller to know the rules.
        preparationTask?.cancel()

        // Initialize statuses + progress before any async work begins.
        // BUG-030 (LF twin of the trap in `prepare(tracks:)`): an M3U can list
        // the same file twice → identical placeholder identities. `uniquingKeysWith`
        // tolerates the duplicate key instead of trapping; both occurrences are
        // still walked by `_runLocalFilePreparation` below.
        trackStatuses = Dictionary(placeholders.map { ($0, .queued) }, uniquingKeysWith: { first, _ in first })
        progress = (0, urls.count)
        networkFailedTracks = []

        let enterMsg = "WIRING: SessionPreparer.prepareLocalFiles ENTER count=\(urls.count) " +
            "delegate=\(delegate == nil ? "nil" : "wired")"
        sessionRecorder?.log(enterMsg)
        logger.info("\(enterMsg, privacy: .public)")

        // Wrap the loop in a stored Task so cancelPreparation() can cancel it.
        let task = Task { [self] in
            await self._runLocalFilePreparation(
                urls: urls,
                placeholders: placeholders,
                delegate: delegate
            )
        }
        preparationTask = task
        let result = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        // LF.5.fix.3-B: see the comment in `prepare(tracks:)` — same
        // rationale. The field stays set so out-of-order returns can't drop
        // a newer task's reference.
        return result
    }

    private func _runLocalFilePreparation(
        urls: [URL],
        placeholders: [TrackIdentity],
        delegate: (any LocalFilePreparing)?
    ) async -> SessionPreparationResult {
        var outcomes = PrepOutcomes()

        for (index, pair) in zip(urls, placeholders).enumerated() {
            if Task.isCancelled { break }
            let (url, placeholder) = pair

            trackStatuses[placeholder] = .analyzing(stage: .stemSeparation)
            let result: LocalFilePrepResult? = await (delegate?.prepareLocalFile(url: url))
            if Task.isCancelled { break }

            let sourceLabel: String
            if let result {
                trackStatuses[placeholder] = .analyzing(stage: .caching)
                cache.store(result.cached, for: result.identity)
                trackStatuses[placeholder] = .ready
                outcomes.success(result.identity)
                sourceLabel = result.source.label
            } else {
                trackStatuses[placeholder] = .partial(reason: "Stems unavailable")
                outcomes.failure(placeholder)
                sourceLabel = "noCache"
            }

            progress = (outcomes.walkedCount, urls.count)
            let perFileMsg = "WIRING: SessionPreparer.prepareLocalFile #\(index + 1) " +
                "of \(urls.count) file='\(url.lastPathComponent)' source=\(sourceLabel)"
            sessionRecorder?.log(perFileMsg)
        }

        let doneMsg = "WIRING: SessionPreparer.prepareLocalFiles DONE " +
            "cached=\(outcomes.cached.count) failed=\(outcomes.failed.count) total=\(urls.count)"
        sessionRecorder?.log(doneMsg)
        logger.info("\(doneMsg, privacy: .public)")

        return outcomes.result(cache: cache)
    }

    // MARK: - PreparationProgressPublishing

    /// Publisher emitting the full `trackStatuses` dictionary on every change.
    public var trackStatusesPublisher: AnyPublisher<[TrackIdentity: TrackPreparationStatus], Never> {
        $trackStatuses.eraseToAnyPublisher()
    }

    /// Cancel the in-flight preparation pass.
    ///
    /// The current in-flight track may complete its MPSGraph predict (≤ 142 ms)
    /// before cancellation takes effect. Unprocessed tracks remain `.queued`.
    public func cancelPreparation() {
        preparationTask?.cancel()
        // LF.5.fix.3-B: clear the field on explicit cancel so a stale
        // reference doesn't outlive the cancelled task. The `prepare*`
        // entry points deliberately do NOT nil at exit (see comments
        // there); explicit cancel is the canonical way to clear.
        preparationTask = nil
    }

    // MARK: - Private

    private func _runPreparation(tracks: [TrackIdentity]) async -> SessionPreparationResult {
        // CLEAN.1.1 (BUG-032): more than one loop in flight means
        // resumeFailedNetworkTracks() spawned a second concurrent loop over the
        // shared StemSeparator (compounds BUG-031). Observability only.
        ConcurrencyAuditProbe.enterRunPreparation()
        defer { ConcurrencyAuditProbe.exitRunPreparation() }
        launchModelWarmUpIfNeeded()

        var outcomes = PrepOutcomes()

        // PREPPERF.2 ①: prefetch the network half (resolve + download) up to a
        // bounded window AHEAD of the serial analysis cursor, so a track's ~2 s
        // download overlaps the previous track's analysis instead of running
        // back-to-back. Analysis stays strictly in playlist order (one StemSeparator
        // call at a time — BUG-031) and the readiness prefix logic is unchanged.
        typealias FetchResult = Result<(PreviewAudio, PreFetchedTrackProfile?), Error>
        var fetchTasks: [Int: Task<FetchResult, Never>] = [:]
        defer { for task in fetchTasks.values { task.cancel() } }

        // Launch the fetch for `index` unless out of range, already launched, or a
        // cache hit (the consumer serves cache hits in order, no network needed).
        func launchFetch(_ index: Int) {
            guard index < tracks.count, fetchTasks[index] == nil else { return }
            let track = tracks[index]
            if cache.loadForPlayback(track: track) != nil { return }
            fetchTasks[index] = Task { [self] in
                do { return .success(try await fetchTrack(track)) } catch { return .failure(error) }
            }
        }

        for index in 0..<min(Self.prefetchWindow, tracks.count) { launchFetch(index) }

        for index in 0..<tracks.count {
            if Task.isCancelled { break }
            let track = tracks[index]

            // Cache-hit short-circuit — idempotent prepare, duplicates (BUG-030), resume.
            if cache.loadForPlayback(track: track) != nil {
                fetchTasks[index]?.cancel()
                fetchTasks[index] = nil
                trackStatuses[track] = .ready
                outcomes.success(track)
                progress = (outcomes.walkedCount, tracks.count)
                logger.info("Cache hit: \(track.title) — skipping re-analysis")
                launchFetch(index + Self.prefetchWindow)
                continue
            }

            if fetchTasks[index] == nil { launchFetch(index) }
            guard let fetchTask = fetchTasks[index] else { continue }
            // Await the (usually already-finished) prefetched fetch. The cancellation
            // handler cancels the in-flight fetch promptly so a Stop doesn't wait out a
            // full download — preserves prompt cancellation (processed == 0).
            let fetchResult = await withTaskCancellationHandler {
                await fetchTask.value
            } onCancel: {
                fetchTask.cancel()
            }
            fetchTasks[index] = nil
            // Check cancellation BEFORE refilling — otherwise a cancel mid-await would
            // still launch the next track's fetch, flipping it out of .queued (the
            // "unprocessed tracks stay .queued" contract).
            if Task.isCancelled { break }
            launchFetch(index + Self.prefetchWindow)   // keep the window full

            do {
                let (preview, profile) = try fetchResult.get()
                let data = try await analyzeFetched(preview, profile: profile, track: track)
                trackStatuses[track] = .analyzing(stage: .caching)
                cache.store(data, for: track)
                trackStatuses[track] = .ready
                outcomes.success(track)
                logger.info("Cached: \(track.title) by \(track.artist)")
            } catch {
                if recordPreparationFailure(error, track: track, outcomes: &outcomes) { break }
            }

            progress = (outcomes.walkedCount, tracks.count)
        }

        logger.info("Preparation complete: \(outcomes.cached.count)/\(tracks.count) cached, \(outcomes.failed.count) failed")
        logWiringDoneSummary(cachedTracks: outcomes.cached, failedTracks: outcomes.failed)

        return outcomes.result(cache: cache)
    }

    /// Map a fetch/analysis error to the track's terminal status + bookkeeping.
    /// Extracted from `_runPreparation` (PREPPERF.2 ①) to keep that loop under the
    /// complexity gate; the classification is byte-identical to the prior catch
    /// ladder. Returns `true` if the loop should break (cancellation).
    private func recordPreparationFailure(
        _ error: Error,
        track: TrackIdentity,
        outcomes: inout PrepOutcomes
    ) -> Bool {
        switch error {
        case is CancellationError:
            logger.info("Preparation cancelled")
            return true
        case SessionPreparationError.noPreviewURL(let title):
            trackStatuses[track] = .failed(reason: "Preview not available")
            networkFailedTracks.insert(track)
            logger.info("No preview for '\(title)'")
        case SessionPreparationError.downloadFailed(let title):
            trackStatuses[track] = .failed(reason: "Download failed")
            networkFailedTracks.insert(track)
            logger.info("Download failed for '\(title)'")
        case SessionPreparationError.analysisError(let detail):
            // Download succeeded; stems failed — playable in reactive mode.
            trackStatuses[track] = .partial(reason: "Stems unavailable")
            logger.info("Analysis failed for '\(track.title)': \(detail)")
        default:
            trackStatuses[track] = .failed(reason: "Unexpected error")
            logger.info("Failed to prepare '\(track.title)': \(error)")
        }
        outcomes.failure(track)
        return false
    }

    /// PREPPERF.2 ②: kick the ML-graph warm-up once per preparer, on the first
    /// `_runPreparation` (a `resumeFailedNetworkTracks()` re-run skips it). Pre-compiles
    /// the stem + beat-grid MPSGraphs on a silent buffer so the ~1 s first-call
    /// compilation (the cold tax on track 1, PREPPERF.1 data) overlaps the track-1
    /// network fetch instead of landing on the critical path. Both graphs are
    /// fixed-shape (StemSeparator pads to requiredMonoSamples; BeatThisModel's
    /// placeholder is tMax), so a short buffer compiles the identical real graph. The
    /// StemSeparator's internal lock serialises this vs the first real separate().
    private func launchModelWarmUpIfNeeded() {
        guard prewarmModels, !modelsWarmed else { return }
        modelsWarmed = true
        let separator = stemSeparator
        let gridAnalyzer = beatGridAnalyzer
        Task.detached(priority: .userInitiated) {
            SessionPreparer.warmUpModels(separator: separator, beatGridAnalyzer: gridAnalyzer)
        }
    }

    /// PREPPERF.2 ②: best-effort pre-compilation of the stem + beat-grid MPSGraphs.
    /// Runs one separation + one beat-grid pass over a short silent buffer to force
    /// MPSGraph compilation off the critical path. Both models pad/clamp internally to
    /// a fixed shape, so any buffer ≥ one hop compiles the same graph the real calls
    /// use. Errors are ignored — `predict()` compiles the graph regardless of any
    /// post-processing hiccup on silence, and a missed warm-up just means track 1 pays
    /// the cold tax (status quo). 1 s @ 44.1 kHz clears both models' minimum-frame needs.
    nonisolated static func warmUpModels(
        separator: any StemSeparating,
        beatGridAnalyzer: (any BeatGridAnalyzing)?
    ) {
        let rate = StemSeparator.modelSampleRate
        let silent = [Float](repeating: 0, count: Int(rate))
        _ = try? separator.separate(audio: silent, channelCount: 1, sampleRate: rate)
        _ = beatGridAnalyzer?.analyzeBeatGrid(samples: silent, sampleRate: Double(rate))
    }

    /// PREPPERF.2 ①: the network half — resolve → download + parallel metadata.
    /// Split from analysis so it can run AHEAD of the serial analysis stage in a
    /// bounded prefetch window (the StemSeparator lock constrains analysis, not the
    /// network). Sets `.resolving` / `.downloading`. Throws the same errors the old
    /// `prepareTrack` did, so the consumer's failure classification (and
    /// `networkFailedTracks` membership) is unchanged.
    private func fetchTrack(_ track: TrackIdentity) async throws -> (PreviewAudio, PreFetchedTrackProfile?) {
        // Resolve 30-second preview URL.
        trackStatuses[track] = .resolving
        guard let url = try await resolver.resolvePreviewURL(for: track) else {
            throw SessionPreparationError.noPreviewURL(track.title)
        }

        // Download + parallel metadata fetch (Round 26, 2026-05-15): the fetcher hits
        // Soundcharts / iTunes Search / MusicBrainz — same I/O class as the download.
        // Async-let gates: download required (throw on failure); metadata optional
        // (best-effort; nil means no meter override, ML-detected value stands).
        // TODO(U.4-followup): wire URLSession download progress callback; use -1 until then.
        trackStatuses[track] = .downloading(progress: -1)
        async let previewTask = downloader.download(track: track, from: url)
        async let profileTask: PreFetchedTrackProfile? = {
            guard let fetcher = self.metadataFetcher else { return nil }
            let trackMetadata = TrackMetadata(title: track.title, artist: track.artist)
            return await fetcher.prefetch(for: trackMetadata)
        }()
        guard let preview = await previewTask else {
            _ = await profileTask
            throw SessionPreparationError.downloadFailed(track.title)
        }
        let prefetchedProfile = await profileTask
        return (preview, prefetchedProfile)
    }

    /// PREPPERF.2 ①: the analysis half — stem separation → MIR → beat grid → cache
    /// data. Runs strictly serially in the consumer loop; the StemSeparator must
    /// never run concurrently (BUG-031). All CPU/GPU work is off the main actor via
    /// `Task.detached`. `.mir`/`.beatGrid` sub-stages aren't emitted separately
    /// (they run inside the detached task alongside stem separation).
    private func analyzeFetched(
        _ preview: PreviewAudio,
        profile: PreFetchedTrackProfile?,
        track: TrackIdentity
    ) async throws -> CachedTrackData {
        trackStatuses[track] = .analyzing(stage: .stemSeparation)
        let separator = stemSeparator
        let analyzer = stemAnalyzer
        let classifier = moodClassifier
        let gridAnalyzer = beatGridAnalyzer
        let famAnalyzer = familyAnalyzer

        do {
            return try await Task.detached(priority: .userInitiated) {
                try SessionPreparer.analyzePreview(
                    preview,
                    separator: separator,
                    analyzer: analyzer,
                    classifier: classifier,
                    beatGridAnalyzer: gridAnalyzer,
                    familyAnalyzer: famAnalyzer,
                    prefetchedProfile: profile
                )
            }.value
        } catch {
            throw SessionPreparationError.analysisError(error.localizedDescription)
        }
    }
}

// MARK: - Network Recovery

extension SessionPreparer {

    /// Retry tracks that previously failed due to network-class errors.
    ///
    /// Called by `NetworkRecoveryCoordinator` when reachability transitions
    /// `false → true` during `.preparing`. Resets eligible tracks to `.queued`
    /// and re-runs the preparation pipeline for them. Non-network failures
    /// (stem separation, malformed audio, missing preview) are left unchanged.
    ///
    /// If the original preparation task is still running, the recovered tracks
    /// will be processed sequentially after the current work finishes.
    /// If it has finished, a fresh task is spawned for the recovered tracks. D-061(d).
    public func resumeFailedNetworkTracks() async {
        let recoverCandidates = networkFailedTracks.filter {
            // Only attempt tracks still in a .failed state (not manually retried).
            if case .failed = trackStatuses[$0] { return true }
            return false
        }
        guard !recoverCandidates.isEmpty else { return }

        logger.info("NetworkRecovery: resuming \(recoverCandidates.count) network-failed track(s)")

        // Remove from the network-failed set immediately so a second rapid recovery
        // event doesn't queue them again while we're already retrying. D-061(d).
        networkFailedTracks.subtract(recoverCandidates)

        // Reset status to .queued so the UI reflects the resumed state.
        for track in recoverCandidates {
            trackStatuses[track] = .queued
        }

        // CLEAN.1.3 (BUG-032 defect 2): never run two `_runPreparation` loops over
        // the shared StemSeparator at once. If the original preparation loop is
        // still in flight, wait for it to finish before starting recovery, then run
        // recovery as a single fresh loop. (Was: an unconditional second Task that
        // interleaved with the original — progress ping-ponged between two
        // denominators and `cancelPreparation` lost the original's reference.)
        if let existing = preparationTask {
            _ = await existing.value
        }
        let sortedCandidates = Array(recoverCandidates)
        let task = Task { [self] in
            await self._runPreparation(tracks: sortedCandidates)
        }
        preparationTask = task
        _ = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        // PUB.2: no exit-nil (LF.5.fix.3-B pattern) — see prepare(tracks:).
    }
}

// MARK: - PreparationProgressPublishing Conformance

extension SessionPreparer: PreparationProgressPublishing {}

// BUG-006.1 wiring logs and BUG-008.2 BPM-mismatch warning live in
// `SessionPreparer+WiringLogs.swift` so this file stays under the 400-line gate.
