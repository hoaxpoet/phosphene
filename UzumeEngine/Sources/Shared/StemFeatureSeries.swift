// StemFeatureSeries — pre-analyzed per-stem features in playback order (LFSTEM.1).
//
// Why this exists: live stem separation costs ~2.5 s of latency by construction — a 2 s
// window plus inference — so every stem-driven behaviour follows the music by about a bar.
// For a LOCAL file that latency is avoidable: the whole file is decoded during preparation
// (`PreviewAudio.fromLocalFile` reads `AVAudioFile` to its full length), so the stems can be
// analysed ahead of time and each frame handed to the renderer at the playback second it
// belongs to.
//
// Streaming cannot have this and never will: a system-audio tap only ever carries audio that
// has already played. This type is therefore local-file-only, the same asymmetry
// `CachedTrackData.loudnessProfile` already carries (DYN.1c).
//
// The pattern is not new — `InstrumentFamilyActivity.sample` (IFC.4 / D-177) is a
// pre-analysed series sampled by playback position, in production since 2026-08. This is
// that pattern applied to the signal it matters most for.

import Foundation

// MARK: - StemFeatureSeries

/// A dense, uniformly-spaced series of `StemFeatures` covering a track, in playback order.
///
/// Frames sit on a fixed grid of `hopSeconds` starting at playback second 0, so frame `i`
/// describes playback second `i * hopSeconds`. The grid is the analysis hop the live path
/// uses (1024 samples ≈ 23.2 ms at 44.1 kHz), not the separation period — stem envelopes
/// vary within a separation window and a coarser grid would flatten exactly the transients
/// the accent routes read.
public struct StemFeatureSeries: Sendable, Equatable {

    /// Per-frame features, index 0 at playback second 0.
    public let frames: [StemFeatures]

    /// Seconds between consecutive frames. Always > 0 for a non-empty series.
    public let hopSeconds: Double

    /// An absent series — what every non-local path carries, and the signal to callers that
    /// they should fall back to live separation.
    public static let empty = StemFeatureSeries(frames: [], hopSeconds: 0)

    public init(frames: [StemFeatures], hopSeconds: Double) {
        self.frames = frames
        self.hopSeconds = hopSeconds
    }

    public var isEmpty: Bool { frames.isEmpty || hopSeconds <= 0 }

    /// Playback seconds the series covers.
    public var durationSeconds: Double {
        isEmpty ? 0 : Double(frames.count) * hopSeconds
    }

    /// The frame describing `playbackSeconds`, or `nil` when the series is empty.
    ///
    /// Nearest-frame, not interpolated: `StemFeatures` carries EMA-smoothed and deviation
    /// fields whose values are only meaningful as a set, and blending two frames would
    /// produce a combination the analyzer never emitted. The grid is 23 ms, so nearest is
    /// within ±12 ms of the requested second — well under the ~60 ms perceptual window.
    ///
    /// Positions past the end clamp to the final frame rather than returning nil: a track
    /// playing marginally longer than its analysed length (decoder tail, a clock that drifts
    /// a few frames) must not drop stem coupling in its last moments.
    public func sample(atPlaybackSeconds playbackSeconds: Double) -> StemFeatures? {
        guard !isEmpty else { return nil }
        let idx = Int((max(0, playbackSeconds) / hopSeconds).rounded())
        return frames[min(idx, frames.count - 1)]
    }
}
