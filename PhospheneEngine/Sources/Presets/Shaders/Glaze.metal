// Glaze.metal — Phosphene port of the Milkdrop/butterchurn builtin
// `Flexi + stahlregen - jelly showoff parade` (cream-of-crop legends; the glossy
// "wet jelly" contour-gel). See docs/presets/GLAZE_PLAN.md +
// docs/VISUAL_REFERENCES/glaze/ (source_shaders.txt = the decoded port artifact).
//
// Character (faithful target): nested concentric contour-ring striations under a thick
// embossed gel sheen (specular highlights + dark rims), a saturated neon palette that
// rotates, on an accreting feedback field — flowing as an audio-driven spring-mass
// "jelly" drags a swirl-poke across it. A DIFFERENT register from Nacre's translucent
// lens-cells despite the shared mv_warp substrate.
//
// ── INCREMENT STATUS — GLAZE.2a (THIS FILE = STUB) ─────────────────────────────────
// This is the 2a WIRING STUB, NOT the faithful look. Goal: a Glaze preset that loads,
// renders non-black through the live warp→comp→swap dispatch, accretes via feedback, and
// never whites out at silence — so the dedicated branch + test harness are proven end to
// end before the faithful shader math lands. Deliberately minimal (ponytail):
//   · warp  = gentle advection + decay + a palette-tinted, energy-gated, silence-floored
//             seed (alive at silence, D-019) + [0,1] clamp (the Nacre white-out bound).
//   · comp  = sample feedback + mild glossy contrast + sRGB decode. NO blur-pyramid emboss.
// GLAZE.2b fills in: the 3-mass spring warp center + emboss/sheen comp + the 3-level blur
// pyramid (its consumer lands with it — not built speculatively in 2a). The greenlit 2026
// uplifts (A per-stem routing, B HDR glossy bloom, C shiver mode) are GLAZE.5+ — AFTER the
// faithful base passes Matt's live M7 (FA #65).
//
// SceneUniforms / MVWarpPerFrame / WarpVertexOut / VertexOut / fullscreen_vertex /
// FeatureVector / StemFeatures / warpSampler come from the mvWarp preamble + Common.metal
// (the loader prepends them; do not redefine — Nacre.metal precedent).

// MARK: - GlazeUniforms (CPU-computed per frame; matches GlazeUniforms in Swift)
//
// Bound at fragment buffer(1) of BOTH the warp and comp passes (the Nacre/FM pattern).
// 32 bytes — see GlazeUniforms in RenderPipeline+Glaze.swift for the byte layout.
struct GlazeUniforms {
    float  time;        // features.time — palette rotation + seed scroll
    float  coreEnergy;  // STEADY total energy → gates the warp seed (faithful modwavealphabyvolume role)
    float2 texel;       // (1/feedbackW, 1/feedbackH) — comp/warp sample offsets (texsize.zw)
    float4 aspect;      // (aspectx, aspecty, 1/aspectx, 1/aspecty) — keeps the field round on a wide canvas
};

// MARK: - Constants (2a stub)

constant float  kGlazeDecay     = 0.94;    // feedback persistence (bounded; source decay 1.0 needs the [0,1] clamp)
constant float  kGlazeBaseZoom  = 1.012;   // slight inward zoom (source zoom 1.06/zoomexp — rings flow inward)
constant float  kGlazeRoamAmp   = 0.010;   // slow centre roam (alive at silence)
constant float  kGlazeCoreTight = 14.0;    // luminous seed spot tightness
constant float  kGlazeCoreBase  = 0.16;    // seed glow
constant float3 kGlazeLuma      = float3(0.32, 0.49, 0.29);   // the source's luma weight

// MARK: - Palette (the source's saturated neon rotation, stand-in for hue_shader)
// Slow red→green→teal→violet drift. Faithful technique: tints the SEED (accumulates in
// feedback), NOT the display (hue-strobing the display is an anti-reference).
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
//
// PresetLoader needs a `fragment_function` to build the direct pipeline, but the Glaze
// branch never renders it (the seed is folded into the warp). Near-black, like Nacre.
fragment float4 glaze_fragment(VertexOut in [[stage_in]]) {
    return float4(0.0, 0.0, 0.0, 1.0);
}

// MARK: - MV-Warp mesh functions (per-vertex feedback transform — stub advection)
//
// 2a stub: slight inward zoom + a slow roam so the feedback accretes/drifts (proves the
// loop). GLAZE.2b replaces this with the source's spring-physics swirl-poke (pixel_eqs:
// a local radial vortex around the audio-driven bouncing tail).

MVWarpPerFrame mvWarpPerFrame(
    constant FeatureVector& f,
    constant StemFeatures&  stems,
    constant SceneUniforms& s
) {
    MVWarpPerFrame pf;
    float t = f.time;
    pf.decay = kGlazeDecay;   // informational on the dedicated branch (decay baked in glaze_warp_fragment)
    pf.zoom  = kGlazeBaseZoom;
    pf.rot   = 0.012 * (0.6 * sin(0.31 * t) + 0.4 * sin(0.47 * t));
    pf.cx    = kGlazeRoamAmp * (0.6 * sin(0.29 * t) + 0.4 * sin(0.19 * t));
    pf.cy    = kGlazeRoamAmp * (0.6 * sin(0.33 * t) + 0.4 * sin(0.23 * t));
    pf.dx    = 0.0; pf.dy = 0.0; pf.warp = 0.0; pf.sx = 1.0; pf.sy = 1.0;
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
    float2 centre = float2(0.5 + pf.cx, 0.5 + pf.cy);
    float2 p = (uv - centre) / max(pf.zoom, 0.001);
    float c = cos(pf.rot), sn = sin(pf.rot);
    return float2(c * p.x - sn * p.y, sn * p.x + c * p.y) + centre;
}

// MARK: - Custom WARP fragment (feedback transfer — 2a STUB)
//
// Stub: warped prev × decay + a palette-tinted, energy-gated, silence-floored central
// seed + [0,1] clamp. The seed keeps the field alive at silence (D-019) and carries the
// rotating palette into the feedback; the clamp bounds accumulation (source stores 8-bit;
// an unclamped float loop blooms to white — the Nacre lesson). GLAZE.2b: spring swirl-poke
// + blur-pyramid emboss + treble grain.
fragment float4 glaze_warp_fragment(
    WarpVertexOut           in   [[stage_in]],
    texture2d<float>        prev [[texture(0)]],
    constant GlazeUniforms& gu   [[buffer(1)]]
) {
    float3 c = prev.sample(warpSampler, in.warped_uv).rgb * kGlazeDecay;

    // Palette-tinted central seed, volume-gated with a silence floor (alive at silence,
    // bright with audio). A low-freq value-noise blob breaks the radial symmetry so the
    // accreting field reads as organic contours, not a clean ring.
    float r        = length(in.uv - 0.5);
    float coreGate = 0.20 + 0.80 * clamp(gu.coreEnergy, 0.0, 1.0);
    float blob     = 0.6 + 0.4 * glazeValueNoise(in.uv * 4.0 + gu.time * 0.10);
    float core     = exp(-r * r * kGlazeCoreTight) * kGlazeCoreBase * coreGate * blob;
    c += core * glazePalette(gu.time);

    return float4(clamp(c, 0.0, 1.0), 1.0);
}

// MARK: - Custom COMP fragment (the display look — 2a STUB, DISPLAY ONLY)
//
// Stub: sample the warped feedback + a mild glossy contrast lift + sRGB decode. GLAZE.2b
// replaces this with the source's multi-scale blur-pyramid emboss (the wet-gel sheen) +
// dual-direction gradient sampling.
fragment float4 glaze_comp_fragment(
    VertexOut               in      [[stage_in]],
    texture2d<float>        mainTex [[texture(0)]],
    constant GlazeUniforms& gu      [[buffer(1)]]
) {
    constexpr sampler m(filter::linear, address::clamp_to_edge);
    float3 ret = mainTex.sample(m, in.uv).rgb;
    ret = ret * (1.0 + ret);   // mild contrast lift (stand-in for the source's ret*ret/sqrt curve)

    // sRGB round-trip cancellation (the FM/Nacre fix, D-139): the source writes to an
    // sRGB-naive canvas; Phosphene's drawable is .bgra8Unorm_srgb, so decode here so the
    // drawable's encode round-trips back to the intended value (keeps the ground deep).
    float3 v = saturate(ret);
    float3 lin = select(v / 12.92, pow((v + 0.055) / 1.055, float3(2.4)), v > 0.04045);
    return float4(lin, 1.0);
}
