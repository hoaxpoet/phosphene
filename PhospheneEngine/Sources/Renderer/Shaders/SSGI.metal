// SSGI.metal — Screen-Space Global Illumination pass for Increment 3.17.
//
// Approximates short-range diffuse indirect light bounces using the existing
// G-buffer (depth + normals) and the direct-lit scene texture from the PBR
// lighting pass.  Runs at half resolution for performance.
//
// Two fragment functions:
//
//   ssgi_fragment        — Reads gbuffer0 (depth), gbuffer1 (normals), and
//                          litTexture (direct lighting).  For each surface
//                          pixel, samples K nearby screen-space positions and
//                          accumulates indirect diffuse contribution weighted
//                          by surface orientation and distance falloff.
//                          Renders into a half-res .rgba16Float accumulation
//                          texture.
//
//   ssgi_blend_fragment  — Bilinearly upsamples the half-res SSGI accumulation
//                          texture.  Rendered additively into litTexture
//                          (loadAction = .load, additive blend pipeline state)
//                          before the composite / bloom pass.
//
// G-buffer slots (same layout as RayMarch.metal):
//   texture(0)  gbuffer0  .rg16Float     R = depth_normalized [0..1)
//   texture(1)  gbuffer1  .rgba8Snorm    RGB = world-space normal; A = AO
//   texture(2)  litTex    .rgba16Float   direct PBR lighting result
//   texture(8)  blueNoise .r8Unorm       IGN dithering for sample rotation
//
// SceneUniforms layout (from Common.metal):
//   sceneParamsB.w  — sample-radius override in [0,1] UV space.
//                     0 → default radius 0.08.  Set via preset JSON / RayMarchPipeline.
//
// Increment 3.17 — SSGI Post-Process Pass.

#include <metal_stdlib>
using namespace metal;

// MARK: - Helpers

/// Reconstruct camera ray direction from UV and SceneUniforms.
/// Duplicated locally (static) from RayMarch.metal so SSGI.metal is
/// self-contained even if concatenation order changes.
static float3 ssgi_rayDir(float2 uv, constant SceneUniforms& s) {
    float2 ndc  = uv * 2.0 - 1.0;
    float  yFov = tan(s.cameraOriginAndFov.w * 0.5);
    float  xFov = yFov * s.sceneParamsA.y;  // * aspectRatio
    return normalize(s.cameraForward.xyz
                     + ndc.x * xFov * s.cameraRight.xyz
                     - ndc.y * yFov * s.cameraUp.xyz);
}

// MARK: - SSGI Accumulation Pass

/// Screen-space GI accumulation.
///
/// For each surface pixel, samples 8 nearby positions in a rotated spiral
/// pattern.  Each sample whose surface is visible and faces the current pixel
/// contributes its direct-lit colour, weighted by the cosine of the angle
/// between the current normal and the inter-pixel direction and a distance
/// falloff in screen space.
///
/// The output is scaled by `kIndirectStrength` (0.3) so that indirect bounces
/// are visually present but do not overpower direct illumination.
///
/// Sky pixels (depth ≥ 0.999) return (0,0,0,0) — no indirect contribution.
///
/// Performance note: runs at half resolution; bilinear upsampling in
/// `ssgi_blend_fragment` recovers full-res quality at minimal cost.
fragment float4 ssgi_fragment(
    VertexOut                   in         [[stage_in]],
    constant FeatureVector&     features   [[buffer(0)]],
    constant SceneUniforms&     scene      [[buffer(4)]],
    texture2d<float>            gbuf0      [[texture(0)]],   // depth
    texture2d<float>            gbuf1      [[texture(1)]],   // normals + AO
    texture2d<float>            litTex     [[texture(2)]],   // direct lighting
    texture2d<float>            blueNoise  [[texture(8)]]    // IGN dithering
) {
    constexpr sampler samp(filter::linear, address::clamp_to_edge);
    float2 uv = in.uv;

    // ── Early exit for sky pixels ──────────────────────────────────
    float depthNorm = gbuf0.sample(samp, uv).r;
    if (depthNorm >= 0.999) {
        return float4(0.0, 0.0, 0.0, 0.0);
    }

    // ── Reconstruct surface geometry ───────────────────────────────
    float3 N          = normalize(gbuf1.sample(samp, uv).xyz);
    float  farPlane   = scene.sceneParamsA.w;
    float3 rayDir     = ssgi_rayDir(uv, scene);
    float3 worldPos   = scene.cameraOriginAndFov.xyz + rayDir * (depthNorm * farPlane);

    // ── Sample pattern configuration ───────────────────────────────
    // sceneParamsB.w: sample-radius override.  0 → default 0.08 in UV space.
    float  sampleRadius = (scene.sceneParamsB.w > 0.0) ? scene.sceneParamsB.w : 0.08;
    float  aspectRatio  = scene.sceneParamsA.y;

    // Noise-based rotation so samples at adjacent pixels don't alias.
    // Tile blue noise at prime frequency to avoid coherent patterns.
    float  noiseVal     = blueNoise.sample(samp, fmod(uv * 7.3, float2(1.0))).r;
    float  angle0       = noiseVal * (M_PI_F * 2.0);

    // ── Accumulate indirect diffuse ────────────────────────────────
    const int   kSamples        = 8;
    const float kIndirectStrength = 0.3;

    float3 indirect   = float3(0.0);
    int    validCount = 0;

    for (int i = 0; i < kSamples; i++) {
        // Samples are distributed at varying radii (1/(2N), 3/(2N), ..., (2N-1)/(2N))
        // so that no sample lands exactly at sampleRadius (which would give falloff = 0).
        float  radiusFactor = (float(i) + 0.5) / float(kSamples);   // in (0, 1) exclusive
        float  angle  = angle0 + float(i) * (M_PI_F * 2.0 / float(kSamples));
        // Compensate for aspect ratio so the sampling disk is circular in UV space.
        float2 offset = float2(cos(angle) / aspectRatio, sin(angle)) * sampleRadius * radiusFactor;
        float2 sUV    = uv + offset;

        // Skip samples outside screen bounds.
        if (sUV.x < 0.0 || sUV.x > 1.0 || sUV.y < 0.0 || sUV.y > 1.0) continue;

        float  sDepth = gbuf0.sample(samp, sUV).r;
        if (sDepth >= 0.999) continue;   // sample on sky — no surface to bounce from

        // Reconstruct sample world position for depth-similarity check.
        float3 sRayDir   = ssgi_rayDir(sUV, scene);
        float3 sWorldPos = scene.cameraOriginAndFov.xyz + sRayDir * (sDepth * farPlane);

        // Reject samples on the far side of the current surface (avoids light bleeding
        // through thin geometry).  Use a world-space depth tolerance of 10% of far plane.
        float3 toSample = sWorldPos - worldPos;
        if (dot(toSample, rayDir) > farPlane * 0.1) continue;

        // Distance falloff: linear, maximum at centre, zero at sampleRadius.
        // radiusFactor is in (0,1) so falloff = 1 - radiusFactor is always in (0,1).
        float  falloff   = 1.0 - radiusFactor;

        // Normal hemisphere weight with minimum floor so convex surfaces
        // (where NdotD ≈ 0 for adjacent samples) still receive indirect light.
        float3 dir   = length(toSample) > 1e-4 ? normalize(toSample) : N;
        float  NdotD = max(dot(N, dir), 0.0);

        float3 sampleLit = litTex.sample(samp, sUV).rgb;
        indirect += sampleLit * (NdotD * 0.7 + 0.3) * falloff;
        validCount++;
    }

    if (validCount > 0) {
        indirect /= float(validCount);
    }

    // Alpha = 0: the additive blend pass (ssgi_blend_fragment) only needs RGB.
    return float4(indirect * kIndirectStrength, 0.0);
}

// MARK: - SSGI Blend Pass

/// Bilinear upsample of the half-res SSGI accumulation texture.
///
/// Rendered with an additive blend pipeline state (src=one, dst=one) into the
/// full-resolution litTexture (loadAction=.load), so the indirect diffuse
/// contribution is layered on top of the existing direct lighting.
fragment float4 ssgi_blend_fragment(
    VertexOut        in       [[stage_in]],
    texture2d<float> ssgiTex  [[texture(0)]],
    sampler          samp     [[sampler(0)]]
) {
    // Bilinear upsampling from half-res to full-res is handled automatically
    // by the linear sampler when the texture dimensions are smaller than the
    // render target.
    return ssgiTex.sample(samp, in.uv);
}
