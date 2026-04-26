// ChromaticAberration.metal — Chromatic aberration (colour fringing) effects.
//
// Simulates lens dispersion by sampling R, G, B channels at slightly offset
// UV coordinates. Radial offset pushes channels toward/away from screen centre;
// directional offset uses a caller-supplied direction.
//
// Zero amount: byte-identical to a single tex.sample(samp, uv) call.
//
// Reference: SHADER_CRAFT.md §10.2, §11.2
//
// DO NOT add #include <metal_stdlib> or using namespace metal.

// Source: SHADER_CRAFT.md §11.2 — ChromaticAberration

// ─── Radial chromatic aberration ─────────────────────────────────────────────

/// Radial chromatic aberration — channels pushed radially from screen centre.
///
/// `uv`     = normalised texture coordinate [0, 1]².
/// `amount` = dispersion strength. 0 = no effect. 0.01–0.05 is typical.
///            Negative values reverse channel order (violet fringe inward).
///
/// When `amount == 0`, returns exactly `tex.sample(samp, uv)` — no extra reads.
static inline float3 chromatic_aberration_radial(
    texture2d<float> scene_tex,
    sampler          samp,
    float2           uv,
    float            amount
) {
    if (amount == 0.0) {
        return scene_tex.sample(samp, uv).rgb;
    }
    // Offset direction: radially outward from centre (0.5, 0.5).
    float2 dir = uv - 0.5;

    // R shifts outward, B shifts inward, G stays.
    float2 uv_r = uv + dir * amount;
    float2 uv_b = uv - dir * amount;

    float r = scene_tex.sample(samp, uv_r).r;
    float g = scene_tex.sample(samp, uv).g;
    float b = scene_tex.sample(samp, uv_b).b;

    return float3(r, g, b);
}

// ─── Directional chromatic aberration ────────────────────────────────────────

/// Directional chromatic aberration — channels offset along a supplied direction.
///
/// `dir`    = 2D direction vector (does not need to be normalised).
///            Determines which way each channel disperses.
/// `amount` = dispersion magnitude. 0 = no effect.
///
/// When `amount == 0`, returns exactly `tex.sample(samp, uv)` — no extra reads.
static inline float3 chromatic_aberration_directional(
    texture2d<float> scene_tex,
    sampler          samp,
    float2           uv,
    float2           dir,
    float            amount
) {
    if (amount == 0.0) {
        return scene_tex.sample(samp, uv).rgb;
    }
    float2 uv_r = uv + dir * amount;
    float2 uv_b = uv - dir * amount;

    float r = scene_tex.sample(samp, uv_r).r;
    float g = scene_tex.sample(samp, uv).g;
    float b = scene_tex.sample(samp, uv_b).b;

    return float3(r, g, b);
}
