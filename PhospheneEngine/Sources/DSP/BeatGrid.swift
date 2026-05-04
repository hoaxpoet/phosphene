// BeatGrid — Offline beat/downbeat grid resolved from Beat This! model output.
//
// Produced once per track by BeatGridResolver during pre-analysis of the 30-second
// preview clip. Cached on CachedTrackData (Session module, S6) for instant playback
// access by LiveBeatDriftTracker.
//
// Lives in DSP (not Session) so that BeatGridResolver, which is also in DSP, can
// return it without creating a circular dependency (Session imports DSP, not vice versa).
// TrackProfile / CachedTrackData in Session reference BeatGrid via the DSP import.

import Foundation

// MARK: - BeatGrid

/// Resolved offline beat grid for one track.
///
/// All times are in seconds, derived from a 50 fps (hop=441, sr=22050) frame grid.
/// `beatsPerBar` and `barConfidence` reflect the meter estimated from downbeat spacing.
public struct BeatGrid: Sendable, Hashable, Codable {

    // MARK: - Fields

    /// Beat positions in seconds (ascending). Includes downbeat positions.
    public let beats: [Double]

    /// Downbeat positions in seconds (ascending). Subset of `beats` — each downbeat
    /// is snapped to its nearest beat within ±40 ms.
    public let downbeats: [Double]

    /// Tempo in BPM from trimmed-mean IOI. 0.0 if fewer than 4 beats were detected.
    public let bpm: Double

    /// Estimated beats per bar (e.g. 4 for 4/4, 3 for 3/4, 2 for 2/4).
    /// Computed as `round(median_downbeat_IOI / beat_period)`.
    /// Defaults to 4 when there are fewer than 2 downbeat pairs or bpm == 0.
    public let beatsPerBar: Int

    /// Fraction of inter-downbeat intervals consistent with `beatsPerBar`. Range 0–1.
    /// 0 when there are fewer than 2 downbeat pairs or when bpm == 0.
    public let barConfidence: Float

    /// Frame rate used during resolution (Beat This! = 50.0 fps).
    public let frameRate: Double

    /// Number of frames the resolver was called with (input length, not beat count).
    public let frameCount: Int

    // MARK: - Init

    public init(
        beats: [Double],
        downbeats: [Double],
        bpm: Double,
        beatsPerBar: Int,
        barConfidence: Float,
        frameRate: Double,
        frameCount: Int
    ) {
        self.beats = beats
        self.downbeats = downbeats
        self.bpm = bpm
        self.beatsPerBar = beatsPerBar
        self.barConfidence = barConfidence
        self.frameRate = frameRate
        self.frameCount = frameCount
    }

    // MARK: - Convenience

    /// Empty grid — no beats, no downbeats, bpm 0, default 4/4, confidence 0.
    public static let empty = BeatGrid(
        beats: [],
        downbeats: [],
        bpm: 0.0,
        beatsPerBar: 4,
        barConfidence: 0,
        frameRate: 50.0,
        frameCount: 0
    )
}
