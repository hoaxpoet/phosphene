// Rosette.metal — John Whitney Sr.'s *Arabesque* (1975) morphing emblem.
//
// WHIT.1c: registered from the WHIT.0 look-spike (docs/ENGINEERING_PLAN.md Phase WHIT),
// verdict GO. Design record: docs/presets/ROSETTE_DESIGN.md. References:
// docs/VISUAL_REFERENCES/rosette/. certified: false.
//
// WHIT.1d/WHIT.1d-2: harmony coupling, all five of WHITNEY_PROGRAM.md's proposed routes
// (figure_tightness<-tonalConsonance, stroke_presence<-bassDev, morph_floor_rate<-
// midAttRel, morph_position<-tonalPhaseFifths, symmetry_order_step<-harmonicFlux).
// BUG-103/BUG-104: aspect-ratio wing placement and a curve-continuity branch-lock bug,
// both fixed live. WHIT.2a: symmetry-order steps interpolate smoothly (RosetteState),
// not an instant jump.
//
// WHIT.2b: converted from a flat 2D `direct + mv_warp` marks-on-top preset to a
// `ray_march` preset — Matt, 2026-08-26, right after seeing the fixed 2D version:
// "Still too basic... The final preset should also be 3D, not 2D, to take better
// advantage of the latest Apple processors." The figure and wing arcs are now genuine
// swept 3D TUBES with real depth, normals, and PBR lighting (Cook-Torrance + IBL + AO +
// screen-space shadows) via the engine's existing ray-march pipeline — the same one
// Volumetric Lithograph/Lumen Mosaic/Ferrofluid Ocean run on (D-021 sceneSDF/sceneMaterial
// contract). This is the established "exploit Apple Silicon" answer already used by the
// catalog's more advanced presets, not an invented technique.
//
// Two-term epicycle z(t) = e^{it} + a·e^{-i(n-1)t} reproduces the film's tangle/petals/
// star/pentagon family (ROSETTE_DESIGN.md §4.1: hits circle/cusped-star/petals/petals-
// with-loops/tangle; misses a true STRAIGHT-edged pentagon — accepted limitation, do not
// add a third harmonic term without Matt's sign-off). `rosetteCurve` is unchanged from the
// 2D version; `rosetteDist` was rewritten in 3D (WHIT.2b, Matt: "fidelity is poor - lines
// are really jagged") from the 2D version's coarse-then-bisect branch search to a dense
// point-to-segment polyline scan — see rosetteDist's own comment for the full diagnosis.
// The 3D tube SDF wraps this 2D distance-to-curve computation: for a 3D point `p` with the
// curve lying in the z=0 plane, `tubeSDF = sqrt(rosetteDist(p.xy)^2 + p.z^2) - tubeRadius`.
// Validated as a prototype first (agent-built, 3 render/look iterations) before this
// production port — the original BUG-104 fix (no gaps at self-crossings) still holds under
// the new distance search, re-verified by test_rosette_curveIsContinuousAtHighA.
//
// The former `aspect`-scaling hack for wing placement (BUG-103) no longer exists — world-
// space positions are aspect-independent; the ray-march camera's own FOV/projection
// handles arbitrary window sizes the same way every other ray-march preset already does.

#include <metal_stdlib>
using namespace metal;

// FeatureVector / StemFeatures / SceneUniforms / RosetteUniforms / sceneSDF / sceneMaterial
// forward declarations are in the shared ray-march preamble PresetLoader prepends ahead of
// every ray-march preset's .metal source — no #include, matching every other ray-march
// preset file in this repo (VolumetricLithograph.metal, LumenMosaic.metal, FerrofluidOcean.metal).

constant float kRosetteAMin     = 0.05;    // tightest state (near-pentagon), task 2 CPU sweep
constant float kRosetteAMax     = 1.80;    // loosest state (tangle), task 2 CPU sweep
constant float kRosettePeriod   = 30.0;    // seconds per tighten/unravel cycle (rosette_build.png spans 30s)
constant float kRosetteRadius   = 0.30;    // figure half-extent, world units
// Dense-polyline sample count for the figure's nearest-point search (WHIT.2b — see
// rosetteDist's comment for why this replaced the earlier coarse+bisect search). A
// polyline's rounded joints are individually smooth, but each STRAIGHT segment cuts the
// true curve's arc — visible live as banding/faceting on the swept tube wherever chord
// deviation approaches the tube radius (0.006 world units). Measured at 150 AND 600: the
// two renders were pixel-identical at the same extreme zoom used to diagnose the original
// jaggedness. Measured at 110 and 70: BOTH still showed visible faceting on the same
// outer arc — the quality floor sits close to 150, not comfortably below it, so segment
// count is not a viable lever for the PresetFrameBudgetTests margin; see
// `kRosetteWingBoundRadius` for where that margin actually came from instead.
constant int kRosetteCurveSegments = 150;

// The epicycle, normalised to unit-ish radius regardless of `a` (F2: the emblem's overall
// SIZE stays roughly constant through the morph; only the character changes, not the
// scale). `n` is dynamic (WHIT.1d-2/WHIT.2a) — the aMin/aMax calibration was tuned
// against n=5 (task 2's CPU sweep) and is reused as-is for the stepped orders (4, 6): a
// reasonable approximation, not re-swept per n.
static float2 rosetteCurve(float t, float a, float n) {
    float2 z1 = float2(cos(t), sin(t));
    float t2 = -(n - 1.0) * t;
    float2 z2 = float2(cos(t2), sin(t2));
    return (z1 + a * z2) / (1.0 + a);
}

// Point-to-SEGMENT distance (capsule SDF core) — see rosetteWingDist below, whose exact
// pattern this section reuses for the main figure.
static float segDist(float2 p, float2 a, float2 b) {
    float2 pa = p - a, ba = b - a;
    float t = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-6), 0.0, 1.0);
    return length(pa - ba * t);
}

// Nearest-point-on-curve distance via a dense polyline (min distance to any of
// kRosetteCurveSegments segments) — no closed-form SDF exists for a two-term epicycle
// once it self-intersects, and no numerical root-find is either, WHIT.2b found live.
//
// History: BUG-104 (2D, "Lines do not connect. The motion is all wrong.") used a
// coarse-sample-then-bisect search, fixed there by finding multiple candidate branches
// before refining each. That fix carried into the first 3D port cleanly — no GAPS at
// self-crossings — but Matt's next live look ("fidelity is poor - lines are really
// jagged") surfaced a DIFFERENT defect the 2D version's flat, non-lit rendering never
// exposed: per-pixel finite-difference NORMALS amplify tiny non-smoothness in the
// underlying distance field into visible shading facets, and the coarse+bisect search
// is not smooth enough at the eps=0.001 scale ray-marching normals need — confirmed by
// isolating an outer petal loop with NO nearby self-crossing (ruling out the branch-
// seam theory) and by comparing directly against the wing arcs, which already use this
// exact dense-polyline technique and render perfectly smooth in the same frame. Adopted
// the wing's proven approach verbatim (FA #73/#65 — don't re-derive a working
// technique already sitting in the same file) rather than continuing to patch the
// numerical search (two patches — a smooth-min branch blend, then more bisection
// precision — were tried first and neither fixed it, the FA #64 threshold for
// switching from guessing to using an existing reference).
static float rosetteDist(float2 p, float a, float n) {
    float bestD = 1e9;
    float2 prev = rosetteCurve(0.0, a, n);
    for (int i = 1; i <= kRosetteCurveSegments; i++) {
        float t = 2.0 * M_PI_F * float(i) / float(kRosetteCurveSegments);
        float2 cur = rosetteCurve(t, a, n);
        bestD = min(bestD, segDist(p, prev, cur));
        prev = cur;
    }
    return bestD;
}

// F4: mirrored coloured wing arcs, each carrying a small ellipse (`ARABESQUE_FILM_NOTES`
// F4). A shallow bowed arc + a small loop near its lower end; `side` = -1 (left) / +1
// (right, mirrored). WHIT.2b: no more `aspect` parameter (BUG-103's fix) — world-space
// positions are camera/aspect-independent by construction in the ray-march pipeline.
static float2 rosetteWingArc(float s, float side) {
    float x = side * (0.62 + 0.05 * sin(s * M_PI_F));
    float y = mix(0.85, -0.85, s);
    return float2(x, y);
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
    float2 c = float2(side * 0.67, -0.30);
    float2 q = (p - c) / float2(0.055, 0.09);
    return (length(q) - 1.0) * 0.07;
}

// ── WHIT.2b: 3D tube SDFs ────────────────────────────────────────────────────────────
//
// For a planar curve C(t) lying in the z=0 plane, the SDF of a tube of radius `r` swept
// around it is `sqrt(dist2D(p.xy, C)^2 + p.z^2) - r` — the 2D nearest-point distance and
// the out-of-plane offset combine as a right triangle's hypotenuse (Pythagorean tube).
// Reuses `rosetteDist`/`rosetteWingDist`/`rosetteWingEllipseDist` completely unmodified.
constant float kRosetteFigureTubeRadius = 0.020;
constant float kRosetteWingTubeRadius   = 0.014;
constant float kRosetteWingEllTubeRadius = 0.010;

// `rosetteCurve`'s magnitude is <= 1 in pf-space for every t/a (triangle inequality:
// |z1 + a*z2| <= |z1| + a|z2| = 1 + a, divided by the curve's own (1+a) normaliser) —
// so the whole figure tube lies within a sphere of exactly this radius (curve extent
// kRosetteRadius=0.3 + tube radius) centred at the origin. A bounding-sphere distance
// is a valid SDF LOWER BOUND for anything inside it (sphere tracing can never overshoot
// on it) and is O(1) instead of the exact search's O(kRosetteCurveSegments) — PERF fix,
// WHIT.2b: PresetFrameBudgetTests measured 150.6 ms/frame at 1080p (14.8x the median,
// over the 60 ms ceiling) before this, because the march loop ran the full dense-polyline
// scan on every step of every pixel, including the ~90% of the frame that is empty
// background far from the small figure.
//
// `kRosetteFigureBoundMargin` is NOT optional precision — the curve reaches exactly
// this bounding radius at t=0 for every `a` (the same identity that makes the bound
// tight), so the bound is TANGENT to the true surface, not merely enclosing it. Returning
// the raw bound near that tangent point reads as a genuine hit to the march loop's
// relative hit epsilon (`d < 0.001 * t`, ~0.002 at this scene's camera distance) —
// rendering a false, audio-INDEPENDENT sphere silhouette that swallowed every
// aMorph/rotation/symmetry difference RosetteRayMarchTests measures (found live: all
// three coupling tests collapsed to near-zero diffs with a bare `boundD > 0.0` cutoff).
// The margin (15x that epsilon) keeps every value the cheap branch returns comfortably
// out of hit range; only the thin shell within it falls through to the exact search.
constant float kRosetteFigureBoundRadius = 0.32;
constant float kRosetteFigureBoundMargin = 0.03;

static float rosetteFigureTubeSDF(float3 p, float a, float n) {
    float boundD = length(p) - kRosetteFigureBoundRadius;
    if (boundD > kRosetteFigureBoundMargin) {
        return boundD;
    }
    float2 pf = p.xy / kRosetteRadius;
    float d2D = rosetteDist(pf, a, n) * kRosetteRadius;
    return sqrt(d2D * d2D + p.z * p.z) - kRosetteFigureTubeRadius;
}
// Same bounding-sphere early-out as the figure (see `kRosetteFigureBoundRadius`'s
// comment for the full rationale and the tangency hazard it was built around). The wing
// arc's OWN endpoints (s=0/1) sit exactly `0.85` from `(side*0.62, 0)` — the same
// tangency case, so this needs the identical safety margin, not a bare `> 0.0`.
constant float kRosetteWingBoundRadius = 0.865;
constant float kRosetteWingBoundMargin = 0.03;

static float rosetteWingTubeSDF(float3 p, float side) {
    float2 center = float2(side * 0.62, 0.0);
    float boundD = length(float3(p.xy - center, p.z)) - kRosetteWingBoundRadius;
    if (boundD > kRosetteWingBoundMargin) {
        return boundD;
    }
    float d2D = rosetteWingDist(p.xy, side, 48);
    return sqrt(d2D * d2D + p.z * p.z) - kRosetteWingTubeRadius;
}
static float rosetteWingEllTubeSDF(float3 p, float side) {
    float d2D = rosetteWingEllipseDist(p.xy, side);
    return sqrt(d2D * d2D + p.z * p.z) - kRosetteWingEllTubeRadius;
}

// Shared tighten/unravel + rotation math — identical logic to the 2D version, called from
// both sceneSDF (geometry needs it) and sceneMaterial (presence/hue need the same clock).
struct RosetteMorphState {
    float aMorph;
    float rotS, rotC;
};
static RosetteMorphState rosetteMorphState(constant FeatureVector& f, constant RosetteUniforms& rosette) {
    // figure_tightness <- tonalConsonance (continuous). TONAL.2b's 1000-track calibration
    // (WHITNEY_PROGRAM.md §5.2): floor 0.05, corpus MEDIAN 0.117, p99 0.32. A sqrt curve on
    // the normalised band lands the median at ~0.50 (linear/smoothstep would put it at
    // ~0.15 of the tightness range — explicitly the failure mode §5.2 warns about).
    float c01 = saturate((f.tonal_consonance - 0.05) / (0.32 - 0.05));
    float tight01 = sqrt(c01);
    float aHarmony = mix(kRosetteAMax, kRosetteAMin, tight01);

    // Plain clock — the tighten/unravel floor when there is little/no tonal signal.
    // TRIANGLE wave (constant |da/dt|, not sinusoidal easing — §9.4, found live at
    // WHIT.0 that easing reads as "frozen" near the extremes).
    // morph_floor_rate <- midAttRel (continuous): scales the clock's rate.
    float floorRateMul = clamp(1.0 + 0.6 * f.mid_att_rel, 0.4, 1.8);
    float x = (f.time * floorRateMul) / kRosettePeriod;
    float tri = 2.0 * abs(x - floor(x + 0.5));
    float aClock = kRosetteAMin + (kRosetteAMax - kRosetteAMin) * tri;

    // Harmony SETS the position; the clock is demoted to the floor drift (the Nacre
    // lesson, §5.3). Consonance's own analyzer floor (0.05, width 0.03) is the natural
    // presence gate.
    float presence = smoothstep(0.02, 0.08, f.tonal_consonance);
    float aMorph = mix(aClock, aHarmony, presence);

    // morph_position <- tonalPhaseFifths (WHIT.1d-2): a rotation of the figure only.
    // `rosette.smoothedFifths` is already circularly smoothed (D-209) by RosetteState.
    RosetteMorphState out;
    out.aMorph = aMorph;
    out.rotS = sin(rosette.smoothedFifths);
    out.rotC = cos(rosette.smoothedFifths);
    return out;
}

// ── Scene SDF ─────────────────────────────────────────────────────────────────────────

float sceneSDF(float3 p,
               constant FeatureVector& f,
               constant SceneUniforms& s,
               constant StemFeatures& stems,
               constant RosetteUniforms& rosette,
               texture2d<float> ferrofluidHeight) {
    (void)s;
    (void)stems;
    (void)ferrofluidHeight;

    RosetteMorphState morph = rosetteMorphState(f, rosette);
    // Rotate the FIGURE's sample point only — wings stay fixed (keeps D-217's frame).
    float2 pRot = float2(morph.rotC * p.x - morph.rotS * p.y, morph.rotS * p.x + morph.rotC * p.y);
    // symmetry_order_step <- harmonicFlux: `rosette.symmetryN` is RosetteState's smoothly-
    // interpolating held order (WHIT.2a) — never an instant jump, never flickers per-beat.
    float figureD = rosetteFigureTubeSDF(float3(pRot, p.z), morph.aMorph, rosette.symmetryN);

    float leftWingD  = rosetteWingTubeSDF(p, -1.0);
    float rightWingD = rosetteWingTubeSDF(p,  1.0);
    float leftEllD   = rosetteWingEllTubeSDF(p, -1.0);
    float rightEllD  = rosetteWingEllTubeSDF(p,  1.0);

    return min(figureD, min(min(leftWingD, rightWingD), min(leftEllD, rightEllD)));
}

// ── Scene Material ───────────────────────────────────────────────────────────────────

void sceneMaterial(float3 p,
                   int matID,
                   constant FeatureVector& f,
                   constant SceneUniforms& s,
                   constant StemFeatures& stems,
                   thread float3& albedo,
                   thread float& roughness,
                   thread float& metallic,
                   thread int& outMatID,
                   constant LumenPatternState& lumen,
                   constant RosetteUniforms& rosette) {
    (void)matID;
    (void)s;
    (void)stems;
    (void)lumen;
    outMatID = 0;   // standard Cook-Torrance dielectric path (matches VolumetricLithograph's simplest case)

    // Re-derive which sub-shape `p` (the ray hit) belongs to — the standard ray-march
    // multi-material pattern: recompute each candidate's distance at the hit point and
    // pick the material of the winner. MUST apply the same rotation sceneSDF used, or the
    // classification misaligns with the actual rendered (rotated) figure geometry — this
    // is why `rosette` (not a placeholder) is threaded all the way into sceneMaterial too.
    RosetteMorphState morph = rosetteMorphState(f, rosette);

    float leftWingD  = rosetteWingTubeSDF(p, -1.0);
    float rightWingD = rosetteWingTubeSDF(p,  1.0);
    float leftEllD   = rosetteWingEllTubeSDF(p, -1.0);
    float rightEllD  = rosetteWingEllTubeSDF(p,  1.0);
    float wingD = min(min(leftWingD, rightWingD), min(leftEllD, rightEllD));

    float2 pRot = float2(morph.rotC * p.x - morph.rotS * p.y, morph.rotS * p.x + morph.rotC * p.y);
    float figureD = rosetteFigureTubeSDF(float3(pRot, p.z), morph.aMorph, rosette.symmetryN);

    if (figureD <= wingD) {
        // The rosette figure — white / pale lavender, always (F3: colour is NOT
        // indexical on the figure; do not hue-cycle this element).
        albedo = mix(float3(1.0), float3(0.88, 0.85, 1.0), 0.30);
        roughness = 0.30;
        metallic  = 0.0;
        // stroke_presence <- bassDev (continuous, D-026 deviation primitive — never an
        // absolute threshold, FA #31). In the 2D version this swelled a Gaussian glow's
        // brightness; in 3D the equivalent is a modest emissive/albedo lift so a bass
        // transient reads as the tube "catching more light", bounded so a quiet passage
        // never fully extinguishes it.
        float presenceBoost = 1.0 + 0.35 * max(0.0, f.bass_dev);
        albedo = saturate(albedo * presenceBoost);
    } else {
        // Mirrored coloured wings (F4) — saturated hue lives HERE, never on the figure.
        // Slow independent drift stands in for "hue changes between passages" (F3), same
        // as the 2D version — no audio route wired for wing hue.
        bool isLeft = (leftWingD <= rightWingD && leftWingD <= leftEllD && leftWingD <= rightEllD)
                   || (leftEllD  <= rightWingD && leftEllD  <= rightEllD && leftEllD <= leftWingD);
        float hueT = f.time * 0.05;
        float3 hue = isLeft
            ? 0.5 + 0.5 * cos(6.2831853 * (hueT + float3(0.0, 0.33, 0.67)))
            : 0.5 + 0.5 * cos(6.2831853 * (hueT + 0.5 + float3(0.0, 0.33, 0.67)));
        albedo = saturate(hue);
        roughness = 0.35;
        metallic  = 0.0;
    }
}
