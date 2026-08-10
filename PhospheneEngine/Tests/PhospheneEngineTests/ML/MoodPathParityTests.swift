// MoodPathParityTests — DYN.7: the prepared mood and the live mood must be one measurement.
//
// THE SPLIT. `TrackProfile.mood` is set at preparation and is 30 % of `DefaultPresetScorer`;
// the `valence`/`arousal` presets read is produced live. They were computed differently on
// every axis that defines the measurement:
//
//   |                  | intended (comments) | live        | offline              |
//   | feature window   | ~7 s                | 1.67 s      | none — INSTANTANEOUS |
//   | classify cadence | —                   | every frame | every 30th frame     |
//   | output window    | ~0.7 s              | 0.167 s     | 6.96 s               |
//
// Both were wrong and in opposite directions, because both constants were per-CALL: their
// meaning in seconds moved with the call rate, exactly as in DYN.4/DYN.5. A track was
// therefore PREPARED with one mood and PLAYED with another, and nothing in the codebase
// compared them — which is what this file now does.
//
// Deterministic drive, deliberately: this asserts an arithmetic property of the smoothing
// and the cadence, not a musical one, so FA #27's bar on synthetic audio for MUSICAL
// diagnosis does not apply and a fixed trajectory makes a failure readable.

import Testing
import Foundation
@testable import ML
@testable import Shared

@Suite("Mood path parity (DYN.7)")
struct MoodPathParityTests {

    /// A feature vector that varies smoothly in wall-clock time, so a window measured in
    /// seconds is genuinely exercised and two samplings of it can be compared.
    private static func features(atSeconds t: Float) -> [Float] {
        let swing = 0.5 + 0.4 * sin(t * (2 * .pi / 20))
        return MoodFeatureAccumulator.assemble(
            bands: [0.10 + 0.30 * swing, 0.20 * swing, 0.12, 0.04 * swing, 0.010, 0.005],
            centroidNormalized: 0.08 + 0.10 * swing,
            rawFlux: 0.30 + 0.60 * swing,
            majorCorrelation: 0.50 + 0.20 * swing,
            minorCorrelation: 0.50 - 0.15 * swing
        )
    }

    private static func maxAbsDiff(_ a: [Float], _ b: [Float]) -> Float {
        zip(a, b).map { abs($0 - $1) }.max() ?? 0
    }

    @Test("the feature window is the same seconds at either analysis rate")
    func accumulatorIsRateInvariant() {
        func run(fps: Float, seconds: Float) -> [Float] {
            var acc = MoodFeatureAccumulator()
            let dt = 1 / fps
            var t: Float = 0
            var last: [Float] = []
            while t < seconds {
                last = acc.update(frameFeatures: Self.features(atSeconds: t), deltaTime: dt)
                t += dt
            }
            return last
        }
        let slow = run(fps: LoudnessProfile.referenceAnalysisHz, seconds: 60)
        let fast = run(fps: 59.9, seconds: 60)
        let drift = Self.maxAbsDiff(slow, fast)
        #expect(drift < 0.002, """
            the accumulated mood features drift \(drift) between 43 Hz and 60 Hz. A per-FRAME \
            alpha makes the window depend on the analysis rate.
            """)
    }

    /// The load-bearing one. Live classifies every analysis frame; preparation used to
    /// classify every 30th. With a wall-clock output window the cadence sets only the cost.
    @Test("classify cadence no longer changes the reading")
    func classifyCadenceDoesNotChangeTheReading() throws {
        func run(fps: Float, everyNthFrame: Int, seconds: Float) throws -> EmotionalState {
            let classifier = MoodClassifier()
            var acc = MoodFeatureAccumulator()
            let dt = 1 / fps
            var t: Float = 0
            var frame = 0
            var sinceClassify: Float = 0
            var state = EmotionalState(valence: 0, arousal: 0)
            while t < seconds {
                let smoothed = acc.update(frameFeatures: Self.features(atSeconds: t), deltaTime: dt)
                sinceClassify += dt
                if frame % everyNthFrame == 0 {
                    state = try classifier.classify(features: smoothed, deltaTime: sinceClassify)
                    sinceClassify = 0
                }
                t += dt
                frame += 1
            }
            return state
        }
        // Live arrangement against the old preparation arrangement, on identical seconds.
        let live = try run(fps: 59.9, everyNthFrame: 1, seconds: 60)
        let prepared = try run(fps: LoudnessProfile.referenceAnalysisHz,
                               everyNthFrame: 30, seconds: 60)
        let dv = abs(live.valence - prepared.valence)
        let da = abs(live.arousal - prepared.arousal)
        #expect(dv < 0.05 && da < 0.05, """
            prepared mood (valence \(prepared.valence), arousal \(prepared.arousal)) disagrees \
            with live (\(live.valence), \(live.arousal)). A track must not be prepared with one \
            mood and played with another.
            """)
    }

    @Test("the output window is 0.7 s of wall clock, not a count of calls")
    func outputWindowIsWallClock() throws {
        // Step from neutral to a fixed input; after one tau the EMA should have covered
        // ~63 % of the distance regardless of how many calls it took to get there.
        func valueAfter(seconds: Float, fps: Float) throws -> Float {
            let classifier = MoodClassifier()
            let dt = 1 / fps
            let target = Self.features(atSeconds: 5)
            var t: Float = 0
            var state = EmotionalState(valence: 0, arousal: 0)
            while t < seconds {
                state = try classifier.classify(features: target, deltaTime: dt)
                t += dt
            }
            return state.arousal
        }
        let converged = try valueAfter(seconds: 8, fps: 60)
        let atOneTau60 = try valueAfter(seconds: MoodClassifier.outputTau, fps: 60)
        let atOneTau5 = try valueAfter(seconds: MoodClassifier.outputTau, fps: 5)
        // 1 − 1/e = 0.632. Generous bounds: the point is rate-independence, not the exact
        // fraction, and a 5 Hz caller takes coarse steps through the curve.
        for (label, v) in [("60 Hz", atOneTau60), ("5 Hz", atOneTau5)] {
            let fraction = converged != 0 ? v / converged : 0
            #expect(fraction > 0.45 && fraction < 0.80, """
                at one tau the \(label) caller reached \(fraction) of its converged value; \
                a wall-clock EMA should be near 0.63 whatever the call rate.
                """)
        }
    }

    @Test("a track change clears the window")
    func resetClearsTheWindow() {
        var acc = MoodFeatureAccumulator()
        _ = acc.update(frameFeatures: Self.features(atSeconds: 0), deltaTime: 1.0 / 60)
        #expect(acc.current != nil)
        acc.reset()
        #expect(acc.current == nil, """
            a 7 s window must not carry the previous track into the new one's first seconds, \
            which is exactly when preparation and the planner read it.
            """)
    }
}
