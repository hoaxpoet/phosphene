// Dashboard.metal — Composite fragment for the Telemetry dashboard layer.
//
// Pairs with DashboardComposer (DASH.6). The layer's CGContext renders into a
// `.bgra8Unorm` MTLBuffer with `kCGBitmapByteOrder32Little | premultipliedFirst`,
// which Core Graphics produces as **premultiplied** sRGB. The composite
// pipeline state therefore configures alpha blending as
//   src = .one,  dst = .oneMinusSourceAlpha
// rather than `.sourceAlpha`/`.oneMinusSourceAlpha` (which would double-multiply
// and produce a black halo around card edges).
//
// The vertex stage reuses Common.metal's `fullscreen_vertex` — a viewport set
// on the encoder restricts the triangle to the top-right card region, and the
// uv sweeps 0..1 across that viewport.

#include <metal_stdlib>
using namespace metal;

// Forward declaration of the shared fullscreen vertex output. Common.metal
// declares `VertexOut`; this file is concatenated alongside Common.metal so
// the type is visible by the time the fragment is compiled.
struct DashboardVertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex DashboardVertexOut dashboard_composite_vertex(uint vid [[vertex_id]]) {
    DashboardVertexOut out;
    out.uv = float2((vid << 1) & 2, vid & 2);
    out.position = float4(out.uv * 2.0 - 1.0, 0.0, 1.0);
    out.uv.y = 1.0 - out.uv.y;
    return out;
}

fragment float4 dashboard_composite_fragment(
    DashboardVertexOut in [[stage_in]],
    texture2d<float> layerTex [[texture(0)]]
) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    return layerTex.sample(s, in.uv);
}
