// Rosette.metal — WHIT.0 look-spike: John Whitney Sr.'s *Arabesque* morphing emblem.
//
// THROWAWAY. Lives only under Tests/.../Presets/Fixtures/Rosette/ — loaded by
// RosetteLookSpikeTests via PresetLoader's `watchDirectory` scratch-dir mechanism
// (PresetLoaderTests precedent), never placed in the shipped Sources/Presets/Shaders/
// directory. No sidecar there, no registration, preset count unchanged (WHIT.0 §pre-flight).
//
// Two-term epicycle z(t) = e^{it} + a·e^{-i(n-1)t} (n=5, `a` swept by a plain clock —
// no audio this session, §6 of docs/prompts/WHIT0_LOOK_SPIKE.md) reproduces the film's
// tangle/petals/star/pentagon family (task 2 verdict: hits circle/cusped-star/petals/
// petals-with-loops/tangle; misses a true STRAIGHT-edged pentagon — two terms round the
// corners where the film shows flats. Not fixed here per task 2's instruction: a miss is
// the finding, not a defect to add terms against).
//
// Drawn as a single fullscreen-triangle overlay (Skein's SDF-in-fragment pattern —
// `skein_geometry_vertex`/`_fragment`, Skein.metal:309) with a numerical nearest-point
// search per pixel for the stroke SDF, because no closed-form distance exists for a
// self-intersecting two-term epicycle. Zero engine touch: marks-on-top mv_warp path
// (D-138/D-143), `strandsOnTop` (RenderPipeline+MVWarp.swift:138).

#include <metal_stdlib>
using namespace metal;

// FeatureVector / StemFeatures / MVWarpPerFrame are declared in the shared preamble
// PresetLoader prepends ahead of every preset's .metal source (Self.shaderPreamble +
// Self.mvWarpPreamble) — no #include, matching every other preset file in this repo.

constant float kRosetteN        = 5.0;     // symmetry order (fixed this spike — harmonicFlux stepping is WHIT.1)
constant float kRosetteAMin     = 0.05;    // tightest state (near-pentagon), task 2 CPU sweep
constant float kRosetteAMax     = 1.80;    // loosest state (tangle), task 2 CPU sweep
constant float kRosettePeriod   = 30.0;    // seconds per tighten/unravel cycle (rosette_build.png spans 30s)
constant float kRosetteRadius   = 0.30;    // figure half-extent, fraction of frame height
constant float kRosetteStrokeW  = 0.0032;  // core stroke half-width, fraction of frame height (task 1 estimate)
constant float kRosetteHaloW    = 0.014;   // halation half-width, fraction of frame height (task 1 estimate, ~4.4x core)
constant int   kRosetteCoarse   = 40;      // coarse nearest-point search samples
constant int   kRosetteRefine   = 7;       // bisection refine steps

// The epicycle, normalised to unit-ish radius regardless of `a` (F2: the emblem's
// overall SIZE stays roughly constant through the morph in rosette_build.png; only the
// character changes, not the scale).
static float2 rosetteCurve(float t, float a) {
    float2 z1 = float2(cos(t), sin(t));
    float t2 = -(kRosetteN - 1.0) * t;
    float2 z2 = float2(cos(t2), sin(t2));
    return (z1 + a * z2) / (1.0 + a);
}

// Coarse-then-bisect nearest-point search on the closed curve — no closed-form SDF
// exists for a two-term epicycle once it self-intersects. Cheap enough for a spike;
// a per-pixel numerical search is not a shipped-perf pattern anywhere else in this
// codebase, so WHIT.1c should revisit this for a 60fps budget (flagged in the
// closeout, not solved here — out of WHIT.0 scope).
static float rosetteDist(float2 p, float a) {
    float bestD2 = 1e9;
    float bestT = 0.0;
    for (int i = 0; i < kRosetteCoarse; i++) {
        float t = 2.0 * M_PI_F * float(i) / float(kRosetteCoarse);
        float2 d = p - rosetteCurve(t, a);
        float d2 = dot(d, d);
        if (d2 < bestD2) { bestD2 = d2; bestT = t; }
    }
    float span = M_PI_F / float(kRosetteCoarse);
    for (int r = 0; r < kRosetteRefine; r++) {
        float tA = bestT - span, tB = bestT + span;
        float2 dA = p - rosetteCurve(tA, a);
        float2 dB = p - rosetteCurve(tB, a);
        float d2A = dot(dA, dA), d2B = dot(dB, dB);
        if (d2A < bestD2) { bestD2 = d2A; bestT = tA; }
        if (d2B < bestD2) { bestD2 = d2B; bestT = tB; }
        span *= 0.5;
    }
    return sqrt(bestD2);
}

// F4: mirrored coloured wing arcs at the frame edges, each carrying a small ellipse
// (`ARABESQUE_FILM_NOTES` F4). A shallow bowed arc + a small loop near its lower end;
// `side` = -1 (left) / +1 (right, mirrored).
static float2 rosetteWingArc(float s, float side) {
    float x = side * (0.62 + 0.05 * sin(s * M_PI_F));
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
static float rosetteWingDist(float2 p, float side, int steps) {
    float bestD = 1e9;
    float2 prev = rosetteWingArc(0.0, side);
    for (int i = 1; i <= steps; i++) {
        float s = float(i) / float(steps);
        float2 cur = rosetteWingArc(s, side);
        bestD = min(bestD, segDist(p, prev, cur));
        prev = cur;
    }
    return bestD;
}
static float rosetteWingEllipseDist(float2 p, float side) {
    // y=-0.60 was off-screen (visible q.y spans roughly [-0.5, 0.5] — found live,
    // the ellipse never appeared). -0.30 sits near the arc's lower end, on-screen.
    float2 c = float2(side * 0.67, -0.30);
    float2 q = (p - c) / float2(0.055, 0.09);
    return (length(q) - 1.0) * 0.07;   // approximate SDF, scaled back to world units
}

struct RosetteGeoVertexOut {
    float4 position [[position]];
    float2 uv;
    float  aspect;
    float  time;   // passed through from the vertex stage — drawSceneGeometryOverlay
                    // (RenderPipeline+SceneGeometry.swift) only binds FeatureVector at the
                    // VERTEX argument table for this draw call, not the fragment's; Skein's
                    // geometry fragment gets its clock/state the same way (interpolated
                    // struct fields, or a dedicated per-preset buffer at slot 6 — never by
                    // re-declaring FeatureVector as a fragment parameter).
};

// Fullscreen triangle — Skein's exact pattern (Skein.metal:309-320), renamed. All
// figure math happens per-pixel in the fragment stage below.
vertex RosetteGeoVertexOut rosette_nowings_geometry_vertex(
    uint vid [[vertex_id]],
    constant FeatureVector& f [[buffer(0)]]
) {
    float2 p = float2((vid == 2) ? 3.0 : -1.0, (vid == 1) ? 3.0 : -1.0);
    RosetteGeoVertexOut out;
    out.position = float4(p, 0.0, 1.0);
    out.uv = p * 0.5 + 0.5;
    out.aspect = (f.aspect_ratio > 0.01) ? f.aspect_ratio : 1.0;
    out.time = f.time;
    return out;
}

fragment float4 rosette_nowings_geometry_fragment(
    RosetteGeoVertexOut in [[stage_in]]
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

    // Plain clock driving the morph — no audio this session (§6 of the prompt).
    // TRIANGLE wave, not sine: a sinusoidal a(t) eases at the tight/loose extremes
    // (da/dt -> 0 at the turning points) — found live via motion_gate.sh, 82/299
    // frames read as near-frozen. A triangle wave has constant |da/dt| everywhere
    // except an instantaneous reversal at each extreme, matching §9.4's "servo-
    // driven, constant rate — any easing reads immediately as wrong."
    float x = in.time / kRosettePeriod;
    float tri = 2.0 * abs(x - floor(x + 0.5));   // period 1, linear ramp 0->1->0
    float aMorph = kRosetteAMin + (kRosetteAMax - kRosetteAMin) * tri;

    // The rosette figure — white / pale lavender, always (F3: colour is NOT indexical
    // on the figure; do not hue-cycle this element).
    float2 pf = float2(q.x, -q.y) / kRosetteRadius;   // figure space, y-up
    float d = rosetteDist(pf, aMorph) * kRosetteRadius;
    float core = exp(-(d * d) / (2.0 * kRosetteStrokeW * kRosetteStrokeW));
    float halo = exp(-(d * d) / (2.0 * kRosetteHaloW * kRosetteHaloW));
    float3 figureCol = mix(float3(1.0), float3(0.88, 0.85, 1.0), 0.30);
    col += figureCol * (1.15 * core + 0.35 * halo);

    // Mirrored coloured wings (F4) — saturated hue lives HERE, never on the figure.
    // Slow independent drift stands in for "hue changes between passages" (F3) with
    // no audio route wired this session.
    float hueT = in.time * 0.05;
    float3 leftHue  = 0.5 + 0.5 * cos(6.2831853 * (hueT + float3(0.0, 0.33, 0.67)));
    float3 rightHue = 0.5 + 0.5 * cos(6.2831853 * (hueT + 0.5 + float3(0.0, 0.33, 0.67)));
    float dLeftArc  = rosetteWingDist(q, -1.0, 48);
    float dRightArc = rosetteWingDist(q,  1.0, 48);
    float dLeftEll  = rosetteWingEllipseDist(q, -1.0);
    float dRightEll = rosetteWingEllipseDist(q,  1.0);
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
    // WHIT.0 task 5: wings intentionally suppressed for the without-wings comparison.

    // Opaque every frame — the film draws the figure complete each frame (FILM_NOTES
    // §4/§9.4), no accumulation. This fragment repaints every pixel, so `decay` below
    // has no visible effect (documented, not a bug).
    return float4(saturate(col), 1.0);
}

// Required by PresetLoader.makeDirectPrimaryPipeline for the library to compile at
// all — never invoked at runtime once the geometry overlay makes this a
// `strandsOnTop` preset (RenderPipeline+MVWarp.swift:138). Trivial fill.
fragment float4 rosette_nowings_fragment(RosetteGeoVertexOut in [[stage_in]]) {
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
