// Metrics — the BeatBench scoring core (GT.3).
//
// Standard beat-tracking metrics as defined in the MIREX / `mir_eval` literature,
// plus the Phosphene-specific ones the program needs. Definitions and windows are
// fixed by the `beatbench` skill; this file is their implementation.
//
// Every metric here is exercised by `BeatBench --self-test` against cases whose
// answers are known a priori (perfect / half-tempo / offbeat / random). That is not
// ceremony: GT.2 lost time twice to metrics that were wrong in a self-flattering
// direction (a least-squares tempo fit that made steady tapping look sloppy; a
// truncated meter candidate list that made an ambiguous track look certain). A
// scoring harness that cannot be caught being wrong will eventually be believed
// when it is.

import Foundation

// MARK: - Result

/// F-measure with its precision/recall parts.
public struct FMeasure: Sendable {
    public let score: Double
    public let precision: Double
    public let recall: Double
}

public struct BeatScores: Sendable {
    public let fMeasure: Double
    public let precision: Double
    public let recall: Double
    public let cemgil: Double
    public let cmlt: Double
    public let amlt: Double
    public let refCount: Int
    public let estCount: Int
}

public enum Metrics {

    /// Tolerance for F-measure matching. The window the whole program scores against.
    public static let fMeasureToleranceS = 0.070
    /// Cemgil Gaussian width (standard σ = 40 ms).
    public static let cemgilSigmaS = 0.040
    /// Continuity tolerance as a fraction of the local inter-beat interval (standard 17.5 %).
    public static let continuityTolerance = 0.175

    // MARK: - F-measure

    /// Greedy one-to-one matching inside `tolerance`.
    ///
    /// One-to-one matters: without it, an estimate that fires twice per reference beat
    /// would score full recall on both, and a double-tempo tracker would look perfect.
    public static func fMeasure(
        reference: [Double],
        estimate: [Double],
        tolerance: Double = fMeasureToleranceS
    ) -> FMeasure {
        guard !reference.isEmpty, !estimate.isEmpty else {
            return FMeasure(score: 0, precision: 0, recall: 0)
        }
        var used = Set<Int>()
        var matched = 0
        for ref in reference {
            var best: Int?
            var bestDelta = tolerance
            for (index, est) in estimate.enumerated() where !used.contains(index) {
                let delta = abs(est - ref)
                if delta <= bestDelta { best = index; bestDelta = delta }
            }
            if let best { used.insert(best); matched += 1 }
        }
        let precision = Double(matched) / Double(estimate.count)
        let recall = Double(matched) / Double(reference.count)
        let sum = precision + recall
        let score = sum > 0 ? 2 * precision * recall / sum : 0
        return FMeasure(score: score, precision: precision, recall: recall)
    }

    // MARK: - Cemgil

    /// Gaussian-weighted accuracy: rewards tightness, not just presence-in-window.
    public static func cemgil(
        reference: [Double],
        estimate: [Double],
        sigma: Double = cemgilSigmaS
    ) -> Double {
        guard !reference.isEmpty, !estimate.isEmpty else { return 0 }
        var total = 0.0
        for ref in reference {
            var best = 0.0
            for est in estimate {
                let delta = est - ref
                // Beyond ~4σ the term is numerically irrelevant; skip the exp.
                if abs(delta) > 8 * sigma { continue }
                best = max(best, exp(-(delta * delta) / (2 * sigma * sigma)))
            }
            total += best
        }
        return total / (Double(reference.count + estimate.count) / 2.0)
    }

    // MARK: - Continuity (CMLt / AMLt)

    /// Fraction of estimated beats that are correctly tracked at the reference's own
    /// metrical level, requiring both the phase AND the period to stay inside
    /// `continuityTolerance` of the local inter-beat interval.
    public static func cmlt(reference: [Double], estimate: [Double]) -> Double {
        continuityTotal(reference: reference, estimate: estimate)
    }

    /// As CMLt, but allowing the metrical variations a listener would also accept:
    /// double time, half time, and offbeat (half-period phase shift). The best score
    /// over those variants wins.
    ///
    /// This is the metric that must RISE where CMLt falls on a half-tempo or offbeat
    /// tracker — if it does not, the implementation is wrong (see the self-test).
    public static func amlt(reference: [Double], estimate: [Double]) -> Double {
        var best = continuityTotal(reference: reference, estimate: estimate)
        for variant in metricalVariants(of: reference) {
            best = max(best, continuityTotal(reference: variant, estimate: estimate))
        }
        return best
    }

    /// Double-time, half-time and offbeat readings of an annotation.
    static func metricalVariants(of reference: [Double]) -> [[Double]] {
        guard reference.count >= 3 else { return [] }
        var variants: [[Double]] = []

        // Half time — every other beat.
        variants.append(stride(from: 0, to: reference.count, by: 2).map { reference[$0] })

        // Double time — interpolate a beat at each midpoint.
        var doubled: [Double] = []
        for index in 0..<(reference.count - 1) {
            doubled.append(reference[index])
            doubled.append((reference[index] + reference[index + 1]) / 2)
        }
        if let last = reference.last { doubled.append(last) }
        variants.append(doubled)

        // Offbeat — shift by half the local period.
        var offbeat: [Double] = []
        for index in 0..<(reference.count - 1) {
            offbeat.append((reference[index] + reference[index + 1]) / 2)
        }
        variants.append(offbeat)

        return variants
    }

    /// Shared continuity engine. A beat counts as correctly tracked when its phase
    /// error and its period error are both within tolerance of the local reference
    /// interval. `*t` variants total every correct beat (as opposed to `*c`, which
    /// takes only the longest unbroken run).
    static func continuityTotal(reference: [Double], estimate: [Double]) -> Double {
        guard reference.count >= 2, estimate.count >= 2 else { return 0 }
        var correct = 0
        for index in 0..<estimate.count {
            let est = estimate[index]
            guard let nearest = nearestIndex(to: est, in: reference) else { continue }
            let interval = localInterval(at: nearest, in: reference)
            guard interval > 0 else { continue }
            let phaseOK = abs(est - reference[nearest]) <= continuityTolerance * interval

            // Period agreement, checked against the previous estimated beat.
            var periodOK = true
            if index > 0 {
                let estPeriod = est - estimate[index - 1]
                periodOK = abs(estPeriod - interval) <= continuityTolerance * interval
            }
            if phaseOK && periodOK { correct += 1 }
        }
        return Double(correct) / Double(estimate.count)
    }

    static func nearestIndex(to time: Double, in times: [Double]) -> Int? {
        guard !times.isEmpty else { return nil }
        var best = 0
        var bestDelta = abs(times[0] - time)
        for index in 1..<times.count {
            let delta = abs(times[index] - time)
            if delta < bestDelta { best = index; bestDelta = delta }
        }
        return best
    }

    static func localInterval(at index: Int, in times: [Double]) -> Double {
        guard times.count >= 2 else { return 0 }
        if index == 0 { return times[1] - times[0] }
        if index >= times.count - 1 { return times[index] - times[index - 1] }
        return (times[index + 1] - times[index - 1]) / 2
    }

    // MARK: - Aggregate

    public static func score(reference: [Double], estimate: [Double]) -> BeatScores {
        let measure = fMeasure(reference: reference, estimate: estimate)
        return BeatScores(
            fMeasure: measure.score,
            precision: measure.precision,
            recall: measure.recall,
            cemgil: cemgil(reference: reference, estimate: estimate),
            cmlt: cmlt(reference: reference, estimate: estimate),
            amlt: amlt(reference: reference, estimate: estimate),
            refCount: reference.count,
            estCount: estimate.count
        )
    }
}
