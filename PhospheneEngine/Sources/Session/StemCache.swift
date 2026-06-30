// StemCache — Thread-safe per-track storage for pre-analyzed session data.
// Populated by SessionPreparer before playback; consumed by VisualizerEngine
// on track change to eliminate the ~10-second stem warmup gap.

import DSP
import Foundation
import ML
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

    /// Per-track offset (ms) between Beat This! grid timing and the live sub-bass
    /// onset detector (BUG-007.8). Computed at preparation time by
    /// `GridOnsetCalibrator` running our `BeatDetector` offline against the same
    /// preview audio that produced `beatGrid`. Consumed by
    /// `LiveBeatDriftTracker.setGrid(_:initialDriftMs:)` as the EMA's initial
    /// bias so drift starts at the right value rather than chasing it at runtime.
    /// Defaults to 0 for backward compatibility — pre-fix calibration omitted.
    public let gridOnsetOffsetMs: Double

    /// IFC.4 (D-177) — per-window instrument-family activity over the preview
    /// clip (2 s window / 1 s hop, in playback order). Layer 5a: available from
    /// frame 1 but not time-aligned to live playback; the live frame samples it
    /// by playback position (`InstrumentFamilyActivity.sample`). Empty when no
    /// `InstrumentFamilyAnalyzing` was wired. In-memory only — NOT persisted to
    /// `PersistentStemCache` (IFC.4 scope; disk-cache reload yields an empty
    /// series → family fields clear to 0, the no-activity fallback).
    public let instrumentFamilySeries: [InstrumentFamilyActivity]

    // MARK: - Init

    public init(
        stemWaveforms: [[Float]],
        stemFeatures: StemFeatures,
        trackProfile: TrackProfile,
        beatGrid: BeatGrid = .empty,
        drumsBeatGrid: BeatGrid = .empty,
        gridOnsetOffsetMs: Double = 0,
        instrumentFamilySeries: [InstrumentFamilyActivity] = []
    ) {
        self.stemWaveforms = stemWaveforms
        self.stemFeatures = stemFeatures
        self.trackProfile = trackProfile
        self.beatGrid = beatGrid
        self.drumsBeatGrid = drumsBeatGrid
        self.gridOnsetOffsetMs = gridOnsetOffsetMs
        self.instrumentFamilySeries = instrumentFamilySeries
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
    /// LRU order, least-recently-used first. `touchLocked` moves a key to the end on
    /// store and on `loadForPlayback` (the metadata accessors don't bump recency —
    /// they're planning-time peeks, not playback). ponytail: O(n) array reorder is fine
    /// — n ≤ `maxEntries` and this is touched per track-change, never per frame.
    private var lruOrder: [TrackIdentity] = []
    private let maxEntries: Int
    private let lock = NSLock()

    // MARK: - Init

    /// Default in-memory LRU cap. Each `CachedTrackData` holds ~10 s of 4 separated
    /// stems (~7 MB), so 64 bounds the cache to ~450 MB — the same order as the on-disk
    /// `PersistentStemCache` LRU. Streaming preview data has no disk backing, so an
    /// evicted track is re-prepared on next demand (CLEAN.3.5).
    public static let defaultMaxEntries = 64

    /// Creates a cache with the default LRU cap. Kept as a distinct no-arg initializer
    /// (rather than a defaulted parameter on `init(maxEntries:)`) so existing
    /// `StemCache()` call sites keep the same mangled `init()` symbol — changing it to a
    /// defaulted parameter alters the symbol and breaks incremental builds whose
    /// dependents weren't recompiled (e.g. `SessionPreparer.init`'s
    /// `cache: StemCache = StemCache()` default-argument thunk). CLEAN.3.5.
    public convenience init() {
        self.init(maxEntries: Self.defaultMaxEntries)
    }

    /// Creates a cache with an explicit LRU cap (used by tests).
    public init(maxEntries: Int) {
        self.maxEntries = max(1, maxEntries)
    }

    // MARK: - Write

    /// Store pre-analyzed data for a track, replacing any existing entry, and evict the
    /// least-recently-used track if this pushes the cache past `maxEntries` (CLEAN.3.5).
    public func store(_ data: CachedTrackData, for identity: TrackIdentity) {
        lock.withLock {
            storage[identity] = data
            touchLocked(identity)
            evictIfNeededLocked()
        }
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

    /// Does the track lack a steady, trustworthy beat? (FBS / D-154.)
    ///
    /// Combines the cached full-mix and drums-stem grids via
    /// `assessBeatIrregularity` (octave-folded BPM disagreement + bar
    /// confidence). `true` ⇒ beat-locked presets (`requires_regular_beat`)
    /// are hard-excluded for this track; `nil` = unknown (uncached track or
    /// missing estimator) — permissive.
    public func beatIrregular(for identity: TrackIdentity) -> Bool? {
        let (grid, drums): (BeatGrid?, BeatGrid?) = lock.withLock {
            (storage[identity]?.beatGrid, storage[identity]?.drumsBeatGrid)
        }
        guard let grid else { return nil }
        return assessBeatIrregularity(
            gridBPM: grid.bpm,
            drumsBPM: drums?.bpm ?? 0,
            barConfidence: grid.barConfidence
        )
    }

    /// Return the full `CachedTrackData` bundle for playback, or nil if uncached.
    ///
    /// Called by `VisualizerEngine` on track change to populate the stem pipeline
    /// from pre-separated waveforms rather than waiting for live separation.
    public func loadForPlayback(track: TrackIdentity) -> CachedTrackData? {
        lock.withLock {
            guard let data = storage[track] else { return nil }
            touchLocked(track)   // playback use bumps LRU recency
            return data
        }
    }

    // MARK: - Housekeeping

    /// Number of tracks currently in the cache.
    public var count: Int {
        lock.withLock { storage.count }
    }

    /// Remove all cached entries.
    public func clear() {
        lock.withLock {
            storage.removeAll()
            lruOrder.removeAll()
        }
    }

    // MARK: - LRU (caller must hold `lock`)

    /// Move `identity` to the most-recently-used end of `lruOrder`.
    private func touchLocked(_ identity: TrackIdentity) {
        if let idx = lruOrder.firstIndex(of: identity) {
            lruOrder.remove(at: idx)
        }
        lruOrder.append(identity)
    }

    /// Evict least-recently-used entries until `storage.count <= maxEntries`.
    private func evictIfNeededLocked() {
        while storage.count > maxEntries, let oldest = lruOrder.first {
            lruOrder.removeFirst()
            storage[oldest] = nil
        }
    }
}
