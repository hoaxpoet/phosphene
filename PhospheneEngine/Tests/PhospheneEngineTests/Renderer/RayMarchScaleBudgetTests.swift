// RayMarchScaleBudgetTests — the marched-pixel budget, kept on Matt's call (PERF.16)
// because it is worth ~2x the frame rate at 4K.
//
// ⚠ The budget's ORIGINAL justification (PERF.14: ray-march cost is a "step", 11.7x from
// a 1.56x pixel cut) was falsified by PERF.16's offline sweep — the curve is smooth and
// mildly sublinear with no discontinuity anywhere. The budget survives on a different and
// better-measured basis: live, VL reads 15.88 ms p50 / 56 fps delivered at 1536x864
// (`2026-08-20T18-17-43Z`) against 31.16 ms / 32 fps at 1920x1080 (PERF.15). Matt chose
// the frame rate over the sharpness. Do not re-derive the step model from these numbers.
//
// Pure arithmetic — no GPU, no drawable. Every expectation below is a size VL has
// actually been measured at live, so a regression here is a regression in something
// Matt has seen.

import Testing
@testable import Renderer

// MARK: - RayMarchScaleBudgetTests

@Suite("Marched-pixel budget")
struct RayMarchScaleBudgetTests {

    /// The three sizes VL has been measured at, and what each must resolve to.
    @Test("resolves the measured VL configurations")
    func matchesMeasuredConfigurations() {
        // 4K fullscreen: 0.5 marched 1920x1080 and cost 175 ms; the budget must pull it to
        // the 0.4 that measured <= 15 ms.
        #expect(abs(RenderPipeline.marchScale(declared: 0.5, width: 3840, height: 2160) - 0.4) < 0.001)

        // The 2884x1662 window VL was certified in — 0.5 must survive untouched.
        #expect(abs(RenderPipeline.marchScale(declared: 0.5, width: 2884, height: 1662) - 0.5) < 0.001)

        // 1080p was never slow; the budget must not soften it.
        #expect(abs(RenderPipeline.marchScale(declared: 0.5, width: 1920, height: 1080) - 0.5) < 0.001)
    }

    /// The budget only ever LOWERS the scale — never raises a preset above what it asked for.
    @Test("never raises a declared scale")
    func neverRaisesDeclaredScale() {
        for (w, h) in [(640, 480), (1280, 720), (1920, 1080), (2884, 1662), (3840, 2160)] {
            #expect(RenderPipeline.marchScale(declared: 0.5, width: w, height: h) <= 0.5)
        }
    }

    /// Presets that never declared a render_scale keep marching at full resolution whatever the
    /// window size — the budget must not silently rescale the certified catalog.
    @Test("leaves undeclared presets at full resolution")
    func leavesUndeclaredPresetsAlone() {
        #expect(abs(RenderPipeline.marchScale(declared: 1.0, width: 3840, height: 2160) - 1.0) < 0.001)
    }

    /// The [0.4, 1.0] floor still wins: past 4K the budget would ask for less, and must not get it.
    @Test("holds the 0.4 floor above 4K")
    func holdsFloorAboveFourK() {
        #expect(abs(RenderPipeline.marchScale(declared: 0.5, width: 7680, height: 4320) - 0.4) < 0.001)
        #expect(abs(RenderPipeline.marchScale(declared: 0.1, width: 1920, height: 1080) - 0.4) < 0.001)
    }

    /// A degenerate drawable must not divide by zero or return something unusable.
    @Test("survives a zero-sized drawable")
    func survivesZeroSizedDrawable() {
        #expect(abs(RenderPipeline.marchScale(declared: 0.5, width: 0, height: 0) - 0.5) < 0.001)
    }
}
