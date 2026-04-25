// PostProcess.metal — HDR post-process chain for Increment 3.4.
//
// Four fragment shaders forming a multi-pass bloom + ACES tone-mapping pipeline:
//   1. pp_bright_pass_fragment  — luminance threshold, full-res → half-res bloom
//   2. pp_blur_h_fragment       — separable 9-tap Gaussian, horizontal pass
//   3. pp_blur_v_fragment       — separable 9-tap Gaussian, vertical pass
//   4. pp_composite_fragment    — scene + bloom → ACES tone-mapped SDR output
//
// All shaders use `fullscreen_vertex` and `VertexOut` from Common.metal,
// which is concatenated ahead of this file by ShaderLibrary.

#include <metal_stdlib>
using namespace metal;

// MARK: - Utilities

/// Rec. 709 perceptual luminance weights.
static constant float3 kLuminanceWeights = float3(0.2126, 0.7152, 0.0722);

/// ACES filmic tone-mapping curve (S. Hill / Narkowicz 2015).
/// Maps HDR linear values to the SDR [0, 1] range with a gentle shoulder.
static float3 aces_tonemap(float3 x) {
    return saturate((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14));
}

/// 9-tap separable Gaussian kernel (sigma ≈ 1.5).
/// Symmetric weights for taps at offsets 0, ±1, ±2, ±3, ±4.
/// Sum of all taps = 0.2666 + 2*(0.2134+0.1096+0.0361+0.0076) = 1.0
static constant float kGauss[5] = { 0.2666, 0.2134, 0.1096, 0.0361, 0.0076 };

// MARK: - Pass 1: Bright Pass

/// Passes pixels whose Rec. 709 luminance exceeds 0.9.
/// Renders from the full-resolution HDR scene texture to the half-resolution
/// bloom texture, naturally downsampling by 2× via bilinear sampling.
fragment float4 pp_bright_pass_fragment(
    VertexOut in                         [[stage_in]],
    texture2d<float> scene               [[texture(0)]],
    sampler samp                         [[sampler(0)]]
) {
    float4 color = scene.sample(samp, in.uv);
    float lum = dot(color.rgb, kLuminanceWeights);
    return lum > 0.9 ? color : float4(0.0, 0.0, 0.0, 0.0);
}

// MARK: - Pass 2: Horizontal Gaussian Blur

/// 9-tap separable Gaussian blur in the horizontal direction.
/// `texel_size.x` = 1.0 / texture_width of the source bloom texture.
fragment float4 pp_blur_h_fragment(
    VertexOut in                         [[stage_in]],
    constant float2& texel_size          [[buffer(0)]],
    texture2d<float> src                 [[texture(0)]],
    sampler samp                         [[sampler(0)]]
) {
    float4 result = src.sample(samp, in.uv) * kGauss[0];
    for (int i = 1; i < 5; i++) {
        float2 offset = float2(texel_size.x * float(i), 0.0);
        result += src.sample(samp, in.uv + offset) * kGauss[i];
        result += src.sample(samp, in.uv - offset) * kGauss[i];
    }
    return result;
}

// MARK: - Pass 3: Vertical Gaussian Blur

/// 9-tap separable Gaussian blur in the vertical direction.
/// `texel_size.y` = 1.0 / texture_height of the source bloom texture.
fragment float4 pp_blur_v_fragment(
    VertexOut in                         [[stage_in]],
    constant float2& texel_size          [[buffer(0)]],
    texture2d<float> src                 [[texture(0)]],
    sampler samp                         [[sampler(0)]]
) {
    float4 result = src.sample(samp, in.uv) * kGauss[0];
    for (int i = 1; i < 5; i++) {
        float2 offset = float2(0.0, texel_size.y * float(i));
        result += src.sample(samp, in.uv + offset) * kGauss[i];
        result += src.sample(samp, in.uv - offset) * kGauss[i];
    }
    return result;
}

// MARK: - Pass 4: ACES Composite

/// Combines the full-resolution HDR scene with the blurred bloom texture,
/// then applies ACES filmic tone mapping to produce SDR output.
///
/// `bloomStrength` scales the bloom contribution: 1.0 = full bloom (0.5× additive),
/// 0.0 = no bloom (frame-budget governor suppression, QualityLevel >= .noBloom).
/// ACES tone mapping always runs regardless of bloomStrength. D-057.
fragment float4 pp_composite_fragment(
    VertexOut in                         [[stage_in]],
    constant float& bloomStrength        [[buffer(0)]],
    texture2d<float> scene               [[texture(0)]],
    texture2d<float> bloom               [[texture(1)]],
    sampler samp                         [[sampler(0)]]
) {
    float3 sceneColor = scene.sample(samp, in.uv).rgb;
    float3 bloomColor = bloom.sample(samp, in.uv).rgb;

    // Additive bloom at half strength — visible glow without washing out the scene.
    // bloomStrength is 0.0 when suppressed by the frame-budget governor.
    float3 hdr = sceneColor + bloomColor * (0.5 * bloomStrength);

    // ACES filmic tone mapping: HDR → SDR [0, 1].
    float3 sdr = aces_tonemap(hdr);

    return float4(sdr, 1.0);
}
