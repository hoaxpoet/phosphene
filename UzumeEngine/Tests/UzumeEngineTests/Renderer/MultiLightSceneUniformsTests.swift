// MultiLightSceneUniformsTests — RMENV.1 decode plumbing.
//
// Verifies makeSceneUniforms() populates the appended light slots + lightCount
// from the sidecar scene_lights array. The byte-identical guarantee (a single
// light produces the same render as before RMENV.1) is covered separately by
// PresetRegressionTests staying green on every existing ray-march preset; this
// suite proves the multi-light path is actually wired, not silently dropped.

import Testing
import Foundation
import simd
@testable import Presets
@testable import Shared

@Suite("RMENV.1 — multi-light SceneUniforms decode")
struct MultiLightSceneUniformsTests {

    /// Decode a descriptor through the real sidecar JSON path with `count` lights,
    /// the i-th light carrying intensity `i+1` so each slot is individually checkable.
    private func uniforms(lightCount count: Int) throws -> SceneUniforms {
        let lights = (0..<count).map { i in
            "{\"position\": [\(i), 5, -2], \"color\": [0.9, 0.5, 0.5], \"intensity\": \(i + 1)}"
        }.joined(separator: ",")
        let json = """
        {"name": "MultiLightProbe", "family": "geometric",
         "passes": ["ray_march", "post_process"],
         "scene_camera": {"position": [2, 1, -3], "target": [0, 0, 0], "fov": 70},
         "scene_lights": [\(lights)]}
        """
        return try JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
            .makeSceneUniforms()
    }

    @Test("Single light → count 1, extra slots zero (the byte-identical case)")
    func singleLight() throws {
        let u = try uniforms(lightCount: 1)
        #expect(u.lightingParams.x == 1)
        #expect(u.lightPositionAndIntensity.w == 1)
        #expect(u.light1PositionAndIntensity == .zero)
        #expect(u.light2PositionAndIntensity == .zero)
        #expect(u.light3PositionAndIntensity == .zero)
    }

    @Test("Three lights → count 3, key + light1 + light2 populated, light3 zero")
    func threeLights() throws {
        let u = try uniforms(lightCount: 3)
        #expect(u.lightingParams.x == 3)
        #expect(u.lightPositionAndIntensity.w == 1)   // light 0 intensity
        #expect(u.light1PositionAndIntensity.w == 2)  // light 1
        #expect(u.light2PositionAndIntensity.w == 3)  // light 2
        #expect(u.light3PositionAndIntensity == .zero)   // unused slot stays zero
    }

    @Test("Four lights fill all slots; a fifth is ignored, count clamps to 4")
    func fourLightsCapped() throws {
        let u = try uniforms(lightCount: 5)
        #expect(u.lightingParams.x == 4)
        #expect(u.lightPositionAndIntensity.w == 1)
        #expect(u.light1PositionAndIntensity.w == 2)
        #expect(u.light2PositionAndIntensity.w == 3)
        #expect(u.light3PositionAndIntensity.w == 4)   // 4th light present
        // The 5th light's intensity (5) must appear in no slot.
    }

    @Test("No lights → count clamps to 1 (never zero — the loop bound is >= 1)")
    func noLights() throws {
        let u = try uniforms(lightCount: 0)
        #expect(u.lightingParams.x == 1)
    }
}
