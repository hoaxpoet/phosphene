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
constant float3 kSkeinCanvasCream = float3(0.66, 0.60, 0.50);

// The single hard-coded TEST STAMP — a fixed disc. Not a real mark model; it exists
// only to give the persistence test a non-trivial pattern to hold and the
// PresetAcceptance "readable form" gate ≥2 luma bins. A deep teal, well separated
// from the cream ground. All real mark morphology is Skein.2+.
constant float2 kSkeinStampCentre = float2(0.5, 0.5);
constant float  kSkeinStampRadius = 0.16;
constant float  kSkeinStampAA     = 0.006;
constant float3 kSkeinStampColor  = float3(0.06, 0.30, 0.32);

// ── Background / canvas fragment ──────────────────────────────────────────────────
//
// Renders ONE frame of the base canvas: cream ground + the fixed test stamp. In the
// canvas-hold path this is the "scene" drawn once onto the held canvas; the mv_warp
// warp pass then carries it forward losslessly without re-rendering. Feature-invariant
// by design — ENGINE.1 has no audio routing (Skein.4 wires the real emission).

fragment float4 skein_fragment(
    VertexOut               in    [[stage_in]],
    constant FeatureVector& f     [[buffer(0)]],   // unused (no audio routing until Skein.4)
    constant float*         fft   [[buffer(1)]],   // unused
    constant float*         wv    [[buffer(2)]],   // unused
    constant StemFeatures&  stems [[buffer(3)]]    // unused
) {
    float  d        = length(in.uv - kSkeinStampCentre);
    float  inStamp  = 1.0 - smoothstep(kSkeinStampRadius - kSkeinStampAA,
                                       kSkeinStampRadius + kSkeinStampAA, d);
    float3 colour   = mix(kSkeinCanvasCream, kSkeinStampColor, inStamp);
    return float4(colour, 1.0);
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
