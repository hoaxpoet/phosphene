// SelfTest — In-memory validation of the CS.1 measurement arithmetic.
//
// `--self-test` constructs controlled scenarios with KNOWN answers and asserts
// the harness recovers them. It exercises the pure measurement chain — the
// ClockOffset onset-pairing estimator and `ColdStartAnalysis.evaluate` (verdict
// from Beat This! audible beats already mapped into playback-time) — with
// synthetic data. The Beat This! inference itself is not self-tested (it needs
// the model + Metal); it is exercised by the real run.
//
// This is a self-test of the harness's OWN math, not a claim about Phosphene's
// behaviour. It is runnable before a session is captured, so the harness is
// verified before it is trusted.

import Foundation

enum SelfTest {

    /// Run the self-test. Throws `ExitCodeFailure` on any assertion miss.
    static func run() throws {
        var failures: [String] = []

        check(ColdStartAnalysis.median([1, 2, 3, 4]) == 2.5, "median(even)", &failures)
        check(ColdStartAnalysis.median([3, 1, 2]) == 2.0, "median(odd)", &failures)

        // --- ClockOffset: recover a known offset from onset pairs ------------
        let period = 0.5
        let beatPts = stride(from: 0.3, through: 11.8, by: period).map { $0 }
        let knownOffset = 2.34
        let rawOnsets = beatPts.map { $0 + knownOffset }
        let estimated = ClockOffset.estimate(
            rawOnsets: rawOnsets,
            beatBassOnsets: beatPts,
            coarseS: knownOffset + 0.05)   // precise coarse anchor (±tens of ms)
        check(
            near(estimated, knownOffset, tol: 0.03),
            "ClockOffset recovered \(fmt(estimated)) ≈ \(knownOffset)",
            &failures)

        // --- evaluate: recover a known per-beat delta -----------------------
        let injectedDeltaMs = 8.0
        let config = VerifierConfig(
            firstWindowS: 10,
            windowStartS: 0,
            passWindowMs: 50,
            tightWindowMs: 30,
            passRate: 0.9,
            displayShiftMs: 0)
        let track = makeTrack(
            audibleBeats: beatPts, injectedDeltaMs: injectedDeltaMs, period: period)
        let result = ColdStartAnalysis.evaluate(
            track: track, audibleBeatsPt: beatPts, offsetS: 0, config: config)
        check(result.verdict == .pass, "verdict == pass (got \(result.verdict.rawValue))", &failures)
        check(result.unmatchedCount == 0, "no unmatched beats (got \(result.unmatchedCount))", &failures)
        if let med = result.medianCorrectedMs {
            check(
                near(med, injectedDeltaMs, tol: 8.0),
                "median corrected Δ \(fmt(med)) ms ≈ \(injectedDeltaMs) ms",
                &failures)
        } else {
            failures.append("median corrected Δ is nil")
        }

        // --- degenerate path: a no-grid track -------------------------------
        let reactive = makeReactiveTrack()
        let degen = ColdStartAnalysis.evaluate(
            track: reactive, audibleBeatsPt: beatPts, offsetS: 0, config: config)
        check(degen.verdict == .degenerate, "reactive (no-grid) track → degenerate", &failures)

        try report(failures: failures)
    }

    private static func report(failures: [String]) throws {
        if failures.isEmpty {
            print("ColdStartVerifier --self-test: PASS (all 7 checks)")
        } else {
            print("ColdStartVerifier --self-test: FAIL")
            for failure in failures { print("  ✗ \(failure)") }
            throw ExitCodeFailure()
        }
    }

    // MARK: - Scenario builders

    private static func makeTrack(
        audibleBeats: [Double], injectedDeltaMs: Double, period: Double
    ) -> TrackSegment {
        let visual0 = audibleBeats[0] + injectedDeltaMs / 1000.0
        let fps = 60.0
        let frameCount = Int(13.0 * fps)
        var frames: [FeatureFrame] = []
        for idx in 0..<frameCount {
            let pt = Double(idx) / fps
            // beatPhase01: linear sawtooth wrapping at each visual beat.
            let beatIdx = ((pt - visual0) / period).rounded(.down)
            let beatStart = visual0 + beatIdx * period
            let phase = max(0, min(0.9999, (pt - beatStart) / period))
            frames.append(FeatureFrame(
                frame: idx,
                wallclockS: 900_000 + pt,
                playbackTimeS: pt,
                beatPhase01: phase,
                subBass: 0.2,
                beatBass: 0.2,
                bassAttRel: 0.2,
                gridBPM: 120,
                driftMs: 8.0,
                lockState: idx > 120 ? 2 : 1,
                sessionMode: 3,
                beatsPerBar: 4))
        }
        return TrackSegment(
            index: 0,
            frames: frames,
            title: "SelfTest",
            artist: "synthetic",
            installedBPM: 120,
            installedMeter: 4)
    }

    private static func makeReactiveTrack() -> TrackSegment {
        var frames: [FeatureFrame] = []
        for idx in 0..<300 {
            let pt = Double(idx) / 60.0
            frames.append(FeatureFrame(
                frame: idx,
                wallclockS: 900_000 + pt,
                playbackTimeS: pt,
                beatPhase01: 0,
                subBass: 0.2,
                beatBass: 0.2,
                bassAttRel: 0.2,
                gridBPM: 0,
                driftMs: 0,
                lockState: 0,
                sessionMode: 0,
                beatsPerBar: 1))
        }
        return TrackSegment(
            index: 0,
            frames: frames,
            title: "Reactive",
            artist: nil,
            installedBPM: nil,
            installedMeter: nil)
    }

    // MARK: - Helpers

    private static func near(_ lhs: Double, _ rhs: Double, tol: Double) -> Bool {
        abs(lhs - rhs) <= tol
    }

    private static func fmt(_ value: Double) -> String { String(format: "%.3f", value) }

    private static func check(_ cond: Bool, _ label: String, _ failures: inout [String]) {
        if !cond { failures.append(label) }
    }
}

/// Minimal error carrying a non-zero process exit (avoids importing ArgumentParser here).
struct ExitCodeFailure: Error {}
