// BPMMismatchCheckTests — Pure-function coverage for BUG-008.2 (2-way) and
// DSP.4 (3-way).
//
// The detector lives at PhospheneEngine/Sources/Session/BPMMismatchCheck.swift.
// These tests pin the threshold semantics (3 % default, generous on purpose so
// the only signal is "this track has the Love Rehab problem") and the
// nil-return paths (zero / non-finite / sub-threshold inputs).

import Testing
import Foundation
@testable import Session

@Suite("BPMMismatchCheck — pure detector")
struct BPMMismatchCheckTests {

    @Test("agreement_withinDefaultThreshold_returnsNil")
    func test_agreement_withinThreshold_returnsNil() {
        // Money in the BUG-008 capture: 123.2 vs 125.0 = 1.4 % — must NOT fire.
        #expect(detectBPMMismatch(mirBPM: 125.0, gridBPM: 123.2) == nil)
        // Pyramid Song: 70.0 vs 68.0 = 2.86 % — also below 3 % default.
        #expect(detectBPMMismatch(mirBPM: 68.0, gridBPM: 70.0) == nil)
        // Resolver-tolerance band: 125.4 vs 125.0 = 0.32 % — well below.
        #expect(detectBPMMismatch(mirBPM: 125.0, gridBPM: 125.4) == nil)
    }

    @Test("disagreement_aboveDefaultThreshold_returnsWarning")
    func test_disagreement_aboveThreshold_returnsWarning() throws {
        // Love Rehab in the BUG-008 capture: 125.0 (MIR) vs 118.1 (grid) = 5.5 %.
        let warn = try #require(detectBPMMismatch(mirBPM: 125.0, gridBPM: 118.1))
        #expect(warn.mirBPM == 125.0)
        #expect(warn.gridBPM == 118.1)
        #expect(abs(warn.deltaPct - 0.0552) < 0.001)
    }

    @Test("zeroEitherSide_returnsNil")
    func test_zeroEitherSide_returnsNil() {
        // Either estimator can fail silently; the existing WIRING beatGrid
        // line already surfaces an empty grid, so we don't double-warn here.
        #expect(detectBPMMismatch(mirBPM: 0.0, gridBPM: 118.0) == nil)
        #expect(detectBPMMismatch(mirBPM: 125.0, gridBPM: 0.0) == nil)
        #expect(detectBPMMismatch(mirBPM: 0.0, gridBPM: 0.0) == nil)
        // Negative input behaves like zero — defensive, shouldn't happen in production.
        #expect(detectBPMMismatch(mirBPM: -125.0, gridBPM: 118.0) == nil)
    }

    @Test("nonFiniteInputs_returnsNil")
    func test_nonFiniteInputs_returnsNil() {
        #expect(detectBPMMismatch(mirBPM: .nan, gridBPM: 118.0) == nil)
        #expect(detectBPMMismatch(mirBPM: 125.0, gridBPM: .infinity) == nil)
        #expect(detectBPMMismatch(mirBPM: -.infinity, gridBPM: 118.0) == nil)
    }

    @Test("exactTie_returnsNil")
    func test_exactTie_atThreshold_returnsNil() {
        // delta_pct must STRICTLY exceed threshold — exactly 3 % does not fire.
        // 100 vs 97 = 3.0 % exact → no warning.
        #expect(detectBPMMismatch(mirBPM: 100.0, gridBPM: 97.0) == nil)
        // Identical values: zero delta, definitely nil.
        #expect(detectBPMMismatch(mirBPM: 125.0, gridBPM: 125.0) == nil)
    }

    @Test("customThreshold_overridesDefault")
    func test_customThreshold_overridesDefault() throws {
        // 1 % threshold: Money's 1.4 % now fires.
        let strict = try #require(
            detectBPMMismatch(mirBPM: 125.0, gridBPM: 123.2, thresholdPct: 0.01)
        )
        #expect(abs(strict.deltaPct - 0.0144) < 0.001)
        // 10 % threshold: Love Rehab's 5.5 % no longer fires.
        #expect(
            detectBPMMismatch(mirBPM: 125.0, gridBPM: 118.1, thresholdPct: 0.10) == nil
        )
        // Out-of-range threshold falls back to 3 % default (Love Rehab fires).
        #expect(
            detectBPMMismatch(mirBPM: 125.0, gridBPM: 118.1, thresholdPct: 0.0) != nil
        )
        #expect(
            detectBPMMismatch(mirBPM: 125.0, gridBPM: 118.1, thresholdPct: 1.5) != nil
        )
    }

    @Test("deltaPct_isRelativeToLargerValue")
    func test_deltaPct_normalizedToMax() throws {
        // Symmetric: 125 vs 118 must equal 118 vs 125 in delta_pct.
        let a = try #require(detectBPMMismatch(mirBPM: 125.0, gridBPM: 118.0))
        let b = try #require(detectBPMMismatch(mirBPM: 118.0, gridBPM: 125.0))
        #expect(abs(a.deltaPct - b.deltaPct) < 1e-9)
        // 125 vs 118 → 7/125 = 0.056 (NOT 7/118 = 0.0593).
        #expect(abs(a.deltaPct - (7.0 / 125.0)) < 1e-9)
    }
}

// MARK: - DSP.4 Three-Way Detector

@Suite("ThreeWayBPMDisagreement — pure detector")
struct ThreeWayBPMDisagreementTests {

    // All three estimators agree within 3 % → returns nil.
    @Test("allAgree_withinThreshold_returnsNil")
    func test_allAgree_returnsNil() {
        // Love Rehab: MIR=125, grid=123.2 (1.4%), drums=124.0 (0.8%) — all pairs < 3 %.
        #expect(detectThreeWayBPMDisagreement(mirBPM: 125.0, gridBPM: 123.2, drumsBPM: 124.0) == nil)
        // Perfect agreement.
        #expect(detectThreeWayBPMDisagreement(mirBPM: 120.0, gridBPM: 120.0, drumsBPM: 120.0) == nil)
    }

    // MIR vs grid disagrees; drums agrees with MIR → fires because one pair exceeds threshold.
    @Test("mirGridDisagrees_drumsMirAgree_fires")
    func test_mirGridDisagrees_returnsFull() throws {
        // MIR=125, grid=118 (5.6%), drums=125 (0%) — mir-grid fires; mir-drums/grid-drums also checked.
        let reading = try #require(
            detectThreeWayBPMDisagreement(mirBPM: 125.0, gridBPM: 118.0, drumsBPM: 125.0)
        )
        #expect(reading.mirBPM == 125.0)
        #expect(reading.gridBPM == 118.0)
        #expect(reading.drumsBPM == 125.0)
        // mir-grid: |125-118|/125 = 7/125 = 0.056
        #expect(abs(reading.mirGridDeltaPct - (7.0 / 125.0)) < 1e-9)
        // mir-drums: 0 %
        #expect(reading.mirDrumsDeltaPct == 0.0)
        // grid-drums: |118-125|/125 = 7/125 = 0.056
        #expect(abs(reading.gridDrumsDeltaPct - (7.0 / 125.0)) < 1e-9)
        #expect(reading.maxDeltaPct > 0.03)
    }

    // All three disagree — all pairs should be populated correctly.
    @Test("allDisagree_allPairsPopulated")
    func test_allDisagree_allPairsCorrect() throws {
        // MIR=125, grid=118, drums=110 — all pairs > 3 %.
        let reading = try #require(
            detectThreeWayBPMDisagreement(mirBPM: 125.0, gridBPM: 118.0, drumsBPM: 110.0)
        )
        // mir-grid: 7/125 = 0.056
        #expect(abs(reading.mirGridDeltaPct - (7.0 / 125.0)) < 1e-9)
        // mir-drums: 15/125 = 0.12
        #expect(abs(reading.mirDrumsDeltaPct - (15.0 / 125.0)) < 1e-9)
        // grid-drums: 8/118 = 0.0678
        #expect(abs(reading.gridDrumsDeltaPct - (8.0 / 118.0)) < 1e-9)
        // maxDeltaPct is the largest of the three.
        let expected = max(7.0 / 125.0, 15.0 / 125.0, 8.0 / 118.0)
        #expect(abs(reading.maxDeltaPct - expected) < 1e-9)
    }

    // Any zero input → returns nil (fall through to 2-way path).
    @Test("zeroAnyInput_returnsNil")
    func test_zeroInput_returnsNil() {
        #expect(detectThreeWayBPMDisagreement(mirBPM: 0.0, gridBPM: 118.0, drumsBPM: 125.0) == nil)
        #expect(detectThreeWayBPMDisagreement(mirBPM: 125.0, gridBPM: 0.0, drumsBPM: 125.0) == nil)
        // drumsBPM == 0 is the primary fall-through case (no drums grid produced).
        #expect(detectThreeWayBPMDisagreement(mirBPM: 125.0, gridBPM: 118.0, drumsBPM: 0.0) == nil)
        #expect(detectThreeWayBPMDisagreement(mirBPM: 0.0, gridBPM: 0.0, drumsBPM: 0.0) == nil)
    }

    // Non-finite inputs → returns nil (defensive guard).
    @Test("nonFiniteInputs_returnsNil")
    func test_nonFinite_returnsNil() {
        #expect(detectThreeWayBPMDisagreement(mirBPM: .nan, gridBPM: 118.0, drumsBPM: 125.0) == nil)
        #expect(detectThreeWayBPMDisagreement(mirBPM: 125.0, gridBPM: .infinity, drumsBPM: 125.0) == nil)
        #expect(detectThreeWayBPMDisagreement(mirBPM: 125.0, gridBPM: 118.0, drumsBPM: -.infinity) == nil)
    }

    // Custom threshold overrides default 3 %.
    @Test("customThreshold_respected")
    func test_customThreshold() {
        // 1 % threshold: 125 vs 123.2 vs 124 = 1.4 % mir-grid fires.
        let reading = detectThreeWayBPMDisagreement(
            mirBPM: 125.0, gridBPM: 123.2, drumsBPM: 124.0, thresholdPct: 0.01
        )
        #expect(reading != nil)
        // 10 % threshold: 125 vs 118 vs 125 = max 5.6 % does NOT fire.
        let noReading = detectThreeWayBPMDisagreement(
            mirBPM: 125.0, gridBPM: 118.0, drumsBPM: 125.0, thresholdPct: 0.10
        )
        #expect(noReading == nil)
        // Out-of-range threshold falls back to 3 %: Love Rehab 5.6 % fires.
        let withDefault = detectThreeWayBPMDisagreement(
            mirBPM: 125.0, gridBPM: 118.0, drumsBPM: 125.0, thresholdPct: 0.0
        )
        #expect(withDefault != nil)
    }

    // Exactly at threshold (not strictly above) → returns nil.
    @Test("exactlyAtThreshold_returnsNil")
    func test_exactBoundary_returnsNil() {
        // 100 vs 97 vs 97 → mir-grid = 3/100 = exactly 3 % — does NOT fire.
        #expect(
            detectThreeWayBPMDisagreement(mirBPM: 100.0, gridBPM: 97.0, drumsBPM: 97.0) == nil
        )
    }
}
