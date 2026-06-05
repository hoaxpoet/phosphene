// Skein.metal — Skein.1: canvas-hold accumulation + the wandering pour line.
//
// Skein is an ACTION-PAINTING / drip-pour visualiser (Pollock's poured technique;
// see docs/presets/SKEIN_DESIGN.md). The canvas-hold accumulation path (identity warp,
// no decay, no colour transfer) lands the LOSSLESS persistent paint canvas; Skein.1 adds
// the first real mark — a SINGLE white pour LINE traced by a wandering "painter" (a closed-
// form ergodic trajectory of features.time), accumulating losslessly on the cream ground.
// There is still NO audio routing, NO splatter / filaments, NO viscosity, NO wetness, NO
// palette beyond white-on-cream, NO mood here — all of that begins at Skein.2+. The pour line
// is the gate-before-the-gate: does a persistent skein hold and read as poured paint?
// (SKEIN_DESIGN §7.) `skein_fragment` remains the flat cream GROUND (what the PresetAcceptance
// + contrast harnesses render; Skein is readable-form-exempt — the mark lives in the overlay).
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

// ── Skein.1: the wandering painter (closed-form ergodic pour trajectory) ───────────
//
// Replaces the ENGINE.1.1 static test disc with a SINGLE moving emission locus — the
// "painter" (SKEIN_DESIGN §1.1). Its position is a CLOSED-FORM function of features.time:
// a sum of incommensurate sinusoids (frequencies in golden-ratio φ multiples, so the 2D
// path is quasi-periodic — it never exactly repeats and fills the canvas ergodically with
// NO focal point: the "allover" composition, SKEIN_DESIGN §1.0 fact (2) / ref
// 01_macro_allover_field.jpg). Driven by features.time ONLY — no audio until Skein.3.
//
// LOAD-BEARING — the loops are the GESTURE, never a coiling term (SKEIN_DESIGN §1.0 fact (1)):
// the fluid-dynamics finding is that Pollock *deliberately avoided* the rope-coil instability;
// the line BETWEEN gesture points is a mostly-straight filament, and the sinuous skeins come
// from his whole-body motion. So the curvature here is PURELY the sinusoid sum (the gesture) —
// there is NO fbm / curl / coil applied to the line. All three frequencies sit in the GESTURE
// band (periods ≈ 13–38 s), never a sub-second jitter band, so the wander reads as a thrown
// gesture (refs 01/02/03_micro_filament_threads), not a vibration.
//
// Path A (the Skein.1 audit): the painter position is computed in the VERTEX shader, which
// already receives `features` at buffer(0) via drawSceneGeometryOverlay — the same slot
// dragon_bloom_strand_vertex reads. The position is a per-frame scalar (identical across the
// 3 fullscreen-triangle verts), passed to the fragment as a varying. ZERO engine touch, no
// per-preset buffer, no CPU state — exactly the ENGINE.1.1 disc pattern with a time-varying
// centre + a swept capsule. (CPU-side SkeinState + an overlay-buffer binding are deferred to a
// future ENGINE.1.2 when Skein.2's stateful painter — droplet positions, per-stem integrators —
// genuinely needs them; not smuggled into Skein.1. SKEIN_DESIGN §7, FA #59/#60.)

// Base pour half-width (v-height units; ≈2 % of canvas height → a thin pour filament). The
// per-frame radius rides this by a speed factor (see skein_geometry_vertex).
constant float kSkeinLineRadius = 0.010;

// Painter position at time t, in UV [0,1]². THREE GESTURE SCALES per axis, at deliberately
// non-harmonic (incommensurate) frequencies → a quasi-periodic path that never exactly repeats
// and fills the canvas ergodically (allover, no focal point — SKEIN_DESIGN §1.0 fact (2)):
//   • SLOW DRIFT  (period ≈ 29 / 33 s): carries the painter across the canvas — the "localized
//     island, then a longer trajectory that joins the islands" build order (§1.0 fact (2)).
//   • GESTURE LOOP (period ≈ 6.6 / 5.9 s): the main looping skeins that cross and double back.
//   • TIGHT LOOP  (period ≈ 2.7 / 2.4 s): finer secondary loops. Still firmly GESTURE scale —
//     NOT a sub-second jitter / coiling term (§1.0 fact (1): the loops are the whole-body gesture,
//     never a noise/coil function; the line BETWEEN gesture points is a mostly-straight filament).
// x and y use DIFFERENT frequencies + phases so the figure is asymmetric (NOT a clean Lissajous /
// spirograph — SKEIN_DESIGN §2 anti-reference). Per-axis amplitudes sum to ≈0.46 so the path stays
// inside ≈[0.04, 0.96] (edge-to-edge, a sliver of margin). The constants are the fixed "seed" for
// the spike (per-track seeding is Skein.3).
static inline float2 skeinPainterPos(float t) {
    float x = 0.5
        + 0.300 * sin(0.220 * t + 0.0)    // slow drift   — period ≈ 28.6 s
        + 0.110 * sin(0.950 * t + 1.7)    // gesture loop — period ≈ 6.6 s
        + 0.045 * sin(2.300 * t + 4.2);   // tight loop   — period ≈ 2.7 s
    float y = 0.5
        + 0.280 * cos(0.190 * t + 2.3)    // slow drift   — period ≈ 33 s
        + 0.120 * cos(1.070 * t + 5.1)    // gesture loop — period ≈ 5.9 s
        + 0.040 * cos(2.620 * t + 0.9);   // tight loop   — period ≈ 2.4 s
    return float2(x, y);
}

// Unsigned distance from p to the 2D segment a→b (project-clamp-distance — the 2D capsule
// core). Degenerate a==b (a perfect turning point) collapses to distance-to-point (a disc).
static inline float skeinSegDist(float2 p, float2 a, float2 b) {
    float2 pa = p - a;
    float2 ba = b - a;
    float  h  = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-9), 0.0, 1.0);
    return length(pa - ba * h);
}

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

// ── Marks-on-top overlay (Skein.1) ─────────────────────────────────────────────────
//
// Draws THIS FRAME'S new pour mark — a swept capsule from painter(t−Δt) → painter(t) — as a
// fullscreen-triangle overlay composited NORMAL-ALPHA on top of the held canvas (the D-138
// marks-on-top mechanism, reachable per-preset since D-143; Dragon Bloom resolves
// `dragon_bloom_strand_*`, Skein resolves these). The painter MOVES each frame, so the capsule
// lands in a NEW place and is then carried forward losslessly by the identity warp + no decay:
// the union of every frame's capsule is the accumulating, continuous, looping pour LINE on the
// cream canvas. Draw params (3 verts / 1 instance / .triangle) come from Skein.json `marks`.
//
// AA is correct here (unlike the ENGINE.1.1 static disc, which was hard-edged for idempotent
// in-place redraw): each capsule is stamped ONCE at a new position and then held — it never
// re-blends in place, so a soft anti-aliased edge does not compound (SKEIN_DESIGN §5.2).
//
// White-on-cream ONLY — palette is Skein.3. No splatter / filaments / viscosity / wetness here.

struct SkeinGeoVertexOut {
    float4 position [[position]];
    float2 uv;
    // Per-frame painter state, computed once in the vertex (constant across the 3 verts) and
    // read in the fragment. Path A: no per-preset buffer — features reaches only the vertex.
    float2 posNow;    // painter UV this frame
    float2 posPrev;   // painter UV last frame (= previous frame's posNow → gap-free chaining)
    float  radius;    // pour half-width (v-units), speed-shaped (pool ↔ filament)
    float  aspect;    // viewport aspect, for isotropic line width
};

vertex SkeinGeoVertexOut skein_geometry_vertex(
    uint vid [[vertex_id]],
    constant FeatureVector& f [[buffer(0)]]   // bound by drawSceneGeometryOverlay (vertex slot 0)
) {
    // Fullscreen triangle in clip space: (-1,-1), (-1,3), (3,-1) — covers the viewport.
    float2 p = float2((vid == 2) ? 3.0 : -1.0, (vid == 1) ? 3.0 : -1.0);
    SkeinGeoVertexOut out;
    out.position = float4(p, 0.0, 1.0);
    out.uv = p * 0.5 + 0.5;   // 0..1

    float aspect = (f.aspect_ratio > 0.01) ? f.aspect_ratio : 1.0;
    float t  = f.time;
    float dt = max(f.delta_time, 1.0 / 240.0);   // guard a zero Δt (would degenerate the capsule)

    // Chaining: posPrev = painter(t−Δt) is exactly the PREVIOUS frame's posNow when time advances
    // by Δt each frame, so consecutive capsules share an endpoint → one continuous, gap-free line.
    float2 now  = skeinPainterPos(t);
    float2 prev = skeinPainterPos(t - dt);

    // Speed-shaped width (SKEIN_DESIGN §1.0 fact (1) / §1.2): the painter LINGERS at the turning
    // points of its trajectory → the line POOLS (thicker, ref 02_meso_pour_pools); it sweeps fast
    // mid-swing → a thin FILAMENT (ref 03_micro_filament_threads). This is gesture physics
    // (width ∝ 1/speed), NOT a noise term — it breaks the "clean geometric tube" anti-reference
    // without faking coiling. Bounded [0.75, 1.6]× so it stays a single legible line.
    float2 dCorr = float2((now.x - prev.x) * aspect, now.y - prev.y);
    float  speed = length(dCorr) / dt;                              // v-units / s, aspect-correct
    float  wscale = mix(1.6, 0.75, smoothstep(0.05, 0.35, speed));  // pool ↔ filament

    out.posNow  = now;
    out.posPrev = prev;
    out.radius  = kSkeinLineRadius * wscale;
    out.aspect  = aspect;
    return out;
}

fragment float4 skein_geometry_fragment(SkeinGeoVertexOut in [[stage_in]]) {
    // Distance to the swept capsule, measured in an aspect-corrected space (x × aspect) so the
    // line width is isotropic in pixels regardless of viewport shape.
    float a = in.aspect;
    float2 q  = float2(in.uv.x      * a, in.uv.y);
    float2 pA = float2(in.posPrev.x * a, in.posPrev.y);
    float2 pB = float2(in.posNow.x  * a, in.posNow.y);
    float d = skeinSegDist(q, pA, pB);

    // Anti-aliased coverage (~1 px transition via the screen-space derivative). Drawn once at a
    // new position each frame then held, so the AA edge never compounds (see the overlay note).
    float aa = max(fwidth(d), 1e-4);
    float cover = 1.0 - smoothstep(in.radius - aa, in.radius + aa, d);

    // White pour on the held cream ground (white-on-cream only — palette is Skein.3). Overlay
    // blend is SRC_ALPHA / ONE_MINUS_SRC_ALPHA (PresetLoader.makeSceneGeometryPipeline).
    return float4(float3(1.0), cover);
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
