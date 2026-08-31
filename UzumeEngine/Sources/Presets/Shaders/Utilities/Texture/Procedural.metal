// Procedural.metal — Procedural texture pattern generators (V.2 Part C).
//
// Provides deterministic 2D/3D pattern generators for use as base textures,
// roughness maps, albedo variation, or specular break-up.
//
// Patterns:
//   proc_stripes       — sharp / soft alternating bands
//   proc_checker       — checkerboard (anti-aliased version available)
//   proc_grid          — square grid lines
//   proc_hex_grid      — hexagonal grid lines
//   proc_dots          — circular dot array
//   proc_concentric    — radial rings from a centre
//   proc_weave         — plain-weave cloth over/under grid
//   proc_brick         — offset-row brick pattern with mortar
//   proc_fish_scale    — overlapping circular scales
//   proc_wood          — radial concentric-ring wood grain

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"

// ─── Stripes ──────────────────────────────────────────────────────────────────

/// Alternating bands along the X axis. Returns [0,1]: 1 = stripe, 0 = gap.
/// scale = bands per unit, width = stripe fill fraction [0,1].
static inline float proc_stripes(float x, float scale, float width) {
    float t = fract(x * scale);
    return step(t, width);
}

/// Soft stripe with smoothstep transition of radius edge (0 = sharp).
static inline float proc_stripes_soft(float x, float scale, float width, float edge) {
    float t = fract(x * scale);
    return smoothstep(width, max(width - edge, 0.0), t) *
           (1.0 - smoothstep(0.0, edge, t));
}

// ─── Checkerboard ────────────────────────────────────────────────────────────

/// Sharp checkerboard. Returns 0 or 1.
static inline float proc_checker(float2 uv, float scale) {
    float2 q = floor(uv * scale);
    return fmod(q.x + q.y, 2.0);
}

/// Anti-aliased checkerboard using fwidth. Only valid in fragment shaders.
/// Falls back to sharp version when fwidth ≈ 0.
static inline float proc_checker_aa(float2 uv, float scale) {
    float2 p  = uv * scale;
    float2 fw = fwidth(p);
    float2 i  = 2.0 * (abs(fract((p - 0.5) * 0.5) - 0.25) - abs(fract((p + fw * 0.5 - 0.5) * 0.5) - 0.25));
    return saturate(0.5 + (i.x + i.y) / max(fw.x + fw.y, 1e-5));
}

// ─── Grid Lines ───────────────────────────────────────────────────────────────

/// Square grid lines. Returns 1 on lines, 0 in cells.
/// scale = cells per unit, lineWidth = line width fraction of cell [0, 0.5].
static inline float proc_grid(float2 uv, float scale, float lineWidth) {
    float2 q = fract(uv * scale);
    float2 g = smoothstep(0.0, lineWidth, q) * (1.0 - smoothstep(1.0 - lineWidth, 1.0, q));
    return 1.0 - g.x * g.y;   // 1 = on a line
}

// ─── Hexagonal Grid ───────────────────────────────────────────────────────────

/// Hexagonal grid lines. Returns 1 on lines, 0 in cells.
static inline float proc_hex_grid(float2 uv, float scale, float lineWidth) {
    float2 p = uv * scale;
    // Convert to hex grid coordinates.
    float2 a = float2(p.x - p.y * 0.577350, p.y * 1.154701);
    float2 b = float2(a.x - floor(a.x) - 0.5, a.y - floor(a.y) - 0.5);
    float  d = length(b) / 0.577350;   // normalised distance to nearest edge
    return 1.0 - smoothstep(1.0 - lineWidth, 1.0, d);
}

// ─── Dot Array ────────────────────────────────────────────────────────────────

/// Array of circular dots. Returns 1 inside dots, 0 outside.
/// radius = dot radius as fraction of cell [0, 0.5].
static inline float proc_dots(float2 uv, float scale, float radius) {
    float2 q = fract(uv * scale) - 0.5;
    return smoothstep(radius + 0.02, radius, length(q));
}

// ─── Concentric Rings ─────────────────────────────────────────────────────────

/// Concentric rings from point centre. Returns [0,1] alternating.
/// count = rings per unit distance from centre.
static inline float proc_concentric(float2 uv, float2 centre, float count, float width) {
    float d = length(uv - centre) * count;
    return step(fract(d), width);
}

// ─── Cloth Weave ─────────────────────────────────────────────────────────────

/// Plain-weave cloth texture. Alternates warp and weft threads going over/under.
/// Returns float in [0,1]: bright = thread on top, dark = thread below.
static inline float proc_weave(float2 uv, float scale) {
    float2 q = uv * scale;
    float2 i = floor(q);
    float2 f = fract(q);
    // Alternating over/under based on parity of cell.
    float warp = step(f.x, 0.5);
    float weft = step(f.y, 0.5);
    float parity = fmod(i.x + i.y, 2.0);
    float over = mix(weft, 1.0 - weft, parity) * warp + (1.0 - warp) * 0.4;
    return over;
}

// ─── Brick ───────────────────────────────────────────────────────────────────

/// Offset-row brick pattern. Returns [0,1]: 1 = brick face, 0 = mortar.
/// width, height = brick size. mortarW, mortarH = mortar thickness fraction.
static inline float proc_brick(float2 uv, float2 size, float2 mortar) {
    float2 q = uv / size;
    // Offset every other row by half a brick.
    float row = floor(q.y);
    q.x += fmod(row, 2.0) * 0.5;
    float2 f = fract(q);
    float mx = step(mortar.x * 0.5, f.x) * (1.0 - step(1.0 - mortar.x * 0.5, f.x));
    float my = step(mortar.y * 0.5, f.y) * (1.0 - step(1.0 - mortar.y * 0.5, f.y));
    return mx * my;
}

// ─── Fish Scales ─────────────────────────────────────────────────────────────

/// Overlapping fish-scale / roof-tile pattern. Returns [0,1]: 1 = scale centre.
static inline float proc_fish_scale(float2 uv, float scale) {
    float2 q = uv * scale;
    float  row = floor(q.y);
    float2 q2  = q;
    q2.x += fmod(row, 2.0) * 0.5;
    float2 f   = fract(q2) - float2(0.5, 0.0);
    float  d   = length(float2(f.x, f.y - 0.4));   // centre slightly above row bottom
    return smoothstep(0.48, 0.44, d);
}

// ─── Wood Grain ──────────────────────────────────────────────────────────────

/// Procedural wood grain: concentric rings disturbed by noise.
/// p = 3D world point (XZ slice). Returns float [0,1] ring value.
static inline float proc_wood(float3 p, float ringFreq, float grainFreq, float grainAmp) {
    float radius  = length(p.xz);
    float noise   = perlin3d(p * grainFreq) * grainAmp;
    float rings   = fract((radius + noise) * ringFreq);
    return smoothstep(0.0, 0.3, rings) * smoothstep(1.0, 0.7, rings);
}

#pragma clang diagnostic pop
