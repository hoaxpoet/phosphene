// Filigree.metal — backdrop ground for the Filigree physarum preset.
//
// Filigree renders entirely through its `ParticleGeometry` (`PhysarumGeometry`
// draws the gold-on-black trail fullscreen in the particles pass). This backdrop
// is the particle-mode preset triangle drawn BEFORE the trail and fully covered
// by it — it only needs to be the Kintsugi ground (pure black) to satisfy the
// particle-mode contract. The real visual + the agent kernels + the colorize live
// in `Renderer/Shaders/Physarum.metal` (engine library). `VertexOut` comes from
// the preset preamble (PresetLoader+Preamble), like every preset fragment.

fragment float4 filigree_ground_fragment(VertexOut in [[stage_in]]) {
    return float4(0.0, 0.0, 0.0, 1.0);   // Kintsugi pure-black ground (covered by the trail)
}
