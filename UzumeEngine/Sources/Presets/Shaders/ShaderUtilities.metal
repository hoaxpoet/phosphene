// ShaderUtilities.metal — Legacy shared shader functions (residual keepers).
//
// This file is concatenated into the PresetLoader preamble, so every
// runtime-compiled preset shader sees these functions without an import.
//
// DO NOT add #include <metal_stdlib> or using namespace metal — the preamble
// already provides them.
//
// All functions are static inline: no symbol collision between independent
// preset compilation units, and unused ones are dead-code eliminated.
//
// ──────────────────────────────────────────────────────────────────────────
// What this file is now (RECON.16, 2026-08-26)
// ──────────────────────────────────────────────────────────────────────────
//
// It used to carry 42 functions — a second, parallel library of noise, SDF,
// ray-marching, PBR, UV-transform and colour helpers alongside the V.1–V.3
// tree in `Sources/Presets/Shaders/Utilities/`. A transitive reachability
// census over every preset, every Renderer shader and every preamble string
// found that 38 of them had NO caller anywhere: the whole SDF-primitive,
// ray-marching, PBR and UV-transform sections were unreachable (the
// ray-march helpers additionally required a user-defined `map()` that no
// preset ever defined), and the rest duplicated the V.1–V.3 tree, which is
// where new work goes. They were deleted; git history has them.
//
// Four survive, and only because they have live consumers:
//
//   hash21   ← perlin3D
//   perlin3D ← fbm3D
//   fbm3D    ← VolumetricLithograph.metal (3 call sites)
//   toneMapACES ← Nimbus.metal (2 call sites)
//
// ──────────────────────────────────────────────────────────────────────────
// Why fbm3D is not simply replaced by the V.1 fbm family
// ──────────────────────────────────────────────────────────────────────────
//
// They are different algorithms, not naming variants — swapping them changes
// the image, so it cannot be done as mechanical cleanup:
//
//   perlin3D                  — VALUE noise; output [0, 1]; cubic fade.
//   perlin3d (V.1)            — GRADIENT noise; output [-1, 1]; C² quintic.
//                               (Utilities/Noise/Perlin.metal)
//
//   fbm3D                     — Variable octave count, simple amplitude
//                               halving, no rotation. Built on perlin3D
//                               (value noise). Output [0, 1].
//   fbm4 / fbm8 / fbm12 (V.1) — Fixed octave count, per-octave rotation
//                               matrix, Hurst-exponent decay. Built on
//                               perlin3d (gradient noise). Output ~[-0.7, 0.7].
//                               (Utilities/Noise/FBM.metal)
//
// Retiring these last four means migrating VolumetricLithograph and Nimbus and
// accepting the visual change — that is ENGINEERING_PLAN §Increment QR.7
// (CLEAN.2), which remains open. New presets use the V.1–V.3 tree.
//
// Reference implementations: noise — Stefan Gustavson / Inigo Quilez;
// ACES — Stephen Hill's fitted curve (Unreal Engine).

// ======================================================================
// MARK: - Hash Functions
// ======================================================================

/// 2D → 1D hash. Fast pseudo-random via sine.
static inline float hash21(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// ======================================================================
// MARK: - Noise Functions
// ======================================================================

/// 3D value/gradient noise (Perlin-style).
static inline float perlin3D(float3 p) {
    float3 i = floor(p);
    float3 f = fract(p);
    float3 u = f * f * (3.0 - 2.0 * f);

    float n000 = hash21(i.xy + float2(i.z * 137.0, 0.0));
    float n100 = hash21(i.xy + float2(i.z * 137.0 + 1.0, 0.0));
    float n010 = hash21(i.xy + float2(i.z * 137.0, 1.0));
    float n110 = hash21(i.xy + float2(i.z * 137.0 + 1.0, 1.0));
    float n001 = hash21(i.xy + float2((i.z + 1.0) * 137.0, 0.0));
    float n101 = hash21(i.xy + float2((i.z + 1.0) * 137.0 + 1.0, 0.0));
    float n011 = hash21(i.xy + float2((i.z + 1.0) * 137.0, 1.0));
    float n111 = hash21(i.xy + float2((i.z + 1.0) * 137.0 + 1.0, 1.0));

    float n00 = mix(n000, n100, u.x);
    float n01 = mix(n010, n110, u.x);
    float n10 = mix(n001, n101, u.x);
    float n11 = mix(n011, n111, u.x);

    float n0 = mix(n00, n01, u.y);
    float n1 = mix(n10, n11, u.y);

    return mix(n0, n1, u.z);
}

/// 3D fractal Brownian motion — layered Perlin noise.
static inline float fbm3D(float3 p, int octaves = 5) {
    float value = 0.0;
    float amplitude = 0.5;
    float frequency = 1.0;
    for (int i = 0; i < octaves; i++) {
        value += amplitude * perlin3D(p * frequency);
        frequency *= 2.0;
        amplitude *= 0.5;
    }
    return value;
}

// ======================================================================
// MARK: - Colour
// ======================================================================

/// ACES filmic tone mapping — legacy camelCase alias; V.3 canonical: tone_map_aces().
/// Superseded by tone_map_aces() in Utilities/Color/ToneMapping.metal (D-062).
/// Retained under camelCase name for any future call sites; no collision with snake_case.
static inline float3 toneMapACES(float3 x) {
    const float a = 2.51;
    const float b = 0.03;
    const float c = 2.43;
    const float d = 0.59;
    const float e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0);
}
