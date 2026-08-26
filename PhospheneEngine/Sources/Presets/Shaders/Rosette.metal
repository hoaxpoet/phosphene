// Rosette.metal — John Whitney Sr.'s *Arabesque* (1975) morphing emblem.
//
// WHIT.1c: registered from the WHIT.0 look-spike (docs/ENGINEERING_PLAN.md Phase WHIT),
// verdict GO. Design record: docs/presets/ROSETTE_DESIGN.md. References:
// docs/VISUAL_REFERENCES/rosette/. certified: false.
//
// WHIT.1d: harmony coupling for three of the program doc's five proposed routes
// (figure_tightness<-tonalConsonance, stroke_presence<-bassDev, morph_floor_rate<-
// midAttRel) — all stateless, read fresh every frame.
//
// WHIT.1d-2: the remaining two routes, which both needed a value held ACROSS FRAMES
// (D-219 audit finding) — `RosetteState` (Presets/Rosette/RosetteState.swift) owns
// both and is bound at fragment buffer(6), Skein's per-preset-uniforms convention:
//   - morph_position <- tonalPhaseFifths: a STATEFUL circular smoother (D-209) on the
//     raw +/-pi sawtooth, recombined via atan2, applied as a ROTATION of the FIGURE
//     ONLY (never the wings — keeps the D-217 frame fixed). Distinct visual channel
//     from figure_tightness, resolving the FA #67 conflict the pre-spike design docs
//     had (both routes originally targeted the same scalar `a`).
//   - symmetry_order_step <- harmonicFlux: a hold-timer steps the symmetry order
//     through Whitney's own sequence (5->6->4, WHITNEY_PROGRAM.md §2) on a flux spike,
//     but only once the current order has held >= minHoldSeconds — never per-beat.
//
// Two-term epicycle z(t) = e^{it} + a·e^{-i(n-1)t} (n now dynamic, WHIT.1d-2) reproduces
// the film's tangle/petals/star/pentagon family
// (ROSETTE_DESIGN.md §4.1: hits circle/cusped-star/petals/petals-with-loops/tangle;
// misses a true STRAIGHT-edged pentagon — two terms round the corners where the film
// shows flats, confirmed against docs/VISUAL_REFERENCES/rosette/
// 05_macro_pentagon_straight_edges.jpg. Accepted limitation, not an open bug — do not
// add a third harmonic term to chase it without Matt's sign-off).
//
// Drawn as a single fullscreen-triangle overlay (Skein's SDF-in-fragment pattern —
// `skein_geometry_vertex`/`_fragment`, Skein.metal:309) with a numerical nearest-point
// search per pixel for the stroke SDF, because no closed-form distance exists for a
// self-intersecting two-term epicycle. Profiled at 1080p (WHIT.1c): geometry-overlay
// pass alone measures ~5.8ms p50 / 6.2ms p95 on an M2 Pro, comfortably inside the 16.67ms
// @60fps total budget. Zero engine touch: marks-on-top mv_warp path (D-138/D-143),
// `strandsOnTop` (RenderPipeline+MVWarp.swift:138).

#include <metal_stdlib>
using namespace metal;

// FeatureVector / StemFeatures / MVWarpPerFrame are declared in the shared preamble
// PresetLoader prepends ahead of every preset's .metal source (Self.shaderPreamble +
// Self.mvWarpPreamble) — no #include, matching every other preset file in this repo.

constant float kRosetteAMin     = 0.05;    // tightest state (near-pentagon), task 2 CPU sweep
constant float kRosetteAMax     = 1.80;    // loosest state (tangle), task 2 CPU sweep
constant float kRosettePeriod   = 30.0;    // seconds per tighten/unravel cycle (rosette_build.png spans 30s)
constant float kRosetteRadius   = 0.30;    // figure half-extent, fraction of frame height
constant float kRosetteStrokeW  = 0.0032;  // core stroke half-width, fraction of frame height (task 1 estimate)
// Halation, RETUNED at WHIT.1c: task 1's thumbnail-based estimate (~4.4x core) was too
// generous. docs/VISUAL_REFERENCES/rosette/06_specular_stroke_core_halo.jpg, viewed at a
// proper crop scale, reads closer to 1.5-2x core width (ROSETTE_DESIGN.md §6.5).
constant float kRosetteHaloW    = 0.0056;  // ~1.75x core, tuned against 06_specular_stroke_core_halo.jpg
constant int   kRosetteCoarse   = 40;      // coarse nearest-point search samples
constant int   kRosetteRefine   = 7;       // bisection refine steps
// BUG-103: the wing arcs (below) were tuned and every test ever run against a 16:9-family
// aspect (960x540 / 1920x1080, aspect 1.778); their x-placement was a hardcoded absolute
// q-space value that assumed that width. At a near-square real window (1080x1018, aspect
// 1.06 — Matt's live session 2026-08-26T12-58-21Z) the visible q.x range shrinks to
// +/-0.53, entirely inside the wings' old x~0.62-0.67, so they render fully off-screen —
// the whole D-217 cartouche silently vanishes. Fix: place wings as a FRACTION of the
// frame's actual visible half-width (0.5*aspect) rather than an absolute unit, referenced
// against 16:9 so the already-approved D-217 look is reproduced exactly at that aspect and
// scales proportionally (never clips) at any other.
constant float kRosetteReferenceAspect = 16.0 / 9.0;

// The epicycle, normalised to unit-ish radius regardless of `a` (F2: the emblem's
// overall SIZE stays roughly constant through the morph in rosette_build.png; only the
// character changes, not the scale). `n` is now dynamic (WHIT.1d-2, `symmetry_order_step`)
// — the aMin/aMax calibration was tuned against n=5 (task 2's CPU sweep) and is reused
// as-is for the stepped orders (4, 6): a reasonable approximation, not re-swept per n.
static float2 rosetteCurve(float t, float a, float n) {
    float2 z1 = float2(cos(t), sin(t));
    float t2 = -(n - 1.0) * t;
    float2 z2 = float2(cos(t2), sin(t2));
    return (z1 + a * z2) / (1.0 + a);
}

// Coarse-then-bisect nearest-point search on the closed curve — no closed-form SDF
// exists for a two-term epicycle once it self-intersects.
//
// BUG-104 (found live, Matt: "Lines do not connect. The motion is all wrong."):
// bisecting from only the SINGLE globally-closest coarse sample locks the search onto
// whichever curve branch happened to own that one sample, and never considers a
// different, ultimately-closer branch passing nearby — a self-intersecting curve can
// have several branches near the same query point. Visible live as literal gaps in the
// rendered stroke at branch-crossing regions (worst at high `a`/tangle, where the second
// term dominates and crossings are dense) and small disconnected artifact dots at cusps
// (worst-case reproduction: `docs/VISUAL_REFERENCES/rosette/` motion review; regression
// guard: `test_rosette_curveIsContinuousAtHighA`). Fixed by finding ALL local minima
// among the coarse samples (not just the global-best raw value) and bisect-refining each
// candidate branch separately, then taking the overall closest result.
constant int kRosetteMaxBranchCandidates = 3;
static float rosetteDist(float2 p, float a, float n) {
    float d2arr[kRosetteCoarse];
    for (int i = 0; i < kRosetteCoarse; i++) {
        float t = 2.0 * M_PI_F * float(i) / float(kRosetteCoarse);
        float2 d = p - rosetteCurve(t, a, n);
        d2arr[i] = dot(d, d);
    }

    // Keep the smallest kRosetteMaxBranchCandidates LOCAL MINIMA (each a candidate
    // distinct branch), not just the single smallest raw sample.
    float candT[kRosetteMaxBranchCandidates];
    float candD2[kRosetteMaxBranchCandidates];
    for (int c = 0; c < kRosetteMaxBranchCandidates; c++) { candD2[c] = 1e9; candT[c] = 0.0; }
    for (int i = 0; i < kRosetteCoarse; i++) {
        int iPrev = (i - 1 + kRosetteCoarse) % kRosetteCoarse;
        int iNext = (i + 1) % kRosetteCoarse;
        if (d2arr[i] <= d2arr[iPrev] && d2arr[i] <= d2arr[iNext]) {
            int worst = 0;
            for (int c = 1; c < kRosetteMaxBranchCandidates; c++) {
                if (candD2[c] > candD2[worst]) worst = c;
            }
            if (d2arr[i] < candD2[worst]) {
                candD2[worst] = d2arr[i];
                candT[worst] = 2.0 * M_PI_F * float(i) / float(kRosetteCoarse);
            }
        }
    }

    float bestD2 = 1e9;
    float span0 = M_PI_F / float(kRosetteCoarse);
    for (int c = 0; c < kRosetteMaxBranchCandidates; c++) {
        if (candD2[c] >= 1e9) continue;   // fewer than kRosetteMaxBranchCandidates branches nearby
        float bestT = candT[c];
        float bestLocalD2 = candD2[c];
        float span = span0;
        for (int r = 0; r < kRosetteRefine; r++) {
            float tA = bestT - span, tB = bestT + span;
            float2 dA = p - rosetteCurve(tA, a, n);
            float2 dB = p - rosetteCurve(tB, a, n);
            float d2A = dot(dA, dA), d2B = dot(dB, dB);
            if (d2A < bestLocalD2) { bestLocalD2 = d2A; bestT = tA; }
            if (d2B < bestLocalD2) { bestLocalD2 = d2B; bestT = tB; }
            span *= 0.5;
        }
        bestD2 = min(bestD2, bestLocalD2);
    }
    return sqrt(bestD2);
}

// F4: mirrored coloured wing arcs at the frame edges, each carrying a small ellipse
// (`ARABESQUE_FILM_NOTES` F4). A shallow bowed arc + a small loop near its lower end;
// `side` = -1 (left) / +1 (right, mirrored).
static float2 rosetteWingArc(float s, float side, float aspect) {
    // BUG-103: x scales with the frame's actual half-width relative to the 16:9 reference
    // it was tuned against, so the wing sits the same FRACTION of the way to the true edge
    // at any aspect — reproduces the approved look exactly at 16:9, never clips off-screen
    // at a narrower window. y is untouched: visible q.y is always +/-0.5 regardless of aspect.
    float xScale = aspect / kRosetteReferenceAspect;
    float x = side * xScale * (0.62 + 0.05 * sin(s * M_PI_F));
    float y = mix(0.85, -0.85, s);
    return float2(x, y);
}
// Point-to-SEGMENT distance (not point-to-nearest-sample-point — that produced a
// "beads on a string" artifact: gaps at the midpoint between coarse samples,
// found live). Standard capsule SDF core.
static float segDist(float2 p, float2 a, float2 b) {
    float2 pa = p - a, ba = b - a;
    float t = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-6), 0.0, 1.0);
    return length(pa - ba * t);
}
static float rosetteWingDist(float2 p, float side, int steps, float aspect) {
    float bestD = 1e9;
    float2 prev = rosetteWingArc(0.0, side, aspect);
    for (int i = 1; i <= steps; i++) {
        float s = float(i) / float(steps);
        float2 cur = rosetteWingArc(s, side, aspect);
        bestD = min(bestD, segDist(p, prev, cur));
        prev = cur;
    }
    return bestD;
}
static float rosetteWingEllipseDist(float2 p, float side, float aspect) {
    // y=-0.60 was off-screen (visible q.y spans roughly [-0.5, 0.5] — found live,
    // the ellipse never appeared). -0.30 sits near the arc's lower end, on-screen.
    // x scales with aspect the same way rosetteWingArc's does (BUG-103).
    float xScale = aspect / kRosetteReferenceAspect;
    float2 c = float2(side * xScale * 0.67, -0.30);
    float2 q = (p - c) / float2(0.055, 0.09);
    return (length(q) - 1.0) * 0.07;   // approximate SDF, scaled back to world units
}

// WHIT.1d-2: per-preset uniforms from RosetteState (Presets/Rosette/RosetteState.swift),
// bound at fragment buffer(6) — Skein's `SkeinUniforms` convention (a dedicated per-preset
// buffer for values a fragment cannot compute per-frame alone). Must match
// `RosetteUniformsGPU` in RosetteState.swift byte-for-byte.
struct RosetteUniforms {
    float smoothedFifths;   // circularly-smoothed tonal_phase_fifths, radians (D-209)
    float symmetryN;        // current held symmetry order (WHIT.1d-2)
    float pad0;
    float pad1;
};

struct RosetteGeoVertexOut {
    float4 position [[position]];
    float2 uv;
    float  aspect;
    float  time;        // passed through from the vertex stage — drawSceneGeometryOverlay
                         // (RenderPipeline+SceneGeometry.swift) only binds FeatureVector at the
                         // VERTEX argument table for this draw call, not the fragment's; Skein's
                         // geometry fragment gets its clock/state the same way (interpolated
                         // struct fields, or a dedicated per-preset buffer at slot 6 — never by
                         // re-declaring FeatureVector as a fragment parameter).
    float  consonance;   // WHIT.1d: f.tonal_consonance, same passthrough contract as `time`.
    float  bassDev;      // WHIT.1d: f.bass_dev (D-026 deviation primitive, never absolute).
    float  midAttRel;    // WHIT.1d: f.mid_att_rel.
};

// Fullscreen triangle — Skein's exact pattern (Skein.metal:309-320), renamed. All
// figure math happens per-pixel in the fragment stage below.
vertex RosetteGeoVertexOut rosette_geometry_vertex(
    uint vid [[vertex_id]],
    constant FeatureVector& f [[buffer(0)]]
) {
    float2 p = float2((vid == 2) ? 3.0 : -1.0, (vid == 1) ? 3.0 : -1.0);
    RosetteGeoVertexOut out;
    out.position = float4(p, 0.0, 1.0);
    out.uv = p * 0.5 + 0.5;
    out.aspect = (f.aspect_ratio > 0.01) ? f.aspect_ratio : 1.0;
    out.time = f.time;
    out.consonance = f.tonal_consonance;
    out.bassDev = f.bass_dev;
    out.midAttRel = f.mid_att_rel;
    return out;
}

fragment float4 rosette_geometry_fragment(
    RosetteGeoVertexOut in [[stage_in]],
    constant RosetteUniforms& ru [[buffer(6)]]
) {
    float aspect = in.aspect;
    float2 q = float2((in.uv.x - 0.5) * aspect, in.uv.y - 0.5);   // aspect-corrected, centred, y-down

    // Near-black ground with a faint blue-violet vignette (task 4 / F1). The render
    // target is bgra8Unorm_srgb (matches the real drawable — MetalContext.swift:55),
    // so a linear value here reads MUCH brighter on screen than the raw number
    // suggests (e.g. 0.035 linear displays as ~20% gray, not near-black — found
    // live). Tuned down to land near-black after the sRGB encode.
    float rEdge = length(q);
    float3 col = mix(float3(0.006, 0.004, 0.009), float3(0.0), smoothstep(0.15, 0.75, rEdge));

    // WHIT.1d/WHIT.1d-2 harmony coupling (ROSETTE_DESIGN.md §5 / §7) — all five of the
    // program doc's proposed routes now shipped. tonalConsonance, bassDev and midAttRel
    // are read fresh every frame below; tonalPhaseFifths and harmonicFlux both need a
    // value smoothed/held ACROSS FRAMES (tonalPhaseFifths is a raw +/-pi sawtooth that
    // must go through a stateful circular smoother before use — D-209,
    // CircularPhaseSmoother.swift — or it jumps at the seam, the exact defect that hit
    // Fractal Tree; harmonicFlux needs a hold-timer so a step lasts "tens of seconds", not
    // one frame) and are supplied by RosetteState (Presets/Rosette/RosetteState.swift) via
    // the `RosetteUniforms` struct bound at fragment buffer(6), Skein's per-preset-uniforms
    // convention.

    // figure_tightness <- tonalConsonance (continuous). TONAL.2b's 1000-track calibration
    // (WHITNEY_PROGRAM.md §5.2): floor 0.05, corpus MEDIAN 0.117, p99 0.32. A linear or
    // smoothstep map puts the median at ~0.15 of the tightness range (too close to the loose
    // end) -- explicitly the failure mode §5.2 warns about. A sqrt curve on the normalised
    // band lands the median at ~0.50: sqrt((0.117-0.05)/(0.32-0.05)) = sqrt(0.248) = 0.498.
    float c01 = saturate((in.consonance - 0.05) / (0.32 - 0.05));
    float tight01 = sqrt(c01);                 // 0 = loose (low consonance), 1 = tight (high)
    float aHarmony = mix(kRosetteAMax, kRosetteAMin, tight01);

    // Plain clock — the tighten/unravel floor when there is little/no tonal signal to read
    // (silence, noise, atonal passages). TRIANGLE wave, not sine: a sinusoidal a(t) eases at
    // the tight/loose extremes (da/dt -> 0 at the turning points) -- found live via
    // motion_gate.sh at WHIT.0, 82/299 frames read as near-frozen. A triangle wave has
    // constant |da/dt| everywhere except an instantaneous reversal at each extreme, matching
    // §9.4's "servo-driven, constant rate -- any easing reads immediately as wrong."
    // morph_floor_rate <- midAttRel (continuous): scales the clock's rate. Not a true
    // per-frame integral (that needs cross-frame state, same constraint as above) -- a
    // bounded multiplicative time-warp is a reasonable, documented approximation for a
    // slowly-varying, heavily-smoothed (*_att_rel) primitive.
    float floorRateMul = clamp(1.0 + 0.6 * in.midAttRel, 0.4, 1.8);
    float x = (in.time * floorRateMul) / kRosettePeriod;
    float tri = 2.0 * abs(x - floor(x + 0.5));   // period 1, linear ramp 0->1->0
    float aClock = kRosetteAMin + (kRosetteAMax - kRosetteAMin) * tri;

    // Harmony SETS the position; the clock is demoted to the floor drift and only shows
    // through when there is little tonal signal (the Nacre lesson, §5.3 -- a free clock
    // additively competing with harmony reads as "not sure if the coupling is working").
    // Consonance's own analyzer floor (0.05, width 0.03 -- §5.2) is the natural gate: below
    // it there is effectively no tonal content to read.
    float presence = smoothstep(0.02, 0.08, in.consonance);
    float aMorph = mix(aClock, aHarmony, presence);

    // The rosette figure — white / pale lavender, always (F3: colour is NOT indexical
    // on the figure; do not hue-cycle this element).
    // morph_position <- tonalPhaseFifths (continuous, WHIT.1d-2): a rotation of the FIGURE
    // ONLY (D-219's resolution to the FA #67 clash with tonalConsonance -> tightness — a
    // genuinely distinct visual channel). `ru.smoothedFifths` is already circularly
    // smoothed (D-209) by RosetteState; rotate the figure's sample coordinate before the
    // distance search. `q` itself is left untouched so the wings (below) do not rotate.
    float2 pf = float2(q.x, -q.y) / kRosetteRadius;   // figure space, y-up
    float rotS = sin(ru.smoothedFifths), rotC = cos(ru.smoothedFifths);
    pf = float2(rotC * pf.x - rotS * pf.y, rotS * pf.x + rotC * pf.y);
    // symmetry_order_step <- harmonicFlux (accent, WHIT.1d-2): `ru.symmetryN` is the
    // held order from RosetteState's hold-timer — never flickers per-beat.
    float d = rosetteDist(pf, aMorph, ru.symmetryN) * kRosetteRadius;
    float core = exp(-(d * d) / (2.0 * kRosetteStrokeW * kRosetteStrokeW));
    float halo = exp(-(d * d) / (2.0 * kRosetteHaloW * kRosetteHaloW));
    float3 figureCol = mix(float3(1.0), float3(0.88, 0.85, 1.0), 0.30);
    // stroke_presence <- bassDev (continuous, D-026 deviation primitive — never an
    // absolute threshold, FA #31). Brightness/halation swell on bass transients; bounded
    // so a quiet passage never fully extinguishes the stroke (D-037-adjacent: this preset
    // has no true silence floor concern since bassDev=0 already gives full unit presence).
    float presenceBoost = 1.0 + 0.5 * max(0.0, in.bassDev);
    col += figureCol * presenceBoost * (1.15 * core + 0.35 * halo);

    // Mirrored coloured wings (F4) — saturated hue lives HERE, never on the figure.
    // Slow independent drift stands in for "hue changes between passages" (F3) with
    // no audio route wired this session.
    float hueT = in.time * 0.05;
    float3 leftHue  = 0.5 + 0.5 * cos(6.2831853 * (hueT + float3(0.0, 0.33, 0.67)));
    float3 rightHue = 0.5 + 0.5 * cos(6.2831853 * (hueT + 0.5 + float3(0.0, 0.33, 0.67)));
    float dLeftArc  = rosetteWingDist(q, -1.0, 48, aspect);
    float dRightArc = rosetteWingDist(q,  1.0, 48, aspect);
    float dLeftEll  = rosetteWingEllipseDist(q, -1.0, aspect);
    float dRightEll = rosetteWingEllipseDist(q,  1.0, aspect);
    float wingCoreW = kRosetteStrokeW * 1.4;
    float wingHaloW = kRosetteHaloW * 1.1;
    float lArcI = exp(-(dLeftArc * dLeftArc) / (2.0 * wingCoreW * wingCoreW))
                + 0.3 * exp(-(dLeftArc * dLeftArc) / (2.0 * wingHaloW * wingHaloW));
    float rArcI = exp(-(dRightArc * dRightArc) / (2.0 * wingCoreW * wingCoreW))
                + 0.3 * exp(-(dRightArc * dRightArc) / (2.0 * wingHaloW * wingHaloW));
    float lEllI = exp(-(dLeftEll * dLeftEll) / (2.0 * wingCoreW * wingCoreW))
                + 0.3 * exp(-(dLeftEll * dLeftEll) / (2.0 * wingHaloW * wingHaloW));
    float rEllI = exp(-(dRightEll * dRightEll) / (2.0 * wingCoreW * wingCoreW))
                + 0.3 * exp(-(dRightEll * dRightEll) / (2.0 * wingHaloW * wingHaloW));
    col += leftHue  * (lArcI + lEllI);
    col += rightHue * (rArcI + rEllI);

    // Opaque every frame — the film draws the figure complete each frame (FILM_NOTES
    // §4/§9.4), no accumulation. This fragment repaints every pixel, so `decay` below
    // has no visible effect (documented, not a bug).
    return float4(saturate(col), 1.0);
}

// Required by PresetLoader.makeDirectPrimaryPipeline for the library to compile at
// all — never invoked at runtime once the geometry overlay makes this a
// `strandsOnTop` preset (RenderPipeline+MVWarp.swift:138). Trivial fill.
fragment float4 rosette_fragment(RosetteGeoVertexOut in [[stage_in]]) {
    return float4(0.0, 0.0, 0.0, 1.0);
}

// mv_warp canvas config (D-027): identity transform, light decay — NOT canvas-hold.
// The geometry fragment above already repaints every pixel opaque each frame, so
// `decay` is moot in practice; set low anyway so this reads as a light-decay preset
// (§6) rather than an infinite-hold one, and to exercise the real
// scene->warp->compose->swap dispatch path (task 3) with a non-degenerate value.
MVWarpPerFrame mvWarpPerFrame(
    constant FeatureVector& f,
    constant StemFeatures&  stems,
    constant SceneUniforms& s
) {
    MVWarpPerFrame pf;
    pf.zoom = 1.0;
    pf.rot  = 0.0;
    pf.decay = 0.15;
    pf.warp = 0.0;
    pf.cx = 0.0; pf.cy = 0.0;
    pf.dx = 0.0; pf.dy = 0.0;
    pf.sx = 1.0; pf.sy = 1.0;
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
    return uv;   // identity — no zoom/rotate/warp ripple (§6)
}
