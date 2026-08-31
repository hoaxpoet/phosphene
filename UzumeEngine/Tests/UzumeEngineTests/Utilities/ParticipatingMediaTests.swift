// ParticipatingMediaTests.swift — Tests for Utilities/Volume/ParticipatingMedia.metal (V.2 Part B).

import Testing
import Metal
@testable import Presets

@Suite("Participating Media")
struct ParticipatingMediaTests {

    @Test func test_preamble_containsVolumeFunctions() {
        let p = PresetLoader.shaderPreamble
        #expect(p.contains("VolumeSample"), "VolumeSample struct missing from preamble")
        #expect(p.contains("vol_sample_zero"), "vol_sample_zero missing")
        #expect(p.contains("vol_density_fbm"), "vol_density_fbm missing")
        #expect(p.contains("vol_accumulate"), "vol_accumulate missing")
        #expect(p.contains("vol_composite"), "vol_composite missing")
    }

    @Test func test_volSampleZero_hasUnitTransmittance() throws {
        let src = """
        kernel void test_kernel(constant float3* inputs [[buffer(10)]],
                                device   float*  outputs [[buffer(11)]],
                                uint tid [[thread_position_in_grid]]) {
            VolumeSample s = vol_sample_zero();
            outputs[0] = s.transmittance;
            outputs[1] = s.color.x + s.color.y + s.color.z;
        }
        """
        let r = try runNoiseKernel(kernelSource: src, inputs: [SIMD3(0, 0, 0)], outputCount: 2)
        #expect(abs(r[0] - 1.0) < 0.001, "Initial transmittance should be 1.0, got \(r[0])")
        #expect(abs(r[1]) < 0.001, "Initial color should be zero, got \(r[1])")
    }

    @Test func test_volDensityHeightFog_decreasesWithHeight() throws {
        // Height fog should be denser at y=0 than at y=2.
        let src = """
        kernel void test_kernel(constant float3* inputs [[buffer(10)]],
                                device   float*  outputs [[buffer(11)]],
                                uint tid [[thread_position_in_grid]]) {
            outputs[0] = vol_density_height_fog(float3(0, 0, 0), 1.0, 1.0);
            outputs[1] = vol_density_height_fog(float3(0, 2, 0), 1.0, 1.0);
        }
        """
        let r = try runNoiseKernel(kernelSource: src, inputs: [SIMD3(0, 0, 0)], outputCount: 2)
        #expect(r[0] > r[1], "Height fog should be denser at y=0 than y=2: \(r[0]) vs \(r[1])")
        #expect(abs(r[0] - 1.0) < 0.001, "Density at y=0 should be scale=1.0, got \(r[0])")
    }

    @Test func test_volAccumulate_reducesTransmittance() throws {
        // Accumulating a non-zero density step must reduce transmittance.
        let src = """
        kernel void test_kernel(constant float3* inputs [[buffer(10)]],
                                device   float*  outputs [[buffer(11)]],
                                uint tid [[thread_position_in_grid]]) {
            VolumeSample s = vol_sample_zero();
            float3 pos = float3(0.5, 0.5, 0.5);
            float3 rd  = float3(0, 0, 1);
            float3 ld  = normalize(float3(1, 1, 0));
            float3 lc  = float3(1.0);
            s = vol_accumulate(s, pos, rd, 1.0, 0.1, ld, lc, 1.0);
            outputs[0] = s.transmittance;
        }
        """
        let r = try runNoiseKernel(kernelSource: src, inputs: [SIMD3(0, 0, 0)])
        #expect(r[0] < 1.0, "Transmittance should decrease after accumulation, got \(r[0])")
        #expect(r[0] > 0.0, "Transmittance should remain positive, got \(r[0])")
    }

    @Test func test_volDensitySphere_insideVsOutside() throws {
        // Sphere density: positive inside, 0 outside.
        let src = """
        kernel void test_kernel(constant float3* inputs [[buffer(10)]],
                                device   float*  outputs [[buffer(11)]],
                                uint tid [[thread_position_in_grid]]) {
            outputs[0] = vol_density_sphere(float3(0,0,0), float3(0,0,0), 1.0);   // centre
            outputs[1] = vol_density_sphere(float3(2,0,0), float3(0,0,0), 1.0);   // outside
        }
        """
        let r = try runNoiseKernel(kernelSource: src, inputs: [SIMD3(0, 0, 0)], outputCount: 2)
        #expect(r[0] > 0.9, "Density at sphere centre should be ~1.0, got \(r[0])")
        #expect(r[1] < 0.001, "Density outside sphere should be 0, got \(r[1])")
    }
}
