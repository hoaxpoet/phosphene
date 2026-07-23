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
// AUDIO (FD.1, both heroes wired):
//   HERO #1 — descent SPEED follows the music's ENERGY, via accumulatedAudioTime
//     (sceneParamsA.x, the engine's running sum of energy x dt): fast when loud,
//     a near-stationary drift in silence (§A5), monotonic, zero CPU state. It is
//     the animation time base, not a declared audio_route (VolumetricLithograph
//     precedent — the QG.1 fixtures don't carry it; QG.1.1 boundary).
//   HERO #2 — fold-open on the bass swell, via f.bass_att_rel (D-026 deviation
//     primitive, soft-saturated) widening the box-fold LIMIT so the chamber
//     unfolds into a bigger one. Only the box-fold clamp bound moves — no scale
//     constant recompute, no per-pixel pow.
// The camera is STATIC (cameraDollySpeed defaults 0), so the descent is purely the
// in-shader scale-zoom; no collision with the preset-agnostic camera dolly.
// FD.2 = look pass (materials, thin-film, god-rays, fog, jewel palette); FD.3 =
// secondary audio + structural-boundary tuning + cert. Palette here is a single
// maquette material (monochrome-ish orbit-trap gold) — the jewel HDR is FD.2.

#include <metal_stdlib>
using namespace metal;

// MARK: - Mandelbox parameters

// Scale 2.7 sits in the "navigable architecture" band (2.0-3.0); Scale 3.0 is
// the perfect-Menger degenerate case and reads as rigid boxes, Scale < 2 closes
// the interior corridors the descent needs. MinRad2 0.25 is the Fragmentarium
// default across essentially every published Mandelbox preset.
constant float FD_SCALE    = 2.7f;
constant float FD_MIN_RAD2 = 0.25f;

// Iteration cap. NOT animated, ever — the fold morph is the continuous fold-limit
// parameter (an integer count change pops the whole structure in one frame).
// Locked at 8 (RMPERF.1 budget): the FD.1 contact sheets showed cap 8 is visually
// near-identical to cap 10 (full recursive architecture) while cap 6 collapses the
// self-elaboration; cap 8 + the RMPERF.1 preamble fits Tier-2 with headroom.
constant int   FD_ITERS    = 8;

// Fold-open (HERO #2): the bass swell widens the box-fold limit, opening the
// current chamber into a larger one — the "breakthrough" on the drop. Kept in a
// narrow band around the canonical 1.0 so the distance estimate stays valid (no
// holes); driven by f.bass_att_rel in sceneSDF. Only the box-fold clamp bound
// moves — the sphere fold, scale, and all precomputed scale constants are
// untouched, so this costs one extra clamp bound per iteration, no per-pixel pow.
constant float FD_FOLD_BASE  = 1.0f;
constant float FD_FOLD_RANGE = 0.18f;   // sweep-validated Lipschitz-safe interval

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
static inline float fd_mandelboxDE(float3 pos, float foldLimit, thread float4& orbitTrap) {
    float4 p  = float4(pos, 1.0f);
    float4 p0 = p;
    orbitTrap = float4(1e10f);

    for (int i = 0; i < FD_ITERS; i++) {
        p.xyz = clamp(p.xyz, -foldLimit, foldLimit) * 2.0f - p.xyz; // box fold (HERO #2)
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

/// Off-axis viewing offset, applied in camera space BEFORE the zoom so it scales
/// with the zoom and the self-similar octave wrap stays seamless: sampling
/// `(p + c) * zoom` at the wrap boundary still maps the structure onto itself
/// (a world-space `p*zoom + c` would break the wrap — the offset must ride the
/// scale). A pure on-axis descent rams the Mandelbox's central sphere dead-centre;
/// this views it off to the side, down a corridor, so the fall reads as spiralling
/// past structure rather than into a disc.
constant float3 FD_DESCENT_OFFSET = float3(0.30f, 0.16f, 0.0f);

static inline float3 fd_descentSample(float3 p, float zoom) {
    return (p + FD_DESCENT_OFFSET) * zoom;
}

// MARK: - Audio → descent + fold (HERO routing)

/// HERO #1 — descent speed follows the music's ENERGY. `accumulatedAudioTime`
/// (sceneParamsA.x) is the engine's running sum of energy × dt: it advances fast
/// when loud and crawls when quiet, so the fall speeds up on peaks and slows to a
/// near-stationary drift in silence (§A5) — for free, monotonic (never reverses),
/// with zero CPU state. This IS the arousal→velocity hero, driven off the more
/// literal energy envelope rather than the mood axis.
static inline float fd_descentPhase(constant SceneUniforms& s) {
    return s.sceneParamsA.x * 0.12f;
}

/// HERO #2 — the fold opens on a bass swell. `bass_att_rel` is the D-026
/// deviation primitive (never an absolute threshold on the AGC value, FA #31);
/// it spikes to ~3× on real music, so soft-saturate it into [0,1] and widen the
/// box-fold limit within the Lipschitz-safe band. A larger limit unfolds the
/// current chamber into a bigger one — the "breakthrough" on the drop.
static inline float fd_foldLimit(constant FeatureVector& f) {
    float swell = 1.0f - exp(-max(0.0f, f.bass_att_rel) * 1.6f);   // soft-saturate → [0,1)
    return FD_FOLD_BASE + FD_FOLD_RANGE * swell;
}

// MARK: - Scene SDF

float sceneSDF(float3 p,
               constant FeatureVector& f,
               constant SceneUniforms& s,
               constant StemFeatures& stems,
               texture2d<float> ferrofluidHeight) {
    (void)stems;
    (void)ferrofluidHeight;   // slot-10; Ferrofluid Ocean only.

    float phase = fd_descentPhase(s);
    float zoom  = fd_descentZoom(phase);               // HERO #1 (energy → speed)
    float3 q    = fd_descentSample(p, zoom);           // off-axis, wrap-preserving
    // A bounding-sphere early-out was tried here and REMOVED: measured at
    // iteration caps 8 and 10 across enclosed and open compositions it changed
    // nothing (8.19 vs 8.01 ms p95), because the cost is not missed rays creeping
    // to the far plane — it is grazing rays crawling near the surface, which an
    // open composition has more of. Do not re-add it without a measurement.
    float4 trap;
    return fd_mandelboxDE(q, fd_foldLimit(f), trap) / zoom;   // HERO #2 (bass → fold)
}

// MARK: - Jewel palette (FD.2 look pass)

/// Backlit-stained-glass jewel range (ref 06_palette_stained_glass_light.jpg:
/// cobalt / teal / emerald / amber / crimson against black). IQ cosine palette —
/// the biggest look lever over the FD.1 monochrome-gold maquette. Deliberately
/// LESS than a full hue cycle (freq 0.85, not 1.0) so neighbouring folds read as
/// related cathedral jewels rather than a garish full-rainbow wash; driven by the
/// orbit trap so colour tracks depth into the structure, like leadlight cells.
static inline float3 fd_jewel(float t) {
    return palette(t,
                   float3(0.50f, 0.47f, 0.55f),   // midtone (brighter)
                   float3(0.55f, 0.55f, 0.55f),   // amplitude (deeper saturation)
                   float3(0.85f, 0.85f, 0.85f),   // < one hue cycle → cohesive range
                   float3(0.55f, 0.30f, 0.10f));  // phase → cobalt→teal→amber→crimson
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

    // The orbit trap is recomputed here because sceneSDF and sceneMaterial are
    // separate entry points off the shared preamble with no channel between
    // them (VolumetricLithograph duplicates its kickPulse for the same reason).
    // Descent phase + fold limit MUST match sceneSDF exactly or the colour
    // detaches from the geometry.
    float phase = fd_descentPhase(s);
    float zoom  = fd_descentZoom(phase);
    float3 q    = fd_descentSample(p, zoom);
    float4 trap;
    fd_mandelboxDE(q, fd_foldLimit(f), trap);

    // Jewel hue follows depth into the structure (trap.w = closest approach to the
    // origin sphere), the same driver that varied cleanly in FD.1 — plus a small
    // per-fold offset so adjacent cells differ without the whole frame going one
    // colour (the v1 over-saturation failure).
    float hue    = fract(trap.w * 1.3f + trap.y * 0.6f);
    float3 jewel = fd_jewel(hue);

    // ── Three materials via matID, dispatched by orbit-trap REGION (§A2 detail
    //    cascade / ≥3 materials). The SHADED jewelled stone (matID 0) is dominant
    //    so the 3D form/AO/depth from FD.1 is preserved; thin-film iridescence
    //    rides the fold ridges; only the DEEPEST recesses self-illuminate (a glow
    //    accent, not a flood — v1 flooded emission and read flat). ──
    float cavity = 1.0f - smoothstep(0.0f, 0.045f, trap.w);  // deepest tiny pockets only
    float ridge  = 1.0f - smoothstep(0.0f, 0.03f, trap.y);   // 1 = right on a fold plane

    if (cavity > 0.85f) {
        // matID 1 — emission-dominated: the deep recesses glow like backlit glass
        // out of the dark (feeds the bloom bright-pass). Threshold kept TIGHT so a
        // large smooth face (e.g. the central sphere) can never go fully emissive
        // and flash the frame bright (D-157 flash safety).
        outMatID  = 1;
        // Vary the emissive hue across cavities (deep-cavity trap.w clusters near
        // one colour → uniform-blue polka-dots) so the recesses read as DIFFERENT
        // coloured votives — the stained-glass mix, not one blue repeated.
        float3 glow = fd_jewel(fract(trap.z * 3.1f + trap.x * 2.0f + 0.4f));
        albedo    = glow * (0.62f + 0.35f * cavity);         // brighter votives (tiny pockets → flash-safe)
        roughness = 0.5f;
        metallic  = 0.0f;
    } else if (ridge > 0.6f) {
        // matID 3 — metallic thin-film: iridescent shimmer on the fold edges
        // (§A2 "thin-film on fold edges" — the psychedelic signature).
        outMatID  = 3;
        albedo    = mix(float3(0.02f), jewel * 0.30f, 0.5f); // dark metal base under the film
        roughness = 0.40f;                                   // rougher → no grazing-angle white blowout
        metallic  = 0.85f;
    } else {
        // matID 0 — polished jewelled stone (chrome/marble ref 04/08): the
        // DOMINANT, shaded material that carries depth. Saturated, brighter than
        // FD.1's near-black, but still lit by Cook-Torrance so form reads.
        outMatID  = 0;
        albedo    = jewel * 0.95f;                            // brighter, more saturated stone
        roughness = mix(0.22f, 0.55f, clamp(trap.x * 2.0f, 0.0f, 1.0f));
        metallic  = 0.42f;
    }
}
