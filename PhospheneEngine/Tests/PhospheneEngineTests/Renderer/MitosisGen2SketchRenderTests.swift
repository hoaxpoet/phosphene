// MitosisGen2SketchRenderTests — THROWAWAY sketch gate for Mitosis gen-2 ("detailed
// psychedelic cell division"). Compiles tools/mitosis_gen2_sketch/Gen2Cell.metal at
// RUNTIME and renders it fullscreen — deliberately isolated from the engine renderer so
// it cannot touch the certified gen-1 (D-097). Proves the FORM and framerate; whether it
// "reads as a detailed dividing cell" vs the reference is a human look (FA #27), for which
// RENDER_VISUAL=1 dumps the division-phase contact sheet.

import Testing
import Metal
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation
@testable import Renderer

@Suite("Mitosis gen-2 sketch (procedural detailed cell)")
struct MitosisGen2SketchRenderTests {

    private enum E: Error { case setup, render, png, source }

    private struct Uniforms {
        var time: Float = 0
        var pad: Float = 0
        var resolution: SIMD2<Float> = .zero
        var energy: Float = 0.6
        var centroid: Float = 0.5
    }

    private func shaderSource() throws -> String {
        var base = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { base.deleteLastPathComponent() }   // → repo root
        let url = base.appendingPathComponent("tools/mitosis_gen2_sketch/Gen2Cell.metal")
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func pipeline(_ ctx: MetalContext) throws -> MTLRenderPipelineState {
        let lib = try ctx.device.makeLibrary(source: shaderSource(), options: nil)
        let pd = MTLRenderPipelineDescriptor()
        pd.vertexFunction = lib.makeFunction(name: "gen2_vertex")
        pd.fragmentFunction = lib.makeFunction(name: "gen2_fragment")
        pd.colorAttachments[0].pixelFormat = ctx.pixelFormat
        return try ctx.device.makeRenderPipelineState(descriptor: pd)
    }

    private func target(_ ctx: MetalContext, _ w: Int, _ h: Int) throws -> MTLTexture {
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: ctx.pixelFormat, width: w, height: h, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]; td.storageMode = .shared
        guard let tex = ctx.device.makeTexture(descriptor: td) else { throw E.render }
        return tex
    }

    @discardableResult
    private func frame(_ ctx: MetalContext, _ ps: MTLRenderPipelineState, _ tex: MTLTexture,
                       _ w: Int, _ h: Int, _ u: Uniforms) throws -> Double {
        var u = u; u.resolution = SIMD2(Float(w), Float(h))
        guard let cmd = ctx.commandQueue.makeCommandBuffer() else { throw E.setup }
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = tex
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        rpd.colorAttachments[0].storeAction = .store
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) else { throw E.render }
        enc.setRenderPipelineState(ps)
        enc.setFragmentBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
        cmd.commit(); cmd.waitUntilCompleted()
        return (cmd.gpuEndTime - cmd.gpuStartTime) * 1000.0
    }

    // MARK: - Framerate (the only hard gate the sketch can assert headlessly)

    @Test("Holds the 60 fps frame budget @ 1080p")
    func test_framerate() throws {
        let ctx = try MetalContext()
        let ps = try pipeline(ctx)
        let tex = try target(ctx, 1920, 1080)
        var u = Uniforms()
        for _ in 0..<10 { u.time += 1.0 / 60.0; try frame(ctx, ps, tex, 1920, 1080, u) }
        var times: [Double] = []
        for _ in 0..<120 { u.time += 1.0 / 60.0; times.append(try frame(ctx, ps, tex, 1920, 1080, u)) }
        times.sort()
        let median = times[times.count / 2]
        print(String(format: "[GEN2] 1080p: median %.2f ms/frame (min %.2f, max %.2f) — budget 16.67",
                     median, times.first ?? 0, times.last ?? 0))
        // Env-gated (PERF_TESTS=1, run serially): render + measurement run every pass
        // (crash/NaN coverage) and always print the median; the numeric 60 fps budget
        // is enforced only in a deliberate serial perf run, not the parallel battery
        // where GPU-timestamp time inflates under contention. (TESTFLAKE.1)
        if ProcessInfo.processInfo.environment["PERF_TESTS"] == "1" {
            #expect(median < 16.67, "must hold 60 fps: median \(median) ms")
        }
    }

    // MARK: - Contact sheet (RENDER_VISUAL=1)

    @Test("Render division-phase contact sheet (RENDER_VISUAL=1)")
    func test_renderContactSheet() throws {
        guard ProcessInfo.processInfo.environment["RENDER_VISUAL"] == "1" else { return }
        let ctx = try MetalContext()
        let ps = try pipeline(ctx)
        let w = 1200, h = 675
        let tex = try target(ctx, w, h)
        var base = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { base.deleteLastPathComponent() }
        let dir = base.appendingPathComponent("tools/mitosis_gen2_sketch/frames", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // One division cycle (7 s period): interphase → metaphase → anaphase → dumbbell → split.
        let phases: [Float] = [0.0, 0.15, 0.30, 0.45, 0.60, 0.75, 0.90]
        for (i, ph) in phases.enumerated() {
            var u = Uniforms(); u.time = ph * 7.0
            try frame(ctx, ps, tex, w, h, u)
            try writePNG(tex, w, h, dir.appendingPathComponent(String(format: "phase_%d_%02.0f.png", i, ph * 100)))
        }
        // Music response at the dumbbell keyframe (phase ~0.82): dark/low-timbre vs bright/high-timbre.
        var u = Uniforms(); u.time = 0.82 * 7.0
        u.energy = 0.18; u.centroid = 0.15; try frame(ctx, ps, tex, w, h, u)
        try writePNG(tex, w, h, dir.appendingPathComponent("music_0_dark_lowtimbre.png"))
        u.energy = 0.95; u.centroid = 0.85; try frame(ctx, ps, tex, w, h, u)
        try writePNG(tex, w, h, dir.appendingPathComponent("music_1_bright_hitimbre.png"))
        print("[GEN2] contact sheet: \(dir.path)")
    }

    private func writePNG(_ tex: MTLTexture, _ w: Int, _ h: Int, _ url: URL) throws {
        var px = [UInt8](repeating: 0, count: w * h * 4)
        tex.getBytes(&px, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        guard let cs = CGColorSpace(name: CGColorSpace.sRGB) else { throw E.png }
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        let image: CGImage? = px.withUnsafeMutableBytes { p in
            guard let baseAddr = p.baseAddress,
                  let cg = CGContext(data: baseAddr, width: w, height: h, bitsPerComponent: 8,
                                     bytesPerRow: w * 4, space: cs, bitmapInfo: info.rawValue) else { return nil }
            return cg.makeImage()
        }
        guard let cgImage = image,
              let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { throw E.png }
        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else { throw E.png }
    }
}
