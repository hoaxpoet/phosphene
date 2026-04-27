// UtilityPerformanceTests.swift — V.4 shader utility GPU benchmark suite.
//
// 24 benchmarks across Noise, PBR, Geometry, Volume, Texture, Color, Materials.
// Each test measures one utility at 1920×1080 (2M threads) via GPU timestamps.
//
// Results inform SHADER_CRAFT.md §9.4 two-column performance table.
// Produce docs/V4_PERF_RESULTS.json by running:
//   swift test --package-path PhospheneEngine --filter UtilityPerformanceTests
//
// NOTE: These tests measure real GPU performance and are skipped gracefully if
// no Metal device is available (e.g. Linux CI). They do NOT assert pass/fail —
// they log results so the UtilityCostTableUpdater CLI can consume them.
//
// On CI: run with PERF_TESTS=1 to enable; otherwise they skip silently.

import Testing
import Foundation
import Metal
@testable import Presets

// MARK: - Gate

private let perfTestsEnabled: Bool = ProcessInfo.processInfo.environment["PERF_TESTS"] == "1"

// MARK: - Suite

@Suite("UtilityPerformanceTests")
struct UtilityPerformanceTests {

    // MARK: - Noise tree

    @Test func bench_fbm8_fullscreen() throws {
        guard perfTestsEnabled else { return }
        let result = try runGPUBenchmark(
            function: "fbm8",
            kernelSource: "result = fbm8(float3(uv * 4.0, t * 0.1));"
        )
        guard let r = result else { return }
        reportAndLog(r, category: "noise", notes: "8-octave fBM, 3D, full-screen")
    }

    @Test func bench_fbm4_fullscreen() throws {
        guard perfTestsEnabled else { return }
        let result = try runGPUBenchmark(
            function: "fbm4",
            kernelSource: "result = fbm4(float3(uv * 4.0, t * 0.1));"
        )
        guard let r = result else { return }
        reportAndLog(r, category: "noise", notes: "4-octave fBM, 3D, full-screen")
    }

    @Test func bench_curl_noise_fullscreen() throws {
        guard perfTestsEnabled else { return }
        let result = try runGPUBenchmark(
            function: "curl_noise",
            kernelSource: "float3 c = curl_noise(wp * 2.0); result = c.x + c.y + c.z;"
        )
        guard let r = result else { return }
        reportAndLog(r, category: "noise", notes: "3D curl noise (6 fbm8 samples)")
    }

    @Test func bench_worley_fbm_fullscreen() throws {
        guard perfTestsEnabled else { return }
        let result = try runGPUBenchmark(
            function: "worley_fbm",
            kernelSource: "result = worley_fbm(wp * 3.0);"
        )
        guard let r = result else { return }
        reportAndLog(r, category: "noise", notes: "Worley-Perlin blend, 3D")
    }

    // MARK: - PBR tree

    @Test func bench_brdf_ggx_fullscreen() throws {
        guard perfTestsEnabled else { return }
        let result = try runGPUBenchmark(
            function: "brdf_ggx",
            kernelSource: """
            float3 L = normalize(float3(1,1,1));
            float3 V = float3(0,0,-1);
            float3 h = normalize(L + V);
            float NdotL = max(0.0, dot(n, L));
            float NdotV = max(0.0, dot(n, V));
            float VdotH = max(0.0, dot(V, h));
            float NdotH = max(0.0, dot(n, h));
            float rough = 0.4;
            float3 f0 = float3(0.04);
            result = brdf_ggx(NdotL, NdotV, NdotH, VdotH, rough, f0).x;
            """
        )
        guard let r = result else { return }
        reportAndLog(r, category: "pbr", notes: "Full Cook-Torrance GGX BRDF")
    }

    @Test func bench_sss_backlit_fullscreen() throws {
        guard perfTestsEnabled else { return }
        let result = try runGPUBenchmark(
            function: "sss_backlit",
            kernelSource: """
            float3 L = normalize(float3(1,1,1));
            float3 V = float3(0,0,-1);
            float3 col = sss_backlit(n, L, V, float3(0.6, 0.9, 0.3), 0.5, 0.8);
            result = col.x;
            """
        )
        guard let r = result else { return }
        reportAndLog(r, category: "pbr", notes: "SSS back-lit approximation")
    }

    @Test func bench_thinfilm_rgb_fullscreen() throws {
        guard perfTestsEnabled else { return }
        let result = try runGPUBenchmark(
            function: "thinfilm_rgb",
            kernelSource: """
            float3 iri = thinfilm_rgb(0.5, 300.0, 1.55, 1.0);
            result = iri.x + iri.y + iri.z;
            """
        )
        guard let r = result else { return }
        reportAndLog(r, category: "pbr", notes: "Thin-film interference RGB")
    }

    // MARK: - Geometry tree

    @Test func bench_ray_march_adaptive_fullscreen() throws {
        guard perfTestsEnabled else { return }
        let result = try runGPUBenchmark(
            function: "ray_march_adaptive",
            kernelSource: """
            float3 ro = float3(0, 0, -3);
            float3 rd = normalize(float3(uv * 2.0 - 1.0, 1.0));
            RayMarchHit hit = ray_march_adaptive(ro, rd, 0.001, 20.0, 64, 0.001, 0.85);
            result = hit.hit ? 1.0 : 0.0;
            """
        )
        guard let r = result else { return }
        reportAndLog(r, category: "geometry", notes: "Adaptive sphere tracer, 64 steps max")
    }

    @Test func bench_sdf_mandelbulb_fullscreen() throws {
        guard perfTestsEnabled else { return }
        let result = try runGPUBenchmark(
            function: "sd_mandelbulb_iterate",
            kernelSource: """
            float3 p = wp * 1.5;
            float dr = 1.0; float r = 0.0;
            result = sd_mandelbulb_iterate(p, 8.0, 6, dr, r);
            """
        )
        guard let r = result else { return }
        reportAndLog(r, category: "geometry", notes: "Mandelbulb iterate, n=8, 6 iters")
    }

    @Test func bench_hex_tile_fullscreen() throws {
        guard perfTestsEnabled else { return }
        let result = try runGPUBenchmark(
            function: "hex_tile_uv",
            kernelSource: """
            HexTileResult h = hex_tile_uv(uv * 4.0);
            result = h.uv.x;
            """
        )
        guard let r = result else { return }
        reportAndLog(r, category: "geometry", notes: "Hex tile UV (Mikkelsen, no textures)")
    }

    // MARK: - Volume tree

    @Test func bench_vol_density_fbm_fullscreen() throws {
        guard perfTestsEnabled else { return }
        let result = try runGPUBenchmark(
            function: "vol_density_fbm",
            kernelSource: "result = vol_density_fbm(wp * 2.0, 1.0, 3);"
        )
        guard let r = result else { return }
        reportAndLog(r, category: "volume", notes: "Volume density fBM, 3 octaves")
    }

    @Test func bench_hg_phase_fullscreen() throws {
        guard perfTestsEnabled else { return }
        let result = try runGPUBenchmark(
            function: "hg_phase",
            kernelSource: "result = hg_phase(0.7, 0.7);"
        )
        guard let r = result else { return }
        reportAndLog(r, category: "volume", notes: "Henyey-Greenstein phase function")
    }

    @Test func bench_cloud_density_cumulus_fullscreen() throws {
        guard perfTestsEnabled else { return }
        let result = try runGPUBenchmark(
            function: "cloud_density_cumulus",
            kernelSource: "result = cloud_density_cumulus(wp * 0.5, 0.6, t);"
        )
        guard let r = result else { return }
        reportAndLog(r, category: "volume", notes: "Cumulus cloud density field")
    }

    // MARK: - Texture tree

    @Test func bench_voronoi_f1f2_fullscreen() throws {
        guard perfTestsEnabled else { return }
        let result = try runGPUBenchmark(
            function: "voronoi_f1f2",
            kernelSource: """
            VoronoiResult v = voronoi_f1f2(uv * 4.0, 1.0);
            result = v.f1;
            """
        )
        guard let r = result else { return }
        reportAndLog(r, category: "texture", notes: "2D Voronoi F1+F2, 9-cell search")
    }

    @Test func bench_worley_cracks_fullscreen() throws {
        guard perfTestsEnabled else { return }
        let result = try runGPUBenchmark(
            function: "voronoi_cracks",
            kernelSource: "result = voronoi_cracks(uv * 3.0, 0.04);"
        )
        guard let r = result else { return }
        reportAndLog(r, category: "texture", notes: "Voronoi crack distance field")
    }

    @Test func bench_grunge_composite_fullscreen() throws {
        guard perfTestsEnabled else { return }
        let result = try runGPUBenchmark(
            function: "grunge_composite",
            kernelSource: """
            GrungeResult g = grunge_composite(uv * 2.0, t);
            result = g.value;
            """
        )
        guard let r = result else { return }
        reportAndLog(r, category: "texture", notes: "Composite grunge (scratches+rust+wear)")
    }

    @Test func bench_rd_animated_fullscreen() throws {
        guard perfTestsEnabled else { return }
        let result = try runGPUBenchmark(
            function: "rd_pattern_animated",
            kernelSource: """
            float2 rd = rd_pattern_animated(uv * 3.0, t);
            result = rd.x;
            """
        )
        guard let r = result else { return }
        reportAndLog(r, category: "texture", notes: "Reaction-diffusion animated approx")
    }

    // MARK: - Color tree

    @Test func bench_palette_fullscreen() throws {
        guard perfTestsEnabled else { return }
        let result = try runGPUBenchmark(
            function: "palette",
            kernelSource: """
            float3 col = palette(t * 0.1,
                float3(0.5), float3(0.5), float3(1,1,0.5), float3(0,0.33,0.67));
            result = col.x;
            """
        )
        guard let r = result else { return }
        reportAndLog(r, category: "color", notes: "IQ cosine palette (4-param)")
    }

    @Test func bench_tone_map_aces_fullscreen() throws {
        guard perfTestsEnabled else { return }
        let result = try runGPUBenchmark(
            function: "tone_map_aces",
            kernelSource: "result = tone_map_aces(float3(uv * 2.0, t)).x;"
        )
        guard let r = result else { return }
        reportAndLog(r, category: "color", notes: "ACES tone mapping (filmic)")
    }

    @Test func bench_chromatic_aberration_fullscreen() throws {
        guard perfTestsEnabled else { return }
        let result = try runGPUBenchmark(
            function: "chromatic_aberration_radial",
            kernelSource: """
            float3 col = chromatic_aberration_radial(float3(uv, 0.5), uv, 0.005);
            result = col.x;
            """
        )
        guard let r = result else { return }
        reportAndLog(r, category: "color", notes: "Chromatic aberration (radial)")
    }

    // MARK: - Materials cookbook

    @Test func bench_mat_polished_chrome_fullscreen() throws {
        guard perfTestsEnabled else { return }
        let result = try runGPUBenchmark(
            function: "mat_polished_chrome",
            kernelSource: """
            MaterialResult m = mat_polished_chrome(wp, n);
            result = m.roughness;
            """
        )
        guard let r = result else { return }
        reportAndLog(r, category: "materials", notes: "Polished chrome (fbm8 streak)")
    }

    @Test func bench_mat_marble_fullscreen() throws {
        guard perfTestsEnabled else { return }
        let result = try runGPUBenchmark(
            function: "mat_marble",
            kernelSource: """
            MaterialResult m = mat_marble(wp, n);
            result = m.albedo.x;
            """
        )
        guard let r = result else { return }
        reportAndLog(r, category: "materials", notes: "Marble (curl_noise + fbm8 veins)")
    }

    @Test func bench_mat_granite_fullscreen() throws {
        guard perfTestsEnabled else { return }
        let result = try runGPUBenchmark(
            function: "mat_granite",
            kernelSource: """
            MaterialResult m = mat_granite(wp, n);
            result = m.roughness;
            """
        )
        guard let r = result else { return }
        reportAndLog(r, category: "materials", notes: "Granite (worley_fbm + fbm8 + triplanar)")
    }

    @Test func bench_mat_ocean_fullscreen() throws {
        guard perfTestsEnabled else { return }
        let result = try runGPUBenchmark(
            function: "mat_ocean",
            kernelSource: """
            MaterialResult m = mat_ocean(wp, n, 0.5, 0.5);
            result = m.roughness;
            """
        )
        guard let r = result else { return }
        reportAndLog(r, category: "materials", notes: "Ocean water (fbm8 capillary ripple)")
    }
}

// MARK: - Helpers

private func reportAndLog(_ sample: PerformanceSample, category: String, notes: String) {
    let ms = sample.medianMicroseconds / 1000.0
    print("""
    [PERF] \(sample.function) | category=\(category) | \
    median=\(String(format: "%.2f", sample.medianMicroseconds))μs (\(String(format: "%.3f", ms))ms) | \
    min=\(String(format: "%.2f", sample.minMicroseconds))μs \
    max=\(String(format: "%.2f", sample.maxMicroseconds))μs | \
    n=\(sample.sampleCount) | \(notes)
    """)
}
