// PresetAcceptanceTests — Structural invariant gate for all production presets.
//
// Fixture vectors represent documented real-audio states from CLAUDE.md's reference
// onset table (Love Rehab ~125 BPM, Miles Davis ~136 BPM). They are not synthetic
// time-domain envelopes — they are structural assertions about the AGC-normalized
// GPU contract. See D-037 in DECISIONS.md.
//
// Why steadyFixture (not silence) for invariants 1 and 4:
//   Presets like Fractal Tree and ray-march scenes are intentionally dark at zero
//   energy — that is correct product behaviour. The meaningful invariant is that
//   presets are visible when music is playing (bass/mid/treble ≈ 0.5 = AGC average).

import Testing
import Metal
@testable import Renderer
@testable import Presets
@testable import Shared

// MARK: - Shared Fixture Context (module-level, computed once)

struct PresetFixtureContext {
    let presets: [PresetLoader.LoadedPreset]
}

let _acceptanceFixture: PresetFixtureContext = {
    guard let ctx = try? MetalContext() else { return PresetFixtureContext(presets: []) }
    let loader = PresetLoader(device: ctx.device, pixelFormat: ctx.pixelFormat, loadBuiltIn: true)
    return PresetFixtureContext(presets: loader.presets)
}()

// MARK: - Suite

@Suite("Preset Acceptance Tests")
struct PresetAcceptanceTests {

    // MARK: - Fixtures

    // Silence: all energy zero. Used for the beat-response baseline only.
    private var silenceFixture: FeatureVector { FeatureVector(time: 1.0, deltaTime: 0.016) }

    // Steady mid-energy: AGC-normalized steady state. All bands at ~0.5 = AGC average.
    // Rel/dev fields are zero (exactly at AGC average). Representative of a sustained
    // piano passage or dense ambient mix. Used for invariants 1, 2, 4.
    private var steadyFixture: FeatureVector {
        FeatureVector(bass: 0.50, mid: 0.50, treble: 0.50, time: 3.0, deltaTime: 0.016)
    }

    // Beat-heavy: bass at 0.80 (bassRel = +0.60), beatBass = 1.0 (peak pulse).
    // Represents an electronic kick drum downbeat (Love Rehab ~125 BPM reference:
    // sub_bass + low_bass ≈ 21 onsets per 5 s window, CLAUDE.md onset table).
    private var beatHeavyFixture: FeatureVector {
        var fv = FeatureVector(bass: 0.80, mid: 0.50, treble: 0.50, beatBass: 1.0, time: 5.0, deltaTime: 0.016)
        fv.bassRel = 0.60
        fv.bassDev = 0.60
        return fv
    }

    // Quiet passage: all energy at 0.15 (well below AGC average → large negative rel).
    // bassRel = (0.15 − 0.5) × 2.0 = −0.70.
    // Representative of sparse jazz (Miles Davis reference: 5 sub_bass onsets per 5 s).
    private var quietFixture: FeatureVector {
        var fv = FeatureVector(bass: 0.15, mid: 0.15, treble: 0.15, time: 2.0, deltaTime: 0.016)
        fv.bassRel = -0.70
        fv.midRel = -0.70
        fv.trebRel = -0.70
        return fv
    }

    // MARK: - Invariant 1: Non-black output at normal energy

    // Presets that are dark at zero energy (Fractal Tree, ray-march scenes) are fine —
    // they require audio to produce visible output, which is correct product behaviour.
    // The gate here is that every preset must be visible when music is playing.
    //
    // Mesh-shader presets are skipped: on M3+ hardware pipelineState is a MTLMeshRenderPipeline
    // that cannot be invoked via drawPrimitives. There is no fallback vertex state on LoadedPreset.
    @Test("Preset produces non-black output with normal energy input", arguments: _acceptanceFixture.presets)
    func test_nonBlack_atSteadyEnergy(_ preset: PresetLoader.LoadedPreset) throws {
        guard !preset.descriptor.passes.contains(.meshShader) else { return }
        // Dragon Bloom L1 (D-137): content is the scene-geometry strands, not the
        // (near-black) standalone fragment this harness renders. See the readable-form
        // exemption below; production coverage is DragonBloomMVWarpAccumulationTest.
        guard preset.descriptor.name != "Dragon Bloom" else { return }
        // Fata Morgana (D-139): same rationale — the mirage is built by the
        // warp+comp+shapes feedback branch (drawWithFataMorgana); the standalone
        // `fata_morgana_fragment` this harness renders is intentionally black.
        // Production coverage: FataMorganaMVWarpAccumulationTest.
        guard preset.descriptor.name != "Fata Morgana" else { return }
        // Nacre (NACRE.2b): same rationale — the jello-mirror is built by the warp+comp
        // feedback branch (drawWithNacre); the standalone `nacre_fragment` this harness
        // renders is intentionally black. Production coverage: NacreMVWarpAccumulationTest.
        guard preset.descriptor.name != "Nacre" else { return }
        // Floret (FLORET.2a): same — built by the warp+comp feedback branch (drawWithFloret);
        // the standalone `floret_fragment` is intentionally black. Coverage: FloretMVWarpAccumulationTest.
        guard preset.descriptor.name != "Floret" else { return }
        // Filigree (PHYS.2): the gold web is the `PhysarumGeometry` particle trail;
        // the standalone `filigree_ground_fragment` this harness renders is the
        // intentionally pure-black Kintsugi ground (covered by the trail in
        // production). Coverage: PhysarumSketchRenderTests (multi-frame trail render).
        guard preset.descriptor.name != "Filigree" else { return }
        // Glaze (GLAZE.2a): same — the contour-gel is built by the warp+comp feedback branch
        // (drawWithGlaze); the standalone `glaze_fragment` is intentionally black. Production
        // coverage: GlazeMVWarpAccumulationTest.
        guard preset.descriptor.name != "Glaze" else { return }
        let ctx = try MetalContext()
        var fixture = steadyFixture
        let pixels = try renderFrame(preset: preset, features: &fixture, context: ctx)
        #expect(maxChannelValue(pixels) > 10, "Preset '\(preset.descriptor.name)' is black with normal energy input")
    }

    // MARK: - Invariant 2: No white clip on steady energy (non-HDR)

    // HDR presets that include post_process are exempt: tone-mapping clips internally.
    // Diagnostic presets are exempt: intentional white text labels for MIR data display
    // are not HDR overflow — they are by design.
    @Test("Preset does not clip to white on steady energy (non-HDR)", arguments: _acceptanceFixture.presets)
    func test_noWhiteClip_steadyEnergy(_ preset: PresetLoader.LoadedPreset) throws {
        guard !preset.descriptor.passes.contains(.postProcess) else { return }
        guard !preset.descriptor.isDiagnostic else { return }
        // Dragon Bloom (D-137) is an HDR-FEEDBACK preset: its scene/strand pipelines
        // render into a float (rgba16f) mv_warp buffer with intentionally bright
        // (>1.0) additive strand injection, and the faithful comp inverts the
        // saturated field. Rendering its standalone fragment to this 8-bit harness
        // target both mismatches the pipeline format and legitimately clips — same
        // exemption rationale as the post_process HDR presets above. Production
        // coverage (no DEGENERATE white-out) is DragonBloomMVWarpAccumulationTest.
        guard preset.descriptor.name != "Dragon Bloom" else { return }
        // Fata Morgana (D-139): same rationale — the mirage is built by the
        // warp+comp+shapes feedback branch (drawWithFataMorgana); the standalone
        // `fata_morgana_fragment` this harness renders is intentionally black.
        // Production coverage: FataMorganaMVWarpAccumulationTest.
        guard preset.descriptor.name != "Fata Morgana" else { return }
        // Nacre (NACRE.2b): same rationale — the jello-mirror is built by the warp+comp
        // feedback branch (drawWithNacre); the standalone `nacre_fragment` this harness
        // renders is intentionally black. Production coverage: NacreMVWarpAccumulationTest.
        guard preset.descriptor.name != "Nacre" else { return }
        // Floret (FLORET.2a): same — built by the warp+comp feedback branch (drawWithFloret);
        // the standalone `floret_fragment` is intentionally black. Coverage: FloretMVWarpAccumulationTest.
        guard preset.descriptor.name != "Floret" else { return }
        // Glaze (GLAZE.2a): same — the contour-gel is built by the warp+comp feedback branch
        // (drawWithGlaze); the standalone `glaze_fragment` is intentionally black. Production
        // coverage: GlazeMVWarpAccumulationTest.
        guard preset.descriptor.name != "Glaze" else { return }
        let ctx = try MetalContext()
        var fixture = steadyFixture
        let pixels = try renderFrame(preset: preset, features: &fixture, context: ctx)
        #expect(maxChannelValue(pixels) < 250, "Preset '\(preset.descriptor.name)' clips to white on steady energy")
    }

    // MARK: - Invariant 3: Beat response bounded relative to continuous response

    // Enforces the audio data hierarchy: beat onset is accent-only, never primary driver.
    // beatMotion ≤ continuousMotion × 2.0 + 1.0 (the +1.0 handles static presets
    // where both values are near zero).
    //
    // Diagnostic presets (motionIntensity == 0) are excluded: SpectralCartograph and
    // similar instrument-family presets visualise MIR data directly and are expected to
    // change dramatically on any FeatureVector change — that is their purpose.
    @Test("Beat response is bounded relative to continuous energy response", arguments: _acceptanceFixture.presets)
    func test_beatResponse_bounded(_ preset: PresetLoader.LoadedPreset) throws {
        guard preset.descriptor.motionIntensity > 0 else { return }
        // V.9 Session 1 (D-124): Ferrofluid Ocean's swell amplitude is routed
        // from `arousal` + (during stem warmup) `f.beat_bass * 0.3` as a
        // drums proxy per the documented D-019 silence fallback. Silence and
        // steady fixtures share arousal=0/beat_bass=0 → identical swell →
        // continuousMotion ≈ 0; the beat fixture has beat_bass=1.0 → larger
        // swell → unbounded beat:continuous ratio. The invariant is sound for
        // raw-band-driven presets but doesn't apply to a preset that derives
        // swell from beat_phase / arousal envelopes. Session 5 cert review
        // will revisit either the invariant or the fixture set.
        if preset.descriptor.name == "Ferrofluid Ocean" { return }
        // AV.2.2d (2026-05-19): Aurora Veil's brightness route switched from
        // `bass_att_rel` to `bass_dev` (positive-only deviation primitive)
        // after the route sat structurally negative on real music. The
        // beat-heavy fixture sets `bassDev = 0.60`; the steady fixture
        // defaults to `bassDev = 0`, so all brightness motion concentrates
        // on the beat-heavy fixture — same shape as Ferrofluid Ocean. The
        // invariant is sound for raw-band-driven presets but doesn't fit
        // positive-only-deviation consumers. On real music `bass_dev` fires
        // on actual bass transients across many frames (not the synthetic
        // "beat-heavy only" pattern this fixture simulates), so the live
        // continuous-vs-accent ratio is governed by the dedicated
        // `AuroraVeilContinuousDominanceTest` (drum-kink MSD ≤ 10% of
        // bass-brightness MSD at peak).
        if preset.descriptor.name == "Aurora Veil" { return }
        // Dragon Bloom (2026-06-02 re-tune): same fixture-conflation exemption as
        // Ferrofluid Ocean / Aurora Veil. The shared `beatHeavyFixture` cranks
        // bass 0.5→0.8 AND bassRel 0→0.6 AND beatBass 0→1.0 simultaneously, so
        // the steady→beatHeavy MSD captures Dragon Bloom's *continuous* bass
        // response (Layer-1 brightness + signed-bass_rel breathing) as if it were
        // beat response. Empirical proof the beat is NOT the culprit: cutting the
        // per-beat boost 2.7× (0.40→0.15) moved beatMotion only 9% (1875→1699) —
        // 91% of the delta is the continuous bass drivers, not the beat. Dragon
        // Bloom's actual beat coupling is a bounded 0.15 brightness shimmer
        // (deliberately small because mv_warp feedback amplifies beat flashes).
        // The real continuous-vs-accent guard is the radiusMotion metric in
        // DragonBloomMVWarpAccumulationTest (beat-free temporal motion driven by
        // bass_rel + flux). See the BUG-025 A/B diagnosis (2026-06-02).
        if preset.descriptor.name == "Dragon Bloom" { return }
        if preset.descriptor.name == "Fata Morgana" { return }
        if preset.descriptor.name == "Nacre" { return }   // NACRE.2b: feedback-branch preset (see above)
        if preset.descriptor.name == "Floret" { return }  // FLORET.2a: feedback-branch preset (see above)
        if preset.descriptor.name == "Glaze" { return }   // GLAZE.2a: feedback-branch preset (see above)
        let ctx = try MetalContext()
        var silence = silenceFixture
        var steady = steadyFixture
        var beatHeavy = beatHeavyFixture
        let silencePixels = try renderFrame(preset: preset, features: &silence, context: ctx)
        let steadyPixels = try renderFrame(preset: preset, features: &steady, context: ctx)
        let beatPixels = try renderFrame(preset: preset, features: &beatHeavy, context: ctx)
        let continuousMotion = meanSquaredDiff(silencePixels, steadyPixels)
        let beatMotion = meanSquaredDiff(steadyPixels, beatPixels)
        #expect(
            beatMotion <= continuousMotion * 2.0 + 1.0,
            """
            Preset '\(preset.descriptor.name)' overreacts to beat: \
            beatMotion=\(beatMotion) continuousMotion=\(continuousMotion)
            """
        )
    }

    // MARK: - Invariant 4: Readable form at normal energy

    // Catches presets that produce a single flat luma value — visually dead even when
    // audio is playing. A minimal gradient or SDF outline scores 2+ bins.
    // Mesh-shader presets are skipped for the same reason as invariant 1.
    // Staged-composition presets (Arachne, etc.) are skipped because their
    // visual signature requires per-preset slot-6/7 buffer bindings + a sampled
    // WORLD texture at [[texture(13)]] which the regression harness doesn't
    // provide — they have full coverage via PresetVisualReviewTests instead.
    @Test("Preset has readable form with normal energy input", arguments: _acceptanceFixture.presets)
    func test_readableForm_atSteadyEnergy(_ preset: PresetLoader.LoadedPreset) throws {
        guard !preset.descriptor.passes.contains(.meshShader) else { return }
        guard !preset.descriptor.passes.contains(.staged) else { return }
        // Dragon Bloom L1 (D-137): its content is the additive spectral STRANDS
        // drawn as scene geometry in the mv_warp scene-render path — the
        // standalone fragment is intentionally a near-black ground. This
        // fragment-only harness can't see the strands, so the readable-form +
        // non-black invariants don't apply. Production-pipeline coverage (strands
        // through scene→warp→compose→swap) lives in DragonBloomMVWarpAccumulationTest.
        guard preset.descriptor.name != "Dragon Bloom" else { return }
        // Fata Morgana (D-139): same rationale — the mirage is built by the
        // warp+comp+shapes feedback branch (drawWithFataMorgana); the standalone
        // `fata_morgana_fragment` this harness renders is intentionally black.
        // Production coverage: FataMorganaMVWarpAccumulationTest.
        guard preset.descriptor.name != "Fata Morgana" else { return }
        // Nacre (NACRE.2b): same rationale — the jello-mirror is built by the warp+comp
        // feedback branch (drawWithNacre); the standalone `nacre_fragment` this harness
        // renders is intentionally black. Production coverage: NacreMVWarpAccumulationTest.
        guard preset.descriptor.name != "Nacre" else { return }
        // Floret (FLORET.2a): same — feedback-branch preset; standalone fragment is black.
        guard preset.descriptor.name != "Floret" else { return }
        // Glaze (GLAZE.2a): same — the contour-gel is built by the warp+comp feedback branch
        // (drawWithGlaze); the standalone `glaze_fragment` is intentionally black. Production
        // coverage: GlazeMVWarpAccumulationTest.
        guard preset.descriptor.name != "Glaze" else { return }
        // Skein (D-143): its readable content (the test stamp; later the poured line) is
        // the marks-on-top overlay (skein_geometry_*) composited onto the held canvas in
        // the mv_warp path. This fragment-only harness renders the flat cream GROUND only
        // (1 luma bin), so the readable-form invariant doesn't apply — same exemption form
        // as Dragon Bloom / Fata Morgana. The overlay's lossless persistence is covered by
        // SkeinCanvasHoldTest's marks-on-top test. NOTE: Skein is NOT exempted from the
        // non-black / no-white-clip / contrast invariants — its cream ground (unlike the
        // near-black DB/FM fragments) genuinely passes those.
        guard preset.descriptor.name != "Skein" else { return }
        // Filigree (PHYS.2): same rationale as Dragon Bloom / Fata Morgana / Nacre —
        // the readable gold web is the `PhysarumGeometry` particle trail; the standalone
        // `filigree_ground_fragment` is the intentionally pure-black Kintsugi ground.
        // Coverage: PhysarumSketchRenderTests.
        guard preset.descriptor.name != "Filigree" else { return }
        // Ricercar (Ricercar.2): the flowing colour FIELD develops over MANY frames — deposited
        // colour masses advect + merge + decay-to-ground through the mv_warp feedback loop. This
        // single-frame fragment harness renders only the light ground (1 luma bin), so the
        // readable-form invariant doesn't apply — same exemption form as Skein. It is NOT exempted
        // from non-black / no-white-clip / beat-bounded (its light ground passes those). Multi-frame
        // coverage: RicercarSubstrateTest (flow + deposit + non-black, live mv_warp path).
        guard preset.descriptor.name != "Ricercar" else { return }
        let ctx = try MetalContext()
        var fixture = steadyFixture
        let pixels = try renderFrame(preset: preset, features: &fixture, context: ctx)
        #expect(
            formComplexity(pixels) >= 2,
            "Preset '\(preset.descriptor.name)' has no readable form with normal energy input"
        )
    }

    // MARK: - Rendering

    private let renderSize = 64

    /// Renders one frame via the preset's direct pipeline into a 64×64 BGRA offscreen texture.
    ///
    /// Provides realistic buffer bindings:
    /// - buffer(0): FeatureVector from `features`
    /// - buffer(1): FFT magnitudes (zeroed)
    /// - buffer(2): waveform (zeroed)
    /// - buffer(3): StemFeatures (zeroed)
    /// - buffer(4): SceneUniforms from descriptor (ray march presets only)
    /// - buffer(5): SpectralHistoryBuffer (zeroed, 16 KB)
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
            throw AcceptanceTestError.textureAllocationFailed
        }
        let buffers = try makeRenderBuffers(context: context, preset: preset)
        guard let cmdBuf = context.commandQueue.makeCommandBuffer() else {
            throw AcceptanceTestError.commandBufferFailed
        }
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = texture
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        rpd.colorAttachments[0].storeAction = .store
        guard let encoder = cmdBuf.makeRenderCommandEncoder(descriptor: rpd) else {
            throw AcceptanceTestError.encoderCreationFailed
        }
        encoder.setRenderPipelineState(preset.pipelineState)
        encoder.setFragmentBytes(&features, length: MemoryLayout<FeatureVector>.size, index: 0)
        encoder.setFragmentBuffer(buffers.fft, offset: 0, index: 1)
        encoder.setFragmentBuffer(buffers.wav, offset: 0, index: 2)
        encoder.setFragmentBuffer(buffers.stem, offset: 0, index: 3)
        if let sceneBuf = buffers.scene { encoder.setFragmentBuffer(sceneBuf, offset: 0, index: 4) }
        encoder.setFragmentBuffer(buffers.hist, offset: 0, index: 5)
        encoder.setFragmentBuffer(buffers.presetState, offset: 0, index: 6)
        encoder.setFragmentBuffer(buffers.presetState, offset: 0, index: 7)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()
        guard cmdBuf.status == .completed else { throw AcceptanceTestError.renderFailed }
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
        let presetState: MTLBuffer  // zeroed 1 KB — covers preset-specific slots (e.g. buffer(6) for Gossamer)
        let scene: MTLBuffer?
    }

    private func makeRenderBuffers(context: MetalContext, preset: PresetLoader.LoadedPreset) throws -> RenderBuffers {
        let floatStride = MemoryLayout<Float>.stride
        guard
            let fft = context.makeSharedBuffer(length: 512 * floatStride),
            let wav = context.makeSharedBuffer(length: 2048 * floatStride),
            let stem = context.makeSharedBuffer(length: MemoryLayout<StemFeatures>.size),
            let hist = context.makeSharedBuffer(length: 4096 * floatStride),
            let presetState = context.makeSharedBuffer(length: 1024)
        else { throw AcceptanceTestError.bufferAllocationFailed }

        _ = fft.contents().initializeMemory(as: UInt8.self, repeating: 0, count: 512 * floatStride)
        _ = stem.contents().initializeMemory(as: UInt8.self, repeating: 0, count: MemoryLayout<StemFeatures>.size)
        _ = hist.contents().initializeMemory(as: UInt8.self, repeating: 0, count: 4096 * floatStride)
        _ = presetState.contents().initializeMemory(as: UInt8.self, repeating: 0, count: 1024)

        // V.7.7C.2 / D-095 — Arachne foreground anchor block now reads
        // `webs[0]` Row 5 BuildState (build_stage / frame_progress /
        // radial_packed / spiral_packed). Without seeding, the zeroed buffer
        // gives `build_stage = 0, frame_progress = 0` → frame phase at 0%
        // progress, nothing rendered. PresetAcceptance expects a visible
        // foreground hero at "normal music energy" (D-037 invariants 1 + 4),
        // so write a fully-built `.stable` BuildState into webs[0]'s Row 5.
        // CPU-side `arachneState.reset()` (in production via applyPreset) does
        // the equivalent at preset bind; the acceptance harness doesn't run
        // ArachneState, so we seed Row 5 directly. Other presets that bind
        // slot 6 (Gossamer / Stalker / Staged Sandbox) read different structs
        // and the first 96 bytes here either don't intersect their layout or
        // are overwritten by their own initialization paths.
        if preset.descriptor.fragmentFunction == "arachne_composite_fragment" {
            let row5Offset = 80   // 5 rows × 16 bytes — Row 5 starts at byte 80 of webs[0]
            let buildStage: Float = 3.0     // .stable
            let frameProgress: Float = 1.0  // 100 %
            let radialPacked: Float = 13.0  // CPU radialCount default; "all radials drawn"
            let spiralPacked: Float = 1.0   // BUG-037: spiral_packed is now the CPU-normalized reveal fraction (0..1); .stable ⇒ shader uses 1.0 regardless
            let row5: [Float] = [buildStage, frameProgress, radialPacked, spiralPacked]
            row5.withUnsafeBytes { src in
                let dst = presetState.contents().advanced(by: row5Offset)
                dst.copyMemory(from: src.baseAddress!, byteCount: src.count)
            }

            // V.7.7C.3 / D-095 follow-up — pack a 5-vertex polygon (anchors
            // [0,1,2,3,4] of branchAnchors) into webs[0].rngSeed at byte
            // offset 28 (Row 1, 4th uint32). This drives the foreground
            // anchor block's polygon-aware spoke clipping + irregular frame
            // thread, keeping PresetRegression goldens sensitive to polygon-
            // mode regressions. polyCount=0 (uninitialised) would fall back
            // to V.7.5 circular geometry and silently mask polygon bugs.
            let rngSeedOffset = 28
            let polyPacked: UInt32 = ArachneState.packPolygonAnchors([0, 1, 2, 3, 4])
            var polyPackedCopy = polyPacked
            withUnsafeBytes(of: &polyPackedCopy) { src in
                let dst = presetState.contents().advanced(by: rngSeedOffset)
                dst.copyMemory(from: src.baseAddress!, byteCount: src.count)
            }
        }

        // SceneUniforms for ray-march presets provide proper camera/lighting.
        // Without them, farPlane = 0 causes every ray to return sky depth — all-black output.
        var scene: MTLBuffer?
        if preset.descriptor.passes.contains(.rayMarch),
           let buf = context.makeSharedBuffer(length: MemoryLayout<SceneUniforms>.size) {
            var su = preset.descriptor.makeSceneUniforms()
            buf.contents().copyMemory(from: &su, byteCount: MemoryLayout<SceneUniforms>.size)
            scene = buf
        }
        return RenderBuffers(fft: fft, wav: wav, stem: stem, hist: hist, presetState: presetState, scene: scene)
    }

    // MARK: - Pixel Statistics

    /// Maximum linear channel value across all pixels (0–255), skipping alpha.
    /// BGRA format: per-pixel byte order is [B, G, R, A].
    private func maxChannelValue(_ pixels: [UInt8]) -> UInt8 {
        var result: UInt8 = 0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            result = max(result, pixels[i], pixels[i + 1], pixels[i + 2])
        }
        return result
    }

    /// Mean squared difference between two pixel buffers (non-alpha channels only).
    private func meanSquaredDiff(_ a: [UInt8], _ b: [UInt8]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var sum: Float = 0
        var count = 0
        for i in stride(from: 0, to: a.count, by: 4) {
            for c in 0..<3 {
                let diff = Float(a[i + c]) - Float(b[i + c])
                sum += diff * diff
                count += 1
            }
        }
        return count > 0 ? sum / Float(count) : 0
    }

    /// Counts luma bins (8 bins of 32 levels each) with ≥ 1% of pixels.
    /// 1 = flat/dead, 8 = rich visual structure. BGRA: luma = 0.299R + 0.587G + 0.114B.
    private func formComplexity(_ pixels: [UInt8]) -> Int {
        let pixelCount = pixels.count / 4
        guard pixelCount > 0 else { return 0 }
        var bins = [Int](repeating: 0, count: 8)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let luma = 0.114 * Float(pixels[i]) + 0.587 * Float(pixels[i + 1]) + 0.299 * Float(pixels[i + 2])
            bins[min(Int(luma / 32.0), 7)] += 1
        }
        let threshold = max(1, pixelCount / 100)
        return bins.filter { $0 >= threshold }.count
    }
}

// MARK: - Error

private enum AcceptanceTestError: Error {
    case textureAllocationFailed
    case bufferAllocationFailed
    case commandBufferFailed
    case encoderCreationFailed
    case renderFailed
}
