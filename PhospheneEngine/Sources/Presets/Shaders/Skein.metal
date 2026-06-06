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
constant float kSkeinBakeWindow = 0.55;   // painter-clock units a burst is redrawn before it freezes

struct SkeinBurstGPU {        // 12 floats = 48 bytes (matches Swift SkeinBurstGPU)
    float posX; float posY;            // uv flick point
    float dirX; float dirY;            // throw direction (aspect-corrected, frozen)
    float spawnTau;                    // painter clock at spawn
    float size;                        // base droplet size (attackRatio)
    float visc;                        // viscosity [0,1] (1 − centroid)
    float colR; float colG; float colB;  // frozen stem colour
    float sharpness;                   // flick sharpness [0,1]
    float hashSeed;                    // per-burst droplet-placement seed
};

struct SkeinUniforms {        // 64-byte header + 48 × 48-byte bursts (matches SkeinState buffer)
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
    float pad0; float pad1; float pad2; float pad3;
    SkeinBurstGPU bursts[48];          // == kSkeinMaxBursts
};

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

    // ── Layer A: the pour LINE + trailing-off tail (dominant-stem coloured, flow-/visc-widened) ──
    // Width rides 1/speed (pools at slow turning points) × the dominant stem's viscosity (thick →
    // heavy lobes) × its pour flow (a surge fattens the pour). The AGE taper trails off the leading
    // edge. lineCol is the DISCRETE dominant-stem colour (SkeinState argmax — never a blend), so the
    // continuous line records who is leading the mix (SKEIN_DESIGN §1.2). At silence lineCol stays
    // white → white-on-cream, silence-non-black trivial.
    float3 lineCol   = float3(st.lineColR, st.lineColG, st.lineColB);
    float  lineVisc  = clamp(st.lineVisc, 0.0, 1.0);
    float  lineWiden = mix(1.0, 1.5, lineVisc) + 0.5 * clamp(st.lineFlow, 0.0, 1.0);
    {
        float2 tip = skeinPainterPos(tau, phx, phy);
        float2 recent = float2(tip.x * a, tip.y);     // k = 0 (newest)
        for (int k = 0; k < kSkeinTailFrames; ++k) {
            float2 pp = skeinPainterPos(tau - float(k + 1) * dtau, phx, phy);
            float2 older = float2(pp.x * a, pp.y);

            float speed = length(recent - older) / dtau;                      // v-units / painter-clock-unit
            float baseR = kSkeinLineRadius * lineWiden * mix(1.6, 0.75, smoothstep(0.05, 0.35, speed));

            float ageFrac = float(k) / float(kSkeinTailFrames);   // 0 = live tip, 1 = tail base
            float r  = baseR * mix(0.18, 1.0, ageFrac);           // width tapers thin → full
            float op = mix(0.04, 1.0, smoothstep(0.0, 0.85, ageFrac));  // leading-edge trail-off

            float d  = skeinSegDist(q, older, recent);
            float aa = max(fwidth(d), 1e-4);
            float cov = (1.0 - smoothstep(r - aa, r + aa, d)) * op;
            if (cov > bestCover) { bestCover = cov; bestCol = lineCol; }

            recent = older;
        }
    }

    // ── Layers B + C: onset-burst RING — per-stem-coloured splatter + filament tendrils ──
    // Each burst is a real per-stem ONSET (SkeinState rising-edge detection on *_energy_dev), frozen
    // at the painter position in that stem's colour, with size ← attackRatio, viscosity ← centroid.
    // We redraw bursts within the bake window (the pour-tail age-ramp), so each fades in then FREEZES
    // into the held canvas once aged out — identical bake-and-hold to Skein.2, now onset-driven. The
    // Skein.2 droplet + filament morphology (ragged edge, exp/poly satellites, isotropic AA,
    // forward-gated filaments) is preserved per burst.
    int nB = min(int(st.burstCount), kSkeinMaxBursts);
    for (int b = 0; b < nB; ++b) {
        SkeinBurstGPU burst = st.bursts[b];
        float age = tau - burst.spawnTau;
        if (age < 0.0 || age > kSkeinBakeWindow) { continue; }
        float ageFrac = age / kSkeinBakeWindow;
        float op = mix(0.05, 1.0, smoothstep(0.0, 0.8, ageFrac));

        float2 fpA  = float2(burst.posX * a, burst.posY);                     // flick point (aspect-corrected)
        float2 dir  = float2(burst.dirX, burst.dirY);                         // throw axis (frozen, aspect-corrected)
        float  base = atan2(dir.y, dir.x);
        float  visc = clamp(burst.visc, 0.0, 1.0);
        float3 col  = float3(burst.colR, burst.colG, burst.colB);

        // Viscosity → burst character (SKEIN_DESIGN §1.2): thin/bright (visc→0) = MANY fine FAR
        // satellites; thick/dark (visc→1) = FEWER, BIGGER, CLOSER droplets. attackRatio (burst.size)
        // scales the base droplet size (sharp transient → smaller/tighter); sharpness narrows the
        // near-satellite splash cone (sharp → tighter forward spray, soft → a full splash halo).
        float sizeScale = clamp(burst.size, 0.4, 1.3);
        int   nDrop    = int(mix(46.0, 13.0, visc));
        float spread   = mix(0.170, 0.075, visc);
        float dropBig  = mix(0.0065, 0.0135, visc) * sizeScale;             // DISTINCT dots, sized to survive the thin line + read per-stem
        float edgeAmp  = mix(0.40, 0.26, visc);                              // thin = more feathered / irregular edge
        float aaScale  = mix(2.6, 1.4, visc);                               // edge AA in PIXELS (thick crisp → thin feathered)
        float coneNear = mix(3.14159, 1.20, clamp(burst.sharpness, 0.0, 1.0)); // soft = full splash, sharp = narrower

        // SCISSOR (§6 — cost ∝ this frame's marks): a fragment outside the burst's bounding disc
        // skips the whole droplet loop. Bound covers the farthest droplet + its ragged radius.
        float bound = spread + dropBig * 2.5 + 0.01;
        if (length(q - fpA) > bound) { continue; }

        for (int n = 0; n < nDrop; ++n) {
            float4 hs      = hash_f01_4x(float4(burst.hashSeed, float(n), 1.0, 0.0));
            float distFrac = pow(hs.x, 1.5);                                  // exp/poly: denser near the line, tail far
            float dist     = spread * distFrac;
            // Near satellites scatter (splash halo, cone narrowed by sharpness); far = forward-thrown.
            float coneHalf = mix(coneNear, 0.42, distFrac);
            float ang      = base + coneHalf * (hs.y * 2.0 - 1.0);
            float2 dpos    = fpA + float2(cos(ang), sin(ang)) * dist;
            float  dr      = dropBig * mix(0.9, 0.18, distFrac) * mix(0.55, 1.3, hs.z);  // mid near, fine far — DISTINCT dots

            // Cheap per-droplet reject BEFORE the noise keeps the inner loop affordable.
            float dc = length(q - dpos);
            if (dc < dr * 1.7 + px * 4.5) {
                // RAGGED organic edge — perturb the radius by ±noise (never a clean circle; anti-ref polka-dots).
                float ragged = 1.0 + edgeAmp * skein_fbm2(q * 70.0 + float2(burst.hashSeed * 7.3, float(n) * 3.1));
                // ISOTROPIC px-based AA — NOT fwidth(dc) (which runs ~41 % wider at the diagonals →
                // rounded-SQUARE droplets, Matt M7 2026-06-05) — + a ~1.5 px ROUND radius floor.
                float drr = max(dr * max(ragged, 0.20), px * 1.5);
                float aa  = px * aaScale;
                float cov = (1.0 - smoothstep(drr - aa, drr + aa, dc)) * op;
                if (cov > bestCover) { bestCover = cov; bestCol = col; }
            }

            // FILAMENT: a thin ragged FORWARD tendril (ref 03_micro_filament_threads). Forward-gated +
            // short + sparse (hash) so threads do NOT radiate as a starburst — that radial-spoke
            // firework IS the particle-burst anti-reference. A few directional spray-streaks, never a web.
            float2 toDrop = dpos - fpA;
            float  dlen   = length(toDrop);
            bool   fwd    = dot(toDrop / max(dlen, 1e-5), dir) > 0.30;        // forward of the throw only
            if (hs.w < 0.16 && fwd && dlen > spread * 0.18 && dlen < spread * 0.5) {
                float fd = skeinSegDist(q, fpA, dpos);
                if (fd < px * 4.0) {
                    float filR  = 0.0015 * (1.0 + 0.5 * skein_fbm2(q * 130.0 + float2(float(n) * 5.0, burst.hashSeed * 2.0)));
                    float filRR = max(filR, px * 0.9);            // keep thin threads ≥ ~1 px so they read as strands
                    float faa   = px * 1.5;                       // isotropic AA (same reason as the droplet edge)
                    float cov = (1.0 - smoothstep(filRR - faa, filRR + faa, fd)) * op * 0.8;
                    if (cov > bestCover) { bestCover = cov; bestCol = col; }
                }
            }
        }
    }

    // OPAQUE alpha-over: the overlay blend (SRC_ALPHA / ONE_MINUS_SRC_ALPHA) composites the TOPMOST
    // mark's colour over the held canvas at bestCover — layers occlude, never average to mud.
    return float4(bestCol, bestCover);
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
