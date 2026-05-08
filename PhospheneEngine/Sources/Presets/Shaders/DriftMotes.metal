// DriftMotes.metal — Sky backdrop for the Drift Motes preset (post-DM.2).
//
// Three layered elements compose the backdrop, all rendered into the same
// fragment (no new render pass — D-029 keeps the pass set
// `["feedback", "particles"]`):
//
//   1. Warm-amber vertical gradient (DM.1 baseline) — deep mahogany at
//      the zenith, slightly brighter near the floor.
//   2. Cool blue-gray floor fog via `vol_density_height_fog`, multiplied
//      into the lower band so the upper sky stays warm.
//   3. One dramatic god-ray light shaft via `ls_radial_step_uv`, additive
//      on top of the fog so it visually "punches through" the haze.
//
// Audio coupling: only `f.mid_att_rel` modulates the shaft intensity
// (continuous, not beat-driven — the shaft "breathes" with vocal energy).
// The cold-stems window is handled at the FeatureVector level (mid_att_rel
// is a deviation primitive — D-026 — so cold and warm sections of a track
// produce comparable shaft brightness without absolute thresholds).

fragment float4 drift_motes_sky_fragment(
    VertexOut in [[stage_in]],
    constant FeatureVector& f [[buffer(0)]]
) {
    float2 uv = in.uv;

    // ── 1. Warm-amber vertical gradient (DM.1 baseline) ───────────────────
    float t = uv.y;
    float3 top    = float3(0.05, 0.03, 0.02);   // Deep mahogany at zenith.
    float3 bottom = float3(0.10, 0.07, 0.04);   // Slightly brighter near floor.
    float3 col = mix(top, bottom, t);

    // ── 2. Floor fog (vol_density_height_fog) ─────────────────────────────
    // Map uv.y → world-space height so the utility gives non-zero density
    // in the lower band of the frame. uv.y=1.0 (frame floor) → p.y=0; uv.y=0.0
    // (zenith) → p.y=1.0. Scale 12.0 controls overall density; falloff 0.85
    // is the exponential decay rate. The 0.05 multiplier on the returned
    // density tunes the visual band thickness — empirically, higher values
    // bleed fog into the upper-mid frame where the shaft anchor lives.
    float3 fogPos     = float3(0.0, max(0.0, 1.0 - uv.y), 0.0);
    float  fogDensity = vol_density_height_fog(fogPos, 12.0, 0.85);
    float  fogMask    = clamp(fogDensity * 0.05, 0.0, 1.0);
    float3 fogColor   = float3(0.18, 0.20, 0.24);
    // Multiplicative composite (warm sky × cool fog → desaturated shadow).
    col = mix(col, col * fogColor * 3.5, fogMask);

    // ── 3. Light shaft (ls_radial_step_uv) ────────────────────────────────
    // Sun anchor at UV (-0.15, 1.20): off-screen upper-left. Shaft axis runs
    // from the anchor through frame centre, giving the ≈30° from-vertical
    // cinematographic angle the design specifies. 32 radial samples per
    // fragment trace from `uv` toward `sunUV`; at each step we evaluate a
    // soft cone mask centred on the shaft axis and accumulate with
    // exponential decay. Decay 0.95 / weight 0.04 are tuned so the shaft
    // is clearly visible at zero audio and saturates around mid_att_rel = 1.
    float2 sunUV    = float2(-0.15, 1.20);
    float2 axisDir  = normalize(float2(0.5, 0.5) - sunUV);
    float2 perpDir  = float2(-axisDir.y, axisDir.x);
    float  shaftAccum = 0.0;
    const int kShaftSteps = 32;
    for (int i = 0; i < kShaftSteps; i++) {
        float2 sUV          = ls_radial_step_uv(uv, sunUV, i, kShaftSteps);
        float2 toSample     = sUV - sunUV;
        float  along        = max(0.0, dot(toSample, axisDir));
        float  perpFromAxis = abs(dot(toSample, perpDir));
        // Cone widens with distance from the sun (0.04 base, +0.12·along).
        float  coneHalfWidth = 0.04 + along * 0.12;
        float  occlusion     = 1.0 - smoothstep(0.0, coneHalfWidth, perpFromAxis);
        shaftAccum += ls_radial_accumulate_step(occlusion, 0.95, 0.04, i);
    }
    // Continuous melody-driven brightness (D-026 deviation form).
    float  shaftIntensity = 0.65 + 0.25 * f.mid_att_rel;
    float3 shaftColor     = float3(1.00, 0.78, 0.45);
    col += shaftColor * shaftIntensity * shaftAccum;

    return float4(col, 1.0);
}
