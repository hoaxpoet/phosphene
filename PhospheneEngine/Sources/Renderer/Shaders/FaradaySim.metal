// FaradaySim.metal — Swift–Hohenberg simulation for the Faraday preset.
//
// The music drives a real pattern-forming PDE; the preset's `sceneSDF` then reads
// the resulting field as a liquid heightfield (bound at fragment texture(10) via
// `RenderPipeline.setRayMarchPresetHeightTexture`).
//
// PHYSICS (ported, FA #73 — not derived). Parametrically-driven surface waves
// (Faraday waves) are canonically described by the Swift–Hohenberg amplitude
// equation — Swift & Hohenberg 1977; Chen & Viñals 1997 for Faraday specifically:
//
//     du/dt = r*u - (lap + k0^2)^2 u + g*u^2 - u^3
//
//   r  — drive above threshold. r < 0 decays to a flat mirror; r > 0 grows pattern.
//        This IS the Faraday threshold: loudness crossing zero is a real
//        supercritical bifurcation, not an animated fade-in.
//   k0 — selected wavenumber, so pattern wavelength = 2*pi/k0. Timbre sets it:
//        bass gives big slow cells, treble a fine lattice.
//   g  — quadratic term; selects hexagonal/square cells rather than stripes.
//
// Biharmonic expanded: (lap+k0^2)^2 u = lap2(u) + 2*k0^2*lap(u) + k0^4*u, so a step
// is two dispatches — pass 1 writes lap(u) into .g, pass 2 consumes it.
//
// Numerics learned the hard way in the concept spike:
//   * The 3x3 Laplacian eigenvalue SATURATES at -1.6 (it is only ~-0.3k^2 for small
//     k), so growth is far slower than a naive -k^2 reading suggests.
//   * dt is bounded by the STIFFEST term, the cubic (d/du of u^3 = 3u^2): dt*3u^2 < 2.
//     Too large and the grid-scale checkerboard mode wins — a diagonal weave that is
//     numerical instability, not physics.
//   * VOLUME CONSERVATION is required. The quadratic term pumps the spatially
//     uniform k=0 mode, which is essentially undamped at small k0; left alone it
//     wins and the field collapses to a flat elevated state (measured: amplitude
//     0.32 -> 0.004). A real dish of liquid cannot change its mean level, so the
//     mean is restored toward zero. `meanDamp` is applied per substep against a
//     mean measured last frame — keep the per-frame product near 1.0, because a
//     delayed feedback with gain >> 1 oscillates and drives the field to its clamp.

#include <metal_stdlib>
using namespace metal;

// MARK: - FaradayConfig (mirror of Swift FaradayConfig — keep in lockstep)

struct FaradayConfig {
    uint  width;
    uint  height;
    uint  frame;        // per-frame RNG salt
    float dt;           // integration step
    float k0;           // selected wavenumber (timbre)
    float drive;        // r — drive above threshold (loudness)
    float quad;         // g — quadratic term (cell selection)
    float noise;        // thermal noise (lets pattern nucleate)
    float uMean;        // measured mean from last frame
    float meanDamp;     // volume-conservation gain
    float modeDepth;    // how strongly the plate mode gates the drive
    float modeA;        // plate mode index X
    float modeB;        // plate mode index Y
};

// MARK: - Helpers

static inline float2 fdy_read(texture2d<float, access::read> t, int x, int y, int W, int H) {
    int sx = (x % W + W) % W;
    int sy = (y % H + H) % H;
    return t.read(uint2(uint(sx), uint(sy))).rg;
}

static inline float fdy_hash(uint x) {
    x ^= x >> 16; x *= 0x7feb352du;
    x ^= x >> 15; x *= 0x846ca68bu;
    x ^= x >> 16;
    return float(x) * (1.0 / 4294967296.0);
}

/// Canonical weighted 3x3 Laplacian (corners .05, edges .2, centre -1); toroidal.
static inline float fdy_lap(texture2d<float, access::read> t,
                            int x, int y, int W, int H, int channel) {
    float2 c = fdy_read(t, x, y, W, H);
    float2 e = fdy_read(t, x-1, y,   W, H) + fdy_read(t, x+1, y,   W, H)
             + fdy_read(t, x,   y-1, W, H) + fdy_read(t, x,   y+1, W, H);
    float2 d = fdy_read(t, x-1, y-1, W, H) + fdy_read(t, x+1, y-1, W, H)
             + fdy_read(t, x-1, y+1, W, H) + fdy_read(t, x+1, y+1, W, H);
    float centre = channel == 0 ? c.r : c.g;
    float edge   = channel == 0 ? e.r : e.g;
    float diag   = channel == 0 ? d.r : d.g;
    return edge * 0.2 + diag * 0.05 - centre;
}

// MARK: - Pass 1: carry u, write lap(u) into .g

kernel void faraday_lap_pass(constant FaradayConfig& cfg [[buffer(0)]],
                             texture2d<float, access::read>  src [[texture(0)]],
                             texture2d<float, access::write> dst [[texture(1)]],
                             uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= cfg.width || gid.y >= cfg.height) { return; }
    int W = int(cfg.width), H = int(cfg.height);
    int x = int(gid.x), y = int(gid.y);
    float u = fdy_read(src, x, y, W, H).r;
    dst.write(float4(u, fdy_lap(src, x, y, W, H, 0), 0.0, 1.0), gid);
}

// MARK: - Pass 2: Swift–Hohenberg update

kernel void faraday_step_pass(constant FaradayConfig& cfg [[buffer(0)]],
                              texture2d<float, access::read>  src [[texture(0)]],
                              texture2d<float, access::write> dst [[texture(1)]],
                              uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= cfg.width || gid.y >= cfg.height) { return; }
    int W = int(cfg.width), H = int(cfg.height);
    int x = int(gid.x), y = int(gid.y);

    float2 cc = fdy_read(src, x, y, W, H);
    float u = cc.r;
    float lap = cc.g;
    float lap2 = fdy_lap(src, x, y, W, H, 1);          // lap(lap(u))

    float k2 = cfg.k0 * cfg.k0;
    float biharmonic = lap2 + 2.0 * k2 * lap + k2 * k2 * u;

    // PLATE MODE. A driven dish is not uniformly excited — it has its own standing
    // modes, and Faraday cells only grow where the plate actually moves, vanishing
    // along the nodal lines. That is what turns a uniform field of cells into a
    // large-scale FIGURE (the same reason Chladni reads as an image, not a texture).
    // cos(2*pi*m*x) is genuinely periodic over the toroidal field; sin(pi*m*x) would
    // force a dead nodal line onto the wrap and tile a grid of seams into the world.
    float2 nn = (float2(gid) + 0.5) / float2(float(cfg.width), float(cfg.height));
    float plate = cos(nn.x * 6.28318530718 * cfg.modeA)
                * cos(nn.y * 6.28318530718 * cfg.modeB);
    float envelope = mix(1.0, plate * plate, cfg.modeDepth);
    float driveLocal = cfg.drive * envelope - 0.05 * (1.0 - envelope);

    float du = driveLocal * u
             - biharmonic
             + cfg.quad * u * u
             - u * u * u
             - cfg.meanDamp * cfg.uMean;               // volume conservation

    u += cfg.dt * du;
    // Thermal noise — a real fluid always has it; it lets pattern nucleate the
    // instant the drive crosses threshold instead of sitting at exactly zero.
    u += (fdy_hash(gid.x * 1973u + gid.y * 9277u + cfg.frame * 26699u) - 0.5) * cfg.noise;
    u = clamp(u, -2.5, 2.5);                           // keeps the cubic term stable

    dst.write(float4(u, lap, 0.0, 1.0), gid);
}
