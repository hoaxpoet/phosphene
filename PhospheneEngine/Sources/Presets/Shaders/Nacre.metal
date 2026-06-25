// Nacre.metal — faithful uplift of the Milkdrop preset `$$$ Royal - Mashup (431)`
// (butterchurn cream-of-crop legends; the "Jello Mirror" translucent refractive
// cell-field). See docs/presets/NACRE_PLAN.md + docs/VISUAL_REFERENCES/nacre/.
//
// Character (faithful to (431)): a field of translucent, overlapping refractive
// lens-cells with chromatic-fringed rims and a bright pulsing central core, on a
// near-black ground; the field breathes + slowly roams and the palette rotates
// (green→teal→violet→red) on a slow time bed.
//
// 2026 uplifts (greenlit — exceed the 2003 original):
//   1. Stem-instrument routing — vocals→core, bass→swell/kick, drums→rim sparkle,
//      harmonic "other"→refraction/iridescence shift.
//   2. Real thin-film iridescence on the rims (vs (431)'s 2-px chromatic hack),
//      hue ← chroma/centroid; on HDR .rgba16Float feedback.
//   3. Smooth-Voronoi refractive cells (vs (431)'s sin-lattice).
//
// ── INCREMENT STATUS ──────────────────────────────────────────────────────────
// NACRE.2a (THIS FILE, current): a STUB that wires the live custom-comp path —
//   minimal scene core + a gentle drifting warp + a comp fragment that samples the
//   feedback and tints it by the rotating palette (proving NacreUniforms.time flows
//   end-to-end). The signature look is intentionally NOT here yet.
// NACRE.2b (next): port (431)'s comp shader + the 3 uplifts into nacre_comp_fragment
//   (radial-pulse zoom + luminance-emboss→iridescence + smooth-Voronoi cells) and
//   the scene/warp (stem routes). The iridescence()/smin() helpers get inlined here
//   then (presets are self-contained — only ShaderUtilities.metal is auto-merged).

// ── NacreUniforms ───────────────────────────────────────────────────────────────
// Comp-stage uniforms (display-only) bound at fragment buffer(1). Must match
// NacreUniformsGPU in NacreState.swift byte-for-byte (16 floats = 64 bytes).
struct NacreUniforms {
    float time;          // wall-clock-accumulated time (radial-pulse + slow palette phase)
    float coreEnergy;    // vocals → central-core brightness (2b)
    float coreShape;     // waveform/overall → core form (2b)
    float bassSwell;     // bass deviation → cell swell (2b)
    float drumsSparkle;  // drums deviation → rim sparkle (2b)
    float trebleGrain;   // treble attack-rel → rim grain (2b)
    float iriShift;      // harmonic "other" → iridescence band shift (2b)
    float hueDrive;      // spectral centroid → iridescence hue base (2b)
    float cellScale;     // overall energy → Voronoi cell density (2b)
    float pad0, pad1, pad2, pad3, pad4, pad5, pad6;
};

// ── Constants ─────────────────────────────────────────────────────────────────
// Feedback baseline. (431): zoom 1.009 (slight zoom-in), near-1 decay. A moderate
// decay gives a persistent-but-drifting field; tune in 2b. Keep kNacreDecay aligned
// with Nacre.json `decay`.
constant float kNacreDecay     = 0.94;
constant float kNacreBaseZoom  = 1.004;   // slight zoom-in baseline
constant float kNacreZoomGain  = 0.020;   // mid-band continuous energy → zoom pump (PRIMARY)
constant float kNacreRotAmp    = 0.020;   // slow roam rotation (bounded sway, faithful (431))
constant float kNacreRoamAmp   = 0.012;   // slow centre roam
constant float kNacreWarpAmp   = 0.004;   // dense cell-advection displacement (mv_x/y ~25/9 analog)
constant float kNacreCellFreqX = 18.0;    // 2a coarse cell frequency (2b: smooth Voronoi)
constant float kNacreCellFreqY = 13.0;

// Near-black ground (the field reads against this; cells are tinted, never opaque).
constant float3 kNacreGround    = float3(0.010, 0.012, 0.022);
// Central core (2a: gentle energy-seeded glow; 2b: vocals→brightness + waveform→shape).
constant float  kNacreCoreTight = 26.0;
constant float  kNacreCoreBase  = 0.12;
constant float  kNacreCoreGain  = 0.9;
constant float3 kNacreCoreColor = float3(0.55, 0.62, 1.00);  // cool luminous core

// ── Scene fragment (the additive "fresh content" seeding the feedback) ──────────
// 2a: near-black ground + a soft central core. The drifting cell-field is the
// feedback INTEGRAL of this (built up by mv_warp), not this single frame.
fragment float4 nacre_fragment(
    VertexOut               in    [[stage_in]],
    constant FeatureVector& f     [[buffer(0)]],
    constant float*         fft   [[buffer(1)]],   // 512 magnitudes (unused 2a)
    constant float*         wv    [[buffer(2)]],   // 2048 samples (unused 2a; 2b: core shape)
    constant StemFeatures&  stems [[buffer(3)]]    // unused 2a; 2b: vocals→core
) {
    float2 uv = in.uv;
    float  r  = length(uv - float2(0.5, 0.5));
    float  core = exp(-r * r * kNacreCoreTight) *
                  (kNacreCoreBase + kNacreCoreGain * max(0.0, f.mid_rel));  // 2b: vocals_energy
    float3 col  = kNacreGround + core * kNacreCoreColor;
    return float4(col, 1.0);   // HDR feedback (rgba16Float): core may exceed 1 → bloom
}

// ── MV-Warp functions (D-027; required by the preamble forward declarations) ────

MVWarpPerFrame mvWarpPerFrame(
    constant FeatureVector& f,
    constant StemFeatures&  stems,
    constant SceneUniforms& s
) {
    MVWarpPerFrame pf;
    float t = f.time;
    pf.decay = kNacreDecay;
    // Mid-band continuous energy → zoom pump (PRIMARY motion; Audio Data Hierarchy).
    // Deviation primitive (D-026), not an absolute threshold (FA #31). 2b: EMA memory.
    pf.zoom = kNacreBaseZoom + kNacreZoomGain * max(0.0, f.mid_rel);
    // Slow bounded roam (faithful (431) cx/cy/rot sines) — alive at silence.
    pf.rot = kNacreRotAmp * sin(t * 0.13);
    pf.cx  = kNacreRoamAmp * sin(t * 0.097);
    pf.cy  = kNacreRoamAmp * sin(t * 0.083 + 1.7);
    pf.dx  = 0.0; pf.dy = 0.0; pf.sx = 1.0; pf.sy = 1.0; pf.warp = 0.0;
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
    float  t      = f.time;
    float2 centre = float2(0.5 + pf.cx, 0.5 + pf.cy);
    float2 p      = uv - centre;
    // Baseline zoom + slow rotation about the (roaming) centre.
    p = p / max(pf.zoom, 0.001);
    float c = cos(pf.rot), sn = sin(pf.rot);
    float2 rp = float2(c * p.x - sn * p.y, sn * p.x + c * p.y) + centre;
    // Dense cell-advection displacement (the (431) mv-field analog; 2a coarse, 2b
    // Voronoi-guided). bass→swell/kick folds in here at 2b.
    float2 disp = kNacreWarpAmp * float2(sin(uv.y * kNacreCellFreqY + t * 0.20),
                                         cos(uv.x * kNacreCellFreqX + t * 0.17));
    return rp + disp;
}

// ── Custom comp/blit fragment (DISPLAY-ONLY; the signature look lives here) ─────
// Auto-selected by PresetLoader naming convention (fragment_function "nacre_fragment"
// → prefix "nacre" → "nacre_comp_fragment"). Samples the composed feedback (warpTex =
// composeTexture), transforms it for display only (never fed back — Milkdrop comp
// semantics), and reads NacreUniforms at buffer(1).
//
// NACRE.2a STUB: sample feedback + tint by (431)'s rotating palette (wave_r/g/b
// sines of nu.time) — this proves the feedback texture AND NacreUniforms.time both
// reach the screen. NACRE.2b replaces the tint with: radial-pulse zoom + luminance-
// emboss rims → real iridescence (hue ← nu.hueDrive/iriShift) + smooth-Voronoi cells
// + drums sparkle + treble grain.
fragment float4 nacre_comp_fragment(
    VertexOut               in      [[stage_in]],
    texture2d<float>        warpTex [[texture(0)]],
    constant float4&        post    [[buffer(0)]],   // shared display params (unused 2a; binding parity)
    constant NacreUniforms& nu      [[buffer(1)]]
) {
    float3 c = warpTex.sample(warpSampler, in.uv).rgb;
    // (431) slow palette rotation (per-frame eqs: wave_r=.85+.25*sin(.437*t+1), etc.).
    float t = nu.time;
    float3 pal = float3(0.85 + 0.25 * sin(0.437 * t + 1.0),
                        0.85 + 0.25 * sin(0.544 * t + 2.0),
                        0.85 + 0.25 * sin(0.751 * t + 3.0));
    c *= pal;
    return float4(c, 1.0);
}
