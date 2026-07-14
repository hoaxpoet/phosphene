// AuroraVeil.metal — Direct-fragment aurora preset (dancing-centers + volumetric
// filament texture).
//
// **AV.6 (2026-07-14, Matt) — dancing-centers core.** Matt's essence of aurora
// behaviour: the aurora is many discrete bright CENTERS, each STRETCHED vertically
// (mostly UP — the light is pulled upward into rays), each MOVING around, its
// brightness FLUCTUATING, in DIFFERENT COLOURS — all dancing rhythmically to the
// music while the stars keep time. So the render is two layers:
//   • CENTERS (`aurora_centers`) — the composition, colour, motion, brightness:
//     overlapping wide soft cores that drift (audio-scaled), pulse (own phase +
//     bass flare), coloured by altitude (green base → magenta crown) with per-
//     centre hue offsets. The bright moving cores are the "dance".
//   • MARCH TEXTURE (`aurora_march_density`) — a scalar filament density from a
//     nimitz volumetric ray-march (angled ray `ro+rd·t` UP through a 3-D noise
//     volume so it crosses many filaments at many depths → real depth + fine
//     rays). It carves the smooth centre field into fine filaments.
// aurora = centers × marchDensity. This is the nimitz recipe ported CORRECTLY
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
constant float kAuroraGain  = 13.0;  // final emission gain
constant float kNoiseScale  = 2.2;   // sample-plane scale (higher = finer filaments)
constant float kSmear       = 0.62;  // running-average persistence (higher = more coherent rays)
constant float kContrast    = 1.22;  // hue-preserving contrast (crisps rays, kills inter-ray haze)

// Dancing CENTERS (Matt's essence, 2026-07-14) — the aurora is many discrete
// bright centers, each STRETCHED vertically (mostly UP, pulling the light into
// rays), each MOVING around, brightness FLUCTUATING, in DIFFERENT COLOURS, all
// dancing rhythmically to the music. The centers ARE the composition / colour /
// motion / brightness; the march texture carves them into fine filaments.
constant int   kNumCenters = 14;     // how many bright centers in the sky
constant float kCoreW      = 0.13;   // horizontal core width — WIDE so centers overlap into a
                                     // continuous curtain with moving bright regions (the march
                                     // carves the fine rays; narrow cores read as discrete blobs)
constant float kStretchUp  = 0.30;   // vertical stretch UP (light pulled upward; fades so tops go faint)
constant float kStretchDn  = 0.11;   // vertical stretch down (short)
constant float kDriftAmp   = 0.11;   // how far a center wanders
constant float kDriftSpd   = 0.20;   // wander speed
constant float kPulseSpd   = 0.60;   // brightness-fluctuation speed
// Center DISTORTION — as a center is pulled/stretched, its stretch LEANS and
// CURLS (per-center, time-varying), so it billows like mist and writhes (the
// dance). A straight stretch reads as falling water; a distorted one as aurora.
constant float kShearAmp   = 0.055;  // how hard the stretch curls sideways
constant float kDistFreq   = 5.0;    // vertical wavelength of the curl
constant float kDistSpd    = 0.30;   // how fast the curl writhes (the dance rate)
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
constant float kCurlAmp          = 0.55;   // curl advection of the sample coord (billowing, not straight)
constant float kSubstrateSpd     = 0.06;   // per-octave noise rotation rate (nimitz spd)

// ── Audio routing constants (design §5.7, preserved) ─────────────────────────
constant float kStemWarmupLow  = 0.02;
constant float kStemWarmupHigh = 0.06;
constant float kVocalsPitchAmp = 0.8;      // vocals pitch → hue-tint magnitude
constant float kBrightnessGateLo = 0.18;   // bass-pulse gate (flares the centers)
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

// Green-dominant altitude palette (Lawlor H(z)): green body → blue-violet mid →
// magenta crown. Pure function of the altitude index `a`∈[0,1] (0 low/green, 1
// high/magenta). Bright cyan-white cores come from the luminance boost, not here.
static inline float3 aurora_palette(float a) {
    const float3 green   = float3(0.12, 1.00, 0.46);
    const float3 blue    = float3(0.28, 0.42, 0.95);
    const float3 magenta = float3(0.95, 0.38, 0.74);
    float3 c = mix(green, blue,    smoothstep(0.62, 0.90, a));
    return     mix(c,     magenta, smoothstep(0.90, 1.00, a));
}

// Volumetric march — SCALAR filament-density texture (depth + fine rays). Marches
// an angled camera ray UP through the 3-D noise volume so it crosses many
// filaments at many depths (the traversal that makes it a volume, not a slice —
// the AV.5 wash marched one fixed column). Running-average smear → coherent
// vertical ribbons; exp-decay weights the bright low-altitude base; the rd.y
// clamp fades toward the horizon. Colour is supplied by the CENTERS, not here.
static inline float aurora_march_density(float3 ro, float3 rd, float2 sampleAdv, float time) {
    float avg = 0.0, d = 0.0;
    for (int i = 0; i < kAuroraSteps; i++) {
        float pt = (0.8 + pow(float(i), 1.4) * 0.002 - ro.y) / (rd.y * 2.0 + 0.4);
        float3 bpos = ro + pt * rd;
        float rzt = aurora_tri_noise_2d(bpos.zx * kNoiseScale + sampleAdv, kSubstrateSpd, time);
        avg = mix(avg, rzt, 1.0 - kSmear);
        d  += avg * exp2(-float(i) * 0.065 - 2.5) * smoothstep(0.0, 5.0, float(i));
    }
    return d * clamp(rd.y * 15.0 + 0.4, 0.0, 1.0);
}

// Dancing CENTERS (Matt's essence, 2026-07-14). Sums many bright centers, each a
// core STRETCHED vertically (long UP, short down, thin across — the light pulled
// upward into a ray), each MOVING on its own slow orbit (audio-scaled → dances
// harder with the music), brightness FLUCTUATING on its own phase (+bass flare),
// coloured by fragment altitude (stratification: green base → magenta crown) with
// a per-center hue offset so the centers differ in colour. Returns the summed
// colour×intensity; the march density carves it into fine filaments.
static inline float3 aurora_centers(float2 uv, float motionAmp, float bassPulse, float time) {
    float3 sum = float3(0.0);
    for (int i = 0; i < kNumCenters; i++) {
        float fi = float(i);
        float h1 = hash_f01_2(float2(fi, 1.3));
        float h2 = hash_f01_2(float2(fi, 2.7));
        float h3 = hash_f01_2(float2(fi, 5.9));
        float h4 = hash_f01_2(float2(fi, 7.1));
        float2 base  = float2(0.06 + h1 * 0.88, 0.32 + h2 * 0.36);
        float2 orbit = float2(sin(time * kDriftSpd * (0.6 + h3) + fi * 2.0),
                              cos(time * kDriftSpd * (0.5 + h4) + fi * 1.3));
        float2 c = base + orbit * kDriftAmp * (0.4 + 0.6 * motionAmp);

        float2 local = uv - c;
        // DISTORTION — the stretch leans + curls as it rises (per-center phase,
        // writhing over time), so the center billows like mist and dances instead
        // of falling straight like water. Amplitude grows with the music.
        float lean = kShearAmp * sin(local.y * kDistFreq + time * kDistSpd * (2.0 + 4.0 * h3) + fi * 1.7)
                   + kShearAmp * 0.5 * sin(local.y * kDistFreq * 2.3 - time * kDistSpd * 5.0 + fi);
        local.x -= lean * (0.5 + 0.8 * motionAmp);

        float wy = (local.y < 0.0) ? kStretchUp : kStretchDn;
        float glow = exp(-local.x * local.x / (kCoreW * kCoreW))
                   * exp(-local.y * local.y / (wy * wy));
        float pulse = (0.40 + 0.60 * (0.5 + 0.5 * sin(time * kPulseSpd * (0.6 + h3) + fi * 3.7)))
                    * (0.85 + 0.6 * bassPulse);

        // Colour along THIS center's own stretch — green at the core, magenta only
        // toward the top of its stretch. Per-center + ragged → no horizontal band.
        float along = saturate(-local.y / kStretchUp);      // 0 core → 1 top of stretch
        float3 ccol = aurora_palette(saturate(along * along * 1.15 + (h4 - 0.5) * 0.16));
        sum += ccol * glow * pulse;
    }
    return sum;
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

    // Filament-density texture (depth + fine rays) — the march (scalar, uncoloured).
    float density = aurora_march_density(ro, rd, sampleAdv, time);

    // Route 2 — bass-transient pulse (also flares the dancing centers' brightness).
    float bassPulse = smoothstep(kBrightnessGateLo, kBrightnessGateHi, bassDev);

    // Dancing CENTERS provide colour / composition / motion / brightness; the march
    // density carves them into fine filaments. This is the aurora's essence: bright
    // centers pulled upward into rays, moving + pulsing + coloured, dancing.
    float3 centers = aurora_centers(uv, motionAmp, bassPulse, time);
    float3 aurora  = centers * density;

    // Hue-preserving contrast — crisp rays over clean dark sky (kills inter-ray haze).
    float lumC = max(max(aurora.r, aurora.g), aurora.b);
    aurora *= (lumC > 1e-4) ? pow(lumC, kContrast) / lumC : 0.0;

    // Clean top edge — sky above the curtain fades to dark (keeps the crown band).
    aurora *= smoothstep(0.04, 0.16, uv.y);

    // White-hot cores — the densest centers bleach toward glowing green-white (the
    // footage's signature bright core), green-leaning (low R+B keeps the lower band
    // green-dominant, L2 gate).
    float coreLum = dot(aurora, float3(0.299, 0.587, 0.114));
    aurora = mix(aurora, float3(0.60, 1.0, 0.82) * coreLum * 1.4,
                 smoothstep(0.35, 0.95, coreLum) * 0.6);

    // Route 1 — vocals pitch → subtle green↔cool-teal hue tint.
    float3 pitchTint = float3(1.0 - paletteOffset * 0.45, 1.0, 1.0 + paletteOffset * 0.75);
    aurora *= pitchTint;

    aurora *= kAuroraGain;

    // ── Composite: additive emission over dark sky (stars punch through, FM #5).
    float3 finalColor = min(sky + aurora, float3(0.97));
    return float4(finalColor, 1.0);
}
