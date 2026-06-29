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

    /// The B field as a flat [Float] (g channel) — for the activity (churn-vs-freeze) metric.
    private func bField(_ geo: MitosisGeometry, _ w: Int, _ h: Int) -> [Float] {
        var px = [Float16](repeating: 0, count: w * h * 2)
        geo.currentStateTexture.getBytes(&px, bytesPerRow: w * 2 * MemoryLayout<Float16>.stride,
                                         from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        var out = [Float](repeating: 0, count: w * h)
        for i in 0..<(w * h) { out[i] = Float(px[i * 2 + 1]) }
        return out
    }

    /// MITOSIS.2 diagnosis — does a regime CHURN (continuous division + death) or FREEZE
    /// to a static packed grid? Seeds a couple of cells, runs 30 s at the real track's
    /// steady ~0.4 energy (no onsets — isolate substrate dynamics), and reports the
    /// spot-count trajectory + end-of-run field activity (mean |ΔB|/frame ≈ 0 ⇒ frozen).
    /// Live M7: the shipped u-skate regime fills then freezes; we want a perpetually
    /// dynamic one. (RENDER_VISUAL=1.)
    @Test("Probe RD regimes for churn-not-freeze from a sparse seed (RENDER_VISUAL=1)")
    func test_regimeProbeDynamic() throws {
        guard ProcessInfo.processInfo.environment["RENDER_VISUAL"] == "1" else { return }
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let w = 320, h = 180
        let tex = try target(ctx, w, h)
        var base = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { base.deleteLastPathComponent() }
        let dir = base.appendingPathComponent("tools/mitosis_sketch/frames/dynamic", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // (F, k, label) — spread across the spot→chaos boundary.
        let regimes: [(Float, Float, String)] = [
            (0.034, 0.0630, "0_current"), (0.034, 0.0645, "1_hiK"),
            (0.030, 0.0620, "2"), (0.026, 0.0600, "3"), (0.026, 0.0555, "4"),
            (0.038, 0.0620, "5"), (0.042, 0.0635, "6"), (0.046, 0.0648, "7"),
            (0.022, 0.0510, "8"), (0.030, 0.0565, "9")
        ]
        for (fF, kK, label) in regimes {
            let geo = try makeGeo(ctx, lib, MitosisConfiguration(feed: fF, kill: kK, seedBlobs: 3),
                                  pixelFormat: ctx.pixelFormat)
            var t: Float = 0
            func runTo(_ frames: Int) throws {
                while Int(t * 60) < frames {
                    var f = FeatureVector(time: t, deltaTime: 1.0 / 60.0); f.bass = 0.4; f.mid = 0.34
                    var s = StemFeatures()
                    s.bassEnergy = 0.4; s.drumsEnergy = 0.4; s.otherEnergy = 0.32; s.vocalsEnergy = 0.24
                    try frame(geo, f, s, tex, ctx); t += 1.0 / 60.0
                }
            }
            try runTo(300);  let c5 = spotCount(geo, w, h)
            try writePNG(tex, w, h, dir.appendingPathComponent("\(label)_05s.png"))
            try runTo(900);  let c15 = spotCount(geo, w, h)
            try runTo(1800); let c30 = spotCount(geo, w, h)
            try writePNG(tex, w, h, dir.appendingPathComponent("\(label)_30s.png"))
            // Activity over the final 60 frames: mean per-cell |ΔB|. Frozen ⇒ ≈ 0.
            var prev = bField(geo, w, h); var activity: Float = 0
            for _ in 0..<60 {
                var f = FeatureVector(time: t, deltaTime: 1.0 / 60.0); f.bass = 0.4; f.mid = 0.34
                var s = StemFeatures()
                s.bassEnergy = 0.4; s.drumsEnergy = 0.4; s.otherEnergy = 0.32; s.vocalsEnergy = 0.24
                try frame(geo, f, s, tex, ctx); t += 1.0 / 60.0
                let cur = bField(geo, w, h)
                var d: Float = 0; for i in 0..<cur.count { d += abs(cur[i] - prev[i]) }
                activity += d / Float(cur.count); prev = cur
            }
            activity /= 60
            print(String(format: "[MITO] dyn %@ (F=%.3f k=%.4f): spots 5s=%d 15s=%d 30s=%d | end-activity=%.5f%@",
                         label, fF, kK, c5, c15, c30, activity, activity < 0.0008 ? "  ← FROZEN" : "  ← churning"))
        }
        print("[MITO] dynamic-probe frames: \(dir.path)")
    }

    /// MITOSIS.2 fix probe — with onset-driven k-oscillation, does the field sustain a
    /// divide↔merge CHURN under a realistic drum-onset train (the real track fired onsets
    /// in 58.9% of frames)? Sweeps base k from a sparse seed; reports spot range (must go
    /// UP and DOWN = divide AND merge), survival, and end activity (must stay > 0 =
    /// not frozen). (RENDER_VISUAL=1.)
    @Test("Probe onset-driven divide/merge churn vs base k (RENDER_VISUAL=1)")
    func test_onsetChurnProbe() throws {
        guard ProcessInfo.processInfo.environment["RENDER_VISUAL"] == "1" else { return }
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let w = 320, h = 180
        let tex = try target(ctx, w, h)
        var base = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { base.deleteLastPathComponent() }
        let dir = base.appendingPathComponent("tools/mitosis_sketch/frames/churn", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        for baseK: Float in [0.0615, 0.0625, 0.0635, 0.0645, 0.0655] {
            let geo = try makeGeo(ctx, lib, MitosisConfiguration(feed: 0.034, kill: baseK, seedBlobs: 3),
                                  pixelFormat: ctx.pixelFormat)
            var t: Float = 0; var loSpot = 99999; var hiSpot = 0; var samples: [Int] = []
            // ~2.1 Hz drum-onset train + steady 0.4 energy (the live track's profile).
            func step() throws {
                let ph = Int(t * 60) % 28
                var f = FeatureVector(time: t, deltaTime: 1.0 / 60.0); f.bass = 0.4; f.mid = 0.34
                var s = StemFeatures()
                s.bassEnergy = 0.4; s.drumsEnergy = 0.4; s.otherEnergy = 0.32; s.vocalsEnergy = 0.24
                s.drumsEnergyDev = ph < 2 ? 1.2 : 0.05
                try frame(geo, f, s, tex, ctx); t += 1.0 / 60.0
            }
            for fr in 0..<1800 {
                try step()
                if fr > 300 && fr % 30 == 0 {           // after the initial populate transient
                    let c = spotCount(geo, w, h); loSpot = min(loSpot, c); hiSpot = max(hiSpot, c); samples.append(c)
                }
                if fr == 300 { try writePNG(tex, w, h, dir.appendingPathComponent(String(format: "k%.4f_05s.png", baseK))) }
                if fr == 1799 { try writePNG(tex, w, h, dir.appendingPathComponent(String(format: "k%.4f_30s.png", baseK))) }
            }
            var prev = bField(geo, w, h); var activity: Float = 0
            for _ in 0..<60 { try step(); let cur = bField(geo, w, h)
                var d: Float = 0; for i in 0..<cur.count { d += abs(cur[i] - prev[i]) }
                activity += d / Float(cur.count); prev = cur }
            activity /= 60
            let mean = samples.isEmpty ? 0 : samples.reduce(0, +) / samples.count
            print(String(format: "[MITO] churn baseK=%.4f: spots lo=%d hi=%d mean=%d swing=%d | activity=%.5f %@",
                         baseK, loSpot, hiSpot, mean, hiSpot - loSpot, activity,
                         activity > 0.0008 && loSpot > 3 && (hiSpot - loSpot) > 15 ? "← CHURNS" : ""))
        }
        print("[MITO] churn frames: \(dir.path)")
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

    // MARK: - Onset-driven churn helpers (MITOSIS.2)

    /// One frame at a fixed tempo: the continuous cached-grid `beatPhase01` always
    /// advances (this is the primary churn driver, MITOSIS.2b), with `onsets` toggling
    /// whether the track is percussive (drum-hit accents on the beat) or sparse/ambient
    /// (grid only). 117 BPM matches the "deep sea dive" failure track (session 20-21-43Z).
    private func churnStep(_ geo: MitosisGeometry, _ energy: Float, onsets: Bool,
                           _ tex: MTLTexture, _ ctx: MetalContext, _ t: inout Float, bpm: Float = 117) throws {
        let beatPhase = (t * bpm / 60).truncatingRemainder(dividingBy: 1)
        var f = FeatureVector(time: t, deltaTime: 1.0 / 60.0); f.bass = energy; f.mid = energy * 0.85
        f.beatPhase01 = beatPhase
        var s = StemFeatures()
        s.bassEnergy = energy; s.drumsEnergy = energy; s.otherEnergy = energy * 0.8; s.vocalsEnergy = energy * 0.5
        s.drumsEnergyDev = onsets ? (beatPhase < 0.07 ? 1.2 : 0.05) : 0.02   // a drum hit at each beat, or none
        try frame(geo, f, s, tex, ctx); t += 1.0 / 60.0
    }

    /// Mean per-cell |ΔB|/frame over `frames` driven frames — ≈ 0 ⇒ frozen, > 0 ⇒ churning.
    private func churnActivity(_ geo: MitosisGeometry, _ w: Int, _ h: Int, energy: Float, onsets: Bool,
                               frames: Int, _ tex: MTLTexture, _ ctx: MetalContext, _ t: inout Float) throws -> Float {
        var prev = bField(geo, w, h); var act: Float = 0
        for _ in 0..<frames {
            try churnStep(geo, energy, onsets: onsets, tex, ctx, &t)
            let cur = bField(geo, w, h)
            var d: Float = 0; for i in 0..<cur.count { d += abs(cur[i] - prev[i]) }
            act += d / Float(cur.count); prev = cur
        }
        return act / Float(frames)
    }

    // MARK: - Criterion: churns — divides AND merges, never freezes (the MITOSIS.2 fix)

    /// The live-M7 failure was fill-to-a-static-grid-then-freeze. Under an onset train the
    /// field must stay alive + bounded, keep CHURNING (activity > 0), and its cell count
    /// must SWING (cells both divide and die) — not lock into a static lattice.
    @Test("Field churns — divides AND merges, bounded, never freezes (MITOSIS.2)")
    func test_churnsNotFreezes() throws {
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let cfg = MitosisConfiguration()
        let geo = try makeGeo(ctx, lib, cfg, pixelFormat: ctx.pixelFormat)
        let tex = try target(ctx, cfg.width, cfg.height)
        var t: Float = 0
        for _ in 0..<600 { try churnStep(geo, 0.55, onsets: true, tex, ctx, &t) }   // populate from the seed

        // Finite + bounded in [0,1] (clamped in-shader; verify no NaN leak).
        var px = [Float16](repeating: 0, count: cfg.width * cfg.height * 2)
        geo.currentStateTexture.getBytes(&px, bytesPerRow: cfg.width * 2 * MemoryLayout<Float16>.stride,
                                         from: MTLRegionMake2D(0, 0, cfg.width, cfg.height), mipmapLevel: 0)
        var bad = false
        for v in px where !Float(v).isFinite || Float(v) < -0.01 || Float(v) > 1.01 { bad = true; break }
        #expect(!bad, "RD field must stay finite and bounded in [0,1]")

        // Cell count swings (divide AND merge) over a steady onset section; stays alive.
        var lo = 99999, hi = 0
        for fr in 0..<600 {
            try churnStep(geo, 0.55, onsets: true, tex, ctx, &t)
            if fr % 30 == 0 { let c = spotCount(geo, cfg.width, cfg.height); lo = min(lo, c); hi = max(hi, c) }
        }
        let mean = lumaMean(tex, cfg.width, cfg.height)
        var t2 = t
        let activity = try churnActivity(geo, cfg.width, cfg.height, energy: 0.55, onsets: true, frames: 60, tex, ctx, &t2)
        print("[MITO] churn: spots lo=\(lo) hi=\(hi) swing=\(hi - lo) lumaMean=\(String(format: "%.3f", mean)) activity=\(String(format: "%.5f", activity))")
        #expect(lo > 5, "colony must stay alive under onsets: min spots \(lo)")
        #expect(mean > 0.02 && mean < 0.75, "field must be bounded, not blown-out/empty: lumaMean \(mean)")
        #expect(activity > 0.0008, "field must keep churning, not freeze to a static grid: activity \(activity)")
        #expect(hi - lo > 15, "cells must both divide and merge (count must swing): swing \(hi - lo)")
    }

    /// Density tracks energy: loud teems, quiet thins — but quiet stays alive (the
    /// energy-survival floor), so a drum-sparse section doesn't kill the colony.
    @Test("Density tracks energy under onsets (loud teems, quiet thins but survives)")
    func test_densityTracksEnergy() throws {
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let cfg = MitosisConfiguration()
        let geo = try makeGeo(ctx, lib, cfg, pixelFormat: ctx.pixelFormat)
        let tex = try target(ctx, cfg.width, cfg.height)
        var t: Float = 0
        func holdMean(_ lvl: Float) throws -> Int {
            for _ in 0..<600 { try churnStep(geo, lvl, onsets: true, tex, ctx, &t) }
            var s: [Int] = []
            for fr in 0..<120 { try churnStep(geo, lvl, onsets: true, tex, ctx, &t); if fr % 20 == 0 { s.append(spotCount(geo, cfg.width, cfg.height)) } }
            return s.reduce(0, +) / s.count
        }
        let loud = try holdMean(0.80), quiet = try holdMean(0.22)
        print("[MITO] density: loud=\(loud) quiet=\(quiet)")
        #expect(loud > quiet, "loud must teem denser than quiet: \(loud) vs \(quiet)")
        #expect(quiet > 0, "quiet must stay alive (energy-survival floor): \(quiet)")
    }

    // MARK: - Criterion: the grid drives the churn ROBUSTLY across track types (MITOSIS.2b)

    /// The "deep sea dive" failure was a non-percussive track (drum onsets in 0.6% of
    /// frames) collapsing the onset-driven field to near-empty. The grid-phase driver
    /// must keep the field churning on BOTH a drum-heavy AND a sparse/ambient track —
    /// the cached beat grid advances either way. This is the robustness proof.
    @Test("Grid drives churn on both drum-heavy AND sparse tracks (MITOSIS.2b)")
    func test_churnsOnBothProfiles() throws {
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let cfg = MitosisConfiguration()
        let tex = try target(ctx, cfg.width, cfg.height)
        for (label, onsets) in [("drum-heavy", true), ("sparse/ambient", false)] {
            let geo = try makeGeo(ctx, lib, cfg, pixelFormat: ctx.pixelFormat)
            var t: Float = 0
            for _ in 0..<600 { try churnStep(geo, 0.35, onsets: onsets, tex, ctx, &t) }
            var lo = 99999, hi = 0
            for fr in 0..<360 { try churnStep(geo, 0.35, onsets: onsets, tex, ctx, &t)
                if fr % 30 == 0 { let c = spotCount(geo, cfg.width, cfg.height); lo = min(lo, c); hi = max(hi, c) } }
            var t2 = t
            let activity = try churnActivity(geo, cfg.width, cfg.height, energy: 0.35, onsets: onsets, frames: 90, tex, ctx, &t2)
            print("[MITO] profile \(label): spots lo=\(lo) hi=\(hi) swing=\(hi - lo) activity=\(String(format: "%.5f", activity))")
            #expect(lo > 5, "[\(label)] colony must stay alive (not a deep-sea-dive): min spots \(lo)")
            #expect(activity > 0.0008, "[\(label)] field must churn, not freeze: activity \(activity)")
            #expect(hi - lo > 10, "[\(label)] cells must divide AND merge (count must swing): swing \(hi - lo)")
        }
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
        // Populate a LIVE churning field with onsets (settling without onsets would die
        // and make this a false pass on an empty ground), then measure under a relentless
        // ~4 Hz onset train (worst case).
        for _ in 0..<600 { try churnStep(geo, 0.6, onsets: true, tex, ctx, &t) }
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

        // Production-coupling arc: a steady ~2.1 Hz drum-onset train throughout (real
        // music always has the beat), with the continuous-energy envelope swinging
        // quiet↔loud. Captures the sparse-seed populate, the loud teem, and the quiet thin.
        func levelAt(_ s: Float) -> Float {
            if s < 8 { return 0.45 }       // populate from the couple of seed cells
            if s < 15 { return 0.85 }      // loud → teeming
            if s < 21 { return 0.18 }      // quiet → thin but alive
            return 0.85
        }
        let shots: [(Float, String)] = [(2.0, "0_seed_dividing"), (6.0, "1_populated"), (12.0, "2_loud_teeming"),
                                        (19.0, "3_quiet_thinned"), (25.0, "4_loud_again")]
        var si = 0
        let total = 27 * 60
        for fr in 0..<total {
            try churnStep(geo, levelAt(Float(fr) / 60), onsets: true, tex, ctx, &t)
            if fr % 4 == 0 { try writePNG(tex, w, h, seqDir.appendingPathComponent(String(format: "f_%03d.png", seq))); seq += 1 }
            if si < shots.count, Float(fr) / 60 >= shots[si].0 {
                print("[MITO] arc \(shots[si].1): energy=\(String(format: "%.2f", geo.currentEnergyEnv)) spots=\(spotCount(geo, w, h))")
                try writePNG(tex, w, h, dir.appendingPathComponent("mito_\(shots[si].1).png"))
                si += 1
            }
        }
        print("[MITO] motion frames: \(seqDir.path)")

        // The "deep sea dive" failure case: a sparse/ambient track (grid only, NO drum
        // onsets) at the failure track's ~0.3 energy — must read as a living churning
        // colony, not a few dots drifting in the dark.
        let sparse = try makeGeo(ctx, lib, cfg, pixelFormat: ctx.pixelFormat)
        var ts: Float = 0
        for fr in 0..<1200 {
            try churnStep(sparse, 0.32, onsets: false, tex, ctx, &ts)
            if fr == 360 || fr == 1199 {
                print("[MITO] sparse-profile @\(fr): spots=\(spotCount(sparse, w, h))")
                try writePNG(tex, w, h, dir.appendingPathComponent("mito_sparse_\(fr).png"))
            }
        }
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
