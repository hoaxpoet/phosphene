// RicercarFluid.metal — GPU fluid dye simulation for Ricercar (the Fantasia rebuild, RICERCAR-FL).
//
// The three prior Ricercar attempts (R.2 flowing-field, IFC.6 marks, RW Skein-recolour) all used
// opaque paint on a flat canvas and were rejected as "not Fantasia / just Skein" (RICERCAR_DESIGN
// §FANTASIA REBUILD). The corrected paradigm: LUMINOUS FLOWING COLOUR MASSES (ink-in-water, ref
// docs/VISUAL_REFERENCES/ricercar/02) — a real GPU fluid dye sim — with glowing weaving ribbons on top
// (ref 01) added later.
//
// FA #73 — PORT the canonical prior art, don't re-derive. This is Jos Stam's stable-fluids method
// (GPU Gems Ch.38; the widely-ported Pavel Dobryakov WebGL-Fluid-Simulation, MIT), re-implemented in
// MSL. Per frame the geometry conformer dispatches: splat → curl → vorticity confinement → divergence
// → pressure Jacobi (N iters) → gradient-subtract → advect velocity → advect dye (+ dissipate). The
// billowing that plain curl-noise advection (R.2) lacked comes from VORTICITY CONFINEMENT.
//
// Fields (ping-pong texture pairs, half-float):
//   velocity  rg16Float   (vx, vy)         dye       rgba16Float (r,g,b, unused)
//   pressure  r16Float                     divergence/curl  r16Float (scratch, single)
//
// Shared FeatureVector / VertexOut / fullscreen_vertex come from Common.metal (ShaderLibrary
// concatenates all Renderer/Shaders/*.metal). Do NOT redefine them here.

#include <metal_stdlib>
using namespace metal;

// MARK: - FluidConfig (mirror of Swift RicercarFluidConfig)

struct FluidConfig {
    uint  width;
    uint  height;
    float dt;                 // timestep (~0.016 scaled)
    float velocityDissipation; // <1: velocity decays (drag), e.g. 0.2/s
    float dyeDissipation;      // <1: dye fades so the field breathes, not fills
    float vorticity;           // vorticity-confinement strength (the billowing)
    float pressure;            // pressure-fade per frame (Jacobi warm-start), ~0.8
    float exposure;            // display: dye → luminance gain (HDR feel)
    float time;                // seconds
    float ribbonBrightness;    // FL.9: soft-wash gain for the demoted fluid dye (1 in production; 0 = wash off)
};

// MARK: - Grid helpers

// Texel-centre UV for a thread. Fields are stored at texel centres.
static inline float2 fl_uv(uint2 gid, uint W, uint H) {
    return (float2(gid) + 0.5) / float2(W, H);
}

// Clamp-to-edge bilinear sample of an rg (velocity) field at UV in [0,1].
static inline float2 fl_bilerp2(texture2d<float, access::read> t, float2 uv, uint W, uint H) {
    float2 st = uv * float2(W, H) - 0.5;
    float2 fl = floor(st);
    float2 f  = st - fl;
    int2 i0 = int2(fl);
    int2 c00 = clamp(i0 + int2(0, 0), int2(0), int2(W - 1, H - 1));
    int2 c10 = clamp(i0 + int2(1, 0), int2(0), int2(W - 1, H - 1));
    int2 c01 = clamp(i0 + int2(0, 1), int2(0), int2(W - 1, H - 1));
    int2 c11 = clamp(i0 + int2(1, 1), int2(0), int2(W - 1, H - 1));
    float2 a = mix(t.read(uint2(c00)).rg, t.read(uint2(c10)).rg, f.x);
    float2 b = mix(t.read(uint2(c01)).rg, t.read(uint2(c11)).rg, f.x);
    return mix(a, b, f.y);
}

// Clamp-to-edge bilinear sample of an rgba (dye) field.
static inline float3 fl_bilerp3(texture2d<float, access::read> t, float2 uv, uint W, uint H) {
    float2 st = uv * float2(W, H) - 0.5;
    float2 fl = floor(st);
    float2 f  = st - fl;
    int2 i0 = int2(fl);
    int2 c00 = clamp(i0 + int2(0, 0), int2(0), int2(W - 1, H - 1));
    int2 c10 = clamp(i0 + int2(1, 0), int2(0), int2(W - 1, H - 1));
    int2 c01 = clamp(i0 + int2(0, 1), int2(0), int2(W - 1, H - 1));
    int2 c11 = clamp(i0 + int2(1, 1), int2(0), int2(W - 1, H - 1));
    float3 a = mix(t.read(uint2(c00)).rgb, t.read(uint2(c10)).rgb, f.x);
    float3 b = mix(t.read(uint2(c01)).rgb, t.read(uint2(c11)).rgb, f.x);
    return mix(a, b, f.y);
}

// Clamped integer neighbour read of velocity.
static inline float2 fl_vel(texture2d<float, access::read> v, int x, int y, uint W, uint H) {
    int sx = clamp(x, 0, int(W) - 1);
    int sy = clamp(y, 0, int(H) - 1);
    return v.read(uint2(uint(sx), uint(sy))).rg;
}

// Clamped integer neighbour read of a scalar (r16Float) field. (Metal kernels avoid C++ lambdas.)
static inline float fl_r(texture2d<float, access::read> t, int x, int y, uint W, uint H) {
    int sx = clamp(x, 0, int(W) - 1);
    int sy = clamp(y, 0, int(H) - 1);
    return t.read(uint2(uint(sx), uint(sy))).r;
}

// MARK: - Clear a field to zero (init; makeTexture does not guarantee zeroed contents)

kernel void fluid_clear(
    texture2d<float, access::write> dst [[texture(0)]],
    constant FluidConfig&           cfg [[buffer(0)]],
    uint2                           gid [[thread_position_in_grid]]
) {
    if (gid.x >= cfg.width || gid.y >= cfg.height) { return; }
    dst.write(float4(0.0), gid);
}

// MARK: - Splats (inject velocity + dye from the sections). Up to 8 per frame.

// Packed as two float4 for a guaranteed Swift↔MSL layout match (no float3 16-byte-alignment trap):
//   posVel   = (pos.xy, vel.xy)      colorRad = (color.rgb, radius)
struct FluidSplat {
    float4 posVel;
    float4 colorRad;
};

// Additive gaussian splat of velocity (rg) into the velocity field.
kernel void fluid_splat_velocity(
    texture2d<float, access::read>  src   [[texture(0)]],
    texture2d<float, access::write> dst   [[texture(1)]],
    constant FluidConfig&           cfg   [[buffer(0)]],
    constant FluidSplat*            splats [[buffer(1)]],
    constant uint&                  count [[buffer(2)]],
    uint2                           gid   [[thread_position_in_grid]]
) {
    if (gid.x >= cfg.width || gid.y >= cfg.height) { return; }
    float2 uv = fl_uv(gid, cfg.width, cfg.height);
    float aspect = float(cfg.width) / float(cfg.height);
    float2 vel = src.read(gid).rg;
    for (uint i = 0; i < count; ++i) {
        float2 d = uv - splats[i].posVel.xy;
        d.x *= aspect;                                   // isotropic gaussian
        float radius = splats[i].colorRad.w;
        float g = exp(-dot(d, d) / max(radius * radius, 1e-6));
        vel += splats[i].posVel.zw * g;
    }
    dst.write(float4(vel, 0.0, 1.0), gid);
}

// Additive gaussian splat of dye colour into the dye field.
kernel void fluid_splat_dye(
    texture2d<float, access::read>  src   [[texture(0)]],
    texture2d<float, access::write> dst   [[texture(1)]],
    constant FluidConfig&           cfg   [[buffer(0)]],
    constant FluidSplat*            splats [[buffer(1)]],
    constant uint&                  count [[buffer(2)]],
    uint2                           gid   [[thread_position_in_grid]]
) {
    if (gid.x >= cfg.width || gid.y >= cfg.height) { return; }
    float2 uv = fl_uv(gid, cfg.width, cfg.height);
    float aspect = float(cfg.width) / float(cfg.height);
    float3 dye = src.read(gid).rgb;
    for (uint i = 0; i < count; ++i) {
        float2 d = uv - splats[i].posVel.xy;
        d.x *= aspect;
        float radius = splats[i].colorRad.w;
        float g = exp(-dot(d, d) / max(radius * radius, 1e-6));
        dye += splats[i].colorRad.rgb * g;
    }
    dst.write(float4(dye, 1.0), gid);
}

// MARK: - Curl (∂vy/∂x − ∂vx/∂y) → r16Float

kernel void fluid_curl(
    texture2d<float, access::read>  vel  [[texture(0)]],
    texture2d<float, access::write> curl [[texture(1)]],
    constant FluidConfig&           cfg  [[buffer(0)]],
    uint2                           gid  [[thread_position_in_grid]]
) {
    if (gid.x >= cfg.width || gid.y >= cfg.height) { return; }
    int x = int(gid.x), y = int(gid.y);
    float vr = fl_vel(vel, x + 1, y, cfg.width, cfg.height).y;
    float vl = fl_vel(vel, x - 1, y, cfg.width, cfg.height).y;
    float vt = fl_vel(vel, x, y + 1, cfg.width, cfg.height).x;
    float vb = fl_vel(vel, x, y - 1, cfg.width, cfg.height).x;
    float c = 0.5 * ((vr - vl) - (vt - vb));
    curl.write(float4(c, 0, 0, 1), gid);
}

// MARK: - Vorticity confinement: push velocity along ∇|curl| × curl (restores small-scale swirl → billowing)

kernel void fluid_vorticity(
    texture2d<float, access::read>  velIn  [[texture(0)]],
    texture2d<float, access::read>  curl   [[texture(1)]],
    texture2d<float, access::write> velOut [[texture(2)]],
    constant FluidConfig&           cfg    [[buffer(0)]],
    uint2                           gid    [[thread_position_in_grid]]
) {
    if (gid.x >= cfg.width || gid.y >= cfg.height) { return; }
    int x = int(gid.x), y = int(gid.y);
    float cR = fl_r(curl, x + 1, y, cfg.width, cfg.height), cL = fl_r(curl, x - 1, y, cfg.width, cfg.height);
    float cT = fl_r(curl, x, y + 1, cfg.width, cfg.height), cB = fl_r(curl, x, y - 1, cfg.width, cfg.height);
    float cC = fl_r(curl, x, y, cfg.width, cfg.height);
    // ∇|curl|
    float2 grad = 0.5 * float2(abs(cT) - abs(cB), abs(cR) - abs(cL));
    grad = grad / max(length(grad), 1e-5);
    // force ⟂ curl: (grad.y, -grad.x) * curl, standard confinement
    float2 force = cfg.vorticity * cC * float2(grad.y, -grad.x);
    float2 vel = velIn.read(gid).rg + force * cfg.dt;
    vel = clamp(vel, -1000.0, 1000.0);
    velOut.write(float4(vel, 0, 1), gid);
}

// MARK: - Divergence of velocity → r16Float (with free-slip velocity boundary)

kernel void fluid_divergence(
    texture2d<float, access::read>  vel [[texture(0)]],
    texture2d<float, access::write> div [[texture(1)]],
    constant FluidConfig&           cfg [[buffer(0)]],
    uint2                           gid [[thread_position_in_grid]]
) {
    if (gid.x >= cfg.width || gid.y >= cfg.height) { return; }
    int x = int(gid.x), y = int(gid.y);
    float l = fl_vel(vel, x - 1, y, cfg.width, cfg.height).x;
    float r = fl_vel(vel, x + 1, y, cfg.width, cfg.height).x;
    float b = fl_vel(vel, x, y - 1, cfg.width, cfg.height).y;
    float t = fl_vel(vel, x, y + 1, cfg.width, cfg.height).y;
    // Free-slip walls: reflect the normal component at the boundary.
    if (x == 0)                    { l = -fl_vel(vel, x, y, cfg.width, cfg.height).x; }
    if (x == int(cfg.width) - 1)   { r = -fl_vel(vel, x, y, cfg.width, cfg.height).x; }
    if (y == 0)                    { b = -fl_vel(vel, x, y, cfg.width, cfg.height).y; }
    if (y == int(cfg.height) - 1)  { t = -fl_vel(vel, x, y, cfg.width, cfg.height).y; }
    float d = 0.5 * ((r - l) + (t - b));
    div.write(float4(d, 0, 0, 1), gid);
}

// MARK: - Pressure: one Jacobi iteration  p = (pL+pR+pB+pT − divergence) * 0.25

kernel void fluid_pressure(
    texture2d<float, access::read>  pIn  [[texture(0)]],
    texture2d<float, access::read>  div  [[texture(1)]],
    texture2d<float, access::write> pOut [[texture(2)]],
    constant FluidConfig&           cfg  [[buffer(0)]],
    uint2                           gid  [[thread_position_in_grid]]
) {
    if (gid.x >= cfg.width || gid.y >= cfg.height) { return; }
    int x = int(gid.x), y = int(gid.y);
    float l = fl_r(pIn, x - 1, y, cfg.width, cfg.height), r = fl_r(pIn, x + 1, y, cfg.width, cfg.height);
    float b = fl_r(pIn, x, y - 1, cfg.width, cfg.height), t = fl_r(pIn, x, y + 1, cfg.width, cfg.height);
    float d = div.read(gid).r;
    float p = (l + r + b + t - d) * 0.25;
    pOut.write(float4(p, 0, 0, 1), gid);
}

// MARK: - Gradient subtract: make velocity divergence-free  v -= ∇p

kernel void fluid_gradient_subtract(
    texture2d<float, access::read>  pressure [[texture(0)]],
    texture2d<float, access::read>  velIn    [[texture(1)]],
    texture2d<float, access::write> velOut   [[texture(2)]],
    constant FluidConfig&           cfg      [[buffer(0)]],
    uint2                           gid      [[thread_position_in_grid]]
) {
    if (gid.x >= cfg.width || gid.y >= cfg.height) { return; }
    int x = int(gid.x), y = int(gid.y);
    float l = fl_r(pressure, x - 1, y, cfg.width, cfg.height), r = fl_r(pressure, x + 1, y, cfg.width, cfg.height);
    float b = fl_r(pressure, x, y - 1, cfg.width, cfg.height), t = fl_r(pressure, x, y + 1, cfg.width, cfg.height);
    float2 vel = velIn.read(gid).rg;
    vel -= 0.5 * float2(r - l, t - b);
    velOut.write(float4(vel, 0, 1), gid);
}

// MARK: - Advection (semi-Lagrangian): trace back along velocity, sample source, dissipate

kernel void fluid_advect_velocity(
    texture2d<float, access::read>  vel    [[texture(0)]],
    texture2d<float, access::write> velOut [[texture(1)]],
    constant FluidConfig&           cfg    [[buffer(0)]],
    uint2                           gid    [[thread_position_in_grid]]
) {
    if (gid.x >= cfg.width || gid.y >= cfg.height) { return; }
    float2 uv = fl_uv(gid, cfg.width, cfg.height);
    float2 v  = vel.read(gid).rg;
    // back-trace in uv space (velocity is in grid units/sec → convert by /resolution)
    float2 coord = uv - cfg.dt * v / float2(cfg.width, cfg.height);
    float2 result = fl_bilerp2(vel, coord, cfg.width, cfg.height);
    float decay = 1.0 / (1.0 + cfg.velocityDissipation * cfg.dt);
    velOut.write(float4(result * decay, 0, 1), gid);
}

kernel void fluid_advect_dye(
    texture2d<float, access::read>  vel    [[texture(0)]],
    texture2d<float, access::read>  dye    [[texture(1)]],
    texture2d<float, access::write> dyeOut [[texture(2)]],
    constant FluidConfig&           cfg    [[buffer(0)]],
    uint2                           gid    [[thread_position_in_grid]]
) {
    if (gid.x >= cfg.width || gid.y >= cfg.height) { return; }
    float2 uv = fl_uv(gid, cfg.width, cfg.height);
    float2 v  = vel.read(gid).rg;
    float2 coord = uv - cfg.dt * v / float2(cfg.width, cfg.height);
    float3 result = fl_bilerp3(dye, coord, cfg.width, cfg.height);
    float decay = 1.0 / (1.0 + cfg.dyeDissipation * cfg.dt);
    dyeOut.write(float4(result * decay, 1.0), gid);
}

// MARK: - Drawn voices (FL.9, option B): luminous lines DRAWN IN TIME, tracking the musical line
//
// docs/VISUAL_REFERENCES/ricercar/01 — glowing weaving light-lines. The FL.3 ribbons were fixed sine
// curves (always fully present, position not audio-driven → static, primitive, lagged — measured
// r=+0.25 / σ=0.028). Option B replaces them with the primary: each voice is a scrolling CONTOUR whose
// height at the right edge is set from THIS frame's audio (zero accumulation lag), scrolling left into
// history — the music drawing its own line. CPU maintains the per-voice (height, brightness) history
// and hands it to the fragment at buffer(1); x = position in that history, so the contour value at a
// pixel is a direct lookup (no fluid latency). Colour = instrument family; brightness = family activity
// (bright where the family sang, fading where it didn't). Counterpoint = the voices' contours crossing.
//   buffer(1) layout: kVoices runs of [ height[0..N-1], brightness[0..N-1] ], oldest→newest (newest = right).

constant int   kVoices  = 4;
constant int   kStrokeN = 96;
// strings violet, woodwinds russet, brass gold, percussion teal — luminous family palette.
constant float3 rc_voiceColor[4] = {
    float3(0.42, 0.28, 0.86), float3(0.90, 0.46, 0.22),
    float3(0.98, 0.72, 0.20), float3(0.16, 0.78, 0.82)
};

// Sample voice `v`'s history at fractional index `fx` → (height, brightness), linearly interpolated.
static inline float2 rc_voiceAt(constant float* strokes, int v, float fx) {
    int stride = kStrokeN * 2;
    int base = v * stride;
    float clamped = clamp(fx, 0.0, float(kStrokeN - 1));
    int i0 = int(floor(clamped));
    int i1 = min(i0 + 1, kStrokeN - 1);
    float f = clamped - float(i0);
    float y = mix(strokes[base + i0], strokes[base + i1], f);
    float b = mix(strokes[base + kStrokeN + i0], strokes[base + kStrokeN + i1], f);
    return float2(y, b);
}

// MARK: - Display: dye field → luminous flowing colour masses (ref 02)

struct FluidVSOut {
    float4 position [[position]];
    float2 uv;
};

vertex FluidVSOut ricercar_fluid_vertex(uint vid [[vertex_id]]) {
    float2 p = float2((vid == 2) ? 3.0 : -1.0, (vid == 1) ? 3.0 : -1.0);
    FluidVSOut o;
    o.position = float4(p, 0.0, 1.0);
    o.uv = p * 0.5 + 0.5;
    return o;
}

fragment float4 ricercar_fluid_fragment(
    FluidVSOut               in  [[stage_in]],
    texture2d<float, access::sample> dye [[texture(0)]],
    constant FluidConfig&    cfg [[buffer(0)]],
    constant float*          strokes [[buffer(1)]]
) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float2 duv = float2(in.uv.x, 1.0 - in.uv.y);
    float3 ground = float3(0.95, 0.94, 0.92);
    // FL.9 (option B): the fluid dye is demoted to a soft background WASH — dial its contribution down
    // (cfg.ribbonBrightness doubles as the wash gain, 1 in production) so the drawn voices read as the
    // subject over a gentle colour field, not a busy mass.
    float3 d = dye.sample(s, duv).rgb * cfg.exposure;
    float density = d.x + d.y + d.z;
    float3 hue = d / max(density, 1e-4);
    float cover = (1.0 - exp(-density)) * 0.45 * cfg.ribbonBrightness;   // soft wash
    float3 col = ground * (1.0 - cover) + hue * cover;

    // DRAWN VOICES (ref 01) — each voice's scrolling contour: look up its height at this pixel's x
    // (direct, zero-lag), glow by vertical distance, brighten by the stored per-column activity. The
    // line is LIGHT: saturated core + soft same-hue halo, composited over the wash.
    float fx = in.uv.x * float(kStrokeN - 1);
    for (int v = 0; v < kVoices; ++v) {
        float2 hb = rc_voiceAt(strokes, v, fx);           // (height in uv-y, brightness 0…1)
        float dist = fabs((1.0 - in.uv.y) - hb.x);        // uv.y is bottom-up; contour stored top-down
        float core = exp(-dist * dist / (0.006 * 0.006));
        float halo = exp(-dist * dist / (0.045 * 0.045));
        float lvl = hb.y;
        float glow = lvl * (3.2 * core + 0.5 * halo);
        float rCover = 1.0 - exp(-glow);
        col = mix(col, rc_voiceColor[v], rCover);
        col += rc_voiceColor[v] * (0.20 * lvl * core);    // keeps the core reading as light
    }
    return float4(col, 1.0);
}
