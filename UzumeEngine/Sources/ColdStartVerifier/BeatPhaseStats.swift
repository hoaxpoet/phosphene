// BeatPhaseStats — Shared circular-mean phase math for Beat This! grid comparisons.
//
// Two grids derived from co-periodic audio (same track, possibly different
// slice positions or captures) can be compared by computing the circular mean
// of their per-beat residuals modulo the beat period. The resultant length is
// the cluster's tightness — high R = tight cluster (tempo agrees + phase stable),
// low R = scattered (tempo disagrees or phase mod period is undetermined).
//
// Used by ReDiagnosis (short-vs-full-window comparison), PositionSweep
// (position-A vs position-B within one capture), and CrossCapture (capture-A
// vs capture-B at the same position). All three answer the same shape of
// question: "do these two Beat This! outputs agree on phase to within ±ε ms?"

import Foundation

enum BeatPhaseStats {

    /// Circular-mean phase offset (signed ms) of `grid` relative to `reference`,
    /// plus the resultant length [0, 1]. Both grids assumed co-periodic; the
    /// residual `grid_beat − nearest_reference_beat` is wrapped into [−P/2, P/2]
    /// and aggregated as a circular mean so the wrap at ±P/2 is handled correctly.
    /// A constant clock shift (raw-tap vs playback) does NOT affect the result —
    /// the function is shift-invariant. Returns (0, 0) on empty input.
    static func phaseOffset(
        of grid: [Double],
        vs reference: [Double],
        period: Double
    ) -> (offsetMs: Double, resultant: Double) {
        guard !grid.isEmpty, !reference.isEmpty, period > 0 else { return (0, 0) }
        var sumCos = 0.0
        var sumSin = 0.0
        var matched = 0
        for beat in grid {
            guard let nearest = ColdStartAnalysis.nearestValue(to: beat, in: reference)
            else { continue }
            var residual = beat - nearest
            residual -= period * (residual / period).rounded()
            let theta = 2.0 * .pi * residual / period
            sumCos += cos(theta)
            sumSin += sin(theta)
            matched += 1
        }
        guard matched > 0 else { return (0, 0) }
        let resultant = (sumCos * sumCos + sumSin * sumSin).squareRoot() / Double(matched)
        let meanResidual = atan2(sumSin, sumCos) * period / (2.0 * .pi)
        return (meanResidual * 1000.0, resultant)
    }

    /// Median inter-onset interval (s) across consecutive beats. 0 when fewer
    /// than 2 beats.
    static func medianIOI(_ beats: [Double]) -> Double {
        guard beats.count >= 2 else { return 0 }
        var iois: [Double] = []
        iois.reserveCapacity(beats.count - 1)
        for i in 1..<beats.count { iois.append(beats[i] - beats[i - 1]) }
        return ColdStartAnalysis.median(iois)
    }
}
