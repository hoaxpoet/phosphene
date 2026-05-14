// POM.metal — Parallax Occlusion Mapping.
//
// Provides per-pixel depth displacement for surfaces with height detail,
// making flat geometry appear to have real depth: brick mortar, stone,
// leather, bark, carved rock.
//
// Both functions require a height texture and must be called from a fragment
// shader (they need the view direction in tangent space).
//
// DO NOT add #include <metal_stdlib> or using namespace metal.

// ─── POM result type ─────────────────────────────────────────────────────────

struct POMResult {
    float2 uv;          ///< Displaced UV coordinate to use for subsequent samples.
    float  self_shadow; ///< Self-shadowing factor [0,1]. Multiply with direct lighting.
};

// ─── Basic POM ────────────────────────────────────────────────────────────────

/// Parallax Occlusion Mapping: 32-step linear search + 8-step binary refinement.
///
/// `height_tex`  — height map (single-channel, white = highest).
/// `samp`        — sampler (bilinear + repeat recommended).
/// `uv`          — input UV coordinates (will be displaced).
/// `view_ts`     — view direction in tangent space. Use ws_to_ts() to convert.
/// `depth_scale` — depth amplitude. 0.02 = subtle brick mortar, 0.1 = deep rock.
///
/// Returns displaced UV. Sample all surface textures at the displaced UV.
///
/// Reference: Morgan McGuire & Max McGuire, "Steep Parallax Mapping" (2005).
static inline float2 parallax_occlusion(
    texture2d<float> height_tex,
    sampler          samp,
    float2           uv,
    float3           view_ts,
    float            depth_scale
) {
    const int linear_steps  = 32;
    const int binary_steps  = 8;

    // Step direction: divide depth range into linear_steps equal layers.
    float layer_depth   = 1.0 / float(linear_steps);
    float2 delta_uv     = (view_ts.xy / view_ts.z) * depth_scale / float(linear_steps);

    float  curr_depth   = 0.0;
    float2 curr_uv      = uv;
    float  curr_height  = 1.0 - height_tex.sample(samp, curr_uv).r;

    // Linear search: find first layer where geometry depth ≥ layer depth.
    for (int i = 0; i < linear_steps; i++) {
        if (curr_depth >= curr_height) break;
        curr_uv      -= delta_uv;
        curr_height   = 1.0 - height_tex.sample(samp, curr_uv).r;
        curr_depth   += layer_depth;
    }

    // Binary refinement between last two layers. The "prev" layer's height
    // is never read inside the refinement loop (only its depth and UV are
    // used; layer heights at the midpoint are sampled freshly), so we omit
    // the sample. Xcode's Metal stage compiles with `-Werror` and trips on
    // an unused `prev_height` declaration.
    float2 prev_uv   = curr_uv + delta_uv;
    float  prev_depth = curr_depth - layer_depth;

    for (int i = 0; i < binary_steps; i++) {
        float2 mid_uv     = (curr_uv + prev_uv) * 0.5;
        float  mid_depth  = (curr_depth + prev_depth) * 0.5;
        float  mid_height = 1.0 - height_tex.sample(samp, mid_uv).r;
        if (mid_depth >= mid_height) {
            curr_uv    = mid_uv;
            curr_depth = mid_depth;
        } else {
            prev_uv    = mid_uv;
            prev_depth = mid_depth;
        }
    }
    return (curr_uv + prev_uv) * 0.5;
}

// ─── POM with self-shadow ─────────────────────────────────────────────────────

/// POM with soft self-shadow term. More expensive than basic POM (~2×) but
/// gives plausible contact shadows inside deep surface features.
///
/// `light_ts` — light direction in tangent space.
/// Returns both displaced UV and a shadow factor [0, 1] to multiply into direct
/// lighting: 0 = fully shadowed, 1 = fully lit.
static inline POMResult parallax_occlusion_shadowed(
    texture2d<float> height_tex,
    sampler          samp,
    float2           uv,
    float3           view_ts,
    float3           light_ts,
    float            depth_scale
) {
    POMResult result;
    result.uv = parallax_occlusion(height_tex, samp, uv, view_ts, depth_scale);

    // Self-shadow: march from displaced point toward light inside height field.
    const int shadow_steps = 16;
    float displaced_height = 1.0 - height_tex.sample(samp, result.uv).r;

    float2 shadow_delta = (light_ts.xy / max(light_ts.z, 0.01)) * depth_scale / float(shadow_steps);
    // (The per-iteration `layer` value is computed fresh in the loop; an
    // outer `shadow_layer` snapshot was unused. `-Werror` in Xcode's Metal
    // stage trips on the declaration.)

    float shadow = 1.0;
    for (int i = 1; i <= shadow_steps; i++) {
        float2 shadow_uv   = result.uv + shadow_delta * float(i);
        float  h           = 1.0 - height_tex.sample(samp, shadow_uv).r;
        float  layer       = displaced_height + (float(i) / float(shadow_steps)) * (1.0 - displaced_height);
        if (h > layer) {
            // Soften shadow proportional to how far we've emerged above the surface.
            shadow = min(shadow, 1.0 - (h - layer) * float(shadow_steps - i));
        }
    }
    result.self_shadow = clamp(shadow, 0.0, 1.0);
    return result;
}
