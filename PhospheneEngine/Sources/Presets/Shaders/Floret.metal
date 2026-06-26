// Floret.metal — port of the Milkdrop/butterchurn builtin
// `suksma - Rovastar - Sunflower Passion (Enlightment Mix)` (projectM cream-of-crop
// legends; pick #1). See docs/presets/FLORET_PLAN.md + docs/VISUAL_REFERENCES/floret/
// (source_shaders.txt = the literal port artifact).
//
// Character (target, faithful): a breathing 3-fold radial fractal bloom on a near-black
// ground — colour-cycling seed-discs swirled by a 1/r² vortex + folded by a z² conformal
// map (warp), then bloomed by a 3-fold-rotational radial-pulse unsharp-high-pass
// kaleidoscope (comp) into iridescent bubble-foam; bass spins the field, energy swells it.
//
// ── Render loop (RenderPipeline+Floret.swift — the Nacre/D-138 dedicated-branch
//    structure, FA #70) ──────────────────────────────────────────────────────────────
//   warp(prev) → composeTexture   (custom feedback warp; bakes decay + seed)
//   comp(compose) → drawable       (the signature look; DISPLAY-ONLY, never fed back)
//   swap warpTexture ↔ composeTexture
//
// Functions looked up by name by PresetLoader.makeWarpPipelines (fragment_function
// prefix `floret`):
//   · floret_fragment       — near-black placeholder (loader needs a fragment_function;
//                             the seed lives in the warp, so this is unused at draw time)
//   · floret_warp_fragment  — the custom feedback warp
//   · floret_comp_fragment  — the signature look (display-only)
// Every OTHER preset's library lacks `floret_*` symbols → falls back to the shared
// mvWarp_* defaults (structural gating; PresetRegression confirms byte-identity).
//
// SceneUniforms / MVWarpPerFrame / WarpVertexOut / VertexOut / fullscreen_vertex /
// FeatureVector / StemFeatures / warpSampler come from the mvWarp preamble + Common.metal.
//
// ── INCREMENT STATUS ──────────────────────────────────────────────────────────────
// FLORET.2a (THIS FILE): WIRING STUB ONLY. The warp seeds a faint palette core + decays
//   (alive at silence, clamp-safe); the comp displays the feedback (sRGB-decoded). The
//   faithful mechanic — vortex + z² fold (warp), 3-fold radial-pulse high-pass kaleidoscope
//   (comp), 4-disc seed — lands at FLORET.2b; audio + uplifts at FLORET.3 (FA #65, faithful
//   base before reactivity). TODO(FLORET.2b) markers flag each stub.

// MARK: - FloretUniforms (CPU-computed per frame; matches FloretUniforms in Swift)
//
// Bound at fragment buffer(1) of BOTH the warp and comp passes (the Nacre pattern).
// 32 bytes — see FloretUniforms in RenderPipeline+Floret.swift for the byte layout.
// FLORET.2b extends this (spin / hueShift / barPush / randPreset / roam) as the audio
// routes + signature comp land; 2a carries only what the stub reads.
struct FloretUniforms {
    float  time;        // features.time — palette + (2b) radial-pulse phase
    float  coreEnergy;  // total energy — gates the warp's core seed (volume-gated)
    float2 texel;       // (1/feedbackW, 1/feedbackH) — (2b) comp sobel/blur offsets
    float4 aspect;      // (aspectx, aspecty, 1/aspectx, 1/aspecty) — (2b) comp cell aspect
};

// MARK: - Constants
constant float kFloretDecay     = 0.90;    // baked in-warp decay (source warp ret*0.9-class)
constant float kFloretBaseZoom  = 1.004;   // gentle zoom-in (stub; 2b: vortex + radial bulge)
constant float kFloretRotAmp    = 0.015;   // slow roam rotation (alive at silence)
constant float kFloretCoreTight = 14.0;    // luminous core spot tightness
constant float kFloretCoreBase  = 0.12;    // central seed glow (the bloom's light source)
constant float kFloretWash      = 0.012;   // faint full-frame palette wash (stub: keeps the
                                           // field alive at silence; 2b → 4 seed-discs + black ground)

constant float3 kLuma = float3(0.32, 0.49, 0.29);

// MARK: - Palette (the slow green→magenta→violet colour-cycle; source shapes' sin(k·t))
// Tints the SEED (accumulates in the feedback), never the display (hue-strobing the
// display is an anti-reference).
static inline float3 floretPalette(float t) {
    return float3(0.55 + 0.35 * sin(0.31 * t + 0.0),
                  0.45 + 0.35 * sin(0.43 * t + 2.1),
                  0.55 + 0.35 * sin(0.27 * t + 4.0));
}

// MARK: - Scene fragment (loader placeholder; unused in the Floret draw branch)
//
// PresetLoader.makeDirectPrimaryPipeline needs a `fragment_function` to build the direct
// pipeline, but the Floret branch never renders it (the seed is folded into the warp).
// Near-black, like nacre_fragment / fata_morgana_fragment.
fragment float4 floret_fragment(VertexOut in [[stage_in]]) {
    return float4(0.0, 0.0, 0.0, 1.0);
}

// MARK: - MV-Warp mesh functions (the per-vertex feedback transform)
//
// FLORET.2a STUB: gentle zoom-in + slow rotation about a fixed centre (keeps the field
// alive and advecting). TODO(FLORET.2b): the source's per-vertex warp —
//   · 1/r² vortex swirl   dx = (.5+…)·y/(r²+1), dy = −(.5+…)·x/(r²+1)
//   · bass → rotation     rot = bass·rad/10
//   · radial bulge        sy = 1.02 + rad/10, sx = sy − r²
MVWarpPerFrame mvWarpPerFrame(
    constant FeatureVector& f,
    constant StemFeatures&  stems,
    constant SceneUniforms& s
) {
    MVWarpPerFrame pf;
    float t = f.time;
    pf.decay = kFloretDecay;                 // informational; the warp fragment bakes decay
    pf.zoom  = kFloretBaseZoom;              // TODO(FLORET.2b): vortex + radial bulge + energy swell
    pf.rot   = kFloretRotAmp * (0.6 * sin(0.31 * t) + 0.4 * sin(0.53 * t));
    pf.cx = 0.0; pf.cy = 0.0;
    pf.dx = 0.0; pf.dy = 0.0;                // TODO(FLORET.2b): bass-onset positional kick
    pf.warp = 0.0;
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
    // STUB: zoom-in + slow rotation about centre. TODO(FLORET.2b): replace with the
    // 1/r² vortex + bass rotation + radial bulge (source pixel_eqs).
    float2 centre = float2(0.5 + pf.cx, 0.5 + pf.cy);
    float2 p = (uv - centre) / max(pf.zoom, 0.001);
    float c = cos(pf.rot), sn = sin(pf.rot);
    return float2(c * p.x - sn * p.y, sn * p.x + c * p.y) + centre + float2(pf.dx, pf.dy);
}

// MARK: - Custom WARP fragment (the feedback transfer)
//
// FLORET.2a STUB: warp prev (vertex-advected) → decay → add a faint palette-tinted,
// volume-gated central core seed → clamp [0,1]. This keeps the field alive at silence
// (D-019) and bounded (no HDR white-out). TODO(FLORET.2b): the source warp shader —
// the z² complex-conformal fold of the sample coords + an unsharp high-pass + treble grain.
fragment float4 floret_warp_fragment(
    WarpVertexOut           in   [[stage_in]],
    texture2d<float>        prev [[texture(0)]],
    constant FloretUniforms& fu  [[buffer(1)]]
) {
    float2 uv = in.warped_uv;
    float3 c  = prev.sample(warpSampler, uv).rgb;
    c *= kFloretDecay;                       // baked decay

    float3 pal = floretPalette(fu.time);
    // Faint full-frame palette wash (the source injects palette-coloured content across the
    // frame each frame; keeps the stub field alive at silence — D-019). TODO(FLORET.2b):
    // replace with the 4 colour-cycling seed-discs near (0.3,0.4) + a properly black ground.
    c += kFloretWash * pal;
    // Palette-coloured, volume-gated central core seed (the bloom's light source). Faint at
    // silence, brighter with energy.
    float r        = length(in.uv - 0.5);
    float coreGate = 0.25 + 0.70 * clamp(fu.coreEnergy, 0.0, 1.0);
    float core     = exp(-r * r * kFloretCoreTight) * kFloretCoreBase * coreGate;
    c += core * pal;

    // Clamp [0,1] — bounds the feedback accumulation (an unclamped HDR loop blooms to
    // white). The rgba16Float buffer is retained for the FLORET.3 iridescence headroom.
    return float4(clamp(c, 0.0, 1.0), 1.0);
}

// MARK: - Custom COMP fragment (the signature look — DISPLAY ONLY, never fed back)
//
// FLORET.2a STUB: display the warped feedback with the sRGB round-trip decode (the FM/
// Nacre fix — Phosphene's drawable is .bgra8Unorm_srgb, so decode here so the target's
// encode round-trips back to the butterchurn display value, keeping the ground deep
// black). TODO(FLORET.2b): the source comp shader — 4 layers at 120° rotation, each a
// radial-pulse `fract(3·uv·dist)` tiling with an unsharp high-pass (main − blur),
// max-combined, ×4 → the 3-fold pulsing bubble-foam kaleidoscope.
fragment float4 floret_comp_fragment(
    VertexOut               in      [[stage_in]],
    texture2d<float>        mainTex [[texture(0)]],
    constant FloretUniforms& fu     [[buffer(1)]]
) {
    constexpr sampler m(filter::linear, address::clamp_to_edge);
    float3 ret = mainTex.sample(m, in.uv).rgb;

    // sRGB round-trip cancellation (D-139): decode so the drawable's sRGB encode restores
    // the intended display value (keeps the ground deep black against the bright bloom).
    float3 v = saturate(ret);
    float3 lin = select(v / 12.92, pow((v + 0.055) / 1.055, float3(2.4)), v > 0.04045);
    return float4(lin, 1.0);
}
