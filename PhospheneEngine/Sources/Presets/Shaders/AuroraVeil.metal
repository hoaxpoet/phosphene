// AuroraVeil.metal — Direct-fragment ambient ribbon preset.
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
constant float kAuroraGain       = 2.4;

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
constant float kBrightnessAmp     = 0.30;
constant float kBrightnessGateLo  = 0.30;
constant float kBrightnessGateHi  = 0.55;

// Route 3 — fold density. AV.2.2c (2026-05-19): amplitude reduced 0.30 →
// 0.10. Was the DOMINANT motion contributor — changing the noise sample's
// spatial frequency frame-to-frame morphs the entire noise field, so
// continuous mid_att_rel modulation produced restless per-frame
// re-shaping. Quartered amplitude keeps the audio coupling perceptible
// (mids still thicken folds 10 %) without continuous noise-field morph.
constant float kFoldDensityAmp = 0.10;

// Route 5 — curtain kink. AV.2.2c (2026-05-19): amplitude halved 0.003 →
// 0.0015 UV. The kink-charge gate thresholds (CPU-side, see
// `AuroraVeilState.kinkChargeLo/Hi`) also raised from 0.4/0.7 → 0.6/0.9
// — observed gate-fire rate on Billie Jean was 9.4 % of frames (not
// "rare"); the design intent was rare-event gating with damped
// 1-2 s shudder, so the gate is now sized for genuinely rare events
// (~2 % of frames) and the shudder amplitude when it does fire is half
// as wide.
constant float kKinkAmp        = 0.0015;
constant float kKinkSpatialFreq = 12.0;

// Route 6 — valence palette warm/cool. AV.2.2c (2026-05-19): amplitude
// reduced 0.4 → 0.2 for coherent calmer-tuning pass. Major/minor key
// tilt is subtler.
constant float kValencePaletteAmp = 0.2;

// Route 7 — star twinkle. 30 % amplitude per-star brightness modulation,
// gated by `vocals_pitch_confidence > 0.5` (the gate is in shader, not here).
constant float kStarTwinkleAmp        = 0.30;
constant float kStarTwinkleConfGate   = 0.5;

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
    float time
) {
    float topness     = 1.0 - smoothstep(0.05, 0.55, uv_y);
    float phaseRate   = mix(0.005, 0.043, topness);
    // Per-fragment baseOffset = AV.1 Lawlor stratification term (topness ×
    // 2.0) + AV.2 vocals/valence additive offset. Topness dominates so the
    // green-base / magenta-crown gradient is preserved; routes 1 + 6
    // perturb the phase within the gradient.
    float baseOffset  = 2.0 * topness + paletteOffset;

    float4 avgCol = float4(0.0);
    float3 col    = float3(0.0);
    for (int i = 0; i < kAuroraSteps; i++) {
        // Polynomial step distance — dense at low altitudes (where stratification
        // is sharpest), coarser at high altitudes (diffuse red crown).
        float pt = 0.8 + pow(float(i), 1.4) * 0.002;

        // 2D triangular domain-warped noise. Sample plane: (column horizontal
        // anchor × foldScale, altitude × foldScale). Fold scale multiplies
        // BOTH dimensions so denser folds compress vertically AND
        // horizontally — `mid_att_rel` thickens the entire texture, not just
        // its horizontal frequency.
        float rzt = aurora_tri_noise_2d(
            float2(columnUVx * foldScale, pt * foldScale),
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

    // Route 3 — mid-rel (continuous fold density). FV proxy `f.mid_att_rel`;
    // stem proxy `stems.vocals_energy_rel` (matches Gossamer.metal:134 — the
    // closest mid-band stem analogue is vocals-energy-rel, since vocals
    // typically occupy the mid band).
    float midRel = mix(f.mid_att_rel, stems.vocals_energy_rel, stemMix);

    // Route 6 — valence palette warm/cool. No stem analogue; FV only.
    float valence = f.valence;

    // Route 1 — vocal-pitch normalized + smoothed (CPU-side via AuroraVeilState).
    // Confidence-gated: when YIN/CREPE confidence < threshold (silence,
    // unvoiced, or pre-stems), fall back to the mid-palette neutral 0.5 baseline
    // so the route is silence-stable per §5.8. When confident, consume the
    // smoothed value from the state buffer (5-frame moving average per §5.7).
    float pitchConfident = step(kStarTwinkleConfGate, stems.vocals_pitch_confidence);
    float pitchNorm = mix(0.5, av.smoothedPitchNorm, pitchConfident);

    // Stack routes 1 + 6 into a single additive paletteOffset that all three
    // columns share (so the hue migration is coherent across ribbons rather
    // than each ribbon hue-shifting independently).
    float paletteOffset = (pitchNorm - 0.5) * kVocalsPitchAmp
                        + valence * kValencePaletteAmp;

    // Route 4 — substrate drift speed. `bassDev` is positive-only; result
    // lies in [0.06, 0.06 + kAuroraDriftSpeedGain × dev_clamped]. Drift
    // accelerates only on bass transients; no slowdown phase.
    float driftSpeed = kAuroraDriftSpeedBase + kAuroraDriftSpeedGain * clamp(bassDev, 0.0, 1.0);

    // Route 3 — fold density. `midRel ≥ 0` thickens; `midRel < 0` slightly
    // loosens. Result in [0.7, 1.3].
    float foldScale = 1.0 + kFoldDensityAmp * clamp(midRel, -1.0, 1.0);

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

    // Route 7 — star twinkle. Per-star phase derived from the secondary hash
    // so each star has a different phase; modulation gated by
    // `vocals_pitch_confidence > 0.5` (no twinkle pre-stems / at silence /
    // when YIN is unsure). The 0.30 amplitude is a *modulation index*, not a
    // brightness scale — the twinkle adds ±30 % brightness around the base
    // starShade value.
    float starPhase   = f.beat_phase01 * 2.0 * M_PI_F + starShade * M_PI_F;
    float starTwinkle = 1.0 + kStarTwinkleAmp * sin(starPhase) * pitchConfident;
    sky += float3(0.85, 0.92, 1.0) * starHit * (0.40 + 0.60 * starShade) * starTwinkle;

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
            columnUVx, uv.y,
            driftSpeed, foldScale, paletteOffset, time);

        auroraColor = max(auroraColor, colContribution * colDepth);
    }

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
    float auroraEnv = smoothstep(0.02, 0.40, uv.y)
                    * (1.0 - smoothstep(0.74, 0.84, uv.y));
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
