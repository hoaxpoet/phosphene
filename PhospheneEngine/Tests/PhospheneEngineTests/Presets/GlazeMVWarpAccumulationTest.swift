// GlazeMVWarpAccumulationTest — Glaze (jelly showoff parade port) production-pipeline test.
//
// Modelled on NacreMVWarpAccumulationTest. Per the preset session checklist: a preset with
// a temporal feedback contract must be tested on the SAME dispatch path the live app uses
// (warp → comp → swap), not single-frame `pipelineState` checks.
//
// ── GLAZE.2a (STUB) ─────────────────────────────────────────────────────────────────
//   1. Static guards: the .metal declares scene + warp + comp + mv_warp fns; the .json
//      declares the right passes (cheap regression sentries against a silent drop).
//   2. Compile/load guard: the preset loads with its custom warp + comp pipelines.
//   3. Accumulation gate (ALWAYS run): drive `renderGlaze` ≥60 frames at silence through
//      the live dispatch path; assert the field stays NON-BLACK (D-019 — the seed sustains
//      it) and never WHITES OUT (the HDR-feedback trip-wire).
//   4. Reduced-motion gate (BUG-061): the .rgba16Float direct pipeline must not be rendered
//      to the 8-bit drawable — `renderGlazeReducedMotion` uses the comp (drawable) pipeline.
//   5. Env-gated PNG diag (GLAZE_MVWARP_DIAG=1): contact frames for the M7 pre-check.
//   Synthetic energy is DEV-PREVIEW ONLY (FA #27) — real-audio behaviour is Matt's live M7.

import Testing
import Foundation
import Metal
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import Renderer
@testable import Presets
@testable import Shared

@Suite("Glaze mv_warp port (GLAZE.2a)")
struct GlazeMVWarpAccumulationTest {

    private static let deltaTime: Float = 1.0 / 60.0

    // MARK: - Static-source guards (cheap regression sentries; no GPU)

    @Test("Glaze.metal declares the scene, custom warp, custom comp, and both mv_warp functions")
    func test_metalSource_declaresRequiredFunctions() throws {
        let src = try String(contentsOf: Self.shaderURL("Glaze.metal"), encoding: .utf8)
        for fn in ["glaze_fragment(",
                   "glaze_warp_fragment(",
                   "glaze_comp_fragment(",
                   "MVWarpPerFrame mvWarpPerFrame(",
                   "float2 mvWarpPerVertex("] {
            #expect(src.contains(fn), "Glaze.metal missing \(fn)")
        }
    }

    @Test("Glaze.json declares passes: [\"direct\", \"mv_warp\"] and fragment_function glaze_fragment")
    func test_json_declaresDirectAndMVWarp() throws {
        let data = try Data(contentsOf: Self.shaderURL("Glaze.json"))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["passes"] as? [String] == ["direct", "mv_warp"],
                "Glaze.json must declare passes: [\"direct\", \"mv_warp\"].")
        #expect((json?["fragment_function"] as? String) == "glaze_fragment",
                "Glaze.json fragment_function must be glaze_fragment (drives glaze_* warp/comp auto-selection).")
    }

    // MARK: - Compile + custom-comp wiring (GPU; worktree-runnable — no external fixtures)

    @Test("Glaze loads and its mv_warp pipelines compile (custom warp + comp auto-selected)")
    func test_presetCompilesAndWiresCustomComp() throws {
        let ctx = try MetalContext()
        let loader = PresetLoader(device: ctx.device, pixelFormat: ctx.pixelFormat, loadBuiltIn: true)
        guard let preset = loader.presets.first(where: { $0.descriptor.name == "Glaze" }) else {
            Issue.record("Glaze preset not loaded — Glaze.metal failed to compile, or the bundle resource wasn't copied.")
            return
        }
        #expect(preset.descriptor.passes.contains(.mvWarp),
                "Glaze descriptor must include the mv_warp pass.")
        #expect(preset.mvWarpPipelines != nil,
                "Glaze.mvWarpPipelines is nil — the .metal failed to compile (incl. glaze_comp_fragment) or passes are misconfigured.")
    }

    // MARK: - Accumulation gate (ALWAYS run): live dispatch path, non-black + no white-out

    @Test("Glaze field stays alive (non-black) and never whites out over 64 silence frames")
    @MainActor
    func test_accumulation_silenceStaysAliveNoWhiteout() throws {
        guard let ctx = try? MetalContext() else {
            Issue.record("No Metal device — cannot run the accumulation gate"); return
        }
        guard let display = try Self.runGlaze(ctx: ctx, width: 192, height: 128, frames: 64, energy: 0) else {
            Issue.record("Glaze render setup failed"); return
        }
        let stats = Self.frameStats(display)
        // Non-black: the palette-tinted, silence-floored seed sustains the field (D-019).
        #expect(stats.meanLuma > 0.01,
                "Glaze silence field is ~black (meanLuma \(stats.meanLuma)) — the seed/feedback isn't sustaining.")
        // No white-out: the HDR-feedback trip-wire. Most pixels saturating ⇒ over-accumulation.
        #expect(stats.saturatedFraction < 0.85,
                "Glaze field whites out (\(Int(stats.saturatedFraction * 100))% saturated) — over-accumulation.")
    }

    // MARK: - Reduced-motion regression (BUG-061: 16-float direct pipeline → 8-bit drawable)

    @Test("Glaze reduced-motion frame renders to the 8-bit drawable format without a format mismatch")
    @MainActor
    func test_reducedMotion_rendersToDrawableFormatNoMismatch() throws {
        guard let ctx = try? MetalContext() else {
            Issue.record("No Metal device — cannot run the reduced-motion gate"); return
        }
        let display = try Self.runGlaze(ctx: ctx, width: 192, height: 128, frames: 3,
                                        energy: 0, reducedMotion: true)
        #expect(display != nil, "Glaze reduced-motion render setup failed")
    }

    // MARK: - Env-gated PNG diag (the M7 pre-check; render BEFORE tuning)

    @Test("Glaze render diag (env-gated GLAZE_MVWARP_DIAG=1)")
    @MainActor
    func test_glazeRender_diag() throws {
        guard ProcessInfo.processInfo.environment["GLAZE_MVWARP_DIAG"] == "1" else {
            print("GlazeMVWarpAccumulationTest: GLAZE_MVWARP_DIAG not set, skipping render diag")
            return
        }
        let ctx = try MetalContext()
        let wPix = ProcessInfo.processInfo.environment["GLAZE_W"].flatMap { Int($0) } ?? 1280
        let hPix = ProcessInfo.processInfo.environment["GLAZE_H"].flatMap { Int($0) } ?? 720
        let frames = ProcessInfo.processInfo.environment["GLAZE_FRAMES"].flatMap { Int($0) } ?? 120
        // DEV PREVIEW ONLY (FA #27): with no real session in the worktree, GLAZE_ENERGY
        // injects a constant band energy so the seed can be eyeballed. Real-audio = Matt's M7.
        let energy = ProcessInfo.processInfo.environment["GLAZE_ENERGY"].flatMap { Float($0) } ?? 0
        guard let display = try Self.runGlaze(ctx: ctx, width: wPix, height: hPix,
                                              frames: frames, energy: energy) else {
            Issue.record("Glaze render setup failed"); return
        }
        let outDir = FileManager.default.temporaryDirectory.appendingPathComponent("glaze_mvwarp_diag")
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let url = outDir.appendingPathComponent("glaze_frame\(frames).png")
        try Self.writePNG(display, to: url)
        print("[glaze_diag] wrote \(url.path) (\(wPix)×\(hPix), \(frames) frames, energy=\(energy))")
    }

    // MARK: - Shared render driver (live dispatch path — FA #66, no reimplemented encode)

    /// Drive the REAL `RenderPipeline.renderGlaze` for `frames` frames into an offscreen
    /// drawable-format texture and return it. Silence-driven (worktree-safe; synthetic
    /// `energy` is dev-preview only). Returns nil on setup failure.
    @MainActor
    static func runGlaze(ctx: MetalContext, width: Int, height: Int, frames: Int,
                         energy: Float, reducedMotion: Bool = false) throws -> MTLTexture? {
        let lib = try ShaderLibrary(context: ctx)
        let texMgr = try TextureManager(context: ctx, shaderLibrary: lib)
        let floatStride = MemoryLayout<Float>.stride
        guard let fft = ctx.makeSharedBuffer(length: 512 * floatStride),
              let wav = ctx.makeSharedBuffer(length: 2048 * floatStride) else { return nil }
        let pipeline = try RenderPipeline(context: ctx, shaderLibrary: lib, fftBuffer: fft, waveformBuffer: wav)
        pipeline.setTextureManager(texMgr)
        let loader = PresetLoader(device: ctx.device, pixelFormat: ctx.pixelFormat, loadBuiltIn: true)
        guard let preset = loader.presets.first(where: { $0.descriptor.name == "Glaze" }),
              let mvWarp = preset.mvWarpPipelines else { return nil }

        let size = CGSize(width: width, height: height)
        pipeline.currentDrawableSize = size
        // Feedback in HDR .rgba16Float (matches PresetLoader.feedbackFormat for Glaze);
        // the comp target stays the drawable format. isGlaze routes the draw branch.
        let bundle = MVWarpPipelineBundle(
            warpState: mvWarp.warpState,
            composeState: mvWarp.composeState,
            blitState: mvWarp.blitState,
            pixelFormat: ctx.pixelFormat,
            feedbackFormat: .rgba16Float,
            isGlaze: true)
        pipeline.setupMVWarp(bundle: bundle, size: size)
        pipeline.setMVWarpDecay(preset.descriptor.decay)

        let fbDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: ctx.pixelFormat, width: width, height: height, mipmapped: false)
        fbDesc.usage = [.renderTarget, .shaderRead]
        fbDesc.storageMode = .shared
        guard let display = ctx.device.makeTexture(descriptor: fbDesc) else { return nil }

        for i in 0..<frames {
            var feat = FeatureVector.zero
            feat.deltaTime = deltaTime
            feat.time = Float(i) * deltaTime
            feat.bass = energy; feat.mid = energy; feat.treble = energy   // dev preview only
            guard let cmd = ctx.commandQueue.makeCommandBuffer(),
                  let warpState = pipeline.mvWarpState else { return display }
            if reducedMotion {
                pipeline.renderGlazeReducedMotion(commandBuffer: cmd, features: feat,
                                                  warpState: warpState, target: display)
            } else {
                pipeline.renderGlaze(commandBuffer: cmd, features: feat, stemFeatures: .zero,
                                     warpState: warpState, target: display)
            }
            cmd.commit(); cmd.waitUntilCompleted()
            if let err = cmd.error {
                Issue.record("Glaze frame \(i) command buffer error (format mismatch?): \(err)")
                return display
            }
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

    // MARK: - PNG writer (8-bit BGRA target; reused from the Nacre diag)

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
        else { throw GlazeDiagError.pngFailed }
        CGImageDestinationAddImage(dest, img, nil)
        guard CGImageDestinationFinalize(dest) else { throw GlazeDiagError.pngFailed }
    }

    enum GlazeDiagError: Error { case pngFailed }

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
