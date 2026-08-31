// MeniscusSurface.metal — the projected serpentine line surface for Meniscus (MEN.2a).
//
// Draws the path samples `MeniscusSurface.swift` serialized this frame. One draw,
// `segmentCount * 6` vertices: every consecutive pair of path samples becomes a quad
// extruded sideways, and the union of those quads under MAX blending IS the source's
// sideways glow spread (see the spread note below).
//
// Engine-library shader: `ShaderLibrary` concatenates `Renderer/Shaders/*.metal`
// alphabetically with NO utility preamble, so this file is self-contained — no
// `fbm8`, no `palette()`. The ground/sky fragment that DOES want those lives in
// `Presets/Shaders/Meniscus.metal`, which is compiled with the preset preamble.
//
// Reference traits this file is responsible for: T1 (serpentine polyline with
// turnaround caps), T2 (low-oblique perspective), T3 (slope-derived brightness).

#include <metal_stdlib>
using namespace metal;

// MARK: - Types

/// Mirror of Swift `MeniscusPoint` (8 B). One sample on the serpentine path.
struct MeniscusPoint {
    float height;
    float slope;
};

/// Mirror of Swift `MeniscusConfig` (60 B).
struct MeniscusConfig {
    uint  gridN;
    uint  pointCount;
    uint  spreadMode;      // 0 = screen-space X (source), 1 = segment normal
    float spread;
    float angleX;          // the three Euler angles the source integrates
    float angleY;
    float angleZ;
    float camDist;
    float camHeight;
    float focal;
    float heightScale;
    float slopeGain;
    float aspect;
    float brightness;
    float hue;             // sky/glare hue, derived from the Euler angles
};

struct MeniscusLineVertexOut {
    float4 position [[position]];
    float3 color;
    /// Signed position across the spread, -1..1. The fragment fades on |across|
    /// so the spread reads as a soft smear rather than a hard ribbon.
    float  across;
    /// 0 at the near margin, 1 at the far margin — used only to hold the far rows
    /// back so the compressed band does not read as a solid bar.
    float  depthFade;
};

// MARK: - Path → world → screen

/// Recover the grid cell a path index addresses. The CPU walks rows in serpentine
/// order (alternate rows reversed), so index `k` is row `k / N`, and within that row
/// the column runs backwards on odd rows. Keeping this here rather than storing (u,v)
/// per point holds the point buffer at 8 B/sample.
static float2 meniscus_path_uv(uint index, uint gridN) {
    uint n = max(gridN, 1u);
    uint row = index / n;
    uint step = index - row * n;
    uint col = ((row & 1u) != 0u) ? (n - 1u - step) : step;
    float denom = float(max(n - 1u, 1u));
    return float2(float(col) / denom, float(row) / denom);
}

/// Project one path sample to normalized device coordinates.
///
/// A hand-rolled yaw/pitch rotation plus a perspective divide, matching the source's
/// own 3×3-rotation-and-divide construction rather than a matrix upload — there is no
/// scene-uniform path on the particle route and this is a dozen instructions.
///
/// The camera sits `camHeight` ABOVE the plate and `camDist` back from it, pitched
/// DOWN. That sign is what delivers trait T2: far rows land higher up the frame and
/// compress toward a vanishing band while near rows spread. Pitching the other way
/// (the MEN.2a first render) looks up from beneath the plate and flattens the
/// recession to nothing.
///
/// Returns `.xy` = NDC, `.z` = view depth (for the far-row fade), `.w` = 1 when the
/// sample is in front of the camera.
static float4 meniscus_project(float2 uv, float height, constant MeniscusConfig& cfg) {
    // Grid → world. The plate spans [-1, 1] in x and z; y is the water height.
    float3 p = float3(uv.x * 2.0 - 1.0, height * cfg.heightScale, uv.y * 2.0 - 1.0);

    // THREE Euler angles, applied Z → Y → X, matching the source's hand-rolled 3x3.
    // MEN.2a used a single yaw plus a fixed pitch; the oracle shows the plate rotating
    // through most of a turn on all three axes within a few seconds, which is most of
    // what makes the source read as a floating object rather than a staged diagram.
    float cz = cos(cfg.angleZ), sz = sin(cfg.angleZ);
    p = float3(p.x * cz - p.y * sz, p.x * sz + p.y * cz, p.z);

    float cy = cos(cfg.angleY), sy = sin(cfg.angleY);
    p = float3(p.x * cy + p.z * sy, p.y, -p.x * sy + p.z * cy);

    float cx = cos(cfg.angleX), sx = sin(cfg.angleX);
    p = float3(p.x, p.y * cx - p.z * sx, p.y * sx + p.z * cx);

    // Into camera-relative space: the camera is up and back. `camDist` rides the slow
    // distance oscillation, which is what sweeps the plate between a small floating
    // rhombus and a frame-filling sheet.
    p.y -= cfg.camHeight;
    p.z += cfg.camDist;

    float depth = p.z;
    float safeDepth = max(depth, 0.05);
    float2 ndc = float2(p.x * cfg.focal / safeDepth / max(cfg.aspect, 0.01),
                        p.y * cfg.focal / safeDepth);
    return float4(ndc, depth, depth > 0.05 ? 1.0 : 0.0);
}

// MARK: - Vertex

/// One quad per path segment.
///
/// THE SPREAD (MEN.2a task 1b). The source spreads the drawn lines with a max-dilation
/// along screen-space X in its composite stage. Extruding each segment by ±`spread`
/// along that same axis and unioning the quads under MAX blending is the *same*
/// operation — the Minkowski sum of the polyline with a horizontal segment IS
/// morphological dilation along X — so the spread needs no extra pass, no new engine
/// surface, and no isotropic bloom (which would close the raster gaps in Y and destroy
/// trait T1; reference README anti-reference 5).
///
/// `spreadMode` selects the axis so MEN.2a task 1a can be answered from a render:
/// 0 = screen-space X (faithful), 1 = the segment's screen-space normal (a
/// uniform-thickness ribbon, which does not thin out as a row turns edge-on).
vertex MeniscusLineVertexOut meniscus_line_vertex(
    uint                     vid    [[vertex_id]],
    device const MeniscusPoint* pts  [[buffer(0)]],
    constant MeniscusConfig& cfg    [[buffer(1)]]
) {
    uint segment = vid / 6u;
    uint corner = vid - segment * 6u;

    uint ia = min(segment, cfg.pointCount - 1u);
    uint ib = min(segment + 1u, cfg.pointCount - 1u);

    MeniscusPoint pa = pts[ia];
    MeniscusPoint pb = pts[ib];

    float4 sa = meniscus_project(meniscus_path_uv(ia, cfg.gridN), pa.height, cfg);
    float4 sb = meniscus_project(meniscus_path_uv(ib, cfg.gridN), pb.height, cfg);

    // Which end of the segment this corner belongs to, and which side of the spread.
    // Triangles (0,1,2) and (2,1,3) over corners a-, a+, b-, b+.
    const uint endLUT[6]  = { 0u, 0u, 1u, 1u, 0u, 1u };
    const float sideLUT[6] = { -1.0, 1.0, -1.0, -1.0, 1.0, 1.0 };
    bool useB = endLUT[corner] != 0u;
    float side = sideLUT[corner];

    float4 s = useB ? sb : sa;
    MeniscusPoint p = useB ? pb : pa;

    float2 axis;
    if (cfg.spreadMode == 0u) {
        // Screen-space X, exactly as the source's comp stage does it. Aspect-corrected
        // so the spread is the same number of PIXELS regardless of window shape.
        axis = float2(1.0 / max(cfg.aspect, 0.01), 0.0);
    } else {
        // The segment's screen-space normal — a constant-thickness ribbon.
        float2 tangent = sb.xy - sa.xy;
        float len = max(length(tangent), 1e-5);
        tangent /= len;
        axis = float2(-tangent.y, tangent.x);
    }

    MeniscusLineVertexOut o;
    o.position = float4(s.xy + axis * side * cfg.spread, 0.0, 1.0);
    // Cull behind-camera samples by collapsing them off-screen; there is no depth
    // buffer on this path and a wrapped sample would otherwise smear across the frame.
    if (s.w < 0.5 || sa.w < 0.5 || sb.w < 0.5) { o.position = float4(0.0, 0.0, 0.0, 0.0); }

    // T3 — brightness from local SLOPE, not from height. A crest goes to blown white
    // while the trough a sample away goes to black; that hard contrast is what makes a
    // field of lines read as a liquid surface (reference `07`). The transition is
    // deliberately sharp: a soft, evenly-lit version looks like fabric, not water.
    float lit = saturate(0.5 + p.slope * cfg.slopeGain);
    float spec = smoothstep(0.55, 0.95, lit);
    float shade = mix(0.06, 0.72, lit) + spec * 0.85;

    // Height → hue as a CONCEPT only (deep = warm, crest = cool). The specific
    // colours are an MEN.3 decision; this is the neutral placeholder so the surface
    // is not a flat grey and the height signal is legible in the contact sheet.
    float warmth = saturate(0.5 - p.height * 1.4);
    float3 cool = float3(0.72, 0.92, 1.00);
    float3 warm = float3(1.00, 0.86, 0.66);
    o.color = mix(cool, warm, warmth) * shade * cfg.brightness;

    o.across = side;
    o.depthFade = saturate((s.z - cfg.camDist + 1.2) / 2.4);
    return o;
}

// MARK: - Fragment

fragment float4 meniscus_line_fragment(MeniscusLineVertexOut in [[stage_in]]) {
    // Soft falloff across the spread. A hard-edged quad would read as a thick ribbon;
    // the falloff is what turns the dilation into a smear that keeps a bright core.
    float across = saturate(1.0 - abs(in.across));
    float profile = across * across * (3.0 - 2.0 * across);
    // Hold the far rows back so the compressed band at the horizon does not fill in
    // as a solid bar — the raster must stay open all the way to the vanishing band.
    float depth = mix(1.0, 0.45, in.depthFade);
    float3 rgb = in.color * profile * depth;
    return float4(rgb, 1.0);
}

// MARK: - Backdrop (MEN.2b)
//
// The ground plane and sky wash moved HERE from `Presets/Shaders/Meniscus.metal` at
// MEN.2b. They have to see the live camera, and the preset fragment cannot: the
// particle path binds FeatureVector but no per-preset buffer, so the MEN.2a version
// mirrored the camera constants by hand and could only work with a fixed camera. Now
// that the camera tumbles and dollies, a mirrored copy would desynchronise within a
// frame. Drawing the backdrop from the geometry — which owns the camera — closes that
// seam with no engine change and no new GPU-contract surface.
//
// Self-contained noise: the engine library gets no utility preamble, so no `fbm8` here.

static float meniscus_hash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453123);
}

/// Value noise with a smooth interpolant — cheap, and the source's ground is a noise
/// texture lookup rather than anything more elaborate.
static float meniscus_vnoise(float2 p) {
    float2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = meniscus_hash(i);
    float b = meniscus_hash(i + float2(1.0, 0.0));
    float c = meniscus_hash(i + float2(0.0, 1.0));
    float d = meniscus_hash(i + float2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

/// Four octaves, output centred on ~0.5 (NOT [-1,1] — the MEN.2a ground was broken by
/// exactly that confusion against the utility `fbm*`, which IS zero-centred).
static float meniscus_fbm(float2 p) {
    float sum = 0.0, amp = 0.5, norm = 0.0;
    for (int i = 0; i < 4; ++i) {
        sum += amp * meniscus_vnoise(p);
        norm += amp;
        amp *= 0.5;
        p *= 2.03;
    }
    return sum / norm;
}

/// Hue → RGB for a fully-saturated cool wash. The source carries its sky colour as
/// pre-computed channel values out of the frame equations; reproducing the BEHAVIOUR
/// (a continuously rotating tint) matters, not the arithmetic that got it there.
static float3 meniscus_hue_rgb(float hue) {
    float3 k = fract(float3(hue) + float3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0;
    return clamp(abs(k) - 1.0, 0.0, 1.0);
}

struct MeniscusBackdropOut {
    float4 position [[position]];
    float2 ndc;
};

vertex MeniscusBackdropOut meniscus_backdrop_vertex(uint vid [[vertex_id]]) {
    float2 uv = float2((vid << 1) & 2, vid & 2);
    MeniscusBackdropOut o;
    o.position = float4(uv * 2.0 - 1.0, 0.0, 1.0);
    o.ndc = uv * 2.0 - 1.0;
    return o;
}

fragment float4 meniscus_backdrop_fragment(
    MeniscusBackdropOut in [[stage_in]],
    constant MeniscusConfig& cfg [[buffer(0)]]
) {
    float aspect = max(cfg.aspect, 0.01);
    float2 ndc = in.ndc;

    // The horizon tilts with the camera's roll, which is what keeps the backdrop
    // welded to the plate as it tumbles (the source ties its horizon to the same
    // angles). MEN.2a had a fixed horizontal horizon because it had a fixed camera.
    float cr = cos(cfg.angleZ), sr = sin(cfg.angleZ);
    float2 rotated = float2(ndc.x * aspect * cr - ndc.y * sr, ndc.x * aspect * sr + ndc.y * cr);

    // Height above the horizon line, in screen units. `angleX` (pitch) slides the
    // horizon up and down the frame exactly as it does for the projected plate.
    float horizon = rotated.y + cfg.angleX * 0.85;

    // ONE cool key light, as a smooth radial falloff from a position that travels with
    // the camera's heading. Radial, never an angular dot product — that produced a
    // hard-edged wedge at MEN.2a.
    float2 lightPos = float2(0.55 * cos(cfg.angleY * 0.5), 0.42);
    float key = exp(-length(rotated - lightPos) * 1.9);

    // The rotating tint (§9 correction 1).
    float3 tint = meniscus_hue_rgb(fract(cfg.hue));
    float3 keyColour = mix(float3(0.18, 0.42, 0.48), tint, 0.72);

    float3 rgb;
    if (horizon < 0.0) {
        // Ground: a grainy dark plane far below, projected so the grain compresses
        // toward the horizon. Scales set from the projected geometry — MEN.2a aliased
        // by sampling world-unit coordinates that diverge at the horizon.
        float dist = min(0.55 / max(-horizon, 0.004), 90.0);
        float2 plane = float2(rotated.x * dist, dist) * 0.55;
        float detail = saturate(1.0 - dist / 26.0);
        float tone = 0.55 * meniscus_fbm(plane * 0.30)
                   + 0.30 * meniscus_fbm(plane * 1.10) * detail
                   + 0.15 * meniscus_fbm(plane * 3.40) * detail * detail;
        tone = saturate((tone - 0.5) * 2.6 + 0.5);
        float level = mix(0.006, 0.032, tone) * (0.55 + 1.9 * key);
        rgb = float3(level * 0.86, level * 0.95, level);
    } else {
        float up = saturate(horizon * 2.2);
        // Measured off the oracle: the sky peaks around value 0.5 at its brightest
        // and spends most of its time at 0.08-0.16. The first port ran ~3x hot and
        // washed the whole frame, which buried the raster it is meant to sit behind.
        rgb = keyColour * key * (1.0 - up * 0.55) * 0.46;
        rgb += keyColour * pow(key, 3.4) * 0.22;      // the lateral glare term
    }

    // Global brightness gate driven by volume, as the source does.
    rgb *= cfg.brightness;
    // Never fully black (D-037) — the source renders black at silence
    // (anti-reference `06`); this floor is the minimum that rule requires.
    rgb = max(rgb, float3(0.004, 0.005, 0.007));
    return float4(rgb, 1.0);
}
