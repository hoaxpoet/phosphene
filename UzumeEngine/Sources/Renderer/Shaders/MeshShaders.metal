// MeshShaders.metal — Mesh shader pipeline utilities for Increment 3.2.
//
// Provides shared meshlet structures, a trivial object + mesh shader pair for
// infrastructure validation, a shared fragment shader, and a standard vertex
// shader fallback for M1/M2 hardware.
//
// These are infrastructure primitives — no preset-specific logic lives here.
// Preset-specific mesh shaders (Increment 3.2b and beyond) are compiled
// separately by PresetLoader using the meshlet struct definitions from the
// PresetLoader preamble.

#include <metal_stdlib>
using namespace metal;

// MARK: - Meshlet Structures

/// Per-meshlet dispatch payload: passed from the object shader to the mesh
/// shader via the [[payload]] attribute.  Each field is written by the object
/// shader and consumed read-only by the mesh shader.
struct ObjectPayload {
    uint meshletIndex;
    uint vertexOffset;
    uint primitiveOffset;
};

/// Per-vertex output from the mesh shader stage.  Consumed by the fragment
/// shader via [[stage_in]].  The [[position]] attribute marks the clip-space
/// position; `normal` is available to preset fragment shaders for lighting.
/// `clipXY` carries the interpolated clip-space XY for fragment-side ray-march
/// presets (e.g. spider SDF in Arachne) that need the screen position without
/// relying on the system [[position]] built-in's window-coordinate semantics.
struct MeshVertex {
    float4 position [[position]];
    float2 uv;
    float3 normal;
    float2 clipXY;
};

/// Per-primitive metadata.  Empty for base infrastructure — extend in presets
/// that require per-face data (e.g. face normals, material indices).
struct MeshPrimitive {};

// MARK: - Object Shader

/// Dispatches one mesh threadgroup for a single meshlet.
///
/// The [[max_total_threads_per_threadgroup(1)]] attribute constrains the
/// object threadgroup to a single thread, matching the
/// `threadsPerObjectThreadgroup: MTLSize(width: 1, ...)` dispatch in
/// MeshGenerator.draw().
[[object, max_total_threads_per_threadgroup(1)]]
void mesh_object_shader(
    object_data ObjectPayload* payload [[payload]],
    mesh_grid_properties mgp,
    uint tid [[thread_index_in_threadgroup]]
) {
    // Dispatch exactly one mesh threadgroup per object shader invocation.
    mgp.set_threadgroups_per_grid(uint3(1, 1, 1));

    // Thread 0 initialises the payload consumed by the mesh shader.
    if (tid == 0) {
        payload->meshletIndex   = 0;
        payload->vertexOffset   = 0;
        payload->primitiveOffset = 0;
    }
}

// MARK: - Mesh Shader

/// Outputs a single full-screen triangle for infrastructure validation.
///
/// Three threads run in parallel — one vertex per thread — matching the
/// `threadsPerMeshThreadgroup: MTLSize(width: 3, ...)` dispatch in
/// MeshGenerator.draw().  The mesh template parameters `<3, 1>` are the
/// per-meshlet vertex/primitive maxima for this trivial shader; production
/// mesh presets use `MeshGeneratorConfiguration.maxVerticesPerMeshlet` (256)
/// and `maxPrimitivesPerMeshlet` (512) instead.
[[mesh, max_total_threads_per_threadgroup(3)]]
void mesh_shader(
    object_data const ObjectPayload& payload [[payload]],
    mesh<MeshVertex, MeshPrimitive, 3, 1, topology::triangle> m,
    uint lid [[thread_index_in_threadgroup]]
) {
    // Thread 0: declare primitive count and set the index list.
    if (lid == 0) {
        m.set_primitive_count(1);
        m.set_index(0, 0);
        m.set_index(1, 1);
        m.set_index(2, 2);
    }

    // Each of the 3 threads emits one vertex (fullscreen triangle pattern,
    // identical to fullscreen_vertex in Common.metal).
    if (lid < 3) {
        float2 uv = float2(float((lid << 1u) & 2u), float(lid & 2u));
        float2 clip = uv * 2.0 - 1.0;
        MeshVertex v;
        v.position = float4(clip, 0.0, 1.0);
        v.uv       = float2(uv.x, 1.0 - uv.y);
        v.normal   = float3(0.0, 0.0, 1.0);
        v.clipXY   = clip;
        m.set_vertex(lid, v);
    }
}

// MARK: - Fragment Shader

/// Shared fragment shader for mesh-rendered geometry.
///
/// Infrastructure output: renders UV coordinates as red/green channels (blue
/// always 0, alpha always 1).  Preset-specific fragment shaders replace this
/// with domain-specific visuals.
fragment float4 mesh_fragment(MeshVertex in [[stage_in]]) {
    return float4(in.uv, 0.0, 1.0);
}

// MARK: - Vertex Shader Fallback (M1 / M2)

/// Standard vertex shader that generates the same full-screen triangle as
/// mesh_shader above, used when `device.supportsFamily(.apple8)` is false.
///
/// Enables mesh shader presets to run without crashing on M1/M2 hardware —
/// the preset's fragment shader executes normally; only the mesh geometry
/// generation stage is missing.
vertex MeshVertex mesh_fallback_vertex(uint vid [[vertex_id]]) {
    float2 uv   = float2(float((vid << 1u) & 2u), float(vid & 2u));
    float2 clip = uv * 2.0 - 1.0;
    MeshVertex out;
    out.position = float4(clip, 0.0, 1.0);
    out.uv       = float2(uv.x, 1.0 - uv.y);
    out.normal   = float3(0.0, 0.0, 1.0);
    out.clipXY   = clip;
    return out;
}
