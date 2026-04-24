// BRDF.metal — Bidirectional Reflectance Distribution Functions.
//
// Provides the full family of PBR lighting primitives: GGX specular,
// Lambert diffuse, Oren-Nayar rough diffuse, and Ashikhmin-Shirley
// anisotropic Phong. A convenience Cook-Torrance function composes them
// for the common metallic-roughness workflow.
//
// These are BRDF primitives only. Material composition (mat_silk_thread,
// mat_polished_chrome, etc.) lives in the V.3 Materials cookbook.
//
// Depends on: Fresnel.metal (fresnel_schlick, fresnel_schlick_roughness)
//
// References:
//   GGX NDF:     Walter et al. 2007 "Microfacet Models for Refraction"
//   Smith G:     Heitz 2014 "Understanding the Masking-Shadowing Function"
//   Oren-Nayar:  Oren & Nayar 1994 (qualitative approximation)
//   Ashikhmin-Shirley: Ashikhmin & Shirley 2000 "An Anisotropic Phong BRDF"
//
// DO NOT add #include <metal_stdlib> or using namespace metal.

// ─── GGX Normal Distribution Function ────────────────────────────────────────

/// GGX/Trowbridge-Reitz Normal Distribution Function.
/// Returns the fraction of microfacets oriented exactly at the half-vector H.
/// `NdotH` = dot(normal, half-vector), in [0, 1].
/// `roughness` = perceptual roughness in [0, 1].
static inline float ggx_d(float NdotH, float roughness) {
    float a  = roughness * roughness;    // remap to alpha
    float a2 = a * a;
    float d  = NdotH * NdotH * (a2 - 1.0) + 1.0;
    return a2 / max(M_PI_F * d * d, 1e-7);
}

// ─── GGX Geometric Shadowing ──────────────────────────────────────────────────

/// Smith's single-lobe Schlick-GGX geometric shadowing function.
/// Used by both view and light directions; call twice and multiply for G.
/// `NdotV` = dot(normal, view or light direction), in [0, 1].
static inline float ggx_g_schlick(float NdotV, float roughness) {
    float k = (roughness + 1.0);
    k = (k * k) / 8.0;   // Disney remapping
    return NdotV / max(NdotV * (1.0 - k) + k, 1e-7);
}

/// Smith combined G term for both view and light directions.
/// `NdotL` = dot(normal, light), `NdotV` = dot(normal, view).
static inline float ggx_g_smith(float NdotL, float NdotV, float roughness) {
    return ggx_g_schlick(max(NdotL, 0.0), roughness)
         * ggx_g_schlick(max(NdotV, 0.0), roughness);
}

// ─── Full GGX Specular BRDF ───────────────────────────────────────────────────

/// Full GGX specular BRDF (NDF × G × F / (4 NdotL NdotV)).
/// Returns specular radiance for one light. Does NOT include the NdotL Lambert term —
/// multiply by NdotL at the call site.
static inline float3 brdf_ggx(float3 N, float3 V, float3 L, float3 F0, float roughness) {
    float3 H     = normalize(V + L);
    float NdotL  = max(dot(N, L), 0.0);
    float NdotV  = max(dot(N, V), 0.0);
    float NdotH  = max(dot(N, H), 0.0);
    float VdotH  = max(dot(V, H), 0.0);

    float  D = ggx_d(NdotH, roughness);
    float  G = ggx_g_smith(NdotL, NdotV, roughness);
    float3 F = fresnel_schlick(VdotH, F0);

    float3 num  = D * G * F;
    float  denom = max(4.0 * NdotL * NdotV, 1e-7);
    return num / denom;
}

// ─── Diffuse BRDFs ────────────────────────────────────────────────────────────

/// Lambert diffuse BRDF (energy-conserving constant).
/// Returns albedo / π — multiply by NdotL and light radiance at the call site.
static inline float3 brdf_lambert(float3 albedo) {
    return albedo / M_PI_F;
}

/// Oren-Nayar rough diffuse BRDF (qualitative approximation).
/// Improves on Lambert for matte surfaces (clay, chalk, concrete).
/// `sigma` = roughness in radians [0, π/2]. 0 = Lambert. π/2 = very rough.
static inline float3 brdf_oren_nayar(float3 N, float3 V, float3 L, float3 albedo, float sigma) {
    float NdotL = max(dot(N, L), 0.0);
    float NdotV = max(dot(N, V), 0.0);

    float sigma2 = sigma * sigma;
    float A = 1.0 - (sigma2 / (2.0 * (sigma2 + 0.33)));
    float B = 0.45 * sigma2 / (sigma2 + 0.09);

    float theta_i = acos(clamp(NdotL, 0.0, 1.0));
    float theta_o = acos(clamp(NdotV, 0.0, 1.0));

    // Azimuthal angle between L and V projected onto surface.
    float3 VprojN  = normalize(V - N * NdotV);
    float3 LprojN  = normalize(L - N * NdotL);
    float cos_phi  = max(dot(VprojN, LprojN), 0.0);

    float alpha = max(theta_i, theta_o);
    float beta  = min(theta_i, theta_o);

    float f = A + B * cos_phi * sin(alpha) * tan(beta);
    return albedo * f / M_PI_F;
}

// ─── Ashikhmin-Shirley Anisotropic BRDF ──────────────────────────────────────

/// Ashikhmin-Shirley anisotropic Phong BRDF.
/// Provides independent roughness along tangent (T) and bitangent (B) axes.
/// `T`, `B` = tangent and bitangent in world space.
/// `Rd` = diffuse albedo, `Rs` = specular albedo (often float3(0.04)).
/// `nu`, `nv` = anisotropic specular exponents (larger = tighter highlight).
///              nu = 8, nv = 1000 → metallic brushed surface along T.
static inline float3 brdf_ashikhmin_shirley(
    float3 N,  float3 V,  float3 L,
    float3 T,  float3 B,
    float3 Rd, float3 Rs,
    float  nu, float  nv
) {
    float3 H     = normalize(V + L);
    float NdotL  = max(dot(N, L), 0.0);
    float NdotV  = max(dot(N, V), 0.0);
    float NdotH  = max(dot(N, H), 0.0);
    float HdotL  = max(dot(H, L), 0.0);
    float HdotT  = dot(H, T);
    float HdotB  = dot(H, B);

    // Anisotropic power term: (nu*(H·T)^2 + nv*(H·B)^2) / (1 - (H·N)^2)
    float denom_exp = max(1.0 - NdotH * NdotH, 1e-6);
    float exponent  = (nu * HdotT * HdotT + nv * HdotB * HdotB) / denom_exp;
    float power     = pow(NdotH, exponent);

    // Normalization constant.
    float norm_spec = sqrt((nu + 1.0) * (nv + 1.0)) / (8.0 * M_PI_F);

    // Specular term.
    float  F_schlick = pow(1.0 - HdotL, 5.0);
    float3 F  = Rs + (float3(1.0) - Rs) * F_schlick;
    float3 spec = F * norm_spec * power / max(HdotL * max(NdotL, NdotV), 1e-7);

    // Diffuse term (energy-conserving, reduces with specular).
    float3 diff = (28.0 / (23.0 * M_PI_F)) * Rd * (float3(1.0) - Rs)
                * (1.0 - pow(1.0 - 0.5 * NdotL, 5.0))
                * (1.0 - pow(1.0 - 0.5 * NdotV, 5.0));

    return (diff + spec) * NdotL;
}

// ─── Cook-Torrance convenience ────────────────────────────────────────────────

/// Combined Cook-Torrance BRDF for the metallic-roughness workflow.
/// Returns (diffuse + specular) × NdotL — ready to multiply by light radiance.
/// This is the same math as RayMarch.metal's lighting pass but exposed for
/// presets that want PBR in a direct fragment shader (V.7+).
static inline float3 brdf_cook_torrance(
    float3 N, float3 V, float3 L,
    float3 albedo, float roughness, float metallic, float3 F0
) {
    float3 H    = normalize(V + L);
    float NdotL = max(dot(N, L), 0.0);
    float NdotV = max(dot(N, V), 0.0);
    float NdotH = max(dot(N, H), 0.0);
    float VdotH = max(dot(V, H), 0.0);

    float3 F = fresnel_schlick(VdotH, F0);
    float  D = ggx_d(NdotH, roughness);
    float  G = ggx_g_smith(NdotL, NdotV, roughness);

    float3 specular = (D * G * F) / max(4.0 * NdotL * NdotV, 1e-7);

    float3 kD = (1.0 - F) * (1.0 - metallic);
    return (kD * albedo / M_PI_F + specular) * NdotL;
}
