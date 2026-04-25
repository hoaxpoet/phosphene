// SDFPrimitives.metal — 30 signed-distance-function primitives (V.2 Part A).
//
// All functions return exact (or conservative lower-bound) signed distances:
//   d < 0  → inside the surface
//   d = 0  → on the surface
//   d > 0  → outside the surface
//
// Lipschitz constant = 1 for all exact SDFs (|∇d| = 1 almost everywhere).
// Approximations are explicitly noted; see per-function headers.
//
// Naming convention: sd_<shape> — snake_case.
// Distinct from legacy ShaderUtilities.metal camelCase (sdSphere, sdBox, …)
// per D-045; no renaming of legacy functions required.
//
// Source: Inigo Quilez "3D SDF" https://iquilezles.org/articles/distfunctions/
//
// V.2 Pre-flight audit findings (2026-04-25):
//   • V.1 Noise (fbm8, worley3d, warped_fbm) confirmed in Utilities/Noise/.
//   • Legacy ShaderUtilities.metal functions are camelCase; no snake_case collisions.
//   • Legacy RayMarch helpers (rayMarch, calcNormal, calcAO, softShadow) are
//     static inline in ShaderUtilities.metal; Renderer/Shaders/RayMarch.metal
//     contains rm_* pipeline functions only. No conflicts with ray_march_adaptive.
//   • D-045 applied: snake_case new names coexist with camelCase legacy names.

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"

// ─── 1. Sphere ───────────────────────────────────────────────────────────────

/// Exact SDF for a sphere of radius r centred at the origin.
static inline float sd_sphere(float3 p, float r) {
    return length(p) - r;
}

// ─── 2. Box ──────────────────────────────────────────────────────────────────

/// Exact SDF for an axis-aligned box with half-extents b.
/// IQ box formula: accounts for corners, edges, and faces correctly.
static inline float sd_box(float3 p, float3 b) {
    float3 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}

// ─── 3. Rounded Box ──────────────────────────────────────────────────────────

/// Box with uniformly rounded edges/corners. r = rounding radius.
/// Equivalent to Minkowski sum of sd_box and sd_sphere.
static inline float sd_round_box(float3 p, float3 b, float r) {
    float3 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0) - r;
}

// ─── 4. Torus ────────────────────────────────────────────────────────────────

/// Exact SDF for a torus in the XZ plane.
/// t.x = major radius (centre → tube centre), t.y = tube radius.
static inline float sd_torus(float3 p, float2 t) {
    float2 q = float2(length(p.xz) - t.x, p.y);
    return length(q) - t.y;
}

// ─── 5. Capped Torus ─────────────────────────────────────────────────────────

/// Torus capped to a sector. sc = float2(sin(angle), cos(angle)) of half-arc,
/// ra = major radius, rb = tube radius. Sector opens in +X half-space.
static inline float sd_capped_torus(float3 p, float2 sc, float ra, float rb) {
    p.x = abs(p.x);
    float k = (sc.y * p.x > sc.x * p.y) ? dot(p.xy, sc) : length(p.xy);
    return sqrt(dot(p, p) + ra * ra - 2.0 * ra * k) - rb;
}

// ─── 6. Link (Chain Link) ────────────────────────────────────────────────────

/// Chain-link shape: cylinder with a torus cap. le = half-length of cylinder,
/// r1 = major torus radius, r2 = tube radius.
static inline float sd_link(float3 p, float le, float r1, float r2) {
    float3 q = float3(p.x, max(abs(p.y) - le, 0.0), p.z);
    return length(float2(length(q.xy) - r1, q.z)) - r2;
}

// ─── 7. Cylinder (axis-aligned, Y-axis) ──────────────────────────────────────

/// Exact SDF for a finite cylinder aligned to the Y axis, height 2h, radius r.
static inline float sd_cylinder(float3 p, float h, float r) {
    float2 d = abs(float2(length(p.xz), p.y)) - float2(r, h);
    return min(max(d.x, d.y), 0.0) + length(max(d, 0.0));
}

// ─── 8. Capped Cylinder (arbitrary axis) ─────────────────────────────────────

/// Cylinder between two points a and b with radius r. Exact SDF.
static inline float sd_capped_cylinder(float3 p, float3 a, float3 b, float r) {
    float3 ba = b - a;
    float3 pa = p - a;
    float baba = dot(ba, ba);
    float paba = dot(pa, ba);
    float x = length(pa * baba - ba * paba) / baba - r;
    float y = (abs(paba - baba * 0.5) - baba * 0.5) / baba;
    float x2 = x * x;
    float y2 = y * y * baba;
    float d = (max(x, y) < 0.0)
        ? -min(x2, y2)
        : (x > 0.0 ? x2 : 0.0) + (y > 0.0 ? y2 : 0.0);
    return sign(d) * sqrt(abs(d));
}

// ─── 9. Cone ─────────────────────────────────────────────────────────────────

/// Infinite cone. c = float2(sin(angle), cos(angle)) of half-aperture.
/// Tip at origin, extending in the +Y direction.
/// LIPSCHITZ NOTE: exact SDF away from tip; numerically stable for c.x < 0.99.
static inline float sd_cone(float3 p, float2 c) {
    float2 q = float2(length(p.xz), -p.y);
    float d = length(q - c * max(dot(q, c), 0.0));
    return d * ((q.x * c.y - q.y * c.x < 0.0) ? -1.0 : 1.0);
}

// ─── 10. Capped Cone ──────────────────────────────────────────────────────────

/// Finite cone between y=0 (radius r1) and y=h (radius r2). Exact SDF.
static inline float sd_capped_cone(float3 p, float h, float r1, float r2) {
    float2 q  = float2(length(p.xz), p.y);
    float2 k1 = float2(r2, h);
    float2 k2 = float2(r2 - r1, 2.0 * h);
    float2 ca = float2(q.x - min(q.x, (q.y < 0.0) ? r1 : r2), abs(q.y) - h);
    float2 cb = q - k1 + k2 * clamp(dot(k1 - q, k2) / dot(k2, k2), 0.0, 1.0);
    float  s  = (cb.x < 0.0 && ca.y < 0.0) ? -1.0 : 1.0;
    return s * sqrt(min(dot(ca, ca), dot(cb, cb)));
}

// ─── 11. Round Cone ───────────────────────────────────────────────────────────

/// Cone with spherically rounded ends. r1 = bottom radius, r2 = top radius,
/// h = height. Exact SDF.
static inline float sd_round_cone(float3 p, float r1, float r2, float h) {
    float2 q = float2(length(p.xz), p.y);
    float  b = (r1 - r2) / h;
    float  a = sqrt(1.0 - b * b);
    float  k = dot(q, float2(-b, a));
    if (k < 0.0) return length(q) - r1;
    if (k > a * h) return length(q - float2(0.0, h)) - r2;
    return dot(q, float2(a, b)) - r1;
}

// ─── 12. Plane ────────────────────────────────────────────────────────────────

/// Signed distance to an infinite plane defined by normal n (unit vector)
/// and offset h (distance from origin along n). Exact SDF.
static inline float sd_plane(float3 p, float3 n, float h) {
    return dot(p, n) + h;
}

// ─── 13. Capsule ──────────────────────────────────────────────────────────────

/// Capsule (sphere-swept line) between points a and b, radius r. Exact SDF.
static inline float sd_capsule(float3 p, float3 a, float3 b, float r) {
    float3 pa = p - a;
    float3 ba = b - a;
    float  h  = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - r;
}

// ─── 14. Hexagonal Prism ──────────────────────────────────────────────────────

/// Hexagonal prism aligned to Y axis. h.x = radial extent, h.y = half-height.
/// Exact SDF (in the XZ plane the hex is regular).
static inline float sd_hex_prism(float3 p, float2 h) {
    const float3 k = float3(-0.8660254, 0.5, 0.57735);
    float3 ap = abs(p);
    ap.x -= 2.0 * min(dot(k.xy, ap.xz), 0.0) * k.x;
    ap.z -= 2.0 * min(dot(k.xy, ap.xz), 0.0) * k.y;
    float2 d = float2(length(ap.xz - float2(clamp(ap.x, -k.z * h.x, k.z * h.x), h.x))
                      * sign(ap.z - h.x), ap.y - h.y);
    return min(max(d.x, d.y), 0.0) + length(max(d, 0.0));
}

// ─── 15. Triangular Prism ────────────────────────────────────────────────────

/// Triangular prism aligned to Y axis. h.x = radial size, h.y = half-height.
static inline float sd_tri_prism(float3 p, float2 h) {
    float3 q = abs(p);
    return max(q.y - h.y,
               max(q.x * 0.866025 + p.z * 0.5, -p.z) - h.x * 0.5);
}

// ─── 16. Octahedron ───────────────────────────────────────────────────────────

/// Exact SDF for a regular octahedron with "radius" s.
/// Vertices at (±s, 0, 0), (0, ±s, 0), (0, 0, ±s).
static inline float sd_octahedron(float3 p, float s) {
    float3 ap = abs(p);
    float  m  = ap.x + ap.y + ap.z - s;
    float3 r;
    if (3.0 * ap.x < m) {
        r = ap;
    } else if (3.0 * ap.y < m) {
        r = float3(ap.y, ap.x, ap.z);
    } else if (3.0 * ap.z < m) {
        r = float3(ap.z, ap.x, ap.y);
    } else {
        return m * 0.57735027;
    }
    float k = clamp(0.5 * (r.z - r.y + s), 0.0, s);
    return length(float3(r.x, r.y - s + k, r.z - k));
}

// ─── 17. Pyramid ──────────────────────────────────────────────────────────────

/// Square-base pyramid. Base is a 2×2 square in XZ at y=0; apex at y=h.
/// Exact SDF.
static inline float sd_pyramid(float3 p, float h) {
    float m2 = h * h + 0.25;
    float3 ap = p;
    ap.x = abs(ap.x);
    ap.z = abs(ap.z);
    if (ap.z > ap.x) { float t = ap.x; ap.x = ap.z; ap.z = t; }
    ap.x -= 0.5;
    ap.z -= 0.5;
    float3 q = float3(ap.z, h * ap.y - 0.5 * ap.x, h * ap.x + 0.5 * ap.y);
    float  s = max(-q.x, 0.0);
    float  t = clamp((q.y - 0.5 * ap.z) / (m2 + 0.25), 0.0, 1.0);
    float  a = m2 * (q.x + s) * (q.x + s) + q.y * q.y;
    float  b = m2 * (q.x + 0.5 * t) * (q.x + 0.5 * t) + (q.y - m2 * t) * (q.y - m2 * t);
    float  d = (min(q.y, -q.x * m2 - q.y * 0.5) > 0.0) ? 0.0 : min(a, b);
    return sqrt((d + q.z * q.z) / m2) * sign(max(q.z, -p.y));
}

// ─── 18. Ellipsoid ────────────────────────────────────────────────────────────

/// LIPSCHITZ NOTE: approximate lower bound, Lipschitz constant ≤ 1/min(r).
/// For r values differing by more than 2×, scale step size by 0.7 in the
/// ray marcher or use Conservative sphere tracing (Keinert 2014).
/// r = half-extents along each axis.
static inline float sd_ellipsoid(float3 p, float3 r) {
    float k0 = length(p / r);
    float k1 = length(p / (r * r));
    return k0 * (k0 - 1.0) / k1;
}

// ─── 19. Solid Angle ──────────────────────────────────────────────────────────

/// Solid angle (ice cream cone): sphere of radius ra with an angular cutout.
/// c = float2(sin, cos) of half-aperture angle. Axis along +Y. Exact SDF.
static inline float sd_solid_angle(float3 p, float2 c, float ra) {
    float2 q = float2(length(p.xz), p.y);
    float  l = length(q) - ra;
    float  m = length(q - c * clamp(dot(q, c), 0.0, ra));
    return max(l, m * sign(c.y * q.x - c.x * q.y));
}

// ─── 20. Arc ──────────────────────────────────────────────────────────────────

/// 2D arc in the XY plane extruded to 3D. sc = float2(sin, cos) of half-angle,
/// ra = arc radius (major), rb = tube radius. Exact SDF.
static inline float sd_arc(float3 p, float2 sc, float ra, float rb) {
    p.x = abs(p.x);
    float k = (sc.y * p.x > sc.x * p.y) ? dot(p.xy, sc) : length(p.xy);
    return sqrt(dot(p, p) + ra * ra - 2.0 * ra * k) - rb;
}

// ─── 21. Disk ─────────────────────────────────────────────────────────────────

/// Thin disk in XZ plane, radius r, half-thickness h. Exact SDF.
static inline float sd_disk(float3 p, float r, float h) {
    float2 d = float2(length(p.xz) - r, abs(p.y) - h);
    return min(max(d.x, d.y), 0.0) + length(max(d, 0.0));
}

// ─── 22. Triangle (3D) ───────────────────────────────────────────────────────

/// Exact SDF to the surface of a 3D triangle (a, b, c). Returns distance
/// to the nearest point on the triangle (vertex, edge, or face).
static inline float sd_triangle(float3 p, float3 a, float3 b, float3 c) {
    float3 ba = b - a; float3 pa = p - a;
    float3 cb = c - b; float3 pb = p - b;
    float3 ac = a - c; float3 pc = p - c;
    float3 nor = cross(ba, ac);
    return sqrt(
        (sign(dot(cross(ba, nor), pa)) +
         sign(dot(cross(cb, nor), pb)) +
         sign(dot(cross(ac, nor), pc)) < 2.0)
        ? min(min(
            dot(ba * clamp(dot(ba, pa) / dot(ba, ba), 0.0, 1.0) - pa,
                ba * clamp(dot(ba, pa) / dot(ba, ba), 0.0, 1.0) - pa),
            dot(cb * clamp(dot(cb, pb) / dot(cb, cb), 0.0, 1.0) - pb,
                cb * clamp(dot(cb, pb) / dot(cb, cb), 0.0, 1.0) - pb)),
            dot(ac * clamp(dot(ac, pc) / dot(ac, ac), 0.0, 1.0) - pc,
                ac * clamp(dot(ac, pc) / dot(ac, ac), 0.0, 1.0) - pc))
        : dot(nor, pa) * dot(nor, pa) / dot(nor, nor));
}

// ─── 23. Quad ────────────────────────────────────────────────────────────────

/// Exact SDF to a planar quad (four coplanar points a, b, c, d in order).
static inline float sd_quad(float3 p, float3 a, float3 b, float3 c, float3 d) {
    float3 ba = b - a; float3 pa = p - a;
    float3 cb = c - b; float3 pb = p - b;
    float3 dc = d - c; float3 pc = p - c;
    float3 ad = a - d; float3 pd = p - d;
    float3 nor = cross(ba, ad);
    return sqrt(
        (sign(dot(cross(ba, nor), pa)) +
         sign(dot(cross(cb, nor), pb)) +
         sign(dot(cross(dc, nor), pc)) +
         sign(dot(cross(ad, nor), pd)) < 3.0)
        ? min(min(min(
            dot(ba * clamp(dot(ba, pa) / dot(ba, ba), 0.0, 1.0) - pa,
                ba * clamp(dot(ba, pa) / dot(ba, ba), 0.0, 1.0) - pa),
            dot(cb * clamp(dot(cb, pb) / dot(cb, cb), 0.0, 1.0) - pb,
                cb * clamp(dot(cb, pb) / dot(cb, cb), 0.0, 1.0) - pb)),
            dot(dc * clamp(dot(dc, pc) / dot(dc, dc), 0.0, 1.0) - pc,
                dc * clamp(dot(dc, pc) / dot(dc, dc), 0.0, 1.0) - pc)),
            dot(ad * clamp(dot(ad, pd) / dot(ad, ad), 0.0, 1.0) - pd,
                ad * clamp(dot(ad, pd) / dot(ad, ad), 0.0, 1.0) - pd))
        : dot(nor, pa) * dot(nor, pa) / dot(nor, nor));
}

// ─── 24. Helix ────────────────────────────────────────────────────────────────

/// Approximate SDF for a helix around Y axis.
/// freq = turns per unit height, thickness = tube radius.
/// LIPSCHITZ NOTE: approximate; conservative scale 0.5 recommended in marcher.
static inline float sd_helix(float3 p, float freq, float thickness) {
    float angle = atan2(p.x, p.z);
    float wind  = p.y * freq * 6.28318;
    float phase = fmod(angle - wind + 31.4159, 6.28318) - 3.14159;
    float rxy   = length(p.xz);
    float r0    = 0.4;  // helix radius
    float2 q    = float2(rxy - r0, p.y - phase / (freq * 6.28318));
    return length(q) - thickness;
}

// ─── 25. Double Helix ────────────────────────────────────────────────────────

/// Two interleaved helices. Like sd_helix but with two strands π apart.
/// LIPSCHITZ NOTE: approximate; conservative scale 0.5 in marcher.
static inline float sd_double_helix(float3 p, float freq, float thickness, float twist) {
    float angle = atan2(p.x, p.z) + twist;
    float wind  = p.y * freq * 6.28318;
    // Strand A: 0 offset; Strand B: π offset
    float pA = fmod(angle - wind + 31.4159, 6.28318) - 3.14159;
    float pB = fmod(angle - wind + 34.5575, 6.28318) - 3.14159;
    float rxy = length(p.xz);
    float r0  = 0.3;
    float dA  = length(float2(rxy - r0, p.y - pA / (freq * 6.28318))) - thickness;
    float dB  = length(float2(rxy - r0, p.y - pB / (freq * 6.28318))) - thickness;
    return min(dA, dB);
}

// ─── 26. Gyroid ───────────────────────────────────────────────────────────────

/// Gyroid TPMS (triply periodic minimal surface) level set.
/// surface: cos(sx)sin(sy) + cos(sy)sin(sz) + cos(sz)sin(sx) = 0
/// scale controls cell period; thickness is the wall half-width.
/// LIPSCHITZ NOTE: level-set, not true SDF. Conservative scale = 0.3.
static inline float sd_gyroid(float3 p, float scale, float thickness) {
    float3 q = p * scale;
    float g = dot(cos(q), sin(float3(q.y, q.z, q.x)));
    return abs(g) / scale - thickness;
}

// ─── 27. Schwarz P Surface ────────────────────────────────────────────────────

/// Schwarz P TPMS: cos(x) + cos(y) + cos(z) = 0.
/// LIPSCHITZ NOTE: level-set. Conservative scale = 0.3.
static inline float sd_schwarz_p(float3 p, float scale, float thickness) {
    float3 q = p * scale;
    float s = cos(q.x) + cos(q.y) + cos(q.z);
    return abs(s) / scale - thickness;
}

// ─── 28. Schwarz D Surface ────────────────────────────────────────────────────

/// Schwarz D TPMS: sin(x)sin(y)sin(z) + sin(x)cos(y)cos(z)
///                + cos(x)sin(y)cos(z) + cos(x)cos(y)sin(z) = 0
/// LIPSCHITZ NOTE: level-set. Conservative scale = 0.25.
static inline float sd_schwarz_d(float3 p, float scale, float thickness) {
    float3 q = p * scale;
    float d = sin(q.x) * sin(q.y) * sin(q.z)
            + sin(q.x) * cos(q.y) * cos(q.z)
            + cos(q.x) * sin(q.y) * cos(q.z)
            + cos(q.x) * cos(q.y) * sin(q.z);
    return abs(d) / scale - thickness;
}

// ─── 29. Mandelbulb (Lipschitz-bounded iterate) ───────────────────────────────

/// Returns a conservative lower-bound SDF for the Mandelbulb of given power.
/// iters is capped at 8 for performance. Uses the Hubbard-Douady potential.
/// LIPSCHITZ NOTE: lower bound estimate only. Use small step scale (0.25–0.5)
/// and verify per-preset; set power=8 for the canonical Mandelbulb shape.
static inline float sd_mandelbulb_iterate(float3 p, float power, int iters) {
    float3 z    = p;
    float  dr   = 1.0;
    float  r    = 0.0;
    int    n    = min(iters, 8);
    for (int i = 0; i < n; i++) {
        r = length(z);
        if (r > 2.0) break;
        float theta = acos(z.z / r) * power;
        float phi   = atan2(z.y, z.x) * power;
        float rn    = pow(r, power);
        dr = rn * power * dr + 1.0;
        z  = rn * float3(sin(theta) * cos(phi),
                         sin(theta) * sin(phi),
                         cos(theta))
           + p;
    }
    return 0.5 * log(r) * r / dr;
}

// ─── 30. Regular Polygon Prism ───────────────────────────────────────────────

/// Regular n-gon prism extruded along Y axis. n = number of sides (3–16),
/// r = circumradius, h = half-height. Exact SDF.
/// Uses repeated reflection into the fundamental domain of the dihedral group.
static inline float sd_regular_polygon(float3 p, int n, float r, float h) {
    float  an  = 3.14159265 / float(n);
    float2 ecs = float2(cos(an), sin(an));
    float2 q   = abs(p.xz);
    float  bn  = floor(atan2(q.y, q.x) / an) * an;
    q = float2x2(cos(bn), -sin(bn), sin(bn), cos(bn)) * q;
    q -= float2(r * ecs.x, clamp(q.y, -r * ecs.y, r * ecs.y));
    float2 d = float2(length(max(abs(float2(q.x, p.y)) - float2(0, h), 0.0))
                      + min(max(q.x, abs(p.y) - h), 0.0),
                      -q.x);
    return (q.x < 0.0) ? d.y : d.x;
}

#pragma clang diagnostic pop
