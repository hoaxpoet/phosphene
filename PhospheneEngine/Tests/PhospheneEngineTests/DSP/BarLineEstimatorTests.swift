// BarLineEstimatorTests — FT.3 task 4's parity gate, plus the controls that keep the port
// honest without any fixture.
//
// The parity test (`PHOSPHENE_BARLINE_PARITY`) is the increment's real gate: the Swift
// margins must reproduce `tools/barline_parity.py`'s to within 1e-3 on the ground-truthed
// tracks. It needs the beats dump and the audio fixtures, so it is env-gated.
//
// Everything else here runs in CI on synthetic input, and the two that matter are:
//
//   - the SplitMix64 known-answer test, which is what stops the two implementations of the
//     null drifting apart silently and turning the parity gate green against nothing;
//   - the no-bar-information control, which is FT.3 task 3's requirement in Swift: a
//     feature set with no bar in it must not favour any meter. That control is what
//     rejected the probe's own combination rule, whose no-information picks skewed to
//     meter 7 — the bias that derailed DBN.2 twice, and two of the probe's six correct
//     answers are 7.

import Testing
import Foundation
@testable import DSP

@Suite("BarLineEstimator")
struct BarLineEstimatorTests {

    // MARK: - PRNG contract

    @Test("SplitMix64 matches the Python reference stream")
    func test_splitMix64KnownAnswer() {
        var rng = SplitMix64(seed: 20_260_731)
        let produced = (0..<5).map { _ in rng.next() }
        #expect(produced == [
            12_920_862_721_943_697_893, 14_594_195_131_876_237_143,
            10_466_480_074_438_955_700, 13_899_156_908_388_841,
            14_612_643_055_735_743_350
        ])
    }

    @Test("Fisher-Yates matches the Python reference permutation")
    func test_shuffleKnownAnswer() {
        var rng = SplitMix64(seed: 7)
        var values: [Double] = (0..<8).map(Double.init)
        rng.shuffle(&values)
        #expect(values == [1, 4, 5, 2, 6, 0, 3, 7])
    }

    // MARK: - The statistic

    @Test("Contrast is zero on a constant feature and scale-invariant otherwise")
    func test_contrastProperties() {
        let constant = [Double](repeating: 3.0, count: 40)
        #expect(BarLineEstimator.contrasts(constant, meter: 4).allSatisfy { $0 == 0 })

        let planted = (0..<40).map { $0 % 4 == 1 ? 5.0 : 1.0 }
        let unit = BarLineEstimator.contrasts(planted, meter: 4)
        let scaled = BarLineEstimator.contrasts(planted.map { $0 * 137.0 }, meter: 4)
        #expect(BarLineEstimator.argmax(unit) == 1)
        for (a, b) in zip(unit, scaled) { #expect(abs(a - b) < 1e-9) }
    }

    // MARK: - Recovery

    @Test("A planted odd-meter accent is recovered with the right phase")
    func test_recoversPlantedMeterAndPhase() {
        // A period-5 accent on phase 2, in every feature, with noise underneath.
        var rng = SplitMix64(seed: 99)
        let features = (0..<4).map { _ -> [Double] in
            (0..<300).map { index in
                let accent = index % 5 == 2 ? 1.0 : 0.0
                return accent + Double(rng.next() % 1_000) / 4_000.0
            }
        }
        let estimate = BarLineEstimator.score(features: features)
        #expect(estimate.beatsPerBar == 5)
        #expect(estimate.barLinePhase == 2)
        #expect(estimate.isConfident)
    }

    @Test("Estimates are deterministic across runs")
    func test_deterministic() {
        var rng = SplitMix64(seed: 3)
        let features = (0..<4).map { _ in (0..<200).map { _ in Double(rng.next() % 5_000) } }
        let first = BarLineEstimator.score(features: features)
        let second = BarLineEstimator.score(features: features)
        #expect(first == second)
    }

    // MARK: - Decline (D-207)

    @Test("Too few beats declines rather than guessing")
    func test_declinesOnTooFewBeats() {
        let estimate = BarLineEstimator.estimate(beats: [0, 0.5, 1.0], audio: [Float](repeating: 0, count: 4_096))
        #expect(estimate.decline == .tooFewBeats)
        #expect(estimate.beatsPerBar == nil)
    }

    @Test("Silence declines rather than returning a meter")
    func test_declinesOnSilence() {
        let beats = (0..<200).map { Double($0) * 0.5 }
        let estimate = BarLineEstimator.estimate(
            beats: beats, audio: [Float](repeating: 0, count: 22_050 * 110)
        )
        #expect(!estimate.isConfident)
        #expect(estimate.beatsPerBar == nil)
    }

    // MARK: - FT.3 task 3's no-bar-information control

    @Test("A feature set with no bar information favours no meter")
    func test_noBarInformationControlIsUnbiased() {
        // 160 synthetic feature sets carrying no periodic structure at all. A clean rule
        // picks each of D-207's four meters ~25 % of the time and shows no trend of margin
        // against meter. `max_feature` — the probe's own rule — fails exactly this.
        //
        // The draw count is lowered here only for runtime; the property under test is the
        // shape of the combination rule, which does not depend on how finely the null is
        // sampled. The full-draw version of this control is `tools/barline_combine.py`.
        var rng = SplitMix64(seed: 4_242)
        var picks: [Int: Int] = [:]
        var meanMargin: [Int: Double] = [:]
        let trials = 160

        for _ in 0..<trials {
            let features = (0..<4).map { _ in
                (0..<160).map { _ in Double(rng.next() % 1_000_000) / 1_000_000.0 }
            }
            let estimate = BarLineEstimator.score(features: features, draws: 60)
            let winner = estimate.marginsByMeter.max { $0.value < $1.value }?.key
            if let winner { picks[winner, default: 0] += 1 }
            for (meter, margin) in estimate.marginsByMeter {
                meanMargin[meter, default: 0] += margin / Double(trials)
            }
        }

        for meter in BarLineEstimator.meters {
            let share = Double(picks[meter] ?? 0) / Double(trials)
            #expect(abs(share - 0.25) <= 0.10, "meter \(meter) picked \(share) of the time")
        }

        // No trend of margin against meter — the DBN.2 failure mode, stated as a slope.
        let meters = BarLineEstimator.meters.map(Double.init)
        let margins = BarLineEstimator.meters.map { meanMargin[$0] ?? 0 }
        #expect(abs(slope(meters, margins)) < 0.01)
    }

    private func slope(_ xs: [Double], _ ys: [Double]) -> Double {
        let n = Double(xs.count)
        let meanX = xs.reduce(0, +) / n
        let meanY = ys.reduce(0, +) / n
        let covariance = zip(xs, ys).reduce(0) { $0 + ($1.0 - meanX) * ($1.1 - meanY) }
        let variance = xs.reduce(0) { $0 + ($1 - meanX) * ($1 - meanX) }
        return variance == 0 ? 0 : covariance / variance
    }
}
