// RayMarch.metal — Lighting and composite passes for the deferred ray march pipeline.
//
// Increment 3.14: Multi-Pass Ray March Pipeline.
//
// This file contains the FIXED render passes that do NOT require the preset's
// scene SDF function:
//
//   raymarch_lighting_fragment   — reads G-buffer, evaluates Cook-Torrance PBR,
//                                  screen-space soft shadows, ambient occlusion.
//                                  Renders into a .rgba16Float lit scene texture.
//
//   raymarch_composite_fragment  — reads the lit .rgba16Float texture, applies ACES
//                                  filmic tone mapping, outputs to drawable format.
//
// The G-buffer pass (raymarch_gbuffer_fragment) is compiled per-preset in the
// preamble (PresetLoader+Preamble.swift) because it calls preset-defined sceneSDF()
// and sceneMaterial() functions.
//
// G-buffer layout (set by the G-buffer pass, read by the lighting pass):
//   texture(0)  .rg16Float      R = depth_normalized [0..1), 1.0 = sky/miss; G = unused
//   texture(1)  .rgba8Snorm     RGB = world-space normal [-1..1]; A = ambient occlusion [0..1]
//   texture(2)  .rgba8Unorm     RGB = albedo [0..1]; A = packed roughness (upper 4b) + metallic (lower 4b)
//
// SceneUniforms is defined in Common.metal (compiled in the same Renderer library).

#include <metal_stdlib>
using namespace metal;

// MARK: - Helpers

/// Reconstruct perspective ray direction for the given screen UV.
/// UV (0,0) = top-left; UV (1,1) = bottom-right.
/// Matches the fullscreen_vertex flip: uv.y = 1 - original_y, so uv.y increases downward.
static float3 rm_rayDir(float2 uv, constant SceneUniforms& s) {
    float2 ndc  = uv * 2.0 - 1.0;
    float  yFov = tan(s.cameraOriginAndFov.w * 0.5);
    float  xFov = yFov * s.sceneParamsA.y;  // * aspectRatio
    // Negate ndc.y: uv.y = 0 is top of screen; positive y_world = up.
    return normalize(s.cameraForward.xyz
                     + ndc.x * xFov * s.cameraRight.xyz
                     - ndc.y * yFov * s.cameraUp.xyz);
}

/// Unpack roughness and metallic from the single-byte G-buffer value.
/// Packing: byte = (int(roughness*15) << 4) | int(metallic*15), normalized to [0..1].
static void rm_unpackMaterial(float packed, thread float& roughness, thread float& metallic) {
    int byte   = int(packed * 255.0 + 0.5);
    roughness  = float(byte >> 4)       / 15.0;
    metallic   = float(byte  & 0xF)     / 15.0;
}

/// GGX normal distribution function.
static float rm_ggxD(float NdotH, float roughness) {
    float a  = roughness * roughness;
    float a2 = a * a;
    float d  = NdotH * NdotH * (a2 - 1.0) + 1.0;
    return a2 / (M_PI_F * d * d + 1e-6);
}

/// Smith geometry term (Schlick-GGX).
static float rm_smith(float NdotV, float NdotL, float roughness) {
    float r  = (roughness + 1.0);
    float k  = (r * r) / 8.0;
    float gv = NdotV / (NdotV * (1.0 - k) + k + 1e-6);
    float gl = NdotL / (NdotL * (1.0 - k) + k + 1e-6);
    return gv * gl;
}

/// Fresnel-Schlick approximation.
static float3 rm_fresnel(float cosTheta, float3 F0) {
    return F0 + (1.0 - F0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
}

/// Cook-Torrance BRDF contribution for one light.
static float3 rm_brdf(float3 N, float3 V, float3 L,
                       float3 albedo, float roughness, float metallic) {
    float3 H      = normalize(V + L);
    float  NdotV  = max(dot(N, V), 0.0);
    float  NdotL  = max(dot(N, L), 0.0);
    float  NdotH  = max(dot(N, H), 0.0);
    float  VdotH  = max(dot(V, H), 0.0);

    float3 F0     = mix(float3(0.04), albedo, metallic);
    float3 F      = rm_fresnel(VdotH, F0);
    float  D      = rm_ggxD(NdotH, roughness);
    float  G      = rm_smith(NdotV, NdotL, roughness);

    float3 specular = (D * G * F) / max(4.0 * NdotV * NdotL, 1e-6);
    float3 kd       = (1.0 - F) * (1.0 - metallic);
    float3 diffuse  = kd * albedo / M_PI_F;

    return (diffuse + specular) * NdotL;
}

/// Procedural sky gradient for miss pixels and environment reflections.
static float3 rm_skyColor(float3 rayDir) {
    float t       = 0.5 * (rayDir.y + 1.0);
    float3 horizon = float3(0.85, 0.90, 1.0);
    float3 zenith  = float3(0.10, 0.30, 0.8);
    return mix(horizon, zenith, t);
}

/// Screen-space soft shadow: march from surface toward the light along the G-buffer.
/// Returns a shadow factor in [0,1] where 0 = fully shadowed, 1 = fully lit.
static float rm_screenSpaceShadow(
    float2 fragUV,
    float3 worldPos,
    float3 lightDir,
    float  lightDist,
    texture2d<float> gbuf0,
    sampler samp,
    constant SceneUniforms& s
) {
    const int   kSteps    = 12;
    const float kBias     = 0.04;   // surface bias to avoid self-shadowing
    const float kPenumbra = 0.08;   // softness of shadow edge

    float farPlane    = s.sceneParamsA.w;
    float aspectRatio = s.sceneParamsA.y;
    float yFov        = tan(s.cameraOriginAndFov.w * 0.5);
    float xFov        = yFov * aspectRatio;

    float3 camPos    = s.cameraOriginAndFov.xyz;
    float3 camFwd    = s.cameraForward.xyz;
    float3 camRight  = s.cameraRight.xyz;
    float3 camUp     = s.cameraUp.xyz;

    float  stepSize  = lightDist / float(kSteps + 1);
    float  shadow    = 1.0;

    for (int i = 1; i <= kSteps; i++) {
        float3 samplePos = worldPos + lightDir * (float(i) * stepSize) + lightDir * kBias;

        // Project samplePos to screen UV.
        float3 toSample  = samplePos - camPos;
        float  sDepth    = dot(toSample, camFwd);
        if (sDepth <= 0.0) continue;

        float  sU = dot(toSample, camRight) / (sDepth * xFov);
        float  sV = dot(toSample, camUp)    / (sDepth * yFov);
        float2 sUV = float2(sU * 0.5 + 0.5, 0.5 - sV * 0.5);

        // Skip samples outside the screen.
        if (sUV.x < 0.0 || sUV.x > 1.0 || sUV.y < 0.0 || sUV.y > 1.0) continue;

        float sampledDepth = gbuf0.sample(samp, sUV).r;
        if (sampledDepth >= 0.999) continue;  // sky — no occlusion

        float sampledT   = sampledDepth * farPlane;
        float expectedT  = sDepth;

        // If G-buffer records a surface closer than our shadow ray sample,
        // something is blocking the path to the light → shadow.
        if (sampledT < expectedT - 0.1) {
            float penumbra = clamp((expectedT - sampledT) / kPenumbra, 0.0, 1.0);
            shadow = min(shadow, 1.0 - penumbra);
        }
    }
    return clamp(shadow, 0.0, 1.0);
}

// MARK: - Lighting Pass

/// Deferred PBR lighting pass for ray march presets.
///
/// Reads the three G-buffer textures written by `raymarch_gbuffer_fragment`,
/// evaluates Cook-Torrance BRDF with the scene's primary light, applies
/// screen-space soft shadows and ambient occlusion, samples IBL textures for
/// physically accurate environment ambient and specular reflections, and writes
/// a linear-HDR colour to the .rgba16Float lit scene texture.
///
/// IBL textures (Increment 3.16):
///   texture(9)  — irradiance cubemap       → diffuse ambient (ibl_sample_irradiance)
///   texture(10) — prefiltered env cubemap  → specular reflections (ibl_sample_prefiltered)
///   texture(11) — BRDF split-sum LUT       → Fresnel split factors (ibl_sample_brdf_lut)
/// When IBL textures are not yet bound, they return zero; the per-component max
/// against `albedo * 0.04 * ao` prevents fully black surfaces during warmup.
fragment float4 raymarch_lighting_fragment(
    VertexOut                   in        [[stage_in]],
    constant FeatureVector&     features  [[buffer(0)]],
    constant SceneUniforms&     scene     [[buffer(4)]],
    texture2d<float>            gbuf0     [[texture(0)]],   // rg16Float: depth, unused
    texture2d<float>            gbuf1     [[texture(1)]],   // rgba8Snorm: normal xyz, AO
    texture2d<float>            gbuf2     [[texture(2)]],   // rgba8Unorm: albedo, packed material
    texture2d<float>            noiseLQ        [[texture(4)]],
    texture2d<float>            noiseHQ        [[texture(5)]],
    texture3d<float>            noiseVol       [[texture(6)]],
    texture2d<float>            noiseFBM       [[texture(7)]],
    texture2d<float>            blueNoise      [[texture(8)]],
    texturecube<float>          iblIrradiance  [[texture(9)]],
    texturecube<float>          iblPrefiltered [[texture(10)]],
    texture2d<float>            iblBRDFLUT     [[texture(11)]]
) {
    constexpr sampler samp(filter::linear, address::clamp_to_edge);
    // IBL sampler: trilinear filtering for mip LOD-based roughness lookup.
    constexpr sampler iblSamp(filter::linear, mip_filter::linear, address::clamp_to_edge);
    float2 uv = in.uv;

    // ── Sample G-buffer ────────────────────────────────────────────
    float4 g0 = gbuf0.sample(samp, uv);
    float4 g1 = gbuf1.sample(samp, uv);
    float4 g2 = gbuf2.sample(samp, uv);

    float depthNorm = g0.r;

    // Miss / sky pixel: depth == 1.0.
    if (depthNorm >= 0.999) {
        float3 rd = rm_rayDir(uv, scene);
        return float4(rm_skyColor(rd), 1.0);
    }

    // ── Reconstruct surface data ───────────────────────────────────
    float  farPlane = scene.sceneParamsA.w;
    float3 rayDir   = rm_rayDir(uv, scene);
    float3 worldPos = scene.cameraOriginAndFov.xyz + rayDir * (depthNorm * farPlane);

    // Normal is stored as-is in rgba8Snorm (values directly in [-1, 1]).
    float3 N  = normalize(g1.xyz);
    float  ao = g1.w;                       // ambient occlusion [0, 1]

    float3 albedo    = g2.rgb;
    float  roughness, metallic;
    rm_unpackMaterial(g2.a, roughness, metallic);

    // ── Lighting ───────────────────────────────────────────────────
    float3 V         = normalize(scene.cameraOriginAndFov.xyz - worldPos);
    float3 lightPos  = scene.lightPositionAndIntensity.xyz;
    float  intensity = scene.lightPositionAndIntensity.w;
    float3 lColor    = scene.lightColor.xyz;

    float3 L         = lightPos - worldPos;
    float  lightDist = length(L);
    L                = normalize(L);

    float3 litColor  = rm_brdf(N, V, L, albedo, roughness, metallic) * lColor * intensity;

    // ── Screen-space soft shadow ───────────────────────────────────
    float shadow = rm_screenSpaceShadow(uv, worldPos, L, lightDist, gbuf0, samp, scene);
    litColor *= shadow;

    // ── IBL ambient (diffuse + specular) ─────────────────────────
    // Diffuse: cosine-weighted irradiance from environment.
    // Specular: prefiltered env + split-sum BRDF LUT (Epic split-sum).
    float  NdotV   = max(dot(N, V), 0.0);
    float3 R       = reflect(-V, N);
    float3 F0      = mix(float3(0.04), albedo, metallic);
    float3 F_ibl   = rm_fresnel(NdotV, F0);
    float3 kd      = (1.0 - F_ibl) * (1.0 - metallic);

    float3 irradiance   = ibl_sample_irradiance(N, iblIrradiance, iblSamp);
    float3 prefColor    = ibl_sample_prefiltered(R, roughness, iblPrefiltered, iblSamp, 4);
    float2 brdfFactors  = ibl_sample_brdf_lut(NdotV, roughness, iblBRDFLUT, iblSamp);
    float3 iblDiffuse   = kd * albedo * irradiance;
    float3 iblSpecular  = prefColor * (F_ibl * brdfFactors.x + brdfFactors.y);
    float3 iblAmbient   = (iblDiffuse + iblSpecular) * ao;

    // Minimum ambient prevents fully black surfaces when IBL textures are not yet bound
    // (unbound textures return zero on Apple Silicon Metal).
    float3 ambient = max(iblAmbient, albedo * 0.04 * ao);
    litColor += ambient;

    // ── HDR clamp — prevent extreme specular from overwhelming bloom ──
    litColor = min(litColor, float3(25.0));

    // ── Atmospheric fog ────────────────────────────────────────────
    float  fogNear   = scene.sceneParamsB.x;
    float  fogFar    = scene.sceneParamsB.y;
    float  t         = depthNorm * farPlane;
    float  fogFactor = clamp((t - fogNear) / max(fogFar - fogNear, 0.001), 0.0, 1.0);
    float3 fogColor  = rm_skyColor(rayDir);
    litColor         = mix(litColor, fogColor, fogFactor);

    return float4(litColor, 1.0);
}

// MARK: - Composite Pass

/// Composite the lit .rgba16Float scene texture to the SDR drawable.
///
/// Applies ACES filmic tone mapping. Invoked when the ray march pipeline is
/// used without a `PostProcessChain` for bloom. When bloom is desired, the
/// caller feeds `litTexture` directly into `PostProcessChain.runBloomAndComposite`.
fragment float4 raymarch_composite_fragment(
    VertexOut        in  [[stage_in]],
    texture2d<float> lit [[texture(0)]],
    sampler          s   [[sampler(0)]]
) {
    float3 hdr = lit.sample(s, in.uv).rgb;

    // ACES filmic tone mapping.
    float3 x = hdr;
    float3 mapped = (x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14);
    mapped = clamp(mapped, 0.0, 1.0);

    return float4(mapped, 1.0);
}
