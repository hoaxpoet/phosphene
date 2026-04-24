// NormalMapping.metal — Tangent-space normal mapping utilities.
//
// Provides normal map decoding, tangent-space / world-space transforms,
// and TBN construction from position/UV derivatives.
//
// DO NOT add #include <metal_stdlib> or using namespace metal.

// ─── Normal map decoding ──────────────────────────────────────────────────────

/// Decode a normal map sample from [0, 1] RGB to [-1, 1] XYZ (OpenGL convention).
/// The alpha channel is ignored (one-channel maps use `.r` and `.rg` directly).
static inline float3 decode_normal_map(float3 rgb) {
    return normalize(rgb * 2.0 - 1.0);
}

/// Decode a DirectX-style normal map (Y-axis flipped vs OpenGL).
/// Use when importing normal maps authored for DX/Unity (green channel flipped).
static inline float3 decode_normal_map_dx(float3 rgb) {
    float3 n = rgb * 2.0 - 1.0;
    n.y = -n.y;
    return normalize(n);
}

// ─── Tangent-space ↔ world-space transforms ───────────────────────────────────

/// Transform a tangent-space normal `n_ts` to world space using the TBN matrix.
/// T, B, N must form a right-handed orthonormal basis in world space.
static inline float3 ts_to_ws(float3 n_ts, float3 T, float3 B, float3 N) {
    return normalize(T * n_ts.x + B * n_ts.y + N * n_ts.z);
}

/// Transform a world-space normal `n_ws` to tangent space.
/// Equivalent to multiplying by the transpose (= inverse) of the TBN matrix.
static inline float3 ws_to_ts(float3 n_ws, float3 T, float3 B, float3 N) {
    return normalize(float3(dot(n_ws, T), dot(n_ws, B), dot(n_ws, N)));
}

// ─── TBN from derivatives ─────────────────────────────────────────────────────

/// Build a TBN matrix from a surface normal `N`, world-space position `p`, and
/// texture coordinates `uv`. Uses screen-space partial derivatives (dfdx / dfdy).
///
/// Returns the columns (T, B) — combine with the input `N` to form the full TBN.
/// `T` = tangent (aligned with dUV.x), `B` = bitangent (dUV.y).
///
/// Call only from fragment shaders (dfdx/dfdy are fragment-stage intrinsics).
static inline float3x3 tbn_from_derivatives(float3 N, float3 p, float2 uv) {
    float3 dp1  = dfdx(p);
    float3 dp2  = dfdy(p);
    float2 duv1 = dfdx(uv);
    float2 duv2 = dfdy(uv);

    float det = duv1.x * duv2.y - duv1.y * duv2.x;
    float inv = (abs(det) > 1e-6) ? (1.0 / det) : 1.0;

    float3 T = normalize((dp1 * duv2.y - dp2 * duv1.y) * inv);
    float3 B = normalize((dp2 * duv1.x - dp1 * duv2.x) * inv);
    // Re-orthogonalize T against N.
    T = normalize(T - N * dot(N, T));
    B = cross(N, T);

    return float3x3(T, B, N);
}
