// RhythmCharacter — Per-track rhythm metadata computed at preparation time
// (BSAudit.3 design §7).
//
// Consumed by `LiveBeatDriftTracker` at install time to scale phase-acquisition
// tunables to the track's actual rhythmic character — dense / sparse, on-beat /
// syncopated, single-tempo / octave-ambiguous. Without this metadata the
// runtime defaults are mediocre across the catalog (BSAudit.3 design §10.4).
//
// All five fields are derived from the existing 30 s preview audio + Beat This!
// output + `BeatDetector` per-band onsets — no new ML inference.

import Foundation

// MARK: - RhythmCharacter

/// Rhythm-character metadata for one track, computed during preparation.
///
/// Stored on `CachedTrackData.rhythmCharacter` and consumed by
/// `LiveBeatDriftTracker.installBPMPrior(bpm:character:)` to scale the
/// phase-acquisition tunables. Optional on the cache for backward
/// compatibility — older cache entries return nil and the runtime
/// treats nil as "neutral character" (mid-default tunables).
public struct RhythmCharacter: Sendable, Codable, Hashable {

    // MARK: - Fields

    /// Per-bar beat-slot mean energy profile. For 4/4 tracks, a 4-element
    /// array `[slot 1, slot 2, slot 3, slot 4]`. Higher = stronger energy
    /// typically at that slot. Drives per-slot visual emphasis at runtime
    /// and serves as the §9.3 mitigation: if runtime phase acquisition
    /// settles on the lowest-energy slot per this profile, that's a
    /// half-beat mis-alignment and the predictor can re-test the
    /// `offset + period/2` candidate.
    public let beatStrengthProfile: [Float]

    /// Average sub-bass onsets per beat over the preview. ~1.0 = sparse
    /// (kick on the beat only), 4+ = dense (busy hi-hat or arpeggiated
    /// bass). Used to tune phase-acquisition patience — sparse tracks get
    /// smaller gain and wider expectation window.
    public let onsetsPerBeat: Float

    /// 0.0–1.0 score for "this BPM might be the half or double of the
    /// true tempo." Computed from cachedBPM vs broadband-flux peak rate
    /// over the preview. When ≥ 0.5, runtime maintains two phase
    /// candidates (cachedBPM and 2×cachedBPM) and picks the higher-
    /// confidence one after a few confirmed predictions.
    public let octaveRisk: Float

    /// 0.0–1.0 score for "this track will be hard to phase-lock at
    /// runtime." Composed from `onsetsPerBeat` (low = harder),
    /// `syncopationIndex` (high = harder), and meter regularity
    /// (irregular = harder). Linearly interpolates the runtime tunables
    /// between the clean-four-on-the-floor defaults (gain 0.30, window
    /// ±50 ms, lockThreshold 0.8) and the sparse-syncopated defaults
    /// (gain 0.15, window ±80 ms, lockThreshold 0.5).
    public let phaseAcquisitionDifficulty: Float

    /// Syncopation index — fraction of detected sub-bass onsets that fall
    /// *outside* the nearest cached beat by more than ¼ beat. Captures
    /// off-beat sub-bass content (syncopated basslines). High = syncopated;
    /// low = on-beat.
    public let syncopationIndex: Float

    // MARK: - Init

    public init(
        beatStrengthProfile: [Float],
        onsetsPerBeat: Float,
        octaveRisk: Float,
        phaseAcquisitionDifficulty: Float,
        syncopationIndex: Float
    ) {
        self.beatStrengthProfile = beatStrengthProfile
        self.onsetsPerBeat = onsetsPerBeat
        self.octaveRisk = max(0, min(1, octaveRisk))
        self.phaseAcquisitionDifficulty = max(0, min(1, phaseAcquisitionDifficulty))
        self.syncopationIndex = max(0, min(1, syncopationIndex))
    }

    // MARK: - Neutral

    /// Neutral character used when no preparation-time metadata is available
    /// (live reactive mode, or a cache entry written before BSAudit.3
    /// landed). Mid-range difficulty, no octave risk — runtime uses the
    /// default tunable band.
    public static let neutral = RhythmCharacter(
        beatStrengthProfile: [],
        onsetsPerBeat: 1.0,
        octaveRisk: 0.0,
        phaseAcquisitionDifficulty: 0.5,
        syncopationIndex: 0.0
    )
}
