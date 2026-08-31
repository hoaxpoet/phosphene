// AuroraHueDriverTests — FBS.S5 (D-158): the FFO aurora hue must glide,
// never snap.
//
// The S5 forensics proved the remaining whole-frame flasher was the raw
// vocals-pitch → aurora-hue route: pitch confidence flaps across the 0.5
// gate boundary ~9×/s on real music (90 crossings in the 10 s So What
// window of session `2026-06-10T19-13-14Z`), snapping the curtain hue
// between the pitch phase and the valence phase. `RenderPipeline
// .auroraHueStep` moves the SAME composite-phase math CPU-side behind a
// τ ≈ 3 s EMA. These tests pin (a) flap immunity, (b) Matt's directed
// 8–10 s transition character, (c) target-math fidelity to the pre-S5
// shader formula at the gate extremes.

import XCTest
@testable import Renderer

final class AuroraHueDriverTests: XCTestCase {

    private let dt: Float = 1.0 / 60.0

    /// Worst-case gate flapping — confidence alternates 0.0 / 0.99 every
    /// frame with the pitch phase at one extreme (80 Hz → -0.20) and the
    /// valence phase at the other (+1 → +0.20). The raw route snapped the
    /// full 0.4 phase swing per frame; the driver must move at glide speed:
    /// per-frame output step bounded by α × swing ≈ 0.0022.
    func test_gateFlapping_neverStepsAtFlashSpeed() {
        var phase: Float = 0
        var maxStep: Float = 0
        for i in 0..<1200 {  // 20 s at 60 fps
            let next = RenderPipeline.auroraHueStep(
                smoothedPhase: phase,
                pitchHz: 80,
                pitchConfidence: i.isMultiple(of: 2) ? 0.0 : 0.99,
                valence: 1.0,
                dt: dt)
            maxStep = max(maxStep, abs(next - phase))
            phase = next
        }
        XCTAssertLessThanOrEqual(maxStep, 0.005,
                                 "hue must glide under gate flapping (max step \(maxStep))")
    }

    /// A sustained confident vocal entry must complete its hue transition
    /// over Matt's directed 8–10 s window: < 94 % of the way at 7 s,
    /// ≥ 94 % by 9.1 s (3τ = 9 s → 95 %).
    func test_sustainedPitch_transitionsOver8to10Seconds() {
        let target: Float = 0.20  // 1 kHz at full confidence
        var phase: Float = 0
        var at7s: Float = 0
        var at9s: Float = 0
        var t: Float = 0
        while t < 9.1 {
            phase = RenderPipeline.auroraHueStep(
                smoothedPhase: phase, pitchHz: 1000, pitchConfidence: 1.0,
                valence: 0, dt: dt)
            t += dt
            if t <= 7.0 { at7s = phase }
            at9s = phase
        }
        XCTAssertLessThan(at7s / target, 0.94,
                          "transition must not complete before ~8 s (at 7 s: \(at7s / target))")
        XCTAssertGreaterThanOrEqual(at9s / target, 0.94,
                                    "transition must be essentially complete by ~9 s (\(at9s / target))")
    }

    /// Target-math fidelity to the pre-S5 shader formula at the gate
    /// extremes: zero confidence converges to the valence phase
    /// (valence × 0.20); full confidence converges to the perceptual
    /// log-scale pitch phase. 283 Hz sits at log2(283/80)/log2(1000/80)
    /// ≈ 0.5 → phase ≈ 0.
    func test_convergedTargets_matchShaderFormula() {
        func converge(hz: Float, conf: Float, valence: Float) -> Float {
            var phase: Float = 0
            for _ in 0..<3600 {  // 60 s — fully settled
                phase = RenderPipeline.auroraHueStep(
                    smoothedPhase: phase, pitchHz: hz, pitchConfidence: conf,
                    valence: valence, dt: dt)
            }
            return phase
        }
        XCTAssertEqual(converge(hz: 1000, conf: 0, valence: -1.0), -0.20, accuracy: 0.002,
                       "zero confidence → valence fallback phase")
        XCTAssertEqual(converge(hz: 80, conf: 1.0, valence: 1.0), -0.20, accuracy: 0.002,
                       "full confidence, 80 Hz → pitch phase floor")
        XCTAssertEqual(converge(hz: 1000, conf: 1.0, valence: -1.0), 0.20, accuracy: 0.002,
                       "full confidence, 1 kHz → pitch phase ceiling")
        XCTAssertEqual(converge(hz: 283, conf: 1.0, valence: 0), 0.0, accuracy: 0.003,
                       "perceptual mid-pitch → neutral phase")
    }
}
