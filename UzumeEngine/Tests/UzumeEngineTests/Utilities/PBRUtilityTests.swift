// PBRUtilityTests.swift — Property tests for the PBR utility tree.
//
// Each @Suite exercises one Metal utility file through the Metal compute-pipeline
// harness. Kernels compile `PresetLoader.shaderPreamble + kernelSource` so the
// same compiled code the renderer uses is under test.
//
// Buffer layout per harness convention: inputs at buffer(10), outputs at buffer(11).
// inputs[tid].x carries the primary scalar input for most tests; .y/.z carry
// secondary parameters when needed.

import Testing
import Foundation
@testable import Presets

// MARK: - Fresnel

@Suite("FresnelProperties") struct FresnelProperties {

    // fresnel_schlick(VdotH=1, F0) == F0   (normal incidence, no extra reflection)
    @Test func schlickNormalIncidenceReturnsF0() throws {
        let kernel = """
        kernel void test_kernel(
            constant float3* inputs  [[buffer(10)]],
            device   float*  outputs [[buffer(11)]],
            uint tid [[thread_position_in_grid]]
        ) {
            // inputs[tid].x = F0 scalar (r=g=b for simplicity)
            float3 F0 = float3(inputs[tid].x);
            float3 r  = fresnel_schlick(1.0, F0);
            outputs[tid] = r.r;
        }
        """
        let f0Values: [Float] = [0.0, 0.04, 0.15, 0.5, 1.0]
        let inputs = f0Values.map { SIMD3<Float>($0, 0, 0) }
        let results = try runNoiseKernel(kernelSource: kernel, inputs: inputs)
        for (f0, got) in zip(f0Values, results) {
            #expect(abs(got - f0) < 1e-4, "fresnel_schlick(1.0, F0=\(f0)) should equal F0, got \(got)")
        }
    }

    // fresnel_schlick(VdotH=0, F0) == 1.0  (grazing angle, full reflection)
    @Test func schlickGrazingReturnsOne() throws {
        let kernel = """
        kernel void test_kernel(
            constant float3* inputs  [[buffer(10)]],
            device   float*  outputs [[buffer(11)]],
            uint tid [[thread_position_in_grid]]
        ) {
            float3 F0 = float3(inputs[tid].x);
            float3 r  = fresnel_schlick(0.0, F0);
            outputs[tid] = r.r;
        }
        """
        let f0Values: [Float] = [0.0, 0.04, 0.5, 0.9]
        let inputs = f0Values.map { SIMD3<Float>($0, 0, 0) }
        let results = try runNoiseKernel(kernelSource: kernel, inputs: inputs)
        for got in results {
            #expect(abs(got - 1.0) < 1e-4, "fresnel_schlick(0.0, F0) should be 1.0, got \(got)")
        }
    }

    // fresnel_schlick output is monotonically decreasing as VdotH increases from 0→1
    @Test func schlickMonotonic() throws {
        let kernel = """
        kernel void test_kernel(
            constant float3* inputs  [[buffer(10)]],
            device   float*  outputs [[buffer(11)]],
            uint tid [[thread_position_in_grid]]
        ) {
            float VdotH = inputs[tid].x;
            float3 r = fresnel_schlick(VdotH, float3(0.04));
            outputs[tid] = r.r;
        }
        """
        let n = 20
        let inputs = (0..<n).map { SIMD3<Float>(Float($0) / Float(n - 1), 0, 0) }
        let results = try runNoiseKernel(kernelSource: kernel, inputs: inputs)
        for i in 1..<results.count {
            #expect(results[i] <= results[i - 1] + 1e-5,
                    "fresnel_schlick should be non-increasing as VdotH increases")
        }
    }

    // fresnel_schlick_roughness flattens the curve vs plain schlick
    @Test func schlickRoughnessFlattensGrazingAngle() throws {
        let kernel = """
        kernel void test_kernel(
            constant float3* inputs  [[buffer(10)]],
            device   float*  outputs [[buffer(11)]],
            uint tid [[thread_position_in_grid]]
        ) {
            float VdotH   = inputs[tid].x;
            float rough   = inputs[tid].y;
            float3 F0     = float3(0.04);
            float plain   = fresnel_schlick(VdotH, F0).r;
            float roughed = fresnel_schlick_roughness(VdotH, F0, rough).r;
            // roughed ≤ plain at all angles when roughness > 0
            outputs[tid] = (roughed <= plain + 1e-5) ? 1.0 : 0.0;
        }
        """
        var inputs: [SIMD3<Float>] = []
        for vi in 0..<5 {
            for ri in 1..<5 {
                inputs.append(SIMD3<Float>(Float(vi) / 4.0, Float(ri) / 4.0, 0))
            }
        }
        let results = try runNoiseKernel(kernelSource: kernel, inputs: inputs)
        for r in results {
            #expect(r == 1.0, "fresnel_schlick_roughness should be ≤ plain schlick")
        }
    }

    // fresnel_dielectric at VdotH=1, ior=1 → 0 (no interface, no reflection)
    @Test func dielectricNormalIncidenceIOR1() throws {
        let kernel = """
        kernel void test_kernel(
            constant float3* inputs  [[buffer(10)]],
            device   float*  outputs [[buffer(11)]],
            uint tid [[thread_position_in_grid]]
        ) {
            outputs[tid] = fresnel_dielectric(1.0, 1.0);
        }
        """
        let results = try runNoiseKernel(kernelSource: kernel, inputs: [SIMD3<Float>(0, 0, 0)])
        #expect(results[0] < 1e-4, "fresnel_dielectric at IOR=1 should be 0, got \(results[0])")
    }

    // fresnel_dielectric at VdotH=1 matches Schlick approximation ((n-1)/(n+1))^2
    @Test func dielectricNormalIncidenceMatchesFormula() throws {
        let kernel = """
        kernel void test_kernel(
            constant float3* inputs  [[buffer(10)]],
            device   float*  outputs [[buffer(11)]],
            uint tid [[thread_position_in_grid]]
        ) {
            float ior = inputs[tid].x;
            outputs[tid] = fresnel_dielectric(1.0, ior);
        }
        """
        let iors: [Float] = [1.5, 2.0, 1.33]
        let inputs = iors.map { SIMD3<Float>($0, 0, 0) }
        let results = try runNoiseKernel(kernelSource: kernel, inputs: inputs)
        for (ior, got) in zip(iors, results) {
            let expected = pow((ior - 1) / (ior + 1), 2)
            #expect(abs(got - expected) < 1e-4, "fresnel_dielectric(1.0, ior=\(ior)) expected \(expected), got \(got)")
        }
    }

    // fresnel_f0_conductor output in [0, 1] for physical metals
    @Test func conductorF0InRange() throws {
        let kernel = """
        kernel void test_kernel(
            constant float3* inputs  [[buffer(10)]],
            device   float*  outputs [[buffer(11)]],
            uint tid [[thread_position_in_grid]]
        ) {
            // Gold: eta=(0.143, 0.374, 1.44), k=(3.98, 2.38, 1.60)
            float3 eta = float3(0.143, 0.374, 1.44);
            float3 k   = float3(3.98,  2.38,  1.60);
            float3 f0  = fresnel_f0_conductor(eta, k);
            outputs[tid] = f0.r;
        }
        """
        let results = try runNoiseKernel(kernelSource: kernel, inputs: [SIMD3<Float>(0, 0, 0)])
        #expect(results[0] >= 0.0 && results[0] <= 1.0, "Gold F0.r should be in [0,1], got \(results[0])")
    }
}

// MARK: - BRDF

@Suite("BRDFProperties") struct BRDFProperties {

    // ggx_d ≥ 0 and peaks at NdotH=1 vs any lower NdotH
    @Test func ggxDNonNegativeAndPeaksAtHalf() throws {
        let kernel = """
        kernel void test_kernel(
            constant float3* inputs  [[buffer(10)]],
            device   float*  outputs [[buffer(11)]],
            uint tid [[thread_position_in_grid]]
        ) {
            float NdotH   = inputs[tid].x;
            float rough   = inputs[tid].y;
            outputs[tid]  = ggx_d(NdotH, rough);
        }
        """
        var inputs: [SIMD3<Float>] = []
        let roughValues: [Float] = [0.1, 0.3, 0.7]
        for rough in roughValues {
            for ni in 0...10 {
                inputs.append(SIMD3<Float>(Float(ni) / 10.0, rough, 0))
            }
        }
        let results = try runNoiseKernel(kernelSource: kernel, inputs: inputs)
        for d in results {
            #expect(d >= 0.0, "ggx_d should be non-negative, got \(d)")
        }
        // For each roughness, the value at NdotH=1 should be ≥ value at NdotH=0.5
        let stride = 11
        for i in 0..<roughValues.count {
            let peak = results[i * stride + 10] // NdotH=1.0
            let mid  = results[i * stride + 5]  // NdotH=0.5
            #expect(peak >= mid - 1e-5, "ggx_d should peak at NdotH=1 for roughness=\(roughValues[i])")
        }
    }

    // ggx_g_schlick output in [0, 1]
    @Test func ggxGSchlickInRange() throws {
        let kernel = """
        kernel void test_kernel(
            constant float3* inputs  [[buffer(10)]],
            device   float*  outputs [[buffer(11)]],
            uint tid [[thread_position_in_grid]]
        ) {
            float NdotV = inputs[tid].x;
            float rough = inputs[tid].y;
            outputs[tid] = ggx_g_schlick(NdotV, rough);
        }
        """
        var inputs: [SIMD3<Float>] = []
        for ni in 0...10 {
            for ri in 0...4 {
                inputs.append(SIMD3<Float>(Float(ni) / 10.0, Float(ri) / 4.0, 0))
            }
        }
        let results = try runNoiseKernel(kernelSource: kernel, inputs: inputs)
        for g in results {
            #expect(g >= 0.0 && g <= 1.0 + 1e-5, "ggx_g_schlick should be in [0,1], got \(g)")
        }
    }

    // ggx_g_smith(NdotL, NdotV, roughness) in [0, 1]
    @Test func ggxGSmithInRange() throws {
        let kernel = """
        kernel void test_kernel(
            constant float3* inputs  [[buffer(10)]],
            device   float*  outputs [[buffer(11)]],
            uint tid [[thread_position_in_grid]]
        ) {
            float NdotL = inputs[tid].x;
            float NdotV = inputs[tid].y;
            float rough = inputs[tid].z;
            outputs[tid] = ggx_g_smith(NdotL, NdotV, rough);
        }
        """
        var inputs: [SIMD3<Float>] = []
        for ni in 0...4 {
            for nv in 0...4 {
                inputs.append(SIMD3<Float>(Float(ni) / 4.0, Float(nv) / 4.0, 0.5))
            }
        }
        let results = try runNoiseKernel(kernelSource: kernel, inputs: inputs)
        for g in results {
            #expect(g >= 0.0 && g <= 1.0 + 1e-5, "ggx_g_smith should be in [0,1], got \(g)")
        }
    }

    // brdf_lambert(albedo) == albedo / π
    @Test func lambertEqualsAlbedoOverPi() throws {
        let kernel = """
        kernel void test_kernel(
            constant float3* inputs  [[buffer(10)]],
            device   float*  outputs [[buffer(11)]],
            uint tid [[thread_position_in_grid]]
        ) {
            float3 albedo = inputs[tid];
            float3 diff   = brdf_lambert(albedo);
            // Sum of components vs expected
            outputs[tid] = diff.r - (albedo.r / M_PI_F);
        }
        """
        let albedos: [SIMD3<Float>] = [
            SIMD3<Float>(1.0, 1.0, 1.0),
            SIMD3<Float>(0.5, 0.3, 0.8),
            SIMD3<Float>(0.0, 0.0, 0.0),
        ]
        let results = try runNoiseKernel(kernelSource: kernel, inputs: albedos)
        for (alb, err) in zip(albedos, results) {
            #expect(abs(err) < 1e-5, "brdf_lambert: expected albedo.r/π=\(alb.x / .pi), got error=\(err)")
        }
    }

    // brdf_oren_nayar at sigma=0 ≈ brdf_lambert (same output within tolerance)
    @Test func orenNayarAtSigmaZeroApproachesLambert() throws {
        let kernel = """
        kernel void test_kernel(
            constant float3* inputs  [[buffer(10)]],
            device   float*  outputs [[buffer(11)]],
            uint tid [[thread_position_in_grid]]
        ) {
            float3 N = normalize(float3(0.0, 0.0, 1.0));
            float3 V = normalize(float3(0.0, 0.0, 1.0));
            float3 L = normalize(float3(inputs[tid].x, 0.0, 1.0));
            float3 albedo = float3(1.0);
            float3 on = brdf_oren_nayar(N, V, L, albedo, 0.0);
            float3 lb = brdf_lambert(albedo);
            outputs[tid] = abs(on.r - lb.r);
        }
        """
        let inputs = (0..<8).map { SIMD3<Float>(Float($0) / 4.0 - 1.0, 0, 0) }
        let results = try runNoiseKernel(kernelSource: kernel, inputs: inputs)
        for diff in results {
            #expect(diff < 0.01, "brdf_oren_nayar(sigma=0) should match Lambert within 1%, got diff=\(diff)")
        }
    }

    // brdf_cook_torrance output ≥ 0
    @Test func cookTorranceNonNegative() throws {
        let kernel = """
        kernel void test_kernel(
            constant float3* inputs  [[buffer(10)]],
            device   float*  outputs [[buffer(11)]],
            uint tid [[thread_position_in_grid]]
        ) {
            float3 N  = normalize(float3(0.0, 0.0, 1.0));
            float3 V  = normalize(float3(0.1, 0.0, 1.0));
            float3 L  = normalize(float3(inputs[tid].x, inputs[tid].y, 1.0));
            float rough = inputs[tid].z;
            float3 albedo = float3(0.5);
            float3 F0     = float3(0.04);
            float3 result = brdf_cook_torrance(N, V, L, albedo, rough, 0.0, F0);
            outputs[tid] = min(min(result.r, result.g), result.b);
        }
        """
        var inputs: [SIMD3<Float>] = []
        for li in -2...2 {
            for ri in 0...4 {
                inputs.append(SIMD3<Float>(Float(li) * 0.5, 0.0, Float(ri) / 4.0))
            }
        }
        let results = try runNoiseKernel(kernelSource: kernel, inputs: inputs)
        for r in results {
            #expect(r >= -1e-5, "brdf_cook_torrance output should be ≥ 0, got \(r)")
        }
    }

    // brdf_ggx(N, V, L=N, F0, roughness) should equal brdf_ggx(N, V, L=N, F0, roughness)
    // i.e. deterministic (same inputs → same output)
    @Test func ggxDeterministic() throws {
        let kernel = """
        kernel void test_kernel(
            constant float3* inputs  [[buffer(10)]],
            device   float*  outputs [[buffer(11)]],
            uint tid [[thread_position_in_grid]]
        ) {
            float3 N = normalize(float3(0.0, 1.0, 0.0));
            float3 V = normalize(float3(0.2, 1.0, 0.1));
            float3 L = normalize(float3(inputs[tid].x, 1.0, inputs[tid].y));
            float3 F0 = float3(0.04, 0.04, 0.04);
            float rough = 0.4;
            float3 r1 = brdf_ggx(N, V, L, F0, rough);
            float3 r2 = brdf_ggx(N, V, L, F0, rough);
            outputs[tid] = length(r1 - r2);
        }
        """
        let inputs = (0..<10).map { i in
            SIMD3<Float>(Float(i) * 0.1 - 0.5, Float(i) * 0.05, 0)
        }
        let results = try runNoiseKernel(kernelSource: kernel, inputs: inputs)
        for diff in results {
            #expect(diff < 1e-6, "brdf_ggx should be deterministic, got diff=\(diff)")
        }
    }

    // Ashikhmin-Shirley: output ≥ 0 for a range of configurations
    @Test func ashikhminShirleyNonNegative() throws {
        let kernel = """
        kernel void test_kernel(
            constant float3* inputs  [[buffer(10)]],
            device   float*  outputs [[buffer(11)]],
            uint tid [[thread_position_in_grid]]
        ) {
            float3 N  = normalize(float3(0.0, 1.0, 0.0));
            float3 V  = normalize(float3(0.2, 1.0, 0.1));
            float3 T  = normalize(float3(1.0, 0.0, 0.0));
            float3 B  = cross(N, T);
            float3 L  = normalize(float3(inputs[tid].x, 1.0, inputs[tid].y));
            float3 Rd = float3(0.5);
            float3 Rs = float3(0.04);
            float nu  = inputs[tid].z * 100.0 + 1.0;   // 1–101
            float nv  = 500.0;
            float3 r  = brdf_ashikhmin_shirley(N, V, L, T, B, Rd, Rs, nu, nv);
            outputs[tid] = min(min(r.r, r.g), r.b);
        }
        """
        var inputs: [SIMD3<Float>] = []
        for li in 0...4 {
            for ri in 0...4 {
                inputs.append(SIMD3<Float>(Float(li) * 0.4 - 0.8, 0.0, Float(ri) / 4.0))
            }
        }
        let results = try runNoiseKernel(kernelSource: kernel, inputs: inputs)
        for r in results {
            #expect(r >= -1e-4, "brdf_ashikhmin_shirley should be ≥ 0, got \(r)")
        }
    }
}

// MARK: - Normal Mapping

@Suite("NormalMappingProperties") struct NormalMappingProperties {

    // decode_normal_map(float3(0.5, 0.5, 1.0)) → approximately (0, 0, 1)
    @Test func decodeIdentityNormal() throws {
        let kernel = """
        kernel void test_kernel(
            constant float3* inputs  [[buffer(10)]],
            device   float*  outputs [[buffer(11)]],
            uint tid [[thread_position_in_grid]]
        ) {
            float3 rgb = float3(0.5, 0.5, 1.0);
            float3 n   = decode_normal_map(rgb);
            // Should point roughly toward +Z after normalize
            outputs[tid] = n.z;
        }
        """
        let results = try runNoiseKernel(kernelSource: kernel, inputs: [SIMD3<Float>(0, 0, 0)])
        #expect(results[0] > 0.9, "decode_normal_map(0.5,0.5,1) should give z≈1, got \(results[0])")
    }

    // decode_normal_map output is unit length
    @Test func decodeOutputIsNormalized() throws {
        let kernel = """
        kernel void test_kernel(
            constant float3* inputs  [[buffer(10)]],
            device   float*  outputs [[buffer(11)]],
            uint tid [[thread_position_in_grid]]
        ) {
            float3 rgb = inputs[tid];
            float3 n   = decode_normal_map(rgb);
            outputs[tid] = length(n);
        }
        """
        let inputs: [SIMD3<Float>] = [
            SIMD3<Float>(0.5, 0.5, 1.0),
            SIMD3<Float>(0.8, 0.2, 0.9),
            SIMD3<Float>(0.1, 0.9, 0.5),
            SIMD3<Float>(0.5, 0.5, 0.7),  // (0.5,0.5,0.5) maps to zero vector → NaN; use 0.7 z
        ]
        let results = try runNoiseKernel(kernelSource: kernel, inputs: inputs)
        for len in results {
            #expect(abs(len - 1.0) < 1e-4, "decode_normal_map output should be unit length, got \(len)")
        }
    }

    // decode_normal_map_dx flips the Y channel vs OpenGL
    @Test func decodeDXFlipsY() throws {
        let kernel = """
        kernel void test_kernel(
            constant float3* inputs  [[buffer(10)]],
            device   float*  outputs [[buffer(11)]],
            uint tid [[thread_position_in_grid]]
        ) {
            float3 rgb  = inputs[tid];
            float3 nGL  = decode_normal_map(rgb);
            float3 nDX  = decode_normal_map_dx(rgb);
            outputs[tid] = nDX.y + nGL.y;  // DX.y == -GL.y, sum should be ~0
        }
        """
        let inputs: [SIMD3<Float>] = [
            SIMD3<Float>(0.7, 0.3, 0.8),
            SIMD3<Float>(0.5, 0.8, 0.9),
        ]
        let results = try runNoiseKernel(kernelSource: kernel, inputs: inputs)
        for sum in results {
            #expect(abs(sum) < 1e-4, "DX.y + GL.y should cancel to 0, got \(sum)")
        }
    }

    // ts_to_ws with identity TBN → same as input
    @Test func tsToWsWithIdentityTBN() throws {
        let kernel = """
        kernel void test_kernel(
            constant float3* inputs  [[buffer(10)]],
            device   float*  outputs [[buffer(11)]],
            uint tid [[thread_position_in_grid]]
        ) {
            float3 n_ts = normalize(inputs[tid]);
            float3 T = float3(1, 0, 0);
            float3 B = float3(0, 1, 0);
            float3 N = float3(0, 0, 1);
            float3 n_ws = ts_to_ws(n_ts, T, B, N);
            outputs[tid] = length(n_ws - n_ts);
        }
        """
        let inputs: [SIMD3<Float>] = [
            SIMD3<Float>(0, 0, 1),
            SIMD3<Float>(0.3, 0.2, 0.9),
            SIMD3<Float>(-0.5, 0.1, 0.8),
        ]
        let results = try runNoiseKernel(kernelSource: kernel, inputs: inputs)
        for diff in results {
            #expect(diff < 1e-4, "ts_to_ws with identity TBN should preserve normal, got diff=\(diff)")
        }
    }

    // ws_to_ts is inverse of ts_to_ws
    @Test func wsToTsIsInverseOfTsToWs() throws {
        let kernel = """
        kernel void test_kernel(
            constant float3* inputs  [[buffer(10)]],
            device   float*  outputs [[buffer(11)]],
            uint tid [[thread_position_in_grid]]
        ) {
            // Build a proper orthonormal TBN.
            float3 N = normalize(float3(0.1, 0.2, 0.9));
            float3 up = float3(0.0, 1.0, 0.0);
            float3 T  = normalize(cross(up, N));
            float3 B  = normalize(cross(N, T));

            float3 n_ts  = normalize(inputs[tid]);
            float3 n_ws  = ts_to_ws(n_ts, T, B, N);
            float3 n_ts2 = ws_to_ts(n_ws, T, B, N);
            outputs[tid] = length(n_ts2 - n_ts);
        }
        """
        let inputs: [SIMD3<Float>] = [
            SIMD3<Float>(0, 0, 1),
            SIMD3<Float>(0.5, 0.2, 0.8),
            SIMD3<Float>(-0.3, 0.4, 0.7),
        ]
        let results = try runNoiseKernel(kernelSource: kernel, inputs: inputs)
        for diff in results {
            #expect(diff < 1e-4, "ws_to_ts should be inverse of ts_to_ws, got diff=\(diff)")
        }
    }
}

// MARK: - Detail Normals

@Suite("DetailNormalsProperties") struct DetailNormalsProperties {

    // combine_normals_udn with flat detail (0,0,1) → approximately base
    @Test func udnWithFlatDetailPreservesBase() throws {
        let kernel = """
        kernel void test_kernel(
            constant float3* inputs  [[buffer(10)]],
            device   float*  outputs [[buffer(11)]],
            uint tid [[thread_position_in_grid]]
        ) {
            float3 base   = normalize(inputs[tid]);
            float3 detail = float3(0.0, 0.0, 1.0);   // flat
            float3 result = combine_normals_udn(base, detail);
            outputs[tid] = length(result - base);
        }
        """
        let inputs: [SIMD3<Float>] = [
            SIMD3<Float>(0, 0, 1),
            SIMD3<Float>(0.3, 0.1, 0.9),
            SIMD3<Float>(-0.4, 0.2, 0.8),
        ]
        let results = try runNoiseKernel(kernelSource: kernel, inputs: inputs)
        for diff in results {
            #expect(diff < 1e-4, "UDN with flat detail should preserve base, got diff=\(diff)")
        }
    }

    // combine_normals_udn output is unit length
    @Test func udnOutputIsNormalized() throws {
        let kernel = """
        kernel void test_kernel(
            constant float3* inputs  [[buffer(10)]],
            device   float*  outputs [[buffer(11)]],
            uint tid [[thread_position_in_grid]]
        ) {
            float3 base   = normalize(inputs[tid]);
            float3 detail = normalize(float3(inputs[tid].y, inputs[tid].z, inputs[tid].x));
            float3 result = combine_normals_udn(base, detail);
            outputs[tid] = length(result);
        }
        """
        let inputs: [SIMD3<Float>] = [
            SIMD3<Float>(0.1, 0.2, 0.9),
            SIMD3<Float>(-0.3, 0.4, 0.8),
            SIMD3<Float>(0.5, -0.5, 0.7),
        ]
        let results = try runNoiseKernel(kernelSource: kernel, inputs: inputs)
        for len in results {
            #expect(abs(len - 1.0) < 1e-4, "UDN output should be unit length, got \(len)")
        }
    }

    // combine_normals_whiteout output is unit length
    @Test func whiteoutOutputIsNormalized() throws {
        let kernel = """
        kernel void test_kernel(
            constant float3* inputs  [[buffer(10)]],
            device   float*  outputs [[buffer(11)]],
            uint tid [[thread_position_in_grid]]
        ) {
            float3 base   = normalize(inputs[tid]);
            float3 detail = normalize(float3(inputs[tid].y, -inputs[tid].x, 0.8));
            float3 result = combine_normals_whiteout(base, detail);
            outputs[tid] = length(result);
        }
        """
        let inputs: [SIMD3<Float>] = [
            SIMD3<Float>(0.2, 0.3, 0.9),
            SIMD3<Float>(-0.1, 0.5, 0.8),
        ]
        let results = try runNoiseKernel(kernelSource: kernel, inputs: inputs)
        for len in results {
            #expect(abs(len - 1.0) < 1e-4, "Whiteout output should be unit length, got \(len)")
        }
    }

    // combine_normals_whiteout: both bases aligned → identical result to UDN
    // (both degenerate to the same thing when base == detail == (0,0,1))
    @Test func whiteoutWithIdentityNormals() throws {
        let kernel = """
        kernel void test_kernel(
            constant float3* inputs  [[buffer(10)]],
            device   float*  outputs [[buffer(11)]],
            uint tid [[thread_position_in_grid]]
        ) {
            float3 flat = float3(0.0, 0.0, 1.0);
            float3 r    = combine_normals_whiteout(flat, flat);
            outputs[tid] = length(r - flat);
        }
        """
        let results = try runNoiseKernel(kernelSource: kernel, inputs: [SIMD3<Float>(0, 0, 0)])
        #expect(results[0] < 1e-4, "whiteout(flat, flat) should return flat, got diff=\(results[0])")
    }
}

// MARK: - Triplanar

@Suite("TriplanarProperties") struct TriplanarProperties {

    // triplanar_blend_weights sums to 1.0 for any surface normal
    @Test func blendWeightsSumToOne() throws {
        let kernel = """
        kernel void test_kernel(
            constant float3* inputs  [[buffer(10)]],
            device   float*  outputs [[buffer(11)]],
            uint tid [[thread_position_in_grid]]
        ) {
            float3 n = normalize(inputs[tid]);
            float3 w = triplanar_blend_weights(n, 4.0);
            outputs[tid] = w.x + w.y + w.z;
        }
        """
        let inputs: [SIMD3<Float>] = [
            SIMD3<Float>(1, 0, 0),
            SIMD3<Float>(0, 1, 0),
            SIMD3<Float>(0, 0, 1),
            SIMD3<Float>(1, 1, 1),
            SIMD3<Float>(0.3, 0.7, 0.1),
            SIMD3<Float>(-0.5, 0.2, 0.8),
        ]
        let results = try runNoiseKernel(kernelSource: kernel, inputs: inputs)
        for sum in results {
            #expect(abs(sum - 1.0) < 1e-4, "triplanar_blend_weights should sum to 1.0, got \(sum)")
        }
    }

    // triplanar_blend_weights with axis-aligned normal → one weight dominates (≥ 0.9)
    @Test func blendWeightsAxisAligned() throws {
        let kernel = """
        kernel void test_kernel(
            constant float3* inputs  [[buffer(10)]],
            device   float*  outputs [[buffer(11)]],
            uint tid [[thread_position_in_grid]]
        ) {
            float3 n = normalize(inputs[tid]);
            float3 w = triplanar_blend_weights(n, 8.0);
            outputs[tid] = max(max(w.x, w.y), w.z);
        }
        """
        let inputs: [SIMD3<Float>] = [
            SIMD3<Float>(1, 0, 0),
            SIMD3<Float>(0, 1, 0),
            SIMD3<Float>(0, 0, 1),
        ]
        let results = try runNoiseKernel(kernelSource: kernel, inputs: inputs)
        for maxW in results {
            #expect(maxW > 0.9, "axis-aligned normal should have one dominant weight, got max=\(maxW)")
        }
    }

    // triplanar_blend_weights: all components ≥ 0
    @Test func blendWeightsNonNegative() throws {
        let kernel = """
        kernel void test_kernel(
            constant float3* inputs  [[buffer(10)]],
            device   float*  outputs [[buffer(11)]],
            uint tid [[thread_position_in_grid]]
        ) {
            float3 n = normalize(inputs[tid]);
            float3 w = triplanar_blend_weights(n, 4.0);
            outputs[tid] = min(min(w.x, w.y), w.z);
        }
        """
        let inputs: [SIMD3<Float>] = [
            SIMD3<Float>(0.3, -0.7, 0.6),
            SIMD3<Float>(-1, -1, -1),
            SIMD3<Float>(0.1, 0.1, 0.1),
        ]
        let results = try runNoiseKernel(kernelSource: kernel, inputs: inputs)
        for minW in results {
            #expect(minW >= -1e-5, "triplanar_blend_weights components should be ≥ 0, got \(minW)")
        }
    }
}

// MARK: - SSS

@Suite("SSSProperties") struct SSSProperties {

    // sss_backlit at thickness=1.0 → 0 (fully opaque, no transmission)
    @Test func backlitThicknessOneReturnsZero() throws {
        let kernel = """
        kernel void test_kernel(
            constant float3* inputs  [[buffer(10)]],
            device   float*  outputs [[buffer(11)]],
            uint tid [[thread_position_in_grid]]
        ) {
            float3 N = float3(0.0, 1.0, 0.0);
            float3 L = float3(0.0, -1.0, 0.0);  // backlit (from below)
            float3 V = float3(0.0, 1.0, 0.0);
            float distortion = inputs[tid].x;
            outputs[tid] = sss_backlit(N, L, V, 1.0, distortion);
        }
        """
        let inputs = [0.0, 0.1, 0.2, 0.5].map { SIMD3<Float>(Float($0), 0, 0) }
        let results = try runNoiseKernel(kernelSource: kernel, inputs: inputs)
        for r in results {
            #expect(r < 1e-5, "sss_backlit(thickness=1) should be 0, got \(r)")
        }
    }

    // sss_backlit at thickness=0.0 → > 0 when light comes from behind
    @Test func backlitThicknessZeroHasTransmission() throws {
        let kernel = """
        kernel void test_kernel(
            constant float3* inputs  [[buffer(10)]],
            device   float*  outputs [[buffer(11)]],
            uint tid [[thread_position_in_grid]]
        ) {
            float3 N = float3(0.0, 1.0, 0.0);
            float3 V = float3(0.0, 1.0, 0.0);
            // Light from exactly opposite the view through the surface
            float3 L = float3(0.0, -1.0, 0.0);
            float distortion = inputs[tid].x;
            outputs[tid] = sss_backlit(N, L, V, 0.0, distortion);
        }
        """
        let inputs = [0.0, 0.2].map { SIMD3<Float>(Float($0), 0, 0) }
        let results = try runNoiseKernel(kernelSource: kernel, inputs: inputs)
        for r in results {
            #expect(r > 0.0, "sss_backlit(thickness=0) should have non-zero transmission")
        }
    }

    // sss_wrap_lighting output ≥ 0 for all wrap values
    @Test func wrapLightingNonNegative() throws {
        let kernel = """
        kernel void test_kernel(
            constant float3* inputs  [[buffer(10)]],
            device   float*  outputs [[buffer(11)]],
            uint tid [[thread_position_in_grid]]
        ) {
            float3 N = normalize(float3(0.0, 1.0, 0.0));
            float3 L = normalize(float3(inputs[tid].x, inputs[tid].y, 1.0));
            float wrap = inputs[tid].z;
            float3 tint = float3(1.0, 0.8, 0.7);
            float3 r = sss_wrap_lighting(N, L, wrap, tint);
            outputs[tid] = min(min(r.r, r.g), r.b);
        }
        """
        var inputs: [SIMD3<Float>] = []
        for li in -2...2 {
            for wi in 0...4 {
                inputs.append(SIMD3<Float>(Float(li) * 0.5, 0, Float(wi) / 4.0))
            }
        }
        let results = try runNoiseKernel(kernelSource: kernel, inputs: inputs)
        for r in results {
            #expect(r >= -1e-5, "sss_wrap_lighting should be ≥ 0, got \(r)")
        }
    }

    // sss_wrap_lighting at wrap=0 → standard Lambert (no extension past terminator)
    @Test func wrapLightingWrapZeroIsLambert() throws {
        let kernel = """
        kernel void test_kernel(
            constant float3* inputs  [[buffer(10)]],
            device   float*  outputs [[buffer(11)]],
            uint tid [[thread_position_in_grid]]
        ) {
            float3 N = normalize(float3(0.0, 0.0, 1.0));
            float3 L = normalize(float3(inputs[tid].x, 0.0, inputs[tid].y));
            float3 tint = float3(1.0);
            float3 wrap0 = sss_wrap_lighting(N, L, 0.0, tint);
            float NdotL = saturate(dot(N, L));
            // wrap=0: wrapped = (NdotL + 0) / 1 = NdotL
            outputs[tid] = abs(wrap0.r - NdotL);
        }
        """
        var inputs: [SIMD3<Float>] = []
        for li in 0...4 {
            inputs.append(SIMD3<Float>(Float(li) * 0.3 - 0.6, 1.0, 0))
        }
        let results = try runNoiseKernel(kernelSource: kernel, inputs: inputs)
        for diff in results {
            #expect(diff < 1e-4, "sss_wrap_lighting(wrap=0) should match Lambert, got diff=\(diff)")
        }
    }
}

// MARK: - Fiber BRDF

@Suite("FiberBRDFProperties") struct FiberBRDFProperties {

    // r_lobe and tt_lobe are both in [0, 1]
    @Test func fibersLobesInRange() throws {
        let kernel = """
        kernel void test_kernel(
            constant float3* inputs  [[buffer(10)]],
            device   float*  outputs [[buffer(11)]],
            uint tid [[thread_position_in_grid]]
        ) {
            float3 T = normalize(float3(1.0, 0.0, 0.0));
            float3 L = normalize(inputs[tid]);
            float3 V = normalize(float3(inputs[tid].z, inputs[tid].y, inputs[tid].x));
            FiberBRDFResult r = fiber_marschner_lite(T, L, V, 0.15, 0.5);
            // outputs: r_lobe, tt_lobe
            outputs[tid * 2 + 0] = r.r_lobe;
            outputs[tid * 2 + 1] = r.tt_lobe;
        }
        """
        let inputs: [SIMD3<Float>] = [
            SIMD3<Float>(1, 0, 0),
            SIMD3<Float>(0, 1, 1),
            SIMD3<Float>(-1, 0.5, 0.5),
            SIMD3<Float>(0.3, -0.7, 0.6),
        ]
        let results = try runNoiseKernel(kernelSource: kernel, inputs: inputs, outputCount: inputs.count * 2)
        for val in results {
            #expect(val >= -1e-4 && val <= 1.0 + 1e-4, "Fiber lobe should be in [0,1], got \(val)")
        }
    }

    // r_lobe is deterministic
    @Test func fiberRLobeDeterministic() throws {
        let kernel = """
        kernel void test_kernel(
            constant float3* inputs  [[buffer(10)]],
            device   float*  outputs [[buffer(11)]],
            uint tid [[thread_position_in_grid]]
        ) {
            float3 T = normalize(float3(1.0, 0.0, 0.0));
            float3 L = normalize(inputs[tid]);
            float3 V = normalize(float3(0.5, 0.5, 0.7));
            FiberBRDFResult r1 = fiber_marschner_lite(T, L, V, 0.15, 0.5);
            FiberBRDFResult r2 = fiber_marschner_lite(T, L, V, 0.15, 0.5);
            outputs[tid] = abs(r1.r_lobe - r2.r_lobe);
        }
        """
        let inputs = (0..<5).map { i in
            SIMD3<Float>(Float(i) * 0.4 - 0.8, Float(i) * 0.2, 0.5)
        }
        let results = try runNoiseKernel(kernelSource: kernel, inputs: inputs)
        for diff in results {
            #expect(diff < 1e-6, "fiber r_lobe should be deterministic, got diff=\(diff)")
        }
    }

    // fiber_trt_lobe output in [0, 1]
    @Test func fiberTRTLobeInRange() throws {
        let kernel = """
        kernel void test_kernel(
            constant float3* inputs  [[buffer(10)]],
            device   float*  outputs [[buffer(11)]],
            uint tid [[thread_position_in_grid]]
        ) {
            float3 T = normalize(float3(0.0, 1.0, 0.0));
            float3 L = normalize(inputs[tid]);
            float3 V = normalize(float3(inputs[tid].y, inputs[tid].z, inputs[tid].x));
            outputs[tid] = fiber_trt_lobe(T, L, V, 0.3);
        }
        """
        let inputs: [SIMD3<Float>] = [
            SIMD3<Float>(1, 0, 0),
            SIMD3<Float>(-1, 0, 0),
            SIMD3<Float>(0, 1, 0),
            SIMD3<Float>(0.5, 0.5, 0.7),
            SIMD3<Float>(-0.3, 0.7, 0.6),
        ]
        let results = try runNoiseKernel(kernelSource: kernel, inputs: inputs)
        for r in results {
            #expect(r >= -1e-4 && r <= 1.0 + 1e-4, "fiber_trt_lobe should be in [0,1], got \(r)")
        }
    }
}

// MARK: - Thin Film

@Suite("ThinFilmProperties") struct ThinFilmProperties {

    // thinfilm_rgb at thickness_nm=0 → returns base dielectric F0
    @Test func thinFilmZeroThicknessReturnsDielectricF0() throws {
        let kernel = """
        kernel void test_kernel(
            constant float3* inputs  [[buffer(10)]],
            device   float*  outputs [[buffer(11)]],
            uint tid [[thread_position_in_grid]]
        ) {
            float VdotH = inputs[tid].x;
            float ior_base = 1.52;
            float3 r = thinfilm_rgb(VdotH, 0.0, 1.5, ior_base);
            // Should equal dielectric F0 = ((n-1)/(n+1))^2
            float expected = fresnel_dielectric(1.0, ior_base);
            outputs[tid] = abs(r.r - expected);
        }
        """
        let vdotHValues: [Float] = [0.0, 0.3, 0.7, 1.0]
        let inputs = vdotHValues.map { SIMD3<Float>($0, 0, 0) }
        let results = try runNoiseKernel(kernelSource: kernel, inputs: inputs)
        for diff in results {
            #expect(diff < 1e-4, "thinfilm_rgb(thickness=0) should return dielectric F0, got diff=\(diff)")
        }
    }

    // thinfilm_rgb output in [0, 1] for physical ranges
    @Test func thinFilmOutputInRange() throws {
        let kernel = """
        kernel void test_kernel(
            constant float3* inputs  [[buffer(10)]],
            device   float*  outputs [[buffer(11)]],
            uint tid [[thread_position_in_grid]]
        ) {
            float VdotH      = inputs[tid].x;
            float thickness  = inputs[tid].y;  // 0–300 nm
            float3 r = thinfilm_rgb(VdotH, thickness, 1.33, 1.52);
            outputs[tid] = min(min(r.r, r.g), r.b);
        }
        """
        var inputs: [SIMD3<Float>] = []
        for vi in 0...5 {
            for ti in 0...6 {
                inputs.append(SIMD3<Float>(Float(vi) / 5.0, Float(ti) * 50.0, 0))
            }
        }
        let results = try runNoiseKernel(kernelSource: kernel, inputs: inputs)
        for r in results {
            #expect(r >= -1e-4, "thinfilm_rgb components should be ≥ 0, got \(r)")
        }
    }

    // thinfilm_hue_rotate at thickness_nm=0 → returns base_f0 unchanged
    @Test func hueRotateZeroThicknessReturnsBase() throws {
        let kernel = """
        kernel void test_kernel(
            constant float3* inputs  [[buffer(10)]],
            device   float*  outputs [[buffer(11)]],
            uint tid [[thread_position_in_grid]]
        ) {
            float3 base_f0 = inputs[tid];
            float3 r = thinfilm_hue_rotate(base_f0, 0.0, 0.5);
            outputs[tid] = length(r - base_f0);
        }
        """
        let bases: [SIMD3<Float>] = [
            SIMD3<Float>(0.04, 0.04, 0.04),
            SIMD3<Float>(0.9, 0.7, 0.2),
            SIMD3<Float>(0.5, 0.5, 0.5),
        ]
        let results = try runNoiseKernel(kernelSource: kernel, inputs: bases)
        for diff in results {
            #expect(diff < 1e-4, "thinfilm_hue_rotate(thickness=0) should return base_f0, got diff=\(diff)")
        }
    }

    // thinfilm_hue_rotate produces color variation at non-zero thickness
    @Test func hueRotateVariesWithThickness() throws {
        let kernel = """
        kernel void test_kernel(
            constant float3* inputs  [[buffer(10)]],
            device   float*  outputs [[buffer(11)]],
            uint tid [[thread_position_in_grid]]
        ) {
            float3 base = float3(0.04);
            float t1 = inputs[tid].x;
            float t2 = inputs[tid].y;
            float3 r1 = thinfilm_hue_rotate(base, t1, 0.5);
            float3 r2 = thinfilm_hue_rotate(base, t2, 0.5);
            outputs[tid] = length(r1 - r2);
        }
        """
        // Different thickness values should produce different colors
        let inputs: [SIMD3<Float>] = [
            SIMD3<Float>(50.0, 150.0, 0),
            SIMD3<Float>(100.0, 250.0, 0),
        ]
        let results = try runNoiseKernel(kernelSource: kernel, inputs: inputs)
        for diff in results {
            #expect(diff > 0.001, "Different thicknesses should produce different colors, got diff=\(diff)")
        }
    }
}

// MARK: - Preamble Presence

@Suite("PBRPreamblePresence") struct PBRPreamblePresence {

    // Verify the preamble contains the new PBR function names
    @Test func preambleContainsFresnel() {
        let preamble = PresetLoader.shaderPreamble
        #expect(preamble.contains("fresnel_schlick"), "preamble must contain fresnel_schlick")
        #expect(preamble.contains("fresnel_schlick_roughness"), "preamble must contain fresnel_schlick_roughness")
        #expect(preamble.contains("fresnel_dielectric"), "preamble must contain fresnel_dielectric")
        #expect(preamble.contains("fresnel_f0_conductor"), "preamble must contain fresnel_f0_conductor")
    }

    @Test func preambleContainsBRDF() {
        let preamble = PresetLoader.shaderPreamble
        #expect(preamble.contains("ggx_d"), "preamble must contain ggx_d")
        #expect(preamble.contains("ggx_g_smith"), "preamble must contain ggx_g_smith")
        #expect(preamble.contains("brdf_ggx"), "preamble must contain brdf_ggx")
        #expect(preamble.contains("brdf_lambert"), "preamble must contain brdf_lambert")
        #expect(preamble.contains("brdf_oren_nayar"), "preamble must contain brdf_oren_nayar")
        #expect(preamble.contains("brdf_cook_torrance"), "preamble must contain brdf_cook_torrance")
    }

    @Test func preambleContainsNormalMapping() {
        let preamble = PresetLoader.shaderPreamble
        #expect(preamble.contains("decode_normal_map"), "preamble must contain decode_normal_map")
        #expect(preamble.contains("ts_to_ws"), "preamble must contain ts_to_ws")
        #expect(preamble.contains("ws_to_ts"), "preamble must contain ws_to_ts")
        #expect(preamble.contains("combine_normals_udn"), "preamble must contain combine_normals_udn")
        #expect(preamble.contains("combine_normals_whiteout"), "preamble must contain combine_normals_whiteout")
        #expect(preamble.contains("triplanar_blend_weights"), "preamble must contain triplanar_blend_weights")
        #expect(preamble.contains("triplanar_sample"), "preamble must contain triplanar_sample")
    }

    @Test func preambleContainsSSSAndFiber() {
        let preamble = PresetLoader.shaderPreamble
        #expect(preamble.contains("sss_backlit"), "preamble must contain sss_backlit")
        #expect(preamble.contains("sss_wrap_lighting"), "preamble must contain sss_wrap_lighting")
        #expect(preamble.contains("fiber_marschner_lite"), "preamble must contain fiber_marschner_lite")
        #expect(preamble.contains("fiber_trt_lobe"), "preamble must contain fiber_trt_lobe")
    }

    @Test func preambleContainsThinFilm() {
        let preamble = PresetLoader.shaderPreamble
        #expect(preamble.contains("thinfilm_rgb"), "preamble must contain thinfilm_rgb")
        #expect(preamble.contains("thinfilm_hue_rotate"), "preamble must contain thinfilm_hue_rotate")
        #expect(preamble.contains("parallax_occlusion"), "preamble must contain parallax_occlusion")
    }

    // Verify PBR functions load AFTER Noise (so Noise is available if needed)
    @Test func pbrLoadsAfterNoise() {
        let preamble = PresetLoader.shaderPreamble
        guard let noiseIdx = preamble.range(of: "perlin2d"),
              let pbrIdx   = preamble.range(of: "fresnel_schlick") else {
            Issue.record("Could not find noise or PBR functions in preamble")
            return
        }
        #expect(noiseIdx.lowerBound < pbrIdx.lowerBound,
                "Noise functions must appear before PBR functions in preamble")
    }
}
