// MitosisGen2.metal — backdrop ground for the Cytokinesis preset (Mitosis gen-2).
//
// Like gen-1 Mitosis, the real visual is drawn entirely by the preset's `ParticleGeometry`
// (`MitosisGen2Geometry` composites the detailed dividing cells fullscreen in the particles
// pass). This backdrop is the particle-mode preset triangle drawn BEFORE the cells and fully
// covered by them — it only needs to be the dark ground. The cell rendering lives in
// `Renderer/Shaders/MitosisGen2.metal` (engine library). `VertexOut` comes from the preset
// preamble (PresetLoader+Preamble), like every preset fragment.

fragment float4 mitosisgen2_ground_fragment(VertexOut in [[stage_in]]) {
    return float4(0.01, 0.02, 0.03, 1.0);   // dark ground (covered by the cell field)
}
