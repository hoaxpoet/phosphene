// AuroraVeil.metal — Direct-fragment aurora preset (footprint-extrusion column
// march with perspective convergence to the magnetic zenith).
//
// **AV.6 (2026-07-14, Matt) — perspective-convergence rebuild.** Real aurora rays
// are world-VERTICAL, field-aligned columns; the "curtain of rays converging to a
// point high in the sky" (Matt's reference) is pure PERSPECTIVE — parallel
// vertical rays converging to their vanishing point, the magnetic zenith. Every
// prior AV.6 core (flat streaks, nimitz plane-stack march, dancing centers) read
// as a flat horizontal band because it lacked that convergence — the nimitz march
// I ported inherits nimitz's horizon-band camera (rd.y stays small, aurora clamped
// to a band; desk research 2026-07-14).
//
// The fix (Lawlor & Genetti 2010 factorization + Wittens NeverSeenTheSky operator):
//   1. Camera LOOKS UP so the world-vertical axis projects to a vanishing point
//      high on/above the frame.
//   2. March a VERTICAL COLUMN through the emission volume, stepping the 2-D
//      footprint UV by  stepUV = rd.xz / rd.y · dH  per altitude shell. This is
//      the whole game: looking up (rd.y→1) → stepUV→0 → the column stays put in
//      footprint space → a tight vertical ray converging to the zenith; toward the
//      horizon (rd.y→0) → stepUV→∞ → rays smear into a band. Adjacent pixels
//      diverge with height → the rays FAN downward and CONVERGE upward (the corona).
//   3. Emission = footprint F(uv) × height-deposition D(h). Colour by HEIGHT
//      (green body at the bright descending base → blue → magenta crown at the
//      converging top), never by a flat screen line — so there is no colour band.
//
// Footprint F: nimitz triangular domain-warped noise (folded curtains, sharp
// filament edges — not fbm pillow-fog FM #8), curl-advected + animated → the
// drapery folds and the dance. Running-average vertical smear coalesces the shells
// into coherent rays. The bright cyan-white cores come from a luminance boost at
// the emission peak.
//
// Preserved from AV.5: audio routes + `audio_routes` manifest (vocals→hue tint,
// bass→brightness, drums→kink, mid→motion), half-bar star blink, `AuroraVeilState`
// (slot 6). mv_warp NOT used (`passes: []`; it washes out the filaments).
//
// Scope (Matt 2026-07-14): CURTAIN of rays (zenith just above the frame).
//
// Reference: real-time aurora footage (Screen Recording 2026-07-14) → stills
// 10/11/12 + the corona frame; the `.mov` is the motion reference.
// Design: docs/presets/AURORA_VEIL_DESIGN.md §5.11. Research:
// docs/presets/AURORA_VEIL_RESEARCH_2026-05-18.md §1.1–1.4 + the AV.6 desk-research
// findings (Wittens stepUV operator, Lawlor F(x,z)×D(h), field-aligned extrusion).
//
// CLEAN-ROOM MSL from the nimitz "Auroras" (Shadertoy XtGGRt, CC-BY-NC-SA), Lawlor
// & Genetti (WSCG 2011), and Wittens NeverSeenTheSky published descriptions.
// Rubric profile: lightweight (D-067(b)). L1–L4 + 9-question rubric apply.

// ── Constants ─────────────────────────────────────────────────────────────────

constant float kAuroraDebug = 0.0;   // debug off
constant int   kAuroraSteps = 48;    // vertical shells marched per column
constant float kShellDH     = 0.018; // altitude per shell
constant float kBaseShell   = 1.0;   // starting shell (near the emission floor)
constant float kAuroraGain  = 9.0;   // emission gain
constant float kToneFloor   = 0.0044; // subtract murk to black (just above measured linear dlum avg 0.0035)
constant float kToneScale   = 43.0;   // stretch survivors: 0.9/(peak0.0252−floor0.0044)

// Footprint F(uv) — the 2-D curtain map extruded upward. Ridged domain-warped
// triangle noise (folded curtains), curl-advected + animated (drapery + dance).
constant float kFootprintFreq = 5.5; // curtain density across the sky
constant float kFoldScale     = 2.5; // curl-fold spatial scale
constant float kFoldAmp        = 0.35; // curl-fold strength (drapery + dance)
constant float kSubstrateSpd   = 0.06; // per-octave noise rotation
constant float kConcFreq       = 1.9; // large-scale concentration frequency (curtain placement)
constant float kFpLo           =  0.05; // concentration threshold: below → dark sky (fbm4 is ~[-1,1])
constant float kFpHi           =  0.40; // above → inside a curtain region

// Emission height profile D(h): sharp lower onset, long tail up (Lawlor D(h)).
constant float kDepOnset = 0.10;     // sharp lower emission edge (green base)
constant float kDepDecay = 0.85;     // long fade up (soft enough that the blue/
                                     // magenta crown survives the base's dominance)

// Camera — looks UP so the world-vertical field axis projects to the magnetic
// zenith high on/above the frame; the stepUV=rd.xz/rd.y column march then makes
// the rays converge there (the corona/curtain perspective, not a flat band).
constant float kAspect    = 1.777;   // 16:9
constant float kLookPitch = 1.02;    // camera up-tilt (radians ~58°) → zenith just above frame
constant float kFov       = 1.15;    // vertical field-of-view scale

// ── Motion (the dance) ───────────────────────────────────────────────────────
constant float kAuroraMotionBase = 0.35;   // motion amplitude at silence
constant float kAuroraMotionGain = 0.65;   // additional from mid activity

// ── Audio routing constants (design §5.7, preserved) ─────────────────────────
constant float kStemWarmupLow  = 0.02;
constant float kStemWarmupHigh = 0.06;
constant float kVocalsPitchAmp = 0.8;      // vocals pitch → hue-tint magnitude
constant float kBrightnessGateLo = 0.18;   // bass-pulse gate (flares the aurora)
constant float kBrightnessGateHi = 0.50;
constant float kKinkAmp          = 0.007;  // drum-kink lateral shudder (bounded fold, D-157)
constant float kKinkBandCenter   = 0.55;   // screen-y center of the localized fold
constant float kKinkBandWidth    = 0.045;  // fold half-width (bounds the beat footprint)
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

// Five octaves of domain-warped triangular noise (nimitz triNoise2d) — the folded
// ridged filament field. `time` animates the folds (whole-curtain drift).
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

// Footprint F(uv) — the 2-D ground-plane curtain map. Ridged folded triangle noise
// (the curtains), curl-advected + animated so the folds drape and the whole thing
// dances (audio-scaled). The negative space is the dark between the ridges.
static inline float aurora_footprint(float2 uv, float motionAmp, float time) {
    float2 adv = curl_noise(float3(uv * kFoldScale, time * 0.12)).xy
               * (kFoldAmp * (0.5 + motionAmp));
    float raw = aurora_tri_noise_2d(uv * kFootprintFreq + adv, kSubstrateSpd, time);
    // Large-scale concentration carves the negative space (where the curtains are
    // vs dark sky); the raw triNoise supplies the fine filament texture within.
    float conc = smoothstep(kFpLo, kFpHi,
                     fbm4(float3(uv * kConcFreq + adv * 0.5, 3.0)));
    return raw * conc;
}

// Height-deposition D(h) — sharp onset at the emission floor (crisp lower edge),
// long tail up (Lawlor). Brightest at the low green body, fading toward the crown.
static inline float aurora_deposition(float h) {
    return smoothstep(0.0, kDepOnset, h) * exp(-h * kDepDecay);
}

// Colour by HEIGHT (Lawlor H(z)): green body → blue mid → magenta crown. Pure
// function of world altitude along the ray (not a screen line) → no colour band.
//
// Thresholds are mapped onto the range the march ACTUALLY traverses:
// h ∈ [kBaseShell·kShellDH, (kBaseShell+kAuroraSteps-1)·kShellDH] ≈ [0.018, 0.864].
// (AV.6 fix: the AV.5 thresholds put magenta at h > 0.98 — above the marched
// ceiling — so the crown was unreachable and the curtain read all-green.)
static inline float3 aurora_height_palette(float h) {
    const float3 green   = float3(0.11, 1.00, 0.46);
    const float3 blue    = float3(0.30, 0.48, 1.00);
    const float3 magenta = float3(0.95, 0.40, 0.74);
    // Transitions sit in the UPPER third of the marched range: each pixel sums its
    // whole column, so an early green→blue crossover desaturates the entire curtain
    // (the green body must stay dominant, L2 gate). Violet is the crown only.
    float3 c = mix(green, blue,    smoothstep(0.42, 0.70, h));
    return     mix(c,     magenta, smoothstep(0.70, 0.86, h));
}

// Footprint-extrusion column march (Wittens operator). Marches a VERTICAL column
// through the emission volume: at each altitude shell it samples the footprint at
// uv += rd.xz/rd.y·dH — the convergence operator that makes looking-up rays tight
// and vertical (converging to the zenith) and horizon rays smear. Emission =
// footprint × deposition; running-average smear coalesces shells into rays.
static inline float3 aurora_march(float3 rd, float2 kink, float motionAmp, float time) {
    if (rd.y < 0.03) return float3(0.0);          // at/below horizon: no aurora
    float2 dirUV  = rd.xz / rd.y;                  // horizontal move per unit height
    float2 stepUV = dirUV * kShellDH;
    float2 uv     = dirUV * (kBaseShell * kShellDH) + kink;
    float3 col = float3(0.0);
    float  acc = 0.0;
    for (int i = 0; i < kAuroraSteps; i++) {
        float h = (kBaseShell + float(i)) * kShellDH;
        float d = aurora_footprint(uv, motionAmp, time) * aurora_deposition(h);
        acc = mix(acc, d, 0.5);                    // running vertical smear → rays
        // exp-decay accumulation weight (nimitz) — bounds the 48-shell sum and
        // weights the bright low base most; without it the column blows out. Rate
        // softened (0.055 → 0.035) so the upper shells still carry visible blue /
        // magenta instead of being drowned by the green base.
        col += aurora_height_palette(h) * acc * exp2(-float(i) * 0.035 - 2.0);
        uv += stepUV;
    }
    return col * smoothstep(0.03, 0.14, rd.y);     // soft horizon fade
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
    float  time = f.time;

    // ── D-019 stem-warmup blend ───────────────────────────────────────────────
    float totalStemEnergy = stems.vocals_energy + stems.drums_energy
                          + stems.bass_energy   + stems.other_energy;
    float stemMix = smoothstep(kStemWarmupLow, kStemWarmupHigh, totalStemEnergy);

    float bassDev = mix(f.bass_dev, stems.bass_energy_dev, stemMix);
    float pitchConfident = step(0.5, stems.vocals_pitch_confidence);
    float pitchNorm = mix(0.5, av.smoothedPitchNorm, pitchConfident);
    float paletteOffset = (pitchNorm - 0.5) * kVocalsPitchAmp;
    float midActivity = saturate(0.5 + 0.5 * f.mid_att_rel);
    float motionAmp   = kAuroraMotionBase + kAuroraMotionGain * midActivity;
    float bassPulse   = smoothstep(kBrightnessGateLo, kBrightnessGateHi, bassDev);

    // ── Layer 1: Sky gradient + sparse pinpoint stars ────────────────────────
    float3 topColor    = float3(0.005, 0.005, 0.010);
    float3 bottomColor = float3(0.008, 0.010, 0.020);
    float3 sky = mix(topColor, bottomColor, uv.y);

    float starField = hash_f01_2(uv * 800.0);
    float starHit   = step(0.997, starField);
    float starShade = hash_f01_2(uv * 800.0 + float2(11.7, 5.3));
    float halfBarPhase = fract(f.bar_phase01 * 2.0);
    float starTick     = fract(halfBarPhase + starShade);
    float starBlink    = exp(-starTick * kStarBlinkDecay);
    float blinkGain    = 1.0 + kStarBlinkAmp * starBlink * stemMix;
    sky += float3(0.85, 0.92, 1.0) * starHit * (0.40 + 0.60 * starShade) * blinkGain;

    // ── Layer 2: Perspective-convergence aurora column march ──────────────────
    // Camera looks UP so world-vertical rays converge to the zenith high on/above
    // the frame. sp: screen coords, y up (+top). rd fans from the pitched-up view.
    float2 sp = float2((uv.x - 0.5) * kAspect, 0.5 - uv.y);
    float  cp = cos(kLookPitch), spi = sin(kLookPitch);
    float3 fwd   = float3(0.0, spi,  cp);
    float3 right = float3(1.0, 0.0,  0.0);
    float3 upv   = float3(0.0, cp,  -spi);
    float3 rd = normalize(fwd + sp.x * kFov * right + sp.y * kFov * upv);

    // Route 5 — drum kink: a lateral fold shudder, localized to a screen-y band so
    // the beat footprint stays bounded (D-157) — a fold travels through the curtain
    // rather than sliding the whole thing (which would swamp the continuous routes).
    float kinkWin = exp(-pow((uv.y - kKinkBandCenter) / kKinkBandWidth, 2.0));
    float2 kink = float2(av.kinkAccumulator * kKinkAmp * kinkWin, 0.0);

    float3 aurora = aurora_march(rd, kink, motionAmp, time) * kAuroraGain;

    // Tone map — the density sits on a dim non-zero floor (the murk) with sparse
    // brighter rays. Subtract the floor to true black (real negative space) then
    // scale the survivors up (pop the rays). Hue held. Measured: raw luminance
    // spans ~0.06–0.19, so the floor sits just above the murk.
    float dlum = dot(aurora, float3(0.35, 0.55, 0.45));
    float toned = max(dlum - kToneFloor, 0.0) * kToneScale;
    aurora *= (dlum > 1e-4) ? toned / dlum : 0.0;

    // White-hot cores — the densest/brightest regions bleach toward glowing
    // green-white (the footage's bright core), green-leaning (low R+B keeps the
    // green body green-dominant, L2 gate).
    float coreLum = dot(aurora, float3(0.299, 0.587, 0.114));
    aurora = mix(aurora, float3(0.62, 1.0, 0.85) * coreLum * 1.35,
                 smoothstep(0.4, 1.05, coreLum) * 0.55);

    // Route 1 — vocals pitch → subtle green↔cool-teal hue tint.
    float3 pitchTint = float3(1.0 - paletteOffset * 0.45, 1.0, 1.0 + paletteOffset * 0.75);
    aurora *= pitchTint;

    // Route 2 — brightness breathing (bass transients flare the whole curtain). Wide
    // swing with headroom below so the continuous route carries real amplitude (must
    // dominate the beat-kink accent by ≥10×, §5.7).
    aurora *= (0.62 + 0.9 * bassPulse);

    // ── Composite: additive emission over dark sky (stars punch through, FM #5).
    float3 finalColor = min(sky + aurora, float3(0.97));
    // DEBUG (AURORA_DEBUG): grayscale density view to see ray structure.
    if (kAuroraDebug > 0.5) {
        float g = dot(aurora, float3(0.4, 0.6, 0.5));
        return float4(float3(saturate(g)), 1.0);
    }
    return float4(finalColor, 1.0);
}
