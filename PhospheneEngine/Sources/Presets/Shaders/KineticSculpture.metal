// KineticSculpture.metal — Ray march preset: taut radiating wire sculpture.
//
// KSRB REBUILD (2026-07-19/20, KSRB.1). The previous geometry was an infinite
// periodic 3-axis rod grid (`ks_rep`, KS_CELL = 2.0). The concept-viability
// gate retired that form: a regular geometric grid is this preset's own
// documented ANTI-REFERENCE ("reads as engineering drawing, not sculpture" —
// docs/VISUAL_REFERENCES/kinetic_sculpture/README.md). The rebuild takes the
// hero reference instead: Lippold, *Flight* (1963) — cones of taut strands
// radiating between hubs, tension as the visual signature.
// Design: docs/presets/KINETIC_SCULPTURE_DESIGN.md.
//
// Geometry — THREE INTERPENETRATING FAN SYSTEMS (Matt's call, 2026-07-20).
//   A first pass built ONE bicone (two hubs + a waist ring). It rendered, but
//   read as a closed lantern/birdcage rather than sculpture. The references are
//   more open: ref 02 (*Wings of Welcome*) is rods at distinct angles passing
//   THROUGH and PAST each other to compose one readable form. So each system is
//   an independent hub-pair with its own centre, axis, scale and anchor ring,
//   placed so the fans interpenetrate. The waist tension ring is KEPT but
//   DEMOTED (system 0 only, thin gauge) — it earns its place as the third
//   material's structural home without belting the silhouette.
//   Per-member hash jitter varies anchor angle/radius/height and strand gauge
//   so no two members are identical (the README meso-cascade requirement).
//
// Thin-strand feasibility (spike, 2026-07-19 — the load-bearing prior):
//   Sphere-tracing thin SDFs was expected to be pathological. Measured on the
//   exact production march loop it is NOT: max 45-53 of 128 steps, 0% budget
//   exhaustion, silhouette legible to sub-pixel radius — the relative hit
//   epsilon (0.001*t) implicitly fattens sub-pixel features and the 0.002
//   min-step floor prevents tiny-step stalls. The one real defect is
//   stipple/shimmer on steeply foreshortened strands below ~2px. The spike's
//   two equivalent fixes were an emissive glow core (needs per-ray min-distance
//   tracking = a shared-march-loop change) or DISTANCE-FATTEN to ~2px (pure
//   sceneSDF math). This ships the latter: no engine surface is touched.
//   Confirmed in the production pipeline at KSRB.1 — strands render continuous.
//
// Cost control: a whole-sculpture bounding sphere skips the member loops for
// far march steps, and each system carries its OWN bounding sphere — because
// the systems are offset, a step near the sculpture still usually evaluates
// only one of them. Without these the 100+ capsule unions would be
// unaffordable inside sceneSDF.
//
// Materials (three, all structurally motivated — KSRB.2 does the full craft
// pass: anisotropic streak, fbm8 chrome roughness, frost normal perturbation,
// and the gallery-interior IBL that chrome NEEDS in order to read as chrome
// rather than dull plastic — README §4.1 / ref 07):
//   Polished Chrome  — the radiating strands (the hero members).
//   Brushed Aluminum — the demoted waist tension ring on system 0.
//   Frosted Glass    — the hub spheres the strands converge into.
//
// Audio routing: NOT WIRED YET — KSRB.3. The rebuild's musical role (Matt
// signed off 2026-07-19) is: sustained energy -> cone splay/tension
// (continuous, Layer 1, deviation primitives per D-026); bar downbeat on the
// cached BeatGrid -> a bounded hub-to-tip luminance shimmer (Layer 4 accent,
// D-157; NOT raw beat_bass — Inc 3.5.4.5 documented a cooldown phase-lock
// issue on live onsets for this preset). Until KSRB.3 the sculpture turns on a
// slow wall-clock orbit, which also satisfies the never-static silence floor
// (D-019 / D-037): geometry stays fully present and lit at zero energy.
//
// Preamble provides: sd_capsule, sd_sphere, op_union, op_smooth_union.
// Pipeline: ray_march -> post_process (G-buffer deferred + bloom/ACES).

// ── Sculpture constants ──────────────────────────────────────────────────────

constant int   KS_SYSTEMS   = 3;       // interpenetrating hub-pair fans
constant int   KS_ANCHORS   = 18;      // anchors per system; 2x this many strands
constant float KS_HUB_Y     = 1.15f;   // hub offset along the system axis (unit scale)
constant float KS_RING_R    = 0.95f;   // anchor-ring radius (unit scale)
constant float KS_HUB_R     = 0.075f;  // frosted-glass hub sphere radius
constant float KS_STRAND_R  = 0.006f;  // base strand gauge — deliberately thin
constant float KS_RING_R_W  = 0.005f;  // demoted tension-ring gauge
constant float KS_BOUND_R   = 1.65f;   // whole-sculpture bounding sphere
constant float KS_SYS_BOUND = 1.35f;   // per-system bound (scaled by system scale)
constant float KS_ORBIT     = 0.11f;   // slow orbit, radians/second

/// Distance-fatten coefficient. Holds a strand at >= ~2 px of screen width:
/// at 1080p / 70 deg fov one pixel subtends ~0.00113 rad, so a 2 px DIAMETER
/// needs world RADIUS ~= 0.00113 * t. Below that width the march stipples
/// foreshortened strands (the spike's only real defect).
constant float KS_FATTEN    = 0.0012f;

/// Per-system placement. Centres are offset and axes tilted so the three fans
/// pass through and past one another (ref 02) instead of nesting concentrically.
/// Axes are pre-normalised — `normalize()` is not a constant initialiser.
constant float3 KS_SYS_C[3] = {
    float3( 0.00f,  0.00f,  0.00f),
    float3( 0.45f,  0.15f, -0.20f),
    float3(-0.40f, -0.10f,  0.25f)
};
constant float3 KS_SYS_A[3] = {
    float3( 0.0000f, 1.0000f, 0.0000f),
    float3( 0.9126f, 0.3549f, 0.2028f),
    float3(-0.2982f, 0.5963f, 0.7454f)
};
constant float  KS_SYS_S[3] = { 1.00f, 0.75f, 0.62f };

// ── Helpers ──────────────────────────────────────────────────────────────────

/// Cheap deterministic hash in [0,1). Meso variation only, never shading —
/// identical every frame, so the form is stable.
static inline float ks_hash11(float n) {
    return fract(sin(n * 127.1f) * 43758.5453f);
}

/// Rotation about the vertical axis (the slow gallery orbit).
static inline float3 ks_rotY(float3 p, float a) {
    float c = cos(a), s = sin(a);
    return float3(c * p.x - s * p.z, p.y, s * p.x + c * p.z);
}

/// Orthonormal basis spanning the plane perpendicular to unit axis `u`.
static inline void ks_basis(float3 u, thread float3& v, thread float3& w) {
    float3 h = (abs(u.y) < 0.9f) ? float3(0.0f, 1.0f, 0.0f) : float3(1.0f, 0.0f, 0.0f);
    v = normalize(cross(u, h));
    w = cross(u, v);
}

/// Anchor `i` on system `k`'s ring, with per-anchor jitter so the fan is
/// irregular rather than lathe-perfect (the README anti-reference is regularity).
static inline float3 ks_anchor(int k, int i, float3 u, float3 v, float3 w) {
    float fi   = float(i) + float(k) * 37.0f;   // decorrelate systems
    float base = 6.2831853f * float(i) / float(KS_ANCHORS);
    float a    = base + (ks_hash11(fi) - 0.5f) * 0.20f;
    float rad  = KS_RING_R * (0.88f + 0.24f * ks_hash11(fi + 17.0f));
    float off  = (ks_hash11(fi + 41.0f) - 0.5f) * 0.10f;   // off-plane wobble
    float3 local = rad * (cos(a) * v + sin(a) * w) + off * u;
    return KS_SYS_C[k] + KS_SYS_S[k] * local;
}

/// Per-strand gauge multiplier — no two members the same cross-section.
static inline float ks_gauge(float fi) {
    return 0.72f + 0.65f * ks_hash11(fi + 91.0f);
}

// ── Sub-SDFs (re-evaluated in sceneMaterial for material assignment) ──────────

/// One system's bicone fan: every anchor strung taut to both of its hubs.
/// Returns the (valid, conservative) bound distance when `p` is outside this
/// system's bounding sphere, so callers can `min()` without a special case.
static inline float ks_sdSystem(float3 p, int k, float r) {
    float3 c = KS_SYS_C[k];
    float  s = KS_SYS_S[k];

    float dSysBound = length(p - c) - KS_SYS_BOUND * s;
    if (dSysBound > 0.05f) { return dSysBound; }

    float3 u = KS_SYS_A[k];
    float3 v, w;
    ks_basis(u, v, w);

    float3 hubT = c + u * (KS_HUB_Y * s);
    float3 hubB = c - u * (KS_HUB_Y * s);

    float d = 1e9f;
    for (int i = 0; i < KS_ANCHORS; ++i) {
        float3 a  = ks_anchor(k, i, u, v, w);
        float  rg = r * ks_gauge(float(i) + float(k) * 37.0f);
        d = min(d, sd_capsule(p, hubT, a, rg));
        d = min(d, sd_capsule(p, hubB, a, rg));
    }
    return d;
}

/// All three fans.
static inline float ks_sdStrands(float3 p, float r) {
    float d = 1e9f;
    for (int k = 0; k < KS_SYSTEMS; ++k) {
        d = min(d, ks_sdSystem(p, k, r));
    }
    return d;
}

/// The demoted waist tension ring — system 0 only, adjacent anchors chorded.
static inline float ks_sdRing(float3 p, float r) {
    float3 u = KS_SYS_A[0];
    float3 v, w;
    ks_basis(u, v, w);
    float d = 1e9f;
    for (int i = 0; i < KS_ANCHORS; ++i) {
        float3 a = ks_anchor(0, i, u, v, w);
        float3 b = ks_anchor(0, (i + 1) % KS_ANCHORS, u, v, w);
        d = min(d, sd_capsule(p, a, b, r));
    }
    return d;
}

/// Every system's hub spheres.
static inline float ks_sdHubs(float3 p) {
    float d = 1e9f;
    for (int k = 0; k < KS_SYSTEMS; ++k) {
        float3 c  = KS_SYS_C[k];
        float  s  = KS_SYS_S[k];
        float3 u  = KS_SYS_A[k];
        float  hr = KS_HUB_R * s;
        d = min(d, sd_sphere(p - (c + u * (KS_HUB_Y * s)), hr));
        d = min(d, sd_sphere(p - (c - u * (KS_HUB_Y * s)), hr));
    }
    return d;
}

/// Screen-space-aware member radius (the spike's shimmer fix).
static inline float ks_fattened(float3 p, float3 camPos, float base) {
    float t = length(p - camPos);
    return max(base, KS_FATTEN * t);
}

// ── Scene SDF ────────────────────────────────────────────────────────────────

float sceneSDF(float3 p,
               constant FeatureVector& f,
               constant SceneUniforms& s,
               constant StemFeatures& stems,
               texture2d<float> ferrofluidHeight) {
    (void)ferrofluidHeight;  // V.9 Session 4.5b slot-10; Ferrofluid Ocean only.
    (void)stems;             // Audio routing lands in KSRB.3.

    // Whole-sculpture bounding sphere. Most march steps are far outside it, and
    // the returned bound distance is a valid (conservative) lower bound on the
    // distance to the contents, so sphere tracing stays correct.
    float dBound = length(p) - KS_BOUND_R;
    if (dBound > 0.05f) { return dBound; }

    // Slow wall-clock orbit. Deliberately NOT driven by accumulated audio time:
    // the retired grid twisted on an audio CLOCK, which reads as motion that
    // merely co-occurs with the music rather than answering it. Real audio
    // coupling is KSRB.3; this keeps the form alive at silence (D-019/D-037).
    float3 rp = ks_rotY(p, f.time * KS_ORBIT);

    float rStrand = ks_fattened(p, s.cameraOriginAndFov.xyz, KS_STRAND_R);
    float rRing   = ks_fattened(p, s.cameraOriginAndFov.xyz, KS_RING_R_W);

    float dStrands = ks_sdStrands(rp, rStrand);
    float dRing    = ks_sdRing(rp, rRing);
    float dHubs    = ks_sdHubs(rp);

    // Strands melt very slightly into the hubs so convergence reads as a cast
    // joint rather than lines clipping a sphere.
    float dJoined = op_smooth_union(dStrands, dHubs, 0.035f);
    return op_union(dJoined, dRing);
}

// ── Scene Material ───────────────────────────────────────────────────────────

void sceneMaterial(float3 p,
                   int matID,
                   constant FeatureVector& f,
                   constant SceneUniforms& s,
                   constant StemFeatures& stems,
                   thread float3& albedo,
                   thread float& roughness,
                   thread float& metallic,
                   thread int& outMatID,
                   constant LumenPatternState& lumen) {
    (void)outMatID;  // 0 = standard dielectric; all three dispatch Cook-Torrance.
    (void)lumen;     // LM.2 / D-LM-buffer-slot-8 — Lumen Mosaic only.
    (void)stems;     // KSRB.3.

    // Apply the SAME orbit as sceneSDF before classifying. (The retired grid
    // skipped this correction because its deformation phase was unavailable
    // here; f.time is available, so the boundary is exact rather than
    // "close enough".)
    float3 rp = ks_rotY(p, f.time * KS_ORBIT);

    float rStrand = ks_fattened(p, s.cameraOriginAndFov.xyz, KS_STRAND_R);
    float rRing   = ks_fattened(p, s.cameraOriginAndFov.xyz, KS_RING_R_W);

    float dStrands = ks_sdStrands(rp, rStrand);
    float dRing    = ks_sdRing(rp, rRing);
    float dHubs    = ks_sdHubs(rp);

    if (dHubs <= dStrands && dHubs <= dRing) {
        // Frosted Glass hub — diffusing, ice-neutral, low metallic.
        albedo    = float3(0.82f, 0.88f, 0.95f);
        roughness = 0.26f;
        metallic  = 0.04f;
    } else if (dRing < dStrands) {
        // Brushed Aluminum tension ring — matte-warm, high metallic.
        // KSRB.2 adds the anisotropic streak grain that makes it read brushed
        // rather than painted (the README §4.2 failure mode).
        albedo    = float3(0.71f, 0.72f, 0.76f);
        roughness = 0.28f;
        metallic  = 0.90f;
    } else {
        // Polished Chrome strand — near-mirror. Reads as chrome only against a
        // detailed, multi-lit environment to reflect (README §4.1 / ref 07).
        // The shared ray-march path can't yet provide that (single light +
        // uniform grey IBL → the strand reflects flat grey = "putty"), so at
        // this KSRB.1 baseline the chrome is deliberately UNDER-served. Phase
        // RMENV (multi-light + gallery IBL + dark background) is the fix, and
        // KSRB.2 consumes it. See docs/RENDER_ENVIRONMENT_SCOPING.md.
        albedo    = float3(0.86f, 0.87f, 0.90f);
        roughness = 0.06f;
        metallic  = 1.0f;
    }
}
