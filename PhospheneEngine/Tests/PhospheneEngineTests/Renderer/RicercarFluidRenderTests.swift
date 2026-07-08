// RicercarFluidRenderTests — headless gate + contact sheet for the Ricercar Fantasia fluid sim
// (RICERCAR-FL). Proves the Stam stable-fluids dye sim runs through the ParticleGeometry path,
// produces a non-empty billowing dye field, and stays bounded (no NaN blow-up). The LOOK — does it
// read as ref 02's luminous flowing colour masses — is judged from the RENDER_VISUAL contact sheet
// against docs/VISUAL_REFERENCES/ricercar/02 (the prototype-the-look-first commitment; FA #27 — the
// still is Matt's / my eye against the reference, not an automated metric).

import Testing
import Metal
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation
@testable import Renderer
@testable import Shared

@Suite("Ricercar fluid (Fantasia rebuild)")
struct RicercarFluidRenderTests {

    private enum E: Error { case setup, render, png }
    static let simW = 320, simH = 180
    static let outW = 960, outH = 540

    // MARK: - Harness

    private func makeGeo(_ ctx: MetalContext, _ lib: ShaderLibrary) throws -> RicercarFluidGeometry {
        try RicercarFluidGeometry(device: ctx.device, library: lib.library,
                                  width: Self.simW, height: Self.simH, pixelFormat: ctx.pixelFormat)
    }

    @discardableResult
    private func frame(_ geo: RicercarFluidGeometry, _ f: FeatureVector,
                       _ tex: MTLTexture, _ ctx: MetalContext) throws -> [UInt8] {
        guard let cmd = ctx.commandQueue.makeCommandBuffer() else { throw E.setup }
        geo.update(features: f, stemFeatures: StemFeatures(), commandBuffer: cmd)
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = tex
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0.95, green: 0.94, blue: 0.92, alpha: 1)
        rpd.colorAttachments[0].storeAction = .store
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) else { throw E.render }
        geo.render(encoder: enc, features: f)
        enc.endEncoding()
        cmd.commit(); cmd.waitUntilCompleted()
        var px = [UInt8](repeating: 0, count: Self.outW * Self.outH * 4)
        tex.getBytes(&px, bytesPerRow: Self.outW * 4, from: MTLRegionMake2D(0, 0, Self.outW, Self.outH), mipmapLevel: 0)
        return px
    }

    private func target(_ ctx: MetalContext) throws -> MTLTexture {
        let td = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: ctx.pixelFormat, width: Self.outW, height: Self.outH, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]; td.storageMode = .shared
        guard let tex = ctx.device.makeTexture(descriptor: td) else { throw E.render }
        return tex
    }

    /// Fraction of pixels visibly coloured vs the light ground (0.95,0.94,0.92 → ~242 per channel).
    private func dyeFraction(_ px: [UInt8]) -> Double {
        var n = 0
        let count = px.count / 4
        for i in 0..<count {
            let b = Int(px[i * 4]), g = Int(px[i * 4 + 1]), r = Int(px[i * 4 + 2])
            // coloured = far enough from the neutral warm ground
            if abs(r - 242) + abs(g - 240) + abs(b - 235) > 60 { n += 1 }
        }
        return Double(n) / Double(count)
    }

    // MARK: - Gate: the sim runs, fills, stays bounded

    @Test("Fluid sim produces a non-empty bounded billowing dye field through the live path")
    func test_fluid_producesDyeField() throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            print("RicercarFluidRenderTests: no Metal device — skipping"); return
        }
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let geo = try makeGeo(ctx, lib)
        let tex = try target(ctx)

        var t: Float = 0
        var last = [UInt8]()
        for _ in 0..<360 {                                   // ~6 s at 60 fps
            let f = FeatureVector(time: t, deltaTime: 1.0 / 60.0, aspectRatio: Float(Self.outW) / Float(Self.outH))
            last = try frame(geo, f, tex, ctx)
            t += 1.0 / 60.0
        }
        let frac = dyeFraction(last)
        print("[ricercar_fluid] dye-covered fraction after 6 s = \(String(format: "%.3f", frac))")
        // The sources bloom + advect → a meaningful part of the frame carries dye, but it must NOT fill
        // the whole frame (dissipation keeps it breathing) and must not be NaN-black.
        #expect(frac > 0.03, "Fluid produced almost no dye (\(frac)) — sim not advecting from the sources.")
        #expect(frac < 0.95, "Fluid filled the whole frame (\(frac)) — dissipation/instability broken.")
    }

    // MARK: - Contact sheet (env-gated: RICERCAR_VISUAL=1 / RENDER_VISUAL=1) — judge vs ref 02

    @Test("Fluid contact sheet (env-gated) — compare against docs/VISUAL_REFERENCES/ricercar/02")
    func test_fluid_contactSheet() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["RICERCAR_VISUAL"] == "1" || env["RENDER_VISUAL"] == "1" else {
            print("RicercarFluidRenderTests: RICERCAR_VISUAL/RENDER_VISUAL not set, skipping contact sheet"); return
        }
        guard MTLCreateSystemDefaultDevice() != nil else { return }
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let geo = try makeGeo(ctx, lib)
        let tex = try target(ctx)

        let secs: [Float] = [2, 5, 9, 14]
        let checkpoints = Set(secs.map { Int(($0 * 60).rounded()) })
        let frames = (checkpoints.max() ?? 0) + 1
        var tiles: [[UInt8]] = []
        var t: Float = 0
        for i in 0..<frames {
            let f = FeatureVector(time: t, deltaTime: 1.0 / 60.0, aspectRatio: Float(Self.outW) / Float(Self.outH))
            let px = try frame(geo, f, tex, ctx)
            if checkpoints.contains(i) { tiles.append(px) }
            t += 1.0 / 60.0
        }
        let dir = try makeOutputDir()
        for (i, tile) in tiles.enumerated() {
            try writeBGRAToPNG(tile, w: Self.outW, h: Self.outH,
                               url: dir.appendingPathComponent(String(format: "ricercar_fluid_t%02.0fs.png", secs[i])))
        }
        try writeMontage(tiles, tileW: Self.outW, tileH: Self.outH,
                         url: dir.appendingPathComponent("ricercar_fluid_contact_sheet.png"))
        print("[ricercar_fluid_contact_sheet] \(dir.path)/ricercar_fluid_contact_sheet.png")
        #expect(tiles.count == checkpoints.count)
    }

    // MARK: - PNG (minimal, BGRA→RGBA)

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
        else { throw E.png }
        CGImageDestinationAddImage(dest, img, nil)
        guard CGImageDestinationFinalize(dest) else { throw E.png }
    }

    private func writeMontage(_ tiles: [[UInt8]], tileW: Int, tileH: Int, url: URL) throws {
        guard !tiles.isEmpty else { return }
        let cols = 2, rows = (tiles.count + 1) / 2, sep = 6
        let bigW = cols * tileW + (cols - 1) * sep
        let bigH = rows * tileH + (rows - 1) * sep
        var out = [UInt8](repeating: 30, count: bigW * bigH * 4)
        for i in stride(from: 3, to: out.count, by: 4) { out[i] = 255 }
        for (idx, tile) in tiles.enumerated() {
            let cx = (idx % cols) * (tileW + sep), cy = (idx / cols) * (tileH + sep)
            for y in 0..<tileH {
                for x in 0..<tileW {
                    let src = (y * tileW + x) * 4, dst = ((cy + y) * bigW + (cx + x)) * 4
                    out[dst] = tile[src]; out[dst + 1] = tile[src + 1]; out[dst + 2] = tile[src + 2]; out[dst + 3] = 255
                }
            }
        }
        try writeBGRAToPNG(out, w: bigW, h: bigH, url: url)
    }

    private func makeOutputDir() throws -> URL {
        let url = URL(fileURLWithPath: "/tmp/ricercar_fluid_diag")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
