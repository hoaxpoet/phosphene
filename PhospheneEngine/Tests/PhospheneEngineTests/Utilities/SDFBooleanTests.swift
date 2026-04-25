// SDFBooleanTests.swift — Tests for Utilities/Geometry/SDFBoolean.metal (V.2 Part A).

import Testing
import Metal
@testable import Presets

@Suite("SDF Boolean Operations")
struct SDFBooleanTests {

    private func eval2(_ expr: String, a: Float, b: Float) throws -> Float {
        let src = """
        kernel void test_kernel(constant float3* inputs [[buffer(10)]],
                                device   float*  outputs [[buffer(11)]],
                                uint tid [[thread_position_in_grid]]) {
            float a = inputs[0].x;
            float b = inputs[0].y;
            outputs[0] = \(expr);
        }
        """
        let r = try runNoiseKernel(kernelSource: src, inputs: [SIMD3(a, b, 0)])
        return r[0]
    }

    @Test func test_opUnion_equivToMin() throws {
        let d = try eval2("op_union(a, b)", a: 1.5, b: 0.7)
        #expect(abs(d - 0.7) < 1e-4)
    }

    @Test func test_opSubtract_orderingMatters() throws {
        // subtract(a=1, b=0.5): max(1, -0.5) = 1
        let d1 = try eval2("op_subtract(a, b)", a: 1.0, b: 0.5)
        // subtract(a=0.5, b=1): max(0.5, -1) = 0.5
        let d2 = try eval2("op_subtract(a, b)", a: 0.5, b: 1.0)
        #expect(abs(d1 - 1.0) < 1e-4)
        #expect(abs(d2 - 0.5) < 1e-4)
        // Verify ordering matters
        #expect(abs(d1 - d2) > 0.01)
    }

    @Test func test_opSmoothUnion_largeK_smoothBlend() throws {
        // At equal distances with large k, result should be less than either input.
        let dHard = try eval2("op_union(a, b)", a: 1.0, b: 1.0)
        let dSmooth = try eval2("op_smooth_union(a, b, 1.0)", a: 1.0, b: 1.0)
        #expect(abs(dHard - 1.0) < 1e-4)
        #expect(dSmooth < dHard)  // smooth blend pulls result inward
    }

    @Test func test_opSmoothUnion_smallK_approachesHard() throws {
        // Very small k → smooth union approaches min(a, b).
        let d = try eval2("op_smooth_union(a, b, 0.001)", a: 2.0, b: 0.5)
        #expect(abs(d - 0.5) < 0.01)
    }

    @Test func test_opChamferUnion_lessThanHardUnion() throws {
        let dHard = try eval2("op_union(a, b)", a: 1.0, b: 1.2)
        let dChamfer = try eval2("op_chamfer_union(a, b, 0.3)", a: 1.0, b: 1.2)
        // Chamfer union should be ≤ hard union near the crease.
        #expect(dChamfer <= dHard + 1e-4)
    }

    @Test func test_opBlend4_symmetricInputs() throws {
        // All four equal inputs → result equals the common value minus blend.
        let src = """
        kernel void test_kernel(constant float3* inputs [[buffer(10)]],
                                device   float*  outputs [[buffer(11)]],
                                uint tid [[thread_position_in_grid]]) {
            outputs[0] = op_blend_4(2.0, 2.0, 2.0, 2.0, 0.5);
        }
        """
        let r = try runNoiseKernel(kernelSource: src, inputs: [SIMD3(0, 0, 0)])
        // log-sum-exp(0,0,0,0) = log(4) ≈ 1.386 → result = 2.0 - 0.5*log(4) ≈ 1.307
        let expected = Float(2.0 - 0.5 * log(4.0))
        #expect(abs(r[0] - expected) < 0.01)
    }

    @Test func test_preamble_containsBooleanFunctions() {
        let p = PresetLoader.shaderPreamble
        let names = ["op_union", "op_subtract", "op_intersect",
                     "op_smooth_union", "op_smooth_subtract", "op_smooth_intersect",
                     "op_chamfer_union", "op_blend_4", "op_blend_8", "op_blend"]
        for name in names {
            #expect(p.contains(name), "\(name) missing from preamble")
        }
    }
}
