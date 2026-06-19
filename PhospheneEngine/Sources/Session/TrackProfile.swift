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

    /// LFPLAN.5: detected section-boundary times in seconds, relative to track start
    /// (the structural detector's `boundaryTimestamps` — section starts, not including 0).
    /// Present only when the pre-analysis ran on the **full** track (local-file playback);
    /// `nil` for streaming 30 s previews and for profiles cached before LFPLAN.5. The
    /// planner segments on these real times when they span the track, else equal slices.
    /// Optional so old persisted profiles decode unchanged.
    public var sectionStartTimes: [TimeInterval]?

    /// Does the track lack a steady, trustworthy beat? (FBS / D-154.)
    /// Computed at consumption time from the cached grids via
    /// `assessBeatIrregularity` (octave-folded full-mix-vs-drums BPM
    /// disagreement + bar confidence). `true` ⇒ the scorer hard-excludes
    /// presets declaring `requires_regular_beat`. **No production preset
    /// declares the flag since the D-154 amendment (2026-06-11): the FFO ban
    /// is retired** — Matt's pick after FFO on Pyramid Song (the gate's
    /// canonical catch, where the live tracker in fact LOCKED at 5.4 s)
    /// "looks and moves great". The signal + mechanism stay for diagnostics
    /// and future presets. `nil` = unknown — permissive, no exclusion.
    /// Optional so old persisted profiles decode unchanged.
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
        sectionStartTimes: [TimeInterval]? = nil,
        beatIrregular: Bool? = nil
    ) {
        self.bpm = bpm
        self.key = key
        self.mood = mood
        self.spectralCentroidAvg = spectralCentroidAvg
        self.genreTags = genreTags
        self.stemEnergyBalance = stemEnergyBalance
        self.estimatedSectionCount = estimatedSectionCount
        self.sectionStartTimes = sectionStartTimes
        self.beatIrregular = beatIrregular
    }

    // MARK: - Defaults

    /// Empty profile — all fields at zero or nil.
    public static let empty = TrackProfile()
}
