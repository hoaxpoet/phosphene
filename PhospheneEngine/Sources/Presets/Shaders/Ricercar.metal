// Ricercar.metal — Ricercar.3: per-section painterly MARK engine (the orchestra painting itself).
//
// Concept (D-176): Ricercar is the orchestra painting itself — each orchestral SECTION has a distinct
// painterly IDENTITY (colour + weight + texture + material), and the painting builds in sync with the
// music. Identity is the soul; sync is the second layer (Ricercar.5). Spirit of Fantasia, elegant +
// luminous on a LIGHT canvas — the elegant/luminous sibling of Skein (graceful composed strokes, not
// Pollock drip). RICERCAR_DESIGN §CONCEPT.
//
// Built on SKEIN's proven painterly mark machinery (FA #73 — reuse, don't reinvent): the canvas-hold
// marks-on-top mv_warp stack (identity warp + no decay + light-ground clear), the swept-capsule SDF
// stroke, and the 4-octave `perlin2d`-fBM ragged-edge perturbation — the things that already read as
// PAINT (Skein.metal:105/137/153). Ricercar reconfigures them: an ELEGANT composed path (graceful
// per-axis-incommensurate sweep, not Skein's wandering drift) + a per-SECTION material identity.
//
// Ricercar.3 is the gate-before-the-gate: does an elegant painterly stroke read on a light Fantasia
// canvas, and is per-section material (heavy-dark-gloopy bass vs fine-crisp-bright flute) visible?
// THREE sections, HAND-FED (closed-form f(features.time), Path A — no CPU state, no audio). The full
// five sections + audio sync are Ricercar.4/.5. Shared types + perlin2d come from the mv_warp preamble
// (no #include, like Skein.metal).

// ── Light canvas ground (paint-on-light; matches Ricercar.json marks.canvas_clear) ──────────────
constant float3 kRicGround = float3(0.93, 0.91, 0.86);   // warm near-white Fantasia canvas

// ── Per-section painterly IDENTITY (RICERCAR_DESIGN §CONCEPT; Ricercar.3 shows 3 of the 5) ──────
// Each row: colour · weight (radius) · texture (edge raggedness + AA softness) · region · gesture.
struct RicSection {
    float3 color;     // section colour family
    float  radius;    // WEIGHT — stroke half-width (basses broad, flutes fine)
    float  edgeAmp;   // TEXTURE — ragged-edge amplitude (high = smeared/gloopy, low = crisp)
    float  aaScale;   // TEXTURE — edge softness (thick matte paint = softer, fine crisp = tight)
    float  fbmScale;  // edge-noise frequency (fine sections get finer grain)
    float2 ctr;       // region centre (uv) — low/mid/high band
    float2 amp;       // sweep amplitude per axis
    float2 freq;      // sweep frequency per axis (incommensurate → graceful open curve; GESTURE speed)
    float2 ph;        // phase
};

// ── 2D capsule segment distance (Skein.metal:137, verbatim) ─────────────────────────────────────
static inline float ricSegDist(float2 p, float2 a, float2 b) {
    float2 pa = p - a;
    float2 ba = b - a;
    float  h  = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-9), 0.0, 1.0);
    return length(pa - ba * h);
}

// ── 4-octave perlin2d fBM ragged-edge noise (Skein.metal:153 `skein_fbm2`, verbatim) ───────────
static inline float ric_fbm2(float2 p) {
    const float2x2 rot = float2x2(0.80, 0.60, -0.60, 0.80);
    float amp = 1.0, sum = 0.0, norm = 0.0;
    for (int i = 0; i < 4; ++i) {
        sum  += amp * perlin2d(p);
        norm += amp;
        amp  *= 0.5;
        p     = rot * p * 2.0;
    }
    return sum / norm;   // ~[-1, 1]
}

// Elegant composed path: per-axis incommensurate sine sweep (graceful open curve, never jitter).
static inline float2 ricStrokePos(thread const RicSection& s, float t) {
    return float2(s.ctr.x + s.amp.x * sin(s.freq.x * t + s.ph.x),
                  s.ctr.y + s.amp.y * sin(s.freq.y * t + s.ph.y));
}

// Swept-capsule coverage of a section's recent stroke tail, with ragged section-textured edge.
static inline float ricStrokeCoverage(thread const RicSection& s, float2 q, float px, float t, float aspect) {
    const int   TAIL = 54;            // ~0.9 s of path redrawn each frame (accumulates on the held canvas)
    const float dt   = 1.0 / 60.0;
    float best = 1e9;
    float2 prevP = float2(0.0);
    for (int i = 0; i <= TAIL; ++i) {
        float2 uv = ricStrokePos(s, t - float(i) * dt);
        float2 P  = float2(uv.x * aspect, uv.y);     // aspect-corrected so the stroke width is isotropic
        if (i > 0) { best = min(best, ricSegDist(q, prevP, P)); }
        prevP = P;
    }
    float r = s.radius * (1.0 + s.edgeAmp * ric_fbm2(q * s.fbmScale));   // ragged edge (the painterly tell)
    return 1.0 - smoothstep(-px * s.aaScale, px * s.aaScale, best - r);
}

// ── Light ground fragment (descriptor `fragment_function`; held canvas is the canvas-clear) ─────
fragment float4 ricercar_fragment(
    VertexOut               in    [[stage_in]],
    constant FeatureVector& f     [[buffer(0)]],
    constant float*         fft   [[buffer(1)]],
    constant float*         wv    [[buffer(2)]],
    constant StemFeatures&  stems [[buffer(3)]]
) {
    return float4(kRicGround, 1.0);
}

// ── Canvas-hold: identity warp + NO decay (the painting persists + builds — Skein.metal:771) ────
MVWarpPerFrame mvWarpPerFrame(constant FeatureVector& f, constant StemFeatures& stems, constant SceneUniforms& s) {
    MVWarpPerFrame pf;
    pf.zoom = 1.0; pf.rot = 0.0; pf.decay = 1.0;   // NO DECAY — the composition holds + accumulates
    pf.warp = 0.0; pf.cx = 0.0; pf.cy = 0.0; pf.dx = 0.0; pf.dy = 0.0; pf.sx = 1.0; pf.sy = 1.0;
    pf.q1 = 0.0; pf.q2 = 0.0; pf.q3 = 0.0; pf.q4 = 0.0; pf.q5 = 0.0; pf.q6 = 0.0; pf.q7 = 0.0; pf.q8 = 0.0;
    return pf;
}

float2 mvWarpPerVertex(float2 uv, float rad, float ang, thread const MVWarpPerFrame& pf,
                       constant FeatureVector& f, constant StemFeatures& stems) {
    return uv;   // identity — the held canvas does not move (Skein canvas-hold)
}

// ── Marks-on-top overlay: the section strokes painting onto the held light canvas ───────────────
struct RicercarGeoVertexOut {
    float4 position [[position]];
    float2 uv;
    float  aspect;
    float  t;       // features.time, flat across the 3 verts (Path A — the vertex reads features@0)
};

vertex RicercarGeoVertexOut ricercar_geometry_vertex(
    uint vid [[vertex_id]],
    constant FeatureVector& f [[buffer(0)]]
) {
    float2 p = float2((vid == 2) ? 3.0 : -1.0, (vid == 1) ? 3.0 : -1.0);
    RicercarGeoVertexOut out;
    out.position = float4(p, 0.0, 1.0);
    out.uv       = p * 0.5 + 0.5;
    out.aspect   = (f.aspect_ratio > 0.01) ? f.aspect_ratio : 1.0;
    out.t        = f.time;
    return out;
}

fragment float4 ricercar_geometry_fragment(RicercarGeoVertexOut in [[stage_in]]) {
    float a = in.aspect;
    float2 q = float2(in.uv.x * a, in.uv.y);
    float px = max(fwidth(q.x), fwidth(q.y));
    float t = in.t;

    // Ricercar.3: three sections, hand-fed, each in its register-band with a distinct material.
    RicSection sections[3];
    // LOW — basses/cellos: deep indigo, HEAVY broad, gloopy/smeared, grave slow sweep (lower band)
    sections[0] = RicSection{ float3(0.20, 0.17, 0.55), 0.020, 0.42, 2.6, 52.0,
                              float2(0.50, 0.70), float2(0.34, 0.10), float2(0.18, 0.13), float2(0.0, 1.0) };
    // MID — violas/clarinets: warm amber, MEDIUM, soft-grained, flowing lyrical sweep (centre band)
    sections[1] = RicSection{ float3(0.82, 0.52, 0.13), 0.011, 0.26, 1.8, 70.0,
                              float2(0.50, 0.48), float2(0.36, 0.16), float2(0.26, 0.21), float2(2.0, 3.5) };
    // HIGH — flutes/piccolo: cool cyan, FINE feather-light, crisp/sparkling, quick darting (upper band)
    sections[2] = RicSection{ float3(0.16, 0.62, 0.72), 0.0055, 0.10, 1.2, 120.0,
                              float2(0.50, 0.28), float2(0.38, 0.12), float2(0.42, 0.55), float2(4.0, 0.5) };

    // OPAQUE compositing (the §colour-mud rule): topmost mark by coverage occludes — never average to mud.
    float  bestCover = 0.0;
    float3 bestCol   = float3(1.0);
    for (int s = 0; s < 3; ++s) {
        float cov = ricStrokeCoverage(sections[s], q, px, t, a);
        if (cov > bestCover) { bestCover = cov; bestCol = sections[s].color; }
    }
    return float4(bestCol, bestCover);
}
