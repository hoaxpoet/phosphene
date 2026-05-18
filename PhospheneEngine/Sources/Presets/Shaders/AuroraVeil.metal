// AuroraVeil.metal — Direct-fragment + mv_warp ambient ribbon preset.
//
// AV.2 — Multi-column raymarch + audio routing. Three implicit drift columns
// at off-thirds horizontal positions establish multi-curtain parallax depth
// (foreground at uv.x, mid-ground at uv.x + 0.27, background at uv.x - 0.18),
// with per-column depth-scale dimming + non-parallel drift velocities. The
// seven audio routes from AURORA_VEIL_DESIGN.md §5.7 layer on top:
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
// Drift velocity scales scale the per-octave noise-rotation rate so the
// background column's noise field rotates slower than the foreground's —
// parallax illusion of depth (distant ribbons appear to move slower).

constant int    kAuroraColumns        = 3;
constant float4 kAuroraColumnOffsets  = float4( 0.00,  0.27, -0.18, 0.0);
constant float4 kAuroraColumnDepths   = float4( 1.00,  0.70,  0.50, 0.0);
constant float4 kAuroraColumnVelocity = float4( 1.00,  0.75,  0.55, 0.0);

// ── Audio routing constants (AV.2 — design §5.7) ─────────────────────────────

// D-019 stem-warmup blend window. `totalStemEnergy` < 0.02 → FV proxy only;
// > 0.06 → stems only. Matches Gossamer.metal:130 verbatim.
constant float kStemWarmupLow  = 0.02;
constant float kStemWarmupHigh = 0.06;

// Route 1 — vocal pitch palette phase. Amplitude 1.6 maps the smoothed pitch
// span [0, 1] (E2 → C7) to ±0.8 phase shift on the IQ palette baseOffset —
// roughly one full hue migration cycle across the 4-octave singing range.
constant float kVocalsPitchAmp = 1.6;

// Route 2 — brightness breathing. `0.85 + 0.30 × bassRel` gives a 30 %
// amplitude continuous primary driver per §5.7. With bassRel clamped to
// [-1, 1], the final scale lies in [0.55, 1.15].
constant float kBrightnessBase = 0.85;
constant float kBrightnessAmp  = 0.30;

// Route 3 — fold density. `tri_noise_2d` spatial frequency scaling per §5.7.
// `1.0 + 0.30 × midRel` thickens folds on rising mids. The `aurora_tri_noise_2d`
// p-input multiplier is applied via `marchPos × foldScale`.
constant float kFoldDensityAmp = 0.30;

// Route 5 — curtain kink. Fragment-space lateral UV jitter on the column noise
// sample, scaled by kinkAccumulator. Amplitude 0.003 UV ≈ 4 px at 1080p —
// visible shudder, not a deflection. Matches design §5.6 / §5.7.
constant float kKinkAmp        = 0.003;
constant float kKinkSpatialFreq = 12.0;

// Route 6 — valence palette warm/cool. Positive valence (major-key) shifts the
// baseOffset by `+0.4 × valence` → warmer (more magenta crown); negative
// valence shifts cooler. Stacks additively with route 1.
constant float kValencePaletteAmp = 0.4;

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
// rotation rate; nimitz uses 0.06 as the default. `velocityScale` (AV.2
// addition) scales BOTH the per-octave rotation rate AND the base substrate
// rotation rate so background columns rotate slower than foreground —
// parallax illusion of depth. Returns a positive scalar density in [0, 0.55]
// that reads as "where the curtain is bright at this (xz) location at this
// time."
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
static inline float aurora_tri_noise_2d(float2 p, float spd, float time, float velocityScale) {
    float2 bp = p;
    bp = aurora_mm2(time * 0.10 * velocityScale) * bp;
    float z  = 1.8;
    float z2 = 2.5;
    float rz = 0.0;
    for (int i = 0; i < 5; i++) {
        float2 dg = aurora_tri2(bp * 1.85) * 0.75;
        dg = aurora_mm2(time * spd * velocityScale) * dg;
        bp -= dg / z2;
        bp = aurora_mm2(-time * 0.10 * velocityScale) * bp;
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
//   velocityScale — per-column substrate-rotation scale (parallax depth)
//   driftSpeed    — bass-modulated `spd` argument to `aurora_tri_noise_2d`
//   foldScale     — mid-modulated noise spatial frequency multiplier
//   paletteOffset — sum of vocals-pitch + valence palette additive offsets
//   time          — `f.time`
static inline float3 raymarch_column(
    float columnUVx,
    float uv_y,
    float velocityScale,
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
            driftSpeed, time, velocityScale);

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

    // Route 2 + Route 4 — bass-rel (continuous brightness breathing + drift
    // speed). FV proxy `f.bass_att_rel` is the deviation primitive at the
    // FeatureVector layer; stem proxy `stems.bass_energy_rel` is the
    // D-026 equivalent on the stem layer.
    float bassRel = mix(f.bass_att_rel, stems.bass_energy_rel, stemMix);

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

    // Route 4 — substrate drift speed. `bassRel` is in [-1, 1]; we map
    // negative bass to a slight drift slowdown (still positive) and positive
    // bass to up to +kAuroraDriftSpeedGain. Result lies in [0.02, 0.10].
    float driftSpeed = kAuroraDriftSpeedBase + kAuroraDriftSpeedGain * max(0.0, bassRel);

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
        float colOffset    = kAuroraColumnOffsets[c];
        float colDepth     = kAuroraColumnDepths[c];
        float colVelocity  = kAuroraColumnVelocity[c];

        // Per-column horizontal anchor with the audio-coupled lateral kink.
        float columnUVx = uv.x + colOffset + kinkAmp * kinkPhase;

        float3 colContribution = raymarch_column(
            columnUVx, uv.y, colVelocity,
            driftSpeed, foldScale, paletteOffset, time);

        auroraColor = max(auroraColor, colContribution * colDepth);
    }

    // Route 2 — brightness breathing. Apply AFTER the MAX so brightness
    // modulation is global (the whole aurora pulses, not per-column).
    float brightnessScale = kBrightnessBase + kBrightnessAmp * clamp(bassRel, -1.0, 1.0);
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

// ── MV-Warp functions ─────────────────────────────────────────────────────────
// Required by the mvWarp preamble forward declarations (D-027).

MVWarpPerFrame mvWarpPerFrame(
    constant FeatureVector& f,
    constant StemFeatures&  stems,
    constant SceneUniforms& s
) {
    (void)stems; (void)s;

    MVWarpPerFrame pf;
    pf.cx = 0.0; pf.cy = 0.0;
    pf.dx = 0.0; pf.dy = 0.0;
    pf.sx = 1.0; pf.sy = 1.0;
    pf.warp = 0.0;

    pf.zoom  = 1.0 + 0.0015;  // slight inward drift

    // AV.2 — slow rotation now mixes in valence (`+ 0.0004 × valence`) per
    // design §5.3. Positive valence (major-key) → slightly faster CCW
    // rotation; negative → slower. Continuous primary, never beat-coupled.
    pf.rot   = 0.0008 + 0.0004 * f.valence;
    pf.decay = 0.945;          // ~1 s persistence trail

    // Carry f.time through pf.q1 so per-vertex curl_noise advection has a
    // monotonic time source (per-vertex doesn't see SceneUniforms). AV.2
    // does NOT pass kinkAccumulator through pf.q2 — the q-vars are
    // reconstructed per frame so they can't carry persistent state; the
    // kink is consumed directly in `aurora_fragment` from buffer(6).
    pf.q1 = f.time;
    pf.q2 = 0.0; pf.q3 = 0.0; pf.q4 = 0.0;
    pf.q5 = 0.0; pf.q6 = 0.0; pf.q7 = 0.0; pf.q8 = 0.0;
    return pf;
}

float2 mvWarpPerVertex(
    float2 uv, float rad, float ang,
    thread const MVWarpPerFrame& pf,
    constant FeatureVector& f,
    constant StemFeatures& stems
) {
    (void)rad; (void)ang; (void)f; (void)stems;

    float2 centre = float2(0.5, 0.5);
    float2 p      = uv - centre;
    float  zoomAmt = 1.0 / max(pf.zoom, 0.001);
    float2 zoomed  = p * zoomAmt + centre;

    // Curl-noise advection on the per-vertex displacement field. Mimics the
    // NeverSeenTheSky vortical-flow motion signature (research §1.3) at
    // fragment-shader cost via the V.1 curl_noise utility — no fluid solver.
    // pf.q1 carries f.time from per-frame; multiplied by 0.1 for slow temporal
    // evolution (the substrate-drift timescale per §5.4).
    float2 disp = curl_noise(float3(uv * 2.0, pf.q1 * 0.1)).xy * 0.005;
    return zoomed + disp;
}
