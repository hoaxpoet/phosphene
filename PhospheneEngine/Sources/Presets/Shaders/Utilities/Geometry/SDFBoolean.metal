// SDFBoolean.metal — SDF boolean operations and multi-node blending (V.2 Part A).
//
// Boolean operations combine two or more signed distances to create complex shapes.
// Smooth variants (polynomial smin) produce C1-continuous transitions.
//
// Naming: op_* — snake_case, distinct from legacy opUnion/opSmoothUnion (camelCase).
// Source: Inigo Quilez https://iquilezles.org/articles/distfunctions/
//         https://iquilezles.org/articles/smin/

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"

// ─── Hard Boolean Operations ─────────────────────────────────────────────────

/// Hard union: the closer of two surfaces.
static inline float op_union(float a, float b) {
    return min(a, b);
}

/// Hard subtraction: carve shape b out of shape a. Order matters: a - b.
static inline float op_subtract(float a, float b) {
    return max(a, -b);
}

/// Hard intersection: only the overlap of both shapes.
static inline float op_intersect(float a, float b) {
    return max(a, b);
}

// ─── Smooth Boolean Operations ────────────────────────────────────────────────
// Polynomial smin (quadratic): cheaper than exponential, C1 continuous.
// k controls blend width; larger k = wider, rounder blend.

/// Smooth union: blends two surfaces with a rounded merge region.
/// k = blend radius (world units). Returns union with smooth crease removal.
static inline float op_smooth_union(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

/// Smooth subtraction: carve b from a with a rounded indent.
static inline float op_smooth_subtract(float a, float b, float k) {
    float h = clamp(0.5 - 0.5 * (a + b) / k, 0.0, 1.0);
    return mix(a, -b, h) + k * h * (1.0 - h);
}

/// Smooth intersection: keep overlap, round the silhouette.
static inline float op_smooth_intersect(float a, float b, float k) {
    float h = clamp(0.5 - 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) + k * h * (1.0 - h);
}

// ─── Chamfer Boolean Operations ───────────────────────────────────────────────
// Produce a flat chamfer (45° bevel) instead of a smooth blend. Useful for
// hard-edge mechanical / architectural aesthetics.

/// Chamfer union: flat 45° bevel at the crease between two surfaces.
/// k = chamfer width.
static inline float op_chamfer_union(float a, float b, float k) {
    return min(min(a, b), (a - k + b) * 0.7071068);
}

/// Chamfer subtraction: flat 45° bevel on the carved edge.
static inline float op_chamfer_subtract(float a, float b, float k) {
    return max(max(a, -b), (a + k - b) * 0.7071068);
}

// ─── Step Union ───────────────────────────────────────────────────────────────

/// Step union: like smooth union but with a stair-step profile.
/// Produces a Lego-brick or rock-strata aesthetic.
/// k = step width.
static inline float op_step_union(float a, float b, float k) {
    float2 u = float2(b - a, a - b);
    u = max(u, 0.0);
    return min(a, b) + k * max(u.x - k, 0.0) / (u.x + 1e-6);
}

// ─── Multi-node Smooth Blend ──────────────────────────────────────────────────
// Generalises smooth union to blend N distances simultaneously.
// Equivalent to a smooth metaball / soft-body merge.

/// Smooth blend of 4 distances with radius k. Returns the blended minimum.
/// Based on the exponential softmin: result ≈ -k * log(Σ exp(-d/k)).
/// For Metal performance, approximated with the faster log-sum-exp via the
/// subtract-max trick to avoid overflow at large d values.
static inline float op_blend_4(float d0, float d1, float d2, float d3, float k) {
    float m   = min(min(d0, d1), min(d2, d3));
    float sum = exp((m - d0) / k)
              + exp((m - d1) / k)
              + exp((m - d2) / k)
              + exp((m - d3) / k);
    return m - k * log(sum);
}

/// Smooth blend of 8 distances (metaball generalization). Uses log-sum-exp.
static inline float op_blend_8(
    float d0, float d1, float d2, float d3,
    float d4, float d5, float d6, float d7,
    float k
) {
    float m   = min(min(min(d0, d1), min(d2, d3)), min(min(d4, d5), min(d6, d7)));
    float sum = exp((m - d0) / k) + exp((m - d1) / k)
              + exp((m - d2) / k) + exp((m - d3) / k)
              + exp((m - d4) / k) + exp((m - d5) / k)
              + exp((m - d6) / k) + exp((m - d7) / k);
    return m - k * log(sum);
}

/// Smooth blend where k → 0 gives hard union. Convenience wrapper that
/// degrades gracefully: at k < 0.001 returns min(a, b) to avoid exp overflow.
static inline float op_blend(float a, float b, float k) {
    if (k < 0.001) return min(a, b);
    float m   = min(a, b);
    float sum = exp((m - a) / k) + exp((m - b) / k);
    return m - k * log(sum);
}

// ─── Paint / Material-preserving Union ────────────────────────────────────────
// These variants return float2 where .x = distance and .y = material ID blend.
// Used when you need to interpolate material properties across a smooth union.

/// Material-preserving smooth union. Returns float2(distance, material).
/// matA, matB = material IDs (floats; typically integer IDs). Blend weight
/// follows the same polynomial curve as op_smooth_union.
static inline float2 op_smooth_union_mat(float a, float b, float k,
                                         float matA, float matB) {
    float h  = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    float d  = mix(b, a, h) - k * h * (1.0 - h);
    float m  = mix(matB, matA, h);
    return float2(d, m);
}

#pragma clang diagnostic pop
