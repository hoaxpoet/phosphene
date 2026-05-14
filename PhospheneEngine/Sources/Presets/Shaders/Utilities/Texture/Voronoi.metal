// Voronoi.metal — Voronoi / Worley cell pattern utilities (V.2 Part C).
//
// Provides F1, F2, and hybrid Voronoi distance functions for cellular patterns,
// crack networks, organic cell structures, and leather-like surface detail.
//
// Distinct from the Worley noise in V.1 (which targets FBM-combined noise fields).
// These utilities expose raw F1/F2 geometry for use in material recipes and SDF
// displacement fields.
//
// Usage:
//   VoronoiResult v = voronoi_f1f2(p.xz, 4.0);
//   float cracks = smoothstep(0.0, 0.05, v.f2 - v.f1);   // crack lines at boundaries
//   float cells  = v.f1;                                   // cell interior shading

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"

// ─── Result Type ──────────────────────────────────────────────────────────────

/// Voronoi result: F1 = distance to nearest cell, F2 = distance to second nearest.
/// id = integer hash of the nearest cell (use for per-cell color / offset).
struct VoronoiResult {
    float f1;   // nearest-cell distance
    float f2;   // second-nearest-cell distance
    int   id;   // hash of nearest cell
    float2 pos; // nearest cell centre (in local space)
};

// ─── Internal Cell Hash ───────────────────────────────────────────────────────

static inline int2 voronoi_hash_int(int2 cell) {
    int2 q = int2(cell.x * 1453 + cell.y * 2971, cell.x * 3539 + cell.y * 1117);
    q = (q ^ (q >> 9)) * 0x45d9f3b;
    return q;
}

static inline float2 voronoi_cell_offset(int2 cell) {
    int2 h = voronoi_hash_int(cell);
    return float2(float(h.x & 0xffff), float(h.y & 0xffff)) / 65535.0;
}

static inline int voronoi_cell_id(int2 cell) {
    int2 h = voronoi_hash_int(cell);
    return h.x ^ h.y;
}

// ─── 2D Voronoi F1 + F2 ───────────────────────────────────────────────────────

/// Full 2D Voronoi: returns F1, F2, nearest cell id and position.
/// p = 2D input point. scale = cell density.
static inline VoronoiResult voronoi_f1f2(float2 p, float scale) {
    float2 sp  = p * scale;
    float2 i   = floor(sp);
    float2 f   = fract(sp);

    VoronoiResult r;
    r.f1  = 1e5; r.f2 = 1e5;
    r.id  = 0;
    r.pos = float2(0.0);

    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            int2   cell   = int2(i) + int2(dx, dy);
            float2 offset = voronoi_cell_offset(cell);
            float2 r_vec  = float2(dx, dy) + offset - f;
            float  dist   = dot(r_vec, r_vec);   // squared distance
            if (dist < r.f1) {
                r.f2  = r.f1;
                r.f1  = dist;
                r.id  = voronoi_cell_id(cell);
                r.pos = (i + float2(cell)) * (1.0 / scale) + offset / scale;
            } else if (dist < r.f2) {
                r.f2 = dist;
            }
        }
    }
    r.f1 = sqrt(r.f1);
    r.f2 = sqrt(r.f2);
    return r;
}

// ─── 2D Smooth Voronoi ────────────────────────────────────────────────────────

/// Smooth Voronoi (Inigo Quilez): soft-min of distances to neighbor cell
/// centres using exponential blending. Replaces the hard `min()` of regular
/// Voronoi with a weighted sum so the output is C¹-continuous across cell
/// boundaries. Useful for height fields and other geometry where the
/// regular Voronoi's discontinuous gradient at cell boundaries causes
/// shading artifacts (sharp normal flips, aliased crease lines).
///
/// Formula: `-(1/k) × log₂(Σ exp₂(-k × dᵢ))` over the 9 neighbor cells.
/// As k → ∞ the function approaches regular Voronoi (sharp); as k → 0 it
/// approaches the unweighted mean distance (smooth blob field). Quilez's
/// reference uses k = 32 for visible cells with smooth boundaries.
///
/// Returns the smoothed distance in scaled-space units (same convention
/// as `voronoi_f1f2.f1`). Divide by `scale` to convert to world space.
///
/// Reference: https://iquilezles.org/articles/smoothvoronoi/
static inline float voronoi_smooth(float2 p, float scale, float k) {
    float2 sp = p * scale;
    float2 i  = floor(sp);
    float2 f  = fract(sp);
    float res = 0.0;
    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            int2   cell   = int2(i) + int2(dx, dy);
            float2 offset = voronoi_cell_offset(cell);
            float2 r_vec  = float2(dx, dy) + offset - f;
            float  d      = length(r_vec);
            res += exp2(-k * d);
        }
    }
    return -(1.0 / k) * log2(res);
}

// ─── 3D Voronoi ──────────────────────────────────────────────────────────────

/// 3D Voronoi F1 distance only (cheaper than F1+F2 in 3D due to 27-cell lookup).
static inline float voronoi_3d_f1(float3 p, float scale) {
    float3 sp = p * scale;
    float3 i  = floor(sp);
    float3 fr = fract(sp);
    float  minD = 1e5;

    for (int dz = -1; dz <= 1; dz++) {
        for (int dy = -1; dy <= 1; dy++) {
            for (int dx = -1; dx <= 1; dx++) {
                float3 neighbor = float3(dx, dy, dz);
                // Hash 3D cell.
                int3   ci = int3(i) + int3(dx, dy, dz);
                int    h  = ci.x * 1453 + ci.y * 2971 + ci.z * 4637;
                h = (h ^ (h >> 9)) * 0x45d9f3b;
                float3 offset = float3(
                    float(h & 0xffff),
                    float((h >> 8) & 0xffff),
                    float((h >> 16) & 0xffff)
                ) / 65535.0;
                float3 r_vec = neighbor + offset - fr;
                minD = min(minD, dot(r_vec, r_vec));
            }
        }
    }
    return sqrt(minD);
}

// ─── Derived Patterns ────────────────────────────────────────────────────────

/// Crack network: thin lines at Voronoi cell boundaries.
/// width = crack width in Voronoi-distance units (0.02–0.08).
static inline float voronoi_cracks(float2 p, float scale, float width) {
    VoronoiResult v = voronoi_f1f2(p, scale);
    return smoothstep(0.0, width, v.f2 - v.f1);
}

/// Leather-tile pattern: F1-based shading with polished peak at cell centres.
/// Returns albedo-modulation factor [0,1].
static inline float voronoi_leather(float2 p, float scale) {
    VoronoiResult v = voronoi_f1f2(p, scale);
    float cell = smoothstep(0.0, 0.5, v.f1);
    float seam = 1.0 - smoothstep(0.0, 0.04, v.f2 - v.f1);
    return clamp(cell - seam * 0.5, 0.0, 1.0);
}

/// Hex-like organic cell shading: bright at centres, dark at boundaries.
static inline float voronoi_cells(float2 p, float scale) {
    VoronoiResult v = voronoi_f1f2(p, scale);
    return 1.0 - smoothstep(0.0, 0.6, v.f1);
}

#pragma clang diagnostic pop
