// SessionPreparer — Batch pre-analysis pipeline for playlist session preparation.
// Orchestrates: preview resolution → download → stem separation → MIR analysis
// → StemCache storage for every track before playback begins.
//
// Tracks whose previews are unavailable receive no cache entry; the real-time
// pipeline fills them during playback via the existing 5-second cadence.

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
/// Progress updates are published on the main actor via `@Published var progress`.
@MainActor
public final class SessionPreparer: ObservableObject {

    // MARK: - Published State

    /// Current preparation progress as (completed, total).
    @Published public private(set) var progress: (completed: Int, total: Int) = (0, 0)

    // MARK: - Dependencies

    private let resolver: any PreviewResolving
    private let downloader: any PreviewDownloading
    private let stemSeparator: any StemSeparating
    private let stemAnalyzer: any StemAnalyzing
    private let moodClassifier: any MoodClassifying

    // MARK: - Cache

    /// Populated during `prepare(tracks:)`. Pass to VisualizerEngine before playback.
    public let cache: StemCache

    // MARK: - Init

    /// Create a preparer with all injectable dependencies.
    ///
    /// - Parameters:
    ///   - resolver: Resolves preview URLs via iTunes Search API (injectable for testing).
    ///   - downloader: Downloads and decodes preview audio (injectable for testing).
    ///   - stemSeparator: MPSGraph-based stem separator (injectable for testing).
    ///   - stemAnalyzer: Per-stem energy analyzer (injectable for testing).
    ///   - moodClassifier: Valence/arousal classifier (injectable for testing).
    ///   - cache: The StemCache to populate. Defaults to a fresh instance.
    public init(
        resolver: any PreviewResolving,
        downloader: any PreviewDownloading,
        stemSeparator: any StemSeparating,
        stemAnalyzer: any StemAnalyzing,
        moodClassifier: any MoodClassifying,
        cache: StemCache = StemCache()
    ) {
        self.resolver = resolver
        self.downloader = downloader
        self.stemSeparator = stemSeparator
        self.stemAnalyzer = stemAnalyzer
        self.moodClassifier = moodClassifier
        self.cache = cache
    }

    // MARK: - Prepare

    /// Analyze every track in the playlist and populate `cache`.
    ///
    /// Tracks are processed sequentially so the `StemSeparator` is never called
    /// concurrently. CPU-bound work (stem separation, FFT, MIR) runs in a
    /// detached task to keep the main actor free.
    ///
    /// - Parameter tracks: Ordered list of tracks from the connected playlist.
    /// - Returns: Result with lists of cached/failed tracks and the populated cache.
    public func prepare(tracks: [TrackIdentity]) async -> SessionPreparationResult {
        progress = (0, tracks.count)
        var cachedTracks: [TrackIdentity] = []
        var failedTracks: [TrackIdentity] = []

        for track in tracks {
            if Task.isCancelled { break }

            do {
                let data = try await prepareTrack(track)
                cache.store(data, for: track)
                cachedTracks.append(track)
                logger.info("Cached: \(track.title) by \(track.artist)")
            } catch is CancellationError {
                logger.info("Preparation cancelled after \(cachedTracks.count) tracks")
                break
            } catch {
                failedTracks.append(track)
                logger.info("Failed to prepare '\(track.title)': \(error)")
            }

            let done = cachedTracks.count + failedTracks.count
            progress = (done, tracks.count)
        }

        logger.info("Preparation complete: \(cachedTracks.count)/\(tracks.count) cached, \(failedTracks.count) failed")
        return SessionPreparationResult(
            cachedTracks: cachedTracks,
            failedTracks: failedTracks,
            cache: cache
        )
    }

    // MARK: - Private

    private func prepareTrack(_ track: TrackIdentity) async throws -> CachedTrackData {
        // Resolve 30-second preview URL.
        guard let url = try await resolver.resolvePreviewURL(for: track) else {
            throw SessionPreparationError.noPreviewURL(track.title)
        }

        // Download and decode to mono PCM.
        guard let preview = await downloader.download(track: track, from: url) else {
            throw SessionPreparationError.downloadFailed(track.title)
        }

        // All CPU-bound analysis runs off the main actor.
        let separator = stemSeparator
        let analyzer = stemAnalyzer
        let classifier = moodClassifier

        return try await Task.detached(priority: .userInitiated) {
            try SessionPreparer.analyzePreview(
                preview,
                separator: separator,
                analyzer: analyzer,
                classifier: classifier
            )
        }.value
    }
}
