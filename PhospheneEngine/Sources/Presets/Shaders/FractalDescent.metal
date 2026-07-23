// FractalDescent.metal — FD.1 maquette: Mandelbox distance estimator + a
// self-similar descent, rendered through the shared ray_march G-buffer path.
//
// CONCEPT (docs/presets/psychedelic_geometry/PG_FD_FRACTAL_DESCENT.md §A0/§A3):
// an endless cinematic fall INTO a Mandelbox cathedral-world — recursive
// chambers opening into deeper chambers. The identity trait is the sensation of
// an unending fall into an infinite, self-elaborating fractal world.
//
// REFERENCES (docs/VISUAL_REFERENCES/mandelbox_cathedral/, inherited by the
// FD supersession of PG.3):
//   01_macro_fan_vault.jpg  (HERO) — cathedral-scale chambers/ribs, the macro read
//   02_meso_muqarnas.jpg           — nested self-similar cells (meso, 2nd iteration)
//   03_micro_geode.jpg             — micro sub-chambers + crystalline character
//   06_palette_stained_glass_light.jpg — jewel palette / mood-tinted IBL target
// Anti-reference: a flat 2D Mandelbrot-zoom look (no 3D depth or lighting), and
// over-iterated mush with no readable architecture.
//
// THE DISTANCE ESTIMATOR IS PORTED, NOT DERIVED (FA #73). Source: Syntopia's
// Fragmentarium, Examples/Historical 3D Fractals/Mandelbox.frag — the
// Rrrola (Jan Kadlec) optimised form of Tom Lowe's Mandelbox. The box fold,
// sphere fold, the `p.w` running-derivative and the final distance expression
// are reproduced verbatim; only the syntax is MSL and the orbit trap is
// unconditional (Fragmentarium gates it on ColorIterations).
//
// AUDIO (FD.1 scope): NONE YET. This maquette is deliberately audio-inert so the
// task-3 performance gate measures the geometry cost alone. The §A4 hero routing
// (f.arousal -> descent velocity, f.bass_att_rel -> fold open) lands only after
// the gate passes, and see the FD.1 report re: the f.arousal / f.bass collision
// with the preset-agnostic modulator in RenderPipeline+RayMarch.swift.

#include <metal_stdlib>
using namespace metal;

// MARK: - Mandelbox parameters

// Scale 2.7 sits in the "navigable architecture" band (2.0-3.0); Scale 3.0 is
// the perfect-Menger degenerate case and reads as rigid boxes, Scale < 2 closes
// the interior corridors the descent needs. MinRad2 0.25 is the Fragmentarium
// default across essentially every published Mandelbox preset.
constant float FD_SCALE    = 2.7f;
constant float FD_MIN_RAD2 = 0.25f;

// Iteration cap. NOT animated, ever — the fold morph is the continuous scale
// parameter (an integer count change pops the whole structure in one frame).
constant int   FD_ITERS    = 10;

// Rrrola's precomputed constants (Fragmentarium `init()`): folding the
// /MinRad2 into the scale vector is what makes the sphere fold a single
// clamp(max(...)) with no branch.
//
// These live in function scope, not the `constant` address space: MSL requires
// `constant` initializers to be compile-time constant expressions, and fabs()/
// pow() calls do not qualify (the shader silently fails to compile and the
// preset is dropped — Failed Approach #44). As locals over literal inputs the
// compiler folds them anyway, so there is no per-invocation cost.
#define FD_SCALE_VEC      (float4(FD_SCALE, FD_SCALE, FD_SCALE, fabs(FD_SCALE)) / FD_MIN_RAD2)
#define FD_ABS_SCALE_M1   (fabs(FD_SCALE - 1.0f))
#define FD_ABS_SCALE_POW  (pow(fabs(FD_SCALE), float(1 - FD_ITERS)))

// MARK: - Distance estimator (ported — see header)

/// Rrrola-optimised Mandelbox distance estimator. `orbitTrap` returns the
/// per-axis closest approach across the iteration, which is what makes the
/// colour follow the geometry rather than sit on it as a flat ramp (§A2
/// "the single biggest look lever").
static inline float fd_mandelboxDE(float3 pos, thread float4& orbitTrap) {
    float4 p  = float4(pos, 1.0f);
    float4 p0 = p;
    orbitTrap = float4(1e10f);

    for (int i = 0; i < FD_ITERS; i++) {
        p.xyz = clamp(p.xyz, -1.0f, 1.0f) * 2.0f - p.xyz;          // box fold
        float r2 = dot(p.xyz, p.xyz);
        orbitTrap = min(orbitTrap, fabs(float4(p.xyz, r2)));
        p *= clamp(max(FD_MIN_RAD2 / r2, FD_MIN_RAD2), 0.0f, 1.0f); // sphere fold
        p  = p * FD_SCALE_VEC + p0;
        if (r2 > 1000.0f) { break; }
    }
    return (length(p.xyz) - FD_ABS_SCALE_M1) / p.w - FD_ABS_SCALE_POW;
}

// MARK: - Descent

/// The descent is a *scale* descent, not a translation.
///
/// A Mandelbox is a bounded object, so translating a camera downward through it
/// necessarily exits it — there is no infinite corridor to fall down. What the
/// object does have is self-similarity under scaling by |Scale|: the structure
/// at zoom z and at zoom z*|Scale| are the same structure. So driving
/// zoom = |Scale|^fract(phase) sweeps one full octave of the fractal and then
/// wraps *onto itself* — a genuinely seamless, unending fall INTO the world,
/// with no pop at the wrap and no possibility of flying out into empty space.
///
/// Uniform scaling is exact for a distance estimator (DE(p*z)/z is still a valid
/// DE), so this costs no Lipschitz safety — unlike domain repetition, which
/// would break the DE across the fold and punch holes in the geometry.
static inline float fd_descentZoom(float phase) {
    return pow(fabs(FD_SCALE), fract(phase));
}

// MARK: - Scene SDF

float sceneSDF(float3 p,
               constant FeatureVector& f,
               constant SceneUniforms& s,
               constant StemFeatures& stems,
               texture2d<float> ferrofluidHeight) {
    (void)f;
    (void)stems;
    (void)ferrofluidHeight;   // slot-10; Ferrofluid Ocean only.

    // sceneParamsA.x is the engine's accumulated audio time.
    float zoom = fd_descentZoom(s.sceneParamsA.x * 0.12f);
    // A bounding-sphere early-out was tried here and REMOVED: measured at
    // iteration caps 8 and 10 across enclosed and open compositions it changed
    // nothing (8.19 vs 8.01 ms p95), because the cost is not missed rays creeping
    // to the far plane — it is grazing rays crawling near the surface, which an
    // open composition has more of. Do not re-add it without a measurement.
    float4 trap;
    return fd_mandelboxDE(p * zoom, trap) / zoom;
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
    (void)f;
    (void)stems;
    (void)outMatID;   // FD.1 ships ONE maquette material (matID 0 dielectric).
    (void)lumen;      // slot-8; Lumen Mosaic only.

    // The orbit trap is recomputed here because sceneSDF and sceneMaterial are
    // separate entry points off the shared preamble with no channel between
    // them (VolumetricLithograph duplicates its kickPulse for the same reason).
    float zoom = fd_descentZoom(s.sceneParamsA.x * 0.12f);
    float4 trap;
    fd_mandelboxDE(p * zoom, trap);

    // Colour follows the geometry: the trap's per-axis closest approach varies
    // with which fold the surface belongs to, so the palette tracks structure
    // (ref 06_palette_stained_glass_light.jpg jewel tones).
    float t = clamp(trap.w * 1.6f, 0.0f, 1.0f);
    albedo    = mix(float3(0.10f, 0.16f, 0.42f), float3(0.85f, 0.62f, 0.20f), t);
    roughness = mix(0.25f, 0.65f, clamp(trap.x, 0.0f, 1.0f));
    metallic  = 0.30f;
}
