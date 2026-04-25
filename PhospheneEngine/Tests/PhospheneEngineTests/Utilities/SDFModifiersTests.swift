// SDFModifiersTests.swift — Tests for Utilities/Geometry/SDFModifiers.metal (V.2 Part A).

import Testing
import Metal
@testable import Presets

@Suite("SDF Modifiers")
struct SDFModifiersTests {

    @Test func test_modRepeat_periodicity() throws {
        // Point at (3, 0, 0) with period (2, 2, 2) should map to (1, 0, 0) → d = sd_sphere(1,0,0,r=0.5) = 0.5
        let src = """
        kernel void test_kernel(constant float3* inputs [[buffer(10)]],
                                device   float*  outputs [[buffer(11)]],
                                uint tid [[thread_position_in_grid]]) {
            float3 p = inputs[tid];
            float3 q = mod_repeat(p, float3(2.0));
            outputs[tid] = sd_sphere(q, 0.3);
        }
        """
        let r = try runNoiseKernel(kernelSource: src,
                                   inputs: [SIMD3(0, 0, 0),   // at cell origin
                                            SIMD3(2, 0, 0),   // one period away
                                            SIMD3(4, 0, 0)])  // two periods away
        // All three should produce identical distances (periodicity).
        #expect(abs(r[0] - r[1]) < 0.001)
        #expect(abs(r[0] - r[2]) < 0.001)
    }

    @Test func test_modMirrorXYZ_foldPositive() throws {
        let src = """
        kernel void test_kernel(constant float3* inputs [[buffer(10)]],
                                device   float*  outputs [[buffer(11)]],
                                uint tid [[thread_position_in_grid]]) {
            float3 p = inputs[tid];
            float3 q = mod_mirror_xyz(p);
            outputs[tid] = sd_sphere(q, 1.0);
        }
        """
        // Positive and negative should map to same distance (mirror symmetry).
        let r = try runNoiseKernel(kernelSource: src,
                                   inputs: [SIMD3(0.5, 0.5, 0.5),
                                            SIMD3(-0.5, -0.5, -0.5)])
        #expect(abs(r[0] - r[1]) < 0.001)
    }

    @Test func test_modTwist_doesNotTwistOnAxis() throws {
        // Points on the Y-axis (x=z=0) are unaffected by twist around Y.
        let src = """
        kernel void test_kernel(constant float3* inputs [[buffer(10)]],
                                device   float*  outputs [[buffer(11)]],
                                uint tid [[thread_position_in_grid]]) {
            float3 p = inputs[tid];
            float3 q = mod_twist(p, 2.0);
            outputs[tid] = length(q.xz) - length(p.xz);  // radial change
        }
        """
        let r = try runNoiseKernel(kernelSource: src,
                                   inputs: [SIMD3(0, 0, 0),
                                            SIMD3(0, 1, 0),
                                            SIMD3(0, 2, 0)])
        for v in r { #expect(abs(v) < 0.001, "radial distance unchanged on Y axis") }
    }

    @Test func test_modRound_inflateSurface() throws {
        let src = """
        kernel void test_kernel(constant float3* inputs [[buffer(10)]],
                                device   float*  outputs [[buffer(11)]],
                                uint tid [[thread_position_in_grid]]) {
            float3 p = inputs[tid];
            float base  = sd_box(p, float3(0.5));
            float rounded = mod_round(base, 0.2);
            outputs[tid] = rounded - base;  // difference should be -0.2
        }
        """
        let r = try runNoiseKernel(kernelSource: src, inputs: [SIMD3(2, 0, 0)])
        #expect(abs(r[0] + 0.2) < 0.001)
    }

    @Test func test_modOnion_thicknessShell() throws {
        // Onion of sd_sphere(p,1): |d - 1| shell. At radius 1.3 → |0.3| = 0.3.
        let src = """
        kernel void test_kernel(constant float3* inputs [[buffer(10)]],
                                device   float*  outputs [[buffer(11)]],
                                uint tid [[thread_position_in_grid]]) {
            float3 p = inputs[tid];
            float d = sd_sphere(p, 1.0);
            outputs[tid] = mod_onion(d, 0.1);
        }
        """
        // At p=(1.05,0,0): d=0.05 → |0.05|-0.1 = -0.05 (inside shell)
        let r = try runNoiseKernel(kernelSource: src,
                                   inputs: [SIMD3(1.05, 0, 0),  // inside shell
                                            SIMD3(2.0, 0, 0)])  // outside shell
        #expect(r[0] < 0)   // inside shell
        #expect(r[1] > 0)   // outside shell
    }

    @Test func test_preamble_containsModifierFunctions() {
        let p = PresetLoader.shaderPreamble
        let names = ["mod_repeat", "mod_repeat_y", "mod_repeat_finite",
                     "mod_mirror_y", "mod_mirror_xyz", "mod_mirror",
                     "mod_twist", "mod_bend", "mod_scale_uniform",
                     "mod_round", "mod_onion", "mod_extrude", "mod_revolve"]
        for name in names {
            #expect(p.contains(name), "\(name) missing from preamble")
        }
    }
}
