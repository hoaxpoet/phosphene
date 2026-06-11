// AuroraOrbitDriverTests — BUG-047: the aurora curtain orbit must advance by
// `arousal-speed × Δtime` per frame, never rescaling history.
//
// The pre-fix shader computed `azimuth = arousalSpeed × accumulatedTime` —
// the speed factor multiplied the ENTIRE elapsed total, so any arousal
// movement retroactively rescaled history. Per-second mood wobble on jazz
// teleported the azimuth ±2+ rad/s and the whole ocean marched through the
// palette second-by-second (So What, session `2026-06-11T13-10-42Z`;
// pixel proof: per-second hue swing 95° → 3° with the integrated orbit).
// The error grew with elapsed time — openings looked fine, minute two
// thrashed.

import XCTest
@testable import Renderer

final class AuroraOrbitDriverTests: XCTestCase {

    /// Worst-case mood wobble LATE in a track (the failure's signature):
    /// arousal alternates ±0.5 every frame while the audio clock advances
    /// normally. The azimuth step must stay bounded by the max orbital
    /// speed × the frame's increment — the legacy product would jump by
    /// elapsed-total × Δspeed ≈ many radians.
    func test_arousalWobble_neverRescalesHistory() {
        var az: Float = 0
        // Wind forward to "minute two" — large accumulated time on the books.
        for _ in 0..<7200 {
            az = RenderPipeline.auroraOrbitStep(azimuth: az, aatDelta: 0.0012, arousal: 0.3)
        }
        let maxStepBound = 0.0012 * 1.0 * 2.0 * Float.pi / 2.5   // max speed = 1.0
        var maxStep: Float = 0
        for i in 0..<600 {
            let next = RenderPipeline.auroraOrbitStep(
                azimuth: az, aatDelta: 0.0012,
                arousal: i.isMultiple(of: 2) ? 0.5 : -0.5)
            maxStep = max(maxStep, abs(next - az))
            az = next
        }
        XCTAssertLessThanOrEqual(maxStep, maxStepBound * 1.001,
                                 "azimuth must advance by speed × Δtime only (step \(maxStep))")
    }

    /// Arousal scales the orbit SPEED: a high-arousal minute advances the
    /// azimuth ~2× a low-arousal minute (speed range [0.5, 1.0]).
    func test_arousal_scalesSpeed() {
        var calm: Float = 0
        var hot: Float = 0
        for _ in 0..<3600 {
            calm = RenderPipeline.auroraOrbitStep(azimuth: calm, aatDelta: 0.0012, arousal: -1)
            hot = RenderPipeline.auroraOrbitStep(azimuth: hot, aatDelta: 0.0012, arousal: 1)
        }
        XCTAssertEqual(hot / calm, 2.0, accuracy: 0.01,
                       "speed range [0.5, 1.0] → 2× advance at full arousal")
    }

    /// A track change resets the audio-time accumulator (delta goes
    /// negative). The orbit must hold, not jump backwards.
    func test_trackChangeReset_holdsAzimuth() {
        var az: Float = 5.0
        let before = az
        az = RenderPipeline.auroraOrbitStep(azimuth: az, aatDelta: -3.7, arousal: 0)
        XCTAssertEqual(az, before, "negative Δtime (track reset) must advance nothing")
    }
}
