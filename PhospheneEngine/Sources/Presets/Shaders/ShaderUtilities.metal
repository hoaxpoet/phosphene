// ShaderUtilities.metal — Reusable shader functions for all presets.
//
// This file is included in the PresetLoader preamble, so every runtime-compiled
// preset shader has access to these functions without explicit imports.
//
// DO NOT add #include <metal_stdlib> or using namespace metal — these are
// already provided by the preamble.
//
// All functions are static inline to avoid symbol collision between
// independent preset compilation units and to enable dead-code elimination.
//
// Reference implementations:
//   Noise:  Stefan Gustavson, Inigo Quilez
//   SDF:    Inigo Quilez — iquilezles.org/articles/distfunctions/
//   PBR:    LearnOpenGL.com Cook-Torrance, Epic Games UE4 PBR notes
//   UV:     Flexi "Box of Tricks" (Milkdrop), standard complex analysis
//   ACES:   Stephen Hill's fitted curve (Unreal Engine)

// ======================================================================
// MARK: - Hash Functions
// ======================================================================

/// 2D → 1D hash. Fast pseudo-random via sine.
static inline float hash21(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

/// 1D → 3D hash.
static inline float3 hash31(float p) {
    float3 p3 = fract(float3(p) * float3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xxy + p3.yzz) * p3.zyx);
}

/// 2D → 2D hash.
static inline float2 hash22(float2 p) {
    float3 p3 = fract(float3(p.xyx) * float3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

/// 3D → 3D hash.
static inline float3 hash33(float3 p3) {
    p3 = fract(p3 * float3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yxz + 33.33);
    return fract((p3.xxy + p3.yxx) * p3.zyx);
}

// ======================================================================
// MARK: - Noise Functions
// ======================================================================

/// 2D value/gradient noise (Perlin-style).
static inline float perlin2D(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);

    float a = hash21(i + float2(0.0, 0.0));
    float b = hash21(i + float2(1.0, 0.0));
    float c = hash21(i + float2(0.0, 1.0));
    float d = hash21(i + float2(1.0, 1.0));

    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

/// 3D value/gradient noise (Perlin-style).
static inline float perlin3D(float3 p) {
    float3 i = floor(p);
    float3 f = fract(p);
    float3 u = f * f * (3.0 - 2.0 * f);

    float n000 = hash21(i.xy + float2(i.z * 137.0, 0.0));
    float n100 = hash21(i.xy + float2(i.z * 137.0 + 1.0, 0.0));
    float n010 = hash21(i.xy + float2(i.z * 137.0, 1.0));
    float n110 = hash21(i.xy + float2(i.z * 137.0 + 1.0, 1.0));
    float n001 = hash21(i.xy + float2((i.z + 1.0) * 137.0, 0.0));
    float n101 = hash21(i.xy + float2((i.z + 1.0) * 137.0 + 1.0, 0.0));
    float n011 = hash21(i.xy + float2((i.z + 1.0) * 137.0, 1.0));
    float n111 = hash21(i.xy + float2((i.z + 1.0) * 137.0 + 1.0, 1.0));

    float n00 = mix(n000, n100, u.x);
    float n01 = mix(n010, n110, u.x);
    float n10 = mix(n001, n101, u.x);
    float n11 = mix(n011, n111, u.x);

    float n0 = mix(n00, n01, u.y);
    float n1 = mix(n10, n11, u.y);

    return mix(n0, n1, u.z);
}

/// 2D simplex noise. Based on Stefan Gustavson's implementation.
static inline float simplex2D(float2 v) {
    const float2 C = float2(0.211324865405187,   // (3.0 - sqrt(3.0)) / 6.0
                             0.366025403784439);  // 0.5 * (sqrt(3.0) - 1.0)
    // First corner.
    float2 i = floor(v + dot(v, C.yy));
    float2 x0 = v - i + dot(i, C.xx);

    // Other corners.
    float2 i1 = (x0.x > x0.y) ? float2(1.0, 0.0) : float2(0.0, 1.0);
    float2 x1 = x0 - i1 + C.xx;
    float2 x2 = x0 - 1.0 + 2.0 * C.xx;

    // Gradients via hashing.
    float3 p = float3(hash21(i), hash21(i + i1), hash21(i + 1.0));
    // Map hash to angle for 2D gradient.
    float3 angle = p * 6.28318530718;

    // Kernel contributions.
    float3 m = max(0.5 - float3(dot(x0, x0), dot(x1, x1), dot(x2, x2)), 0.0);
    m = m * m;
    m = m * m;

    // Gradient dot products.
    float3 g = float3(
        dot(x0, float2(cos(angle.x), sin(angle.x))),
        dot(x1, float2(cos(angle.y), sin(angle.y))),
        dot(x2, float2(cos(angle.z), sin(angle.z)))
    );

    return 70.0 * dot(m, g);
}

/// 3D simplex noise.
static inline float simplex3D(float3 v) {
    const float2 C = float2(1.0 / 6.0, 1.0 / 3.0);

    // First corner.
    float3 i = floor(v + dot(v, C.yyy));
    float3 x0 = v - i + dot(i, C.xxx);

    // Other corners — determine simplex.
    float3 g = step(x0.yzx, x0.xyz);
    float3 l = 1.0 - g;
    float3 i1 = min(g.xyz, l.zxy);
    float3 i2 = max(g.xyz, l.zxy);

    float3 x1 = x0 - i1 + C.xxx;
    float3 x2 = x0 - i2 + 2.0 * C.xxx;
    float3 x3 = x0 - 1.0 + 3.0 * C.xxx;

    // Hash gradients.
    float4 h = float4(
        hash21(float2(dot(i, float3(1.0, 57.0, 113.0)), 0.0)),
        hash21(float2(dot(i + i1, float3(1.0, 57.0, 113.0)), 0.0)),
        hash21(float2(dot(i + i2, float3(1.0, 57.0, 113.0)), 0.0)),
        hash21(float2(dot(i + 1.0, float3(1.0, 57.0, 113.0)), 0.0))
    );

    // Kernel falloff.
    float4 m = max(0.6 - float4(dot(x0, x0), dot(x1, x1), dot(x2, x2), dot(x3, x3)), 0.0);
    m = m * m;
    m = m * m;

    // Gradient directions from hash.
    float4 angles = h * 6.28318530718;
    float4 gz = cos(angles);
    float4 gx = sin(angles) * cos(angles * 2.399);
    float4 gy = sin(angles) * sin(angles * 2.399);

    float4 gdot = float4(
        dot(x0, float3(gx.x, gy.x, gz.x)),
        dot(x1, float3(gx.y, gy.y, gz.y)),
        dot(x2, float3(gx.z, gy.z, gz.z)),
        dot(x3, float3(gx.w, gy.w, gz.w))
    );

    return 42.0 * dot(m, gdot);
}

/// 2D Worley (cellular/Voronoi) noise. Returns distance to nearest cell center.
static inline float worley2D(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);

    float minDist = 1.0;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            float2 neighbor = float2(float(x), float(y));
            float2 point = hash22(i + neighbor);
            float2 diff = neighbor + point - f;
            minDist = min(minDist, length(diff));
        }
    }
    return minDist;
}

/// 3D Worley (cellular/Voronoi) noise.
static inline float worley3D(float3 p) {
    float3 i = floor(p);
    float3 f = fract(p);

    float minDist = 1.0;
    for (int z = -1; z <= 1; z++) {
        for (int y = -1; y <= 1; y++) {
            for (int x = -1; x <= 1; x++) {
                float3 neighbor = float3(float(x), float(y), float(z));
                float3 point = hash33(i + neighbor);
                float3 diff = neighbor + point - f;
                minDist = min(minDist, length(diff));
            }
        }
    }
    return minDist;
}

/// 2D fractal Brownian motion — layered Perlin noise.
static inline float fbm2D(float2 p, int octaves = 5) {
    float value = 0.0;
    float amplitude = 0.5;
    float frequency = 1.0;
    for (int i = 0; i < octaves; i++) {
        value += amplitude * perlin2D(p * frequency);
        frequency *= 2.0;
        amplitude *= 0.5;
    }
    return value;
}

/// 3D fractal Brownian motion — layered Perlin noise.
static inline float fbm3D(float3 p, int octaves = 5) {
    float value = 0.0;
    float amplitude = 0.5;
    float frequency = 1.0;
    for (int i = 0; i < octaves; i++) {
        value += amplitude * perlin3D(p * frequency);
        frequency *= 2.0;
        amplitude *= 0.5;
    }
    return value;
}

/// 2D curl noise — divergence-free vector field from noise derivatives.
static inline float2 curl2D(float2 p) {
    const float e = 0.001;
    float n1 = perlin2D(float2(p.x, p.y + e));
    float n2 = perlin2D(float2(p.x, p.y - e));
    float n3 = perlin2D(float2(p.x + e, p.y));
    float n4 = perlin2D(float2(p.x - e, p.y));
    float dx = (n1 - n2) / (2.0 * e);
    float dy = (n3 - n4) / (2.0 * e);
    return float2(dx, -dy);
}

/// 3D curl noise — divergence-free vector field.
static inline float3 curl3D(float3 p) {
    const float e = 0.001;
    // Partial derivatives of noise components.
    float n1 = perlin3D(float3(p.x, p.y + e, p.z)) - perlin3D(float3(p.x, p.y - e, p.z));
    float n2 = perlin3D(float3(p.x, p.y, p.z + e)) - perlin3D(float3(p.x, p.y, p.z - e));
    float n3 = perlin3D(float3(p.x + e, p.y, p.z)) - perlin3D(float3(p.x + e, p.y, p.z));
    float n4 = perlin3D(float3(p.x, p.y, p.z + e)) - perlin3D(float3(p.x, p.y, p.z - e));
    float n5 = perlin3D(float3(p.x + e, p.y, p.z)) - perlin3D(float3(p.x - e, p.y, p.z));
    float n6 = perlin3D(float3(p.x, p.y + e, p.z)) - perlin3D(float3(p.x, p.y - e, p.z));
    float inv2e = 1.0 / (2.0 * e);
    return float3(
        (n1 - n2) * inv2e,
        (n3 - n4) * inv2e,
        (n5 - n6) * inv2e
    );
}

// ======================================================================
// MARK: - SDF Primitives
// ======================================================================

/// Signed distance to a sphere centered at origin.
static inline float sdSphere(float3 p, float r) {
    return length(p) - r;
}

/// Signed distance to an axis-aligned box centered at origin.
static inline float sdBox(float3 p, float3 b) {
    float3 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}

/// Signed distance to a rounded box.
static inline float sdRoundBox(float3 p, float3 b, float r) {
    float3 q = abs(p) - b + r;
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0) - r;
}

/// Signed distance to a torus in the XZ plane.
static inline float sdTorus(float3 p, float2 t) {
    float2 q = float2(length(p.xz) - t.x, p.y);
    return length(q) - t.y;
}

/// Signed distance to a vertical cylinder (Y-axis).
static inline float sdCylinder(float3 p, float h, float r) {
    float2 d = abs(float2(length(p.xz), p.y)) - float2(r, h);
    return min(max(d.x, d.y), 0.0) + length(max(d, 0.0));
}

/// Signed distance to a capsule between two endpoints.
static inline float sdCapsule(float3 p, float3 a, float3 b, float r) {
    float3 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - r;
}

/// Signed distance to a cone with tip at origin, axis along Y.
static inline float sdCone(float3 p, float2 c, float h) {
    // c is (sin, cos) of the cone half-angle.
    float q = length(p.xz);
    return max(dot(c.xy, float2(q, p.y)), -h - p.y);
}

/// Signed distance to an infinite plane with normal n (must be normalized) at height h.
static inline float sdPlane(float3 p, float3 n, float h) {
    return dot(p, n) + h;
}

// ======================================================================
// MARK: - SDF Operations
// ======================================================================

/// Boolean union (min).
static inline float opUnion(float d1, float d2) {
    return min(d1, d2);
}

/// Boolean subtraction.
static inline float opSubtract(float d1, float d2) {
    return max(-d1, d2);
}

/// Boolean intersection.
static inline float opIntersect(float d1, float d2) {
    return max(d1, d2);
}

/// Smooth union with blending factor k.
static inline float opSmoothUnion(float d1, float d2, float k) {
    float h = clamp(0.5 + 0.5 * (d2 - d1) / k, 0.0, 1.0);
    return mix(d2, d1, h) - k * h * (1.0 - h);
}

/// Smooth subtraction with blending factor k.
static inline float opSmoothSubtract(float d1, float d2, float k) {
    float h = clamp(0.5 - 0.5 * (d2 + d1) / k, 0.0, 1.0);
    return mix(d2, -d1, h) + k * h * (1.0 - h);
}

/// Infinite domain repetition with spacing c.
static inline float3 opRepeat(float3 p, float3 c) {
    return fmod(p + 0.5 * c, c) - 0.5 * c;
}

/// Twist deformation around the Y axis.
static inline float3 opTwist(float3 p, float k) {
    float c = cos(k * p.y);
    float s = sin(k * p.y);
    float2 q = float2(c * p.x - s * p.z, s * p.x + c * p.z);
    return float3(q.x, p.y, q.y);
}

/// Cheap bend deformation around the Y axis.
static inline float3 opBend(float3 p, float k) {
    float c = cos(k * p.x);
    float s = sin(k * p.x);
    float2 q = float2(c * p.x - s * p.y, s * p.x + c * p.y);
    return float3(q.x, q.y, p.z);
}

/// Round an SDF by subtracting a radius.
static inline float opRound(float d, float r) {
    return d - r;
}

// ======================================================================
// MARK: - Ray Marching
// ======================================================================

// Ray marching utilities call a user-defined scene function: float map(float3 p).
// Presets using these functions MUST define map() before calling them.
// Presets that do not use ray marching should not call these functions.
float map(float3 p);

/// Sphere-trace along a ray. Returns hit distance, or -1.0 on miss.
static inline float rayMarch(float3 ro, float3 rd, float tMin, float tMax, int maxSteps) {
    float t = tMin;
    for (int i = 0; i < maxSteps; i++) {
        float d = map(ro + rd * t);
        if (abs(d) < 0.0005) return t;
        t += d;
        if (t > tMax) break;
    }
    return -1.0;
}

/// Compute surface normal via central differences.
static inline float3 calcNormal(float3 p) {
    const float2 e = float2(0.0005, 0.0);
    return normalize(float3(
        map(p + e.xyy) - map(p - e.xyy),
        map(p + e.yxy) - map(p - e.yxy),
        map(p + e.yyx) - map(p - e.yyx)
    ));
}

/// Ambient occlusion via short-range ray marching along the normal.
static inline float calcAO(float3 p, float3 n) {
    float occ = 0.0;
    float sca = 1.0;
    for (int i = 0; i < 5; i++) {
        float h = 0.01 + 0.12 * float(i);
        float d = map(p + h * n);
        occ += (h - d) * sca;
        sca *= 0.95;
    }
    return clamp(1.0 - 3.0 * occ, 0.0, 1.0);
}

/// Soft shadow with penumbra factor k. Larger k = harder shadow.
static inline float softShadow(float3 ro, float3 rd, float tMin, float tMax, float k) {
    float res = 1.0;
    float t = tMin;
    for (int i = 0; i < 64; i++) {
        float h = map(ro + rd * t);
        if (h < 0.001) return 0.0;
        res = min(res, k * h / t);
        t += clamp(h, 0.02, 0.1);
        if (t > tMax) break;
    }
    return clamp(res, 0.0, 1.0);
}

// ======================================================================
// MARK: - PBR Lighting
// ======================================================================

/// Fresnel-Schlick approximation.
static inline float3 fresnelSchlick(float cosTheta, float3 F0) {
    return F0 + (1.0 - F0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
}

/// GGX/Trowbridge-Reitz normal distribution function.
static inline float distributionGGX(float3 N, float3 H, float roughness) {
    float a = roughness * roughness;
    float a2 = a * a;
    float NdotH = max(dot(N, H), 0.0);
    float NdotH2 = NdotH * NdotH;

    float denom = NdotH2 * (a2 - 1.0) + 1.0;
    denom = M_PI_F * denom * denom;

    return a2 / max(denom, 0.0001);
}

/// Smith's geometry function using Schlick-GGX for both view and light directions.
static inline float geometrySmith(float3 N, float3 V, float3 L, float roughness) {
    float r = roughness + 1.0;
    float k = (r * r) / 8.0;

    float NdotV = max(dot(N, V), 0.0);
    float NdotL = max(dot(N, L), 0.0);

    float ggx1 = NdotV / (NdotV * (1.0 - k) + k);
    float ggx2 = NdotL / (NdotL * (1.0 - k) + k);

    return ggx1 * ggx2;
}

/// Full Cook-Torrance specular BRDF evaluation.
/// Returns the specular contribution (does not include diffuse).
static inline float3 cookTorranceBRDF(float3 N, float3 V, float3 L,
                                       float3 albedo, float metallic, float roughness) {
    float3 H = normalize(V + L);
    float3 F0 = mix(float3(0.04), albedo, metallic);

    float NDF = distributionGGX(N, H, roughness);
    float G = geometrySmith(N, V, L, roughness);
    float3 F = fresnelSchlick(max(dot(H, V), 0.0), F0);

    float3 numerator = NDF * G * F;
    float denom = 4.0 * max(dot(N, V), 0.0) * max(dot(N, L), 0.0) + 0.0001;
    float3 specular = numerator / denom;

    // Energy conservation: diffuse is reduced by metallic and Fresnel.
    float3 kD = (1.0 - F) * (1.0 - metallic);
    float NdotL = max(dot(N, L), 0.0);

    return (kD * albedo / M_PI_F + specular) * NdotL;
}

/// Evaluate a point light at the given surface point.
static inline float3 evaluatePointLight(float3 P, float3 N, float3 V,
                                         float3 lightPos, float3 lightColor,
                                         float3 albedo, float metallic, float roughness) {
    float3 L = normalize(lightPos - P);
    float dist = length(lightPos - P);
    float attenuation = 1.0 / (dist * dist);
    float3 radiance = lightColor * attenuation;
    return cookTorranceBRDF(N, V, L, albedo, metallic, roughness) * radiance;
}

/// Evaluate a directional light (infinite distance).
static inline float3 evaluateDirectionalLight(float3 N, float3 V, float3 lightDir,
                                               float3 lightColor, float3 albedo,
                                               float metallic, float roughness) {
    float3 L = normalize(-lightDir);
    return cookTorranceBRDF(N, V, L, albedo, metallic, roughness) * lightColor;
}

// ======================================================================
// MARK: - UV Transforms
// ======================================================================

/// Cartesian to polar coordinates. Returns (angle/2π, radius).
static inline float2 uvPolar(float2 uv, float2 center) {
    float2 d = uv - center;
    float angle = atan2(d.y, d.x) / (2.0 * M_PI_F) + 0.5;
    float radius = length(d);
    return float2(angle, radius);
}

/// Inverse radius mapping — maps center to infinity. Creates tunnel effects.
static inline float2 uvInvRadius(float2 uv, float2 center) {
    float2 d = uv - center;
    float r = length(d);
    float invR = 1.0 / max(r, 0.001);
    float angle = atan2(d.y, d.x);
    return float2(angle / (2.0 * M_PI_F), invR);
}

/// Kaleidoscope: fold UV into n angular segments.
static inline float2 uvKaleidoscope(float2 uv, float2 center, int n) {
    float2 d = uv - center;
    float angle = atan2(d.y, d.x);
    float segment = 2.0 * M_PI_F / float(n);
    angle = fmod(angle, segment);
    if (angle > segment * 0.5) angle = segment - angle;
    float r = length(d);
    return float2(cos(angle) * r, sin(angle) * r);
}

/// Möbius transformation: (az + b) / (cz + d) in complex plane.
static inline float2 uvMoebius(float2 uv, float2 a, float2 b, float2 c, float2 d) {
    // Complex multiplication: (x1+iy1)(x2+iy2) = (x1x2-y1y2) + i(x1y2+y1x2)
    float2 num = float2(a.x * uv.x - a.y * uv.y + b.x,
                         a.x * uv.y + a.y * uv.x + b.y);
    float2 den = float2(c.x * uv.x - c.y * uv.y + d.x,
                         c.x * uv.y + c.y * uv.x + d.y);
    float denom = dot(den, den);
    return float2(dot(num, den), num.y * den.x - num.x * den.y) / max(denom, 0.0001);
}

/// Bipolar coordinate transform.
static inline float2 uvBipolar(float2 uv, float a) {
    float denom = cosh(uv.y * a) - cos(uv.x * a);
    float sigma = sinh(uv.y * a) / max(denom, 0.001);
    float tau = sin(uv.x * a) / max(denom, 0.001);
    return float2(sigma, tau);
}

/// Logarithmic spiral mapping.
static inline float2 uvLogSpiral(float2 uv, float2 center, float rate) {
    float2 d = uv - center;
    float r = length(d);
    float angle = atan2(d.y, d.x);
    float logR = log(max(r, 0.001));
    return float2(angle / (2.0 * M_PI_F), logR * rate);
}

// ======================================================================
// MARK: - Color and Atmosphere
// ======================================================================

/// Inigo Quilez cosine palette: a + b * cos(2π(c * t + d)).
static inline float3 palette(float t, float3 a, float3 b, float3 c, float3 d) {
    return a + b * cos(6.28318530718 * (c * t + d));
}

/// ACES filmic tone mapping (Stephen Hill's fitted curve).
static inline float3 toneMapACES(float3 x) {
    const float a = 2.51;
    const float b = 0.03;
    const float c = 2.43;
    const float d = 0.59;
    const float e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0);
}

/// Reinhard tone mapping.
static inline float3 toneMapReinhard(float3 x) {
    return x / (x + 1.0);
}

/// Linear to sRGB gamma correction.
static inline float3 linearToSRGB(float3 c) {
    float3 lo = c * 12.92;
    float3 hi = 1.055 * pow(c, float3(1.0 / 2.4)) - 0.055;
    return mix(lo, hi, step(float3(0.0031308), c));
}

/// sRGB to linear.
static inline float3 sRGBToLinear(float3 c) {
    float3 lo = c / 12.92;
    float3 hi = pow((c + 0.055) / 1.055, float3(2.4));
    return mix(lo, hi, step(float3(0.04045), c));
}

/// Exponential distance fog.
static inline float3 fog(float3 color, float3 fogColor, float dist, float density) {
    float f = exp(-dist * density);
    return mix(fogColor, color, f);
}

/// Simplified atmospheric Rayleigh scattering.
static inline float3 atmosphericScatter(float3 rd, float3 sunDir, float3 sunColor) {
    // Rayleigh scattering coefficients (wavelength-dependent).
    const float3 betaR = float3(5.8e-6, 13.5e-6, 33.1e-6);

    float cosTheta = dot(rd, sunDir);
    // Rayleigh phase function.
    float phase = 0.75 * (1.0 + cosTheta * cosTheta);

    // Simple optical depth approximation based on view elevation.
    float elevation = max(rd.y, 0.0);
    float opticalDepth = 1.0 / (elevation + 0.1);

    float3 scatter = betaR * phase * opticalDepth;
    float3 extinction = exp(-betaR * opticalDepth * 2.0);

    return sunColor * scatter * 2000.0 + float3(0.1, 0.2, 0.4) * extinction;
}

/// Basic volumetric ray march through density field defined by 3D noise.
/// Returns (accumulated color, transmittance).
static inline float4 volumetricMarch(float3 ro, float3 rd, float tMin, float tMax,
                                      int steps, float density, float3 lightDir,
                                      float3 lightColor) {
    float stepSize = (tMax - tMin) / float(steps);
    float3 accum = float3(0.0);
    float transmittance = 1.0;

    for (int i = 0; i < steps; i++) {
        float t = tMin + (float(i) + 0.5) * stepSize;
        float3 p = ro + rd * t;

        float d = fbm3D(p * 0.5, 4) * density;
        if (d > 0.01) {
            // Simple directional lighting.
            float lightSample = fbm3D((p + lightDir * 0.3) * 0.5, 3);
            float shadow = exp(-lightSample * density * 2.0);
            float3 luminance = lightColor * shadow;

            accum += transmittance * d * luminance * stepSize;
            transmittance *= exp(-d * stepSize);

            if (transmittance < 0.01) break;
        }
    }

    return float4(accum, transmittance);
}
