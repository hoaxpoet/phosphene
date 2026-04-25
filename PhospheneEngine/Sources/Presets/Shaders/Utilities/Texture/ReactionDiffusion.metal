// ReactionDiffusion.metal — Gray-Scott reaction-diffusion utilities (V.2 Part C).
//
// The Gray-Scott model produces organic patterns (spots, stripes, coral, labyrinths)
// from two chemical species A and B reacting and diffusing through space.
//
// dA/dt = Da ∇²A − A·B² + feed·(1−A)
// dB/dt = Db ∇²B + A·B² − (kill+feed)·B
//
// Because the model is a time-stepping simulation, these utilities provide:
//   1. A stateless single-step update for use with GPU ping-pong textures.
//   2. A procedural steady-state pattern approximation (no state required).
//      Use (2) in presets that don't manage per-frame state textures.
//
// Preset usage (stateless approximation):
//   float3 rdCol = rd_pattern_spots(p.xz, time, scale, feed, kill);
//   albedo = mix(colorA, colorB, rdCol.r);
//
// Full simulation usage (ping-pong textures):
//   float2 ab = rd_step(prevAB, neighbors, dt, feed, kill);
//   // Caller must manage texture read/write; this returns updated (A, B) for one pixel.

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"

// ─── Stateless Steady-State Approximation ────────────────────────────────────

/// Approximate Gray-Scott steady-state pattern using noise.
/// Reproduces labyrinthine / spot patterns without simulation state.
/// feed/kill control morphology:
///   feed=0.037, kill=0.060 → spots
///   feed=0.060, kill=0.062 → stripes
///   feed=0.025, kill=0.060 → worms
/// Returns float B-concentration in [0,1].
static inline float rd_pattern_approx(float2 p, float scale, float feed, float kill) {
    // Two-frequency warped noise to mimic Turing instability pattern.
    float2 q    = p * scale;
    float  warp = perlin3d(float3(q * 0.3, 0.5)) * 0.8;
    float2 qw   = q + warp;
    float  n1   = perlin3d(float3(qw, 0.0));
    float  n2   = perlin3d(float3(qw * 2.0 + 3.7, 1.0));
    float  raw  = n1 * 0.6 + n2 * 0.4;

    // Map noise to B-concentration via kill/feed threshold.
    // perlin3d is centered at 0 in [-1,1], so threshold is centered at 0.
    // Distinct feed/kill values produce distinct thresholds → distinct coverage patterns.
    float threshold = (kill - 0.06) * 10.0 - (feed - 0.04) * 8.0;
    return smoothstep(threshold - 0.15, threshold + 0.15, raw);
}

/// Animated reaction-diffusion approximation with music-driven evolution.
/// t = accumulatedAudioTime; midRel animates pattern speed.
static inline float rd_pattern_animated(float2 p, float scale, float t, float feed, float kill, float midRel) {
    float speed = 1.0 + max(0.0, midRel) * 0.5;
    float2 q = p + float2(sin(t * 0.07 * speed), cos(t * 0.05 * speed)) * 0.8;
    return rd_pattern_approx(q, scale, feed, kill);
}

/// Spot-mode pattern (feed=0.037, kill=0.060).
static inline float rd_spots(float2 p, float scale, float t) {
    return rd_pattern_animated(p, scale, t, 0.037, 0.060, 0.0);
}

/// Stripe-mode pattern (feed=0.060, kill=0.062).
static inline float rd_stripes(float2 p, float scale, float t) {
    return rd_pattern_animated(p, scale, t, 0.060, 0.062, 0.0);
}

/// Worm-mode pattern (feed=0.025, kill=0.060).
static inline float rd_worms(float2 p, float scale, float t) {
    return rd_pattern_animated(p, scale, t, 0.025, 0.060, 0.0);
}

// ─── Full Simulation Step (for ping-pong textures) ────────────────────────────

/// Single Gray-Scott update step for one texel.
/// ab        = current (A, B) concentrations at this pixel.
/// lapA, lapB = Laplacian (∇²A, ∇²B) computed by caller from 5-point stencil.
/// dt        = time step (0.5–1.0 for stability at standard Da/Db).
/// feed      = feed rate (f). kill = kill rate (k).
/// Returns updated float2(A, B).
///
/// Caller computes Laplacians:
///   lapA = (east.r + west.r + north.r + south.r - 4*ab.r) (or 9-point stencil)
///   lapB = (east.g + west.g + north.g + south.g - 4*ab.g)
static inline float2 rd_step(
    float2 ab, float lapA, float lapB,
    float dt, float feed, float kill
) {
    float Da = 1.0, Db = 0.5;
    float A = ab.x, B = ab.y;
    float reactionAB2 = A * B * B;
    float newA = A + (Da * lapA - reactionAB2 + feed * (1.0 - A)) * dt;
    float newB = B + (Db * lapB + reactionAB2 - (kill + feed) * B) * dt;
    return clamp(float2(newA, newB), 0.0, 1.0);
}

// ─── Color Mapping ────────────────────────────────────────────────────────────

/// Map B-concentration to a 2-color palette.
/// colorA = color at B=0 (background species), colorB = color at B=1 (active).
static inline float3 rd_colorize(float b, float3 colorA, float3 colorB) {
    return mix(colorA, colorB, b);
}

/// Three-way palette: dark background → mid active → bright highlight.
static inline float3 rd_colorize_tri(float b, float3 dark, float3 mid, float3 bright) {
    return (b < 0.5)
        ? mix(dark, mid, b * 2.0)
        : mix(mid, bright, (b - 0.5) * 2.0);
}

#pragma clang diagnostic pop
