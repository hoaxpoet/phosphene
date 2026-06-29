// Ricercar.metal — Ricercar.2: flowing-colour-field SUBSTRATE spike (no audio, no voices).
//
// Ricercar is a contrapuntal visual-music painting preset (see docs/presets/RICERCAR_DESIGN.md).
// This increment establishes ONLY the substrate (§1.4 / §4 layer 1): the flowing colour FIELD the
// voices will later be deposited onto. It reuses Skein's canvas-hold mv_warp machinery (D-142/143)
// but RECONFIGURED — the deliberate fork that makes Ricercar painterly visual-music rather than a
// second drip-record:
//
//   • FLOW warp   — mvWarpPerVertex returns `uv + curl-noise(...)` (divergence-free advection), so
//                   deposited colour DRIFTS and merges wet-into-wet, instead of Skein's identity hold.
//   • DECAY-TO-GROUND — `ricercar_warp_fragment` (the per-prefix <prefix>_warp_fragment override, the
//                   skein_warp_fragment precedent) advects the previous canvas AND blends it toward a
//                   light GROUND: `mix(ground, prev, decay)`. A flowing field with decay<1 must breathe
//                   back toward LIGHT, never fade to black — this satisfies silence-non-black (D-037) by
//                   construction and matches the 02_meso ink-plume-on-near-white reference.
//
// Colour is HAND-FED here (Ricercar.2 has no audio): ricercar_geometry_fragment deposits three soft,
// slowly-drifting colour masses in the LOW/MID/HIGH lane families, which the flow carries and merges.
// The agent "voices" (Filigree-class trails), audio routing, and the per-track seed all arrive later
// (Ricercar.3.x/.3/.4). The gate-before-the-gate (RICERCAR_DESIGN §7): does this read as FLOWING,
// MERGING painterly colour? If not, re-tune before any voices land.
//
// Path A (Skein.1/.2 precedent): closed-form, in-shader, driven by features.time only — NO CPU state,
// NO per-preset buffer, NO engine touch. The warp/comp/geometry fragments auto-resolve by the
// `ricercar_` prefix (PresetLoader.makeWarpPipelines / makeSceneGeometryPipeline). Shared types
// (FeatureVector, StemFeatures, SceneUniforms, VertexOut, MVWarpPerFrame, WarpVertexOut, warpSampler,
// fullscreen_vertex) come from the prepended mv_warp preamble — no #include, exactly like Skein.metal.

// ── Ground + lane colour families (RICERCAR_DESIGN §1.1; tunable in the spike) ──────────────
// kRicercarGround MUST match Ricercar.json `marks.canvas_clear` (the initial clear == the decay target).
constant float3 kRicercarGround = float3(0.90, 0.88, 0.84);  // warm light ground (paint-on-light, D-037)
constant float3 kRicercarLow    = float3(0.20, 0.17, 0.55);  // LOW  — deep indigo (basses)
constant float3 kRicercarMid    = float3(0.82, 0.52, 0.13);  // MID  — amber / gold (horns, violas)
constant float3 kRicercarHigh   = float3(0.16, 0.62, 0.72);  // HIGH — cyan (violins, flutes)

constant float kRicercarFlowAmp   = 0.010;   // per-vertex advection amplitude — colour streams + swirls
constant float kRicercarFlowFreq  = 1.8;     // spatial frequency of the flow field (broad swirls)
constant float kRicercarFlowDrift = 0.05;    // how fast the flow field itself evolves over time
constant float kRicercarDeposit   = 0.32;    // per-frame deposit alpha (richer masses, still trail-dominated)
constant float kRicercarBlobSigma = 0.13;    // colour-source radius — sources overlap + merge wet-into-wet

// ── Self-contained 2D gradient noise + curl (divergence-free flow). No external dependency. ──
static inline float ric_hash21(float2 p) {
    p = fract(p * float2(123.34, 345.45));
    p += dot(p, p + 34.345);
    return fract(p.x * p.y);
}

// Smooth value noise on the integer lattice (quintic fade) → C¹, enough for a curl potential.
static inline float ric_noise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    float a = ric_hash21(i + float2(0.0, 0.0));
    float b = ric_hash21(i + float2(1.0, 0.0));
    float c = ric_hash21(i + float2(0.0, 1.0));
    float d = ric_hash21(i + float2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Curl of the scalar potential field N: ∇⊥N = (-∂N/∂y, ∂N/∂x) → divergence-free (no sources/sinks).
static inline float2 ric_curl(float2 p) {
    const float e = 0.01;
    float ny1 = ric_noise(p + float2(0.0, e));
    float ny2 = ric_noise(p - float2(0.0, e));
    float nx1 = ric_noise(p + float2(e, 0.0));
    float nx2 = ric_noise(p - float2(e, 0.0));
    return float2(-(ny1 - ny2), (nx1 - nx2)) / (2.0 * e);
}

// ── Ground fragment ─────────────────────────────────────────────────────────────────────────
// Required by the descriptor (`fragment_function: ricercar_fragment`). On the marks-on-top path
// Pass 0 is skipped and the per-preset canvas-clear IS the held ground, so this is rarely drawn;
// it returns the same light ground for parity (the skein_fragment precedent).
fragment float4 ricercar_fragment(
    VertexOut               in    [[stage_in]],
    constant FeatureVector& f     [[buffer(0)]],   // unused (no audio in the substrate spike)
    constant float*         fft   [[buffer(1)]],   // unused
    constant float*         wv    [[buffer(2)]],   // unused
    constant StemFeatures&  stems [[buffer(3)]]    // unused
) {
    return float4(kRicercarGround, 1.0);
}

// ── mv_warp: gentle curl-noise FLOW + slow decay ──────────────────────────────────────────────
MVWarpPerFrame mvWarpPerFrame(
    constant FeatureVector& f,
    constant StemFeatures&  stems,
    constant SceneUniforms& s
) {
    MVWarpPerFrame pf;
    pf.zoom  = 1.0;
    pf.rot   = 0.0;
    pf.decay = 0.97;          // SLOW decay — colour lingers ~33 frames → an allover flowing field (decays to ground).
    pf.warp  = 0.0;
    pf.cx = 0.0; pf.cy = 0.0;
    pf.dx = 0.0; pf.dy = 0.0;
    pf.sx = 1.0; pf.sy = 1.0;
    pf.q1 = f.time; pf.q2 = 0.0; pf.q3 = 0.0; pf.q4 = 0.0;
    pf.q5 = 0.0; pf.q6 = 0.0; pf.q7 = 0.0; pf.q8 = 0.0;
    return pf;
}

float2 mvWarpPerVertex(
    float2 uv, float rad, float ang,
    thread const MVWarpPerFrame& pf,
    constant FeatureVector& f,
    constant StemFeatures& stems
) {
    // Divergence-free curl-noise flow; the field itself drifts slowly over time so the swirls evolve.
    float t = pf.q1;   // features.time (passed through q1)
    float2 fp = uv * kRicercarFlowFreq + float2(0.0, t * kRicercarFlowDrift);
    float2 flow = ric_curl(fp);
    return uv + flow * kRicercarFlowAmp;
}

// ── Custom warp fragment: advect + decay TOWARD the light ground (silence-non-black, D-037) ───
// Same bindings as the shared mvWarp_fragment (prevTex@0, chromaticMix@0); chromaticMix is 0 for
// Ricercar so the hue-transfer path is irrelevant — we just advect and breathe toward ground.
fragment float4 ricercar_warp_fragment(
    WarpVertexOut      in           [[stage_in]],
    texture2d<float>   prevTex      [[texture(0)]],
    constant float&    chromaticMix [[buffer(0)]]   // unused (0) — kept for binding parity
) {
    float4 prev = prevTex.sample(warpSampler, in.warped_uv);   // flow-advected sample of the prev canvas
    // mix(ground, prev, decay): at rest converges to the light ground (never black); under deposits the
    // colour dissolves toward ground over ~1/(1-decay) ≈ 16 frames → a moving present with fading memory.
    float3 col = mix(kRicercarGround, prev.rgb, in.decay);
    return float4(col, 1.0);
}

// ── Marks-on-top: hand-fed drifting colour masses (Ricercar.2 colour source; NO audio) ────────
struct RicercarGeoVertexOut {
    float4 position [[position]];
    float2 uv;
    float  aspect;
    float  t;        // features.time, flat across the 3 verts (the Path-A vertex reads features@0)
};

vertex RicercarGeoVertexOut ricercar_geometry_vertex(
    uint vid [[vertex_id]],
    constant FeatureVector& f [[buffer(0)]]   // bound by drawSceneGeometryOverlay (vertex slot 0)
) {
    float2 p = float2((vid == 2) ? 3.0 : -1.0, (vid == 1) ? 3.0 : -1.0);
    RicercarGeoVertexOut out;
    out.position = float4(p, 0.0, 1.0);
    out.uv       = p * 0.5 + 0.5;
    out.aspect   = (f.aspect_ratio > 0.01) ? f.aspect_ratio : 1.0;
    out.t        = f.time;
    return out;
}

// Soft gaussian colour-mass deposit. Three masses (LOW/MID/HIGH lane colours) drift on slow,
// incommensurate Lissajous paths; overlaps BLEND (wet-into-wet) rather than occlude — the merging
// colour ground the voices will later weave through. Output (rgb, coverage) → normal alpha-over.
fragment float4 ricercar_geometry_fragment(
    RicercarGeoVertexOut in [[stage_in]]
) {
    float a = in.aspect;
    float2 q = float2(in.uv.x * a, in.uv.y);   // aspect-corrected → round masses
    float t = in.t;

    // Source centres SWEEP wide, incommensurate paths around the canvas (uv space) so colour is laid
    // everywhere and the three lanes cross + merge; the flow then carries and swirls the trails.
    float2 cLow  = float2(0.50 + 0.42 * sin(t * 0.230),       0.52 + 0.38 * cos(t * 0.190));
    float2 cMid  = float2(0.50 + 0.44 * sin(t * 0.170 + 2.0), 0.50 + 0.34 * sin(t * 0.270));
    float2 cHigh = float2(0.50 + 0.42 * cos(t * 0.210 + 1.0), 0.50 + 0.40 * sin(t * 0.200 + 3.0));

    float twoSigma2 = 2.0 * kRicercarBlobSigma * kRicercarBlobSigma;
    float wLow  = exp(-distance(q, float2(cLow.x  * a, cLow.y )) * distance(q, float2(cLow.x  * a, cLow.y )) / twoSigma2);
    float wMid  = exp(-distance(q, float2(cMid.x  * a, cMid.y )) * distance(q, float2(cMid.x  * a, cMid.y )) / twoSigma2);
    float wHigh = exp(-distance(q, float2(cHigh.x * a, cHigh.y)) * distance(q, float2(cHigh.x * a, cHigh.y)) / twoSigma2);

    float  sumW = wLow + wMid + wHigh;
    if (sumW < 1e-4) { return float4(0.0); }   // no deposit here this frame

    float3 col   = (kRicercarLow * wLow + kRicercarMid * wMid + kRicercarHigh * wHigh) / sumW;  // blend (merge)
    float  cover = saturate(sumW) * kRicercarDeposit;   // per-frame deposit alpha
    return float4(col, cover);
}
