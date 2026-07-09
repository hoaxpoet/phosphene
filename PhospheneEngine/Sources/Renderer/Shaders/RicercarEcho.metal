// RicercarEcho.metal — Fantasia-fugue prototype: a clear GESTURE that visibly ANSWERS ITSELF.
//
// Concept (design-aligned with Matt, 2026-07-09): a fugue = repetition with variation. A voice plays → an
// abstract gesture is DRAWN (a pen traces a curve over time — the movement IS the sound); then it ECHOES —
// the same recognisable stroke returns, transformed by a small fugue grammar (answer higher, invert, augment,
// diminish) and recoloured to another voice — accumulating (stretto) on the swell. Recognition is a FEATURE,
// not a whisper (Matt: "more than subtle"). Glowing strokes over a deep ground (FL.10 substrate, kept).
//
// This file is a PROTOTYPE depositor: pens (curve-tracing points) deposit additive glow into an HDR trail
// that decays each frame — the drawn strokes linger and weave. Reuses `fullscreen_vertex` (Common.metal).

#include <metal_stdlib>
using namespace metal;

// MARK: - EchoConfig (mirror of Swift RicercarEchoConfig — 3 uint + 5 float, all 4-byte, no padding)

struct EchoConfig {
    uint  width;
    uint  height;
    uint  penCount;
    float decay;        // per-frame trail multiply (stroke persistence → how long the weave holds)
    float exposure;     // display tonemap gain
    float aspect;       // width/height (keep the curve's proportions in sample space)
    float groundBlend;  // 0 deep-indigo ground … reserved for the colour-shifting cloud ground (later)
    float pad0;
};

// MARK: - EchoPen (mirror of Swift EchoPen, 32 bytes — two float4, no alignment trap)

struct EchoPen {
    float4 posSize;   // pos.xy in [0,1] trail space; .z = point size (px); .w = brightness (0 = inactive)
    float4 color;     // rgb emissive; .a unused
};

// MARK: - Deposit: draw each active pen as a soft additive glow sprite at its current curve position

struct EchoPointOut {
    float4 position [[position]];
    float  pointSize [[point_size]];
    float3 color;
};

vertex EchoPointOut ricercar_echo_point_vertex(uint vid [[vertex_id]],
                                               device const EchoPen* pens [[buffer(0)]],
                                               constant EchoConfig& cfg [[buffer(1)]]) {
    EchoPen p = pens[vid];
    EchoPointOut o;
    float2 pos = p.posSize.xy;
    o.position = float4(pos.x * 2.0 - 1.0, pos.y * 2.0 - 1.0, 0.0, 1.0);
    o.pointSize = max(1.0, p.posSize.z) * (p.posSize.w > 0.0 ? 1.0 : 0.0);   // size 0 ⇒ culled when inactive
    o.color = p.color.rgb * p.posSize.w;                                     // brightness gates emission
    return o;
}

fragment float4 ricercar_echo_point_fragment(EchoPointOut in [[stage_in]],
                                             float2 pc [[point_coord]]) {
    // Soft round sprite — bright core, smooth halo, so overlapping deposits fuse into a continuous stroke.
    float d = length(pc - 0.5) * 2.0;              // 0 centre → 1 edge
    float core = smoothstep(1.0, 0.0, d);
    float w = core * core;                          // soft shoulder
    return float4(in.color * w, w);
}

// MARK: - Decay the previous trail into the current target (opaque)

fragment float4 ricercar_echo_decay_fragment(VertexOut in [[stage_in]],
                                            constant EchoConfig& cfg [[buffer(0)]],
                                            texture2d<float, access::sample> trail [[texture(0)]]) {
    constexpr sampler s(address::clamp_to_edge, filter::linear, coord::normalized);
    return float4(trail.sample(s, in.uv).rgb * cfg.decay, 1.0);
}

// MARK: - Display: tonemap the HDR trail → luminous over a deep ground

fragment float4 ricercar_echo_display_fragment(VertexOut in [[stage_in]],
                                              constant EchoConfig& cfg [[buffer(0)]],
                                              texture2d<float, access::sample> trail [[texture(0)]]) {
    constexpr sampler s(address::clamp_to_edge, filter::linear, coord::normalized);
    float2 texel = 1.0 / float2(cfg.width, cfg.height);
    float3 hdr = trail.sample(s, in.uv).rgb;
    float3 bloom = float3(0.0);
    const float2 offs[4] = { float2(3, 0), float2(-3, 0), float2(0, 3), float2(0, -3) };
    for (int i = 0; i < 4; ++i) { bloom += trail.sample(s, in.uv + offs[i] * texel).rgb; }
    hdr += bloom * 0.4;
    hdr *= cfg.exposure;
    float3 tone = 1.0 - exp(-hdr);
    float3 groundTop = float3(0.010, 0.012, 0.030);
    float3 groundBot = float3(0.020, 0.022, 0.050);
    float3 ground = mix(groundBot, groundTop, in.uv.y);
    return float4(ground + tone, 1.0);
}
