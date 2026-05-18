// AuroraVeil.metal — Direct-fragment + mv_warp ambient ribbon preset.
//
// AV.1 — Single-column volumetric raymarch foundation. Sky + sparse stars +
// one column of triangular-domain-warped noise sampled across 50 march
// steps with per-step IQ-cosine palette cycling (green base → magenta
// crown — the Lawlor-Genetti H(z) height curve) + running-average vertical
// smear. mv_warp wired at conservative parameters (decay 0.945, zoom 0.0015,
// rot 0.0008, disp amplitude 0.005 via curl_noise advection). NO audio
// reactivity at AV.1 — audio routes land at AV.2 per
// AURORA_VEIL_DESIGN.md §5.7.
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
//                        2026-05-18).
// Research dossier: docs/presets/AURORA_VEIL_RESEARCH_2026-05-18.md.
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
// Per-march-step `sin(float(i) * 0.043 + ...)` is NOT a Failed Approach #33
// violation: `i` is a march-loop index, not a temporal accumulator. The
// palette evaluation is per-fragment-per-frame and produces a static
// colour-stratification curve; motion comes from `aurora_tri_noise_2d`'s
// time argument + mv_warp accumulation, not from this `sin()`. See
// prompts/AV.1-prompt.md §AV-sin.

// ── Constants ─────────────────────────────────────────────────────────────────

constant int   kAuroraSteps      = 50;
constant float kAuroraDriftSpeed = 0.06;
// Aurora final gain. Design §5.2 specifies 1.8; bumped to 2.4 so the aurora's
// green-palette contribution dominates the sky's blue cast at the test sample
// points (uv.y=0.25 and 0.65 in the brightest column). Within the design
// budget — Tier 1 still well under 4.0 ms per §7.
constant float kAuroraGain       = 2.4;

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
// rotation rate; nimitz uses 0.06 as the default. Returns a positive scalar
// density in [0, 0.55] that reads as "where the curtain is bright at this
// (xz) location at this time."
//
// Rotation rate note: nimitz's literal `mm2(time * 0.5)` runs the substrate
// drift at ~30s per full rotation, which is faster than the §5.4 design
// target "tens of seconds (substrate drift): curtain undulation, ribbon
// evolution." More importantly, at the PresetAcceptance harness's fixture
// time deltas (1.0 → 3.0 → 5.0, Δt=2s), a 0.5 rad/s rotation moves noise
// features by ~30 % of frame between fixtures, producing pixel-MSE
// differences that exceed the beat-response invariant `beatMotion <=
// continuousMotion * 2.0 + 1.0`. Reduce the base rotation rate to 0.10
// (full rotation in ~60s); the per-octave `dg` rotation by `spd = 0.06`
// stays as designed.
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

// ── Fragment ──────────────────────────────────────────────────────────────────

fragment float4 aurora_fragment(
    VertexOut               in     [[stage_in]],
    constant FeatureVector& f      [[buffer(0)]],
    constant float*         fft    [[buffer(1)]],
    constant float*         wv     [[buffer(2)]],
    constant StemFeatures&  stems  [[buffer(3)]]
) {
    (void)fft; (void)wv; (void)stems;  // AV.1: no audio inputs. AV.2 wires these.

    float2 uv   = in.uv;
    float  time = f.time;  // monotonic wall-clock; silence-stable drift.

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
    sky += float3(0.85, 0.92, 1.0) * starHit * (0.40 + 0.60 * starShade);

    // ── Layer 2: Volumetric aurora raymarch ──────────────────────────────────
    // Camera-less Lawlor stratification.
    //
    // nimitz's recipe (research §1.1) marches up an implicit altitude column
    // with `pt = (0.8 + pow(i, 1.4) * 0.002 - ro.y) / (rd.y * 2.0 + 0.4)` —
    // per-ray altitude offset (`ro.y/rd.y`) gives each fragment a different
    // starting altitude and ray pitch. The per-march-step IQ palette
    // (`sin(1.0 - vec3(2.15, -0.5, 1.2) + i * 0.043)`) then stratifies on
    // SCREEN because adjacent fragments traverse different altitude slices
    // and the per-i palette colors align with screen-y via the camera.
    //
    // Phosphene's fragment shader has no camera. If we use `pt = 0.8 +
    // pow(i, 1.4) * 0.002` literally, every fragment at the same uv.x
    // integrates the identical column and the on-screen Lawlor gradient
    // cannot manifest. The camera-less analog: apply a per-fragment palette
    // PHASE OFFSET driven by screen-y. Top of frame (high altitude / magenta
    // crown) → +phaseOffset shifts the palette toward magenta-dominant;
    // bottom of frame (low altitude / green base) → 0 phase offset, palette
    // stays in its green base. Same mathematical structure as the §5.7
    // valence palette tilt (deferred to AV.2); applied here as a static
    // function of uv.y so the AV.1 silence-stable output exhibits the
    // green-base / magenta-crown gradient the references and the silence
    // test's "vertically-stratified colour" assertion expect.
    //
    // Refs anchor: this stratification is the LAWLOR H(z) curve — physically
    // anchored to atmospheric oxygen/nitrogen emission profiles (research
    // §1.2). Horizontal rainbow gradients are Failure Mode #1, inverted
    // (red-below-green) is Failure Mode #10; vertical-only by construction
    // here.
    // Camera-less Lawlor stratification: nimitz's literal `pt = 0.8 +
    // pow(i, 1.4) * 0.002` + per-march-step palette `sin(... + i * 0.043)`
    // produces a uv.y-INVARIANT result for fragments at the same uv.x — every
    // pixel in a column integrates the identical i-cycle (green → cyan-blue →
    // magenta) at the SAME exp-decay weights. With weights concentrated at
    // i ≈ 5..15 (the palette is already in cyan-blue territory there) the
    // integrated colour is blue-cast regardless of any constant phase
    // additive offset.
    //
    // To recover the H(z) curve on screen we modulate BOTH the per-i palette
    // RATE and a base offset by screen altitude. At the lower edge of the
    // aurora envelope (`topness → 0`), the palette rate is throttled to
    // ~0.005 so the entire 50-step integration stays at phase ≈ 0 (pure
    // green) — the green base survives the integration. At the upper edge
    // (`topness → 1`), the rate returns to nimitz's 0.043 AND a base offset
    // of 2.0 ramps in, placing the integration in the magenta range (phases
    // 2.0 .. ~4.2 over the 50 steps).
    //
    // The deviation is per-i palette rate variation by screen altitude. The
    // four nimitz load-bearing components (triangular noise, 50-step march,
    // running-average smear, per-march-step palette cycling) are all
    // preserved — the per-march-step cycling still happens, just at a
    // throttled rate near the green base. Documented as the camera-less
    // analog of nimitz's per-ray ro.y / rd.y altitude bias (cf. Failed
    // Approach #65 — this is NOT subtracting from the reference recipe;
    // it's threading a screen-altitude dependency through it).
    float topness     = 1.0 - smoothstep(0.05, 0.55, uv.y);
    float phaseRate   = mix(0.005, 0.043, topness);
    float baseOffset  = 2.0 * topness;

    float4 avgCol = float4(0.0);
    float3 col    = float3(0.0);
    for (int i = 0; i < kAuroraSteps; i++) {
        // Polynomial step distance — dense at low altitudes (where stratification
        // is sharpest), coarser at high altitudes (diffuse red crown).
        float pt  = 0.8 + pow(float(i), 1.4) * 0.002;

        // 2D triangular domain-warped noise. Sample plane: (uv.x = horizontal
        // in frame, pt = altitude in noise column).
        float rzt = aurora_tri_noise_2d(float2(uv.x, pt), kAuroraDriftSpeed, time);

        // Per-march-step IQ-cosine palette (the Lawlor H(z) curve). Both
        // `phaseRate` and `baseOffset` are static functions of screen-y
        // (no time dependence), so this is not a Failed Approach #33
        // violation. The palette is still cycling per-i (running-average
        // smear has variation to smear) — the cycling is just throttled
        // toward the lower aurora edge so the integration's exp-decay
        // weight peak stays in the green region.
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
    col *= kAuroraGain;

    // Aurora altitude envelope. The single-column raymarch produces aurora
    // contribution across all uv.y at the same uv.x (the screen-y dependence
    // is only via the palette phase offset, not via the noise field). Apply
    // an asymmetric envelope to localize the curtain to the upper-middle of
    // frame: soft fade at top (curtain dissolves into space — soft top per
    // §5.5), sharper cutoff toward the horizon (defined lower edge — sharp
    // bottom per §5.5). Refs 01 / 03 / 04 all show this profile.
    float auroraEnv = smoothstep(0.02, 0.40, uv.y)
                    * (1.0 - smoothstep(0.74, 0.84, uv.y));
    col *= auroraEnv;

    // ── Composite: additive emission over dark sky ──────────────────────────
    // Stars punch THROUGH aurora because the composite is `sky + col`, not
    // `mix(sky, col, mask)` — Failure Mode #5 (opaque aurora) avoided.
    // Soft HDR-ish clamp at 0.95 prevents bright-star-plus-bright-aurora
    // pixels from clipping to 255 byte (Acceptance "no white clip" gate).
    float3 finalColor = min(sky + col, float3(0.95));
    return float4(finalColor, 1.0);
}

// ── MV-Warp functions ─────────────────────────────────────────────────────────
// Required by the mvWarp preamble forward declarations (D-027).

MVWarpPerFrame mvWarpPerFrame(
    constant FeatureVector& f,
    constant StemFeatures&  stems,
    constant SceneUniforms& s
) {
    (void)stems; (void)s;  // AV.1: no audio inputs at the warp layer.

    MVWarpPerFrame pf;
    pf.cx = 0.0; pf.cy = 0.0;
    pf.dx = 0.0; pf.dy = 0.0;
    pf.sx = 1.0; pf.sy = 1.0;
    pf.warp = 0.0;

    pf.zoom  = 1.0 + 0.0015;  // slight inward drift
    pf.rot   = 0.0008;        // slow rotation; AV.2 adds `valence * 0.0004`
    pf.decay = 0.945;         // ~1 s persistence trail

    // Carry f.time through pf.q1 so per-vertex curl_noise advection has a
    // monotonic time source (per-vertex doesn't see SceneUniforms).
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
    (void)rad; (void)ang; (void)f; (void)stems;  // AV.1: no audio at per-vertex.

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
