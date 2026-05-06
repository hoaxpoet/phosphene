// StemCache — Thread-safe per-track storage for pre-analyzed session data.
// Populated by SessionPreparer before playback; consumed by VisualizerEngine
// on track change to eliminate the ~10-second stem warmup gap.

import DSP
import Foundation
import Shared

// MARK: - CachedTrackData

/// All pre-computed data for a single track.
///
/// Stored by `StemCache` and loaded by `VisualizerEngine` at the start of
/// each track so the visual show begins with warmed-up, accurate stems.
public struct CachedTrackData: Sendable {

    /// Separated stem waveforms, ordered [vocals, drums, bass, other].
    /// Each is mono Float32 at 44100 Hz, ~10 seconds long.
    public let stemWaveforms: [[Float]]

    /// Pre-analyzed per-stem energy snapshot ready for GPU buffer(3) upload.
    public let stemFeatures: StemFeatures

    /// MIR summary: BPM, key, mood, spectral centroid, stem energy balance.
    public let trackProfile: TrackProfile

    /// Offline beat/downbeat grid resolved from Beat This! over the preview clip.
    /// Defaults to `.empty` when no beat-grid analyzer is wired (backward compat).
    public let beatGrid: BeatGrid

    /// Offline beat/downbeat grid resolved from Beat This! over the **drums stem only**.
    /// Logged alongside `beatGrid` at preparation time (DSP.4 diagnostic).
    /// Not consumed by `LiveBeatDriftTracker` — full-mix grid is the runtime source.
    /// Defaults to `.empty` when no beat-grid analyzer is wired.
    public let drumsBeatGrid: BeatGrid

    // MARK: - Init

    public init(
        stemWaveforms: [[Float]],
        stemFeatures: StemFeatures,
        trackProfile: TrackProfile,
        beatGrid: BeatGrid = .empty,
        drumsBeatGrid: BeatGrid = .empty
    ) {
        self.stemWaveforms = stemWaveforms
        self.stemFeatures = stemFeatures
        self.trackProfile = trackProfile
        self.beatGrid = beatGrid
        self.drumsBeatGrid = drumsBeatGrid
    }
}

// MARK: - StemCache

/// Thread-safe dictionary keyed by `TrackIdentity`.
///
/// All public methods acquire a lock before accessing `storage`, making
/// the cache safe to read from the main actor and write from the preparation
/// background task concurrently.
public final class StemCache: @unchecked Sendable {

    // MARK: - State

    private var storage: [TrackIdentity: CachedTrackData] = [:]
    private let lock = NSLock()

    // MARK: - Init

    public init() {}

    // MARK: - Write

    /// Store pre-analyzed data for a track, replacing any existing entry.
    public func store(_ data: CachedTrackData, for identity: TrackIdentity) {
        lock.withLock { storage[identity] = data }
    }

    // MARK: - Read

    /// Return the pre-analyzed `StemFeatures` for the given track, or nil if not cached.
    public func stemFeatures(for identity: TrackIdentity) -> StemFeatures? {
        lock.withLock { storage[identity]?.stemFeatures }
    }

    /// Return the `TrackProfile` for the given track, or nil if not cached.
    public func trackProfile(for identity: TrackIdentity) -> TrackProfile? {
        lock.withLock { storage[identity]?.trackProfile }
    }

    /// Return the offline `BeatGrid` for the given track, or nil if not cached.
    public func beatGrid(for identity: TrackIdentity) -> BeatGrid? {
        lock.withLock { storage[identity]?.beatGrid }
    }

    /// Return the drums-stem `BeatGrid` for the given track, or nil if not cached.
    /// Diagnostic only (DSP.4) — not consumed by the live drift tracker.
    public func drumsBeatGrid(for identity: TrackIdentity) -> BeatGrid? {
        lock.withLock { storage[identity]?.drumsBeatGrid }
    }

    /// Return the full `CachedTrackData` bundle for playback, or nil if uncached.
    ///
    /// Called by `VisualizerEngine` on track change to populate the stem pipeline
    /// from pre-separated waveforms rather than waiting for live separation.
    public func loadForPlayback(track: TrackIdentity) -> CachedTrackData? {
        lock.withLock { storage[track] }
    }

    // MARK: - Housekeeping

    /// Number of tracks currently in the cache.
    public var count: Int {
        lock.withLock { storage.count }
    }

    /// Remove all cached entries.
    public func clear() {
        lock.withLock { storage.removeAll() }
    }
}
