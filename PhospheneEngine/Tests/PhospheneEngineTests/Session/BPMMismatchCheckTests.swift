// BPMMismatchCheckTests — Pure-function coverage for BUG-008.2.
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
