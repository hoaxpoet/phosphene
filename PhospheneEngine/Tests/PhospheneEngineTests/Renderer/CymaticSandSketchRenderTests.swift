// CymaticSandSketchRenderTests — look/motion review for the CR.2 vibrating-sand
// rebuild. Drives CymaticSandGeometry through the real compute+render path on a
// synthetic musical arc (energy pulses on the beat, centroid ramps to change the
// mode, harmony rotates the hue) and, under RENDER_VISUAL=1, dumps a PNG sequence
// to /tmp/phosphene_visual/<ts>/ for the motion gate. Also a non-degenerate gate
// (sand actually forms bright nodal lines) so it fails if the sim dies.

import Testing
import Metal
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation
@testable import Renderer
@testable import Shared

@Suite("Cymatic Sand (CR.2 sketch)")
struct CymaticSandSketchRenderTests {

    static let W = 1280   // 16:9 so the sketch matches the live frame (exercises the cover-fit)
    static let H = 720
    static let outputRoot = "/tmp/phosphene_visual"

    // Synthetic musical arc: 120 BPM beats (bass_dev spikes), energy pulsing on the
    // beat, spectral_centroid ramping 0.08→0.18 (mode climb) then a drop, harmony rotating.
    private func features(frame i: Int, total: Int) -> (FeatureVector, StemFeatures) {
        let t = Float(i) / 60.0
        let beatPhase = (t / 0.5).truncatingRemainder(dividingBy: 1.0)   // 120 BPM
        let onBeat = beatPhase < 0.06
        let frac = Float(i) / Float(total)
        // centroid: ramp up over 0.7 then a drop back down (mode climb + snap).
        let centroid: Float = frac < 0.7 ? (0.08 + 0.11 * (frac / 0.7)) : 0.10
        var f = FeatureVector(time: t, deltaTime: 1.0 / 60.0)
        f.spectralCentroid = centroid
        f.bass = 0.4 + (onBeat ? 0.35 : 0.0)
        f.mid = 0.35
        f.bassDev = onBeat ? 1.4 : 0.05
        f.tonalPhaseFifths = Float.pi * sin(t * 0.35)   // slow harmonic sweep
        f.aspectRatio = Float(Self.W) / Float(Self.H)   // 16:9 → exercises the display cover-fit
        var s = StemFeatures.zero
        s.drumsEnergy = 0.35; s.bassEnergy = 0.4; s.otherEnergy = 0.3; s.vocalsEnergy = 0.2
        s.drumsEnergyDev = onBeat ? 1.2 : 0.0
        return (f, s)
    }

    private func renderFrame(_ geo: CymaticSandGeometry, _ f: FeatureVector, _ s: StemFeatures,
                             _ tex: MTLTexture, _ ctx: MetalContext) throws -> [UInt8] {
        guard let cmd = ctx.commandQueue.makeCommandBuffer() else { throw E.render }
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
        var px = [UInt8](repeating: 0, count: Self.W * Self.H * 4)
        tex.getBytes(&px, bytesPerRow: Self.W * 4, from: MTLRegionMake2D(0, 0, Self.W, Self.H), mipmapLevel: 0)
        return px
    }

    private func makeGeo(_ ctx: MetalContext) throws -> CymaticSandGeometry {
        let lib = try ShaderLibrary(context: ctx)
        return try CymaticSandGeometry(device: ctx.device, library: lib.library,
                                       pixelFormat: ctx.pixelFormat)
    }

    private func target(_ ctx: MetalContext) throws -> MTLTexture {
        let td = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: ctx.pixelFormat, width: Self.W, height: Self.H, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]; td.storageMode = .shared
        guard let t = ctx.device.makeTexture(descriptor: td) else { throw E.render }
        return t
    }

    // MARK: - Non-degenerate: sand forms bright nodal lines

    @Test("Sand settles into bright nodal lines (non-degenerate)")
    func nonDegenerate() throws {
        guard let ctx = try? MetalContext() else { return }
        let geo = try makeGeo(ctx)
        let tex = try target(ctx)
        // Settle ~2s at a fixed mid mode.
        var last: [UInt8] = []
        for i in 0..<150 { last = try renderFrame(geo, features(frame: i, total: 150).0, features(frame: i, total: 150).1, tex, ctx) }
        // Bright pixels (nodal lines) must exist, and it must not be a full-white wash.
        var bright = 0, total = last.count / 4
        for p in 0..<total {
            let lum = 0.114 * Float(last[4*p]) + 0.587 * Float(last[4*p+1]) + 0.299 * Float(last[4*p+2])
            if lum > 60 { bright += 1 }
        }
        let frac = Double(bright) / Double(total)
        print("[sand] bright-line fraction = \(frac)")
        #expect(frac > 0.002, "sand should form visible bright nodal lines (got \(frac))")
        #expect(frac < 0.5, "should not be a white wash (got \(frac))")
    }

    // MARK: - RENDER_VISUAL: motion sequence

    @Test("Render sand motion sequence (RENDER_VISUAL=1)")
    func renderVisual() throws {
        guard ProcessInfo.processInfo.environment["RENDER_VISUAL"] == "1" else { return }
        guard let ctx = try? MetalContext() else { return }
        let geo = try makeGeo(ctx)
        let tex = try target(ctx)
        let dir = try makeOutputDirectory()
        print("[sand RENDER_VISUAL] \(dir.path)")
        let total = 150
        // Warm up so grains have settled before the captured window.
        for i in 0..<60 { _ = try renderFrame(geo, features(frame: i, total: total).0, features(frame: i, total: total).1, tex, ctx) }
        for i in 0..<total {
            let (f, s) = features(frame: i, total: total)
            let px = try renderFrame(geo, f, s, tex, ctx)
            try writePNG(bgra: px, to: dir.appendingPathComponent(String(format: "cymatic_sand_seq_%04d.png", i)))
        }
        print("[sand RENDER_VISUAL] wrote \(total) frames (cymatic_sand_seq_*.png)")
    }

    // MARK: - Helpers

    enum E: Error { case render }

    private func makeOutputDirectory() throws -> URL {
        let fmt = ISO8601DateFormatter(); fmt.formatOptions = [.withYear, .withMonth, .withDay, .withTime]
        let stamp = fmt.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = URL(fileURLWithPath: Self.outputRoot).appendingPathComponent(stamp)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writePNG(bgra: [UInt8], to url: URL) throws {
        guard let cs = CGColorSpace(name: CGColorSpace.sRGB) else { throw E.render }
        let bi = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        var copy = bgra
        let cg = copy.withUnsafeMutableBytes { (ptr: UnsafeMutableRawBufferPointer) -> CGImage? in
            guard let base = ptr.baseAddress,
                  let c = CGContext(data: base, width: Self.W, height: Self.H, bitsPerComponent: 8,
                                    bytesPerRow: Self.W * 4, space: cs, bitmapInfo: bi.rawValue) else { return nil }
            return c.makeImage()
        }
        guard let img = cg, let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw E.render }
        CGImageDestinationAddImage(dest, img, nil)
        guard CGImageDestinationFinalize(dest) else { throw E.render }
    }
}
