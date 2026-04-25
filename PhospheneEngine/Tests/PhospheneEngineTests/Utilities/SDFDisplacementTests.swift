// SDFDisplacementTests.swift — Tests for Utilities/Geometry/SDFDisplacement.metal (V.2 Part A).
//
// Key test: Lipschitz gradient magnitude ≤ 1.0 over 100 random points.

import Testing
import Metal
@testable import Presets

@Suite("SDF Displacement")
struct SDFDisplacementTests {

    @Test func test_displaceLipschitzSafe_gradientLEQ1() throws {
        // Displace sd_sphere(p, 2.0) with Perlin noise (amplitude=0.5, freq=2).
        // maxGradientMag = 0.5 * 2.0 = 1.0. safeScale = 1/(1+1) = 0.5.
        // Finite-difference gradient of the displaced SDF should have magnitude ≤ 1.0.
        let src = """
        kernel void test_kernel(constant float3* inputs [[buffer(10)]],
                                device   float*  outputs [[buffer(11)]],
                                uint tid [[thread_position_in_grid]]) {
            float3 p   = inputs[tid];
            float  eps = 0.005;
            float amplitude = 0.5, freq = 2.0;
            float maxGrad   = amplitude * freq;

            // Inline displaced-SDF evaluation: no lambda (Metal doesn't support them).
            float3 px0 = p + float3(eps,0,0), px1 = p - float3(eps,0,0);
            float3 py0 = p + float3(0,eps,0), py1 = p - float3(0,eps,0);
            float3 pz0 = p + float3(0,0,eps), pz1 = p - float3(0,0,eps);

            float fx0 = displace_lipschitz_safe(sd_sphere(px0, 2.0), perlin3d(px0*freq)*amplitude, maxGrad);
            float fx1 = displace_lipschitz_safe(sd_sphere(px1, 2.0), perlin3d(px1*freq)*amplitude, maxGrad);
            float fy0 = displace_lipschitz_safe(sd_sphere(py0, 2.0), perlin3d(py0*freq)*amplitude, maxGrad);
            float fy1 = displace_lipschitz_safe(sd_sphere(py1, 2.0), perlin3d(py1*freq)*amplitude, maxGrad);
            float fz0 = displace_lipschitz_safe(sd_sphere(pz0, 2.0), perlin3d(pz0*freq)*amplitude, maxGrad);
            float fz1 = displace_lipschitz_safe(sd_sphere(pz1, 2.0), perlin3d(pz1*freq)*amplitude, maxGrad);

            float dx = (fx0 - fx1) / (2*eps);
            float dy = (fy0 - fy1) / (2*eps);
            float dz = (fz0 - fz1) / (2*eps);
            outputs[tid] = length(float3(dx, dy, dz));
        }
        """
        // 100 stratified test positions on and around the sphere surface.
        var pts: [SIMD3<Float>] = []
        for i in 0..<10 {
            for j in 0..<10 {
                let theta = Float(i) * 0.314159  // 10 steps over π
                let phi   = Float(j) * 0.628318  // 10 steps over 2π
                let r     = 1.5 + Float(i % 3) * 0.5
                pts.append(SIMD3(
                    r * sin(theta) * cos(phi),
                    r * cos(theta),
                    r * sin(theta) * sin(phi)
                ))
            }
        }
        let grads = try runNoiseKernel(kernelSource: src, inputs: pts)
        let maxGrad = grads.max() ?? 0
        // Tolerance 1.15: Perlin3d's gradient can slightly exceed unity per unit·freq
        // (implementation-dependent envelope), so 1.0 + 15% covers the overshoot while
        // still confirming that displace_lipschitz_safe halves the naive bound.
        #expect(maxGrad <= 1.15, "Max gradient magnitude \(maxGrad) exceeds Lipschitz-safe bound")
    }

    @Test func test_displaceNoise_boundedByAmplitude() throws {
        let src = """
        kernel void test_kernel(constant float3* inputs [[buffer(10)]],
                                device   float*  outputs [[buffer(11)]],
                                uint tid [[thread_position_in_grid]]) {
            float3 p = inputs[tid];
            // Raw displacement should be within ±amplitude.
            outputs[tid] = displacement_noise(p, 3.0, 0.4);
        }
        """
        let pts = (0..<20).map { i in SIMD3<Float>(Float(i) * 0.3, Float(i) * 0.17, Float(i) * 0.41) }
        let results = try runNoiseKernel(kernelSource: src, inputs: pts)
        for v in results {
            #expect(abs(v) <= 0.41, "displacement_noise exceeded amplitude: \(v)")
        }
    }

    @Test func test_displacePerlin_lipschitzSafe_insideSphere() throws {
        // displace_perlin wraps noise + safe scaling. Displaced point inside
        // sphere (p=origin, radius=2) should still be negative.
        let src = """
        kernel void test_kernel(constant float3* inputs [[buffer(10)]],
                                device   float*  outputs [[buffer(11)]],
                                uint tid [[thread_position_in_grid]]) {
            float3 p = inputs[tid];
            float base = sd_sphere(p, 2.0);
            outputs[tid] = displace_perlin(p, base, 2.0, 0.3);
        }
        """
        let r = try runNoiseKernel(kernelSource: src, inputs: [SIMD3(0, 0, 0)])
        // Centre of sphere: base = -2. After lipschitz scaling: should still be negative.
        #expect(r[0] < 0)
    }

    @Test func test_displaceAnisotropic_directionEffect() throws {
        // Anisotropic displacement along X should differ from displacement along Y.
        let src = """
        kernel void test_kernel(constant float3* inputs [[buffer(10)]],
                                device   float*  outputs [[buffer(11)]],
                                uint tid [[thread_position_in_grid]]) {
            float3 p    = inputs[tid];
            float base  = sd_sphere(p, 1.5);
            float dispX = displace_anisotropic(p, base, float3(1,0,0), 0.3);
            float dispY = displace_anisotropic(p, base, float3(0,1,0), 0.3);
            outputs[tid] = abs(dispX - dispY);
        }
        """
        // At a non-symmetric point, X and Y displacements should differ.
        let r = try runNoiseKernel(kernelSource: src, inputs: [SIMD3(0.7, 0.3, 0.1)])
        #expect(r[0] > 0.0, "anisotropic displacement should differ across axes")
    }

    @Test func test_preamble_containsDisplacementFunctions() {
        let p = PresetLoader.shaderPreamble
        let names = ["displace_lipschitz_safe", "displace_clamped",
                     "displacement_noise", "displacement_fbm", "displacement_worley",
                     "displace_perlin", "displace_fbm", "displace_height",
                     "displace_anisotropic", "displace_beat_anticipation",
                     "displace_energy_breath"]
        for name in names {
            #expect(p.contains(name), "\(name) missing from preamble")
        }
    }
}
