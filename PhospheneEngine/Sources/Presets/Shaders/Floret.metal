// Floret.metal — port of the Milkdrop/butterchurn builtin
// `suksma - Rovastar - Sunflower Passion (Enlightment Mix)` (projectM cream-of-crop
// legends; pick #1). See docs/presets/FLORET_PLAN.md + docs/VISUAL_REFERENCES/floret/
// (source_shaders.txt = the literal port artifact).
//
// Character (faithful): a breathing 3-fold radial fractal bloom on a near-black ground —
// colour-cycling seed-discs folded by a z² conformal map (warp) into a fractal field, then
// bloomed by a 3-fold-rotational radial-pulse unsharp-high-pass kaleidoscope (comp).
//
// ── Render loop (RenderPipeline+Floret.swift — the Nacre/D-138 dedicated branch, FA #70):
//   warp(prev) → composeTexture   (z² fold of the feedback + colour-cycling seed discs)
//   comp(compose) → drawable       (the signature look; DISPLAY-ONLY, never fed back)
//   swap warpTexture ↔ composeTexture
//
// Functions looked up by PresetLoader.makeWarpPipelines (prefix `floret`):
//   · floret_fragment       — near-black placeholder (loader needs a fragment_function;
//                             the seed lives in the warp, so this is unused at draw time)
//   · floret_warp_fragment  — the custom feedback warp (z² fold + decay + seed discs)
//   · floret_comp_fragment  — the signature look (display-only kaleidoscope)
//
// SceneUniforms / MVWarpPerFrame / WarpVertexOut / VertexOut / fullscreen_vertex /
// FeatureVector / StemFeatures / warpSampler come from the mvWarp preamble + Common.metal.
//
// ── INCREMENT STATUS ──────────────────────────────────────────────────────────────
// FLORET.2b (THIS FILE): the FAITHFUL BASE — port the source warp (z² fold), comp (3-fold
//   radial-pulse high-pass kaleidoscope), and seed (4 colour-cycling discs) verbatim, then
//   tune to read as the source at silence (time-driven). Flash-safe by construction (the
//   3 staggered pulse phases keep ≥1 layer lit + a luminance floor — D-157). Faithful audio
//   (energy→pace, bass→spin) + the 2026 uplifts (real iridescence, stem routing) are
//   FLORET.3+ (FA #65 — faithful base before reactivity). Source decode notes:
//   · the warp shader samples sampler_fc_main at z²(uv_orig) — it BYPASSES the per-vertex
//     mesh warp (the pixel_eqs vortex is vestigial in this `_Phat_edit`; verified by render,
//     cf. Nacre's mv_x/y debug-grid misread, FA #73) → mvWarpPerVertex is identity here.
//   · the comp's 4th layer duplicates the 0th (rotation ≈0°, phase offset 1.0≡0) → the loop
//     of 4 with angle k·120° + offset k/3 reproduces the source exactly.

// MARK: - FloretUniforms (CPU-computed per frame; matches FloretUniforms in Swift)
//
// Bound at fragment buffer(1) of BOTH the warp and comp passes. 32 bytes — see
// FloretUniforms in RenderPipeline+Floret.swift for the byte layout.
struct FloretUniforms {
    float  time;        // features.time — palette cycle + seed jitter + comp radial-pulse phase
    float  coreEnergy;  // total energy — volume-gates the seed discs (faithful modwavealphabyvolume)
    float2 texel;       // (1/feedbackW, 1/feedbackH) — comp high-pass blur tap spread
    float4 aspect;      // (aspectx, aspecty, 1/aspectx, 1/aspecty) — comp keeps the bloom round
};

// MARK: - Constants
// Warp (the z² conformal feedback fold — source warp shader).
constant float  kFloretFoldScale = 1.81;                 // (uv_orig-0.5)*1.81 before z²
constant float2 kFloretFoldOffset = float2(0.448, 0.701);// z² sample offset
constant float  kFloretWarpFade  = 0.006;                // subtractive decay (source 0.004; +a touch
                                                         // to shorten trails on our HDR buffer)
// Seed discs (source shapes: 4 nested colour-cycling discs near (0.3,0.4)).
constant float  kFloretSeedGain  = 0.80;                 // seed brightness into the feedback (denser field
                                                         // → the 3-fold max-combine fills into a mandala)
constant float  kFloretWash      = 0.006;                // faint full-frame palette wash (alive at
                                                         // silence between discs; the slow-decay ground)
// Comp (the 3-fold radial-pulse high-pass kaleidoscope — source comp shader).
constant float  kFloretCompGain  = 3.8;                  // source ×4 + gamma 1.98; bright filaments clip
                                                         // toward white (carries the source's white+accent read)
constant float  kFloretHighpass  = 0.90;                 // unsharp weight (main − blur·k); cell contrast
constant float  kFloretBlurSpread = 2.5;                 // high-pass blur radius (texels) → foam-cell scale
constant float  kFloretLumaFloor = 0.02;                 // a faint floor only (the ~0.5 Hz pulse is below the
                                                         // flash band; this just stops a fully dead trough)

constant float3 kLuma = float3(0.299, 0.587, 0.114);

// MARK: - Palette (the slow green→magenta→violet colour-cycle; source shapes' sin(k·t))
static inline float3 floretPalette(float t) {
    return float3(0.55 + 0.40 * sin(0.31 * t + 0.0),
                  0.45 + 0.40 * sin(0.43 * t + 2.1),
                  0.55 + 0.40 * sin(0.27 * t + 4.0));
}

// Soft radial-gradient disc (the source's 100-gon shape with centre→edge colour). Returns an
// additive contribution: bright centre fading to the edge colour at `rad`, zero beyond.
static inline float3 floretDisc(float2 uv, float2 ctr, float rad, float3 inner, float3 outer) {
    float d = length(uv - ctr);
    float t = smoothstep(rad, 0.0, d);   // 1 at centre → 0 at the edge
    return mix(outer, inner, t) * t;
}

// MARK: - Scene fragment (loader placeholder; unused in the Floret draw branch)
fragment float4 floret_fragment(VertexOut in [[stage_in]]) {
    return float4(0.0, 0.0, 0.0, 1.0);
}

// MARK: - MV-Warp mesh functions
//
// The warp fragment samples the feedback at z²(uv_orig) (the source warp shader), so the
// per-vertex mesh warp is BYPASSED — identity here (the source's vortex pixel_eqs are
// vestigial in this edit; the z² iteration IS the feedback motion). FLORET.3 may route
// bass→rotation through a real mvWarpPerVertex if the render wants live spin.
MVWarpPerFrame mvWarpPerFrame(
    constant FeatureVector& f,
    constant StemFeatures&  stems,
    constant SceneUniforms& s
) {
    MVWarpPerFrame pf;
    pf.decay = 0.95;                  // informational (the warp fragment bakes its own fade)
    pf.zoom = 1.0; pf.rot = 0.0;
    pf.cx = 0.0; pf.cy = 0.0;
    pf.dx = 0.0; pf.dy = 0.0;
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
    return uv;   // identity — the z² fold lives in floret_warp_fragment (uv_orig)
}

// MARK: - Custom WARP fragment (the z² conformal feedback fold + seed discs)
//
// Verbatim source warp shader: sample the feedback at z²((uv_orig−0.5)·1.81)+offset, fade.
// The seed (the source's 4 custom shapes, folded in — the Nacre pattern) is added on top in
// screen space so it re-folds through z² each frame → the fractal bloom.
fragment float4 floret_warp_fragment(
    WarpVertexOut           in   [[stage_in]],
    texture2d<float>        prev [[texture(0)]],
    constant FloretUniforms& fu  [[buffer(1)]]
) {
    float2 uv = in.uv;                                   // uv_orig (the source warp ignores the mesh warp)

    // z² complex-conformal fold of the sample coordinate.
    float2 p = (uv - 0.5) * kFloretFoldScale;
    float2 z2 = float2(p.x * p.x - p.y * p.y, 2.0 * p.x * p.y);
    float3 c = prev.sample(warpSampler, z2 + kFloretFoldOffset).rgb;
    c -= kFloretWarpFade;                                // subtractive decay (faithful)

    // Seed: 4 nested colour-cycling discs near (0.3, 0.4), volume-gated (faithful
    // modwavealphabyvolume + the musical role: brighter with energy, dim-but-alive at silence).
    float  gate = (0.30 + 0.70 * clamp(fu.coreEnergy, 0.0, 1.0)) * kFloretSeedGain;
    float  t = fu.time;
    float3 pal = floretPalette(t);
    float3 seed = float3(0.0);
    seed += floretDisc(uv, float2(0.30 + 0.05 * sin(0.39 * t), 0.40 - 0.05 * cos(0.34 * t)),
                       0.135, pal,                       floretPalette(t + 1.5));
    seed += floretDisc(uv, float2(0.30 - 0.05 * sin(0.31 * t), 0.40 + 0.05 * cos(0.22 * t)),
                       0.066, floretPalette(t + 0.8),    floretPalette(t + 2.2));
    seed += floretDisc(uv, float2(0.30 + 0.05 * sin(0.30 * t), 0.40 - 0.05 * cos(0.38 * t)),
                       0.036, floretPalette(t + 2.0),    floretPalette(t + 3.0));
    seed += floretDisc(uv, float2(0.30 + 0.05 * sin(0.41 * t), 0.40 - 0.05 * cos(0.43 * t)),
                       0.012, float3(1.0),               floretPalette(t + 1.0));
    c += seed * gate;
    c += kFloretWash * pal;                              // faint ground so the field never starves

    return float4(clamp(c, 0.0, 1.0), 1.0);
}

// MARK: - Custom COMP fragment (the signature look — DISPLAY ONLY, never fed back)
//
// Verbatim source comp shader: 4 layers at k·120° (the 4th duplicates the 0th → 3-fold
// symmetry), each a radial-pulse `fract(3·uv·dist)` tiling with an unsharp high-pass
// (main − blur), max-combined, ×gain. butterchurn's blur1 is approximated by an inline
// multi-tap of `main` (the in-comp path; FLORET_PLAN §3 — switch to an FM-style blur target
// only if a render shows the foam reads mushy). Flash-safe: the staggered pulse phases keep
// ≥1 layer lit + a luminance floor (D-157), so the breath reads as expansion, not strobe.
fragment float4 floret_comp_fragment(
    VertexOut               in      [[stage_in]],
    texture2d<float>        mainTex [[texture(0)]],
    constant FloretUniforms& fu     [[buffer(1)]]
) {
    constexpr sampler m(filter::linear, address::repeat);
    float2 uv1 = (in.uv - 0.5) * fu.aspect.xy;
    float  tph = fu.time / 2.0;                          // radial-pulse phase (~2 s)
    float2 bs = fu.texel * kFloretBlurSpread;            // high-pass blur tap spread

    float3 ret1 = float3(0.0);
    for (int k = 0; k < 4; ++k) {
        float ang = float(k) * 2.0943951;               // k · 120°
        float ca = cos(ang), sa = sin(ang);
        float2 uvr = float2(ca * uv1.x - sa * uv1.y, sa * uv1.x + ca * uv1.y);
        float dist  = 1.0 - fract(float(k) / 3.0 + tph);
        float inten = sqrt(dist) * (1.0 - dist) * 8.0;
        float2 tile = fract(3.0 * uvr * dist + 0.5 + 0.025);   // q1=q2=0.5 → +0.025

        // Unsharp high-pass: main − blur(main). Inline 5-tap (cross) blur stands in for blur1.
        float3 mc = mainTex.sample(m, tile).rgb;
        float3 blur = mc * 2.0
                    + mainTex.sample(m, tile + float2( bs.x, 0)).rgb
                    + mainTex.sample(m, tile + float2(-bs.x, 0)).rgb
                    + mainTex.sample(m, tile + float2(0,  bs.y)).rgb
                    + mainTex.sample(m, tile + float2(0, -bs.y)).rgb;
        blur *= (1.0 / 6.0);
        float3 neu = mc - blur * kFloretHighpass;
        ret1 = max(ret1, neu * inten);
    }
    float3 ret = ret1 * kFloretCompGain;

    // Flash-safety floor (D-157): lift the trough so the radial pulse reads as expanding
    // light, not a full-field dark↔bright strobe (the source's near-black-trough breathing
    // would fail the cert flash gate). A faint palette-tinted floor, not a grey wash.
    ret = max(ret, kFloretLumaFloor * floretPalette(fu.time) * 0.5);

    // sRGB round-trip cancellation (D-139): decode so the drawable's sRGB encode restores the
    // intended display value (keeps the ground deep against the bright bloom).
    float3 v = saturate(ret);
    float3 lin = select(v / 12.92, pow((v + 0.055) / 1.055, float3(2.4)), v > 0.04045);
    return float4(lin, 1.0);
}
