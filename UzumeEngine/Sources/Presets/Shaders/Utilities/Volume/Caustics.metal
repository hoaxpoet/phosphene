// Caustics.metal — Procedural caustic pattern utilities (V.2 Part B).
//
// Caustics are the bright focusing patterns cast by light through wavy transparent
// surfaces (water, glass, crystal). These utilities provide real-time procedural
// approximations without requiring actual ray-traced photon maps.
//
// Techniques:
//   caust_wave      — Voronoi-based caustic (classic "swimming light" look)
//   caust_fbm       — fBM-distorted caustic for organic materials
//   caust_refract   — Fake refraction offset for cheap caustic placement
//   caust_animated  — Time-animated swimming caustics
//   caust_audio     — Audio-reactive caustic brightness modulation
//
// Usage:
//   float c = caust_animated(pos.xz, time, midRel);
//   albedo += lightColor * c * 0.3;

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"

// ─── Voronoi-Based Caustic ────────────────────────────────────────────────────

/// Voronoi distance for caustic pattern.
/// Returns distance to nearest cell centre in a jittered grid.
static inline float caust_voronoi(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float minDist = 1e5;
    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            float2 neighbor = float2(dx, dy);
            // Hash cell to random offset using integer arithmetic.
            float2 cell = i + neighbor;
            int2   ci   = int2(cell);
            int    h    = ci.x * 1453 + ci.y * 3571;
            h = (h ^ (h >> 9)) * 0x45d9f3b;
            float2 offset = float2(float(h & 0xffff), float((h >> 16) & 0xffff))
                            / 65535.0;
            float2 r = neighbor + offset - f;
            minDist  = min(minDist, dot(r, r));
        }
    }
    return sqrt(minDist);
}

/// Caustic intensity from Voronoi: bright at cell boundaries, dark at centres.
/// Invert and sharpen the Voronoi distance for the lens-focus effect.
/// scale = tiling frequency, sharpness = contrast (2–8 typical).
static inline float caust_wave(float2 p, float scale, float sharpness) {
    float d = caust_voronoi(p * scale);
    return pow(max(0.0, 1.0 - d), sharpness);
}

// ─── fBM-Distorted Caustic ────────────────────────────────────────────────────

/// Caustic with fBM domain warping — more organic than pure Voronoi.
/// Uses 2D perlin to displace UV before the Voronoi lookup.
static inline float caust_fbm(float2 p, float scale, float warpAmp) {
    float2 warp = float2(perlin3d(float3(p, 0.0)), perlin3d(float3(p + 5.2, 0.0)));
    float2 q    = p + warp * warpAmp;
    return caust_wave(q, scale, 3.0);
}

// ─── Refraction Offset ────────────────────────────────────────────────────────

/// Fake refraction offset for a point light through a wavy interface at height yPlane.
/// lightPos = world light position. p = surface point below the interface.
/// normal = interface normal (e.g. from a noise-driven water normal).
/// Returns UV displacement for caustic texture sampling on the receiver plane.
static inline float2 caust_refract_offset(float3 lightPos, float3 p, float3 normal, float ior) {
    float3 toLight = normalize(lightPos - p);
    float3 refracted = refract(-toLight, normal, 1.0 / ior);
    // Project refracted direction onto the receiver plane (XZ).
    float t = (p.y - 0.0) / max(-refracted.y, 1e-4);
    float3 hit = p + refracted * t;
    return hit.xz - p.xz;
}

// ─── Animated Caustics ────────────────────────────────────────────────────────

/// Time-animated swimming caustic pattern.
/// Blends two Voronoi caustics at different speeds and phases for complexity.
/// t = accumulatedAudioTime (music-locked, not wall-clock).
static inline float caust_animated(float2 p, float t) {
    float2 q0 = p + float2(t * 0.08, t * 0.06);
    float2 q1 = p - float2(t * 0.05, t * 0.09) + float2(3.7, 1.3);
    float c0 = caust_wave(q0, 3.0, 4.0);
    float c1 = caust_wave(q1, 2.5, 3.0);
    return (c0 + c1) * 0.5;
}

// ─── Audio-Reactive Caustics ──────────────────────────────────────────────────

/// Caustic with audio-driven animation and brightness.
/// bassRel brightens caustics on transients; midRel animates warp amplitude.
static inline float caust_audio(float2 p, float t, float bassRel, float midRel) {
    float warpAmp = 0.15 + max(0.0, midRel) * 0.15;
    float base    = caust_fbm(p, 3.5, warpAmp);
    // Animate phase via accumulatedAudioTime so caustics track the music.
    float2 q = p + float2(t * 0.06, t * 0.04);
    float layer = caust_wave(q, 4.0, 5.0);
    float brightness = 1.0 + max(0.0, bassRel) * 0.6;
    return clamp((base * 0.6 + layer * 0.4) * brightness, 0.0, 1.0);
}

#pragma clang diagnostic pop
