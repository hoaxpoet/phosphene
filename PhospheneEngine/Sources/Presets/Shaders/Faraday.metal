// Faraday.metal — an iridescent liquid sea that the music physically drives.
//
// The music does not tint a pretty surface; it CAUSES the pattern, the same way it
// does in Cymatic Resonance. A Swift–Hohenberg simulation of parametrically-driven
// surface waves runs on the GPU each frame (`FaradaySim.metal` /
// `FaradaySimulation.swift`) and arrives here as a liquid heightfield at
// texture(10). Loudness crossing the Faraday THRESHOLD is a real supercritical
// bifurcation — below it the sea is glassy and still, above it cells erupt — so a
// drop genuinely switches the surface on. Timbre selects the cell size.
//
// COLOUR IS OPTICS, NOT A PALETTE. A thin film is iridescent because light reflected
// from its two surfaces interferes, and which wavelengths survive depends on the
// film THICKNESS. The standing wave IS a thickness map, so the colour bands ripple
// and swap as the pattern moves. Oil on a puddle; a soap bubble.
//
// WHY THIS EXERCISES THE HARDWARE (MFX.1 + RMPERF.1). Interference fringes are the
// finest colour detail there is — they crowd tighter than a pixel wherever the
// surface steepens, and the sub-cell capillary ripple is finer still. Static
// rendering must throw that detail away to avoid aliasing; MetalFX Temporal AA
// accumulates it across frames instead, so this preset carries detail a still frame
// cannot. RMPERF.1's cheaper per-hit normal + AO pays for the per-pixel optics.

#include <metal_stdlib>
using namespace metal;

// MARK: - Tunables

/// World size of one tile of the (toroidal) simulation field.
constant float FDY_TILE = 3.4f;
/// Wave height in world units. Faraday ripples are SHALLOW relative to their
/// wavelength — at an aspect near 1 they read as rock mesas, not liquid.
constant float FDY_AMP = 0.032f;
/// Lipschitz safety for the heightfield march (cf. VL_SDF_STEP_SCALE).
constant float FDY_STEP_SCALE = 0.55f;
/// Crest steepening. The raw field rolls off gently between cells and reads as soft
/// blobs; tanh sharpens the walls without unbounding the amplitude.
constant float FDY_SHARPEN = 1.35f;
/// Sub-cell capillary ripple. MUST be finer than the cells — at a coarser
/// wavelength it is just another big wobble, not surface detail.
constant float FDY_CAP_FREQ = 88.0f;
constant float FDY_CAP_AMP = 0.17f;
/// Thin-film thickness mapping (fringe orders across the wave).
constant float FDY_FILM_BASE = 2.5f;
// MEASURED (session 2026-07-27T16-31-01Z): at scale 0.95 / drift 3.10 roughly
// three-quarters of the colour came from the STATIC world-space drift, so the frame
// barely moved (luminance swing 7 %, median frame delta 1.1/255) — which is exactly
// why the sync was invisible and the preset read as boring. The concept's premise is
// that the WAVE is the film thickness, so the wave must dominate: the colour bands
// now ripple and invert WITH the standing wave, which makes the subharmonic legible
// as a rhythmic colour pulse rather than a geometric subtlety nobody can see.
constant float FDY_FILM_SCALE = 1.50f;
constant float FDY_FILM_DRIFT = 0.85f;

constexpr sampler fdySampler(coord::normalized, address::repeat, filter::linear);

// MARK: - Field sampling

/// Surface height at a world XZ, in world units.
///
/// `detail` fades the sub-cell capillary layer with the pixel footprint. Faded
/// wholesale it takes the cells with it — the detail must be band-limited PER
/// FEATURE, each against its own wavelength.
static inline float fdy_height(float2 wxz,
                               constant FeatureVector& f,
                               constant SceneUniforms& s,
                               texture2d<float> field,
                               float detail) {
    float2 uv = wxz / FDY_TILE;
    float u = field.sample(fdySampler, uv).r;
    u = tanh(u * FDY_SHARPEN) * 1.15f;

    // THE FARADAY SUBHARMONIC — the preset's beat sync, and its actual signature.
    //
    // A parametrically-driven surface responds at HALF the drive frequency: crests
    // and troughs trade places every other drive cycle. That inversion IS what you
    // observe in a Faraday experiment. Musically it means the sea should invert every
    // other BEAT — so it is beat-locked by construction rather than by a mapping.
    //
    // `bar_phase01` runs 0→1 across a 4-beat bar (the CACHED grid, not live onsets —
    // Layer 4), so 4π·bar_phase01 completes one full cycle every TWO beats. Exactly
    // the subharmonic. Previously this ran off `accumulatedAudioTime` at ~0.1 Hz — a
    // ten-second breath with no relationship to the music, which is why Matt read it
    // as "not synced even remotely": there was no beat route in the preset at all.
    //
    // Cold start: `bar_phase01` is 0 until the grid installs, so cos(0) = 1 and the
    // sea simply holds its extension without breathing — nothing fires at the wrong
    // phase (the cold-start contract), and there is no jump when the grid arrives.
    float subPhase = 4.0f * 3.14159265f * f.bar_phase01;
    float eta = u * cos(subPhase);

    // Capillary ripple in WORLD coordinates. Tile-local coordinates jump 1 -> 0 at
    // every tile edge and, at a non-integer frequency, that discontinuity draws a
    // hard seam across the world.
    float amp = FDY_CAP_AMP * clamp(fabs(u), 0.0f, 1.5f) * detail;
    float2 q = (wxz / FDY_TILE) * FDY_CAP_FREQ * 6.28318530718f;
    float ripple = sin(q.x + subPhase * 2.0f) * sin(q.y * 0.86f - subPhase * 1.7f)
                 + 0.45f * sin((q.x * 0.55f + q.y * 0.62f) + subPhase * 2.4f);

    return (eta + amp * ripple * 0.10f) * FDY_AMP;
}

// MARK: - Scene SDF

float sceneSDF(float3 p,
               constant FeatureVector& f,
               constant SceneUniforms& s,
               constant StemFeatures& stems,
               texture2d<float> ferrofluidHeight) {
    (void)stems;
    // Detail is faded by view distance: a distant pixel covers many ripples, so
    // keeping them produces sparkle rather than detail. Cells are ~10x coarser and
    // survive much further, which is why they are faded separately.
    float dist = length(p - s.cameraOriginAndFov.xyz);
    float detail = 1.0f / (1.0f + dist * dist * 0.12f);
    float h = fdy_height(p.xz, f, s, ferrofluidHeight, detail);
    return (p.y - h) * FDY_STEP_SCALE;
}

// MARK: - MetalFX motion vectors (MFX.1)

/// The camera is static and the sea deforms in place, so a surface feature keeps its
/// world XZ from frame to frame — the previous position is the same point. Exact for
/// the dominant screen motion; the standing wave's vertical breathing is a slow
/// continuous deformation that MetalFX's history rejection absorbs.
float3 scenePrevPosition(float3 worldPos,
                         constant FeatureVector& f,
                         constant SceneUniforms& s,
                         constant StemFeatures& stems) {
    (void)f;
    (void)s;
    (void)stems;
    return worldPos;
}

// MARK: - Thin-film optics

/// Interference colour for a film of the given optical thickness.
/// I(lambda) = 0.5 + 0.5*cos(4*pi*n*d*cosTheta / lambda), evaluated at R/G/B.
static inline float3 fdy_thinFilm(float thickness, float shift) {
    float3 invLambda = float3(1.0f, 1.26f, 1.60f);   // R < G < B
    return 0.5f + 0.5f * cos(6.28318530718f * thickness * invLambda + shift);
}

/// IQ cosine palette — a slower second colour layer so the frame carries several
/// widely-separated hues at once instead of one rainbow ramp.
static inline float3 fdy_palette(float t) {
    return 0.55f + 0.45f * cos(6.28318530718f * (t + float3(0.00f, 0.28f, 0.58f)));
}

// MARK: - Scene Material

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
    outMatID = 0;     // dielectric — the engine's Cook-Torrance carries the sheen

    // This is a heightfield, so the hit point's own height IS the film thickness —
    // no second field sample needed (sceneMaterial has no access to texture(10)).
    float hLocal = p.y / FDY_AMP;

    // Colour travels with the music's energy clock.
    float huePhase = s.sceneParamsA.x * 0.55f;

    // Large-scale thickness drift. Without it every region sits at one thickness and
    // renders as a dead flat colour; with it, different areas land on different
    // fringe orders and the frame carries several hues at once.
    float2 dw = p.xz * 0.55f;
    float drift = sin(dw.x * 2.1f + huePhase * 0.7f) * cos(dw.y * 1.7f - huePhase * 0.5f)
                + 0.6f * sin((dw.x + dw.y) * 1.3f + huePhase * 0.9f);

    float thickness = FDY_FILM_BASE + hLocal * FDY_FILM_SCALE + drift * FDY_FILM_DRIFT;

    float3 base = fdy_palette(drift * 0.30f + hLocal * 0.14f + huePhase * 0.16f);

    // Band-limit the fringes with view distance, fading toward the PALETTE colour —
    // fading to grey is what washes every steep face and the whole distance to cream.
    float dist = length(p - s.cameraOriginAndFov.xyz);
    float aa = 1.0f / (1.0f + dist * dist * 0.05f);
    float3 iridescence = mix(base, fdy_thinFilm(thickness, huePhase), aa);

    // Crests bloom into brighter, more saturated colour.
    float crest = smoothstep(0.25f, 1.20f, hLocal);

    albedo = mix(base * 0.62f, iridescence, 0.80f) * (0.85f + 0.55f * crest);
    // Wet, glossy liquid: low roughness so the engine's specular reads as a sheen on
    // the crests; troughs sit slightly rougher.
    roughness = mix(0.34f, 0.16f, clamp(crest, 0.0f, 1.0f));
    metallic = 0.0f;
}
