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
    float feedBurst;    // 0..1 reseed gate (cluster nucleation)
    float energyEnv;    // 0..1 smoothed energy — display brightness
    uint  paletteId;    // display only
    float huePhase;     // music-paced accumulating hue animation (energy → speed)
    float colorBias;    // spectral-centroid hue offset (timbre → colour)
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
    // Survival floor: a CLUSTER reseed GATED BY MUSIC ENERGY (`cfg.feedBurst`, set on
    // the first substep only). At the death-leaning base k an ISOLATED nucleated cell
    // dies (below critical mass) — only a small cluster establishes (MITOSIS.2b) — so
    // each event stamps a ~2 px disk at a per-frame hashed centre. Keeps a couple of
    // cells alive while music plays regardless of energy level (dead Gray–Scott can't
    // revive: no B → no A·B² reaction). Silence → no reseed → calm fade (no Drift-Motes).
    if (cfg.feedBurst > 0.0001 && B < 0.20) {
        uint cx = uint(rd_hash(cfg.frame * 9781u + 17u) * float(cfg.width));
        uint cy = uint(rd_hash(cfg.frame * 6271u + 31u) * float(cfg.height));
        float dx = float(gid.x) - float(cx), dy = float(gid.y) - float(cy);
        if (dx * dx + dy * dy < 4.0 && rd_hash(cfg.frame * 40503u) < cfg.feedBurst * 0.20) {
            nB = 0.5; nA = 0.5;   // stamp a small establishing cluster (population backbone)
        }
    }

    dst.write(float4(clamp(nA, 0.0, 1.0), clamp(nB, 0.0, 1.0), 0.0, 1.0), gid);
}

// MARK: - Fragment: fluorescence-microscopy colorize (MITOSIS.2c)

// "Psychedelic cell division" (Matt): magenta nuclei (cell interiors) + electric
// cyan/green membranes (the B-gradient at cell boundaries) glowing on black — the look
// of fluorescence microscopy of dividing cells. A slow hue shimmer over space+time gives
// the psychedelic shift. The gradient-driven membrane sharpens the cell read (the blur
// complaint is also addressed by the higher sim resolution).
fragment float4 mitosis_fragment(VertexOut in [[stage_in]],
                                 constant MitosisConfig& cfg [[buffer(0)]],
                                 texture2d<float, access::sample> state [[texture(0)]]) {
    constexpr sampler s(address::repeat, filter::linear, coord::normalized);
    float2 texel = float2(1.0 / float(cfg.width), 1.0 / float(cfg.height));
    float bC = state.sample(s, in.uv).g;
    float bL = state.sample(s, in.uv - float2(texel.x, 0.0)).g;
    float bR = state.sample(s, in.uv + float2(texel.x, 0.0)).g;
    float bD = state.sample(s, in.uv - float2(0.0, texel.y)).g;
    float bU = state.sample(s, in.uv + float2(0.0, texel.y)).g;
    float grad = length(float2(bR - bL, bU - bD));        // cell boundary (membrane)

    float nucleus  = smoothstep(0.22, 0.55, bC);          // bright cell interior → nucleus stain
    float membrane = smoothstep(0.03, 0.16, grad);        // cell boundary → membrane stain

    // Psychedelic hue tied to the MUSIC (Matt MITOSIS.2c): `huePhase` accumulates
    // energy-paced (louder → faster colour motion); `colorBias` from the spectral
    // centroid shifts the palette with the timbre; a spatial term sends colour waves
    // travelling across the field. The two-stain identity holds — nucleus stays in the
    // magenta family, membrane in the cyan/green family — but both drift with the music.
    float wave = cfg.huePhase + in.uv.x * 0.9 + in.uv.y * 0.5;
    float nucHue = fract(0.88 + cfg.colorBias * 0.35 + 0.10 * sin(wave));         // magenta family, drifting
    float memHue = fract(0.48 + cfg.colorBias * 0.35 + 0.10 * sin(wave + 2.0));   // cyan/green family, drifting
    float3 nucCol = hsv2rgb(float3(nucHue, 0.95, 1.0));
    float3 memCol = hsv2rgb(float3(memHue, 0.85, 1.0));

    float3 col = nucCol * nucleus * 1.15 + memCol * membrane * 1.5;   // additive fluorescence on black
    col *= 0.9 + 0.3 * clamp(cfg.energyEnv, 0.0, 1.0);
    return float4(min(col, 1.4), 1.0);                    // bright cores allowed; clamp the bloom
}
