// RenderPipeline+Nacre — the Nacre mv_warp draw branch (NACRE.2b).
//
// Faithful port of the butterchurn builtin `$$$ Royal - Mashup (431)` render loop
// (read wholesale from source, FA #70). Per frame — the D-138 structure, simpler than
// Fata Morgana (no blur target, no shapes; the seed is folded into the warp):
//
//   warp(prev, u) → composeTexture       (custom feedback warp; bakes its own decay,
//                                          unsharp, grain, palette-tinted core seed)
//   comp(compose, u) → target            (the signature look; DISPLAY-only)
//   swap warpTexture ↔ composeTexture
//
// NacreUniforms carries the (431) builtins the custom shaders reference (time, the
// treble grain gate, feedback texel size + aspect, the fixed per-load randoms + slow
// colour roam). All time-driven / stateless — no CPU accumulators (the bass-onset kick
// runs GPU-side off bassDev in mvWarpPerVertex).

import Metal
@preconcurrency import MetalKit
import Shared

// MARK: - NacreUniforms (matches `struct NacreUniforms` in Nacre.metal)

/// 96-byte uniform bound at fragment buffer(1) of the warp + comp passes.
/// Layout: time/trebleGrain/coreEnergy/pad0 fill the first 16-byte slot, then
/// texel+pad1, then four 16-aligned SIMD4<Float> — byte-identical to the MSL struct.
struct NacreUniforms {
    var time: Float = 0
    var trebleGrain: Float = 0
    var coreEnergy: Float = 0          // STEADY total energy → the warp's core seed (no smear)
    var hueShift: Float = 0            // NACRE.3: harmony → palette-phase nudge (seconds), bounded
    var texel: SIMD2<Float> = .init(1, 1)
    var barPush: Float = 0             // NACRE.4: downbeat envelope → display-stage camera push (visible motion)
    var spin: Float = 0                // NACRE.3: energy → continuous warp rotation (turning ← music)
    var aspect: SIMD4<Float> = .init(1, 1, 1, 1)
    // Fixed per-load random (the comp's tint + dz-scale character). Chosen in the
    // green-gold register the (431) reference sits in (tint 1+rand ≈ (1.62,1.74,1.30)).
    // Swept against the reference stills at port time; a comp-only constant.
    var randPreset: SIMD4<Float> = .init(0.62, 0.74, 0.30, 0.55)
    var slowRoamSin: SIMD4<Float> = .init(repeating: 0.5)
    var roamCos: SIMD4<Float> = .init(repeating: 0.5)
    // TONAL.3 (D-178): x = palette desaturate amount (consonance-gated toward the atonal
    // rest state). y,z,w spare (y reserved for the deferred tension→dispersion route).
    var tonal: SIMD4<Float> = .init(0.20, 1.0, 0, 0)
}

// TONAL.3 (D-178) hue ← real harmony. The circle-of-fifths phase maps to the full
// ~14.4 s `nacrePalette` cycle (2π/0.437), so the 12 keys span the colour wheel evenly
// (~1.2 s ≈ 30° per key) and fifth-adjacent keys land on adjacent colours — related keys
// → related colours, the whole point. Consonance gates the coupling to the neutral rest
// state (atonal / percussive passages desaturate). The tonal_tension → rim-dispersion
// secondary is DEFERRED to round 2 (it under-develops on 30 s preview fixtures, so the
// QG.1 route-coverage gate can't exercise it — a fixture-breadth limit, not a dead route).
private let kNacrePalettePeriod: Float = 14.4
// Round 2 drift rates (palette-seconds per real second). At silence/atonal the palette
// rotates at the faithful ~14.4 s cycle (rate 1.0); when tonal the clock nearly stops
// (0.06 ≈ a 240 s cycle) so the KEY holds the hue — the palette's motion then comes from
// the harmony moving through the song's chords, not the clock. Matt tunes the tonal rate.
private let kNacreFaithfulRate: Float = 1.0
private let kNacreTonalDriftRate: Float = 0.06
private let kNacreDesatTonal: Float = 0.20     // the faithful (431) desaturate (shader kNacreDesat)
private let kNacreDesatAtonal: Float = 0.38    // atonal → gentle desaturate toward rest (mud-safe; Matt tunes in M7)
// Turning ← energy. `spin` is radians/frame of continuous warp rotation. At ~60 fps the
// peak envelope (~0.55 − floor 0.18 = 0.37) × gain 0.012 ≈ 0.0044 rad/frame ≈ 15°/s (a full
// turn ~24 s); the quietest passages sit near-still. Both are feel knobs (Matt tunes live).
private let kNacreSpinGain: Float = 0.012
private let kNacreSpinFloor: Float = 0.18

extension RenderPipeline {

    // MARK: Per-frame uniforms

    /// Compute the Nacre warp/comp uniforms for this frame. Holds smoothing accumulators
    /// (`nacreSeedEMA`/`nacreSpinEMA`/`nacreHueEMA`/`nacreCentroidNorm`) — the audio routes.
    @MainActor
    func computeNacreUniforms(features: FeatureVector, stems: StemFeatures) -> NacreUniforms {
        var uni = NacreUniforms()
        let tSec = features.time
        uni.time = tSec
        uni.trebleGrain = max(0, features.trebDev)

        // ── Core SEED (warp), STEADY (NACRE.3) ──
        // The warp's core seed is STEADY total energy (~0.5 s EMA) — it sustains the field's
        // central convergence without flaring (a dynamic seed advects into a radial smear;
        // audio dynamics stay display-stage, the Dragon Bloom precedent). [The display-stage
        // voice GLOW that used to ride on top was cut — Matt M7: "blindingly bright at some
        // points"; it added +0.46 at centre on the vocal peaks and never read as a connection.
        // nacreCoreEMA / voiceLevel removed with it.]
        let total = max(0, (features.bass + features.mid + features.treble) / 3.0)
        nacreSeedEMA += (total - nacreSeedEMA) * 0.03    // ~0.5 s → near-steady seed (no warp smear)
        uni.coreEnergy = nacreSeedEMA

        // ── Turning speed ← the music's energy (NACRE.3) — motion, not brightness ──
        // The downbeat brightness pulse read as a flash on the bright iridescent field no
        // matter how it was tuned (Matt M7: "the pulse is accurate, but the brightness is
        // still bothersome"). Nacre speaks in flow + swirl, so move the connection into the
        // lever Matt named — the field's TURNING. `nu.spin` is a continuous per-frame rotation
        // the warp adds to its swirl: the molten field turns faster as the music fills out,
        // slower when sparse. Driven off avgStem (full-band-aware — bands are BLIND to full-band
        // entries, ≈0.14 there; the energy lives in the stems, which jump together to ~0.55) on
        // a smooth ~0.5 s envelope, so it reads as intensity, not the per-beat jerk of the first
        // port. The floor keeps the quietest passages near-still; the spin ACCUMULATES (the warp
        // re-samples the already-spun feedback) so even a small rate reads as a clear swirl.
        // ~2× envelope swing across this song's arc (p10 0.27 → p90 0.55, session 15-44-34Z).
        let avgStem = max(0, (stems.drumsEnergy + stems.bassEnergy
                              + stems.vocalsEnergy + stems.otherEnergy) * 0.25)
        nacreSpinEMA += (avgStem - nacreSpinEMA) * 0.03               // ~0.5 s — tracks the song's arc
        uni.spin = kNacreSpinGain * max(0, nacreSpinEMA - kNacreSpinFloor)

        // ── Downbeat camera push (NACRE.4) — the connection as VISIBLE MOTION ──
        // The detectable rhythm (the downbeat DID read in M7 — "the pulse is accurate") in a
        // medium that isn't brightness (flashes) or invisible (whole-field rotation): a sharp-
        // attack / bar-decay envelope on the cached BeatGrid's barPhase01 → the comp magnifies
        // the whole field on the downbeat (display-stage, no smear). Static on beatless tracks.
        uni.barPush = pow(max(0, 1 - features.barPhase01), 2.5)

        // ── Hue ← REAL harmony (TONAL.3, D-178) ──────────────────────────────────
        // Replaces the NACRE.3 centroid-deviation PROXY with the true Tonal Interval Vector
        // fifths phase. The palette now TRAVELS WITH THE HARMONY: related keys → related
        // colours (the circle of fifths, not the chromatic circle), holding on a vamp,
        // drifting on a modulation, and the same song transposed lands on shifted-but-related
        // colours. Hue never strobes (the Nacre anti-reference) — the fifths phase is a slow
        // harmonic signal, not per-beat energy.
        //   · Consonance gates the whole tonal coupling toward the neutral rest state, so
        //     silence / percussion / noise falls back to the faithful time rotation (D-019).
        //   · The fifths phase is circular-EMA'd as a unit vector (a circular mean, ~0.8 s)
        //     so modulations GLIDE — wrap-safe, unlike a scalar EMA across ±π.
        let tonalGate = max(0, min(1, (features.tonalConsonance - 0.05) / 0.03))  // analyzer atonal floor
        let fifthsVec = SIMD2<Float>(cos(features.tonalPhaseFifths), sin(features.tonalPhaseFifths))
        nacreFifthsVec += (fifthsVec - nacreFifthsVec) * 0.025                    // ~0.8 s circular smoothing
        let smoothedFifths = atan2(nacreFifthsVec.y, nacreFifthsVec.x)
        // Round 2: harmony SETS the hue position — the key you're in IS the colour (a POSITION
        // on the palette wheel), not a nudge on the clock. Round 1's `time + offset` let the
        // clock rotate the palette ~14× over a song while harmony only wobbled ±½ cycle, so
        // the coupling was invisible (M7 session 15-00-03Z: fifths swept the full range but the
        // palette read as the usual time rotation). Now the clock is DEMOTED to a slow drift
        // when tonal (harmony holds the hue on a vamp) and restored to the faithful full
        // rotation at silence/atonal — a continuous accumulator so the rate change never snaps.
        let harmonyAnchor = (smoothedFifths / (2 * .pi)) * kNacrePalettePeriod
        let driftRate = kNacreFaithfulRate + (kNacreTonalDriftRate - kNacreFaithfulRate) * tonalGate
        nacrePaletteDrift += features.deltaTime * driftRate
        uni.hueShift = harmonyAnchor * tonalGate + nacrePaletteDrift              // FULL palette phase

        // ── Saturation ← consonance (TONAL.3) ── atonal MUSIC desaturates toward the rest
        // state; SILENCE keeps the faithful palette (D-019 warmup must stay colourful — the
        // gate would otherwise wash out the certified silence look). Desaturate only when
        // there is energy AND consonance is low (percussion / noise dominated).
        let hasEnergy = max(0, min(1, (total - 0.03) / 0.05))       // 0 silence → 1 music
        let satFaithful = max(tonalGate, 1 - hasEnergy)             // 1 = faithful 0.20, 0 = desaturate
        uni.tonal.x = kNacreDesatAtonal + (kNacreDesatTonal - kNacreDesatAtonal) * satFaithful
        // (tonal_tension → rim dispersion is DEFERRED — it under-develops on a 30 s preview
        //  clip so the route-coverage fixtures can't exercise it; a round-2 lever. `tonal.y`
        //  stays at its 1.0 default.)

        let size = mvWarpDrawableSize
        let wPx = max(Float(size.width), 1), hPx = max(Float(size.height), 1)
        uni.texel = SIMD2<Float>(1.0 / wPx, 1.0 / hPx)
        // butterchurn aspect: the LONGER axis is normalised to 1, the shorter carries
        // the ratio — keeps the comp's sine-cell field round on a wide canvas.
        let aspectX: Float = wPx >= hPx ? hPx / wPx : 1
        let aspectY: Float = hPx > wPx ? wPx / hPx : 1
        uni.aspect = SIMD4<Float>(aspectX, aspectY, 1.0 / aspectX, 1.0 / aspectY)

        // Slow colour roam (the comp's subtractive `slow_roam_sin.wzy * roam_cos.zxy`).
        // Slow rates → a gentle desaturating drift; the *0.4 in-shader keeps it subtle.
        uni.slowRoamSin = SIMD4<Float>(0.5 + 0.5 * sin(tSec * 0.05),
                                       0.5 + 0.5 * sin(tSec * 0.08),
                                       0.5 + 0.5 * sin(tSec * 0.13),
                                       0.5 + 0.5 * sin(tSec * 0.22))
        uni.roamCos = SIMD4<Float>(0.5 + 0.5 * cos(tSec * 0.03),
                                   0.5 + 0.5 * cos(tSec * 0.05),
                                   0.5 + 0.5 * cos(tSec * 0.08),
                                   0.5 + 0.5 * cos(tSec * 0.11))
        return uni
    }

    // MARK: Draw branch

    /// Live entry point: render the Nacre frame to the drawable, then present. Thin
    /// wrapper over `renderNacre(target:)` so the live path and the diag harness run the
    /// EXACT SAME render code (FA #66 — no reimplemented test path).
    @MainActor
    func drawWithNacre(
        commandBuffer: MTLCommandBuffer,
        view: MTKView,
        features: inout FeatureVector,
        stemFeatures: StemFeatures,
        warpState: MVWarpState
    ) {
        guard let drawable = view.currentDrawable else { return }
        renderNacre(
            commandBuffer: commandBuffer,
            features: features,
            stemFeatures: stemFeatures,
            warpState: warpState,
            target: drawable.texture)
        commandBuffer.present(drawable)
    }

    /// Nacre feedback loop rendered into `target`: warp → signature comp (→ target) →
    /// swap. Target-agnostic so the live drawable path and the offscreen diag both call
    /// it identically.
    @MainActor
    func renderNacre(
        commandBuffer: MTLCommandBuffer,
        features: FeatureVector,
        stemFeatures: StemFeatures,
        warpState: MVWarpState,
        target: MTLTexture
    ) {
        var uni = computeNacreUniforms(features: features, stems: stemFeatures)

        // ── Warp pass: warp(prev, u) → composeTexture ─────────────────────────
        let wdesc = MTLRenderPassDescriptor()
        wdesc.colorAttachments[0].texture = warpState.composeTexture
        wdesc.colorAttachments[0].loadAction = .clear
        wdesc.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        wdesc.colorAttachments[0].storeAction = .store
        if let enc = commandBuffer.makeRenderCommandEncoder(descriptor: wdesc) {
            enc.setRenderPipelineState(warpState.warpPipeline)
            var feat = features
            enc.setVertexBytes(&feat, length: MemoryLayout<FeatureVector>.stride, index: 0)
            var stm = stemFeatures
            enc.setVertexBytes(&stm, length: MemoryLayout<StemFeatures>.stride, index: 1)
            var scene = getSceneUniforms()
            enc.setVertexBytes(&scene, length: MemoryLayout<SceneUniforms>.stride, index: 2)
            enc.setFragmentTexture(warpState.warpTexture, index: 0)
            enc.setFragmentBytes(&uni, length: MemoryLayout<NacreUniforms>.stride, index: 1)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 4278)  // 31×23 quads
            enc.endEncoding()
        }

        // ── Comp blit: signature(compose, u) → target (display-only) ──────────
        let cdesc = MTLRenderPassDescriptor()
        cdesc.colorAttachments[0].texture     = target
        cdesc.colorAttachments[0].loadAction  = .dontCare
        cdesc.colorAttachments[0].storeAction = .store
        if let enc = commandBuffer.makeRenderCommandEncoder(descriptor: cdesc) {
            enc.setRenderPipelineState(warpState.blitPipeline)
            enc.setFragmentTexture(warpState.composeTexture, index: 0)
            enc.setFragmentBytes(&uni, length: MemoryLayout<NacreUniforms>.stride, index: 1)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            enc.endEncoding()
        }

        // ── Swap: composeTexture becomes next frame's warpTexture ─────────────
        mvWarpLock.withLock {
            guard var state = mvWarpState else { return }
            swap(&state.warpTexture, &state.composeTexture)
            mvWarpState = state
        }
    }

    /// Reduced-motion (U.9 / a11y) Nacre frame into `target`: the signature comp of the
    /// CURRENT (un-advanced) feedback — NO warp pass, NO swap → no feedback accumulation,
    /// hence no motion. Target-agnostic (FA #66) so the live drawable path and a headless
    /// test drive the same code.
    ///
    /// This exists because the shared `drawMVWarpReducedMotion` renders a preset's DIRECT
    /// pipeline straight to the drawable, and Nacre's direct pipeline is compiled for its
    /// `.rgba16Float` feedback format — a 16-float pipeline → 8-bit drawable is an
    /// attachment-format mismatch that crashes (BUG-061). The comp (blit) pipeline is
    /// compiled for the drawable format, so routing reduced-motion Nacre through it is
    /// both crash-safe and the correct "static frame" the U.9 contract wants.
    @MainActor
    func renderNacreReducedMotion(
        commandBuffer: MTLCommandBuffer,
        features: FeatureVector,
        warpState: MVWarpState,
        target: MTLTexture
    ) {
        var uni = computeNacreUniforms(features: features, stems: .zero)   // static frame; no vocal pulse
        let desc = MTLRenderPassDescriptor()
        desc.colorAttachments[0].texture     = target
        desc.colorAttachments[0].loadAction  = .dontCare
        desc.colorAttachments[0].storeAction = .store
        guard let enc = commandBuffer.makeRenderCommandEncoder(descriptor: desc) else { return }
        enc.setRenderPipelineState(warpState.blitPipeline)        // nacre_comp (drawable format)
        enc.setFragmentTexture(warpState.warpTexture, index: 0)   // current feedback, NOT advanced
        enc.setFragmentBytes(&uni, length: MemoryLayout<NacreUniforms>.stride, index: 1)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
    }
}
