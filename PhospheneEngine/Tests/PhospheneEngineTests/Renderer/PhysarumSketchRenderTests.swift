// PhysarumSketchRenderTests — headless go/no-go harness for the throwaway
// physarum agent-network sketch (Physarum sketch spec §7). Proves three of the
// four gate criteria without the app: framerate (GPU frame time @ 1080p),
// a stable bounded network, and flash-safe collapse-regrow (steady global
// luminance). The fourth — "energy→consolidation reads as locked on a real
// track" — is a live Phase-2 listen (FA #27: automated tests prove pipeline,
// not feel). RENDER_VISUAL=1 dumps PNG sequences for the look review.

import Testing
import Metal
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation
@testable import Renderer
@testable import Shared

@Suite("Physarum sketch (agent network)")
struct PhysarumSketchRenderTests {

    private enum E: Error { case setup, render, png }

    // MARK: - Helpers

    private func makeGeo(_ ctx: MetalContext, _ lib: ShaderLibrary,
                         _ cfg: PhysarumConfiguration, pixelFormat: MTLPixelFormat?) throws -> PhysarumGeometry {
        try PhysarumGeometry(device: ctx.device, library: lib.library, configuration: cfg, pixelFormat: pixelFormat)
    }

    /// Sustained energetic audio (drives consolidation → veins).
    private func energetic(_ t: Float) -> (FeatureVector, StemFeatures) {
        var f = FeatureVector(time: t, deltaTime: 1.0 / 60.0)
        f.bass = 0.6; f.mid = 0.5; f.arousal = 0.7
        var s = StemFeatures()
        s.bassEnergy = 0.6; s.drumsEnergy = 0.6; s.otherEnergy = 0.5; s.vocalsEnergy = 0.3
        return (f, s)
    }

    /// One frame: update (compute) + render (draw) into `tex`. Returns GPU time (ms).
    @discardableResult
    private func frame(_ geo: PhysarumGeometry, _ f: FeatureVector, _ s: StemFeatures,
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

    /// Mean + variance of luminance over a rendered BGRA frame (0..1).
    private func lumaStats(_ tex: MTLTexture, _ w: Int, _ h: Int) -> (mean: Float, variance: Float) {
        var px = [UInt8](repeating: 0, count: w * h * 4)
        tex.getBytes(&px, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        var sum: Float = 0, sumSq: Float = 0
        let n = w * h
        for i in 0..<n {
            let b = Float(px[i * 4 + 0]), g = Float(px[i * 4 + 1]), r = Float(px[i * 4 + 2])
            let l = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
            sum += l; sumSq += l * l
        }
        let mean = sum / Float(n)
        return (mean, sumSq / Float(n) - mean * mean)
    }

    // MARK: - Criterion 1: framerate

    @Test("Holds the 60 fps frame budget @ 1080p (262k agents, 1280×720 sim)")
    func test_framerate() throws {
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let geo = try makeGeo(ctx, lib, PhysarumConfiguration(), pixelFormat: ctx.pixelFormat)
        let tex = try target(ctx, 1920, 1080)
        var t: Float = 0
        for _ in 0..<60 { let (f, s) = energetic(t); try frame(geo, f, s, tex, ctx); t += 1.0 / 60.0 }  // warmup
        var times: [Double] = []
        for _ in 0..<120 { let (f, s) = energetic(t); times.append(try frame(geo, f, s, tex, ctx)); t += 1.0 / 60.0 }
        times.sort()
        let median = times[times.count / 2]
        print(String(format: "[PHYS] 262k agents @1080p: median %.2f ms/frame (min %.2f, max %.2f) — 60fps budget 16.67 ms",
                     median, times.first ?? 0, times.last ?? 0))
        #expect(median < 16.67, "must hold 60 fps: median \(median) ms")

        // Headroom probe at 1M agents (spec §4 stretch — reported, not gated).
        let big = try makeGeo(ctx, lib, PhysarumConfiguration(agentCount: 1_048_576), pixelFormat: ctx.pixelFormat)
        for _ in 0..<30 { let (f, s) = energetic(t); try frame(big, f, s, tex, ctx); t += 1.0 / 60.0 }
        var bt: [Double] = []
        for _ in 0..<60 { let (f, s) = energetic(t); bt.append(try frame(big, f, s, tex, ctx)); t += 1.0 / 60.0 }
        bt.sort()
        print(String(format: "[PHYS] 1M agents @1080p: median %.2f ms/frame", bt[bt.count / 2]))
    }

    // MARK: - Criterion 2: stable, bounded network

    @Test("Network stays bounded and structured — no blow-up, no degenerate clumping")
    func test_stability() throws {
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let cfg = PhysarumConfiguration()
        let geo = try makeGeo(ctx, lib, cfg, pixelFormat: ctx.pixelFormat)
        let tex = try target(ctx, 640, 360)
        var t: Float = 0
        for _ in 0..<600 { let (f, s) = energetic(t); try frame(geo, f, s, tex, ctx); t += 1.0 / 60.0 }

        // Agents stay finite and in-bounds (direct numeric blow-up check).
        let n = cfg.agentCount
        let ptr = geo.agentBuffer.contents().bindMemory(to: PhysAgent.self, capacity: n)
        var bad = false
        for i in stride(from: 0, to: n, by: 37) {   // sample — 262k is plenty
            let a = ptr[i]
            if !a.positionX.isFinite || !a.positionY.isFinite || !a.heading.isFinite { bad = true; break }
            if a.positionX < 0 || a.positionX > Float(cfg.width) || a.positionY < 0 || a.positionY > Float(cfg.height) { bad = true; break }
        }
        #expect(!bad, "agents must stay finite and inside the toroidal field")

        // Rendered field has structure (veins + gaps), not saturation or emptiness.
        let (mean, variance) = lumaStats(tex, 640, 360)
        print(String(format: "[PHYS] steady-state luma mean %.3f variance %.4f", mean, variance))
        #expect(mean > 0.02 && mean < 0.80, "trail must be bounded, not blown-out: mean \(mean)")
        #expect(variance > 0.002, "network must have vein/gap structure, not a flat field: var \(variance)")
    }

    // MARK: - Criterion 4: collapse-regrow is flash-safe

    @Test("Collapse holds steady global luminance (flash-safe re-route, not a blackout)")
    func test_collapseFlashSafe() throws {
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let geo = try makeGeo(ctx, lib, PhysarumConfiguration(), pixelFormat: ctx.pixelFormat)
        let tex = try target(ctx, 640, 360)
        var t: Float = 0
        for _ in 0..<300 { let (f, s) = energetic(t); try frame(geo, f, s, tex, ctx); t += 1.0 / 60.0 }  // settle to veins

        var baseline: Float = 0
        for _ in 0..<60 { let (f, s) = energetic(t); try frame(geo, f, s, tex, ctx); baseline += lumaStats(tex, 640, 360).mean; t += 1.0 / 60.0 }
        baseline /= 60.0

        geo.requestCollapse()
        var minL: Float = .greatestFiniteMagnitude, maxL: Float = 0
        for _ in 0..<120 {   // 2 s across the collapse + regrow
            let (f, s) = energetic(t); try frame(geo, f, s, tex, ctx)
            let m = lumaStats(tex, 640, 360).mean
            minL = min(minL, m); maxL = max(maxL, m); t += 1.0 / 60.0
        }
        print(String(format: "[PHYS] collapse luma: baseline %.3f  min %.3f  max %.3f", baseline, minL, maxL))
        #expect(minL > 0.6 * baseline, "collapse must not crater luminance (flash-safe): min \(minL) vs baseline \(baseline)")
        #expect(maxL < 1.6 * baseline, "collapse must not spike luminance (flash-safe): max \(maxL) vs baseline \(baseline)")
    }

    // MARK: - Criterion 3 (PHYS.4): per-beat accent reads AND stays flash-safe

    /// Sustained energy + periodic drum transients (`drumsEnergyDev` spikes). The
    /// PHYS.4 event channel must make the web visibly pulse ON the beats (the
    /// connection the live M7 found missing) while holding global luminance steady
    /// (no strobe — D-157).
    @Test("Per-beat accent pulses the web on drum hits without strobing")
    func test_perBeatAccent() throws {
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let geo = try makeGeo(ctx, lib, PhysarumConfiguration(), pixelFormat: ctx.pixelFormat)
        let tex = try target(ctx, 640, 360)
        var t: Float = 0
        func beatStep(_ fr: Int) throws {
            var f = FeatureVector(time: t, deltaTime: 1.0 / 60.0); f.bass = 0.5; f.mid = 0.4
            var s = StemFeatures()
            s.bassEnergy = 0.5; s.drumsEnergy = 0.5; s.otherEnergy = 0.4; s.vocalsEnergy = 0.3
            let phase = fr % 24                                     // ~2.5 Hz at 60 fps
            s.drumsEnergyDev = phase < 2 ? 1.2 : (phase < 6 ? 0.35 : 0.03)
            try frame(geo, f, s, tex, ctx); t += 1.0 / 60.0
        }
        for fr in 0..<260 { try beatStep(fr) }                      // settle into the beat regime
        var lumas: [Float] = [], hitAtBeat: [Float] = [], hitOffBeat: [Float] = []
        for fr in 0..<240 {
            try beatStep(fr)
            lumas.append(lumaStats(tex, 640, 360).mean)
            if fr % 24 == 2 { hitAtBeat.append(geo.currentHitEnv) }     // just after a spike
            if fr % 24 == 20 { hitOffBeat.append(geo.currentHitEnv) }   // between beats
        }
        lumas.sort()
        let median = lumas[lumas.count / 2], lo = lumas.first ?? 0, hi = lumas.last ?? 0
        let mean = lumas.reduce(0, +) / Float(lumas.count)
        let varc = lumas.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Float(lumas.count)
        let cov = varc.squareRoot() / max(mean, 1e-4)
        let beatHit = hitAtBeat.reduce(0, +) / Float(max(hitAtBeat.count, 1))
        let offHit = hitOffBeat.reduce(0, +) / Float(max(hitOffBeat.count, 1))
        print(String(format: "[PHYS] beat accent: luma median %.3f (min %.3f, max %.3f) cov %.3f | hitEnv beat %.2f vs off %.2f",
                     median, lo, hi, cov, beatHit, offHit))
        // Envelope fires on beats, decays between (the event channel works).
        #expect(beatHit > 3 * offHit && beatHit > 0.2, "hitEnv must spike on beats: beat \(beatHit) vs off \(offHit)")
        // Reads: the web visibly pulses frame-to-frame (not a static field).
        #expect(cov > 0.03, "per-beat luminance must visibly pulse: cov \(cov)")
        // Flash-safe: bounded excursions, no strobe / no crater (D-157).
        #expect(hi < 1.4 * median, "accent must not strobe global luminance: max \(hi) vs median \(median)")
        #expect(lo > 0.6 * median, "accent must not crater global luminance: min \(lo) vs median \(median)")
    }

    // MARK: - Look: PNG sequences (RENDER_VISUAL=1)

    @Test("Render sequences (RENDER_VISUAL=1)")
    func test_render() throws {
        guard ProcessInfo.processInfo.environment["RENDER_VISUAL"] == "1" else { return }
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let cfg = PhysarumConfiguration()
        let geo = try makeGeo(ctx, lib, cfg, pixelFormat: ctx.pixelFormat)
        let w = cfg.width, h = cfg.height
        let tex = try target(ctx, w, h)
        var u = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { u.deleteLastPathComponent() }
        let outDir = u.appendingPathComponent("tools/physarum_sketch/frames", isDirectory: true)
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        var t: Float = 0

        // Low energy → faint searching web.
        for i in 0..<5 {
            for _ in 0..<60 {
                var f = FeatureVector(time: t, deltaTime: 1.0 / 60.0); f.bass = 0.08; f.mid = 0.06
                try frame(geo, f, StemFeatures(), tex, ctx); t += 1.0 / 60.0
            }
            try writePNG(tex, w, h, outDir.appendingPathComponent(String(format: "phys_web_%02d.png", i)))
        }
        // Sustained energy → consolidated bright veins.
        for i in 0..<6 {
            for _ in 0..<60 { let (f, s) = energetic(t); try frame(geo, f, s, tex, ctx); t += 1.0 / 60.0 }
            try writePNG(tex, w, h, outDir.appendingPathComponent(String(format: "phys_veins_%02d.png", i)))
        }
        // Collapse-regrow: trigger, then sample the dissolve + regrowth closely.
        geo.requestCollapse()
        for i in 0..<8 {
            for _ in 0..<15 { let (f, s) = energetic(t); try frame(geo, f, s, tex, ctx); t += 1.0 / 60.0 }
            try writePNG(tex, w, h, outDir.appendingPathComponent(String(format: "phys_collapse_%02d.png", i)))
        }
    }

    /// Web-as-the-star variant: form held in the fine-web regime at every energy
    /// (formEnergyCoupling 0); the music drives brightness + flow within it, not
    /// coarsening. Frames ramp quiet → loud so the web "breathes". (RENDER_VISUAL=1.)
    @Test("Render web-focus variant (RENDER_VISUAL=1)")
    func test_render_webfocus() throws {
        guard ProcessInfo.processInfo.environment["RENDER_VISUAL"] == "1" else { return }
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let cfg = PhysarumConfiguration(formEnergyCoupling: 0)
        let geo = try makeGeo(ctx, lib, cfg, pixelFormat: ctx.pixelFormat)
        let w = cfg.width, h = cfg.height
        let tex = try target(ctx, w, h)
        var u = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { u.deleteLastPathComponent() }
        let outDir = u.appendingPathComponent("tools/physarum_sketch/frames", isDirectory: true)
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        var t: Float = 0
        let levels: [Float] = [0.05, 0.18, 0.32, 0.50, 0.70, 0.90]
        for (i, lvl) in levels.enumerated() {
            for _ in 0..<90 {
                var f = FeatureVector(time: t, deltaTime: 1.0 / 60.0); f.bass = lvl; f.mid = lvl * 0.85
                var s = StemFeatures()
                s.bassEnergy = lvl; s.drumsEnergy = lvl; s.otherEnergy = lvl * 0.8; s.vocalsEnergy = lvl * 0.5
                try frame(geo, f, s, tex, ctx); t += 1.0 / 60.0
            }
            try writePNG(tex, w, h, outDir.appendingPathComponent(String(format: "phys_webfocus_%02d.png", i)))
        }
    }

    /// The web-dominant concept as a musical arc: quiet web → build → peak
    /// bloom (veins) → recede → back to web. One frame at the settle of each
    /// phase, so the breathe reads end-to-end. (RENDER_VISUAL=1.)
    @Test("Render web-dominant arc (RENDER_VISUAL=1)")
    func test_render_arc() throws {
        guard ProcessInfo.processInfo.environment["RENDER_VISUAL"] == "1" else { return }
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let cfg = PhysarumConfiguration()   // default = web-dominant (peaks bloom to veins)
        let geo = try makeGeo(ctx, lib, cfg, pixelFormat: ctx.pixelFormat)
        let w = cfg.width, h = cfg.height
        let tex = try target(ctx, w, h)
        var u = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { u.deleteLastPathComponent() }
        let outDir = u.appendingPathComponent("tools/physarum_sketch/frames", isDirectory: true)
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        var t: Float = 0
        // (raw energy level, hold frames) — the envelope (τ 0.45 s) trails these.
        let arc: [(Float, Int)] = [(0.10, 150), (0.35, 120), (0.55, 120), (0.92, 150), (0.50, 120), (0.12, 150)]
        for (i, phase) in arc.enumerated() {
            for _ in 0..<phase.1 {
                var f = FeatureVector(time: t, deltaTime: 1.0 / 60.0); f.bass = phase.0; f.mid = phase.0 * 0.85
                var s = StemFeatures()
                s.bassEnergy = phase.0; s.drumsEnergy = phase.0; s.otherEnergy = phase.0 * 0.8; s.vocalsEnergy = phase.0 * 0.5
                try frame(geo, f, s, tex, ctx); t += 1.0 / 60.0
            }
            try writePNG(tex, w, h, outDir.appendingPathComponent(String(format: "phys_arc_%02d.png", i)))
        }
    }

    /// Continuous frame sequences for GIF stitching — the one thing stills can't
    /// show: is the web alive (searching/flowing), and how does the build→bloom→
    /// settle transition feel in motion. (RENDER_VISUAL=1.)
    @Test("Render motion sequences (RENDER_VISUAL=1)")
    func test_render_motion() throws {
        guard ProcessInfo.processInfo.environment["RENDER_VISUAL"] == "1" else { return }
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let cfg = PhysarumConfiguration()
        let w = cfg.width, h = cfg.height
        let tex = try target(ctx, w, h)
        var base = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { base.deleteLastPathComponent() }
        let fm = FileManager.default

        func step(_ geo: PhysarumGeometry, _ lvl: Float, _ t: inout Float) throws {
            var f = FeatureVector(time: t, deltaTime: 1.0 / 60.0); f.bass = lvl; f.mid = lvl * 0.85
            var s = StemFeatures()
            s.bassEnergy = lvl; s.drumsEnergy = lvl; s.otherEnergy = lvl * 0.8; s.vocalsEnergy = lvl * 0.5
            try frame(geo, f, s, tex, ctx); t += 1.0 / 60.0
        }

        // 1) Resting web (gentle ambient energy, below the bloom threshold) — flow.
        let webDir = base.appendingPathComponent("tools/physarum_sketch/frames/motion_web", isDirectory: true)
        try? fm.createDirectory(at: webDir, withIntermediateDirectories: true)
        let webGeo = try makeGeo(ctx, lib, cfg, pixelFormat: ctx.pixelFormat)
        var t: Float = 0
        for _ in 0..<150 { try step(webGeo, 0.28, &t) }            // settle
        for i in 0..<90 { for _ in 0..<2 { try step(webGeo, 0.28, &t) }; try writePNG(tex, w, h, webDir.appendingPathComponent(String(format: "f_%03d.png", i))) }

        // 2) Build → bloom → settle, every frame (the arc in motion).
        let arcDir = base.appendingPathComponent("tools/physarum_sketch/frames/motion_arc", isDirectory: true)
        try? fm.createDirectory(at: arcDir, withIntermediateDirectories: true)
        let arcGeo = try makeGeo(ctx, lib, cfg, pixelFormat: ctx.pixelFormat)
        for _ in 0..<120 { try step(arcGeo, 0.12, &t) }            // settle into the web
        let n = 150
        for i in 0..<n {
            let p = Float(i) / Float(n)                            // 0→1 across the arc
            let bump = sin(Float.pi * p)                           // rise then fall
            try step(arcGeo, 0.12 + 0.83 * bump * bump, &t)
            try writePNG(tex, w, h, arcDir.appendingPathComponent(String(format: "f_%03d.png", i)))
        }
        print("[PHYS] motion frames: \(webDir.path) , \(arcDir.path)")
    }

    /// Palette candidates — each anchored palette across the three states it must
    /// survive (faint web / bright veins / peak bloom), so a palette can't hide a
    /// muddy bloom behind a pretty web. (RENDER_VISUAL=1.)
    @Test("Render palette candidates (RENDER_VISUAL=1)")
    func test_render_palettes() throws {
        guard ProcessInfo.processInfo.environment["RENDER_VISUAL"] == "1" else { return }
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let w = 1280, h = 720
        let tex = try target(ctx, w, h)
        var u = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { u.deleteLastPathComponent() }
        let outDir = u.appendingPathComponent("tools/physarum_sketch/frames/palettes", isDirectory: true)
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let palettes: [(UInt32, String)] = [(0, "biolum"), (1, "physarum"), (2, "kintsugi")]
        let states: [(Float, String)] = [(0.12, "1web"), (0.55, "2vein"), (0.92, "3bloom")]
        for (pid, pname) in palettes {
            for (lvl, sname) in states {
                let geo = try makeGeo(ctx, lib, PhysarumConfiguration(paletteId: pid), pixelFormat: ctx.pixelFormat)
                var t: Float = 0
                for _ in 0..<200 {
                    var f = FeatureVector(time: t, deltaTime: 1.0 / 60.0); f.bass = lvl; f.mid = lvl * 0.85
                    var s = StemFeatures()
                    s.bassEnergy = lvl; s.drumsEnergy = lvl; s.otherEnergy = lvl * 0.8; s.vocalsEnergy = lvl * 0.5
                    try frame(geo, f, s, tex, ctx); t += 1.0 / 60.0
                }
                try writePNG(tex, w, h, outDir.appendingPathComponent("\(pname)_\(sname).png"))
            }
        }
    }

    /// On-beat vs off-beat frames so the per-beat accent can be eyeballed (PHYS.4).
    @Test("Render beat accent on/off frames (RENDER_VISUAL=1)")
    func test_render_beat() throws {
        guard ProcessInfo.processInfo.environment["RENDER_VISUAL"] == "1" else { return }
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let cfg = PhysarumConfiguration()
        let geo = try makeGeo(ctx, lib, cfg, pixelFormat: ctx.pixelFormat)
        let w = cfg.width, h = cfg.height
        let tex = try target(ctx, w, h)
        var u = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { u.deleteLastPathComponent() }
        let outDir = u.appendingPathComponent("tools/physarum_sketch/frames", isDirectory: true)
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        var t: Float = 0
        var shot = 0
        for fr in 0..<400 {
            var f = FeatureVector(time: t, deltaTime: 1.0 / 60.0); f.bass = 0.5; f.mid = 0.4
            var s = StemFeatures()
            s.bassEnergy = 0.5; s.drumsEnergy = 0.5; s.otherEnergy = 0.4; s.vocalsEnergy = 0.3
            let phase = fr % 24
            s.drumsEnergyDev = phase < 2 ? 1.2 : (phase < 6 ? 0.35 : 0.03)
            try frame(geo, f, s, tex, ctx); t += 1.0 / 60.0
            if fr >= 300 && shot < 2 {
                if phase == 2 { try writePNG(tex, w, h, outDir.appendingPathComponent("phys_beat_on.png")); shot += 1 }
                if phase == 20 { try writePNG(tex, w, h, outDir.appendingPathComponent("phys_beat_off.png")); shot += 1 }
            }
        }
    }

    private func writePNG(_ tex: MTLTexture, _ w: Int, _ h: Int, _ url: URL) throws {
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
        print("[PHYS] wrote \(url.path)")
    }
}
