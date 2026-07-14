// AuroraVeil.metal — Direct-fragment ambient ribbon preset.
//
// **AV.2.h (2026-05-19) — Three-Channel curation.** Matt's feedback on
// session `2026-05-19T22-49-41Z` ("first 40 s works better; after that
// the programming is muddled") triggered a design pivot away from the
// 8-route maximally-coupled state of AV.2.2g. The first 40 s of any
// track is the stem-cache pre-warmup window where most routes are
// gated off (stems sit at static cached values below their thresholds);
// post-warmup all 8 routes wake up simultaneously and visually compete.
// The fix isn't more tuning — it's curating the route set.
//
// Three musical features → three independent visual axes, no
// competition. The other 5 audio routes are removed.
//
//   1. Vocals melody  → ribbon HUE (palette baseOffset, slow walk)
//   2. Bass transients → BRIGHTNESS pulse (gated, smoothstep(0.30, 0.55))
//   5. Drum events    → curtain KINK (rare-event gated, 0.90/1.50)
//
// Routes dropped from AV.2.2g:
//   3 — fold density (mid → noise spatial frequency): every-frame
//       modulation that morphed the noise field; was contributing to
//       the "muddled" reading
//   4 — drift speed (bass → noise rotation rate): redundant with the
//       brightness route's bass coupling; one primitive per axis (FA #67)
//   6 — valence palette warm/cool: slow tilt that competed with the
//       vocals-pitch hue route for the palette baseOffset axis
//   7 — star twinkle (beat_phase01 gated by pitch confidence): an
//       additional beat-coupled signal that added noise without anchoring
//       a distinct musical feature
//   8 — synth flash (other_energy_dev → palette baseOffset): added a
//       second hue-axis driver that competed with route 1
//
// AV.2.2 (2026-05-18): mv_warp pass DROPPED. The empirical
// `AuroraVeilMVWarpAccumulationTest` (env-gated) demonstrated that mv_warp
// at the design parameters (decay 0.945, curl-noise advection 0.005 UV)
// washes out ALL high-frequency content over its ~17-frame decay window:
// 0 stars / sky-max-luma 0.39 / smeared blobs after 60 frames at silence,
// matching the live-session bug Matt reported in sessions
// `2026-05-18T21-44-14Z` and `2026-05-18T22-17-36Z`. With mv_warp OFF:
// 115 crisp stars / sky-max-luma 0.96 / clean rendering matching the
// reference photos. The references (`01` / `02` / `03` / `04`) show
// static curtains with slow internal drift — NOT persistence trails;
// mv_warp was producing the wrong character for this preset. The
// triangular-noise field's own time-driven rotation (0.10 rad/s × time)
// provides the slow drift the design §5.4 substrate-row asked for.
//
// AV.2 — Multi-column raymarch + audio routing. Three implicit drift columns
// at off-thirds horizontal positions establish multi-curtain parallax depth
// (foreground at uv.x, mid-ground at uv.x + 0.27, background at uv.x - 0.18),
// with per-column depth-scale dimming. The seven audio routes from
// AURORA_VEIL_DESIGN.md §5.7 layer on top:
//
//   1. Hue along ribbon  ← stems.vocals_pitch_hz (smoothed CPU-side, §5.7)
//   2. Brightness breath ← f.bass_att_rel (D-019-blended with stems)
//   3. Fold density     ← f.mid_att_rel  (D-019-blended with stems)
//   4. Drift speed       ← f.bass_att_rel (substrate spd argument)
//   5. Curtain kink      ← kinkAccumulator (rare-event gated on drums_energy_dev)
//   6. Palette warm/cool ← f.valence (additive palette phase)
//   7. Star twinkle      ← f.beat_phase01 gated by vocals_pitch_confidence
//
// Continuous primaries (routes 1, 2, 3, 4, 6, 7-when-confident) dominate the
// gated rare-event kink (route 5) by ≥ 10× per the §5.7 / Audio Data
// Hierarchy contract. Validated by `AuroraVeilContinuousDominanceTest`.
//
// AV.1 (single column, silence-stable, no audio routing) is preserved as the
// foreground column with topness/phaseRate/baseOffset stratification intact;
// AV.2 wraps it in a 3-column loop and threads the audio routes through.
//
// CLEAN-ROOM MSL reimplementation of the procedural-aurora recipe described in:
//   - nimitz, "Auroras," Shadertoy XtGGRt (2017) — triangular-noise
//     volumetric raymarch + running-average smear + per-march-step palette
//     cycling. ALGORITHM ADOPTED; CC-BY-NC-SA Shadertoy source NOT
//     incorporated. Algorithm is reimplemented from the published
//     descriptions in docs/presets/AURORA_VEIL_RESEARCH_2026-05-18.md §1.1
//     + Roy Theunissen's algorithm breakdown (cited there).
//   - Lawlor & Genetti, "Interactive Volume Rendering Aurora on the GPU"
//     (WSCG 2011) — height-curve × 2D flux-map factorization (the per-
//     march-step sin() palette IS the Lawlor H(z) curve).
//
// Authoritative design: docs/presets/AURORA_VEIL_DESIGN.md §5 (amended
//                        2026-05-18) + §5.7 audio routing.
// Research dossier: docs/presets/AURORA_VEIL_RESEARCH_2026-05-18.md §3.x.
// Architecture contract: docs/VISUAL_REFERENCES/aurora_veil/
//                        Aurora_Veil_Rendering_Architecture_Contract.md.
// Reference set: docs/VISUAL_REFERENCES/aurora_veil/ (4 must-pass + anti-ref).
//
// Anti-reference: 09_anti_neon_festival_aurora.jpg. The rendered output
// must NOT read like that image — pure-saturation neon, no green base,
// no vertical stratification, kinetic ribbons converging to a focal
// point. If it does, the preset is uncertified by definition.
//
// Rubric profile: lightweight (D-067(b)) — emission-only direct
// fragment, exempt from M1 detail cascade and M3 material count gates.
// L1-L4 ladder applies. 9-question authenticity rubric in
// AURORA_VEIL_RESEARCH_2026-05-18.md §2.3 is the AV.3 cert gate.
//
// Per-march-step `sin(float(i) * phaseRate + baseOffset)` is NOT a Failed
// Approach #33 violation: `i` is a march-loop index, not a temporal
// accumulator. The palette evaluation is per-fragment-per-frame and
// produces a static colour-stratification curve; motion comes from
// `aurora_tri_noise_2d`'s time argument + mv_warp accumulation + audio
// routes, not from this `sin()`. See prompts/AV.1-prompt.md §AV-sin.

// ── Constants ─────────────────────────────────────────────────────────────────

constant int   kAuroraSteps      = 50;
// Substrate drift speed base (per AURORA_VEIL_DESIGN.md §5.7 route 4 — the
// effective rate is `kAuroraDriftSpeedBase + 0.04 × bassRel`).
constant float kAuroraDriftSpeedBase = 0.06;
constant float kAuroraDriftSpeedGain = 0.04;
// Aurora final gain. Design §5.2 specifies 1.8; bumped to 2.4 at AV.1 so the
// aurora's green-palette contribution dominates the sky's blue cast at the
// test sample points (uv.y=0.25 and 0.65 in the brightest column). Within
// the design budget — Tier 1 still well under 4.0 ms per §7.
// AV.5: raised 2.4 → 3.3 to compensate for the footprint's average dimming (the
// cluster×bands mask multiplies emission down); cluster cores now read bright
// against the negative space, and the bass-brightness route regains its
// observable mean-luma span (AuroraVeilContinuousDominanceTest).
constant float kAuroraGain       = 3.3;

// ── AV.3 (2026-07-14, Matt) — authentic aurora MOTION (the "dance") ──────────
//
// Matt M7: the AV.2.h aurora reads as the RIGHT look but too STATIC — it only
// has the nimitz field's slow whole-field rotation. Real aurora dances via
// (grounded in aurora-motion research 2026-07-14, Alaska GI / NOAA SWPC):
//   • traveling waves ALONG the arc — "like a hand run along a curtain," the
//     wave sweeps sideways;  • the sheet FOLDS/undulates;  • RAYS flicker;
//   • the whole curtain PULSATES in brightness.
// We add a traveling-ripple warp to the noise sample: a horizontal ray
// displacement that varies with altitude and travels over time (the curtain
// waves like fabric), plus a small altitude fold that travels along x. It is a
// TRAVELLING SUBSTRATE WAVE (same category as the allowed `mm2(time*0.10)`
// rotation — coherent field motion, not decorative free sin(time)), and its
// amplitude is audio-gated (motionAmp) so it surges with the music and settles
// (to a gentle base) when the music thins. NOT mv_warp (no persistence smear,
// AV.2.2 lesson stands).
constant float kAuroraWaveAmp    = 0.055;  // curtain ripple: horizontal ray sway (UV)
constant float kAuroraWaveFreqY  = 3.2;    // ripples per unit altitude (vertical wavelength)
constant float kAuroraWaveFreqX  = 2.4;    // fold wavelength along the arc
constant float kAuroraWaveSpeed  = 0.85;   // wave travel speed along the curtain
constant float kAuroraFoldAmp    = 0.22;   // altitude-fold amplitude (sheet undulation)
constant float kAuroraMotionBase = 0.35;   // motion amplitude at silence (gently alive)
constant float kAuroraMotionGain = 0.65;   // additional amplitude from mid activity
// CURTAIN-BAND undulation — the dominant visible dance. The internal noise
// warp averages out over the 50-step integration, so the BAND itself must
// undulate: a traveling vertical wave of x lifts/folds the whole curtain
// across the sky. This is what actually reads as "dancing" frame-to-frame.
constant float kAuroraBandWaveAmp = 0.10;  // vertical undulation of the band (UV)
constant float kAuroraBandFreq    = 4.5;   // undulations across screen width

// ── AV.4 SPIKE (2026-07-14) — Lawlor footprint F(x) + Wittens curl motion ────
// The reauthor's core: aurora emission = H(z) × F(x,y) (Lawlor). The old code
// collapsed F(x,y) to FULL-FIELD noise (bright everywhere → the wash). Here
// F(x) is a real FOOTPRINT — bright only along a few meandering bands, dark
// between (negative space) — multiplied into the nimitz H(z)×texture so the
// authentic look is kept while discrete curtains emerge. The footprint is
// advected by curl_noise (Wittens vortical plasma motion, audio-scaled) so the
// curtains DANCE with real curling flow, not sine-panning. Feasibility spike:
// prove this reads as draping dancing curtains before the full reauthor.
// Two-scale footprint (AV.5): a low-freq CLUSTER envelope carves big dark-sky
// regions (aurora concentrates in a few areas, refs 05/06); a mid-freq BAND
// pattern defines individual draped curtains WITHIN the clusters. Curtains
// appear only where cluster AND band agree → a few grouped curtains, dominant
// negative space, not an even picket of rays.
constant float kClusterFreq        = 1.1;   // large-scale: 2-3 bright regions across the frame
constant float kClusterLo          = -0.06; // below → dark-sky region (big negative space)
constant float kClusterHi          = 0.12;  // above → inside a cluster (saturates → bright cores)
constant float kFootprintFreq      = 2.5;   // band freq WITHIN a cluster → distinct curtains
constant float kFootprintCurlAmp   = 0.35;  // curl advection strength (the dance)
constant float kFootprintContrast  = 2.1;   // widen fbm8 dynamic range so gaps go truly dark
constant float kFootprintLo        = -0.05; // below → dark gap between curtains
constant float kFootprintHi        = 0.15;  // above → full curtain brightness
// Smooth ALTITUDE SHEAR — the curtain leans and curves as it rises so it drapes
// instead of standing as a dead-straight bar. Analytic (NOT noise: vertical
// noise here chops the coherent rays into horizontal clumps, FM #3/#8). The
// footprint noise stays 1D-in-x (coherent vertical rays); only x is sheared by
// altitude + curl-advected, so curtains curve and drift while staying coherent.
constant float kFootprintShearAmp  = 0.55;  // horizontal lean over the curtain's height (visible curve)
constant float kFootprintShearFreq = 2.3;   // vertical wavelength of the lean/fold

// ── Multi-column geometry (AV.2) ─────────────────────────────────────────────
//
// Three implicit drift columns at off-thirds horizontal positions per
// design §5.5 — `uv.x` (foreground), `uv.x + 0.27` (mid-ground), `uv.x - 0.18`
// (background). Off-thirds rather than symmetric so the composition reads
// as asymmetric ribbons-at-distance (Failure Mode #9 avoided).
//
// Depth scales dim each column proportional to its perceived distance from
// camera. Foreground depth = 1.0 (brightest); background = 0.5 (dimmest).
// Reference `04_atmosphere_multi_curtain_parallax.jpg` shows three ribbons
// with this depth-ordered brightness pattern.
//
// AV.2.1 (2026-05-18): per-column drift-velocity differential dropped. The
// AV.2 design's "parallax illusion of depth via differential drift speed"
// idea (background rotating at 0.55× foreground rate, etc.) compounded
// badly with mv_warp's ~1 s persistence trail: each pixel's "winner"
// column (after the MAX-merge of the three columns' noise samples) shifted
// over time as the columns drifted at different rates, and mv_warp
// accumulated those shifts into a painterly smear that destroyed the
// nimitz vertical-streak ribbon character. Reference photos `01` and `04`
// show depth separation via horizontal position + atmospheric perspective
// (depth-scale dimming), NOT via differential motion — still frames don't
// encode velocity differentials anyway. Live session 2026-05-18T21:44:14Z
// confirmed: with the velocity differential, even silence renders as
// smeared green clouds with no readable ribbons + washed-out stars; the
// fix restores ribbon character without losing the multi-column horizontal
// distinction.

constant int    kAuroraColumns        = 3;
constant float4 kAuroraColumnOffsets  = float4( 0.00,  0.27, -0.18, 0.0);
constant float4 kAuroraColumnDepths   = float4( 1.00,  0.70,  0.50, 0.0);

// ── Audio routing constants (AV.2 — design §5.7) ─────────────────────────────

// D-019 stem-warmup blend window. `totalStemEnergy` < 0.02 → FV proxy only;
// > 0.06 → stems only. Matches Gossamer.metal:130 verbatim.
constant float kStemWarmupLow  = 0.02;
constant float kStemWarmupHigh = 0.06;

// Route 1 — vocal pitch palette phase. AV.2.2c (2026-05-19): amplitude
// reduced 1.6 → 0.8 after live session 2026-05-19T01-12-47Z showed the
// hue migration shifting visibly per-frame; halving slows the migration
// to "Sigur-Rós-slow" perceived rate (~half an IQ palette cycle across
// the 4-octave singing range).
constant float kVocalsPitchAmp = 0.8;

// Route 2 — brightness breathing. AV.2.2c reduced amplitude 0.30 → 0.15;
// AV.2.2d restored to 0.30 after switching primitive to positive-only
// `bass_dev`. AV.2.2e (2026-05-19) adds a smoothstep threshold-gate on
// top — live session 2026-05-19T21-30-32Z showed `stems.bass_energy_dev`
// > 0.2 fires on 60.2 % of frames during Billie Jean, so the unfiltered
// route modulated brightness continuously and read as "uncoordinated"
// rather than "pulsing with the music." The gate (lo 0.3 / hi 0.55) lets
// only the larger transients through (~16 % of frames at 0.3, ~4 % at
// 0.55) so brightness clearly pulses on bass events and settles to base
// between them.
constant float kBrightnessBase    = 0.85;
// AV.5: amp 0.30 → 0.42 and gate lowered (0.30/0.55 → 0.18/0.50) so the
// bass-breathing route is visible against the sparser footprint band (most of
// the band is now negative space; the route needs more range + an earlier onset
// to clear the dominance-test's observable-span floor and to read on real music).
constant float kBrightnessAmp     = 0.48;
constant float kBrightnessGateLo  = 0.18;
constant float kBrightnessGateHi  = 0.50;

// Route 3 — fold density: REMOVED (AV.2.h). Was an every-frame modulator
// of the noise spatial frequency, which morphed the entire noise field
// per frame. Contributed to the "muddled" reading post-warmup.

// Route 5 — curtain kink. AV.2.h (2026-05-19): kink gate thresholds raised
// to 0.90 / 1.50 (CPU-side in `AuroraVeilState`) for genuinely rare-event
// firing — observed `drumsEnergyDev` distribution on heavy-drum music
// (Outkast / Foo Fighters) extended past 0.6, so the prior 0.6/0.9 gate
// fired 8.9 % of frames (not rare). 0.90/1.50 limits firing to ~1-3 % on
// heavy-drum music, ~0.5 % on lighter material — matches the "1-2 s slow
// shudder on rare drum emphasis" design intent (§5.6 + research §3.2).
constant float kKinkAmp         = 0.0015;
constant float kKinkSpatialFreq = 12.0;

// AV.3 — half-bar star blink (Matt's explicit request). Reverses AV.2.h's
// route-7 removal. See the blink block in the fragment for the mechanism.
constant float kStarBlinkAmp    = 0.70;   // additive per-star brightness index
constant float kStarBlinkDecay  = 6.0;    // blink attack sharpness (higher = snappier)

// Routes 4 (drift speed), 6 (valence palette), 7 (star twinkle), 8 (synth
// flash) REMOVED in AV.2.h — see header docstring for rationale.

// (Route 7 star-twinkle confidence-gate constant retained at module scope
// even though the route is removed — its threshold value 0.5 doubles as
// the gate threshold for Route 1's pitchConfident check, which is still
// active and now actually fires post-PT.1.)

// Route 7 — star twinkle. 30 % amplitude per-star brightness modulation,
// gated by `vocals_pitch_confidence > 0.5` (the gate is in shader, not here).
// kStarTwinkleAmp removed (route 7 dropped).
// kStarTwinkleConfGate removed; pitchConfident now uses the literal 0.5
// inline.

// ── GPU state buffer (AV.2 — Path B per prompts/AV.2-prompt.md §AV-kink) ─────
//
// Persistent state lives CPU-side in `AuroraVeilState.swift` and is flushed
// each frame to a 16-byte buffer bound at fragment buffer(6). Two persistent
// values cross frames:
//   - kinkAccumulator: drum-coupled rare-event charge (decays at ~0.93/frame)
//   - smoothedPitchNorm: 5-frame moving average of normalized vocal pitch
//
// Byte layout must match `AuroraVeilStateGPU` in AuroraVeilState.swift.
struct AuroraVeilStateGPU {
    float kinkAccumulator;
    float smoothedPitchNorm;
    float _pad0;
    float _pad1;
};

// ── Triangular domain-warped noise (clean-room from research §1.1) ───────────
//
// `aurora_tri`  — triangular waveform; clamped to [0.01, 0.49] so the final
//                 `1 / pow(rz * 29, 1.3)` clamp never divides by zero. The
//                 sharp slopes of the triangle are what give aurora its
//                 sharp ribbon edges — substituting Perlin or fBM here is
//                 Failure Mode #8 (pillow noise) and Failed Approach #65
//                 (do not subtract from the reference recipe).
// `aurora_tri2` — 2D triangle noise with cross-coupling. Two-component
//                 output is consumed by the domain-warp step.
// `aurora_mm2`  — 2D rotation matrix; used per-octave to produce biological
//                 asymmetry (without the recursive rotation, the noise field
//                 is statistically uniform and ribbons read as a tiling).

static inline float aurora_tri(float x) {
    return clamp(abs(fract(x) - 0.5), 0.01, 0.49);
}

static inline float2 aurora_tri2(float2 p) {
    return float2(aurora_tri(p.x) + aurora_tri(p.y),
                  aurora_tri(p.y + aurora_tri(p.x)));
}

static inline float2x2 aurora_mm2(float a) {
    float c = cos(a);
    float s = sin(a);
    return float2x2(c, -s, s, c);
}

// Five octaves of domain-warped triangular noise. `spd` is the per-octave
// rotation rate; nimitz uses 0.06 as the default. AV.2.1 dropped the
// per-column `velocityScale` parameter that AV.2 introduced — see the
// AV.2.1 comment block above on `kAuroraColumnOffsets` for the rationale.
// All columns now share the same noise-field rotation rate; depth
// distinction comes from horizontal sample position + per-column depth
// scaling. Returns a positive scalar density in [0, 0.55] that reads as
// "where the curtain is bright at this (xz) location at this time."
//
// Rotation rate note: nimitz's literal `mm2(time * 0.5)` runs the substrate
// drift at ~30s per full rotation, which is faster than the §5.4 design
// target "tens of seconds (substrate drift): curtain undulation, ribbon
// evolution." More importantly, at the PresetAcceptance harness's fixture
// time deltas (1.0 → 3.0 → 5.0, Δt=2s), a 0.5 rad/s rotation moves noise
// features by ~30 % of frame between fixtures, producing pixel-MSE
// differences that exceed the beat-response invariant `beatMotion <=
// continuousMotion * 2.0 + 1.0`. Reduce the base rotation rate to 0.10
// (full rotation in ~60s); the per-octave `dg` rotation by `spd` stays as
// designed.
static inline float aurora_tri_noise_2d(float2 p, float spd, float time) {
    float2 bp = p;
    bp = aurora_mm2(time * 0.10) * bp;
    float z  = 1.8;
    float z2 = 2.5;
    float rz = 0.0;
    for (int i = 0; i < 5; i++) {
        float2 dg = aurora_tri2(bp * 1.85) * 0.75;
        dg = aurora_mm2(time * spd) * dg;
        bp -= dg / z2;
        bp = aurora_mm2(-time * 0.10) * bp;
        rz += (aurora_tri(bp.x) + aurora_tri(bp.y)) * z;
        bp *= 1.3;
        z  *= 0.42;
        z2 *= 0.45;
    }
    return clamp(1.0 / pow(rz * 29.0, 1.3), 0.0, 0.55);
}

// Per-column raymarch helper. Walks the polynomial-stepped altitude column
// rooted at `columnUVx` (the audio-kinked, column-offset horizontal anchor)
// and accumulates the exp-decay-weighted running-average IQ-palette × noise
// product. Returns the column's emission contribution before depth-scale
// dimming.
//
// Parameters:
//   columnUVx     — anchor horizontal noise coordinate (uv.x + offset + kink)
//   uv_y          — fragment screen y (for the Lawlor stratification curve)
//   driftSpeed    — bass-modulated `spd` argument to `aurora_tri_noise_2d`
//   foldScale     — mid-modulated noise spatial frequency multiplier
//   paletteOffset — sum of vocals-pitch + valence palette additive offsets
//   time          — `f.time`
static inline float3 raymarch_column(
    float columnUVx,
    float uv_y,
    float driftSpeed,
    float foldScale,
    float paletteOffset,
    float motionAmp,
    float time
) {
    float topness     = 1.0 - smoothstep(0.05, 0.55, uv_y);
    float phaseRate   = mix(0.005, 0.043, topness);
    // Per-fragment baseOffset = AV.1 Lawlor stratification term (topness ×
    // 2.0) + AV.2 vocals/valence additive offset. Topness dominates so the
    // green-base / magenta-crown gradient is preserved; routes 1 + 6
    // perturb the phase within the gradient.
    float baseOffset  = 2.0 * topness + paletteOffset;

    // NOTE (AV.5): the Lawlor footprint F(x) is applied ONCE in screen space in
    // the fragment (aurora_footprint), AFTER the multi-column MAX — not per
    // column. Applying it per column let the 3-column MAX fill the gaps the
    // footprint carves (three shifted footprints OR'd ≈ full coverage). A single
    // screen-space mask gives all columns the same negative space, and costs one
    // fbm8+curl per fragment instead of three. The columns now only supply
    // horizontal parallax + depth dimming WITHIN the lit regions.

    float4 avgCol = float4(0.0);
    float3 col    = float3(0.0);
    for (int i = 0; i < kAuroraSteps; i++) {
        // Polynomial step distance — dense at low altitudes (where stratification
        // is sharpest), coarser at high altitudes (diffuse red crown).
        float pt = 0.8 + pow(float(i), 1.4) * 0.002;

        // AV.3 — authentic aurora MOTION (the "dance"). Traveling curtain wave:
        // the horizontal ray position sways by an amount that varies with
        // altitude and TRAVELS over time → the vertical rays ripple like fabric
        // and the wave sweeps along the curtain ("a hand run along the
        // curtain"). A second, slower term folds the altitude along the arc so
        // the sheet undulates. Two summed sines (not one) → organic, not
        // metronomic. Amplitude = motionAmp (audio-gated; gentle base at
        // silence). This is coherent SUBSTRATE motion, audio-scaled — the same
        // category as the field's `mm2(time*0.10)` rotation, not decorative
        // free sin(time) (FA #33).
        float ripple = sin(pt * kAuroraWaveFreqY - time * kAuroraWaveSpeed + columnUVx * 1.7) * 0.6
                     + sin(pt * kAuroraWaveFreqY * 1.9 - time * kAuroraWaveSpeed * 1.4) * 0.4;
        float xWarp  = kAuroraWaveAmp * motionAmp * ripple;
        float ptFold = pt + kAuroraFoldAmp * motionAmp
                     * sin(columnUVx * kAuroraWaveFreqX - time * kAuroraWaveSpeed * 0.55);

        // 2D triangular domain-warped noise. Sample plane: (warped column
        // anchor × foldScale, folded altitude × foldScale). Fold scale
        // multiplies BOTH dimensions.
        float rzt = aurora_tri_noise_2d(
            float2((columnUVx + xWarp) * foldScale, ptFold * foldScale),
            driftSpeed, time);

        // Per-march-step IQ-cosine palette (the Lawlor H(z) curve). Both
        // `phaseRate` and `baseOffset` are static-or-slowly-varying functions
        // of screen-y + audio (no high-frequency time dependence), so this is
        // not a Failed Approach #33 violation. The palette is still cycling
        // per-i (running-average smear has variation to smear) — the cycling
        // is just throttled toward the lower aurora edge so the integration's
        // exp-decay weight peak stays in the green region.
        float3 col2 = (sin(1.0 - float3(2.15, -0.5, 1.2)
                           + float(i) * phaseRate
                           + baseOffset) * 0.5 + 0.5) * rzt;

        // Running-average vertical smear (research §1.1 line 6 — load-bearing).
        // Without this, adjacent altitudes don't blur and the column reads as
        // volumetric salt-and-pepper. With it, samples coalesce into vertical
        // ribbon streaks.
        avgCol = mix(avgCol, float4(col2, rzt), 0.5);

        // Exponential decay accumulator. Early steps (low altitude, green
        // base) contribute most; smoothstep avoids hard cutoff at i=0.
        col += avgCol.rgb
             * exp2(-float(i) * 0.065 - 2.5)
             * smoothstep(0.0, 5.0, float(i));
    }
    return col * kAuroraGain;
}

// ── Lawlor footprint F(x) — screen-space curtain mask (AV.5) ─────────────────
//
// The auroral oval is bright only along a few meandering curtain bands; between
// them is dark sky (negative space). This is the structural fix vs the wash: the
// old model's F(x,y) was full-field (bright everywhere). Applied ONCE in screen
// space (over the whole aurora, after the column MAX) so the negative space is
// shared across columns.
//
// Kept 1D-in-x so the vertical rays stay coherent top-to-bottom (2D-noise here
// chops them into horizontal fog, FM #3/#8). The DRAPE comes from a smooth
// altitude shear that leans/curves x as the curtain rises; curl-noise advection
// (Wittens vortical flow, audio-scaled by motionAmp) drifts and curls the whole
// silhouette — the dance. Contrast-widened before the threshold so gaps go truly
// dark (real negative space), never a dim ramp wash. Colour is untouched — the
// footprint only decides WHERE the aurora hangs (research §1.2: no altitude in
// the palette noise; H(z) stays indexed by world-y in the march).
static inline float aurora_footprint(float uv_x, float uv_y, float motionAmp, float time) {
    float2 curlAdv = curl_noise(float3(uv_x * 1.6, time * 0.12, 0.0)).xy
                   * (kFootprintCurlAmp * motionAmp);

    // Large-scale cluster envelope — a few broad bright regions, big dark sky
    // between (drifts slowly). Low freq, 4 octaves (doesn't need hero detail).
    float cluster = smoothstep(kClusterLo, kClusterHi,
                       fbm4(float3(uv_x * kClusterFreq + curlAdv.x * 0.5, 7.1, time * 0.03)));

    // Individual curtain bands within a cluster, sheared by altitude so each
    // curtain leans/curves as it rises (drape). curlAdv adds vortical drift.
    float shear   = kFootprintShearAmp
                  * sin(uv_y * kFootprintShearFreq + curlAdv.y * 4.0 + uv_x * 2.0);
    float fpx     = uv_x * kFootprintFreq + curlAdv.x + shear;
    float bands   = smoothstep(kFootprintLo, kFootprintHi,
                       fbm8(float3(fpx, 11.3, time * 0.05)) * kFootprintContrast);

    return cluster * bands;
}

// ── Fragment ──────────────────────────────────────────────────────────────────

fragment float4 aurora_fragment(
    VertexOut                       in     [[stage_in]],
    constant FeatureVector&         f      [[buffer(0)]],
    constant float*                 fft    [[buffer(1)]],
    constant float*                 wv     [[buffer(2)]],
    constant StemFeatures&          stems  [[buffer(3)]],
    constant AuroraVeilStateGPU&    av     [[buffer(6)]]
) {
    (void)fft; (void)wv;

    float2 uv   = in.uv;
    float  time = f.time;  // monotonic wall-clock; silence-stable drift.

    // ── D-019 stem-warmup blend (matches Gossamer.metal:127–135) ──────────────
    // Mix FeatureVector proxies → stem-deviation primitives as total stem
    // energy climbs through [0.02, 0.06]. Pre-warmup (and at silence): the
    // stem-side reads contribute zero; routes 2-4 fall back to the FV
    // deviation primitives. Post-warmup: stems dominate and the routes
    // respond to per-stem energy.
    float totalStemEnergy = stems.vocals_energy + stems.drums_energy
                          + stems.bass_energy   + stems.other_energy;
    float stemMix = smoothstep(kStemWarmupLow, kStemWarmupHigh, totalStemEnergy);

    // Route 2 + Route 4 — bass-driven brightness + drift speed.
    //
    // AV.2.2d (2026-05-19): switched from `bass_att_rel` to `bass_dev` after
    // live session 2026-05-19T21-05-33Z showed bassAttRel sat structurally
    // negative (mean −0.586, max +0.054) on real music — the route ran
    // entirely in its dim-half, brightness barely modulated upward. Root
    // cause: AGC normalises full-mix bass to ~0.21 mean on rock/hip-hop,
    // so `bass_att_rel = 2 × bass_att − 1 ≈ −0.58` typical. The deviation
    // primitive `f.bass_dev` = max(0, bassRel) is the right shape — fires
    // only when the instantaneous bass band crosses its running average,
    // i.e., on actual transients. Same for `stems.bass_energy_dev`. Both
    // are positive-only; the brightness route now goes UP on bass, never
    // down (matches "breathing" intuition).
    float bassDev = mix(f.bass_dev, stems.bass_energy_dev, stemMix);

    // Route 1 — vocal-pitch normalized + smoothed (CPU-side via AuroraVeilState).
    // Confidence-gated: when YIN/CREPE confidence < threshold (silence,
    // unvoiced, or pre-stems), fall back to the mid-palette neutral 0.5 baseline
    // so the route is silence-stable per §5.8. When confident, consume the
    // smoothed value from the state buffer (5-frame moving average per §5.7).
    // PT.1 (2026-05-19) fixed the upstream PitchTracker ring-buffer bug;
    // before that, pitchConfidence was 0 % across every session and this
    // gate kept pitchNorm at the 0.5 fallback always.
    float pitchConfident = step(0.5, stems.vocals_pitch_confidence);
    float pitchNorm = mix(0.5, av.smoothedPitchNorm, pitchConfident);

    // Route 1 only — paletteOffset is the single palette-axis driver after
    // AV.2.h's curation (route 6 valence + route 8 synth-flash both
    // dropped to keep one primitive per visual axis).
    float paletteOffset = (pitchNorm - 0.5) * kVocalsPitchAmp;

    // Drift speed + fold density are constants in AV.2.h — routes 4 and 3
    // dropped to reduce the per-frame noise-field morphing that was
    // contributing to the "muddled" reading. Substrate drift comes from
    // the noise field's own time-driven rotation inside
    // `aurora_tri_noise_2d` (the nimitz recipe).
    float driftSpeed = kAuroraDriftSpeedBase;
    float foldScale  = 1.0;

    // AV.3 — MOTION amplitude (the dance). Continuous mid-band activity drives
    // how vigorously the curtains ripple/fold: gentle base at silence, surging
    // when the music's harmonic body is busy. `mid_att_rel` is the free FV
    // primitive (bass=brightness, vocals=hue, drums=kink) and is Layer-1
    // continuous energy — zero delay, live from frame 1, no stem warmup (there
    // is no `mid` stem; mid is a frequency band). One primitive per axis.
    float midActivity = saturate(0.5 + 0.5 * f.mid_att_rel);
    float motionAmp   = kAuroraMotionBase + kAuroraMotionGain * midActivity;

    // Route 5 — curtain kink (fragment-space lateral UV jitter on the column
    // noise sample). Path B per prompts/AV.2-prompt.md §AV-kink: CPU-side
    // AuroraVeilState rare-event-gates and decays kinkAccumulator each frame
    // (`max(prev * 0.93, drumsDev * smoothstep(0.4, 0.7, drumsDev))`); the
    // shader reads the result via buffer(6) and applies a lateral shudder
    // that varies along screen-y (sin(uv.y × 12)) — a vertical wave running
    // through the column, decaying with the same 1-2 s timescale as the
    // accumulator.
    //
    // Per design §5.6 the effect is mv_warp y-displacement; mvWarpPerFrame
    // can't read slot 6 without engine plumbing, so we apply an equivalent
    // visual effect inside the fragment (the lateral UV jitter perturbs the
    // noise column slightly, producing a side-to-side shudder that reads as
    // a curtain kink). This is fragment-space jitter on column UV (Failed
    // Approach safe — fragment-space deformation on an active subject is
    // explicitly OK per D-094 scope clarification; the column is not
    // architecture-permanent geometry).
    float kinkAmp = av.kinkAccumulator * kKinkAmp;

    // ── Layer 1: Sky gradient + sparse pinpoint stars ────────────────────────
    // Phosphene UV: uv.y=0 = top of frame (deep night sky); uv.y=1 = bottom
    // (slightly warmer near horizon). Stars: hash_f01_2 thresholded > 0.997
    // ~0.3% pixel coverage — sparse pinpoints, not procedural texture.
    //
    // Sky blue cast trimmed vs design §5.2 (top B 0.020 → 0.010; bottom B
    // 0.040 → 0.020). The design values produced a sky bluer than the aurora
    // was green at the silence-test sample points, which contradicts both the
    // physical reference (real aurora photos: sky is near-black; only the
    // aurora carries chromatic signal) and the L2 stratification gate
    // (lower-band G > B). Refs 01 / 04 confirm the trimmed values.
    float3 topColor    = float3(0.005, 0.005, 0.010);
    float3 bottomColor = float3(0.008, 0.010, 0.020);
    float3 sky = mix(topColor, bottomColor, uv.y);

    float starField = hash_f01_2(uv * 800.0);
    float starHit   = step(0.997, starField);
    float starShade = hash_f01_2(uv * 800.0 + float2(11.7, 5.3));

    // AV.3 — half-bar star blink (Matt M7: "stars blink with some connection
    // to the beat — every half bar"). Layer-4 accent on the CACHED grid.
    // `f.bar_phase01`: 0 at downbeat → 1 at next downbeat, so half-bar ticks
    // sit at phase 0.0 and 0.5 and `fract(bar_phase01 * 2)` is 0 at each.
    // Per-star staggered phase (starShade offset) → stars brighten around the
    // tick on their own offsets, never a unison flash, so global luminance
    // stays steady (D-157, flash-safe; the blink is purely ADDITIVE — stars
    // never dim below base). Amplitude fades in with stemMix so the cold-start
    // window (bar_phase01 is drift-corrected → phase may be wrong) doesn't fire
    // loud off-beat blinks at track start.
    float halfBarPhase = fract(f.bar_phase01 * 2.0);
    float starTick     = fract(halfBarPhase + starShade);
    float starBlink    = exp(-starTick * kStarBlinkDecay);
    float blinkGain    = 1.0 + kStarBlinkAmp * starBlink * stemMix;
    sky += float3(0.85, 0.92, 1.0) * starHit * (0.40 + 0.60 * starShade) * blinkGain;

    // ── Layer 2: Multi-column volumetric aurora raymarch ─────────────────────
    // Per design §5.5: three implicit drift columns at off-thirds horizontal
    // positions establish multi-curtain parallax depth. Per-column noise
    // sample uses a lateral kink offset (route 5) and a per-column horizontal
    // anchor; the combined accumulator is MAX over columns ("the ribbon you
    // see at this pixel is the brightest ribbon at this pixel"), not SUM —
    // SUM would over-saturate where columns coincide and lose ribbon
    // identity. MAX preserves the ribbon character even where multiple
    // columns overlap.
    float3 auroraColor = float3(0.0);

    // Common kink phase shared across all columns — the shudder is a single
    // event in time, not three independent kinks.
    float kinkPhase = sin(uv.y * kKinkSpatialFreq);

    // AV.3 — CURTAIN-BAND undulation (the visible dance). A traveling vertical
    // wave of x displaces the whole curtain band up/down and folds it across
    // the sky ("a hand run along the curtain" — aurora-motion research). Two
    // summed sines → organic, not metronomic; amplitude audio-gated. `auroraY`
    // replaces `uv.y` for the band envelope + palette stratification so the
    // whole sheet ripples, not just its internal texture.
    float bandWave = kAuroraBandWaveAmp * motionAmp * (
          sin(uv.x * kAuroraBandFreq       - time * kAuroraWaveSpeed)             * 0.6
        + sin(uv.x * kAuroraBandFreq * 2.1 - time * kAuroraWaveSpeed * 1.5 + 1.3) * 0.4);
    float auroraY = uv.y + bandWave;

    for (int c = 0; c < kAuroraColumns; c++) {
        float colOffset = kAuroraColumnOffsets[c];
        float colDepth  = kAuroraColumnDepths[c];

        // Per-column horizontal anchor with the audio-coupled lateral kink.
        float columnUVx = uv.x + colOffset + kinkAmp * kinkPhase;

        // AV.2.1: all columns share the same substrate-rotation rate; depth
        // distinction is from `colOffset` (horizontal screen position) +
        // `colDepth` (atmospheric perspective dimming). Per-column velocity
        // differential was producing column-winner switching under mv_warp's
        // ~1 s accumulator → painterly smear. See `kAuroraColumnOffsets`
        // comment block above.
        float3 colContribution = raymarch_column(
            columnUVx, auroraY,
            driftSpeed, foldScale, paletteOffset, motionAmp, time);

        auroraColor = max(auroraColor, colContribution * colDepth);
    }

    // Lawlor footprint F(x) — applied ONCE here (screen space), carving the
    // negative space between a few draped, curl-advected curtains. Uses the
    // band-undulated `auroraY` so the footprint drapes with the sheet. Shared
    // across all columns → real gaps (the per-column form let the MAX refill
    // them). THE structural fix vs the full-field wash.
    auroraColor *= aurora_footprint(uv.x, auroraY, motionAmp, time);

    // Route 2 — brightness breathing. Apply AFTER the MAX so brightness
    // modulation is global (the whole aurora pulses, not per-column).
    // AV.2.2e: threshold-gate the bassDev signal so brightness only pulses
    // on the larger bass transients (gate ramp 0.30 → 0.55), not on every
    // small bass-stem fluctuation. Below 0.30 the brightness stays at
    // base 0.85; above 0.55 it reaches the full kBrightnessAmp shift.
    float bassPulse = smoothstep(kBrightnessGateLo, kBrightnessGateHi, bassDev);
    float brightnessScale = kBrightnessBase + kBrightnessAmp * bassPulse;
    auroraColor *= brightnessScale;

    // Aurora altitude envelope. Localizes the curtain to the upper-middle of
    // frame: soft fade at top (curtain dissolves into space — soft top per
    // §5.5), sharper cutoff toward the horizon (defined lower edge — sharp
    // bottom per §5.5). Refs 01 / 03 / 04 all show this profile. Unchanged
    // from AV.1 — multi-column doesn't widen the vertical envelope.
    // Envelope uses the undulated `auroraY` so the whole band ripples/folds.
    float auroraEnv = smoothstep(0.02, 0.40, auroraY)
                    * (1.0 - smoothstep(0.74, 0.84, auroraY));
    auroraColor *= auroraEnv;

    // ── Composite: additive emission over dark sky ──────────────────────────
    // Stars punch THROUGH aurora because the composite is `sky + col`, not
    // `mix(sky, col, mask)` — Failure Mode #5 (opaque aurora) avoided.
    // Soft HDR-ish clamp at 0.95 prevents bright-star-plus-bright-aurora
    // pixels from clipping to 255 byte (Acceptance "no white clip" gate).
    float3 finalColor = min(sky + auroraColor, float3(0.95));
    return float4(finalColor, 1.0);
}

// AV.2.2: mv_warp pass dropped. The `mvWarpPerFrame` + `mvWarpPerVertex`
// functions that AV.1 + AV.2 required are no longer compiled — the
// preset's `passes: []` in `AuroraVeil.json` means the loader skips the
// mv_warp preamble's forward-declaration enforcement. See header docstring
// for the empirical justification from `AuroraVeilMVWarpAccumulationTest`.
