// NimbusBloomFollowerTest — NB.4 Energy bloom production-grade temporal gate.
//
// Nimbus is a `direct` preset whose GPU side is STATELESS frame-to-frame (the
// body is recomputed every frame). Its temporal behaviour — the Energy "bloom"
// and the gas "flow phase" — lives entirely in `NimbusState` (CPU-side),
// flushed each frame to the 16-byte slot-6 buffer the shader reads. So the
// CLAUDE.md "test in the production-grade rendering pipeline" rule is honoured
// here by (a) ticking the follower over the relevant attack/release window and
// (b) rendering the converged states through the SAME direct dispatch path the
// live app uses — `preset.pipelineState` + the slot-6 NimbusState buffer +
// noiseVolume at texture(6) (RenderPipeline+Draw / VisualizerEngine+Presets).
//
// Two gates:
//
//   • Part A (follower feel) — ticks NimbusState across a silence → energy →
//     silence profile and asserts the asymmetric envelope: bloom rises under
//     energy, falls under silence, reaches half FASTER on the way up than on
//     the way down (fast attack / slow release = gas-like momentum, DESIGN
//     §1.3), settles near 0 at the silence floor and near 1 under sustained
//     energy. Pure CPU — no Metal required.
//
//   • Part B (the render tracks bloom) — converges the follower to the silence
//     floor and to full energy, renders each through the live direct path, and
//     asserts the silence frame is measurably NON-BLACK (D-037) while the
//     energetic frame is brighter AND covers more of the frame (bigger). Skips
//     gracefully if no Metal device is present (CI fallback).
//
// This is a regression gate for the route's CORRECTNESS. The musical-feel
// sign-off (does the bloom feel married to the music, settle-not-die at
// silence) is Matt's ear on a real session — an automated test cannot prove it
// (CLAUDE.md "Manual validation required for musical feel").

import Testing
import Metal
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import Presets
@testable import Renderer
import Shared

@Suite("Nimbus bloom follower (NB.4)")
struct NimbusBloomFollowerTest {

    private static let dt: Float = 1.0 / 60.0

    // MARK: - Fixtures

    /// True-silence FeatureVector: the smoothed band deviations sit at −1 (bands
    /// hit 0 → `AttRel = (0 − 0.5)·2 = −1`), so the follower target floors to 0.
    private func silenceFV() -> FeatureVector {
        var fv = FeatureVector(time: 1.0, deltaTime: Self.dt)
        fv.bassAttRel = -1.0
        fv.midAttRel  = -1.0
        fv.trebAttRel = -1.0
        return fv
    }

    /// Energetic FeatureVector: above-average broadband energy (+0.9 deviation),
    /// so the follower target rises to ~1.
    private func energyFV() -> FeatureVector {
        var fv = FeatureVector(bass: 0.9, mid: 0.9, treble: 0.9, time: 3.0, deltaTime: Self.dt)
        fv.bassAttRel = 0.9
        fv.midAttRel  = 0.9
        fv.trebAttRel = 0.9
        return fv
    }

    // MARK: - Part A: follower attack/release feel (CPU only)

    @Test("bloom floors at silence, fills under energy, and is fast-attack / slow-release")
    func test_followerAsymmetry() throws {
        let device = MTLCreateSystemDefaultDevice()
        guard let device, let state = NimbusState(device: device) else {
            print("NimbusBloomFollowerTest: no Metal device — skipping Part A")
            return
        }
        let silence = silenceFV()
        let energy  = energyFV()

        // ── Converge to the silence floor ────────────────────────────────────
        for _ in 0..<120 { state.tick(deltaTime: Self.dt, features: silence, stems: .zero) }
        let bloomFloor = state.bloom
        #expect(
            bloomFloor < 0.05,
            "bloom did not settle to the silence floor under sustained silence: \(bloomFloor)"
        )

        // ── Attack: count frames for bloom to cross 0.5 from the floor ───────
        var attackFrames = 0
        while state.bloom < 0.5 && attackFrames < 600 {
            state.tick(deltaTime: Self.dt, features: energy, stems: .zero)
            attackFrames += 1
        }
        let bloomAfterAttackCross = state.bloom
        #expect(
            bloomAfterAttackCross >= 0.5 && attackFrames > 0,
            "bloom never rose past 0.5 under sustained energy (rises under energy failed)"
        )

        // ── Converge to full bloom ───────────────────────────────────────────
        for _ in 0..<120 { state.tick(deltaTime: Self.dt, features: energy, stems: .zero) }
        let bloomPeak = state.bloom
        #expect(
            bloomPeak > 0.85,
            "bloom did not fill toward 1 under sustained energy: \(bloomPeak)"
        )

        // ── Release: count frames for bloom to fall back below 0.5 ───────────
        var releaseFrames = 0
        while state.bloom > 0.5 && releaseFrames < 600 {
            state.tick(deltaTime: Self.dt, features: silence, stems: .zero)
            releaseFrames += 1
        }
        #expect(
            releaseFrames > 0,
            "bloom never fell back below 0.5 under sustained silence (falls under silence failed)"
        )

        // ── The core asymmetry: attack reaches half FASTER than release ──────
        // (fast attack / slow release → gas-like momentum, DESIGN §1.3). With
        // τ_attack ≈ 0.15 s and τ_release ≈ 0.40 s this is ~7 vs ~17 frames; the
        // assertion uses a margin so the exact tunable τ values can move.
        #expect(
            attackFrames < releaseFrames,
            """
            Follower is NOT fast-attack/slow-release: attack crossed 0.5 in \
            \(attackFrames) frames but release fell below 0.5 in \(releaseFrames) \
            frames. The gas would snap rather than settle — wrong feel.
            """
        )

        // ── Continue to the floor and confirm it settles, not collapses ─────
        for _ in 0..<120 { state.tick(deltaTime: Self.dt, features: silence, stems: .zero) }
        #expect(state.bloom < 0.05, "bloom did not return to the silence floor: \(state.bloom)")

        // ── flowPhase advances monotonically (gas never freezes, even at the
        // floor — DESIGN §5.7 "Flow is alive"). ──────────────────────────────
        let phaseA = state.flowPhase
        for _ in 0..<60 { state.tick(deltaTime: Self.dt, features: silence, stems: .zero) }
        let phaseB = state.flowPhase
        #expect(
            phaseB > phaseA,
            "flowPhase did not advance at the silence floor (gas froze): \(phaseA) → \(phaseB)"
        )
    }

    // MARK: - Bloom calibration (NB.10 r1.6 — "input problem, solve permanently")

    @Test("typical-loudness music blooms to a clearly visible body, quiet stays small")
    func test_bloomVisibleOnTypicalMusic() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("NimbusBloomFollowerTest: no Metal device — skipping bloom calibration"); return
        }
        // Real music sits at meanStemEnergy ~0.27 (measured p50 across 3 sessions),
        // NOT the 0.5 the pre-r1.6 calibration assumed — `{stem}Energy` is 3 AGC
        // bands summed and the AGC normalises the 6-band TOTAL to 0.5, so the
        // 3-band sum centres at ~0.30 (BUG-027 class). The old ×1.4−0.2 mapped
        // that to bloom ≈ 0.18 → a tiny dim body. tick past the cold-start gate
        // so the stem path (not the FV proxy) drives bloom.
        func converge(_ e: Float) -> Float {
            guard let s = NimbusState(device: device) else { return 0 }
            var st = StemFeatures.zero
            st.drumsEnergy = e; st.bassEnergy = e; st.vocalsEnergy = e; st.otherEnergy = e
            let fv = FeatureVector(deltaTime: Self.dt)
            for _ in 0..<200 { s.tick(deltaTime: 0.1, features: fv, stems: st) }
            return s.bloom
        }
        let typical = converge(0.27)
        let quiet   = converge(0.14)
        let loud    = converge(0.55)
        print(String(format: "[NimbusBloomCal] quiet(0.14)=%.2f  typical(0.27)=%.2f  loud(0.55)=%.2f", quiet, typical, loud))
        #expect(typical > 0.35,
                "typical-loudness music (meanStem 0.27) bloomed to only \(typical) — the tiny-body bug (bloom calibrated to a non-existent 0.5 stem centre). Should read as a clearly visible body.")
        // Dynamic range preserved: quiet < typical < loud.
        #expect(quiet < typical && typical < loud,
                "bloom lost its dynamic range: quiet=\(quiet) typical=\(typical) loud=\(loud)")
    }

    // MARK: - Cold-start gate (NB.5 fix — the ~20 s freeze)

    @Test("cold-start: kick pulses on the live beat while cached stems are frozen; lobes gate in after")
    func test_coldStartGate() throws {
        let device = MTLCreateSystemDefaultDevice()
        guard let device, let state = NimbusState(device: device) else {
            print("NimbusBloomFollowerTest: no Metal device — skipping cold-start gate"); return
        }
        // A "cached snapshot": every stem field CONSTANT, with a hot bass
        // deviation. The old energy-based warmup gate would flip onto these
        // immediately and freeze the kick at 0 (drumsEnergyDev=0) and the bass
        // lobe at a constant bulge. The new time-based gate must instead drive
        // the kick from the live FV beat and keep the lobes gated until ~13 s.
        var cached = StemFeatures.zero
        cached.drumsEnergy = 0.4; cached.bassEnergy = 0.4
        cached.vocalsEnergy = 0.4; cached.otherEnergy = 0.4
        cached.bassEnergyDev = 1.5   // a frozen "bass hit"

        // ── Cold-start (trackTime < ~9 s): pulse the FV beat, hold stems constant.
        var kickMin: Float = 1, kickMax: Float = 0, lobeMax: Float = 0
        var t: Float = 0
        while t < 5.0 {
            let beatOn = (Int(t * 4) % 2 == 0)   // ~2 Hz square wave
            var fv = FeatureVector(deltaTime: Self.dt)
            fv.beatComposite = beatOn ? 1.0 : 0.0
            state.tick(deltaTime: Self.dt, features: fv, stems: cached)
            kickMin = min(kickMin, state.kickPunch); kickMax = max(kickMax, state.kickPunch)
            lobeMax = max(lobeMax, state.bassLobe)
            t += Self.dt
        }
        #expect(
            kickMax - kickMin > 0.2,
            "kick did not PULSE on the live beat during cold-start — frozen on the cached stems? min=\(kickMin) max=\(kickMax)"
        )
        #expect(
            lobeMax < 0.1,
            "bassLobe fired during cold-start despite the gate (would be frozen on the constant cached dev): \(lobeMax)"
        )

        // ── Past convergence (trackTime > ~13 s): the lobes gate IN on the stems.
        for _ in 0..<800 { state.tick(deltaTime: Self.dt, features: FeatureVector(deltaTime: Self.dt), stems: cached) }
        #expect(
            state.bassLobe > 0.5,
            "bassLobe did not engage after the cold-start convergence window: \(state.bassLobe)"
        )
    }

    // MARK: - Part B: the render tracks bloom (live direct dispatch path)

    @Test("silence floor renders non-black; energetic renders bigger + brighter")
    func test_renderTracksBloom() throws {
        let ctx: MetalContext
        do { ctx = try MetalContext() } catch {
            print("NimbusBloomFollowerTest: no Metal context — skipping Part B"); return
        }

        // Real production compile path: PresetLoader auto-discovers + compiles Nimbus.
        let loader = PresetLoader(device: ctx.device, pixelFormat: ctx.pixelFormat)
        guard let nimbus = loader.presets.first(where: { $0.descriptor.name == "Nimbus" }) else {
            Issue.record("Nimbus preset not found — shader failed to compile or auto-discover")
            return
        }
        // Production binds the full noise set on the direct path (noiseVolume at
        // texture 6); bind the SAME set so the render matches production (FA #66).
        guard let lib = try? ShaderLibrary(context: ctx),
              let texMgr = try? TextureManager(context: ctx, shaderLibrary: lib) else {
            Issue.record("could not build noise textures — render would mis-measure"); return
        }
        guard let state = NimbusState(device: ctx.device) else {
            Issue.record("NimbusState alloc failed"); return
        }

        // Converge the follower to each level, then render through the live path.
        let silence = silenceFV()
        let energy  = energyFV()

        for _ in 0..<150 { state.tick(deltaTime: Self.dt, features: silence, stems: .zero) }
        let floorBloom = state.bloom
        guard let silencePixels = renderNimbus(nimbus, ctx: ctx, texMgr: texMgr,
                                               state: state, features: silenceFV()) else {
            Issue.record("silence render failed"); return
        }

        for _ in 0..<150 { state.tick(deltaTime: Self.dt, features: energy, stems: .zero) }
        let peakBloom = state.bloom
        guard let energyPixels = renderNimbus(nimbus, ctx: ctx, texMgr: texMgr,
                                              state: state, features: energyFV()) else {
            Issue.record("energy render failed"); return
        }

        let silenceLuma = meanLuma(silencePixels)
        let energyLuma  = meanLuma(energyPixels)
        // Body coverage: pixels clearly brighter than the haze floor (luma > 0.12
        // in [0,1] = ~31/255). Captures body pixels, excludes the dim haze halo.
        let silenceCover = coverage(silencePixels, lumaThreshold: 0.12)
        let energyCover  = coverage(energyPixels, lumaThreshold: 0.12)

        print(String(format:
            "[NimbusBloom] floorBloom=%.3f silenceLuma=%.4f cover=%.3f | peakBloom=%.3f energyLuma=%.4f cover=%.3f",
            floorBloom, silenceLuma, silenceCover, peakBloom, energyLuma, energyCover))

        // D-037: the silence floor is measurably NON-BLACK (dim body + haze).
        #expect(
            silenceLuma > 0.003,
            "Nimbus silence floor is ~black (mean luma \(silenceLuma)) — D-037 violated (must be a dim settle, not a collapse)."
        )

        // Energetic blooms brighter than the silence floor (the +80 % luminosity route).
        #expect(
            energyLuma > silenceLuma * 1.15,
            "Energetic frame (luma \(energyLuma)) is not clearly brighter than the silence floor (luma \(silenceLuma)) — bloom→brightness route not firing."
        )

        // Energetic blooms bigger than the silence floor (the +45 % size route):
        // more of the frame is covered by body-bright pixels.
        #expect(
            energyCover > silenceCover,
            "Energetic frame (body coverage \(energyCover)) is not bigger than the silence floor (coverage \(silenceCover)) — bloom→size route not firing."
        )
    }

    // MARK: - NB.8 half-res render path

    @Test("half-res render + bilinear upscale produces a valid (non-black, body-present) image")
    func test_halfResUpscale() throws {
        let ctx: MetalContext
        do { ctx = try MetalContext() } catch {
            print("NimbusBloomFollowerTest: no Metal context — skipping half-res"); return
        }
        let loader = PresetLoader(device: ctx.device, pixelFormat: ctx.pixelFormat)
        guard let nimbus = loader.presets.first(where: { $0.descriptor.name == "Nimbus" }),
              let lib = try? ShaderLibrary(context: ctx),
              let texMgr = try? TextureManager(context: ctx, shaderLibrary: lib),
              let state = NimbusState(device: ctx.device) else {
            Issue.record("half-res setup failed"); return
        }
        // The same feedback_blit + linear-clamp sampler the live half-res path
        // uses for the upscale (RenderPipeline drawDirect / feedbackBlitPipelineState).
        guard let blit = try? lib.renderPipelineState(
                named: "feedback_blit", vertexFunction: "fullscreen_vertex",
                fragmentFunction: "feedback_blit_fragment",
                pixelFormat: ctx.pixelFormat, device: ctx.device) else {
            Issue.record("feedback_blit pipeline failed"); return
        }
        let sd = MTLSamplerDescriptor()
        sd.minFilter = .linear; sd.magFilter = .linear
        sd.sAddressMode = .clampToEdge; sd.tAddressMode = .clampToEdge
        guard let sampler = ctx.device.makeSamplerState(descriptor: sd) else {
            Issue.record("sampler failed"); return
        }

        // Converge to a present, swelled body (the case the half-res path exists for).
        var fv = FeatureVector(bass: 0.5, mid: 0.5, treble: 0.5, time: 3.0, deltaTime: Self.dt)
        fv.aspectRatio = 1.0
        for _ in 0..<60 { state.tick(deltaTime: Self.dt, features: fv, stems: stemFixture(energy: 0.8)) }

        let full = 256, half = 128
        func makeTex(_ width: Int, _ height: Int) -> MTLTexture? {
            let td = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: ctx.pixelFormat, width: width, height: height, mipmapped: false)
            td.usage = [.renderTarget, .shaderRead]; td.storageMode = .shared
            return ctx.device.makeTexture(descriptor: td)
        }
        guard let halfTex = makeTex(half, half), let fullTex = makeTex(full, full),
              let cmd = ctx.commandQueue.makeCommandBuffer() else {
            Issue.record("texture/cmd alloc failed"); return
        }

        // Pass 1 — Nimbus fragment → half-res texture (the same bindings drawDirect uses).
        let rpd1 = MTLRenderPassDescriptor()
        rpd1.colorAttachments[0].texture = halfTex
        rpd1.colorAttachments[0].loadAction = .clear
        rpd1.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        rpd1.colorAttachments[0].storeAction = .store
        guard let e1 = cmd.makeRenderCommandEncoder(descriptor: rpd1) else { Issue.record("enc1"); return }
        e1.setRenderPipelineState(nimbus.pipelineState)
        e1.setFragmentBytes(&fv, length: MemoryLayout<FeatureVector>.size, index: 0)
        texMgr.bindTextures(to: e1)
        e1.setFragmentBuffer(state.stateBuffer, offset: 0, index: 6)
        e1.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        e1.endEncoding()

        // Pass 2 — bilinear upscale → full-res texture.
        let rpd2 = MTLRenderPassDescriptor()
        rpd2.colorAttachments[0].texture = fullTex
        rpd2.colorAttachments[0].loadAction = .clear
        rpd2.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        rpd2.colorAttachments[0].storeAction = .store
        guard let e2 = cmd.makeRenderCommandEncoder(descriptor: rpd2) else { Issue.record("enc2"); return }
        e2.setRenderPipelineState(blit)
        e2.setFragmentTexture(halfTex, index: 0)
        e2.setFragmentSamplerState(sampler, index: 0)
        e2.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        e2.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()
        guard cmd.status == .completed else { Issue.record("render failed"); return }

        var px = [UInt8](repeating: 0, count: full * full * 4)
        fullTex.getBytes(&px, bytesPerRow: full * 4,
                         from: MTLRegionMake2D(0, 0, full, full), mipmapLevel: 0)
        let luma = meanLuma(px), cover = coverage(px, lumaThreshold: 0.12)
        print(String(format: "[NimbusHalfRes] upscaled luma=%.4f cover=%.3f", luma, cover))
        #expect(luma > 0.003, "half-res upscaled output is ~black (luma \(luma)) — the path produced nothing")
        #expect(cover > 0.03, "no body in the half-res upscaled output (coverage \(cover))")
    }

    // MARK: - Render harness (live direct dispatch path)

    /// Render Nimbus into a square BGRA buffer through `preset.pipelineState`
    /// with the slot-6 NimbusState buffer + noiseVolume bound — the exact
    /// dispatch the live direct path uses.
    private func renderNimbus(_ preset: PresetLoader.LoadedPreset,
                              ctx: MetalContext,
                              texMgr: TextureManager,
                              state: NimbusState,
                              features: FeatureVector) -> [UInt8]? {
        let size = Self.lobeRenderSize
        let td = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: ctx.pixelFormat, width: size, height: size, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]
        td.storageMode = .shared
        guard let target = ctx.device.makeTexture(descriptor: td),
              let cmd = ctx.commandQueue.makeCommandBuffer() else { return nil }

        var fv = features
        fv.aspectRatio = 1.0   // square target → body centred, unstretched

        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = target
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        rpd.colorAttachments[0].storeAction = .store
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) else { return nil }
        enc.setRenderPipelineState(preset.pipelineState)
        enc.setFragmentBytes(&fv, length: MemoryLayout<FeatureVector>.size, index: 0)
        texMgr.bindTextures(to: enc)                                   // noiseVolume → texture(6)
        enc.setFragmentBuffer(state.stateBuffer, offset: 0, index: 6)  // NimbusStateGPU → buffer(6)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()
        guard cmd.status == .completed else { return nil }

        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        target.getBytes(&pixels, bytesPerRow: size * 4,
                        from: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0)
        return pixels
    }

    // MARK: - Pixel metrics

    /// Mean luma over the frame in [0, 1] (BGRA bytes, BT.601 weights).
    private func meanLuma(_ pixels: [UInt8]) -> Float {
        var sum: Float = 0
        let count = pixels.count / 4
        for i in 0..<count {
            let b = Float(pixels[i * 4 + 0])
            let g = Float(pixels[i * 4 + 1])
            let r = Float(pixels[i * 4 + 2])
            sum += (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
        }
        return sum / Float(count)
    }

    /// Fraction of pixels whose luma exceeds `lumaThreshold` (in [0, 1]).
    private func coverage(_ pixels: [UInt8], lumaThreshold: Float) -> Float {
        var n = 0
        let count = pixels.count / 4
        for i in 0..<count {
            let b = Float(pixels[i * 4 + 0])
            let g = Float(pixels[i * 4 + 1])
            let r = Float(pixels[i * 4 + 2])
            let luma = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
            if luma > lumaThreshold { n += 1 }
        }
        return Float(n) / Float(count)
    }

    /// Mean luma in [0,1] over a rectangular region [rows) × [cols) of a `size`²
    /// BGRA frame. Used for the negative-space (corner-vs-centre) coherence gate.
    private func regionMeanLuma(_ pixels: [UInt8], size: Int,
                                rows: Range<Int>, cols: Range<Int>) -> Float {
        var sum: Float = 0; var n = 0
        for y in rows {
            for x in cols {
                let i = (y * size + x) * 4
                let b = Float(pixels[i + 0]), g = Float(pixels[i + 1]), r = Float(pixels[i + 2])
                sum += (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
                n += 1
            }
        }
        return n > 0 ? sum / Float(n) : 0
    }

    /// Mean of the four corner blocks (each `frac` of the frame edge) — the
    /// truest negative space for a centred body.
    private func cornerMeanLuma(_ pixels: [UInt8], size: Int, frac: Float = 0.16) -> Float {
        let m = max(1, Int(Float(size) * frac))
        let tl = regionMeanLuma(pixels, size: size, rows: 0..<m, cols: 0..<m)
        let tr = regionMeanLuma(pixels, size: size, rows: 0..<m, cols: (size - m)..<size)
        let bl = regionMeanLuma(pixels, size: size, rows: (size - m)..<size, cols: 0..<m)
        let br = regionMeanLuma(pixels, size: size, rows: (size - m)..<size, cols: (size - m)..<size)
        return (tl + tr + bl + br) / 4.0
    }

    /// Mean luma of the central block (`frac` of the frame, centred).
    private func centreMeanLuma(_ pixels: [UInt8], size: Int, frac: Float = 0.25) -> Float {
        let h = Int(Float(size) * frac) / 2
        let c = size / 2
        return regionMeanLuma(pixels, size: size, rows: (c - h)..<(c + h), cols: (c - h)..<(c + h))
    }

    /// Mean squared per-channel difference between two BGRA buffers (non-alpha).
    private func meanSquaredDiff(_ a: [UInt8], _ b: [UInt8]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var sum: Float = 0; var count = 0
        for i in stride(from: 0, to: a.count, by: 4) {
            for c in 0..<3 {
                let d = Float(a[i + c]) - Float(b[i + c])
                sum += d * d; count += 1
            }
        }
        return count > 0 ? sum / Float(count) : 0
    }

    // MARK: - Part C: stem beat-lobes (the band plays the body — NB.5)

    private static let lobeRenderSize = 256

    @Test("each stem heaves the body in its direction; drums punch + brighten; one mass holds")
    func test_stemLobes() throws {
        let ctx: MetalContext
        do { ctx = try MetalContext() } catch {
            print("NimbusBloomFollowerTest: no Metal context — skipping Part C"); return
        }
        let loader = PresetLoader(device: ctx.device, pixelFormat: ctx.pixelFormat)
        guard let nimbus = loader.presets.first(where: { $0.descriptor.name == "Nimbus" }) else {
            Issue.record("Nimbus preset not found"); return
        }
        guard let lib = try? ShaderLibrary(context: ctx),
              let texMgr = try? TextureManager(context: ctx, shaderLibrary: lib) else {
            Issue.record("could not build noise textures"); return
        }

        // Each fixture converges the followers to one regime. The whole-body kick
        // punch is BEAT-driven (NB.8) so the "kick" fixture supplies a beat; the
        // directional lobes are stem-driven, so each lobe fixture has one hot stem
        // deviation. All stem energies sum past the D-019 warmup.
        let fixtures: [(name: String, stems: StemFeatures, beat: Bool)] = [
            ("baseline", stemFixture(),               false),   // present body, no lobes
            ("bloom",    stemFixture(energy: 0.95),   false),   // big swell, no lobes
            ("kick",     stemFixture(),               true),    // whole-body punch + brightness (beat)
            ("bass",     stemFixture(bassDev: 1.6),   false),   // heaves DOWN
            ("vocals",   stemFixture(vocalsDev: 1.6), false),   // flares UP
            ("other",    stemFixture(otherDev: 1.6),  false),   // swells to the SIDE (right)
        ]

        var rendered: [String: [UInt8]] = [:]
        var followers: [String: NimbusStateGPU] = [:]
        for fixture in fixtures {
            guard let state = NimbusState(device: ctx.device) else {
                Issue.record("NimbusState alloc failed"); return
            }
            var fv = FeatureVector(bass: 0.5, mid: 0.5, treble: 0.5, time: 3.0, deltaTime: Self.dt)
            if fixture.beat { fv.beatComposite = 1.0; fv.beatBass = 1.0 }
            // Converge AND advance past the cold-start gate (trackTime >
            // stemConvergeHi ≈ 13 s) so the lobes are ungated — trackTime
            // advances by the clamped dt (≤ 0.1/tick), so this needs ~150 ticks.
            for _ in 0..<150 { state.tick(deltaTime: 0.1, features: fv, stems: fixture.stems) }
            followers[fixture.name] = NimbusStateGPU(
                bloom: state.bloom,
                flowPhase: state.flowPhase,
                kickPunch: state.kickPunch,
                bassLobe: state.bassLobe,
                vocalsLobe: state.vocalsLobe,
                otherLobe: state.otherLobe,
                valence: state.smoothedValence,
                arousal: state.smoothedArousal)
            guard let px = renderNimbus(nimbus, ctx: ctx, texMgr: texMgr, state: state, features: fv) else {
                Issue.record("render failed for \(fixture.name)"); return
            }
            rendered[fixture.name] = px
        }

        // ── Followers respond to the right stem only ─────────────────────────
        let kf = followers["kick"]!, bf = followers["bass"]!
        let vf = followers["vocals"]!, of = followers["other"]!
        #expect(kf.kickPunch > 0.7 && kf.bassLobe < 0.1 && kf.vocalsLobe < 0.1 && kf.otherLobe < 0.1,
                "kick (beat) fixture should fire kickPunch only: \(kf)")
        #expect(bf.bassLobe > 0.7 && bf.kickPunch < 0.1, "bass fixture should fire bassLobe only: \(bf)")
        #expect(vf.vocalsLobe > 0.7 && vf.kickPunch < 0.1, "vocals fixture should fire vocalsLobe only: \(vf)")
        #expect(of.otherLobe > 0.7 && of.kickPunch < 0.1, "other fixture should fire otherLobe only: \(of)")

        // ── The render moves the right way ───────────────────────────────────
        let size = Self.lobeRenderSize
        let base = bodyCentroid(rendered["baseline"]!, size: size)
        let bass = bodyCentroid(rendered["bass"]!, size: size)
        let vocals = bodyCentroid(rendered["vocals"]!, size: size)
        let other = bodyCentroid(rendered["other"]!, size: size)

        print(String(format: "[NimbusLobes] baseline c=(%.1f,%.1f) cover=%.3f | bass row=%.1f vocals row=%.1f other col=%.1f",
                     base.row, base.col, coverage(rendered["baseline"]!, lumaThreshold: 0.12),
                     bass.row, vocals.row, other.col))

        // Body-space −y (bass, down) → screen DOWN = larger row; +y (vocals, up)
        // → smaller row; +x (other, side) → larger col. Margins are loose (the
        // lobe magnitudes are tunable); we assert direction, not amount.
        #expect(bass.row > base.row + 2.0, "bass did not heave the body DOWN (row \(bass.row) vs base \(base.row))")
        #expect(vocals.row < base.row - 2.0, "vocals did not flare the body UP (row \(vocals.row) vs base \(base.row))")
        #expect(other.col > base.col + 2.0, "other did not swell the body SIDEways (col \(other.col) vs base \(base.col))")

        // ── Drums = whole-body punch: brighter AND bigger than baseline ─────
        let baseLuma = meanLuma(rendered["baseline"]!), kickLuma = meanLuma(rendered["kick"]!)
        let baseCover = coverage(rendered["baseline"]!, lumaThreshold: 0.12)
        let kickCover = coverage(rendered["kick"]!, lumaThreshold: 0.12)
        #expect(kickLuma > baseLuma * 1.1, "kick did not brighten the body (\(kickLuma) vs \(baseLuma))")
        #expect(kickCover > baseCover, "kick did not inflate the body (\(kickCover) vs \(baseCover))")

        // ── One mass holds: every fixture renders a present, non-black body ──
        for fixture in fixtures {
            let cov = coverage(rendered[fixture.name]!, lumaThreshold: 0.12)
            #expect(cov > 0.03, "\(fixture.name) body vanished (coverage \(cov)) — fragmentation or collapse")
        }

        // Optional contact sheet for the eye (gated): 6 PNGs to /tmp/nimbus_nb5.
        if ProcessInfo.processInfo.environment["NB5_VISUAL"] == "1" {
            let dir = URL(fileURLWithPath: "/tmp/nimbus_nb5")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for fixture in fixtures {
                writePNG(rendered[fixture.name]!, size: size,
                         to: dir.appendingPathComponent("nimbus_\(fixture.name).png"))
            }
            print("[NimbusLobes] wrote 6 PNGs to \(dir.path)")
        }
    }

    // MARK: - Body coherence + negative space (NB.9 §5.7 — ≠ 05_anti_uniform_fog)

    /// The single worst failure mode for a volumetric preset is the dead-soup
    /// uniform fog (DESIGN §1.4, README "the single worst outcome"). The other
    /// gates put a FLOOR under coverage (the body must be present); this one puts
    /// a CEILING on it at the body's absolute largest — full bloom + max kick +
    /// every directional lobe heaving at once (the budget-probe worst case). Even
    /// there the body must (a) stay a MINORITY of the frame and (b) leave the
    /// corners dark — the negative space the §1.4 idea-to-protect depends on.
    /// Rendered through the live direct path with noiseVolume bound (FA #66).
    @Test("worst-case body stays a bounded mass with dark corners (≠ uniform fog)")
    func test_bodyCoherenceNegativeSpace() throws {
        let ctx: MetalContext
        do { ctx = try MetalContext() } catch {
            print("NimbusBloomFollowerTest: no Metal context — skipping coherence"); return
        }
        let loader = PresetLoader(device: ctx.device, pixelFormat: ctx.pixelFormat)
        guard let nimbus = loader.presets.first(where: { $0.descriptor.name == "Nimbus" }),
              let lib = try? ShaderLibrary(context: ctx),
              let texMgr = try? TextureManager(context: ctx, shaderLibrary: lib),
              let state = NimbusState(device: ctx.device) else {
            Issue.record("coherence setup failed"); return
        }

        // Prime the absolute worst case: full bloom + kick + every lobe maxed
        // (the NimbusBudgetProbe worst-case prime). Beat live so the kick
        // converges; all four stem deviations maxed so every directional lobe
        // heaves; past the cold-start gate so the lobes are ungated.
        var fv = FeatureVector(bass: 0.9, mid: 0.9, treble: 0.9, time: 3.0, deltaTime: Self.dt)
        fv.aspectRatio = 1.0
        fv.beatComposite = 1.0; fv.beatBass = 1.0; fv.beatPhase01 = 1.0
        fv.bassAttRel = 1.0; fv.midAttRel = 1.0; fv.trebAttRel = 1.0
        var worst = StemFeatures.zero
        worst.drumsEnergy = 0.9; worst.bassEnergy = 0.9
        worst.vocalsEnergy = 0.9; worst.otherEnergy = 0.9
        worst.drumsEnergyDev = 2.0; worst.bassEnergyDev = 2.0
        worst.vocalsEnergyDev = 2.0; worst.otherEnergyDev = 2.0
        for _ in 0..<200 { state.tick(deltaTime: 0.1, features: fv, stems: worst) }

        guard let px = renderNimbus(nimbus, ctx: ctx, texMgr: texMgr, state: state, features: fv) else {
            Issue.record("worst-case render failed"); return
        }
        let size = Self.lobeRenderSize
        let cover  = coverage(px, lumaThreshold: 0.12)
        let corner = cornerMeanLuma(px, size: size)
        let centre = centreMeanLuma(px, size: size)
        print(String(format:
            "[NimbusCoherence] worst-case cover=%.3f corner=%.4f centre=%.4f corner/centre=%.3f",
            cover, corner, centre, corner / max(centre, 1e-4)))

        // (a) Body present (not a collapse) but still leaves real void even at
        // its absolute largest — it does NOT fill the frame (that is uniform
        // fog). Measured worst case = 0.668 (full bloom + max kick + all three
        // lobes heaving at once — a pathological synthetic max; typical energetic
        // coverage is ~0.24–0.36). The 0.80 ceiling keeps ≥ 20 % dark void even
        // there, robust to legitimate body-size tuning; the primary negative-
        // space proof is the corner/centre ratio below.
        #expect(cover > 0.05, "worst-case body vanished (coverage \(cover)) — collapse, not a body")
        #expect(cover < 0.80,
                "worst-case body fills the frame (coverage \(cover)) — negative space lost (05_anti_uniform_fog)")
        // (b) Corners stay dark vs the lit centre — the true discriminator from
        // uniform fog (a flat field reads corner/centre ≈ 1; a bounded centred
        // body reads ≪ 1). Measured 0.082; the haze halo concentrates near the
        // body and fades to near-black corners by construction (kNimbusHazeFalloff).
        #expect(corner < centre * 0.30,
                "corners not dark relative to the centre (corner \(corner) vs centre \(centre)) — frame-filling haze, negative space lost (05_anti_uniform_fog)")
    }

    // MARK: - Mood travel (NB.6 — valence→colour, arousal→agitation)

    @Test("mood: high valence renders warmer than low; renders are valid (NB.6)")
    func test_moodTravel() throws {
        let ctx: MetalContext
        do { ctx = try MetalContext() } catch {
            print("NimbusBloomFollowerTest: no Metal context — skipping mood"); return
        }
        let loader = PresetLoader(device: ctx.device, pixelFormat: ctx.pixelFormat)
        guard let nimbus = loader.presets.first(where: { $0.descriptor.name == "Nimbus" }),
              let lib = try? ShaderLibrary(context: ctx),
              let texMgr = try? TextureManager(context: ctx, shaderLibrary: lib) else {
            Issue.record("mood setup failed"); return
        }
        // valence/arousal arrive on the FeatureVector; smoothed ~4 s in state, so
        // tick well past the EMA (and the cold-start gate) to converge.
        func render(valence: Float, arousal: Float, energy: Float = 0.7) -> [UInt8]? {
            guard let state = NimbusState(device: ctx.device) else { return nil }
            var fv = FeatureVector(bass: 0.5, mid: 0.5, treble: 0.5, time: 3.0, deltaTime: Self.dt)
            fv.valence = valence; fv.arousal = arousal; fv.aspectRatio = 1.0
            for _ in 0..<250 { state.tick(deltaTime: 0.1, features: fv, stems: stemFixture(energy: energy)) }
            return renderNimbus(nimbus, ctx: ctx, texMgr: texMgr, state: state, features: fv)
        }
        guard let cool = render(valence: -0.85, arousal: 0),
              let warm = render(valence:  0.85, arousal: 0),
              let calm = render(valence: 0, arousal: -0.85),
              let wild = render(valence: 0, arousal:  0.85) else {
            Issue.record("mood render failed"); return
        }
        let c = meanChannels(cool), w = meanChannels(warm)
        // Warm valence → the body is redder relative to blue than the cool pole.
        let coolRB = c.r / max(c.b, 1), warmRB = w.r / max(w.b, 1)
        print(String(format: "[NimbusMood] cool R/B=%.2f  warm R/B=%.2f  (warm should be > cool)", coolRB, warmRB))
        #expect(warmRB > coolRB * 1.3,
                "high valence did not render warmer than low: cool R/B=\(coolRB), warm R/B=\(warmRB)")
        // Arousal → flow agitation (NB.6 / §5.7): `calm` and `wild` differ ONLY
        // in arousal, which drives the detail-erosion strength (calm = smoother
        // lobes, wild = torn/fraying edges). Assert the route is LIVE — it
        // produces a visible per-pixel change. (The directional read — wild is
        // more torn — is M7; this completes the §5.7 mood-travel bullet by
        // proving the second mood axis carries signal, the partner to the
        // valence→colour assertion above.)
        let arousalMSD = meanSquaredDiff(calm, wild)
        print(String(format: "[NimbusMood] calm↔wild agitation MSD=%.2f", arousalMSD))
        #expect(arousalMSD > 1.0,
                "arousal→agitation route is dead: calm and wild renders are ~identical (MSD \(arousalMSD))")
        // NB.10 (D-144): ENERGY warms the body. At NEUTRAL valence, a high-energy
        // state (high arousal + big bloom) must render warmer than a low-energy
        // one — so an energetic-but-"dark" track (B.O.B.) reads hot, not cool
        // (Matt M7 r1). This gates the energy→warmth route the mood uplift added.
        guard let lowE = render(valence: 0, arousal: -0.9, energy: 0.15),
              let highE = render(valence: 0, arousal: 0.9, energy: 0.95) else {
            Issue.record("energy-warmth render failed"); return
        }
        let le = meanChannels(lowE), he = meanChannels(highE)
        let lowERB = le.r / max(le.b, 1), highERB = he.r / max(he.b, 1)
        print(String(format: "[NimbusMood] energy-warmth: lowE R/B=%.2f  highE R/B=%.2f", lowERB, highERB))
        #expect(highERB > lowERB * 1.3,
                "energy did not warm the body: low-energy R/B=\(lowERB), high-energy R/B=\(highERB) — B.O.B. would still read cool")
        for (name, px) in [("cool", cool), ("warm", warm), ("calm", calm), ("wild", wild)] {
            #expect(meanLuma(px) > 0.003, "\(name) mood render is ~black")
        }
        if ProcessInfo.processInfo.environment["NB_MOOD"] == "1" {
            let dir = URL(fileURLWithPath: "/tmp/nimbus_mood")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for (name, px) in [("cool", cool), ("warm", warm), ("calm", calm), ("wild", wild)] {
                writePNG(px, size: Self.lobeRenderSize, to: dir.appendingPathComponent("mood_\(name).png"))
            }
            print("[NimbusMood] wrote 4 PNGs to \(dir.path)")
        }
    }

    /// Mean (r, g, b) over the frame in [0, 255] (BGRA bytes).
    private func meanChannels(_ px: [UInt8]) -> (r: Float, g: Float, b: Float) {
        var sr: Float = 0, sg: Float = 0, sb: Float = 0
        let n = px.count / 4
        for i in 0..<n { sb += Float(px[i * 4 + 0]); sg += Float(px[i * 4 + 1]); sr += Float(px[i * 4 + 2]) }
        return (sr / Float(n), sg / Float(n), sb / Float(n))
    }

    // MARK: - Motion strip (NB.3.5 rising/curling smoke — env-gated, visual)

    /// Renders a sequence of frames at advancing flow so the MOTION (rising,
    /// curling, churning) can be judged — a still can't show it. Writes N PNGs to
    /// /tmp/nimbus_motion under NB_MOTION=1; not a CI assertion.
    @Test("Nimbus motion strip (NB_MOTION=1)")
    func test_motionStrip() throws {
        guard ProcessInfo.processInfo.environment["NB_MOTION"] == "1" else {
            print("NimbusBloomFollowerTest: NB_MOTION not set, skipping motion strip"); return
        }
        let ctx = try MetalContext()
        let loader = PresetLoader(device: ctx.device, pixelFormat: ctx.pixelFormat)
        guard let nimbus = loader.presets.first(where: { $0.descriptor.name == "Nimbus" }),
              let lib = try? ShaderLibrary(context: ctx),
              let texMgr = try? TextureManager(context: ctx, shaderLibrary: lib),
              let state = NimbusState(device: ctx.device) else {
            Issue.record("motion strip setup failed"); return
        }
        // Energy fixture → bloom high, flow fast. Converge bloom first.
        let fv = energyFV()
        let stems = stemFixture(energy: 0.8)
        for _ in 0..<60 { state.tick(deltaTime: Self.dt, features: fv, stems: stems) }

        let dir = URL(fileURLWithPath: "/tmp/nimbus_motion")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let frames = 8, ticksBetween = 16   // ~0.27 s of motion between captures
        for i in 0..<frames {
            guard let px = renderNimbus(nimbus, ctx: ctx, texMgr: texMgr, state: state, features: fv) else {
                Issue.record("motion render \(i) failed"); return
            }
            writePNG(px, size: Self.lobeRenderSize, to: dir.appendingPathComponent("m_\(i).png"))
            for _ in 0..<ticksBetween { state.tick(deltaTime: Self.dt, features: fv, stems: stems) }
        }
        print("[NimbusMotion] wrote \(frames) frames to \(dir.path) (flowPhase \(state.flowPhase))")
    }

    /// Build a StemFeatures with a baseline energy on every stem (so the D-019
    /// warmup is satisfied → post-warmup stem path) and one hot deviation.
    private func stemFixture(energy: Float = 0.5, drumsDev: Float = 0, bassDev: Float = 0,
                             vocalsDev: Float = 0, otherDev: Float = 0) -> StemFeatures {
        var s = StemFeatures.zero
        s.drumsEnergy = energy; s.bassEnergy = energy
        s.vocalsEnergy = energy; s.otherEnergy = energy
        s.drumsEnergyDev = drumsDev; s.bassEnergyDev = bassDev
        s.vocalsEnergyDev = vocalsDev; s.otherEnergyDev = otherDev
        return s
    }

    /// Luma-weighted centroid (row, col) of body pixels (luma > 0.12), in pixels.
    private func bodyCentroid(_ pixels: [UInt8], size: Int) -> (row: Float, col: Float) {
        var sumW: Float = 0, sumR: Float = 0, sumC: Float = 0
        for y in 0..<size {
            for x in 0..<size {
                let i = (y * size + x) * 4
                let b = Float(pixels[i + 0]), g = Float(pixels[i + 1]), r = Float(pixels[i + 2])
                let luma = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
                if luma > 0.12 {
                    sumW += luma
                    sumR += luma * Float(y)
                    sumC += luma * Float(x)
                }
            }
        }
        guard sumW > 0 else { return (Float(size) / 2, Float(size) / 2) }
        return (sumR / sumW, sumC / sumW)
    }

    private func writePNG(_ bgra: [UInt8], size: Int, to url: URL) {
        var rgba = [UInt8](repeating: 0, count: bgra.count)
        for i in stride(from: 0, to: bgra.count, by: 4) {
            rgba[i + 0] = bgra[i + 2]; rgba[i + 1] = bgra[i + 1]
            rgba[i + 2] = bgra[i + 0]; rgba[i + 3] = bgra[i + 3]
        }
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let provider = CGDataProvider(data: Data(rgba) as CFData),
              let img = CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32,
                                bytesPerRow: size * 4, space: cs,
                                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return }
        CGImageDestinationAddImage(dest, img, nil)
        CGImageDestinationFinalize(dest)
    }
}
