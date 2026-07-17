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

constant float kAuroraDebug = 0.0;   // 0 = ship · 1 = grayscale density · 2 = F(x,z) map
constant float kFpSpikeSpan = 1.4;   // spike: footprint-plane span shown across screen
                                     // (the march samples uv = rd.xz·t, |uv| ≲ 0.62)
constant int   kAuroraSteps = 48;    // samples marched along each view ray
// nimitz step distribution (research §1.1(4)): t_raw = base + i^1.4·grow — dense
// near the curtain base, coarse toward the diffuse crown. Spans 0.8 → ~1.24.
constant float kMarchBase   = 0.8;   // march start distance
constant float kMarchGrow   = 0.002; // polynomial step growth
constant float kMarchFalloff = 2.0;  // distance-scaling denominator: t = tRaw/(rd.y·2+F).
                                     // nimitz uses F=0.4, tuned for his near-horizon
                                     // camera. With our up-tilt that SATURATES the
                                     // altitude map (h≈0.25 at rd.y=0.2 vs 0.40 at 0.86)
                                     // — the whole frame collapses to one altitude and
                                     // green gets squeezed to a strip. F=2.0 spreads
                                     // h across ~0.02…0.29 over the elevation window.
constant float kCrownH      = 0.286; // altitude of the magenta crown (H(z) ceiling);
                                     // = the altitude the steepest in-frame ray reaches
constant float kCrownCurve  = 1.5;   // H(z) index curve: >1 holds green across most of
                                     // the altitude range, violet only at the tips
constant float kAuroraGain  = 9.0;   // emission gain
constant float kToneFloor   = 0.0012; // subtract murk to black (just above measured linear dlum avg 0.00095)
constant float kToneScale   = 68.0;   // stretch survivors: 0.9/(peak0.0144−floor0.0012)

// Footprint F(uv) — the 2-D ground-plane flux map (Lawlor F(x,z)), rebuilt as a
// localized BAND (the auroral arc), not isotropic noise. The F-map spike proved
// the old tri-noise×fbm concentration was scattered mottle islands → streaks
// strewn across the sky, pebbly rays, and amplitude ~0.03/0.55. The band gives a
// coherent curtain over dark negative space, striations that extrude into rays,
// and full amplitude.
constant float kFoldScale     = 2.5;  // curl-fold spatial scale
constant float kFoldAmp        = 0.35; // curl-fold strength (drapery + dance)
constant float kSubstrateSpd   = 0.06; // per-octave noise rotation
// Band shape:
constant float kBandHalfWidth  = 0.16; // across-band soft half-width (curtain depth)
constant float kBandMeanderAmp = 0.10; // centerline meander amplitude (the arc's sway)
constant float kBandMeanderFrq = 1.15; // centerline meander frequency
constant float kBandDrift      = 0.04; // slow centerline drift (dance; ≪ half-width)
constant float kStriationFreq  = 8.5;  // along-band filament density (the rays)
constant float kStriationAniso = 0.22; // across-band coherence (rays hold together)
constant float kStriationAdv   = 0.15; // fraction of curl adv applied to filaments only
constant float kBandFloor      = 0.40; // lit curtain body between filaments (band supplies
                                       // brightness; ridges lift to 1.0 as the rays)

// Emission height profile D(h): sharp lower onset, long tail up (Lawlor D(h)).
constant float kDepOnset = 0.05;     // sharp lower emission edge — the curtain's bright
                                     // green BASE. Sits above the horizon so the rays
                                     // read as ASCENDING from a visible base, with dark
                                     // sky below it (ref video, Matt 2026-07-16).
constant float kDepDecay = 3.0;      // fade upward along the ascending rays

// Camera — looks UP so the world-vertical field axis projects to the magnetic
// zenith high on/above the frame; the stepUV=rd.xz/rd.y column march then makes
// the rays converge there (the corona/curtain perspective, not a flat band).
constant float kAspect    = 1.777;   // 16:9
// Up-tilt chosen so the BOTTOM of the frame sits on the horizon: tan(pitch) =
// 0.5·kFov → the frame spans ~0°…60° elevation. The wide elevation window is what
// lets the distance march separate colour by height (a narrow 28°…88° window put
// rd.y in 0.55…1.0 — too small a spread to tell green from magenta). The magnetic
// zenith / vanishing point now sits just ABOVE the frame, matching ref_240.
constant float kLookPitch = 0.52;    // camera up-tilt (radians ~30°)
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

// Footprint F(uv) — the 2-D ground-plane flux map as a BAND (the auroral arc).
// A meandering centerline carves a soft-edged strip (bright core → dark sky
// outside = real negative space); anisotropic striations inside it (fine along the
// band, coherent across) are the filaments that extrude into rays. Curl-advected
// so the arc sways and folds (the dance). Amplitude runs to the tri-noise ceiling.
static inline float aurora_footprint(float2 uv, float motionAmp, float time) {
    // Band membership on GENTLY-drifted coords. The arc sways slowly (the dance);
    // it must NOT be scattered — a displacement larger than the band half-width
    // dissolves the band into all-over mottle (learned: the full curl adv ±0.5 ≫
    // half-width 0.2 erased the strip). Drift is a small fraction of the width.
    float drift  = kBandDrift * curl_noise(float3(uv * 0.8, time * 0.08)).x;
    float center = kBandMeanderAmp * sin(uv.x * kBandMeanderFrq + time * 0.05)
                 + kBandMeanderAmp * 0.45 * sin(uv.x * kBandMeanderFrq * 2.3 - time * 0.04)
                 + drift;
    float d    = uv.y - center;
    float band = exp(-(d * d) / (kBandHalfWidth * kBandHalfWidth));

    // Striations MODULATE the band (they don't supply its brightness — the nimitz
    // ridged noise is sparse, ~0.03 avg). Advected only modestly so filaments
    // shimmer without scattering the band. Anisotropic: fine along the band (many
    // rays), stretched across (coherent). Body = kBandFloor, ridges lift to 1.0.
    float2 adv = curl_noise(float3(uv * kFoldScale, time * 0.12)).xy
               * (kFoldAmp * (0.5 + motionAmp) * kStriationAdv);
    float2 sp = float2((uv.x + adv.x) * kStriationFreq, d / kStriationAniso);
    float filament = aurora_tri_noise_2d(sp, kSubstrateSpd, time) / 0.55; // [0,1] ridges
    float texture  = mix(kBandFloor, 1.0, filament);

    return band * texture;
}

// Height-deposition D(h) — sharp onset at the emission floor (crisp lower edge),
// long tail up (Lawlor). Brightest at the low green body, fading toward the crown.
static inline float aurora_deposition(float h) {
    return smoothstep(0.0, kDepOnset, h) * exp(-h * kDepDecay);
}

// Colour by ALTITUDE (Lawlor H(z)) — the nimitz per-march-step IQ-cosine palette,
// ported verbatim (research §1.1 load-bearing element (c), §1.2). Green base →
// pale cyan → magenta crown: t=0 → (0.04, 1.00, 0.40), t=0.5 → (0.46, 0.77, 0.88),
// t=1 → (0.91, 0.27, 0.97).
//
// `t` is the MARCH-STEP FRACTION (i / steps-1), not an absolute world height. That
// is the point: the ramp always spans the full range the column traverses, so it
// cannot fall out of register with the marched altitudes. The AV.5 palette keyed
// smoothstep thresholds off absolute h and put magenta at h > 0.98 — above the
// marched ceiling of ~0.864 — so the crown was unreachable and the curtain could
// only ever read green (AV.6, Matt M7: "the aurora is more than green").
static inline float3 aurora_height_palette(float t) {
    return sin(1.0 - float3(2.15, -0.5, 1.2) + t * 2.107) * 0.5 + 0.5;
}

// Emission march along the view ray, parameterized by DISTANCE (nimitz traversal),
// not by a fixed altitude range:  pos = rd·t  →  uv = rd.xz·t,  h = rd.y·t.
//
// The line through footprint space is identical to the altitude-parameterized form
// (uv = (rd.xz/rd.y)·h), so the perspective convergence is preserved — rays still
// fan down from the magnetic zenith. What changes is the altitude each ray REACHES:
// it now scales with rd.y, so low-elevation rays stay in the green emission base
// while steep rays climb into the magenta crown. That elevation→colour coupling is
// impossible under a fixed h range (every pixel integrated the identical altitude
// span, so colour could not vary with elevation — AV.6, Matt M7).
//
// It also bounds the footprint sweep: at the horizon rd.y→0 sent dirUV=rd.xz/rd.y→∞
// and the column aliased across unbounded uv.
//
// The 1/(rd.y·2+0.4) distance scaling is nimitz's, adopted verbatim (research
// §1.1(4)) and it is load-bearing twice over:
//   • Shallow rays march FARTHER, so they still reach the emission layer (which
//     starts at h≈kDepOnset) at distance — without it they never get there within a
//     fixed march and the aurora tears off the horizon into a ragged fringe.
//   • It makes each ray sample a NARROW altitude band whose height tracks rd.y
//     (h = rd.y·t_raw/(rd.y·2+0.4) → ~0.08 at the horizon, ~0.50 at frame top). A
//     narrow band per ray is what gives a clean elevation→colour read: green base
//     low, magenta crown high, instead of every pixel blending the whole H(z) range.
static inline float3 aurora_march(float3 rd, float2 kink, float motionAmp, float time) {
    if (rd.y < 0.01) return float3(0.0);           // at/below horizon: no aurora
    float3 col = float3(0.0);
    float  acc = 0.0;
    for (int i = 0; i < kAuroraSteps; i++) {
        float  tRaw = kMarchBase + pow(float(i), 1.4) * kMarchGrow;
        float  t    = tRaw / (rd.y * 2.0 + kMarchFalloff);
        float2 uv   = rd.xz * t + kink;
        float  h    = rd.y * t;                    // altitude reached ∝ elevation
        float  d    = aurora_footprint(uv, motionAmp, time) * aurora_deposition(h);
        acc = mix(acc, d, 0.5);                    // running smear → coherent rays
        // Palette by ALTITUDE (Lawlor H(z)) — under distance marching the step index
        // no longer maps to a height, so H(z) must key off h itself.
        // exp-decay accumulation weight + ramp-in (nimitz §1.1(7)) bounds the sum.
        col += aurora_height_palette(pow(saturate(h / kCrownH), kCrownCurve))
             * acc * exp2(-float(i) * 0.065 - 2.5) * smoothstep(0.0, 5.0, float(i));
    }
    return col * clamp(rd.y * 15.0 + 0.4, 0.0, 1.0);  // nimitz horizon fade
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

    // ── SPIKE (kAuroraDebug == 2): render the footprint F(x,z) alone as a flat 2-D
    // map over the ground plane — no march, no camera. Go/no-go for the band
    // rebuild: does F read as a coherent arc with striations over dark negative
    // space? Grayscale = F directly (now full-amplitude, no boost needed).
    if (kAuroraDebug > 1.5) {
        float2 fpUV = (uv - 0.5) * kFpSpikeSpan;
        float  fp   = aurora_footprint(fpUV, motionAmp, time);
        return float4(saturate(fp), saturate(fp), saturate(fp), 1.0);
    }
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
    // Gated on GREEN-DOMINANCE: the bleach target is a fixed green-white, so applied
    // to the violet crown it dragged the hue to grey (AV.6, Matt 2026-07-16 — "rays
    // should be ascending", crown washing out). Only the green base bleaches now;
    // where r/b exceed g (the crown) the mix weight falls to zero and violet survives.
    float greenDom = saturate((aurora.g - max(aurora.r, aurora.b)) * 2.0);
    aurora = mix(aurora, float3(0.62, 1.0, 0.85) * coreLum * 1.35,
                 smoothstep(0.4, 1.05, coreLum) * 0.55 * greenDom);

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
