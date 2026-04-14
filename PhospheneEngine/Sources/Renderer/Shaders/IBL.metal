// IBL.metal — Image-Based Lighting: texture generation compute kernels + sampling utilities.
//
// Increment 3.16: IBL Pipeline.
//
// Three compute kernels generate IBL textures at startup via IBLManager:
//   ibl_gen_irradiance      — 32² cubemap, .rgba16Float, cosine-weighted hemisphere convolution
//   ibl_gen_prefiltered_env — 128² cubemap, .rgba16Float, 5 mip levels, GGX importance sampling
//   ibl_gen_brdf_lut        — 512², .rg16Float, split-sum BRDF integration (NdotV × roughness)
//
// Three static-inline utility functions are called from raymarch_lighting_fragment
// in RayMarch.metal (same ShaderLibrary compilation unit):
//   ibl_sample_irradiance   — sample irradiance cubemap for diffuse ambient
//   ibl_sample_prefiltered  — sample prefiltered env cubemap with roughness LOD for specular
//   ibl_sample_brdf_lut     — sample split-sum BRDF LUT
//
// Source environment: procedural gradient sky (zenith/horizon/ground gradient matching rm_skyColor).
// All ibl_ helpers are static inline with the ibl_ prefix to avoid symbol collision with
// other files in the same compilation unit (Common.metal, RayMarch.metal, NoiseGen.metal, etc.).
//
// Texture binding layout (set by IBLManager.bindTextures):
//   texture(9)  — irradianceMap   (texturecube, 32² per face, .rgba16Float)
//   texture(10) — prefilteredEnvMap (texturecube, 128² per face, 5 mip levels, .rgba16Float)
//   texture(11) — brdfLUT         (texture2d, 512², .rg16Float)

#include <metal_stdlib>
using namespace metal;

// MARK: - Source Environment

/// Procedural environment radiance for a given world-space direction.
///
/// Configured as a warm concrete-corridor interior — appropriate for enclosed
/// architectural presets (GlassBrutalist).  The blue-sky gradient that was here
/// previously caused all surfaces to appear sky-blue regardless of geometry.
///
/// Three zones by elevation:
///   up > 0.5  — warm overhead zone (corridor ceiling / light source)
///   up ∈ [-0.15, 0.5] — neutral concrete-grey walls
///   up < -0.15 — dark floor zone
///
/// NOTE: This is a global function shared by all ray march presets.  When an
/// outdoor preset is added, per-preset IBL support should be introduced so each
/// preset can declare its own environment type.  For now GlassBrutalist is the
/// only ray march preset, so the interior environment is correct.
static inline float3 ibl_proc_env(float3 dir) {
    float up = dir.y;

    if (up > 0.5f) {
        // Upper zone: warm overhead corridor light bleeding into ceiling.
        float t = (up - 0.5f) / 0.5f;
        float3 ceilAmb   = float3(0.80f, 0.76f, 0.68f);   // warm grey upper wall
        float3 ceilLight = float3(1.20f, 1.10f, 0.90f);   // warm white overhead
        return mix(ceilAmb, ceilLight, t * t);
    } else if (up > -0.15f) {
        // Mid zone: neutral concrete walls (horizontal directions included here,
        // which is what glass panels reflect when facing the camera).
        float t = (up + 0.15f) / 0.65f;                   // 0 at bottom, 1 at top
        float3 wallLow  = float3(0.25f, 0.23f, 0.20f);    // lower wall (darker)
        float3 wallHigh = float3(0.45f, 0.43f, 0.40f);    // upper wall (lighter)
        return mix(wallLow, wallHigh, t);
    } else {
        // Lower zone: dark concrete floor.
        float t = clamp((-0.15f - up) / 0.85f, 0.0f, 1.0f);
        float3 wallLow = float3(0.25f, 0.23f, 0.20f);
        float3 floor_  = float3(0.12f, 0.11f, 0.10f);
        return mix(wallLow, floor_, t * t);
    }
}

// MARK: - Cubemap UV ↔ Direction

/// Convert a cubemap face index (0–5) and UV in [0,1] to a normalised world direction.
/// Face indices follow the Metal/OpenGL convention:
///   0 = +X, 1 = −X, 2 = +Y, 3 = −Y, 4 = +Z, 5 = −Z
static inline float3 ibl_cube_dir(uint face, float2 uv) {
    float s = uv.x * 2.0 - 1.0;    // [-1, 1] horizontal
    float t = uv.y * 2.0 - 1.0;    // [-1, 1] vertical
    switch (face) {
        case 0u: return normalize(float3( 1.0, -t, -s));   // +X
        case 1u: return normalize(float3(-1.0, -t,  s));   // -X
        case 2u: return normalize(float3(   s,  1.0,  t)); // +Y
        case 3u: return normalize(float3(   s, -1.0, -t)); // -Y
        case 4u: return normalize(float3(   s, -t,  1.0)); // +Z
        case 5u: return normalize(float3(  -s, -t, -1.0)); // -Z
        default: return float3(0.0, 1.0, 0.0);
    }
}

// MARK: - Quasi-Random Sampling (Hammersley)

/// Van der Corput radical inverse — reverses the bit pattern of an integer.
static inline float ibl_van_der_corput(uint bits) {
    bits = (bits << 16u) | (bits >> 16u);
    bits = ((bits & 0x55555555u) << 1u) | ((bits & 0xAAAAAAAAu) >> 1u);
    bits = ((bits & 0x33333333u) << 2u) | ((bits & 0xCCCCCCCCu) >> 2u);
    bits = ((bits & 0x0F0F0F0Fu) << 4u) | ((bits & 0xF0F0F0F0u) >> 4u);
    bits = ((bits & 0x00FF00FFu) << 8u) | ((bits & 0xFF00FF00u) >> 8u);
    return float(bits) * 2.3283064365386963e-10;    // / 0x100000000
}

/// 2D Hammersley point set — low-discrepancy quasi-random sequence.
static inline float2 ibl_hammersley(uint i, uint N) {
    return float2(float(i) / float(N), ibl_van_der_corput(i));
}

// MARK: - GGX Importance Sampling

/// Sample a half-vector from the GGX distribution aligned to normal N.
/// Xi is a 2D quasi-random sample; roughness is linear roughness [0,1].
static inline float3 ibl_importance_sample_ggx(float2 Xi, float3 N, float roughness) {
    float a  = roughness * roughness;
    float a2 = a * a;

    float phi      = 2.0 * M_PI_F * Xi.x;
    float cosTheta = sqrt((1.0 - Xi.y) / (1.0 + (a2 - 1.0) * Xi.y + 1e-6));
    float sinTheta = sqrt(max(0.0, 1.0 - cosTheta * cosTheta));

    // Half-vector in tangent space.
    float3 H = float3(cos(phi) * sinTheta, sin(phi) * sinTheta, cosTheta);

    // Tangent frame aligned to N.
    float3 up      = (abs(N.z) < 0.999) ? float3(0.0, 0.0, 1.0) : float3(1.0, 0.0, 0.0);
    float3 tangent = normalize(cross(up, N));
    float3 bitan   = cross(N, tangent);

    return normalize(tangent * H.x + bitan * H.y + N * H.z);
}

// MARK: - IBL Geometry Functions (split-sum / IBL version)

/// Schlick-GGX geometry term for the IBL pre-integration.
/// Uses k = a² / 2 (IBL variant), NOT the direct-light variant k = (a+1)² / 8.
static inline float ibl_geo_schlick_ggx(float NdotX, float roughness) {
    float a = roughness;
    float k = (a * a) * 0.5;
    return NdotX / (NdotX * (1.0 - k) + k + 1e-6);
}

/// Smith combined geometry (V × L) for the BRDF LUT integration.
static inline float ibl_geo_smith(float3 N, float3 V, float3 L, float roughness) {
    float NdotV = max(dot(N, V), 0.0);
    float NdotL = max(dot(N, L), 0.0);
    return ibl_geo_schlick_ggx(NdotV, roughness) * ibl_geo_schlick_ggx(NdotL, roughness);
}

// MARK: - Compute Kernel: Irradiance Cubemap

/// Generate a cosine-weighted irradiance cubemap from the procedural sky environment.
///
/// Each texel stores the hemisphere-integrated radiance for outgoing normal direction N:
///   L_irr(N) = ∫_Ω L(ω_i) * max(cos θ_i, 0) dω_i  (via Monte Carlo, 512 samples)
///
/// - texture(0): write target — texturecube .rgba16Float, 32² per face
/// - buffer(0):  faceSize — face edge length in pixels (32)
kernel void ibl_gen_irradiance(
    texturecube<float, access::write> irr     [[texture(0)]],
    constant uint&                    faceSize [[buffer(0)]],
    uint3                             gid      [[thread_position_in_grid]])
{
    if (gid.x >= faceSize || gid.y >= faceSize || gid.z >= 6u) { return; }

    float2 uv = (float2(gid.xy) + 0.5) / float(faceSize);
    float3 N  = ibl_cube_dir(gid.z, uv);

    // Build a tangent frame for N.
    float3 up  = (abs(N.z) < 0.999) ? float3(0, 0, 1) : float3(1, 0, 0);
    float3 tan = normalize(cross(up, N));
    float3 bit = cross(N, tan);

    // Cosine-weighted hemisphere integration via Hammersley + cosine sampling.
    const uint SAMPLES = 512u;
    float3 irradiance  = float3(0.0);

    for (uint i = 0u; i < SAMPLES; i++) {
        float2 Xi  = ibl_hammersley(i, SAMPLES);
        // Cosine-weighted hemisphere: theta = acos(sqrt(1 - Xi.y))
        float phi      = 2.0 * M_PI_F * Xi.x;
        float cosTheta = sqrt(1.0 - Xi.y);      // PDF = cosTheta / pi
        float sinTheta = sqrt(Xi.y);

        // Light direction in world space.
        float3 L = normalize(tan * (sinTheta * cos(phi))
                           + bit * (sinTheta * sin(phi))
                           + N   *  cosTheta);
        irradiance += ibl_proc_env(L);
    }
    // Monte Carlo estimate: divide by sample count (cosine PDF already folded in).
    irradiance /= float(SAMPLES);

    irr.write(float4(irradiance, 1.0), gid.xy, gid.z);
}

// MARK: - Compute Kernel: Prefiltered Environment Map

/// Generate one mip level of the prefiltered specular environment cubemap.
///
/// Dispatched once per mip level (0..4); roughness and mipLevel are buffer parameters.
/// Uses GGX importance sampling (256 samples) to integrate environment radiance.
///
/// - texture(0): write target — texturecube .rgba16Float, all 5 mip levels allocated
/// - buffer(0):  roughness — linear roughness for this mip: 0, 0.25, 0.5, 0.75, 1.0
/// - buffer(1):  faceSize  — edge length of this mip level (128 >> mipLevel)
/// - buffer(2):  mipLevel  — mip index (0–4)
kernel void ibl_gen_prefiltered_env(
    texturecube<float, access::write> prefEnv   [[texture(0)]],
    constant float&                   roughness  [[buffer(0)]],
    constant uint&                    faceSize   [[buffer(1)]],
    constant uint&                    mipLevel   [[buffer(2)]],
    uint3                             gid        [[thread_position_in_grid]])
{
    if (gid.x >= faceSize || gid.y >= faceSize || gid.z >= 6u) { return; }

    float2 uv = (float2(gid.xy) + 0.5) / float(faceSize);
    float3 R  = ibl_cube_dir(gid.z, uv);
    // Treat reflection direction as both N and V for prefiltering
    // (view-independent assumption, standard Epic split-sum).
    float3 N = R;
    float3 V = R;

    const uint SAMPLES      = 256u;
    float3     prefColor    = float3(0.0);
    float      totalWeight  = 0.0;

    for (uint i = 0u; i < SAMPLES; i++) {
        float2 Xi = ibl_hammersley(i, SAMPLES);
        float3 H  = ibl_importance_sample_ggx(Xi, N, roughness);
        float3 L  = normalize(2.0 * dot(V, H) * H - V);

        float NdotL = max(dot(N, L), 0.0);
        if (NdotL > 0.0) {
            prefColor   += ibl_proc_env(L) * NdotL;
            totalWeight += NdotL;
        }
    }
    prefColor /= max(totalWeight, 1e-6);

    prefEnv.write(float4(prefColor, 1.0), gid.xy, ushort(gid.z), ushort(mipLevel));
}

// MARK: - Compute Kernel: BRDF Integration LUT

/// Generate the split-sum BRDF integration LUT used in the specular IBL term.
///
/// Each texel (NdotV, roughness) stores (scale, bias) such that:
///   ∫ BRDF(V, L) * NdotL * dL ≈ F0 * scale + bias
///
/// Based on Epic Games' split-sum approximation (Karis 2014 "Real Shading in UE4").
///
/// - texture(0): write target — texture2d .rg16Float, 512²
/// - buffer(0):  texSize — edge length in pixels (512)
kernel void ibl_gen_brdf_lut(
    texture2d<float, access::write> lut     [[texture(0)]],
    constant uint&                  texSize [[buffer(0)]],
    uint2                           gid     [[thread_position_in_grid]])
{
    if (gid.x >= texSize || gid.y >= texSize) { return; }

    // X → NdotV in (0, 1]; Y → roughness in (0, 1].
    float NdotV    = (float(gid.x) + 0.5) / float(texSize);
    float roughness = (float(gid.y) + 0.5) / float(texSize);

    // Tangent-space view vector with NdotV as cosine of polar angle.
    float3 V = float3(sqrt(max(0.0, 1.0 - NdotV * NdotV)), 0.0, NdotV);
    float3 N = float3(0.0, 0.0, 1.0);

    const uint SAMPLES = 1024u;
    float scale = 0.0, bias = 0.0;

    for (uint i = 0u; i < SAMPLES; i++) {
        float2 Xi = ibl_hammersley(i, SAMPLES);
        float3 H  = ibl_importance_sample_ggx(Xi, N, roughness);
        float3 L  = normalize(2.0 * dot(V, H) * H - V);

        float NdotL = max(L.z,        0.0);
        float NdotH = max(H.z,        0.0);
        float VdotH = max(dot(V, H),  0.0);

        if (NdotL > 0.0) {
            float G      = ibl_geo_smith(N, V, L, roughness);
            float G_Vis  = (G * VdotH) / max(NdotH * NdotV, 1e-6);
            float Fc     = pow(1.0 - VdotH, 5.0);
            scale += (1.0 - Fc) * G_Vis;
            bias  +=        Fc  * G_Vis;
        }
    }
    scale = clamp(scale / float(SAMPLES), 0.0, 1.0);
    bias  = clamp(bias  / float(SAMPLES), 0.0, 1.0);

    lut.write(float4(scale, bias, 0.0, 1.0), gid);
}

// MARK: - IBL Sampling Utilities (called from raymarch_lighting_fragment)

/// Sample diffuse ambient from the irradiance cubemap for surface normal N.
/// Returns linear-HDR radiance (pre-divided by π, ready for direct multiplication).
static inline float3 ibl_sample_irradiance(
    float3             N,
    texturecube<float> irrMap,
    sampler            s)
{
    return irrMap.sample(s, N).rgb;
}

/// Sample the prefiltered specular environment map for reflection direction R.
/// `roughness` in [0,1] selects the LOD: 0 = sharp (mip 0), 1 = diffuse (mip maxMip).
static inline float3 ibl_sample_prefiltered(
    float3             R,
    float              roughness,
    texturecube<float> prefEnv,
    sampler            s,
    int                maxMip)
{
    float lod = roughness * float(maxMip);
    return prefEnv.sample(s, R, level(lod)).rgb;
}

/// Sample the split-sum BRDF LUT for Schlick-Fresnel split factors (scale, bias).
/// NdotV and roughness both in [0, 1].  Returns float2(scale, bias).
static inline float2 ibl_sample_brdf_lut(
    float           NdotV,
    float           roughness,
    texture2d<float> lut,
    sampler          s)
{
    return lut.sample(s, float2(NdotV, roughness)).rg;
}
