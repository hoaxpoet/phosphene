// LocalFilePreparing — protocol that `SessionManager.startLocalFile(at:)` delegates
// to for the actual hash + persistent-cache + analyze + persist work. The deps
// (StemSeparator, StemAnalyzer, MoodClassifier, BeatGridAnalyzer, PersistentStemCache,
// SessionRecorder) all live on `VisualizerEngine` in the app layer; the protocol
// lets SessionManager drive the lifecycle without growing those imports.

import Foundation

// MARK: - LocalFilePrepResult

/// Bundle returned by `LocalFilePreparing.prepareLocalFile(url:)` on success.
/// Carries the freshly-loaded cached data + the synthetic track identity +
/// a label describing the source (cache hit vs fresh analysis) for the
/// session-log breadcrumb.
public struct LocalFilePrepResult: Sendable {

    /// Kind of source the result came from. Mirrors LF.3's `LocalFilePrepOutcome.Source`.
    public enum Source: Sendable {
        case persistentDisk
        case freshAnalysis

        public var label: String {
            switch self {
            case .persistentDisk: return "persistentDisk"
            case .freshAnalysis: return "freshAnalysis"
            }
        }
    }

    /// Synthetic `TrackIdentity` for the local file. `spotifyID` has the
    /// `local:sha256:<hash>` form (LF.3 / D-130) so cache lookups don't
    /// collide with any real catalog track.
    public let identity: TrackIdentity

    /// Pre-analyzed track data. Already stored in the in-memory
    /// `StemCache` by the implementer if available; the publisher
    /// also keeps it around for the caller in case re-store is wanted.
    public let cached: CachedTrackData

    /// Duration of the source audio file, in seconds.
    public let decodedDuration: TimeInterval

    /// Where the data came from (disk cache hit vs fresh analysis).
    public let source: Source

    /// Raw artwork bytes (PNG / JPEG, depending on container) lifted from
    /// the LF.5 persistent cache's `artwork.bin` sibling on a cache hit, or
    /// extracted directly by `PreviewAudio.extractArtwork(at:)` on a fresh
    /// analysis. `nil` when the source file shipped no embedded artwork.
    /// LF.6: consumed by the engine's `currentTrackArtworkData` publisher.
    public let artworkData: Data?

    public init(
        identity: TrackIdentity,
        cached: CachedTrackData,
        decodedDuration: TimeInterval,
        source: Source,
        artworkData: Data? = nil
    ) {
        self.identity = identity
        self.cached = cached
        self.decodedDuration = decodedDuration
        self.source = source
        self.artworkData = artworkData
    }
}

// MARK: - LocalFilePreparing

/// Protocol implemented by the app-layer entity that owns the heavy ML
/// dependencies (`VisualizerEngine`). `SessionManager.startLocalFile(at:)`
/// calls into this protocol so the engine can run the hash + cache + analyze
/// + persist pipeline without `SessionManager` itself having to import
/// every ML module.
///
/// Implementations are responsible for:
///   1. Hashing the file off-main (~30 ms for typical AAC).
///   2. Consulting the persistent cache (cache hit → load + return).
///   3. Running `SessionPreparer.analyzePreview` on cache miss.
///   4. Persisting the fresh analysis result back to the disk cache.
///   5. Logging `STEM_CACHE_HIT` / `STEM_CACHE_MISS` / `STEM_CACHE_WROTE`
///      session-log breadcrumbs matching the LF.3 format.
///
/// Returning `nil` signals "preparation failed; caller should fall through
/// to LF.1 no-cache start." Non-nil result means the cached data has been
/// stored in the live `StemCache` and the identity is ready for
/// `resetStemPipeline(for:)`.
public protocol LocalFilePreparing: AnyObject, Sendable {
    /// Run the LF.4 preparation pipeline for the given local file.
    ///
    /// - Parameter url: Local audio file to prepare. Caller must verify
    ///   the URL is readable before invoking.
    /// - Returns: A `LocalFilePrepResult` on success, or `nil` if the
    ///   file could not be hashed, analyzed, or otherwise prepared.
    ///   `nil` is non-fatal — the LF.1 live-analyze fallthrough still
    ///   gets the user playback, just without the cached BeatGrid.
    func prepareLocalFile(url: URL) async -> LocalFilePrepResult?
}
