// Simplex.metal — Ken Perlin's simplex noise in 3D and 4D.
//
// Simplex noise uses a tetrahedral (3D) or 5-cell (4D) lattice rather than a
// hypercubic one, giving better isotropy and fewer gradient alignment artifacts.
// Preferred over classic Perlin when isotropy matters (volumes, flow fields).
//
// Reference: Stefan Gustavson, "Simplex Noise Demystified" (2005).
//
// Depends on: Hash.metal (hash_grad3, hash_grad4)
//
// DO NOT add #include <metal_stdlib> or using namespace metal.

// ─── 3D simplex noise ─────────────────────────────────────────────────────────

/// Simplex noise in 3D. Tetrahedral lattice, good isotropy.
/// Output: approximately [-1, 1].
static inline float simplex3d(float3 v) {
    // Skewing/unskewing factors for 3D simplex.
    const float F3 = 1.0 / 3.0;  // (sqrt(4) - 1) / 3 = 1/3
    const float G3 = 1.0 / 6.0;  // (1 - 1/sqrt(4)) / 3 = 1/6

    // Skew input space to determine which simplex cell.
    float s  = (v.x + v.y + v.z) * F3;
    float3 i = floor(v + s);

    float t  = (i.x + i.y + i.z) * G3;
    float3 x0 = v - i + t;   // unskewed first corner

    // Determine simplex tetrahedron from relative position.
    float3 e = step(x0.yzx, x0.xyz);   // which axes are dominant
    float3 i1 = e * (1.0 - e.zxy);     // first step vertex
    float3 i2 = 1.0 - e.zxy * (1.0 - e); // second step vertex

    float3 x1 = x0 - i1 + G3;
    float3 x2 = x0 - i2 + 2.0 * G3;
    float3 x3 = x0 - 1.0 + 3.0 * G3;

    // Gradient contributions.
    float3 g0 = hash_grad3(int3(i));
    float3 g1 = hash_grad3(int3(i) + int3(i1));
    float3 g2 = hash_grad3(int3(i) + int3(i2));
    float3 g3 = hash_grad3(int3(i) + int3(1, 1, 1));

    // Kernel falloff: max(0, r^2 - |x|^2)^4
    float4 m = max(0.6 - float4(dot(x0,x0), dot(x1,x1), dot(x2,x2), dot(x3,x3)), 0.0);
    m = m * m;
    m = m * m;

    float4 gdot = float4(dot(g0,x0), dot(g1,x1), dot(g2,x2), dot(g3,x3));
    return 32.0 * dot(m, gdot);
}

// ─── 4D simplex noise ─────────────────────────────────────────────────────────

/// Simplex noise in 4D. 5-cell (pentatope) lattice.
/// The fourth dimension is ideal for animated 3D fields: simplex4d(float4(p, time)).
/// Output: approximately [-1, 1].
static inline float simplex4d(float4 v) {
    // Skewing/unskewing factors for 4D simplex (sqrt(5) geometry).
    const float F4 = (sqrt(5.0) - 1.0) * 0.25;  // 0.3090169944
    const float G4 = (5.0 - sqrt(5.0)) * 0.05;  // 0.1381966012

    // Skew to 4D integer space.
    float s  = (v.x + v.y + v.z + v.w) * F4;
    float4 i = floor(v + s);

    float t   = (i.x + i.y + i.z + i.w) * G4;
    float4 x0 = v - i + t;

    // Sort the components of x0 to traverse the simplex correctly.
    // rank[k] = number of components of x0 with magnitude > x0[k].
    float4 rank = step(x0.yzwx, x0.xyzw) + step(x0.zwxy, x0.xyzw) + step(x0.wxyz, x0.xyzw);

    // Simplex vertices: rank indicates which axes cross a unit step first.
    float4 i1 = clamp(rank - 2.0, 0.0, 1.0);
    float4 i2 = clamp(rank - 1.0, 0.0, 1.0);
    float4 i3 = clamp(rank,       0.0, 1.0);

    float4 x1 = x0 - i1 + G4;
    float4 x2 = x0 - i2 + 2.0 * G4;
    float4 x3 = x0 - i3 + 3.0 * G4;
    float4 x4 = x0 - 1.0 + 4.0 * G4;

    // 5 gradient contributions.
    float4 g0 = hash_grad4(int4(i));
    float4 g1 = hash_grad4(int4(i) + int4(i1));
    float4 g2 = hash_grad4(int4(i) + int4(i2));
    float4 g3 = hash_grad4(int4(i) + int4(i3));
    float4 g4 = hash_grad4(int4(i) + int4(1, 1, 1, 1));

    // Kernel falloff: max(0, r^2 - |x|^2)^4 (5 separate scalars, no float5 in MSL)
    float m0 = max(0.6 - dot(x0,x0), 0.0); m0 *= m0; m0 *= m0;
    float m1 = max(0.6 - dot(x1,x1), 0.0); m1 *= m1; m1 *= m1;
    float m2 = max(0.6 - dot(x2,x2), 0.0); m2 *= m2; m2 *= m2;
    float m3 = max(0.6 - dot(x3,x3), 0.0); m3 *= m3; m3 *= m3;
    float m4 = max(0.6 - dot(x4,x4), 0.0); m4 *= m4; m4 *= m4;

    return 27.0 * (m0*dot(g0,x0) + m1*dot(g1,x1) + m2*dot(g2,x2)
                 + m3*dot(g3,x3) + m4*dot(g4,x4));
}
