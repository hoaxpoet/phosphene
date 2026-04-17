// MVWarp.metal — Milkdrop-style per-vertex feedback warp pass (MV-2, D-027).
//
// Compiled by ShaderLibrary into the engine library for reference and
// standalone testing.  The per-preset warp pipeline is compiled via
// mvWarpPreamble in PresetLoader+Preamble.swift (injected alongside the
// preset's mvWarpPerFrame / mvWarpPerVertex implementations).
//
// Architecture:
//   1. Scene pass:  rayMarch/postProcess → sceneTexture (offscreen)
//   2. Warp pass:   mvWarp_vertex (32×24 grid) samples warpTexture[prev]
//                   at per-vertex warped UV × decay → composeTexture
//   3. Compose:     scene additively alpha-blended onto composeTexture
//   4. Blit:        composeTexture → drawable
//   5. Swap:        warpTexture ↔ composeTexture for next frame
//
// The engine library provides default (identity) implementations of the
// per-preset functions and all fixed fragment shaders.
//
// Types used below (FeatureVector, StemFeatures, SceneUniforms, VertexOut)
// are defined in Common.metal and shared by all engine shaders.

#include <metal_stdlib>
using namespace metal;

// ── MV-Warp types ──────────────────────────────────────────────────────────

// Per-frame warp parameters returned by mvWarpPerFrame().
// Must match the MVWarpPerFrame struct in PresetLoader+Preamble.swift exactly.
struct MVWarpPerFrame {
    float zoom, rot, decay, warp;
    float cx, cy, dx, dy, sx, sy;
    float q1, q2, q3, q4, q5, q6, q7, q8;
};

// Vertex → fragment IO for the warp pass.
struct WarpVertexOut {
    float4 position  [[position]];
    float2 uv;
    float2 warped_uv;
    float  decay;
};

// Clamp-to-edge sampler for warp texture reads (avoids border-wrap artifacts).
constexpr sampler warpEdgeSampler(filter::linear, address::clamp_to_edge);
constexpr sampler warpRepeatSampler(filter::linear, address::repeat);

// ── Default per-preset functions (identity warp, no displacement) ──────────
// Presets in the mv_warp family override these in their own compiled library.

static MVWarpPerFrame mvWarpPerFrame_default(
    constant FeatureVector& f,
    constant StemFeatures&  stems,
    constant SceneUniforms& s
) {
    MVWarpPerFrame pf;
    pf.zoom = 1.0f;  pf.rot  = 0.0f;  pf.decay = 0.96f;  pf.warp = 0.0f;
    pf.cx   = 0.0f;  pf.cy   = 0.0f;  pf.dx    = 0.0f;   pf.dy   = 0.0f;
    pf.sx   = 1.0f;  pf.sy   = 1.0f;
    pf.q1   = 0.0f;  pf.q2   = 0.0f;  pf.q3    = 0.0f;   pf.q4   = 0.0f;
    pf.q5   = 0.0f;  pf.q6   = 0.0f;  pf.q7    = 0.0f;   pf.q8   = 0.0f;
    return pf;
}

static float2 mvWarpPerVertex_default(
    float2 uv, float rad, float ang,
    thread const MVWarpPerFrame& pf,
    constant FeatureVector& f,
    constant StemFeatures& stems
) {
    float2 centre = float2(0.5f + pf.cx, 0.5f + pf.cy);
    float2 p      = uv - centre;
    float  cosR   = cos(pf.rot), sinR = sin(pf.rot);
    p = float2(p.x * cosR - p.y * sinR, p.x * sinR + p.y * cosR);
    p /= pf.zoom;
    return p + centre + float2(pf.dx, pf.dy);
}

// ── Engine-library vertex shader (uses default implementations) ────────────
// Named mvWarp_vertex_default to distinguish from the preset-preamble version
// (mvWarp_vertex) which calls the preset's own mvWarpPerFrame/mvWarpPerVertex.
vertex WarpVertexOut mvWarp_vertex_default(
    uint                    vid      [[vertex_id]],
    constant FeatureVector& features [[buffer(0)]],
    constant StemFeatures&  stems    [[buffer(1)]],
    constant SceneUniforms& scene    [[buffer(2)]]
) {
    // 31×23 quads = 4278 vertices (triangle list, 6 per quad).
    const uint2 qoffsets[6] = { {0,0},{1,0},{0,1}, {1,0},{1,1},{0,1} };
    uint quad_idx     = vid / 6;
    uint vert_in_quad = vid % 6;
    uint col = quad_idx % 31;
    uint row = quad_idx / 31;
    uint2 corner = uint2(col, row) + qoffsets[vert_in_quad];

    float2 uv = float2(float(corner.x) / 31.0f, float(corner.y) / 23.0f);

    MVWarpPerFrame pf = mvWarpPerFrame_default(features, stems, scene);
    float2 centre  = float2(0.5f + pf.cx, 0.5f + pf.cy);
    float2 p       = uv - centre;
    float  rad     = length(p) * 2.0f;
    float  ang     = atan2(p.y, p.x);
    float2 warped  = mvWarpPerVertex_default(uv, rad, ang, pf, features, stems);

    WarpVertexOut out;
    out.position  = float4(uv.x * 2.0f - 1.0f, 1.0f - uv.y * 2.0f, 0.0f, 1.0f);
    out.uv        = uv;
    out.warped_uv = warped;
    out.decay     = pf.decay;
    return out;
}

// ── mvWarp_fragment ────────────────────────────────────────────────────────
// Samples the previous warp texture at the warped UV, scaled by decay.
// Output goes to composeTexture (clear load); compose pass adds scene on top.
fragment float4 mvWarp_fragment(
    WarpVertexOut    in      [[stage_in]],
    texture2d<float> prevTex [[texture(0)]]
) {
    return prevTex.sample(warpEdgeSampler, in.warped_uv) * in.decay;
}

// ── mvWarp_compose_fragment ────────────────────────────────────────────────
// Composites the current scene onto the decay-warped compose texture.
// Alpha = (1 - decay): the compose render pass uses sourceAlpha × src + one × dst
// blending so steady-state scene contribution sums to 1.0 across frames.
fragment float4 mvWarp_compose_fragment(
    WarpVertexOut    in       [[stage_in]],
    texture2d<float> sceneTex [[texture(0)]],
    constant float&  decay    [[buffer(0)]]
) {
    float4 scene = sceneTex.sample(warpRepeatSampler, in.uv);
    return float4(scene.rgb, 1.0f - decay);
}

// ── mvWarp_blit_fragment ───────────────────────────────────────────────────
// Copies the composed warp texture to the drawable.
// The scene was already ACES-composited before entering the warp pipeline.
fragment float4 mvWarp_blit_fragment(
    WarpVertexOut    in      [[stage_in]],
    texture2d<float> warpTex [[texture(0)]]
) {
    return warpTex.sample(warpEdgeSampler, in.uv);
}
