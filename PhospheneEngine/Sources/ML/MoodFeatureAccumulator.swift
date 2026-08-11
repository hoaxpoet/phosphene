// MoodFeatureAccumulator — DYN.7: one definition of "the mood input", shared by both paths.
//
// THE SPLIT THIS CLOSES. A track's mood was measured two different ways depending on who
// asked. `TrackProfile.mood`, set at preparation and worth 30 % of `DefaultPresetScorer`,
// came from `SessionPreparer+Analysis`; the live `valence`/`arousal` that presets read came
// from `VisualizerEngine`. They disagreed on all three of the things that define the
// measurement:
//
//   |                  | intended (comments) | live (9.9 Hz) | offline              |
//   | feature window   | ~7 s                | 10.1 s        | none — INSTANTANEOUS |
//   | classify cadence | —                   | every frame   | every 30th frame     |
//   | output window    | ~0.7 s              | 1.01 s        | 6.96 s               |
//
// **The LIVE side was close to intent; the OFFLINE side was the broken one** — 6.96 s
// against 0.7 s, and no feature smoothing at all. The original DYN.7 note had this
// backwards because it assumed a 59.9 Hz analysis rate; the DYN.3 probe later measured the
// real rate at 9.9 Hz (the 59.9 figure is the RENDER rate, which is what `features.csv`
// rows are written at — the analysis queue runs an order of magnitude slower).
//
// Both were wrong, in opposite directions, and for the same reason as DYN.4/DYN.5: the
// constants are per-CALL, so their meaning in seconds moves with the call rate. The
// seconds those two comments quote are the design intent; the "~94 callbacks/s" they quote
// alongside is not the analysis rate (measured 9.9 Hz), which is why neither alpha produced
// the window it claimed. DYN.7 keeps the intent and discards the alphas.
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
