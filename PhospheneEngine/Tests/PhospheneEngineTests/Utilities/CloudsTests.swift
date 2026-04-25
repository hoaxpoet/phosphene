// CloudsTests.swift — Tests for Utilities/Volume/Clouds.metal (V.2 Part B).

import Testing
import Metal
@testable import Presets

@Suite("Clouds")
struct CloudsTests {

    @Test func test_preamble_containsCloudFunctions() {
        let p = PresetLoader.shaderPreamble
        #expect(p.contains("cloud_density_cumulus"), "cloud_density_cumulus missing")
        #expect(p.contains("cloud_density_stratus"), "cloud_density_stratus missing")
        #expect(p.contains("cloud_density_cirrus"),  "cloud_density_cirrus missing")
        #expect(p.contains("cloud_march"),            "cloud_march missing")
    }

    @Test func test_cumulusDensity_zeroOutsideLayer() throws {
        // Cumulus layer is between y=0.5 and y=4.0; density at y=-1 and y=10 should be 0.
        let src = """
        kernel void test_kernel(constant float3* inputs [[buffer(10)]],
                                device   float*  outputs [[buffer(11)]],
                                uint tid [[thread_position_in_grid]]) {
            outputs[0] = cloud_density_cumulus(float3(0, -1.0, 0), 0.0, 0.0);
            outputs[1] = cloud_density_cumulus(float3(0, 10.0, 0), 0.0, 0.0);
        }
        """
        let r = try runNoiseKernel(kernelSource: src, inputs: [SIMD3(0, 0, 0)], outputCount: 2)
        #expect(r[0] < 0.001, "Cumulus density below layer should be 0, got \(r[0])")
        #expect(r[1] < 0.001, "Cumulus density above layer should be 0, got \(r[1])")
    }

    @Test func test_cumulusDensity_nonNegative() throws {
        // Density must never be negative over a grid of positions within the cloud layer.
        let src = """
        kernel void test_kernel(constant float3* inputs [[buffer(10)]],
                                device   float*  outputs [[buffer(11)]],
                                uint tid [[thread_position_in_grid]]) {
            float3 p = inputs[tid];
            outputs[tid] = cloud_density_cumulus(p, 0.0, 0.0);
        }
        """
        var pts: [SIMD3<Float>] = []
        for i in 0..<8 {
            for j in 0..<8 {
                pts.append(SIMD3(Float(i) * 0.5, 1.0 + Float(j) * 0.4, 0.0))
            }
        }
        let results = try runNoiseKernel(kernelSource: src, inputs: pts)
        for (i, d) in results.enumerated() {
            #expect(d >= -0.001, "Cumulus density should be non-negative, got \(d) at index \(i)")
        }
    }

    @Test func test_cloudMarch_transmittanceIn01() throws {
        // A short cloud march should return transmittance in [0, 1].
        let src = """
        kernel void test_kernel(constant float3* inputs [[buffer(10)]],
                                device   float*  outputs [[buffer(11)]],
                                uint tid [[thread_position_in_grid]]) {
            float3 ro = float3(0, 5, -10);
            float3 rd = normalize(float3(0, -1, 1));
            float3 ld = normalize(float3(1, 1, 0));
            float3 lc = float3(1.0, 0.95, 0.85);
            VolumeSample s = cloud_march(ro, rd, 0.0, 20.0, 16, 0.0, 0.3, ld, lc);
            outputs[0] = s.transmittance;
            outputs[1] = s.color.x;
        }
        """
        let r = try runNoiseKernel(kernelSource: src, inputs: [SIMD3(0, 0, 0)], outputCount: 2)
        #expect(r[0] >= 0.0 && r[0] <= 1.0,
                "Cloud march transmittance should be in [0,1], got \(r[0])")
        #expect(r[1] >= 0.0, "Cloud march color.x should be non-negative, got \(r[1])")
    }
}
