// PresetDescriptor+SceneUniforms — Build SceneUniforms from a preset's JSON scene config.
//
// Extracted from VisualizerEngine+Presets.swift so the camera math is testable without
// an app-layer dependency. Tests import Presets and call desc.makeSceneUniforms() directly.
//
// Contract:
//   - JSON `fov` is in degrees. Conversion to radians happens exactly once, here.
//   - `audioTime` (sceneParamsA.x) and `aspectRatio` (sceneParamsA.y) are written as
//     placeholders (0 and 16/9). The render loop overwrites both each frame.
//   - `nearPlane` (sceneParamsA.z) and `farPlane` (sceneParamsA.w) are set from the
//     descriptor and never changed again. A farPlane of 0 causes the G-buffer ray march
//     loop to exit immediately, rendering all-sky — this is the regression caught by
//     RayMarchDiagnosticTests.test_nearAndFarPlanesAreNonZero.

import Foundation
import Shared
import simd

// MARK: - PresetDescriptor + SceneUniforms

extension PresetDescriptor {

    // MARK: - makeSceneUniforms

    /// Build a `SceneUniforms` value from this descriptor's scene camera, lights, fog,
    /// and ambient configuration.
    ///
    /// `audioTime` and `aspectRatio` in the returned uniforms are placeholder values (0
    /// and 16/9). The render loop in `RenderPipeline+RayMarch.drawWithRayMarch` overwrites
    /// them each frame before encoding the G-buffer pass.
    ///
    /// ## FOV Conversion
    /// The JSON `scene_camera.fov` field is in **degrees** (e.g. 65). This method converts
    /// it to radians exactly once. The value stored in `cameraOriginAndFov.w` must be in
    /// radians because the G-buffer shader computes `tan(fov * 0.5)` directly.
    ///
    /// ## Camera Basis
    /// ```
    /// right = normalize(cross(worldUp, forward))   // +X for a +Z-forward camera
    /// up    = cross(forward, right)                 // +Y for a level camera
    /// ```
    /// Note: `cross(forward, worldUp)` gives −X (mirrors the image). Both cross product
    /// orders appear in tutorials — only `cross(worldUp, forward)` is correct here.
    public func makeSceneUniforms() -> SceneUniforms {
        var uniforms = SceneUniforms()

        // sceneParamsA: z = nearPlane, w = farPlane.
        // Must be set here — drawWithRayMarch only updates .x (audioTime) and .y (aspectRatio).
        // Zero-initialised SceneUniforms() gives farPlane = 0; the ray march loop condition
        // `t < farPlane` is always false at t=0.1, so every ray returns sky depth (1.0).
        uniforms.sceneParamsA = SIMD4(0, 16.0 / 9.0, 0.1, sceneFarPlane)

        // Camera: compute orthonormal basis from position + target.
        if let cam = sceneCamera {
            let fwd     = simd_normalize(cam.target - cam.position)
            let worldUp = SIMD3<Float>(0, 1, 0)

            // cross(worldUp, fwd) → right (+X for a camera pointing along +Z).
            // cross(fwd, worldUp) gives −X and mirrors the image horizontally.
            let right = simd_normalize(simd_cross(worldUp, fwd))

            // cross(fwd, right) → up (orthogonal to both, +Y for a level camera).
            // cross(right, fwd) gives −Y and flips the image vertically.
            let up = simd_cross(fwd, right)

            // JSON fov is in degrees; the G-buffer shader calls tan(fov * 0.5) and expects
            // radians. Storing the raw degree value produces tan(32.5 rad) ≈ 1.84 — a ~123°
            // frustum half-angle that makes almost every ray miss all geometry.
            let fovRadians = cam.fov * Float.pi / 180.0

            uniforms.cameraOriginAndFov = SIMD4(cam.position.x, cam.position.y, cam.position.z, fovRadians)
            uniforms.cameraForward      = SIMD4(fwd.x, fwd.y, fwd.z, 0)
            uniforms.cameraRight        = SIMD4(right.x, right.y, right.z, 0)
            uniforms.cameraUp           = SIMD4(up.x, up.y, up.z, 0)
        }

        // Lighting (RMENV.1). The primary light stays in its original slot so a
        // single-light preset is byte-identical to the pre-RMENV path; lights 1–3
        // and lightingParams populate only when the sidecar declares more (capped
        // at 4, the deferred-lighting loop bound). Extra sidecar lights beyond 4
        // are ignored (documented, not silently reinterpreted).
        if let light = sceneLights.first {
            uniforms.lightPositionAndIntensity = SIMD4(
                light.position.x, light.position.y, light.position.z, light.intensity)
            uniforms.lightColor = SIMD4(light.color.x, light.color.y, light.color.z, 0)
        }
        let extraLights = sceneLights.dropFirst().prefix(3)
        for (offset, light) in extraLights.enumerated() {
            let pos = SIMD4<Float>(light.position.x, light.position.y, light.position.z, light.intensity)
            let col = SIMD4<Float>(light.color.x, light.color.y, light.color.z, 0)
            switch offset {
            case 0: uniforms.light1PositionAndIntensity = pos; uniforms.light1Color = col
            case 1: uniforms.light2PositionAndIntensity = pos; uniforms.light2Color = col
            default: uniforms.light3PositionAndIntensity = pos; uniforms.light3Color = col
            }
        }
        uniforms.lightingParams.x = Float(min(max(sceneLights.count, 1), 4))
        // RMENV.3: lane .y carries the environment type into the shader so the
        // miss/background path can render a matching backdrop (0 = sky, unchanged).
        uniforms.lightingParams.y = Float(environmentType)

        // Fog: convert density → far distance. Dense fog (0.05) → 20 units; light (0.015) → ~67.
        //
        // scene_fog == 0 semantically means "no fog" (e.g. printmaking aesthetic).
        // The shader formula `fogFactor = clamp((t - fogNear) / max(fogFar - fogNear, 0.001), 0, 1)`
        // with a zero fogFar saturates to 1.0 for any t > 0.001 — i.e. max fog,
        // the exact opposite of the intent. Using a very large fallback pushes
        // fogFactor well below the visible threshold at any realistic far-plane.
        //
        // sceneFogNear (default 20.0) was previously the hard-coded value in
        // `SceneUniforms()` — preserving it as the descriptor default keeps
        // existing presets (Kinetic Sculpture) byte-identical.
        // Close-framed presets (Ferrofluid Ocean) set `scene_fog_near: 0` in
        // JSON so the fog band starts at the camera and covers the visible
        // surface. See V.9 Session 2 carry-forward note.
        let fogFar: Float = sceneFog > 0 ? max(1.0, 1.0 / sceneFog) : 1_000_000

        // sceneParamsB.z is the D-057 frame-budget step multiplier — NOT a preset
        // config value. It defaults to 1.0 (the live path's full-quality value) so
        // fixtures march the same 128-step budget as production by construction;
        // the live render loop overwrites it per frame under frame-budget pressure
        // (BUG-034: packing sceneAmbient here had every fixture marching at 32
        // steps). Slot map: see the SceneUniforms definition.
        uniforms.sceneParamsB = SIMD4(sceneFogNear, fogFar, 1.0, 0)

        return uniforms
    }
}
