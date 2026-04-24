// DetailNormals.metal — Detail normal blending utilities.
//
// Combines a base normal map with a detail normal map in a way that preserves
// perceived surface detail — simple averaging flattens normals toward the base,
// while UDN (Unity Detail Normal) blending preserves detail scale correctly.
//
// Depends on: NormalMapping.metal (ts_to_ws)
//
// Reference: Blinn 1978 "Simulation of Wrinkled Surfaces" (blending principle),
//            Unity HDRP documentation on detail normals.
//
// DO NOT add #include <metal_stdlib> or using namespace metal.

/// UDN (Unity Detail Normal) blending.
/// Preserves the apparent detail scale of both normals — the industry standard
/// for layering a detail normal over a base normal map.
/// Both inputs are in tangent space, with z pointing up (i.e. (0,0,1) = flat).
/// Returns a normalized tangent-space normal.
static inline float3 combine_normals_udn(float3 base, float3 detail) {
    // UDN: (base.xy + detail.xy, base.z) — avoids tilting the base normal.
    float3 n = float3(base.xy + detail.xy, base.z);
    return normalize(n);
}

/// Whiteout blending — alternative to UDN that better preserves steep tilts.
/// More expensive than UDN (requires extra normalize) but more accurate when
/// the base normal is itself tilted significantly.
static inline float3 combine_normals_whiteout(float3 base, float3 detail) {
    // Whiteout: normalize(base + detail) with z correction.
    float3 n = float3(
        base.x * detail.z + detail.x * base.z,
        base.y * detail.z + detail.y * base.z,
        base.z * detail.z
    );
    return normalize(n);
}
