// FlowMapsTests.swift — Tests for Utilities/Texture/FlowMaps.metal (V.2 Part C).

import Testing
import Metal
@testable import Presets

@Suite("Flow Maps")
struct FlowMapsTests {

    @Test func test_preamble_containsFlowFunctions() {
        let p = PresetLoader.shaderPreamble
        #expect(p.contains("flow_sample_offset"),   "flow_sample_offset missing")
        #expect(p.contains("flow_blend_weight"),    "flow_blend_weight missing")
        #expect(p.contains("flow_curl_advect"),     "flow_curl_advect missing")
        #expect(p.contains("flow_noise_velocity"),  "flow_noise_velocity missing")
        #expect(p.contains("flow_audio"),           "flow_audio missing")
    }

    @Test func test_flowSampleOffset_movesUV() throws {
        // With non-zero velocity and phase, the offset UV should differ from the original.
        let src = """
        kernel void test_kernel(constant float3* inputs [[buffer(10)]],
                                device   float*  outputs [[buffer(11)]],
                                uint tid [[thread_position_in_grid]]) {
            float2 uv  = float2(0.5, 0.5);
            float2 vel = float2(1.0, 0.0);
            float2 off = flow_sample_offset(uv, vel, 0.7, 0.5);
            outputs[0] = off.x;
            outputs[1] = off.y;
        }
        """
        let r = try runNoiseKernel(kernelSource: src, inputs: [SIMD3(0, 0, 0)], outputCount: 2)
        #expect(abs(r[0] - 0.5) > 0.05, "flow_sample_offset should displace UV.x, got \(r[0])")
        #expect(abs(r[1] - 0.5) < 0.01, "flow_sample_offset should not displace UV.y (vel.y=0), got \(r[1])")
    }

    @Test func test_flowBlendWeight_sumToOne_atBothPhases() throws {
        // Weight at phase p + (1 - weight at phase p) should always equal 1.
        let src = """
        kernel void test_kernel(constant float3* inputs [[buffer(10)]],
                                device   float*  outputs [[buffer(11)]],
                                uint tid [[thread_position_in_grid]]) {
            float phase = inputs[tid].x;
            float w = flow_blend_weight(phase);
            outputs[tid] = w + (1.0 - w);   // should always be 1.0
        }
        """
        let phases: [Float] = [0, 0.1, 0.3, 0.5, 0.7, 0.9, 1.0]
        let inputs = phases.map { SIMD3<Float>($0, 0, 0) }
        let results = try runNoiseKernel(kernelSource: src, inputs: inputs)
        for (i, r) in results.enumerated() {
            #expect(abs(r - 1.0) < 0.001,
                    "flow_blend_weight + (1-weight) should equal 1 at phase \(phases[i]), got \(r)")
        }
    }

    @Test func test_flowCurlAdvect_changesUV() throws {
        // Curl advection should produce a different UV than the input.
        let src = """
        kernel void test_kernel(constant float3* inputs [[buffer(10)]],
                                device   float*  outputs [[buffer(11)]],
                                uint tid [[thread_position_in_grid]]) {
            float2 uv = float2(0.4, 0.6);
            float2 out = flow_curl_advect(uv, 2.0, 1.0, 1.0, 0.3);
            outputs[0] = distance(uv, out);
        }
        """
        let r = try runNoiseKernel(kernelSource: src, inputs: [SIMD3(0, 0, 0)])
        #expect(r[0] > 0.001, "Curl advection should move UV, got delta=\(r[0])")
    }

    @Test func test_flowLayered_inRange() throws {
        // flow_layered should produce values in [0,1].
        let src = """
        kernel void test_kernel(constant float3* inputs [[buffer(10)]],
                                device   float*  outputs [[buffer(11)]],
                                uint tid [[thread_position_in_grid]]) {
            float2 uv = inputs[tid].xy;
            outputs[tid] = flow_layered(uv, 2.0, 1.0);
        }
        """
        var pts: [SIMD3<Float>] = []
        for i in 0..<16 { for j in 0..<16 {
            pts.append(SIMD3(Float(i) / 16.0, Float(j) / 16.0, 0))
        }}
        let results = try runNoiseKernel(kernelSource: src, inputs: pts)
        for (i, v) in results.enumerated() {
            #expect(v >= -0.05 && v <= 1.05,
                    "flow_layered out of range at index \(i): \(v)")
        }
    }
}
