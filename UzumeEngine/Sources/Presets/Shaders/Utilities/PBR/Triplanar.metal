// Triplanar.metal — Triplanar texture projection.
//
// Projects a texture onto geometry from three axis-aligned directions and blends
// the results, avoiding UV seams on procedural geometry (SDF surfaces, terrain,
// mesh primitives with no UV layout).
//
// Triplanar is mandatory for rock, stone, bark, and organic surfaces — uniplanar
// mapping stretches visibly on surfaces perpendicular to the UV axis.
//
// Depends on: NormalMapping.metal (decode_normal_map, ts_to_ws)
//
// Reference: SHADER_CRAFT.md §8.1–§8.2.
//
// DO NOT add #include <metal_stdlib> or using namespace metal.

// ─── Blend weights ────────────────────────────────────────────────────────────

/// Compute triplanar blend weights from the world-space normal `n`.
/// `sharpness` controls how sharply the three faces blend:
///   2–4 = soft blending, 8–16 = sharp projection boundaries.
/// Returns a float3 where x, y, z sum to 1.0.
static inline float3 triplanar_blend_weights(float3 n, float sharpness) {
    float3 w = pow(abs(n), float3(sharpness));
    return w / max(w.x + w.y + w.z, 1e-6);
}

// ─── RGB triplanar sample ─────────────────────────────────────────────────────

/// Sample a texture from three world-space directions and blend by surface normal.
/// `wp`     = world-space position (drives UV coordinates).
/// `n`      = world-space normal (drives blend weights).
/// `tiling` = texture tiling frequency (world units per texture repeat).
static inline float3 triplanar_sample(
    texture2d<float> tex,
    sampler           samp,
    float3            wp,
    float3            n,
    float             tiling
) {
    float3 w  = triplanar_blend_weights(n, 4.0);
    float3 xz = tex.sample(samp, wp.xz * tiling).rgb;
    float3 xy = tex.sample(samp, wp.xy * tiling).rgb;
    float3 yz = tex.sample(samp, wp.yz * tiling).rgb;
    return xz * w.y + xy * w.z + yz * w.x;
}

// ─── Normal map triplanar ─────────────────────────────────────────────────────

/// Sample a tangent-space normal map triplanarly and reorient each face's normal
/// to world space before blending — the "Reoriented Normal Mapping" approach.
///
/// Returns a world-space normal (NOT tangent-space). Ready for lighting.
static inline float3 triplanar_normal(
    texture2d<float> nmap,
    sampler           samp,
    float3            wp,
    float3            n,
    float             tiling
) {
    float3 w  = triplanar_blend_weights(n, 4.0);

    // Sample tangent-space normals from three faces.
    float3 nXZ = decode_normal_map(nmap.sample(samp, wp.xz * tiling).rgb);
    float3 nXY = decode_normal_map(nmap.sample(samp, wp.xy * tiling).rgb);
    float3 nYZ = decode_normal_map(nmap.sample(samp, wp.yz * tiling).rgb);

    // Reorient each face's tangent-space normal to world space.
    // XZ face: tangent=+X, bitangent=+Z, normal=+Y
    float3 wsXZ = float3(nXZ.x, nXZ.z, nXZ.y + sign(n.y));
    // XY face: tangent=+X, bitangent=+Y, normal=+Z
    float3 wsXY = float3(nXY.x, nXY.y, nXY.z + sign(n.z));
    // YZ face: tangent=+Z, bitangent=+Y, normal=+X
    float3 wsYZ = float3(nYZ.z + sign(n.x), nYZ.y, nYZ.x);

    // Blend and normalize.
    float3 blended = wsXZ * w.y + wsXY * w.z + wsYZ * w.x;
    return normalize(blended);
}
