// Physarum.metal — Throwaway physarum (slime-mold) agent-network SKETCH.
//
// NOT a preset: no JSON sidecar, no certification. Single purpose — prove
// framerate + look + the energy→consolidation musical role on Apple Silicon,
// gating a real preset increment (see the Physarum sketch spec, §7 go/no-go).
//
// Algorithm ported from the Jones / Bleuje / Sage Jenson physarum model
// (FA #73 — port, don't re-derive). Re-implemented in MSL: their GLSL is
// CC-BY-NC-SA, so the technique is reused but no source is copied.
//
// Shared FeatureVector / VertexOut / fullscreen_vertex / hsv2rgb come from
// Common.metal — one combined compilation unit (ShaderLibrary concatenates
// all Shaders/*.metal). Do NOT redefine them here.
//
// Per frame, one compute encoder runs three kernels with buffer barriers
// between them (Metal does not serialize consecutive dispatches —
// cf. FerrofluidParticles.swift): physarum_reset → physarum_agents →
// physarum_diffuse, ping-ponging two r16Float trail textures. The deposit +
// colorize stages of the canonical 4-shader loop are folded into the diffuse
// pass and the display fragment respectively (both are per-cell anyway).

#include <metal_stdlib>
using namespace metal;

// MARK: - PhysConfig (mirror of Swift PhysConfig)

struct PhysConfig {
    uint  width;
    uint  height;
    uint  agentCount;
    uint  frame;            // per-frame RNG salt
    float sensorDistance;   // px, energy-scaled
    float sensorAngle;      // rad
    float rotationAngle;    // rad
    float moveDistance;     // px/step, energy-scaled
    float depositF;         // deposit weight, energy-scaled
    float decay;            // per-frame trail multiply, energy-scaled toward persistence
    float collapseEnv;      // 0..1 collapse pulse — perturbs headings + gentle trail dip
    float energyEnv;        // 0..1 smoothed energy — palette + consolidation
    uint  paletteId;        // 0 biolum · 1 physarum · 2 kintsugi (display only)
};

// MARK: - PhysAgent (mirror of Swift PhysAgent, 16 bytes)

struct PhysAgent {
    float2 pos;     // pixel space [0,W)×[0,H)
    float  heading; // radians
    float  age;
};

// MARK: - Cheap integer-hash RNG → [0,1)

static inline float phys_hash(uint x) {
    x ^= x >> 16; x *= 0x7feb352du;
    x ^= x >> 15; x *= 0x846ca68bu;
    x ^= x >> 16;
    return float(x) * (1.0 / 4294967296.0);
}

// Toroidal sampler: address::repeat gives the wrap for free.
constexpr sampler physTrailSampler(address::repeat, filter::linear, coord::normalized);

// MARK: - Kernel 1: zero the per-cell deposit accumulator

kernel void physarum_reset(device atomic_uint*  acc [[buffer(0)]],
                           constant PhysConfig&  cfg [[buffer(1)]],
                           uint gid [[thread_position_in_grid]]) {
    if (gid >= cfg.width * cfg.height) { return; }
    atomic_store_explicit(&acc[gid], 0u, memory_order_relaxed);
}

// MARK: - Kernel 2: agents sense → steer → move → deposit

kernel void physarum_agents(device PhysAgent*    agents [[buffer(0)]],
                            constant PhysConfig&  cfg    [[buffer(1)]],
                            device atomic_uint*   acc    [[buffer(2)]],
                            texture2d<float, access::sample> trail [[texture(0)]],
                            uint gid [[thread_position_in_grid]]) {
    if (gid >= cfg.agentCount) { return; }
    PhysAgent a = agents[gid];
    float2 size = float2(cfg.width, cfg.height);

    // Sense the trail ahead, ahead-left, ahead-right at sensorDistance.
    float sd = cfg.sensorDistance, sa = cfg.sensorAngle;
    float2 dF = float2(cos(a.heading),      sin(a.heading));
    float2 dL = float2(cos(a.heading + sa), sin(a.heading + sa));
    float2 dR = float2(cos(a.heading - sa), sin(a.heading - sa));
    float wF = trail.sample(physTrailSampler, (a.pos + dF * sd) / size).r;
    float wL = trail.sample(physTrailSampler, (a.pos + dL * sd) / size).r;
    float wR = trail.sample(physTrailSampler, (a.pos + dR * sd) / size).r;

    // Steer toward the brightest sensor (Jones); random tie-break when both
    // sides win.
    float rnd = phys_hash(gid * 2654435761u + cfg.frame * 40503u);
    float ra = cfg.rotationAngle;
    if (wF >= wL && wF >= wR) {
        // straight
    } else if (wF < wL && wF < wR) {
        a.heading += (rnd < 0.5 ? -ra : ra);
    } else if (wL > wR) {
        a.heading += ra;
    } else {
        a.heading -= ra;
    }

    // Collapse accent: perturb headings → veins dissolve and regrow elsewhere.
    // Reroute, not erase: total deposit is conserved, so global luminance holds
    // (flash-safe per §5 / D-157).
    if (cfg.collapseEnv > 0.001) {
        float jitter = phys_hash(gid * 668265263u + cfg.frame * 374761u) - 0.5;
        a.heading += jitter * cfg.collapseEnv * 2.5;
    }

    // Step forward; wrap toroidally into [0,size).
    a.pos += float2(cos(a.heading), sin(a.heading)) * cfg.moveDistance;
    a.pos -= floor(a.pos / size) * size;
    a.age += 1.0;
    agents[gid] = a;

    // Deposit: atomic +1 at the new cell.
    uint cx = min(uint(a.pos.x), cfg.width  - 1u);
    uint cy = min(uint(a.pos.y), cfg.height - 1u);
    atomic_fetch_add_explicit(&acc[cy * cfg.width + cx], 1u, memory_order_relaxed);
}

// MARK: - Kernel 3: diffuse (3×3 box blur) + decay + this-frame deposit

kernel void physarum_diffuse(constant PhysConfig& cfg [[buffer(0)]],
                             device atomic_uint*  acc [[buffer(1)]],
                             texture2d<float, access::read>  src [[texture(0)]],
                             texture2d<float, access::write> dst [[texture(1)]],
                             uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= cfg.width || gid.y >= cfg.height) { return; }
    uint W = cfg.width, H = cfg.height;

    // 3×3 box blur of the previous trail, toroidal wrap on neighbour taps.
    float sum = 0.0;
    int iW = int(W), iH = int(H);
    for (int dy = -1; dy <= 1; ++dy) {
        for (int dx = -1; dx <= 1; ++dx) {
            int sx = (int(gid.x) + dx + iW) % iW;
            int sy = (int(gid.y) + dy + iH) % iH;
            sum += src.read(uint2(uint(sx), uint(sy))).r;
        }
    }
    float blurred = sum * (1.0 / 9.0);

    // Deposit: Bleuje's sqrt(count)·f reads better than linear count.
    uint count = atomic_load_explicit(&acc[gid.y * W + gid.x], memory_order_relaxed);
    float deposit = sqrt(float(count)) * cfg.depositF;

    // Decay toward persistence; collapse adds a gentle, bounded dip. Clamp
    // keeps the sqrt mapping stable under feedback (§9 precision risk).
    float decay = cfg.decay * (1.0 - 0.15 * cfg.collapseEnv);
    float v = blurred * decay + deposit;
    dst.write(float4(clamp(v, 0.0, 1.5), 0.0, 0.0, 1.0), gid);
}

// MARK: - Fragment: colorize the trail for display

fragment float4 physarum_trail_fragment(VertexOut in [[stage_in]],
                                        constant PhysConfig& cfg [[buffer(0)]],
                                        texture2d<float, access::sample> trail [[texture(0)]]) {
    float v = trail.sample(physTrailSampler, in.uv).r;
    float tone = pow(clamp(v, 0.0, 1.0), 0.65);   // lift mids so the faint web reads

    // Reference-anchored 3-stop ramp: ground (empty) → searching web → bright vein.
    float3 ground, web, vein;
    switch (cfg.paletteId) {
        case 1u:   // Physarum polycephalum (the organism, macro) — damp umber → chrome-yellow
            ground = float3(0.04, 0.025, 0.01); web = float3(0.55, 0.32, 0.05); vein = float3(1.00, 0.85, 0.20); break;
        case 2u:   // Kintsugi (gold-lacquer repair) — pure black → bright gold
            ground = float3(0.0);               web = float3(0.30, 0.18, 0.05); vein = float3(1.00, 0.80, 0.34); break;
        default:   // 0 — Bioluminescence (dinoflagellate / deep-sea) — near-black → cyan-white
            ground = float3(0.01, 0.02, 0.03);  web = float3(0.00, 0.45, 0.55); vein = float3(0.75, 0.98, 1.00); break;
    }
    float3 col = tone < 0.5 ? mix(ground, web, tone * 2.0)
                            : mix(web, vein, (tone - 0.5) * 2.0);
    col *= 0.92 + 0.25 * cfg.energyEnv;           // energy lifts the glow toward the peak
    return float4(col, 1.0);
}
