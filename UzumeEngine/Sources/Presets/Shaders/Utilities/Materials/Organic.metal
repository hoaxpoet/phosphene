// Organic.metal — Organic and biological surface material recipes.
//
// Recipes: mat_bark, mat_leaf, mat_silk_thread, mat_chitin, mat_velvet.
//
// All recipes follow the cookbook convention: return MaterialResult.
// See MaterialResult.metal for the composition pattern.
//
// Reference: SHADER_CRAFT.md §4.3, §4.7, §4.8, §4.12, §4.18
//
// Depends on: Noise tree (fbm8, worley3d), PBR tree (fiber_marschner_lite,
//             sss_backlit, thinfilm_rgb), Materials/MaterialResult (FiberParams,
//             triplanar_detail_normal).
//
// DO NOT add #include <metal_stdlib> or using namespace metal.

// ─── 4.7 Bark ────────────────────────────────────────────────────────────────
// Source: SHADER_CRAFT.md §4.7 (verbatim transcription)

/// Tree bark: vertical fiber ridges, lichen patches, triplanar micro detail.
///
/// Caller responsibilities:
///   - `fiber_up`: world-space unit vector along the tree trunk direction.
///     Typically float3(0, 1, 0) for vertical trunks.
MaterialResult mat_bark(float3 wp, float3 n, float3 fiber_up) {
    MaterialResult m;
    // Base color: warm brown with variation
    float3 base  = float3(0.18, 0.11, 0.07);
    float3 lichen = float3(0.35, 0.42, 0.22);

    // Lichen patches via Worley
    float w = worley3d(wp * 0.6).x;
    float lichen_mask = smoothstep(0.25, 0.40, w);
    m.albedo = mix(base, lichen, lichen_mask * 0.4);

    // Vertical fiber displacement: ridges along fiber_up
    float fiber_coord = dot(wp, fiber_up);
    float ridges = abs(fract(fiber_coord * 8.0) - 0.5);
    ridges = smoothstep(0.1, 0.4, ridges);

    // Overall bark normal perturbation
    float3 horizontal = normalize(cross(fiber_up, n));
    m.normal = normalize(n + horizontal * ridges * 0.35);
    // Micro detail via triplanar procedural fBM normal perturbation.
    // triplanar_detail_normal is defined in MaterialResult.metal.
    m.normal = triplanar_detail_normal(m.normal, wp * 30.0, 0.04);

    m.roughness = 0.85 + 0.1 * fbm8(wp * 5.0);
    m.roughness = clamp(m.roughness, 0.0, 1.0);
    m.metallic  = 0.0;
    m.emission  = float3(0.0);
    return m;
}

// ─── 4.8 Translucent leaf ────────────────────────────────────────────────────
// Source: SHADER_CRAFT.md §4.8 (verbatim transcription)

/// Translucent leaf: chlorophyll green with vein variation and back-lit SSS.
///
/// Caller responsibilities:
///   - `V`: world-space view direction (toward camera).
///   - `L`: world-space light direction (toward light source).
///   Both must be unit vectors.
MaterialResult mat_leaf(float3 wp, float3 n, float3 V, float3 L) {
    MaterialResult m;
    // Chlorophyll green with vein variation
    float3 base = float3(0.12, 0.25, 0.08);
    float3 vein = float3(0.20, 0.35, 0.12);
    float vein_mask = smoothstep(0.45, 0.55, fbm8(wp * 12.0));
    m.albedo = mix(base, vein, vein_mask);

    // Back-lit SSS: leaf glows warmly when light shines through
    float VdotL = dot(V, -L);
    float sss = saturate(VdotL);
    sss = pow(sss, 3.0);
    float3 sss_tint = float3(0.6, 0.8, 0.2);
    m.emission = sss_tint * sss * 0.8;

    m.roughness = 0.5;
    m.metallic  = 0.0;
    m.normal    = n;
    return m;
}

// ─── 4.3 Silk thread (Marschner-lite fiber BRDF) ─────────────────────────────
// Source: SHADER_CRAFT.md §4.3 (verbatim transcription)
//
// FiberParams is declared in MaterialResult.metal.

/// Silk thread: Marschner-lite R and TT lobe evaluation for spider silk.
///
/// Caller responsibilities:
///   - `L`: world-space light direction (toward light source). Unit vector.
///   - `V`: world-space view direction (toward camera). Unit vector.
///   - FiberParams.fiber_tangent: along-thread direction (world space).
///   - FiberParams.fiber_normal: perpendicular to thread, around which the
///     thread is symmetric.
///   - FiberParams.tint: silk colour tint. float3(1.0) for natural white silk.
///
/// Combines R lobe (specular cone around thread tangent) and TT lobe
/// (back-lit warm scatter). Emission carries the combined fiber BRDF output.
MaterialResult mat_silk_thread(float3 wp, FiberParams p, float3 L, float3 V) {
    MaterialResult m;
    float3 T = p.fiber_tangent;

    // R lobe: specular cone around T with roughness azimuthal_r
    float cos_theta_i = dot(T, L);
    float cos_theta_o = dot(T, V);
    float theta_h = acos(clamp((cos_theta_i + cos_theta_o) * 0.5, -1.0, 1.0));
    float r_lobe = exp(-theta_h * theta_h / (2.0 * p.azimuthal_r * p.azimuthal_r));

    // TT lobe: transmission-transmission, approximated as back-lit rim
    float backlit = saturate(-dot(T, L) * dot(T, V));
    float tt_lobe = pow(backlit, 1.0 / max(0.01, p.azimuthal_tt));

    m.albedo    = p.tint;
    m.roughness = 0.3;
    m.metallic  = 0.0;
    m.normal    = normalize(p.fiber_normal);
    m.emission  = p.tint * (r_lobe * 1.5 + tt_lobe * 0.6);

    return m;
}

// ─── 4.18 Bioluminescent chitin ──────────────────────────────────────────────
// Source: SHADER_CRAFT.md §4.18 (expanded from paragraph form)
// Expanded from SHADER_CRAFT.md §4.18 paragraph form

/// Bioluminescent chitin: near-black carapace with thin-film iridescence and rim glow.
///
/// Perfect for the Arachne spider easter-egg carapace (D-040).
///
/// Caller responsibilities:
///   - `VdotH` ∈ [0, 1]: dot product of view direction and half-vector.
///     Used for Fresnel-dependent thin-film interference.
///   - `NdotV` ∈ [0, 1]: dot product of surface normal and view direction.
///     Used for grazing rim emission.
///   - `thickness_nm`: iridescent film thickness in nanometres (150–400 typical).
///     400 nm = neutral, 200 nm = blue-shift, 300 nm = rainbow peak.
///
/// Thin-film interference from V.1 PBR Thin.metal (thinfilm_rgb).
MaterialResult mat_chitin(float3 wp, float3 n,
                          float VdotH, float NdotV, float thickness_nm)
{
    MaterialResult m;

    // Near-black base (chitin is dark, non-reflective in diffuse)
    m.albedo   = float3(0.02, 0.025, 0.03);
    m.roughness = 0.2;
    m.metallic  = 0.0;

    // Iridescent thin-film specular: wavelength-dependent F0 from surface interference.
    // thinfilm_rgb from V.1 PBR/Thin.metal: returns RGB Fresnel reflectance.
    float ior_thin = 1.55;   // chitin IOR
    float ior_base = 1.0;    // air
    float3 iridescent = thinfilm_rgb(VdotH, thickness_nm, ior_thin, ior_base);

    // Spatial variation: noise-driven thickness perturbation for micro-structure.
    float thickness_var = fbm8(wp * 15.0) * 50.0;
    iridescent = mix(iridescent,
        thinfilm_rgb(VdotH, thickness_nm + thickness_var, ior_thin, ior_base),
        0.4);

    // Rim emission: bioluminescent glow at grazing angles.
    // Inverted NdotV — maximum glow at silhouette edges.
    float rim = pow(1.0 - NdotV, 3.0);
    float3 biolum = float3(0.3, 0.8, 0.4);   // cool green bioluminescence

    m.normal   = n;
    m.emission = iridescent * 0.5 + biolum * rim * 0.6;

    return m;
}

// ─── 4.12 Velvet (retro-reflective fuzz) ─────────────────────────────────────
// Source: SHADER_CRAFT.md §4.12 (Increment V.4)

/// Velvet: Oren-Nayar diffuse base with Fresnel-driven fuzz term.
///
/// Retro-reflective at grazing angles (opposite of normal Fresnel dielectrics).
/// Fuzz term brightens at silhouette edges — characteristic velvet sheen.
///
/// Caller responsibilities:
///   - `velvet_color`: fabric colour. Deep, saturated colors read best.
///   - `NdotV` ∈ [0, 1]: view-incidence cosine.
MaterialResult mat_velvet(float3 wp, float3 n, float3 velvet_color, float NdotV) {
    MaterialResult m;
    m.albedo    = velvet_color;
    m.roughness = 0.90;   // Oren-Nayar-equivalent matte diffuse base
    m.metallic  = 0.0;
    m.normal    = n;

    // Fuzz term: brightens at grazing angles (sigma=0.35 Oren-Nayar approximation).
    // pow(1-NdotV, 2) peaks at silhouette edges, zero at direct view.
    float fuzz = pow(1.0 - NdotV, 2.0);
    m.emission = velvet_color * fuzz * 0.5;

    return m;
}
