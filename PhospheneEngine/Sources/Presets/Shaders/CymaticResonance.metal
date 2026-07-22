// CymaticResonance.metal — resonant-plate Chladni nodal figure (family: geometric).
//
// A square resonant plate whose nodal figure is selected LIVE by the music's
// brightness: as the track brightens the figure climbs a fixed low→high
// complexity ladder into finer 4-fold-symmetric patterns; a bass drop snaps it
// back to a big simple figure. "The pitch of the sound made solid." Rendered as
// a strong-oblique-tilt displaced relief on a deep-black plate, jewel-emissive
// nodal ridges lit by a height-gradient-derived normal + GGX, through the shared
// ACES + bloom post_process chain. Camera holds — the figure is the motion
// (direct_time_modulation, D-029; NO mv_warp — it would smear the crisp lines).
//
// Contract of record: docs/presets/psychedelic_geometry/PG_CR_CYMATIC_RESONANCE.md.
// This is the CR.1 "clay maquette" (SHADER_CRAFT §2.2): plate + hero figure +
// derived-normal relief + jewel emissive + strong tilt + non-black fundamental
// silence. Materials / micro-grain / secondary-audio / cert are CR.2–CR.3.
//
// PORT, not derivation (FA #73): the square-plate eigenmode superposition is the
// standard Chladni model; reference Shadertoy 4dXSD2 (Chladni figures). We use
// the PLUS basis  cos(mπξ)cos(nπη) + cos(nπξ)cos(mπη)  — NOT 4dXSD2's minus
// combination, which forces ξ=η onto a nodal line on every figure (a spurious
// dominant diagonal). The plus basis recovers the real 4-fold axis-symmetric
// concentric figures (concept-gate finding vs Matt's real-plate footage, and the
// committed references 01_macro_chladni_plate / 02_micro_chladni_filigree).
//
// Audio liveness (§14.1): the HERO driver is `spectral_centroid` — reliably alive
// and level-independent (it tracks timbre, which always varies), which is why
// this mapping is alive by construction where a raw-FFT-magnitude driver would be
// near-dead on quiet bands. The centroid EMA + bass-drop snap + D-019 warmup live
// CPU-side in CymaticResonanceState (buffer 6); deviation/centroid only, no
// absolute thresholds on AGC-normalized values (FA #31).

#include <metal_stdlib>
using namespace metal;

// MARK: - Per-frame state (matches CymaticStateGPU in CymaticResonanceState.swift)

struct CymaticStateGPU {
    float ladderPos;   // continuous ladder position [0, kLadderCount-1]
    float warmup;      // excitation / brightness gate [0,1] (D-019; 0 in silence)
    float snap;        // bass-drop snap envelope [0,1] (diagnostic + subtle kick)
    float hueOffset;   // CR.1.2 global hue shift [0,1] from smoothed harmonic phase
};

// MARK: - Mode ladder (fixed low→high complexity; m < n, plus basis)

// SAME-PARITY (m,n) pairs only — the (m, m+2) family. CR.1 concept-gate
// correction #5 (found at the maquette, 2026-07-22): the plus basis forces an
// anti-diagonal nodal line (η = 1−ξ) whenever m,n have OPPOSITE parity (verified:
// max|φ| along η=1−ξ is exactly 0 for (1,2),(2,3),… and 2 for (1,3),(2,4),…). The
// design's adjacent-pair ladder (1,2)(2,3)(3,4)… is full of opposite-parity modes —
// including the fundamental (1,2) — so half its figures (and the silence rest state)
// carried the very "spurious diagonal" the concept gate switched plus↔minus to kill.
// Same-parity pairs are 4-fold symmetric AND diagonal-free on BOTH diagonals. The
// (m,m+2) family climbs complexity monotonically, coarse (1,3) → fine (11,13).
// CR.1.2 (M7: "not moving through more than 3 different patterns, a bit boring"):
// a VARIED same-parity ladder — alternating m=n concentric grids with m<n cross-hatch
// so adjacent rungs read as DISTINCT figures, not the same grid at rising density.
// Still all same-parity (diagonal-free, correction #5), roughly rising in complexity.
constant int kLadderCount = 11;
constant int2 kLadder[11] = {
    int2(1, 3), int2(2, 2), int2(2, 4), int2(3, 3), int2(3, 5), int2(4, 4),
    int2(2, 6), int2(4, 6), int2(5, 5), int2(3, 7), int2(5, 7)
};

// MARK: - Camera / plate framing (strong oblique tilt — ref 01/02 are flat, we tilt)

constant float kPI          = 3.14159265358979;
// CR.1.2 (M7: "camera directly above the plate would be better; the angled top shows
// background"): TOP-DOWN orthographic view, cover-fit — the square plate fills the 16:9
// frame edge-to-edge with NO receding background. `kTopZoom` = plate half-extent mapped
// to the frame half-width (1.0 = full plate width fills the frame width).
constant float kTopZoom     = 1.0;

// MARK: - Look tunables (CR.1 maquette; Matt's M7 sets finals)

constant float kLineWidthPx = 2.3;    // nodal ridge screen width (isotropic-AA via fwidth, §18.3)
constant float kHeightSigma = 0.30;   // width of the smooth relief bump around a nodal line (field units)
constant float kHeightScale = 2.4;    // relief steepness for the derived normal (§18.9)
constant float kEmissiveGain = 1.5;   // CR.1.1: jewel ridge emissive sits NEAR the bloom threshold so colour
                                      // survives ACES (only the brightest crests bloom white — the M7 "reads
                                      // white" fix; was 2.6 → whole ridge over threshold → washed to white)
constant float kEmissiveFloor = 0.30; // dim emissive at silence (non-black fundamental, D-037)
constant float kGGXRough    = 0.46;   // key-highlight roughness — broad sheen on the relief, not tight glint-dots
constant float kGGXGain     = 1.5;    // CR.1.1: softer key (was 2.2) — the white highlight was washing the jewel hue

// Deep-black plate + faint background floor (never pure black, D-037).
constant float3 kPlateBody  = float3(0.006, 0.007, 0.012);
constant float3 kBgFloor    = float3(0.010, 0.008, 0.016);

// Jewel palette anchors (fixed spatial iridescence for CR.1 — hue routing is CR.3).
// Saturated sweep sapphire → magenta → gold along the relief (references 03 warm
// pole + the Phosphene jewel signature). Pale-tone ≤ 30 % (§12.7).
constant float3 kJewelA = float3(0.15, 0.35, 1.00);  // sapphire
constant float3 kJewelB = float3(0.95, 0.20, 0.85);  // magenta
constant float3 kJewelC = float3(1.00, 0.72, 0.22);  // gold

// MARK: - Plus-basis eigenmode field

// φ_{m,n}(ξ,η) = cos(mπξ)cos(nπη) + cos(nπξ)cos(mπη).  Returns value only (used
// for the relief-height taps — the derived normal needs height, not gradient).
static inline float cr_phi(float2 p, int2 mn) {
    float mp = kPI * float(mn.x);
    float np = kPI * float(mn.y);
    return cos(mp * p.x) * cos(np * p.y) + cos(np * p.x) * cos(mp * p.y);
}

// φ and its analytic gradient ∂φ/∂ξ, ∂φ/∂η (for the crisp nodal-line distance).
static inline float3 cr_phi_grad(float2 p, int2 mn) {
    float mp = kPI * float(mn.x);
    float np = kPI * float(mn.y);
    float cmx = cos(mp * p.x), smx = sin(mp * p.x);
    float cnx = cos(np * p.x), snx = sin(np * p.x);
    float cmy = cos(mp * p.y), smy = sin(mp * p.y);
    float cny = cos(np * p.y), sny = sin(np * p.y);
    float value = cmx * cny + cnx * cmy;
    float dxi   = -mp * smx * cny - np * snx * cmy;
    float deta  = -np * cmx * sny - mp * cnx * smy;
    return float3(value, dxi, deta);
}

// Active field = crossfade of the two adjacent ladder modes (value only).
static inline float cr_field(float2 p, float ladderPos) {
    int i = clamp(int(floor(ladderPos)), 0, kLadderCount - 2);
    float f = clamp(ladderPos - float(i), 0.0, 1.0);
    return mix(cr_phi(p, kLadder[i]), cr_phi(p, kLadder[i + 1]), f);
}

// Active field value + gradient (for the crisp emissive ridge distance).
static inline float3 cr_field_grad(float2 p, float ladderPos) {
    int i = clamp(int(floor(ladderPos)), 0, kLadderCount - 2);
    float f = clamp(ladderPos - float(i), 0.0, 1.0);
    return mix(cr_phi_grad(p, kLadder[i]), cr_phi_grad(p, kLadder[i + 1]), f);
}

// Smooth relief height at a plate point — a rounded bump around the nodal set
// (z ≈ 0). Cheap: one field value per tap, no gradient. Used for the §18.9
// central-difference normal.
static inline float cr_height(float2 p, float ladderPos) {
    float z = cr_field(p, ladderPos);
    return exp(-(z * z) / (2.0 * kHeightSigma * kHeightSigma));
}

// MARK: - HSV → RGB (self-contained; preamble hsv2rgb also available)

static inline float3 cr_hsv2rgb(float3 c) {
    float3 pp = abs(fract(float3(c.x) + float3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
    return c.z * mix(float3(1.0), clamp(pp - 1.0, 0.0, 1.0), c.y);
}

// MARK: - GGX specular (isotropic, single key light — the relief depth cue)

static inline float cr_ggx(float3 n, float3 v, float3 l, float rough) {
    float3 h = normalize(v + l);
    float nh = max(dot(n, h), 0.0);
    float nv = max(dot(n, v), 1e-3);
    float nl = max(dot(n, l), 0.0);
    float a  = rough * rough;
    float a2 = a * a;
    float d  = nh * nh * (a2 - 1.0) + 1.0;
    float ndf = a2 / max(kPI * d * d, 1e-5);
    float k  = (rough + 1.0) * (rough + 1.0) / 8.0;
    float gv = nv / (nv * (1.0 - k) + k);
    float gl = nl / (nl * (1.0 - k) + k);
    return ndf * gv * gl * nl;
}

// MARK: - Fragment

// Direct + post_process: outputs LINEAR HDR (no tone map here — the shared
// PostProcessChain does bright-pass bloom on crests > 0.9, then ACES → drawable).
fragment float4 cymatic_resonance_fragment(
    VertexOut               in       [[stage_in]],
    constant FeatureVector& features [[buffer(0)]],
    constant CymaticStateGPU& st     [[buffer(6)]])
{
    float aspect = max(features.aspect_ratio, 1e-4);   // w/h

    // ── Top-down orthographic cover-fit (CR.1.2) ────────────────────────────────
    // The square plate fills the 16:9 frame edge-to-edge: the full frame WIDTH maps
    // to the plate width; the height is scaled by `aspect` (square pixels) so the
    // frame shows the full-width, centre-height band of the plate — no background.
    float2 uv  = in.uv;
    float2 ndc = uv * 2.0 - 1.0;
    ndc.y = -ndc.y;                 // uv.y = 0 is top of screen → +screen-up
    float2 plate = float2(ndc.x, ndc.y / aspect) * kTopZoom;

    // Faint non-black background floor (D-037) — only reached if kTopZoom > 1.
    float3 bg = kBgFloor * (0.4 + 0.6 * exp(-dot(ndc, ndc) * 1.6));
    if (any(abs(plate) > 1.0)) { return float4(bg, 1.0); }

    float2 p = plate * 0.5 + 0.5;                  // → [0,1]² plate coords (ξ,η)
    float ladderPos = clamp(st.ladderPos, 0.0, float(kLadderCount - 1));

    // ── Crisp emissive nodal ridge: distance to the zero-isoline, isotropic-AA ──
    float3 fg = cr_field_grad(p, ladderPos);
    float z  = fg.x;
    float gradLen = max(length(fg.yz), 1e-4);
    float d  = abs(z) / gradLen;                   // ≈ distance (plate units) to the nodal line
    float aa = max(fwidth(d), 1e-6);               // §18.3 isotropic screen-space AA
    float ridge = 1.0 - smoothstep(0.0, aa * kLineWidthPx, d);

    // ── Derived-normal relief (§18.9): central-difference the smooth height field.
    // ξ = world X, η = world Z, plate up = +Y, so the plate-space normal maps
    // straight to world with no basis rotation.
    float eps = max(1.5 * aa, 0.002);
    float hpx = cr_height(p + float2(eps, 0.0), ladderPos);
    float hmx = cr_height(p - float2(eps, 0.0), ladderPos);
    float hpy = cr_height(p + float2(0.0, eps), ladderPos);
    float hmy = cr_height(p - float2(0.0, eps), ladderPos);
    float dhdx = (hpx - hmx) / (2.0 * eps);
    float dhdy = (hpy - hmy) / (2.0 * eps);
    float3 normal = normalize(float3(-dhdx * kHeightScale, 1.0, -dhdy * kHeightScale));

    // ── Lighting: one warm key + GGX highlight on the relief (the depth cue) ────
    float3 viewDir  = float3(0.0, 1.0, 0.0);   // top-down (CR.1.2)
    float3 lightDir = normalize(float3(-0.45, 0.72, 0.30));
    float3 keyColor = float3(1.0, 0.82, 0.52);   // CR.1.1: warm-gold key (was near-white) — a white key washed the jewel hue
    float spec = cr_ggx(normal, viewDir, lightDir, kGGXRough) * kGGXGain;

    // ── Jewel emissive: fixed spatial iridescence (hue routing is CR.3) ─────────
    // Hue sweeps with radius + the relief slope so ridges read jewel-toned and
    // iridescent (sapphire → magenta → gold), not a flat white line drawing.
    float r  = length(plate);
    float slope = clamp(dhdx * 0.5 + dhdy * 0.5 + 0.5, 0.0, 1.0);
    // CR.1.1: sweep the FULL jewel range across the plate radius — sapphire (0.58) →
    // magenta (0.85) → gold (wraps to ~0.08) — with a slope wobble for iridescence.
    // CR.1.2: + a MUSIC-driven global offset `st.hueOffset` (smoothed harmonic phase,
    // D-178) so the whole jewel palette rotates with the chord progression — "the
    // sand colour changes with the music" (M7). Higher saturation, less white anchor.
    float hue = fract(0.58 + 0.50 * r + 0.12 * slope + st.hueOffset);
    float3 jewel = cr_hsv2rgb(float3(hue, 0.88, 1.0));
    float3 anchor = mix(mix(kJewelA, kJewelB, clamp(r * 1.3, 0.0, 1.0)),
                        kJewelC, clamp(slope, 0.0, 1.0));
    jewel = normalize(mix(jewel, anchor, 0.35) + 1e-4);

    // Excitation gate (D-019): dim at silence (floor), full when the plate rings.
    float excite = mix(kEmissiveFloor, kEmissiveGain, clamp(st.warmup, 0.0, 1.0));
    // Silence breathing (A5): a gentle slow pulse so the rested plate is alive.
    float breath = 0.85 + 0.15 * sin(features.time * 0.7);
    excite *= mix(breath, 1.0, clamp(st.warmup, 0.0, 1.0));
    // Subtle brightness kick on the snap restructure (the one big legible event).
    excite *= (1.0 + 0.25 * st.snap);

    float3 emissive = jewel * ridge * excite;

    // ── Composite: deep-black plate + emissive ridges + key highlight ───────────
    // The GGX highlight lives on the RAISED relief (smooth ridge height `hc`,
    // z ≈ 0), not the flat antinode fields — otherwise it sparkles as bright dots
    // where sand should be CLEARED (antinodes vibrate most). Gated by excitation so
    // the rested silence plate is calm, not a field of specular blobs.
    float hc = exp(-(z * z) / (2.0 * kHeightSigma * kHeightSigma));
    float specGate = hc * (0.25 + 0.75 * clamp(st.warmup, 0.0, 1.0));
    float3 col = kPlateBody + emissive + keyColor * spec * specGate;
    // Keep the off-ridge plate honestly dark but never pure black (D-037).
    col = max(col, kPlateBody);

    return float4(col, 1.0);
}
