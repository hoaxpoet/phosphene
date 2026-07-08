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

// MARK: - Splats (inject velocity + dye from the sections). Up to 8 per frame.

struct FluidSplat {
    float2 pos;      // uv [0,1]
    float2 vel;      // velocity impulse
    float3 color;    // dye colour
    float  radius;   // gaussian radius (uv units)
    float  _pad;
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
        float2 d = uv - splats[i].pos;
        d.x *= aspect;                                   // isotropic gaussian
        float g = exp(-dot(d, d) / max(splats[i].radius * splats[i].radius, 1e-6));
        vel += splats[i].vel * g;
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
        float2 d = uv - splats[i].pos;
        d.x *= aspect;
        float g = exp(-dot(d, d) / max(splats[i].radius * splats[i].radius, 1e-6));
        dye += splats[i].color * g;
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
    constant FluidConfig&    cfg [[buffer(0)]]
) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    // The stored dye is HDR density; tonemap softly so masses read luminous, not clipped, and let the
    // warm light ground show through where dye is thin (ref 02 = colour on a clean light ground).
    float3 d = dye.sample(s, float2(in.uv.x, 1.0 - in.uv.y)).rgb * cfg.exposure;
    float3 ground = float3(0.95, 0.94, 0.92);
    // soft "over" of luminous dye onto the light ground: 1 - exp keeps highlights from clipping.
    float3 col = ground * exp(-d) + (1.0 - exp(-d)) * (d / max(max(d.x, max(d.y, d.z)), 1e-4));
    return float4(col, 1.0);
}
