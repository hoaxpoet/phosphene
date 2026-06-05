// PresetRegressionTests — dHash visual regression gate for all production presets.
//
// Renders each preset at three FeatureVector fixtures (steady, beat-heavy, quiet),
// computes a 64-bit dHash of the 64×64 BGRA output, and compares against stored
// golden values with Hamming distance ≤ 8 (~87.5% match). Any intentional shader
// change that alters visual output must regenerate goldens; accidental changes fail.
//
// Skip rules (non-negotiable):
//   - meshShader presets: MTLMeshRenderPipeline cannot be invoked via drawPrimitives.
//   - Preset with no golden entry: skips silently (new preset or update in progress).
//
// To regenerate all goldens:
//   UPDATE_GOLDEN_SNAPSHOTS=1 swift test --package-path PhospheneEngine \
//     --filter "Print golden hashes"
// Paste the printed lines into goldenPresetHashes below.
//
// See D-039 in docs/DECISIONS.md.

import Testing
import Metal
@testable import Renderer
@testable import Presets
@testable import Shared

// MARK: - Golden Hash Table

private typealias PresetHashes = (steady: UInt64, beatHeavy: UInt64, quiet: UInt64)

/// Inline golden dHash values for each preset × 3 fixtures.
/// Update when a shader edit intentionally changes visual output — never silently.
private let goldenPresetHashes: [String: PresetHashes] = [
    // V.7.7B Arachne: staged COMPOSITE fragment now ports the V.7.5 v5 web
    // walk + spider + mist + dust motes. The regression renders the COMPOSITE
    // stage in isolation with `worldTex` unbound (texture sampler returns 0),
    // so the hash captures the foreground composition alone — silk strands,
    // adhesive droplets, mist + motes — over a black backdrop. The full
    // WORLD + COMPOSITE composite is exercised by PresetVisualReviewTests.
    //
    // V.7.7C (D-093): drop overlay rewritten to §5.8 Snell's-law refractive
    // recipe. Under this regression path `worldTex` is unbound → bgSeen reads
    // black; drops compose as thin warm fresnel rim + warm specular pinpoint
    // + dark edge ring × audio gain. dHash UNCHANGED at the V.7.7B values:
    // the new contributions sum below the 9×8 luma quantization threshold of
    // dHash, so the foreground silhouette fingerprint is bytewise identical.
    // Real visual divergence is observed in PresetVisualReviewTests.
    //
    // V.7.7D (D-094): 3D SDF spider replaces the 2D overlay (spider not drawn
    // under regression — `spider.blend = 0` when buffer is unbound), and a
    // §8.2 12 Hz UV-jitter vibration is applied to the foreground web walks.
    // Vibration amplitude is gated by `bass_dev` + `beat_bass` so the silence
    // and quiet fixtures (zero/low values) produce no visible shake — those
    // hashes stay byte-identical. The beatHeavy fixture (`beat_bass` ≈ 1.0)
    // produces a small UV jitter that drifts the silk pattern by a few bits;
    // hash updated to match. Real visual divergence — including the new 3D
    // spider — is observed in PresetVisualReviewTests / ArachneSpiderRenderTests.
    //
    // V.7.7C.2 (D-095): Commit 3 swaps the foreground anchor's data source
    // from hardcoded (stage=3, progress=1) to webs[0] Row 5 BuildState. At
    // the harness's 0.5 s warmup the foreground hero is in frame phase at
    // frameProgress ≈ 0.166 (only the partial bridge thread renders), so the
    // V.7.7D upper-left fully-built foreground web disappears from the
    // regression composition. webs[1] (the second seedInitialWebs() stable
    // web) continues to render at lower-right unchanged, providing background
    // depth context. All three fixtures converge to the same hash because
    // the harness warmup uses one shared warmFV regardless of fixture — the
    // per-fixture pace differences surface only on real-music playback
    // (Matt's manual smoke gate). Hamming distance from V.7.7D `steady`:
    // 16 bits, within the D-095 expected [10, 30] band.
    //
    // V.7.7C.3 (D-095 follow-up): hash UNCHANGED. PresetRegression's render
    // harness does not bind slot 6 / 7 (sees zeroed buffers), so:
    //   - webs[0].rng_seed = 0 → polyCount = 0 → V.7.5 fallback (circular
    //     spoke tips, regular oval) instead of the new polygon path.
    //   - Pool loop iterates `wi=1..1` (empty) so the V.7.5 churn that
    //     V.7.7C.3 retired never appeared in this regression anyway.
    //   - webs[0].build_stage = 0 → foreground frame phase at 0 % progress,
    //     no visible foreground content.
    // Net: only the WORLD backdrop renders, identical to V.7.7C.2's
    // composition. The V.7.7C.3 polygon-mode visual change IS exercised by
    // ArachneSpiderRenderTests (which binds a real, reset()-seeded
    // ArachneState) and by PresetVisualReviewTests' RENDER_VISUAL=1 path.
    //
    // V.7.7C.5 (D-100): Arachne hashes UNCHANGED again. The §4 atmospheric
    // reframe retires the WORLD-side six-layer forest and replaces it with
    // the §4.2 sky band + volumetric atmosphere, AND the WEB pillar's
    // foreground hero web is now canvas-filling (`webR = 0.55`, hub at
    // (0.5, 0.5), polygon vertices off-frame). PresetRegression still
    // doesn't bind slot 6/7, so:
    //   - The COMPOSITE fragment samples `worldTex` for its backdrop, but
    //     the regression harness leaves `worldTex` unbound → bgColor = 0.
    //     The §4 WORLD reframe therefore produces no visible change in the
    //     regression-mode composition (which only sees COMPOSITE alone).
    //   - Foreground hero web at (0.5, 0.5) / `webR = 0.55` would now span
    //     most of the canvas — but the harness's zeroed slot-6 buffer gives
    //     `build_stage = 0, frame_progress = 0` → frame phase at 0 % →
    //     nothing rendered, so the canvas-filling change also doesn't
    //     surface here.
    //   - Spider hash DOES drift (`ArachneSpiderRenderTests` binds a
    //     `state.reset()`-seeded `ArachneState`, so the off-frame
    //     `kBranchAnchors[6]` move into the polygon decode path). Hamming
    //     distance V.7.7C.4 → V.7.7C.5: 7 bits (`0x06129A55C258494D` →
    //     `0x06D29A65E458494D`).
    // Real visual divergence — sky band + light shafts + canvas-filling
    // web — is observed in `PresetVisualReviewTests` (per-stage harness
    // with worldTex bound + reset()-seeded `ArachneState`).
    //
    // V.7.7C.4 (D-095 follow-up): hashes drift. Three fixes contribute:
    //   - Silk palette enrichment (silkTint 0.60 → 0.85; mood-driven hue;
    //     vocal-pitch coupling; ambient tint 0.25 → 0.40). Affects the
    //     foreground anchor block's silk emission stage — visible whenever
    //     `wr.strandCov > 0.001`.
    //   - Hub knot brightness 0.80 → 1.20 (saturated). Visible from
    //     `stage >= 1u`.
    //   - Per-beat global emission pulse `beatPulse * 0.45`. Adds
    //     `beat_bass`/`beat_composite` energy to silk brightness when a
    //     beat is firing.
    // PresetRegression still doesn't bind slot 6/7, so foreground at
    // frame-phase 0% has no silk content. The hash drift here comes from
    // the §8.2 vibration UV jitter applied at the top of
    // arachne_composite_fragment — which uses `bass_att_rel`. The
    // V.7.7C.4 changes don't move this term, but the cumulative shifts
    // through the V.7.7C.3 polygon mode + V.7.7C.4 emission stage produce
    // a slightly different per-pixel composition under noise alignment.
    // beatHeavy fixture (`beat_bass = 1.0`, `bassDev = 0.60`) diverges
    // from steady/quiet (zero bass deviation → no vibration). All three
    // fixtures within the [10, 30] hamming band documented for D-095.
    //
    // V.7.7C.5.1 (D-100 follow-up): hashes drift hard. The combined effect
    // of (a) silk line widths halved (spoke/frame 0.0024 → 0.0010, spiral
    // 0.0013 → 0.0007), (b) silk luminescence dimmed (silkTint 0.85 → 0.55,
    // hub knot 1.20 → 0.70, ambient tint 0.40 → 0.20, axial coefficient
    // 0.6 → 0.3, halo magnitudes ~halved), (c) per-segment macro variation
    // (`ancSeed = arachHashU32(webs[0].rng_seed ^ 0xCA51u)` instead of
    // hardcoded 1984u), (d) §4.3 palette pumped (sat 0.55–0.95 / val
    // 0.30–0.70 / hue cycle on accumulated_audio_time), and (e) shaft
    // engagement reformulated to floor+scale collapses the frame-phase-0
    // foreground hash to near-zero (the harness's zeroed slot 6 makes
    // foreground render minimally; thinner+dimmer lines push contribution
    // below dHash quantization). Real visual divergence is observed in
    // PresetVisualReviewTests where the harness binds a fully-built
    // Arachne state with a real polygon.
    "Arachne": (steady: 0x0000000000000000, beatHeavy: 0x0000004000000000, quiet: 0x0000000000000000),
    // AV.2 (2026-05-18): Aurora Veil now wires seven audio routes per §5.7,
    // but the regression fixtures don't set `bass_att_rel` / `mid_att_rel`
    // / `valence` / stems, so routes 2/3/4/6/7 fire at their neutral
    // values and the harness's zeroed slot-6 buffer leaves the
    // smoothedPitchNorm gated to the 0.5 baseline (route 1 inactive) and
    // the kinkAccumulator at 0 (route 5 inactive). The shader's pixel
    // output therefore diverges from AV.1 ONLY by the 3-column max-merge
    // raymarch structure (and the per-column non-parallel substrate drift
    // velocities, which only matter when `f.time` differs across fixtures
    // — i.e. between the three fixtures, not between AV.1 and AV.2 at the
    // same fixture). At 64×64 dHash with 9×8 cell quantisation the AV.1 →
    // AV.2 visual delta is Hamming-distance ~1-4 bits per fixture.
    "Aurora Veil": (steady: 0x109B0A1B5E1B1B9A, beatHeavy: 0x109F0E1F1E1D1F9E, quiet: 0x109F0E1F561D1F9E),
    // V.9 Session 1 — regen at Session 5 cert review (D-124 redirect: full preset
    // rewrite, glass-dish baseline replaced; golden hashes are stale by design).
    // "Ferrofluid Ocean": (steady: 0x56AB1C4A28B32727, beatHeavy: 0x5CB393AAAFA84840, quiet: 0xA64C51A62FD35356),
    "Glass Brutalist": (steady: 0x336954B4B4544D33, beatHeavy: 0x336954B4B4544D33, quiet: 0x336954B4B4544D33),
    "Gossamer": (steady: 0x5756A72F070F0F0D, beatHeavy: 0x5756A72F070F0F0D, quiet: 0x5756872D0F0F0F0D),
    // QR.1 (D-079): sminK now mixes continuous bass (Layer 1) + bass_dev
    // accent. steady/quiet hashes regenerated to original V.7 values within
    // the 8-bit dHash tolerance; beatHeavy shifts slightly because bass_dev
    // now contributes a small +0.06 to the smooth-union radius.
    "Kinetic Sculpture": (steady: 0x5EAB7295D25B4A4A, beatHeavy: 0x5AAB72B5564B4A4B, quiet: 0x56AB7295925B4A4A),
    // LM.4.5 (full-spectrum palette card model): the regression harness
    // leaves slot 8 bound to the zero placeholder buffer, so every cell
    // picks card slot `(cellHash + 0) % 48` and the per-track seed hash
    // is a fixed constant. The new card-model HSV samples produce a 64×64
    // dHash luma pattern that matches the prior LM.3.2 hash inside the
    // 8-bit Hamming tolerance — the Voronoi cell quantization dominates
    // dHash at this resolution, not the palette algorithm. Real visual
    // divergence between LM.3.2 and LM.4.5 is observed via
    // `RENDER_VISUAL=1 PresetVisualReviewTests` with the 9-fixture set
    // (the 4 per-track-seed corner fixtures exercise the card variety
    // that the regression harness can't reach with zero seeds).
    //
    // LM.6 (cell-depth gradient + hot-spot): hash UNCHANGED. The depth
    // gradient and hot-spot modulate `cell_hue` based on the Voronoi
    // `f1/f2` field — the same field that already drives cell quantization
    // and frost mixing — so the per-cell luma envelope shifts smoothly
    // toward darker at edges + brighter at centres, but the 9×8 dHash
    // grid's 64×64 luma quantization is dominated by the Voronoi cell
    // boundary positions (large-scale signal) rather than per-cell
    // intensity gradients (small-scale signal). Real visual divergence
    // — domed cells reading as backlit glass instead of flat tiles, plus
    // optional centre hot-spots — is observed via `RENDER_VISUAL=1
    // PresetVisualReviewTests` 9-fixture set.
    //
    // LM.4.7 (curated 18-palette library + per-song mood-biased selection):
    // hash UNCHANGED. The regression harness now binds an explicit Autumnal
    // palette (index 0 of `LumenMosaicPaletteLibrary.all`) at slot 8 with
    // pre-ticked band counters so `lm_cell_palette` walks the 12 palette
    // entries deterministically — but the harness samples `color(0)` of the
    // ray-march G-buffer (`{depth, matID}`), not the lighting-pass albedo.
    // Per-cell palette colour drift is invisible at this hash; cell shape
    // (depth + matID) is what dHash measures. Real per-track palette
    // identity is observed via `RENDER_VISUAL=1 PresetVisualReviewTests`
    // and Matt M7 review on real-music sessions (BUG-014 acceptance).
    "Lumen Mosaic": (steady: 0xF0F0C8CCCCC8F0F0, beatHeavy: 0xF0F0C8CCCCC8F0F0, quiet: 0xF0F0C8CCCCC8F0F0),
    "Membrane": (steady: 0x33E3A919C9627939, beatHeavy: 0x12A3A998C9646139, quiet: 0x47E3C919CD627959),
    "Murmuration": (steady: 0x07449B6727773FF8, beatHeavy: 0x0B449A4727373FF8, quiet: 0x0744936727773FF8),
    // NB.9 (D-140, first volumetric preset): all three fixtures are IDENTICAL.
    // Nimbus's GPU output is animated (flowPhase) and entirely driven by the
    // CPU-side NimbusStateGPU at slot 6 (bloom / flow / stem lobes / mood) plus
    // noiseVolume at texture(6) — the only FeatureVector field the shader reads
    // is aspect_ratio. The regression harness binds a ZEROED slot-6 buffer (the
    // deterministic silence-floor body at flowPhase 0) and the three fixtures
    // differ only in FeatureVector fields the shader never reads, so steady /
    // beatHeavy / quiet all converge to one hash. The 0x0F-per-byte pattern is a
    // clean centred body — each row brightens toward the centre (left 4 cells
    // set) then darkens (right 4 clear) — so a regression that broke the
    // silhouette, the backlit lighting gradient, or the haze falloff shifts it.
    // Production-parity coverage (ticked followers + bound noiseVolume) is
    // NimbusBloomFollowerTest + PresetVisualReviewTests.
    "Nimbus": (steady: 0x0F0F0F0F0F0F0F0F, beatHeavy: 0x0F0F0F0F0F0F0F0F, quiet: 0x0F0F0F0F0F0F0F0F),
    "Nebula": (steady: 0x0000080C0C080000, beatHeavy: 0x0000080C0C080000, quiet: 0x0000080C0C080000),
    "Plasma": (steady: 0x030F170A072F1B0F, beatHeavy: 0x4193254F0E8E87C7, quiet: 0x0F1F0F0F0F07070F),
    "Spectral Cartograph": (steady: 0x00180C0C0C0C0000, beatHeavy: 0x00180C0C0C0C6080, quiet: 0x00180C0C0C0C0000),
    "Staged Sandbox": (steady: 0x000022160A162A00, beatHeavy: 0x000022160A162A00, quiet: 0x000022160A162A00),
    "Volumetric Lithograph": (steady: 0x8C63D43512030000, beatHeavy: 0x8C63D43512030000, quiet: 0x8C63D43512030000),
    "Waveform": (steady: 0x000F0F0000000000, beatHeavy: 0x000F0F0000000000, quiet: 0x000F0F0000000000),
]

private let hammingThreshold = 8  // ≤ 8 of 64 bits may differ

// MARK: - Suite

@Suite("Preset Regression Tests")
struct PresetRegressionTests {

    // MARK: - Fixtures (identical definitions to PresetAcceptanceTests)

    private var steadyFixture: FeatureVector {
        FeatureVector(bass: 0.50, mid: 0.50, treble: 0.50, time: 3.0, deltaTime: 0.016)
    }

    private var beatHeavyFixture: FeatureVector {
        var fv = FeatureVector(bass: 0.80, mid: 0.50, treble: 0.50, beatBass: 1.0, time: 5.0, deltaTime: 0.016)
        fv.bassRel = 0.60
        fv.bassDev = 0.60
        return fv
    }

    private var quietFixture: FeatureVector {
        var fv = FeatureVector(bass: 0.15, mid: 0.15, treble: 0.15, time: 2.0, deltaTime: 0.016)
        fv.bassRel = -0.70
        fv.midRel = -0.70
        fv.trebRel = -0.70
        return fv
    }

    // MARK: - Regression Tests

    @Test("Visual regression: steady energy", arguments: _acceptanceFixture.presets)
    func test_steadyHash(_ preset: PresetLoader.LoadedPreset) throws {
        guard !preset.descriptor.passes.contains(.meshShader) else { return }
        guard let golden = goldenPresetHashes[preset.descriptor.name] else { return }
        let ctx = try MetalContext()
        var fixture = steadyFixture
        let pixels = try renderFrame(preset: preset, features: &fixture, context: ctx)
        let hash = dHash(pixels)
        let distance = hammingDistance(hash, golden.steady)
        #expect(
            distance <= hammingThreshold,
            """
            Preset '\(preset.descriptor.name)' steady hash drifted: \
            distance=\(distance) threshold=\(hammingThreshold) \
            new=0x\(String(hash, radix: 16, uppercase: true)) \
            golden=0x\(String(golden.steady, radix: 16, uppercase: true))
            """
        )
    }

    @Test("Visual regression: beat-heavy energy", arguments: _acceptanceFixture.presets)
    func test_beatHeavyHash(_ preset: PresetLoader.LoadedPreset) throws {
        guard !preset.descriptor.passes.contains(.meshShader) else { return }
        guard let golden = goldenPresetHashes[preset.descriptor.name] else { return }
        let ctx = try MetalContext()
        var fixture = beatHeavyFixture
        let pixels = try renderFrame(preset: preset, features: &fixture, context: ctx)
        let hash = dHash(pixels)
        let distance = hammingDistance(hash, golden.beatHeavy)
        #expect(
            distance <= hammingThreshold,
            """
            Preset '\(preset.descriptor.name)' beat-heavy hash drifted: \
            distance=\(distance) threshold=\(hammingThreshold) \
            new=0x\(String(hash, radix: 16, uppercase: true)) \
            golden=0x\(String(golden.beatHeavy, radix: 16, uppercase: true))
            """
        )
    }

    @Test("Visual regression: quiet passage", arguments: _acceptanceFixture.presets)
    func test_quietHash(_ preset: PresetLoader.LoadedPreset) throws {
        guard !preset.descriptor.passes.contains(.meshShader) else { return }
        guard let golden = goldenPresetHashes[preset.descriptor.name] else { return }
        let ctx = try MetalContext()
        var fixture = quietFixture
        let pixels = try renderFrame(preset: preset, features: &fixture, context: ctx)
        let hash = dHash(pixels)
        let distance = hammingDistance(hash, golden.quiet)
        #expect(
            distance <= hammingThreshold,
            """
            Preset '\(preset.descriptor.name)' quiet hash drifted: \
            distance=\(distance) threshold=\(hammingThreshold) \
            new=0x\(String(hash, radix: 16, uppercase: true)) \
            golden=0x\(String(golden.quiet, radix: 16, uppercase: true))
            """
        )
    }

    @Test("Print golden hashes (UPDATE_GOLDEN_SNAPSHOTS only)")
    func test_printGoldenHashes() throws {
        guard ProcessInfo.processInfo.environment["UPDATE_GOLDEN_SNAPSHOTS"] != nil else { return }
        let ctx = try MetalContext()
        print("\n// Paste into goldenPresetHashes in PresetRegressionTests.swift:")
        for preset in _acceptanceFixture.presets {
            guard !preset.descriptor.passes.contains(.meshShader) else { continue }
            var steady = steadyFixture
            var beatHeavy = beatHeavyFixture
            var quiet = quietFixture
            let sp = try renderFrame(preset: preset, features: &steady, context: ctx)
            let bp = try renderFrame(preset: preset, features: &beatHeavy, context: ctx)
            let qp = try renderFrame(preset: preset, features: &quiet, context: ctx)
            let sh = dHash(sp)
            let bh = dHash(bp)
            let qh = dHash(qp)
            print("""
            "\(preset.descriptor.name)": \
            (steady: 0x\(hexString(sh)), beatHeavy: 0x\(hexString(bh)), quiet: 0x\(hexString(qh))),
            """)
        }
    }

    // MARK: - Rendering (duplicated from PresetAcceptanceTests — no shared helpers across @Suite structs)

    private let renderSize = 64

    private func renderFrame(
        preset: PresetLoader.LoadedPreset,
        features: inout FeatureVector,
        context: MetalContext
    ) throws -> [UInt8] {
        let size = renderSize
        let texDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: context.pixelFormat, width: size, height: size, mipmapped: false)
        texDesc.usage = [.renderTarget, .shaderRead]
        texDesc.storageMode = .shared
        guard let texture = context.device.makeTexture(descriptor: texDesc) else {
            throw RegressionTestError.textureAllocationFailed
        }
        let buffers = try makeRenderBuffers(context: context, preset: preset)
        guard let cmdBuf = context.commandQueue.makeCommandBuffer() else {
            throw RegressionTestError.commandBufferFailed
        }
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = texture
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        rpd.colorAttachments[0].storeAction = .store
        guard let encoder = cmdBuf.makeRenderCommandEncoder(descriptor: rpd) else {
            throw RegressionTestError.encoderCreationFailed
        }
        encoder.setRenderPipelineState(preset.pipelineState)
        encoder.setFragmentBytes(&features, length: MemoryLayout<FeatureVector>.size, index: 0)
        encoder.setFragmentBuffer(buffers.fft, offset: 0, index: 1)
        encoder.setFragmentBuffer(buffers.wav, offset: 0, index: 2)
        encoder.setFragmentBuffer(buffers.stem, offset: 0, index: 3)
        if let sceneBuf = buffers.scene { encoder.setFragmentBuffer(sceneBuf, offset: 0, index: 4) }
        encoder.setFragmentBuffer(buffers.hist, offset: 0, index: 5)
        // AV.2: Aurora Veil reads a 16-byte AuroraVeilStateGPU at slot 6
        // (kinkAccumulator + smoothedPitchNorm). The fixtures have zero
        // stems → confidence gate is 0 → smoothedPitchNorm is ignored; the
        // kink is 0; so a zero buffer is the silence-equivalent state and
        // the harness binds it explicitly to avoid an unbound-buffer read.
        if let avState = buffers.auroraVeilState {
            encoder.setFragmentBuffer(avState, offset: 0, index: 6)
        }
        // NB.9 (D-140): Nimbus reads a 32-byte NimbusStateGPU at slot 6 (the
        // CPU-side bloom / flow / stem-lobe / mood followers). The shader reads
        // ALL of its music response from this buffer plus noiseVolume at
        // texture(6); the only FeatureVector field it touches is aspect_ratio.
        // Bind a ZEROED state — the deterministic silence-floor body at
        // flowPhase 0 — so the golden hash is reproducible (the three fixtures
        // differ only in FeatureVector fields the shader never reads, so all
        // three Nimbus hashes converge). noiseVolume stays unbound (→ 0) per the
        // suite convention; the dHash captures the macro silhouette + lighting +
        // haze, which is the fingerprint regressions must preserve. Production-
        // parity coverage (noiseVolume + ticked followers) lives in
        // NimbusBloomFollowerTest + PresetVisualReviewTests.
        if let nbState = buffers.nimbusState {
            encoder.setFragmentBuffer(nbState, offset: 0, index: 6)
        }
        if let lumenBuf = buffers.lumen {
            encoder.setFragmentBuffer(lumenBuf, offset: 0, index: 8)
        }
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()
        guard cmdBuf.status == .completed else { throw RegressionTestError.renderFailed }
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        texture.getBytes(&pixels, bytesPerRow: size * 4,
                         from: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0)
        return pixels
    }

    private struct RenderBuffers {
        let fft: MTLBuffer
        let wav: MTLBuffer
        let stem: MTLBuffer
        let hist: MTLBuffer
        let scene: MTLBuffer?
        let lumen: MTLBuffer?
        let auroraVeilState: MTLBuffer?
        let nimbusState: MTLBuffer?
    }

    private func makeRenderBuffers(context: MetalContext, preset: PresetLoader.LoadedPreset) throws -> RenderBuffers {
        let floatStride = MemoryLayout<Float>.stride
        guard
            let fft = context.makeSharedBuffer(length: 512 * floatStride),
            let wav = context.makeSharedBuffer(length: 2048 * floatStride),
            let stem = context.makeSharedBuffer(length: MemoryLayout<StemFeatures>.size),
            let hist = context.makeSharedBuffer(length: 4096 * floatStride)
        else { throw RegressionTestError.bufferAllocationFailed }

        _ = fft.contents().initializeMemory(as: UInt8.self, repeating: 0, count: 512 * floatStride)
        _ = stem.contents().initializeMemory(as: UInt8.self, repeating: 0, count: MemoryLayout<StemFeatures>.size)
        _ = hist.contents().initializeMemory(as: UInt8.self, repeating: 0, count: 4096 * floatStride)

        var scene: MTLBuffer?
        if preset.descriptor.passes.contains(.rayMarch),
           let buf = context.makeSharedBuffer(length: MemoryLayout<SceneUniforms>.size) {
            var su = preset.descriptor.makeSceneUniforms()
            buf.contents().copyMemory(from: &su, byteCount: MemoryLayout<SceneUniforms>.size)
            scene = buf
        }

        // LM.4.7: Lumen Mosaic reads a 12-entry palette payload at slot 8.
        // The regression harness binds an explicit Autumnal-palette state
        // (palette index 0 from `LumenMosaicPaletteLibrary.all`) so the
        // golden hash is deterministic and reproducible across runs. Other
        // presets receive a nil binding; they don't read slot 8 (the
        // preamble's `LumenPatternState` parameter is silenced via
        // `(void)lumen;` in their `sceneMaterial` overrides, but the
        // pipeline requires SOMETHING bound — falls through to the
        // pipeline's automatic placeholder if the encoder skips slot 8).
        var lumen: MTLBuffer?
        if preset.descriptor.name == "Lumen Mosaic" {
            let stateStride = MemoryLayout<LumenPatternState>.stride
            if let buf = context.makeSharedBuffer(length: stateStride) {
                var state = LumenPatternState()
                let palette = LumenMosaicPaletteLibrary.all[0]   // Autumnal
                let entries: [LumenPaletteEntry] = palette.colors.map { LumenPaletteEntry($0) }
                state.palette = (
                    entries[0], entries[1], entries[2],  entries[3],
                    entries[4], entries[5], entries[6],  entries[7],
                    entries[8], entries[9], entries[10], entries[11]
                )
                // Tick a few synthetic beats forward so `bassCounter` is
                // non-zero and the palette walk produces a representative
                // sample of the 12 entries (sectionSalt = 0, step varies).
                state.bassCounter   = 7
                state.midCounter    = 3
                state.trebleCounter = 1
                state.activeLightCount = 4
                buf.contents().copyMemory(from: &state, byteCount: stateStride)
                lumen = buf
            }
        }

        // AV.2: Aurora Veil reads a 16-byte AuroraVeilStateGPU at slot 6
        // (kinkAccumulator + smoothedPitchNorm). The regression fixtures
        // have zero stems → shader's confidence gate is 0 → smoothedPitchNorm
        // ignored; the kink is 0 anyway. Bind a zero buffer so the slot is
        // populated rather than left undefined.
        var auroraVeilState: MTLBuffer?
        if preset.descriptor.name == "Aurora Veil" {
            let avStride = 16   // matches AuroraVeilStateGPU stride (4 × float)
            if let buf = context.makeSharedBuffer(length: avStride) {
                _ = buf.contents().initializeMemory(as: UInt8.self, repeating: 0, count: avStride)
                auroraVeilState = buf
            }
        }

        // NB.9 (D-140): Nimbus reads a 32-byte NimbusStateGPU at slot 6. A zeroed
        // buffer is the silence-floor state (all followers 0, flowPhase 0) — the
        // deterministic body the golden registers against.
        var nimbusState: MTLBuffer?
        if preset.descriptor.name == "Nimbus" {
            let nbStride = MemoryLayout<NimbusStateGPU>.stride   // 32 bytes
            if let buf = context.makeSharedBuffer(length: nbStride) {
                _ = buf.contents().initializeMemory(as: UInt8.self, repeating: 0, count: nbStride)
                nimbusState = buf
            }
        }

        return RenderBuffers(fft: fft, wav: wav, stem: stem, hist: hist,
                             scene: scene, lumen: lumen,
                             auroraVeilState: auroraVeilState,
                             nimbusState: nimbusState)
    }

    // MARK: - dHash

    /// Computes a 64-bit dHash: downsample to a 9×8 luma grid, compare adjacent horizontal cells.
    private func dHash(_ pixels: [UInt8], width: Int = 64, height: Int = 64) -> UInt64 {
        let grid = computeLumaGrid(pixels: pixels, width: width, height: height, cols: 9, rows: 8)
        var hash: UInt64 = 0
        for row in 0..<8 {
            for col in 0..<8 {
                if grid[row * 9 + col + 1] > grid[row * 9 + col] {
                    hash |= UInt64(1) << UInt64(row * 8 + col)
                }
            }
        }
        return hash
    }

    /// Downsamples pixels to a cols×rows luma grid by averaging cells.
    /// BGRA byte order: luma = 0.114·B + 0.587·G + 0.299·R.
    private func computeLumaGrid(
        pixels: [UInt8], width: Int, height: Int, cols: Int, rows: Int
    ) -> [Float] {
        var grid = [Float](repeating: 0, count: cols * rows)
        for row in 0..<rows {
            let yStart = row * height / rows
            let yEnd = (row + 1) * height / rows
            for col in 0..<cols {
                let xStart = col * width / cols
                let xEnd = (col + 1) * width / cols
                var sum: Float = 0
                var count = 0
                for y in yStart..<yEnd {
                    for x in xStart..<xEnd {
                        let idx = (y * width + x) * 4
                        sum += 0.114 * Float(pixels[idx]) + 0.587 * Float(pixels[idx + 1]) + 0.299 * Float(pixels[idx + 2])
                        count += 1
                    }
                }
                grid[row * cols + col] = count > 0 ? sum / Float(count) : 0
            }
        }
        return grid
    }

    private func hammingDistance(_ a: UInt64, _ b: UInt64) -> Int {
        (a ^ b).nonzeroBitCount
    }

    private func hexString(_ value: UInt64) -> String {
        String(format: "%016llX", value)
    }
}

// MARK: - Error

private enum RegressionTestError: Error {
    case textureAllocationFailed
    case bufferAllocationFailed
    case commandBufferFailed
    case encoderCreationFailed
    case renderFailed
}
