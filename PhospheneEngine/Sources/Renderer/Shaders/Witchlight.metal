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
    float energyBreath;    // WL.4 — per-frame energy, 0…1 centred 0.5 (WitchlightStroke)
    float barPulse;        // WL.8 — the head-flare envelope, 0…1; the bar-line beads blink with it
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

/// How far past the bead the halo reaches, in bead radii (bead sprites only).
///
/// `08` is explicit that the halo is *wider* than the core, not just dimmer than it — and
/// while core and halo shared one quad the halo could not be wider than the bead by
/// construction, so every bead rendered as a hard-edged dot. Expanding the QUAD and
/// rescaling the core's radial term by the same factor keeps the core pinned to exactly the
/// bead size WL.2-f settled: the bead does not get bigger, its glow gets reach.
///
/// **WL.2-j — 3.2 → 1.6, because the reach had eaten the beads.** Bead centres sit
/// `1.2 × 2 × baseRadius` apart (WL.2-f, calibrated against the BARE bead), and WL.2-g/-h
/// widened the drawn sprite to 2.6× then 3.2× that radius without revisiting the spacing.
/// At the measured `viewScale` of 1.38–1.88 consecutive sprites overlapped **30–48 %** and
/// fused into the uniform glow tube of anti-reference `11`; they would only have read as
/// distinct above `viewScale` 2.67, which never occurs. Matt's M7 saw it as a lumpy
/// caterpillar.
///
/// Beads separate when `WL_HALO_EXTENT < 1.2 × viewScale`, so 1.6 clears the whole measured
/// range (−3 % overlap at the tight end, −41 % at the loose one). The luminance this gives
/// up is bought back in the CORE and the connecting thread, which is the honest trade: light
/// per bead rather than light from beads merging into each other.
constant float WL_HALO_EXTENT = 1.6;

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
    // WL.8 — and on the downbeat they BLINK, in unison with the head.
    //
    // Matt asked for the head plus "any other nodules desired". The bar-line beads are
    // already the right nodules — they mark exactly the event being pulsed — so this reuses
    // the head-flare envelope rather than inventing a second one: the head and every bar
    // marker in the trail brighten on the same frames, which is what makes it read as one
    // rhythmic gesture instead of two things happening near each other.
    //
    // Restricted to promoted beads BY DESIGN (D-157: bounded spatial footprint per beat,
    // steady global luminance). They are ~1 bead in 7, so the lit-pixel share moves a few
    // percent on the downbeat while the ribbon's overall level holds — a whole-trail flash
    // at 0.71/s would be a different, and much less safe, object.
    // WL.9 — raised from +35 % / +80 % after Matt read the WL.8 pulse as "too polite".
    // The §5 headroom is enormous (measured 0.0081 mean luminance against a 0.35 ceiling at
    // the worst-case pulse rate), and the head flare itself covers 0.006 % of the frame, so
    // the BEAD blink is the channel that actually carries this to the viewer — the flare is
    // a highlight, the bar-line chain lighting up is the gesture.
    float pulse = cfg.barPulse * b.promoted;
    radius *= 1.0 + 0.55 * pulse;
    alpha  *= 1.0 + 1.40 * pulse;
    // WL.4 — the ribbon BREATHES with the music, every frame.
    //
    // Applied to the whole stroke rather than per-bead-age on purpose: a listener reads
    // "the drawing swelled just then" far more easily than a travelling wave along a
    // curve, and a per-bead phase would fight the age falloff that mandatory trait #2
    // requires to stay monotonic. Thickness AND brightness together — either alone is
    // easy to miss on a thin stroke against black.
    //
    // Bounded ±22 % / ±35 %: enough to read as breathing, not so much that a loud bar
    // turns the ribbon into a different object. `energyBreath` is centred on 0.5, so
    // silence leaves this at exactly 1.0 and D-037's non-black silence state is unchanged.
    float breath = cfg.energyBreath * 2.0 - 1.0;          // -1…+1
    radius *= 1.0 + 0.22 * breath;
    alpha  *= 1.0 + 0.35 * breath;

    float2 corner = wl_corner(vid);
    float2 halfExtent = wl_screen_extent(radius * WL_HALO_EXTENT * proj.z, cfg);

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
    //
    // WL.2-g — why the halo is a LIFTED colour rather than the raw hue. Bead hue is laid
    // down at S 0.80 / V 1.0 (§3.4), so its Rec.601 luma runs 0.29 (violet/blue) to 0.67
    // (yellow-green). Multiplying that by a halo profile leaves the violet half of the hue
    // circle permanently below the luminance the source's ribbon actually carries — the
    // measured 9× shortfall in the M7 frame was almost entirely this: only the pinpoint
    // core ever crossed, so the ribbon read as hard dots on a thread instead of `08`'s
    // glowing arc. The halo is therefore mixed toward a cool blue-white before it is
    // scaled, which buys luminance at every hue while keeping the hue legible — `08`'s
    // halo is *cooler* than its core, not merely dimmer, so the lift is the reference
    // behaviour rather than a brightness workaround.
    // Core radius is rescaled back out of the widened quad so it stays pinned to the bead
    // size, independent of WL_HALO_EXTENT.
    float rc2 = r2 * (WL_HALO_EXTENT * WL_HALO_EXTENT);
    float core = exp(-rc2 * 9.0);
    // Windowed to zero at the quad edge. Without it a halo bright enough to read leaves a
    // hard disc boundary where `discard_fragment` cuts it.
    float halo = exp(-r2 * 2.8) * smoothstep(1.0, 0.75, r2);
    // 0.34, not more. A cooler halo is closer to `08` in the abstract, but at 0.44 the
    // stroke measurably lost its hue (the head washed to neutral white) for no gain in
    // ribbon share — and hue IS the information here (trait #7), so the lift stops at the
    // point where it buys luminance and stops before it starts costing colour.
    float3 cool = mix(in.color, float3(0.58, 0.66, 1.0), 0.34);
    // The core reaches near-white and saturates (`08`: a real arc core is white). Trait #7
    // is not lost by this: the hue lives in the halo, which is the far larger area — a
    // white core inside a violet halo still reads violet, and it is the only way the peak
    // reaches the source's 255 rather than topping out at the hue's brightest channel.
    float3 hot = mix(in.color, float3(1.0), 0.90);
    // The split matters more than the total, and level alone is close to useless here:
    // near-doubling it moved ribbon share only 0.405 % → 0.421 %, because `wl_age_alpha`
    // scales the whole sprite, so extra level saturates the head while the faded tail
    // stays under threshold either way. Worse, beads emit at ~34 Hz and blending is
    // ADDITIVE, so a halo bright enough to read on its own sums with its neighbours into
    // the uniform white tube of anti-`11` (measured: a 2.5/1.6 split did exactly that).
    // The halo is therefore set to read as a glow only where several beads overlap, and
    // the per-bead sparkle is carried by the core, whose area is too small to stack into
    // a tube. The falloff curve is untouched throughout — still exactly `(1-t)^1.6`,
    // still monotonic (mandatory trait #2); the tail gains presence from reach, not level.
    // WL.2-h raised these from 1.45/2.0. Not a re-tune: WL.2-g's numbers were measured over
    // a backdrop that was contributing additive light under the ribbon, and dropping the
    // quiet field to the source's darkness took ribbon share 0.707 % → 0.541 % without the
    // beads changing at all. The ribbon now has to carry its own luminance the way the
    // source's does over ITS near-black ground, which is the honest version of the same
    // target rather than a borrowed one.
    float3 rgb = cool * halo * 2.4 + hot * core * 4.5;
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
    // Breathes with the beads (WL.4) — a static thread between pulsing beads reads as a
    // wire the beads are sliding on, which is the opposite of the intended reading.
    out.alpha = wl_age_alpha(b.age, cfg.trailSeconds) * cfg.lineAlpha
              * (1.0 + 0.35 * (cfg.energyBreath * 2.0 - 1.0));
    return out;
}

fragment float4 witchlight_line_fragment(WLLineOut in [[stage_in]]) {
    // The thread the beads sit on: hue-carrying but dimmer than the beads, so the
    // stroke reads as beads-on-a-thread rather than as a uniform glow tube (anti-`11`).
    // WL.2-g lifts it — `01`/`02` are a line *that glows* with sparks on it, and at the
    // pre-WL.2-g level the thread was invisible between beads, which is what made the
    // ribbon read as a row of dots. It stays well under the bead level, so the
    // beads-on-a-thread reading (and the distance from `11`) is preserved.
    return float4(mix(in.color, float3(1.0), 0.45) * in.alpha * 3.5, 1.0);
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
