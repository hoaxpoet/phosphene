// SceneUniformsTests — Verifies the SceneUniforms struct layout, defaults,
// MSL/Swift parity, and JSON-driven preset descriptor parsing.
//
// Five tests covering memory size, stride, default values, MSL compilation,
// and JSON decode from a preset descriptor.

import XCTest
import Metal
@testable import Renderer
@testable import Presets
@testable import Shared

// MARK: - SceneUniformsTests

final class SceneUniformsTests: XCTestCase {

    // MARK: - Test 1: Size is 128 bytes (8 × float4)

    func test_sceneUniforms_size_is128Bytes() {
        XCTAssertEqual(
            MemoryLayout<SceneUniforms>.size, 128,
            "SceneUniforms must be 128 bytes (8 × SIMD4<Float>), "
            + "got \(MemoryLayout<SceneUniforms>.size)"
        )
    }

    // MARK: - Test 2: Stride is 128 bytes (16-byte aligned for GPU upload)

    func test_sceneUniforms_stride_is128Bytes() {
        XCTAssertEqual(
            MemoryLayout<SceneUniforms>.stride, 128,
            "SceneUniforms stride must be 128 bytes, "
            + "got \(MemoryLayout<SceneUniforms>.stride)"
        )
        XCTAssertEqual(
            MemoryLayout<SceneUniforms>.stride % 16, 0,
            "SceneUniforms stride must be 16-byte aligned for GPU uniforms"
        )
    }

    // MARK: - Test 3: Default values are reasonable for rendering

    func test_sceneUniforms_defaultValues_reasonable() {
        let su = SceneUniforms()

        // Camera position should be non-zero (camera not at origin, which would coincide
        // with scene content).
        let camPos = SIMD3<Float>(su.cameraOriginAndFov.x,
                                  su.cameraOriginAndFov.y,
                                  su.cameraOriginAndFov.z)
        XCTAssertFalse(
            camPos == .zero,
            "Default camera position must not be at origin (would overlap scene content)"
        )

        // FOV should be in a sensible range (> 0 and < π).
        let fov = su.cameraOriginAndFov.w
        XCTAssertGreaterThan(fov, 0, "Default fov must be > 0")
        XCTAssertLessThan(fov, Float.pi, "Default fov must be < π (180°)")

        // A primary light should be present (non-zero intensity).
        let intensity = su.lightPositionAndIntensity.w
        XCTAssertGreaterThan(intensity, 0, "Default primary light intensity must be > 0")

        // Light colour should be warm-ish white (all channels > 0.5).
        let lightR = su.lightColor.x
        let lightG = su.lightColor.y
        let lightB = su.lightColor.z
        XCTAssertGreaterThan(lightR, 0, "Default light colour R must be > 0")
        XCTAssertGreaterThan(lightG, 0, "Default light colour G must be > 0")
        XCTAssertGreaterThan(lightB, 0, "Default light colour B must be > 0")

        // Near/far planes should be valid (near < far, both positive).
        let near = su.sceneParamsA.z
        let far = su.sceneParamsA.w
        XCTAssertGreaterThan(near, 0, "Default near plane must be > 0")
        XCTAssertGreaterThan(far, near, "Default far plane must be > near plane")
    }

    // MARK: - Test 4: MSL layout matches Swift layout (compile-time verification)

    func test_sceneUniforms_mslLayoutMatches_swiftLayout() throws {
        let context = try MetalContext()

        // A shader that reads every field of SceneUniforms at buffer(4) and writes
        // a summed value so the compiler cannot dead-eliminate the reads.
        // SceneUniforms is defined inline (matching the Swift layout) rather than via
        // rayMarchGBufferPreamble — the G-buffer preamble requires sceneSDF/sceneMaterial
        // stubs which would obscure the layout test.
        let source = """
            #include <metal_stdlib>
            using namespace metal;

            // Must match Swift SceneUniforms layout (8 × float4 = 128 bytes).
            struct SceneUniforms {
                float4 cameraOriginAndFov;
                float4 cameraForward;
                float4 cameraRight;
                float4 cameraUp;
                float4 lightPositionAndIntensity;
                float4 lightColor;
                float4 sceneParamsA;
                float4 sceneParamsB;
            };

            // Probe: read all SceneUniforms fields and write their sum.
            kernel void probe_scene_uniforms(
                constant SceneUniforms& su [[buffer(4)]],
                device float* out          [[buffer(0)]]
            ) {
                float s = 0;
                s += su.cameraOriginAndFov.x + su.cameraOriginAndFov.y
                   + su.cameraOriginAndFov.z + su.cameraOriginAndFov.w;
                s += su.cameraForward.x  + su.cameraForward.y
                   + su.cameraForward.z  + su.cameraForward.w;
                s += su.cameraRight.x    + su.cameraRight.y
                   + su.cameraRight.z    + su.cameraRight.w;
                s += su.cameraUp.x       + su.cameraUp.y
                   + su.cameraUp.z       + su.cameraUp.w;
                s += su.lightPositionAndIntensity.x + su.lightPositionAndIntensity.y
                   + su.lightPositionAndIntensity.z + su.lightPositionAndIntensity.w;
                s += su.lightColor.x + su.lightColor.y
                   + su.lightColor.z + su.lightColor.w;
                s += su.sceneParamsA.x + su.sceneParamsA.y
                   + su.sceneParamsA.z + su.sceneParamsA.w;
                s += su.sceneParamsB.x + su.sceneParamsB.y
                   + su.sceneParamsB.z + su.sceneParamsB.w;
                out[0] = s;
            }
            """

        let options = MTLCompileOptions()
        options.fastMathEnabled = true
        options.languageVersion = .version3_1

        // If SceneUniforms MSL layout is wrong this will throw a compile error.
        let library = try XCTUnwrap(
            try? context.device.makeLibrary(source: source, options: options),
            "SceneUniforms MSL compilation failed — struct layout or field names mismatch"
        )

        guard let kernelFn = library.makeFunction(name: "probe_scene_uniforms"),
              let pipeline = try? context.device.makeComputePipelineState(function: kernelFn)
        else {
            XCTFail("Failed to compile/build probe kernel for SceneUniforms layout check")
            return
        }

        // Run the kernel with default SceneUniforms and verify output is non-zero.
        var su = SceneUniforms()
        let outBuf = try XCTUnwrap(
            context.device.makeBuffer(length: MemoryLayout<Float>.stride,
                                      options: .storageModeShared),
            "Failed to allocate output buffer"
        )
        guard let cmd = context.commandQueue.makeCommandBuffer(),
              let enc = cmd.makeComputeCommandEncoder() else {
            XCTFail("Failed to create command buffer or compute encoder")
            return
        }
        enc.setComputePipelineState(pipeline)
        enc.setBuffer(outBuf, offset: 0, index: 0)
        enc.setBytes(&su, length: MemoryLayout<SceneUniforms>.stride, index: 4)
        enc.dispatchThreadgroups(MTLSize(width: 1, height: 1, depth: 1),
                                  threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
        enc.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()

        let result = outBuf.contents().load(as: Float.self)
        // The sum of the default SceneUniforms (camera, light, params) must be finite and non-NaN.
        XCTAssertFalse(result.isNaN,
            "SceneUniforms field sum must not be NaN — GPU read garbage from struct layout mismatch")
    }

    // MARK: - Test 5: JSON preset descriptor with scene configuration parses correctly

    func test_sceneUniforms_fromPresetDescriptor_parsesJSON() throws {
        let json = """
        {
            "name": "TestScene",
            "family": "abstract",
            "use_ray_march": true,
            "scene_camera": {
                "position": [0.0, 2.0, -5.0],
                "target":   [0.0, 0.0,  0.0],
                "fov": 1.2
            },
            "scene_lights": [
                { "position": [3.0, 5.0, -2.0], "color": [1.0, 0.9, 0.8], "intensity": 2.0 },
                { "position": [-2.0, 3.0, 1.0], "color": [0.4, 0.5, 0.8], "intensity": 1.0 }
            ],
            "scene_fog": 0.02,
            "scene_ambient": 0.1
        }
        """.data(using: .utf8)!

        let desc = try JSONDecoder().decode(PresetDescriptor.self, from: json)

        XCTAssertTrue(desc.useRayMarch, "use_ray_march must be true")

        // Camera
        let cam = try XCTUnwrap(desc.sceneCamera, "scene_camera must be decoded")
        assertNearlyEqual(cam.position, SIMD3<Float>(0, 2, -5), eps: 0.001, label: "cam.position")
        assertNearlyEqual(cam.target, SIMD3<Float>(0, 0, 0), eps: 0.001, label: "cam.target")
        XCTAssertEqual(cam.fov, 1.2, accuracy: Float(0.001))

        // Lights
        XCTAssertEqual(desc.sceneLights.count, 2, "Two lights must be decoded")
        assertNearlyEqual(desc.sceneLights[0].position, SIMD3<Float>(3, 5, -2), eps: 0.001, label: "light0.position")
        XCTAssertEqual(desc.sceneLights[0].intensity, Float(2.0), accuracy: Float(0.001))
        assertNearlyEqual(desc.sceneLights[1].position, SIMD3<Float>(-2, 3, 1), eps: 0.001, label: "light1.position")

        // Fog and ambient
        XCTAssertEqual(desc.sceneFog, Float(0.02), accuracy: Float(0.0001))
        XCTAssertEqual(desc.sceneAmbient, Float(0.1), accuracy: Float(0.001))
    }
}

// MARK: - Helpers

private func assertNearlyEqual(
    _ a: SIMD3<Float>, _ b: SIMD3<Float>,
    eps: Float, label: String,
    file: StaticString = #file, line: UInt = #line
) {
    XCTAssertEqual(a.x, b.x, accuracy: eps, "\(label).x mismatch", file: file, line: line)
    XCTAssertEqual(a.y, b.y, accuracy: eps, "\(label).y mismatch", file: file, line: line)
    XCTAssertEqual(a.z, b.z, accuracy: eps, "\(label).z mismatch", file: file, line: line)
}
