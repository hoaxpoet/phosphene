// Ricercar.metal — backdrop ground for the Ricercar fluid-dye preset (RICERCAR-FL.5).
//
// Ricercar renders entirely through its `ParticleGeometry` (`RicercarFluidGeometry` draws
// the fluid dye field + ribbon overlay fullscreen in the particles pass). This backdrop is
// the particle-mode preset triangle drawn BEFORE the field and fully covered by it — it only
// needs to be the warm light ground (matching the display fragment's ground so a dropped
// frame is invisible). The fluid kernels + display live in `Renderer/Shaders/RicercarFluid.metal`
// (engine library). `VertexOut` comes from the preset preamble (PresetLoader+Preamble).

fragment float4 ricercar_ground_fragment(VertexOut in [[stage_in]]) {
    return float4(0.95, 0.94, 0.92, 1.0);   // warm light ground (covered by the dye field)
}
