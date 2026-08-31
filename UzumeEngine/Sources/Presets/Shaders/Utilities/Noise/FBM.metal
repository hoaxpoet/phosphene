// FBM.metal — Fractional Brownian Motion in multiple octave counts.
//
// fBM layers multiple octaves of Perlin noise with amplitude halving and
// frequency doubling. A rotation matrix between octaves breaks grid-aligned
// artifacts that appear in axis-aligned fBM (important for terrain and
// organic surfaces).
//
// Provides fbm4, fbm8, fbm12, and a vector-valued fbm_vec3 for domain warping.
//
// Depends on: Perlin.metal (perlin3d)
//
// DO NOT add #include <metal_stdlib> or using namespace metal.

// ─── fbm4 — 4 octaves ────────────────────────────────────────────────────────

/// 4-octave fBM. Light-weight option for secondary/background surfaces.
/// `H` = Hurst exponent controlling roughness; 0.5 = natural terrain.
/// Output: approximately [-1, 1].
static inline float fbm4(float3 p, float H = 0.5) {
    // Rotation matrix applied between octaves to break axial alignment artifacts.
    // Orthonormal — pure rotation, no scale. SHADER_CRAFT.md §3.2.
    const float3x3 rot = float3x3(
        float3( 0.00,  0.80,  0.60),
        float3(-0.80,  0.36, -0.48),
        float3(-0.60, -0.48,  0.64)
    );
    float a = 1.0, f = 1.0, sum = 0.0, norm = 0.0;
    for (int i = 0; i < 4; ++i) {
        sum  += a * perlin3d(p * f);
        norm += a;
        a    *= H;
        f    *= 2.0;
        p     = rot * p;
    }
    return sum / norm;
}

// ─── fbm8 — 8 octaves (hero) ─────────────────────────────────────────────────

/// 8-octave fBM. The hero workhorse for primary surfaces.
/// Reference implementation from SHADER_CRAFT.md §3.2.
/// Cost: ~8× single-octave Perlin. Avoid inside inner ray-march loops.
/// Output: approximately [-1, 1].
static inline float fbm8(float3 p, float H = 0.5) {
    const float3x3 rot = float3x3(
        float3( 0.00,  0.80,  0.60),
        float3(-0.80,  0.36, -0.48),
        float3(-0.60, -0.48,  0.64)
    );
    float a = 1.0, f = 1.0, sum = 0.0, norm = 0.0;
    for (int i = 0; i < 8; ++i) {
        sum  += a * perlin3d(p * f);
        norm += a;
        a    *= H;
        f    *= 2.0;
        p     = rot * p;
    }
    return sum / norm;
}

// ─── fbm12 — 12 octaves ───────────────────────────────────────────────────────

/// 12-octave fBM. For volumetric terrain and cloud density fields where
/// high-frequency detail is critical. Use per-vertex or per-hit, not per-pixel.
/// Output: approximately [-1, 1].
static inline float fbm12(float3 p, float H = 0.5) {
    const float3x3 rot = float3x3(
        float3( 0.00,  0.80,  0.60),
        float3(-0.80,  0.36, -0.48),
        float3(-0.60, -0.48,  0.64)
    );
    float a = 1.0, f = 1.0, sum = 0.0, norm = 0.0;
    for (int i = 0; i < 12; ++i) {
        sum  += a * perlin3d(p * f);
        norm += a;
        a    *= H;
        f    *= 2.0;
        p     = rot * p;
    }
    return sum / norm;
}

// ─── fbm_vec3 — vector-valued fBM ────────────────────────────────────────────

/// Vector-valued 8-octave fBM returning a float3.
/// Used as the warp field in warped_fbm (DomainWarp.metal).
/// Each component is an independent fbm8 evaluated at offset coordinates,
/// producing a smoothly-varying 3D vector field.
static inline float3 fbm_vec3(float3 p, float H = 0.5) {
    return float3(
        fbm8(p,                           H),
        fbm8(p + float3(5.2,  1.3,  7.1), H),
        fbm8(p + float3(3.1,  9.7,  2.9), H)
    );
}
