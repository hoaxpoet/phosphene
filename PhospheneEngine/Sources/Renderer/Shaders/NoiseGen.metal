// NoiseGen.metal — Compute kernels for pre-generating tileable noise textures at startup.
//
// Four kernels populate the five noise textures owned by TextureManager:
//   gen_perlin_2d  → noiseLQ (256²) and noiseHQ (1024²)  — tileable FBM value noise
//   gen_perlin_3d  → noiseVolume (64³)                    — tileable 3D FBM value noise
//   gen_fbm_rgba   → noiseFBM (1024²)                     — R=Perlin, G=shifted, B=Worley, A=curl
//   gen_blue_noise → blueNoise (256²)                     — interleaved gradient noise
//
// All kernels are deterministic: same thread position → same output every launch.
// ng_ prefix on helpers avoids symbol collisions with Common.metal and ShaderLib.metal.

#include <metal_stdlib>
using namespace metal;

// MARK: - Private Hash Functions

/// 2D hash → scalar in [0, 1].  Seeded by the constant float3 multipliers.
static inline float ng_hash(float2 p) {
    float3 p3 = fract(float3(p.xyx) * float3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

/// 3D hash → scalar in [0, 1].
static inline float ng_hash3(float3 p) {
    float3 p3 = fract(p * float3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// MARK: - Tileable Value Noise

/// Smooth noise with bilinear interpolation.  Tileable because grid lookups
/// use fmod(cell, period) — the boundary cells wrap to the same hash values.
static inline float ng_valueNoise2D(float2 p, float period) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);   // C1-smooth step

    float a = ng_hash(fmod(i,                     period));
    float b = ng_hash(fmod(i + float2(1.0, 0.0),  period));
    float c = ng_hash(fmod(i + float2(0.0, 1.0),  period));
    float d = ng_hash(fmod(i + float2(1.0, 1.0),  period));

    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

/// 3D tileable value noise.
static inline float ng_valueNoise3D(float3 p, float period) {
    float3 i = floor(p);
    float3 f = fract(p);
    float3 u = f * f * (3.0 - 2.0 * f);

    float a = ng_hash3(fmod(i + float3(0, 0, 0), period));
    float b = ng_hash3(fmod(i + float3(1, 0, 0), period));
    float c = ng_hash3(fmod(i + float3(0, 1, 0), period));
    float d = ng_hash3(fmod(i + float3(1, 1, 0), period));
    float e = ng_hash3(fmod(i + float3(0, 0, 1), period));
    float g = ng_hash3(fmod(i + float3(1, 0, 1), period));
    float h = ng_hash3(fmod(i + float3(0, 1, 1), period));
    float k = ng_hash3(fmod(i + float3(1, 1, 1), period));

    return mix(
        mix(mix(a, b, u.x), mix(c, d, u.x), u.y),
        mix(mix(e, g, u.x), mix(h, k, u.x), u.y),
        u.z
    );
}

// MARK: - Worley / Cellular Noise

/// Distance to nearest Poisson-distributed seed point in the unit cell neighbourhood.
/// Returns a value in [0, 1] (clamped).  Not tileable by default — used in noiseFBM
/// at a scale where tiling is not perceptible.
static inline float ng_worley2D(float2 p) {
    float2 cell = floor(p);
    float minDist = 8.0;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            float2 n = cell + float2(x, y);
            // Two independent jitter values per cell
            float2 jitter = float2(ng_hash(n), ng_hash(n + float2(13.7, 5.3)));
            float2 point = n + jitter;
            minDist = min(minDist, length(p - point));
        }
    }
    return clamp(minDist, 0.0, 1.0);
}

// MARK: - FBM Helper

/// 4-octave FBM over ng_valueNoise2D.
static inline float ng_fbm2D(float2 p, float period) {
    float n = 0.0, amp = 0.5, freq = 1.0, total = 0.0;
    for (int i = 0; i < 4; i++) {
        n     += ng_valueNoise2D(p * freq, period * freq) * amp;
        total += amp;
        amp   *= 0.5;
        freq  *= 2.0;
    }
    return n / total;
}

/// 3-octave FBM over ng_valueNoise3D.
static inline float ng_fbm3D(float3 p, float period) {
    float n = 0.0, amp = 0.5, freq = 1.0, total = 0.0;
    for (int i = 0; i < 3; i++) {
        n     += ng_valueNoise3D(p * freq, period * freq) * amp;
        total += amp;
        amp   *= 0.5;
        freq  *= 2.0;
    }
    return n / total;
}

// MARK: - Compute Kernels

/// Generate tileable 2D FBM value noise into an `.r8Unorm` texture.
///
/// Used for both noiseLQ (256²) and noiseHQ (1024²) — the same kernel is
/// dispatched twice with different texture bindings and `texSize` values.
///
/// - texture(0): write target (2D `.r8Unorm`)
/// - buffer(0):  `texSize` — texture edge length in pixels
kernel void gen_perlin_2d(
    texture2d<float, access::write> out [[texture(0)]],
    constant uint&                  texSize [[buffer(0)]],
    uint2                           gid [[thread_position_in_grid]])
{
    if (gid.x >= texSize || gid.y >= texSize) { return; }

    // UV centred on pixel centres (avoids edge artefacts on mip-0 boundaries).
    float2 uv = (float2(gid) + 0.5) / float(texSize);

    // 8 noise cycles across the texture at the base frequency.
    const float period = 8.0;
    float n = ng_fbm2D(uv * period, period);

    out.write(float4(n, 0.0, 0.0, 1.0), gid);
}

/// Generate tileable 3D FBM value noise into an `.r8Unorm` 3D texture.
///
/// - texture(0): write target (3D `.r8Unorm`)
/// - buffer(0):  `texSize` — cube edge length in pixels (64)
kernel void gen_perlin_3d(
    texture3d<float, access::write> out [[texture(0)]],
    constant uint&                  texSize [[buffer(0)]],
    uint3                           gid [[thread_position_in_grid]])
{
    if (gid.x >= texSize || gid.y >= texSize || gid.z >= texSize) { return; }

    float3 uvw = (float3(gid) + 0.5) / float(texSize);

    const float period = 4.0;
    float n = ng_fbm3D(uvw * period, period);

    out.write(float4(n, 0.0, 0.0, 1.0), gid);
}

/// Generate a 4-channel RGBA FBM texture into an `.rgba8Unorm` target.
///
/// Channel layout:
///   R — FBM value noise (standard seed)
///   G — FBM value noise (offset seed — different visual character)
///   B — Inverted Worley / cellular noise (bright at cell centres)
///   A — Curl-magnitude approximation from finite-difference gradient
///
/// - texture(0): write target (2D `.rgba8Unorm`)
/// - buffer(0):  `texSize` — texture edge length in pixels (1024)
kernel void gen_fbm_rgba(
    texture2d<float, access::write> out [[texture(0)]],
    constant uint&                  texSize [[buffer(0)]],
    uint2                           gid [[thread_position_in_grid]])
{
    if (gid.x >= texSize || gid.y >= texSize) { return; }

    float2 uv = (float2(gid) + 0.5) / float(texSize);
    const float period = 8.0;
    float2 p = uv * period;

    // R: standard FBM
    float r = ng_fbm2D(p, period);

    // G: same FBM, shifted seed domain
    float g = ng_fbm2D(p + float2(17.3, 43.7), period);

    // B: inverted Worley — bright halos at cell seeds, dark veins between
    float b = 1.0 - ng_worley2D(p);

    // A: curl magnitude — finite differences of the noise gradient.
    //    eps = 1 texel in noise space.
    float eps = period / float(texSize);
    float dfdx = ng_valueNoise2D(p + float2(eps, 0.0), period) -
                 ng_valueNoise2D(p - float2(eps, 0.0), period);
    float dfdy = ng_valueNoise2D(p + float2(0.0, eps), period) -
                 ng_valueNoise2D(p - float2(0.0, eps), period);
    // Perpendicular gradient (curl z-component), remapped to [0, 1].
    float a = clamp(length(float2(dfdy, -dfdx)) / (2.0 * eps) * 0.25 + 0.5, 0.0, 1.0);

    out.write(float4(r, g, b, a), gid);
}

/// Generate a blue-noise-like dither texture into an `.r8Unorm` target.
///
/// Uses Interleaved Gradient Noise (IGN), which has excellent spectral
/// properties for dithering and is free of visible low-frequency patterns.
/// It is deterministic (no random seed required) and cheap to evaluate.
///
/// Reference: Jimenez 2014, "Next Generation Post Processing in Call of Duty"
///
/// - texture(0): write target (2D `.r8Unorm`)
/// - buffer(0):  `texSize` — texture edge length in pixels (256)
kernel void gen_blue_noise(
    texture2d<float, access::write> out [[texture(0)]],
    constant uint&                  texSize [[buffer(0)]],
    uint2                           gid [[thread_position_in_grid]])
{
    if (gid.x >= texSize || gid.y >= texSize) { return; }

    // Interleaved gradient noise — good high-frequency spectral distribution.
    float v = fract(52.9829189f * fract(0.06711056f * float(gid.x)
                                      + 0.00583715f * float(gid.y)));

    out.write(float4(v, 0.0, 0.0, 1.0), gid);
}
