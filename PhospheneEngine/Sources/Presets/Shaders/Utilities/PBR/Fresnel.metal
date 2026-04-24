// Fresnel.metal — Fresnel reflectance utilities.
//
// Provides Schlick approximation, roughness-modified Schlick, exact Fresnel
// for dielectrics, and conductor F0 from IOR + extinction coefficient.
//
// DO NOT add #include <metal_stdlib> or using namespace metal.

// ─── Schlick approximation ────────────────────────────────────────────────────

/// Schlick approximation: F(VdotH) ≈ F0 + (1 - F0) * (1 - VdotH)^5.
/// `VdotH` = dot(view, half-vector), clamped to [0, 1].
/// `F0` = reflectance at normal incidence (0° = full face-on reflection).
static inline float3 fresnel_schlick(float VdotH, float3 F0) {
    float f = pow(clamp(1.0 - VdotH, 0.0, 1.0), 5.0);
    return F0 + (1.0 - F0) * f;
}

/// Roughness-modified Schlick — flattens the Fresnel curve for rough surfaces.
/// Used in image-based lighting to avoid over-bright grazing angles on rough materials.
/// Reference: Epic Games UE4 PBR notes (Karis 2013).
static inline float3 fresnel_schlick_roughness(float VdotH, float3 F0, float roughness) {
    float f = pow(clamp(1.0 - VdotH, 0.0, 1.0), 5.0);
    return F0 + (max(float3(1.0 - roughness), F0) - F0) * f;
}

// ─── Exact Fresnel for dielectrics ───────────────────────────────────────────

/// Exact Fresnel reflectance for a dielectric (non-conducting) surface.
/// `VdotH` = cosine of incidence angle (dot of view and half-vector).
/// `ior` = index of refraction of the transmission medium (e.g. 1.5 for glass).
/// Returns the unpolarised reflectance (average of s and p polarisation).
static inline float fresnel_dielectric(float VdotH, float ior) {
    float cos_i = clamp(VdotH, 0.0, 1.0);
    float sin2_t = (1.0 - cos_i * cos_i) / (ior * ior);

    // Total internal reflection.
    if (sin2_t >= 1.0) return 1.0;

    float cos_t = sqrt(max(0.0, 1.0 - sin2_t));
    float rs = (cos_i - ior * cos_t) / (cos_i + ior * cos_t);
    float rp = (ior * cos_i - cos_t) / (ior * cos_i + cos_t);
    return (rs * rs + rp * rp) * 0.5;
}

// ─── Conductor F0 ─────────────────────────────────────────────────────────────

/// Compute the RGB F0 (normal-incidence reflectance) for a conductor from its
/// complex index of refraction (eta + i*k). Useful for physically-based metals.
/// Reference: "Physically Based Shading in Theory and Practice" (SIGGRAPH 2012).
///
/// Typical values:
///   Gold:   eta ≈ (0.143, 0.374, 1.44),  k ≈ (3.98, 2.38, 1.60)
///   Silver: eta ≈ (0.154, 0.130, 0.172), k ≈ (3.48, 3.23, 2.88)
///   Copper: eta ≈ (0.200, 0.924, 1.10),  k ≈ (3.72, 2.57, 2.36)
static inline float3 fresnel_f0_conductor(float3 eta, float3 k) {
    float3 eta2 = eta * eta;
    float3 k2   = k * k;
    float3 rs   = (eta2 + k2 - 2.0 * eta + 1.0) / (eta2 + k2 + 2.0 * eta + 1.0);
    return clamp(rs, 0.0, 1.0);
}
