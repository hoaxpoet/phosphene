// MoodScalerRefitABTests — DYN.6.2: the objective before/after for the flux-scaler refit.
//
// WHY AN A/B AND NOT A UNIT TEST. Mood is 30 % of `DefaultPresetScorer`, so re-scaling one
// classifier input changes preset selection for every track in the library. BUG-066 set the
// precedent for how a change like this is accepted: the live M7 was retired as unfit for a
// diffuse scoring change and replaced by an objective corpus before/after. This is that
// instrument for DYN.6.2.
//
// WHAT IS BEING CHANGED, AND WHY. DYN.6.1's census (n = 27,638) found nine of the ten mood
// features well calibrated (z(median) −0.45…+0.21) and flux at +1.01 with **33.8 % of the
// corpus beyond |z| > 2**. The scaler is not stale — it reproduces the annotated training
// set (n = 818) to five decimals. The gap is COVERAGE: that set's maximum flux is 1.0167 and
// 15.3 % of the corpus exceeds it outright, so the model extrapolates on feature [7] for a
// large minority of the library. Matt authorised refitting the flux mean/std to corpus
// statistics.
//
// HOW BOTH SIDES ARE MEASURED WITH ONE COMPILED CLASSIFIER. The scaler is static, so rather
// than making it injectable (production API surface for a diagnostic), each side is produced
// by transforming the flux input so the COMPILED z-score equals the TARGET scaler's z-score:
//
//     (x' − compiledMean) / compiledStd  ==  (x − targetMean) / targetStd
//
// The arithmetic is exact and stays valid whichever pair is compiled in — so this file keeps
// working after the constants change, which a hardcoded "before" would not.
//
// The classifier EMA-smooths toward its output with alpha 0.1 from a zero seed, so one call
// returns 10 % of the answer. Each row is classified repeatedly until converged.
//
//   MOOD_AB_CSV="/Volumes/Extreme SSD/phosphene_census/full_results.csv" \
//     swift test --package-path PhospheneEngine --filter MoodScalerRefitAB

import Testing
import Foundation
@testable import ML
@testable import Shared

@Suite("Mood scaler refit A/B (DYN.6.2)")
struct MoodScalerRefitABTests {

    private static let fluxIndex = 7

    /// The scaler fitted on the 818-track annotated training set — what shipped before
    /// DYN.6.2, and what the other nine features still use.
    private static let trainingFlux = (mean: Float(0.25158), std: Float(0.20444))
    /// The scaler fitted on the 27,638-track corpus (DYN.6.1 measurement).
    private static let corpusFlux = (mean: Float(0.56498), std: Float(0.43400))
    /// A narrower lever, measured so the choice between them is evidence and not taste:
    /// widen the SPREAD to the corpus's but keep the training MEAN. That removes the
    /// extrapolation (the |z|>2 tail) with a much smaller shift in where the centre sits.
    private static let widenOnlyFlux = (mean: Float(0.25158), std: Float(0.43400))

    /// Rewrite feature [7] so the COMPILED z-score equals `target`'s z-score.
    private static func retargetFlux(_ features: [Float], to target: (mean: Float, std: Float)) -> [Float] {
        let compiledMean = MoodClassifier.scalerMeansForTesting[fluxIndex]
        let compiledStd = MoodClassifier.scalerStdsForTesting[fluxIndex]
        var out = features
        let z = (features[fluxIndex] - target.mean) / target.std
        out[fluxIndex] = compiledMean + compiledStd * z
        return out
    }

    /// The classifier's converged output for one feature vector. The EMA seeds at zero, so
    /// a single call returns a tenth of the answer; 80 calls is > 0.9997 of convergence.
    private static func converged(_ features: [Float]) -> (v: Float, a: Float)? {
        let classifier = MoodClassifier()
        var last: EmotionalState?
        // 80 calls at a fifth of the output window is > 15 tau — fully converged, and the
        // dt is explicit now that the window is wall-clock (DYN.7).
        let dt = MoodClassifier.outputTau / 5
        for _ in 0..<80 { last = try? classifier.classify(features: features, deltaTime: dt) }
        guard let last else { return nil }
        return (last.valence, last.arousal)
    }

    private static func quadrant(_ v: Float, _ a: Float) -> Int {
        (v >= 0 ? 1 : 0) + (a >= 0 ? 2 : 0)
    }

    private static func stdev(_ v: [Float]) -> Float {
        guard v.count > 1 else { return 0 }
        let mean = v.reduce(0, +) / Float(v.count)
        return (v.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Float(v.count)).squareRoot()
    }

    @Test("corpus before/after for the flux-scaler refit (MOOD_AB_CSV=…)")
    func reportRefitAB() throws {
        guard let path = ProcessInfo.processInfo.environment["MOOD_AB_CSV"] else { return }
        let text = try String(contentsOfFile: (path as NSString).expandingTildeInPath,
                              encoding: .utf8)
        var lines = text.components(separatedBy: "\n")
        guard let header = lines.first else { return }
        lines.removeFirst()
        let cols = header.components(separatedBy: ",")
        guard let errorIdx = cols.firstIndex(of: "error"),
              let feat0 = cols.firstIndex(of: "feat0") else {
            Issue.record("census CSV missing feat0/error columns"); return
        }

        var before: [(v: Float, a: Float)] = []
        var after: [(v: Float, a: Float)] = []
        var widen: [(v: Float, a: Float)] = []
        var flips = 0
        var widenFlips = 0
        for line in lines where !line.isEmpty {
            let cells = line.components(separatedBy: ",")
            guard cells.count > max(errorIdx, feat0 + 9), cells[errorIdx].isEmpty else { continue }
            let features = (0..<10).compactMap { Float(cells[feat0 + $0]) }
            guard features.count == 10, features.allSatisfy({ $0.isFinite }) else { continue }
            guard let b = Self.converged(Self.retargetFlux(features, to: Self.trainingFlux)),
                  let a = Self.converged(Self.retargetFlux(features, to: Self.corpusFlux)),
                  let w = Self.converged(Self.retargetFlux(features, to: Self.widenOnlyFlux))
            else { continue }
            before.append(b); after.append(a); widen.append(w)
            if Self.quadrant(b.v, b.a) != Self.quadrant(w.v, w.a) { widenFlips += 1 }
            if Self.quadrant(b.v, b.a) != Self.quadrant(a.v, a.a) { flips += 1 }
        }
        guard before.count > 100 else { Issue.record("only \(before.count) usable rows"); return }

        func report(_ label: String, _ rows: [(v: Float, a: Float)]) {
            let vs = rows.map(\.v), aas = rows.map(\.a)
            print(String(format: "  %-8@ valence mean %+.3f sd %.3f  [%+.2f…%+.2f]   arousal mean %+.3f sd %.3f  [%+.2f…%+.2f]",
                         label as NSString,
                         vs.reduce(0, +) / Float(vs.count), Self.stdev(vs), vs.min() ?? 0, vs.max() ?? 0,
                         aas.reduce(0, +) / Float(aas.count), Self.stdev(aas), aas.min() ?? 0, aas.max() ?? 0))
        }
        print("\n── MOOD SCALER REFIT A/B (DYN.6.2) ────────────────────────────────")
        print("  tracks   \(before.count)")
        print(String(format: "  flux scaler   training (%.5f, %.5f)  ->  corpus (%.5f, %.5f)",
                     Self.trainingFlux.mean, Self.trainingFlux.std,
                     Self.corpusFlux.mean, Self.corpusFlux.std))
        report("BEFORE", before)
        report("AFTER", after)
        report("WIDEN", widen)
        let pct = 100.0 * Double(flips) / Double(before.count)
        print(String(format: "  quadrant flips  full refit %d (%.1f %%)   widen-std-only %d (%.1f %%)",
                     flips, pct, widenFlips, 100.0 * Double(widenFlips) / Double(before.count)))
        let saturatedBefore = before.filter { abs($0.a) > 0.95 }.count
        let saturatedAfter = after.filter { abs($0.a) > 0.95 }.count
        print(String(format: "  arousal railed (|a| > 0.95)  before %.1f %%   after %.1f %%",
                     100.0 * Double(saturatedBefore) / Double(before.count),
                     100.0 * Double(saturatedAfter) / Double(after.count)))
        print("───────────────────────────────────────────────────────────────────\n")

        // MECHANICAL CLAIMS ONLY. Whether the new mood readings are BETTER is a judgement
        // on 27k tracks nobody has labelled; these assert that the change is real, bounded,
        // and does not collapse the output — the failure modes an A/B can actually catch.
        #expect(pct > 1, "the refit moved \(pct)% of tracks — too few to be the change we think it is")
        #expect(pct < 60, "the refit moved \(pct)% of tracks — that is a different model, not a rescale")
        let afterArousal = after.map(\.a)
        #expect(Self.stdev(afterArousal) > 0.10,
                "arousal spread collapsed to \(Self.stdev(afterArousal)) — the feature stopped discriminating")
    }
}
