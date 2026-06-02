// FataMorgana.metal — faithful port of the Milkdrop/butterchurn builtin
// `martin [shadow harlequins shape code] - fata morgana` (D-139).
//
// A MIRAGE: starfield night sky + glowing horizon + reflective rippling neon
// floor. Built — per the butterchurn source (read wholesale, FA #70) — from a
// custom feedback WARP shader, a custom procedural COMP shader (the mirage
// projection), and 4 custom SHAPES (40-gons; L2). The render loop is the D-138
// structure: warp(prev) → blur → shapes-on-top (= the feedback) → comp
// (display-only) → swap. See docs/presets/FATA_MORGANA_PLAN.md and the decode
// in /tmp/fata_faithful_checklist.md.
//
// Increment FM.L1 — the mirage SUBSTRATE (warp + comp + blur), no shapes yet.
//
// The functions are looked up by name by PresetLoader.makeWarpPipelines when the
// preset's fragment_function prefix is `fata_morgana`:
//   · fata_morgana_warp_fragment  — custom feedback warp (blur-driven rotation +
//                                    lattice distortion; bakes its own decay)
//   · fata_morgana_comp_fragment  — the mirage (display-only blit)
//   · fata_morgana_blur_fragment  — multi-tap blur of the previous frame (the
//                                    butterchurn `blur1` approximation)
// All three fall back to the shared mvWarp_* defaults for every OTHER preset
// (whose libraries don't define these symbols) — so the gating is structural.
//
// SceneUniforms / MVWarpPerFrame / WarpVertexOut / VertexOut / fullscreen_vertex
// / FeatureVector / StemFeatures come from the mvWarp preamble + Common.metal.

// MARK: - Fata uniforms (CPU-computed per frame; matches FataUniforms in Swift)

// Bound at fragment buffer(1) of the warp + comp passes. Carries the butterchurn
// builtins those custom shaders reference (time, the q1/q2 beat-rotation cos/sin,
// the roaming sin vectors, rand_preset, and the feedback texture size).
struct FataUniforms {
    float  time;        // seconds (energy-weighted accumulated_audio_time)
    float  q1;          // cos(rott) — beat-rotation accumulator (frame_eqs)
    float  q2;          // sin(rott)
    float  gammaAdj;    // 1.98 (unused: custom comp replaces fixed-function; kept for parity)
    float4 texsize;     // xy = feedback px size, zw = 1/size
    float4 roamSin;     // [0.5+0.5 sin(t·{0.3,1.3,5,20})]
    float4 slowRoamSin; // [0.5+0.5 sin(t·{0.005,0.008,0.013,0.022})]
    float4 randPreset;  // fixed per-load random vec4 (the comp's blue-gradient scale)
};

// MARK: - Samplers

// The warp samples the feedback with REPEAT wrapping — butterchurn's warp `uv_1`
// carries a net −1.0 offset (two −0.5 terms) that is a no-op only under wrap
// (uv−1 ≡ uv). Replicated verbatim; the wrap makes it identity. (checklist §WARP)
constexpr sampler fataWrap(filter::linear, address::repeat);
constexpr sampler fataClamp(filter::linear, address::clamp_to_edge);

// MARK: - Direct background fragment
//
// Unused in the live fata render path (the mirage is built by warp + shapes +
// comp, like Dragon Bloom's strands-on-top branch skips the scene pass), but the
// loader needs a `fragment_function` to build the direct pipeline. Near-black.
fragment float4 fata_morgana_fragment(VertexOut in [[stage_in]]) {
    return float4(0.0, 0.0, 0.0, 1.0);
}

// MARK: - MV-Warp mesh functions (the per_pixel warp)
//
// Source per_pixel is just `zoom = 1.05` (constant 5% magnify → content flows
// OUTWARD each frame). baseVals warp/rot are negligible (warp 0.01). The custom
// warp FRAGMENT adds the blur-driven rotation + lattice on top of this mesh UV.

MVWarpPerFrame mvWarpPerFrame(
    constant FeatureVector& f,
    constant StemFeatures&  stems,
    constant SceneUniforms& s
) {
    MVWarpPerFrame pf;
    pf.zoom = 1.05;          // source per_pixel zoom (constant)
    pf.rot  = 0.0;
    pf.decay = 1.0;          // custom warp bakes its own decay (×0.98 − 0.02); no compose decay
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
    // Constant inward sample by 1/zoom about centre → on-screen content magnifies
    // 1.05× (flows outward) through the feedback. The custom warp fragment then
    // displaces from here.
    float2 centre = float2(0.5, 0.5);
    float2 p      = (uv - centre) / max(pf.zoom, 0.001);
    return p + centre;
}

// MARK: - Custom WARP fragment (the feedback warp)
//
// Verbatim transcription of the converted butterchurn warp body (checklist §WARP):
//   c     = blur1(uv)·scale1 + bias1                       (blur stored in colour space ⇒ scale1=1,bias1=0)
//   rot   = dot(vec4(c,0), roam_sin) · 16
//   uv1   = (uv−0.5) + 0.2·luma(c)·rotate(uv−0.5, rot) − 0.5   (net −1.0 ≡ no-op under wrap)
//   t     = uv1 · texsize.xy · 0.02
//   lat   = (cos(t.y·q1)·sin(−t.y), sin(t.x)·cos(t.y·q2))
//   uv1  -= lat · texsize.zw · 12
//   ret   = main(uv1)·0.98 − 0.02                          (the baked decay / black-point lift)
fragment float4 fata_morgana_warp_fragment(
    WarpVertexOut         in    [[stage_in]],
    texture2d<float>      prev  [[texture(0)]],
    texture2d<float>      blur  [[texture(1)]],
    constant FataUniforms& u    [[buffer(1)]]
) {
    float2 uv = in.warped_uv;
    float3 c  = blur.sample(fataClamp, uv).rgb;          // scale1=1, bias1=0

    float  rot = dot(float4(c, 0.0), u.roamSin) * 16.0;
    float  cr  = cos(rot), sr = sin(rot);
    float2 p   = uv - 0.5;
    float2 rotP = float2(p.x * cr - p.y * sr, p.x * sr + p.y * cr);   // GLSL v*mat2 rotation
    float  luma = dot(c, float3(0.32, 0.49, 0.29));
    float2 uv1 = (p + 0.2 * luma * rotP) - 0.5;          // verbatim double −0.5 (wrap no-op)

    float2 t = (uv1 * u.texsize.xy) * 0.02;
    float2 lat = float2(cos(t.y * u.q1) * sin(-t.y),
                        sin(t.x)        * cos(t.y * u.q2));
    uv1 = uv1 - (lat * u.texsize.zw) * 12.0;

    float3 ret = prev.sample(fataWrap, uv1).rgb * 0.98 - 0.02;   // baked decay
    return float4(ret, 1.0);
}

// MARK: - Custom COMP fragment (the mirage — display only)
//
// Verbatim transcription of the converted butterchurn comp body (checklist §COMP).
// A custom comp FULLY REPLACES fixed-function — no gamma/darken/echo/invert.
// Shader `uv` is Y-flipped vs vUv. noise_hq → slot 5 (noiseHQ), pw_noise_lq →
// slot 4 (noiseLQ). The `main` texture is the warped+shapes feedback target.
fragment float4 fata_morgana_comp_fragment(
    VertexOut              in        [[stage_in]],
    texture2d<float>       mainTex   [[texture(0)]],
    texture2d<float>       noiseLQ   [[texture(4)]],   // pw_noise_lq
    texture2d<float>       noiseHQ   [[texture(5)]],   // noise_hq
    constant FataUniforms& u         [[buffer(1)]]
) {
    constexpr sampler nWrap(filter::linear, address::repeat);
    // butterchurn's comp does `uv.y = 1.0 - vUv.y` on a BOTTOM-left-origin vUv.
    // Phosphene's fullscreen_vertex emits TOP-left-origin uv (uv.y=0 at top), i.e.
    // in.uv.y = 1 - vUv.y already — so the butterchurn flip resolves to in.uv
    // directly. (An explicit `1.0 - in.uv.y` double-flips → sky/water reversed.)
    float2 uv = in.uv;
    float2 uv1 = uv - 0.5;

    // Perspective floor/ceiling + scrolling ground noise (starfield in the sky).
    float  z  = 0.2 / abs(uv1.y);
    float2 rs = float2(uv1.x * z, z / 2.0 + u.time * 4.0);
    float3 n  = noiseHQ.sample(nWrap, rs).rrr;          // r8 noise → replicate to rgb
    n = (n * step(0.0, n)) - 0.6;

    float  m = clamp(128.0 * uv1.y, 0.0, 1.0);          // 1 top half, 0 bottom

    // Floor reflection sample of the feedback.
    float2 p = fract((uv1 * (1.0 - abs(uv1.x)) - 0.5) - (n.xy * 0.05) * m);
    float  xf = p.y - 0.52;
    float3 col = mainTex.sample(fataClamp, p).rgb
               + (0.02 / (0.02 + abs(xf))) * u.slowRoamSin.xyz;   // horizon glow line

    // Neon grid.
    float2x2 gm = float2x2(0.6, -0.8, 0.8, 0.6);        // columns (0.6,-0.8),(0.8,0.6)
    float2 g  = 32.0 * ((uv * gm) + (col * 0.1).xy + u.time / 64.0);
    float2 gt = abs(fract(g) - 0.5);
    float  gv = clamp((0.25 / sqrt(dot(gt, gt)))
                      * (noiseLQ.sample(nWrap, g / 256.0).r - 0.9), 0.0, 1.0);

    float3 ret = col + (gv * gv + (u.randPreset.xyz * (0.5 - uv.y)) * float3(0.0, 0.0, 1.0)) * (1.0 - m);
    return float4(saturate(ret), 1.0);
}

// MARK: - Blur fragment (butterchurn blur1 approximation)
//
// Phosphene has no blur-mip chain; approximate butterchurn's `blur1` (the warp's
// low-frequency feedback read) with a 9-tap separable-ish gaussian of the prev
// frame, stored in colour space so the warp's scale1=1 / bias1=0. Radius ≈ a few
// px; the warp only uses blur1 for a luma-weighted rotation/displacement, so an
// exact gaussian isn't needed — a smooth low-pass is.
fragment float4 fata_morgana_blur_fragment(
    VertexOut              in   [[stage_in]],
    texture2d<float>       src  [[texture(0)]],
    constant FataUniforms& u    [[buffer(1)]]
) {
    float2 px = u.texsize.zw;                            // 1/size
    float3 acc = float3(0.0);
    // 3×3 gaussian (1 2 1 / 2 4 2 / 1 2 1) / 16, radius 2 px.
    const float w[9] = { 1, 2, 1, 2, 4, 2, 1, 2, 1 };
    int i = 0;
    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            float2 o = float2(float(dx), float(dy)) * px * 2.0;
            acc += src.sample(fataClamp, in.uv + o).rgb * w[i];
            i++;
        }
    }
    return float4(acc / 16.0, 1.0);
}
