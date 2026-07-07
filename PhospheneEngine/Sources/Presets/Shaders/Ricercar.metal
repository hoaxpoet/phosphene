// Ricercar.metal — IFC.6: per-section painterly MARK engine, driven by REAL instrument-family capture.
//
// Concept (D-176): Ricercar is the orchestra painting itself — each orchestral SECTION has a distinct
// painterly IDENTITY (colour + weight + texture + material), and the painting builds in sync with the
// music. Identity is the soul; sync is the second layer. Spirit of Fantasia, elegant + luminous on a
// LIGHT canvas — the elegant/luminous sibling of Skein (graceful composed strokes, not Pollock drip).
// RICERCAR_DESIGN §CONCEPT.
//
// Built on SKEIN's proven painterly mark machinery (FA #73 — reuse, don't reinvent): the canvas-hold
// marks-on-top mv_warp stack (identity warp + no decay + light-ground clear), the swept-capsule SDF
// stroke, and the 4-octave `perlin2d`-fBM ragged-edge perturbation — the things that already read as
// PAINT (Skein.metal:105/137/153). Ricercar reconfigures them: an ELEGANT composed path (graceful
// per-axis-incommensurate sweep, not Skein's wandering drift) + a per-SECTION material identity.
//
// IFC.6 — DRIVE-LAYER SWAP (D-177). Ricercar.3's THREE hand-fed sections (closed-form f(time), no audio)
// are replaced by FIVE sections activated by the real instrument-family capture (StemFeatures floats
// 48–55, the preview-clip PANNs sweep sampled by playback position): each section paints only while its
// family is sounding above its own running mean. Per Matt (IFC.6 product call):
//   • FIVE sections: strings split into LOW-strings + HIGH-strings by register (the 6-band energy split
//     WITHIN the strings family — a register proxy, since PANNs is family-level not cello-vs-violin),
//     plus brass and woodwinds. One family's dev partitioned across its two register sections sums to
//     the family dev → the two string sections TRADE by register, never double (FA #67).
//   • PERCUSSION = sparkle accents (bright flecks on hits), NOT a weaving line — percussion is transient.
// DRIVE OFF *_activity_dev, NEVER the *_activity absolutes (FA #31 — brass absolute saturates 0.4–0.75
// across a whole ensemble; only dev surfaces the moment-to-moment lead, proven live IFC.5). The FLOOR
// (0.04) and per-family SATURATION points below are measured from the IFC.6 dumper traces on the
// orchestral corpus (Sym5 / Gran Partita / Clarinet Concerto), NOT guessed — see RICERCAR_DESIGN §IFC.6.
//
// Shared types (FeatureVector, StemFeatures) + perlin2d come from the mv_warp preamble (no #include,
// like Skein.metal). The marks VERTEX reads live StemFeatures at buffer(1) (bound by
// drawSceneGeometryOverlay) — no renderer change; the fragment reads the flat-interpolated activations.

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

// ── IFC.6 drive constants (measured from the dumper traces, RICERCAR_DESIGN §IFC.6) ──────────────
// FLOOR kills the near-zero leader-flap (pooled dev p75 ≈ 0.012; the IFC.5 finding); real family
// entries sit ≥ 0.05. Per-section SATURATION = the family's own dev p99 on the orchestral corpus, so a
// characteristic strong entry paints FULL regardless of the family's natural loudness (soft-saturate vs
// p99, NOT vs 1.0 — project_deviation_primitive_real_range). The string SAT is lower because the family
// dev is PARTITIONED across the two register sections (each rarely exceeds ~0.36).
constant float kRicFloor      = 0.04;   // weaving-section wake floor
constant float kRicSatStrings = 0.30;   // per split-section (low/high), measured 0.45 partitioned
constant float kRicSatBrass   = 0.85;   // brass dev p99 ≈ 0.89 (the loud, peaky family)
constant float kRicSatWinds   = 0.35;   // woodwinds dev p99 ≈ 0.37 (a subtle family)
constant float kRicFloorPerc  = 0.03;   // percussion is transient + usually near-zero
constant float kRicSatPerc    = 0.20;   // percussion dev spikes ~0.31 on real hits (IFC.5 so_what)

// ── Marks-on-top overlay: the section strokes painting onto the held light canvas ───────────────
struct RicercarGeoVertexOut {
    float4 position [[position]];
    float2 uv;
    float  aspect;
    float  t;        // features.time, flat across the 3 verts — the sweep clock
    float4 act;      // section activation ∈[0,1]: (lowStrings, brass, woodwinds, highStrings)
    float  perc;     // percussion sparkle activation ∈[0,1]
};

// smoothstep wake: dormant below floor, full at the family's p99 saturation.
static inline float ricAct(float dev, float sat) {
    return clamp(smoothstep(kRicFloor, sat, dev), 0.0, 1.0);
}

vertex RicercarGeoVertexOut ricercar_geometry_vertex(
    uint vid [[vertex_id]],
    constant FeatureVector& f     [[buffer(0)]],
    constant StemFeatures&  stems [[buffer(1)]]   // live family activity (bound by drawSceneGeometryOverlay)
) {
    float2 p = float2((vid == 2) ? 3.0 : -1.0, (vid == 1) ? 3.0 : -1.0);
    RicercarGeoVertexOut out;
    out.position = float4(p, 0.0, 1.0);
    out.uv       = p * 0.5 + 0.5;
    out.aspect   = (f.aspect_ratio > 0.01) ? f.aspect_ratio : 1.0;
    out.t        = f.time;

    // IFC.6 DRIVE-LAYER SWAP: each section wakes on its family's D-026 deviation (never the absolute).
    // Strings split low/high by REGISTER — partition the strings dev by the 3-band bass/treble balance
    // so the two register sections TRADE (they sum to the family dev, never double — FA #67). The
    // register ratio is a position mask, not an absolute gate (gating stays on strings dev — FA #31).
    float strDev = stems.strings_activity_dev;
    float denom  = f.bass + f.treble;
    float lowFrac = 0.5, highFrac = 0.5;                     // 50/50 when the band read is silent
    if (denom > 1e-3) { lowFrac = f.bass / denom; highFrac = f.treble / denom; }

    out.act = float4(
        ricAct(strDev * lowFrac,  kRicSatStrings),          // low-strings  (indigo, heavy)
        ricAct(stems.brass_activity_dev,     kRicSatBrass), // brass        (gold, glossy)
        ricAct(stems.woodwinds_activity_dev, kRicSatWinds), // woodwinds    (russet, matte)
        ricAct(strDev * highFrac, kRicSatStrings));         // high-strings (scarlet, crisp)
    out.perc = clamp(smoothstep(kRicFloorPerc, kRicSatPerc, stems.percussion_activity_dev), 0.0, 1.0);
    return out;
}

// Percussion SPARKLE (Matt's IFC.6 call — percussion is transient, flecks not a weaving line). A sparse
// animated hash-dot field gated by percussion activation: bright silver specks that land on hits. On the
// held canvas they deposit where percussion fired (percussion is near-zero most of the time, so the
// field stays sparse — the specks accumulate as the piece's hit-print, not a flood).
static inline float ricHash(float2 c) {
    return fract(sin(dot(c, float2(127.1, 311.7))) * 43758.5453);
}
static inline float ricSparkle(float2 q, float t, float act) {
    if (act < 0.01) { return 0.0; }
    const float cells = 9.0;                      // ~9 sparkle cells across the aspect-corrected width
    float2 cell = floor(q * cells);
    float  seed = floor(t * 3.0);                 // reseed 3×/s so specks twinkle to fresh spots
    float  lit  = step(0.90, ricHash(cell + seed * 7.0));   // ~10% of cells lit this instant
    float2 jit  = float2(ricHash(cell + seed), ricHash(cell + seed * 3.0));
    float2 ctr  = (cell + 0.15 + 0.7 * jit) / cells;        // jittered speck centre inside the cell
    float  d    = length(q - ctr);
    float  dot  = 1.0 - smoothstep(0.0, 0.009, d);          // fine bright point
    return lit * dot * act;
}

fragment float4 ricercar_geometry_fragment(RicercarGeoVertexOut in [[stage_in]]) {
    float a = in.aspect;
    float2 q = float2(in.uv.x * a, in.uv.y);
    float px = max(fwidth(q.x), fwidth(q.y));
    float t = in.t;

    // IFC.6: FOUR weaving sections mapped to the captured instrument families, each in its register-band
    // (vertical position ≈ register, for legibility — reference 04_palette_register_legibility) with a
    // distinct material. Order matches in.act: (lowStrings, brass, woodwinds, highStrings).
    RicSection sections[4];
    // LOW-STRINGS — basses/cellos: deep indigo, HEAVY broad, gloopy/smeared, grave slow sweep (bottom)
    sections[0] = RicSection{ float3(0.22, 0.18, 0.55), 0.020, 0.42, 2.6, 52.0,
                              float2(0.50, 0.74), float2(0.34, 0.10), float2(0.18, 0.13), float2(0.0, 1.0) };
    // BRASS — horns/trombones: burnished gold, heavy but GLOSSY (tight AA, smooth edge), grand arcs (low-mid)
    sections[1] = RicSection{ float3(0.86, 0.60, 0.16), 0.015, 0.14, 1.0, 60.0,
                              float2(0.50, 0.60), float2(0.34, 0.13), float2(0.22, 0.17), float2(1.2, 2.4) };
    // WOODWINDS — violas/clarinets/bassoons: warm russet, MEDIUM soft-grained matte, lyrical (centre)
    sections[2] = RicSection{ float3(0.74, 0.36, 0.18), 0.011, 0.30, 1.9, 78.0,
                              float2(0.50, 0.47), float2(0.36, 0.16), float2(0.26, 0.21), float2(2.0, 3.5) };
    // HIGH-STRINGS — violins: scarlet/rose, medium-light, CRISP singing (slight gloss), agile (high-mid)
    sections[3] = RicSection{ float3(0.80, 0.22, 0.30), 0.008, 0.16, 1.3, 100.0,
                              float2(0.50, 0.32), float2(0.38, 0.12), float2(0.42, 0.31), float2(4.0, 0.5) };

    // OPAQUE compositing (the §colour-mud rule): topmost mark by ACTIVE coverage occludes — never average
    // to mud. Each section's coverage is scaled by its activation, so it paints only while its family
    // sounds above its running mean (the drive-layer swap; dormant families contribute nothing).
    float  bestCover = 0.0;
    float3 bestCol   = float3(1.0);
    for (int s = 0; s < 4; ++s) {
        float cov = ricStrokeCoverage(sections[s], q, px, t, a) * in.act[s];
        if (cov > bestCover) { bestCover = cov; bestCol = sections[s].color; }
    }

    // Percussion sparkle on top — cool teal glints on hits (the reference "bells sparkle" colour; a
    // light silver-white would vanish on the cream canvas, so the sparkle reads by cool saturation).
    // Topmost when brighter than any stroke.
    float spark = ricSparkle(q, t, in.perc);
    if (spark > bestCover) { bestCover = spark; bestCol = float3(0.12, 0.58, 0.66); }

    return float4(bestCol, bestCover);
}
