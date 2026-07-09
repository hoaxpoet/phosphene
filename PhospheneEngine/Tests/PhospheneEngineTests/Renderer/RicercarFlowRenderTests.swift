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

    // MARK: - Beat-grid sync: the pulse fires ON the beat, not off the saturated live beatComposite

    /// Drive the geometry with a synthetic CACHED-GRID beat phase (beatPhase01 sawtooth) and assert the
    /// beat envelope blooms on the beat and stays quiet mid-beat — and stays ~0 at silence (pulseAmp01=0).
    /// This is the FL.11 fix: the live `beatComposite` was saturated (~95% of frames) so it carried no
    /// rhythm; the grid phase does. (No BeatGrid install needed here — we feed the phase columns directly.)
    @Test("FL.11: the beat pulse blooms on the grid beat, is quiet mid-beat, and silent at silence")
    func test_beatPulse_tracksGridPhase() throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            print("RicercarFlowRenderTests: no Metal device — skipping"); return
        }
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let geo = try makeGeo(ctx, lib)

        func drive(beatPhase: Float, barPhase: Float, amp: Float, t: Float) {
            var f = FeatureVector(time: t, deltaTime: 1.0 / 60.0, aspectRatio: 16.0 / 9.0)
            f.bassDev = 0.2; f.midDev = 0.1                     // some energy so the field is live
            f.beatPhase01 = beatPhase; f.barPhase01 = barPhase; f.pulseAmp01 = amp
            guard let cmd = ctx.commandQueue.makeCommandBuffer() else { return }
            geo.update(features: f, stemFeatures: StemFeatures.zero, commandBuffer: cmd)
            cmd.commit(); cmd.waitUntilCompleted()
        }

        // Sit at mid-beat for a moment → the pulse should be low.
        var t: Float = 0
        for _ in 0..<12 { drive(beatPhase: 0.5, barPhase: 0.5, amp: 1, t: t); t += 1.0 / 60.0 }
        let midBeat = geo.currentBeatEnv
        // Now hit the beat (phase ≈ 0) → the pulse should snap high.
        drive(beatPhase: 0.02, barPhase: 0.5, amp: 1, t: t); t += 1.0 / 60.0
        let onBeat = geo.currentBeatEnv
        print("[ricercar_flow] beatEnv: mid-beat=\(String(format: "%.3f", midBeat)) on-beat=\(String(format: "%.3f", onBeat))")
        #expect(onBeat > 0.7, "the beat pulse should bloom on the grid beat (got \(onBeat))")
        #expect(midBeat < 0.25, "the pulse should be quiet mid-beat (got \(midBeat))")

        // Silence (pulseAmp01 = 0): even at phase 0 the pulse must stay dark (no ghost pulsing).
        for _ in 0..<20 { drive(beatPhase: 0.02, barPhase: 0.02, amp: 0, t: t); t += 1.0 / 60.0 }
        let silent = geo.currentBeatEnv
        print("[ricercar_flow] beatEnv at silence=\(String(format: "%.3f", silent))")
        #expect(silent < 0.05, "the beat must not pulse at silence (pulseAmp01=0), got \(silent)")
    }

    // MARK: - FL.14 articulation: staccato → shorter/choppier lines, legato → longer/flowing

    // Mean particle age (s) per family, read from the geometry's shared particle buffer (@testable). Staccato
    // families respawn faster ⇒ lower mean age ⇒ shorter/choppier lines. FL.14 differentiation measure.
    private func meanAgeByFamily(_ geo: RicercarFlowGeometry) -> SIMD4<Float> {
        let count = geo.configuration.particleCount
        let ptr = geo.particleBuffer.contents().bindMemory(to: FlowParticle.self, capacity: count)
        var sum = SIMD4<Float>.zero, cnt = SIMD4<Float>.zero
        for i in 0..<count { let fm = Int(ptr[i].misc.x.rounded()) & 3; sum[fm] += ptr[i].misc.y; cnt[fm] += 1 }
        return sum / cnt
    }

    // A frame with per-stem AttackRatio set (the FL.14 line-character signal). vocals→strings, bass→brass,
    // other→woodwinds, drums→percussion (FL.13 hybrid mapping). Energy on the stems so the warmup gate opens.
    private func articFrame(vocalsAttack: Float, bassAttack: Float, otherAttack: Float, drumsAttack: Float,
                            t: Float) -> (FeatureVector, StemFeatures) {
        var f = FeatureVector(time: t, deltaTime: 1.0 / 60.0, aspectRatio: Float(Self.outW) / Float(Self.outH))
        f.bassDev = 0.25; f.midDev = 0.2; f.trebDev = 0.15
        var s = StemFeatures.zero
        s.vocalsEnergy = 0.3; s.bassEnergy = 0.3; s.otherEnergy = 0.3; s.drumsEnergy = 0.3
        s.vocalsAttackRatio = vocalsAttack; s.bassAttackRatio = bassAttack
        s.otherAttackRatio = otherAttack; s.drumsAttackRatio = drumsAttack
        return (f, s)
    }

    /// Feed a STACCATO strings voice (high vocals-stem AttackRatio) against a LEGATO percussion voice (low
    /// drums-stem AttackRatio) and prove the mechanism: the staccato family respawns far more often, so its
    /// mean particle age (and thus line-segment length) is much shorter — the visual "shorter choppy vs
    /// longer flowing" distinction, measured. Motion is untouched (this only sets respawn cadence).
    @Test("FL.14: staccato drives short-lived (choppy) particles; legato drives long-lived (flowing) ones")
    func test_articulation_shortensStaccatoLines() throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            print("RicercarFlowRenderTests: no Metal device — skipping"); return
        }
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let geo = try makeGeo(ctx, lib)
        let tex = try target(ctx)

        // Strings staccato (AttackRatio 2.6 → art≈1), percussion legato (0.9 → art≈0). Run 20 s to steady state.
        var t: Float = 0
        for _ in 0..<1200 {
            let (f, s) = articFrame(vocalsAttack: 2.6, bassAttack: 1.0, otherAttack: 1.0, drumsAttack: 0.9, t: t)
            _ = try frame(geo, f, s, tex, ctx); t += 1.0 / 60.0
        }
        let art = geo.currentArticulation
        let age = meanAgeByFamily(geo)
        print("[ricercar_flow] artic strings=\(String(format: "%.2f", art.x)) perc=\(String(format: "%.2f", art.w)); " +
              "meanAge strings=\(String(format: "%.2f", age.x))s perc=\(String(format: "%.2f", age.w))s")
        #expect(art.x > 0.5, "staccato strings articulation should be high (got \(art.x))")
        #expect(art.w < 0.15, "legato percussion articulation should be low (got \(art.w))")
        #expect(age.x < 1.5, "staccato family should be short-lived / choppy (mean age \(age.x)s)")
        #expect(age.w > age.x * 2.0,
                "legato family should trace much longer lines than staccato (perc \(age.w)s vs strings \(age.x)s)")
    }

    /// FL.14.1 regression guard for the FIRST LIVE MISS: real AttackRatio is baseline (~1.0) with brief,
    /// sparse spikes — NOT a held-high value. The shipped instantaneous-map + symmetric-EMA collapsed such a
    /// stream to ~0 (always-legato). The fast-attack/slow-release PEAK-HOLD must instead build and sustain a
    /// high env across a burst-dense passage. Feed a realistic staccato burst pattern (spike 3 frames, rest 12
    /// — ~20% duty, like the measured session) on strings vs a FLAT baseline on percussion, and assert the
    /// bursty family holds a high env + short life while the flat one stays legato.
    @Test("FL.14.1: sparse staccato bursts build+hold a high articulation env (not smoothed to legato)")
    func test_articulation_peakHoldSurvivesSparseBursts() throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            print("RicercarFlowRenderTests: no Metal device — skipping"); return
        }
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let geo = try makeGeo(ctx, lib)
        let tex = try target(ctx)

        var t: Float = 0
        for i in 0..<1200 {
            let burst = (i % 15) < 3          // strings: sharp attack 3 of every 15 frames (~20% duty)
            let (f, s) = articFrame(vocalsAttack: burst ? 2.5 : 1.0, bassAttack: 1.0,
                                    otherAttack: 1.0, drumsAttack: 1.0, t: t)   // percussion flat = legato
            _ = try frame(geo, f, s, tex, ctx); t += 1.0 / 60.0
        }
        let art = geo.currentArticulation, age = meanAgeByFamily(geo)
        print("[ricercar_flow] bursty strings art=\(String(format: "%.2f", art.x)) age=\(String(format: "%.2f", age.x))s; " +
              "flat perc art=\(String(format: "%.2f", art.w)) age=\(String(format: "%.2f", age.w))s")
        #expect(art.x > 0.4, "sparse bursts must HOLD a high env (regression: symmetric EMA smoothed it to ~0), got \(art.x)")
        #expect(art.w < 0.15, "flat baseline stays legato (got \(art.w))")
        #expect(age.x < age.w * 0.6, "the bursty (staccato) family must trace shorter lines (\(age.x)s vs \(age.w)s)")
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

    /// FL.14 articulation sheet (env-gated): an ALL-STACCATO field beside an ALL-LEGATO field, same drive,
    /// same moment — so Matt can eyeball "short choppy segments" vs "long flowing ribbons" as a still before
    /// the live look (the harness can't produce band-stem AttackRatio, so this is the rendered preview).
    @Test("FL.14 articulation sheet (env-gated) — staccato-choppy vs legato-flowing side by side")
    func test_articulation_contactSheet() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["RICERCAR_VISUAL"] == "1" || env["RENDER_VISUAL"] == "1" else {
            print("RicercarFlowRenderTests: RICERCAR_VISUAL/RENDER_VISUAL not set, skipping articulation sheet"); return
        }
        guard MTLCreateSystemDefaultDevice() != nil else { return }
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)

        // Render one field for 12 s at a fixed articulation, return the final frame.
        func run(attack: Float) throws -> [UInt8] {
            let geo = try makeGeo(ctx, lib)
            let tex = try target(ctx)
            var t: Float = 0, px = [UInt8]()
            for _ in 0..<720 {
                let (f, s) = articFrame(vocalsAttack: attack, bassAttack: attack, otherAttack: attack,
                                        drumsAttack: attack, t: t)
                px = try frame(geo, f, s, tex, ctx); t += 1.0 / 60.0
            }
            return px
        }
        let staccato = try run(attack: 2.8)   // all voices staccato → choppy
        let legato = try run(attack: 0.85)    // all voices legato → flowing
        let dir = try makeOutputDir()
        try writeMontage([staccato, legato], tileW: Self.outW, tileH: Self.outH,
                         url: dir.appendingPathComponent("ricercar_articulation_sheet.png"))
        print("[ricercar_articulation_sheet] \(dir.path)/ricercar_articulation_sheet.png  (LEFT staccato/choppy, RIGHT legato/flowing)")
        #expect(!staccato.isEmpty && !legato.isEmpty)
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
