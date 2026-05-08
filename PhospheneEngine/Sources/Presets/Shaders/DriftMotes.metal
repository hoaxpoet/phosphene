// DriftMotes.metal — Sky backdrop for the Drift Motes preset (Increment DM.1).
//
// Cinematographic warm-amber vertical gradient evoking late-afternoon
// interior light: deep amber at the zenith, slightly brighter mahogany
// near the floor. The single dramatic god-ray light shaft, floor fog,
// and palette modulation by valence are deferred to Sessions 2 and 3.
//
// Audio coupling in Session 1: NONE. The backdrop is fully audio-
// independent. `f.valence` tinting arrives in Session 3 when the full
// audio routing lands.

fragment float4 drift_motes_sky_fragment(
    VertexOut in [[stage_in]],
    constant FeatureVector& f [[buffer(0)]]
) {
    float t = in.uv.y;
    float3 top    = float3(0.05, 0.03, 0.02);   // Deep mahogany at zenith.
    float3 bottom = float3(0.10, 0.07, 0.04);   // Slightly brighter near floor.
    float3 col = mix(top, bottom, t);
    return float4(col, 1.0);
}
