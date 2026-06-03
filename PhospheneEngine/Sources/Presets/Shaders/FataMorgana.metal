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
    texture2d<float>       blueNoise [[texture(8)]],   // scattered point noise (the stars)
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

    // Neon grid → scattered STARS. Source samples pw_noise_lq (a point-wrap noise
    // with many high values); Phosphene's noiseLQ is smooth FBM that rarely exceeds
    // the 0.9 gate (→ no stars), so use the scattered blueNoise instead — its high
    // values are spatially isolated, giving crisp star points along the grid.
    float2x2 gm = float2x2(0.6, -0.8, 0.8, 0.6);        // columns (0.6,-0.8),(0.8,0.6)
    float2 g  = 32.0 * ((uv * gm) + (col * 0.1).xy + u.time / 64.0);
    float2 gt = abs(fract(g) - 0.5);
    float  gv = clamp((0.25 / sqrt(dot(gt, gt)))
                      * (blueNoise.sample(nWrap, g / 256.0).r - 0.82), 0.0, 1.0);

    float3 ret = col + (gv * gv + (u.randPreset.xyz * (0.5 - uv.y)) * float3(0.0, 0.0, 1.0)) * (1.0 - m);
    return float4(saturate(ret), 1.0);
}

// MARK: - Custom SHAPES (FM.L2) — 4 forty-gon n-gons drawn on top of the warp
//
// Faithful to butterchurn's CustomShape (source ~L4589): TRIANGLE_FAN per
// instance, CENTER vertex = primary colour (r,g,b,a), perimeter = secondary
// (r2,g2,b2,a2). For all 4 fata shapes the rim secondary is (0,0,0,0), so the
// additive shapes (1/2/3) read as a bright cycled centre fading to transparent =
// soft neon blobs; shape 0 is a faint textured central echo. Metal has no
// TRIANGLE_FAN, so the fan is expanded to a triangle LIST in the vertex shader:
// `sides` triangles × 3 verts; tri t = (center, perimeter[t], perimeter[t+1]).
// Drawn ON TOP of the warped composeTexture (= the feedback), like DB strands.
//
// Per-instance frame_eqs transcribed from source (orbit + colour cycle); the 3
// additive shapes' radius = baseVals.rad × the band attack (the source uses
// {mid,bass,treb}_att — that IS the faithful copy; the stem map is the L-uplift).

struct FataShapeParams {
    int   shapeIndex;   // 0 textured echo, 1 mid, 2 bass, 3 treb
    int   sides;        // 30 (shape 0) or 40
    int   numInst;      // instances (1/4/1/5)
    float frame;        // butterchurn frame counter (colour cycle + shape-0 rotation)
    float aspectY;      // texsizeY/texsizeX (keeps n-gons round on a wide canvas)
    float audioBoost;   // multiplies the band attack driving the blob radius
    float pad0; float pad1;
};

struct FataShapeVtxOut {
    float4 position [[position]];
    float4 color;
    float2 uv;
    float  textured;
};

// div(a,b) — Milkdrop's guarded divide (b==0 ⇒ 0), used by shapes 1/3 orbits.
static float fataDiv(float a, float b) { return (b == 0.0) ? 0.0 : a / b; }

vertex FataShapeVtxOut fata_shape_vertex(
    uint                      vid [[vertex_id]],
    uint                      iid [[instance_id]],
    constant FeatureVector&   f   [[buffer(0)]],
    constant FataShapeParams& sp  [[buffer(1)]]
) {
    int   sides  = sp.sides;
    int   tri    = int(vid) / 3;
    int   corner = int(vid) % 3;
    float time   = f.time;
    int   inst   = int(iid);

    // ── per-instance frame_eqs (source verbatim) ─────────────────────────────
    float x = 0.5, y = 0.5, rad = 0.1, ang = 0.0, aCenter = 1.0;
    float cyc = 0.5 * sp.frame;
    // colour cycle: r=sin(cyc), b=sin(cyc+2.094), g=sin(cyc+4.188)
    float3 col = float3(0.5 + 0.5 * sin(cyc),
                        0.5 + 0.5 * sin(cyc + 4.188),
                        0.5 + 0.5 * sin(cyc + 2.094));
    if (sp.shapeIndex == 0) {
        rad = 0.06623; ang = 0.02 * sp.frame; x = 0.5; y = 0.5;
        col = float3(0.0); aCenter = 0.1;                 // faint textured echo
    } else if (sp.shapeIndex == 1) {                       // mid
        float d = 0.7 * fataDiv(time, float(inst));
        x = 0.5 + 0.225 * sin(d); y = 0.5 + 0.3 * cos(d);
        x -= 0.4 * x * sin(time);  y -= 0.4 * y * cos(time);
        rad = 0.1 * (f.mid_att * sp.audioBoost);
    } else if (sp.shapeIndex == 2) {                       // bass
        x = 0.5 + 0.225 * sin(time + 2.09); y = 0.5 + 0.3 * cos(time + 2.09);
        rad = 0.1 * (f.bass_att * sp.audioBoost);
    } else {                                               // treb
        float d = fataDiv(time, float(inst));
        x = 0.5 + 0.225 * sin(d); y = 0.5 + 0.3 * cos(d);
        x += 0.4 * x * sin(time);  y += 0.4 * y * cos(time);
        rad = 0.07419 * (f.treb_att * sp.audioBoost);
    }

    float xn = x * 2.0 - 1.0;
    float yn = y * -2.0 + 1.0;     // butterchurn frame.y*-2+1 (y=0 → NDC top)
    float quarterPi = M_PI_F * 0.25;

    // Additive blobs injected BRIGHTER than the source's [0,1] colour (HDR). Phosphene's
    // feedback accumulates less than butterchurn's minutes-long run (the warp's
    // ×0.98−0.02 self-regulation), so a single-frame blob carries less luminous content
    // for the floor reflection + horizon glow to pick up; the brightness compensates so
    // the water reflection + colored horizon read at oracle strength. (Shape 0 textured
    // echo unaffected — its colour is near-zero by design.) FM.L2 live-M7 finding.
    constexpr float kBlobBrightness = 2.2;
    if (sp.shapeIndex != 0) { col *= kBlobBrightness; }

    FataShapeVtxOut out;
    out.textured = (sp.shapeIndex == 0) ? 1.0 : 0.0;
    if (corner == 0) {
        out.position = float4(xn, yn, 0.0, 1.0);
        out.color    = float4(col, aCenter);              // CENTER = primary
        out.uv       = float2(0.5, 0.5);
    } else {
        int   k = (corner == 1) ? tri : (tri + 1);        // perimeter vertex, wraps
        float p = float(k) / float(sides);
        float angSum = p * 2.0 * M_PI_F + ang + quarterPi;
        out.position = float4(xn + rad * cos(angSum) * sp.aspectY,
                              yn + rad * sin(angSum), 0.0, 1.0);
        out.color    = float4(0.0, 0.0, 0.0, 0.0);        // RIM = secondary (0 for all 4 shapes)
        float texZoom = (sp.shapeIndex == 0) ? 1.79845 : 1.0;
        float texAngSum = p * 2.0 * M_PI_F + quarterPi;   // tex_ang = 0
        out.uv = float2(0.5 + 0.5 * cos(texAngSum) / texZoom * sp.aspectY,
                        0.5 + 0.5 * sin(texAngSum) / texZoom);
    }
    return out;
}

fragment float4 fata_shape_fragment(
    FataShapeVtxOut  in   [[stage_in]],
    texture2d<float> prev [[texture(0)]]
) {
    if (in.textured > 0.5) {
        constexpr sampler s(filter::linear, address::repeat);
        return prev.sample(s, in.uv) * in.color;          // textured echo (shape 0)
    }
    return in.color;                                       // additive blob colour
}

// MARK: - Blur fragment (butterchurn blur1 approximation)
//
// Phosphene has no blur-mip chain; approximate butterchurn's `blur1` (the warp's
// low-frequency feedback read) with a 9-tap gaussian of the prev frame, stored in
// colour space so the warp's scale1=1 / bias1=0. The warp only uses blur1 for a
// luma-weighted rotation/displacement, so a smooth low-pass suffices. (A much wider
// blur was tried for the fill gap — it did not spread the field; the fill gap is a
// deeper feedback-transport issue, not blur width. FM.L2.)
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
