// PresetVisualReviewTests — On-demand visual review harness for Phosphene presets.
//
// Renders a named preset at 1920×1280 for three audio fixtures (silence, steady
// mid-energy, beat-heavy), encodes each frame to PNG, and (for Arachne only)
// composes a contact sheet alongside the four must-pass references.
//
// Gated behind RENDER_VISUAL=1 so it stays out of normal CI / `swift test` runs.
//
// Invocation:
//   RENDER_VISUAL=1 swift test --package-path PhospheneEngine \
//       --filter PresetVisualReview
//
// Output: /tmp/phosphene_visual/<ISO8601>/<preset>_{silence,mid,beat}.png
//         /tmp/phosphene_visual/<ISO8601>/<preset>_contact_sheet.png  (Arachne only)
//         /tmp/phosphene_visual/<ISO8601>/Lumen_palette_<name>.png  (LM.4.7 — one per palette)
//         /tmp/phosphene_visual/<ISO8601>/Lumen_palette_library_contact_sheet.png  (6×3 grid of 18 palettes)
//
// See V.7.6.1 in docs/ENGINEERING_PLAN.md and D-072 in docs/DECISIONS.md.

import Testing
import Metal
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import AppKit
import simd
@testable import Renderer
@testable import Presets
@testable import Shared

// MARK: - Suite

@Suite("PresetVisualReview")
struct PresetVisualReviewTests {

    // MARK: - Fixtures

    private var silenceFixture: FeatureVector {
        FeatureVector(time: 1.0, deltaTime: 1.0 / 60.0)
    }

    private var midFixture: FeatureVector {
        FeatureVector(bass: 0.50, mid: 0.50, treble: 0.50, time: 3.0, deltaTime: 1.0 / 60.0)
    }

    private var beatFixture: FeatureVector {
        var fv = FeatureVector(bass: 0.80, mid: 0.50, treble: 0.50,
                               beatBass: 1.0, time: 5.0, deltaTime: 1.0 / 60.0)
        fv.bassRel = 0.60
        fv.bassDev = 0.60
        return fv
    }

    /// HV-HA mood fixture (contract §"Certification fixtures"). Steady moderate
    /// energy on top of high valence + high arousal so LumenPatternEngine
    /// produces a warm-shifted palette and faster drift speed. Used in the LM.2
    /// contact sheet to verify the mood-coupled hue shift (Decision E.1).
    private var hvHaFixture: FeatureVector {
        var fv = FeatureVector(
            bass: 0.55, mid: 0.55, treble: 0.55,
            valence: 0.6, arousal: 0.6,
            time: 7.0, deltaTime: 1.0 / 60.0
        )
        fv.bassRel = 0.10
        fv.midRel  = 0.10
        fv.trebRel = 0.10
        fv.bassAttRel = 0.05
        fv.midAttRel  = 0.05
        return fv
    }

    /// LV-LA mood fixture (contract §"Certification fixtures"). Steady moderate
    /// energy on top of low valence + low arousal so LumenPatternEngine
    /// produces a cool-shifted palette and slower drift speed. Pair with
    /// `hvHaFixture` in the LM.2 contact sheet to confirm visible mood shift.
    private var lvLaFixture: FeatureVector {
        var fv = FeatureVector(
            bass: 0.45, mid: 0.45, treble: 0.45,
            valence: -0.5, arousal: -0.4,
            time: 9.0, deltaTime: 1.0 / 60.0
        )
        fv.bassRel = -0.10
        fv.midRel  = -0.10
        fv.trebRel = -0.10
        return fv
    }

    // MARK: - Constants

    private static let renderWidth = 1920
    private static let renderHeight = 1280
    private static let outputRoot = "/tmp/phosphene_visual"

    private static let arachneReferenceRelPaths: [(label: String, path: String)] = [
        ("Ref 01", "docs/VISUAL_REFERENCES/arachne/01_macro_dewy_web_on_dark.jpg"),
        ("Ref 04", "docs/VISUAL_REFERENCES/arachne/04_specular_silk_fiber_highlight.jpg"),
        ("Ref 05", "docs/VISUAL_REFERENCES/arachne/05_lighting_backlit_atmosphere.jpg"),
        ("Ref 08", "docs/VISUAL_REFERENCES/arachne/08_palette_bioluminescent_organism.jpg"),
    ]

    // Nimbus review cells: the three TRUST refs (form / meso / micro) the body
    // is authored against + the two AVOID anti-refs the body must not match.
    private static let nimbusReferenceRelPaths: [(label: String, path: String)] = [
        ("01 form (TRUST)",    "docs/VISUAL_REFERENCES/nimbus/01_macro_coherent_body.jpg"),
        ("02 meso (TRUST)",    "docs/VISUAL_REFERENCES/nimbus/02_meso_billow_and_filament.jpg"),
        ("03 micro (TRUST)",   "docs/VISUAL_REFERENCES/nimbus/03_micro_wisp_feathering.jpg"),
        ("05 fog (AVOID)",     "docs/VISUAL_REFERENCES/nimbus/05_anti_uniform_fog.jpg"),
        ("05 solid (AVOID)",   "docs/VISUAL_REFERENCES/nimbus/05_anti_solid_surface.jpg"),
    ]

    // MARK: - Tests

    /// Pass-separated capture for staged-composition presets (V.ENGINE.1).
    /// Renders one PNG per stage per fixture so harness reviewers can inspect
    /// the WORLD pass alone, the COMPOSITE pass, and any intermediate stages.
    /// Setting `RENDER_STAGE=<name>` limits output to a single stage.
    @Test("Render staged preset per-stage PNGs (RENDER_VISUAL=1)",
          arguments: ["Staged Sandbox", "Arachne"])
    func renderStagedPresetPerStage(_ presetName: String) throws {
        guard ProcessInfo.processInfo.environment["RENDER_VISUAL"] == "1" else {
            print("[PresetVisualReview] RENDER_VISUAL not set, skipping staged \(presetName)")
            return
        }
        let stageFilter = ProcessInfo.processInfo.environment["RENDER_STAGE"]

        let ctx = try MetalContext()
        guard let preset = _acceptanceFixture.presets.first(where: {
            $0.descriptor.name == presetName
        }) else {
            print("[PresetVisualReview] preset '\(presetName)' not found, skipping")
            return
        }
        guard !preset.stages.isEmpty else {
            print("[PresetVisualReview] preset '\(presetName)' has no staged compilation, skipping")
            return
        }

        let outputDir = try makeOutputDirectory()
        print("[PresetVisualReview] staged output dir: \(outputDir.path)")

        // Warm an ArachneState so the staged WORLD + COMPOSITE fragments can
        // read mood / web / spider buffers at slots 6 / 7. Other staged
        // presets (e.g. "Staged Sandbox") need no per-preset state.
        let arachneState: ArachneState? = {
            guard presetName == "Arachne" else { return nil }
            guard let state = ArachneState(device: ctx.device, seed: 42) else { return nil }
            let warmFV = FeatureVector(bass: 0.5, mid: 0.5, treble: 0.5,
                                       time: 1.0, deltaTime: 1.0 / 60.0)
            for _ in 0..<30 { state.tick(features: warmFV, stems: .zero) }
            return state
        }()

        let fixtures: [(name: String, fv: FeatureVector)] = [
            ("silence", silenceFixture),
            ("mid", midFixture),
            ("beat", beatFixture),
        ]

        for fixture in fixtures {
            var fv = fixture.fv
            let stagePixels = try renderStagedFrame(preset: preset,
                                                    context: ctx,
                                                    features: &fv,
                                                    arachneState: arachneState)
            for (stageName, pixels) in stagePixels {
                if let stageFilter, stageFilter != stageName { continue }
                let safeName = presetName.replacingOccurrences(of: " ", with: "_")
                let url = outputDir.appendingPathComponent(
                    "\(safeName)_\(fixture.name)_\(stageName).png")
                try writePNG(bgraPixels: pixels,
                             width: Self.renderWidth, height: Self.renderHeight,
                             to: url)
                print("[PresetVisualReview] wrote \(url.lastPathComponent)")
            }
        }
    }

    // Pure-ray-march presets (passes contain `.rayMarch` and NOT `.mvWarp`)
    // dispatch through `renderDeferredRayMarchFrame`, which composes a
    // standalone `RayMarchPipeline` to run G-buffer → lighting → composite.
    // Mv_warp ray-march presets (Volumetric Lithograph) and direct presets
    // (Gossamer) continue down `renderFrame`. Without this
    // dispatch, pure-ray-march presets would bind a 3-attachment G-buffer
    // pipeline state to a 1-attachment encoder — a Metal format mismatch
    // that produces raw G-buffer output instead of the deferred lit result.
    @Test("Render preset to PNGs + contact sheet (RENDER_VISUAL=1)",
          arguments: ["Arachne", "Aurora Veil", "Gossamer", "Volumetric Lithograph", "Lumen Mosaic", "Nimbus",
                      // BUG-034: remaining ray-march presets, so before/after step-budget
                      // pairs cover the full affected set. Ferrofluid Ocean renders its
                      // legacy SDF path here (no mesh encoder / height texture in this
                      // harness); both halves of an A/B pair use the identical harness,
                      // so deltas isolate the uniform change.
                      "Ferrofluid Ocean", "Kinetic Sculpture"])
    func renderPresetVisualReview(_ presetName: String) throws {
        guard ProcessInfo.processInfo.environment["RENDER_VISUAL"] == "1" else {
            print("[PresetVisualReview] RENDER_VISUAL not set, skipping \(presetName)")
            return
        }

        let ctx = try MetalContext()
        // Full noise set for direct presets that sample any of it (Nimbus reads
        // noiseVolume [[texture(6)]] + blueNoise [[texture(8)]]). Production binds
        // slots 4–8 on the direct path (RenderPipeline+Draw.bindNoiseTextures →
        // TextureManager.bindTextures); bind the SAME set here so the review PNG
        // matches production exactly (FA #66 parity, NB.2 — never trip it again).
        let noiseTextureManager: TextureManager? = {
            guard let lib = try? ShaderLibrary(context: ctx),
                  let tm = try? TextureManager(context: ctx, shaderLibrary: lib) else { return nil }
            return tm
        }()
        guard let preset = _acceptanceFixture.presets.first(where: {
            $0.descriptor.name == presetName
        }) else {
            print("[PresetVisualReview] preset '\(presetName)' not found, skipping")
            return
        }
        guard !preset.descriptor.passes.contains(.meshShader) else {
            print("[PresetVisualReview] '\(presetName)' is mesh-shader, skipping")
            return
        }

        let outputDir = try makeOutputDirectory()
        print("[PresetVisualReview] output dir: \(outputDir.path)")

        // Per-preset state.
        let arachneState: ArachneState? = {
            guard presetName == "Arachne" else { return nil }
            guard let state = ArachneState(device: ctx.device, seed: 42) else { return nil }
            let warmFV = FeatureVector(bass: 0.5, mid: 0.5, treble: 0.5,
                                       time: 1.0, deltaTime: 1.0 / 60.0)
            for _ in 0..<30 { state.tick(features: warmFV, stems: .zero) }
            return state
        }()

        // AV.2: Aurora Veil reads a 16-byte AuroraVeilStateGPU at slot 6.
        // Allocate a state class and reset it; the per-fixture render loop
        // below ticks it once per fixture to produce the appropriate
        // kinkAccumulator + smoothedPitchNorm for each frame. Standard
        // fixtures (silence / mid / beat) have stems.zero so the audio
        // routes stay at their neutral / fallback values — the visual
        // review verifies the multi-column structure + substrate-drift
        // motion across time, not the audio coupling (which has dedicated
        // tests: AuroraVeilContinuousDominanceTest + AuroraVeilPitchHueTest).
        let auroraVeilState: AuroraVeilState? = {
            guard presetName == "Aurora Veil" else { return nil }
            return AuroraVeilState(device: ctx.device)
        }()

        // NB.4: Nimbus reads a 16-byte NimbusStateGPU at slot 6 (Energy bloom +
        // flow phase). Allocate the state; the per-fixture loop below primes it
        // to each fixture's energy level so the contact sheet shows the bloom
        // RANGE (silence floor → baseline → energetic).
        let nimbusState: NimbusState? = {
            guard presetName == "Nimbus" else { return nil }
            return NimbusState(device: ctx.device)
        }()

        // Lumen Mosaic: allocate the 4-light pattern engine once, re-prewarm
        // it per fixture so mood smoothing converges to that fixture's
        // valence/arousal before rendering. The engine flushes
        // LumenPatternState into its UMA buffer; we pass the buffer as
        // `presetFragmentBuffer3` to slot 8 in the deferred ray-march path.
        let lumenEngine: LumenPatternEngine? = {
            guard presetName == "Lumen Mosaic" else { return nil }
            return LumenPatternEngine(device: ctx.device, seed: 42)
        }()

        // 9-fixture set for Lumen Mosaic — 5 mood / energy frames plus
        // 4 per-track-seed variety frames at neutral mood (LM.3.2 calibration
        // follow-up 2026-05-09: Matt's M7-prep review observed that the 5-mood
        // contact sheet showed limited variety; the per-track seed is the
        // mechanism for between-track palette variation but the harness wasn't
        // exercising it).
        //
        // Track-seed variants pick four corners of the seed-tesseract:
        // {(+,+,+,+), (-,-,-,-), (+,-,+,-), (-,+,-,+)}. Each component
        // ∈ [-1, +1] perturbs one IQ palette parameter (a / b / c / d) by
        // its `kSeedMagnitude*` magnitude. Choosing extremal corners
        // maximises visible inter-track variety without leaving the
        // saturated regime.
        //
        // All other presets keep the existing 3-fixture set.
        let fixtures: [(name: String, fv: FeatureVector, trackSeed: SIMD4<Float>?)] = {
            if presetName == "Lumen Mosaic" {
                // LM.3.2 round 8 (2026-05-10): beat envelope removed. Cells
                // hold their previous state until the next beat advances the
                // palette step (no dark "pulse off" gap between beats). The
                // round-6 pulse_off / pulse_anticipate demo fixtures are
                // retired since `f.beat_phase01` no longer modulates albedo.
                return [
                    ("silence",          silenceFixture, nil),
                    ("mid",              midFixture,     nil),
                    ("beat",             beatFixture,    nil),
                    ("hv_ha_mood",       hvHaFixture,    nil),
                    ("lv_la_mood",       lvLaFixture,    nil),
                    ("track_v1",         midFixture,     SIMD4<Float>( 1,  1,  1,  1)),
                    ("track_v2",         midFixture,     SIMD4<Float>(-1, -1, -1, -1)),
                    ("track_v3",         midFixture,     SIMD4<Float>( 1, -1,  1, -1)),
                    ("track_v4",         midFixture,     SIMD4<Float>(-1,  1, -1,  1)),
                ]
            }
            if presetName == "Nimbus" {
                // NB.4: explicit broadband-energy deviation (D-026 AttRel) per
                // fixture so the contact sheet exercises the Energy bloom RANGE.
                // The shared silence/mid/beat fixtures leave AttRel at 0, which
                // would render every cell at the same baseline bloom (~0.5) and
                // could not show the silence floor or full bloom.
                // NB.6: a cool valence so the contact sheet shows the cool baseline
                // body (matching the 06_cool references / the approved NB.3 look) —
                // mood now drives colour, and neutral valence reads mid-palette.
                var nbSilence = FeatureVector(time: 1.0, deltaTime: 1.0 / 60.0)
                nbSilence.bassAttRel = -1.0   // bands at 0 → bloom 0: small/dim/slow floor
                nbSilence.midAttRel  = -1.0
                nbSilence.trebAttRel = -1.0
                nbSilence.valence = -0.7
                var nbMid = FeatureVector(bass: 0.5, mid: 0.5, treble: 0.5,
                                          time: 3.0, deltaTime: 1.0 / 60.0)  // AttRel 0 → ~0.5 baseline
                nbMid.valence = -0.7
                var nbEnergy = FeatureVector(bass: 0.9, mid: 0.9, treble: 0.9,
                                             time: 5.0, deltaTime: 1.0 / 60.0)
                nbEnergy.bassAttRel = 0.9     // above-average swell → bloom ~1: big/bright/fast
                nbEnergy.midAttRel  = 0.9
                nbEnergy.trebAttRel = 0.9
                nbEnergy.valence = -0.7
                return [
                    ("silence", nbSilence, nil),
                    ("mid",     nbMid,     nil),
                    ("energy",  nbEnergy,  nil),
                ]
            }
            return [
                ("silence", silenceFixture, nil),
                ("mid",     midFixture,     nil),
                ("beat",    beatFixture,    nil),
            ]
        }()

        var midPNGURL: URL?
        for index in 0..<fixtures.count {
            var fv = fixtures[index].fv
            // Pre-warm Lumen Mosaic per fixture: one tick at dt=5.0 saturates
            // the 5 s low-pass on valence/arousal in a single step, then 30
            // ticks at dt=1/60 advance the drift Lissajous + dance to a
            // representative phase before the GPU read. Apply per-fixture
            // track seed (or zero out for the unseeded variants — without
            // the explicit zero, a previous track_v* fixture's seed would
            // bleed into the next fixture rendered against the same engine
            // instance).
            if let engine = lumenEngine {
                engine.setTrackSeed(fixtures[index].trackSeed ?? .zero)
                var primer = fv
                primer.deltaTime = 5.0
                engine.tick(features: primer, stems: .zero)
                var advance = fv
                advance.deltaTime = 1.0 / 60.0
                for _ in 0..<30 { engine.tick(features: advance, stems: .zero) }
                // LM.4.7: cell colour comes from the Orchestrator-set palette
                // table (`lumen.palette[0..11]`), not self-generated per-cell RGB.
                // Without `setPalette`, every entry reads (0,0,0,0) and the shader
                // returns black cells (the frost seams still render white, which
                // masks the miss). Bind a curated palette LAST so its writeToGPU
                // flush carries the payload — mirrors the palette-library sheet and
                // PresetRegressionTests' Autumnal-bound fixture. Track-seed variety
                // still reads: `lm_track_seed_hash` walks the same palette differently
                // per seed.
                engine.setPalette(LumenMosaicPaletteLibrary.all[0])
            }
            // AV.2: tick AuroraVeilState so the slot-6 buffer reflects the
            // current fixture's kink + pitch. With stems.zero in the
            // standard fixtures the accumulator stays at 0 and the pitch
            // ring stays at the neutral 0.5 baseline (silence-equivalent).
            if let avState = auroraVeilState {
                avState.tick(deltaTime: fv.deltaTime, features: fv, stems: .zero)
            }
            // NB.4: prime the Nimbus follower so bloom converges to THIS
            // fixture's energy level before the GPU read. One big-dt tick snaps
            // the fast-attack/slow-release follower to its target (coeff → 1 at
            // dt ≫ τ); a few small ticks then advance the flow phase off the
            // t=0 lattice so the gas pattern reads.
            if let nbState = nimbusState {
                // ~150 ticks at dt 0.1 = 15 s — converges the bloom AND the ~4 s
                // mood EMA (NB.6) so the fixture's cool valence reads on the body.
                for _ in 0..<150 { nbState.tick(deltaTime: 0.1, features: fv, stems: .zero) }
            }
            let pixels = try renderFrame(preset: preset, context: ctx,
                                         arachneState: arachneState,
                                         auroraVeilState: auroraVeilState,
                                         nimbusState: nimbusState,
                                         lumenEngine: lumenEngine,
                                         noiseTextureManager: noiseTextureManager,
                                         features: &fv)
            let url = outputDir.appendingPathComponent(
                "\(presetName.replacingOccurrences(of: " ", with: "_"))_\(fixtures[index].name).png"
            )
            try writePNG(bgraPixels: pixels,
                         width: Self.renderWidth, height: Self.renderHeight,
                         to: url)
            print("[PresetVisualReview] wrote \(url.lastPathComponent)")
            if fixtures[index].name == "mid" { midPNGURL = url }
        }

        // Contact sheet — preset-specific layouts.
        if presetName == "Arachne", let midURL = midPNGURL {
            let sheetURL = outputDir.appendingPathComponent("Arachne_contact_sheet.png")
            try buildArachneContactSheet(renderedMidPNG: midURL, to: sheetURL)
            print("[PresetVisualReview] wrote \(sheetURL.lastPathComponent)")
        } else if presetName == "Nimbus", let midURL = midPNGURL {
            let sheetURL = outputDir.appendingPathComponent("Nimbus_contact_sheet.png")
            try buildContactSheet(renderedMidPNG: midURL,
                                  references: Self.nimbusReferenceRelPaths,
                                  renderLabel: "Nimbus render (mid) — lit",
                                  to: sheetURL)
            print("[PresetVisualReview] wrote \(sheetURL.lastPathComponent)")
        }
    }

    // MARK: - Lumen Mosaic palette-library contact sheet (LM.4.7)
    //
    // Render Lumen Mosaic once per palette in the 18-entry library and
    // compose a 6×3 contact sheet so Matt can sign off on per-palette
    // character without playing every track in a real-music session.
    //
    // Each cell: rendered preset frame downscaled into a fixed-size tile +
    // a label band carrying the palette name and its (valence, arousal)
    // mood anchor. The per-cell render uses a fixed mid-energy fixture
    // and zero per-track seed so the only inter-cell variable is the
    // palette payload — the layout reads as a side-by-side compare.

    @Test("Render Lumen Mosaic palette library contact sheet (RENDER_VISUAL=1)")
    func renderLumenMosaicPaletteContactSheet() throws {
        guard ProcessInfo.processInfo.environment["RENDER_VISUAL"] == "1" else {
            print("[PresetVisualReview] RENDER_VISUAL not set, skipping palette contact sheet")
            return
        }

        let ctx = try MetalContext()
        guard let preset = _acceptanceFixture.presets.first(where: {
            $0.descriptor.name == "Lumen Mosaic"
        }) else {
            print("[PresetVisualReview] Lumen Mosaic preset not found, skipping palette contact sheet")
            return
        }

        let outputDir = try makeOutputDirectory()
        print("[PresetVisualReview] palette contact-sheet output dir: \(outputDir.path)")

        let library = LumenMosaicPaletteLibrary.all
        var perPaletteImages: [(palette: LumenPalette, image: CGImage)] = []
        perPaletteImages.reserveCapacity(library.count)

        for palette in library {
            guard let engine = LumenPatternEngine(device: ctx.device, seed: 42) else {
                throw VisualReviewError.preconditionFailed(
                    "failed to allocate LumenPatternEngine for palette \(palette.name)")
            }
            // Zero track seed: the only inter-cell variable should be the
            // palette payload. Pre-warm the smoothed valence/arousal toward
            // a neutral (0, 0) so the per-palette read is the palette's
            // character, not a mood-induced agent drift. `setPalette(_:)`
            // is called last so the write-to-GPU at the end flushes the
            // most recent state including the palette payload.
            engine.setTrackSeed(.zero)
            var primer = midFixture
            primer.deltaTime = 5.0
            engine.tick(features: primer, stems: .zero)
            var advance = midFixture
            advance.deltaTime = 1.0 / 60.0
            for _ in 0..<30 { engine.tick(features: advance, stems: .zero) }
            engine.setPalette(palette)

            var fv = midFixture
            let pixels = try renderDeferredRayMarchFrame(preset: preset,
                                                         context: ctx,
                                                         lumenEngine: engine,
                                                         features: &fv)
            let safeName = palette.name.replacingOccurrences(of: " ", with: "_")
            let url = outputDir.appendingPathComponent("Lumen_palette_\(safeName).png")
            try writePNG(bgraPixels: pixels,
                         width: Self.renderWidth, height: Self.renderHeight,
                         to: url)
            print("[PresetVisualReview] wrote \(url.lastPathComponent)")

            if let cgImage = makeCGImage(bgraPixels: pixels,
                                         width: Self.renderWidth,
                                         height: Self.renderHeight) {
                perPaletteImages.append((palette, cgImage))
            }
        }

        let sheetURL = outputDir.appendingPathComponent("Lumen_palette_library_contact_sheet.png")
        try buildLumenPaletteContactSheet(images: perPaletteImages, to: sheetURL)
        print("[PresetVisualReview] wrote \(sheetURL.lastPathComponent)")
    }

    /// Compose 18 per-palette renders into a 6×3 grid. Each cell contains
    /// the rendered preset frame on top, a 12-square strip of raw palette
    /// colours immediately below it, and a name + mood-anchor label band
    /// at the bottom. The swatch strip is what makes the per-palette
    /// character read at thumbnail size — the Voronoi-mosaic render's
    /// per-cell colour signal averages out on downsample, but the strip
    /// shows the curated 12 colours directly. Sheet sized so it's
    /// readable on a 27" display (~2960 px wide).
    private func buildLumenPaletteContactSheet(
        images: [(palette: LumenPalette, image: CGImage)],
        to outURL: URL
    ) throws {
        let cols = 6
        let rows = 3
        let cellW = 480
        let renderH = 320
        let swatchH = 36
        let labelH = 56
        let cellH = renderH + swatchH + labelH
        let gutter = 8
        let margin = 16

        let sheetW = margin * 2 + cols * cellW + (cols - 1) * gutter
        let sheetH = margin * 2 + rows * cellH + (rows - 1) * gutter

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw VisualReviewError.cgImageFailed
        }
        let bitmapInfo = CGBitmapInfo(rawValue:
            CGImageAlphaInfo.premultipliedFirst.rawValue
            | CGBitmapInfo.byteOrder32Little.rawValue)
        guard let ctx = CGContext(data: nil,
                                  width: sheetW, height: sheetH,
                                  bitsPerComponent: 8,
                                  bytesPerRow: sheetW * 4,
                                  space: colorSpace,
                                  bitmapInfo: bitmapInfo.rawValue) else {
            throw VisualReviewError.cgImageFailed
        }

        // Dark background — keeps the per-cell renders' tonal envelope
        // visible without a competing white surround.
        ctx.setFillColor(red: 0.08, green: 0.08, blue: 0.08, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: sheetW, height: sheetH))

        // Lanczos resampling for the 1920 → 480 downsample preserves cell
        // boundaries better than the default (bilinear).
        ctx.interpolationQuality = .high

        // CoreGraphics origin is bottom-left; we fill cells top-to-bottom
        // by computing y from the top, then flipping into CG coordinates.
        for (index, entry) in images.enumerated() {
            let row = index / cols
            let col = index % cols
            let xPx = margin + col * (cellW + gutter)
            let yPxFromTop = margin + row * (cellH + gutter)
            let cgY = sheetH - yPxFromTop - cellH

            // Render image — top of the cell.
            let imageRect = CGRect(x: xPx, y: cgY + swatchH + labelH,
                                   width: cellW, height: renderH)
            ctx.draw(entry.image, in: imageRect)

            // 12-square swatch strip — middle band of the cell, directly
            // below the render. Each swatch is `cellW / 12` wide × swatchH
            // tall. Linear-RGB palette entries are encoded to sRGB by the
            // CGContext via the colourspace conversion.
            let swatchW = CGFloat(cellW) / 12.0
            for (slot, color) in entry.palette.colors.enumerated() {
                let swatchRect = CGRect(
                    x: CGFloat(xPx) + swatchW * CGFloat(slot),
                    y: CGFloat(cgY + labelH),
                    width: ceil(swatchW),
                    height: CGFloat(swatchH))
                ctx.setFillColor(
                    red: CGFloat(linearToSRGBChannel(color.x)),
                    green: CGFloat(linearToSRGBChannel(color.y)),
                    blue: CGFloat(linearToSRGBChannel(color.z)),
                    alpha: 1)
                ctx.fill(swatchRect)
            }

            // Label band — bottom of the cell.
            let labelRect = CGRect(x: xPx, y: cgY,
                                   width: cellW, height: labelH)
            ctx.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
            ctx.fill(labelRect)
        }

        // Draw labels via NSGraphicsContext for clean AppKit-rendered text.
        let nsContext = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsContext

        let nameAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 18),
            .foregroundColor: NSColor.white,
        ]
        let anchorAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor(red: 0.78, green: 0.78, blue: 0.78, alpha: 1),
        ]

        for (index, entry) in images.enumerated() {
            let row = index / cols
            let col = index % cols
            let xPx = margin + col * (cellW + gutter)
            let yPxFromTop = margin + row * (cellH + gutter)
            let cgY = sheetH - yPxFromTop - cellH

            let nameOrigin = NSPoint(x: CGFloat(xPx + 12),
                                     y: CGFloat(cgY + labelH - 26))
            NSAttributedString(string: entry.palette.name, attributes: nameAttrs)
                .draw(at: nameOrigin)

            let anchorText = String(format: "v=%+.2f  a=%+.2f",
                                    entry.palette.moodAnchor.x,
                                    entry.palette.moodAnchor.y)
            let anchorOrigin = NSPoint(x: CGFloat(xPx + 12),
                                       y: CGFloat(cgY + 6))
            NSAttributedString(string: anchorText, attributes: anchorAttrs)
                .draw(at: anchorOrigin)
        }
        NSGraphicsContext.restoreGraphicsState()

        guard let cgImage = ctx.makeImage() else {
            throw VisualReviewError.cgImageFailed
        }
        try writeCGImage(cgImage, to: outURL)
    }

    /// Linear-RGB → sRGB transfer for one channel (IEC 61966-2-1). Used by
    /// the contact-sheet swatch strip so on-screen pixel colour matches
    /// what the shader paints into the rgba8Unorm albedo: the rendered
    /// preset frame is encoded to sRGB by the swapchain; the swatch strip
    /// has to do the same conversion explicitly because `ctx.setFillColor`
    /// in an sRGB colourspace context takes its arguments as sRGB values.
    private func linearToSRGBChannel(_ value: Float) -> Float {
        let clamped = max(0, min(1, value))
        if clamped <= 0.0031308 { return clamped * 12.92 }
        return 1.055 * powf(clamped, 1 / 2.4) - 0.055
    }

    // MARK: - Output directory

    private func makeOutputDirectory() throws -> URL {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withYear, .withMonth, .withDay, .withTime]
        let stamp = formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let url = URL(fileURLWithPath: Self.outputRoot)
            .appendingPathComponent(stamp)
        try FileManager.default.createDirectory(at: url,
                                                withIntermediateDirectories: true)
        return url
    }

    // MARK: - Render

    private func renderFrame(
        preset: PresetLoader.LoadedPreset,
        context: MetalContext,
        arachneState: ArachneState?,
        auroraVeilState: AuroraVeilState? = nil,
        nimbusState: NimbusState? = nil,
        lumenEngine: LumenPatternEngine? = nil,
        noiseTextureManager: TextureManager? = nil,
        features: inout FeatureVector
    ) throws -> [UInt8] {
        // Dispatch: pure-ray-march presets go through the deferred pipeline so
        // the harness captures actual lit output rather than raw G-buffer.
        // Mv_warp ray-march presets stay on the warp path below (their
        // `pipelineState` is the warp pipeline, not the G-buffer state).
        let passes = preset.descriptor.passes
        if passes.contains(.rayMarch) && !passes.contains(.mvWarp) {
            return try renderDeferredRayMarchFrame(preset: preset,
                                                    context: context,
                                                    lumenEngine: lumenEngine,
                                                    noiseTextureManager: noiseTextureManager,
                                                    features: &features)
        }

        let width = Self.renderWidth
        let height = Self.renderHeight

        let texDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: context.pixelFormat,
            width: width, height: height, mipmapped: false)
        texDesc.usage = [.renderTarget, .shaderRead]
        texDesc.storageMode = .shared
        guard let texture = context.device.makeTexture(descriptor: texDesc) else {
            throw VisualReviewError.textureAllocationFailed
        }

        let floatStride = MemoryLayout<Float>.stride
        guard
            let fftBuf = context.makeSharedBuffer(length: 512 * floatStride),
            let wavBuf = context.makeSharedBuffer(length: 2048 * floatStride),
            let stemBuf = context.makeSharedBuffer(length: MemoryLayout<StemFeatures>.size),
            let histBuf = context.makeSharedBuffer(length: 4096 * floatStride)
        else { throw VisualReviewError.bufferAllocationFailed }
        _ = stemBuf.contents().initializeMemory(as: UInt8.self, repeating: 0,
                                                count: MemoryLayout<StemFeatures>.size)
        _ = histBuf.contents().initializeMemory(as: UInt8.self, repeating: 0,
                                                count: 4096 * floatStride)

        var sceneBuf: MTLBuffer?
        if preset.descriptor.passes.contains(.rayMarch),
           let buf = context.makeSharedBuffer(length: MemoryLayout<SceneUniforms>.size) {
            var su = preset.descriptor.makeSceneUniforms()
            buf.contents().copyMemory(from: &su, byteCount: MemoryLayout<SceneUniforms>.size)
            sceneBuf = buf
        }

        guard let cmdBuf = context.commandQueue.makeCommandBuffer() else {
            throw VisualReviewError.commandBufferFailed
        }
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = texture
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        rpd.colorAttachments[0].storeAction = .store
        guard let encoder = cmdBuf.makeRenderCommandEncoder(descriptor: rpd) else {
            throw VisualReviewError.encoderCreationFailed
        }

        encoder.setRenderPipelineState(preset.pipelineState)
        encoder.setFragmentBytes(&features, length: MemoryLayout<FeatureVector>.size, index: 0)
        // Noise textures at slots 4–8 (orthogonal to the buffer(6)/(7) per-preset
        // state Arachne/Aurora bind). Matches production's bindNoiseTextures so the
        // review PNG is byte-faithful (FA #66). Nimbus samples noiseVolume(6) +
        // blueNoise(8); harmless/free for presets that sample fewer slots.
        noiseTextureManager?.bindTextures(to: encoder)
        encoder.setFragmentBuffer(fftBuf, offset: 0, index: 1)
        encoder.setFragmentBuffer(wavBuf, offset: 0, index: 2)
        encoder.setFragmentBuffer(stemBuf, offset: 0, index: 3)
        if let sceneBuf = sceneBuf {
            encoder.setFragmentBuffer(sceneBuf, offset: 0, index: 4)
        }
        encoder.setFragmentBuffer(histBuf, offset: 0, index: 5)

        if let arachneState = arachneState {
            encoder.setFragmentBuffer(arachneState.webBuffer, offset: 0, index: 6)
            encoder.setFragmentBuffer(arachneState.spiderBuffer, offset: 0, index: 7)
        } else if let auroraVeilState = auroraVeilState {
            // AV.2: bind the 16-byte AuroraVeilStateGPU at slot 6. Ticked
            // per fixture by the caller before this dispatch — for the
            // standard silence/mid/beat fixtures (all stems.zero) the
            // buffer stays at silence-equivalent values.
            encoder.setFragmentBuffer(auroraVeilState.stateBuffer, offset: 0, index: 6)
        } else if let nimbusState = nimbusState {
            // NB.4: bind the 16-byte NimbusStateGPU at buffer slot 6 (Energy
            // bloom + flow phase). Orthogonal to noiseVolume at *texture* 6 —
            // different binding namespaces. Primed per fixture by the caller.
            encoder.setFragmentBuffer(nimbusState.stateBuffer, offset: 0, index: 6)
        }

        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()
        guard cmdBuf.status == .completed else { throw VisualReviewError.renderFailed }

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(&pixels, bytesPerRow: width * 4,
                         from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        return pixels
    }

    // MARK: - Render (deferred ray-march)

    /// Render a pure-ray-march preset (passes contain `.rayMarch` and NOT
    /// `.mvWarp`) by composing a standalone `RayMarchPipeline` and running the
    /// full G-buffer → lighting → (SSGI) → (bloom/post-process) sequence with
    /// production-parity bindings (BUG-034 M7-lite review upgrade, mirroring
    /// the FerrofluidOceanVisualTests round-56/57 parity work):
    ///
    /// - **Noise textures bound at slots 4–8** via the caller's TextureManager
    ///   (production: `RenderPipeline+RayMarch` passes `textureManager`).
    /// - **IBL bound** (production always binds `iblManager` on this path).
    /// - **SSGI enabled when the preset declares `.ssgi`** (no production preset
    ///   currently declares it after Glass Brutalist's retirement, D-185).
    /// - **PostProcessChain constructed when the preset declares `.postProcess`**
    ///   (production: `passesIncludePostProcess ? ppChain : nil`).
    /// - **Ferrofluid Ocean: 4096² height field baked and bound at texture 10**
    ///   (production bakes it at preset wire-up; live uses the same SDF path
    ///   since round 57).
    /// - **Slot 8 (`presetFragmentBuffer3`) bound when `lumenEngine` is non-nil**
    ///   (Lumen Mosaic's 4-light pattern state).
    ///
    /// Remaining live-path deltas: stems are `.zero` and `audioTime` is 0
    /// (deterministic review fixtures), and the D-022 valence light tint is
    /// not applied (fixtures carry neutral valence).
    ///
    /// `RENDER_STEP_MULT=<float>` overrides the D-057 step multiplier in
    /// `sceneParamsB.z` — used to render "before" halves of step-budget A/B
    /// pairs at the pre-BUG-034 budget (0.25 → 32 steps). Unset = the
    /// `makeSceneUniforms()` default (1.0 → 128 steps, live parity).
    private func renderDeferredRayMarchFrame(
        preset: PresetLoader.LoadedPreset,
        context: MetalContext,
        lumenEngine: LumenPatternEngine? = nil,
        noiseTextureManager: TextureManager? = nil,
        features: inout FeatureVector
    ) throws -> [UInt8] {
        let width  = Self.renderWidth
        let height = Self.renderHeight

        guard let gbufferState = preset.rayMarchPipelineState else {
            throw VisualReviewError.preconditionFailed(
                "preset '\(preset.descriptor.name)' missing rayMarchPipelineState")
        }

        let shaderLibrary = try ShaderLibrary(context: context)
        let pipeline = try RayMarchPipeline(context: context,
                                            shaderLibrary: shaderLibrary)
        pipeline.allocateTextures(width: width, height: height)

        // SceneUniforms — same construction as production. Override aspect
        // ratio to match the harness render dimensions; audioTime stays at 0.
        var sceneUniforms = preset.descriptor.makeSceneUniforms()
        sceneUniforms.sceneParamsA.y = Float(width) / Float(height)

        // BUG-034 A/B hook: override the D-057 step multiplier for "before"
        // renders. Production never reads this env var.
        if let raw = ProcessInfo.processInfo.environment["RENDER_STEP_MULT"],
           let stepMult = Float(raw) {
            sceneUniforms.sceneParamsB.z = stepMult
        }
        pipeline.sceneUniforms = sceneUniforms

        // Production-parity bindings (see doc comment).
        let iblManager = try IBLManager(context: context, shaderLibrary: shaderLibrary)
        pipeline.ssgiEnabled = preset.descriptor.passes.contains(.ssgi)

        let ppChain: PostProcessChain?
        if preset.descriptor.passes.contains(.postProcess) {
            let chain = try PostProcessChain(context: context, shaderLibrary: shaderLibrary)
            chain.allocateTextures(width: width, height: height)
            ppChain = chain
        } else {
            ppChain = nil
        }

        var heightTexture: MTLTexture?
        if preset.descriptor.name == "Ferrofluid Ocean" {
            guard let particles = FerrofluidParticles(device: context.device,
                                                      library: shaderLibrary.library) else {
                throw VisualReviewError.preconditionFailed(
                    "FerrofluidParticles allocation failed — height texture cannot be bound")
            }
            particles.bakeHeightField(commandQueue: context.commandQueue)
            heightTexture = particles.heightTexture
        }

        let floatStride = MemoryLayout<Float>.stride
        guard
            let fftBuf = context.makeSharedBuffer(length: 512 * floatStride),
            let wavBuf = context.makeSharedBuffer(length: 2048 * floatStride)
        else { throw VisualReviewError.bufferAllocationFailed }

        let outDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: context.pixelFormat,
            width: width, height: height, mipmapped: false)
        outDesc.usage = [.renderTarget, .shaderRead]
        outDesc.storageMode = .shared
        guard let outTex = context.device.makeTexture(descriptor: outDesc) else {
            throw VisualReviewError.textureAllocationFailed
        }

        guard let cmdBuf = context.commandQueue.makeCommandBuffer() else {
            throw VisualReviewError.commandBufferFailed
        }

        pipeline.render(
            gbufferPipelineState: gbufferState,
            features: &features,
            fftBuffer: fftBuf,
            waveformBuffer: wavBuf,
            stemFeatures: .zero,
            outputTexture: outTex,
            commandBuffer: cmdBuf,
            noiseTextures: noiseTextureManager,
            iblManager: iblManager,
            postProcessChain: ppChain,
            presetFragmentBuffer3: lumenEngine?.patternBuffer,
            presetHeightTexture: heightTexture
        )

        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()
        guard cmdBuf.status == .completed else { throw VisualReviewError.renderFailed }

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        outTex.getBytes(&pixels, bytesPerRow: width * 4,
                         from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        return pixels
    }

    // MARK: - Render (staged)

    /// Render a staged preset stage-by-stage. Returns BGRA pixel arrays keyed
    /// by stage name so the caller can write one PNG per stage.
    ///
    /// Implementation: stage 0..N-2 are rendered into per-stage `.rgba16Float`
    /// offscreen textures (the same textures stage N samples). For PNG output
    /// each stage is also re-rendered into a parallel BGRA texture so it can
    /// be encoded as 8-bit. Final stage (N-1) renders directly into BGRA.
    private func renderStagedFrame(
        preset: PresetLoader.LoadedPreset,
        context: MetalContext,
        features: inout FeatureVector,
        arachneState: ArachneState? = nil
    ) throws -> [(stage: String, pixels: [UInt8])] {
        let width = Self.renderWidth
        let height = Self.renderHeight

        let floatStride = MemoryLayout<Float>.stride
        guard
            let fftBuf = context.makeSharedBuffer(length: 512 * floatStride),
            let waveBuf = context.makeSharedBuffer(length: 2048 * floatStride),
            let stemBuf = context.makeSharedBuffer(length: MemoryLayout<StemFeatures>.size),
            let histBuf = context.makeSharedBuffer(length: 4096 * floatStride)
        else { throw VisualReviewError.bufferAllocationFailed }
        _ = stemBuf.contents().initializeMemory(as: UInt8.self, repeating: 0,
                                                count: MemoryLayout<StemFeatures>.size)
        _ = histBuf.contents().initializeMemory(as: UInt8.self, repeating: 0,
                                                count: 4096 * floatStride)

        // One offscreen `.rgba16Float` texture per non-final stage (used by
        // later stages that name it in `samples`).
        var offscreen: [String: MTLTexture] = [:]
        for stage in preset.stages where !stage.writesToDrawable {
            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba16Float,
                width: width, height: height, mipmapped: false)
            desc.usage = [.renderTarget, .shaderRead]
            desc.storageMode = .private
            guard let tex = context.device.makeTexture(descriptor: desc) else {
                throw VisualReviewError.textureAllocationFailed
            }
            offscreen[stage.name] = tex
        }

        // Encode the staged dispatch into a single command buffer.
        guard let cmd = context.commandQueue.makeCommandBuffer() else {
            throw VisualReviewError.commandBufferFailed
        }
        for stage in preset.stages where !stage.writesToDrawable {
            guard let target = offscreen[stage.name] else { continue }
            try encodeStagePass(stage: stage, target: target, commandBuffer: cmd,
                                features: &features,
                                fft: fftBuf, wave: waveBuf, stems: stemBuf, hist: histBuf,
                                samples: offscreen,
                                arachneState: arachneState)
        }
        cmd.commit()
        cmd.waitUntilCompleted()

        // Read each stage back as BGRA pixels for PNG export.
        var result: [(stage: String, pixels: [UInt8])] = []
        // 1) Each non-final stage: re-render into a BGRA shared texture so we can `getBytes`.
        for stage in preset.stages where !stage.writesToDrawable {
            let bgra = try makeShared8BitTexture(device: context.device,
                                                 format: context.pixelFormat,
                                                 width: width, height: height)
            // Build a one-off pipeline that runs the same fragment but writes to BGRA.
            let bgraPipeline = try makeBGRAPipeline(for: stage,
                                                     preset: preset,
                                                     context: context)
            guard let cb = context.commandQueue.makeCommandBuffer() else {
                throw VisualReviewError.commandBufferFailed
            }
            try encodeStagePass(stage: stage,
                                explicitPipeline: bgraPipeline,
                                target: bgra,
                                commandBuffer: cb,
                                features: &features,
                                fft: fftBuf, wave: waveBuf, stems: stemBuf, hist: histBuf,
                                samples: offscreen,
                                arachneState: arachneState)
            cb.commit()
            cb.waitUntilCompleted()
            result.append((stage.name, readBGRA(bgra, width: width, height: height)))
        }
        // 2) Final stage: render directly into a BGRA shared texture.
        if let finalStage = preset.stages.last, finalStage.writesToDrawable {
            let bgra = try makeShared8BitTexture(device: context.device,
                                                 format: context.pixelFormat,
                                                 width: width, height: height)
            guard let cb = context.commandQueue.makeCommandBuffer() else {
                throw VisualReviewError.commandBufferFailed
            }
            try encodeStagePass(stage: finalStage,
                                target: bgra,
                                commandBuffer: cb,
                                features: &features,
                                fft: fftBuf, wave: waveBuf, stems: stemBuf, hist: histBuf,
                                samples: offscreen,
                                arachneState: arachneState)
            cb.commit()
            cb.waitUntilCompleted()
            result.append((finalStage.name, readBGRA(bgra, width: width, height: height)))
        }
        return result
    }

    private func encodeStagePass(
        stage: PresetLoader.LoadedStage,
        explicitPipeline: MTLRenderPipelineState? = nil,
        target: MTLTexture,
        commandBuffer: MTLCommandBuffer,
        features: inout FeatureVector,
        fft: MTLBuffer, wave: MTLBuffer, stems: MTLBuffer, hist: MTLBuffer,
        samples: [String: MTLTexture],
        arachneState: ArachneState? = nil
    ) throws {
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = target
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        rpd.colorAttachments[0].storeAction = .store
        guard let enc = commandBuffer.makeRenderCommandEncoder(descriptor: rpd) else {
            throw VisualReviewError.encoderCreationFailed
        }
        enc.setRenderPipelineState(explicitPipeline ?? stage.pipelineState)
        enc.setFragmentBytes(&features, length: MemoryLayout<FeatureVector>.size, index: 0)
        enc.setFragmentBuffer(fft, offset: 0, index: 1)
        enc.setFragmentBuffer(wave, offset: 0, index: 2)
        enc.setFragmentBuffer(stems, offset: 0, index: 3)
        enc.setFragmentBuffer(hist, offset: 0, index: 5)
        // Per-preset fragment buffers — mirrors RenderPipeline+Staged.encodeStage
        // (slot 6 = ArachneWebGPU pool, slot 7 = ArachneSpiderGPU). Required for
        // V.7.7B's staged Arachne fragments to read mood / web / spider state.
        if let arachneState = arachneState {
            enc.setFragmentBuffer(arachneState.webBuffer, offset: 0, index: 6)
            enc.setFragmentBuffer(arachneState.spiderBuffer, offset: 0, index: 7)
        }
        for (offset, name) in stage.samples.enumerated() {
            guard let tex = samples[name] else { continue }
            enc.setFragmentTexture(tex, index: kStagedSampledTextureFirstSlot + offset)
        }
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
    }

    /// Build a BGRA-target pipeline for an intermediate stage so the harness
    /// can write its output to PNG. Recompiles the preset shader file once
    /// per call; only used for `RENDER_VISUAL=1` runs.
    private func makeBGRAPipeline(
        for stage: PresetLoader.LoadedStage,
        preset: PresetLoader.LoadedPreset,
        context: MetalContext
    ) throws -> MTLRenderPipelineState {
        // BUG-002: `Bundle.module` here resolves the *test* target's bundle, which
        // has no `Shaders` resource — the harness was silently failing the staged
        // preset PNG export. `PresetLoader.bundledShadersURL` reaches the same
        // Presets-module resource bundle the loader uses internally.
        guard let bundleShaders = PresetLoader.bundledShadersURL else {
            throw VisualReviewError.cgImageFailed
        }
        let metalURL = bundleShaders.appendingPathComponent(
            preset.descriptor.shaderFileName)
        let source = try String(contentsOf: metalURL, encoding: .utf8)
        let fullSource = PresetLoader.shaderPreamble + "\n\n" + source
        let options = MTLCompileOptions()
        options.fastMathEnabled = true
        options.languageVersion = .version3_1
        let library = try context.device.makeLibrary(source: fullSource, options: options)

        guard let descStage = preset.descriptor.stages.first(where: { $0.name == stage.name }),
              let vertexFn = library.makeFunction(name: preset.descriptor.vertexFunction),
              let fragmentFn = library.makeFunction(name: descStage.fragmentFunction) else {
            throw VisualReviewError.cgImageFailed
        }
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vertexFn
        desc.fragmentFunction = fragmentFn
        desc.colorAttachments[0].pixelFormat = context.pixelFormat
        return try context.device.makeRenderPipelineState(descriptor: desc)
    }

    private func makeShared8BitTexture(
        device: MTLDevice,
        format: MTLPixelFormat,
        width: Int, height: Int
    ) throws -> MTLTexture {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: format, width: width, height: height, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .shared
        guard let tex = device.makeTexture(descriptor: desc) else {
            throw VisualReviewError.textureAllocationFailed
        }
        return tex
    }

    private func readBGRA(_ texture: MTLTexture, width: Int, height: Int) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(&pixels, bytesPerRow: width * 4,
                         from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        return pixels
    }

    // MARK: - PNG encoding

    private func writePNG(bgraPixels: [UInt8],
                          width: Int, height: Int,
                          to url: URL) throws {
        guard let cgImage = makeCGImage(bgraPixels: bgraPixels,
                                        width: width, height: height) else {
            throw VisualReviewError.cgImageFailed
        }
        try writeCGImage(cgImage, to: url)
    }

    private func makeCGImage(bgraPixels: [UInt8],
                             width: Int, height: Int) -> CGImage? {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let bitmapInfo = CGBitmapInfo(rawValue:
            CGImageAlphaInfo.premultipliedFirst.rawValue
            | CGBitmapInfo.byteOrder32Little.rawValue)
        var copy = bgraPixels
        return copy.withUnsafeMutableBytes { (ptr: UnsafeMutableRawBufferPointer) -> CGImage? in
            guard let base = ptr.baseAddress else { return nil }
            guard let ctx = CGContext(data: base,
                                      width: width, height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: width * 4,
                                      space: colorSpace,
                                      bitmapInfo: bitmapInfo.rawValue) else { return nil }
            return ctx.makeImage()
        }
    }

    private func writeCGImage(_ image: CGImage, to url: URL) throws {
        let type: CFString
        if #available(macOS 11.0, *) { type = UTType.png.identifier as CFString }
        else { type = "public.png" as CFString }
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type, 1, nil) else {
            throw VisualReviewError.pngWriteFailed
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw VisualReviewError.pngWriteFailed
        }
    }

    // MARK: - Contact sheet (Arachne only)

    private func buildArachneContactSheet(renderedMidPNG: URL, to outURL: URL) throws {
        let sheetW = Self.renderWidth
        let sheetH = Self.renderHeight
        let topHalfH = sheetH / 2
        let cellW = sheetW / 4
        let cellH = sheetH / 2

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw VisualReviewError.cgImageFailed
        }
        let bitmapInfo = CGBitmapInfo(rawValue:
            CGImageAlphaInfo.premultipliedFirst.rawValue
            | CGBitmapInfo.byteOrder32Little.rawValue)
        guard let ctx = CGContext(data: nil,
                                  width: sheetW, height: sheetH,
                                  bitsPerComponent: 8,
                                  bytesPerRow: sheetW * 4,
                                  space: colorSpace,
                                  bitmapInfo: bitmapInfo.rawValue) else {
            throw VisualReviewError.cgImageFailed
        }

        // Black background.
        ctx.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: sheetW, height: sheetH))

        // Top half: rendered output letterboxed to fit (1920×640).
        if let renderedImage = loadCGImage(from: renderedMidPNG) {
            let topRect = CGRect(x: 0, y: cellH, width: sheetW, height: topHalfH)
            drawLetterboxed(image: renderedImage, in: topRect, ctx: ctx)
        }

        // Bottom half: 4 references each in a 480×640 cell.
        let projectRoot = projectRootURL()
        for (index, ref) in Self.arachneReferenceRelPaths.enumerated() {
            let url = projectRoot.appendingPathComponent(ref.path)
            let rect = CGRect(x: index * cellW, y: 0,
                              width: cellW, height: cellH)
            if let img = loadCGImage(from: url) {
                drawLetterboxed(image: img, in: rect, ctx: ctx)
            }
        }

        // Labels — render via NSGraphicsContext bridging to CGContext.
        let nsContext = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsContext

        let labels: [(text: String, originX: Int, originY: Int)] = [
            ("Render: steady-mid", 12, sheetH - 24),
        ] + Self.arachneReferenceRelPaths.enumerated().map { index, ref in
            (ref.label, index * cellW + 12, cellH - 24)
        }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor(red: 0, green: 0, blue: 0, alpha: 0.7),
        ]
        for label in labels {
            let attributed = NSAttributedString(string: " \(label.text) ", attributes: attrs)
            attributed.draw(at: NSPoint(x: label.originX, y: label.originY))
        }
        NSGraphicsContext.restoreGraphicsState()

        guard let cgImage = ctx.makeImage() else {
            throw VisualReviewError.cgImageFailed
        }
        try writeCGImage(cgImage, to: outURL)
    }

    /// General N-cell contact sheet: rendered output letterboxed across the top
    /// half, `references.count` reference cells across the bottom half, each
    /// labelled. Used for Nimbus (5 cells: 3 TRUST refs + 2 AVOID anti-refs) and
    /// any future preset that wants a render-vs-references sheet; Arachne keeps
    /// its bespoke 4-cell builder above.
    private func buildContactSheet(
        renderedMidPNG: URL,
        references: [(label: String, path: String)],
        renderLabel: String,
        to outURL: URL
    ) throws {
        let sheetW = Self.renderWidth
        let sheetH = Self.renderHeight
        let topHalfH = sheetH / 2
        let cols = max(references.count, 1)
        let cellW = sheetW / cols
        let cellH = sheetH / 2

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw VisualReviewError.cgImageFailed
        }
        let bitmapInfo = CGBitmapInfo(rawValue:
            CGImageAlphaInfo.premultipliedFirst.rawValue
            | CGBitmapInfo.byteOrder32Little.rawValue)
        guard let ctx = CGContext(data: nil, width: sheetW, height: sheetH,
                                  bitsPerComponent: 8, bytesPerRow: sheetW * 4,
                                  space: colorSpace, bitmapInfo: bitmapInfo.rawValue) else {
            throw VisualReviewError.cgImageFailed
        }

        ctx.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: sheetW, height: sheetH))
        ctx.interpolationQuality = .high

        // Top half: rendered output letterboxed.
        if let renderedImage = loadCGImage(from: renderedMidPNG) {
            let topRect = CGRect(x: 0, y: cellH, width: sheetW, height: topHalfH)
            drawLetterboxed(image: renderedImage, in: topRect, ctx: ctx)
        }

        // Bottom half: reference cells, left → right.
        let projectRoot = projectRootURL()
        for (index, ref) in references.enumerated() {
            let url = projectRoot.appendingPathComponent(ref.path)
            let rect = CGRect(x: index * cellW, y: 0, width: cellW, height: cellH)
            if let img = loadCGImage(from: url) {
                drawLetterboxed(image: img, in: rect, ctx: ctx)
            }
        }

        // Labels via NSGraphicsContext.
        let nsContext = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsContext
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 20),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor(red: 0, green: 0, blue: 0, alpha: 0.7),
        ]
        NSAttributedString(string: " \(renderLabel) ", attributes: attrs)
            .draw(at: NSPoint(x: 12, y: sheetH - 30))
        for (index, ref) in references.enumerated() {
            NSAttributedString(string: " \(ref.label) ", attributes: attrs)
                .draw(at: NSPoint(x: index * cellW + 8, y: cellH - 30))
        }
        NSGraphicsContext.restoreGraphicsState()

        guard let cgImage = ctx.makeImage() else { throw VisualReviewError.cgImageFailed }
        try writeCGImage(cgImage, to: outURL)
    }

    private func loadCGImage(from url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    /// Draw `image` into `rect` preserving aspect ratio (letterboxed in black).
    private func drawLetterboxed(image: CGImage, in rect: CGRect, ctx: CGContext) {
        let srcW = CGFloat(image.width)
        let srcH = CGFloat(image.height)
        let scale = min(rect.width / srcW, rect.height / srcH)
        let drawW = srcW * scale
        let drawH = srcH * scale
        let drawX = rect.origin.x + (rect.width - drawW) / 2
        let drawY = rect.origin.y + (rect.height - drawH) / 2
        ctx.draw(image, in: CGRect(x: drawX, y: drawY,
                                   width: drawW, height: drawH))
    }

    /// Walk up from `#filePath` to the project root (4 levels:
    /// PhospheneEngine/Tests/PhospheneEngineTests/Renderer/<file> → repo root).
    private func projectRootURL(file: String = #filePath) -> URL {
        var url = URL(fileURLWithPath: file)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url
    }
}

// MARK: - Errors

private enum VisualReviewError: Error {
    case textureAllocationFailed
    case bufferAllocationFailed
    case commandBufferFailed
    case encoderCreationFailed
    case renderFailed
    case cgImageFailed
    case pngWriteFailed
    case preconditionFailed(String)
}
