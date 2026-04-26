// Dielectrics.metal — Dielectric (non-metallic) surface material recipes.
//
// Recipes: mat_ceramic, mat_frosted_glass, mat_wet_stone.
//
// All recipes follow the cookbook convention: return MaterialResult.
// See MaterialResult.metal for the composition pattern.
//
// Reference: SHADER_CRAFT.md §4.4, §4.5, §4.13
//
// Depends on: Noise tree (fbm8), Materials/MaterialResult (triplanar_normal).
//
// DO NOT add #include <metal_stdlib> or using namespace metal.

// ─── 4.4 Wet stone ───────────────────────────────────────────────────────────
// Source: SHADER_CRAFT.md §4.4 (verbatim transcription)

/// Wet stone: darkened surface with clear-coat highlight.
///
/// Caller responsibilities:
///   - `wetness` ∈ [0, 1]: 0 = bone-dry, 1 = fully saturated.
///     Route from weather state or audio (bass_energy_dev for rain impact).
static MaterialResult mat_wet_stone(float3 wp, float3 n, float wetness) {
    MaterialResult m;
    float3 dry_albedo = float3(0.35, 0.32, 0.30);
    float3 wet_albedo = dry_albedo * 0.55;      // wet darkens albedo
    m.albedo = mix(dry_albedo, wet_albedo, wetness);

    // Wet surface: smooth (low roughness) but still dielectric
    m.roughness = mix(0.85, 0.15, wetness);
    m.metallic = 0.0;

    // Detail normal from triplanar fBM for stone surface.
    // Uses the 3-param procedural overload from MaterialResult.metal.
    m.normal = triplanar_normal(wp * 3.0, n, 0.08);

    // Clear-coat highlight layer: add glossy specular on top of rough base
    // (handled in PBR composite by boosting specular contribution when wetness > 0.3)
    m.emission = float3(0.0);
    return m;
}

// ─── 4.5 Frosted glass ───────────────────────────────────────────────────────
// Source: SHADER_CRAFT.md §4.5 (verbatim transcription)

/// Frosted glass: translucent diffuser with frost-pattern normal perturbation.
///
/// Caller responsibilities: none. Faint internal scattering is approximated as
/// emissive SSS — not a true transmission model. For full refraction, use a
/// separate transmission pass at the preset level.
MaterialResult mat_frosted_glass(float3 wp, float3 n) {
    MaterialResult m;
    // High albedo (near white) for diffuse scattering
    m.albedo = float3(0.85, 0.88, 0.90);
    // Moderate roughness — not quite matte, not quite clear
    m.roughness = 0.45;
    m.metallic = 0.0;

    // Frost variation: surface-scale noise perturbs normal
    float3 frost = float3(
        fbm8(wp * 25.0),
        fbm8(wp * 25.0 + float3(13.1, 0.0, 0.0)),
        fbm8(wp * 25.0 + float3(0.0, 17.3, 0.0))
    );
    m.normal = normalize(n + (frost - 0.5) * 0.15);

    // Faint internal scattering — emissive approximation for SSS
    float sss_factor = 0.15;
    m.emission = m.albedo * sss_factor;

    return m;
}

// ─── 4.13 Ceramic (clear-coat) ───────────────────────────────────────────────
// Source: SHADER_CRAFT.md §4.13 (expanded from paragraph form)
// Expanded from SHADER_CRAFT.md §4.13 paragraph form

/// Ceramic with clear-coat: saturated diffuse base with a glossy secondary lobe.
///
/// Caller responsibilities:
///   - `base_color`: the saturated clay/glaze colour. Full authorial control.
///   - The clear-coat second specular lobe (roughness_coat = 0.05, F0 = 0.04)
///     is not modelled by MaterialResult's single roughness field. To achieve
///     the double-lobe in the PBR composite, split the surface into two
///     MaterialResult outputs and composite manually, or use SHADER_CRAFT §5
///     lighting recipes.
///
/// This function models the diffuse layer only; roughness represents the base
/// glaze scatter. Add a clear-coat term in the lighting stage.
MaterialResult mat_ceramic(float3 wp, float3 n, float3 base_color) {
    MaterialResult m;
    m.albedo   = base_color;
    m.roughness = 0.6;   // base glaze scatter (not the clear-coat)
    m.metallic  = 0.0;

    // Subtle surface variation to avoid "3D-print" flatness.
    float variation = fbm8(wp * 8.0) * 0.04;
    m.roughness += variation;
    m.roughness = clamp(m.roughness, 0.0, 1.0);

    m.normal   = n;
    m.emission = float3(0.0);
    return m;
}
