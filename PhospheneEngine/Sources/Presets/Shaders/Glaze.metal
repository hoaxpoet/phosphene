// Glaze.metal — Phosphene port of the Milkdrop/butterchurn builtin
// `Flexi + stahlregen - jelly showoff parade` (cream-of-crop legends; the glossy
// "wet jelly" contour-gel). See docs/presets/GLAZE_PLAN.md +
// docs/VISUAL_REFERENCES/glaze/ (source_shaders.txt + the raw warp/comp HLSL = the port spec).
//
// Character: nested concentric contour-ring striations under a thick embossed gel sheen
// (specular highlights + dark rims), a saturated neon palette that rotates, on an accreting
// feedback field — flowing as a spring-mass "jelly" drags a swirl-poke across it.
//
// ── INCREMENT STATUS — GLAZE.2b.2 (the FAITHFUL BASE) ──────────────────────────────
// Faithful HLSL→MSL port of the source warp + comp (FA #73 — port, don't re-derive):
//   · warp = blur1 emboss gradient → per-channel decoupled flow (R unsharp+grow, G/B max of
//            flowed taps) + the pixel-eq swirl-poke around the spring tail + [0,1] clamp
//            (the source's 8-bit feedback bound; an unclamped float loop blooms — Nacre lesson).
//            The R-channel `+0.006` self-seeds the field from black (no separate seed needed).
//   · comp = multi-scale unsharp/bandpass from blur1/2/3 (0.8·blur3−blur1 + 0.6·blur1 −
//            (blur2−blur1) + 1.2·main) + dual-direction gradient sampling + palette hue +
//            `ret*ret`/`sqrt` contrast + sRGB-decode.
// The 3-mass spring runs CPU-side (RenderPipeline+Glaze); at silence the anchor is a slow
// time-driven idle (audio drive → GLAZE.3). butterchurn-only uniforms substituted: hue_shader
// → glazePalette(time); scale*/bias* → identity (we store linear blur); texsize.zw → gu.texel.
// The greenlit uplifts (A per-stem, B HDR bloom, C shiver) are GLAZE.5+ (after Matt's M7).
//
// SceneUniforms / MVWarpPerFrame / WarpVertexOut / VertexOut / fullscreen_vertex /
// FeatureVector / StemFeatures / warpSampler come from the mvWarp preamble + Common.metal.

// MARK: - GlazeUniforms (CPU-computed per frame; matches GlazeUniforms in Swift)
//
// Bound at fragment buffer(1) of the warp + comp passes. 32 bytes — see GlazeUniforms in
// RenderPipeline+Glaze.swift for the byte layout.
struct GlazeUniforms {
    float  time;          // features.time — palette rotation
    float  coreEnergy;    // reserved (silence-floor lever; faithful warp self-seeds via +0.006)
    float  pokeStrength;  // pixel-eq poke scale (spring mass-3 x → `q3`)
    float  seedY;         // spring tail Y → the seed band's vertical centre (GLAZE.3b audio fill)
    float2 texel;         // (1/feedbackW, 1/feedbackH) = the source's texsize.zw
    float2 pokeCenter;    // spring tail position (cx1, cy1) — the swirl-poke centre
};

// MARK: - Constants

constant float3 kGlazeLuma = float3(0.32, 0.49, 0.29);   // the source's exact luma weight
constant float  kGlazePokeRadius = 0.2;                  // source pixel_eqs `r = .2`
// The source runs decay 1.0 on an 8-bit feedback whose quantisation + butterchurn dynamics
// bound the R-channel +0.006 grow; on our float buffer that grow floods to white (the Nacre
// float-bloom lesson). A gentle decay equilibrates R at ~0.006·d/(1−d) instead of saturating.
constant float  kGlazeWarpDecay = 0.96;   // persistence = how many nested seed-rings the zoom accretes

// MARK: - Palette (the source's saturated neon rotation; substitutes butterchurn hue_shader)
// Slow red→green→teal→violet drift. Values in [0.2, 1.0] so the comp's `pow(hue, g9)` mix
// reads as a hue tint, not a brightness change.
static inline float3 glazePalette(float t) {
    return float3(0.60 + 0.40 * sin(0.27 * t + 0.0),
                  0.60 + 0.40 * sin(0.31 * t + 2.1),
                  0.60 + 0.40 * sin(0.23 * t + 4.2));
}

static inline float glazeHash(float2 p) {
    return fract(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453);
}
static inline float glazeValueNoise(float2 p) {
    float2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = glazeHash(i), b = glazeHash(i + float2(1.0, 0.0));
    float c = glazeHash(i + float2(0.0, 1.0)), d = glazeHash(i + float2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// MARK: - Scene fragment (loader placeholder; unused in the Glaze draw branch)
fragment float4 glaze_fragment(VertexOut in [[stage_in]]) {
    return float4(0.0, 0.0, 0.0, 1.0);
}

// MARK: - MV-Warp mesh functions (per-vertex feedback transform)
//
// Source per-frame overrides: zoom 1.001 (≈identity), rot 0, warp 0.2. The strong baseVals
// zoom 1.06/zoomexp is overridden to 1.001 by the frame_eqs — the inward flow comes from the
// accreting feedback + the fragment poke, NOT a big zoom. A slight zoom + a gentle warp ripple
// + a slow roam keep the field flowing + alive at silence. The swirl-poke is applied in the
// FRAGMENT (the vertex stage can't receive the CPU spring state).
// Source baseVals carried as constants (frame_eqs override zoom→1.001, rot→0, warp→0.2).
constant float kGlazeZoom     = 1.001;    // per-frame zoom (the zoomexp radial weighting does the work)
constant float kGlazeZoomExp  = 11.56;    // baseVals zoomexp — strong edge-inward flow → concentric rings
constant float kGlazeWarp     = 0.2;      // per-frame warp ripple amplitude
constant float kGlazeWarpScaleInv = 1.0 / 16.016;   // baseVals warpscale

MVWarpPerFrame mvWarpPerFrame(
    constant FeatureVector& f,
    constant StemFeatures&  stems,
    constant SceneUniforms& s
) {
    MVWarpPerFrame pf;
    pf.decay = 1.0;                          // source decay 1.0 (the warp's bounding decay caps it)
    pf.zoom = kGlazeZoom; pf.rot = 0.0; pf.warp = kGlazeWarp;
    pf.cx = 0.0; pf.cy = 0.0; pf.dx = 0.0; pf.dy = 0.0; pf.sx = 1.0; pf.sy = 1.0;
    pf.q1 = 0.0; pf.q2 = 0.0; pf.q3 = 0.0; pf.q4 = 0.0;
    pf.q5 = 0.0; pf.q6 = 0.0; pf.q7 = 0.0; pf.q8 = 0.0;
    return pf;
}

// Faithful port of butterchurn's per-vertex warp mesh (butterchurn.js L2627–2660):
// the zoomexp radial zoom (near-identity at centre, strong inward at the edges → the
// concentric contour rings) + the 4-term time-varying warp ripple + rot + translation.
// The pixel-eq swirl-poke runs in the fragment (the vertex stage can't see the CPU spring).
float2 mvWarpPerVertex(
    float2 uv, float rad, float ang,
    thread const MVWarpPerFrame& pf,
    constant FeatureVector& f,
    constant StemFeatures& stems
) {
    // zoomexp radial zoom: zoom2V = pow(zoom, pow(zoomExp, rad*2−1)). rad ∈ [0, ~1.414].
    float zoom2V = pow(max(pf.zoom, 1e-4), pow(kGlazeZoomExp, rad * 2.0 - 1.0));
    zoom2V = clamp(zoom2V, 0.5, 4.0);
    float2 c = float2(0.5 + pf.cx, 0.5 + pf.cy);
    float2 sp = 0.5 + (uv - 0.5) / zoom2V;          // contract toward centre (inward flow)
    sp = (sp - c) / float2(pf.sx, pf.sy) + c;        // sx/sy stretch

    // 4-term time-varying warp ripple (butterchurn warpf0–3 + warpScaleInv).
    if (pf.warp != 0.0) {
        float x = (uv.x - 0.5) * 2.0, y = (uv.y - 0.5) * 2.0;   // NDC [-1,1]
        float wt = f.time;                                     // warpTimeV (warpanimspeed 1)
        float wf0 = 11.68 + 4.0 * cos(wt * 1.413 + 10.0);
        float wf1 =  8.77 + 3.0 * cos(wt * 1.113 +  7.0);
        float wf2 = 10.54 + 3.0 * cos(wt * 1.233 +  3.0);
        float wf3 = 11.49 + 4.0 * cos(wt * 0.933 +  5.0);
        float a = pf.warp * 0.0035, wsi = kGlazeWarpScaleInv;
        sp.x += a * sin(wt * 0.333 + wsi * (x * wf0 - y * wf3));
        sp.y += a * cos(wt * 0.375 - wsi * (x * wf2 + y * wf1));
        sp.x += a * cos(wt * 0.753 - wsi * (x * wf1 - y * wf2));
        sp.y += a * sin(wt * 0.825 + wsi * (x * wf0 + y * wf3));
    }
    // rotation about (cx,cy) + translation.
    float2 d = sp - c;
    float co = cos(pf.rot), si = sin(pf.rot);
    sp = float2(d.x * co - d.y * si, d.x * si + d.y * co) + c - float2(pf.dx, pf.dy);
    return sp;
}

// MARK: - Blur pyramid (GLAZE.2b.1) — butterchurn sampler_blur1/2/3
//
// One 9-tap (1-2-4) gaussian run three times into progressively smaller targets (blur1 ½-res
// ← prev, blur2 ¼ ← blur1, blur3 ⅛ ← blur2) — the resolution halving widens each level. `src`
// is the previous level; tap spacing from its own texel size.
fragment float4 glaze_blur_fragment(
    VertexOut        in  [[stage_in]],
    texture2d<float> src [[texture(0)]]
) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float2 t = float2(1.0 / float(src.get_width()), 1.0 / float(src.get_height())) * 1.5;
    float3 c = src.sample(s, in.uv).rgb * 4.0;
    c += (src.sample(s, in.uv + float2( t.x, 0)).rgb + src.sample(s, in.uv + float2(-t.x, 0)).rgb +
          src.sample(s, in.uv + float2(0,  t.y)).rgb + src.sample(s, in.uv + float2(0, -t.y)).rgb) * 2.0;
    c += (src.sample(s, in.uv + t).rgb + src.sample(s, in.uv - t).rgb +
          src.sample(s, in.uv + float2( t.x, -t.y)).rgb + src.sample(s, in.uv + float2(-t.x, t.y)).rgb);
    return float4(c * (1.0 / 16.0), 1.0);
}

// MARK: - Custom WARP fragment (the feedback transfer — faithful port of warp.hlsl)
//
// blur1 Sobel gradient (8-texel taps) → per-channel decoupled flow: R unsharps against blur2
// and grows (+0.006, self-seeding from black); B = max(blur1 edge, B flowed along the perp +
// blue gradient, −0.008 decay); G = max(R, G flowed along the green gradient, −0.016 decay).
// The differing per-channel flow + decay = the chromatic trailing. Plus the pixel-eq swirl-poke
// around the spring tail. [0,1] clamp = the source's 8-bit feedback bound (Nacre lesson).
fragment float4 glaze_warp_fragment(
    WarpVertexOut           in    [[stage_in]],
    texture2d<float>        prev  [[texture(0)]],   // sampler_main / sampler_fc_main
    texture2d<float>        blur1 [[texture(1)]],
    texture2d<float>        blur2 [[texture(2)]],
    constant GlazeUniforms& gu    [[buffer(1)]]
) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);

    // Pixel-eq swirl-poke (source pixel_eqs): within radius r of the spring tail, a curl
    // displacement scaled by pokeStrength, dragged across the field as the jelly bounces.
    float2 dpc = in.uv - gu.pokeCenter;
    float  dd  = dot(dpc, dpc);
    float  r2  = kGlazePokeRadius * kGlazePokeRadius;
    float  dir = (dd < r2) ? -(r2 - dd) * gu.pokeStrength : 0.0;
    float2 poke = float2(sin(in.uv.y - gu.pokeCenter.y) * dir, -sin(in.uv.x - gu.pokeCenter.x) * dir);

    float2 uv1 = 0.5 + (in.warped_uv - 0.5) * 1.002 + poke;
    float2 g   = gu.texel * 8.0;
    float3 gx  = blur1.sample(s, uv1 + float2(g.x, 0)).rgb - blur1.sample(s, uv1 - float2(g.x, 0)).rgb;
    float3 gy  = blur1.sample(s, uv1 + float2(0, g.y)).rgb - blur1.sample(s, uv1 - float2(0, g.y)).rgb;

    float3 ret;
    float2 flow = fract(uv1 - float2(gx.x, gy.x) * gu.texel);   // sample prev along the red gradient
    // R = the advected feedback ONLY. NO in-warp unsharp (the GLAZE.2b.2 grain root cause):
    // the source's `(main−blur2)*0.4` unsharp is a high-pass boost with feedback gain > 1, so on
    // our float buffer it compounds into a razor-filament sharpening instability = the grain (the
    // source's 8-bit storage quantizes the runaway; we can't). Sharpening is DISPLAY-only — the
    // comp embosses the smooth feedback into the gel sheen, never fed back. And NO +0.006 uniform
    // grow (it floods the ground grey + isn't needed — the explicit curve seed below provides the
    // structure; dropping it keeps the oracle's dark ground). The rings come from persistence:
    // the zoom carries each frame's seed outward, the decay sets how many nested rings persist.
    ret.x = prev.sample(s, flow).x;
    // B: max(blur1 edge threshold, B flowed along perp + blue gradient, decay −0.008).
    float2 perp = float2(gy.x, -gx.x);
    float2 gz   = float2(gx.z, gy.z);
    float2 uvB  = uv1 - perp * gu.texel * 8.0 + gz * gu.texel * 4.0;
    ret.z = max(clamp(blur1.sample(s, uv1).x - 0.3, 0.0, 1.0) * 2.0, prev.sample(s, uvB).z - 0.008);
    // G: max(R, G flowed along the green gradient, decay −0.016).
    ret.y = max(ret.x, prev.sample(s, uv1 + float2(gx.y, gy.y) * gu.texel).y - 0.016);

    // Structure SEED (the source's waveform `wave_a 0.207` role): a uniform field has no
    // gradient → the zoomexp flow + unsharp have nothing to propagate. Inject a bright spot at
    // the spring poke (the zoomexp carries it outward into concentric rings) + a faint
    // time-varying noise floor so the field is alive + structured at silence (D-019).
    // The seed is a CURVE (the source's waveform `wave_a 0.207`), not a point — the zoomexp flow
    // rings a curve into nested CONCENTRIC contours (a point → radial rays). GLAZE.3b: the curve's
    // vertical centre rides the audio-driven spring tail (`gu.seedY`), so the bright band sweeps
    // the whole frame as the jelly bounces (filling the field); a slow time wiggle keeps it organic
    // and alive when the tail idles at silence.
    float yCurve = gu.seedY + 0.16 * sin(in.uv.x * 8.0 + gu.time * 0.6)
                            + 0.07 * sin(in.uv.x * 15.0 - gu.time * 0.4);
    float dCurve = in.uv.y - yCurve;
    // A bright curve (the waveform) + a faint LOW-frequency noise field. The noise now fills the
    // frame with smooth contour variation the zoom accretes into nested rings — safe only because
    // the unsharp instability is gone (it would have amplified any noise into grain before).
    float seed = exp(-dCurve * dCurve * 500.0) * 0.12
               + (glazeValueNoise(in.uv * 2.0 + gu.time * 0.03) - 0.5) * 0.03;
    ret.x += seed; ret.y += seed;

    // Bounding decay (the float-bloom fix; the source's 8-bit storage bounded this implicitly).
    return float4(clamp(ret * kGlazeWarpDecay, 0.0, 1.0), 1.0);
}

// MARK: - Custom COMP fragment (the display look — faithful port of comp.hlsl, DISPLAY ONLY)
//
// blur1 luminance Sobel (6-texel) → dual-direction gradient-displaced sampling (uvA/uvB);
// multi-scale unsharp/bandpass: 0.8·blur3(uvA) − blur1(uvA) + 0.6·blur1(uv) − (blur2(uvB) −
// blur1(uvB)) + 1.2·main(uvB) + 0.15·blur1(uvB) + 1.0 → the glossy embossed gel sheen. Then
// the palette hue mix, `ret*ret`/`sqrt` contrast, and the sRGB-decode (FM/Nacre, D-139).
fragment float4 glaze_comp_fragment(
    VertexOut               in      [[stage_in]],
    texture2d<float>        mainTex [[texture(0)]],   // composeTexture (the warped feedback)
    texture2d<float>        blur1   [[texture(1)]],
    texture2d<float>        blur2   [[texture(2)]],
    texture2d<float>        blur3   [[texture(3)]],
    constant GlazeUniforms& gu      [[buffer(1)]]
) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float2 uv = in.uv;
    float2 g  = gu.texel * 6.0;
    float3 gx = blur1.sample(s, uv + float2(g.x, 0)).rgb - blur1.sample(s, uv - float2(g.x, 0)).rgb;
    float3 gy = blur1.sample(s, uv + float2(0, g.y)).rgb - blur1.sample(s, uv - float2(0, g.y)).rgb;
    float2 lum = float2(dot(gx, kGlazeLuma), dot(gy, kGlazeLuma));
    float2 uvA = uv - 0.25 * lum;
    float2 uvB = uv + 0.25 * lum;

    float3 ret = 0.8 * blur3.sample(s, uvA).rgb - blur1.sample(s, uvA).rgb;
    ret += 0.6 * blur1.sample(s, uv).rgb;
    ret -= (blur2.sample(s, uvB).rgb - blur1.sample(s, uvB).rgb);
    ret += 1.2 * mainTex.sample(s, uvB).rgb + 0.15 * blur1.sample(s, uvB).rgb;
    ret += 1.0;

    float  g9 = dot(ret, kGlazeLuma);
    float3 tint = 0.75 * float3(g9) * dot(0.6 * blur3.sample(s, uvA).rgb
                  - 0.7 * mainTex.sample(s, uv).rgb - 0.3 * blur1.sample(s, uvB).rgb, kGlazeLuma);
    ret = mix(float3(g9), tint, pow(glazePalette(gu.time), float3(g9))) * 0.9;
    ret = ret * ret;
    ret = sqrt(ret);

    // sRGB round-trip cancellation (FM/Nacre fix, D-139): decode so the .bgra8Unorm_srgb
    // drawable's encode round-trips back to the intended (sRGB-naive) display value.
    float3 v = saturate(ret);
    float3 lin = select(v / 12.92, pow((v + 0.055) / 1.055, float3(2.4)), v > 0.04045);
    return float4(lin, 1.0);
}
