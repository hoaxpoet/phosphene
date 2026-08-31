// DomainWarp.metal — Domain-warped fBM for organic liquid flow.
//
// Domain warping evaluates fBM at coordinates pre-warped by another fBM field.
// Two levels of warping (q then r) produce the organic, swirling flows that
// single-level fBM cannot — characteristic of Inigo Quilez's seminal 2002 demo.
//
// Reference: Inigo Quilez, "Warping" (2002), SHADER_CRAFT.md §3.4.
//
// Depends on: FBM.metal (fbm8, fbm_vec3)
// (FBM.metal must be concatenated before DomainWarp.metal.)
//
// DO NOT add #include <metal_stdlib> or using namespace metal.

/// Two-level domain-warped fBM.
/// Cost: 7 × fbm8 = ~56 Perlin evaluations. Use per-hit or per-vertex only.
/// Output: approximately [-1, 1].
///
/// Reference offsets from SHADER_CRAFT.md §3.4 (IQ's original constants).
static inline float warped_fbm(float3 p) {
    // First warp level: build a displacement field q from p.
    float3 q = float3(
        fbm8(p + float3(0.0, 0.0, 0.0)),
        fbm8(p + float3(5.2, 1.3, 7.1)),
        fbm8(p + float3(3.1, 9.7, 2.9))
    );

    // Second warp level: build r by warping p with q.
    float3 r = float3(
        fbm8(p + 4.0 * q + float3(1.7, 9.2, 3.4)),
        fbm8(p + 4.0 * q + float3(8.3, 2.8, 1.1)),
        fbm8(p + 4.0 * q + float3(4.5, 6.1, 2.3))
    );

    // Final evaluation with r displacement.
    return fbm8(p + 4.0 * r);
}

/// Vector-valued warped fBM — returns a float3 displacement field.
/// Useful as a flow map for UV offset, particle advection, or normal perturbation.
static inline float3 warped_fbm_vec(float3 p) {
    float3 q = fbm_vec3(p);
    float3 r = fbm_vec3(p + 4.0 * q + float3(1.7, 9.2, 3.4));
    return fbm_vec3(p + 4.0 * r);
}
