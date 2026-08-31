// Worley.metal — Cellular / Voronoi noise in 2D and 3D.
//
// Returns F1 (nearest cell distance) and F2 (second-nearest) for feature-based
// surfaces: stones, cells, crack networks, organic tissue.
// Also provides worley_fbm: a Worley-Perlin blend for marble and granite.
//
// Depends on: Hash.metal (hash_f01_2x, hash_f01_3x)
// worley_fbm also depends on FBM.metal (fbm8) — only include after FBM.metal.
// (worley_fbm is defined at the bottom with a note about load order.)
//
// DO NOT add #include <metal_stdlib> or using namespace metal.

// ─── 2D Worley noise ─────────────────────────────────────────────────────────

/// 2D Worley (cellular/Voronoi) noise.
/// Returns float2(F1, F2) — distances to the nearest and second-nearest cell centers.
/// F1 in [0, ~0.7], F2 in [F1, ~1.1] (exact max depends on cell density).
static inline float2 worley2d(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);

    float F1 = 1.5;   // start larger than max possible distance in 3×3 grid
    float F2 = 1.5;

    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            float2 cell = float2(float(x), float(y));
            float2 offset = hash_f01_2x(i + cell);   // feature point offset in [0,1)²
            float2 diff   = cell + offset - f;
            float  dist   = dot(diff, diff);           // squared distance for efficiency

            if (dist < F1) { F2 = F1; F1 = dist; }
            else if (dist < F2) { F2 = dist; }
        }
    }
    return float2(sqrt(F1), sqrt(F2));
}

// ─── 3D Worley noise ─────────────────────────────────────────────────────────

/// 3D Worley (cellular/Voronoi) noise.
/// Returns float3(F1, F2, cell_hash) where cell_hash is a unique float in [0,1)
/// identifying the nearest cell (useful for per-cell color variation).
static inline float3 worley3d(float3 p) {
    float3 i = floor(p);
    float3 f = fract(p);

    float F1 = 2.0;
    float F2 = 2.0;
    float cell_hash = 0.0;

    for (int z = -1; z <= 1; z++) {
        for (int y = -1; y <= 1; y++) {
            for (int x = -1; x <= 1; x++) {
                float3 cell   = float3(float(x), float(y), float(z));
                float3 offset = hash_f01_3x(i + cell);
                float3 diff   = cell + offset - f;
                float  dist   = dot(diff, diff);

                if (dist < F1) {
                    F2 = F1;
                    F1 = dist;
                    // Cell identity: hash of the integer cell coordinates.
                    cell_hash = hash_f01(hash_u32_3(uint3(int3(i) + int3(x,y,z))));
                } else if (dist < F2) {
                    F2 = dist;
                }
            }
        }
    }
    return float3(sqrt(F1), sqrt(F2), cell_hash);
}

// ─── Worley-fBM blend ─────────────────────────────────────────────────────────

// NOTE: worley_fbm calls fbm8(), which is defined in FBM.metal.
// The load order in PresetLoader+Preamble.swift places FBM.metal BEFORE Worley.metal
// (Hash → Perlin → Simplex → FBM → RidgedMultifractal → Worley → DomainWarp → Curl → BlueNoise),
// so fbm8 is guaranteed to be defined when the compiler reaches worley_fbm.

/// Blend Worley F1 with fBM for marble, granite, and stone surfaces.
/// `p` should be scaled to your surface scale (try p * 2.0 for granite).
static inline float worley_fbm(float3 p) {
    float w = worley3d(p * 2.0).x;   // F1 distance
    float f = fbm8(p);
    return mix(f, w, 0.35);
}
