// FerrofluidOceanVisualTests — V.9 Session 1–4.5 visual harness.
//
// Session 1 gates (per FERROFLUID_OCEAN_CLAUDE_CODE_PROMPTS.md §1–§3):
//
//   1. testFerrofluidOceanShaderCompiles — preset loads and the ray-march
//      G-buffer pipeline state is non-nil. Failed Approach #44 (silent Metal
//      compile drop) is gated by this assertion in combination with
//      `PresetLoaderCompileFailureTest` (preset count remains 15).
//
//   2. testFerrofluidOceanRendersFourFixtures — preset renders successfully
//      at the four standard fixtures (silence / steady-mid / beat-heavy /
//      quiet) and produces non-black, non-clipped output. Every fixture
//      ticks a real `FerrofluidStageRig` (Session 4.5: aurora-band sky
//      reflection requires an active rig to produce visible chromatic
//      content; silence-only rig from Session 3 left non-silence fixtures
//      rendering placeholder-only with no bands).
//
//   3. testFerrofluidOceanIndependenceStatesReachable — D-124(d) independence
//      contract: calm-body-with-spikes (low arousal + high bass_dev) and
//      agitated-body-without-spikes (high arousal + low bass_dev) produce
//      visibly distinct frames. Pixel diff > threshold, no golden hash lock.
//
// Session 2 gates, adapted for Session 4.5 (per FERROFLUID_OCEAN prompt §4):
//
//   4. testFerrofluidOceanMoodTintAtmosphereShifts — silence fixture rendered
//      twice (valence -0.9 → cool; valence +0.9 → warm) produces a visible
//      palette shift through the V.9 Session 4.5 procedural-sky path. The
//      sky function's `baseSky * scene.lightColor.rgb` multiply carries
//      D-022 mood-tint through the entire reflected sky. Asserts average
//      channel difference > 1.0.
//
//   5. testFerrofluidOceanMoodTintSkyBaseShift — same valence-shift comparison
//      with fog explicitly disabled, so the gate exercises only the sky-base
//      `scene.lightColor.rgb` multiply (the Session 4.5 replacement for the
//      Session 2 IBL ambient path; matID == 2 no longer reads
//      iblIrradiance/iblPrefiltered/iblBRDFLUT after the
//      `rm_finishLightingPass` bypass).
//
// Session 3 + Session 4.5 dispatch gate:
//
//   6. testFerrofluidOceanSkyReflectionDispatchActive — steady-mid fixture
//      rendered with an active `FerrofluidStageRig` (4 lights, non-zero
//      intensity) vs the zero-filled placeholder (activeLightCount = 0).
//      Under Session 4.5, an active rig adds aurora bands to the sky
//      reflection; placeholder leaves only the dim purple base. Diff
//      threshold ≥ 1.0 in avg channel.
//
// All six tests share the deferred-ray-march render path (`RayMarchPipeline`
// driven directly), the same path used by PresetVisualReviewTests for pure
// ray-march presets.

import Metal
import XCTest
@testable import Presets
@testable import Renderer
@testable import Shared

final class FerrofluidOceanVisualTests: XCTestCase {

    private var device: MTLDevice!
    private var loader: PresetLoader!

    // V.9 Session 4.5: bumped from the 384×216 thumbnail resolution to
    // full 1920×1080 (production-target 1080p). Lower resolutions hid
    // pixel-scale artifacts and led to incorrect "production won't show this"
    // assessments; tests now render at the resolution Phosphene actually
    // ships at. Per-pixel threshold-based assertions (avg channel diff, lit
    // count) are resolution-independent so all gate values port as-is.
    private static let renderWidth  = 1920
    private static let renderHeight = 1080

    override func setUpWithError() throws {
        device = MTLCreateSystemDefaultDevice()
        try XCTSkipIf(device == nil, "No Metal device")
        loader = PresetLoader(device: device, pixelFormat: .bgra8Unorm_srgb)
    }

    // MARK: - Gate 1: shader compiles

    func testFerrofluidOceanShaderCompiles() throws {
        let preset = try XCTUnwrap(
            loader.presets.first { $0.descriptor.name == "Ferrofluid Ocean" },
            "Ferrofluid Ocean preset not found — Metal compile likely silently dropped (Failed Approach #44)"
        )
        XCTAssertTrue(preset.descriptor.useRayMarch,
                      "V.9 Session 1 redirect expects passes to contain 'ray_march'")
        XCTAssertTrue(preset.descriptor.usePostProcess,
                      "V.9 Session 1 redirect expects passes to contain 'post_process'")
        XCTAssertNotNil(preset.pipelineState,
                        "Preset pipelineState must be non-nil after compilation")
        XCTAssertNotNil(preset.rayMarchPipelineState,
                        "Ray-march G-buffer state must be non-nil for a ray_march preset")
    }

    // MARK: - Gate 2: 4-fixture render

    func testFerrofluidOceanRendersFourFixtures() throws {
        let outDir = try makeOutputDirectory(suffix: "fixtures")
        let preset = try requirePreset()

        let fixtures: [(name: String, features: FeatureVector, stems: StemFeatures)] = [
            ("01_silence",     fixtureSilence(),     stemsZero()),
            ("02_steady_mid",  fixtureSteadyMid(),   stemsMid()),
            ("03_beat_heavy",  fixtureBeatHeavy(),   stemsBeatHeavy()),
            ("04_quiet",       fixtureQuiet(),       stemsQuiet())
        ]

        for fixture in fixtures {
            var features = fixture.features
            let stems    = fixture.stems
            // Session 4.5: every fixture exercises the matID == 2 sky-
            // reflection dispatch with a real rig bound. The Session 3 silence-
            // only rig allocation left steady-mid / beat-heavy / quiet
            // rendering with `activeLightCount = 0` — no aurora bands
            // contributed, so the rendered output was indistinguishable from
            // a placeholder render and the Phase A acceptance gate
            // ("Steady-mid fixture: bands brighter") could not fire. Ticking
            // a rig per fixture lets the per-fixture stems drive the rig's
            // palette / intensity / orbit-speed state and produces a
            // contact sheet that reflects the §5.8 musical contract end-to-end.
            let fixtureRig: FerrofluidStageRig?
            if let descriptor = preset.descriptor.stageRig {
                fixtureRig = FerrofluidStageRig(device: device, descriptor: descriptor)
                if let rig = fixtureRig {
                    // 30 ticks at 60 fps so the smoothedDrumsDev envelope has
                    // converged toward the fixture's stem values per the §5.8
                    // 150 ms smoothing constant (~3 τ at 0.5 s of ticks).
                    for _ in 0..<30 {
                        rig.tick(features: features, stems: stems, dt: 1.0 / 60.0)
                    }
                }
            } else {
                fixtureRig = nil
            }
            let pixels   = try renderDeferredRayMarch(preset: preset,
                                                     features: &features,
                                                     stems: stems,
                                                     stageRig: fixtureRig)
            try writePNG(bgraPixels: pixels,
                         width: Self.renderWidth, height: Self.renderHeight,
                         to: outDir.appendingPathComponent("\(fixture.name).png"))

            // Non-trivial output: at least some pixels with luminance above the
            // near-black floor. Threshold low enough that the calm silence state
            // (which is intentionally dark) still satisfies; high enough that an
            // all-black render fails.
            let lit = pixels.enumerated().reduce(0) { acc, idx in
                idx.offset % 4 == 3 ? acc : (acc + (idx.element > 5 ? 1 : 0))
            }
            XCTAssertGreaterThan(
                lit, 100,
                "Fixture '\(fixture.name)' produced effectively all-black output")

            // Not clipped to full white: at least one pixel below 250 in some
            // channel. (A constant-white frame would also fail visual review.)
            var anyUnderClipped = false
            for i in stride(from: 0, to: pixels.count, by: 4) where pixels[i] < 250 || pixels[i + 1] < 250 || pixels[i + 2] < 250 {
                anyUnderClipped = true
                break
            }
            XCTAssertTrue(anyUnderClipped,
                          "Fixture '\(fixture.name)' rendered fully clipped — unexpected")

            // Session 4.5: silence-state sky-reflection presence. Even with
            // drumsEnergyDev = 0 the rig's per-light intensity collapses to
            // floor_coef × baseline (≈ 2.0 at §5.8 defaults), so the dim
            // aurora bands ride on top of the base purple gradient — the
            // substrate is dark but never pure black. The `lit > 100` gate
            // above accepts up to 99.97 % black pixels; this stricter
            // average-channel gate catches a regression where the matID == 2
            // sky function returns vec3(0) at silence (e.g. a stale buffer
            // binding, an `activeLightCount = 0` shortcut, or a future
            // refactor that drops the rig.lights iteration). Threshold 4
            // ≈ 1.6 % linear average — below the Session 4.5 silence
            // baseline (~6–10) and far above the all-black floor. Lower
            // than the Session 3 threshold of 8 because the new sky path
            // intentionally renders darker at silence (base purple, not
            // gray-blue IBL) — the visual change is the whole point.
            if fixture.name == "01_silence" {
                var channelSum: UInt64 = 0
                for i in 0 ..< pixels.count where i % 4 != 3 {
                    channelSum &+= UInt64(pixels[i])
                }
                let channelCount = UInt64(pixels.count / 4 * 3)
                let avgChannel = Double(channelSum) / Double(channelCount)
                XCTAssertGreaterThan(
                    avgChannel, 4.0,
                    "Silence fixture avg channel \(avgChannel) ≤ 4 — matID == 2 sky reflection likely collapsed (V.9 Session 4.5)")
            }
        }

        print("[FerrofluidOcean V.9 Session 4.5] fixtures written to: \(outDir.path)")
    }

    // MARK: - Gate 3: independence states reachable (D-124(d))

    func testFerrofluidOceanIndependenceStatesReachable() throws {
        let outDir = try makeOutputDirectory(suffix: "independence")
        let preset = try requirePreset()

        // Calm body + tall spikes: low arousal, no drum accent, strong bass dev.
        var calmWithSpikes = fixtureSilence()
        calmWithSpikes.arousal = -0.5
        var stemsCalmSpikes = StemFeatures()
        stemsCalmSpikes.bassEnergy = 0.6     // makes warmup blend cross over
        stemsCalmSpikes.bassEnergyDev = 0.4

        // Agitated body + flat surface: high arousal, drum accent, no bass dev.
        var agitatedNoSpikes = fixtureSilence()
        agitatedNoSpikes.arousal = 0.5
        var stemsAgitated = StemFeatures()
        stemsAgitated.drumsEnergy = 0.6
        stemsAgitated.drumsEnergyDev = 0.3

        var calmFV     = calmWithSpikes
        var agitatedFV = agitatedNoSpikes
        let pixelsCalm     = try renderDeferredRayMarch(preset: preset, features: &calmFV, stems: stemsCalmSpikes)
        let pixelsAgitated = try renderDeferredRayMarch(preset: preset, features: &agitatedFV, stems: stemsAgitated)

        try writePNG(bgraPixels: pixelsCalm,
                     width: Self.renderWidth, height: Self.renderHeight,
                     to: outDir.appendingPathComponent("a_calm_body_with_spikes.png"))
        try writePNG(bgraPixels: pixelsAgitated,
                     width: Self.renderWidth, height: Self.renderHeight,
                     to: outDir.appendingPathComponent("b_agitated_body_no_spikes.png"))

        // The two frames should be measurably distinct — they share no audio
        // routing primitive. Sum absolute pixel difference and require it to
        // exceed a modest threshold (1 / 255 average per channel pixel).
        precondition(pixelsCalm.count == pixelsAgitated.count)
        var diff: UInt64 = 0
        for i in 0 ..< pixelsCalm.count where i % 4 != 3 {
            diff &+= UInt64(abs(Int(pixelsCalm[i]) - Int(pixelsAgitated[i])))
        }
        let pixelChannels = UInt64(pixelsCalm.count / 4 * 3)
        // Average channel difference (out of 255). Even at low absolute values,
        // 0.5 average is well above noise (typical pure-noise diff is < 0.05).
        let avg = Double(diff) / Double(pixelChannels)
        XCTAssertGreaterThan(
            avg, 0.5,
            "Independence states produced near-identical frames (avg channel diff = \(avg))")

        print("[FerrofluidOcean V.9 Session 1] independence frames written to: \(outDir.path) (avg diff = \(avg))")
    }

    // MARK: - Gate 4 (V.9 Session 4.5): mood-tint atmosphere shift (D-022)

    /// Verifies that the D-022 cool/warm valence tint propagates through the
    /// matID == 2 procedural sky path (Session 4.5 / D-126). The sky function's
    /// `baseSky * scene.lightColor.rgb` multiply carries the entire reflected
    /// sky toward the mood-derived tint; aurora bands are additive on top and
    /// keep their palette-driven colors unchanged. With fog ENABLED the far-sky
    /// fog tail (also fed by `rm_ferrofluidBaseSky`) carries the tint at depth
    /// as well, giving the strongest signal.
    func testFerrofluidOceanMoodTintAtmosphereShifts() throws {
        let outDir = try makeOutputDirectory(suffix: "mood_tint")
        let preset = try requirePreset()

        // The production render loop calls RenderPipeline.applyAudioModulation
        // each frame, which derives `scene.lightColor` from valence (warm/cool
        // tint multiplier on base.lightColor). The test harness drives
        // RayMarchPipeline directly and bypasses that path — so we replicate
        // the tint formula manually in `renderDeferredRayMarch` when
        // `applyValenceTint: true`. Keeping the formula colocated with the
        // production formula in RenderPipeline+RayMarch.swift:185–193.
        var coolFeatures = fixtureSilence()
        coolFeatures.valence = -0.9
        var warmFeatures = fixtureSilence()
        warmFeatures.valence = 0.9
        let stems = stemsZero()

        let pixelsCool = try renderDeferredRayMarch(preset: preset,
                                                   features: &coolFeatures,
                                                   stems: stems,
                                                   applyValenceTint: true)
        let pixelsWarm = try renderDeferredRayMarch(preset: preset,
                                                   features: &warmFeatures,
                                                   stems: stems,
                                                   applyValenceTint: true)

        try writePNG(bgraPixels: pixelsCool,
                     width: Self.renderWidth, height: Self.renderHeight,
                     to: outDir.appendingPathComponent("a_valence_negative_cool.png"))
        try writePNG(bgraPixels: pixelsWarm,
                     width: Self.renderWidth, height: Self.renderHeight,
                     to: outDir.appendingPathComponent("b_valence_positive_warm.png"))

        precondition(pixelsCool.count == pixelsWarm.count)
        var diff: UInt64 = 0
        for i in 0 ..< pixelsCool.count where i % 4 != 3 {
            diff &+= UInt64(abs(Int(pixelsCool[i]) - Int(pixelsWarm[i])))
        }
        let pixelChannels = UInt64(pixelsCool.count / 4 * 3)
        let avg = Double(diff) / Double(pixelChannels)

        // Cool→warm tint at valence ±0.9 multiplies the base sky's
        // (0.05, 0.025, 0.07) horizon stripe by lightColor (~0.70, 0.86, 1.36)
        // vs (1.22, 1.08, 0.73), giving the substrate a clear cool-purple vs
        // warm-amber shift. The 1.0 threshold leaves headroom against the
        // expected diff (~5–15 under the new dim-sky baseline; the absolute
        // diff is lower than the Session 2 matID == 3 path because the base
        // sky's value range is intentionally smaller, but the *relative*
        // shift is the same). If a future refactor drops the
        // `baseSky * scene.lightColor.rgb` multiply this gate trips.
        XCTAssertGreaterThan(
            avg, 1.0,
            "Mood-tint atmosphere shift collapsed (avg channel diff = \(avg)) — D-022 tint not propagating through matID == 2 procedural sky")

        print("[FerrofluidOcean V.9 Session 4.5] mood-tint frames written to: \(outDir.path) (avg diff = \(avg))")
    }

    // MARK: - Gate 5 (V.9 Session 4.5): sky-base mood-tint propagation (fog disabled)

    /// Verifies that the sky function's `baseSky * scene.lightColor.rgb`
    /// multiply (inside `rm_ferrofluidBaseSky`) is the sole mood-tint vector
    /// when fog is disabled. Session 2 ran this as `testFerrofluidOcean
    /// MoodTintIBLPropagation` against the `rm_finishLightingPass` IBL path;
    /// Session 4.5 bypasses that helper for matID == 2 and the IBL ambient
    /// path is no longer reachable. The replacement gates the sky base's
    /// lightColor multiply directly.
    ///
    /// Disables fog explicitly (`sceneParamsB.y = 1e6` matches the "fog
    /// disabled" sentinel in PresetDescriptor+SceneUniforms) so any visible
    /// cool-vs-warm shift here MUST come from the sky-base multiply.
    func testFerrofluidOceanMoodTintSkyBaseShift() throws {
        let outDir = try makeOutputDirectory(suffix: "mood_tint_sky_base")
        let preset = try requirePreset()

        var coolFeatures = fixtureSilence()
        coolFeatures.valence = -0.9
        var warmFeatures = fixtureSilence()
        warmFeatures.valence = 0.9
        let stems = stemsZero()

        // bindIBL is kept on so the placeholder IBL textures don't fall back
        // to unbound-texture zero — but matID == 2 doesn't read them under
        // Session 4.5, so this should be a no-op for the actual rendered
        // pixels. Keeping it true preserves Session 2 test isolation against
        // a future regression that re-routes matID == 2 through
        // `rm_finishLightingPass`.
        let pixelsCool = try renderDeferredRayMarch(
            preset: preset, features: &coolFeatures, stems: stems,
            applyValenceTint: true, bindIBL: true, disableFog: true)
        let pixelsWarm = try renderDeferredRayMarch(
            preset: preset, features: &warmFeatures, stems: stems,
            applyValenceTint: true, bindIBL: true, disableFog: true)

        try writePNG(bgraPixels: pixelsCool,
                     width: Self.renderWidth, height: Self.renderHeight,
                     to: outDir.appendingPathComponent("a_valence_negative_cool_no_fog.png"))
        try writePNG(bgraPixels: pixelsWarm,
                     width: Self.renderWidth, height: Self.renderHeight,
                     to: outDir.appendingPathComponent("b_valence_positive_warm_no_fog.png"))

        precondition(pixelsCool.count == pixelsWarm.count)
        var diff: UInt64 = 0
        for i in 0 ..< pixelsCool.count where i % 4 != 3 {
            diff &+= UInt64(abs(Int(pixelsCool[i]) - Int(pixelsWarm[i])))
        }
        let pixelChannels = UInt64(pixelsCool.count / 4 * 3)
        let avg = Double(diff) / Double(pixelChannels)

        // With fog disabled, all tint propagation flows through the
        // `baseSky * scene.lightColor.rgb` multiply in `rm_ferrofluidBaseSky`.
        // The aurora bands are zero (placeholder rig path), so the substrate
        // reflects only the dim purple gradient × thin-film F0 — the cool
        // vs warm shift comes entirely from the base sky's lightColor
        // multiply. 1.0 threshold leaves headroom against the expected
        // diff (~2–8 under the new dim baseline).
        XCTAssertGreaterThan(
            avg, 1.0,
            "Sky-base mood-tint shift collapsed (avg channel diff = \(avg)) — `baseSky * scene.lightColor.rgb` in rm_ferrofluidBaseSky is the most likely regression site")

        print("[FerrofluidOcean V.9 Session 4.5 sky base] mood-tint frames written to: \(outDir.path) (avg diff = \(avg))")
    }

    // MARK: - Gate 6 (V.9 Session 4.5): sky-reflection dispatch active (D-126)

    /// Verifies that the matID == 2 dispatch branch in
    /// `raymarch_lighting_fragment` actually reads the slot-9 stage-rig
    /// buffer and consumes it through `rm_ferrofluidSky`. Two renders of the
    /// steady-mid fixture:
    ///   - "active rig"      — a FerrofluidStageRig with activeLightCount = 4
    ///                         and non-zero intensities. Buffer bound at slot 9.
    ///                         Aurora bands ride on top of the base purple sky.
    ///   - "placeholder only" — nil rig, so the zero-filled
    ///                         RayMarchPipeline.stageRigPlaceholderBuffer is
    ///                         bound (activeLightCount = 0 ⇒ rm_ferrofluidSky's
    ///                         aurora loop never executes). Surface reflects
    ///                         only the dim base purple sky.
    ///
    /// The two frames must be measurably distinct (avg channel diff > 1.0).
    /// If this collapses, either (a) the slot-9 buffer is not reaching the
    /// shader, (b) the rm_ferrofluidSky aurora loop is unreachable, or (c)
    /// the ferrofluid surface stopped emitting matID == 2 from sceneMaterial.
    /// Renamed from `testFerrofluidOceanStageRigDispatchActive` at Session 4.5
    /// because the dispatch path no longer accumulates Cook-Torrance per-beam
    /// contributions — it samples a procedural sky at the reflection vector.
    func testFerrofluidOceanSkyReflectionDispatchActive() throws {
        let outDir = try makeOutputDirectory(suffix: "sky_reflection_dispatch")
        let preset = try requirePreset()

        // The dispatch gate uses a *test-harness-tuned* StageRig descriptor —
        // boosted intensity_baseline — so the aurora-band contributions
        // produce a clearly measurable diff against the placeholder render.
        // The production Ferrofluid Ocean values (intensity_baseline 5) are
        // tuned for the V.9 reference frames at Session 5 cert review; that
        // tuning lives in JSON and is not the dispatch gate's concern. This
        // gate verifies the slot-9 buffer reaches the shader — the
        // production tuning is validated by Session 5 manual M7 review
        // against `04_*` / `08_*`.
        //
        // Orbit altitude / radius stay at production values (6 / 4) so the
        // bandDir = normalize(lightPos) computation in rm_ferrofluidSky
        // produces the same upper-hemisphere band placement under test as
        // under production. The Session 3 dispatch test used close-in 2/2
        // orbit to amplify Cook-Torrance attenuation; under Session 4.5
        // the relevant signal is bandDir direction, not surface distance,
        // so production values give a more representative test.
        let stageRigDesc = StageRig(
            lightCount: 4,
            orbitAltitude: 6.0,
            orbitRadius: 4.0,
            orbitSpeedBaseline: 0.05,
            orbitSpeedArousalCoef: 0.15,
            palettePhaseOffsets: [0.0, 0.33, 0.67, 0.17],
            intensityBaseline: 200.0,
            intensityFloorCoef: 0.4,
            intensitySwingCoef: 0.6,
            intensitySmoothingTauMs: 150
        )
        let rig = try XCTUnwrap(FerrofluidStageRig(device: device, descriptor: stageRigDesc),
                                "FerrofluidStageRig allocation failed")
        var rigFeatures = fixtureSteadyMid()
        var rigStems = stemsMid()
        rigStems.drumsEnergyDev = 0.6
        rigStems.vocalsPitchHz = 220
        rigStems.vocalsPitchConfidence = 0.8
        rigFeatures.arousal = 0.3
        // 30 frames at 60 fps so the 150 ms drums smoother + audio_time-driven
        // palette have time to evolve past silence.
        for _ in 0 ..< 30 {
            rig.tick(features: rigFeatures, stems: rigStems, dt: 1.0 / 60.0)
        }

        var fActive = fixtureSteadyMid()
        var fInactive = fixtureSteadyMid()
        let stemsActive = rigStems
        let stemsInactive = stemsMid()
        let pixelsActive = try renderDeferredRayMarch(
            preset: preset, features: &fActive, stems: stemsActive,
            stageRig: rig)
        let pixelsInactive = try renderDeferredRayMarch(
            preset: preset, features: &fInactive, stems: stemsInactive,
            stageRig: nil)

        try writePNG(bgraPixels: pixelsActive,
                     width: Self.renderWidth, height: Self.renderHeight,
                     to: outDir.appendingPathComponent("a_sky_reflection_active.png"))
        try writePNG(bgraPixels: pixelsInactive,
                     width: Self.renderWidth, height: Self.renderHeight,
                     to: outDir.appendingPathComponent("b_placeholder_only.png"))

        precondition(pixelsActive.count == pixelsInactive.count)
        var diff: UInt64 = 0
        for i in 0 ..< pixelsActive.count where i % 4 != 3 {
            diff &+= UInt64(abs(Int(pixelsActive[i]) - Int(pixelsInactive[i])))
        }
        let pixelChannels = UInt64(pixelsActive.count / 4 * 3)
        let avg = Double(diff) / Double(pixelChannels)

        // 1.0 threshold per the Session 4.5 prompt's Phase A acceptance
        // gate. With the boosted intensity_baseline (200) and 4 active
        // bands at non-zero intensities, the aurora contribution to the
        // sky should be visibly bright at the band centers — placeholder
        // gives only the dim base purple. ACES tone-mapping in the
        // composite pass bounds the visible per-pixel delta, but the diff
        // accumulates across the full frame.
        XCTAssertGreaterThan(
            avg, 1.0,
            "Sky-reflection dispatch inactive (avg channel diff = \(avg)) — slot-9 buffer not reaching matID == 2 sky branch")

        print("[FerrofluidOcean V.9 Session 4.5] sky-reflection dispatch frames written to: \(outDir.path) (avg diff = \(avg))")
    }

    // MARK: - Render

    private func renderDeferredRayMarch(
        preset: PresetLoader.LoadedPreset,
        features: inout FeatureVector,
        stems: StemFeatures,
        applyValenceTint: Bool = false,
        bindIBL: Bool = false,
        disableFog: Bool = false,
        stageRig: FerrofluidStageRig? = nil
    ) throws -> [UInt8] {
        let context       = try MetalContext()
        let shaderLibrary = try ShaderLibrary(context: context)
        let pipeline      = try RayMarchPipeline(context: context,
                                                 shaderLibrary: shaderLibrary)
        pipeline.allocateTextures(width: Self.renderWidth, height: Self.renderHeight)

        // V.9 Session 4.5b Phase 1: allocate FerrofluidParticles + bake the
        // 1024×1024 height field once. The Ferrofluid Ocean sceneSDF samples
        // this texture in place of the Phase A inline `voronoi_smooth` path;
        // without a bound height texture, the bound placeholder (zero-filled
        // 1×1) means the substrate renders without spikes. Every gate in
        // this suite tests Ferrofluid Ocean, so always bake.
        let particles = try XCTUnwrap(
            FerrofluidParticles(device: device, library: shaderLibrary.library),
            "FerrofluidParticles allocation failed — slot-10 height texture cannot be bound")
        particles.bakeHeightField(commandQueue: context.commandQueue)

        var sceneUniforms = preset.descriptor.makeSceneUniforms()
        sceneUniforms.sceneParamsA.y = Float(Self.renderWidth) / Float(Self.renderHeight)

        if disableFog {
            // Match the descriptor's "no fog" sentinel (>= 1e5 → fog effectively
            // disabled by the lighting fragment). Used by the IBL-propagation
            // gate to isolate the IBL ambient mood-tint path.
            sceneUniforms.sceneParamsB.y = 1_000_000
        }

        if applyValenceTint {
            // Mirrors RenderPipeline.applyAudioModulation (RenderPipeline+RayMarch.swift:185–193).
            // Test harness bypasses the production frame loop, so we apply the
            // same tint formula directly to sceneUniforms.lightColor.
            let valence = max(-1, min(1, features.valence))
            let warm = max(Float(0), valence)
            let cool = max(Float(0), -valence)
            let tint = SIMD3<Float>(
                1.0 + warm * 0.40 - cool * 0.25,
                1.0 + warm * 0.15 - cool * 0.10,
                1.0 + cool * 0.40 - warm * 0.30
            )
            let baseColor = SIMD3<Float>(
                sceneUniforms.lightColor.x,
                sceneUniforms.lightColor.y,
                sceneUniforms.lightColor.z
            )
            let tinted = baseColor * tint
            sceneUniforms.lightColor = SIMD4(tinted.x, tinted.y, tinted.z, 0)

            // `scene_fog_near: 0.0` in FerrofluidOcean.json (P2-B follow-up to
            // V.9 Session 2) puts the fog band at the camera so the visible
            // surface (4–14 m) actually enters fog territory. Pre-P2-B,
            // `SceneUniforms()` hard-coded `fogNear = 20.0` and the visible
            // surface fell entirely before the fog band, so the harness had
            // to override sceneParamsB.x manually here. With the JSON schema
            // extension, the override is no longer needed.
        }

        pipeline.sceneUniforms = sceneUniforms

        let iblManager: IBLManager? = bindIBL
            ? try IBLManager(context: context, shaderLibrary: shaderLibrary)
            : nil

        let floatStride = MemoryLayout<Float>.stride
        let fftBuf = try XCTUnwrap(context.makeSharedBuffer(length: 512 * floatStride))
        let wavBuf = try XCTUnwrap(context.makeSharedBuffer(length: 2048 * floatStride))

        let outDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: context.pixelFormat,
            width: Self.renderWidth, height: Self.renderHeight, mipmapped: false)
        outDesc.usage = [.renderTarget, .shaderRead]
        outDesc.storageMode = .shared
        let outTex = try XCTUnwrap(context.device.makeTexture(descriptor: outDesc))

        let cmdBuf = try XCTUnwrap(context.commandQueue.makeCommandBuffer())
        let gbufferState = try XCTUnwrap(
            preset.rayMarchPipelineState,
            "Ferrofluid Ocean missing rayMarchPipelineState — Session 1 expects ray_march pass")

        pipeline.render(
            gbufferPipelineState: gbufferState,
            features: &features,
            fftBuffer: fftBuf,
            waveformBuffer: wavBuf,
            stemFeatures: stems,
            outputTexture: outTex,
            commandBuffer: cmdBuf,
            noiseTextures: nil,
            iblManager: iblManager,
            postProcessChain: nil,
            presetFragmentBuffer3: nil,
            presetFragmentBuffer4: stageRig?.buffer,
            presetHeightTexture: particles.heightTexture
        )
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()
        XCTAssertEqual(cmdBuf.status, .completed,
                       "Render command buffer failed: \(String(describing: cmdBuf.error))")

        var pixels = [UInt8](repeating: 0,
                             count: Self.renderWidth * Self.renderHeight * 4)
        outTex.getBytes(&pixels,
                        bytesPerRow: Self.renderWidth * 4,
                        from: MTLRegionMake2D(0, 0, Self.renderWidth, Self.renderHeight),
                        mipmapLevel: 0)
        return pixels
    }

    // MARK: - Helpers

    private func requirePreset() throws -> PresetLoader.LoadedPreset {
        try XCTUnwrap(
            loader.presets.first { $0.descriptor.name == "Ferrofluid Ocean" },
            "Ferrofluid Ocean preset not found")
    }

    private func makeOutputDirectory(suffix: String) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("PhospheneFerrofluidOceanV9Session1")
            .appendingPathComponent(suffix)
        try FileManager.default.createDirectory(at: url,
                                                withIntermediateDirectories: true)
        return url
    }

    private func writePNG(bgraPixels: [UInt8],
                          width: Int, height: Int,
                          to url: URL) throws {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width, height: height, mipmapped: false)
        desc.usage = [.shaderRead]
        desc.storageMode = .shared
        let tex = try XCTUnwrap(device.makeTexture(descriptor: desc))
        bgraPixels.withUnsafeBytes { bytes in
            tex.replace(region: MTLRegionMake2D(0, 0, width, height),
                        mipmapLevel: 0,
                        withBytes: bytes.baseAddress!,
                        bytesPerRow: width * 4)
        }
        _ = writeTextureToPNG(tex, url: url)
    }

    // MARK: - Fixtures

    private func fixtureSilence() -> FeatureVector {
        FeatureVector(
            time: 1.0, deltaTime: 1.0 / 60.0,
            aspectRatio: Float(Self.renderWidth) / Float(Self.renderHeight),
            accumulatedAudioTime: 1.0
        )
    }

    private func fixtureSteadyMid() -> FeatureVector {
        var fv = FeatureVector(
            bass: 0.5, mid: 0.5, treble: 0.4,
            bassAtt: 0.5, midAtt: 0.5, trebleAtt: 0.4,
            arousal: 0.0,
            time: 5.0, deltaTime: 1.0 / 60.0,
            aspectRatio: Float(Self.renderWidth) / Float(Self.renderHeight),
            accumulatedAudioTime: 5.0
        )
        fv.bassAttRel = 0.0
        return fv
    }

    private func fixtureBeatHeavy() -> FeatureVector {
        var fv = FeatureVector(
            bass: 0.75, mid: 0.55, treble: 0.45,
            bassAtt: 0.7, midAtt: 0.55, trebleAtt: 0.45,
            beatBass: 0.85, beatComposite: 0.6,
            arousal: 0.6,
            time: 10.0, deltaTime: 1.0 / 60.0,
            aspectRatio: Float(Self.renderWidth) / Float(Self.renderHeight),
            accumulatedAudioTime: 10.0
        )
        fv.bassAttRel = 0.4
        return fv
    }

    private func fixtureQuiet() -> FeatureVector {
        var fv = FeatureVector(
            bass: 0.3, mid: 0.25, treble: 0.2,
            bassAtt: 0.3, midAtt: 0.25, trebleAtt: 0.2,
            arousal: -0.3,
            time: 15.0, deltaTime: 1.0 / 60.0,
            aspectRatio: Float(Self.renderWidth) / Float(Self.renderHeight),
            accumulatedAudioTime: 15.0
        )
        fv.bassAttRel = -0.2
        return fv
    }

    private func stemsZero() -> StemFeatures { .zero }

    private func stemsMid() -> StemFeatures {
        var s = StemFeatures(vocalsEnergy: 0.4,
                             drumsEnergy: 0.4,
                             bassEnergy: 0.4,
                             otherEnergy: 0.3)
        s.bassEnergyDev = 0.1
        s.drumsEnergyDev = 0.1
        return s
    }

    private func stemsBeatHeavy() -> StemFeatures {
        var s = StemFeatures(vocalsEnergy: 0.5,
                             drumsEnergy: 0.7, drumsBeat: 0.9,
                             bassEnergy: 0.7,
                             otherEnergy: 0.4)
        s.bassEnergyDev = 0.4
        s.drumsEnergyDev = 0.35
        return s
    }

    private func stemsQuiet() -> StemFeatures {
        StemFeatures(vocalsEnergy: 0.15,
                     drumsEnergy: 0.15,
                     bassEnergy: 0.15,
                     otherEnergy: 0.1)
    }
}
