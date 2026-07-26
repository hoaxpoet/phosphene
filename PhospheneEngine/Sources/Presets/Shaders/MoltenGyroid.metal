// MoltenGyroid.metal — LOOK-SPIKE (concept gate artifact 4) for the molten
// gyroid concept. NOT a certified preset; this exists to prove the LOOK and,
// above all, the MOTION COHERENCE before any real build (the FFB / BUG-071
// lesson: measure whole-frame frame-to-frame coherence before tuning anything).
//
// CONCEPT (watched source, FA #73 port). diatribes' "Molten Shapes"
// (shadertoy.com/view/WXyfzw): a raymarched GYROID surface skinned as molten
// lava — glowing magma in the cracks, cooled black basalt crust, fine bubbling
// texture. Ported here as a gyroid SHELL labyrinth the camera flies through.
//
// WHY THIS FITS MFX.1 + RMPERF.1 (and why it is the anti-FFB):
//   * A gyroid is a SMOOTH, fixed-scale, large-featured minimal surface. The
//     travel is a rigid TRANSLATION through it — not FFB's scale-zoom that
//     refined new detail every frame. Consecutive frames share almost all their
//     structure → coherent by construction → exactly what MetalFX Temporal AA
//     (MFX.1) can reconstruct, and its motion vectors are a trivial closed form.
//   * The lava bump (A()) crawls fine high-frequency detail across the crust —
//     the shimmer-prone sub-pixel detail temporal AA resolves.
//   * The map runs a multi-tap lava texture + a turbulence loop per sample: an
//     expensive DE, so RMPERF.1's cheaper per-hit normal+AO pays off.
//
// SPIKE SCOPE: prove look + coherence. Audio is minimal (energy → travel speed,
// bass → magma glow). Full material cascade / routing / cert come at the real
// build if this clears the gate.

#include <metal_stdlib>
using namespace metal;

// MARK: - Tunables

// Gyroid spatial frequency (feature size ≈ 2π/freq). Large features = coherent
// flight; keep it well below the Mandelbox's self-similar refinement.
constant float MG_FREQ       = 0.85f;
// Shell half-thickness: |gyroid| - thickness carves a membrane labyrinth with
// large open channels the camera threads.
constant float MG_THICK      = 0.46f;
// Lipschitz safety: the gyroid gradient exceeds 1, so under-step the march
// (same role as VL_SDF_STEP_SCALE 0.6).
constant float MG_STEP_SCALE = 0.55f;
// Lava displacement amplitude on the surface.
constant float MG_LAVA_AMP   = 0.16f;
// Forward travel: units per accumulatedAudioTime. accAudioTime advances ~0.1/s
// on a loud track (energy clock), so ~5 ≈ a channel every ~15 s — a calm molten
// drift that speeds up with the music. Shared with scenePrevPosition — they MUST
// agree or the motion vectors smear.
constant float MG_TRAVEL_RATE = 5.0f;
// Forward direction of travel through the field.
constant float3 MG_TRAVEL_DIR = float3(0.0f, 0.12f, 1.0f);
// Gentle rigid yaw as we travel so it is not a straight monotonous tunnel
// (FFB FLY.9 lesson). Rigid rotation preserves the DE. Radians per travel unit.
constant float MG_YAW_RATE   = 0.06f;

// MARK: - Ported field + lava texture (from "Molten Shapes")

/// Classic gyroid implicit. ~[-1.5, 1.5]. (The shadertoy's extra `q` lines were
/// dead code — it returns this.)
static inline float mg_gyroid(float3 x) {
    return dot(sin(x), cos(x.yzx));
}

/// Moderate-frequency lumpy field (~[-1,1]), 4 octaves. Readable crust/vein
/// detail — NOT the source's sub-pixel A() dither (which aliases and reads as
/// noise). Kept in the MATERIAL, not the geometry, so it adds molten look
/// without hurting motion coherence or SDF Lipschitz continuity.
static inline float mg_detail(float3 p) {
    float d = 0.0f, a = 0.6f;
    for (int i = 0; i < 4; ++i) {
        d += a * (sin(p.x) * sin(p.y) * sin(p.z));
        p = p * 1.93f + float3(1.3f, 2.1f, 0.7f);
        a *= 0.55f;
    }
    return d;
}

/// Slowly crawling molten flow offset so the crust/veins churn like lava.
static inline float3 mg_flow(float3 q, float t) {
    return q + 0.25f * float3(sin(t * 0.6f + q.y), cos(t * 0.5f + q.z), sin(t * 0.4f + q.x));
}

// MARK: - Travel (rigid, coherent)

/// Forward distance travelled = energy clock × rate (HERO: speed follows the
/// music's energy, like FFB but as a pure translation).
static inline float mg_travel(constant SceneUniforms& s) {
    return s.sceneParamsA.x * MG_TRAVEL_RATE;
}

/// Rigid yaw about Y by `ang` — preserves distances (DE stays exact).
static inline float3 mg_yaw(float3 v, float ang) {
    float c = cos(ang), sn = sin(ang);
    return float3(v.x * c - v.z * sn, v.y, v.x * sn + v.z * c);
}

/// Sample point in gyroid space for a given travel distance: translate forward,
/// then rigid-yaw so new architecture swings into frame.
static inline float3 mg_sample(float3 p, float travel) {
    float3 q = p + MG_TRAVEL_DIR * travel;
    return mg_yaw(q, travel * MG_YAW_RATE);
}

// MARK: - Distance estimator

/// Molten gyroid shell. `gyr` (the raw gyroid value, [-1.5,1.5]) is returned via
/// out-param so sceneMaterial can reuse it as the "heat" coordinate without a
/// second gyroid eval.
static inline float mg_map(float3 p, constant SceneUniforms& s,
                           thread float& gyr) {
    float travel = mg_travel(s);
    float3 q     = mg_sample(p, travel);
    float g      = mg_gyroid(q * MG_FREQ) / MG_FREQ;   // scale-normalised DE
    gyr          = g;
    // Gentle low-frequency undulation so the shell breathes (small amplitude to
    // stay Lipschitz-safe and keep motion coherent — detail lives in material).
    float bump   = mg_detail(q * 0.8f) * MG_LAVA_AMP;
    float d = fabs(g) - MG_THICK - bump;
    return d * MG_STEP_SCALE;
}

float sceneSDF(float3 p,
               constant FeatureVector& f,
               constant SceneUniforms& s,
               constant StemFeatures& stems,
               texture2d<float> ferrofluidHeight) {
    (void)f;
    (void)stems;
    (void)ferrofluidHeight;   // slot-10; Ferrofluid Ocean only.
    float gyr;
    return mg_map(p, s, gyr);
}

// MARK: - MetalFX motion vectors (MFX.1)

/// Where the surface point at `worldPos` was one frame ago. The travel is a
/// rigid TRANSLATION (plus yaw), so the previous-frame position is exact:
/// last frame's travel was smaller, so the same field feature sat further along
/// the travel direction. `lightingParams.z` carries the previous frame's
/// accumulated audio time (RenderPipeline+RayMarch), identical to FFB's plumbing.
///
/// Translation part is exact; the slow yaw is a rigid rotation MetalFX's history
/// rejection absorbs (same class as FFB's slow fold morph). We invert the
/// dominant translation, which is where essentially all the screen motion is.
float3 scenePrevPosition(float3 worldPos,
                         constant FeatureVector& f,
                         constant SceneUniforms& s,
                         constant StemFeatures& stems) {
    (void)f;
    (void)stems;
    float travelNow  = mg_travel(s);
    float travelPrev = s.lightingParams.z * MG_TRAVEL_RATE;
    return worldPos + MG_TRAVEL_DIR * (travelNow - travelPrev);
}

// MARK: - Molten material

/// Blackbody-ish magma ramp: black crust → deep red → orange → yellow-white.
/// `h` in [0,1] = heat.
static inline float3 mg_magma(float h) {
    h = clamp(h, 0.0f, 1.0f);
    float3 crust  = float3(0.02f, 0.015f, 0.02f);   // near-black basalt
    float3 dull   = float3(0.45f, 0.06f, 0.015f);   // cooling deep red
    float3 hot    = float3(1.00f, 0.34f, 0.05f);    // orange magma
    float3 white  = float3(1.00f, 0.80f, 0.42f);    // incandescent core (warm, not paper-white)
    // Most of the range stays red→orange; white only in the very hottest cores.
    float3 c = mix(crust, dull, smoothstep(0.12f, 0.50f, h));
    c = mix(c, hot,   smoothstep(0.55f, 0.86f, h));
    c = mix(c, white, smoothstep(0.93f, 1.0f, h));
    return c;
}

void sceneMaterial(float3 p,
                   int matID,
                   constant FeatureVector& f,
                   constant SceneUniforms& s,
                   constant StemFeatures& stems,
                   thread float3& albedo,
                   thread float& roughness,
                   thread float& metallic,
                   thread int& outMatID,
                   constant LumenPatternState& lumen) {
    (void)matID;
    (void)stems;
    (void)lumen;      // slot-8; Lumen Mosaic only.

    // Recompute travel/sample exactly as sceneSDF (separate entry point, no
    // shared locals — VL/FFB do the same) so colour tracks the geometry.
    float travel = mg_travel(s);
    float3 q     = mg_sample(p, travel);
    float3 fq    = mg_flow(q, s.sceneParamsA.x);   // crawling molten flow

    // CRUST texture: two octaves of lumpy detail → mottled dark basalt.
    float crustN = mg_detail(fq * 1.7f) * 0.5f + 0.5f;          // [0,1]
    float3 basalt = mix(float3(0.015f, 0.010f, 0.012f),         // near-black rock
                        float3(0.10f, 0.055f, 0.045f),          // warm-grey ash
                        crustN);

    // VEINS: a low-frequency ridged field → thin bright cracks where the field
    // crosses zero. This is the molten-crack signature (the reference's glowing
    // magma between cooled plates), and it reads at the SURFACE (unlike the shell
    // midline, which the ray never sees).
    float vfield = mg_detail(fq * 0.9f + 4.0f);                 // ~[-1,1]
    float ridge  = 1.0f - fabs(vfield);                         // 1 at the crack line
    float vein   = smoothstep(0.80f, 0.97f, ridge);            // thin lines
    // A broader ember term so cracks widen into pooled magma, not just hairlines.
    float ember  = smoothstep(0.55f, 0.95f, ridge);

    // Bass surges the magma: continuous bass band widens + brightens the glow
    // (Layer-1 continuous energy, primary driver; deviation-primitive routing at
    // real build — FA #31). Silence keeps a base ember so it never goes black.
    float bassGlow = clamp(f.bass, 0.0f, 1.5f);
    // Thin cracks carry the heat; the broad ember only warms, so large areas
    // never saturate to white (the round-1 blow-out). Bass surges the cracks.
    float heat = clamp(vein * (0.62f + 0.45f * bassGlow)
                     + ember * (0.14f + 0.20f * bassGlow), 0.0f, 1.0f);

    if (heat > 0.35f) {
        // matID 1 — emission-dominated: glowing magma in the cracks. Feeds the
        // bloom bright-pass; kept to the thin/pooled crack regions so the broad
        // crust can never flash the whole frame (D-157). Emission scaled to sit
        // BELOW clipping for most of the range → saturated orange, not white.
        outMatID  = 1;
        albedo    = mg_magma(heat) * (0.35f + 0.55f * heat);
        roughness = 0.5f;
        metallic  = 0.0f;
    } else {
        // matID 0 — cooled basalt crust: dark, rough, faintly warmed by the
        // nearby magma so cracks bleed a little heat into the rock.
        outMatID  = 0;
        albedo    = basalt + mg_magma(0.55f) * ember * 0.25f;   // faint warm bleed
        roughness = mix(0.85f, 0.6f, crustN);
        metallic  = 0.0f;
    }
}
