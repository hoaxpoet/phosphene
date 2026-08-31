// BlueNoise.metal — Blue-noise and IGN sampling helpers.
//
// Provides banding-free noise for dithering integration passes (SSGI, volumetric,
// probe sampling). Two variants:
//   - Texture-based: samples the existing blueNoise texture at texture(8).
//   - IGN formula: cheap per-pixel computation, no texture required.
//
// DO NOT add #include <metal_stdlib> or using namespace metal.

// ─── Texture-based blue noise ─────────────────────────────────────────────────

/// Sample the pre-computed blue-noise texture (256² IGN, bound at texture(8)).
/// `screen_uv` is in [0, 1]², `screen_size` is the render target resolution.
/// Tiles the 256² texture over the screen with nearest sampling.
static inline float blue_noise_sample(
    texture2d<float> tex,
    sampler           samp,
    float2            screen_uv,
    float2            screen_size
) {
    float2 tile_uv = screen_uv * screen_size / 256.0;
    return tex.sample(samp, tile_uv).r;
}

// ─── IGN (Interleaved Gradient Noise) ────────────────────────────────────────

/// Robert Jimenez's IGN formula.
/// Returns a pseudo-random float in [0, 1) for pixel coordinate `pixel_coord`.
/// Has excellent blue-noise properties (low-discrepancy point set per frame).
/// Reference: http://www.iryoku.com/next-generation-post-processing-in-call-of-duty-advanced-warfare
static inline float ign(float2 pixel_coord) {
    float3 magic = float3(0.06711056, 0.00583715, 52.9829189);
    return fract(magic.z * fract(dot(pixel_coord, magic.xy)));
}

/// Temporal IGN — offsets IGN by a per-frame constant so samples rotate over
/// time. Use `frame % 64` (or similar) for good temporal distribution.
/// Jitter moves with a golden-ratio step to maintain blue-noise characteristics.
static inline float ign_temporal(float2 pixel_coord, uint frame) {
    // Golden-ratio temporal accumulation per "Stochastic All the Things" (SIGGRAPH 2019).
    float base = ign(pixel_coord);
    float offset = float(frame) * 0.6180339887; // 1/phi
    return fract(base + offset);
}
