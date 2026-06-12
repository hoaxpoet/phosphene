// StepBudgetParityTests — BUG-034 regression gate: fixtures and the live app
// march identical step budgets by construction.
//
// History: makeSceneUniforms() packed sceneAmbient (default 0.1) into
// sceneParamsB.z, which the G-buffer preamble reads as the D-057 frame-budget
// step multiplier (clamp(0.1, 0.25, 1.0) = 0.25 → 32 steps). The live path
// overwrites .z = 1.0 per frame, so every ray-march fixture rendered at 1/4
// the live step budget — golden hashes, RENDER_VISUAL contact sheets, and
// certification evidence included. These tests pin the contract that killed
// that class of bug:
//
//   1. Parity: the effective march-step budget derived from a descriptor's
//      raw makeSceneUniforms() output equals the budget derived from the
//      live pipeline's default multiplier — both run through the same
//      preamble formula, neither side a hardcoded step count.
//   2. Default: raw makeSceneUniforms() (and the bare SceneUniforms() init)
//      yield multiplier 1.0, guarding against the regression re-entering
//      via a new packing into sceneParamsB.z.
//
// Slot-map contract: Shared/AudioFeatures+SceneUniforms.swift.

import Testing
import Foundation
import simd
@testable import Renderer
@testable import Presets
@testable import Shared

// MARK: - Suite

@Suite("StepBudgetParity")
struct StepBudgetParityTests {

    // MARK: - Preamble formula mirror

    /// The G-buffer preamble's step-budget computation, mirrored verbatim from
    /// the MSL emitted in `PresetLoader+Preamble` (see "frame-budget step
    /// multiplier (D-057)"):
    ///
    ///     float stepMult = (scene.sceneParamsB.z > 0.0) ? clamp(scene.sceneParamsB.z, 0.25, 1.0) : 1.0;
    ///     int maxMarchSteps = int(128.0 * stepMult);
    ///
    /// Both parity sides below run through THIS function, so the assertion
    /// compares the two code paths' multiplier values — not two constants.
    private func effectiveMaxMarchSteps(multiplier: Float) -> Int {
        let stepMult = multiplier > 0.0 ? min(max(multiplier, 0.25), 1.0) : 1.0
        return Int(128.0 * stepMult)
    }

    /// A minimal ray-march descriptor decoded from sidecar JSON — the same
    /// construction path every preset sidecar takes.
    private func makeRayMarchDescriptor() throws -> PresetDescriptor {
        let json = """
        {
            "name": "Step Budget Parity Fixture",
            "family": "geometric",
            "passes": ["ray_march"],
            "scene_camera": {
                "position": [0, 2, -5],
                "target":   [0, 0, 0],
                "fov": 65
            },
            "scene_lights": [{
                "position": [3, 8, -3],
                "color":    [1, 1, 1],
                "intensity": 5.0
            }],
            "scene_fog": 0.015
        }
        """
        return try JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
    }

    // MARK: - Tests

    @Test("Fixture helper and live path derive the same march-step budget")
    func fixtureAndLivePathMarchIdenticalStepBudgets() throws {
        // Fixture side: the multiplier exactly as every test harness binds it —
        // raw makeSceneUniforms() output, no per-frame overwrites.
        let descriptor = try makeRayMarchDescriptor()
        let fixtureMultiplier = descriptor.makeSceneUniforms().sceneParamsB.z

        // Live side: the multiplier the render loop writes into the same slot
        // each frame (RenderPipeline+RayMarch), read from a real pipeline
        // instance at its default (full-quality) state.
        let context = try MetalContext()
        let shaderLibrary = try ShaderLibrary(context: context)
        let pipeline = try RayMarchPipeline(context: context, shaderLibrary: shaderLibrary)
        let liveMultiplier = pipeline.stepCountMultiplier

        let fixtureSteps = effectiveMaxMarchSteps(multiplier: fixtureMultiplier)
        let liveSteps = effectiveMaxMarchSteps(multiplier: liveMultiplier)

        #expect(fixtureSteps == liveSteps,
                """
                Fixture path marches \(fixtureSteps) steps but the live path marches \
                \(liveSteps) (fixture multiplier \(fixtureMultiplier), live multiplier \
                \(liveMultiplier)). BUG-034 regression: something other than the D-057 \
                step multiplier is being packed into sceneParamsB.z.
                """)
        // Pin full quality explicitly: parity at a degraded budget would also
        // satisfy ==, but the default contract is the full 128-step budget.
        #expect(liveSteps == 128, "Live default step budget moved off 128 — D-057 default changed?")
    }

    @Test("Raw makeSceneUniforms() defaults the D-057 multiplier slot to 1.0")
    func makeSceneUniformsDefaultsMultiplierToFullQuality() throws {
        let descriptor = try makeRayMarchDescriptor()
        let multiplier = descriptor.makeSceneUniforms().sceneParamsB.z
        #expect(multiplier == 1.0,
                """
                makeSceneUniforms() wrote \(multiplier) into sceneParamsB.z — the D-057 \
                step-multiplier slot must default to 1.0 (live full-quality). A value \
                like 0.05–0.1 means a config scalar was packed into the slot again \
                (the BUG-034 shape: fixtures silently march a fraction of the live budget).
                """)

        // The bare init must agree — hand-rolled test uniforms start from it.
        #expect(SceneUniforms().sceneParamsB.z == 1.0,
                "SceneUniforms() bare init no longer defaults sceneParamsB.z to 1.0")
    }
}
