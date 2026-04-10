// RayTracing.metal — Native Metal ray tracing utility structs, helpers, and kernels.
//
// Uses the Metal ray tracing API (MSL 3.1, macOS 11+) — no MPS dependency.
// Requires device.supportsRaytracing (true on all Apple Silicon).
//
// Key MSL distinctions:
//   • primitive_acceleration_structure — the kernel buffer binding type.
//     This is acceleration_structure<> with no tags. Only valid for buffer(N).
//   • intersector<triangle_data>       — the intersector object inside the kernel.
//     The triangle_data tag enables triangle_barycentric_coord in the result.
//   • intersection_result<triangle_data>.triangle_barycentric_coord — the correct
//     member name for per-triangle barycentrics (NOT .barycentrics, which does not
//     exist on macOS 14 / Metal compiler 32023).
//   They are separate types; mixing them (e.g. acceleration_structure<triangle_data>
//   as a buffer param) is a compile error on macOS 14 Metal compiler 32023.
//
// Struct layouts (must match Swift-side types in RayIntersector.swift exactly):
//   RTRay        → RayGPUData     (32 bytes: packed_float3 × 2 + float × 2)
//   RTNearestHit → NearestHitData (16 bytes: float + uint + float2)

#include <metal_stdlib>
#include <metal_raytracing>
using namespace metal;
using namespace metal::raytracing;

// MARK: - Shared Structs

/// Packed ray matching RayGPUData in RayIntersector.swift (32 bytes).
///
/// packed_float3 is 12 bytes (no alignment padding), so the layout is:
///   [ox oy oz minDist dx dy dz maxDist] = 32 bytes.
struct RTRay {
    packed_float3 origin;       ///< World-space ray origin.
    float         minDistance;  ///< Near clip (> 0 avoids self-intersection).
    packed_float3 direction;    ///< World-space ray direction (need not be normalised).
    float         maxDistance;  ///< Far clip.
};

/// Nearest-hit result matching NearestHitData in RayIntersector.swift (16 bytes).
///
/// distance < 0 means no triangle was hit.
struct RTNearestHit {
    float    distance;       ///< Ray parameter t to the hit. Negative = miss.
    uint     primitiveIndex; ///< Index of the intersected triangle.
    float2   barycentrics;   ///< Barycentric (u, v) at the hit point.
};

// MARK: - Ray Generation Utilities

/// Generate a camera ray for a pixel given its NDC coordinates.
inline RTRay rt_camera_ray(float2 ndc, float3 cameraOrigin, float focalLength) {
    RTRay r;
    r.origin      = cameraOrigin;
    r.direction   = normalize(float3(ndc.x, ndc.y, -focalLength));
    r.minDistance = 1e-4;
    r.maxDistance = 1e10;
    return r;
}

/// Compute the specular reflection direction for an incident ray.
///
/// Both `incident` and `normal` should be unit-length.
inline float3 rt_reflect(float3 incident, float3 normal) {
    return incident - 2.0 * dot(incident, normal) * normal;
}

/// Offset a surface point along its normal to avoid self-intersection.
inline float3 rt_offset_point(float3 position, float3 normal, float eps = 1e-4) {
    return position + normal * eps;
}

// MARK: - Nearest-Hit Kernel

/// Find the closest triangle intersection for each ray.
///
/// Bindings:
///   buffer(0) — primitive_acceleration_structure (the scene BVH)
///   buffer(1) — RTRay array, one entry per ray (read-only)
///   buffer(2) — RTNearestHit array, one entry per ray (write-only)
///
/// Thread configuration: one thread per ray.
kernel void rt_nearest_hit_kernel(
    primitive_acceleration_structure scene [[buffer(0)]],
    device const RTRay*  rays [[buffer(1)]],
    device RTNearestHit* hits [[buffer(2)]],
    uint tid [[thread_position_in_grid]]
) {
    RTRay r = rays[tid];

    ray metalRay;
    metalRay.origin       = float3(r.origin);
    metalRay.direction    = float3(r.direction);
    metalRay.min_distance = r.minDistance;
    metalRay.max_distance = r.maxDistance;

    // intersector<triangle_data> adds barycentrics to intersection_result.
    intersector<triangle_data> isect;
    intersection_result<triangle_data> result = isect.intersect(metalRay, scene);

    RTNearestHit hit;
    if (result.type == intersection_type::none) {
        hit.distance       = -1.0;
        hit.primitiveIndex = 0;
        hit.barycentrics   = float2(0.0);
    } else {
        hit.distance       = result.distance;
        hit.primitiveIndex = result.primitive_id;
        hit.barycentrics   = result.triangle_barycentric_coord;
    }
    hits[tid] = hit;
}

// MARK: - Shadow Kernel

/// Any-hit shadow test. Stops as soon as the first occluder is found.
///
/// Uses intersector<> with no tags (no barycentrics needed) for efficiency.
/// accept_any_intersection(true) terminates traversal at the first hit.
///
/// Bindings:
///   buffer(0) — primitive_acceleration_structure (the scene BVH)
///   buffer(1) — RTRay array, one entry per shadow ray (read-only)
///   buffer(2) — float array, one per shadow ray (write-only)
///               1.0 = fully lit, 0.0 = fully occluded.
///
/// Thread configuration: one thread per shadow ray.
kernel void rt_shadow_kernel(
    primitive_acceleration_structure scene [[buffer(0)]],
    device const RTRay* rays       [[buffer(1)]],
    device       float* visibility [[buffer(2)]],
    uint tid [[thread_position_in_grid]]
) {
    RTRay r = rays[tid];

    ray metalRay;
    metalRay.origin       = float3(r.origin);
    metalRay.direction    = float3(r.direction);
    metalRay.min_distance = r.minDistance;
    metalRay.max_distance = r.maxDistance;

    // No triangle_data tag — we only need hit/miss, not barycentrics.
    intersector<> isect;
    isect.accept_any_intersection(true);
    intersection_result<> result = isect.intersect(metalRay, scene);

    visibility[tid] = (result.type == intersection_type::none) ? 1.0 : 0.0;
}
