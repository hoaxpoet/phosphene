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
        var checksRun = 0

        check(ColdStartAnalysis.median([1, 2, 3, 4]) == 2.5, "median(even)", &failures, &checksRun)
        check(ColdStartAnalysis.median([3, 1, 2]) == 2.0, "median(odd)", &failures, &checksRun)

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
            &failures,
            &checksRun)

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
        check(
            result.verdict == .pass,
            "verdict == pass (got \(result.verdict.rawValue))",
            &failures,
            &checksRun)
        check(
            result.unmatchedCount == 0,
            "no unmatched beats (got \(result.unmatchedCount))",
            &failures,
            &checksRun)
        if let med = result.medianCorrectedMs {
            check(
                near(med, injectedDeltaMs, tol: 8.0),
                "median corrected Δ \(fmt(med)) ms ≈ \(injectedDeltaMs) ms",
                &failures,
                &checksRun)
        } else {
            failures.append("median corrected Δ is nil")
            checksRun += 1
        }

        // --- degenerate path: a no-grid track -------------------------------
        let reactive = makeReactiveTrack()
        let degen = ColdStartAnalysis.evaluate(
            track: reactive, audibleBeatsPt: beatPts, offsetS: 0, config: config)
        check(
            degen.verdict == .degenerate,
            "reactive (no-grid) track → degenerate",
            &failures,
            &checksRun)

        // --- BSAudit.3.validate.1 accent-window self-tests -------------------
        runAccentWindowSelfTests(&failures, &checksRun)

        try report(failures: failures, checksRun: checksRun)
    }

    /// Two synthetic-input cases for `AccentWindowPassRate.evaluate`:
    /// (A) 3/4 hits + climbing confidence → FAIL; (B) confidence pinned below
    /// the degraded floor + no rising-edge composite → PASS-degraded.
    private static func runAccentWindowSelfTests(
        _ failures: inout [String], _ checksRun: inout Int
    ) {
        let beats: [Double] = [1.0, 2.0, 3.0, 4.0]
        let accentConfig = AccentWindowConfig(
            firstWindowS: 5.0,
            windowStartS: 0,
            acceptMs: 60,
            accentThreshold: 0.3,
            perTrackPassRate: 0.80,
            degradedConfThreshold: 0.3)

        // Case A — 3/4 accents within ±60 ms; the 4th composite spike at
        // 4.10 s is 100 ms past beat 4 and outside the acceptance window.
        // Confidence ramps 0 → 1, so the graceful-degradation escape hatch
        // is closed — verdict must be FAIL.
        let caseA = makeAccentScenario(
            audibleBeats: beats,
            accentHitTimes: [1.0, 2.0, 3.0, 4.10],
            confidenceRamp: (start: 0.0, end: 1.0),
            compositeAmplitude: 0.5)
        let resultA = AccentWindowPassRate.evaluate(
            track: caseA, audibleBeatsPt: beats, offsetS: 0, config: accentConfig)
        check(
            resultA.verdict == .fail,
            "case A verdict == fail (got \(resultA.verdict.rawValue), "
                + "hits \(resultA.accentHits)/\(resultA.audibleBeats))",
            &failures,
            &checksRun)
        check(
            resultA.accentHits == 3,
            "case A accent hits == 3 (got \(resultA.accentHits))",
            &failures,
            &checksRun)

        // Case B — accent_confidence stuck at 0.1 (below the 0.3 degraded
        // floor); no composite > threshold; verdict must be PASS-degraded.
        let caseB = makeAccentScenario(
            audibleBeats: beats,
            accentHitTimes: [],
            confidenceRamp: (start: 0.1, end: 0.1),
            compositeAmplitude: 0.1)
        let resultB = AccentWindowPassRate.evaluate(
            track: caseB, audibleBeatsPt: beats, offsetS: 0, config: accentConfig)
        check(
            resultB.verdict == .passDegraded,
            "case B verdict == pass-degraded (got \(resultB.verdict.rawValue))",
            &failures,
            &checksRun)
        check(
            near(resultB.maxConfidence, 0.1, tol: 0.01),
            "case B max confidence \(fmt(resultB.maxConfidence)) ≈ 0.10",
            &failures,
            &checksRun)
    }

    private static func report(failures: [String], checksRun: Int) throws {
        if failures.isEmpty {
            print("ColdStartVerifier --self-test: PASS (all \(checksRun) checks)")
        } else {
            print("ColdStartVerifier --self-test: FAIL "
                + "(\(checksRun - failures.count)/\(checksRun) passed)")
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
                beatComposite: 0.2,
                bassAttRel: 0.2,
                gridBPM: 120,
                driftMs: 8.0,
                lockState: idx > 120 ? 2 : 1,
                sessionMode: 3,
                beatsPerBar: 4,
                accentConfidence: 1.0))
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
                beatComposite: 0.2,
                bassAttRel: 0.2,
                gridBPM: 0,
                driftMs: 0,
                lockState: 0,
                sessionMode: 0,
                beatsPerBar: 1,
                accentConfidence: 0.0))
        }
        return TrackSegment(
            index: 0,
            frames: frames,
            title: "Reactive",
            artist: nil,
            installedBPM: nil,
            installedMeter: nil)
    }

    /// Build a synthetic track with `audibleBeats` worth of windowed playback
    /// time, composite spikes at `accentHitTimes`, and accent_confidence
    /// linearly ramped from `confidenceRamp.start` to `confidenceRamp.end`
    /// across the recording.
    private static func makeAccentScenario(
        audibleBeats: [Double],
        accentHitTimes: [Double],
        confidenceRamp: (start: Double, end: Double),
        compositeAmplitude: Double
    ) -> TrackSegment {
        let fps = 60.0
        let durationS = (audibleBeats.last ?? 0) + 1.0
        let frameCount = max(1, Int(durationS * fps))
        // 16.6 ms per frame at 60 fps — frames within ±0.012 s of a hit time
        // straddle the spike. ±60 ms (the default acceptance window) is ±3.6
        // frames; firing the spike for ±1 frame guarantees the audible-beat
        // match logic still detects it inside the accept window.
        let frameSpan = 0.5 / fps
        var frames: [FeatureFrame] = []
        for idx in 0..<frameCount {
            let pt = Double(idx) / fps
            let progress = frameCount > 1
                ? Double(idx) / Double(frameCount - 1)
                : 0.0
            let conf = confidenceRamp.start
                + (confidenceRamp.end - confidenceRamp.start) * progress
            let nearHit = accentHitTimes.contains { abs($0 - pt) <= frameSpan }
            let composite = nearHit ? compositeAmplitude : 0.0
            frames.append(FeatureFrame(
                frame: idx,
                wallclockS: 900_000 + pt,
                playbackTimeS: pt,
                beatPhase01: 0,
                subBass: 0.0,
                beatBass: 0.0,
                beatComposite: composite,
                bassAttRel: 0.0,
                gridBPM: 120,
                driftMs: 0,
                lockState: 2,
                sessionMode: 3,
                beatsPerBar: 4,
                accentConfidence: conf))
        }
        _ = audibleBeats  // shape-only; audible reference is passed to evaluate().
        return TrackSegment(
            index: 0,
            frames: frames,
            title: "AccentWindowSelfTest",
            artist: "synthetic",
            installedBPM: 120,
            installedMeter: 4)
    }

    // MARK: - Helpers

    private static func near(_ lhs: Double, _ rhs: Double, tol: Double) -> Bool {
        abs(lhs - rhs) <= tol
    }

    private static func fmt(_ value: Double) -> String { String(format: "%.3f", value) }

    private static func check(
        _ cond: Bool, _ label: String,
        _ failures: inout [String], _ checksRun: inout Int
    ) {
        checksRun += 1
        if !cond { failures.append(label) }
    }
}

/// Minimal error carrying a non-zero process exit (avoids importing ArgumentParser here).
struct ExitCodeFailure: Error {}
