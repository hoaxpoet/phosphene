// AuroraVeil.metal — Faithful MSL reproduction of nimitz "Auroras".
//
// Source: nimitz (@stormoid), "Auroras", Shadertoy XtGGRt (2017) — the
// canonical procedural aurora. This is a straight port of that shader's
// algorithm and constants to Metal. Adapted ONLY for the Phosphene harness:
//   • iTime            → f.time
//   • gl_FragCoord.xy  → in.position.xy   (per-pixel march dither)
//   • iResolution      → baked 1920×1080  (the 60 fps @ 1080p target; only
//                        affects aspect ratio + star density)
//   • no iMouse        → nimitz's untouched-mouse default view, mo = (-0.1, 0.1)
//   • y flip           → Phosphene uv.y = 0 is top, so p.y = 0.5 - uv.y
//
// NOTHING is added. The AV.2–AV.6 accretion is deleted: no footprint F(x), no
// multi-column parallax, no band undulation, no traveling waves, no drum kink,
// no audio routing. Those were successive negotiations away from the working
// reference (FA #65) and each one broke fidelity. This is the reference itself.
//
// The audio buffers remain in the fragment signature only because the engine
// binds them; they are unused. `AuroraVeilState.swift` still flushes buffer(6)
// — also unused now; left in place to avoid loader churn.
//
// Prior-art credit: nimitz (algorithm + all constants). Lawlor & Genetti
// (WSCG 2011) — the per-step `sin(...)` palette is their H(z) height curve.
// nimitz's Shadertoy source is CC-BY-NC-SA; this port carries the attribution
// and adds no Phosphene-specific behaviour.

// ── Tunables (the only departures from nimitz's defaults) ─────────────────────
// Matt live-review 2026-07-19: static upward view (no pan → no star twinkle),
// sky only (no horizon / ground / reflection), livelier aurora.
constant float kAuroraPitchUp     = 0.60;  // view tilt up (radians) — look into the sky
constant float kAuroraEvolveSpeed = 0.18;  // aurora shimmer rate (nimitz native = 0.06)

// Stars as beat-keeper (Layer-4 accent on the cached BeatGrid). Additive-only,
// sparse footprint → flash-safe (D-157). Gated by pulse_amp01 (0 at silence /
// cold-start). See aurora_stars.
constant float kStarBeatAmp    = 1.5;   // peak brightness lift on the beat (~2.5×)
constant float kStarBeatDecay  = 10.0;  // attack sharpness — crisp pop, short tail
constant float kStarBeatSpread = 0.04;  // near-unison → a clear collective sparkle, not haze

// A — Breathe: whole-veil brightness on the intensity envelope (arousal). Slow
// and gentle, but strong enough to read within the in-song arousal range
// (~0.35–0.63 on real music), not just silence-vs-loud.
constant float kBreatheGain = 0.8;   // brightness swing per unit arousal
constant float kBreatheMid  = 0.50;  // arousal → reference brightness (mid of quiet↔loud tracks)
constant float kBreatheLo   = 0.85;  // clamp — silence settles, never drops out (D-037)
constant float kBreatheHi   = 1.15;  // clamp — cap peak so it never washes the sky
// Gentle bass layer: a small lift-only term from bass_att_rel — the attack-
// SMOOTHED bass deviation (D-026; ~4× less frame-jerk than bass_dev). A fast-
// but-smoothed transient riding on the slow mood breathe (different timescale →
// no fighting). Satisfies the L2 continuous-energy gate honestly.
// 0.20 (not 0.30): at 0.30 the peak lift (+11%) rivalled the mood breathe's own
// clamped range (+15%), so the bass stopped being a subordinate layer. 0.20
// keeps it clearly under the envelope — perceptually identical (Matt: "can
// barely notice it"), and the hierarchy is honest.
constant float kBassLift = 0.20;     // peak brightness lift on a bass swell (~+8%)
// C — Colour with mood: valence shifts the WHOLE palette phase (not just the
// crown, which the exp-decay weighting makes invisible). Warmer toward pink at
// higher mood, cooler/greener when it darkens; valence 0 == nimitz's green.
constant float kMoodWarmth  = 0.50;  // global palette-phase shift per unit valence

// ── nimitz helpers ────────────────────────────────────────────────────────────

constant float2x2 kAuroraM2 = float2x2(0.95534, -0.29552, 0.29552, 0.95534);

static inline float2x2 aurora_mm2(float a) {
    float c = cos(a);
    float s = sin(a);
    return float2x2(c, -s, s, c);
}

static inline float aurora_tri(float x) {
    return clamp(abs(fract(x) - 0.5), 0.01, 0.49);
}

static inline float2 aurora_tri2(float2 p) {
    return float2(aurora_tri(p.x) + aurora_tri(p.y),
                  aurora_tri(p.y + aurora_tri(p.x)));
}

// Five octaves of domain-warped triangular noise. The ONLY time term is the
// per-octave `mm2(time * spd)` rotation of the warp vector (spd = 0.06) — this
// is nimitz's slow substrate evolution. Initial rotation is spatial
// (`mm2(p.x * 0.06)`), not temporal.
static inline float aurora_tri_noise_2d(float2 p, float spd, float time) {
    float z  = 1.8;
    float z2 = 2.5;
    float rz = 0.0;
    p = aurora_mm2(p.x * 0.06) * p;
    float2 bp = p;
    for (int i = 0; i < 5; i++) {
        float2 dg = aurora_tri2(bp * 1.85) * 0.75;
        dg = aurora_mm2(time * spd) * dg;
        p -= dg / z2;
        bp *= 1.3;
        z2 *= 0.45;
        z  *= 0.42;
        p  *= 1.21 + (rz - 1.0) * 0.02;
        rz += aurora_tri(p.x + aurora_tri(p.y)) * z;
        p = -(kAuroraM2 * p);
    }
    return clamp(1.0 / pow(rz * 29.0, 1.3), 0.0, 0.55);
}

static inline float aurora_hash21(float2 n) {
    return fract(sin(dot(n, float2(12.9898, 4.1414))) * 43758.5453);
}

static inline float3 aurora_hash33(float3 p) {
    p = fract(p * float3(443.8975, 397.2973, 491.1871));
    p += dot(p.zxy, p.yxz + 19.27);
    return fract(float3(p.x * p.y, p.z * p.x, p.y * p.z));
}

// 50-step volumetric column march along the real 3D ray. `pt` is the world
// distance to altitude `0.8 + pow(i,1.4)*0.002`; the noise is sampled in the
// world xz plane (`bpos.zx`). Running-average smear (`avgCol`) turns per-step
// noise into vertical ribbons; the per-step `sin()` palette is the H(z) curve.
static inline float4 aurora_march(float3 ro, float3 rd, float2 fragCoord, float time, float paletteWarm) {
    float4 col    = float4(0.0);
    float4 avgCol = float4(0.0);
    for (int i = 0; i < 50; i++) {
        float fi = float(i);
        float of = 0.006 * aurora_hash21(fragCoord) * smoothstep(0.0, 15.0, fi);
        float pt = ((0.8 + pow(fi, 1.4) * 0.002) - ro.y) / (rd.y * 2.0 + 0.4);
        pt -= of;
        float3 bpos = ro + pt * rd;
        float2 p    = bpos.zx;
        float  rzt  = aurora_tri_noise_2d(p, kAuroraEvolveSpeed, time);
        float4 col2 = float4(0.0, 0.0, 0.0, rzt);
        col2.rgb = (sin(1.0 - float3(2.15, -0.5, 1.2) + fi * 0.043 + paletteWarm) * 0.5 + 0.5) * rzt;
        avgCol = mix(avgCol, col2, 0.5);
        col += avgCol * exp2(-fi * 0.065 - 2.5) * smoothstep(0.0, 5.0, fi);
    }
    col *= clamp(rd.y * 15.0 + 0.4, 0.0, 1.0);
    return col * 1.8;
}

// Beat-keeper twinkle: each star peaks at the beat (beatPhase = 0), decaying
// over the beat, with a slight per-star spread (rn.y) so the field shimmers on
// the beat rather than strobing in unison. Additive only + sparse footprint →
// flash-safe (D-157). `gate` (pulse_amp01) fades the twinkle to zero at
// silence / cold-start, leaving steady stars.
static inline float3 aurora_stars(float3 p, float beatPhase, float gate) {
    float3 c = float3(0.0);
    float res = 1920.0;  // baked 1080p width — star density ∝ resolution
    for (int i = 0; i < 4; i++) {
        float fi = float(i);
        float3 q  = fract(p * (0.15 * res)) - 0.5;
        float3 id = floor(p * (0.15 * res));
        float2 rn = aurora_hash33(id).xy;
        float c2 = 1.0 - smoothstep(0.0, 0.6, length(q));
        c2 *= step(rn.x, 0.0005 + fi * fi * 0.001);
        float sp = fract(beatPhase + rn.y * kStarBeatSpread);
        float tw = exp(-sp * kStarBeatDecay);
        float3 base = mix(float3(1.0, 0.49, 0.1), float3(0.75, 0.9, 1.0), rn.y) * 0.1 + 0.9;
        c += c2 * base * (1.0 + kStarBeatAmp * tw * gate);
        p *= 1.3;
    }
    return c * c * 0.8;
}

static inline float3 aurora_bg(float3 rd) {
    float sd = dot(normalize(float3(-0.5, -0.6, 0.9)), rd) * 0.5 + 0.5;
    sd = pow(sd, 5.0);
    float3 col = mix(float3(0.05, 0.1, 0.2), float3(0.1, 0.05, 0.2), sd);
    return col * 0.63;
}

// ── GPU state buffer (unused; retained to match the loader binding) ───────────
struct AuroraVeilStateGPU {
    float kinkAccumulator;
    float smoothedPitchNorm;
    float _pad0;
    float _pad1;
};

// ── Fragment ──────────────────────────────────────────────────────────────────

fragment float4 aurora_fragment(
    VertexOut                    in    [[stage_in]],
    constant FeatureVector&      f     [[buffer(0)]],
    constant float*              fft   [[buffer(1)]],
    constant float*              wv    [[buffer(2)]],
    constant StemFeatures&       stems [[buffer(3)]],
    constant AuroraVeilStateGPU& av    [[buffer(6)]]
) {
    (void)fft; (void)wv; (void)stems; (void)av;  // unused — reactivity reads f only

    float time = f.time;

    // A — Breathe: gentle brightness envelope on intensity, centered on the
    // track median so silence/calm ≈ reference and lifts brighten. Plus a small
    // smoothed-bass lift (bass_att_rel, lift-only) riding on top.
    float breathe = clamp(1.0 + kBreatheGain * (f.arousal - kBreatheMid)
                              + kBassLift * max(0.0, f.bass_att_rel),
                          kBreatheLo, kBreatheHi);
    // C — Colour with mood: valence shifts the whole palette (visible region).
    float paletteWarm = clamp(f.valence, -1.0, 1.0) * kMoodWarmth;
    const float aspect = 1920.0 / 1080.0;  // 60 fps @ 1080p target

    // Phosphene uv.y = 0 at top; nimitz q.y = 0 at bottom → flip y.
    float2 p = float2((in.uv.x - 0.5) * aspect, 0.5 - in.uv.y);

    float3 ro = float3(0.0, 0.0, -6.7);
    float3 rd = normalize(float3(p, 1.3));

    // Static upward view. No azimuth pan (that pan made the view-indexed stars
    // twinkle); pitch up so the whole frame is sky — vertical ray curtains
    // overhead, no horizon, no ground, no reflection.
    rd.yz = aurora_mm2(kAuroraPitchUp) * rd.yz;

    // Sky + stars everywhere; aurora composited where the ray looks upward.
    // No reflection branch — the frame is sky only.
    float fade = smoothstep(0.0, 0.01, abs(rd.y)) * 0.1 + 0.9;
    // Downbeat-timed (not per-beat) — calmer, and the strong pulse people feel.
    float3 col = aurora_bg(rd) * fade + aurora_stars(rd, f.bar_phase01, f.pulse_amp01);

    if (rd.y > 0.0) {
        float4 aur = smoothstep(0.0, 1.5, aurora_march(ro, rd, in.position.xy, time, paletteWarm)) * fade;
        aur.rgb *= breathe;  // A — breathe brightness (emission only; stars unaffected)
        col = col * (1.0 - aur.a) + aur.rgb;
    }

    return float4(col, 1.0);
}
