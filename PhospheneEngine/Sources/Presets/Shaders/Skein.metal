// Skein.metal — Skein.3: canvas-hold accumulation + audio-routed, per-stem-coloured drip painting.
//
// Skein is an ACTION-PAINTING / drip-pour visualiser (Pollock's poured technique;
// see docs/presets/SKEIN_DESIGN.md). The canvas-hold accumulation path (identity warp,
// no decay, no colour transfer) lands the LOSSLESS persistent paint canvas; Skein.1 added
// the wandering "painter" pour LINE (a closed-form ergodic trajectory), Skein.2 the SPLATTER
// VOCABULARY — the VisComp 2014 droplet + filament layers (Ni et al.; SKEIN_DESIGN §1.0):
// velocity-biased droplet BURSTS with ragged organic edges and exp/poly satellite falloff (ref
// 03_micro_satellite_spatter), thin connecting FILAMENT tendrils (ref 03_micro_filament_threads),
// and a VISCOSITY axis (thin-fast-fine ↔ thick-slow-gloopy; refs 02_meso_pour_pools /
// 06_palette_saturated_peak) shaping every mark — all baked normal-alpha into the held canvas.
//
// Skein.3 makes the painting MUSICAL (the §5.4 routing): the fragment now consumes SkeinState's
// SkeinUniforms at fragment buffer(6) (the ENGINE.1.2 gated strands-on-top slot-6 binding), so the
// marks are STEM-COLOURED and AUDIO-DRIVEN:
//   • painter clock     ← audio-modulated painterTau (busy passages fill faster);
//   • pour LINE colour   ← the dominant stem (SkeinState discrete argmax — never a colour blend);
//   • splatter BURSTS    ← real per-stem ONSETS (rising edges on *_energy_dev, in SkeinState), each
//                          frozen at its stem's colour (the onset-burst ring) — RETIRES the Skein.2
//                          debug flick schedule;
//   • viscosity          ← each burst's spectral centroid (RETIRES the debug viscosity sweep);
//   • flick sharpness    ← attackRatio; pour width ← the dominant stem's energy deviation;
//   • per-track seed     ← seedPhase offsets on the trajectory (the §5.7 determinism property).
// NO wetness/sheen (ENGINE.2/Skein.4), NO mood/valence/arousal (Skein.5).
//
// Marks composite OPAQUE: the fragment tracks the TOPMOST mark's colour by coverage (paired
// bestCover/bestCol — never averaging two stem colours into mud, the dead-mat anti-ref), and the
// normal-alpha overlay blend occludes the held canvas. `skein_fragment` remains the flat cream
// GROUND (what the PresetAcceptance + contrast harnesses render; the marks live in the overlay).
// The gate stays aesthetic: read as POURED PAINT (Pollock), never a particle fountain / clean
// polka-dots / brush stroke / dead mat / kaleidoscope (the 5 Skein.0 anti-refs) — AND now legibly
// per-stem (drums flicks / bass pools / vocals lines, distinct by colour).
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
// Skein.3: `phx`/`phy` are the per-track seed phase offsets (SkeinUniforms.seedPhaseX/Y) — same
// track → same offsets → same painting (§5.7 determinism). phx == phy == 0 reproduces the exact
// Skein.1/2 trajectory (the seed-0 base the corridor test mirror checks against).
static inline float2 skeinPainterPos(float t, float phx, float phy) {
    float x = 0.5
        + 0.300 * sin(0.220 * t + 0.0 + phx)   // slow drift   — period ≈ 28.6 s
        + 0.110 * sin(0.950 * t + 1.7 + phx)   // gesture loop — period ≈ 6.6 s
        + 0.045 * sin(2.300 * t + 4.2 + phx);  // tight loop   — period ≈ 2.7 s
    float y = 0.5
        + 0.280 * cos(0.190 * t + 2.3 + phy)   // slow drift   — period ≈ 33 s
        + 0.120 * cos(1.070 * t + 5.1 + phy)   // gesture loop — period ≈ 5.9 s
        + 0.040 * cos(2.620 * t + 0.9 + phy);  // tight loop   — period ≈ 2.4 s
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

// ── Skein.2: 2D ragged-edge noise + splatter / viscosity constants ─────────────────
//
// 4-octave 2D fBM (the 2D analogue of the hero-surface ≥4-octave floor the README mandates
// on the edge / spatter fields). Built from the preamble's `perlin2d` (gradient noise — NOT
// value-on-lattice), sampled at NON-integer coords with an inter-octave rotation, so the FA #43
// Perlin lattice-degeneracy trap (value noise at integer lattice points; thresholds in the
// dead [0.4,1.0] band) does not apply: perlin2d is centred at 0 (range ~[-0.9,0.9]) and we ride
// it as a ±amplitude radius perturbation, never threshold it. Scale must be ≥3 at the call site
// (we use 70 / 120) — see SHADER_CRAFT.md §3.
static inline float skein_fbm2(float2 p) {
    // ~37° orthonormal rotation between octaves (det = 1) — breaks axis-aligned fBM banding.
    const float2x2 rot = float2x2(0.80, 0.60, -0.60, 0.80);
    float amp = 1.0, sum = 0.0, norm = 0.0;
    for (int i = 0; i < 4; ++i) {
        sum  += amp * perlin2d(p);
        norm += amp;
        amp  *= 0.5;
        p     = rot * p * 2.0;       // rotate + frequency-double each octave
    }
    return sum / norm;               // ~[-1, 1]
}

// ── Skein.3 — SkeinState GPU contract (matches SkeinState.swift byte-for-byte) ─────
//
// The marks-on-top overlay FRAGMENT consumes this at fragment buffer(6) via the strands-on-top
// slot-6 binding (RenderPipeline+MVWarpScene, Skein.ENGINE.1.2). It carries the audio-modulated
// painter clock (painterTau), the per-track seed phase offsets, the dominant-stem line colour,
// and a ring of onset-spawned splatter bursts — each frozen at its stem's colour. This RETIRES
// the Skein.2 debug drivers: the deterministic flick schedule is replaced by the onset-burst
// ring (a burst fires on a real per-stem onset, in that stem's colour), and the debug viscosity
// sweep is replaced by each burst's centroid-driven `visc` + the line's
// `lineVisc`. Marks composite OPAQUE (paired bestCover/bestColor → topmost colour, never mud).

constant int kSkeinMaxBursts = 48;        // MUST equal SkeinState.maxBursts + the bursts[] size below
constant int kSkeinMaxBreaks = 16;        // MUST equal SkeinState.maxColorBreaks + the breaks[] size below
constant float kSkeinBakeWindow = 0.55;   // painter-clock units a burst is redrawn before it freezes

struct SkeinBurstGPU {        // 12 floats = 48 bytes (matches Swift SkeinBurstGPU)
    float posX; float posY;            // uv flick point
    float dirX; float dirY;            // throw direction (aspect-corrected, frozen)
    float spawnTau;                    // painter clock at spawn
    float size;                        // base droplet size (attackRatio)
    float visc;                        // viscosity [0,1] (1 − centroid)
    float colR; float colG; float colB;  // frozen stem colour
    float sharpness;                   // flick sharpness [0,1]; < 0 ⇒ pour DRIP (Skein.5.4 marker —
                                       // the fragment draws drip morphology, skips the flick layers)
    float hashSeed;                    // per-burst droplet-placement seed
};

// Skein.4.1 — one line-colour + new-pour breakpoint (matches Swift SkeinBreakGPU byte-for-byte).
struct SkeinBreakGPU {        // 6 floats = 24 bytes
    float tauStart;                    // painter clock at the dominant-stem switch (pour valid from here)
    float colR; float colG; float colB;  // frozen line colour (LINEAR — sRGB-decoded, like the bursts)
    float offX; float offY;            // bounded new-pour position offset (the "new container" jump)
};

struct SkeinUniforms {        // 64-byte header + 48 × 48-byte bursts + 16 × 24-byte breaks (matches SkeinState)
    float painterTau;
    float painterTauStep;
    float seedPhaseX;
    float seedPhaseY;
    float lineColR; float lineColG; float lineColB;
    float lineFlow;
    float lineVisc;
    float jitter;
    uint  burstCount;
    uint  seed;
    uint  breakCount;                  // Skein.4.1 active colour breakpoints (was pad0)
    float locusEnable;                 // Skein.5 painter-locus build flag, 0/1 (was pad1)
    float pad2; float pad3;
    SkeinBurstGPU bursts[48];          // == kSkeinMaxBursts
    SkeinBreakGPU breaks[16];          // == kSkeinMaxBreaks (Skein.4.1)
    float4 ground;                     // Skein.5.3b: the palette's canvas ground, LINEAR (rgb; w unused).
                                       // Offset 2752 = 64 + 48·48 + 16·24, 16-byte aligned — the second
                                       // additive tail. The comp paint-mask compares the auto-decoded
                                       // (linear) canvas sample against it; per-track in library mode.
};

// Skein.4.1 — the line state in effect at a given painter-clock value: frozen colour + new-pour offset
// + the breakpoint's start (so the tail loop can tell whether two endpoints belong to the SAME pour).
struct SkeinLineLookup { float3 col; float2 off; float start; };

// Look up the line colour + offset in effect when painter-clock value `t` was laid: the latest
// breakpoint with tauStart ≤ t. The ring is ASCENDING in tauStart (SkeinState appends in monotonic
// painter-clock order; eviction removes the oldest, preserving order), so we early-out at the first
// tauStart > t — typically 1–3 iterations. For `t` older than every retained breakpoint we fall back
// to breaks[0] (only the already-baked tail can be that old, never the live tail — see
// SkeinState.maxColorBreaks). This is the per-burst colour freeze applied to the continuous line: a
// tail segment keeps its lay-time colour, and a switch carries a position jump so the new pour is
// spatially displaced (Skein.4.1 option 2). `start` lets the tail loop tell two pours apart.
static inline SkeinLineLookup skeinLineLookupAt(float t, constant SkeinUniforms& st) {
    SkeinLineLookup r;
    int n = min(int(st.breakCount), kSkeinMaxBreaks);
    if (n <= 0) {                                              // no ring yet → the current pour, no jump
        r.col = float3(st.lineColR, st.lineColG, st.lineColB);
        r.off = float2(0.0, 0.0);
        r.start = -1e30;
        return r;
    }
    SkeinBreakGPU sel = st.breaks[0];                          // oldest retained (the fallback for t < all)
    for (int i = 1; i < n; ++i) {
        SkeinBreakGPU bk = st.breaks[i];
        if (bk.tauStart <= t) { sel = bk; } else { break; }    // ascending → first miss ends the search
    }
    r.col = float3(sel.colR, sel.colG, sel.colB);
    r.off = float2(sel.offX, sel.offY);
    r.start = sel.tauStart;
    return r;
}

// ── Background / canvas fragment ──────────────────────────────────────────────────
//
// Renders the flat cream/toned GROUND only. Skein.ENGINE.1.1 (D-143) moved the test
// stamp OUT of this fragment and into the marks-on-top overlay (skein_geometry_*, below):
//   • LIVE, the marks-on-top path SKIPS this fragment (Pass 0 is not run for presets with
//     a scene-geometry overlay); the held ground comes from the canvas CLEAR (same value,
//     kSkeinCanvasCream) and the pour line is drawn on top by the overlay every frame.
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

// -- Marks-on-top overlay (Skein.1) -------------------------------------------------
//
// Draws the leading END of the pour -- a short TRAILING TAIL of the painter's last K positions --
// as a fullscreen-triangle overlay composited NORMAL-ALPHA on top of the held canvas (the D-138
// marks-on-top mechanism, reachable per-preset since D-143; Dragon Bloom resolves
// `dragon_bloom_strand_*`, Skein resolves these). The painter position is the closed-form
// skeinPainterPos(features.time); the tail is the last K frames recomputed in-shader (no buffer).
//
// TRAILING-OFF / build-up (Matt 2026-06-05 -- "less paint at the end of the pour, a trailing-off
// effect"; the VisComp 2014 line layer -- width tapers toward the endpoint as the stream thins,
// SKEIN_DESIGN 1.0): the tail TAPERS from faint + thin at the live tip (newest paint) to full +
// wide at its base (~0.4 s back). Redrawn every frame onto the HELD canvas, each point ages
// through the tail and is composited at INCREASING opacity (normal-alpha only ever brightens),
// so paint FADES IN over the tail window -- the leading edge trails off, older paint is solid.
// Once a point ages past the tail it is no longer drawn -> frozen, carried forward losslessly by
// the identity warp + no decay. The union over the session is the accumulating, continuous,
// looping pour LINE on cream with a trailing-off live edge. (A single per-frame capsule cannot
// show this -- the next frame fills its tip to full; the multi-frame tail is what persists.)
// Draw params (3 verts / 1 instance / .triangle) from Skein.json `marks`.
//
// SKEIN.2 adds, baked into the SAME held canvas alongside the pour line: velocity-biased droplet
// BURSTS (ragged-edge discs, exp/poly satellite size+density falloff with distance from the flick),
// thin FILAMENT tendrils (line→droplet), and a VISCOSITY axis shaping width / satellite count+spread /
// edge raggedness. White-on-cream ONLY -- palette is Skein.3; wetness/sheen is ENGINE.2/Skein.4.

struct SkeinGeoVertexOut {
    float4 position [[position]];
    float2 uv;
    float  aspect;   // viewport aspect, for isotropic mark width
};

// Path A still holds at the VERTEX: drawSceneGeometryOverlay binds `features` at vertex slot 0, so
// the vertex reads aspect from it. Skein.3 moves the painter clock + all audio routing to the
// FRAGMENT, which reads SkeinUniforms at buffer(6) (the ENGINE.1.2 strands-on-top slot-6 binding).
vertex SkeinGeoVertexOut skein_geometry_vertex(
    uint vid [[vertex_id]],
    constant FeatureVector& f [[buffer(0)]]   // bound by drawSceneGeometryOverlay (vertex slot 0)
) {
    // Fullscreen triangle in clip space: (-1,-1), (-1,3), (3,-1) -- covers the viewport.
    float2 p = float2((vid == 2) ? 3.0 : -1.0, (vid == 1) ? 3.0 : -1.0);
    SkeinGeoVertexOut out;
    out.position = float4(p, 0.0, 1.0);
    out.uv = p * 0.5 + 0.5;   // 0..1
    out.aspect = (f.aspect_ratio > 0.01) ? f.aspect_ratio : 1.0;
    return out;
}

// Trailing-tail length in frames (~0.67 s at 60 fps): the leading run that tapers + builds up.
constant int kSkeinTailFrames = 40;

fragment float4 skein_geometry_fragment(
    SkeinGeoVertexOut in [[stage_in]],
    constant SkeinUniforms& st [[buffer(6)]]   // Skein.ENGINE.1.2 — painter state + onset-burst ring
) {
    float a = in.aspect;
    float2 q = float2(in.uv.x * a, in.uv.y);          // aspect-corrected fragment position
    // ~1 screen pixel in aspect-corrected q-units, ISOTROPIC (fwidth(q.x) == fwidth(q.y) == 1/height).
    // Used for the droplet/filament edge AA + the minimum-size floor — see the droplet block (Matt M7).
    float px = max(fwidth(q.x), fwidth(q.y));

    // The painter clock + per-track seed phases come from SkeinState (buffer(6)). painterTau is the
    // audio-modulated clock (faster on busy passages — the §M7 pacing note); dtau is this frame's
    // step, used to recompute the trailing tail (the Skein.2 mechanism, now in painter-clock space).
    float tau  = st.painterTau;
    float dtau = max(st.painterTauStep, 1.0 / 240.0);  // guard a zero step (would collapse the tail)
    float phx  = st.seedPhaseX, phy = st.seedPhaseY;

    // OPAQUE compositing (the §colour-mud audit): track the TOPMOST mark's colour by coverage, never
    // a blend of two stem colours. Each contribution updates (bestCover, bestCol) together, so an
    // overlap takes whichever mark covers this fragment most — occlude, never average to mud.
    float  bestCover = 0.0;
    float3 bestCol   = float3(1.0);   // unpainted: white (the held cream shows through at cover 0)

    // ── Layer A: the pour LINE — per-segment FROZEN colour + per-switch NEW pour (Skein.4.1) ──
    // The colour is the DISCRETE dominant-stem colour, but FROZEN PER SEGMENT at lay-time via the
    // SkeinState colour-breakpoint ring (skeinLineLookupAt): a segment laid before a dominant switch
    // keeps the OLD colour, one laid after gets the new — the line no longer recolours along its length
    // (Matt M7 2026-06-09: "the colour changes in the middle of a stroke"). AND a colour switch starts a
    // genuinely NEW pour (Matt's option 2): each breakpoint carries a small bounded position OFFSET —
    // "the painter grabs a new paint container" — so the new line is spatially displaced from the old,
    // with a clean GAP at the switch. The segment that would BRIDGE two different pours (different
    // start) is simply NOT drawn → the gap.
    //
    // Skein.5.1 (Matt M7 2026-06-09: "white disturbs the colour palette"): the ring starts EMPTY —
    // until the first COLOURED pour commits there is NO line at all (the white-baseline era is
    // retired; the first commit retro-colours the pre-commit tail via tauStart = 0). At silence
    // nothing commits and the painter clock pauses → the painter rests, the canvas stays clean.
    //
    // Coverage is UNCHANGED from Skein.4 M7-round-3/4 — ONE union SDF, ONE per-frame radius (no
    // per-segment radius → no scalloping → no rings; the sheen finds no internal luminance ridges). With
    // a single radius, `max over per-capsule coverage` ≡ `1 − smoothstep(min segDist − r)`, so tracking
    // the nearest drawn segment to pick its frozen colour does NOT change coverage. Width is per-FRAME
    // (viscosity/flow widen it; overall tip→tail speed THINS it to a filament on fast sweeps), never
    // per-segment (§18.8: an overall-speed widening fattens the loop and buries the droplets).
    float  lineVisc  = clamp(st.lineVisc, 0.0, 1.0);
    float  lineWiden = mix(1.0, 1.5, lineVisc) + 0.5 * clamp(st.lineFlow, 0.0, 1.0);
    if (int(st.breakCount) > 0) {   // Skein.5.1: no committed pour yet ⇒ no line (never white)
        // Per-frame radius (never per-segment). Speed estimated from the natural (un-offset) path.
        float2 tip0  = skeinPainterPos(tau, phx, phy);
        float2 oldP0 = skeinPainterPos(tau - float(kSkeinTailFrames) * dtau, phx, phy);
        float  oSpeed = length(float2((tip0.x - oldP0.x) * a, tip0.y - oldP0.y))
                      / max(float(kSkeinTailFrames) * dtau, 1e-4);
        float  r = kSkeinLineRadius * lineWiden * mix(1.05, 0.70, smoothstep(0.05, 0.35, oSpeed));

        // Walk the tail newest→oldest, one breakpoint lookup per point. Draw segment k only when both
        // endpoints belong to the SAME pour (equal breakpoint `start`); a segment straddling a switch is
        // the JUMP and is skipped → the gap. Each drawn point is displaced by its pour's offset, and the
        // segment is coloured by its pour's frozen colour.
        SkeinLineLookup pr = skeinLineLookupAt(tau, st);
        float2 prQ = float2((tip0.x + pr.off.x) * a, tip0.y + pr.off.y);   // k = 0 (newest)
        float  lineSDF = 1e9;
        float3 lineCol = pr.col;
        for (int k = 1; k <= kSkeinTailFrames; ++k) {
            float  ctau = tau - float(k) * dtau;
            SkeinLineLookup cu = skeinLineLookupAt(ctau, st);
            float2 cb  = skeinPainterPos(ctau, phx, phy);
            float2 cuQ = float2((cb.x + cu.off.x) * a, cb.y + cu.off.y);
            if (cu.start == pr.start) {                              // same pour → draw (no bridge)
                float d = skeinSegDist(q, cuQ, prQ) - r;
                if (d < lineSDF) { lineSDF = d; lineCol = cu.col; }   // nearest drawn segment's frozen colour
            }
            pr = cu; prQ = cuQ;
        }
        float cov = 1.0 - smoothstep(-px, px, lineSDF);   // ONE smooth tube; uniformly solid interior
        if (cov > bestCover) { bestCover = cov; bestCol = lineCol; }
    }

    // ── Layers B + C: onset-burst RING — Pollock splatter (Skein.5.4 morphology rebuild) ──
    // Each burst is a real per-stem ONSET (SkeinState detection on *_energy_dev), frozen at the
    // painter position in that stem's colour. Emission timing is UNCHANGED (Matt 2026-06-10:
    // keep the spray; fix what the paint LOOKS like). Morphology rebuilt against the reference
    // set (the round-1 "only dots / confetti" rejection):
    //   • PRIMARY SPLAT — an irregular LOBED blot at the flick point (the paint mass that hit;
    //     the large ragged blots in 03_micro_satellite_spatter + 03_micro_filament_threads).
    //   • FLUNG STREAKS — long thin threads shooting along the throw, slightly curved, each
    //     ending in a terminal droplet (the white flung threads in both micro refs — the
    //     signature Pollock element the old 1-2 px tendrils never delivered).
    //   • SATELLITES — the dense→sparse halo, now with a POWER-LAW size spread (big blots →
    //     pinprick dust, the refs' ~20:1 range; the old ~4:1 band read as confetti) and
    //     RADIAL ELONGATION (teardrops pointing away from the impact — splash physics).
    // burst.size now carries attack × THROW MAGNITUDE (how hard the onset hit) — a heavy hit
    // flings a bigger blot, longer streaks, wider satellites. Bake-and-hold unchanged.
    int nB = min(int(st.burstCount), kSkeinMaxBursts);
    for (int b = 0; b < nB; ++b) {
        SkeinBurstGPU burst = st.bursts[b];
        float age = tau - burst.spawnTau;
        if (age < 0.0 || age > kSkeinBakeWindow) { continue; }
        float ageFrac = age / kSkeinBakeWindow;
        float op = mix(0.05, 1.0, smoothstep(0.0, 0.8, ageFrac));

        float2 fpA  = float2(burst.posX * a, burst.posY);                     // landing point (aspect-corrected)
        float2 dir  = float2(burst.dirX, burst.dirY);                         // throw axis (frozen)
        float  base = atan2(dir.y, dir.x);
        float  visc = clamp(burst.visc, 0.0, 1.0);
        float  mag  = clamp(burst.size, 0.3, 2.0);                            // attack × throw magnitude (CPU)
        float  mag01 = (mag - 0.3) / 1.7;                                     // 0 = soft flick, 1 = heavy hit
        float3 col  = float3(burst.colR, burst.colG, burst.colB);

        // ── DRIP (sharpness < 0 — Skein.5.4): the POUR's by-product, a different technique
        // from the flick (Matt's distinction). One round heavy drop shed beside the line —
        // ragged-edged, occasionally with a faint close satellite — in the pour's colour.
        // No streaks, no spray cone: paint that FELL, not paint that was thrown.
        if (burst.sharpness < 0.0) {
            float dripR = mix(0.0030, 0.0085, clamp((mag - 0.5) / 1.1, 0.0, 1.0))
                        * mix(0.85, 1.25, visc);
            if (length(q - fpA) < dripR * 3.0 + px * 5.0) {
                float ragged = 1.0 + 0.30 * skein_fbm2(q * 65.0 + float2(burst.hashSeed * 4.9, 2.7));
                float drr = max(dripR * ragged, px * 1.3);
                float cov = (1.0 - smoothstep(drr - px * 1.6, drr + px * 1.6, length(q - fpA))) * op;
                if (cov > bestCover) { bestCover = cov; bestCol = col; }
                // One faint micro-satellite (the secondary droplet a heavy drop kicks up).
                float4 hd = hash_f01_4x(float4(burst.hashSeed, 77.0, 1.0, 0.0));
                if (hd.x > 0.45) {
                    float2 sp = fpA + float2(cos(hd.y * 6.2832), sin(hd.y * 6.2832)) * dripR * mix(1.8, 2.6, hd.z);
                    float sr = max(dripR * mix(0.18, 0.32, hd.w), px * 1.1);
                    float scov = (1.0 - smoothstep(sr - px * 1.4, sr + px * 1.4, length(q - sp))) * op;
                    if (scov > bestCover) { bestCover = scov; bestCol = col; }
                }
            }
            continue;
        }
        float  sharp = clamp(burst.sharpness, 0.0, 1.0);

        // Viscosity → character (SKEIN_DESIGN §1.2): thin/bright = many fine far satellites,
        // long thin streaks; thick/dark = fewer, bigger, closer drops, stubbier streaks.
        int   nDrop    = int(mix(46.0, 13.0, visc));
        float spread   = mix(0.170, 0.075, visc) * mix(0.6, 1.6, mag01);      // heavy hits fling farther
        float dropBig  = mix(0.0065, 0.0135, visc) * mix(0.6, 1.5, mag01);
        float edgeAmp  = mix(0.40, 0.26, visc);
        float aaScale  = mix(2.6, 1.4, visc);
        float coneNear = mix(3.14159, 1.20, sharp);                           // soft = full halo, sharp = narrower
        float primR    = mix(0.005, 0.016, mag01) * mix(0.8, 1.3, visc);      // primary blot radius
        float streakLen = mix(0.035, 0.20, mag01) * mix(1.2, 0.6, visc);      // thin paint throws long
        int   nStreak  = 1 + int(mag01 > 0.35) + int(mag01 > 0.75);           // 1–3 flung threads

        // SCISSOR (§6 — cost ∝ this frame's marks): the bound covers the farthest satellite AND
        // the longest streak tip + raggedness.
        float bound = max(spread + dropBig * 2.5, streakLen + 0.015) + 0.01;
        if (length(q - fpA) > bound) { continue; }

        // ── B1: PRIMARY SPLAT — a 3-lobe irregular blot (union-min SDF), heavy ragged edge.
        // Soft attacks (sharp→0) pull the lobes together into one rounder, heavier drop — the
        // "drop from above"; sharp flicks scatter the lobes along the throw.
        {
            float lobeScatter = primR * mix(0.45, 1.1, sharp);
            float blotSDF = 1e9;
            for (int l = 0; l < 3; ++l) {
                float4 hl = hash_f01_4x(float4(burst.hashSeed, 300.0 + float(l), 1.0, 0.0));
                float lAng = base + (hl.x * 2.0 - 1.0) * 2.2;
                float lDist = (l == 0) ? 0.0 : lobeScatter * mix(0.4, 1.0, hl.y);
                float2 lPos = fpA + float2(cos(lAng), sin(lAng)) * lDist;
                float lR = primR * ((l == 0) ? 1.0 : mix(0.35, 0.65, hl.z));
                blotSDF = min(blotSDF, length(q - lPos) - lR);
            }
            float ragged = edgeAmp * 1.2 * primR
                         * skein_fbm2(q * 55.0 + float2(burst.hashSeed * 3.7, 9.1));
            float cov = (1.0 - smoothstep(-px, px * aaScale, blotSDF + ragged)) * op;
            if (cov > bestCover) { bestCover = cov; bestCol = col; }
        }

        // ── B2: FLUNG STREAKS — long thin slightly-curved threads along the throw, tapering,
        // each ending in a terminal droplet (refs: the white threads crossing both micro images).
        // Angular spread tight on sharp hits, looser on soft ones; never a radial starburst
        // (1–3 threads in the throw's half-plane, not spokes).
        for (int sIdx = 0; sIdx < nStreak; ++sIdx) {
            float4 hsk = hash_f01_4x(float4(burst.hashSeed, 200.0 + float(sIdx), 1.0, 0.0));
            float sAng = base + (hsk.x * 2.0 - 1.0) * mix(0.65, 0.20, sharp);
            float sLen = streakLen * mix(0.55, 1.0, hsk.y);
            float2 sDir = float2(cos(sAng), sin(sAng));
            float2 sPerp = float2(-sDir.y, sDir.x);
            float2 sMid = fpA + sDir * (sLen * 0.5) + sPerp * sLen * 0.14 * (hsk.z * 2.0 - 1.0);
            float2 sTip = fpA + sDir * sLen;
            // Distance to the two-segment polyline + a linear width taper base→tip.
            float d1 = skeinSegDist(q, fpA, sMid);
            float d2 = skeinSegDist(q, sMid, sTip);
            float sd = min(d1, d2);
            if (sd < px * 6.0 + 0.004) {
                float tAlong = clamp(dot(q - fpA, sDir) / max(sLen, 1e-5), 0.0, 1.0);
                float wBase = mix(0.0026, 0.0014, visc) * mix(0.8, 1.4, mag01);
                float sw = mix(wBase, wBase * 0.30, tAlong)
                         * (1.0 + 0.45 * skein_fbm2(q * 120.0 + float2(burst.hashSeed * 5.1, float(sIdx) * 7.7)));
                float swr = max(sw, px * 0.9);
                float cov = (1.0 - smoothstep(swr - px * 1.5, swr + px * 1.5, sd)) * op * 0.95;
                if (cov > bestCover) { bestCover = cov; bestCol = col; }
            }
            // Terminal droplet — the pearl at the thread's end (string-of-pearls read).
            float tdR = max(mix(0.0022, 0.0052, mag01) * mix(0.7, 1.3, hsk.w), px * 1.2);
            float tdc = length(q - sTip);
            if (tdc < tdR * 2.0 + px * 3.0) {
                float ragged = 1.0 + edgeAmp * skein_fbm2(q * 80.0 + float2(burst.hashSeed * 6.3, float(sIdx) * 4.4));
                float cov = (1.0 - smoothstep(tdR * ragged - px * 1.5, tdR * ragged + px * 1.5, tdc)) * op;
                if (cov > bestCover) { bestCover = cov; bestCol = col; }
            }
        }

        // ── B3: SATELLITES — the dense→sparse halo with a POWER-LAW size spread (a few big
        // blots, many mid drops, a dust tail — the confetti becomes the tail of a real
        // distribution) and RADIAL ELONGATION (far drops stretch into teardrops pointing away
        // from the impact). Isotropic px AA + round floor (Matt M7 2026-06-05) retained.
        for (int n = 0; n < nDrop; ++n) {
            float4 hs      = hash_f01_4x(float4(burst.hashSeed, float(n), 1.0, 0.0));
            float distFrac = pow(hs.x, 1.5);
            float dist     = spread * distFrac;
            float coneHalf = mix(coneNear, 0.42, distFrac);
            float ang      = base + coneHalf * (hs.y * 2.0 - 1.0);
            float2 rd      = float2(cos(ang), sin(ang));
            float2 dpos    = fpA + rd * dist;
            // Power-law size: pow(hs.z, 2.2) spans big→pinprick (~20:1 before the px floor).
            float  dr      = dropBig * mix(1.25, 0.30, distFrac) * mix(0.10, 1.35, pow(hs.z, 2.2));

            float2 pd = q - dpos;
            float cheap = length(pd);
            if (cheap < dr * 3.2 + px * 4.5) {
                // Radial elongation: stretch the distance metric ALONG the flight direction —
                // far, fast drops smear into teardrops; near drops stay round.
                float stretch = 1.0 + 1.8 * distFrac * mix(0.3, 1.0, mag01);
                float along = dot(pd, rd) / stretch;
                float perp  = dot(pd, float2(-rd.y, rd.x));
                float dc    = length(float2(along, perp));
                float ragged = 1.0 + edgeAmp * skein_fbm2(q * 70.0 + float2(burst.hashSeed * 7.3, float(n) * 3.1));
                float drr = max(dr * max(ragged, 0.20), px * 1.2);
                float aa  = px * aaScale;
                float cov = (1.0 - smoothstep(drr - aa, drr + aa, dc)) * op;
                if (cov > bestCover) { bestCover = cov; bestCol = col; }
            }
        }
    }

    // OPAQUE alpha-over: the overlay blend (SRC_ALPHA / ONE_MINUS_SRC_ALPHA) composites the TOPMOST
    // mark's colour over the held canvas at bestCover — layers occlude, never average to mud.
    return float4(bestCol, bestCover);
}

// ── Skein.ENGINE.2: the wetness channel (canvas-hold warp/hold fragment) ────────────
//
// Skein owns its warp/hold fragment via the PresetLoader `<prefix>_warp_fragment` override
// (the same per-prefix mechanism Fata Morgana's `fata_warp_fragment` uses — PresetLoader.swift
// makeWarpPipelines). The shared `mvWarp_fragment` is left BYTE-IDENTICAL for every other preset
// (this is the ENGINE.2 byte-identical guarantee — no shared GPU code is touched).
//
// RGB is the LOSSLESS PERMANENT PAINT RECORD (the ENGINE.1 invariant): under identity warp
// (mvWarpPerVertex returns uv → in.warped_uv == this texel) the previous canvas is sampled at
// exactly this fragment's texel and returned BYTE-FOR-BYTE — no resampling, no decay, no drift.
// This is the SAME RGB result the shared `mvWarp_fragment` produces for Skein (chromaticMix=0,
// decay=1.0 collapse it to the identity copy), so the canvas-hold RGB regression is unchanged.
//
// ALPHA carries the transient WETNESS signal (SKEIN_DESIGN §5.5: drying is a READ-TIME effect on
// a SEPARATE channel, never a destructive multiply on the RGB record). The overlay normal-alpha
// blend (skein_geometry_fragment → float4(bestCol, bestCover); blend SRC_ALPHA/ONE_MINUS_SRC_ALPHA
// on both colour AND alpha) STAMPS coverage into A where paint lands this frame. Here the hold
// DECAYS A by `wetnessDecay` each frame (= exp(-rate·dt·stemMix) from SkeinState — pauses at
// silence). Net per texel: A jumps to ~1 when (re)painted, then dries toward 0; Skein.4's
// `skein_comp_fragment` reads A as the wet/dry sheen mask. RGB is untouched by the A decay.
fragment float4 skein_warp_fragment(
    WarpVertexOut      in           [[stage_in]],
    texture2d<float>   prevTex      [[texture(0)]],
    constant float&    chromaticMix [[buffer(0)]],   // unused (0 for Skein) — kept for binding parity
    constant float&    wetnessDecay [[buffer(1)]]    // Skein.ENGINE.2 — ALPHA decay multiplier
) {
    // Identity hold: sample the previous canvas at the un-displaced UV → lossless RGB copy.
    float4 prev = prevTex.sample(warpSampler, in.warped_uv);
    // RGB held byte-identical (the lossless permanent paint record); ALPHA dries by wetnessDecay
    // (1.0 at silence ⇒ held; < 1.0 while music plays ⇒ wetness decays toward 0).
    return float4(prev.rgb, prev.a * wetnessDecay);
}

// ── Skein.4: the wet/dry SHEEN (display/lighting comp fragment) ─────────────────────
//
// Skein owns its blit/comp fragment via the PresetLoader `<prefix>_comp_fragment` override
// (the same per-prefix mechanism Fata Morgana's `fata_comp_fragment` uses). The shared
// `mvWarp_blit_fragment` is left BYTE-IDENTICAL for every other preset. This is the READ side
// of the ENGINE.2 wetness channel: it reads canvas RGB + wetness A from the (already-bound)
// compose texture and renders the wet-now / dry-past legibility device (SKEIN_DESIGN §1.4 / §5.2
// step 4): wet paint catches a specular highlight, dry paint is matte + slightly desaturated, so
// the eye tracks the musical NOW (the live painter edge glistens) while the accumulated past
// reads matte.
//
// GROUNDING (CLAUDE.md grounding rule, FA #64/#73 — desk-researched, not first-principles):
//   • Normal-from-canvas: a flat 2D canvas has no geometric normal, so derive one from the
//     canvas LUMINANCE GRADIENT (central-difference / Sobel bump) — the standard heightfield→
//     normal technique (LearnOpenGL "Normal Mapping"; Sobel-terrain normal generation). Paint
//     ridges/edges tilt the normal → they catch the light; flat bare ground stays normal-up.
//   • Specular: the GGX / Trowbridge-Reitz microfacet NDF (Walter et al. 2007), the §2-Lighting
//     "only specular event is WET paint catching light". Tonemapped (x/(x+knee)) so the broad
//     gloss is visible AND the edge glints stay bounded; roughness drops with wetness (wet =
//     glossier). The specular is an ADDITIVE highlight on top of the Skein.3 stem colour — never
//     a recolour, so the stem palette reads through (§Skein.4 contract).
//
// sRGB (FA #71): the compose texture is `.bgra8Unorm_srgb`, so `warpTex.sample(...).rgb` already
// sRGB-DECODES to LINEAR — the lighting is done in linear and the `.bgra8Unorm_srgb` DRAWABLE
// re-encodes on store. We must NOT manually decode (that double-decode is the FA #71 trap; Skein's
// situation is the inverse of Fata Morgana, whose feedback is linear `.bgra8Unorm`). The wetness
// in A is linear (sRGB never touches alpha). Gated by construction: only Skein resolves
// `skein_comp_fragment`; every other mv_warp preset keeps the untouched shared blit.

// Linear-space relative luminance (Rec.709) — the canvas is already linear at this point.
static inline float skeinLuma(float3 c) { return dot(c, float3(0.2126, 0.7152, 0.0722)); }

// Tonemapped GGX/Trowbridge-Reitz NDF (Walter et al. 2007): the highlight intensity for a given
// half-angle cosine + roughness, compressed by `knee` so the unbounded peak becomes a bounded
// highlight while the broad gloss stays visible. Used for both the broad wet gloss and the sparkle.
static inline float skeinGGX(float NdotH, float rough, float knee) {
    float a = rough * rough, a2 = a * a;
    float d = NdotH * NdotH * (a2 - 1.0) + 1.0;
    float g = a2 / (M_PI_F * d * d);
    return g / (g + knee);
}

// Sheen tuning (Skein.4). Conservative + tunable; verified through the live SKEIN_VISUAL harness.
// M7-round-3 (Matt 2026-06-09: "the glistening just makes the paint look SPECKLED — it does not convey
// wet"). The micro-normal sparkle is RETIRED — it read as grain, not wet. The real wet cue is the BODY
// treatment + a clean glossy reflection: WET paint is DARKER + more SATURATED (water-soaked depth, the
// classic "wet look"); DRY paint is LIGHTER + matte. A smooth glossy specular highlight (a coherent
// catch-light, never speckle) adds the reflection. Both hard-gated by wetness × paint (wet-now / dry-past).
constant float3 kSkeinLightDir   = float3(0.2357, 0.3300, 0.9146);  // normalize(0.25,0.35,0.97) — flat overhead, slight tilt
constant float3 kSkeinSpecColor  = float3(1.00, 0.97, 0.92);        // warm-white glossy catch-light
constant float  kSkeinNormalAmp  = 2.2;    // canvas luminance-gradient → normal tilt (edge response)
constant float  kSkeinSpecKnee   = 2.4;    // GGX tonemap knee (compresses the peak; keeps a coherent catch-light)
constant float2 kSkeinWetGate    = float2(0.05, 0.95);  // smoothstep(lo,hi) on wetness → near-LINEAR wet→dry ramp (a
                                                       // steep gate amplified per-pass age differences into rings)
constant float  kSkeinWeaveAmp   = 0.015;  // canvas-weave grain beneath the paint (very subtle)
// Wet body = DARKER + more saturated (water-soaked). Dry body = LIGHTER + desaturated (matte). The
// DARKEN must DOMINATE — Matt M7-round-3: a broad glossy highlight BRIGHTENED the fresh paint enough
// that it read "lighter on application, darker as it dries", inverting the wet read. So the body
// darken is strong and the gloss is a TINY TIGHT glint (a small wet shine, not a broad brightening).
constant float  kSkeinWetDarken   = 0.74;  // wet body brightness × (clearly DARKER = wet) — must dominate the gloss
constant float  kSkeinWetSat      = 1.28;  // wet body saturation × (richer = wet)
constant float  kSkeinDryLighten  = 1.08;  // dry body brightness × (clearly lighter = dry/matte)
constant float  kSkeinDryDesat    = 0.18;  // dry body desaturation toward luma (matte chalk)
constant float  kSkeinRoughGloss  = 0.12;  // TIGHT glint (small wet shine only — does NOT broadly brighten the body)
constant float  kSkeinGainGloss   = 0.40;  // glossy catch-light strength (kept small so the DARKEN reads as "wet")

fragment float4 skein_comp_fragment(
    VertexOut          in      [[stage_in]],
    texture2d<float>   warpTex [[texture(0)]],
    constant float4&   post    [[buffer(0)]],  // unused for Skein (identity comp) — kept for binding parity
    constant SkeinUniforms& st [[buffer(1)]]   // Skein.5 — painter state for the DISPLAY-ONLY locus
) {
    float2 uv = in.uv;
    float4 c  = warpTex.sample(warpSampler, uv);   // rgb = LINEAR canvas paint; a = wetness [0,1]
    float3 col = c.rgb;

    // BLURRED wetness (Skein.4 M7-round-4 — Matt: "rings appear ~1 s after the line and then fade").
    // When the painter LOOPS it lays overlapping passes at progressively different AGES; each pass's
    // wetness decays separately, and the sheen renders those age differences as CONCENTRIC RINGS — but
    // only ~1 s after laying, once the wetness has decayed into the steep part of the specWet gate
    // (where tiny age differences become visible darkness steps), then they fade as it dries fully. A
    // small spatial blur of the wetness blends the per-pass age bands into one smooth wet region, so
    // there are no fine steps for the sheen to amplify. The large-scale wet→dry boundary is preserved
    // (the blur radius ≈ the loop-pass spacing, small vs the wet region). 9-tap Gaussian at ±7 texels.
    float2 t1 = (1.0 / float2(warpTex.get_width(), warpTex.get_height())) * 6.0;   // inner ring ±6 texels
    float2 t2 = t1 * 2.0;                                                           // outer ring ±12 texels
    float  wet = 0.20 * c.a
        + 0.09 * (warpTex.sample(warpSampler, uv + float2(t1.x, 0.0)).a + warpTex.sample(warpSampler, uv - float2(t1.x, 0.0)).a
                + warpTex.sample(warpSampler, uv + float2(0.0, t1.y)).a + warpTex.sample(warpSampler, uv - float2(0.0, t1.y)).a)
        + 0.05 * (warpTex.sample(warpSampler, uv + t1).a + warpTex.sample(warpSampler, uv - t1).a
                + warpTex.sample(warpSampler, uv + float2(t1.x, -t1.y)).a + warpTex.sample(warpSampler, uv + float2(-t1.x, t1.y)).a)
        + 0.06 * (warpTex.sample(warpSampler, uv + float2(t2.x, 0.0)).a + warpTex.sample(warpSampler, uv - float2(t2.x, 0.0)).a
                + warpTex.sample(warpSampler, uv + float2(0.0, t2.y)).a + warpTex.sample(warpSampler, uv - float2(0.0, t2.y)).a);
    wet = clamp(wet, 0.0, 1.0);   // 13-tap, two-ring Gaussian (≈ ±10 texel radius) — blends the loop-pass age bands

    // Paint-present mask: the bare ground reads MATTE — the sheen only touches PAINT. (Bare
    // ground carries wetness in A too, since the clear seeds A=1; the mask is what keeps the
    // bare ground from glistening — wet paint, not a wet floor.) Skein.5.3b: the ground is
    // per-palette (st.ground, LINEAR — light cream/linen or dark indigo/maroon), no longer
    // the fixed cream constant.
    float paint = smoothstep(0.015, 0.080, distance(col, st.ground.rgb));

    // Wetness → gloss gate (hard wet/dry split): the specular + micro-relief fire only on WET
    // (recent) paint, gated to ~0 on the dried past — the wet-now / dry-past legibility read.
    float specWet = smoothstep(kSkeinWetGate.x, kSkeinWetGate.y, wet);

    // Normal from the canvas luminance gradient (central difference) — the 2D analogue of a surface
    // normal. Paint ridges/edges tilt N → they catch the overhead light; flat areas keep N ≈ +z.
    float2 texel = 1.0 / float2(warpTex.get_width(), warpTex.get_height());
    float lR = skeinLuma(warpTex.sample(warpSampler, uv + float2(texel.x, 0.0)).rgb);
    float lL = skeinLuma(warpTex.sample(warpSampler, uv - float2(texel.x, 0.0)).rgb);
    float lU = skeinLuma(warpTex.sample(warpSampler, uv + float2(0.0, texel.y)).rgb);
    float lD = skeinLuma(warpTex.sample(warpSampler, uv - float2(0.0, texel.y)).rgb);
    float3 N = normalize(float3(-(lR - lL) * kSkeinNormalAmp, -(lU - lD) * kSkeinNormalAmp, 1.0));

    // Wet / dry BODY treatment (the primary "wet" cue — M7-round-3). WET paint is DARKER + more
    // SATURATED (water-soaked, glossy depth); DRY paint is LIGHTER + matte/chalky. Applied only to
    // PAINT (bare cream untouched), blended dry↔wet by specWet. No speckle.
    float  lumaC   = skeinLuma(col);
    float3 wetBody = (lumaC + (col - lumaC) * kSkeinWetSat) * kSkeinWetDarken;   // saturate then darken
    float3 dryBody = mix(col, float3(lumaC), kSkeinDryDesat) * kSkeinDryLighten; // desaturate + lighten
    float3 painted = mix(dryBody, wetBody, specWet);
    col = mix(col, painted, paint);

    // Glossy catch-light (a clean, coherent specular reflection on WET paint — NOT a speckle). GGX
    // from the smooth luminance-gradient normal, so it catches at the wet stroke's edges/ridges where
    // the surface faces the light. Gated by specWet × paint.
    float3 V = float3(0.0, 0.0, 1.0);
    float3 H = normalize(kSkeinLightDir + V);
    float  spec = skeinGGX(max(dot(N, H), 0.0), kSkeinRoughGloss, kSkeinSpecKnee) * specWet * paint * kSkeinGainGloss;

    // Subtle canvas-weave grain beneath the paint (the §2-Material "subtle canvas-weave texture
    // beneath") — a faint high-frequency modulation, strongest on the bare/thin ground, fading
    // under thick opaque paint so it never competes with the marks.
    float weave = sin(uv.x * 760.0) * sin(uv.y * 760.0);
    col *= 1.0 + kSkeinWeaveAmp * weave * (1.0 - paint);

    // Add the wet specular highlight ON TOP of the stem colour (additive — never a recolour, so the
    // Skein.3 palette reads through). The drawable (.bgra8Unorm_srgb) sRGB-encodes on store.
    col += spec * kSkeinSpecColor;

    // ── Skein.5: painter LOCUS (build-flagged, OFF by default) ──────────────────────
    // A faint luminous pour-point hovering at the live painter tip — makes "where the paint is
    // coming from" trackable by eye. DISPLAY-ONLY by construction: drawn here at comp (the blit to
    // the drawable), NEVER in the geometry overlay — anything the overlay draws is baked losslessly
    // into the held canvas, so a locus there would paint itself permanently (the same display-only
    // contract as butterchurn comp, FA #70). Position = the live tip on the current pour (trajectory
    // + the pour's frozen jump offset, exactly what Layer A draws at k = 0).
    if (st.locusEnable > 0.5) {
        float2 tip = skeinPainterPos(st.painterTau, st.seedPhaseX, st.seedPhaseY)
                   + skeinLineLookupAt(st.painterTau, st).off;
        float aspect = float(warpTex.get_width()) / max(float(warpTex.get_height()), 1.0);
        float d = length(float2((uv.x - tip.x) * aspect, uv.y - tip.y));
        // A luminous point ABOVE the canvas needs contrast on BOTH grounds: a warm-white glow is
        // near-invisible over cream, so the "hovering" cue is a soft occlusion SHADOW ring under
        // the glow (an object above a surface casts one) — legible on cream AND on paint.
        float dr = d - 0.014;
        float ring = exp(-dr * dr / (2.0 * 0.008 * 0.008));
        col = mix(col, col * 0.78, 0.45 * ring);
        float core = exp(-d * d / (2.0 * 0.006 * 0.006));          // bright pin core (~0.6 % of height)
        float halo = exp(-d * d / (2.0 * 0.028 * 0.028));          // soft hovering halo
        col += float3(1.0, 0.95, 0.82) * (0.55 * core + 0.10 * halo);
    }

    return float4(saturate(col), 1.0);
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
