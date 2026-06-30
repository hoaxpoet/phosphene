// Gen2Cell.metal — THROWAWAY SKETCH for Mitosis gen-2 ("detailed psychedelic cell
// division"). Proves the procedural FORM only: can we draw one convincing detailed
// dividing cell — dumbbell furrow + two radial green asters + red cortical rim +
// blue chromatin — on a green filament field, music-coloured, at 60 fps?
//
// Reference: docs/VISUAL_REFERENCES/mitosis/gen2_cytokinesis_confocal.png (cytokinesis).
// Substrate (locked): explicit per-cell objects, NOT Gray–Scott. This sketch hardcodes
// a handful of cells and drives the central cell's division phase off time. Cell
// management (spawn/track/phase from the music) is the real increment's job, not the
// sketch's — the sketch only has to make the LOOK land.
//
// Compiled at runtime by MitosisGen2SketchRenderTests; never linked into the engine.

#include <metal_stdlib>
using namespace metal;

struct Gen2Uniforms {
    float  time;
    float2 resolution;
    float  energy;     // 0..1 — global vividness (MITOSIS.5 reuse, sketched)
    float  centroid;   // 0..1 — timbre → palette hue bias (MITOSIS.5 reuse, sketched)
};

// MARK: - fullscreen triangle

struct VOut { float4 pos [[position]]; };

vertex VOut gen2_vertex(uint vid [[vertex_id]]) {
    float2 p = float2((vid << 1) & 2, vid & 2);   // (0,0) (2,0) (0,2)
    VOut o;
    o.pos = float4(p * 2.0 - 1.0, 0.0, 1.0);
    return o;
}

// MARK: - noise

static inline float hash21(float2 p) {
    p = fract(p * float2(123.34, 345.45));
    p += dot(p, p + 34.123);
    return fract(p.x * p.y);
}
static inline float vnoise(float2 p) {
    float2 i = floor(p), f = fract(p);
    float a = hash21(i), b = hash21(i + float2(1, 0));
    float c = hash21(i + float2(0, 1)), d = hash21(i + float2(1, 1));
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}
static inline float fbm(float2 p) {
    float s = 0.0, a = 0.5;
    for (int i = 0; i < 5; i++) { s += a * vnoise(p); p *= 2.0; a *= 0.5; }
    return s;
}
// ridged fbm → thin vein/filament strands rather than soft clouds
static inline float ridged(float2 p) {
    float s = 0.0, a = 0.5;
    for (int i = 0; i < 4; i++) {
        float r = 1.0 - abs(2.0 * vnoise(p) - 1.0);
        s += a * r * r; p *= 2.1; a *= 0.5;
    }
    return s;
}
static inline float smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}
static inline float2 rot(float2 v, float a) {
    float c = cos(a), s = sin(a);
    return float2(c * v.x - s * v.y, s * v.x + c * v.y);
}
// hue rotation around the (1,1,1) luma axis (Rodrigues)
static inline float3 hueShift(float3 col, float angle) {
    const float3 k = float3(0.57735027);
    float c = cos(angle), s = sin(angle);
    return col * c + cross(k, col) * s + k * dot(k, col) * (1.0 - c);
}

// MARK: - the cell

// One aster: many fine, IRREGULAR fibres bursting radially from a small bright pole.
// Fibre brightness/length is sampled on a circle (seamless, no ±π seam) so it reads as
// organic microtubules, not a geometric sunburst. Fibres reach out toward the rim.
static inline float aster(float2 q, float seed) {
    float r = length(q);
    float ang = atan2(q.y, q.x);
    float2 ring = float2(cos(ang), sin(ang));
    float lo = vnoise(ring * 22.0 + seed);            // dense fibres
    float hi = vnoise(ring * 48.0 + seed * 2.3);      // finer fibres between
    float streak = pow(0.45 * lo + 0.55 * hi, 1.8);   // gentle sharpen → fine fur, not spikes
    float radial = smoothstep(1.05, 0.05, r) * (0.62 + 0.22 * exp(-r * 1.8));  // flatter — no white center spike
    float core   = exp(-r * r * 200.0) * 0.3;         // small, modest pole (stays green, not white)
    return streak * radial * 1.1 + core;
}
// Mottled chromatin — a real blue/purple DNA mass in each lobe (a co-feature, not a dot).
static inline float chrom(float2 q, float seed) {
    float m = exp(-dot(q, q) * 15.0);                 // tighter — a localized mass, not a center-fill
    float mott = 0.45 + 0.55 * vnoise(q * 13.0 + seed);
    return m * mott;
}

// A whole cell, returned as (rgb, coverage) so it COMPOSITES OVER the background and the
// membrane OCCLUDES its interior — a cell is an opaque object, not an additive glow.
// phase 0..1: interphase(0) → metaphase → anaphase → cytokinesis dumbbell(~0.85) → split(1).
static inline float4 drawCell(float2 q, float phase, float radius, float axis, float seed) {
    float2 d = rot(q, -axis) / radius;          // unit-radius cell space, division axis = x
    float ang = atan2(d.y, d.x);

    float sep = smoothstep(0.20, 1.0, phase) * 1.0;   // poles separate as it divides
    float k   = mix(0.55, 0.06, smoothstep(0.20, 0.95, phase));  // neck pinches (furrow)
    float poleR = 0.55;
    float2 c1 = float2(-sep * 0.5, 0.0), c2 = float2(sep * 0.5, 0.0);
    float d1 = length(d - c1) - poleR;
    float d2 = length(d - c2) - poleR;
    float sd = smin(d1, d2, k);                 // dumbbell SDF, <0 inside

    // The membrane = a thick SOLID WALL hugging the boundary from just inside. Opaque.
    float wob  = 0.012 * (vnoise(float2(ang * 3.0, seed)) - 0.5);
    float wall = smoothstep(0.010, -0.004, sd + wob)       // crisp outer edge at boundary
               * smoothstep(-0.095, -0.060, sd);           // solid band ~0.06–0.095 deep

    // Interior content lives strictly INSIDE the wall — nothing bleeds through the membrane.
    float innerMask = smoothstep(-0.060, -0.120, sd);

    float as = (aster(d - c1, seed) + aster(d - c2, seed + 3.13)) * innerMask;
    float ch = (chrom(d - c1 * 0.55, seed) + chrom(d - c2 * 0.55, seed + 1.7)) * innerMask;
    float midz = exp(-pow(d.y / 0.18, 2.0)) * exp(-pow(d.x / (0.10 + sep * 0.42), 2.0)) * sep * innerMask;
    float midFib = 0.55 + 0.45 * cos(d.y * 64.0 + seed);
    float spk = pow(smoothstep(0.80, 0.97, vnoise(d * 24.0 + seed * 5.0)), 1.0) * innerMask;

    // Cortical colour ring: a band of colour RIGHT INSIDE the membrane (the reference's
    // coloured cortex around the rim), hue varying around the perimeter so it's not flat.
    float cortexRing = exp(-pow((sd + 0.135) / 0.060, 2.0));
    float3 cortexCol = mix(float3(1.0, 0.28, 0.5), float3(0.65, 0.22, 1.0), 0.5 + 0.5 * cos(ang * 5.0 + seed));

    const float3 GREEN   = float3(0.30, 1.0, 0.38);
    const float3 WALLCOL = float3(1.0, 0.32, 0.14);   // red/orange membrane
    const float3 BLUE    = float3(0.34, 0.30, 1.0);   // chromatin
    const float3 MAGENTA = float3(1.0, 0.18, 0.78);   // spindle midzone

    // interior (linear, inside the wall)
    float3 interior = float3(0.02, 0.05, 0.03);       // faint cytoplasm, not pure black
    interior += GREEN   * as   * 0.9;
    interior += BLUE    * ch   * 1.0;
    interior += MAGENTA * midz * midFib;
    interior += cortexCol * cortexRing * 1.3;          // the colour ring around the membrane
    interior  = mix(interior, float3(1.0, 0.6, 0.45), spk * 0.7);  // vesicle speckles

    // membrane paints OPAQUELY over the interior; cell covers the background within its boundary
    float3 cellCol = mix(interior, WALLCOL * 1.35, wall);
    float coverage = max(smoothstep(0.012, -0.012, sd + wob), wall);
    return float4(cellCol, coverage);
}

// MARK: - fragment

fragment float4 gen2_fragment(VOut in [[stage_in]],
                              constant Gen2Uniforms &u [[buffer(0)]]) {
    float2 frag = in.pos.xy;
    float2 p = (2.0 * frag - u.resolution) / u.resolution.y;
    p.y = -p.y;                                  // y up

    // background: domain-warped green filament web (neighbour cytoskeleton) — thin veins
    float2 w = p * 2.0;
    w += 0.35 * float2(fbm(w * 1.4 + u.time * 0.02), fbm(w.yx * 1.4 + 5.0));
    float fil = pow(ridged(w * 2.6), 1.4);
    float3 col = float3(0.08, 0.52, 0.14) * fil * 0.55;

    // cells composite OVER the background (and each other) — opaque objects, not glows
    float4 n1 = drawCell(p - float2(-1.65,  0.85), 0.05, 0.95, 0.6, 17.0);
    float4 n2 = drawCell(p - float2( 1.75, -0.70), 0.05, 1.05, 2.1, 41.0);
    float4 n3 = drawCell(p - float2( 1.45,  1.10), 0.05, 0.85, 4.3, 63.0);
    col = mix(col, n1.rgb, n1.a);
    col = mix(col, n2.rgb, n2.a);
    col = mix(col, n3.rgb, n3.a);

    // the showcase: one large cell dividing on a ~7 s cycle, drawn last (on top)
    float phase = fract(u.time / 7.0);
    float4 cell = drawCell(p, phase, 0.62, -0.42, 5.0);
    col = mix(col, cell.rgb, cell.a);

    // music (MITOSIS.5 reuse, sketched): timbre swings hue, energy lifts vividness
    col = hueShift(col, (u.centroid - 0.4) * 2.0);
    col *= 0.7 + 0.6 * u.energy;

    col = 1.0 - exp(-col * 0.9);                 // tonemap, keep glows from clipping to white
    return float4(col, 1.0);
}
