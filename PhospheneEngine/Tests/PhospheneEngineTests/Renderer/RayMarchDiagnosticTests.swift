// RayMarchDiagnosticTests — CPU-only tests for SceneUniforms construction and JSON parsing.
//
// These tests cover the three failure modes that caused the Glass Brutalist preset to
// produce a flat grey orb and 85%+ ray misses across multiple debug sessions:
//
//   Failure mode A — FOV in radians stored as degrees (or double-converted):
//     tan(65 * 0.5) ≈ tan(32.5 rad) ≈ 1.84 → ~123° frustum half-angle → almost every ray
//     misses all geometry. Caught by: test_fovIsStoredInRadians, test_fovIsNotDoubleConverted.
//
//   Failure mode B — Cross product in wrong order for camera basis:
//     cross(fwd, worldUp) gives right = −X, mirroring the image. For an off-centre camera
//     at x=0.8 this also shifts the visible corridor wall differently per side. Caught by:
//     test_cameraRightIsPositiveXForZForwardCamera, test_cameraBasisOrthonormal.
//
//   Failure mode C — Light intensity corrupted in JSON (300 instead of 3):
//     Full HDR over-exposure overwhelms bloom and produces a blown-out white frame.
//     Caught by: test_lightIntensityPassesThroughUnchanged.
//
// (The per-preset GlassBrutalist JSON validation suite that once lived here was
//  removed with the Glass Brutalist preset — see docs/DECISIONS.md D-186.)
//
// All tests call PresetDescriptor.makeSceneUniforms() — the function extracted from
// VisualizerEngine+Presets.swift in Increment 3.5.3. No Metal, no GPU, no MTLDevice.

import XCTest
import simd
@testable import Presets
@testable import Shared

// MARK: - SceneUniforms Construction Tests

final class SceneUniformsConstructionTests: XCTestCase {

    // MARK: - Helpers

    private func desc(
        posX: Float = 0.8,  posY: Float = 1.8,  posZ: Float = -1.0,
        tgtX: Float = -0.3, tgtY: Float = 1.6,  tgtZ: Float = 12.0,
        fov: Float = 65.0,
        intensity: Float = 3.0,
        fog: Float = 0.015
    ) throws -> PresetDescriptor {
        let json = """
        {
            "name": "Diagnostic Test",
            "family": "geometric",
            "passes": ["ray_march"],
            "scene_camera": {
                "position": [\(posX), \(posY), \(posZ)],
                "target":   [\(tgtX), \(tgtY), \(tgtZ)],
                "fov": \(fov)
            },
            "scene_lights": [{
                "position": [0, 4.5, 2],
                "color":    [1, 0.95, 0.9],
                "intensity": \(intensity)
            }],
            "scene_fog": \(fog)
        }
        """
        return try JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
    }

    // MARK: - FOV Tests

    /// 65° in radians is ~1.1345. Storing raw degrees (65.0) produces tan(32.5 rad) ≈ 1.84 —
    /// a 123° frustum half-angle that makes almost every ray miss all geometry.
    func test_fovIsStoredInRadians() throws {
        let d = try desc(fov: 65)
        let uniforms = d.makeSceneUniforms()
        let expected = Float(65.0 * .pi / 180.0)   // ≈ 1.1345
        XCTAssertEqual(uniforms.cameraOriginAndFov.w, expected, accuracy: 0.001,
            "FOV must be stored in radians (~1.13 for 65°). "
            + "Got \(uniforms.cameraOriginAndFov.w). "
            + "Conversion must happen exactly once in makeSceneUniforms.")
    }

    /// Double conversion (degrees → radians → radians again) yields 65 * (π/180)² ≈ 0.0198,
    /// making tan(fov * 0.5) ≈ 0.0099 — almost all rays travel parallel to forward, missing
    /// all side walls and producing a tiny, barely-visible centre dot.
    func test_fovIsNotDoubleConverted() throws {
        let d = try desc(fov: 65)
        let uniforms = d.makeSceneUniforms()
        XCTAssertGreaterThan(uniforms.cameraOriginAndFov.w, 0.5,
            "FOV appears double-converted to radians: \(uniforms.cameraOriginAndFov.w). "
            + "Expected ~1.13. Check PresetDescriptor.makeSceneUniforms — conversion must "
            + "happen exactly once (cam.fov * .pi / 180).")
    }

    // MARK: - Camera Basis Tests

    /// For a camera at (0, 2, -3) looking at (0, 2, 4) the forward vector points along +Z.
    func test_cameraForwardPointsTowardTarget() throws {
        let d = try desc(posX: 0, posY: 2, posZ: -3, tgtX: 0, tgtY: 2, tgtZ: 4)
        let u = d.makeSceneUniforms()
        let fwd = SIMD3<Float>(u.cameraForward.x, u.cameraForward.y, u.cameraForward.z)
        XCTAssertGreaterThan(fwd.z, 0.99,
            "Forward must point along +Z for a camera looking from z=-3 to z=4. Got \(fwd).")
        XCTAssertEqual(simd_length(fwd), 1.0, accuracy: 0.001,
            "Forward vector must be normalised, got length \(simd_length(fwd)).")
    }

    /// cross(worldUp, fwd) → +X for a +Z-forward camera.
    /// The wrong order, cross(fwd, worldUp), gives −X and mirrors the image horizontally.
    func test_cameraRightIsPositiveXForZForwardCamera() throws {
        let d = try desc(posX: 0, posY: 2, posZ: -3, tgtX: 0, tgtY: 2, tgtZ: 4)
        let u = d.makeSceneUniforms()
        let right = SIMD3<Float>(u.cameraRight.x, u.cameraRight.y, u.cameraRight.z)
        XCTAssertGreaterThan(right.x, 0.99,
            "Right must be +X for camera looking along +Z. "
            + "Got \(right). cross(worldUp, fwd) gives +X; cross(fwd, worldUp) gives −X.")
    }

    /// cross(fwd, right) → +Y for a level camera.
    /// The wrong order, cross(right, fwd), gives −Y and flips the image vertically.
    func test_cameraUpIsPositiveYForLevelCamera() throws {
        let d = try desc(posX: 0, posY: 2, posZ: -3, tgtX: 0, tgtY: 2, tgtZ: 4)
        let u = d.makeSceneUniforms()
        let up = SIMD3<Float>(u.cameraUp.x, u.cameraUp.y, u.cameraUp.z)
        XCTAssertGreaterThan(up.y, 0.99,
            "Up must be +Y for a level camera. Got \(up). "
            + "cross(fwd, right) gives +Y; cross(right, fwd) gives −Y.")
    }

    /// The three camera basis vectors must be mutually orthogonal and unit length.
    /// Violation causes skewed or distorted geometry on screen.
    func test_cameraBasisOrthonormal() throws {
        let d = try desc()
        let u = d.makeSceneUniforms()
        let fwd   = SIMD3<Float>(u.cameraForward.x, u.cameraForward.y, u.cameraForward.z)
        let right = SIMD3<Float>(u.cameraRight.x,   u.cameraRight.y,   u.cameraRight.z)
        let up    = SIMD3<Float>(u.cameraUp.x,      u.cameraUp.y,      u.cameraUp.z)

        XCTAssertEqual(simd_dot(fwd, right), 0, accuracy: 0.001,
            "Forward · Right must be 0, got \(simd_dot(fwd, right))")
        XCTAssertEqual(simd_dot(fwd, up),    0, accuracy: 0.001,
            "Forward · Up must be 0, got \(simd_dot(fwd, up))")
        XCTAssertEqual(simd_dot(right, up),  0, accuracy: 0.001,
            "Right · Up must be 0, got \(simd_dot(right, up))")
        XCTAssertEqual(simd_length(fwd),   1, accuracy: 0.001, "Forward must be unit length")
        XCTAssertEqual(simd_length(right), 1, accuracy: 0.001, "Right must be unit length")
        XCTAssertEqual(simd_length(up),    1, accuracy: 0.001, "Up must be unit length")
    }

    // MARK: - Near / Far Plane Tests

    /// farPlane = 0 makes `t < farPlane` false at t = nearPlane, so every ray exits immediately
    /// and every pixel returns sky depth (1.0). The G-buffer is all-sky.
    func test_nearAndFarPlanesAreNonZero() throws {
        let d = try desc()
        let u = d.makeSceneUniforms()
        XCTAssertGreaterThan(u.sceneParamsA.z, 0,
            "nearPlane (sceneParamsA.z) must be > 0. Got \(u.sceneParamsA.z).")
        XCTAssertGreaterThan(u.sceneParamsA.w, 1,
            "farPlane (sceneParamsA.w) must be > 1. Got \(u.sceneParamsA.w). "
            + "Zero far plane causes all rays to exit immediately (all-sky frame).")
    }

    // MARK: - Light Tests

    /// Intensity must pass through the JSON → SceneUniforms pipeline unchanged.
    /// Mutation here (e.g. accidental normalisation) would dim or brighten the scene.
    func test_lightIntensityPassesThroughUnchanged() throws {
        let d = try desc(intensity: 3.0)
        let u = d.makeSceneUniforms()
        XCTAssertEqual(u.lightPositionAndIntensity.w, 3.0, accuracy: 0.001,
            "Light intensity must be 3.0. Got \(u.lightPositionAndIntensity.w).")
    }
}
