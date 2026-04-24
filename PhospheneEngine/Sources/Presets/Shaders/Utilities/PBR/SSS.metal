// SSS.metal — Subsurface scattering approximations.
//
// Provides real-time approximations of subsurface scattering for thin or
// translucent surfaces (skin, wax, leaves, silk, candles).
// Not full physical SSS — these are view-space approximations suitable for
// real-time rendering at 60fps.
//
// DO NOT add #include <metal_stdlib> or using namespace metal.

// ─── Back-lit SSS ─────────────────────────────────────────────────────────────

/// Back-lit subsurface scattering approximation.
/// Returns the fraction of incident light transmitted through thin geometry.
///
/// `N`          — surface normal (world space, pointing away from surface).
/// `L`          — light direction (world space, pointing toward the light).
/// `V`          — view direction (world space, pointing toward the camera).
/// `thickness`  — normalized surface thickness [0, 1]. 0 = infinitely thin
///                (maximum transmission); 1 = opaque (no transmission).
/// `distortion` — controls how much the transmission lobe spreads toward the
///                normal. 0 = pure backlit; 0.5 = broad scatter. Default 0.2.
///
/// Reference: "GPU Gems 3, Chapter 16: Real-Time Approximations to SSS" (d'Eon 2007).
static inline float sss_backlit(
    float3 N, float3 L, float3 V,
    float thickness,
    float distortion
) {
    // Translate light direction through the surface by bending it toward the normal.
    float3 L_bent = L + N * distortion;
    // Transmission: how much the bent light aligns with the view direction.
    float VdotL = pow(clamp(dot(V, -L_bent), 0.0, 1.0), 12.0);
    // Attenuate by thickness: thick regions transmit less.
    float attenuation = 1.0 - thickness;
    return VdotL * attenuation;
}

// ─── Wrap lighting (cheap diffuse SSS) ───────────────────────────────────────

/// Pre-integrated wrap-lighting approximation for diffuse SSS.
/// Wraps the diffuse lobe past the terminator to simulate sub-surface glow on
/// rounded surfaces (skin, fruit, candle wax).
///
/// `N`           — surface normal.
/// `L`           — light direction.
/// `wrap`        — how far past the terminator to extend the lobe [0, 1].
///                 0 = standard Lambert, 0.5 = typical skin, 1 = full hemisphere.
/// `scatter_tint` — RGB tint for scattered light (skin: warm peach, wax: amber).
///
/// Returns the wrapped diffuse contribution, pre-multiplied by scatter_tint.
static inline float3 sss_wrap_lighting(float3 N, float3 L, float wrap, float3 scatter_tint) {
    float NdotL = dot(N, L);
    // Shifted and re-normalized Lambert kernel.
    float wrapped = (NdotL + wrap) / ((1.0 + wrap) * (1.0 + wrap));
    float diffuse = saturate(wrapped);
    return scatter_tint * diffuse;
}
