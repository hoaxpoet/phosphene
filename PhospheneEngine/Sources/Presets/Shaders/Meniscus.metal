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
/// Screen-space direction of the single key light — upper right, as in every
/// reference frame in the curated set.
constant float2 kMeniscusLightDir = float2(0.80, -0.60);

// MARK: - Ground

/// Grainy dark plane. Four distinct spatial scales per the detail-cascade rule:
/// a broad tonal drift, the `fbm8` body, a fine grain, and a sub-pixel sparkle that
/// keeps the plane from banding where it is nearly black.
static float3 meniscus_ground(float2 plane, float lightFacing) {
    float broad = fbm4(float3(plane * 0.35, 0.0));
    float body = fbm8(float3(plane * 1.9, 3.7));
    float grain = fbm4(float3(plane * 11.0, 8.1));
    float sparkle = fbm4(float3(plane * 47.0, 17.3));

    float tone = 0.24 * broad + 0.34 * body + 0.28 * grain + 0.14 * sparkle;
    // Push the grain toward contrast — the reference ground (`04`) is coarse and
    // speckled, not a smooth grey mist, and a low-contrast plane reads as fog.
    tone = saturate((tone - 0.42) * 2.4 + 0.42);
    // The plane is nearly black — it exists to give the plate something to float
    // OVER (T5), and the gap between the two layers is what carries the depth.
    float level = mix(0.012, 0.085, tone) * lightFacing;
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

    // Single cool key light, off to one side and grazing (T6).
    float facing = saturate(dot(normalize(ndc * float2(aspect, 1.0) + 1e-5),
                                kMeniscusLightDir) * 0.5 + 0.5);

    float3 rgb;
    if (ray.y < -0.004) {
        // Below the horizon — the ground plane, well beneath the floating plate. The
        // camera sits `camHeight` above the plate and the plane `groundDrop` below it.
        float dist = (kMeniscusGroundDrop + kMeniscusCamHeight) / -ray.y;
        float2 plane = float2(ray.x, ray.z) * dist;
        // Drift the texture slowly so the void is not a frozen photograph. This is
        // the ground's only motion; the plate carries everything else.
        plane += float2(features.time * 0.045, features.time * 0.021);
        rgb = meniscus_ground(plane, mix(0.55, 1.25, facing));
        // Fade the plane toward the horizon so it does not terminate in a hard line.
        rgb *= mix(0.25, 1.0, saturate(1.0 / (1.0 + dist * 0.10)));
    } else {
        // Above the horizon — one soft gradient wash from the light side, falling to
        // black. Reference `02`: not a skybox, not stars, not clouds.
        float up = saturate(ray.y * 3.4);
        float wash = pow(facing, 2.2) * (1.0 - up * 0.72);
        // Cool teal, the source's own light colour. The PALETTE is an MEN.3 decision
        // (`MENISCUS_PLAN.md` §6) — this is the neutral inherited value, not a choice.
        float3 key = float3(0.10, 0.62, 0.58);
        rgb = key * wash * 0.55;
        rgb += key * pow(facing, 9.0) * 0.30;   // the lateral glare term
    }

    // Never fully black anywhere (D-037) — the backdrop alone clears the floor even
    // before the surface is drawn on top.
    rgb = max(rgb, float3(0.004, 0.005, 0.007));
    return float4(rgb, 1.0);
}
