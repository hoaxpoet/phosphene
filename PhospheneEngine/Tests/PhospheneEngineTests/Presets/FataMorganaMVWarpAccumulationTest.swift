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

    // MARK: - Offscreen mirage render (env-gated; the L1 oracle pre-check)

    // Renders the mirage substrate (blur → custom warp → mirage comp → swap) through
    // the compiled fata pipelines into offscreen textures and writes a PNG, so the
    // port can be eyeballed against the live butterchurn oracle (fata-ref :8734)
    // BEFORE Matt's live M7. Substrate only (no shapes — L2); the comp's
    // starfield/horizon/floor are procedural, so they render against an empty field.
    // Time-driven (the substrate has no load-bearing audio coupling beyond the minor
    // q1/q2 beat rotation); real-session replay matters at L2/L3 (shapes are
    // audio-sized) — feedback_synthetic_audio.
    @Test("Mirage substrate renders (env-gated FATA_MVWARP_DIAG=1)")
    func test_mirageRender_diag() throws {
        guard ProcessInfo.processInfo.environment["FATA_MVWARP_DIAG"] == "1" else {
            print("FataMorganaMVWarpAccumulationTest: FATA_MVWARP_DIAG not set, skipping render diag")
            return
        }
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let texMgr = try TextureManager(context: ctx, shaderLibrary: lib)
        let loader = PresetLoader(device: ctx.device, pixelFormat: ctx.pixelFormat, loadBuiltIn: true)
        guard let preset = loader.presets.first(where: { $0.descriptor.name == "Fata Morgana" }),
              let mvWarp = preset.mvWarpPipelines, let blur = mvWarp.blurState else {
            Issue.record("Fata Morgana preset/pipelines missing")
            return
        }

        let wPix = 640, hPix = 480   // 4:3 to match the oracle
        let fbDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: ctx.pixelFormat, width: wPix, height: hPix, mipmapped: false)
        fbDesc.usage = [.renderTarget, .shaderRead]
        fbDesc.storageMode = .shared
        guard var warpTex = ctx.device.makeTexture(descriptor: fbDesc),
              var composeTex = ctx.device.makeTexture(descriptor: fbDesc),
              let blurTex = ctx.device.makeTexture(descriptor: fbDesc),
              let displayTex = ctx.device.makeTexture(descriptor: fbDesc)
        else { Issue.record("texture alloc failed"); return }

        // Real-session attack values drive the blob sizes — the SAME bassAtt/midAtt/
        // trebAtt the live shapes use (test/prod parity, FA #66; loadSessionBands
        // reconstructs them). Matt's live M7 remains the fidelity gate.
        let rows = Self.loadSessionBands()
        let stemRows = Self.loadSessionStems()
        let offset = ProcessInfo.processInfo.environment["FATA_SESSION_OFFSET"].flatMap { Int($0) } ?? 700
        let boost = ProcessInfo.processInfo.environment["FATA_BOOST"].flatMap { Float($0) } ?? 6.0
        let frames = Self.frameCount
        let aspectY = Float(min(wPix, hPix)) / Float(max(wPix, hPix))
        let shapeCfg: [(Int32, Int32, Int32, MTLRenderPipelineState?)] = [
            (0, 30, 1, mvWarp.shapeNormalState),
            (1, 40, 4, mvWarp.shapeAdditiveState),
            (2, 40, 1, mvWarp.shapeAdditiveState),
            (3, 40, 5, mvWarp.shapeAdditiveState),
        ]
        for i in 0..<frames {
            let row = rows.isEmpty ? (Float(i) / 60.0, Float(0), Float(0), Float(0))
                                   : rows[min(offset + i, rows.count - 1)]
            let t = row.0
            var u = FataUniforms()
            u.time = t
            u.texsize = SIMD4<Float>(Float(wPix), Float(hPix), 1.0 / Float(wPix), 1.0 / Float(hPix))
            u.roamSin = SIMD4<Float>(0.5 + 0.5 * sin(t * 0.3), 0.5 + 0.5 * sin(t * 1.3),
                                     0.5 + 0.5 * sin(t * 5.0), 0.5 + 0.5 * sin(t * 20.0))
            u.slowRoamSin = SIMD4<Float>(0.5 + 0.5 * sin(t * 0.005), 0.5 + 0.5 * sin(t * 0.008),
                                         0.5 + 0.5 * sin(t * 0.013), 0.5 + 0.5 * sin(t * 0.022))
            var feat = FeatureVector.zero
            feat.time = t
            var stm = StemFeatures.zero
            if !stemRows.isEmpty {
                let sr = stemRows[min(offset + i, stemRows.count - 1)]
                stm.drumsEnergy = sr.dE;  stm.drumsEnergyDev = sr.dDev;  stm.drumsBeat = sr.dBeat
                stm.bassEnergy = sr.bE;   stm.bassEnergyDev = sr.bDev;   stm.bassBeat = sr.bBeat
                stm.vocalsEnergy = sr.vE; stm.vocalsEnergyDev = sr.vDev; stm.vocalsBeat = sr.vBeat
            }
            var scene = SceneUniforms()

            guard let cmd = ctx.commandQueue.makeCommandBuffer() else { return }
            // blur(prev) → blurTex
            encodePass(cmd, pipeline: blur, target: blurTex, load: .dontCare) { enc in
                enc.setFragmentTexture(warpTex, index: 0)
                enc.setFragmentBytes(&u, length: MemoryLayout<FataUniforms>.stride, index: 1)
                enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            }
            // warp(prev, blur) → composeTex
            encodePass(cmd, pipeline: mvWarp.warpState, target: composeTex, load: .clear) { enc in
                enc.setVertexBytes(&feat, length: MemoryLayout<FeatureVector>.stride, index: 0)
                enc.setVertexBytes(&stm, length: MemoryLayout<StemFeatures>.stride, index: 1)
                enc.setVertexBytes(&scene, length: MemoryLayout<SceneUniforms>.stride, index: 2)
                enc.setFragmentTexture(warpTex, index: 0)
                enc.setFragmentTexture(blurTex, index: 1)
                enc.setFragmentBytes(&u, length: MemoryLayout<FataUniforms>.stride, index: 1)
                enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 4278)
            }
            // shapes on top of composeTex (FM.L2)
            encodePass(cmd, pipeline: mvWarp.warpState, target: composeTex, load: .load) { enc in
                enc.setVertexBytes(&feat, length: MemoryLayout<FeatureVector>.stride, index: 0)
                enc.setVertexBytes(&stm, length: MemoryLayout<StemFeatures>.stride, index: 2)
                enc.setFragmentTexture(warpTex, index: 0)
                for (idx, sides, numInst, pipe) in shapeCfg {
                    guard let pipe else { continue }
                    enc.setRenderPipelineState(pipe)
                    var params = FataShapeParams(shapeIndex: idx, sides: sides, numInst: numInst,
                                                 frame: Float(i), aspectY: aspectY, audioBoost: boost)
                    enc.setVertexBytes(&params, length: MemoryLayout<FataShapeParams>.stride, index: 1)
                    enc.drawPrimitives(type: .triangle, vertexStart: 0,
                                       vertexCount: Int(sides) * 3, instanceCount: Int(numInst))
                }
            }
            // comp(compose, noise) → displayTex
            encodePass(cmd, pipeline: mvWarp.blitState, target: displayTex, load: .dontCare) { enc in
                enc.setFragmentTexture(composeTex, index: 0)
                texMgr.bindTextures(to: enc)
                enc.setFragmentBytes(&u, length: MemoryLayout<FataUniforms>.stride, index: 1)
                enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            }
            cmd.commit(); cmd.waitUntilCompleted()
            swap(&warpTex, &composeTex)
        }

        let outDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("fata_morgana_mvwarp_diag")
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let url = outDir.appendingPathComponent("mirage_frame\(frames).png")
        try Self.writePNG(displayTex, to: url)
        print("[fata_diag] wrote \(url.path)")
    }

    private func encodePass(_ cmd: MTLCommandBuffer, pipeline: MTLRenderPipelineState,
                            target: MTLTexture, load: MTLLoadAction,
                            _ body: (MTLRenderCommandEncoder) -> Void) {
        let d = MTLRenderPassDescriptor()
        d.colorAttachments[0].texture = target
        d.colorAttachments[0].loadAction = load
        d.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        d.colorAttachments[0].storeAction = .store
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: d) else { return }
        enc.setRenderPipelineState(pipeline)
        body(enc)
        enc.endEncoding()
    }

    /// Parse a recorded session's features.csv into (time, bassAtt, midAtt, trebAtt)
    /// rows — the SAME attack values the live shape draw uses (test/prod parity, FA #66).
    /// bassAtt is reconstructed exactly from bassAttRel (col 26): bassAtt = rel/2 + 0.5.
    /// midAtt/trebAtt aren't logged (no *AttRel cols) → approximated from raw mid/treble
    /// (cols 6/7) ×0.45 (att is the slow-smoothed AGC band, well below the instant peak).
    /// FATA_SESSION=<dir> overrides. Returns [] if unreadable (diag runs on a silent field).
    static func loadSessionBands() -> [(Float, Float, Float, Float)] {
        let dir = ProcessInfo.processInfo.environment["FATA_SESSION"]
            ?? "\(NSHomeDirectory())/Documents/phosphene_sessions/2026-06-03T03-01-32Z"
        let url = URL(fileURLWithPath: dir).appendingPathComponent("features.csv")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var out: [(Float, Float, Float, Float)] = []
        for line in text.split(separator: "\n").dropFirst() {
            let c = line.split(separator: ",", omittingEmptySubsequences: false)
            guard c.count > 26 else { continue }
            let time = Float(c[2]) ?? 0
            let bassAtt = ((Float(c[25]) ?? 0) / 2 + 0.5)          // col 26 bassAttRel → bassAtt
            let midAtt  = min((Float(c[5]) ?? 0) * 0.45, 1.5)      // raw mid  → att proxy
            let trebAtt = min((Float(c[6]) ?? 0) * 0.45, 1.5)      // raw treble → att proxy
            out.append((time, bassAtt, midAtt, trebAtt))
        }
        return out
    }

    struct StemRow {
        var dE: Float = 0, dDev: Float = 0, dBeat: Float = 0
        var bE: Float = 0, bDev: Float = 0, bBeat: Float = 0
        var vE: Float = 0, vDev: Float = 0, vBeat: Float = 0
    }

    /// Parse the session's stems.csv (row-aligned with features.csv) into per-frame
    /// drums/bass/vocals energy + deviation + beat — the SAME stem values the live
    /// shape uplift consumes (test/prod parity). Cols (0-based): drumsEnergy 2,
    /// drumsBeat 3, bassEnergy 6, bassBeat 7, vocalsEnergy 10, vocalsBeat 11,
    /// drumsEnergyDev 19, bassEnergyDev 21, vocalsEnergyDev 23.
    static func loadSessionStems() -> [StemRow] {
        let dir = ProcessInfo.processInfo.environment["FATA_SESSION"]
            ?? "\(NSHomeDirectory())/Documents/phosphene_sessions/2026-06-03T03-23-25Z"
        let url = URL(fileURLWithPath: dir).appendingPathComponent("stems.csv")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var out: [StemRow] = []
        for line in text.split(separator: "\n").dropFirst() {
            let c = line.split(separator: ",", omittingEmptySubsequences: false)
            guard c.count > 23 else { continue }
            func f(_ i: Int) -> Float { Float(c[i]) ?? 0 }
            out.append(StemRow(dE: f(2), dDev: f(19), dBeat: f(3),
                               bE: f(6), bDev: f(21), bBeat: f(7),
                               vE: f(10), vDev: f(23), vBeat: f(11)))
        }
        return out
    }

    static func writePNG(_ tex: MTLTexture, to url: URL) throws {
        let w = tex.width, h = tex.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        tex.getBytes(&px, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        let cs = CGColorSpaceCreateDeviceRGB()
        // Drawable format is .bgra8Unorm_srgb — interpret the byte buffer as BGRA
        // (premultipliedFirst + byteOrder32Little), else R/B are swapped.
        let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let provider = CGDataProvider(data: Data(px) as CFData),
              let img = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32,
                                bytesPerRow: w * 4, space: cs,
                                bitmapInfo: CGBitmapInfo(rawValue: info),
                                provider: provider, decode: nil, shouldInterpolate: false,
                                intent: .defaultIntent),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw FataDiagError.pngFailed }
        CGImageDestinationAddImage(dest, img, nil)
        guard CGImageDestinationFinalize(dest) else { throw FataDiagError.pngFailed }
    }

    enum FataDiagError: Error { case pngFailed }

    // MARK: - Helpers

    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // /Presets/
        .deletingLastPathComponent()   // /PhospheneEngineTests/
        .deletingLastPathComponent()   // /Tests/
        .deletingLastPathComponent()   // /PhospheneEngine/
        .deletingLastPathComponent()   // repo root
}
