// NacreMVWarpAccumulationTest — Nacre ($$$ Royal - Mashup (431) uplift) production-pipeline test.
//
// Modelled on DragonBloomMVWarpAccumulationTest / AuroraVeilMVWarpAccumulationTest. Per the
// preset session checklist (and the AV.1 failure mode it cites): any preset with a temporal
// feedback contract must be tested on the SAME dispatch path the live app uses
// (scene → warp → compose → blit → swap), not just single-frame `pipelineState` checks.
//
// ── INCREMENT STATUS ──────────────────────────────────────────────────────────
// NACRE.2a (THIS FILE, current): prove the custom-comp path is REACHABLE + COMPILES —
//   (1) the .metal declares all four required functions (scene + the two mv_warp fns +
//   the custom comp fragment), (2) the .json declares the right passes, and (3) the
//   preset loads and its mv_warp pipelines compile (which means `nacre_comp_fragment`
//   was auto-selected by PresetLoader's naming convention and the MSL is valid).
// NACRE.2b (next): ADD the multi-frame accumulation loop here FIRST — drive
//   `renderMVWarpToTexture` for ≥60 frames at silence (+ synthetic music), read the
//   final frame back, and assert the field stays non-black and never whites out — BEFORE
//   porting the look shaders (the harness-before-shader-work rule). Adapt the loop from
//   DragonBloomMVWarpAccumulationTest.runAccumulationLoop / RenderPipeline.renderMVWarpToTexture.

import Testing
import Foundation
import Metal
@testable import Renderer
@testable import Presets
@testable import Shared

@Suite("Nacre mv_warp wiring (NACRE.2a)")
struct NacreMVWarpAccumulationTest {

    // MARK: - Static-source guards (cheap regression sentries; no GPU)

    @Test("Nacre.metal declares the scene fragment, both mv_warp functions, and the custom comp")
    func test_metalSource_declaresRequiredFunctions() throws {
        let src = try String(contentsOf: Self.shaderURL("Nacre.metal"), encoding: .utf8)
        #expect(src.contains("nacre_fragment("),
                "Nacre.metal missing nacre_fragment scene entry point.")
        #expect(src.contains("MVWarpPerFrame mvWarpPerFrame("),
                "Nacre.metal missing mvWarpPerFrame implementation (D-027 contract).")
        #expect(src.contains("float2 mvWarpPerVertex("),
                "Nacre.metal missing mvWarpPerVertex implementation (D-027 contract).")
        #expect(src.contains("nacre_comp_fragment("),
                "Nacre.metal missing nacre_comp_fragment — the custom display-stage comp the look lives in.")
    }

    @Test("Nacre.json declares passes: [\"direct\", \"mv_warp\"]")
    func test_json_declaresDirectAndMVWarp() throws {
        let data = try Data(contentsOf: Self.shaderURL("Nacre.json"))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let passes = json?["passes"] as? [String]
        #expect(passes == ["direct", "mv_warp"],
                "Nacre.json must declare passes: [\"direct\", \"mv_warp\"].")
        #expect((json?["fragment_function"] as? String) == "nacre_fragment",
                "Nacre.json fragment_function must be nacre_fragment (drives the nacre_* comp/warp auto-selection).")
    }

    // MARK: - Compile + custom-comp wiring (GPU; worktree-runnable — no external fixtures)

    @Test("Nacre loads and its mv_warp pipelines compile (custom comp auto-selected)")
    func test_presetCompilesAndWiresCustomComp() throws {
        let ctx = try MetalContext()
        let loader = PresetLoader(device: ctx.device, pixelFormat: ctx.pixelFormat, loadBuiltIn: true)
        guard let preset = loader.presets.first(where: { $0.descriptor.name == "Nacre" }) else {
            Issue.record("Nacre preset not loaded — Nacre.metal failed to compile, or the bundle resource wasn't copied.")
            return
        }
        #expect(preset.descriptor.passes.contains(.mvWarp),
                "Nacre descriptor must include the mv_warp pass.")
        #expect(preset.mvWarpPipelines != nil,
                "Nacre.mvWarpPipelines is nil — the .metal failed to compile (incl. nacre_comp_fragment) or passes are misconfigured.")
    }

    // MARK: - Helpers

    /// Repo-relative path to a file under Sources/Presets/Shaders (5 levels up from this test file).
    private static func shaderURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // /Presets/
            .deletingLastPathComponent()   // /PhospheneEngineTests/
            .deletingLastPathComponent()   // /Tests/
            .deletingLastPathComponent()   // /PhospheneEngine/
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("PhospheneEngine/Sources/Presets/Shaders/\(name)")
    }
}
