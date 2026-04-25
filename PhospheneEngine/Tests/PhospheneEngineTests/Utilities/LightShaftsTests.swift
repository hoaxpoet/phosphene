// LightShaftsTests.swift — Tests for Utilities/Volume/LightShafts.metal (V.2 Part B).

import Testing
import Metal
@testable import Presets

@Suite("Light Shafts")
struct LightShaftsTests {

    @Test func test_preamble_containsLightShaftFunctions() {
        let p = PresetLoader.shaderPreamble
        #expect(p.contains("ls_radial_step_uv"),      "ls_radial_step_uv missing")
        #expect(p.contains("ls_shadow_march"),         "ls_shadow_march missing")
        #expect(p.contains("ls_sun_disk"),             "ls_sun_disk missing")
        #expect(p.contains("ls_intensity_audio"),      "ls_intensity_audio missing")
    }

    @Test func test_lsRadialStepUV_interpolatesCorrectly() throws {
        // Step 0 should return uv itself; step N should be near sunUV.
        let src = """
        kernel void test_kernel(constant float3* inputs [[buffer(10)]],
                                device   float*  outputs [[buffer(11)]],
                                uint tid [[thread_position_in_grid]]) {
            float2 uv    = float2(0.2, 0.3);
            float2 sunUV = float2(0.8, 0.7);
            float2 step0 = ls_radial_step_uv(uv, sunUV, 0, 32);
            float2 stepN = ls_radial_step_uv(uv, sunUV, 32, 32);
            outputs[0] = step0.x;
            outputs[1] = step0.y;
            outputs[2] = stepN.x;
            outputs[3] = stepN.y;
        }
        """
        let r = try runNoiseKernel(kernelSource: src, inputs: [SIMD3(0, 0, 0)], outputCount: 4)
        #expect(abs(r[0] - 0.2) < 0.01, "Step 0 UV.x should be ~uv.x=0.2, got \(r[0])")
        #expect(abs(r[1] - 0.3) < 0.01, "Step 0 UV.y should be ~uv.y=0.3, got \(r[1])")
        #expect(abs(r[2] - 0.8) < 0.02, "Step N UV.x should be ~sunUV.x=0.8, got \(r[2])")
        #expect(abs(r[3] - 0.7) < 0.02, "Step N UV.y should be ~sunUV.y=0.7, got \(r[3])")
    }

    @Test func test_lsShadowMarch_clearPath_returnsHigh() throws {
        // Marching through empty space (no fog density along shadow ray) should give high transmittance.
        let src = """
        kernel void test_kernel(constant float3* inputs [[buffer(10)]],
                                device   float*  outputs [[buffer(11)]],
                                uint tid [[thread_position_in_grid]]) {
            // Shadow from below y=-5 upward — outside cloud layer, density ≈ 0.
            float3 p = float3(0, -5, 0);
            float3 ld = float3(0, 1, 0);
            outputs[0] = ls_shadow_march(p, ld, 10.0, 8, 1.0);
        }
        """
        let r = try runNoiseKernel(kernelSource: src, inputs: [SIMD3(0, 0, 0)])
        #expect(r[0] > 0.5, "Shadow march through clear space should give high transmittance, got \(r[0])")
    }

    @Test func test_lsSunDisk_brighterOnAxis() throws {
        // Sun disk should be brightest when rd == sunDir (cosAngle = 1).
        let src = """
        kernel void test_kernel(constant float3* inputs [[buffer(10)]],
                                device   float*  outputs [[buffer(11)]],
                                uint tid [[thread_position_in_grid]]) {
            float3 sunDir = normalize(float3(1, 1, 0));
            float3 sunColor = float3(1.0, 0.95, 0.8);
            float3 onAxis   = ls_sun_disk(sunDir, sunDir, sunColor);
            float3 offAxis  = ls_sun_disk(float3(0, 0, 1), sunDir, sunColor);
            outputs[0] = onAxis.x;
            outputs[1] = offAxis.x;
        }
        """
        let r = try runNoiseKernel(kernelSource: src, inputs: [SIMD3(0, 0, 0)], outputCount: 2)
        #expect(r[0] > r[1], "Sun disk on-axis should be brighter than off-axis: \(r[0]) vs \(r[1])")
        #expect(r[0] > 0.9, "Sun disk exactly on-axis should be near peak, got \(r[0])")
    }
}
