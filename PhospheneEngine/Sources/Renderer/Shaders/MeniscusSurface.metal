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

/// Mirror of Swift `MeniscusConfig` (48 B).
struct MeniscusConfig {
    uint  gridN;
    uint  pointCount;
    uint  spreadMode;      // 0 = screen-space X (source), 1 = segment normal
    float spread;
    float yaw;
    float pitch;
    float camDist;
    float camHeight;
    float focal;
    float heightScale;
    float aspect;
    float brightness;
    float lightDir;
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

    // Yaw about Y.
    float cy = cos(cfg.yaw), sy = sin(cfg.yaw);
    p = float3(p.x * cy + p.z * sy, p.y, -p.x * sy + p.z * cy);

    // Into camera-relative space: the camera is up and back.
    p.y -= cfg.camHeight;
    p.z += cfg.camDist;

    // Pitch about X, looking down.
    float cp = cos(cfg.pitch), sp = sin(cfg.pitch);
    float3 view = float3(p.x, p.y * cp + p.z * sp, -p.y * sp + p.z * cp);

    float depth = view.z;
    float safeDepth = max(depth, 0.05);
    float2 ndc = float2(view.x * cfg.focal / safeDepth / max(cfg.aspect, 0.01),
                        view.y * cfg.focal / safeDepth);
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
    float lit = saturate(0.5 + p.slope * 9.0);
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
