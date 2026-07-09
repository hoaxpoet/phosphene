// RicercarFlowRenderTests — headless gate + contact sheet for the Ricercar Fantasia particle flow-field
// (RICERCAR-FL.10). Proves the audio-reactive glowing-particle flow-field runs through the live
// ParticleGeometry dispatch path (compute advance → decay + additive point deposit → tonemap display),
// stays bounded (no NaN blow-up / runaway brightness), and that the flow RESPONDS to energy — glowing
// light appears when the music drives and fades toward the deep ground at silence. The LOOK — does it
// read as the luminous weaving light of the Fantasia spirit — is judged from the RENDER_VISUAL contact
// sheet and, above all, the real-audio video (RicercarFluidVideoHarness) against Matt's eye, not a metric.

import Testing
import Metal
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation
@testable import Renderer
@testable import Shared

@Suite("Ricercar flow-field (Fantasia rebuild)")
struct RicercarFlowRenderTests {

    private enum E: Error { case setup, render, png }
    static let simW = 960, simH = 540
    static let outW = 960, outH = 540

    // MARK: - Harness

    private func makeGeo(_ ctx: MetalContext, _ lib: ShaderLibrary) throws -> RicercarFlowGeometry {
        try RicercarFlowGeometry(
            device: ctx.device, library: lib.library,
            configuration: RicercarFlowConfiguration(width: Self.simW, height: Self.simH),
            pixelFormat: ctx.pixelFormat)
    }

    @discardableResult
    private func frame(_ geo: RicercarFlowGeometry, _ f: FeatureVector, _ s: StemFeatures,
                       _ tex: MTLTexture, _ ctx: MetalContext) throws -> [UInt8] {
        guard let cmd = ctx.commandQueue.makeCommandBuffer() else { throw E.setup }
        geo.update(features: f, stemFeatures: s, commandBuffer: cmd)
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = tex
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0.015, green: 0.017, blue: 0.04, alpha: 1)
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

    /// Fraction of pixels lit above the deep ground (sRGB luminance ≈ 42 for the ground; 70 is a margin).
    private func litFraction(_ px: [UInt8]) -> Double {
        var n = 0
        let count = px.count / 4
        for i in 0..<count {
            let b = Double(px[i * 4]), g = Double(px[i * 4 + 1]), r = Double(px[i * 4 + 2])
            if 0.299 * r + 0.587 * g + 0.114 * b > 70 { n += 1 }
        }
        return Double(n) / Double(count)
    }

    // A driving frame: MODERATE sustained band energy (sized to real band-dev magnitudes, not a
    // synthetic all-bands-max blast) + a periodic beat, so the flow surges and flares.
    private func drivenFrame(_ t: Float) -> FeatureVector {
        var f = FeatureVector(time: t, deltaTime: 1.0 / 60.0, aspectRatio: Float(Self.outW) / Float(Self.outH))
        f.bassDev = 0.22; f.midDev = 0.16; f.trebDev = 0.11
        f.beatComposite = (Int(t * 2) % 2 == 0) ? 0.8 : 0.0
        return f
    }

    // A family-leading frame (one instrument family clearly dominant), over some stem energy.
    private func famFrame(strings: Float = 0, brass: Float = 0, woodwinds: Float = 0, percussion: Float = 0,
                          bassDev: Float = 0.3, midDev: Float = 0.3, trebDev: Float = 0.2, t: Float)
    -> (FeatureVector, StemFeatures) {
        var f = FeatureVector(time: t, deltaTime: 1.0 / 60.0, aspectRatio: Float(Self.outW) / Float(Self.outH))
        f.bassDev = bassDev; f.midDev = midDev; f.trebDev = trebDev
        var s = StemFeatures.zero
        s.otherEnergy = 0.4
        s.stringsActivityDev = strings; s.brassActivityDev = brass
        s.woodwindsActivityDev = woodwinds; s.percussionActivityDev = percussion
        return (f, s)
    }

    // MARK: - Gate: the flow responds (light appears on energy, fades at silence, stays bounded)

    @Test("FL.10: energy lights the flow; silence fades it; the field stays bounded")
    func test_flow_respondsToEnergy_boundedAndFades() throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            print("RicercarFlowRenderTests: no Metal device — skipping"); return
        }
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let geo = try makeGeo(ctx, lib)
        let tex = try target(ctx)
        let zero = StemFeatures.zero

        // 1. Drive with music for 30 s: the energy envelope surges, light fills a meaningful (bounded)
        // fraction of the frame, and nothing blows up to fill the whole screen.
        var t: Float = 0
        var last = [UInt8]()
        for _ in 0..<1800 { last = try frame(geo, drivenFrame(t), zero, tex, ctx); t += 1.0 / 60.0 }
        let drivenLit = litFraction(last)
        print("[ricercar_flow] driven energyEnv = \(String(format: "%.3f", geo.currentEnergyEnv)), lit = \(String(format: "%.3f", drivenLit))")
        #expect(geo.currentEnergyEnv > 0.3, "energy envelope should surge under sustained music (got \(geo.currentEnergyEnv))")
        #expect(drivenLit > 0.03, "music drove almost no light (\(drivenLit)) — the flow is not depositing")
        #expect(drivenLit < 0.98, "light saturated the entire frame (\(drivenLit)) — decay/deposit unbounded (NaN?)")

        // 2. Go silent for ~12 s: the energy envelope relaxes toward 0 and the energy-driven light drops.
        // A dim floor persists (baseGlow keeps the calm field non-black, D-037) — assert it clearly dims,
        // not that it reaches zero.
        for _ in 0..<720 {
            let f = FeatureVector(time: t, deltaTime: 1.0 / 60.0, aspectRatio: Float(Self.outW) / Float(Self.outH))
            last = try frame(geo, f, zero, tex, ctx); t += 1.0 / 60.0
        }
        let restLit = litFraction(last)
        print("[ricercar_flow] rest energyEnv = \(String(format: "%.3f", geo.currentEnergyEnv)), lit = \(String(format: "%.3f", restLit))")
        #expect(geo.currentEnergyEnv < 0.15, "energy envelope should relax at silence (got \(geo.currentEnergyEnv))")
        #expect(restLit < drivenLit, "the flow did not calm at silence (\(restLit) vs driven \(drivenLit))")
    }

    // MARK: - Contact sheet (env-gated: RICERCAR_VISUAL=1 / RENDER_VISUAL=1)
    // A little "score": strings enter, brass joins, then a woodwinds+percussion beat passage — so the
    // sheet shows different family colours leading over time. The judgement is Matt's eye vs the Fantasia
    // spirit (deep luminous weaving light), not this test.

    @Test("Flow contact sheet (env-gated) — judged vs the Fantasia spirit + docs/VISUAL_REFERENCES/ricercar/01")
    func test_flow_contactSheet() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["RICERCAR_VISUAL"] == "1" || env["RENDER_VISUAL"] == "1" else {
            print("RicercarFlowRenderTests: RICERCAR_VISUAL/RENDER_VISUAL not set, skipping contact sheet"); return
        }
        guard MTLCreateSystemDefaultDevice() != nil else { return }
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let geo = try makeGeo(ctx, lib)
        let tex = try target(ctx)

        func drive(_ t: Float) -> (FeatureVector, StemFeatures) {
            switch t {
            case ..<5:  return famFrame(strings: 0.6, bassDev: 0.45, midDev: 0.2, trebDev: 0.1, t: t)
            case ..<11: return famFrame(strings: 0.25, brass: 0.85, bassDev: 0.3, midDev: 0.55, trebDev: 0.2, t: t)
            default:
                var (f, s) = famFrame(woodwinds: 0.4, percussion: 0.05, bassDev: 0.2, midDev: 0.4, trebDev: 0.5, t: t)
                f.beatComposite = (Int(t * 2) % 2 == 0) ? 0.9 : 0.0
                return (f, s)
            }
        }
        let secs: [Float] = [3, 8, 14, 18]
        let checkpoints = Set(secs.map { Int(($0 * 60).rounded()) })
        let frames = (checkpoints.max() ?? 0) + 1
        var tiles: [[UInt8]] = []
        var t: Float = 0
        for i in 0..<frames {
            let (f, s) = drive(t)
            let px = try frame(geo, f, s, tex, ctx)
            if checkpoints.contains(i) { tiles.append(px) }
            t += 1.0 / 60.0
        }
        let dir = try makeOutputDir()
        for (i, tile) in tiles.enumerated() {
            try writeBGRAToPNG(tile, w: Self.outW, h: Self.outH,
                               url: dir.appendingPathComponent(String(format: "ricercar_flow_t%02.0fs.png", secs[i])))
        }
        try writeMontage(tiles, tileW: Self.outW, tileH: Self.outH,
                         url: dir.appendingPathComponent("ricercar_flow_contact_sheet.png"))
        print("[ricercar_flow_contact_sheet] \(dir.path)/ricercar_flow_contact_sheet.png")
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
