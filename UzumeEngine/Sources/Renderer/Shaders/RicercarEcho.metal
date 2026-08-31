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
    uint  subSteps;     // pens per gesture — segments per gesture are subSteps - 1
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

// MARK: - Deposit: draw each gesture's pen path as a CONTINUOUS STROKE (RICERCAR-WIRE.3)
//
// ⚠ This replaced a point-sprite depositor, and the reason is Matt's: *"Why does it have to be a
// dotted line? This still is not reading as crisp / sharp."* He was right, and it was a mechanism
// problem no amount of resolution or falloff tuning could reach. The old path deposited each pen
// as a soft Gaussian POINT — inherited from FL.10's particle flow-field, where a chain of glowing
// dots IS the look. A calligraphic stroke is not a chain of dots. Worse, it failed in both
// directions at once: the soft sprite BODIES overlapped into haze while the tight `pow(halo,5)`
// CORES never merged, so the same stroke read as simultaneously blurry and beaded.
//
// A stroke is now drawn as a stroke. Consecutive pens are expanded into a capsule quad and shaded
// by DISTANCE TO THE SEGMENT — the standard antialiased-polyline construction (FA #64: this is
// textbook, not something to derive). Coverage is continuous along the path by construction, so
// beading is impossible rather than tuned-against, and the edge is a ~1px smoothstep, which is
// what "crisp" actually means. Joints are filled by the caps overlapping; additive overlap
// saturates under the display tonemap rather than showing as a bright knot.

constant float kStrokeWidth = 0.09;   // sprite extent -> stroke half-width

struct EchoSegOut {
    float4 position [[position]];
    float3 color;
    float2 p0;          // segment start, TRAIL PIXELS
    float2 p1;          // segment end, TRAIL PIXELS
    float  radius;      // half-width at this fragment, pixels
    float  hardness;    // 0 = slightly soft edge, 1 = hard flat-topped (brass slabs)
};

vertex EchoSegOut ricercar_echo_seg_vertex(uint vid [[vertex_id]],
                                           device const EchoPen* pens [[buffer(0)]],
                                           constant EchoConfig& cfg [[buffer(1)]]) {
    EchoSegOut o;
    const uint perGesture = max(cfg.subSteps, 2u) - 1u;      // segments per gesture
    const uint seg = vid / 6u, corner = vid % 6u;
    const uint g = seg / perGesture, k = seg % perGesture;
    const uint i0 = g * cfg.subSteps + k, i1 = i0 + 1u;

    EchoPen a = pens[i0], b = pens[i1];
    // ⚠ Y-DOWN PIXEL SPACE THROUGHOUT. The fragment shades from `[[position]]`, which is window
    // coordinates with y measured DOWN from the top, while pen positions are y-UP normalized. The
    // first version mixed the two: the capsule distance compared a y-down pixel against a y-up
    // centreline, so a stroke only registered where y happened to land near height/2 and the frame
    // rendered as a few specks along the middle. Flip here, once, and convert to clip at the end.
    float2 dim = float2(cfg.width, cfg.height);
    float2 p0 = float2(a.posSize.x, 1.0 - a.posSize.y) * dim;
    float2 p1 = float2(b.posSize.x, 1.0 - b.posSize.y) * dim;
    float w0 = a.posSize.z, w1 = b.posSize.z;
    float br = min(a.posSize.w, b.posSize.w);                // a segment is only as live as its dimmer end

    // Cull: an inactive endpoint, or a degenerate width, collapses the quad to zero area.
    if (br <= 0.0 || w0 <= 0.0 || w1 <= 0.0) {
        o.position = float4(0.0, 0.0, 2.0, 1.0);             // outside clip — discarded before raster
        o.color = float3(0.0); o.p0 = p0; o.p1 = p1; o.radius = 0.0; o.hardness = 0.0;
        return o;
    }

    // ⚠ `sz` is a legacy POINT SIZE: the full extent of a Gaussian sprite whose visible core was a
    // small fraction of it. As a hard capsule DIAMETER the same number draws a solid 48 px bar
    // (RICERCAR-WIRE.3's first render). kStrokeWidth converts sprite-extent to stroke half-width.
    float r = max(max(w0, w1) * kStrokeWidth, 0.75);
    float2 d = p1 - p0;
    float len = max(length(d), 1e-4);
    float2 dir = d / len;
    float2 nrm = float2(-dir.y, dir.x);

    // Quad spans exactly p0..p1 — NO cap extension. Extending by r let consecutive capsules
    // overlap by ~2r along the path, and under ADDITIVE blending that double-counts at every
    // joint, which re-introduced beading as a regular brightness ripple: the same artefact the
    // point sprites produced, arriving by a different route. Segments share endpoints, so a
    // smoothly-sampled path closes without them; only a hard corner could gap, and the pen
    // curves are sampled 6x per frame.
    const float2 uv[6] = { float2(0,-1), float2(0,1), float2(1,-1),
                           float2(1,-1), float2(0,1), float2(1,1) };
    float2 c = uv[corner];
    float2 pos = mix(p0, p1, c.x) + nrm * (c.y * r);

    float2 ndc = float2(pos.x / dim.x * 2.0 - 1.0, 1.0 - pos.y / dim.y * 2.0);
    o.position = float4(ndc, 0.0, 1.0);
    o.color = mix(a.color.rgb, b.color.rgb, c.x) * br;
    o.p0 = p0; o.p1 = p1;
    o.radius = mix(w0, w1, c.x) * kStrokeWidth;
    o.hardness = a.color.a;
    return o;
}

fragment float4 ricercar_echo_seg_fragment(EchoSegOut in [[stage_in]]) {
    // Distance from this pixel to the segment's centreline — the capsule SDF.
    float2 pt = in.position.xy;
    float2 d = in.p1 - in.p0;
    float dd = max(dot(d, d), 1e-6);
    float t = clamp(dot(pt - in.p0, d) / dd, 0.0, 1.0);
    float dist = length(pt - (in.p0 + d * t));

    float r = max(in.radius, 0.75);
    // Crisp edge: ~1 px of antialiasing and nothing more. `hardness` flattens the shoulder further
    // for brass, whose marks are meant to read as architectural slabs.
    float aa = mix(1.0, 0.5, in.hardness);
    float core = 1.0 - smoothstep(r - aa, r + aa * 0.5, dist);

    // A faint outer bloom so the stroke reads as PAINT rather than vector art — deliberately small,
    // because the T&F reference is painterly, not neon, and Matt has ruled out luminosity twice.
    float halo = exp(-max(0.0, dist - r) / max(1.5, r * 0.5)) * 0.18;

    float a = core + halo;
    return float4(in.color * a, a);
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
