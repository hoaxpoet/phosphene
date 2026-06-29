// Mitosis.metal — backdrop ground for the Mitosis reaction–diffusion preset.
//
// Mitosis renders entirely through its `ParticleGeometry` (`MitosisGeometry` draws
// the colorized reaction–diffusion field fullscreen in the particles pass). This
// backdrop is the particle-mode preset triangle drawn BEFORE the field and fully
// covered by it — it only needs to be the dark ground to satisfy the particle-mode
// contract. The real visual + the Gray–Scott kernel + the colorize live in
// `Renderer/Shaders/Mitosis.metal` (engine library). `VertexOut` comes from the
// preset preamble (PresetLoader+Preamble), like every preset fragment.

fragment float4 mitosis_ground_fragment(VertexOut in [[stage_in]]) {
    return float4(0.01, 0.02, 0.03, 1.0);   // dark ground (covered by the cell field)
}
