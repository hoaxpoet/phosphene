// Grunge.metal — Surface grunge, wear, and micro-detail utilities (V.2 Part C).
//
// Grunge maps add the real-world surface history that makes CGI materials
// read as physical objects rather than procedural renders.
//
// Patterns model:
//   grunge_scratches   — directional micro-scratches (brushed metal)
//   grunge_rust        — layered oxide bloom (Voronoi + fBM)
//   grunge_edge_wear   — AO-like darkening at convex edges
//   grunge_fingerprint — whorled fingerprint ridge detail
//   grunge_dust        — speckled settled dust layer
//   grunge_dirt_mask   — accumulated grime in surface crevices
//   grunge_crack       — fine hairline crack network
//   grunge_composite   — layered compositor: returns roughness delta and albedo tint

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"

// ─── Directional Scratches ────────────────────────────────────────────────────

/// Micro-scratches along a dominant direction (brushed aluminum, machined metal).
/// dir = scratch direction (unit 2D vector). Returns scratch intensity [0,1].
/// density = scratches per unit. sharpness = scratch narrowness (4–32).
static inline float grunge_scratches(float2 uv, float2 dir, float density, float sharpness) {
    float2 perp = float2(-dir.y, dir.x);
    float  t    = dot(uv, perp) * density;
    // Thin stripes along dir, randomized by noise.
    float  noise = perlin3d(float3(uv * density * 0.3, 0.7)) * 0.5 + 0.5;
    float  stripe = pow(max(0.0, sin(t * 3.14159265)), sharpness);
    return stripe * noise;
}

// ─── Rust ─────────────────────────────────────────────────────────────────────

/// Layered rust pattern: Voronoi oxide blooms + fBM overlay.
/// Returns float [0,1]: 0 = clean metal, 1 = heavy rust.
/// coverage ∈ [0,1]: 0 = pristine, 1 = fully rusted.
static inline float grunge_rust(float2 uv, float scale, float coverage) {
    VoronoiResult v = voronoi_f1f2(uv, scale * 0.5);
    float bloom = 1.0 - smoothstep(0.0, 0.8, v.f1);   // oxide bloom at cell centres
    float texture = perlin3d(float3(uv * scale * 2.0, 0.3)) * 0.5 + 0.5;
    float rust = bloom * 0.6 + texture * 0.4;
    return clamp(rust - (1.0 - coverage), 0.0, 1.0) / max(coverage, 0.01);
}

// ─── Edge Wear ────────────────────────────────────────────────────────────────

/// Simulate paint/coating wear at convex edges.
/// curvature = approximate surface curvature (from normal dot product proxy).
/// Returns 1 at exposed bare edges, 0 on flat faces.
static inline float grunge_edge_wear(float curvature, float wearAmount) {
    return smoothstep(0.6 - wearAmount * 0.4, 0.6, curvature);
}

// ─── Fingerprint ─────────────────────────────────────────────────────────────

/// Whorled fingerprint ridge pattern. Returns ridge intensity [0,1].
/// Simulates the loop/whorl structure of actual fingerprints.
static inline float grunge_fingerprint(float2 uv, float scale) {
    float2 q = uv * scale;
    float  r = length(q - 0.5);   // distance from centre of whorl
    float  angle = atan2(q.y - 0.5, q.x - 0.5);
    float  warp = perlin3d(float3(q, 0.5)) * 0.3;
    float  rings = sin((r + warp) * 40.0 + angle * 0.5);
    return smoothstep(0.0, 0.3, rings) * smoothstep(1.0, 0.7, r * 2.0);
}

// ─── Dust ─────────────────────────────────────────────────────────────────────

/// Settled dust speckle. More dust in recesses (low normal.y).
/// Returns dust density [0,1].
static inline float grunge_dust(float2 uv, float scale, float normalY, float amount) {
    float speckle = step(0.7, perlin3d(float3(uv * scale, 2.3)) * 0.5 + 0.5);
    float recess  = 1.0 - clamp(normalY, 0.0, 1.0);   // more in concavities
    return speckle * recess * amount;
}

// ─── Dirt Mask ────────────────────────────────────────────────────────────────

/// Accumulated grime in surface crevices (AO-proxy dirt).
/// ao = ambient occlusion estimate [0,1] (0 = fully occluded / dirty).
/// Returns dirt intensity [0,1].
static inline float grunge_dirt_mask(float ao, float dirtyness) {
    float base = 1.0 - ao;   // more dirt where light can't reach
    return smoothstep(0.0, 1.0, base * dirtyness);
}

// ─── Hairline Cracks ─────────────────────────────────────────────────────────

/// Fine hairline crack network. Returns 1 on cracks, 0 elsewhere.
/// scale = crack frequency, width = crack width fraction [0.01, 0.05].
static inline float grunge_crack(float2 uv, float scale, float width) {
    VoronoiResult v = voronoi_f1f2(uv, scale);
    float edge = v.f2 - v.f1;
    return 1.0 - smoothstep(0.0, width, edge);
}

// ─── Composite Grunge ─────────────────────────────────────────────────────────

/// Layered grunge composite: applies scratches + rust + dust to roughness and albedo.
/// Designed for one-call material dirtying.
///
/// Outputs:
///   roughnessDelta = additive roughness change from grunge [0, 0.4]
///   albedoTint     = multiplicative albedo tint (rust/dirt darkening)
struct GrungeResult {
    float  roughnessDelta;
    float3 albedoTint;
};

static inline GrungeResult grunge_composite(
    float2 uv, float3 p,
    float curvature, float ao,
    float rustAmount, float scratchAmount, float dustAmount
) {
    GrungeResult g;
    float rust     = grunge_rust(uv, 3.0, rustAmount);
    float scratch  = grunge_scratches(uv, float2(0.707, 0.707), 12.0, 8.0) * scratchAmount;
    float dust     = grunge_dust(uv, 20.0, 1.0, dustAmount);
    float wear     = grunge_edge_wear(curvature, rustAmount * 0.5);
    float dirt     = grunge_dirt_mask(ao, 0.5);

    g.roughnessDelta = rust * 0.3 + scratch * 0.15 + dust * 0.1;
    float3 rustColor = float3(0.55, 0.27, 0.07);
    float3 dustColor = float3(0.70, 0.68, 0.60);
    g.albedoTint     = mix(float3(1.0), rustColor, rust * 0.6)
                     * mix(float3(1.0), dustColor, dust * 0.4)
                     * (1.0 - wear * 0.3 * rustAmount)
                     * (1.0 - dirt * 0.2);
    return g;
}

#pragma clang diagnostic pop
