// Exotic.metal — Exotic and stylized surface material recipes.
//
// Recipes: mat_ocean, mat_ink, mat_marble, mat_granite, mat_sand_glints.
//
// All recipes follow the cookbook convention: return MaterialResult.
// See MaterialResult.metal for the composition pattern.
//
// Reference: SHADER_CRAFT.md §4.14, §4.15, §4.16, §4.17, §4.19
//
// Depends on: Noise tree (fbm8, worley_fbm, curl_noise, hash_f01),
//             PBR tree (sss_backlit), Materials/MaterialResult.
//
// DO NOT add #include <metal_stdlib> or using namespace metal.

// ─── 4.14 Ocean water ────────────────────────────────────────────────────────
// Source: SHADER_CRAFT.md §4.14 (expanded from paragraph form)
// Expanded from SHADER_CRAFT.md §4.14 paragraph form

/// Ocean water: Fresnel-weighted specular, deep-water absorption, foam on crests.
///
/// Caller responsibilities:
///   - `NdotV` ∈ [0, 1]: view-incidence cosine for Fresnel blend.
///   - `depth` ∈ [0, 1]: depth below wave crest (0 = crest/foam, 1 = trough).
///     Callers compute this from wave geometry (displacement derivatives).
///   - Gerstner-wave displacement and capillary fbm8 ripples are SDF/geometry
///     concerns at the preset level (SHADER_CRAFT §4.14 §7). This function
///     handles only material properties (albedo, roughness, metallic, foam).
MaterialResult mat_ocean(float3 wp, float3 n, float NdotV, float depth) {
    MaterialResult m;

    // Foam mask on wave crests: low depth → high foam fraction.
    float foam_mask = smoothstep(0.10, 0.35, 1.0 - depth);

    // Deep water absorption: dark blue-green at depth, lighter near surface.
    float3 deep_albedo    = float3(0.02, 0.06, 0.12);
    float3 shallow_albedo = float3(0.07, 0.18, 0.28);
    float3 foam_albedo    = float3(0.92, 0.94, 0.96);   // white foam

    float3 water_albedo = mix(deep_albedo, shallow_albedo, (1.0 - depth) * 0.6);
    m.albedo = mix(water_albedo, foam_albedo, foam_mask);

    // Roughness: mirror-smooth in deep troughs, rough foam at crests.
    m.roughness = mix(0.08, 0.85, foam_mask);
    // Metallic: foam is dielectric; open water uses Fresnel (approximated as 0)
    m.metallic  = 0.0;

    // Capillary ripple normal perturbation via fbm8.
    float3 ripple = float3(
        fbm8(wp.xzy * 8.0 + float3(0.0)),
        fbm8(wp.xzy * 8.0 + float3(4.3, 0.0, 0.0)),
        fbm8(wp.xzy * 8.0 + float3(0.0, 8.7, 0.0))
    );
    float ripple_amp = 0.04 * (1.0 - foam_mask);   // less ripple in foam
    m.normal = normalize(n + (ripple - 0.5) * ripple_amp);

    m.emission = float3(0.0);
    return m;
}

// ─── 4.15 Ink (2D stylized) ──────────────────────────────────────────────────
// Source: SHADER_CRAFT.md §4.15 (expanded from paragraph form)
// Expanded from SHADER_CRAFT.md §4.15 paragraph form

/// Ink: flat emissive surface with flow-field UV distortion.
///
/// Caller responsibilities:
///   - `ink_color`: the ink tint. Saturated colours read best.
///   - `flow_uv`: caller-computed distorted UV from a flow-map pass, or
///     simply wp.xy / scale for non-distorted output.
///   - `time`: accumulated audio time (FeatureVector.accumulated_audio_time)
///     for animated flow distortion.
///
/// Albedo and metallic are intentionally zero — ink is emissive-only.
MaterialResult mat_ink(float3 wp, float3 n,
                       float3 ink_color, float2 flow_uv, float t)
{
    MaterialResult m;

    // Flow-driven UV distortion via curl noise.
    float3 curl = curl_noise(float3(flow_uv, t * 0.3));
    float2 distorted_uv = flow_uv + curl.xy * 0.06;

    // Ink density from fBM at distorted UV — creates pooling and flow patterns.
    float density = fbm8(float3(distorted_uv * 3.0, t * 0.05)) * 0.5 + 0.5;
    density = smoothstep(0.3, 0.7, density);

    m.albedo    = float3(0.0);   // no diffuse reflection
    m.roughness = 0.0;
    m.metallic  = 0.0;
    m.normal    = n;
    m.emission  = ink_color * density;

    return m;
}

// ─── 4.17 Marble veining ─────────────────────────────────────────────────────
// Source: SHADER_CRAFT.md §4.17 (expanded from paragraph form)
// Expanded from SHADER_CRAFT.md §4.17 paragraph form

/// Marble: curl-noise-warped Perlin veins with sharp colour transition.
///
/// Produces bimodal distribution: near-white matrix and deep-saturation veins.
/// Vein sharpness is determined by the smoothstep transition width (0.02 default).
/// A subtle SSS emission term gives luminous translucency visible in back-lit scenes.
///
/// Caller responsibilities: none. All inputs are world-space position and normal.
MaterialResult mat_marble(float3 wp, float3 n) {
    MaterialResult m;

    // Domain-warped base coordinate: curl noise shifts vein lines organically.
    float3 curl = curl_noise(wp * 1.2) * 0.35;
    float3 warped = wp + curl;

    // Vein pattern from Perlin (curl-warped domain).
    // fbm8 returns ~[-1, 1]; crossover near 0 gives bimodal split.
    float vein_val = fbm8(warped * 2.5);

    // Sharp colour transition — bimodal: matrix vs vein.
    // Threshold centered at 0 (midpoint of fbm8's ~[-1, 1] range).
    float vein_mask = smoothstep(-0.05, 0.05, vein_val);

    float3 marble_base = float3(0.90, 0.88, 0.85);   // near-white matrix
    float3 marble_vein = float3(0.15, 0.08, 0.22);   // deep violet vein

    m.albedo    = mix(marble_base, marble_vein, vein_mask);
    m.roughness = mix(0.30, 0.55, vein_mask);   // veins are rougher
    m.metallic  = 0.0;

    // Subtle SSS: luminous translucency in back-lit configuration.
    float sss_term = (1.0 - vein_mask) * 0.06;   // matrix only
    m.emission = marble_base * sss_term;

    m.normal = n;
    return m;
}

// ─── 4.16 Granite ────────────────────────────────────────────────────────────
// Source: SHADER_CRAFT.md §4.16 (expanded from paragraph form)
// Expanded from SHADER_CRAFT.md §4.16 paragraph form

/// Granite: Worley-Perlin speckle over three colour stops, triplanar-projected.
///
/// Produces distinct crystal cells (dark matrix / medium feldspar / bright mica).
/// Mica inclusions have low roughness (0.15); everything else is rough (0.85).
///
/// The spec references `worley_fbm` for speckle mask — this function exists in
/// V.1 Noise/Worley.metal and produces a Worley-Perlin blend (SHADER_CRAFT §3.6).
///
/// Caller responsibilities: none.
MaterialResult mat_granite(float3 wp, float3 n) {
    MaterialResult m;

    // Three granite colour stops (dark matrix, warm feldspar, bright mica).
    float3 dark_matrix  = float3(0.08, 0.08, 0.10);
    float3 feldspar     = float3(0.58, 0.50, 0.44);
    float3 mica         = float3(0.82, 0.80, 0.76);

    // Worley-Perlin speckle for crystal grain boundaries.
    // worley_fbm effective range ~[-0.65, 0.79]; centre near 0.
    float w = worley_fbm(wp * 2.0);

    // Two-threshold classification into three stops.
    // Thresholds chosen relative to the worley_fbm ~[-0.65, 0.79] range.
    float mask_dark  = smoothstep(-0.35, 0.0,  w);   // lower 30% → dark matrix

    // Mica: high-frequency fbm8 inclusions at a separate scale.
    // fbm8 range is ~[-1, 1]; remap to [0, 1] via * 0.5 + 0.5.
    float mica_noise = fbm8(wp * 10.0 + float3(3.7, 9.1, 6.3));
    float mica_t     = mica_noise * 0.5 + 0.5;          // [0, 1]
    float mask_mica  = smoothstep(0.70, 0.90, mica_t);  // top ~10% → mica glints

    float3 grain_color = mix(dark_matrix, feldspar, mask_dark);
    grain_color = mix(grain_color, mica, mask_mica);

    m.albedo = grain_color;

    // Roughness: driven by grain noise at scale 5 — amplitude 0.70 gives
    // realistically wide speckle variation (low mica glints, rough matrix).
    m.roughness = clamp(0.50 + 0.70 * fbm8(wp * 5.0), 0.08, 0.92);
    m.metallic  = 0.0;   // granite is dielectric throughout

    // Triplanar normal perturbation — fbm8-based, avoids UV stretching.
    m.normal = triplanar_detail_normal(n, wp * 4.0, 0.05);

    m.emission = float3(0.0);
    return m;
}

// ─── 4.19 Sand with glints ────────────────────────────────────────────────────
// Source: SHADER_CRAFT.md §4.19 (Increment V.4)

/// Sand with specular glints: warm base with hash-lattice micro-facet sparkle.
///
/// Glints modelled as isolated high-frequency cells in a 3D hash lattice.
/// ~0.8% of cells get a near-mirror micro-facet (roughness 0.05, HDR emission).
///
/// Caller responsibilities: none.
MaterialResult mat_sand_glints(float3 wp, float3 n) {
    MaterialResult m;

    // Warm sand base with subtle fbm8 color variation.
    float var    = fbm8(wp * 4.0) * 0.5 + 0.5;
    m.albedo     = float3(0.85, 0.70, 0.50) * (0.85 + var * 0.20);
    m.roughness  = 0.90;
    m.metallic   = 0.0;

    // Triplanar detail normal for sand ripple micro-structure.
    m.normal = triplanar_detail_normal(n, wp * 8.0, 0.04);

    // Hash-lattice glint: rare cells (step(0.992, ...) ≈ 0.8%) fire a sparkle.
    // hash_f01_3 maps float3 → [0,1]; floor(wp*500) gives one cell ≈ 2mm world-space.
    float glint_hash = hash_f01_3(floor(wp * 500.0));
    float glint_mask = step(0.992, glint_hash);
    m.roughness = mix(m.roughness, 0.05, glint_mask);
    m.emission  = float3(1.0) * glint_mask * 2.0;   // HDR sparkle

    return m;
}
