// StaveTrace.metal — Stave's four geometry passes, drawn on top of the field backdrop.
//
// The backdrop (`Presets/Shaders/Stave.metal`, `stave_field_fragment`) draws first as the
// particle-mode preset triangle; these passes then recolour and mark it:
//
//   stave_tint    fullscreen MULTIPLY wash — the room the stems tint (D-216)
//   stave_rule    vertical rules on cached BeatGrid beats
//   stave_thread  the faint connecting thread between beads
//   stave_bead    the beads themselves — the hero trait (`02_meso_bead_spacing.png`)
//
// All four share one vertex struct and one config struct with `StaveTrace.swift`; field
// ORDER is the contract, not field names.

#include <metal_stdlib>
using namespace metal;

// MARK: - Shared structs

// PACKED, and this is load-bearing. A plain `float4 color` is 16-byte aligned in MSL, which
// pads this struct to a 48-byte stride against Swift's 28 — the vertex buffer is then read at
// the wrong offsets and the traces render as large mis-coloured triangles (CHR.2 defect 1;
// magenta in a flat-WHITE control was the tell). Same reason `Particles.metal` uses
// `packed_float4`.
struct StaveVertexGPU {
    packed_float2 pos;
    packed_float4 color;
    float width;
};

// All scalar floats — no vector members, so there is no alignment padding to disagree about.
struct StaveConfigGPU {
    float aspect;
    float tintR;
    float tintG;
    float tintB;
    float ruleAlpha;
    float time;
};

struct StaveVOut {
    float4 position [[position]];
    float4 color;
    float2 local;
};

static_assert(sizeof(StaveVertexGPU) == 28, "StaveVertexGPU must stay 28 bytes");
static_assert(sizeof(StaveConfigGPU) == 24, "StaveConfigGPU must stay 24 bytes");

// MARK: - Tint wash

vertex StaveVOut stave_tint_vertex(uint vid [[vertex_id]],
                                   constant StaveConfigGPU &cfg [[buffer(1)]]) {
    float2 p = float2((vid & 1) ? 1.0 : -1.0, (vid >> 1) ? 1.0 : -1.0);
    StaveVOut o;
    o.position = float4(p, 0.0, 1.0);
    o.color = float4(cfg.tintR, cfg.tintG, cfg.tintB, 1.0);
    o.local = p * 0.5 + 0.5;
    return o;
}

fragment float4 stave_tint_fragment(StaveVOut in [[stage_in]]) {
    // Multiply blend: the returned colour scales the backdrop. Every channel is <= 1 and the
    // peak channel is pinned to 1 on the Swift side, so this recolours without darkening the
    // frame overall — the field's haze, cloud and sparkle survive being tinted (reference
    // `03`: colour lives in the field, the structure stays).
    return in.color;
}

// MARK: - Segment-quad expansion (rules and thread)

/// `.lineStrip` cannot carry a per-sample thickness, so both the rules and the thread expand
/// each segment into a quad. Shared by `stave_rule_vertex` and `stave_thread_vertex`.
static inline StaveVOut stave_expand_segment(uint vid,
                                             StaveVertexGPU a,
                                             StaveVertexGPU b,
                                             float aspect) {
    // Perpendicular in aspect-corrected space, so the ribbon keeps an even thickness on a
    // steep segment instead of pinching.
    float2 d = float2((b.pos.x - a.pos.x) * aspect, b.pos.y - a.pos.y);
    float len = length(d);
    // A degenerate segment has no meaningful direction, so its perpendicular is pure
    // numerical noise and the quad splays in a random direction. Fall back to a vertical
    // normal rather than normalising near-zero (CHR.2 defect 3's other half — the 20 Hz plot
    // rate is the first half).
    float2 n = (len > 1e-4) ? float2(-d.y, d.x) / len : float2(0.0, 1.0);
    n.x /= aspect;

    bool atEnd = (vid >= 2);
    StaveVertexGPU s = atEnd ? b : a;
    float side = (vid & 1) ? 1.0 : -1.0;

    StaveVOut o;
    o.position = float4(s.pos + n * side * s.width, 0.0, 1.0);
    o.color = s.color;
    o.local = float2(side, atEnd ? 1.0 : 0.0);
    return o;
}

// MARK: - Vertical rules (the beat)

vertex StaveVOut stave_rule_vertex(uint vid [[vertex_id]],
                                   const device StaveVertexGPU *verts [[buffer(0)]],
                                   constant StaveConfigGPU &cfg [[buffer(1)]]) {
    StaveVOut o = stave_expand_segment(vid, verts[0], verts[1], cfg.aspect);
    // Density fade (§5 decision (c)) — meter-free, so no `beatsPerBar` inference is needed.
    // Above ~23 rules per 8 s window (Bleed, 172 bpm) the rules stop reading as a pulse and
    // start reading as graph paper; fading opacity keeps them present without ruling.
    o.color.a *= cfg.ruleAlpha;
    return o;
}

fragment float4 stave_rule_fragment(StaveVOut in [[stage_in]]) {
    // Soft-edged so a 1-2 px rule does not alias into a dotted line, and dimmer at the top
    // and bottom so the rules read as ruling on a field rather than as bars across it.
    float edge = 1.0 - smoothstep(0.55, 1.0, abs(in.local.x));
    float4 c = in.color;
    c.a *= edge * 0.5;
    return float4(c.rgb * c.a, c.a);
}

// MARK: - Thread

vertex StaveVOut stave_thread_vertex(uint vid [[vertex_id]],
                                     uint iid [[instance_id]],
                                     const device StaveVertexGPU *verts [[buffer(0)]],
                                     constant StaveConfigGPU &cfg [[buffer(1)]]) {
    StaveVertexGPU a = verts[iid];
    StaveVertexGPU b = verts[iid + 1];
    // The thread is much thinner than the beads it connects: reference `02` makes the beads
    // the hero and `05_anti_solid_line_plot.png` is exactly two solid polylines, so the
    // thread stays subordinate — it says the beads belong to one trace and nothing more.
    a.width *= 0.16;
    b.width *= 0.16;
    return stave_expand_segment(vid, a, b, cfg.aspect);
}

fragment float4 stave_thread_fragment(StaveVOut in [[stage_in]]) {
    float edge = 1.0 - smoothstep(0.4, 1.0, abs(in.local.x));
    float4 c = in.color;
    c.a *= edge * 0.42;
    return float4(c.rgb * c.a, c.a);
}

// MARK: - Beads

vertex StaveVOut stave_bead_vertex(uint vid [[vertex_id]],
                                   uint iid [[instance_id]],
                                   const device StaveVertexGPU *verts [[buffer(0)]],
                                   constant StaveConfigGPU &cfg [[buffer(1)]]) {
    StaveVertexGPU s = verts[iid];
    float2 corner = float2((vid & 1) ? 1.0 : -1.0, (vid >> 1) ? 1.0 : -1.0);
    // The halo needs room outside the bead core, so the quad is drawn oversized and the
    // fragment falls off inside it.
    float2 extent = float2(s.width * 2.6 / cfg.aspect, s.width * 2.6);

    StaveVOut o;
    o.position = float4(s.pos + corner * extent, 0.0, 1.0);
    o.color = s.color;
    o.local = corner;
    return o;
}

fragment float4 stave_bead_fragment(StaveVOut in [[stage_in]]) {
    float r = length(in.local);
    if (r > 1.0) { discard_fragment(); }
    // Core plus a soft halo — reference `02`: "beads carry soft glow halos". Two terms rather
    // than one so the bead has a defined body instead of being a pure gaussian smudge, which
    // is what makes bead SIZE readable at all.
    float core = exp(-r * r * 14.0);
    float halo = exp(-r * r * 2.6) * 0.30;
    float a = in.color.a * (core + halo);
    return float4(in.color.rgb * a, a);
}
