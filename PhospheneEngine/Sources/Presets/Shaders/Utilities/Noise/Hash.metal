// Hash.metal — Foundation hash functions for all Noise utilities.
//
// Every other Noise file depends on these functions, so this file must be
// concatenated FIRST in the Noise utility block.
//
// Uses PCG-inspired integer mixing for good distribution quality and speed.
// All functions are static inline to allow dead-code elimination and avoid
// symbol conflicts across independent preset compilation units.
//
// DO NOT add #include <metal_stdlib> or using namespace metal —
// these are already provided by the preamble.

// ─── Integer hashes ──────────────────────────────────────────────────────────

/// 32-bit integer hash (PCG-style mixing). Fast, good distribution.
static inline uint hash_u32(uint x) {
    x ^= x >> 17u;
    x *= 0xBF324C81u;
    x ^= x >> 11u;
    x *= 0x68BC4E25u;
    x ^= x >> 16u;
    return x;
}

/// 2D integer pair → 32-bit hash.
static inline uint hash_u32_2(uint2 p) {
    uint h = p.x * 1664525u + p.y * 22695477u + 1013904223u;
    return hash_u32(h);
}

/// 3D integer triple → 32-bit hash.
static inline uint hash_u32_3(uint3 p) {
    uint h = p.x * 1664525u ^ p.y * 22695477u ^ p.z * 2246822519u;
    return hash_u32(h);
}

// ─── Float hashes in [0, 1) ───────────────────────────────────────────────────

/// Integer seed → float in [0, 1).
static inline float hash_f01(uint x) {
    return float(hash_u32(x)) * (1.0 / 4294967296.0);
}

/// float2 lattice point → float in [0, 1). Floors before hashing.
static inline float hash_f01_2(float2 p) {
    int2 ip = int2(floor(p));
    return hash_f01(hash_u32_2(uint2(ip)));
}

/// float3 lattice point → float in [0, 1). Floors before hashing.
static inline float hash_f01_3(float3 p) {
    int3 ip = int3(floor(p));
    return hash_f01(hash_u32_3(uint3(ip)));
}

// ─── Vector hashes in [0, 1) ─────────────────────────────────────────────────

/// float2 → float2 in [0, 1)² (cell-feature-point offset).
static inline float2 hash_f01_2x(float2 p) {
    int2 ip = int2(floor(p));
    uint base = hash_u32_2(uint2(ip));
    return float2(hash_f01(base), hash_f01(base ^ 0x9E3779B9u));
}

/// float3 → float3 in [0, 1)³ (cell-feature-point offset).
static inline float3 hash_f01_3x(float3 p) {
    int3 ip = int3(floor(p));
    uint base = hash_u32_3(uint3(ip));
    return float3(
        hash_f01(base),
        hash_f01(base ^ 0x9E3779B9u),
        hash_f01(base ^ 0x6C62272Eu)
    );
}

/// float4 → float4 in [0, 1)⁴.
static inline float4 hash_f01_4x(float4 p) {
    int4 ip = int4(floor(p));
    uint h0 = hash_u32(uint(ip.x) * 1664525u ^ uint(ip.y) * 22695477u);
    uint h1 = hash_u32(uint(ip.z) * 2246822519u ^ uint(ip.w) * 1013904223u);
    uint base = hash_u32(h0 ^ h1);
    return float4(
        hash_f01(base),
        hash_f01(base ^ 0x9E3779B9u),
        hash_f01(base ^ 0x6C62272Eu),
        hash_f01(base ^ 0xDEADBEEFu)
    );
}

// ─── Gradient hashes (unit vectors) ──────────────────────────────────────────

/// int2 lattice point → unit gradient vector in 2D (for gradient Perlin noise).
static inline float2 hash_grad2(int2 p) {
    uint h = hash_u32_2(uint2(p));
    float angle = float(h) * (6.28318530718 / 4294967296.0);
    return float2(cos(angle), sin(angle));
}

/// int3 lattice point → unit gradient vector in 3D (for gradient Perlin noise).
/// Uses spherical coordinates for an approximately uniform distribution.
static inline float3 hash_grad3(int3 p) {
    uint h = hash_u32_3(uint3(p));
    // Split hash into azimuth (full circle) and elevation (upper hemisphere only,
    // then mirrored for full sphere distribution).
    float phi   = float(h & 0xFFFFu)  * (6.28318530718 / 65536.0);
    float theta = float(h >> 16u)     * (3.14159265359 / 65536.0);
    float st = sin(theta), ct = cos(theta);
    float sp = sin(phi),   cp = cos(phi);
    return float3(st * cp, st * sp, ct);
}

/// int4 lattice point → unit gradient vector in 4D (for 4D simplex noise).
static inline float4 hash_grad4(int4 p) {
    uint h = hash_u32(uint(p.x) * 1664525u ^ uint(p.y) * 22695477u
                    ^ uint(p.z) * 2246822519u ^ uint(p.w) * 1013904223u);
    // Build from two spherical coordinates to span 4D unit sphere.
    float phi1  = float(h & 0xFFu) * (6.28318530718 / 256.0);
    float phi2  = float((h >> 8u) & 0xFFu) * (6.28318530718 / 256.0);
    float theta = float((h >> 16u) & 0xFFFFu) * (3.14159265359 / 65536.0);
    float st = sin(theta), ct = cos(theta);
    return float4(
        st * cos(phi1),
        st * sin(phi1),
        ct * cos(phi2),
        ct * sin(phi2)
    );
}
