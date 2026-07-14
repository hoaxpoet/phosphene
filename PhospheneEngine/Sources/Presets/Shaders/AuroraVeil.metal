// AuroraVeil.metal — Direct-fragment aurora preset (volumetric ray-march core).
//
// **AV.6 (2026-07-14, Matt) — volumetric-march core rebuild.** Aurora is a
// VOLUME of glowing gas seen at an angle, not a flat field of stripes. This core
// marches a camera ray `ro + rd·t` UP THROUGH a 3-D noise volume so it crosses
// many filaments at many depths as it rises — that traversal is where the depth,
// fine-filament density, perspective convergence and soft bloom come from. This
// is the nimitz "Auroras" recipe ported CORRECTLY.
//
// Why the two prior cores failed:
//   • AV.5 "wash": the same march, but MIS-PORTED — it marched straight down a
//     fragment-fixed screen column (sampled one vertical slice of low-freq
//     noise) → a smooth wash, no filaments (FA #73: ported the shape, not the
//     angled traversal).
//   • The AV.6 first attempt: a flat 2-D streak field. It produced streaks but
//     read as a 2-D poster, not a volume — "not even close" (Matt, 2026-07-14).
//     A flat field cannot carry the volumetric depth real aurora has.
// The fix is the reference itself, traversed right: a real ray through the
// volume. The load-bearing nimitz elements (research §1.1): triangular
// domain-warped noise (sharp filament edges, not fbm pillow-fog FM #8), the
// running-average vertical smear (`avgCol = mix(avgCol, col2, 0.5)` — turns
// samples into ribbons), the per-march-step palette (Lawlor H(z): green base →
// magenta crown BY ALTITUDE, not by uv.y), and the polynomial step growth.
//
// Wittens motion (§1.3): the sample coordinate is curl-noise advected so the
// curtains curl and dance (audio-scaled), not straight time-panned. Preserved
// from AV.5: the audio routes + `audio_routes` manifest (vocals→hue tint,
// bass→brightness, drums→kink, mid→motion), the half-bar star blink, and
// `AuroraVeilState` (CPU-side kink + smoothed pitch, buffer slot 6). The manual
// perspective "drape" is DROPPED — the ray march produces real perspective.
//
// Scope (Matt 2026-07-14): CURTAIN of streaks only.
//
// Reference: real-time aurora footage (Screen Recording 2026-07-14, streaky-
// curtain section ~235–266 s) → curated stills 10/11/12 + the `.mov` motion ref.
// Authoritative design: docs/presets/AURORA_VEIL_DESIGN.md §5.11.
// Research: docs/presets/AURORA_VEIL_RESEARCH_2026-05-18.md §1.1 (nimitz recipe),
//           §1.2 (Lawlor H(z)×F(x,y)), §1.3 (Wittens curl), §2.1–2.3.
//
// CLEAN-ROOM MSL reimplementation of the nimitz "Auroras" algorithm (Shadertoy
// XtGGRt, CC-BY-NC-SA) from the published description + Lawlor & Genetti (WSCG
// 2011). Algorithm adopted; source not incorporated.
//
// mv_warp is NOT used (AV.2.2: it washes out the high-frequency content).
// `passes: []` in AuroraVeil.json. Do NOT re-add it.
//
// Rubric profile: lightweight (D-067(b)). L1–L4 ladder + 9-question rubric apply.

// ── Constants ─────────────────────────────────────────────────────────────────

constant int   kAuroraSteps = 50;    // volumetric march steps (nimitz)
constant float kAuroraGain  = 12.0;  // final emission gain
constant float kNoiseScale  = 1.5;   // sample-plane scale (higher = finer filaments)
constant float kSaturate    = 1.5;   // post-march saturation (the running-avg smear greys the hue)
constant float kSmear       = 0.62;  // running-average persistence (higher = more coherent rays)
constant float kContrast    = 1.22;  // hue-preserving contrast (crisps rays, kills inter-ray haze)

// Large-scale concentration (Lawlor F(x)) — the march gives H(z)×texture (depth +
// filaments); this footprint carves the dark-sky negative space and a concentrated
// bright region so the curtain occupies PART of the frame (refs 10/12), not a
// uniform sky-filling green field. Screen-x based → vertical curtains stay coherent.
constant float kClusterFreq = 1.7;   // a few bright regions across the width
constant float kClusterLo   = -0.16; // below → dark-sky negative space
constant float kClusterHi   =  0.26; // above → inside a bright region
constant float kAspect      = 1.777; // 16:9 (ray x-scale; app renders 16:9)
// Camera: origin below/in-front, ray fans up into the sky. `kHorizon` is the
// uv.y where the ray grazes the horizon (rd.y=0) — the aurora fades below it, so
// this sets how far DOWN the frame the curtain hangs.
constant float kCamZ        = -6.7;
constant float kCamDepth    = 1.3;
constant float kHorizon     = 0.74;

// ── Motion (the dance) ───────────────────────────────────────────────────────
constant float kAuroraMotionBase = 0.35;   // motion amplitude at silence (gently alive)
constant float kAuroraMotionGain = 0.65;   // additional amplitude from mid activity
constant float kCurlAmp          = 0.30;   // curl advection of the sample coord (Wittens dance)
constant float kSubstrateSpd     = 0.06;   // per-octave noise rotation rate (nimitz spd)

// ── Audio routing constants (design §5.7, preserved) ─────────────────────────
constant float kStemWarmupLow  = 0.02;
constant float kStemWarmupHigh = 0.06;
constant float kVocalsPitchAmp = 0.8;      // vocals pitch → hue-tint magnitude
constant float kBrightnessBase   = 0.85;
constant float kBrightnessAmp    = 0.55;
constant float kBrightnessGateLo = 0.18;
constant float kBrightnessGateHi = 0.50;
constant float kKinkAmp          = 0.09;   // drum-kink lateral shudder on the sample coord
constant float kStarBlinkAmp     = 0.70;
constant float kStarBlinkDecay   = 6.0;

// ── GPU state buffer (slot 6, layout matches AuroraVeilState.swift) ──────────
struct AuroraVeilStateGPU {
    float kinkAccumulator;
    float smoothedPitchNorm;
    float _pad0;
    float _pad1;
};

// ── Triangular domain-warped noise (clean-room, research §1.1) ───────────────
// `aurora_tri` — triangle waveform (sharp filament edges; fbm/Perlin here =
//                pillow fog, FM #8). `aurora_tri2` — 2-component for domain warp.
// `aurora_mm2` — per-octave rotation → biological asymmetry.
static inline float aurora_tri(float x) {
    return clamp(abs(fract(x) - 0.5), 0.01, 0.49);
}
static inline float2 aurora_tri2(float2 p) {
    return float2(aurora_tri(p.x) + aurora_tri(p.y),
                  aurora_tri(p.y + aurora_tri(p.x)));
}
static inline float2x2 aurora_mm2(float a) {
    float c = cos(a), s = sin(a);
    return float2x2(c, -s, s, c);
}

// Five octaves of domain-warped triangular noise. Returns a positive density in
// [0, 0.55] — the load-bearing ribbon-shape function (nimitz triNoise2d). `time`
// drives the substrate evolution (whole-curtain drift, tens of seconds).
static inline float aurora_tri_noise_2d(float2 p, float spd, float time) {
    float2 bp = p;
    bp = aurora_mm2(time * 0.10) * bp;
    float z = 1.8, z2 = 2.5, rz = 0.0;
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

// Per-march-step palette (Lawlor H(z) smuggled into the loop): green base at low
// step (low altitude) → cyan/blue → magenta crown at high step. Pure function of
// march step (= altitude), never of x (research §1.2: no horizontal rainbow).
// nimitz's IQ-cosine anchor; naturalistic green-dominant with a magenta crown.
static inline float3 aurora_step_palette(int i) {
    return sin(1.0 - float3(2.15, -0.5, 1.2) + float(i) * 0.043) * 0.5 + 0.5;
}

// Volumetric aurora march. Marches an angled camera ray UP through the 3-D noise
// volume (the traversal that makes it a volume, not a slice): each step lands at
// a higher altitude and a different (x,z), so the ray crosses many filaments. The
// running-average smear coalesces samples into vertical ribbons; the exp-decay
// accumulator weights the bright low-altitude base most. `col *= clamp(rd.y…)`
// fades the aurora toward/below the horizon.
static inline float3 aurora_march(float3 ro, float3 rd, float2 sampleAdv, float time) {
    float4 avgCol = float4(0.0);
    float3 col    = float3(0.0);
    for (int i = 0; i < kAuroraSteps; i++) {
        // Polynomial step — dense (sharp detail) low, coarser (diffuse crown) high.
        float pt = (0.8 + pow(float(i), 1.4) * 0.002 - ro.y) / (rd.y * 2.0 + 0.4);
        float3 bpos = ro + pt * rd;
        // Sample the (z,x) plane at this altitude + curl/drum advection (the dance).
        float rzt = aurora_tri_noise_2d(bpos.zx * kNoiseScale + sampleAdv, kSubstrateSpd, time);
        float3 c2 = aurora_step_palette(i) * rzt;
        // Running-average vertical smear — turns samples into coherent ribbons
        // (§1.1 line 6). Higher persistence = straighter, more parallel rays.
        avgCol = mix(avgCol, float4(c2, rzt), 1.0 - kSmear);
        col += avgCol.rgb * exp2(-float(i) * 0.065 - 2.5) * smoothstep(0.0, 5.0, float(i));
    }
    col *= clamp(rd.y * 15.0 + 0.4, 0.0, 1.0);
    return col;
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

    // ── D-019 stem-warmup blend ───────────────────────────────────────────────
    float totalStemEnergy = stems.vocals_energy + stems.drums_energy
                          + stems.bass_energy   + stems.other_energy;
    float stemMix = smoothstep(kStemWarmupLow, kStemWarmupHigh, totalStemEnergy);

    // Route 2 — bass-driven brightness (positive-only deviation, D-026).
    float bassDev = mix(f.bass_dev, stems.bass_energy_dev, stemMix);

    // Route 1 — vocals-pitch palette phase (confidence-gated, smoothed CPU-side).
    float pitchConfident = step(0.5, stems.vocals_pitch_confidence);
    float pitchNorm = mix(0.5, av.smoothedPitchNorm, pitchConfident);
    float paletteOffset = (pitchNorm - 0.5) * kVocalsPitchAmp;   // [-0.4, 0.4]

    // Route (mid) — MOTION amplitude (the dance). Layer-1 continuous energy.
    float midActivity = saturate(0.5 + 0.5 * f.mid_att_rel);
    float motionAmp   = kAuroraMotionBase + kAuroraMotionGain * midActivity;

    // ── Layer 1: Sky gradient + sparse pinpoint stars ────────────────────────
    float3 topColor    = float3(0.005, 0.005, 0.010);
    float3 bottomColor = float3(0.008, 0.010, 0.020);
    float3 sky = mix(topColor, bottomColor, uv.y);

    float starField = hash_f01_2(uv * 800.0);
    float starHit   = step(0.997, starField);
    float starShade = hash_f01_2(uv * 800.0 + float2(11.7, 5.3));

    // Route 7 — half-bar star blink (Layer-4 accent on the CACHED grid; additive,
    // per-star staggered so global luminance stays steady, D-157 flash-safe;
    // fades in with stemMix so cold-start doesn't fire off-beat).
    float halfBarPhase = fract(f.bar_phase01 * 2.0);
    float starTick     = fract(halfBarPhase + starShade);
    float starBlink    = exp(-starTick * kStarBlinkDecay);
    float blinkGain    = 1.0 + kStarBlinkAmp * starBlink * stemMix;
    sky += float3(0.85, 0.92, 1.0) * starHit * (0.40 + 0.60 * starShade) * blinkGain;

    // ── Layer 2: Volumetric aurora ray-march (AV.6 — DESIGN §5.11) ────────────
    // Build a camera ray that fans UP into the sky. `kHorizon` places the horizon
    // (rd.y≈0) low in the frame so the curtain hangs down; below it rd.y<0 and the
    // march fades the aurora out (dark foreground). A slow xz rotation drifts the
    // whole sky (tens of seconds); it is coherent field motion, audio-scaled — not
    // free sin(time) primary motion (FA #33).
    float2 pp = float2((uv.x - 0.5) * kAspect, kHorizon - uv.y);
    float3 ro = float3(0.0, 0.0, kCamZ);
    float3 rd = normalize(float3(pp, kCamDepth));
    float2x2 drift = aurora_mm2(sin(time * 0.03) * 0.15 * motionAmp);
    rd.xz = drift * rd.xz;

    // Wittens curl advection (the dance, audio-scaled) + Route 5 drum kink (a
    // lateral shudder decaying on the CPU-side accumulator's 1–2 s timescale).
    float2 curlAdv = curl_noise(float3(rd.x * 1.5, rd.z * 1.5, time * 0.10)).xy
                   * (kCurlAmp * motionAmp);
    float2 kink = float2(av.kinkAccumulator * kKinkAmp, 0.0);
    float2 sampleAdv = curlAdv + kink;

    float3 aurora = aurora_march(ro, rd, sampleAdv, time);

    // Restore saturation — the running-average smear averages green→cyan→blue
    // across march steps toward grey; push back toward the dominant hue so the
    // green body reads vivid (the footage is saturated green, not grey-teal).
    float aurLum = dot(aurora, float3(0.299, 0.587, 0.114));
    aurora = max(mix(float3(aurLum), aurora, kSaturate), 0.0);

    // Large-scale concentration footprint F(x) — carves dark-sky negative space +
    // a concentrated bright region (drifts slowly). Screen-x based so the vertical
    // curtains stay coherent; curl-advected x so the silhouette dances.
    float cx = fbm4(float3(uv.x * kClusterFreq + curlAdv.x * 0.5 + time * 0.02, 5.0, 0.0));
    float conc = smoothstep(kClusterLo, kClusterHi, cx);
    aurora *= conc;

    // Hue-preserving contrast — drops the dim inter-ray haze toward black and
    // lets the bright rays pop, so the curtain reads as crisp filaments over clean
    // dark sky rather than a smoky wash. Gamma on luminance, hue held constant.
    float lumC = max(max(aurora.r, aurora.g), aurora.b);
    aurora *= (lumC > 1e-4) ? pow(lumC, kContrast) / lumC : 0.0;

    // Clean top — the sky above the curtain fades to dark (the footage has a
    // defined upper edge, not haze to the frame top). Keeps the crown band.
    aurora *= smoothstep(0.04, 0.16, uv.y);

    // White-hot cores — the densest regions bleach toward glowing green-white
    // (the footage's signature bright core), green-leaning so it stays green-
    // dominant (low R keeps the lower band off the magenta side, L2 gate).
    float coreLum = dot(aurora, float3(0.299, 0.587, 0.114));
    aurora = mix(aurora, float3(0.55, 1.0, 0.78) * coreLum * 1.4,
                 smoothstep(0.30, 0.85, coreLum) * 0.6);

    // Crown tint — the high sky (low uv.y) leans magenta/pink (the Lawlor H(z)
    // crown, ref 07), so the altitude stratification reads even though the march's
    // exp-decay weights the bright green base most (research §1.2 permits uv.y
    // indexing as the H(z) fallback). A dim magenta crown over the bright green
    // body = the naturalistic stratification.
    float crown = smoothstep(0.52, 0.06, uv.y);          // 1 at the top of the sky
    aurora = mix(aurora, aurora * float3(2.2, 0.72, 1.6) * 1.25, crown * 0.85);

    // Route 1 — vocals pitch → subtle green↔cool-teal hue tint (reads on the
    // green-dominant palette where an altitude nudge would not).
    float3 pitchTint = float3(1.0 - paletteOffset * 0.45, 1.0, 1.0 + paletteOffset * 0.75);
    aurora *= pitchTint;

    // Route 2 — brightness breathing (global bass-transient pulse).
    float bassPulse = smoothstep(kBrightnessGateLo, kBrightnessGateHi, bassDev);
    aurora *= (kBrightnessBase + kBrightnessAmp * bassPulse);

    aurora *= kAuroraGain;

    // ── Composite: additive emission over dark sky (stars punch through, FM #5).
    float3 finalColor = min(sky + aurora, float3(0.97));
    return float4(finalColor, 1.0);
}
