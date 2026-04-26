// MaterialResult.metal — Shared result type and helpers for the V.3 Materials cookbook.
//
// MaterialResult is the common return type for all 16 cookbook material functions.
// It is NOT a replacement for the `sceneMaterial()` engine signature — preset authors
// unpack its fields into the engine's out-parameter convention themselves.
//
// ┌─────────────────────────────────────────────────────────────────────────────┐
// │ Calling a cookbook material from a ray-march sceneMaterial() out-param sig: │
// │                                                                             │
// │   void sceneMaterial(float3 p, float matID, FeatureVector& f,              │
// │                      SceneUniforms& s, StemFeatures& stems,                │
// │                      thread float3& albedo, thread float& roughness,       │
// │                      thread float& metallic)                               │
// │   {                                                                         │
// │       float3 n = calcNormal(p);   // engine convention                     │
// │       MaterialResult m = mat_polished_chrome(p, n);                        │
// │       albedo    = m.albedo;                                                 │
// │       roughness = m.roughness;                                              │
// │       metallic  = m.metallic;                                               │
// │       // m.normal and m.emission are NOT plumbed through the out-param     │
// │       // signature.  Presets that need them must use a side channel or     │
// │       // composite stage.                                                   │
// │   }                                                                         │
// └─────────────────────────────────────────────────────────────────────────────┘
//
// D-062(a): MaterialResult is placed here (Materials/MaterialResult.metal) rather
// than in V.1 PBR because it depends on materials-cookbook conventions, not on
// lower-level BRDF primitives. Keeping it here makes the dependency direction clear:
// PBR utilities → cookbook (not the reverse).
//
// DO NOT add #include <metal_stdlib> or using namespace metal.

// ─── MaterialResult struct ────────────────────────────────────────────────────

/// Common result type for all V.3 cookbook material functions.
///
/// `albedo`    — diffuse/base colour [0, 1]³. Never HDR.
/// `roughness` — surface roughness [0, 1]. 0 = mirror, 1 = fully diffuse.
/// `metallic`  — metallic fraction [0, 1]. 0 = dielectric, 1 = full conductor.
/// `normal`    — optional world-space normal perturbation. Pass the vertex
///              normal unchanged for surfaces that don't perturb normals.
/// `emission`  — HDR emission. float3(0) for non-emissive surfaces.
struct MaterialResult {
    float3 albedo;
    float  roughness;
    float  metallic;
    float3 normal;
    float3 emission;
};

/// Zero-initialise a MaterialResult with sensible mid-range defaults.
/// Albedo 0.5 grey, roughness 0.7, dielectric, identity normal.
static inline MaterialResult material_default(float3 n) {
    MaterialResult m;
    m.albedo    = float3(0.5);
    m.roughness = 0.7;
    m.metallic  = 0.0;
    m.normal    = n;
    m.emission  = float3(0.0);
    return m;
}

// ─── FiberParams ─────────────────────────────────────────────────────────────
// Used by mat_silk_thread (Organic.metal §4.3).

struct FiberParams {
    float3 fiber_tangent;     ///< Along the thread (world space).
    float3 fiber_normal;      ///< Perpendicular to thread axis.
    float  azimuthal_r;       ///< Cuticle roughness (R lobe width). Typical silk: 0.10–0.25.
    float  azimuthal_tt;      ///< Internal scatter roughness (TT lobe exp). Typical: 0.5.
    float  absorption;        ///< Silk absorption along thread.
    float3 tint;              ///< Silk tint colour.
};

// ─── Cookbook-local helpers ───────────────────────────────────────────────────
// These helpers are narrow wrappers used by multiple cookbook recipes.
// They intentionally have different parameter counts from the V.1 PBR
// triplanar functions (which require textures) — Metal resolves them as
// distinct overloads.

/// Procedural triplanar detail normal perturbation using fbm8.
///
/// Perturbs `base_n` with noise sampled triplanarly at world-space position `wp`.
/// `amplitude` controls how strongly the surface is perturbed (0.04–0.12 typical).
///
/// Distinct from V.1 `triplanar_normal(nmap, samp, wp, n, tiling)` — that form
/// requires a texture; this is a purely procedural 3-param overload.
///
/// Caller responsibilities: none — all inputs are value types.
static inline float3 triplanar_detail_normal(float3 base_n, float3 wp, float amplitude) {
    // Triplanar blend weights from the surface normal.
    float3 w = triplanar_blend_weights(base_n, 4.0);

    // Sample fbm8 from three orthogonal faces with per-channel phase offsets
    // to avoid correlated X/Y/Z directions reading the same noise value.
    float3 perturb = float3(
        fbm8(float3(wp.x, wp.z, 0.0 )) * w.y + fbm8(float3(wp.x, wp.y, 0.0 )) * w.z + fbm8(float3(wp.y, wp.z, 0.0 )) * w.x,
        fbm8(float3(wp.x, wp.z, 5.1 )) * w.y + fbm8(float3(wp.x, wp.y, 5.1 )) * w.z + fbm8(float3(wp.y, wp.z, 5.1 )) * w.x,
        fbm8(float3(wp.x, wp.z, 10.3)) * w.y + fbm8(float3(wp.x, wp.y, 10.3)) * w.z + fbm8(float3(wp.y, wp.z, 10.3)) * w.x
    );
    return normalize(base_n + perturb * amplitude);
}

/// Simplified procedural triplanar normal.
///
/// 3-parameter overload (vs V.1's 5-param texture form) used by mat_wet_stone.
/// Perturbs `base_n` at world-space position `wp` with fbm8 triplanar blending.
/// `amplitude` controls perturbation strength (0.05–0.12 typical for stone).
static inline float3 triplanar_normal(float3 wp, float3 base_n, float amplitude) {
    return triplanar_detail_normal(base_n, wp, amplitude);
}
