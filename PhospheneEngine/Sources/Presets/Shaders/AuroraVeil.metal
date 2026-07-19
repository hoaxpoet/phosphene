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
// **AV.6 ORGANIC ray generator (2026-07-18, Matt).** Earlier AV.6 cores failed as
// either FOG (isotropic noise-as-footprint), clean SPOTLIGHT BEAMS (geometric ridges),
// or HAZE (over-soft). The working recipe is ORGANIC anisotropic noise in the
// convergence frame — `aurora_rays`: fine multi-octave striation FINE across the
// curtain (angle) but COHERENT along each ray (low radial freq) → soft vertical
// filaments (ref 11), plus a large-scale CONCENTRATION field (irregular glowing masses
// / dim gaps) so it clumps like real aurora, on a soft luminous body. angle/radius are
// about the convergence point (atan2(rd.z,rd.x) is t-invariant → rays fan from the
// vanishing point). A soft angular SECTOR gives negative space; D(h) the base-bright
// fade; a crown fade the faint crown. Colour is elevation-tilted (§5.11) so it tracks
// SCREEN height: green base → violet crown. Bright green concentrations bleach toward
// cyan-white cores. (Not clean ridges, not isotropic tri-noise — those are the failures.)
//
// Preserved from AV.5: audio routes + `audio_routes` manifest (vocals→hue tint,
// bass→brightness, drums→kink, mid→motion), half-bar star blink, `AuroraVeilState`
// (slot 6). mv_warp NOT used (`passes: []`; it washes out the filaments).
//
// Scope (Matt 2026-07-14): overhead CURTAIN of rays (zenith just above the frame).
//
// Reference: real-time aurora footage (Screen Recording 2026-07-14) → stills
// 10/11/12 + `/tmp/aurora_ref/ref_240.png` (overhead-curtain target); the `.mov` is
// the motion reference. Design: docs/presets/AURORA_VEIL_DESIGN.md §5.11–5.12.
// Research: docs/presets/AURORA_VEIL_RESEARCH_2026-05-18.md §1.1–1.4.
//
// CLEAN-ROOM MSL grounded in Lawlor & Genetti (WSCG 2011, F(x,z)×D(h) factorization)
// and Wittens NeverSeenTheSky published descriptions. (The nimitz "Auroras" traversal
// informed earlier cores but its tri-noise footprint is retired — see above.)
// Rubric profile: lightweight (D-067(b)). L1–L4 + 9-question rubric apply.

// ── Constants ─────────────────────────────────────────────────────────────────

constant float kAuroraDebug = 0.0;   // 0 = ship · 1 = grayscale density · 2 = F(x,z) map
constant float kFpSpikeSpan = 1.4;   // spike: footprint-plane span shown across screen
                                     // (the march samples uv = rd.xz·t, |uv| ≲ 0.62)
constant int   kAuroraSteps = 20;    // samples marched along each view ray
// nimitz step distribution (research §1.1(4)): t_raw = base + i^1.4·grow — dense
// near the curtain base, coarse toward the diffuse crown. Spans 0.8 → ~1.24.
constant float kMarchBase   = 0.8;   // march start distance
constant float kMarchGrow   = 0.0071; // polynomial step growth
constant float kMarchFalloff = 2.0;  // distance-scaling denominator: t = tRaw/(rd.y·2+F).
                                     // nimitz uses F=0.4, tuned for his near-horizon
                                     // camera. With our up-tilt that SATURATES the
                                     // altitude map (h≈0.25 at rd.y=0.2 vs 0.40 at 0.86)
                                     // — the whole frame collapses to one altitude and
                                     // green gets squeezed to a strip. F=2.0 spreads
                                     // h across ~0.02…0.29 over the elevation window.
constant float kCrownH      = 0.286; // altitude of the magenta crown (H(z) ceiling);
                                     // = the altitude the steepest in-frame ray reaches
constant float kElevTilt    = 0.55;  // screen-elevation → crown-colour bias (§5.11 gap fix)
constant float kCrownCurve  = 1.6;   // H(z) index curve: >1 holds green across most of
                                     // the altitude range, violet only at the tips
constant float kAuroraGain  = 1.45;  // emission gain (steady peak stays under the sRGB clip)
constant float kToneFloor   = 0.0;    // tone map off (band recalibration)
constant float kToneScale   = 1.0;

// Footprint F(uv) — the 2-D ground-plane flux map (Lawlor F(x,z)), rebuilt as a
// localized BAND (the auroral arc), not isotropic noise. The F-map spike proved
// the old tri-noise×fbm concentration was scattered mottle islands → streaks
// strewn across the sky, pebbly rays, and amplitude ~0.03/0.55. The band gives a
// coherent curtain over dark negative space, striations that extrude into rays,
// and full amplitude.
constant float kFoldScale     = 2.5;  // curl-fold spatial scale
constant float kFoldAmp        = 0.35; // curl-fold strength (drapery + dance)
constant float kAdvSampleT     = 0.30; // representative march-t for the once-per-ray warp
// Band shape — the curtain occupies a soft ANGULAR SECTOR about the convergence
// point (zenith), giving dark sky to the sides (negative space) and rays that
// converge upward. All widths/offsets below are in RADIANS of sector angle.
constant float kBandCenterAngle = 1.62; // sector center (rad); ~π/2 = straight up, biased
constant float kBandHalfWidth  = 0.34; // angular half-width of the curtain sector (fuller)
constant float kBandMeanderAmp = 0.17; // sector-center sway amplitude (the arc's dance)
constant float kBandMeanderFrq = 1.15; // sway frequency (over radius → the arc curves)
constant float kBandDrift      = 0.09; // slow curl drift of the sector center (the dance)
// Filaments live in the CONVERGENCE frame (angle/radius about the uv-origin, which
// is the zenith/vanishing point — see aurora_footprint). Angle is the tangential
// coordinate (across the curtain → many rays); radius is radial (along each ray).
// Screen-space aurora TEXTURE (aurora_intensity) about the vanishing point.
constant float kFilVpY         = -0.55; // vanishing point Y in screen uv (above the frame)
// Motion — LATERAL curtain sway (the ref-video motion), NOT a vertical scroll:
constant float kSwayAmp        = 0.13; // how far the curtain ripples side-to-side (radians)
constant float kSwayFreq       = 1.05;  // wave crests up the curtain (along r)
constant float kSwaySpeed      = 0.35; // how fast the ripple travels up the curtain
constant float kMassMorph      = 0.03; // slow mass shape-morph (persist, don't pop)
// Localized bright MASSES (distinct glowing concentrations, like the references):
constant float kMassAngFreq    = 3.2;  // few, large masses across the curtain
constant float kMassRadFreq    = 1.5;  // mass variation up the curtain
constant float kMassThresh     = 0.02; // higher → smaller/rarer, more distinct masses
constant float kMassBoost      = 1.05;  // how bright the masses pop above the dim body
constant float kBodyFloor      = 0.14; // dim aurora body outside the masses
constant float kBodyFil        = 0.36; // filament texture amplitude on the dim body
// Fine turbulent FILAMENTS:
constant float kFilAngFreq     = 40.0; // MANY fine filaments across the curtain
constant float kFilRadFreq     = 2.2;  // along-filament variation (low → coherent streaks)
constant float kFilWarp        = 1.6;  // domain-warp strength (turbulent/broken, not clean lines)
constant float kFilPow         = 2.3;  // ridge sharpen (thin bright filaments)
constant float kCrownFadeR     = 0.34; // radial fade toward the convergence (dim faint crown)
constant float kStriationAdv   = 0.80; // fbm4 sway of the rays (the dance — rays wave/curl)
constant float kBandFloor      = 0.24; // soft luminous body inside a concentration (glow, not
                                       // lines on black); dark between concentrations = negative space

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
constant float kAuroraMotionGain = 0.65;   // additional from `other`-stem activity
constant float kOtherDanceScale  = 1.6;    // other_energy_dev → dance-activity gain

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

// Ray field — sharp, irregular, radially-COHERENT filaments for the curtain. Ridges
// live in the ANGULAR coordinate about the convergence point, so each ridge extrudes
// into a ray fanning from the zenith; irregular spacing + per-ray brightness keep them
// organic (not clean spotlight beams, FM #14). Coherent in radius (only a slow
// meander), so a ray holds together down its length instead of averaging to fog.
// The MARCH produces the smooth COLOURED FORM only — a large-scale concentration
// (irregular glowing masses / dim gaps) that the running-average smear coalesces into
// the soft curtain body. The FINE FILAMENT TEXTURE is applied separately in screen
// space (aurora_filaments, in the fragment) because the march's smear washes any fine
// detail into smooth "vertical lines" (Matt 2026-07-19) — decoupling form (marched)
// from texture (unsmeared screen-space) keeps the fine detail crisp at native res.
// The MARCH produces only the smooth COLOURED FORM — sector shape, base-bright fade
// D(h), green→violet colour-by-height. All TEXTURE (localized bright masses + fine
// filaments) is applied in screen space (aurora_intensity) so it is not smeared into
// vertical gradients by the march (Matt 2026-07-19: masses read as a uniform field
// when marched). aurora_rays is a constant here — the form carries no texture.
static inline float aurora_rays(float ang, float rad, float time, float motionAmp) {
    return 1.0;
}

// Screen-space aurora TEXTURE, about the vanishing point above the frame:
//   • MASSES — localized, high-contrast glowing blobs (irregular bright concentrations
//     like the references), drifting + brightening with the music (the dance).
//   • FILAMENTS — fine turbulent domain-warped ridges (the wispy fine structure).
// Returns a brightness MULTIPLIER for the marched curtain: dim textured body
// everywhere, distinct bright masses (with bright filament cores) on top.
static inline float aurora_intensity(float2 uv, float time, float motionAmp) {
    float2 rel = uv - float2(0.5, kFilVpY);
    float  theta = atan2(rel.x, rel.y);        // 0 = toward the VP; constant-θ = a ray
    float  r     = length(rel);
    float  act   = 0.4 + 0.6 * motionAmp;      // musical activity → how much it dances

    // LATERAL SWAY — the whole curtain ripples SIDE TO SIDE, a wave travelling UP the
    // curtain (along r). This is how real aurora moves (ref video 2026-07-19): the
    // pattern undulates laterally and the bright masses TRANSLATE with it — there is NO
    // vertical scroll ("moving down") and masses do not appear/disappear. Two wave
    // scales + a θ term make it irregular, not a uniform slide. Amplitude rises with
    // the music. The sway shifts θ, so masses AND filaments move together, coherently.
    float sway = kSwayAmp * act *
                 (fbm4(float3(r * kSwayFreq + time * kSwaySpeed * act, theta * 1.4, 0.0)) * 0.7
                + fbm4(float3(r * kSwayFreq * 2.1 - time * kSwaySpeed * act * 0.7, theta * 2.3, 4.0)) * 0.3);
    float th = theta + sway;

    // Localized bright MASSES — sampled at the swayed angle so they translate with the
    // ripple; a SLOW shape morph (3rd-dim time), NO radial scroll → they persist and
    // move from place to place rather than flashing in and out.
    float m1  = fbm4(float3(th * kMassAngFreq,             r * kMassRadFreq,       time * kMassMorph));
    float m2  = fbm4(float3(th * kMassAngFreq * 2.0 + 4.0, r * kMassRadFreq * 1.6, time * kMassMorph * 1.3 + 6.0));
    float mass = smoothstep(kMassThresh, kMassThresh + 0.45, m1 * 0.65 + m2 * 0.35);

    // Fine turbulent FILAMENTS — domain-warped ridges at the swayed angle (they sway
    // with the curtain); only a gentle in-place shimmer, no scroll.
    float2 q = float2(th * kFilAngFreq, r * kFilRadFreq);
    float2 w = float2(fbm4(float3(q * 0.55, time * 0.025)),
                      fbm4(float3(q * 0.55 + 21.0, time * 0.03)));
    q += w * kFilWarp;
    float n1 = fbm4(float3(q, time * 0.012));
    float n2 = fbm4(float3(q * 3.1 + 9.0, time * 0.02));
    float fil = pow(saturate(1.0 - abs(n1 * 0.66 + n2 * 0.34)), kFilPow);

    // Dim textured body + boosted localized masses whose cores carry the bright filaments.
    float body   = kBodyFloor + kBodyFil * fil;
    float bright = mass * kMassBoost * (0.35 + 0.65 * fil);
    return body + bright;
}

// Footprint F(uv) — the flux map, expressed in the CONVERGENCE frame. The march
// samples uv = rd.xz·t, so angle = atan2(uv.y, uv.x) = atan2(rd.z, rd.x) is
// INDEPENDENT of t: constant along each view ray, and constant-angle lines fan from
// the zenith/vanishing point above the frame. The curtain is a soft angular SECTOR
// about that point (→ dark sky to the sides = negative space, rays converging up);
// the ray field carves thin bright filaments across it; the vertical base-bright
// fade is supplied downstream by the height-deposition D(h), not here.
// `driftW`/`advW` are the two curl-advection warp scalars (curl_noise .x), computed
// ONCE per ray by the caller — NOT per march step. curl_noise is 6·fbm8 = 48 noise
// octaves; calling it twice per step × 48 steps (~4.6k octaves/pixel) was choking the
// GPU (M2 Pro choppiness). Per-ray-constant advection is also more coherent — the ray
// sways as a whole instead of wiggling along its length.
static inline float aurora_footprint(float2 uv, float motionAmp, float time,
                                     float driftW, float advW) {
    float ang = atan2(uv.y, uv.x);
    float rad = length(uv);

    // Sector membership. The center sways slowly (the arc's dance) — over radius so
    // the curtain curves, and in time; a gentle curl drift too. Kept well within the
    // half-width so the sector holds together rather than scattering.
    float drift = kBandDrift * driftW;
    float centerAng = kBandCenterAngle
                    + kBandMeanderAmp * sin(rad * kBandMeanderFrq + time * 0.05)
                    + kBandMeanderAmp * 0.45 * sin(rad * kBandMeanderFrq * 2.3 - time * 0.04)
                    + drift;
    float dA   = (ang - centerAng) / kBandHalfWidth;
    float band = exp(-dA * dA);

    // Organic striation field (soft luminous body + concentration masses, [0,1] — it
    // already includes the body floor, so use it directly). Curl-advect the angle so
    // the whole curtain sways/curls (the dance).
    float advA = advW * (kFoldAmp * (0.5 + motionAmp) * kStriationAdv);
    float texture = aurora_rays(ang + advA, rad, time, motionAmp);

    // Crown fade — dim toward the convergence point (small rad). Kills the atan2
    // singularity's bright alias blob AND matches the reference, where the rays fade
    // to a faint crown at the zenith rather than piling into a hot spot.
    float crownFade = smoothstep(0.0, kCrownFadeR, rad);

    return band * texture * crownFade;
}

// Height-deposition D(h) — sharp onset at the emission floor (crisp lower edge),
// long tail up (Lawlor). Brightest at the low green body, fading toward the crown.
static inline float aurora_deposition(float h) {
    return smoothstep(0.0, kDepOnset, h) * exp(-h * kDepDecay);
}

// Colour by ALTITUDE (Lawlor H(z)) — green base → cool teal → violet/magenta crown,
// the locked dramatic palette (Matt 2026-07-14, refs 01/07; design §5.10). The
// saturated green BASE is authored from ref_240's measured emission (~19,130,61);
// the violet/magenta CROWN is the design intent (ref_240's own crown reads cyan, but
// the stratification gate + refs 01/07 specify a magenta crown, so the crown tips to
// magenta). Green held low (L2 gate) and violet reserved for the upper third so the
// column integral stays green-dominant rather than washing to a muddy average.
static inline float3 aurora_height_palette(float t) {
    float3 base  = float3(0.08, 1.00, 0.16);   // vivid saturated green base (ref_240, low R+B)
    float3 mid   = float3(0.22, 0.78, 0.90);   // cool teal transition
    float3 crown = float3(0.95, 0.42, 1.00);   // violet/magenta crown (refs 01/07)
    return (t < 0.5) ? mix(base, mid, t * 2.0) : mix(mid, crown, (t - 0.5) * 2.0);
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
    // Elevation tilt (§5.11 known-gap fix): every pixel integrates its whole column,
    // so pure per-step altitude colour washes out — the crown never separates from
    // the base on screen. Bias the palette index toward the crown for high-elevation
    // pixels (rd.y constant per ray → the upper screen), so colour tracks SCREEN
    // height: green base low, violet crown high. Low bands get ~0 tilt (stay green).
    float elevTilt = smoothstep(0.40, 0.85, rd.y) * kElevTilt;
    // Advection warps — computed ONCE per ray (see aurora_footprint), with fbm4 (a
    // smooth [-1,1] scalar, ~[cheap]) instead of curl_noise (6·fbm8 = 48 octaves,
    // ×50-amplified detail). The old per-STEP curl only looked smooth because the
    // running-average smeared it; sampled once it marbled the rays. fbm4 is smooth at
    // a single sample AND ~576× cheaper (the M2 Pro choppiness). Each pixel/ray gets
    // its own warp (cross-curtain variation), constant along the ray (coherent).
    float2 uvRep = rd.xz * kAdvSampleT + kink;
    float driftW = fbm4(float3(uvRep * 0.8, time * 0.08));
    float advW   = fbm4(float3(uvRep * kFoldScale, time * 0.12));
    for (int i = 0; i < kAuroraSteps; i++) {
        float  tRaw = kMarchBase + pow(float(i), 1.4) * kMarchGrow;
        float  t    = tRaw / (rd.y * 2.0 + kMarchFalloff);
        float2 uv   = rd.xz * t + kink;
        float  h    = rd.y * t;                    // altitude reached ∝ elevation
        float  d    = aurora_footprint(uv, motionAmp, time, driftW, advW) * aurora_deposition(h);
        acc = mix(acc, d, 0.5);                    // running smear → coherent rays
        // Palette by ALTITUDE (Lawlor H(z)) + the screen-elevation tilt above.
        // exp-decay accumulation weight + ramp-in (nimitz §1.1(7)) bounds the sum.
        float paletteT = saturate(pow(saturate(h / kCrownH), kCrownCurve) + elevTilt);
        col += aurora_height_palette(paletteT)
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
    // Dance vigor — driven by the synth/pad body (the `other` stem), Aurora Veil's
    // song-defining anchor. On real music `other_energy_dev` swings hard (~0.04→0.64)
    // where the whole-mix mid band is nearly static (±0.006) — routing the dance off
    // mid gave almost no reactivity. Pre-warmup (no stems) fall back to the mid proxy.
    float otherActivity = saturate(stems.other_energy_dev * kOtherDanceScale);
    float midProxy      = saturate(0.5 + 0.5 * f.mid_att_rel);
    float danceActivity = mix(midProxy, otherActivity, stemMix);
    float motionAmp     = kAuroraMotionBase + kAuroraMotionGain * danceActivity;

    // ── SPIKE (kAuroraDebug == 2): render the footprint F(x,z) alone as a flat 2-D
    // map over the ground plane — no march, no camera. Go/no-go for the band
    // rebuild: does F read as a coherent arc with striations over dark negative
    // space? Grayscale = F directly (now full-amplitude, no boost needed).
    if (kAuroraDebug > 1.5) {
        float2 fpUV = (uv - 0.5) * kFpSpikeSpan;
        float  dW   = fbm4(float3(fpUV * 0.8, time * 0.08));
        float  aW   = fbm4(float3(fpUV * kFoldScale, time * 0.12));
        float  fp   = aurora_footprint(fpUV, motionAmp, time, dW, aW);
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
    // Screen-space aurora texture — localized bright masses + fine filaments (unsmeared
    // → distinct + crisp at native res). The march above supplied only the colour form.
    aurora *= aurora_intensity(uv, time, motionAmp);

    // Tone map — the density sits on a dim non-zero floor (the murk) with sparse
    // brighter rays. Subtract the floor to true black (real negative space) then
    // scale the survivors up (pop the rays). Hue held. Measured: raw luminance
    // spans ~0.06–0.19, so the floor sits just above the murk.
    float dlum = dot(aurora, float3(0.35, 0.55, 0.45));
    float toned = max(dlum - kToneFloor, 0.0) * kToneScale;
    aurora *= (dlum > 1e-4) ? toned / dlum : 0.0;

    // White-hot cores — only the very brightest ray concentrations lift toward a
    // green-white core (the footage's bright base). Gentle: the reference base is a
    // SATURATED green, not white, so the bleach is subtle and green-leaning (low R+B).
    // Green-dominance gated so the violet crown keeps its hue (never dragged to grey).
    float coreLum = dot(aurora, float3(0.299, 0.587, 0.114));
    float greenDom = saturate((aurora.g - max(aurora.r, aurora.b)) * 2.0);
    aurora = mix(aurora, float3(0.60, 1.0, 0.78) * coreLum,
                 smoothstep(0.45, 1.05, coreLum) * 0.30 * greenDom);

    // Route 1 — vocals pitch → subtle green↔cool-teal hue tint.
    float3 pitchTint = float3(1.0 - paletteOffset * 0.45, 1.0, 1.0 + paletteOffset * 0.75);
    aurora *= pitchTint;

    // Route 2 — brightness breathing (bass transients gently lift the curtain). Kept
    // GENTLE (small swing) so it breathes, not FLASHES on every kick (Matt 2026-07-19);
    // still dominates the beat-kink accent by ≥10× (§5.7).
    aurora *= (0.82 + 0.26 * bassPulse);

    // ── Composite: additive emission over dark sky (stars punch through, FM #5).
    // Clamp in LINEAR at 0.94 — the render target is bgra8Unorm_srgb, so a linear
    // channel is sRGB-encoded on write (0.94 → ~248/255); a higher clamp (0.97 → 251)
    // trips PresetAcceptance "does not clip to white" (max channel < 250).
    float3 finalColor = min(sky + aurora, float3(0.94));
    // DEBUG (AURORA_DEBUG): grayscale density view to see ray structure.
    if (kAuroraDebug > 0.5) {
        float g = dot(aurora, float3(0.4, 0.6, 0.5));
        return float4(float3(saturate(g)), 1.0);
    }
    return float4(finalColor, 1.0);
}
