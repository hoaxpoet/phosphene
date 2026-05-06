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
        cache: StemCache = StemCache(),
        sessionRecorder: SessionRecorder? = nil
    ) {
        self.resolver = resolver
        self.downloader = downloader
        self.stemSeparator = stemSeparator
        self.stemAnalyzer = stemAnalyzer
        self.moodClassifier = moodClassifier
        self.beatGridAnalyzer = beatGridAnalyzer
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
        trackStatuses = Dictionary(uniqueKeysWithValues: tracks.map { ($0, .queued) })
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
    }

    // MARK: - Private

    private func _runPreparation(tracks: [TrackIdentity]) async -> SessionPreparationResult {
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
        guard let preview = await downloader.download(track: track, from: url) else {
            throw SessionPreparationError.downloadFailed(track.title)
        }

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
                    beatGridAnalyzer: gridAnalyzer
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

        // The original preparationTask may have completed. Always spawn a fresh task
        // for the recovered set — the sequential loop won't race because we own the
        // @MainActor here and the new task runs asynchronously. D-061 risk-note.
        let sortedCandidates = Array(recoverCandidates)
        let task = Task { [self] in
            await self._runPreparation(tracks: sortedCandidates)
        }
        preparationTask = task
        _ = await task.value
        preparationTask = nil
    }
}

// MARK: - PreparationProgressPublishing Conformance

extension SessionPreparer: PreparationProgressPublishing {}

// BUG-006.1 wiring logs and BUG-008.2 BPM-mismatch warning live in
// `SessionPreparer+WiringLogs.swift` so this file stays under the 400-line gate.
