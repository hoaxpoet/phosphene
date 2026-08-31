// Thin.metal — Thin-film interference for iridescent surfaces.
//
// Thin-film interference produces wavelength-dependent reflectance — the
// iridescent shimmer of soap bubbles, oil slicks, beetle carapaces, and
// spider silk. The color shifts with viewing angle (VdotH).
//
// Two levels of fidelity:
//   thinfilm_rgb     — wavelength-sampled RGB approximation (moderate cost).
//   thinfilm_hue_rotate — cheap hue-rotation approximation (near-free).
//
// Depends on: Fresnel.metal (fresnel_dielectric)
//
// Reference: Belcour & Barla 2017 "A Practical Extension to Microfacet Theory
//            for the Modeling of Varying Iridescence" (simplified RGB version).
//
// DO NOT add #include <metal_stdlib> or using namespace metal.

// ─── RGB wavelength-sampled approximation ────────────────────────────────────

/// Thin-film reflectance as a wavelength-dependent RGB approximation.
///
/// `VdotH`       = dot(view, half-vector), in [0, 1].
/// `thickness_nm`= film thickness in nanometres (80–200 nm is the visible range
///                 where interference colors cycle). 0 = no film.
/// `ior_thin`    = IOR of the thin film (soap: 1.33, oil: 1.47, gold: varies).
/// `ior_base`    = IOR of the substrate below the film (glass: 1.52).
///
/// Returns: RGB thin-film reflectance to use as F0 for the top interface.
/// Typical usage: replace brdf_ggx's F0 argument with thinfilm_rgb(...).
static inline float3 thinfilm_rgb(float VdotH, float thickness_nm, float ior_thin, float ior_base) {
    if (thickness_nm < 0.5) {
        // No film — return standard dielectric F0.
        float F0 = fresnel_dielectric(1.0, ior_base);
        return float3(F0);
    }

    // Refracted angle inside the thin film.
    float cos_i = clamp(VdotH, 0.0, 1.0);
    float sin2_t = (1.0 - cos_i * cos_i) / (ior_thin * ior_thin);
    float cos_t  = sqrt(max(0.0, 1.0 - sin2_t));

    // Optical path difference for each RGB wavelength (nm).
    const float3 lambda = float3(680.0, 550.0, 450.0);   // R G B peak wavelengths
    float OPD = 2.0 * ior_thin * thickness_nm * cos_t;   // optical path difference

    // Phase difference per wavelength.
    float3 phase = (2.0 * M_PI_F * OPD) / lambda;

    // Interference factor (power of the superposed reflections).
    float F_in  = fresnel_dielectric(cos_i, ior_thin);
    float F_out = fresnel_dielectric(cos_t, ior_base);

    // Two-beam interference: R = |r01 + r12 * exp(i*delta)|^2
    // Approximated as F01 + F12 + 2*sqrt(F01*F12)*cos(phase).
    float F12   = F_out;
    float3 F01  = float3(F_in);
    float3 interference = F01 + F12 + 2.0 * sqrt(F_in * F12) * cos(phase);
    return clamp(interference * 0.5, 0.0, 1.0);
}

// ─── Cheap hue-rotation approximation ────────────────────────────────────────

/// Simple iridescence via hue rotation driven by view angle and film thickness.
/// Much cheaper than thinfilm_rgb — suitable for real-time use inside inner loops.
///
/// `base_f0`     = base reflectance color (used when no interference).
/// `thickness_nm`= nominal film thickness in nm. Controls which hue is rotated to.
/// `VdotH`       = dot(view, half-vector) — drives the per-angle shift.
///
/// Returns: RGB reflectance with hue-rotated iridescent shimmer.
static inline float3 thinfilm_hue_rotate(float3 base_f0, float thickness_nm, float VdotH) {
    if (thickness_nm < 0.5) return base_f0;

    // Map angle + thickness to a hue offset (cycles through the visible spectrum).
    float t = (1.0 - VdotH) * 0.6 + thickness_nm * (1.0 / 500.0);
    float hue_offset = fract(t);

    // Shift hue using HSV-inspired rotation on the base color.
    // We add an iridescent term proportional to the hue offset.
    float3 iridescent = float3(
        cos(hue_offset * 6.28318 + 0.0),
        cos(hue_offset * 6.28318 + 2.094),
        cos(hue_offset * 6.28318 + 4.189)
    ) * 0.5 + 0.5;

    // Blend iridescent tint into the base F0.
    float blend = smoothstep(0.0, 0.3, thickness_nm / 300.0);
    return mix(base_f0, iridescent * length(base_f0), blend * 0.7);
}
