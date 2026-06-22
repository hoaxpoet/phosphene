// BoundaryStrengthFilterTests — LFPLAN.8 strong-boundary filter.
//
// The offline planner keeps only boundaries whose novelty peak is ≥ half the track's
// strongest, so planned transitions land on big audible section changes, not sub-section
// blips. Pure function over the (timestamp, score) parallel arrays.

import Foundation
import Testing
@testable import Session

@Suite("BoundaryStrengthFilter (LFPLAN.8)")
struct BoundaryStrengthFilterTests {

    @Test("keeps boundaries ≥ half the strongest, drops weak blips")
    func keepsStrongDropsWeak() {
        // strongest = 0.020 → cutoff 0.010. 0.005 / 0.008 dropped; 0.020 / 0.012 / 0.018 kept.
        let times: [Float] = [10, 25, 40, 60, 90]
        let scores: [Float] = [0.005, 0.020, 0.008, 0.012, 0.018]
        let kept = SessionPreparer.strongBoundaryTimes(times: times, scores: scores)
        #expect(kept == [25, 60, 90])
    }

    @Test("no scores → all boundaries pass through (fallback)")
    func noScoresFallsBack() {
        let kept = SessionPreparer.strongBoundaryTimes(times: [10, 25, 40], scores: [])
        #expect(kept == [10, 25, 40])
    }

    @Test("the strongest boundary always survives")
    func strongestSurvives() {
        let kept = SessionPreparer.strongBoundaryTimes(times: [10, 25], scores: [0.001, 0.001])
        #expect(kept == [10, 25])
    }
}
