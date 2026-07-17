# Your first preset — a complete working pair in ~60 lines

The fastest path from zero to pixels-moving-with-music (PUB.7). Copy both
files into `~/Library/Application Support/Phosphene/Presets/` while the app
runs — hot-reload compiles every save and swaps it in live. Jargon:
[docs/GLOSSARY.md](../GLOSSARY.md); when it lands in the repo, follow
[NEW_PRESET_CHECKLIST.md](NEW_PRESET_CHECKLIST.md).

The two smallest shipped presets, `Plasma` and `Waveform`
(`PhospheneEngine/Sources/Presets/Shaders/`, 55 and 101 lines), are real
worked examples of this exact shape; `Skein` and `Nacre` show the
full-featured registers.

## Halo.metal

Every direct-pass shader gets Phosphene's preamble prepended at compile time
(`VertexOut`, `FeatureVector`, helpers — see ARCHITECTURE §GPU Contract
Details). Your file is JUST the fragment:

```metal
// Halo — a breathing ring driven by continuous energy.
// One deviation primitive (bass_dev) + one smoothed band (mid_att):
// NOTE: the MSL preamble uses snake_case field names (bass_dev), while the
// Swift FeatureVector and the sidecar audio_routes use camelCase (bassDev).
// the Layer-1 recipe from the Audio Data Hierarchy.

fragment float4 preset_fragment(VertexOut in [[stage_in]],
                                constant FeatureVector& features [[buffer(0)]],
                                constant float* fftMagnitudes [[buffer(1)]],
                                constant float* waveformData [[buffer(2)]]) {
    float2 p = (in.uv - 0.5) * 2.0;
    p.x *= features.aspect_ratio;
    float r = length(p);

    // Continuous energy is the PRIMARY driver (never raw beat detections):
    // the ring breathes with bass deviation, glows with smoothed mids.
    float radius   = 0.45 + 0.18 * features.bass_dev;
    float softness = 0.05 + 0.08 * features.mid_att;
    float ring = exp(-pow((r - radius) / softness, 2.0));

    // Slow hue drift on wall-clock; treble tilts it warm.
    float hue = fract(features.time * 0.02 + features.treb_att * 0.15);
    float3 color = 0.5 + 0.5 * cos(6.28318 * (hue + float3(0.0, 0.33, 0.67)));

    // Silence stays calm-but-alive (D-019): a dim floor, never black-out.
    float floorGlow = 0.06;
    return float4(color * (ring + floorGlow), 1.0);
}
```

## Halo.json

```json
{
  "name": "Halo",
  "family": "hypnotic",
  "duration": 25,
  "description": "A breathing energy ring — bass deviation drives the radius, smoothed mids the glow.",
  "author": "you",
  "passes": ["direct"],
  "visual_density": 0.3,
  "motion_intensity": 0.4,
  "color_temperature_range": [0.3, 0.7],
  "fatigue_risk": "low",
  "certified": false,
  "rubric_profile": "lightweight",
  "audio_routes": [
    { "route": "ring_radius", "primitive": "bassDev", "kind": "continuous" },
    { "route": "ring_glow",   "primitive": "midAtt",  "kind": "continuous" }
  ]
}
```

## Run it

1. Launch Phosphene → Settings → Visuals → **Show uncertified presets**.
2. File → Open Local File (⌘O) — no streaming account needed.
3. Cycle to *Halo* (arrow keys). Edit the `.metal`, save — it hot-swaps.
   A broken save toasts and keeps the last-good version
   (`log stream --predicate 'subsystem == "com.phosphene.presets"'` for the
   compiler diagnostics).

## Where to go next

- **The design rule that matters most:** drive visuals from continuous
  energy (`bassDev`/`bassRel`, stem `*EnergyDev`), not raw beat events —
  CLAUDE.md §Audio Data Hierarchy explains why, from hard experience.
- Field maps for everything you can read: ARCHITECTURE §Key Types
  (`FeatureVector`, `StemFeatures`).
- The quality bar and sidecar schema: SHADER_CRAFT (§17 for every key).
- The authoring discipline that saves weeks: PRESET_SESSION_CHECKLIST.
