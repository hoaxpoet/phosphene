// Skein.metal — Skein.ENGINE.1: the canvas-hold accumulation path.
//
// Skein is an ACTION-PAINTING / drip-pour visualiser (Pollock's poured technique;
// see docs/presets/SKEIN_DESIGN.md). This file is the ENGINE.1 SKELETON only — it
// establishes the persistent, LOSSLESS paint canvas and nothing else. There is NO
// mark morphology, NO audio routing, NO wetness, NO palette, NO mood here; all of
// that begins at Skein.1+. The only "paint" is a single hard-coded test stamp
// (a fixed disc on a cream ground), present solely so the persistence test and the
// PresetAcceptance "readable form" gate have something to read.
//
// ── Canvas-hold = the no-decay / identity CONFIG of the mv_warp brush-on-feedback
//    paradigm (D-135 / D-138). It is NOT a new render paradigm and NOT a D-029
//    concern — Skein is a SIBLING of Dragon Bloom (`passes: ["direct","mv_warp"]`).
//    The ENGINE.1 audit (see closeout + DECISIONS D-142) established that canvas-hold
//    is reachable as pure per-preset CONFIG of the existing mv_warp machinery — no
//    engine source change, no new warp mode:
//      • IDENTITY warp   — mvWarpPerVertex returns `uv` unchanged; mvWarpPerFrame
//                          returns zoom=1, rot=0, no translation. The shared
//                          `mvWarp_fragment` then samples prev at the un-displaced UV.
//      • NO DECAY        — mvWarpPerFrame returns decay = 1.0; the shared warp
//                          fragment's `decayMul = (chromaticMix>0)?1.0:in.decay`
//                          resolves to in.decay = 1.0 (chromaticMix is 0 for Skein —
//                          the default; the app sets setMVWarpChromatic(0) for any
//                          preset with no scene-geometry overlay).
//      • NO R→G→B TRANSFER — chromaticMix = 0 collapses the hue-zoom resample +
//                          colour transfer in `mvWarp_fragment` to identity.
//    Net: under identity + no-decay + no-transfer the warp fragment returns the
//    previous canvas byte-for-byte (an unpainted texel is copied unchanged frame
//    after frame). 8-bit is therefore lossless — see SKEIN_DESIGN.md §5.5.
//
//    Marks (Skein.1+) composite normal-alpha ON TOP of the held canvas via the same
//    setSceneGeometry strands-on-top mechanism Dragon Bloom already ships (D-138).
//
// Gate: SkeinCanvasHoldTest proves Hamming-0 persistence across ≥120 frames through
// the live scene → warp → swap dispatch path.

// ── Canvas constants (ENGINE.1 placeholders only) ─────────────────────────────────

// ENGINE.1 PLACEHOLDER ground — a warm TONED canvas (mid-value, like an imprimatura),
// NOT the design's bright cream. Deliberately darkened so white overlay chrome clears
// the WCAG 4.5:1 contrast gate (PresetContrastCertificationTests): a bright cream ground
// drops white-text contrast to ~4.23:1. Skein is the FIRST light-ground preset, so the
// design's "ground stays light" (SKEIN_DESIGN §1.2) is in genuine tension with the white
// playback chrome — a Skein.1+ palette/UX decision (darker chrome backdrop for light
// presets, dark chrome text, or a toned ground). Canvas-hold is colour-agnostic, so this
// value is not load-bearing for ENGINE.1. See the ENGINE.1 closeout + SKEIN_DESIGN flag.
//
// Skein.ENGINE.1.1 (D-143): this MUST stay byte-identical to Skein.json `marks.canvas_clear`.
// LIVE, the held ground comes from the per-preset canvas CLEAR (the marks-on-top path skips
// Pass 0, so skein_fragment is not drawn); skein_fragment below renders the same value for
// the single-frame acceptance/contrast harnesses. Keep the two in sync.
constant float3 kSkeinCanvasCream = float3(0.66, 0.60, 0.50);

// The single hard-coded TEST STAMP — a fixed disc. Not a real mark model; it exists only
// to give the persistence test a non-trivial pattern to hold. A deep teal, well separated
// from the cream ground. All real mark morphology is Skein.2+.
//
// HARD EDGE (no AA): the marks-on-top overlay redraws this stamp EVERY frame onto the held
// canvas (the live path runs drawSceneGeometryOverlay per frame). A normal-alpha redraw is
// IDEMPOTENT only when alpha is exactly 0 or 1 — teal-over-teal and keep-cream both produce
// byte-identical frames (the canvas-hold "consecutive frames byte-identical" contract). A
// partial-alpha AA fringe would re-blend toward teal every frame and creep for hundreds of
// frames. Real Skein.1 marks are drawn ONCE as the painter moves (not redrawn in place), so
// they get their AA without this constraint.
constant float2 kSkeinStampCentre = float2(0.5, 0.5);
constant float  kSkeinStampRadius = 0.16;
constant float3 kSkeinStampColor  = float3(0.06, 0.30, 0.32);

// ── Background / canvas fragment ──────────────────────────────────────────────────
//
// Renders the flat cream/toned GROUND only. Skein.ENGINE.1.1 (D-143) moved the test
// stamp OUT of this fragment and into the marks-on-top overlay (skein_geometry_*, below):
//   • LIVE, the marks-on-top path SKIPS this fragment (Pass 0 is not run for presets with
//     a scene-geometry overlay); the held ground comes from the canvas CLEAR (same value,
//     kSkeinCanvasCream) and the disc is drawn on top by the overlay every frame.
//   • This fragment is still what the single-frame acceptance / contrast harnesses render
//     (they call preset.pipelineState directly), so it must equal the live ground.
// Feature-invariant by design — Skein has no audio routing until Skein.4.

fragment float4 skein_fragment(
    VertexOut               in    [[stage_in]],
    constant FeatureVector& f     [[buffer(0)]],   // unused (no audio routing until Skein.4)
    constant float*         fft   [[buffer(1)]],   // unused
    constant float*         wv    [[buffer(2)]],   // unused
    constant StemFeatures&  stems [[buffer(3)]]    // unused
) {
    return float4(kSkeinCanvasCream, 1.0);
}

// ── Marks-on-top overlay (Skein.ENGINE.1.1, D-143) ─────────────────────────────────
//
// Draws the fixed TEST STAMP (the disc) as a fullscreen-triangle overlay composited
// NORMAL-ALPHA on top of the held canvas — the D-138 marks-on-top mechanism, now reachable
// per-preset (Dragon Bloom resolves `dragon_bloom_strand_*`; Skein resolves these). Live,
// the disc is redrawn in place every frame onto the warped/held frame; identity warp + no
// decay carry the canvas forward losslessly, so the result is a Hamming-0 hold.
//
// ENGINE.1.1 SKELETON ONLY: the stamp is STATIC (fixed UV, no audio, no motion). The
// wandering painter + swept-capsule pour that ACCUMULATE a continuous line are Skein.1.
// Draw params (3 verts / 1 instance / .triangle) come from Skein.json `marks`.

struct SkeinGeoVertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex SkeinGeoVertexOut skein_geometry_vertex(uint vid [[vertex_id]]) {
    // Fullscreen triangle in clip space: (-1,-1), (-1,3), (3,-1) — covers the viewport.
    float2 p = float2((vid == 2) ? 3.0 : -1.0, (vid == 1) ? 3.0 : -1.0);
    SkeinGeoVertexOut out;
    out.position = float4(p, 0.0, 1.0);
    out.uv = p * 0.5 + 0.5;   // 0..1; the disc is centred + radially symmetric, so Y-flip is moot
    return out;
}

fragment float4 skein_geometry_fragment(SkeinGeoVertexOut in [[stage_in]]) {
    float d = length(in.uv - kSkeinStampCentre);
    // HARD edge (alpha ∈ {0,1}) so the per-frame redraw is idempotent — see kSkeinStamp*.
    float inStamp = (d <= kSkeinStampRadius) ? 1.0 : 0.0;
    // Normal-alpha over the held canvas: opaque teal inside the disc, fully transparent
    // outside so the cream ground shows through. The overlay pipeline's blend is
    // SRC_ALPHA / ONE_MINUS_SRC_ALPHA (PresetLoader.makeSceneGeometryPipeline).
    return float4(kSkeinStampColor, inStamp);
}

// ── MV-Warp functions (D-027) — the canvas-hold config ─────────────────────────────
// Both required by the mvWarpPreamble forward declarations. Identity + no decay.

MVWarpPerFrame mvWarpPerFrame(
    constant FeatureVector& f,
    constant StemFeatures&  stems,
    constant SceneUniforms& s
) {
    MVWarpPerFrame pf;
    pf.zoom = 1.0;        // no zoom
    pf.rot  = 0.0;        // no rotation
    pf.decay = 1.0;       // NO DECAY — paint persists (canvas-hold). Must match Skein.json `decay`.
    pf.warp = 0.0;        // no warp ripple
    pf.cx = 0.0; pf.cy = 0.0;   // warp centre = screen centre (irrelevant at identity)
    pf.dx = 0.0; pf.dy = 0.0;   // no translation
    pf.sx = 1.0; pf.sy = 1.0;   // no scale correction
    pf.q1 = 0.0; pf.q2 = 0.0; pf.q3 = 0.0; pf.q4 = 0.0;
    pf.q5 = 0.0; pf.q6 = 0.0; pf.q7 = 0.0; pf.q8 = 0.0;
    return pf;
}

float2 mvWarpPerVertex(
    float2 uv, float rad, float ang,
    thread const MVWarpPerFrame& pf,
    constant FeatureVector& f,
    constant StemFeatures& stems
) {
    // IDENTITY warp — the canvas does not move once paint lands. Returning the
    // un-displaced UV means the shared `mvWarp_fragment` samples the previous frame
    // at exactly this fragment's texel → a lossless copy (no resampling, no drift).
    return uv;
}
