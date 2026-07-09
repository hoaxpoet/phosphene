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
    static let simW = 480, simH = 270
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

    // MARK: - Gate: the music paints (forms appear on energy, rest at silence, stay bounded)

    /// A driving frame: sustained band energy + a periodic beat, so the FL.8 drive summons blooms/sprays.
    private func drivenFrame(_ t: Float) -> FeatureVector {
        var f = FeatureVector(time: t, deltaTime: 1.0 / 60.0, aspectRatio: Float(Self.outW) / Float(Self.outH))
        f.bassDev = 0.45; f.midDev = 0.35; f.trebDev = 0.25
        f.beatComposite = (Int(t * 2) % 2 == 0) ? 0.8 : 0.0
        return f
    }

    @Test("FL.8: music paints a bounded field; silence rests")
    func test_fluid_musicPaints_silenceRests() throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            print("RicercarFluidRenderTests: no Metal device — skipping"); return
        }
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let geo = try makeGeo(ctx, lib)
        geo.ribbonBrightness = 0            // gate measures the DYE field, not the ribbon overlay
        let tex = try target(ctx)

        // 1. Drive with music for 60 s: forms appear, field stays bounded, no wash-out creep.
        var t: Float = 0
        var last = [UInt8]()
        var frac6: Double = 0
        for i in 0..<3600 {
            last = try frame(geo, drivenFrame(t), tex, ctx)
            if i == 359 { frac6 = dyeFraction(last) }
            t += 1.0 / 60.0
        }
        let frac60 = dyeFraction(last)
        print("[ricercar_fluid] driven dye fraction: 6 s = \(String(format: "%.3f", frac6)), 60 s = \(String(format: "%.3f", frac60))")
        #expect(frac6 > 0.03, "Music drove almost no dye (\(frac6)) — summonForms not painting from energy.")
        #expect(frac6 < 0.95, "Field filled the frame (\(frac6)) — dissipation/instability broken.")
        #expect(frac60 < 0.85, "Coverage still climbing at 60 s (\(frac60)) — injection outruns dissipation.")

        // 2. Then go silent: nothing new is summoned and the field dissipates toward the ground (rests).
        var restFrac = frac60
        for _ in 0..<600 {                                    // ~10 s of silence
            let f = FeatureVector(time: t, deltaTime: 1.0 / 60.0, aspectRatio: Float(Self.outW) / Float(Self.outH))
            last = try frame(geo, f, tex, ctx)
            t += 1.0 / 60.0
        }
        restFrac = dyeFraction(last)
        print("[ricercar_fluid] rest dye fraction after 10 s silence = \(String(format: "%.3f", restFrac))")
        #expect(restFrac < frac60 * 0.5,
                "Field did not rest at silence (\(restFrac) vs driven \(frac60)) — the drive is autonomous, not music-painted.")
    }

    // MARK: - Contact sheets (env-gated: RICERCAR_VISUAL=1 / RENDER_VISUAL=1)
    // Two sheets: masses-only (judge vs ref 02) and masses+ribbons (judge vs ref 01 + 02 — the FL.3
    // combined look). The comparison against the reference IMAGES is the gate, not these tests.

    @Test("Fluid contact sheets (env-gated) — compare against docs/VISUAL_REFERENCES/ricercar/01 + 02")
    func test_fluid_contactSheet() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["RICERCAR_VISUAL"] == "1" || env["RENDER_VISUAL"] == "1" else {
            print("RicercarFluidRenderTests: RICERCAR_VISUAL/RENDER_VISUAL not set, skipping contact sheet"); return
        }
        guard MTLCreateSystemDefaultDevice() != nil else { return }
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let dir = try makeOutputDir()
        let variants: [(ribbons: Float, stem: String)] = [(0, "masses"), (1, "combined")]
        for v in variants {
            let geo = try makeGeo(ctx, lib)
            geo.ribbonBrightness = v.ribbons
            let tex = try target(ctx)
            let secs: [Float] = [2, 5, 9, 14]
            let checkpoints = Set(secs.map { Int(($0 * 60).rounded()) })
            let frames = (checkpoints.max() ?? 0) + 1
            var tiles: [[UInt8]] = []
            var t: Float = 0
            for i in 0..<frames {
                let px = try frame(geo, drivenFrame(t), tex, ctx)   // FL.8: music paints — drive with energy
                if checkpoints.contains(i) { tiles.append(px) }
                t += 1.0 / 60.0
            }
            for (i, tile) in tiles.enumerated() {
                try writeBGRAToPNG(tile, w: Self.outW, h: Self.outH,
                                   url: dir.appendingPathComponent(String(format: "ricercar_%@_t%02.0fs.png", v.stem, secs[i])))
            }
            try writeMontage(tiles, tileW: Self.outW, tileH: Self.outH,
                             url: dir.appendingPathComponent("ricercar_\(v.stem)_contact_sheet.png"))
            print("[ricercar_fluid_contact_sheet] \(dir.path)/ricercar_\(v.stem)_contact_sheet.png")
            #expect(tiles.count == checkpoints.count)
        }
    }

    // MARK: - FL.4 audio drive: routing fires (mechanical) + a synthetic-stream contact sheet
    //
    // FA #27: this feeds a HAND-BUILT feature stream, so it proves the ROUTING (family → which ribbon
    // brightens; energy → flow/undulation; beat → inflow) fires and stays bounded — it is NOT a claim
    // about audio-musical FEEL. That gate is Matt's live M7 on a real track (no captured session CSV is
    // available to replay here). The contact sheet is a response-shape preview, not a fidelity artifact.

    /// A frame with one family clearly leading by deviation, over moderate band energy.
    private func famFrame(strings: Float = 0, woodwinds: Float = 0, brass: Float = 0,
                          percussion: Float = 0, bassDev: Float = 0, midDev: Float = 0,
                          trebDev: Float = 0, beat: Float = 0, t: Float) -> (FeatureVector, StemFeatures) {
        var f = FeatureVector(time: t, deltaTime: 1.0 / 60.0, aspectRatio: Float(Self.outW) / Float(Self.outH))
        f.bassDev = bassDev; f.midDev = midDev; f.trebDev = trebDev; f.beatComposite = beat
        var s = StemFeatures.zero
        s.otherEnergy = 0.4
        s.stringsActivityDev = strings; s.woodwindsActivityDev = woodwinds
        s.brassActivityDev = brass; s.percussionActivityDev = percussion
        return (f, s)
    }

    @Test("FL.9 position sync: a voice's drawn height moves with its band energy (zero-lag)")
    func test_fl9_voiceHeightTracksAudio() throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            print("RicercarFluidRenderTests: no Metal device — skipping"); return
        }
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let geo = try makeGeo(ctx, lib)
        let base = RicercarFluidGeometry.voiceBase          // rest heights: strings, woodwinds, brass, perc

        // High bass → voice 0 (strings, bass-driven) head rises (top-down height DROPS below its base),
        // immediately (the head is set from THIS frame's audio — no accumulation lag).
        let (fb, sb) = famFrame(bassDev: 0.8, t: 0.1)
        geo.update(features: fb, stemFeatures: sb, commandBuffer: ctx.commandQueue.makeCommandBuffer()!)
        let hb = geo.voiceHeadHeightsForTest
        #expect(hb.x < base[0] - 0.05, "high bass should raise voice 0 (got \(hb.x) vs base \(base[0]))")

        // High treble → voice 3 (percussion, treble-driven) rises; voice 0 returns toward its base.
        let (ft, st) = famFrame(trebDev: 0.8, t: 0.2)
        geo.update(features: ft, stemFeatures: st, commandBuffer: ctx.commandQueue.makeCommandBuffer()!)
        let ht = geo.voiceHeadHeightsForTest
        #expect(ht.w < base[3] - 0.05, "high treble should raise voice 3 (got \(ht.w) vs base \(base[3]))")
        #expect(ht.x > hb.x, "voice 0 head should fall back toward base once bass drops")
    }

    @Test("FL.4 synthetic contact sheet (env-gated) — response-shape preview, NOT a fidelity gate")
    func test_fl4_contactSheet() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["RICERCAR_VISUAL"] == "1" || env["RENDER_VISUAL"] == "1" else {
            print("RicercarFluidRenderTests: RICERCAR_VISUAL/RENDER_VISUAL not set, skipping FL.4 sheet"); return
        }
        guard MTLCreateSystemDefaultDevice() != nil else { return }
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let geo = try makeGeo(ctx, lib)
        let tex = try target(ctx)

        // A little "score": strings enter, then brass joins, then a percussion beat burst — so the sheet
        // shows different families blooming/brightening over time.
        func drive(_ t: Float) -> (FeatureVector, StemFeatures) {
            switch t {
            case ..<4:  return famFrame(strings: 0.6, bassDev: 0.5, midDev: 0.15, t: t)
            case ..<9:  return famFrame(strings: 0.3, brass: 0.85, bassDev: 0.3, midDev: 0.55, t: t)
            default:    return famFrame(woodwinds: 0.4, percussion: 0.05, midDev: 0.4, trebDev: 0.5,
                                        beat: (Int(t * 2) % 2 == 0) ? 0.9 : 0.0, t: t)
            }
        }
        let secs: [Float] = [2, 6, 12, 16]
        let checkpoints = Set(secs.map { Int(($0 * 60).rounded()) })
        let frames = (checkpoints.max() ?? 0) + 1
        var tiles: [[UInt8]] = []
        var t: Float = 0
        for i in 0..<frames {
            let (f, s) = drive(t)
            guard let cmd = ctx.commandQueue.makeCommandBuffer() else { throw E.setup }
            geo.update(features: f, stemFeatures: s, commandBuffer: cmd)
            let rpd = MTLRenderPassDescriptor()
            rpd.colorAttachments[0].texture = tex
            rpd.colorAttachments[0].loadAction = .clear
            rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0.95, green: 0.94, blue: 0.92, alpha: 1)
            rpd.colorAttachments[0].storeAction = .store
            guard let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) else { throw E.render }
            geo.render(encoder: enc, features: f)
            enc.endEncoding(); cmd.commit(); cmd.waitUntilCompleted()
            if checkpoints.contains(i) {
                var px = [UInt8](repeating: 0, count: Self.outW * Self.outH * 4)
                tex.getBytes(&px, bytesPerRow: Self.outW * 4,
                             from: MTLRegionMake2D(0, 0, Self.outW, Self.outH), mipmapLevel: 0)
                tiles.append(px)
            }
            t += 1.0 / 60.0
        }
        let dir = try makeOutputDir()
        try writeMontage(tiles, tileW: Self.outW, tileH: Self.outH,
                         url: dir.appendingPathComponent("ricercar_fl4_audio_contact_sheet.png"))
        print("[ricercar_fl4_audio_contact_sheet] \(dir.path)/ricercar_fl4_audio_contact_sheet.png")
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
