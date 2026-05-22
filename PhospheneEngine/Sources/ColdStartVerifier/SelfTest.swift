// SelfTest — In-memory validation of the CS.1 measurement arithmetic.
//
// `--self-test` constructs a controlled scenario with KNOWN answers — a clock
// offset, a per-beat calibration error, a degenerate track — and asserts the
// harness recovers them. It exercises the whole arithmetic chain (cross-
// correlation alignment, beatPhase01 wrap detection, onset→playback-time
// mapping, delta matching, verdict) using pure numeric arrays — no audio files.
//
// This is a self-test of the harness's OWN math, not a claim about Phosphene's
// behaviour: the CS.1 verdict itself comes only from a real captured session
// (the no-synthetic-audio rule governs claims about the engine, not unit tests
// of measurement code). It is runnable before the real session is captured, so
// the harness is verified before it is trusted.

import Foundation

enum SelfTest {

    /// Run the self-test. Throws `ExitCodeFailure` on any assertion miss.
    static func run() throws {
        var failures: [String] = []

        // --- median ---------------------------------------------------------
        check(ColdStartAnalysis.median([1, 2, 3, 4]) == 2.5, "median(even)", &failures)
        check(ColdStartAnalysis.median([3, 1, 2]) == 2.0, "median(odd)", &failures)

        // --- full pipeline on a known scenario ------------------------------
        // Track starts 2.0 s into the raw tap → offset O = pt − raw = −2.0.
        // Beats every 0.5 s (120 BPM). Visual beats lead onsets by +8 ms.
        let clockOffset = -2.0
        let injectedDeltaMs = 8.0
        let period = 0.5
        let beatPts = stride(from: 0.3, through: 11.8, by: period).map { $0 }

        let rawTap = makeRawTap(beatPts: beatPts, clockOffset: clockOffset)
        let track = makeTrack(
            beatPts: beatPts, injectedDeltaMs: injectedDeltaMs, period: period)
        let config = VerifierConfig(
            firstWindowS: 10,
            passWindowMs: 50,
            tightWindowMs: 30,
            passRate: 0.9,
            displayShiftMs: 0)

        let result = ColdStartAnalysis.run(tracks: [track], rawTap: rawTap, config: config)
        guard let res = result.tracks.first else {
            throw fail("self-test produced no track result")
        }

        check(res.verdict == .pass, "verdict == pass (got \(res.verdict.rawValue))", &failures)
        check(result.overallPass, "overallPass true", &failures)
        check(
            near(res.alignment.offsetS, clockOffset, tol: 0.030),
            "recovered clock offset \(fmt(res.alignment.offsetS)) ≈ \(clockOffset)",
            &failures)
        check(res.alignment.confident, "alignment confident", &failures)
        if let med = res.medianCorrectedMs {
            check(
                near(med, injectedDeltaMs, tol: 8.0),
                "median corrected Δ \(fmt(med)) ms ≈ \(injectedDeltaMs) ms",
                &failures)
        } else {
            failures.append("median corrected Δ is nil")
        }
        check(
            res.unmatchedCount == 0,
            "no unmatched onsets (got \(res.unmatchedCount))",
            &failures)

        // --- degenerate path: a no-grid track -------------------------------
        let reactive = makeReactiveTrack()
        let degen = ColdStartAnalysis.run(tracks: [reactive], rawTap: rawTap, config: config)
        check(
            degen.tracks.first?.verdict == .degenerate,
            "reactive (no-grid) track → degenerate",
            &failures)

        if failures.isEmpty {
            print("ColdStartVerifier --self-test: PASS (all 7 checks)")
        } else {
            print("ColdStartVerifier --self-test: FAIL")
            for failure in failures { print("  ✗ \(failure)") }
            throw ExitCodeFailure()
        }
    }

    // MARK: - Scenario builders

    private static func makeRawTap(beatPts: [Double], clockOffset: Double) -> RawTapAnalysis {
        let sampleRate = 48_000.0
        let hopS = Double(RawTapAnalysis.hop) / sampleRate
        // raw-tap time = pt − clockOffset.
        let onsetTimes = beatPts.map { $0 - clockOffset }
        let durationS = (onsetTimes.max() ?? 0) + 2.0
        let count = Int(durationS / hopS) + 1
        var env = [Double](repeating: 0.1, count: count)
        for hopIdx in 0..<count {
            let time = Double(hopIdx) * hopS
            for onset in onsetTimes {
                env[hopIdx] += spike(time, onset)
            }
        }
        return RawTapAnalysis(
            sampleRate: sampleRate,
            durationS: durationS,
            onsets: onsetTimes,
            lowEnvelope: env,
            envelopeHopS: hopS)
    }

    private static func makeTrack(
        beatPts: [Double], injectedDeltaMs: Double, period: Double
    ) -> TrackSegment {
        let visual0 = beatPts[0] + injectedDeltaMs / 1000.0
        var frames: [FeatureFrame] = []
        let fps = 60.0
        let frameCount = Int(13.0 * fps)
        for idx in 0..<frameCount {
            let pt = Double(idx) / fps
            var sub = 0.1
            for beat in beatPts { sub += spike(pt, beat) }
            // Linear sawtooth wrapping exactly at each visual beat.
            let beatIdx = ((pt - visual0) / period).rounded(.down)
            let beatStart = visual0 + beatIdx * period
            let phase = max(0, min(0.9999, (pt - beatStart) / period))
            frames.append(FeatureFrame(
                frame: idx,
                wallclockS: 1000 + pt,
                playbackTimeS: pt,
                beatPhase01: phase,
                subBass: sub,
                beatBass: sub,
                bassAttRel: sub,
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
                wallclockS: 2000 + pt,
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

    /// Triangular spike, ±40 ms wide, peak 1.0 at `center`.
    private static func spike(_ time: Double, _ center: Double) -> Double {
        max(0, 1.0 - abs(time - center) / 0.04)
    }

    private static func near(_ lhs: Double, _ rhs: Double, tol: Double) -> Bool {
        abs(lhs - rhs) <= tol
    }

    private static func fmt(_ value: Double) -> String { String(format: "%.3f", value) }

    private static func check(_ cond: Bool, _ label: String, _ failures: inout [String]) {
        if !cond { failures.append(label) }
    }

    private static func fail(_ message: String) -> ExitCodeFailure {
        print("ColdStartVerifier --self-test: FAIL — \(message)")
        return ExitCodeFailure()
    }
}

/// Minimal error carrying a non-zero process exit (avoids importing ArgumentParser here).
struct ExitCodeFailure: Error {}
