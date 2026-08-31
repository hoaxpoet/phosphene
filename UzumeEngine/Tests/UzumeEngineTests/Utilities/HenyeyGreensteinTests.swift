// HenyeyGreensteinTests.swift — Tests for Utilities/Volume/HenyeyGreenstein.metal (V.2 Part B).

import Testing
import Metal
@testable import Presets

@Suite("Henyey-Greenstein Phase Function")
struct HenyeyGreensteinTests {

    @Test func test_preamble_containsHGFunctions() {
        let p = PresetLoader.shaderPreamble
        #expect(p.contains("hg_phase"), "hg_phase missing from preamble")
        #expect(p.contains("hg_schlick"), "hg_schlick missing from preamble")
        #expect(p.contains("hg_dual_lobe"), "hg_dual_lobe missing from preamble")
        #expect(p.contains("hg_transmittance"), "hg_transmittance missing from preamble")
    }

    @Test func test_hgPhase_isotropic_uniformOverHemisphere() throws {
        // g=0 → isotropic: hg_phase should return ~1/(4π) ≈ 0.0796 for all cosTheta.
        let src = """
        kernel void test_kernel(constant float3* inputs [[buffer(10)]],
                                device   float*  outputs [[buffer(11)]],
                                uint tid [[thread_position_in_grid]]) {
            float cosTheta = inputs[tid].x;   // cosTheta passed in x channel
            outputs[tid] = hg_phase(cosTheta, 0.0);
        }
        """
        let cosThetaValues: [Float] = [-1, -0.5, 0, 0.5, 1]
        let inputs = cosThetaValues.map { SIMD3<Float>($0, 0, 0) }
        let results = try runNoiseKernel(kernelSource: src, inputs: inputs)
        let expected: Float = 1.0 / (4.0 * 3.14159265)
        for (i, r) in results.enumerated() {
            #expect(abs(r - expected) < 0.001,
                    "hg_phase isotropic should be ~1/(4π) ≈ \(expected), got \(r) at index \(i)")
        }
    }

    @Test func test_hgPhase_forwardScatter_peaksAtOneCosTheta() throws {
        // g=0.8 → strong forward scatter: phase(cosTheta=1) >> phase(cosTheta=-1).
        let src = """
        kernel void test_kernel(constant float3* inputs [[buffer(10)]],
                                device   float*  outputs [[buffer(11)]],
                                uint tid [[thread_position_in_grid]]) {
            outputs[0] = hg_phase( 1.0, 0.8);   // forward  (cosTheta=1)
            outputs[1] = hg_phase(-1.0, 0.8);   // backward (cosTheta=-1)
        }
        """
        let r = try runNoiseKernel(kernelSource: src, inputs: [SIMD3(0, 0, 0)], outputCount: 2)
        #expect(r[0] > r[1] * 10.0,
                "Forward scatter (g=0.8) should make forward phase >> backward, got \(r[0]) vs \(r[1])")
    }

    @Test func test_hgTransmittance_decreasesWithDistance() throws {
        // Transmittance must decrease monotonically with increasing distance.
        let src = """
        kernel void test_kernel(constant float3* inputs [[buffer(10)]],
                                device   float*  outputs [[buffer(11)]],
                                uint tid [[thread_position_in_grid]]) {
            float t = inputs[tid].x;
            outputs[tid] = hg_transmittance(0.5, t, 1.0);
        }
        """
        let distances: [Float] = [0, 0.5, 1.0, 2.0, 5.0]
        let inputs  = distances.map { SIMD3<Float>($0, 0, 0) }
        let results = try runNoiseKernel(kernelSource: src, inputs: inputs)
        for i in 0..<results.count - 1 {
            #expect(results[i] >= results[i + 1],
                    "Transmittance should decrease with distance: \(results[i]) vs \(results[i+1])")
        }
        #expect(abs(results[0] - 1.0) < 0.001, "Transmittance at t=0 should be ~1.0")
    }

    @Test func test_hgSchlick_closeToHG() throws {
        // Schlick approximation should be within 10% of full HG at g=0.5.
        let src = """
        kernel void test_kernel(constant float3* inputs [[buffer(10)]],
                                device   float*  outputs [[buffer(11)]],
                                uint tid [[thread_position_in_grid]]) {
            float cosTheta = inputs[tid].x;
            outputs[tid * 2    ] = hg_phase(cosTheta,  0.5);
            outputs[tid * 2 + 1] = hg_schlick(cosTheta, 0.5);
        }
        """
        let cosThetaValues: [Float] = [-0.8, -0.3, 0.0, 0.3, 0.8]
        let inputs  = cosThetaValues.map { SIMD3<Float>($0, 0, 0) }
        let results = try runNoiseKernel(kernelSource: src, inputs: inputs, outputCount: 10)
        for i in 0..<cosThetaValues.count {
            let hg  = results[i * 2]
            let sch = results[i * 2 + 1]
            let relErr = abs(hg - sch) / max(hg, 1e-5)
            #expect(relErr < 0.25,
                    "Schlick should be within 25% of HG at cosTheta=\(cosThetaValues[i]): hg=\(hg) sch=\(sch)")
        }
    }
}
