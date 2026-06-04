// Murmuration3DRenderTests — verify the 3D parametric-ellipse flock against the
// murmuration must-haves headlessly (compiles the murmuration3d_* shader, checks
// the flock stays framed on-canvas, renders sequences for eyeball) BEFORE the live
// review — so the next live look is a sign-off, not a tweak round.

import Testing
import Metal
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation
@testable import Renderer
@testable import Shared

@Suite("Murmuration 3D (parametric-ellipse flock)")
struct Murmuration3DRenderTests {

    private enum E: Error { case setup, render, png }
    private let cfg = Murmuration3DConfiguration()

    private func makeGeo(_ ctx: MetalContext, _ lib: ShaderLibrary, pixelFormat: MTLPixelFormat?) throws -> Murmuration3DGeometry {
        try Murmuration3DGeometry(device: ctx.device, library: lib.library, configuration: cfg, pixelFormat: pixelFormat)
    }

    private func step(_ geo: Murmuration3DGeometry, _ f: FeatureVector, _ s: StemFeatures, _ q: MTLCommandQueue) throws {
        guard let cmd = q.makeCommandBuffer() else { throw E.setup }
        geo.update(features: f, stemFeatures: s, commandBuffer: cmd)
        cmd.commit(); cmd.waitUntilCompleted()
    }

    /// Replicate the vertex projection (camera pitch + perspective) to check the
    /// flock projects on-canvas — the load-bearing "stays framed" must-have.
    private func framedFraction(_ geo: Murmuration3DGeometry) -> (framed: Float, bad: Bool) {
        let n = geo.configuration.particleCount
        let ptr = geo.particleBuffer.contents().bindMemory(to: M3DParticle.self, capacity: n)
        let cp = cosf(cfg.camPitch), sp = sinf(cfg.camPitch)
        var framed = 0, bad = false
        for i in 0..<n {
            let p = ptr[i]
            if !p.positionX.isFinite || !p.positionY.isFinite || !p.positionZ.isFinite { bad = true; continue }
            let cy = p.positionY * cp + p.positionZ * sp
            let cz = -p.positionY * sp + p.positionZ * cp
            let persp = cfg.camDist / max(cfg.camDist - cz, 0.05) * cfg.viewScale
            if abs(p.positionX * persp) < 1.0 && abs(cy * persp) < 1.0 { framed += 1 }
        }
        return (Float(framed) / Float(n), bad)
    }

    @Test("Compiles, settles dense + framed on-canvas at silence")
    func test_framed() throws {
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let geo = try makeGeo(ctx, lib, pixelFormat: nil)
        var t: Float = 0
        for _ in 0..<420 { try step(geo, FeatureVector(time: t, deltaTime: 1.0 / 60.0), .zero, ctx.commandQueue); t += 1.0 / 60.0 }
        let (frac, bad) = framedFraction(geo)
        #expect(!bad, "positions must stay finite")
        #expect(frac > 0.95, "the 3D flock must stay framed on-canvas at silence: framedFrac=\(frac)")
    }

    @Test("Render sequences (RENDER_VISUAL=1)")
    func test_render() throws {
        guard ProcessInfo.processInfo.environment["RENDER_VISUAL"] == "1" else { return }
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let geo = try makeGeo(ctx, lib, pixelFormat: ctx.pixelFormat)
        let w = 960, h = 540
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: ctx.pixelFormat, width: w, height: h, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]; td.storageMode = .shared
        guard let tex = ctx.device.makeTexture(descriptor: td) else { throw E.render }
        var u = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { u.deleteLastPathComponent() }
        let outDir = u.appendingPathComponent("tools/murmuration_reference/frames", isDirectory: true)
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        // Silence baseline sequence (gradual morphing).
        var t: Float = 0
        for _ in 0..<180 { try step(geo, FeatureVector(time: t, deltaTime: 1.0 / 60.0), .zero, ctx.commandQueue); t += 1.0 / 60.0 }
        for frame in 0..<6 {
            for _ in 0..<150 { try step(geo, FeatureVector(time: t, deltaTime: 1.0 / 60.0), .zero, ctx.commandQueue); t += 1.0 / 60.0 }
            try renderPNG(geo, t, tex, ctx, w, h, outDir.appendingPathComponent(String(format: "mm3d_silence_%02d.png", frame)))
        }
        // Audio sequence: bass (elongation) + pulsing drums (turning-wave → banking
        // dark bands) + other (flutter) + vocals (compression). Verifies the routes
        // and the rolling dark-band shimmer.
        var pulse: Float = 0
        var shot = 0
        for frame in 0..<900 {
            if frame % 26 == 0 { pulse = 1.0 }
            var f = FeatureVector(time: t, deltaTime: 1.0 / 60.0)
            f.arousal = 0.7; f.bassAttRel = 0.6
            var s = StemFeatures()
            s.bassEnergy = 0.5; s.drumsEnergy = 0.5; s.drumsBeat = pulse
            s.otherEnergy = 0.35; s.vocalsEnergy = 0.2
            try step(geo, f, s, ctx.commandQueue)
            pulse *= 0.82; t += 1.0 / 60.0
            if frame >= 120 && frame % 120 == 0 {
                try renderPNG(geo, t, tex, ctx, w, h, outDir.appendingPathComponent(String(format: "mm3d_audio_%02d.png", shot))); shot += 1
            }
        }
    }

    private func renderPNG(_ geo: Murmuration3DGeometry, _ t: Float, _ tex: MTLTexture, _ ctx: MetalContext,
                           _ w: Int, _ h: Int, _ url: URL) throws {
        guard let cmd = ctx.commandQueue.makeCommandBuffer() else { throw E.render }
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = tex
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0.55, green: 0.62, blue: 0.72, alpha: 1)
        rpd.colorAttachments[0].storeAction = .store
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) else { throw E.render }
        geo.render(encoder: enc, features: FeatureVector(time: t, deltaTime: 1.0 / 60.0))
        enc.endEncoding(); cmd.commit(); cmd.waitUntilCompleted()
        var px = [UInt8](repeating: 0, count: w * h * 4)
        tex.getBytes(&px, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        guard let cs = CGColorSpace(name: CGColorSpace.sRGB) else { throw E.png }
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        let image: CGImage? = px.withUnsafeMutableBytes { p in
            guard let base = p.baseAddress,
                  let cg = CGContext(data: base, width: w, height: h, bitsPerComponent: 8,
                                     bytesPerRow: w * 4, space: cs, bitmapInfo: info.rawValue) else { return nil }
            return cg.makeImage()
        }
        guard let cgImage = image,
              let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { throw E.png }
        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else { throw E.png }
        print("[MM3D] wrote \(url.path)")
    }
}
