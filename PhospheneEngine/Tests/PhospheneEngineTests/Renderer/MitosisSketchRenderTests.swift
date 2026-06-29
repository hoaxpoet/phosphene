// MitosisSketchRenderTests — headless gates for the Mitosis reaction–diffusion
// preset (MITOSIS.2c "psychedelic cell division"). Proves what the app can't show
// in CI: framerate, a stable bounded field, the grow→crowd→dissolve→regrow cycle
// (few cells divide into many until crowded, then melt back and regrow), and that
// the cycle's luminance changes are GRADUAL (flash-safe, D-157). The look itself —
// fluorescence stain + music-driven psychedelic hue — is a live review (FA #27);
// RENDER_VISUAL=1 dumps the cycle frames for it.

import Testing
import Metal
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation
@testable import Renderer
@testable import Shared

@Suite("Mitosis sketch (reaction–diffusion)")
struct MitosisSketchRenderTests {

    private enum E: Error { case setup, render, png }

    // MARK: - Helpers

    private func makeGeo(_ ctx: MetalContext, _ lib: ShaderLibrary,
                         _ cfg: MitosisConfiguration, pixelFormat: MTLPixelFormat?) throws -> MitosisGeometry {
        try MitosisGeometry(device: ctx.device, library: lib.library, configuration: cfg, pixelFormat: pixelFormat)
    }

    @discardableResult
    private func frame(_ geo: MitosisGeometry, _ f: FeatureVector, _ s: StemFeatures,
                       _ tex: MTLTexture, _ ctx: MetalContext) throws -> Double {
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
        return (cmd.gpuEndTime - cmd.gpuStartTime) * 1000.0
    }

    /// One frame at a steady energy + a rising spectral centroid (so the music-driven
    /// hue has something to track). The cycle/division is paced by energy.
    @discardableResult
    private func step(_ geo: MitosisGeometry, _ energy: Float, _ tex: MTLTexture, _ ctx: MetalContext,
                      _ t: inout Float) throws -> Double {
        var f = FeatureVector(time: t, deltaTime: 1.0 / 60.0)
        f.bass = energy; f.mid = energy * 0.85
        f.spectralCentroid = 0.3 + 0.4 * (0.5 + 0.5 * sin(t * 0.2))
        var s = StemFeatures()
        s.bassEnergy = energy; s.drumsEnergy = energy; s.otherEnergy = energy * 0.8; s.vocalsEnergy = energy * 0.5
        let ms = try frame(geo, f, s, tex, ctx); t += 1.0 / 60.0
        return ms
    }

    private func target(_ ctx: MetalContext, _ w: Int, _ h: Int) throws -> MTLTexture {
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: ctx.pixelFormat, width: w, height: h, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]; td.storageMode = .shared
        guard let tex = ctx.device.makeTexture(descriptor: td) else { throw E.render }
        return tex
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

    /// Count cells = local maxima of B above a threshold (the g channel of the rg16Float
    /// state). Tracks the true cell count as the colony grows/dissolves.
    private func spotCount(_ geo: MitosisGeometry, _ w: Int, _ h: Int, threshold: Float = 0.20) -> Int {
        var px = [Float16](repeating: 0, count: w * h * 2)
        geo.currentStateTexture.getBytes(&px, bytesPerRow: w * 2 * MemoryLayout<Float16>.stride,
                                         from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        func b(_ x: Int, _ y: Int) -> Float { Float(px[(y * w + x) * 2 + 1]) }
        var count = 0
        for y in 1..<(h - 1) {
            for x in 1..<(w - 1) {
                let v = b(x, y)
                if v <= threshold { continue }
                var isMax = true
                loop: for dy in -1...1 {
                    for dx in -1...1 where !(dx == 0 && dy == 0) {
                        let nv = b(x + dx, y + dy)
                        if nv > v || (nv == v && (y + dy) * w + (x + dx) < y * w + x) { isMax = false; break loop }
                    }
                }
                if isMax { count += 1 }
            }
        }
        return count
    }

    // MARK: - Criterion 1: framerate

    @Test("Holds the 60 fps frame budget @ 1080p")
    func test_framerate() throws {
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let cfg = MitosisConfiguration()
        let geo = try makeGeo(ctx, lib, cfg, pixelFormat: ctx.pixelFormat)
        let tex = try target(ctx, 1920, 1080)
        var t: Float = 0
        for _ in 0..<60 { try step(geo, 0.5, tex, ctx, &t) }
        var times: [Double] = []
        for _ in 0..<180 { times.append(try step(geo, 0.5, tex, ctx, &t)) }
        times.sort()
        let median = times[times.count / 2]
        print(String(format: "[MITO] %d×%d sim @1080p: median %.2f ms/frame (min %.2f, max %.2f) — budget 16.67",
                     cfg.width, cfg.height, median, times.first ?? 0, times.last ?? 0))
        #expect(median < 16.67, "must hold 60 fps: median \(median) ms")
    }

    // MARK: - Criterion 2: stable, bounded field

    @Test("Field stays finite, bounded, and populated mid-growth")
    func test_stability() throws {
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let cfg = MitosisConfiguration()
        let geo = try makeGeo(ctx, lib, cfg, pixelFormat: ctx.pixelFormat)
        let tex = try target(ctx, cfg.width, cfg.height)
        var t: Float = 0
        for _ in 0..<900 { try step(geo, 0.5, tex, ctx, &t) }   // ~15 s — well into a growth phase

        var px = [Float16](repeating: 0, count: cfg.width * cfg.height * 2)
        geo.currentStateTexture.getBytes(&px, bytesPerRow: cfg.width * 2 * MemoryLayout<Float16>.stride,
                                         from: MTLRegionMake2D(0, 0, cfg.width, cfg.height), mipmapLevel: 0)
        var bad = false
        for v in px where !Float(v).isFinite || Float(v) < -0.01 || Float(v) > 1.01 { bad = true; break }
        #expect(!bad, "RD field must stay finite and bounded in [0,1]")

        let spots = spotCount(geo, cfg.width, cfg.height)
        let mean = lumaMean(tex, cfg.width, cfg.height)
        print("[MITO] mid-growth: spots=\(spots) lumaMean=\(String(format: "%.3f", mean))")
        #expect(spots > 20, "colony must have divided into many cells mid-growth: spots \(spots)")
        #expect(mean > 0.01 && mean < 0.80, "field must be bounded, not blown-out: lumaMean \(mean)")
    }

    // MARK: - Criterion 3: the grow → crowd → dissolve → regrow cycle (MITOSIS.2c)

    /// Few cells divide into many until crowded, then the field dissolves back to a few
    /// and regrows — the whole point. Over ~75 s at steady energy: the count must reach
    /// crowded (a high peak), dissolve to a few (a deep trough), and still be alive late
    /// in the run (it regrew — the cycle continues across a long track).
    @Test("Cells divide few→many→crowded, then dissolve & regrow (cycle)")
    func test_growthCycle() throws {
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let cfg = MitosisConfiguration()
        let geo = try makeGeo(ctx, lib, cfg, pixelFormat: ctx.pixelFormat)
        let tex = try target(ctx, cfg.width, cfg.height)
        var t: Float = 0
        var samples: [Int] = []
        for fr in 0..<(75 * 60) {
            try step(geo, 0.45, tex, ctx, &t)
            if fr % 30 == 0 && fr > 120 { samples.append(spotCount(geo, cfg.width, cfg.height)) }
        }
        let peak = samples.max() ?? 0
        let trough = samples.min() ?? 0
        let late = samples.suffix(20).max() ?? 0     // still growing/alive late in the run
        print("[MITO] cycle: peak=\(peak) trough=\(trough) late-max=\(late)")
        #expect(peak > 250, "cells must divide into a crowded field: peak \(peak)")
        #expect(trough < 30, "the field must dissolve back to a few cells: trough \(trough)")
        #expect(late > 150, "the colony must regrow (cycle continues across the track): late-max \(late)")
    }

    // MARK: - Criterion 4: flash-safe — the cycle's luminance changes are GRADUAL (D-157)

    /// Growth and the dissolve change global brightness a lot over a cycle, but SLOWLY
    /// (seconds), never a strobe. The frame-to-frame luminance step must stay tiny.
    @Test("Cycle luminance changes are gradual — no strobe (D-157)")
    func test_flashSafe() throws {
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let cfg = MitosisConfiguration()
        let geo = try makeGeo(ctx, lib, cfg, pixelFormat: ctx.pixelFormat)
        let tex = try target(ctx, cfg.width, cfg.height)
        var t: Float = 0
        try step(geo, 0.6, tex, ctx, &t)
        var prev = lumaMean(tex, cfg.width, cfg.height)
        var maxDelta: Float = 0, lo: Float = prev, hi: Float = prev
        for _ in 0..<(75 * 60) {       // a couple of full cycles incl. dissolves
            try step(geo, 0.6, tex, ctx, &t)
            let m = lumaMean(tex, cfg.width, cfg.height)
            maxDelta = max(maxDelta, abs(m - prev)); lo = min(lo, m); hi = max(hi, m); prev = m
        }
        print(String(format: "[MITO] flash: maxΔ/frame %.4f  luma range %.3f–%.3f", maxDelta, lo, hi))
        #expect(maxDelta < 0.05, "brightness must change gradually, never strobe: maxΔ \(maxDelta)")
    }

    // MARK: - Look (RENDER_VISUAL=1)

    /// The full "psychedelic cell division" cycle: few cells divide into many until
    /// crowded (~25–35 s), then dissolve & regrow. Steady moderate energy + a moving
    /// spectral centroid so the music-driven hue shifts. (RENDER_VISUAL=1.)
    @Test("Render psychedelic cell-division cycle (RENDER_VISUAL=1)")
    func test_renderCycle() throws {
        guard ProcessInfo.processInfo.environment["RENDER_VISUAL"] == "1" else { return }
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let cfg = MitosisConfiguration()
        let geo = try makeGeo(ctx, lib, cfg, pixelFormat: ctx.pixelFormat)
        let w = cfg.width, h = cfg.height
        let tex = try target(ctx, w, h)
        var base = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { base.deleteLastPathComponent() }
        let dir = base.appendingPathComponent("tools/mitosis_sketch/frames/cycle", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var t: Float = 0; var shot = 0
        for fr in 0..<(75 * 60) {
            try step(geo, 0.45, tex, ctx, &t)
            if fr % 180 == 0 {   // every 3 s
                print(String(format: "[MITO] cycle t=%.0fs cyc=%.2f spots=%d", t, geo.currentCycleClock, spotCount(geo, w, h)))
                try writePNG(tex, w, h, dir.appendingPathComponent(String(format: "c_%02d.png", shot))); shot += 1
            }
        }
        print("[MITO] cycle frames: \(dir.path)")
    }

    /// MITOSIS.5 — show the colour responding to the music: a populated field rendered
    /// under different energy/timbre/drum conditions, so the palette swing + glow pulse
    /// are visible side by side. (RENDER_VISUAL=1.)
    @Test("Render colour response to music (RENDER_VISUAL=1)")
    func test_renderColorResponse() throws {
        guard ProcessInfo.processInfo.environment["RENDER_VISUAL"] == "1" else { return }
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let cfg = MitosisConfiguration()
        let geo = try makeGeo(ctx, lib, cfg, pixelFormat: ctx.pixelFormat)
        let w = cfg.width, h = cfg.height
        let tex = try target(ctx, w, h)
        var base = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { base.deleteLastPathComponent() }
        let dir = base.appendingPathComponent("tools/mitosis_sketch/frames/color", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var t: Float = 0
        for _ in 0..<720 { try step(geo, 0.5, tex, ctx, &t) }   // ~12 s — a populated mid-growth field

        func hold(_ energy: Float, _ centroid: Float, drum: Bool, frames: Int) throws {
            for fr in 0..<frames {
                var f = FeatureVector(time: t, deltaTime: 1.0 / 60.0); f.bass = energy; f.mid = energy * 0.85
                f.spectralCentroid = centroid
                var s = StemFeatures()
                s.bassEnergy = energy; s.drumsEnergy = energy; s.otherEnergy = energy * 0.8; s.vocalsEnergy = energy * 0.5
                s.drumsEnergyDev = (drum && fr % 24 < 2) ? 1.3 : 0.03
                try frame(geo, f, s, tex, ctx); t += 1.0 / 60.0
            }
        }
        try hold(0.15, 0.15, drum: false, frames: 150); try writePNG(tex, w, h, dir.appendingPathComponent("0_quiet_dark.png"))
        try hold(0.85, 0.85, drum: false, frames: 150); try writePNG(tex, w, h, dir.appendingPathComponent("1_loud_bright.png"))
        try hold(0.85, 0.35, drum: false, frames: 150); try writePNG(tex, w, h, dir.appendingPathComponent("2_loud_lowtimbre.png"))
        // On a drum hit vs between (the glow/colour pulse).
        try hold(0.55, 0.5, drum: true, frames: 120)
        for fr in 0..<24 { var f = FeatureVector(time: t, deltaTime: 1.0 / 60.0); f.bass = 0.55; f.mid = 0.47; f.spectralCentroid = 0.5
            var s = StemFeatures(); s.bassEnergy = 0.55; s.drumsEnergy = 0.55; s.otherEnergy = 0.44; s.vocalsEnergy = 0.33
            s.drumsEnergyDev = fr < 2 ? 1.3 : 0.03
            try frame(geo, f, s, tex, ctx); t += 1.0 / 60.0
            if fr == 1 { try writePNG(tex, w, h, dir.appendingPathComponent("3_on_drum_hit.png")) }
            if fr == 20 { try writePNG(tex, w, h, dir.appendingPathComponent("4_between_hits.png")) }
        }
        print("[MITO] colour-response frames: \(dir.path)")
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
