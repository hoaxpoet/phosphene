// Nimbus — volumetric luminous-body preset (family: volumetric).
//
// A single coherent gaseous body suspended in a true-black void, rendered as a
// single-pass 2D direct-fragment volumetric ray-march that composes the
// preamble-injected V.2 Volume tree. No engine changes, no new utilities, no
// extra passes (`passes: []`). Contract of record: docs/presets/NIMBUS_DESIGN.md.
//
// NB.1 SCAFFOLD (this commit): placeholder fragment that compiles, loads through
// the standard direct path, and renders a cool disc on a black void — enough to
// prove the sidecar wiring + auto-discovery + framing. The real macro-body
// volumetric march (density field + single-scatter + cheap self-shadow + debug
// views) lands in the next NB.1 commit.

// MARK: - Nimbus fragment (NB.1 scaffold placeholder)

fragment float4 nimbus_fragment(VertexOut in [[stage_in]],
                                constant FeatureVector& features [[buffer(0)]]) {
    // Aspect-correct, centred coordinates. Production 1080p aspect = 1.777
    // (the FeatureVector default); the live pipeline overwrites aspect_ratio
    // with the real drawable aspect each frame.
    float2 p = in.uv - 0.5;
    p.x *= max(features.aspect_ratio, 1e-4);

    // Placeholder body: a soft cool disc on a true-black void. Colour anchored
    // to the cool baseline (deep desaturated indigo/violet, per
    // docs/VISUAL_REFERENCES/nimbus/06_palette_cool_baseline). Linear output —
    // the .bgra8Unorm_srgb drawable sRGB-encodes on write.
    float r = length(p);
    float disc = smoothstep(0.42, 0.04, r);
    float3 coolBaseline = float3(0.30, 0.28, 0.62);
    float3 col = coolBaseline * disc;

    return float4(col, 1.0);
}
