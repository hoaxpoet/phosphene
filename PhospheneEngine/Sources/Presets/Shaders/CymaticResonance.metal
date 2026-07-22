// CymaticResonance.metal — deep-black ground for the vibrating-sand Chladni preset.
//
// CR.2 rebuild (D-199): Cymatic Resonance is now a `feedback + particles` preset.
// The actual content — glowing sand grains that vibrate on the plate and collect
// onto the nodal lines — is a particle simulation in `CymaticSandGeometry` +
// `CymaticSand.metal` (the vibration-driven random walk, ported per FA #73). This
// preset shader only provides the black plate ground; the sand density fragment
// (drawn fullscreen by the geometry, on top) is the visible output. Same pattern
// as Filigree (`filigree_ground_fragment`) / Murmuration.
//
// The CR.1 direct figure-shader (plus-basis nodal-line relief) was retired at the
// CR.2 rebuild — Matt's 3rd M7 (2026-07-22): a static morphing figure showed the
// RESULT of resonance, not the phenomenon; the references are about sand vibrating
// and re-forming. See docs/DECISIONS.md D-199.

#include <metal_stdlib>
using namespace metal;

fragment float4 cymatic_ground_fragment(VertexOut in [[stage_in]]) {
    return float4(0.006, 0.007, 0.012, 1.0);   // deep-black plate (covered by the sand density)
}
