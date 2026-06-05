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

    // MARK: - Render harness (live direct dispatch path)

    /// Render Nimbus into a square BGRA buffer through `preset.pipelineState`
    /// with the slot-6 NimbusState buffer + noiseVolume bound — the exact
    /// dispatch the live direct path uses.
    private func renderNimbus(_ preset: PresetLoader.LoadedPreset,
                              ctx: MetalContext,
                              texMgr: TextureManager,
                              state: NimbusState,
                              features: FeatureVector) -> [UInt8]? {
        let size = 256
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
}
