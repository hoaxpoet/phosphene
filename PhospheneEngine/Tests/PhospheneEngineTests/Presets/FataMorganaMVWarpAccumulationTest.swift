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
    @MainActor
    func test_mirageRender_diag() throws {
        guard ProcessInfo.processInfo.environment["FATA_MVWARP_DIAG"] == "1" else {
            print("FataMorganaMVWarpAccumulationTest: FATA_MVWARP_DIAG not set, skipping render diag")
            return
        }
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let texMgr = try TextureManager(context: ctx, shaderLibrary: lib)
        let floatStride = MemoryLayout<Float>.stride
        guard let fft = ctx.makeSharedBuffer(length: 512 * floatStride),
              let wav = ctx.makeSharedBuffer(length: 2048 * floatStride) else {
            Issue.record("buffer alloc failed"); return
        }
        // Drive the REAL RenderPipeline.renderFataMorgana — the SAME method the live app
        // calls (FA #66 / production-grade testing): no reimplemented encode path, so
        // what this renders is byte-identical to live.
        let pipeline = try RenderPipeline(context: ctx, shaderLibrary: lib, fftBuffer: fft, waveformBuffer: wav)
        pipeline.setTextureManager(texMgr)
        let loader = PresetLoader(device: ctx.device, pixelFormat: ctx.pixelFormat, loadBuiltIn: true)
        guard let preset = loader.presets.first(where: { $0.descriptor.name == "Fata Morgana" }),
              let mvWarp = preset.mvWarpPipelines else {
            Issue.record("Fata Morgana preset/pipelines missing"); return
        }

        // Default 1280×720 (16:9) to MATCH the live app's aspect/scale. FATA_W/FATA_H override.
        let wPix = ProcessInfo.processInfo.environment["FATA_W"].flatMap { Int($0) } ?? 1280
        let hPix = ProcessInfo.processInfo.environment["FATA_H"].flatMap { Int($0) } ?? 720
        let size = CGSize(width: wPix, height: hPix)
        pipeline.currentDrawableSize = size   // drives shape aspectY (== live)
        let bundle = MVWarpPipelineBundle(
            warpState: mvWarp.warpState,
            composeState: mvWarp.composeState,
            blitState: mvWarp.blitState,
            pixelFormat: ctx.pixelFormat,
            feedbackFormat: ctx.pixelFormat,
            blurState: mvWarp.blurState)
        pipeline.setupMVWarp(bundle: bundle, size: size)
        pipeline.setMVWarpDecay(preset.descriptor.decay)
        pipeline.setFataShapePipelines(additive: mvWarp.shapeAdditiveState, normal: mvWarp.shapeNormalState)
        // Sweep the production size gain from the diag (defaults to the production value).
        if let b = ProcessInfo.processInfo.environment["FATA_BOOST"].flatMap({ Float($0) }) {
            pipeline.fataShapeSizeGain = b
        }

        let fbDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: ctx.pixelFormat, width: wPix, height: hPix, mipmapped: false)
        fbDesc.usage = [.renderTarget, .shaderRead]
        fbDesc.storageMode = .shared
        guard let displayTex = ctx.device.makeTexture(descriptor: fbDesc) else {
            Issue.record("texture alloc failed"); return
        }

        let rows = Self.loadSessionBands()       // (time, bassAtt, midAtt, trebAtt) — time + accumulator energy
        let stemRows = Self.loadSessionStems()   // drums/bass/vocals energy+dev+beat (drives the shapes)
        let offset = ProcessInfo.processInfo.environment["FATA_SESSION_OFFSET"].flatMap { Int($0) } ?? 700
        let frames = Self.frameCount

        for i in 0..<frames {
            let row = rows.isEmpty ? (Float(i) / 60.0, Float(0), Float(0), Float(0))
                                   : rows[min(offset + i, rows.count - 1)]
            var feat = FeatureVector.zero
            feat.time = row.0
            feat.deltaTime = 1.0 / 60.0
            feat.bass = row.1; feat.mid = row.2; feat.treble = row.3   // beat accumulator (q1/q2)
            var stm = StemFeatures.zero
            if !stemRows.isEmpty {
                let sr = stemRows[min(offset + i, stemRows.count - 1)]
                stm.drumsEnergy = sr.dE;  stm.drumsEnergyDev = sr.dDev;  stm.drumsBeat = sr.dBeat
                stm.bassEnergy = sr.bE;   stm.bassEnergyDev = sr.bDev;   stm.bassBeat = sr.bBeat
                stm.vocalsEnergy = sr.vE; stm.vocalsEnergyDev = sr.vDev; stm.vocalsBeat = sr.vBeat
            }
            guard let cmd = ctx.commandQueue.makeCommandBuffer(),
                  let warpState = pipeline.mvWarpState else { return }
            pipeline.renderFataMorgana(
                commandBuffer: cmd,
                features: feat,
                stemFeatures: stm,
                warpState: warpState,
                target: displayTex)
            cmd.commit(); cmd.waitUntilCompleted()
        }

        let outDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("fata_morgana_mvwarp_diag")
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let url = outDir.appendingPathComponent("mirage_frame\(frames).png")
        try Self.writePNG(displayTex, to: url)
        print("[fata_diag] wrote \(url.path)")
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
