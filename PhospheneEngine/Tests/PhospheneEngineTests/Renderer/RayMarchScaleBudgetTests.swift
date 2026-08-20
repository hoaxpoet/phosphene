// RayMarchScaleBudgetTests — the ray-march scale a drawable actually marches at.
//
// This suite used to guard PERF.14's marched-pixel cap (1536×864). PERF.16 falsified the
// step the cap was built on — an offline sweep found a smooth, mildly sublinear cost curve
// with no discontinuity anywhere — and Matt removed it. What is left to protect is the
// property the cap kept violating: a preset marches at the scale its sidecar declares,
// at every window size, so a look certified at one size is the same look at another.
//
// Pure arithmetic — no GPU, no drawable.

import Testing
@testable import Renderer

// MARK: - RayMarchScaleBudgetTests

@Suite("Marched-pixel scale")
struct RayMarchScaleBudgetTests {

    /// The declared scale survives every window size. PERF.14's cap silently dropped VL from
    /// 0.5 to 0.4 at 4K — softer at fullscreen than in the window it was certified in, which is
    /// exactly the drift a certified look must not have.
    @Test("a declared scale is honoured at every size")
    func honoursDeclaredScale() {
        #expect(abs(RenderPipeline.marchScale(declared: 0.5) - 0.5) < 0.001)
        #expect(abs(RenderPipeline.marchScale(declared: 0.65) - 0.65) < 0.001)
    }

    /// Presets that never declared a render_scale keep marching at full resolution.
    @Test("leaves undeclared presets at full resolution")
    func leavesUndeclaredPresetsAlone() {
        #expect(abs(RenderPipeline.marchScale(declared: 1.0) - 1.0) < 0.001)
    }

    /// The [0.4, 1.0] clamp holds from both ends: below 0.4 the upscale stops being softness
    /// and starts being a different image, and nothing may be raised above what it asked for.
    @Test("clamps to [0.4, 1.0]")
    func clampsToFloorAndCeiling() {
        #expect(abs(RenderPipeline.marchScale(declared: 0.1) - 0.4) < 0.001)
        #expect(abs(RenderPipeline.marchScale(declared: 1.5) - 1.0) < 0.001)
    }
}
