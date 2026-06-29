// Mitosis.metal — Throwaway reaction–diffusion (Gray–Scott) cell-colony SKETCH.
//
// NOT a preset: no JSON sidecar, no certification. Single purpose — prove
// framerate + the onset→division SYNC that physarum/Filigree couldn't carry
// (FILIGREE_DESIGN §"sync finding"), gating a real preset increment.
//
// Algorithm ported from the public-domain Gray–Scott model (FA #73 — port,
// don't re-derive). References: Karl Sims (karlsims.com/rd.html), mrob Xmorphia
// parameter atlas, pmneila jsexp GrayScott. Re-implemented in our own MSL.
//
//   A' = A + (Da·∇²A − A·B² + F·(1−A))·dt
//   B' = B + (Db·∇²B + A·B² − (k+F)·B)·dt
//   Da=1.0 Db=0.5 dt=1.0; Laplacian 3×3 [[.05,.2,.05],[.2,−1,.2],[.05,.2,.05]]
//   toroidal. Mitosis regime F≈0.0367 k≈0.0649. ~10–20 react substeps/frame.
//
// State lives in ONE rg16Float texture pair, ping-ponged per substep: r=A, g=B
// (cleaner than two r16Float — half the binds, one filterable sample for display).
// Metal does not serialise consecutive dispatches, so the geometry barriers
// (.textures) between substeps (cf. FerrofluidParticles.swift / Physarum.metal).
//
// Shared FeatureVector / VertexOut / fullscreen_vertex / hsv2rgb come from
// Common.metal (ShaderLibrary concatenates all Shaders/*.metal). Do NOT redefine.

#include <metal_stdlib>
using namespace metal;

// MARK: - MitosisConfig (mirror of Swift MitosisConfig)

struct MitosisConfig {
    uint  width;
    uint  height;
    uint  frame;        // per-frame RNG salt (onset injection sites)
    float Da;           // A diffusion (≈1.0)
    float Db;           // B diffusion (≈0.5)
    float feed;         // F — feed rate; slow envelope shifts the regime
    float kill;         // k — kill rate
    float dt;           // integration step (≈1.0; energy can quicken metabolism)
    float feedBurst;    // 0..1 onset pulse → localized B injection = visible mitosis
    float energyEnv;    // 0..1 smoothed energy — display brightness
    uint  paletteId;    // display only
    float _pad;
};

// MARK: - Toroidal neighbour read (wrap for free is via % since access::read has no sampler wrap)

static inline float2 rd_read(texture2d<float, access::read> t, int x, int y, int W, int H) {
    int sx = (x % W + W) % W;
    int sy = (y % H + H) % H;
    return t.read(uint2(uint(sx), uint(sy))).rg;
}

static inline float rd_hash(uint x) {
    x ^= x >> 16; x *= 0x7feb352du;
    x ^= x >> 15; x *= 0x846ca68bu;
    x ^= x >> 16;
    return float(x) * (1.0 / 4294967296.0);
}

// MARK: - Kernel: one Gray–Scott react+diffuse substep, src → dst

kernel void mitosis_react(constant MitosisConfig& cfg [[buffer(0)]],
                          texture2d<float, access::read>  src [[texture(0)]],
                          texture2d<float, access::write> dst [[texture(1)]],
                          uint2 gid [[thread_position_in_grid]]) {
    int W = int(cfg.width), H = int(cfg.height);
    if (gid.x >= cfg.width || gid.y >= cfg.height) { return; }
    int x = int(gid.x), y = int(gid.y);

    float2 c = rd_read(src, x, y, W, H);
    float A = c.r, B = c.g;

    // Weighted toroidal Laplacian (the canonical 3×3 kernel — corners .05, edges .2).
    float2 lap =
        (rd_read(src, x-1, y,   W, H) + rd_read(src, x+1, y,   W, H) +
         rd_read(src, x,   y-1, W, H) + rd_read(src, x,   y+1, W, H)) * 0.2 +
        (rd_read(src, x-1, y-1, W, H) + rd_read(src, x+1, y-1, W, H) +
         rd_read(src, x-1, y+1, W, H) + rd_read(src, x+1, y+1, W, H)) * 0.05
        - c;

    float F = cfg.feed, k = cfg.kill, dt = cfg.dt;
    float reaction = A * B * B;
    float nA = A + (cfg.Da * lap.r - reaction + F * (1.0 - A)) * dt;
    float nB = B + (cfg.Db * lap.g + reaction - (k + F) * B) * dt;

    // Division↔merge is driven by the onset-oscillated kill rate `k` (CPU-side in
    // MitosisGeometry.update — onset drops k → division burst; base k leans to the death
    // side → cells die back between beats). Constant-k Gray–Scott freezes to a static
    // grid (MITOSIS.2), so the music keeps the field churning.
    //
    // Survival floor: a sparse nucleation trickle GATED BY MUSIC ENERGY (`cfg.feedBurst`,
    // set on the first substep only). At the death-leaning base k the field would
    // otherwise die out — and dead Gray–Scott can't revive (no B → no A·B² reaction) —
    // so this keeps a couple of cells alive while music plays (and reads as "starting
    // from a couple of cells", Matt MITOSIS.2). Silence → no nucleation → calm fade.
    if (cfg.feedBurst > 0.0001 && B < 0.04 && A > 0.5) {
        float r = rd_hash((gid.y * cfg.width + gid.x) * 2654435761u + cfg.frame * 40503u);
        if (r < cfg.feedBurst * 0.00002) { nB = 0.5; nA = 0.5; }   // nucleate a cell
    }

    dst.write(float4(clamp(nA, 0.0, 1.0), clamp(nB, 0.0, 1.0), 0.0, 1.0), gid);
}

// MARK: - Fragment: colorize B for display

fragment float4 mitosis_fragment(VertexOut in [[stage_in]],
                                 constant MitosisConfig& cfg [[buffer(0)]],
                                 texture2d<float, access::sample> state [[texture(0)]]) {
    constexpr sampler s(address::repeat, filter::linear, coord::normalized);
    float B = state.sample(s, in.uv).g;
    float tone = pow(clamp(B * 2.4, 0.0, 1.0), 0.75);   // lift mids so spot rims read

    // 3-stop ramp ground → membrane → nucleus. Sketch palette only (final grade
    // is increment work, §10) — abstract cells, cyan-on-dark biological reading.
    float3 ground = float3(0.01, 0.02, 0.03);
    float3 membrane = float3(0.05, 0.45, 0.55);
    float3 nucleus = float3(0.85, 0.98, 1.00);
    float3 col = tone < 0.5 ? mix(ground, membrane, tone * 2.0)
                            : mix(membrane, nucleus, (tone - 0.5) * 2.0);
    col *= 0.90 + 0.30 * cfg.energyEnv;
    return float4(col, 1.0);
}
