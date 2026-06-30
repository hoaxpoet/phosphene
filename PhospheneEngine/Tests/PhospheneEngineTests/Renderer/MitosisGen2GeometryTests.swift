// MitosisGen2GeometryTests — headless gates for the Cytokinesis preset (Mitosis gen-2,
// MITOSIS-G2.1). Exercises the PRODUCTION dispatch path (the real `MitosisGen2Geometry`
// update→render, the same calls `RenderPipeline.drawParticleMode` makes) — not a standalone
// shader (that's the throwaway `MitosisGen2SketchRenderTests`). Proves what CI can check:
// framerate, the bounded few-large-cells lifecycle (seed → advance → onset SNAP → two
// daughters → never exceeds the cap), and that brightness changes stay gradual (flash-safe,
// D-157). The look itself is Matt's live M7 (FA #27); RENDER_VISUAL=1 dumps frames for it.

import Testing
import Metal
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation
@testable import Renderer
@testable import Shared

@Suite("Mitosis gen-2 geometry (Cytokinesis)")
struct MitosisGen2GeometryTests {

    private enum E: Error { case setup, render, png }

    private func makeGeo(_ ctx: MetalContext, _ lib: ShaderLibrary,
                         _ cfg: MitosisGen2Configuration = .init()) throws -> MitosisGen2Geometry {
        try MitosisGen2Geometry(device: ctx.device, library: lib.library, configuration: cfg,
                                pixelFormat: ctx.pixelFormat)
    }

    private func target(_ ctx: MetalContext, _ w: Int, _ h: Int) throws -> MTLTexture {
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: ctx.pixelFormat, width: w, height: h, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]; td.storageMode = .shared
        guard let tex = ctx.device.makeTexture(descriptor: td) else { throw E.render }
        return tex
    }

    /// One production frame: update (advance envelopes + cell model) then render.
    @discardableResult
    private func step(_ geo: MitosisGen2Geometry, energy: Float, drum: Bool,
                      _ tex: MTLTexture, _ ctx: MetalContext, _ t: inout Float) throws -> Double {
        var f = FeatureVector(time: t, deltaTime: 1.0 / 60.0)
        f.bass = energy; f.mid = energy * 0.85
        f.spectralCentroid = 0.3 + 0.4 * (0.5 + 0.5 * sin(t * 0.2))
        f.aspectRatio = 16.0 / 9.0
        var s = StemFeatures()
        s.bassEnergy = energy; s.drumsEnergy = energy; s.otherEnergy = energy * 0.8; s.vocalsEnergy = energy * 0.5
        s.drumsEnergyDev = drum ? 1.3 : 0.03

        guard let cmd = ctx.commandQueue.makeCommandBuffer() else { throw E.setup }
        geo.update(features: f, stemFeatures: s, commandBuffer: cmd)
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = tex
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        rpd.colorAttachments[0].storeAction = .store
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) else { throw E.render }
        geo.render(encoder: enc, features: f)
        enc.endEncoding()
        cmd.commit(); cmd.waitUntilCompleted()
        t += 1.0 / 60.0
        return (cmd.gpuEndTime - cmd.gpuStartTime) * 1000.0
    }

    private func lumaMean(_ tex: MTLTexture, _ w: Int, _ h: Int) -> Float {
        var px = [UInt8](repeating: 0, count: w * h * 4)
        tex.getBytes(&px, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        var sum: Float = 0
        for i in 0..<(w * h) {
            sum += (0.299 * Float(px[i * 4 + 2]) + 0.587 * Float(px[i * 4 + 1]) + 0.114 * Float(px[i * 4])) / 255
        }
        return sum / Float(w * h)
    }

    // MARK: - Criterion 1: framerate

    @Test("Holds the 60 fps frame budget @ 1080p")
    func test_framerate() throws {
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let geo = try makeGeo(ctx, lib)
        let tex = try target(ctx, 1920, 1080)
        var t: Float = 0
        for _ in 0..<30 { try step(geo, energy: 0.5, drum: false, tex, ctx, &t) }
        var times: [Double] = []
        for fr in 0..<180 { times.append(try step(geo, energy: 0.5, drum: fr % 30 == 0, tex, ctx, &t)) }
        times.sort()
        let median = times[times.count / 2]
        print(String(format: "[GEN2] geometry @1080p: median %.2f ms/frame (min %.2f, max %.2f) — budget 16.67",
                     median, times.first ?? 0, times.last ?? 0))
        #expect(median < 16.67, "must hold 60 fps: median \(median) ms")
    }

    // MARK: - Criterion 2: bounded few-large-cells lifecycle

    @Test("Cells seed, divide on a snap into two daughters, and stay bounded (few large cells)")
    func test_cellLifecycle() throws {
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let cfg = MitosisGen2Configuration()
        let geo = try makeGeo(ctx, lib, cfg)
        let tex = try target(ctx, 640, 360)
        var t: Float = 0

        #expect(geo.currentCellCount == cfg.seedCells, "colony seeds with \(cfg.seedCells) cells")

        // Over a long run with onsets the count grows to the cap and is never exceeded
        // (the bounded few-large-cells arc).
        var maxSeen = geo.currentCellCount
        for fr in 0..<(40 * 60) {
            try step(geo, energy: 0.6, drum: fr % 24 == 0, tex, ctx, &t)
            maxSeen = max(maxSeen, geo.currentCellCount)
            #expect(geo.currentCellCount <= cfg.maxCells, "never exceeds the few-cells cap")
            #expect(geo.currentCellCount >= 1, "colony never dies out")
        }
        print("[GEN2] lifecycle: maxSeen=\(maxSeen) cap=\(cfg.maxCells) final=\(geo.currentCellCount)")
        #expect(maxSeen == cfg.maxCells, "cells divide up to the cap: maxSeen \(maxSeen)")

        // The onset SNAP causes division: an onset-driven colony divides MORE in a short
        // window than an identically-seeded silent-drum control (the gen-1 sketch pattern —
        // proves the mechanism without depending on exact phase timing; the *feel* is the
        // live M7). Neither reaches a natural completion in this window, so the difference
        // is the snaps.
        var tA: Float = 0, tB: Float = 0
        let geoOnset = try makeGeo(ctx, lib, cfg)
        let geoControl = try makeGeo(ctx, lib, cfg)
        for fr in 0..<150 {
            try step(geoOnset, energy: 0.8, drum: fr % 20 == 0, tex, ctx, &tA)
            try step(geoControl, energy: 0.8, drum: false, tex, ctx, &tB)
        }
        print("[GEN2] snap: onset-driven=\(geoOnset.currentCellCount) control=\(geoControl.currentCellCount)")
        #expect(geoOnset.currentCellCount > geoControl.currentCellCount,
                "onsets snap ready cells into divisions: onset \(geoOnset.currentCellCount) vs control \(geoControl.currentCellCount)")
    }

    // MARK: - Criterion 3: flash-safe (D-157)

    @Test("Brightness changes are gradual — no strobe (D-157)")
    func test_flashSafe() throws {
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let geo = try makeGeo(ctx, lib)
        let w = 640, h = 360
        let tex = try target(ctx, w, h)
        var t: Float = 0
        try step(geo, energy: 0.6, drum: false, tex, ctx, &t)
        var prev = lumaMean(tex, w, h)
        var maxDelta: Float = 0, lo = prev, hi = prev
        for fr in 0..<(40 * 60) {
            try step(geo, energy: 0.6, drum: fr % 15 == 0, tex, ctx, &t)   // 4 Hz onset train
            let m = lumaMean(tex, w, h)
            maxDelta = max(maxDelta, abs(m - prev)); lo = min(lo, m); hi = max(hi, m); prev = m
        }
        print(String(format: "[GEN2] flash: maxΔ/frame %.4f  luma range %.3f–%.3f", maxDelta, lo, hi))
        #expect(maxDelta < 0.05, "brightness must change gradually, never strobe: maxΔ \(maxDelta)")
    }

    // MARK: - Look (RENDER_VISUAL=1)

    @Test("Render the live cell-division look (RENDER_VISUAL=1)")
    func test_renderLook() throws {
        guard ProcessInfo.processInfo.environment["RENDER_VISUAL"] == "1" else { return }
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let geo = try makeGeo(ctx, lib)
        let w = 1200, h = 675
        let tex = try target(ctx, w, h)
        var base = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { base.deleteLastPathComponent() }
        let dir = base.appendingPathComponent("tools/mitosis_gen2_sketch/frames/geometry", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var t: Float = 0; var shot = 0
        for fr in 0..<(30 * 60) {
            try step(geo, energy: 0.55, drum: fr % 26 == 0, tex, ctx, &t)
            if fr % 120 == 0 {
                print("[GEN2] t=\(String(format: "%.0f", t))s cells=\(geo.currentCellCount)")
                try writePNG(tex, w, h, dir.appendingPathComponent(String(format: "g_%02d.png", shot))); shot += 1
            }
        }
        print("[GEN2] geometry frames: \(dir.path)")
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
