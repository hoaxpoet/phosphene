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
public struct TrackProfile: Sendable {

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

    // MARK: - Init

    public init(
        bpm: Float? = nil,
        key: String? = nil,
        mood: EmotionalState = .neutral,
        spectralCentroidAvg: Float = 0,
        genreTags: [String] = [],
        stemEnergyBalance: StemFeatures = .zero,
        estimatedSectionCount: Int = 0
    ) {
        self.bpm = bpm
        self.key = key
        self.mood = mood
        self.spectralCentroidAvg = spectralCentroidAvg
        self.genreTags = genreTags
        self.stemEnergyBalance = stemEnergyBalance
        self.estimatedSectionCount = estimatedSectionCount
    }

    // MARK: - Defaults

    /// Empty profile — all fields at zero or nil.
    public static let empty = TrackProfile()
}
