// Perlin.metal — Classic gradient Perlin noise in 2D, 3D, and 4D.
//
// Uses the improved (2002) fade function 6t^5 - 15t^4 + 10t^3 for C2 continuity.
// Output range: approximately [-1, 1] (slightly tighter in practice: ~[-0.9, 0.9]).
//
// Depends on: Hash.metal (hash_grad2, hash_grad3, hash_grad4)
//
// DO NOT add #include <metal_stdlib> or using namespace metal.

// ─── 2D gradient Perlin noise ─────────────────────────────────────────────────

/// C2-continuous improved Perlin noise in 2D.
/// Output: approximately [-1, 1].
static inline float perlin2d(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);

    // C2 quintic fade (Perlin 2002): 6t^5 - 15t^4 + 10t^3
    float2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);

    // Lattice corner gradients.
    float2 g00 = hash_grad2(int2(i) + int2(0, 0));
    float2 g10 = hash_grad2(int2(i) + int2(1, 0));
    float2 g01 = hash_grad2(int2(i) + int2(0, 1));
    float2 g11 = hash_grad2(int2(i) + int2(1, 1));

    // Gradient contribution: dot(gradient, offset from corner).
    float n00 = dot(g00, f - float2(0.0, 0.0));
    float n10 = dot(g10, f - float2(1.0, 0.0));
    float n01 = dot(g01, f - float2(0.0, 1.0));
    float n11 = dot(g11, f - float2(1.0, 1.0));

    // Bilinear interpolation with fade weights.
    return mix(mix(n00, n10, u.x), mix(n01, n11, u.x), u.y);
}

// ─── 3D gradient Perlin noise ─────────────────────────────────────────────────

/// C2-continuous improved Perlin noise in 3D.
/// Output: approximately [-1, 1].
static inline float perlin3d(float3 p) {
    float3 i = floor(p);
    float3 f = fract(p);

    // C2 quintic fade.
    float3 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);

    // 8 corner gradients.
    float3 g000 = hash_grad3(int3(i) + int3(0, 0, 0));
    float3 g100 = hash_grad3(int3(i) + int3(1, 0, 0));
    float3 g010 = hash_grad3(int3(i) + int3(0, 1, 0));
    float3 g110 = hash_grad3(int3(i) + int3(1, 1, 0));
    float3 g001 = hash_grad3(int3(i) + int3(0, 0, 1));
    float3 g101 = hash_grad3(int3(i) + int3(1, 0, 1));
    float3 g011 = hash_grad3(int3(i) + int3(0, 1, 1));
    float3 g111 = hash_grad3(int3(i) + int3(1, 1, 1));

    float n000 = dot(g000, f - float3(0, 0, 0));
    float n100 = dot(g100, f - float3(1, 0, 0));
    float n010 = dot(g010, f - float3(0, 1, 0));
    float n110 = dot(g110, f - float3(1, 1, 0));
    float n001 = dot(g001, f - float3(0, 0, 1));
    float n101 = dot(g101, f - float3(1, 0, 1));
    float n011 = dot(g011, f - float3(0, 1, 1));
    float n111 = dot(g111, f - float3(1, 1, 1));

    // Trilinear interpolation.
    float n00 = mix(n000, n100, u.x);
    float n01 = mix(n010, n110, u.x);
    float n10 = mix(n001, n101, u.x);
    float n11 = mix(n011, n111, u.x);
    float n0  = mix(n00, n01, u.y);
    float n1  = mix(n10, n11, u.y);
    return mix(n0, n1, u.z);
}

// ─── 4D gradient Perlin noise ─────────────────────────────────────────────────

/// C2-continuous improved Perlin noise in 4D.
/// The fourth dimension is ideal for animated 3D fields: perlin4d(float4(p, time)).
/// Output: approximately [-1, 1].
static inline float perlin4d(float4 p) {
    float4 i = floor(p);
    float4 f = fract(p);

    // C2 quintic fade.
    float4 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);

    // 16 corner gradients (4D hypercube).
    float4 g0000 = hash_grad4(int4(i) + int4(0,0,0,0));
    float4 g1000 = hash_grad4(int4(i) + int4(1,0,0,0));
    float4 g0100 = hash_grad4(int4(i) + int4(0,1,0,0));
    float4 g1100 = hash_grad4(int4(i) + int4(1,1,0,0));
    float4 g0010 = hash_grad4(int4(i) + int4(0,0,1,0));
    float4 g1010 = hash_grad4(int4(i) + int4(1,0,1,0));
    float4 g0110 = hash_grad4(int4(i) + int4(0,1,1,0));
    float4 g1110 = hash_grad4(int4(i) + int4(1,1,1,0));
    float4 g0001 = hash_grad4(int4(i) + int4(0,0,0,1));
    float4 g1001 = hash_grad4(int4(i) + int4(1,0,0,1));
    float4 g0101 = hash_grad4(int4(i) + int4(0,1,0,1));
    float4 g1101 = hash_grad4(int4(i) + int4(1,1,0,1));
    float4 g0011 = hash_grad4(int4(i) + int4(0,0,1,1));
    float4 g1011 = hash_grad4(int4(i) + int4(1,0,1,1));
    float4 g0111 = hash_grad4(int4(i) + int4(0,1,1,1));
    float4 g1111 = hash_grad4(int4(i) + int4(1,1,1,1));

    float n0000 = dot(g0000, f - float4(0,0,0,0));
    float n1000 = dot(g1000, f - float4(1,0,0,0));
    float n0100 = dot(g0100, f - float4(0,1,0,0));
    float n1100 = dot(g1100, f - float4(1,1,0,0));
    float n0010 = dot(g0010, f - float4(0,0,1,0));
    float n1010 = dot(g1010, f - float4(1,0,1,0));
    float n0110 = dot(g0110, f - float4(0,1,1,0));
    float n1110 = dot(g1110, f - float4(1,1,1,0));
    float n0001 = dot(g0001, f - float4(0,0,0,1));
    float n1001 = dot(g1001, f - float4(1,0,0,1));
    float n0101 = dot(g0101, f - float4(0,1,0,1));
    float n1101 = dot(g1101, f - float4(1,1,0,1));
    float n0011 = dot(g0011, f - float4(0,0,1,1));
    float n1011 = dot(g1011, f - float4(1,0,1,1));
    float n0111 = dot(g0111, f - float4(0,1,1,1));
    float n1111 = dot(g1111, f - float4(1,1,1,1));

    // 4-linear interpolation across the hypercube.
    float n000 = mix(n0000, n1000, u.x);
    float n100 = mix(n0100, n1100, u.x);
    float n010 = mix(n0010, n1010, u.x);
    float n110 = mix(n0110, n1110, u.x);
    float n001 = mix(n0001, n1001, u.x);
    float n101 = mix(n0101, n1101, u.x);
    float n011 = mix(n0011, n1011, u.x);
    float n111 = mix(n0111, n1111, u.x);

    float n00 = mix(n000, n100, u.y);
    float n10 = mix(n010, n110, u.y);
    float n01 = mix(n001, n101, u.y);
    float n11 = mix(n011, n111, u.y);

    float n0 = mix(n00, n10, u.z);
    float n1 = mix(n01, n11, u.z);

    return mix(n0, n1, u.w);
}
