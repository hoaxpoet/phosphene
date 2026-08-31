// Curl.metal — Divergence-free curl noise vector field.
//
// The curl of a vector potential field is divergence-free: no net inflow or
// outflow at any point. This makes curl noise ideal for fluid-like flow fields
// used in particle systems, UV advection, and flow-map generation.
//
// Uses central differences on fbm8 to approximate the curl operator ∇ × F.
//
// Reference: Bridson, Houriham & Nordenstam (2007) "Curl-Noise for Procedural
//            Fluid Flow", SHADER_CRAFT.md §3.5.
//
// Depends on: FBM.metal (fbm8)
// (FBM.metal must be concatenated before Curl.metal.)
//
// DO NOT add #include <metal_stdlib> or using namespace metal.

/// Divergence-free 3D curl noise via central differences on fbm8.
/// `e` = finite-difference epsilon (default 0.01; smaller = more accurate but
///       noisier at fine scale).
/// Returns a divergence-free vector field suitable for fluid advection.
static inline float3 curl_noise(float3 p, float e = 0.01) {
    // Finite-difference approximation of ∇ × (fbm8, fbm8, fbm8).
    // For the curl of (Fx, Fy, Fz) evaluated via central differences:
    //   curl.x = dFz/dy - dFy/dz
    //   curl.y = dFx/dz - dFz/dx
    //   curl.z = dFy/dx - dFx/dy
    // Here we use fbm8 for each component with offset coordinates.
    float inv2e = 0.5 / e;

    float n1 = fbm8(p + float3(0, e, 0)) - fbm8(p - float3(0, e, 0));
    float n2 = fbm8(p + float3(0, 0, e)) - fbm8(p - float3(0, 0, e));
    float n3 = fbm8(p + float3(e, 0, 0)) - fbm8(p - float3(e, 0, 0));
    float n4 = fbm8(p + float3(0, 0, e)) - fbm8(p - float3(0, 0, e));
    float n5 = fbm8(p + float3(e, 0, 0)) - fbm8(p - float3(e, 0, 0));
    float n6 = fbm8(p + float3(0, e, 0)) - fbm8(p - float3(0, e, 0));

    return float3(
        (n1 - n2) * inv2e,   // dFz/dy - dFy/dz
        (n3 - n4) * inv2e,   // dFx/dz - dFz/dx
        (n5 - n6) * inv2e    // dFy/dx - dFx/dy
    );
}
