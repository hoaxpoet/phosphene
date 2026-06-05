// Skein.metal — Skein.2: canvas-hold accumulation + wandering pour line + splatter morphology.
//
// Skein is an ACTION-PAINTING / drip-pour visualiser (Pollock's poured technique;
// see docs/presets/SKEIN_DESIGN.md). The canvas-hold accumulation path (identity warp,
// no decay, no colour transfer) lands the LOSSLESS persistent paint canvas; Skein.1 added
// the wandering "painter" pour LINE (a closed-form ergodic trajectory of features.time),
// accumulating losslessly on the cream ground. Skein.2 adds the SPLATTER VOCABULARY — the
// VisComp 2014 droplet + filament layers (Ni et al.; SKEIN_DESIGN §1.0): velocity-biased
// droplet BURSTS with ragged organic edges and exp/poly satellite falloff (ref
// 03_micro_satellite_spatter), thin connecting FILAMENT tendrils (ref 03_micro_filament_threads),
// and a VISCOSITY axis (thin-fast-fine ↔ thick-slow-gloopy; refs 02_meso_pour_pools /
// 06_palette_saturated_peak) shaping every mark — all baked normal-alpha into the SAME held
// canvas as the pour line.
//
// Still NO audio routing here: bursts fire on a DETERMINISTIC flick schedule and viscosity is
// a closed-form DEBUG sweep of features.time (so a STILL frame exhibits the full morphology).
// Real onset→splatter / centroid→viscosity / stem→colour routing + the per-track seed is Skein.3.
// NO palette beyond white-on-cream, NO wetness/sheen (ENGINE.2/Skein.4), NO mood (Skein.5).
//
// Path A (closed-form, in-shader; the Skein.1 audit, extended): splatter is a pure deterministic
// HASH of (flick index, droplet index) generated in skein_geometry_fragment with the Noise/Hash
// utilities — paint LANDS and the canvas HOLDS it (the canvas is a temporal integral, §1.4), so
// there is no persistent per-frame physics state, no CPU SkeinState, no per-preset overlay buffer,
// and NO engine touch (DragonBloom / FataMorgana byte-identical by construction). CPU-side state +
// the gated ENGINE.1.2 overlay buffer are deferred to Skein.3, where stateful audio routing is the
// demonstrated consumer (FA #59/#60; SKEIN_DESIGN §7). drawSceneGeometryOverlay binds `features`
// only at the VERTEX stage (RenderPipeline+SceneGeometry.swift:36-37) with no fragment buffer, so
// the debug viscosity is computed in skein_geometry_vertex and passed to the fragment as a varying.
//
// The gate is purely aesthetic: a still frame must read as POURED PAINT (Pollock), never a particle
// fountain / clean polka-dots / brush stroke / dead mat / kaleidoscope (the 5 Skein.0 anti-refs).
// Marks composite OPAQUE alpha-over (the normal-alpha overlay → layers occlude, never additive mud).
// `skein_fragment` remains the flat cream GROUND (what the PresetAcceptance + contrast harnesses
// render; Skein is readable-form-exempt — the marks live in the overlay).
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

// Flick schedule (DEBUG, no audio — Skein.3 routes onsets). A "flick" is a discrete paint-throw
// event at time T_i = i·kSkeinFlickDt along the SAME painter trajectory; its burst BAKES into the
// held canvas and is carried forward losslessly (so a still frame shows the full vocabulary).
constant float kSkeinFlickDt      = 0.46;   // ~2.2 flicks / s — studs the line with spatter
constant float kSkeinSplatWindow  = 0.55;   // s — the bake-in window (fade-in then freeze; like the pour tail)
constant int   kSkeinActiveFlicks = 3;      // recent flicks considered per frame (age-gated to the window)

// Debug VISCOSITY sweep (Skein.2 only). A slow closed-form function of features.time that traverses
// the FULL viscosity range, so a multi-second contact sheet — and a still frame at any t — exhibits
// BOTH poles: thin-fast-fine (visc→0; ref 03_micro) and thick-slow-gloopy (visc→1; refs 02 / 06).
// Period ~12 s: thin at t≈0 / 12 / 24, thick at t≈6 / 18. NOT time-as-RNG — a deterministic f(time),
// reproducible frame-over-frame. Real per-stem spectral-centroid → viscosity routing lands at Skein.3
// (§1.2); this whole function is throwaway, the MARK MORPHOLOGY it shapes is the deliverable.
static inline float skeinDebugViscosity(float t) {
    return 0.5 - 0.5 * cos(t * (6.2831853 / 12.0));
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
    float  t;        // features.time -- the painter clock (Path A: features reaches only the vertex)
    float  dt;       // features.delta_time (guarded) -- one tail step
    float  aspect;   // viewport aspect, for isotropic line width
    float  visc;     // Skein.2 DEBUG viscosity [0,1] -- computed here (features reaches only the vertex)
};

vertex SkeinGeoVertexOut skein_geometry_vertex(
    uint vid [[vertex_id]],
    constant FeatureVector& f [[buffer(0)]]   // bound by drawSceneGeometryOverlay (vertex slot 0)
) {
    // Fullscreen triangle in clip space: (-1,-1), (-1,3), (3,-1) -- covers the viewport.
    float2 p = float2((vid == 2) ? 3.0 : -1.0, (vid == 1) ? 3.0 : -1.0);
    SkeinGeoVertexOut out;
    out.position = float4(p, 0.0, 1.0);
    out.uv = p * 0.5 + 0.5;   // 0..1
    out.t  = f.time;
    out.dt = max(f.delta_time, 1.0 / 240.0);          // guard a zero dt (would collapse the tail)
    out.aspect = (f.aspect_ratio > 0.01) ? f.aspect_ratio : 1.0;
    out.visc = skeinDebugViscosity(f.time);           // Skein.2 debug viscosity sweep (Skein.3 → centroid)
    return out;
}

// Trailing-tail length in frames (~0.67 s at 60 fps): the leading run that tapers + builds up.
constant int kSkeinTailFrames = 40;

fragment float4 skein_geometry_fragment(SkeinGeoVertexOut in [[stage_in]]) {
    float a = in.aspect;
    float2 q = float2(in.uv.x * a, in.uv.y);          // aspect-corrected fragment position
    float t = in.t, dt = in.dt;
    float visc = clamp(in.visc, 0.0, 1.0);            // DEBUG viscosity (0 = thin-fine, 1 = thick-gloopy)
    // ~1 screen pixel in aspect-corrected q-units, ISOTROPIC (fwidth(q.x) == fwidth(q.y) == 1/height).
    // Used for the droplet/filament edge AA + the minimum-size floor — see the droplet block (Matt M7).
    float px = max(fwidth(q.x), fwidth(q.y));

    float cover = 0.0;

    // ── Layer A: the Skein.1 pour LINE + trailing-off tail (now viscosity-WIDENED) ─────────
    // Unchanged mechanism (width rides 1/speed → pools at slow turning points; the AGE taper
    // trails off the leading edge — SKEIN_DESIGN §1.0/§1.2). The Skein.2 viscosity factor only
    // ever WIDENS (mix floor = 1.0 = the exact Skein.1 width at the thin pole), so the Skein.1
    // continuity + lossless-hold invariants are preserved; the thick pole fattens the pour into
    // the heavy lobes/pools of ref 02_meso_pour_pools / 06_palette_saturated_peak.
    float lineVisc = mix(1.0, 1.5, visc);
    {
        float2 tip = skeinPainterPos(t);
        float2 recent = float2(tip.x * a, tip.y);     // k = 0 (newest)
        for (int k = 0; k < kSkeinTailFrames; ++k) {
            float2 pp = skeinPainterPos(t - float(k + 1) * dt);
            float2 older = float2(pp.x * a, pp.y);

            float speed = length(recent - older) / dt;                        // v-units / s
            float baseR = kSkeinLineRadius * lineVisc * mix(1.6, 0.75, smoothstep(0.05, 0.35, speed));

            float ageFrac = float(k) / float(kSkeinTailFrames);   // 0 = live tip, 1 = tail base
            float r  = baseR * mix(0.18, 1.0, ageFrac);           // width tapers thin → full
            float op = mix(0.04, 1.0, smoothstep(0.0, 0.85, ageFrac));  // leading-edge trail-off

            float d  = skeinSegDist(q, older, recent);
            float aa = max(fwidth(d), 1e-4);
            cover = max(cover, (1.0 - smoothstep(r - aa, r + aa, d)) * op);

            recent = older;
        }
    }

    // ── Layers B + C: SPLATTER droplet bursts + FILAMENT tendrils (VisComp droplet + filament) ─
    // Each FLICK is a discrete throw at time T_i = i·kSkeinFlickDt along the SAME painter
    // trajectory. We redraw flicks within the bake-in window each frame (the pour-tail age-ramp),
    // so a burst fades in then FREEZES into the held canvas once aged out — identical bake-and-hold.
    // All offsets / sizes are a deterministic HASH of (flick, droplet) → reproducible (§5.7).
    int iHi = int(floor(t / kSkeinFlickDt));
    for (int j = 0; j < kSkeinActiveFlicks; ++j) {
        int fi = iHi - j;
        if (fi < 0) { continue; }
        float Ti  = float(fi) * kSkeinFlickDt;
        float age = t - Ti;
        if (age < 0.0 || age > kSkeinSplatWindow) { continue; }

        // ~25 % of ticks throw no burst (breaks the metronome — reads thrown, not metered).
        if (hash_f01(uint(fi) * 1973u + 9u) > 0.75) { continue; }

        float ageFrac = age / kSkeinSplatWindow;
        float op = mix(0.05, 1.0, smoothstep(0.0, 0.8, ageFrac));

        float2 fp     = skeinPainterPos(Ti);
        float2 fpPrev = skeinPainterPos(Ti - dt);
        float2 fpA    = float2(fp.x * a, fp.y);                                // flick point (aspect-corrected)
        float2 dir    = normalize(float2((fp.x - fpPrev.x) * a, fp.y - fpPrev.y) + float2(1e-5, 0.0));
        float  base   = atan2(dir.y, dir.x);                                   // direction of travel (flung-forward axis)

        // Viscosity → burst character (SKEIN_DESIGN §1.2):
        //   thin/bright (visc→0): MANY fine FAR-flung satellites — delicate filigree (ref 03_micro).
        //   thick/dark  (visc→1): FEWER, BIGGER, CLOSER droplets — heavy spatter (refs 02 / 06).
        float flickJit = hash_f01(uint(fi) * 7919u + 3u);                      // per-flick size/count variation
        int   nDrop    = int(mix(46.0, 13.0, visc) * mix(0.45, 1.0, flickJit));
        float spread   = mix(0.170, 0.075, visc) * mix(0.7, 1.15, flickJit);  // thin flings WIDER (fine far satellites)
        float dropBig  = mix(0.0042, 0.0100, visc);                           // small DISTINCT dots, not merged froth
        float edgeAmp  = mix(0.40, 0.26, visc);                               // thin = more feathered / irregular edge
        float aaScale  = mix(2.6, 1.4, visc);                                 // edge AA in PIXELS: thick ~1.4 px (crisp) → thin ~2.6 px (feathered)

        // SCISSOR (§6 — cost ∝ this frame's marks): a fragment outside the burst's bounding disc
        // skips the whole droplet loop. Bound covers the farthest droplet + its ragged radius.
        float bound = spread + dropBig * 2.5 + 0.01;
        if (length(q - fpA) > bound) { continue; }

        for (int n = 0; n < nDrop; ++n) {
            float4 hs      = hash_f01_4x(float4(float(fi), float(n), 1.0, 0.0));
            float distFrac = pow(hs.x, 1.5);                                  // exp/poly: denser near the line, tail far
            float dist     = spread * distFrac;
            // Near satellites scatter all directions (splash halo); far ones are forward-thrown.
            float coneHalf = mix(3.14159, 0.42, distFrac);
            float ang      = base + coneHalf * (hs.y * 2.0 - 1.0);
            float2 dpos    = fpA + float2(cos(ang), sin(ang)) * dist;
            float  dr      = dropBig * mix(0.9, 0.18, distFrac) * mix(0.55, 1.3, hs.z);  // mid near, fine far — DISTINCT dots

            // Cheap per-droplet reject BEFORE the noise keeps the inner loop affordable.
            float dc = length(q - dpos);
            if (dc < dr * 1.7 + px * 4.5) {
                // RAGGED organic edge — perturb the radius by ±noise (never a clean circle; anti-ref polka-dots).
                float ragged = 1.0 + edgeAmp * skein_fbm2(q * 70.0 + float2(float(fi) * 7.3, float(n) * 3.1));
                // ISOTROPIC px-based AA — NOT fwidth(dc): the gradient of length() is the radial unit vector,
                // so fwidth(dc) runs ~41 % wider at the diagonals than the cardinals → sharp axis-aligned edges
                // snap to the pixel grid = ROUNDED-SQUARE droplets (Matt M7 2026-06-05). And FLOOR the radius at
                // ~1.5 px so even the finest far satellites read ROUND, not as a single square texel.
                float drr = max(dr * max(ragged, 0.20), px * 1.5);
                float aa  = px * aaScale;
                cover = max(cover, (1.0 - smoothstep(drr - aa, drr + aa, dc)) * op);
            }

            // FILAMENT: a thin ragged tendril from the line to a FORWARD, mid-distance droplet — reads as
            // a string of paint stretched along the throw (ref 03_micro_filament_threads). Gated FORWARD-
            // ONLY + short + sparse (hash) so threads do NOT radiate as a starburst — that radial-spoke
            // firework IS the particle-burst anti-reference. A few directional spray-streaks, never a web.
            float2 toDrop = dpos - fpA;
            float  dlen   = length(toDrop);
            bool   fwd    = dot(toDrop / max(dlen, 1e-5), dir) > 0.30;        // forward of the throw only
            if (hs.w < 0.16 && fwd && dlen > spread * 0.18 && dlen < spread * 0.5) {
                float fd = skeinSegDist(q, fpA, dpos);
                if (fd < px * 4.0) {
                    float filR = 0.0015 * (1.0 + 0.5 * skein_fbm2(q * 130.0 + float2(float(n) * 5.0, float(fi) * 2.0)));
                    float filRR = max(filR, px * 0.9);            // keep thin threads ≥ ~1 px so they read as strands
                    float faa  = px * 1.5;                        // isotropic AA (same reason as the droplet edge)
                    cover = max(cover, (1.0 - smoothstep(filRR - faa, filRR + faa, fd)) * op * 0.8);
                }
            }
        }
    }

    // White paint on the held cream ground (white-on-cream only — palette is Skein.3). Overlay blend
    // is SRC_ALPHA / ONE_MINUS_SRC_ALPHA → OPAQUE alpha-over (layers occlude, never additive mud).
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
