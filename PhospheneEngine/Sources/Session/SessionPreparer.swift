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

    /// The populated cache ready for the Orchestrator and VisualizerEngine.
    public let cache: StemCache

    public init(cachedTracks: [TrackIdentity], failedTracks: [TrackIdentity], cache: StemCache) {
        self.cachedTracks = cachedTracks
        self.failedTracks = failedTracks
        self.cache = cache
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
    public init(
        resolver: any PreviewResolving,
        downloader: any PreviewDownloading,
        stemSeparator: any StemSeparating,
        stemAnalyzer: any StemAnalyzing,
        moodClassifier: any MoodClassifying,
        beatGridAnalyzer: (any BeatGridAnalyzing)? = nil,
        metadataFetcher: MetadataPreFetcher? = nil,
        cache: StemCache = StemCache(),
        sessionRecorder: SessionRecorder? = nil
    ) {
        self.resolver = resolver
        self.downloader = downloader
        self.stemSeparator = stemSeparator
        self.stemAnalyzer = stemAnalyzer
        self.moodClassifier = moodClassifier
        self.beatGridAnalyzer = beatGridAnalyzer
        self.metadataFetcher = metadataFetcher
        self.cache = cache
        self.sessionRecorder = sessionRecorder
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
        preparationTask = nil
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
        var cachedTracks: [TrackIdentity] = []
        var failedTracks: [TrackIdentity] = []

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
                cachedTracks.append(result.identity)
                sourceLabel = result.source.label
            } else {
                trackStatuses[placeholder] = .partial(reason: "Stems unavailable")
                failedTracks.append(placeholder)
                sourceLabel = "noCache"
            }

            let done = cachedTracks.count + failedTracks.count
            progress = (done, urls.count)
            let perFileMsg = "WIRING: SessionPreparer.prepareLocalFile #\(index + 1) " +
                "of \(urls.count) file='\(url.lastPathComponent)' source=\(sourceLabel)"
            sessionRecorder?.log(perFileMsg)
        }

        let doneMsg = "WIRING: SessionPreparer.prepareLocalFiles DONE " +
            "cached=\(cachedTracks.count) failed=\(failedTracks.count) total=\(urls.count)"
        sessionRecorder?.log(doneMsg)
        logger.info("\(doneMsg, privacy: .public)")

        return SessionPreparationResult(
            cachedTracks: cachedTracks,
            failedTracks: failedTracks,
            cache: cache
        )
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
        var cachedTracks: [TrackIdentity] = []
        var failedTracks: [TrackIdentity] = []

        for track in tracks {
            if Task.isCancelled { break }

            // Cache-hit short-circuit — idempotent prepare(tracks:) skips re-analysis.
            if cache.loadForPlayback(track: track) != nil {
                trackStatuses[track] = .ready
                cachedTracks.append(track)
                let done = cachedTracks.count + failedTracks.count
                progress = (done, tracks.count)
                logger.info("Cache hit: \(track.title) — skipping re-analysis")
                continue
            }

            do {
                let data = try await prepareTrack(track)

                trackStatuses[track] = .analyzing(stage: .caching)
                cache.store(data, for: track)
                trackStatuses[track] = .ready

                cachedTracks.append(track)
                logger.info("Cached: \(track.title) by \(track.artist)")
            } catch is CancellationError {
                logger.info("Preparation cancelled after \(cachedTracks.count) tracks")
                break
            } catch SessionPreparationError.noPreviewURL(let title) {
                failedTracks.append(track)
                trackStatuses[track] = .failed(reason: "Preview not available")
                networkFailedTracks.insert(track)
                logger.info("No preview for '\(title)'")
            } catch SessionPreparationError.downloadFailed(let title) {
                failedTracks.append(track)
                trackStatuses[track] = .failed(reason: "Download failed")
                networkFailedTracks.insert(track)
                logger.info("Download failed for '\(title)'")
            } catch SessionPreparationError.analysisError(let detail) {
                // Download succeeded; stems failed — playable in reactive mode.
                failedTracks.append(track)
                trackStatuses[track] = .partial(reason: "Stems unavailable")
                logger.info("Analysis failed for '\(track.title)': \(detail)")
            } catch {
                failedTracks.append(track)
                trackStatuses[track] = .failed(reason: "Unexpected error")
                logger.info("Failed to prepare '\(track.title)': \(error)")
            }

            let done = cachedTracks.count + failedTracks.count
            progress = (done, tracks.count)
        }

        logger.info("Preparation complete: \(cachedTracks.count)/\(tracks.count) cached, \(failedTracks.count) failed")
        logWiringDoneSummary(cachedTracks: cachedTracks, failedTracks: failedTracks)

        return SessionPreparationResult(
            cachedTracks: cachedTracks,
            failedTracks: failedTracks,
            cache: cache
        )
    }

    private func prepareTrack(_ track: TrackIdentity) async throws -> CachedTrackData {
        // Resolve 30-second preview URL.
        trackStatuses[track] = .resolving
        guard let url = try await resolver.resolvePreviewURL(for: track) else {
            throw SessionPreparationError.noPreviewURL(track.title)
        }

        // Download and decode to mono PCM.
        // TODO(U.4-followup): wire URLSession download progress callback; use -1 until then.
        trackStatuses[track] = .downloading(progress: -1)
        // Round 26 (2026-05-15): fetch metadata in parallel with the PCM
        // download. The fetcher hits Soundcharts / iTunes Search /
        // MusicBrainz over the network — same I/O class as the download.
        // Async-let gates: the download value is required (throw on
        // failure); the metadata is optional (best-effort; nil on
        // failure means no override gets applied, ML-detected meter
        // stands).
        async let previewTask = downloader.download(track: track, from: url)
        async let profileTask: PreFetchedTrackProfile? = {
            guard let fetcher = self.metadataFetcher else { return nil }
            let trackMetadata = TrackMetadata(
                title: track.title,
                artist: track.artist
            )
            return await fetcher.prefetch(for: trackMetadata)
        }()
        guard let preview = await previewTask else {
            throw SessionPreparationError.downloadFailed(track.title)
        }
        let prefetchedProfile = await profileTask

        // All CPU-bound analysis runs off the main actor.
        // NOTE: .mir and .beatGrid sub-stages are not emitted separately
        // (both run inside the detached task alongside stem separation).
        trackStatuses[track] = .analyzing(stage: .stemSeparation)
        let separator = stemSeparator
        let analyzer = stemAnalyzer
        let classifier = moodClassifier
        let gridAnalyzer = beatGridAnalyzer

        do {
            return try await Task.detached(priority: .userInitiated) {
                try SessionPreparer.analyzePreview(
                    preview,
                    separator: separator,
                    analyzer: analyzer,
                    classifier: classifier,
                    beatGridAnalyzer: gridAnalyzer,
                    prefetchedProfile: prefetchedProfile
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
        preparationTask = nil
    }
}

// MARK: - PreparationProgressPublishing Conformance

extension SessionPreparer: PreparationProgressPublishing {}

// BUG-006.1 wiring logs and BUG-008.2 BPM-mismatch warning live in
// `SessionPreparer+WiringLogs.swift` so this file stays under the 400-line gate.
