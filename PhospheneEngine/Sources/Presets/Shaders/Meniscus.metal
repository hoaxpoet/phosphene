// Meniscus.metal — the backdrop the line surface floats over (MEN.2a).
//
// Two spatial layers, drawn fullscreen BEFORE the geometry overlay:
//
//   T5 — a grainy dark ground plane far below the plate (reference `04` is the
//        clearest frame for the separation; `01` shows the plate's shadow side
//        falling across it).
//   T6 — ONE cool directional light off to one side, everything else falling to
//        near black. Not ambient, not multi-light. The sky above the horizon is a
//        single soft gradient wash from the light side — not a skybox, not stars,
//        not clouds (reference `02`).
//
// The line surface itself is NOT drawn here — it is `MeniscusSurface` geometry
// composited on top via the `.particles` pass (the `CymaticResonance` /
// `Filigree` ground-fragment precedent).
//
// NO AUDIO COUPLING AT MEN.2a — deliberately. The source's own audio path lands at
// MEN.2b, the Phosphene stem routing at MEN.3. `features` is read for `time` only.
//
// Preset-library shader: compiled WITH the utility preamble, so `fbm4`/`fbm8` are
// available here (they are not in `Renderer/Shaders/MeniscusSurface.metal`).

#include <metal_stdlib>
using namespace metal;

// MARK: - Camera constants
//
// These MIRROR `MeniscusSurface.makeConfig` so the ground's horizon sits at the same
// perspective as the plate. MEN.2b SEAM: when the source's camera integration lands,
// both consumers need the angles from one place — a per-preset fragment buffer (slot
// 6) is the obvious carrier. Duplicated constants are the MEN.2a shortcut and the
// first thing MEN.2b should delete.
constant float kMeniscusPitch = 0.30;
constant float kMeniscusFocal = 1.0;
constant float kMeniscusCamHeight = 0.72;
/// How far the ground plane sits below the floating plate. This gap IS trait T5 —
/// "the gap between them is what gives the composition its depth".
constant float kMeniscusGroundDrop = 2.6;
/// Screen-space POSITION of the single key light — upper right, as in every
/// reference frame in the curated set. Aspect-corrected NDC.
///
/// A position with a radial falloff, NOT a direction with an angular dot product.
/// The first version took `dot(normalize(ndc), lightDir)`, which depends only on the
/// ANGLE about screen centre — so it painted a hard-edged wedge with a seam where the
/// dot product crossed over, and `normalize` was unstable near the centre. Reference
/// `02` is a soft blob falling off in every direction; distance-based falloff has no
/// boundary to show.
constant float2 kMeniscusLightPos = float2(0.58, 0.52);
/// Exponential falloff rate. Exponential, not a power of a clamped dot: it never
/// reaches zero, so there is no edge anywhere in the frame.
/// Fast enough that the wash is a CORNER glow falling to black across the frame
/// (reference `01`), not a uniform band. A gentle rate removes the edge but flattens
/// the sky into a lit strip above the horizon, which is its own kind of wrong.
constant float kMeniscusLightFalloff = 2.05;

// MARK: - Ground

/// Grainy dark plane. Four distinct spatial scales per the detail-cascade rule:
/// a broad tonal drift, the `fbm8` body, a coarse grain, and a fine speckle.
///
/// SCALES ARE SET FROM THE PROJECTED GEOMETRY, NOT PICKED. `plane` is in world units
/// and runs from ~3 at the bottom of the frame to the hundreds at the horizon, because
/// `dist` diverges as the ray flattens. The first version used scales of 1.9 / 11 / 47
/// on those coordinates, which sampled the noise at coordinates in the thousands: every
/// octave aliased and averaged to a constant, and the measured grain was **stdev 0.00**
/// — a flat plate that no amount of extra contrast could rescue, because there was no
/// signal left to stretch.
///
/// So: low base frequencies, and the two detail octaves fade out with distance rather
/// than aliasing. That is what makes the plane read as the coarse speckle of reference
/// `04` instead of fog.
static float3 meniscus_ground(float2 plane, float dist, float lightFacing) {
    // Detail survives only in the near field; past that it would be sub-pixel.
    float detail = saturate(1.0 - dist / 26.0);

    float broad = fbm4(float3(plane * 0.09, 0.0));
    float body = fbm8(float3(plane * 0.30, 3.7));
    float grain = fbm4(float3(plane * 0.95, 8.1));
    float speckle = fbm4(float3(plane * 2.60, 17.3));

    float raw = 0.26 * broad + 0.30 * body
              + 0.28 * grain * detail
              + 0.16 * speckle * detail * detail;
    // `fbm4`/`fbm8` return approximately [-1, 1] CENTRED ON ZERO, not [0, 1]. Remap
    // before any contrast or threshold work. Assuming [0, 1] here is what made the
    // plane a flat clipped sheet: a contrast stretch about 0.4 drove a zero-mean
    // signal to -1.1 and saturated it to zero for every pixel — measured grain was
    // exactly stdev 0.00, and raising the brightness range only lifted the floor
    // because there was no signal left to lift.
    float tone = raw * 0.5 + 0.5;
    // Now push toward contrast — the reference ground is coarse and SPECKLED, not a
    // smooth grey mist. T5 needs two distinct spatial layers, and a layer you cannot
    // see is not one of them.
    tone = saturate((tone - 0.5) * 2.9 + 0.5);
    // Still far darker than the plate (whose lines run near 1.0), so the surface stays
    // the subject — but no longer indistinguishable from the void.
    // Kept DARK on purpose. T5 is "the plate floats in a dark void over a separate
    // textured ground" — a mid-grey plane reads as a road and the void is gone, so
    // the grain has to live at low levels rather than be bought with brightness.
    float level = mix(0.006, 0.030, tone) * lightFacing;
    return float3(level * 0.86, level * 0.95, level);
}

// MARK: - Fragment

fragment float4 meniscus_ground_fragment(
    VertexOut in [[stage_in]],
    constant FeatureVector& features [[buffer(0)]]
) {
    // NDC, matching the plate's projection exactly. `uv` is top-left origin, so the
    // y flip is what puts +1 at the top of the frame.
    float aspect = max(features.aspect_ratio, 0.01);
    float2 ndc = float2((in.uv.x - 0.5) * 2.0, 1.0 - in.uv.y * 2.0);

    // Invert the plate's projection to a world-space view ray. `meniscus_project`
    // maps view→NDC as (vx·f/z/aspect, vy·f/z), so a pixel's view direction is
    // (ndc.x·aspect/f, ndc.y/f, 1); the world direction is that rotated back by the
    // TRANSPOSE of the pitch matrix.
    float3 view = float3(ndc.x * aspect / kMeniscusFocal, ndc.y / kMeniscusFocal, 1.0);
    float cp = cos(kMeniscusPitch), sp = sin(kMeniscusPitch);
    float3 ray = normalize(float3(view.x,
                                  view.y * cp - view.z * sp,
                                  view.y * sp + view.z * cp));

    // ONE cool key light (T6), as a smooth radial falloff from its screen position.
    // Shared by both layers so the ground brightens toward the same side the sky does.
    float keyDist = length(ndc * float2(aspect, 1.0) - kMeniscusLightPos);
    float key = exp(-keyDist * kMeniscusLightFalloff);

    // Cool teal, the source's own light colour. The PALETTE is an MEN.3 decision
    // (`MENISCUS_PLAN.md` §6) — this is the neutral inherited value, not a choice.
    const float3 keyColour = float3(0.10, 0.62, 0.58);

    // --- ground -------------------------------------------------------------------
    // Below the horizon: the plane sits `groundDrop` beneath the plate, and the camera
    // `camHeight` above it. Clamped away from ray.y = 0 so the grazing term stays
    // finite through the horizon blend below.
    float downward = min(ray.y, -0.006);
    // Clamped: the raw distance diverges toward the horizon, which is what pushed the
    // noise coordinates past the point of aliasing.
    float dist = min((kMeniscusGroundDrop + kMeniscusCamHeight) / -downward, 140.0);
    float2 plane = float2(ray.x, ray.z) * dist;
    // Drift the texture slowly so the void is not a frozen photograph. This is the
    // ground's only motion; the plate carries everything else.
    plane += float2(features.time * 0.045, features.time * 0.021);
    float3 groundRGB = meniscus_ground(plane, dist, 0.55 + 2.1 * key);
    // Fade toward the horizon so the plane does not terminate in a hard line.
    groundRGB *= mix(0.40, 1.0, saturate(1.0 / (1.0 + dist * 0.10)));

    // --- sky ----------------------------------------------------------------------
    // One soft gradient wash from the light side, falling to black. Reference `02`:
    // not a skybox, not stars, not clouds.
    float up = saturate(ray.y * 3.4);
    float3 skyRGB = keyColour * key * (1.0 - up * 0.30) * 1.35;
    skyRGB += keyColour * pow(key, 3.2) * 0.34;   // the tighter lateral glare core

    // --- horizon ------------------------------------------------------------------
    // Blend rather than branch. A hard `if (ray.y < 0)` cut left a visible seam across
    // the frame where a bright sky met a near-black ground; a narrow blend reads as the
    // haze in reference `02` while staying tight enough for `04`'s crisper horizon.
    float3 rgb = mix(groundRGB, skyRGB, smoothstep(-0.012, 0.014, ray.y));

    // Never fully black anywhere (D-037) — the backdrop alone clears the floor even
    // before the surface is drawn on top.
    rgb = max(rgb, float3(0.004, 0.005, 0.007));
    return float4(rgb, 1.0);
}
