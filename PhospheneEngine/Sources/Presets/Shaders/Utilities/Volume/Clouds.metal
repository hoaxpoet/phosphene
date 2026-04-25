// Clouds.metal — Procedural cloud rendering utilities (V.2 Part B).
//
// Builds on ParticipatingMedia.metal for the density field and HenyeyGreenstein.metal
// for scattering. Provides higher-level cloud-layer helpers ready for use in
// direct-pass or ray-march presets.
//
// Cloud types available:
//   cloud_density_cumulus   — billowing cumulus (tall, cauliflower tops)
//   cloud_density_stratus   — flat layer (even density slab)
//   cloud_density_cirrus    — wispy high-altitude ice strands
//   cloud_march             — single-pass volumetric integration
//   cloud_lighting          — Dual-lobe phase + ambient occlusion approx
//
// Usage (ray-march preset):
//   float den = cloud_density_cumulus(pos, time, coverageRel);
//   float3 col = cloud_lighting(pos, rd, den, lightDir, lightColor);

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"

// ─── Cloud Density Models ─────────────────────────────────────────────────────

/// Cumulus cloud density. Active between yMin and yMax (world units).
/// coverageRel ∈ [-1,1] (deviation primitive): 0 = average cover.
static inline float cloud_density_cumulus(float3 p, float t, float coverageRel) {
    // Height gradient: zero at base, peak at 2/3 of layer, tail off at top.
    float yMin = 0.5, yMax = 4.0;
    float h    = (p.y - yMin) / (yMax - yMin);
    if (h < 0.0 || h > 1.0) return 0.0;
    float shape = smoothstep(0.0, 0.2, h) * smoothstep(1.0, 0.6, h);

    // Animated noise: slow drift on XZ, no vertical animation.
    float3 q = float3(p.x * 0.5 + t * 0.03, p.y * 0.8, p.z * 0.5 + t * 0.02);
    float  n = perlin3d(q) * 0.5 + perlin3d(q * 2.0) * 0.3 + perlin3d(q * 4.0) * 0.2;

    float coverage = 0.5 + coverageRel * 0.3;
    return max(0.0, n - (1.0 - coverage)) * shape;
}

/// Stratus cloud: flat slab with gentle fBM texture.
static inline float cloud_density_stratus(float3 p, float t, float thickness) {
    float yBase = 1.0;
    float h = abs(p.y - yBase) / max(thickness, 0.01);
    if (h > 1.0) return 0.0;
    float shape = 1.0 - h * h;
    float3 q = float3(p.x * 0.3 + t * 0.01, 0.0, p.z * 0.3 + t * 0.008);
    float n = perlin3d(q) * 0.6 + perlin3d(q * 3.0) * 0.4;
    return max(0.0, n * 0.6) * shape;
}

/// Cirrus: wispy strands at high altitude. Domain-warped noise.
static inline float cloud_density_cirrus(float3 p, float t) {
    float yTarget = 8.0;
    float h = abs(p.y - yTarget) / 1.5;
    if (h > 1.0) return 0.0;
    float shape = exp(-h * h * 4.0);
    float3 q = float3(p.x * 1.5 + t * 0.05, p.y * 0.2, p.z * 1.5);
    float warp = perlin3d(q * 0.5) * 0.3;
    float n    = perlin3d(q + warp);
    return max(0.0, n - 0.4) * shape * 0.5;
}

// ─── Cloud Lighting ───────────────────────────────────────────────────────────

/// Combined cloud lighting: dual-lobe HG phase + cheap ambient occlusion.
/// Uses 3 upward density samples to estimate occlusion above p.
/// Returns float3 radiance for this density sample.
static inline float3 cloud_lighting(
    float3 p, float3 rd,
    float density, float t,
    float3 lightDir, float3 lightColor
) {
    if (density < 1e-5) return float3(0.0);

    // Phase: forward-scatter (silver lining) + mild back-scatter.
    float cosTheta = dot(rd, lightDir);
    float phase    = hg_dual_lobe(cosTheta, 0.7, -0.2, 0.85);

    // Fake ambient occlusion: sample density above p in 3 steps.
    float ao = 0.0;
    for (int i = 1; i <= 3; i++) {
        float3 q = p + float3(0.0, float(i) * 0.3, 0.0);
        ao += cloud_density_cumulus(q, t, 0.0) * 0.3;
    }
    float ambient = exp(-ao * 2.0);

    float3 sunLight = lightColor * phase * 2.0;
    float3 skyLight = float3(0.5, 0.65, 0.9) * ambient * 0.4;
    return (sunLight + skyLight) * density;
}

// ─── Cloud March ──────────────────────────────────────────────────────────────

/// Single-pass cloud ray march. ro = ray origin, rd = direction.
/// tMin/tMax = cloud layer bounds along the ray. steps = 32 recommended.
/// Returns VolumeSample (accumulate via vol_composite with background).
static inline VolumeSample cloud_march(
    float3 ro, float3 rd,
    float tMin, float tMax, int steps,
    float t, float coverageRel,
    float3 lightDir, float3 lightColor
) {
    VolumeSample s = vol_sample_zero();
    float dt = (tMax - tMin) / float(steps);
    for (int i = 0; i < steps; i++) {
        float  ti  = tMin + (float(i) + 0.5) * dt;
        float3 pos = ro + rd * ti;
        float  den = cloud_density_cumulus(pos, t, coverageRel);
        if (den < 1e-4) continue;
        float3 col = cloud_lighting(pos, rd, den, t, lightDir, lightColor);
        float stepTau = den * 0.15 * dt;
        float stepT   = exp(-stepTau);
        s.color        += col * s.transmittance * (1.0 - stepT) * dt;
        s.transmittance *= stepT;
        if (s.transmittance < 0.005) break;
    }
    return s;
}

#pragma clang diagnostic pop
