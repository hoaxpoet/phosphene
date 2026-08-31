// SDFModifiers.metal — Domain-space modifiers for SDF composition (V.2 Part A).
//
// Modifiers transform the input point p before passing it to an SDF, enabling
// repetition, mirroring, twisting, and bending without duplicating geometry.
//
// Usage pattern:
//   float3 q = mod_twist(p, 0.5);          // transform domain
//   float  d = sd_sphere(q, 1.0);          // evaluate SDF in transformed domain
//
// Naming: mod_* — snake_case, distinct from legacy opRepeat/opTwist (camelCase).
// Source: Inigo Quilez https://iquilezles.org/articles/distfunctions/

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"

// ─── Repetition ───────────────────────────────────────────────────────────────

/// Infinite repetition along all three axes with period c.
/// Maps p into the nearest cell centre, enabling periodic SDF evaluation.
/// NOTE: the resulting SDF may not be Lipschitz-1 near cell boundaries
/// if the primitive extends beyond half the period. Keep primitive ≤ c/2.
static inline float3 mod_repeat(float3 p, float3 c) {
    return p - c * round(p / c);
}

/// Infinite repetition along a single axis (Y by default).
static inline float3 mod_repeat_y(float3 p, float c) {
    return float3(p.x, p.y - c * round(p.y / c), p.z);
}

/// Finite repetition along all axes: clamp cell index to [0, count-1].
/// count = number of cells per axis. Safe for up to 8 cells per axis
/// before floating-point precision issues arise at large distances.
/// NOTE: count must be ≥ 1.
static inline float3 mod_repeat_finite(float3 p, float3 period, int3 count) {
    float3 halfCount = float3(count - 1) * 0.5;
    float3 idx       = round(p / period);
    idx = clamp(idx, -halfCount, halfCount);
    return p - period * idx;
}

/// Finite repetition along Y axis only. count = number of cells.
static inline float3 mod_repeat_finite_y(float3 p, float period, int count) {
    float hc  = float(count - 1) * 0.5;
    float idx = clamp(round(p.y / period), -hc, hc);
    return float3(p.x, p.y - period * idx, p.z);
}

// ─── Mirroring ────────────────────────────────────────────────────────────────

/// Mirror across the XZ plane (fold along Y = 0).
static inline float3 mod_mirror_y(float3 p) {
    return float3(p.x, abs(p.y), p.z);
}

/// Mirror across all three planes (octant symmetry: folds into +++ octant).
static inline float3 mod_mirror_xyz(float3 p) {
    return abs(p);
}

/// Mirror across an arbitrary axis: reflect p into the half-space where
/// dot(p, axis) ≥ 0. axis must be unit length.
static inline float3 mod_mirror(float3 p, float3 axis) {
    float d = dot(p, axis);
    return p - 2.0 * min(d, 0.0) * axis;
}

// ─── Twist ────────────────────────────────────────────────────────────────────

/// Twist geometry around the Y axis by k radians per unit height.
/// Lifschitz NOTE: twisting is not distance-preserving; the resulting
/// SDF may overestimate. Use conservative step scale ≈ 1/(1 + |k| * R)
/// where R is the approximate radial extent of the geometry.
static inline float3 mod_twist(float3 p, float k) {
    float c = cos(k * p.y);
    float s = sin(k * p.y);
    float2 q = float2x2(c, -s, s, c) * p.xz;
    return float3(q.x, p.y, q.y);  // preserve y; q.x→x, q.y→z
}

// ─── Bend ─────────────────────────────────────────────────────────────────────

/// Bend geometry along the X axis with curvature k (radians per unit X).
/// Lifschitz NOTE: bending is not distance-preserving. Conservative scale:
/// 1/(1 + |k| * bounding_radius).
static inline float3 mod_bend(float3 p, float k) {
    float c = cos(k * p.x);
    float s = sin(k * p.x);
    float2 q = float2x2(c, -s, s, c) * p.xy;
    return float3(q, p.z);
}

// ─── Scale ────────────────────────────────────────────────────────────────────

/// Uniform scale: evaluate SDF at p/s then multiply result by s.
/// Returns the domain point to use; caller must multiply SDF result by scale.
/// Pattern: float q = mod_scale_uniform(p, 2.0); return sd_sphere(q, 1.0) * 2.0;
static inline float3 mod_scale_uniform(float3 p, float s) {
    return p / s;
}

/// Anisotropic scale along each axis. Breaks Lipschitz-1 for non-uniform s.
/// Caller must divide SDF result by min(s.x, min(s.y, s.z)) to compensate.
static inline float3 mod_scale_anisotropic(float3 p, float3 s) {
    return p / s;
}

// ─── Rounding and Onion ───────────────────────────────────────────────────────

/// Round (inflate) a surface by r: pushes the zero-level outward.
/// Applies to any SDF: sd_round = baseSDF(p) - r.
/// Combine with sd_box to get sd_round_box equivalently.
static inline float mod_round(float d, float r) {
    return d - r;
}

/// Onion shell: hollow out a surface to thickness t.
/// Creates a shell at distance ±t/2 from the original surface.
static inline float mod_onion(float d, float t) {
    return abs(d) - t;
}

// ─── Extrusion and Revolution ─────────────────────────────────────────────────

/// Extrude a 2D SDF d2 (in XY plane) along Z by half-height h.
/// d2 must be the signed distance to the 2D shape in the XY plane.
static inline float mod_extrude(float3 p, float d2, float h) {
    float2 w = float2(d2, abs(p.z) - h);
    return min(max(w.x, w.y), 0.0) + length(max(w, 0.0));
}

/// Revolve a 2D profile (defined in XZ plane) around the Y axis.
/// Returns the modified 3D point and radius for the revolution.
/// Usage: float3 q = mod_revolve(p, offset); d = sdf2D(q.xy);
static inline float3 mod_revolve(float3 p, float offset) {
    return float3(length(p.xz) - offset, p.y, 0.0);
}

#pragma clang diagnostic pop
