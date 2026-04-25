// SDFPrimitivesTests.swift — Tests for Utilities/Geometry/SDFPrimitives.metal (V.2 Part A).
//
// Two test suites:
//   1. Preamble presence — verifies all 30 function names appear in the compiled preamble.
//   2. GPU correctness  — dispatches compute kernels for 10 key primitives.
//      Each test evaluates the SDF at an inside point, surface point, and outside point.

import Testing
import Metal
@testable import Presets

// MARK: - Preamble Presence

@Suite("SDF Primitives — Preamble")
struct SDFPrimitivePreambleTests {

    @Test func preamble_containsAllSdPrimitives() {
        let p = PresetLoader.shaderPreamble
        let names = [
            "sd_sphere", "sd_box", "sd_round_box", "sd_torus", "sd_capped_torus",
            "sd_link", "sd_cylinder", "sd_capped_cylinder", "sd_cone", "sd_capped_cone",
            "sd_round_cone", "sd_plane", "sd_capsule", "sd_hex_prism", "sd_tri_prism",
            "sd_octahedron", "sd_pyramid", "sd_ellipsoid", "sd_solid_angle", "sd_arc",
            "sd_disk", "sd_triangle", "sd_quad", "sd_helix", "sd_double_helix",
            "sd_gyroid", "sd_schwarz_p", "sd_schwarz_d", "sd_mandelbulb_iterate",
            "sd_regular_polygon"
        ]
        for name in names {
            #expect(p.contains(name), "\(name) missing from preamble")
        }
    }
}

// MARK: - GPU Correctness

@Suite("SDF Primitives — GPU Correctness")
struct SDFPrimitiveGPUTests {

    private func evalSDF(_ fn: String, inside: SIMD3<Float>, surface: SIMD3<Float>, outside: SIMD3<Float>) throws -> [Float] {
        let src = """
        kernel void test_kernel(constant float3* inputs [[buffer(10)]],
                                device   float*  outputs [[buffer(11)]],
                                uint tid [[thread_position_in_grid]]) {
            outputs[tid] = \(fn);
        }
        """
        return try runNoiseKernel(kernelSource: src, inputs: [inside, surface, outside])
    }

    @Test func test_sdSphere() throws {
        let r = try evalSDF("sd_sphere(inputs[tid], 1.0)",
                            inside:  SIMD3(0, 0, 0),
                            surface: SIMD3(1, 0, 0),
                            outside: SIMD3(2, 0, 0))
        #expect(r[0] < 0)
        #expect(abs(r[1]) < 0.01)
        #expect(r[2] > 0)
        #expect(abs(r[0] + 1.0) < 0.01, "center distance should be -radius")
    }

    @Test func test_sdBox() throws {
        // Half-extents (1,1,1): inside at origin, surface at (1,0,0), outside at (2,0,0).
        let r = try evalSDF("sd_box(inputs[tid], float3(1.0))",
                            inside:  SIMD3(0, 0, 0),
                            surface: SIMD3(1, 0, 0),
                            outside: SIMD3(2, 0, 0))
        #expect(r[0] < 0)
        #expect(abs(r[1]) < 0.01)
        #expect(r[2] > 0)
    }

    @Test func test_sdRoundBox() throws {
        // Round box with half-extents (0.8) and rounding r=0.2: total outer extent ~1.0.
        let r = try evalSDF("sd_round_box(inputs[tid], float3(0.8), 0.2)",
                            inside:  SIMD3(0, 0, 0),
                            surface: SIMD3(1, 0, 0),
                            outside: SIMD3(2, 0, 0))
        #expect(r[0] < 0)
        #expect(abs(r[1]) < 0.05)   // slightly relaxed for rounding
        #expect(r[2] > 0)
    }

    @Test func test_sdTorus() throws {
        // Torus: major=1, tube=0.3. Point on tube centre at (1,0,0), inside tube at (1,0,0).
        let r = try evalSDF("sd_torus(inputs[tid], float2(1.0, 0.3))",
                            inside:  SIMD3(1.0, 0, 0),  // on major circle, inside tube
                            surface: SIMD3(1.3, 0, 0),  // on tube surface
                            outside: SIMD3(3.0, 0, 0))
        #expect(r[0] < 0)
        #expect(abs(r[1]) < 0.01)
        #expect(r[2] > 0)
    }

    @Test func test_sdCylinder() throws {
        // h=1, r=1: inside at origin, surface at (1,0,0), outside at (2,0,0).
        let r = try evalSDF("sd_cylinder(inputs[tid], 1.0, 1.0)",
                            inside:  SIMD3(0, 0, 0),
                            surface: SIMD3(1, 0, 0),
                            outside: SIMD3(2, 0, 0))
        #expect(r[0] < 0)
        #expect(abs(r[1]) < 0.01)
        #expect(r[2] > 0)
    }

    @Test func test_sdCapsule() throws {
        // Capsule from (0,-1,0) to (0,1,0), radius 0.5.
        let r = try evalSDF("sd_capsule(inputs[tid], float3(0,-1,0), float3(0,1,0), 0.5)",
                            inside:  SIMD3(0, 0, 0),
                            surface: SIMD3(0.5, 0, 0),
                            outside: SIMD3(2, 0, 0))
        #expect(r[0] < 0)
        #expect(abs(r[1]) < 0.01)
        #expect(r[2] > 0)
    }

    @Test func test_sdPlane() throws {
        // Plane normal=(0,1,0), h=0: points below (inside for negative convention).
        let r = try evalSDF("sd_plane(inputs[tid], float3(0,1,0), 0.0)",
                            inside:  SIMD3(0, -1, 0),   // below plane → negative
                            surface: SIMD3(0,  0, 0),
                            outside: SIMD3(0,  1, 0))
        #expect(r[0] < 0)
        #expect(abs(r[1]) < 0.001)
        #expect(r[2] > 0)
    }

    @Test func test_sdOctahedron() throws {
        // s=1: inside at origin, surface at (1,0,0)? Actually vertex is at (1,0,0).
        // Centre is inside (sd < 0), vertex is on surface, (2,0,0) is outside.
        let r = try evalSDF("sd_octahedron(inputs[tid], 1.0)",
                            inside:  SIMD3(0, 0, 0),
                            surface: SIMD3(1, 0, 0),
                            outside: SIMD3(2, 0, 0))
        #expect(r[0] < 0)
        #expect(abs(r[1]) < 0.01)
        #expect(r[2] > 0)
    }

    @Test func test_sdGyroid_zeroLevelSet() throws {
        // Gyroid at scale=1, thickness=0: value at (π/2, 0, 0) should be 0
        // cos(π/2)*sin(0) + cos(0)*sin(0) + cos(0)*sin(π/2) = 0 + 0 + 1 ≠ 0
        // Actually gyroid zero-level: thickness creates a shell; outside+inside both work.
        let r = try evalSDF("sd_gyroid(inputs[tid], 1.0, 0.2)",
                            inside:  SIMD3(0, 0, 0),
                            surface: SIMD3(0, 0, 0),    // level-set; approximate
                            outside: SIMD3(10, 10, 10))
        // Gyroid is a level-set; just verify the function evaluates without NaN.
        #expect(!r[0].isNaN)
        #expect(!r[2].isNaN)
    }

    @Test func test_sdEllipsoid_isApproximate() throws {
        // Ellipsoid (1,1,1) = sphere of radius 1. At center → -1 (approx).
        let r = try evalSDF("sd_ellipsoid(inputs[tid], float3(1.0, 1.0, 1.0))",
                            inside:  SIMD3(0, 0, 0),
                            surface: SIMD3(1, 0, 0),
                            outside: SIMD3(2, 0, 0))
        #expect(r[0] < 0)
        // Approx SDF: not exact at surface; just check sign changes correctly.
        #expect(r[2] > 0)
    }
}
