// RicercarSubstrateTest — Ricercar.2 gate-before-the-gate (RICERCAR_DESIGN §7).
//
// Drives the Ricercar preset through the SAME live mv_warp dispatch path the app runs
// (scene → warp → marks-on-top overlay → blit → swap, in a loop) via the headless
// `renderMVWarpToTexture` seam — feedback persists across frames through the production swap.
// Ricercar.2 has NO CPU state (Path A: the flow warp + hand-fed colour masses are closed-form
// f(features.time)), so the harness is the generic mv_warp setup with NO follower (unlike Skein).
//
// The substrate's headline property is the INVERSE of Skein's canvas-hold Hamming-0: the field must
// ADVECT and BREATHE, not freeze. The assertions: (1) colour is deposited and persists; (2) the field
// changes frame-to-frame (it flows, it does not hold); (3) it never goes black — decay is toward the
// LIGHT GROUND (D-037 by construction, the `ricercar_warp_fragment` override, D-175). The real gate is
// the env-gated contact sheet (RICERCAR_VISUAL=1 / RENDER_VISUAL=1): does it READ as flowing, merging
// painterly colour? If not, re-tune before any voices land.

import Testing
import Metal
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation
@testable import Renderer
@testable import Presets
@testable import Shared

@Suite("Ricercar.2 — flowing-colour-field substrate")
@MainActor
struct RicercarSubstrateTest {

    static let width = 480
    static let height = 270   // 16:9, the live viewport shape

    enum RicercarTestError: Error { case setup(String) }

    // MARK: - Live-path substrate run

    @Test("Substrate flows: colour deposited, field advects (not held), never black")
    func test_substrate_flowsAndBreathes() throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            print("RicercarSubstrateTest: no Metal device — skipping"); return
        }
        let w = Self.width, h = Self.height
        let dt: Float = 1.0 / 60.0
        let checkpoints = [60, 180, 420, 900]            // ~1 / 3 / 7 / 15 s
        let frames = (checkpoints.max() ?? 0) + 1

        let (pipeline, ctx, preset) = try makeRicercarPipeline()
        let outTex = try makeOutputTexture(ctx)
        let stem = StemFeatures()                        // zero stems — substrate is time-driven only

        var captured: [Int: [UInt8]] = [:]
        var pixels = [UInt8](repeating: 0, count: w * h * 4)

        for i in 0..<frames {
            var fv = FeatureVector(time: Float(i) * dt, deltaTime: dt, aspectRatio: Float(w) / Float(h))
            guard let cmd = ctx.commandQueue.makeCommandBuffer(),
                  let warpState = pipeline.mvWarpState else {
                throw RicercarTestError.setup("command buffer / warp state")
            }
            pipeline.renderMVWarpToTexture(
                commandBuffer: cmd, target: outTex, features: &fv, stemFeatures: stem,
                activePipeline: preset.pipelineState, warpState: warpState, sceneAlreadyRendered: false)
            try commitReadback(cmd, outTex, into: &pixels, w: w, h: h)
            if checkpoints.contains(i) { captured[i] = pixels }
        }

        let finalBuf = captured[checkpoints.max()!]!
        let depositFrac = saturatedFraction(finalBuf)          // colour masses present + persisting
        // FLOW over time: the field at 3 s vs 7 s differs substantially. A canvas-HOLD (Skein) would
        // be ~0 here; this is the substrate's defining inverse property. Per-frame deltas are tiny for
        // SMOOTH flow, so the gate is measured over a 4 s interval (240 frames), not frame-to-frame.
        let evolve = meanAbsDiff(captured[180]!, captured[900]!)
        let lumas = checkpoints.compactMap { captured[$0] }.map { meanLuma($0) }
        let minLuma = lumas.min() ?? 0

        print("""
        [ricercar_substrate] live scene→warp→overlay→blit→swap, \(w)×\(h), \(frames) frames:
          deposited-colour fraction (final) = \(String(format: "%.3f", depositFrac))
          field evolution (3 s vs 15 s)     = \(String(format: "%.4f", evolve))   (canvas-hold would be ~0)
          checkpoint mean luminance         = \(lumas.map { String(format: "%.3f", $0) })
        """)

        // 1. Colour is deposited and persists into the field.
        #expect(depositFrac > 0.05, "Almost no deposited colour (\(depositFrac)) — the masses are not painting / persisting.")
        // 2. The field FLOWS — it evolves over seconds, it does not freeze (the inverse of Skein's canvas-hold).
        #expect(evolve > 0.02, "Field barely changed across 12 s (\(evolve)) — the substrate is frozen, not flowing.")
        // 3. It never goes black — decay is toward the LIGHT ground (D-037 by construction).
        #expect(minLuma > 0.20, "Canvas darkened to mean luma \(minLuma) — the field is decaying toward black, not the light ground.")
    }

    @Test("Substrate contact sheet (env-gated: RICERCAR_VISUAL=1 / RENDER_VISUAL=1)")
    func test_substrate_contactSheet() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["RICERCAR_VISUAL"] == "1" || env["RENDER_VISUAL"] == "1" else {
            print("RicercarSubstrateTest: RICERCAR_VISUAL/RENDER_VISUAL not set, skipping contact sheet"); return
        }
        guard MTLCreateSystemDefaultDevice() != nil else { return }
        let w = Self.width, h = Self.height
        let dt: Float = 1.0 / 60.0
        let secs: [Float] = [1, 3, 7, 15]
        let checkpoints = secs.map { Int(($0 / dt).rounded()) }
        let frames = (checkpoints.max() ?? 0) + 1

        let (pipeline, ctx, preset) = try makeRicercarPipeline()
        let outTex = try makeOutputTexture(ctx)
        let stem = StemFeatures()
        var captured: [Int: [UInt8]] = [:]
        var pixels = [UInt8](repeating: 0, count: w * h * 4)

        for i in 0..<frames {
            var fv = FeatureVector(time: Float(i) * dt, deltaTime: dt, aspectRatio: Float(w) / Float(h))
            guard let cmd = ctx.commandQueue.makeCommandBuffer(), let warpState = pipeline.mvWarpState else {
                throw RicercarTestError.setup("command buffer / warp state")
            }
            pipeline.renderMVWarpToTexture(
                commandBuffer: cmd, target: outTex, features: &fv, stemFeatures: stem,
                activePipeline: preset.pipelineState, warpState: warpState, sceneAlreadyRendered: false)
            try commitReadback(cmd, outTex, into: &pixels, w: w, h: h)
            if checkpoints.contains(i) { captured[i] = pixels }
        }

        let outDir = try makeOutputDir()
        var tiles: [[UInt8]] = []
        for (i, f) in checkpoints.enumerated() {
            guard let buf = captured[f] else { continue }
            tiles.append(buf)
            try writeBGRAToPNG(buf, w: w, h: h,
                               url: outDir.appendingPathComponent(String(format: "ricercar_t%02.0fs.png", secs[i])))
        }
        try writeMontage(tiles, tileW: w, tileH: h, url: outDir.appendingPathComponent("ricercar_substrate_contact_sheet.png"))
        print("""
        [ricercar_contact_sheet] live mv_warp path, \(w)×\(h):
          output dir: \(outDir.path)
          → ricercar_substrate_contact_sheet.png  +  ricercar_t01/03/07/15s.png
        """)
        #expect(tiles.count == checkpoints.count, "Missing contact-sheet checkpoints.")
    }

    // MARK: - Setup (generic mv_warp; mirrors MultiPassFlashHarnessTests.configureMVWarp for the no-follower path)

    private func makeRicercarPipeline() throws -> (RenderPipeline, MetalContext, PresetLoader.LoadedPreset) {
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let noise = try TextureManager(context: ctx, shaderLibrary: lib)
        let fstride = MemoryLayout<Float>.stride
        guard let fft = ctx.makeSharedBuffer(length: 512 * fstride),
              let wav = ctx.makeSharedBuffer(length: 2048 * fstride) else {
            throw RicercarTestError.setup("audio buffers")
        }
        let pipeline = try RenderPipeline(context: ctx, shaderLibrary: lib, fftBuffer: fft, waveformBuffer: wav)
        pipeline.setTextureManager(noise)
        guard let preset = _acceptanceFixture.presets.first(where: { $0.descriptor.name == "Ricercar" }) else {
            throw RicercarTestError.setup("Ricercar preset not loaded — bundle resource not copied?")
        }
        guard let warp = preset.mvWarpPipelines else {
            throw RicercarTestError.setup("Ricercar mvWarpPipelines nil — JSON passes misconfigured")
        }
        guard warp.sceneGeometryState != nil else {
            throw RicercarTestError.setup("ricercar_geometry_* not resolved (per-prefix lookup) — overlay missing")
        }
        let size = CGSize(width: Self.width, height: Self.height)
        pipeline.currentDrawableSize = size

        let desc = preset.descriptor
        let canvasClear = desc.marks?.canvasClear.map { SIMD4<Double>(Double($0.x), Double($0.y), Double($0.z), 1) }
            ?? SIMD4<Double>(0, 0, 0, 1)
        let bundle = MVWarpPipelineBundle(
            warpState: warp.warpState, composeState: warp.composeState, blitState: warp.blitState,
            pixelFormat: ctx.pixelFormat, feedbackFormat: ctx.pixelFormat,
            blurState: warp.blurState, isNacre: false, isFloret: false, canvasClearColor: canvasClear)
        pipeline.setupMVWarp(bundle: bundle, size: size)
        pipeline.setMVWarpDecay(desc.decay)
        if let geoState = warp.sceneGeometryState, let marks = desc.marks {
            pipeline.setSceneGeometry(geoState, vertexCount: marks.vertexCount,
                                      instanceCount: marks.instanceCount, primitive: .triangle)
            pipeline.setMVWarpChromatic(marks.chromatic)
            pipeline.setMVWarpPost(invert: marks.comp.invert, echo: marks.comp.echo,
                                   gamma: marks.comp.gamma, beatPulse: marks.beatPulse)
        }
        pipeline.setFataShapePipelines(additive: warp.shapeAdditiveState, normal: warp.shapeNormalState)
        return (pipeline, ctx, preset)
    }

    private func makeOutputTexture(_ ctx: MetalContext) throws -> MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: ctx.pixelFormat, width: Self.width, height: Self.height, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .shared
        guard let t = ctx.device.makeTexture(descriptor: d) else {
            throw RicercarTestError.setup("output texture allocation")
        }
        return t
    }

    private func commitReadback(_ cmd: MTLCommandBuffer, _ tex: MTLTexture, into pixels: inout [UInt8], w: Int, h: Int) throws {
        cmd.commit(); cmd.waitUntilCompleted()
        guard cmd.status == .completed else { throw RicercarTestError.setup("render failed") }
        tex.getBytes(&pixels, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
    }

    // MARK: - Pixel metrics

    /// Fraction of pixels whose channel spread (max−min) is high → saturated deposited colour
    /// (the LOW/MID/HIGH masses), vs the near-neutral light ground.
    private func saturatedFraction(_ bgra: [UInt8]) -> Double {
        var n = 0, total = 0, i = 0
        while i < bgra.count {
            let b = Int(bgra[i]), g = Int(bgra[i + 1]), r = Int(bgra[i + 2])
            let spread = max(max(r, g), b) - min(min(r, g), b)
            if spread > 40 { n += 1 }
            total += 1; i += 4
        }
        return total > 0 ? Double(n) / Double(total) : 0
    }

    private func meanAbsDiff(_ a: [UInt8], _ b: [UInt8]) -> Double {
        var acc = 0.0, i = 0
        while i < a.count {
            acc += Double(abs(Int(a[i]) - Int(b[i])) + abs(Int(a[i + 1]) - Int(b[i + 1])) + abs(Int(a[i + 2]) - Int(b[i + 2])))
            i += 4
        }
        return acc / Double(a.count / 4) / (3.0 * 255.0)
    }

    private func meanLuma(_ bgra: [UInt8]) -> Double {
        var acc = 0.0, i = 0
        while i < bgra.count {
            acc += (0.0722 * Double(bgra[i]) + 0.7152 * Double(bgra[i + 1]) + 0.2126 * Double(bgra[i + 2])) / 255.0
            i += 4
        }
        return acc / Double(bgra.count / 4)
    }

    // MARK: - PNG / montage (copied minimal from SkeinCanvasHoldTest)

    private func writeBGRAToPNG(_ bgra: [UInt8], w: Int, h: Int, url: URL) throws {
        var rgba = [UInt8](repeating: 0, count: bgra.count)
        for i in stride(from: 0, to: bgra.count, by: 4) {
            rgba[i] = bgra[i + 2]; rgba[i + 1] = bgra[i + 1]; rgba[i + 2] = bgra[i]; rgba[i + 3] = 255
        }
        let cs = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.noneSkipLast.rawValue
        guard let provider = CGDataProvider(data: Data(rgba) as CFData),
              let img = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32,
                                bytesPerRow: w * 4, space: cs, bitmapInfo: CGBitmapInfo(rawValue: info),
                                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw RicercarTestError.setup("png encode") }
        CGImageDestinationAddImage(dest, img, nil)
        guard CGImageDestinationFinalize(dest) else { throw RicercarTestError.setup("png finalize") }
    }

    private func writeMontage(_ tiles: [[UInt8]], tileW: Int, tileH: Int, url: URL) throws {
        guard !tiles.isEmpty else { return }
        let sep = 4
        let bigW = tiles.count * tileW + (tiles.count - 1) * sep
        let bigH = tileH
        var out = [UInt8](repeating: 40, count: bigW * bigH * 4)
        for i in stride(from: 3, to: out.count, by: 4) { out[i] = 255 }
        for (t, tile) in tiles.enumerated() {
            let x0 = t * (tileW + sep)
            for y in 0..<tileH {
                for x in 0..<tileW {
                    let src = (y * tileW + x) * 4
                    let dst = (y * bigW + (x0 + x)) * 4
                    out[dst] = tile[src]; out[dst + 1] = tile[src + 1]; out[dst + 2] = tile[src + 2]; out[dst + 3] = 255
                }
            }
        }
        try writeBGRAToPNG(out, w: bigW, h: bigH, url: url)
    }

    private func makeOutputDir() throws -> URL {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withColonSeparatorInTime]
        let stamp = iso.string(from: Date()).replacingOccurrences(of: ":", with: "").replacingOccurrences(of: "-", with: "")
        let url = URL(fileURLWithPath: "/tmp/ricercar_substrate_diag/\(stamp)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
