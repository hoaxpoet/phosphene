// FloretMVWarpAccumulationTest — Floret (Sunflower Passion port) production-pipeline test.
//
// Modelled on NacreMVWarpAccumulationTest. Per the preset session checklist: a preset with
// a temporal feedback contract must be tested on the SAME dispatch path the live app uses
// (warp → comp → swap), not just single-frame `pipelineState` checks. Written FIRST (with
// the stub) so the live `renderFloret` path is proven test-reachable before any shader work
// (the checklist's "write the multi-frame harness first").
//
// ── FLORET.2a (wiring stub) ─────────────────────────────────────────────────────────
//   1. Static guards: the .metal declares scene + warp + comp + mv_warp fns; the .json
//      declares the right passes (cheap regression sentries; catch a silent drop).
//   2. Compile/load guard: the preset loads with its custom warp + comp pipelines.
//   3. Accumulation gate (ALWAYS run): drive `renderFloret` for ≥60 frames at silence
//      through the live dispatch path; assert NON-BLACK (the seed sustains it; D-019) and
//      never WHITES OUT (the HDR-feedback trip-wire).
//   4. Reduced-motion regression (BUG-061): the 16-float direct pipeline must not be
//      rendered to the 8-bit drawable — the comp path is used instead.
//   5. Env-gated PNG diag (FLORET_MVWARP_DIAG=1): contact frame; NO synthetic envelopes
//      for faithfulness claims (FA #27) — a constant energy is dev-preview only.

import Testing
import Foundation
import Metal
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import Renderer
@testable import Presets
@testable import Shared

@Suite("Floret mv_warp port (FLORET.2a)")
struct FloretMVWarpAccumulationTest {

    private static let deltaTime: Float = 1.0 / 60.0

    // MARK: - Static-source guards (cheap regression sentries; no GPU)

    @Test("Floret.metal declares the scene, custom warp, custom comp, and both mv_warp functions")
    func test_metalSource_declaresRequiredFunctions() throws {
        let src = try String(contentsOf: Self.shaderURL("Floret.metal"), encoding: .utf8)
        for fn in ["floret_fragment(",
                   "floret_warp_fragment(",
                   "floret_comp_fragment(",
                   "MVWarpPerFrame mvWarpPerFrame(",
                   "float2 mvWarpPerVertex("] {
            #expect(src.contains(fn), "Floret.metal missing \(fn)")
        }
    }

    @Test("Floret.json declares passes: [\"direct\", \"mv_warp\"]")
    func test_json_declaresDirectAndMVWarp() throws {
        let data = try Data(contentsOf: Self.shaderURL("Floret.json"))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["passes"] as? [String] == ["direct", "mv_warp"],
                "Floret.json must declare passes: [\"direct\", \"mv_warp\"].")
        #expect((json?["fragment_function"] as? String) == "floret_fragment",
                "Floret.json fragment_function must be floret_fragment (drives floret_* warp/comp auto-selection).")
    }

    // MARK: - Compile + custom-comp wiring (GPU; worktree-runnable — no external fixtures)

    @Test("Floret loads and its mv_warp pipelines compile (custom warp + comp auto-selected)")
    func test_presetCompilesAndWiresCustomComp() throws {
        let ctx = try MetalContext()
        let loader = PresetLoader(device: ctx.device, pixelFormat: ctx.pixelFormat, loadBuiltIn: true)
        guard let preset = loader.presets.first(where: { $0.descriptor.name == "Floret" }) else {
            Issue.record("Floret preset not loaded — Floret.metal failed to compile, or the bundle resource wasn't copied.")
            return
        }
        #expect(preset.descriptor.passes.contains(.mvWarp),
                "Floret descriptor must include the mv_warp pass.")
        #expect(preset.mvWarpPipelines != nil,
                "Floret.mvWarpPipelines is nil — the .metal failed to compile (incl. floret_comp_fragment) or passes are misconfigured.")
    }

    // MARK: - Accumulation gate (ALWAYS run): live dispatch path, non-black + no white-out

    @Test("Floret field stays alive (non-black) and never whites out over 64 silence frames")
    @MainActor
    func test_accumulation_silenceStaysAliveNoWhiteout() throws {
        guard let ctx = try? MetalContext() else {
            Issue.record("No Metal device — cannot run the accumulation gate"); return
        }
        guard let display = try Self.runFloret(ctx: ctx, width: 192, height: 128, frames: 64, energy: 0) else {
            Issue.record("Floret render setup failed"); return
        }
        let stats = Self.frameStats(display)
        // Non-black: the palette wash + core seed sustain the field at silence (D-019).
        #expect(stats.meanLuma > 0.01,
                "Floret silence field is ~black (meanLuma \(stats.meanLuma)) — the seed/feedback isn't sustaining.")
        // No white-out: the HDR-feedback trip-wire. The custom warp clamps [0,1]; a mostly
        // saturated field means over-accumulation (lower the seed/decay).
        #expect(stats.saturatedFraction < 0.85,
                "Floret field whites out (\(Int(stats.saturatedFraction * 100))% saturated) — over-accumulation.")
    }

    // MARK: - Flash-safety sentry (FLORET.2b — the ~0.5 Hz radial-pulse breath must not strobe)

    @Test("Floret's radial-pulse breath stays below the flash band (bounded per-frame luma delta)")
    @MainActor
    func test_flashSafety_pulseBelowFlashBand() throws {
        guard let ctx = try? MetalContext() else {
            Issue.record("No Metal device — cannot run the flash-safety sentry"); return
        }
        // 150 frames (>2 pulse cycles at 60 fps) at silence. The comp's radial pulse is
        // time-driven at ~0.5 Hz — well below the ≥3 Hz flash band — so the WHOLE-FRAME mean
        // luma must change only gradually frame-to-frame. A large per-frame jump would mean a
        // strobe (the source's near-black↔bright swing) and the cert flash gate (FLORET.4)
        // would red. Lightweight 2b sentry; the Harding multi-pass gate comes at FLORET.4.
        var lumas: [Float] = []
        _ = try Self.runFloret(ctx: ctx, width: 192, height: 128, frames: 150, energy: 0,
                               perFrame: { lumas.append(Self.frameStats($0).meanLuma) })
        let maxDelta = zip(lumas, lumas.dropFirst()).map { abs($1 - $0) }.max() ?? 0
        #expect(maxDelta < 0.06,
                "Floret per-frame mean-luma jump \(maxDelta) exceeds the flash bound — the radial pulse is strobing, not breathing (D-157).")
    }

    // MARK: - Reduced-motion regression (BUG-061: 16-float direct pipeline → 8-bit drawable crash)

    @Test("Floret reduced-motion frame renders to the 8-bit drawable format without a format mismatch")
    @MainActor
    func test_reducedMotion_rendersToDrawableFormatNoMismatch() throws {
        guard let ctx = try? MetalContext() else {
            Issue.record("No Metal device — cannot run the reduced-motion gate"); return
        }
        let display = try Self.runFloret(ctx: ctx, width: 192, height: 128, frames: 3,
                                         energy: 0, reducedMotion: true)
        #expect(display != nil, "Floret reduced-motion render setup failed")
    }

    // MARK: - Env-gated PNG diag (the M7 pre-check; render BEFORE tuning)

    @Test("Floret render diag (env-gated FLORET_MVWARP_DIAG=1)")
    @MainActor
    func test_floretRender_diag() throws {
        guard ProcessInfo.processInfo.environment["FLORET_MVWARP_DIAG"] == "1" else {
            print("FloretMVWarpAccumulationTest: FLORET_MVWARP_DIAG not set, skipping render diag")
            return
        }
        let ctx = try MetalContext()
        let wPix = ProcessInfo.processInfo.environment["FLORET_W"].flatMap { Int($0) } ?? 1280
        let hPix = ProcessInfo.processInfo.environment["FLORET_H"].flatMap { Int($0) } ?? 720
        let frames = ProcessInfo.processInfo.environment["FLORET_FRAMES"].flatMap { Int($0) } ?? 120
        // DEV PREVIEW ONLY (not a faithfulness/pipeline claim — FA #27): a constant band
        // energy so the volume-gated seed can be eyeballed. Real-audio behaviour = Matt's M7.
        let energy = ProcessInfo.processInfo.environment["FLORET_ENERGY"].flatMap { Float($0) } ?? 0
        guard let display = try Self.runFloret(ctx: ctx, width: wPix, height: hPix,
                                               frames: frames, energy: energy) else {
            Issue.record("Floret render setup failed"); return
        }
        let outDir = FileManager.default.temporaryDirectory.appendingPathComponent("floret_mvwarp_diag")
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let url = outDir.appendingPathComponent("floret_frame\(frames).png")
        try Self.writePNG(display, to: url)
        print("[floret_diag] wrote \(url.path) (\(wPix)×\(hPix), \(frames) frames)")
    }

    // MARK: - Shared render driver (live dispatch path — FA #66, no reimplemented encode)

    /// Drive the REAL `RenderPipeline.renderFloret` for `frames` frames into an offscreen
    /// drawable-format texture and return it. Silence by default; `energy` injects a
    /// constant band level (dev preview only). Returns nil on setup failure.
    @MainActor
    static func runFloret(ctx: MetalContext, width: Int, height: Int, frames: Int,
                          energy: Float, reducedMotion: Bool = false,
                          perFrame: ((MTLTexture) -> Void)? = nil) throws -> MTLTexture? {
        let lib = try ShaderLibrary(context: ctx)
        let texMgr = try TextureManager(context: ctx, shaderLibrary: lib)
        let floatStride = MemoryLayout<Float>.stride
        guard let fft = ctx.makeSharedBuffer(length: 512 * floatStride),
              let wav = ctx.makeSharedBuffer(length: 2048 * floatStride) else { return nil }
        let pipeline = try RenderPipeline(context: ctx, shaderLibrary: lib, fftBuffer: fft, waveformBuffer: wav)
        pipeline.setTextureManager(texMgr)
        let loader = PresetLoader(device: ctx.device, pixelFormat: ctx.pixelFormat, loadBuiltIn: true)
        guard let preset = loader.presets.first(where: { $0.descriptor.name == "Floret" }),
              let mvWarp = preset.mvWarpPipelines else { return nil }

        let size = CGSize(width: width, height: height)
        pipeline.currentDrawableSize = size
        // Feedback in HDR .rgba16Float (matches PresetLoader.feedbackFormat for Floret); the
        // comp target stays the drawable format. isFloret routes the draw branch.
        let bundle = MVWarpPipelineBundle(
            warpState: mvWarp.warpState,
            composeState: mvWarp.composeState,
            blitState: mvWarp.blitState,
            pixelFormat: ctx.pixelFormat,
            feedbackFormat: .rgba16Float,
            isFloret: true)
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
                pipeline.renderFloretReducedMotion(commandBuffer: cmd, features: feat,
                                                   warpState: warpState, target: display)
            } else {
                pipeline.renderFloret(commandBuffer: cmd, features: feat, stemFeatures: .zero,
                                      warpState: warpState, target: display)
            }
            cmd.commit(); cmd.waitUntilCompleted()
            // A render-pipeline / attachment-format mismatch sets the command-buffer error
            // (the BUG-061 class). Fail loud if the Floret path binds a pipeline whose colour
            // format doesn't match its target.
            if let err = cmd.error {
                Issue.record("Floret frame \(i) command buffer error (format mismatch?): \(err)")
                return display
            }
            perFrame?(display)
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

    // MARK: - PNG writer (8-bit BGRA target)

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
        else { throw FloretDiagError.pngFailed }
        CGImageDestinationAddImage(dest, img, nil)
        guard CGImageDestinationFinalize(dest) else { throw FloretDiagError.pngFailed }
    }

    enum FloretDiagError: Error { case pngFailed }

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
