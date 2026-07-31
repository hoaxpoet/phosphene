// Witchlight.metal (engine library) — the beaded luminous stroke.
//
// Witchlight's ribbon is CPU-simulated in `WitchlightStroke` (Renderer/Geometry) and
// drawn here from the shared bead ring buffer. Four draws, in order, all off the SAME
// buffer — this is the whole ribbon; the preset-side `witchlight_sky_fragment` supplies
// only the procedural backdrop.
//
//   1. `witchlight_suppress_*` — a wide soft dark disc per bead, blended dst *= (1-a).
//      The depth cue from reference trait #6: stars visibly dim behind the ribbon so the
//      stroke reads as occluding the field rather than being pasted onto it.
//   2. `witchlight_line_*`     — a thin additive line strip through the bead centres
//      (`01`: the trail is a *line* with sparks on it, not a row of dots).
//   3. `witchlight_bead_*`     — the alpha-graded round sprites. Two-part radial profile,
//      hot near-white core inside a wider, cooler, hue-carrying halo — mandatory trait #3,
//      read off `08` (lightning: white core, distinctly cooler and wider violet halo) and
//      `09` (a bright core that does NOT bleach the thin filaments beside it).
//   4. `witchlight_flare_*`    — the bounded head burst. A small radiating spark burst at
//      the pen head (`03` — a real burning head is roughly the diameter of the trail),
//      explicitly NOT the six-spoke frame-filling star of anti-reference `12`. The
//      luminance ceiling, the extent cap and the refractory interval are enforced
//      CPU-side in `WitchlightStroke` (WITCHLIGHT_DESIGN §5) and arrive here already
//      bounded in `WLConfig.flareIntensity`.
//
// Beads are drawn as INSTANCED QUADS, not `[[point_size]]` sprites: point size is in
// pixels, so a pixel-sized bead would occupy a different fraction of the frame at every
// drawable size. A quad sized in world units is resolution-independent, which the flash
// budget (a frame-AREA rule) depends on.
//
// Layout note: `WLBead` / `WLConfig` mirror the Swift structs in `WitchlightStroke.swift`
// field-for-field, scalar floats only (no packed vectors) so the byte layout matches
// without alignment surprises — the `PhysAgent` precedent.

#include <metal_stdlib>
using namespace metal;

// MARK: - Shared layout (mirrors WitchlightStroke.swift)

struct WLBead {
    float px, py, pz;     // stroke-plane position, world units (frame height = 2.0)
    float age;            // seconds since emission
    float cr, cg, cb;     // frozen hue at emission (WITCHLIGHT_DESIGN §3.4)
    float promoted;       // 1 = downbeat bead (bigger, brighter, permanent)
};

struct WLConfig {
    uint  beadCount;
    uint  frame;
    float trailSeconds;     // T — the visible age window (contracts on a section boundary)
    float baseRadius;       // r0, world units
    float aspect;           // drawable w/h
    float tumbleYaw;        // slow 3-D drift of the stroke plane
    float tumblePitch;
    float tumbleRoll;
    float centroidX;        // smoothed trail centroid — the figure stays framed
    float centroidY;
    float viewScale;        // slow auto-fit so the figure keeps a legible frame share
    float headX, headY, headZ;
    float headR, headG, headB;
    float flareIntensity;   // 0…1, already bounded by the §5 budget
    float lineAlpha;
};

// MARK: - Shared projection

/// Rotate a centroid-relative point by the drifting plane orientation.
static inline float3 wl_tumble(float3 p, constant WLConfig& cfg) {
    float cy = cos(cfg.tumbleYaw),   sy = sin(cfg.tumbleYaw);
    float cp = cos(cfg.tumblePitch), sp = sin(cfg.tumblePitch);
    float cr = cos(cfg.tumbleRoll),  sr = sin(cfg.tumbleRoll);
    float3 a = float3(p.x * cr - p.y * sr, p.x * sr + p.y * cr, p.z);          // roll (in-plane)
    float3 b = float3(a.x, a.y * cp - a.z * sp, a.y * sp + a.z * cp);          // pitch
    return float3(b.x * cy + b.z * sy, b.y, -b.x * sy + b.z * cy);             // yaw
}

/// Project a stroke-space position to NDC. Returns `.xy` = NDC, `.z` = the perspective
/// factor (near beads slightly larger — the foreshortening cue that makes the tumble read
/// as depth rather than as a 2-D squash).
static inline float3 wl_project(float3 world, constant WLConfig& cfg) {
    float3 rel = wl_tumble(world - float3(cfg.centroidX, cfg.centroidY, 0.0), cfg);
    const float camDist = 3.0;
    float persp = camDist / max(camDist - rel.z * cfg.viewScale, 0.35);
    float2 ndc = rel.xy * cfg.viewScale * persp;
    ndc.x /= max(cfg.aspect, 0.05);
    return float3(ndc, persp);
}

/// Half-extent of a sprite of screen radius `r`, aspect-corrected.
///
/// Sprite sizes are SCREEN-space (NDC), deliberately NOT scaled by `viewScale`. A real
/// burning trail has a thickness set by the burning head, not by how large the figure
/// happens to be: scaling the beads with the auto-fit made them go sub-pixel exactly as
/// the trail filled out — the ribbon vanished as the drawing got good. `WitchlightStroke`'s
/// `baseRadius` is therefore a fraction of half the frame height, and the flash budget's
/// frame-AREA rules read directly off these numbers.
static inline float2 wl_screen_extent(float r, constant WLConfig& cfg) {
    return float2(r / max(cfg.aspect, 0.05), r);
}

/// Corner offset for instanced-quad expansion. `vid` 0…3 → a triangle-strip unit quad.
static inline float2 wl_corner(uint vid) {
    return float2((vid & 1) ? 1.0 : -1.0, (vid & 2) ? 1.0 : -1.0);
}

/// Age → brightness. `(1 - a/T)^1.6`: superlinear, so the newest third of the stroke
/// carries most of the light (`02` — the decay is visibly not linear) and it reaches
/// exactly 0 at T so the tail never pops out of existence. Monotonic by construction,
/// which is mandatory trait #2.
static inline float wl_age_alpha(float age, float trailSeconds) {
    float t = clamp(age / max(trailSeconds, 0.001), 0.0, 1.0);
    float f = 1.0 - t;
    return f * f * pow(f, 0.6);
}

/// Age → radius. Beads taper but do not vanish before they fade, so the ribbon narrows
/// toward its tail instead of dotting out (`05`: stroke width modulates along a stroke).
static inline float wl_age_radius(float age, float trailSeconds) {
    float t = clamp(age / max(trailSeconds, 0.001), 0.0, 1.0);
    return 1.0 - 0.65 * t;
}

// MARK: - Bead sprites (pass 3)

struct WLBeadOut {
    float4 position [[position]];
    float2 quad;
    float3 color;
    float  alpha;
};

vertex WLBeadOut witchlight_bead_vertex(
    uint                vid      [[vertex_id]],
    uint                iid      [[instance_id]],
    constant WLBead*    beads    [[buffer(0)]],
    constant WLConfig&  cfg      [[buffer(1)]])
{
    WLBead b = beads[iid];
    float3 proj = wl_project(float3(b.px, b.py, b.pz), cfg);

    float alpha  = wl_age_alpha(b.age, cfg.trailSeconds);
    float radius = cfg.baseRadius * wl_age_radius(b.age, cfg.trailSeconds);
    // A downbeat bead is SET: bigger and brighter, and it never decays back to an
    // ordinary bead — the ribbon carries a visible chain of bar markers (§3.2).
    radius *= mix(1.0, 2.2, b.promoted);
    alpha  *= mix(1.0, 1.6, b.promoted);

    float2 corner = wl_corner(vid);
    float2 halfExtent = wl_screen_extent(radius * proj.z, cfg);

    WLBeadOut out;
    out.position = float4(proj.xy + corner * halfExtent, 0.0, 1.0);
    out.quad  = corner;
    out.color = float3(b.cr, b.cg, b.cb);
    out.alpha = clamp(alpha, 0.0, 1.0);
    return out;
}

fragment float4 witchlight_bead_fragment(WLBeadOut in [[stage_in]]) {
    float r2 = dot(in.quad, in.quad);
    if (r2 > 1.0) { discard_fragment(); }
    // Two-part profile (`08`, `09`): a tight near-white core sitting inside a wider,
    // cooler, hue-carrying halo. A single colour at two intensities fails trait #3, so
    // the core is deliberately desaturated toward white while the halo keeps the hue.
    float core = exp(-r2 * 15.0);
    float halo = exp(-r2 * 2.7);
    // The core lifts toward white but does NOT reach it: a fully white core erases the
    // frozen hue, and the hue IS the information (mandatory trait #7).
    float3 hot = mix(in.color, float3(1.0), 0.58);
    float3 rgb = in.color * halo * 1.05 + hot * core * 0.75;
    return float4(rgb * in.alpha, 1.0);
}

// MARK: - Connecting line (pass 2)

struct WLLineOut {
    float4 position [[position]];
    float3 color;
    float  alpha;
};

vertex WLLineOut witchlight_line_vertex(
    uint                vid    [[vertex_id]],
    constant WLBead*    beads  [[buffer(0)]],
    constant WLConfig&  cfg    [[buffer(1)]])
{
    WLBead b = beads[vid];
    float3 proj = wl_project(float3(b.px, b.py, b.pz), cfg);
    WLLineOut out;
    out.position = float4(proj.xy, 0.0, 1.0);
    out.color = float3(b.cr, b.cg, b.cb);
    out.alpha = wl_age_alpha(b.age, cfg.trailSeconds) * cfg.lineAlpha;
    return out;
}

fragment float4 witchlight_line_fragment(WLLineOut in [[stage_in]]) {
    // The thread the beads sit on: hue-carrying but dimmer than the beads, so the
    // stroke reads as beads-on-a-thread rather than as a uniform glow tube (anti-`11`).
    return float4(mix(in.color, float3(1.0), 0.25) * in.alpha, 1.0);
}

// MARK: - Star suppression (pass 1)

vertex WLBeadOut witchlight_suppress_vertex(
    uint                vid      [[vertex_id]],
    uint                iid      [[instance_id]],
    constant WLBead*    beads    [[buffer(0)]],
    constant WLConfig&  cfg      [[buffer(1)]])
{
    WLBead b = beads[iid];
    float3 proj = wl_project(float3(b.px, b.py, b.pz), cfg);
    float radius = cfg.baseRadius * wl_age_radius(b.age, cfg.trailSeconds) * 4.5;
    float2 corner = wl_corner(vid);
    float2 halfExtent = wl_screen_extent(radius * proj.z, cfg);
    WLBeadOut out;
    out.position = float4(proj.xy + corner * halfExtent, 0.0, 1.0);
    out.quad  = corner;
    out.color = float3(0.0);
    // Follows the trail's own falloff so the tail stops occluding as it fades out.
    out.alpha = wl_age_alpha(b.age, cfg.trailSeconds);
    return out;
}

fragment float4 witchlight_suppress_fragment(WLBeadOut in [[stage_in]]) {
    float r2 = dot(in.quad, in.quad);
    if (r2 > 1.0) { discard_fragment(); }
    // Alpha-only output; the pipeline blends dst *= (1 - src.a), so this darkens the
    // backdrop without adding any light of its own.
    return float4(0.0, 0.0, 0.0, exp(-r2 * 2.2) * in.alpha * 0.80);
}

// MARK: - Head flare (pass 4)

struct WLFlareOut {
    float4 position [[position]];
    float2 quad;
    float3 color;
    float  intensity;
};

vertex WLFlareOut witchlight_flare_vertex(
    uint                vid   [[vertex_id]],
    constant WLConfig&  cfg   [[buffer(1)]])
{
    float3 proj = wl_project(float3(cfg.headX, cfg.headY, cfg.headZ), cfg);
    // Extent cap (§5): the burst spans a fixed small world radius regardless of how hard
    // it fires — intensity varies, area does not. This is the structural difference from
    // anti-reference `12`, whose flare grows until it covers the frame.
    const float flareRadius = 0.24;
    float2 corner = wl_corner(vid);
    float2 halfExtent = wl_screen_extent(flareRadius * proj.z, cfg);
    WLFlareOut out;
    out.position  = float4(proj.xy + corner * halfExtent, 0.0, 1.0);
    out.quad      = corner;
    out.color     = float3(cfg.headR, cfg.headG, cfg.headB);
    out.intensity = cfg.flareIntensity;
    return out;
}

fragment float4 witchlight_flare_fragment(WLFlareOut in [[stage_in]]) {
    float r2 = dot(in.quad, in.quad);
    if (r2 > 1.0) { discard_fragment(); }
    float r = sqrt(r2);
    // `03`: a hot core roughly the diameter of the trail, surrounded by fine radiating
    // spark lines that fall off fast. Many thin needles, NOT six fat spokes — the spokes
    // are what let the source's flare cover the frame (`12`).
    float ang = atan2(in.quad.y, in.quad.x);
    float needles = pow(max(0.0, 0.5 + 0.5 * cos(ang * 17.0)), 6.0)
                  + pow(max(0.0, 0.5 + 0.5 * cos(ang * 11.0 + 1.7)), 8.0);
    float core  = exp(-r2 * 60.0);
    float glow  = exp(-r2 * 7.0) * 0.45;
    float spark = needles * exp(-r * 5.0) * 0.30;
    float3 hot  = mix(in.color, float3(1.0), 0.70);
    float3 rgb  = hot * core + in.color * (glow + spark);
    return float4(rgb * in.intensity, 1.0);
}
