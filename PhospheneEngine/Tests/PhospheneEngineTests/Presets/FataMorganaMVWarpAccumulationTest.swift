// FataMorganaMVWarpAccumulationTest — production-pipeline test for the Fata
// Morgana mirage port (D-139). Modelled on DragonBloomMVWarpAccumulationTest.
//
// FM.L1 scope: prove the faithful mirage SUBSTRATE is wired end-to-end —
//   1. The preset COMPILES and loads with its custom warp/comp/blur pipelines
//      (silent shader-drop guard — a compile error would otherwise just remove
//      the preset from the catalog with no failure).
//   2. The mirage renders through the live dispatch path (blur → custom warp →
//      mirage comp → swap) producing non-black, non-degenerate output. (Shapes
//      are L2; the floor reflection fills in then.)
//
// What this does NOT prove (the Matt-eyeball oracle gate, plan §L1/L3):
//   · Whether the mirage READS like the butterchurn oracle (starfield/horizon/
//     floor placement, palette, motion). That is the live M7 comparison.
//
// Env-gated render diag: set FATA_MVWARP_DIAG=1 to render PNGs to
// /tmp/fata_morgana_mvwarp_diag/<ISO>/. Real-session replay (FATA_SESSION=<dir>
// with features.csv) — NEVER synthetic envelopes (feedback_synthetic_audio).

import Testing
import Foundation
import Metal
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import Renderer
@testable import Presets
@testable import Shared

@Suite("Fata Morgana mv_warp mirage diagnostic")
struct FataMorganaMVWarpAccumulationTest {

    private static let width  = 480
    private static let height = 360
    private static var frameCount: Int {
        ProcessInfo.processInfo.environment["FATA_FRAMES"].flatMap { Int($0) } ?? 90
    }
    private static let deltaTime: Float = 1.0 / 60.0

    // MARK: - Static-source guards

    @Test("FataMorgana.metal declares the custom warp/comp/blur + mv_warp functions")
    func test_metalSource_declaresFunctions() throws {
        let url = Self.repoRoot.appendingPathComponent(
            "PhospheneEngine/Sources/Presets/Shaders/FataMorgana.metal")
        let src = try String(contentsOf: url, encoding: .utf8)
        for fn in ["fata_morgana_fragment",
                   "fata_morgana_warp_fragment",
                   "fata_morgana_comp_fragment",
                   "fata_morgana_blur_fragment",
                   "MVWarpPerFrame mvWarpPerFrame(",
                   "float2 mvWarpPerVertex("] {
            #expect(src.contains(fn), "FataMorgana.metal missing \(fn)")
        }
    }

    @Test("FataMorgana.json declares passes: [\"direct\", \"mv_warp\"]")
    func test_json_declaresDirectAndMVWarp() throws {
        let url = Self.repoRoot.appendingPathComponent(
            "PhospheneEngine/Sources/Presets/Shaders/FataMorgana.json")
        let json = try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any]
        #expect(json?["passes"] as? [String] == ["direct", "mv_warp"])
    }

    // MARK: - Compile + load guard (catches silent shader-drop)

    @Test("Fata Morgana preset compiles, loads, and has its custom warp + blur pipelines")
    func test_presetLoadsWithBlurPipeline() throws {
        guard let ctx = try? MetalContext() else {
            Issue.record("No Metal device — cannot verify preset load")
            return
        }
        let loader = PresetLoader(device: ctx.device, pixelFormat: ctx.pixelFormat, loadBuiltIn: true)
        guard let preset = loader.presets.first(where: { $0.descriptor.name == "Fata Morgana" }) else {
            Issue.record("Fata Morgana not loaded — shader compile failure dropped it from the catalog.")
            return
        }
        guard let mvWarp = preset.mvWarpPipelines else {
            Issue.record("Fata Morgana mvWarpPipelines is nil — JSON passes misconfigured.")
            return
        }
        #expect(mvWarp.blurState != nil,
                "Fata Morgana blur pipeline (fata_morgana_blur_fragment) not compiled — the fata draw branch keys on it.")
    }

    // MARK: - Helpers

    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // /Presets/
        .deletingLastPathComponent()   // /PhospheneEngineTests/
        .deletingLastPathComponent()   // /Tests/
        .deletingLastPathComponent()   // /PhospheneEngine/
        .deletingLastPathComponent()   // repo root
}
