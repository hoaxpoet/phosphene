// MitosisGen2.metal — "detailed psychedelic cell division" (Cytokinesis preset, MITOSIS-G2.1).
//
// Ported from the Matt-approved throwaway sketch (tools/mitosis_gen2_sketch/Gen2Cell.metal),
// made data-driven: the CPU cell model (MitosisGen2Geometry) packs the live cells into
// buffer(1) and per-frame uniforms into buffer(0); this fragment composites each cell as an
// OPAQUE object over a green filament field, then applies the music-tied hue/vividness.
//
// A cell = a smooth-min dumbbell (the cytokinesis furrow pinch as `phase` advances) with two
// radial green microtubule asters, a solid OPAQUE membrane wall (occludes — asters do NOT
// show through it), a coloured cortical ring just inside the wall, blue chromatin, a magenta
// spindle midzone, and pink vesicle speckles. Procedural techniques: IQ smooth-min metaball,
// ring-sampled angular noise for the irregular fibres, ridged fbm for the filaments.
//
// VertexOut / fullscreen_vertex / hsv2rgb come from Common.metal (the ShaderLibrary
// concatenates all Shaders/*.metal). All free functions are `g2_`-prefixed to avoid
// one-definition-rule collisions with other preset shaders in that shared namespace.

#include <metal_stdlib>
using namespace metal;

// MARK: - GPU layouts (mirror Swift Gen2CellGPU / Gen2Uniforms in MitosisGen2Geometry.swift)

struct G2Cell {
    float2 pos;       // aspect-corrected space, y up
    float  radius;
    float  axis;      // division-axis angle
    float  phase;     // 0 interphase → 1 split
    float  seed;
};

struct G2Uniforms {
    float  aspect;    // viewport width/height
    float  energy;
    float  centroid;  // timbre → palette hue bias
    float  huePhase;
    float  hit;       // drum transient → bounded glow accent
    uint   cellCount;
    float  time;
};

// MARK: - noise / helpers

static inline float g2_hash21(float2 p) {
    p = fract(p * float2(123.34, 345.45));
    p += dot(p, p + 34.123);
    return fract(p.x * p.y);
}
static inline float g2_vnoise(float2 p) {
    float2 i = floor(p), f = fract(p);
    float a = g2_hash21(i), b = g2_hash21(i + float2(1, 0));
    float c = g2_hash21(i + float2(0, 1)), d = g2_hash21(i + float2(1, 1));
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}
static inline float g2_fbm(float2 p) {
    float s = 0.0, a = 0.5;
    for (int i = 0; i < 5; i++) { s += a * g2_vnoise(p); p *= 2.0; a *= 0.5; }
    return s;
}
static inline float g2_ridged(float2 p) {
    float s = 0.0, a = 0.5;
    for (int i = 0; i < 4; i++) {
        float r = 1.0 - abs(2.0 * g2_vnoise(p) - 1.0);
        s += a * r * r; p *= 2.1; a *= 0.5;
    }
    return s;
}
static inline float g2_smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}
static inline float2 g2_rot(float2 v, float a) {
    float c = cos(a), s = sin(a);
    return float2(c * v.x - s * v.y, s * v.x + c * v.y);
}
static inline float3 g2_hueShift(float3 col, float angle) {
    const float3 k = float3(0.57735027);
    float c = cos(angle), s = sin(angle);
    return col * c + cross(k, col) * s + k * dot(k, col) * (1.0 - c);
}

// MARK: - cell features

static inline float g2_aster(float2 q, float seed) {
    float r = length(q);
    float ang = atan2(q.y, q.x);
    float2 ring = float2(cos(ang), sin(ang));
    float lo = g2_vnoise(ring * 22.0 + seed);
    float hi = g2_vnoise(ring * 48.0 + seed * 2.3);
    float streak = pow(0.45 * lo + 0.55 * hi, 1.8);
    float radial = smoothstep(1.05, 0.05, r) * (0.62 + 0.22 * exp(-r * 1.8));
    float core   = exp(-r * r * 200.0) * 0.3;
    return streak * radial * 1.1 + core;
}
static inline float g2_chrom(float2 q, float seed) {
    float m = exp(-dot(q, q) * 15.0);
    float mott = 0.45 + 0.55 * g2_vnoise(q * 13.0 + seed);
    return m * mott;
}

// One cell → (rgb, coverage). Opaque membrane occludes the interior; the cell occludes the
// background within its boundary. `q` is the pixel relative to the cell centre.
static inline float4 g2_drawCell(float2 q, float phase, float radius, float axis, float seed) {
    float2 d = g2_rot(q, -axis) / radius;
    float ang = atan2(d.y, d.x);

    float sep = smoothstep(0.20, 1.0, phase) * 1.0;
    float k   = mix(0.55, 0.06, smoothstep(0.20, 0.95, phase));
    float poleR = 0.55;
    float2 c1 = float2(-sep * 0.5, 0.0), c2 = float2(sep * 0.5, 0.0);
    float d1 = length(d - c1) - poleR;
    float d2 = length(d - c2) - poleR;
    float sd = g2_smin(d1, d2, k);

    float wob  = 0.012 * (g2_vnoise(float2(ang * 3.0, seed)) - 0.5);
    float wall = smoothstep(0.010, -0.004, sd + wob) * smoothstep(-0.095, -0.060, sd);
    float innerMask = smoothstep(-0.060, -0.120, sd);

    float as = (g2_aster(d - c1, seed) + g2_aster(d - c2, seed + 3.13)) * innerMask;
    float ch = (g2_chrom(d - c1 * 0.55, seed) + g2_chrom(d - c2 * 0.55, seed + 1.7)) * innerMask;
    float midz = exp(-pow(d.y / 0.18, 2.0)) * exp(-pow(d.x / (0.10 + sep * 0.42), 2.0)) * sep * innerMask;
    float midFib = 0.55 + 0.45 * cos(d.y * 64.0 + seed);
    float spk = pow(smoothstep(0.80, 0.97, g2_vnoise(d * 24.0 + seed * 5.0)), 1.0) * innerMask;

    float cortexRing = exp(-pow((sd + 0.135) / 0.060, 2.0));
    float3 cortexCol = mix(float3(1.0, 0.28, 0.5), float3(0.65, 0.22, 1.0), 0.5 + 0.5 * cos(ang * 5.0 + seed));

    const float3 GREEN   = float3(0.30, 1.0, 0.38);
    const float3 WALLCOL = float3(1.0, 0.32, 0.14);
    const float3 BLUE    = float3(0.34, 0.30, 1.0);
    const float3 MAGENTA = float3(1.0, 0.18, 0.78);

    float3 interior = float3(0.02, 0.05, 0.03);
    interior += GREEN   * as   * 0.95;
    interior += BLUE    * ch   * 1.05;
    interior += MAGENTA * midz * midFib;
    interior += cortexCol * cortexRing * 1.3;
    interior  = mix(interior, float3(1.0, 0.6, 0.45), spk * 0.7);

    float3 cellCol = mix(interior, WALLCOL * 1.35, wall);
    float coverage = max(smoothstep(0.012, -0.012, sd + wob), wall);
    return float4(cellCol, coverage);
}

// MARK: - fragment

fragment float4 mitosisgen2_fragment(VertexOut in [[stage_in]],
                                     constant G2Uniforms& u [[buffer(0)]],
                                     constant G2Cell* cells [[buffer(1)]]) {
    float2 p = float2((in.uv.x * 2.0 - 1.0) * u.aspect, 1.0 - in.uv.y * 2.0);   // y up

    // background: domain-warped green filament web (neighbour cytoskeleton) — thin veins
    float2 w = p * 2.0;
    w += 0.35 * float2(g2_fbm(w * 1.4 + u.time * 0.02), g2_fbm(w.yx * 1.4 + 5.0));
    float fil = pow(g2_ridged(w * 2.6), 1.4);
    float3 col = float3(0.08, 0.52, 0.14) * fil * 0.55;

    // composite each live cell OVER the background (and earlier cells) — opaque objects
    uint n = min(u.cellCount, 32u);
    for (uint i = 0; i < n; i++) {
        float4 c = g2_drawCell(p - cells[i].pos, cells[i].phase, cells[i].radius, cells[i].axis, cells[i].seed);
        col = mix(col, c.rgb, c.a);
    }

    // music: timbre swings hue, energy lifts vividness, a drum transient adds a bounded glow
    col = g2_hueShift(col, (u.centroid - 0.4) * 2.0);
    col *= 0.7 + 0.6 * clamp(u.energy, 0.0, 1.2) + 0.12 * min(1.0, u.hit);

    col = 1.0 - exp(-col * 0.9);
    return float4(col, 1.0);
}
