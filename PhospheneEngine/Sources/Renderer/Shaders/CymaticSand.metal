// CymaticSand.metal — vibrating-sand Chladni simulation (CR.2 rebuild).
//
// PORT, not derivation (FA #73). The technique is the "vibration-driven random
// walk" (Zhou et al., Physics Letters A 2017): sand bounces on a vibrating plate
// with a mean step length PROPORTIONAL to the local vibration amplitude, in a
// random direction, so grains accumulate at the nodal lines (amplitude ≈ 0). The
// per-frame update mirrors luciopaiva/chladni (MIT): `pos += gradientDrift·toNode
// + random·vibration`, with the vibration scaled by the local Chladni amplitude
// (the amplitude-proportional variant, addiebarron/chladni). No source copied.
//
// Why this preset is the phenomenon, not the figure (Matt M7 2026-07-22): grains
// VISIBLY shimmer where the plate flexes (antinodes), settle onto the nodal lines,
// and when the driving mode changes (brightness → mode) the grains sitting on the
// OLD nodes are suddenly at antinodes → they scatter and re-collect into the new
// figure. The music connection is direct and visible: energy scales the vibration,
// a beat is a burst, pitch picks the mode, harmony drives the hue.
//
// Kernels (one compute encoder/frame, barriers between — Metal does not serialize
// consecutive dispatches): sand_reset → sand_grains → sand_diffuse, ping-ponging
// two r16Float density textures. Display: sand_density_fragment.
//
// Shared FeatureVector / VertexOut / fullscreen_vertex come from Common.metal
// (ShaderLibrary concatenates Renderer/Shaders/*.metal). Do NOT redefine them.

#include <metal_stdlib>
using namespace metal;

// MARK: - SandConfig (mirror of Swift SandConfig)

struct SandConfig {
    uint  width;
    uint  height;
    uint  grainCount;
    uint  frame;          // per-frame RNG salt
    float ladderPos;      // mode-ladder position [0, kSandLadderCount-1] (brightness → mode)
    float vibAmp;         // baseline vibration step (px) at unit amplitude·energy
    float beatBurst;      // 0..~1 transient — grains jump on the beat
    float gradientDrift;  // px/frame drift toward the node (crisp lines)
    float minWalk;        // stochastic floor (px) so grains never fully freeze
    float decay;          // density-texture persistence (glow trails)
    float depositF;       // deposit weight
    float energyEnv;      // 0..~1.2 smoothed energy — vibration + glow
    float hueOffset;      // 0..1 harmonic-phase hue rotation
};

// MARK: - SandGrain (16 bytes; float2 pos + float age + pad)

struct SandGrain {
    float2 pos;   // pixel space [0,W)×[0,H)
    float  age;
    float  pad;
};

// MARK: - Mode ladder (same-parity, diagonal-free — CR.1.1 correction #5)

constant int kSandLadderCount = 11;
constant int2 kSandLadder[11] = {
    int2(1, 3), int2(2, 2), int2(2, 4), int2(3, 3), int2(3, 5), int2(4, 4),
    int2(2, 6), int2(4, 6), int2(5, 5), int2(3, 7), int2(5, 7)
};

constant float kSandPI = 3.14159265358979;

// MARK: - Plus-basis eigenmode field φ_{m,n} + analytic gradient (in ξ-space)

// Returns (value, ∂/∂ξ, ∂/∂η) for one mode.
static inline float3 sand_phi_grad(float2 p, int2 mn) {
    float mp = kSandPI * float(mn.x);
    float np = kSandPI * float(mn.y);
    float cmx = cos(mp * p.x), smx = sin(mp * p.x);
    float cnx = cos(np * p.x), snx = sin(np * p.x);
    float cmy = cos(mp * p.y), smy = sin(mp * p.y);
    float cny = cos(np * p.y), sny = sin(np * p.y);
    float value = cmx * cny + cnx * cmy;
    float dxi   = -mp * smx * cny - np * snx * cmy;
    float deta  = -np * cmx * sny - mp * cnx * smy;
    return float3(value, dxi, deta);
}

// Active field = crossfade of the two adjacent ladder modes (smooth mode change).
static inline float3 sand_field_grad(float2 p, float ladderPos) {
    int i = clamp(int(floor(ladderPos)), 0, kSandLadderCount - 2);
    float f = clamp(ladderPos - float(i), 0.0, 1.0);
    return mix(sand_phi_grad(p, kSandLadder[i]), sand_phi_grad(p, kSandLadder[i + 1]), f);
}

// MARK: - Cheap integer-hash RNG → [0,1)

static inline float sand_hash(uint x) {
    x ^= x >> 16; x *= 0x7feb352du;
    x ^= x >> 15; x *= 0x846ca68bu;
    x ^= x >> 16;
    return float(x) * (1.0 / 4294967296.0);
}

constexpr sampler sandSampler(address::clamp_to_edge, filter::linear, coord::normalized);

// MARK: - Kernel 1: zero the per-cell deposit accumulator

kernel void sand_reset(device atomic_uint*  acc [[buffer(0)]],
                       constant SandConfig&  cfg [[buffer(1)]],
                       uint gid [[thread_position_in_grid]]) {
    if (gid >= cfg.width * cfg.height) { return; }
    atomic_store_explicit(&acc[gid], 0u, memory_order_relaxed);
}

// MARK: - Kernel 2: grains do the vibration-driven random walk + deposit

kernel void sand_grains(device SandGrain*     grains [[buffer(0)]],
                        constant SandConfig&  cfg    [[buffer(1)]],
                        device atomic_uint*   acc    [[buffer(2)]],
                        uint gid [[thread_position_in_grid]]) {
    if (gid >= cfg.grainCount) { return; }
    SandGrain g = grains[gid];
    float2 size = float2(cfg.width, cfg.height);

    // Local plate vibration amplitude + gradient at this grain (current mode).
    float2 xi = clamp(g.pos / size, 0.0, 1.0);
    float3 fg = sand_field_grad(xi, cfg.ladderPos);
    float phi = fg.x;
    float2 grad = fg.yz;                 // ∇φ in ξ-space
    float amp = abs(phi);                // 0 at nodes … ~2 at antinodes

    // Vibration-driven random walk (Zhou 2017): step ∝ amplitude × drive, random
    // direction. CR.2.1 (M7: "expected more motion of the sand grains in louder
    // passages") — real energy tops out ~0.45 on music, so amplify it super-linearly
    // so loud passages visibly shake harder. `minWalk` keeps grains from freezing.
    float drive = 0.15 + 3.2 * cfg.energyEnv + cfg.beatBurst;   // real energy tops ~0.45 → high gain so loud pops
    float vib = cfg.vibAmp * amp * drive + cfg.minWalk;
    float ang = sand_hash(gid * 2654435761u + cfg.frame * 40503u) * 6.2831853;
    float2 rdir = float2(cos(ang), sin(ang));

    // Gradient drift toward the node (luciopaiva) — a fixed small step down |φ| for
    // crisp lines. Direction only (magnitude-independent), scaled to pixels.
    float glen = max(length(grad), 1e-4);
    float2 driftDir = (-sign(phi) * grad) / glen;

    g.pos += rdir * vib + driftDir * cfg.gradientDrift;
    // Bounded plate: reflect at the edges so grains stay on the plate (not clamp,
    // which would pile a bright rim).
    if (g.pos.x < 0.0)      { g.pos.x = -g.pos.x; }
    if (g.pos.x > size.x)   { g.pos.x = 2.0 * size.x - g.pos.x; }
    if (g.pos.y < 0.0)      { g.pos.y = -g.pos.y; }
    if (g.pos.y > size.y)   { g.pos.y = 2.0 * size.y - g.pos.y; }
    g.pos = clamp(g.pos, float2(0.0), size - 1.0);
    g.age += 1.0;
    grains[gid] = g;

    // Deposit +1 at the grain's cell.
    uint cx = min(uint(g.pos.x), cfg.width  - 1u);
    uint cy = min(uint(g.pos.y), cfg.height - 1u);
    atomic_fetch_add_explicit(&acc[cy * cfg.width + cx], 1u, memory_order_relaxed);
}

// MARK: - Kernel 3: diffuse (3×3 box blur) + decay + this-frame deposit

kernel void sand_diffuse(constant SandConfig& cfg [[buffer(0)]],
                         device atomic_uint*  acc [[buffer(1)]],
                         texture2d<float, access::read>  src [[texture(0)]],
                         texture2d<float, access::write> dst [[texture(1)]],
                         uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= cfg.width || gid.y >= cfg.height) { return; }
    uint W = cfg.width, H = cfg.height;
    int iW = int(W), iH = int(H);
    float sum = 0.0;
    for (int dy = -1; dy <= 1; ++dy) {
        for (int dx = -1; dx <= 1; ++dx) {
            int sx = clamp(int(gid.x) + dx, 0, iW - 1);
            int sy = clamp(int(gid.y) + dy, 0, iH - 1);
            sum += src.read(uint2(uint(sx), uint(sy))).r;
        }
    }
    float blurred = sum * (1.0 / 9.0);
    uint count = atomic_load_explicit(&acc[gid.y * W + gid.x], memory_order_relaxed);
    float deposit = sqrt(float(count)) * cfg.depositF;
    float v = blurred * cfg.decay + deposit;
    dst.write(float4(clamp(v, 0.0, 2.0), 0.0, 0.0, 1.0), gid);
}

// MARK: - Fragment: glowing jewel sand on deep black

static inline float3 sand_hsv2rgb(float3 c) {
    float3 pp = abs(fract(float3(c.x) + float3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
    return c.z * mix(float3(1.0), clamp(pp - 1.0, 0.0, 1.0), c.y);
}

fragment float4 sand_density_fragment(VertexOut in [[stage_in]],
                                      constant SandConfig& cfg [[buffer(0)]],
                                      texture2d<float, access::sample> density [[texture(0)]]) {
    float v = density.sample(sandSampler, in.uv).r;
    // Steeper curve so only concentrated sand (the nodal lines) reads bright and the
    // thin scatter between stays dark → crisp Chladni lines, not a filled wash.
    float tone = pow(clamp(v * 0.6, 0.0, 1.0), 1.3);

    // Jewel sand: hue sweeps sapphire→magenta→gold with radius + the harmonic offset.
    float2 c = in.uv - 0.5;
    float r = length(c);
    float hue = fract(0.58 + 0.42 * r + cfg.hueOffset);
    float3 jewel = sand_hsv2rgb(float3(hue, 0.85, 1.0));

    // Deep black ground → jewel sand; energy lifts the glow. HDR crests for bloom.
    float3 ground = float3(0.006, 0.007, 0.012);
    float3 col = ground + jewel * tone * (1.3 + 0.6 * cfg.energyEnv);
    return float4(col, 1.0);
}
