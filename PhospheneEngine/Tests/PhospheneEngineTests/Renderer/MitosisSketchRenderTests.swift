// MitosisSketchRenderTests — headless go/no-go harness for the throwaway
// reaction–diffusion (Gray–Scott) cell-colony sketch (Mitosis sketch spec §8).
// Proves the gate criteria the app can't: framerate, a stable bounded field,
// flash-safe under an onset train, cells that divide AND merge (a spot-count
// metric), and — the make-or-break — that a drum onset CAUSES extra division
// (the sync handle physarum/Filigree lacked, FILIGREE_DESIGN §"sync finding").
// "Reads as synced on a real track" is a live listen (FA #27). RENDER_VISUAL=1
// dumps PNG sequences + a spot-count trajectory for the look review.

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

    /// Sustained energetic audio (fast metabolism → frequent division).
    private func energetic(_ t: Float) -> (FeatureVector, StemFeatures) {
        var f = FeatureVector(time: t, deltaTime: 1.0 / 60.0)
        f.bass = 0.6; f.mid = 0.5; f.arousal = 0.7
        var s = StemFeatures()
        s.bassEnergy = 0.6; s.drumsEnergy = 0.6; s.otherEnergy = 0.5; s.vocalsEnergy = 0.3
        return (f, s)
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

    /// Count cells = local maxima of B above a threshold, read off the RD state
    /// texture's g channel. A dividing dumbbell counts as 2 (two nuclei) even while
    /// still connected, and a packed field counts every nucleus even when cells touch —
    /// so this tracks the true cell count monotonically, unlike connected components.
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
                // Strict local max over the 8-neighbourhood (>= with a tie-break to the
                // lower index so a flat-topped nucleus is counted once, not N times).
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
        let geo = try makeGeo(ctx, lib, MitosisConfiguration(), pixelFormat: ctx.pixelFormat)
        let tex = try target(ctx, 1920, 1080)
        var t: Float = 0
        for _ in 0..<60 { let (f, s) = energetic(t); try frame(geo, f, s, tex, ctx); t += 1.0 / 60.0 }
        var times: [Double] = []
        for _ in 0..<120 { let (f, s) = energetic(t); times.append(try frame(geo, f, s, tex, ctx)); t += 1.0 / 60.0 }
        times.sort()
        let median = times[times.count / 2]
        print(String(format: "[MITO] 320×180 sim, ≤20 substeps @1080p: median %.2f ms/frame (min %.2f, max %.2f) — budget 16.67",
                     median, times.first ?? 0, times.last ?? 0))
        #expect(median < 16.67, "must hold 60 fps: median \(median) ms")

        // Headroom probe at a denser sim grid (reported, not gated).
        let big = try makeGeo(ctx, lib, MitosisConfiguration(width: 640, height: 360), pixelFormat: ctx.pixelFormat)
        for _ in 0..<30 { let (f, s) = energetic(t); try frame(big, f, s, tex, ctx); t += 1.0 / 60.0 }
        var bt: [Double] = []
        for _ in 0..<60 { let (f, s) = energetic(t); bt.append(try frame(big, f, s, tex, ctx)); t += 1.0 / 60.0 }
        bt.sort()
        print(String(format: "[MITO] 640×360 sim @1080p: median %.2f ms/frame", bt[bt.count / 2]))
    }

    // MARK: - Criterion 2: stable, bounded field

    @Test("Field stays bounded and structured — no blow-up, no all-on/all-off")
    func test_stability() throws {
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let cfg = MitosisConfiguration()
        let geo = try makeGeo(ctx, lib, cfg, pixelFormat: ctx.pixelFormat)
        let tex = try target(ctx, cfg.width, cfg.height)
        var t: Float = 0
        for _ in 0..<900 { let (f, s) = energetic(t); try frame(geo, f, s, tex, ctx); t += 1.0 / 60.0 }

        // State stays finite and in [0,1] (clamped in-shader; verify no NaN leak).
        var px = [Float16](repeating: 0, count: cfg.width * cfg.height * 2)
        geo.currentStateTexture.getBytes(&px, bytesPerRow: cfg.width * 2 * MemoryLayout<Float16>.stride,
                                         from: MTLRegionMake2D(0, 0, cfg.width, cfg.height), mipmapLevel: 0)
        var bad = false
        for v in px where !Float(v).isFinite || Float(v) < -0.01 || Float(v) > 1.01 { bad = true; break }
        #expect(!bad, "RD field must stay finite and bounded in [0,1]")

        // Not degenerate: a healthy population of spots, neither empty nor saturated.
        let spots = spotCount(geo, cfg.width, cfg.height)
        let mean = lumaMean(tex, cfg.width, cfg.height)
        print("[MITO] steady-state: spots=\(spots) lumaMean=\(String(format: "%.3f", mean))")
        #expect(spots > 5, "colony must have many distinct cells, not collapse: spots \(spots)")
        #expect(mean > 0.02 && mean < 0.70, "field must be bounded, not blown-out/empty: mean \(mean)")
    }

    // MARK: - Criterion 4: divide AND merge

    /// Quiet → loud → quiet. Louder = faster metabolism = more division (spot count
    /// rises); quieter lets spots merge/settle (count falls). Both directions must show.
    @Test("Cells divide (count rises with energy) and merge (count falls)")
    func test_divideAndMerge() throws {
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let cfg = MitosisConfiguration()
        let geo = try makeGeo(ctx, lib, cfg, pixelFormat: ctx.pixelFormat)
        let tex = try target(ctx, cfg.width, cfg.height)
        var t: Float = 0
        func hold(_ lvl: Float, _ frames: Int) throws {
            for _ in 0..<frames {
                var f = FeatureVector(time: t, deltaTime: 1.0 / 60.0); f.bass = lvl; f.mid = lvl * 0.85
                var s = StemFeatures()
                s.bassEnergy = lvl; s.drumsEnergy = lvl; s.otherEnergy = lvl * 0.8; s.vocalsEnergy = lvl * 0.5
                try frame(geo, f, s, tex, ctx); t += 1.0 / 60.0
            }
        }
        try hold(0.10, 600); let quietA = spotCount(geo, cfg.width, cfg.height)
        try hold(0.85, 600); let loud = spotCount(geo, cfg.width, cfg.height)
        try hold(0.10, 600); let quietB = spotCount(geo, cfg.width, cfg.height)
        print("[MITO] divide/merge: quiet=\(quietA) → loud=\(loud) → quiet=\(quietB)")
        #expect(loud > quietA, "loud must drive more division than quiet: \(loud) vs \(quietA)")
        #expect(quietB < loud, "quieting must let cells merge/settle back: \(quietB) vs \(loud)")
    }

    // MARK: - Criterion: onset CAUSES division (the make-or-break sync mechanism)

    /// A/B causal proof. Two identically-seeded colonies settle to the same state,
    /// then one receives a drum-onset train and the other doesn't. The onset run must
    /// show measurably more division — this is the mechanism physarum/Filigree lacked
    /// (FILIGREE §"sync finding"). Whether it READS as locked is the live gate (FA #27).
    @Test("Drum onsets cause extra mitosis vs the no-onset control")
    func test_onsetCausesDivision() throws {
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let cfg = MitosisConfiguration()
        let onset = try makeGeo(ctx, lib, cfg, pixelFormat: ctx.pixelFormat)
        let control = try makeGeo(ctx, lib, cfg, pixelFormat: ctx.pixelFormat)
        let tex = try target(ctx, cfg.width, cfg.height)
        var t: Float = 0

        // Settle both identically (no onsets) to the same moderate-energy state.
        func settle(_ g: MitosisGeometry) throws {
            var tt = t
            for _ in 0..<360 {
                var f = FeatureVector(time: tt, deltaTime: 1.0 / 60.0); f.bass = 0.45; f.mid = 0.38
                var s = StemFeatures(); s.bassEnergy = 0.45; s.drumsEnergy = 0.45; s.otherEnergy = 0.36; s.vocalsEnergy = 0.27
                try frame(g, f, s, tex, ctx); tt += 1.0 / 60.0
            }
        }
        try settle(onset); try settle(control)
        let onset0 = spotCount(onset, cfg.width, cfg.height)
        let ctrl0 = spotCount(control, cfg.width, cfg.height)

        // 240 frames: `onset` gets a ~2.5 Hz drum train; `control` stays flat.
        var tt = t
        for fr in 0..<240 {
            let phase = fr % 24
            var f = FeatureVector(time: tt, deltaTime: 1.0 / 60.0); f.bass = 0.45; f.mid = 0.38
            var sOn = StemFeatures(); sOn.bassEnergy = 0.45; sOn.drumsEnergy = 0.45; sOn.otherEnergy = 0.36; sOn.vocalsEnergy = 0.27
            var sOff = sOn
            sOn.drumsEnergyDev = phase < 2 ? 1.2 : (phase < 6 ? 0.3 : 0.02)
            sOff.drumsEnergyDev = 0.02
            try frame(onset, f, sOn, tex, ctx)
            try frame(control, f, sOff, tex, ctx)
            tt += 1.0 / 60.0
        }
        let onset1 = spotCount(onset, cfg.width, cfg.height)
        let ctrl1 = spotCount(control, cfg.width, cfg.height)
        let onsetGain = onset1 - onset0, ctrlGain = ctrl1 - ctrl0
        print("[MITO] onset-causes-division: onset \(onset0)→\(onset1) (Δ\(onsetGain)) | control \(ctrl0)→\(ctrl1) (Δ\(ctrlGain)) | hitEnv-fires=\(onset.currentHitEnv > control.currentHitEnv)")
        // The onset envelope must actually fire (the event channel is wired).
        #expect(onset.currentHitEnv > 0.1, "onset envelope must fire on the drum train: \(onset.currentHitEnv)")
        // And it must produce more division than the identical no-onset colony.
        #expect(onsetGain > ctrlGain, "drum onsets must cause more mitosis than the control: Δ\(onsetGain) vs Δ\(ctrlGain)")
    }

    // MARK: - Criterion: flash-safe under a worst-case onset train (D-157)

    @Test("Onset train holds global luminance bounded — no strobe (D-157)")
    func test_flashSafe() throws {
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let cfg = MitosisConfiguration()
        let geo = try makeGeo(ctx, lib, cfg, pixelFormat: ctx.pixelFormat)
        let tex = try target(ctx, cfg.width, cfg.height)
        var t: Float = 0
        // Settle, then a relentless ~4 Hz onset train (worst case).
        for _ in 0..<360 { let (f, s) = energetic(t); try frame(geo, f, s, tex, ctx); t += 1.0 / 60.0 }
        var lumas: [Float] = []; var prev = lumaMean(tex, cfg.width, cfg.height); var maxDelta: Float = 0
        for fr in 0..<240 {
            var f = FeatureVector(time: t, deltaTime: 1.0 / 60.0); f.bass = 0.6; f.mid = 0.5
            var s = StemFeatures(); s.bassEnergy = 0.6; s.drumsEnergy = 0.6; s.otherEnergy = 0.5; s.vocalsEnergy = 0.3
            s.drumsEnergyDev = (fr % 15) < 2 ? 1.4 : 0.03   // ~4 Hz
            try frame(geo, f, s, tex, ctx)
            let m = lumaMean(tex, cfg.width, cfg.height)
            lumas.append(m); maxDelta = max(maxDelta, abs(m - prev)); prev = m
            t += 1.0 / 60.0
        }
        lumas.sort()
        let median = lumas[lumas.count / 2], lo = lumas.first ?? 0, hi = lumas.last ?? 0
        print(String(format: "[MITO] flash-safe: luma median %.3f (min %.3f, max %.3f) maxΔ/frame %.3f", median, lo, hi, maxDelta))
        #expect(maxDelta < 0.10, "onset must not strobe frame-to-frame: maxΔ \(maxDelta)")
        #expect(hi < 1.4 * median, "onset must not flash global luminance up: max \(hi) vs median \(median)")
        #expect(lo > 0.6 * median, "onset must not crater global luminance: min \(lo) vs median \(median)")
    }

    // MARK: - Look + metric (RENDER_VISUAL=1)

    @Test("Render divide/merge arc + onset frames (RENDER_VISUAL=1)")
    func test_render() throws {
        guard ProcessInfo.processInfo.environment["RENDER_VISUAL"] == "1" else { return }
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let cfg = MitosisConfiguration()
        let geo = try makeGeo(ctx, lib, cfg, pixelFormat: ctx.pixelFormat)
        let w = cfg.width, h = cfg.height
        let tex = try target(ctx, w, h)
        var base = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { base.deleteLastPathComponent() }
        let dir = base.appendingPathComponent("tools/mitosis_sketch/frames", isDirectory: true)
        let seqDir = dir.appendingPathComponent("motion", isDirectory: true)
        try? FileManager.default.createDirectory(at: seqDir, withIntermediateDirectories: true)
        var t: Float = 0; var seq = 0

        // Arc: quiet (merge) → surge w/ onsets (divide burst) → quiet → surge.
        func levelAt(_ s: Float) -> Float {
            if s < 5 { return 0.10 }
            if s < 12 { return 0.85 }
            if s < 17 { return 0.10 }
            if s < 24 { return 0.85 }
            return 0.10
        }
        let shots: [(Float, String)] = [(4.5, "0_quiet_merged"), (8.0, "1_onset_divide"), (12.5, "2_loud_teeming"),
                                        (16.5, "3_merged_again"), (23.0, "4_onset_divide2")]
        var si = 0
        let total = 25 * 60
        for fr in 0..<total {
            let s = Float(fr) / 60; let lvl = levelAt(s)
            var f = FeatureVector(time: t, deltaTime: 1.0 / 60.0); f.bass = lvl; f.mid = lvl * 0.85
            var st = StemFeatures()
            st.bassEnergy = lvl; st.drumsEnergy = lvl; st.otherEnergy = lvl * 0.8; st.vocalsEnergy = lvl * 0.5
            st.drumsEnergyDev = (fr % 24) < 2 ? 1.2 * lvl : 0.02   // onsets only when loud
            try frame(geo, f, st, tex, ctx); t += 1.0 / 60.0
            if fr % 4 == 0 { try writePNG(tex, w, h, seqDir.appendingPathComponent(String(format: "f_%03d.png", seq))); seq += 1 }
            if si < shots.count, s >= shots[si].0 {
                let spots = spotCount(geo, w, h)
                print("[MITO] arc \(shots[si].1): energy=\(String(format: "%.2f", geo.currentEnergyEnv)) spots=\(spots)")
                try writePNG(tex, w, h, dir.appendingPathComponent("mito_\(shots[si].1).png"))
                si += 1
            }
        }
        print("[MITO] motion frames: \(seqDir.path)")
    }

    /// Empirical regime probe (RENDER_VISUAL=1): sweep published (F,k) pairs with NO
    /// audio coupling, fixed substeps, and report autonomous spot count + a frame each.
    /// Picks the regime whose RESTING colony self-sustains a living, dividing field
    /// (not extinction, not a frozen blob). Data over first-principles guessing (FA #64).
    @Test("Probe RD regimes for an autonomous dividing colony (RENDER_VISUAL=1)")
    func test_regimeProbe() throws {
        guard ProcessInfo.processInfo.environment["RENDER_VISUAL"] == "1" else { return }
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let w = 320, h = 180
        let tex = try target(ctx, w, h)
        var base = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { base.deleteLastPathComponent() }
        let dir = base.appendingPathComponent("tools/mitosis_sketch/frames/regimes", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // (F, k, label) — published reaction–diffusion regimes (mrob Xmorphia / Sims).
        let regimes: [(Float, Float, String)] = [
            (0.0367, 0.0649, "mitosis"),
            (0.0545, 0.0620, "coral"),
            (0.0300, 0.0620, "spots_a"),
            (0.0250, 0.0600, "spots_b"),
            (0.0390, 0.0580, "worms"),
            (0.0340, 0.0630, "uskate"),
            (0.0420, 0.0610, "bubbles"),
            (0.0290, 0.0570, "holes")
        ]
        for (fF, kK, label) in regimes {
            // Fixed metabolism, no audio coupling: just settle the pure RD.
            let geo = try makeGeo(ctx, lib, MitosisConfiguration(feed: fF, kill: kK), pixelFormat: ctx.pixelFormat)
            var t: Float = 0
            // ~3000 iterations (300 frames × 10 substeps at rest energy 0).
            for _ in 0..<300 {
                var f = FeatureVector(time: t, deltaTime: 1.0 / 60.0); f.bass = 0; f.mid = 0
                try frame(geo, f, StemFeatures(), tex, ctx); t += 1.0 / 60.0
            }
            let spots = spotCount(geo, w, h)
            print("[MITO] regime \(label) (F=\(fF) k=\(kK)): autonomous spots=\(spots)")
            try writePNG(tex, w, h, dir.appendingPathComponent("\(label)_F\(fF)_k\(kK).png"))
        }
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
