// Ricercar.metal — backdrop ground for the Ricercar particle flow-field preset (RICERCAR-FL.10).
//
// Ricercar renders entirely through its `ParticleGeometry` (`RicercarFlowGeometry` tonemaps its HDR
// light-trail fullscreen in the particles pass). This backdrop is the particle-mode preset triangle
// drawn BEFORE the field and fully covered by it — it only needs to be the DEEP ground (matching the
// display fragment's ground so a dropped frame is invisible). The T&F "visual fantasia" is luminous
// light over deep/dark space, not the light canvas the curated refs 01/02 implied (RICERCAR_DESIGN
// §FANTASIA REBUILD). The flow kernels + display live in `Renderer/Shaders/RicercarFlow.metal` (engine
// library). `VertexOut` comes from the preset preamble (PresetLoader+Preamble).

fragment float4 ricercar_ground_fragment(VertexOut in [[stage_in]]) {
    // Deep indigo, gentle top-darker gradient — matches ricercar_flow_display_fragment's ground.
    float3 groundTop = float3(0.010, 0.012, 0.030);
    float3 groundBot = float3(0.020, 0.022, 0.050);
    return float4(mix(groundBot, groundTop, in.uv.y), 1.0);
}
