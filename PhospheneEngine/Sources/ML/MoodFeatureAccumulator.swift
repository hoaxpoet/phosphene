// MoodFeatureAccumulator — DYN.7: one definition of "the mood input", shared by both paths.
//
// THE SPLIT THIS CLOSES. A track's mood was measured two different ways depending on who
// asked. `TrackProfile.mood`, set at preparation and worth 30 % of `DefaultPresetScorer`,
// came from `SessionPreparer+Analysis`; the live `valence`/`arousal` that presets read came
// from `VisualizerEngine`. They disagreed on all three of the things that define the
// measurement:
//
//   |                  | intended (code comments) | live         | offline            |
//   | feature window   | ~7 s                     | 1.67 s       | none — INSTANTANEOUS |
//   | classify cadence | —                        | every frame  | every 30th frame   |
//   | output window    | ~0.7 s                   | 0.167 s      | 6.96 s             |
//
// Both were wrong, in opposite directions, and for the same reason as DYN.4/DYN.5: the
// constants are per-CALL, so their meaning in seconds moves with the call rate. The two
// comments (`featureEmaAlpha` "≈7 s at ~94 callbacks/s", `emaAlpha` "≈0.7 s at ~94
// callbacks/s") are each off by ~4.2× against their own stated rate — the same 4.2× as
// 59.9 Hz / 14.3 Hz, which is what the analysis rate actually was when they were written.
// **So the seconds in those comments are the design intent, and the alphas stopped meaning
// them.** DYN.7 keeps the intent and discards the alphas.
//
// Housing the accumulation here rather than at each call site is the point: two call sites
// assembling "the same" vector is exactly how they drifted, and a shared type makes the
// divergence unrepresentable rather than merely discouraged.

import Foundation
import Shared

// MARK: - MoodFeatureAccumulator

/// Smooths the ten mood-classifier inputs over a wall-clock window.
///
/// Not thread-safe by design — each path owns one and drives it from its own serial
/// analysis context, the same ownership the two ad-hoc accumulators had.
public struct MoodFeatureAccumulator {

    /// Feature-window time constant. The `~7 s effective window` the app-layer comment
    /// always claimed, now true at any analysis rate.
    public static let featureTau: Float = 7.0

    private var accumulated: [Float]?

    public init() {}

    /// Assemble the ten inputs in the canonical order.
    ///
    /// Every caller goes through here. The order is the contract (`MoodClassifier`
    /// class docs), and it is not restated at any call site — the previous arrangement had
    /// two hand-written literals that had to be kept in step by eye, and they were not:
    /// one spelled feature [6] `fv.spectralCentroid` and the other
    /// `mir.rawSmoothedCentroid / nyquist`. Those happen to be equal today, which is
    /// precisely the kind of coincidence that stops being true silently.
    ///
    /// - Parameters:
    ///   - bands: the six-band energies in order, sub-bass → high. Exactly six; a wrong
    ///     count returns an empty vector rather than a silently misaligned one.
    ///   - centroidNormalized: spectral centroid divided by the live Nyquist (BUG-053 — the
    ///     divisor must be the real tap rate, not a hardcoded 24 kHz).
    ///   - rawFlux: `MIRPipeline.rawSmoothedFlux`, unnormalised (the classifier z-scores it).
    ///   - majorCorrelation / minorCorrelation: Krumhansl-Schmuckler key correlations.
    public static func assemble(
        bands: [Float],
        centroidNormalized: Float,
        rawFlux: Float,
        majorCorrelation: Float,
        minorCorrelation: Float
    ) -> [Float] {
        guard bands.count == 6 else { return [] }
        return bands + [centroidNormalized, rawFlux, majorCorrelation, minorCorrelation]
    }

    /// Advance the window by one analysis frame and return the smoothed vector.
    ///
    /// Seeds on the first frame rather than ramping from zero: a 7 s ramp from silence would
    /// hand the classifier a vector that describes nothing for the first several seconds of
    /// every track, which is when preparation reads it.
    public mutating func update(frameFeatures: [Float], deltaTime: Float) -> [Float] {
        guard frameFeatures.count == MoodClassifier.featureCount else {
            return accumulated ?? frameFeatures
        }
        guard var current = accumulated else {
            accumulated = frameFeatures
            return frameFeatures
        }
        let alpha = LoudnessProfile.emaAlpha(deltaTime: deltaTime, tau: Self.featureTau)
        for idx in 0..<MoodClassifier.featureCount {
            current[idx] = alpha * frameFeatures[idx] + (1 - alpha) * current[idx]
        }
        accumulated = current
        return current
    }

    /// The current smoothed vector, or `nil` before the first frame.
    public var current: [Float]? { accumulated }

    /// Track change: the next track must not inherit this one's window.
    public mutating func reset() { accumulated = nil }
}
