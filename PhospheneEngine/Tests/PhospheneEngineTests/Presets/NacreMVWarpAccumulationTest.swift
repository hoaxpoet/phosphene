// NacreMVWarpAccumulationTest — Nacre ($$$ Royal - Mashup (431) port) production-pipeline test.
//
// Modelled on FataMorgana/DragonBloom MVWarpAccumulationTest. Per the preset session
// checklist (and the AV.1 failure it cites): a preset with a temporal feedback contract
// must be tested on the SAME dispatch path the live app uses (warp → comp → swap), not
// just single-frame `pipelineState` checks.
//
// ── NACRE.2b ───────────────────────────────────────────────────────────────────
//   1. Static guards: the .metal declares the scene + warp + comp + mv_warp fns; the
//      .json declares the right passes (cheap regression sentries; catch silent drop).
//   2. Compile/load guard: the preset loads with its custom warp + comp pipelines
//      (a compile error would silently remove it from the catalog).
//   3. Accumulation gate (ALWAYS run): drive `renderNacre` for ≥60 frames at silence
//      through the live dispatch path and assert the field stays NON-BLACK (D-019 warmup
//      — the seed sustains it) and never WHITES OUT (the HDR-feedback trip-wire).
//   4. Env-gated PNG diag (NACRE_MVWARP_DIAG=1): higher-res contact frames + optional
//      real-session replay (NACRE_SESSION=<dir> with features.csv) — NEVER synthetic
//      envelopes (FA #27). Absent fixtures → silence (worktree-safe).

import Testing
import Foundation
import Metal
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import Renderer
@testable import Presets
@testable import Shared

@Suite("Nacre mv_warp port (NACRE.2b)")
struct NacreMVWarpAccumulationTest {

    private static let deltaTime: Float = 1.0 / 60.0

    // MARK: - Static-source guards (cheap regression sentries; no GPU)

    @Test("Nacre.metal declares the scene, custom warp, custom comp, and both mv_warp functions")
    func test_metalSource_declaresRequiredFunctions() throws {
        let src = try String(contentsOf: Self.shaderURL("Nacre.metal"), encoding: .utf8)
        for fn in ["nacre_fragment(",
                   "nacre_warp_fragment(",
                   "nacre_comp_fragment(",
                   "MVWarpPerFrame mvWarpPerFrame(",
                   "float2 mvWarpPerVertex("] {
            #expect(src.contains(fn), "Nacre.metal missing \(fn)")
        }
    }

    @Test("Nacre.json declares passes: [\"direct\", \"mv_warp\"]")
    func test_json_declaresDirectAndMVWarp() throws {
        let data = try Data(contentsOf: Self.shaderURL("Nacre.json"))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["passes"] as? [String] == ["direct", "mv_warp"],
                "Nacre.json must declare passes: [\"direct\", \"mv_warp\"].")
        #expect((json?["fragment_function"] as? String) == "nacre_fragment",
                "Nacre.json fragment_function must be nacre_fragment (drives nacre_* warp/comp auto-selection).")
    }

    // MARK: - Compile + custom-comp wiring (GPU; worktree-runnable — no external fixtures)

    @Test("Nacre loads and its mv_warp pipelines compile (custom warp + comp auto-selected)")
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

    // MARK: - Accumulation gate (ALWAYS run): live dispatch path, non-black + no white-out

    @Test("Nacre field stays alive (non-black) and never whites out over 64 silence frames")
    @MainActor
    func test_accumulation_silenceStaysAliveNoWhiteout() throws {
        guard let ctx = try? MetalContext() else {
            Issue.record("No Metal device — cannot run the accumulation gate"); return
        }
        let w = 192, h = 128
        guard let display = try Self.runNacre(ctx: ctx, width: w, height: h, frames: 64, session: nil, energy: 0) else {
            Issue.record("Nacre render setup failed"); return
        }
        let stats = Self.frameStats(display)
        // Non-black: the palette-tinted core seed + grain sustain the field at silence
        // (D-019). A dead-black result means the warp starved or the seed isn't reaching.
        #expect(stats.meanLuma > 0.01,
                "Nacre silence field is ~black (meanLuma \(stats.meanLuma)) — the seed/feedback isn't sustaining.")
        // No white-out: the HDR-feedback trip-wire (kickoff §0.5/§6). A field where most
        // pixels saturate has over-accumulated → fall back to 8-bit or lower grain/decay.
        #expect(stats.saturatedFraction < 0.85,
                "Nacre field whites out (\(Int(stats.saturatedFraction * 100))% saturated) — over-accumulation.")
    }

    // MARK: - Env-gated PNG diag (the M7 pre-check; render BEFORE tuning)

    @Test("Nacre render diag (env-gated NACRE_MVWARP_DIAG=1)")
    @MainActor
    func test_nacreRender_diag() throws {
        guard ProcessInfo.processInfo.environment["NACRE_MVWARP_DIAG"] == "1" else {
            print("NacreMVWarpAccumulationTest: NACRE_MVWARP_DIAG not set, skipping render diag")
            return
        }
        let ctx = try MetalContext()
        let wPix = ProcessInfo.processInfo.environment["NACRE_W"].flatMap { Int($0) } ?? 1280
        let hPix = ProcessInfo.processInfo.environment["NACRE_H"].flatMap { Int($0) } ?? 720
        let frames = ProcessInfo.processInfo.environment["NACRE_FRAMES"].flatMap { Int($0) } ?? 120
        let session = ProcessInfo.processInfo.environment["NACRE_SESSION"]
        // DEV PREVIEW ONLY (not a faithfulness/pipeline claim — FA #27): with no real
        // session in the worktree, NACRE_ENERGY injects a constant band energy so the
        // volume-gated core can be eyeballed. Real-audio behaviour is Matt's live M7.
        let energy = ProcessInfo.processInfo.environment["NACRE_ENERGY"].flatMap { Float($0) } ?? 0
        guard let display = try Self.runNacre(ctx: ctx, width: wPix, height: hPix,
                                              frames: frames, session: session, energy: energy) else {
            Issue.record("Nacre render setup failed"); return
        }
        let outDir = FileManager.default.temporaryDirectory.appendingPathComponent("nacre_mvwarp_diag")
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let url = outDir.appendingPathComponent("nacre_frame\(frames).png")
        try Self.writePNG(display, to: url)
        print("[nacre_diag] wrote \(url.path) (\(wPix)×\(hPix), \(frames) frames, session=\(session ?? "silence"))")
    }

    // MARK: - Shared render driver (live dispatch path — FA #66, no reimplemented encode)

    /// Drive the REAL `RenderPipeline.renderNacre` for `frames` frames into an offscreen
    /// drawable-format texture and return it. Real-session replay if `session` resolves a
    /// features.csv; otherwise silence (worktree-safe). Returns nil on setup failure.
    @MainActor
    static func runNacre(ctx: MetalContext, width: Int, height: Int, frames: Int,
                         session: String?, energy: Float) throws -> MTLTexture? {
        let lib = try ShaderLibrary(context: ctx)
        let texMgr = try TextureManager(context: ctx, shaderLibrary: lib)
        let floatStride = MemoryLayout<Float>.stride
        guard let fft = ctx.makeSharedBuffer(length: 512 * floatStride),
              let wav = ctx.makeSharedBuffer(length: 2048 * floatStride) else { return nil }
        let pipeline = try RenderPipeline(context: ctx, shaderLibrary: lib, fftBuffer: fft, waveformBuffer: wav)
        pipeline.setTextureManager(texMgr)
        let loader = PresetLoader(device: ctx.device, pixelFormat: ctx.pixelFormat, loadBuiltIn: true)
        guard let preset = loader.presets.first(where: { $0.descriptor.name == "Nacre" }),
              let mvWarp = preset.mvWarpPipelines else { return nil }

        let size = CGSize(width: width, height: height)
        pipeline.currentDrawableSize = size
        // Feedback in HDR .rgba16Float (matches PresetLoader.feedbackFormat for Nacre);
        // the comp target stays the drawable format. isNacre routes the draw branch.
        let bundle = MVWarpPipelineBundle(
            warpState: mvWarp.warpState,
            composeState: mvWarp.composeState,
            blitState: mvWarp.blitState,
            pixelFormat: ctx.pixelFormat,
            feedbackFormat: .rgba16Float,
            isNacre: true)
        pipeline.setupMVWarp(bundle: bundle, size: size)
        pipeline.setMVWarpDecay(preset.descriptor.decay)

        let fbDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: ctx.pixelFormat, width: width, height: height, mipmapped: false)
        fbDesc.usage = [.renderTarget, .shaderRead]
        fbDesc.storageMode = .shared
        guard let display = ctx.device.makeTexture(descriptor: fbDesc) else { return nil }

        let rows = session.flatMap { loadSessionBands(dir: $0) } ?? []
        for i in 0..<frames {
            var feat = FeatureVector.zero
            feat.deltaTime = deltaTime
            if rows.isEmpty {
                feat.time = Float(i) * deltaTime
                feat.bass = energy; feat.mid = energy; feat.treble = energy   // dev preview only
                feat.midRel = energy; feat.bassDev = energy; feat.trebDev = energy
            } else {
                let r = rows[min(i, rows.count - 1)]
                feat.time = r.t; feat.bass = r.bass; feat.mid = r.mid; feat.treble = r.treble
                feat.midRel = r.midRel; feat.bassDev = r.bassDev; feat.trebDev = r.trebleDev
            }
            guard let cmd = ctx.commandQueue.makeCommandBuffer(),
                  let warpState = pipeline.mvWarpState else { return display }
            pipeline.renderNacre(commandBuffer: cmd, features: feat, stemFeatures: .zero,
                                 warpState: warpState, target: display)
            cmd.commit(); cmd.waitUntilCompleted()
        }
        return display
    }

    // MARK: - Frame analysis

    struct FrameStats { var meanLuma: Float; var saturatedFraction: Float }

    /// Mean luma + fraction of near-saturated pixels of an 8-bit BGRA target.
    static func frameStats(_ tex: MTLTexture) -> FrameStats {
        let w = tex.width, h = tex.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        tex.getBytes(&px, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        var lumaSum: Double = 0, sat = 0
        for i in stride(from: 0, to: px.count, by: 4) {
            let b = Float(px[i]) / 255, g = Float(px[i + 1]) / 255, r = Float(px[i + 2]) / 255
            let luma = 0.299 * r + 0.587 * g + 0.114 * b
            lumaSum += Double(luma)
            if r > 0.96 && g > 0.96 && b > 0.96 { sat += 1 }
        }
        let n = w * h
        return FrameStats(meanLuma: Float(lumaSum / Double(n)), saturatedFraction: Float(sat) / Float(n))
    }

    // MARK: - Session replay (real audio; absent in worktrees → silence)

    struct BandRow { var t: Float; var bass: Float; var mid: Float; var treble: Float
                     var midRel: Float; var bassDev: Float; var trebleDev: Float }

    /// Parse a recorded session's features.csv → (time, raw bands, the deviation
    /// primitives Nacre drives from). Cols match FataMorganaMVWarpAccumulationTest's
    /// reader: time 2, mid 5, treble 6 (raw); bassAttRel 25 → bassDev proxy. midRel/
    /// trebleDev aren't logged → approximated from raw bands (att proxy). Returns [] if
    /// unreadable.
    static func loadSessionBands(dir: String) -> [BandRow] {
        let url = URL(fileURLWithPath: dir).appendingPathComponent("features.csv")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var out: [BandRow] = []
        for line in text.split(separator: "\n").dropFirst() {
            let c = line.split(separator: ",", omittingEmptySubsequences: false)
            guard c.count > 25 else { continue }
            let t = Float(c[2]) ?? 0
            let mid = Float(c[5]) ?? 0, treble = Float(c[6]) ?? 0
            let bassDev = Float(c[25]) ?? 0
            out.append(BandRow(t: t, bass: 0, mid: mid, treble: treble,
                               midRel: min(mid, 1.5), bassDev: max(0, bassDev), trebleDev: min(treble, 1.5)))
        }
        return out
    }

    // MARK: - PNG writer (8-bit BGRA target; reused from the FM diag)

    static func writePNG(_ tex: MTLTexture, to url: URL) throws {
        let w = tex.width, h = tex.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        tex.getBytes(&px, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        let cs = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let provider = CGDataProvider(data: Data(px) as CFData),
              let img = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32,
                                bytesPerRow: w * 4, space: cs,
                                bitmapInfo: CGBitmapInfo(rawValue: info),
                                provider: provider, decode: nil, shouldInterpolate: false,
                                intent: .defaultIntent),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw NacreDiagError.pngFailed }
        CGImageDestinationAddImage(dest, img, nil)
        guard CGImageDestinationFinalize(dest) else { throw NacreDiagError.pngFailed }
    }

    enum NacreDiagError: Error { case pngFailed }

    // MARK: - Helpers

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
