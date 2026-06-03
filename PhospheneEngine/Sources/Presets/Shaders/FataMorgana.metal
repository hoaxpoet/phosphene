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
    float  time;        // features.time — seconds since visualization start (session-monotonic, butterchurn's wall-clock `time`)
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
    pf.zoom = 1.05;          // source per_pixel zoom (constant). The bar gesture lives in
                            // the shapes' coordinated horizontal sway (fata_shape_vertex),
                            // not a whole-field zoom — isolating Matt's "sway over the
                            // water in time with the bars" as the single clear bar motion.
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
    // Source displacement is 0.2·luma·rotP; calmed to 0.15 (Matt: "calm the warp swirl
    // slightly") — less per-frame drag → the swaying spectra streak less. Deliberate,
    // Matt-requested L-uplift divergence from the faithful 0.2.
    float2 uv1 = (p + 0.15 * luma * rotP) - 0.5;         // verbatim double −0.5 (wrap no-op)

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
    texture2d<float>       noiseLQ   [[texture(4)]],   // pw_noise_lq (grid stars)
    texture2d<float>       noiseHQ   [[texture(5)]],   // noise_hq (ground noise)
    texture2d<float>       blueNoise [[texture(8)]],   // point-wrap random (pw_noise_lq stand-in)
    constant FataUniforms& u         [[buffer(1)]]
) {
    constexpr sampler nWrap(filter::linear, address::repeat);
    constexpr sampler pwWrap(filter::nearest, address::repeat);   // POINT-wrap (butterchurn pw_noise_lq)
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

    // Neon grid stars (source mechanic). butterchurn gates the grid with pw_noise_lq —
    // a POINT-WRAP random noise (nearest-sampled), so the lit grid cells scatter. Mine
    // sampled Perlin FBM (smooth, linear) → spatially-correlated gating → a regular
    // diagonal lattice (Matt M7). Sample blueNoise with a NEAREST/repeat sampler (the
    // point-wrap behaviour) so the >threshold cells scatter into a starfield.
    float2x2 gm = float2x2(0.6, -0.8, 0.8, 0.6);        // columns (0.6,-0.8),(0.8,0.6)
    float2 g  = 32.0 * ((uv * gm) + (col * 0.1).xy + u.time / 64.0);
    float2 gt = abs(fract(g) - 0.5);
    float  gv = clamp((0.25 / sqrt(dot(gt, gt)))
                      * (blueNoise.sample(pwWrap, g / 256.0).r - 0.9), 0.0, 1.0);

    float3 ret = col + (gv * gv + (u.randPreset.xyz * (0.5 - uv.y)) * float3(0.0, 0.0, 1.0)) * (1.0 - m);

    // ── Diagnostic term isolation (u.gammaAdj carries fataDebugMode; 0 = normal) ──
    // 1: field reflection only (main(p), no glow/stars)  2: glow only  3: raw field at uv
    if (u.gammaAdj > 0.5) {
        if (u.gammaAdj < 1.5) return float4(mainTex.sample(fataClamp, p).rgb, 1.0);
        if (u.gammaAdj < 2.5) return float4((0.02 / (0.02 + abs(xf))) * u.slowRoamSin.xyz, 1.0);
        return float4(mainTex.sample(fataClamp, in.uv).rgb, 1.0);
    }

    // sRGB round-trip cancellation. butterchurn writes to an sRGB-NAIVE WebGL canvas —
    // its comp output bytes are scanned out and displayed directly (the shader's value
    // IS the display value). Phosphene's drawable is .bgra8Unorm_srgb, so Metal would
    // sRGB-ENCODE this return (linear 0.2 → byte ~0.48), lifting blacks and washing the
    // image toward midtone (Matt M7: "deeper black needed"; the purple haze). Decode
    // here so the target's encode round-trips back to the butterchurn display value:
    // displayed = srgbEncode(srgbDecode(ret)) = ret. Only the final comp→drawable write
    // needs this — the feedback textures are linear .bgra8Unorm (butterchurn 8-bit clamp).
    float3 v = saturate(ret);
    float3 lin = select(v / 12.92,
                        pow((v + 0.055) / 1.055, float3(2.4)),
                        v > 0.04045);
    return float4(lin, 1.0);
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
// additive shapes' radius = baseVals.rad × the band attack. The source uses
// {mid,bass,treb}_att — a ~1.0-centred peak-follower that spikes on transients and
// decays between them. The faithful Phosphene analog is `(1 + *_energy_dev)` (D-026):
// `_energy_dev` is the deviation about the running average, so `1 + dev` ≡ `_energy_rel`
// ≡ `_att` (~1.0 baseline, spikes on hits). max(0,·) clamps the rare sub-baseline dip.
// This was the AGC `*_energy` (~0.5-centred, steady) ×gain-5 before — which kept blobs
// continuously oversized so the additive feedback never decayed dark (gray-wash). The
// stem map (drums/bass/vocals) is the L-uplift.

struct FataShapeParams {
    int   shapeIndex;   // 0 textured echo, 1 mid, 2 bass, 3 treb
    int   sides;        // 30 (shape 0) or 40
    int   numInst;      // instances (1/4/1/5)
    float frame;        // butterchurn frame counter (colour cycle + shape-0 rotation)
    float aspectY;      // texsizeY/texsizeX (keeps n-gons round on a wide canvas)
    float audioBoost;   // multiplies the band attack driving the blob radius
    float swayClock;    // CPU bar clock (+1 per bar); drives the coordinated horizontal sway
    float pad1;
};

struct FataShapeVtxOut {
    float4 position [[position]];
    float4 color;
    float2 uv;
    float  textured;
};

vertex FataShapeVtxOut fata_shape_vertex(
    uint                      vid [[vertex_id]],
    uint                      iid [[instance_id]],
    constant FeatureVector&   f   [[buffer(0)]],
    constant FataShapeParams& sp  [[buffer(1)]],
    constant StemFeatures&    st  [[buffer(2)]]
) {
    int   sides  = sp.sides;
    int   tri    = int(vid) / 3;
    int   corner = int(vid) % 3;

    // ── colour cycle (source: r=sin(cyc), b=sin(cyc+2.094), g=sin(cyc+4.188)) ──
    float x = 0.5, y = 0.5, rad = 0.1, ang = 0.0, aCenter = 1.0;
    float cyc = 0.5 * sp.frame;
    float3 col = float3(0.5 + 0.5 * sin(cyc),
                        0.5 + 0.5 * sin(cyc + 4.188),
                        0.5 + 0.5 * sin(cyc + 2.094));

    // COORDINATED BAR SWAY (the L-uplift, redesigned). Matt's vision: a FEW spectra
    // swaying over the water back-and-forth IN TIME WITH THE BARS — not a crowd of
    // independent orbits (chaos). So there are now just 3 bright spectra (one per
    // instrument), each at a fixed spread-out base position, and ALL share one
    // horizontal sway offset = A·cos(π·swayClock). swayClock advances +1 per bar, so
    // cos has a 2-bar period and hits an EXTREME at every downbeat: the spectra sweep
    // together to one side over a bar, turn around exactly on the downbeat, and sweep
    // back the next bar. The coordinated, low-count motion is legible where 11
    // independent orbits were not. (No bar grid → swayClock frozen → they hold still.)
    // beatPulse (one gentle pop per grid beat) + per-stem _energy_dev (brightness
    // identity) ride on top.
    float A    = 0.30;                                             // horizontal sway amplitude (Matt: more sway)
    float beatPulse = pow(max(0.0, 1.0 - f.beat_phase01), 4.0);    // one sharp pulse per grid beat
    float flare = 1.0;
    // Each shape sways by A·cos(π·(swayClock + phase)). The three are PHASE-OFFSET so
    // they spread across the frame at all times instead of bunching to one side at the
    // extremes (Matt): drums (phase 0) and vocals (phase 1.0) are ANTI-PHASE — one
    // swings right while the other swings left — and bass (phase 0.5) weaves through the
    // centre. At every downbeat they sit right/centre/left, so the frame stays balanced
    // while each still turns once per bar. Base Y < 0.5 places them ABOVE the horizon
    // (the comp samples the sky at feedback v ∈ [0 top, 0.5 horizon]; a shape's v = its y,
    // so y > 0.5 would read as IN the water).
    if (sp.shapeIndex == 0) {                              // faint textured echo (central, still)
        rad = 0.06623; ang = 0.02 * sp.frame; x = 0.5; y = 0.5;
        col = float3(0.0); aCenter = 0.1;
    } else if (sp.shapeIndex == 1) {                       // DRUMS — phase 0 (right on downbeat)
        x = 0.50 + A * cos(M_PI_F * sp.swayClock); y = 0.35;
        float dev = max(0.0, st.drums_energy_dev);
        rad   = 0.11 * (1.0 + 0.45 * beatPulse) * sp.audioBoost;
        flare = 0.55 + 0.7 * beatPulse + 0.5 * dev;
    } else if (sp.shapeIndex == 2) {                       // BASS — phase 0.5 (centre, weaving)
        x = 0.50 + A * cos(M_PI_F * (sp.swayClock + 0.5)); y = 0.28;
        float dev = max(0.0, st.bass_energy_dev);
        rad   = 0.11 * (1.0 + 0.45 * beatPulse) * sp.audioBoost;
        flare = 0.55 + 0.7 * beatPulse + 0.5 * dev;
    } else {                                               // VOCALS — phase 1.0 (anti-phase to drums)
        x = 0.50 + A * cos(M_PI_F * (sp.swayClock + 1.0)); y = 0.35;
        float dev = max(0.0, st.vocals_energy_dev);
        rad   = 0.09 * (1.0 + 0.45 * beatPulse) * sp.audioBoost;
        flare = 0.55 + 0.7 * beatPulse + 0.5 * dev;
    }
    col *= flare;                                          // brightness = instrument identity

    float xn = x * 2.0 - 1.0;
    float yn = y * -2.0 + 1.0;     // butterchurn frame.y*-2+1 (y=0 → NDC top)
    float quarterPi = M_PI_F * 0.25;

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

// MARK: - Blur fragment (butterchurn blur1 — moderate downsampled gaussian)
//
// butterchurn's blur1 is a SEPARABLE gaussian (blurRatios[0] = [0.5, 0.25] → stored at
// ~1/4 resolution) spanning ~±4 source texels — a MODERATE low-pass, NOT a wide one.
// The warp reads blur1 to compute its swirl direction (`rot = dot(c, roam_sin)·16`) and
// luma displacement, so the blur WIDTH governs ring vs ribbon: at the right width the
// swirl varies at fine scale and the zoom-1.05 feedback echoes survive as concentric
// neon RINGS (the oracle); too WIDE and the swirl is coherent over large regions, which
// twists the rings into smeared RIBBONS (Matt M7: "too much smearing"). The earlier
// ×6 (±12 texel) blur was over-wide on a wrong "ribbons = oracle" assumption — corrected
// to ×2 (±4 texels) to match butterchurn's blur1. The 1/4-res store + the warp's
// bilinear read widen it slightly, as in butterchurn. Output in colour space (scale1=1).
fragment float4 fata_morgana_blur_fragment(
    VertexOut              in   [[stage_in]],
    texture2d<float>       src  [[texture(0)]],
    constant FataUniforms& u    [[buffer(1)]]
) {
    float2 step = u.texsize.zw * 2.0;                    // ~±4 full-res texels (butterchurn blur1)
    const float w1d[5] = { 1.0, 4.0, 6.0, 4.0, 1.0 };   // separable gaussian
    float3 acc = float3(0.0);
    float  wsum = 0.0;
    for (int dy = -2; dy <= 2; dy++) {
        for (int dx = -2; dx <= 2; dx++) {
            float wt = w1d[dx + 2] * w1d[dy + 2];
            acc += src.sample(fataClamp, in.uv + float2(float(dx), float(dy)) * step).rgb * wt;
            wsum += wt;
        }
    }
    return float4(acc / wsum, 1.0);
}
