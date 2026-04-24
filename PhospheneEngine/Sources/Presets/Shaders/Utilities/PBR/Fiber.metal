// Fiber.metal — Marschner-lite fiber BRDF primitives.
//
// Provides R (reflection) and TT (transmission-transmission) lobe primitives
// for hair and silk rendering, plus an approximated TRT (transmission-reflection-
// transmission) rim highlight.
//
// These are BRDF primitives only. The full silk material (combining fiber BRDF
// with albedo, absorption, and geometry) is in the V.3 Materials cookbook as
// mat_silk_thread — see SHADER_CRAFT.md §4.3.
//
// Reference: Marschner et al. 2003 "Light Scattering from Human Hair Fibers",
//            SHADER_CRAFT.md §4.3.
//
// DO NOT add #include <metal_stdlib> or using namespace metal.

/// Result from the Marschner-lite BRDF evaluation.
struct FiberBRDFResult {
    float r_lobe;   ///< R lobe: specular reflection off the cuticle surface.
    float tt_lobe;  ///< TT lobe: transmission-transmission (back-lit scatter).
};

// ─── Marschner-lite fiber BRDF ────────────────────────────────────────────────

/// Marschner-lite R and TT lobe evaluation for silk/hair fibers.
///
/// `T`            = fiber tangent direction (world space, along fiber axis).
/// `L`            = light direction (world space, toward light).
/// `V`            = view direction (world space, toward camera).
/// `azimuthal_r`  = R lobe width (cuticle longitudinal roughness, e.g. 0.15).
///                  Smaller = sharper highlight. Typical silk: 0.10–0.25.
/// `azimuthal_tt` = TT lobe exponent (e.g. 0.5). Larger = tighter backlit rim.
///
/// Returns FiberBRDFResult with r_lobe and tt_lobe in [0, 1].
/// Combine with tint and emission in the material: emission = tint * (r * 1.5 + tt * 0.6).
static inline FiberBRDFResult fiber_marschner_lite(
    float3 T, float3 L, float3 V,
    float azimuthal_r,
    float azimuthal_tt
) {
    FiberBRDFResult res;

    // Longitudinal angles from the fiber axis.
    float cos_theta_i = dot(T, L);
    float cos_theta_o = dot(T, V);

    // R lobe: specular cone around T.
    // Half-angle in the longitudinal plane — maximum when L and V are symmetric
    // about a plane perpendicular to T.
    float theta_h = acos(clamp((cos_theta_i + cos_theta_o) * 0.5, -1.0, 1.0));
    float sig = max(azimuthal_r * azimuthal_r, 1e-4);
    res.r_lobe = exp(-theta_h * theta_h / (2.0 * sig));

    // TT lobe: transmission-transmission (back-scatter, brightest when L and V
    // are on opposite sides of the fiber — hence the sign inversion).
    float backlit = saturate(-cos_theta_i * cos_theta_o);
    res.tt_lobe = pow(backlit, max(1.0 / max(azimuthal_tt, 0.01), 1.0));

    return res;
}

// ─── TRT secondary rim ────────────────────────────────────────────────────────

/// Approximated TRT (transmission-reflection-transmission) lobe.
/// Appears as a secondary specular rim on the far side of the fiber from the
/// main R highlight. Much weaker than R — scale by ~0.2 at most.
///
/// `T`            = fiber tangent.
/// `L`, `V`       = light and view directions.
/// `azimuthal_trt`= TRT lobe width (0.2–0.5 typical).
static inline float fiber_trt_lobe(
    float3 T, float3 L, float3 V,
    float azimuthal_trt
) {
    // TRT peaks when L and V are on the same side but near backlit configuration.
    float cos_theta_i = dot(T, L);
    float cos_theta_o = dot(T, V);
    float theta_h = acos(clamp((cos_theta_i + cos_theta_o) * 0.5, -1.0, 1.0));
    // Offset peak to ~π/2 to place it on the far-side rim.
    float offset_theta = theta_h - 0.5 * M_PI_F;
    float sig = max(azimuthal_trt * azimuthal_trt, 1e-4);
    return exp(-offset_theta * offset_theta / (2.0 * sig));
}
