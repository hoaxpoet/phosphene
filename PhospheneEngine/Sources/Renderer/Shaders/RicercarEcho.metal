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
    float groundBlend;  // richness of the painterly atmospheric ground (0 = flat)
    float time;         // seconds — drifts the cloud ground + slowly shifts its hue
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

// MARK: - Soft value noise / fbm for the painterly atmospheric ground

static inline float echo_hash(float2 p) {
    p = fract(p * float2(127.1, 311.7)); p += dot(p, p + 34.5); return fract(p.x * p.y);
}
static inline float echo_vnoise(float2 p) {
    float2 i = floor(p), f = fract(p); float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(echo_hash(i), echo_hash(i + float2(1, 0)), u.x),
               mix(echo_hash(i + float2(0, 1)), echo_hash(i + float2(1, 1)), u.x), u.y);
}
static inline float echo_fbm(float2 p) {
    float v = 0.0, a = 0.5;
    for (int o = 0; o < 4; ++o) { v += a * echo_vnoise(p); p = p * 2.02 + 7.3; a *= 0.5; }
    return v;
}

// MARK: - Display: soft PAINTERLY atmospheric ground + the marks composited over it (not neon-glow)

fragment float4 ricercar_echo_display_fragment(VertexOut in [[stage_in]],
                                              constant EchoConfig& cfg [[buffer(0)]],
                                              texture2d<float, access::sample> trail [[texture(0)]]) {
    constexpr sampler s(address::clamp_to_edge, filter::linear, coord::normalized);
    float tt = cfg.time;

    // Painterly ground — soft drifting cloud texture in deep, warm-shifting tones (recessive backdrop, not
    // the subject). Two fbm layers slowly advecting; the palette drifts mauve↔plum over ~30 s (Fantasia mood).
    float2 gp = float2(in.uv.x * cfg.aspect, in.uv.y);
    float cloud = echo_fbm(gp * 2.3 + float2(tt * 0.020, -tt * 0.014)) * 0.65
                + echo_fbm(gp * 5.1 - float2(tt * 0.011, tt * 0.007)) * 0.35;
    cloud = cloud * cloud * 1.4;                      // more contrast → billows, not flat fog
    float hueT = 0.5 + 0.5 * sin(tt * 0.06);
    float3 coolTone = float3(0.024, 0.045, 0.150);   // deep saturated blue
    float3 warmTone = float3(0.150, 0.070, 0.035);   // deep warm amber/rust
    float3 ground = mix(coolTone, warmTone, hueT) * (0.30 + 1.5 * cloud) * cfg.groundBlend;
    ground *= mix(0.55, 1.15, in.uv.y);              // top-darker depth

    // Marks — a soft small bloom, then tonemap so bright marks keep their COLOUR (painterly) instead of
    // blowing out to neon white. exposure stays modest (we are NOT chasing luminosity).
    float2 texel = 1.0 / float2(cfg.width, cfg.height);
    float3 hdr = trail.sample(s, in.uv).rgb;
    float3 bloom = float3(0.0);
    const float2 offs[4] = { float2(2, 0), float2(-2, 0), float2(0, 2), float2(0, -2) };
    for (int i = 0; i < 4; ++i) { bloom += trail.sample(s, in.uv + offs[i] * texel).rgb; }
    hdr += bloom * 0.3;
    float3 marks = 1.0 - exp(-hdr * cfg.exposure);

    return float4(ground + marks, 1.0);
}
