// TrackProfile — Pre-computed MIR features for a single track.
// Populated by SessionPreparer from the 30-second preview clip and stored
// in StemCache for instant access at playback start.

import Foundation
import Shared

// MARK: - TrackProfile

/// Pre-analyzed MIR summary for a track derived from its 30-second preview.
///
/// All fields are optional where the analysis may not converge in 30 seconds
/// (e.g., BPM estimation needs multiple beat onsets). The Orchestrator treats
/// nil fields as "unknown" and falls back to live MIR as playback progresses.
public struct TrackProfile: Sendable, Codable {

    // MARK: - Fields

    /// Estimated tempo in BPM, or nil if insufficient onset data.
    public var bpm: Float?

    /// Estimated musical key (e.g. "C major", "F# minor"), or nil if atonal/percussive.
    public var key: String?

    /// Emotional state (valence × arousal) from the mood classifier.
    public var mood: EmotionalState

    /// Average normalized spectral centroid across the preview (0–1).
    public var spectralCentroidAvg: Float

    /// Genre tags from external APIs. Empty when no pre-fetch data is available.
    public var genreTags: [String]

    /// Per-stem energy balance from the preview separation (GPU buffer(3) layout).
    public var stemEnergyBalance: StemFeatures

    /// Coarse section count estimated from 30 seconds of structural analysis.
    /// Typically 1–3 for a 30-second preview window.
    public var estimatedSectionCount: Int

    /// Does the track lack a steady, trustworthy beat? (FBS / D-154.)
    /// Computed at consumption time from the cached grids via
    /// `assessBeatIrregularity` (octave-folded full-mix-vs-drums BPM
    /// disagreement + bar confidence). `true` ⇒ the scorer hard-excludes
    /// presets declaring `requires_regular_beat` (Ferrofluid Ocean — Matt's
    /// 2026-06-10 rule: irregular tracks never see FFO). `nil` = unknown
    /// (missing estimators / pre-D-154 cache entries) — permissive, no
    /// exclusion. Optional so old persisted profiles decode unchanged.
    public var beatIrregular: Bool?

    // MARK: - Init

    public init(
        bpm: Float? = nil,
        key: String? = nil,
        mood: EmotionalState = .neutral,
        spectralCentroidAvg: Float = 0,
        genreTags: [String] = [],
        stemEnergyBalance: StemFeatures = .zero,
        estimatedSectionCount: Int = 0,
        beatIrregular: Bool? = nil
    ) {
        self.bpm = bpm
        self.key = key
        self.mood = mood
        self.spectralCentroidAvg = spectralCentroidAvg
        self.genreTags = genreTags
        self.stemEnergyBalance = stemEnergyBalance
        self.estimatedSectionCount = estimatedSectionCount
        self.beatIrregular = beatIrregular
    }

    // MARK: - Defaults

    /// Empty profile — all fields at zero or nil.
    public static let empty = TrackProfile()
}
