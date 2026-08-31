// StagedSandbox.metal — V.ENGINE.1 diagnostic preset.
//
// Proves the staged-composition scaffold end-to-end:
//   • Stage A ("world")     — renders a sky gradient + 3 dark silhouettes into
//                             an offscreen `.rgba16Float` texture.
//   • Stage B ("composite") — samples the world texture at [[texture(13)]] and
//                             overlays a simple placeholder "web" of straight
//                             lines + a hub dot on top of it. Renders to drawable.
//
// This file is deliberately tiny and free of audio reactivity: it exists to
// validate the renderer scaffold (named offscreen texture + later-pass
// sampling + harness pass capture), NOT to look good. Real presets that
// adopt staged composition (Arachne v8) author proper world / web / droplet
// passes against the references — see ARACHNE_V8_DESIGN.md §3A.
//
// Texture binding convention for staged presets:
//   [[texture(13)]] = first sampled stage in this stage's `samples` array
//   [[texture(14)]] = second sampled stage, etc.

// Sampler used by the composite stage to read the world texture.
constant constexpr sampler sandbox_world_sampler(filter::linear,
                                                 address::clamp_to_edge);

// ─── Stage A: WORLD ──────────────────────────────────────────────────────────
//
// Vertical gradient (cool blue at top → near-black at bottom) plus three dark
// vertical silhouettes ("trees") at fixed positions. No audio inputs are read;
// the world deliberately stays still.

fragment float4 staged_sandbox_world_fragment(
    VertexOut in [[stage_in]],
    constant FeatureVector& f [[buffer(0)]]
) {
    float2 uv = in.uv;

    // Sky gradient.
    float3 topCol = float3(0.18, 0.30, 0.42);
    float3 botCol = float3(0.05, 0.07, 0.10);
    float3 col    = mix(topCol, botCol, uv.y);

    // Subtle noise to break perfectly-smooth banding.
    float n = fract(sin(dot(uv * 137.0, float2(12.9898, 78.233))) * 43758.5453);
    col *= (0.97 + 0.03 * n);

    // Three dark silhouettes — distance-to-vertical-line SDFs.
    float3 trunkCol = botCol * 0.5;
    float silhouette = 0.0;
    float treeXs[3] = { 0.22, 0.55, 0.82 };
    float treeWs[3] = { 0.018, 0.024, 0.014 };
    for (int i = 0; i < 3; i++) {
        float d = abs(uv.x - treeXs[i]);
        float w = treeWs[i];
        // Trunks taper slightly with height — wider near the floor.
        w *= mix(0.6, 1.0, uv.y);
        silhouette = max(silhouette, smoothstep(w + 0.004, w - 0.004, d));
    }
    col = mix(col, trunkCol, silhouette);

    // Forest-floor fade at the bottom.
    float floorFade = smoothstep(0.78, 1.0, uv.y);
    col = mix(col, botCol * 0.4, floorFade * 0.7);

    return float4(col, 1.0);
}

// ─── Stage B: COMPOSITE ──────────────────────────────────────────────────────
//
// Samples the world texture written by stage A (bound at [[texture(13)]]) and
// overlays a placeholder web — 8 radial spokes from a hub at (0.5, 0.42) plus
// three concentric "rings" approximated as hub-distance bands.
//
// The renderer's scaffold is what is being proved here, not the visual: any
// future preset that wants real refractive droplets, depth-of-focus, or
// per-layer atmospheric composition follows this same `samples: [...]` pattern.

fragment float4 staged_sandbox_composite_fragment(
    VertexOut in [[stage_in]],
    constant FeatureVector& f [[buffer(0)]],
    texture2d<float, access::sample> worldTex [[texture(13)]]
) {
    float2 uv = in.uv;

    // World backdrop from stage A.
    float3 col = worldTex.sample(sandbox_world_sampler, uv).rgb;

    // Placeholder web overlay — additive light strokes.
    float2 hub  = float2(0.50, 0.42);
    float2 d2   = uv - hub;
    float dist  = length(d2);
    float ang   = atan2(d2.y, d2.x);

    // 8 radial spokes — periodic distance-to-line.
    float spokeStep = 6.2831853 / 8.0;
    float spokeAng  = fract(ang / spokeStep + 0.5) - 0.5;
    float perp      = abs(spokeAng) * spokeStep * dist;
    float spokeMask = smoothstep(0.0026, 0.0014, perp)
                    * smoothstep(0.32, 0.30, dist);

    // Three rings — periodic distance-to-radius.
    float ringDist = abs(fract(dist * 7.5) - 0.5);
    float ringMask = smoothstep(0.04, 0.02, ringDist)
                   * smoothstep(0.04, 0.06, dist)
                   * smoothstep(0.32, 0.28, dist);

    float web = max(spokeMask, ringMask * 0.45);

    // Hub dot.
    float hubMask = smoothstep(0.018, 0.010, dist);
    web = max(web, hubMask);

    col += float3(0.85, 0.92, 1.00) * web * 0.55;
    col = min(col, float3(1.0));
    return float4(col, 1.0);
}
