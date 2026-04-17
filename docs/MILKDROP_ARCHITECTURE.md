# Milkdrop Architecture Research — Findings and Implications for Phosphene

**Status:** Reference document. MV-0 through MV-3 complete (2026-04-17). See "Phase MV Implementation Outcomes" section at the end for what shipped and key learnings. Phase MV is finished; next is Phase 4 (Orchestrator).

**Written:** 2026-04-16, after six failed iterations on Volumetric Lithograph made it clear that preset-level tuning was not converging on "feels musical." Matt challenged the premise: Milkdrop achieves convincing musical synchronization with 20-year-old technology, so why can't we?

This document is the self-contained record of what Milkdrop actually does, where Phosphene's architecture diverges, and what must change to match Milkdrop's baseline musicality. Future sessions can execute the plan without re-doing the research.

---

## 1. Milkdrop's audio vocabulary is identical to ours

From Ryan Geiss's [Milkdrop Preset Authoring Guide](https://www.geisswerks.com/milkdrop/milkdrop_preset_authoring.html) and the [projectM reimplementation](https://github.com/projectM-visualizer/projectm), Milkdrop presets have access to **only these audio inputs**:

| Variable | Meaning |
|---|---|
| `bass`, `mid`, `treb` | AGC-normalized 3-band energies, **centered at 1.0** |
| `bass_att`, `mid_att`, `treb_att` | Smoothed (attenuated) versions of the same |
| `vol`, `vol_att` | Total volume / attenuated total volume |
| Waveform samples | 1D array of PCM samples for the current frame |
| FFT magnitudes | Spectrum bins |
| Beat detection | Internal, drives preset-switching timing |

That is the complete list. Milkdrop presets do **not** have access to:
- Stem separation
- Chord recognition
- Pitch tracking
- Key estimation
- Mood / valence / arousal
- Structural analysis
- Spectral centroid or flux

Phosphene already produces all of the above via MIRPipeline / StemAnalyzer / MoodClassifier / ChromaExtractor / StructuralAnalyzer. **Our audio analysis is richer than Milkdrop's, not poorer.** This eliminates the hypothesis that we lack audio sophistication.

## 2. The AGC normalization convention matters

The [projectM `Loudness.cpp`](https://github.com/projectM-visualizer/projectm/tree/master/src/libprojectM/Audio) source reveals the exact formula Milkdrop uses:

```cpp
m_currentRelative = m_current / m_longAverage;   // exposed as "bass"
m_averageRelative = m_average  / m_longAverage;  // exposed as "bass_att"
```

Both are **ratios against a slowly-decaying running average**, not raw amplitudes. The Milkdrop Preset Authoring Guide explicitly tells authors:

> "`bass` / `mid` / `treb` values — 1 is normal; below ~0.7 is quiet; above ~1.3 is loud."

Authors drive visuals from **deviation from 1.0**:

```
zoom = zoom + 0.1 * (bass - 1.0);       // per-frame equation
my_volume = (bass + mid + treb) / 3;
zoom = zoom + 0.1 * (my_volume - 1.0);  // pulses on loud moments, recedes on quiet
```

### How Phosphene currently does it

[`BandEnergyProcessor.swift:21`](../PhospheneEngine/Sources/DSP/BandEnergyProcessor.swift) implements the same Milkdrop-style AGC with one key difference — our convention centers `bass`/`mid`/`treble` around **0.5** rather than 1.0:

```
/// AGC normalizes output so average levels map to ~0.5, loud moments reach 0.8–1.0.
```

The pipeline is equivalent. The scaling is cosmetic. What isn't cosmetic: **Phosphene preset shaders have been authored using absolute thresholds** like `smoothstep(0.22, 0.32, f.bass)`.

Absolute thresholds are the wrong primitive for an AGC-normalized signal. The output of AGC inherently depends on running-average context — a kick drum that reads as `bass = 0.7` during a sparse section might read as `bass = 0.25` during a busy section, because the running average rose. The kick is equally acoustically loud. Absolute thresholds are brittle across tracks and even across sections of the same track.

**This was a confirmed cause of several "works on one track, breaks on another" failures we hit.** The correct authoring primitive is deviation from center (`bass - 0.5` in our convention, or `bass - 1.0` in Milkdrop's).

## 3. Milkdrop's musical feel comes from *architecture*, not audio

The Milkdrop preset authoring guide describes four mechanisms that together produce musical-feeling visuals from simple audio:

### 3a. Feedback texture

Every frame is a **warped sample of the previous frame**, with decay and new elements drawn on top. The warp shader is fundamentally this:

```glsl
shader_body
{
    ret = tex2D(sampler_main, uv).xyz;   // sample previous frame at warped UV
    ret *= 0.97;                         // gentle decay
}
```

The composite shader then draws new audio-reactive elements (waveforms, shapes) on top of the warped-and-decayed previous frame.

### 3b. Per-vertex warp mesh (32×24 grid by default)

UV displacement is computed **at grid points**, not per-pixel. The preset's per-vertex equations run once per grid vertex and output a per-vertex UV offset. The GPU interpolates across triangles, so DIFFERENT regions of the frame warp differently.

From the guide:
> "The screen is divided into a grid and the code is evaluated at each grid point. The pixels in-between these points interpolate their values from the surrounding 4 points on the grid."

### 3c. Per-frame equations set baseline; per-vertex equations modulate spatially

A preset's per-frame code might say:

```
my_volume = (bass + mid + treb) / 3;
zoom = zoom + 0.1 * (my_volume - 1.0);   // baseline zoom pulses with loudness
```

And its per-vertex code might say:

```
zoom = zoom + rad * 0.1;   // zoom amount varies by radial distance
```

The baseline zoom is the same for all grid points; the per-vertex equation *spatially modulates* it so the center zooms differently from the edges. This creates radial perspective that persists frame-to-frame via the feedback loop.

### 3d. The critical insight — feedback compounds simple inputs

**Because motion accumulates in the feedback texture across many frames, simple audio inputs produce compound organic motion.** A 5% zoom on `bass - 1.0` doesn't look like a pulse — it looks like *breathing*. A slow rotation from `mid` sums over seconds into spiral motion. The visual richness emerges from the feedback loop itself, not from the richness of the audio signal.

Milkdrop does not need symbolic audio analysis because the feedback architecture integrates simple audio into rich visuals.

### Authorable parameters

The guide documents roughly 40 authorable per-frame parameters that Milkdrop preset authors routinely modulate:

| Category | Parameters |
|---|---|
| Motion / geometry | `zoom`, `zoomexp`, `rot`, `warp`, `cx`, `cy`, `dx`, `dy`, `sx`, `sy`, `decay` |
| Waveform display | `wave_mode`, `wave_x`, `wave_y`, `wave_r`/`g`/`b`/`a`, `wave_mystery`, `wave_usedots`, `wave_thick`, `wave_additive`, `wave_brighten` |
| Borders | `ob_size`/`_r`/`_g`/`_b`/`_a`, `ib_size`/`_r`/`_g`/`_b`/`_a` |
| Motion vectors | `mv_r`/`_g`/`_b`/`_a`, `mv_x`, `mv_y`, `mv_l`, `mv_dx`, `mv_dy` |
| Echo / compositing | `echo_zoom`, `echo_alpha`, `echo_orient` |
| Color filters | `gamma`, `darken_center`, `wrap`, `invert`, `brighten`, `darken`, `solarize` |
| Q variables | `q1`–`q32` (user-defined state passed between per-frame → per-vertex → shaders) |

This is a rich authoring vocabulary. Our presets author Metal shader functions directly — more flexible than Milkdrop's equation language, but much heavier and less iterative.

## 4. Phosphene's architectural divergence

Render-pass breakdown of our 11 presets (post-MV-2):

| Preset | Pass type | Uses per-vertex feedback? |
|---|---|---|
| Waveform | `direct` | No |
| Plasma | `direct` | No |
| Nebula | `direct` | No |
| Starburst | `mv_warp` | **Yes — full per-vertex warp** (MV-2) |
| Membrane | `feedback` | Thin — global zoom+rot only |
| FractalTree | `mesh_shader` | No |
| FerrofluidOcean | `post_process` | No |
| GlassBrutalist | `ray_march` + `ssgi` + `post_process` | **No** |
| KineticSculpture | `ray_march` + `post_process` | **No** |
| TestSphere | `ray_march` + `post_process` | **No** |
| VolumetricLithograph | `ray_march` + `post_process` + `mv_warp` | **Yes — full per-vertex warp** (MV-2) |

Prior to MV-2, 9 of 11 presets used no feedback loop. Post-MV-2, two presets use full per-vertex warp. Glass Brutalist, Kinetic Sculpture, and TestSphere are candidates for mv_warp conversion once the MV-2 visual checkpoint passes on VL and Starburst.

Even our two feedback presets have a much thinner warp than Milkdrop's per-vertex mesh. See [`Common.metal:107-156`](../PhospheneEngine/Sources/Renderer/Shaders/Common.metal):

```metal
fragment float4 feedback_warp_fragment(...) {
    float2 uv = in.uv;
    float2 centered = uv - 0.5;
    float rad = length(centered);
    float zoom = feedback.base_zoom * 0.3;
    centered *= 1.0 - zoom;                    // single global zoom
    float rot = feedback.base_rot * 0.2 * features.mid_att + 0.001 * sin(t * 0.2);
    // ... single global rotation applied uniformly to all pixels ...
}
```

A single zoom and rotation applied uniformly across the frame. Milkdrop warps every pixel differently based on its screen position. The difference is the mechanism that produces compound organic motion vs. simple pulsation.

## 5. Summary of why we've struggled

The Milkdrop-quality "musical" feel we've been chasing is not achievable in the current architecture for ray-march or direct presets. The issue is not audio-analysis capability (we have more than Milkdrop) but the *missing mechanism that turns simple audio into compound motion*:

1. **Per-vertex feedback warp**, which Milkdrop pioneered and uses in every preset.
2. **Proper audio-deviation primitives**, which our AGC pipeline already produces but our preset authoring has not used correctly.

Everything else (richer stems, pitch tracking, harmonic analysis) is enhancement *on top of* this foundation. Without the foundation, even perfect audio analysis will not produce Milkdrop-quality musical feel — it will just produce more-informed reactive visuals.

## 6. What to do about it

Three coordinated phases, each independently shippable and each gated on a visual checkpoint:

- **MV-1 — Milkdrop-correct audio primitives.** ✅ Complete (commit `a05fd753`). `bassRel`/`bassDev` etc. in FeatureVector; `{stem}EnergyRel/Dev` in StemFeatures. VolumetricLithograph reference implementation. 4 contract tests.
- **MV-2 — Per-vertex feedback warp mesh.** ✅ Complete (commit `c8cd558f`). `mv_warp` render pass; 32×24 vertex grid; three-pass warp/compose/blit pipeline; VolumetricLithograph and Starburst converted. 2 GPU regression tests.
- **MV-3 — Beyond-Milkdrop extensions.** ✅ Complete (2026-04-17). See MV-3 outcomes below.

See [ENGINEERING_PLAN.md](ENGINEERING_PLAN.md) Phase MV section for full increment definitions, file lists, and verification plans.

## 7. Phase MV Implementation Outcomes

Documenting what shipped and key implementation learnings for future reference.

### MV-0 (2026-04-16)

The `RayMarch.metal` miss/sky path now gates the `lightColor.rgb` tint behind `sceneParamsB.y > 1e5` (fog-disabled sentinel). Result: Glass Brutalist and Kinetic Sculpture retain cool blue sky contrast; VolumetricLithograph (fog disabled, `sceneParamsB.y = 1e6` sentinel) still picks up warm sky tint. The sentinel is set by `PresetDescriptor+SceneUniforms.makeSceneUniforms()` when `scene_fog == 0`.

### MV-1 (2026-04-16)

Deviation primitives landed as designed. **Checkpoint outcome:** deviation alone did not converge VL on musical feel — the absolute-threshold anti-pattern was a real problem (confirmed the fix across tracks) but it was not the primary bottleneck. The missing feedback mechanism (MV-2) was the critical path, as MILKDROP_ARCHITECTURE.md had predicted.

### MV-2 (2026-04-17)

Three non-obvious implementation discoveries:

1. **`@unchecked Sendable` for Metal resource structs.** Swift 6.0 strict concurrency requires `Sendable` on structs stored behind locks. `MTLTexture` is a protocol with no `Sendable` conformance, so `MVWarpState` (which contains three textures) must be `@unchecked Sendable`. The struct is only mutated under `mvWarpLock` so the annotation is safe.

2. **`SceneUniforms` preprocessor guard.** `mvWarpPerFrame` takes a `constant SceneUniforms& s` parameter to allow warp functions to use scene-level state (camera position, accumulated audio time). But `SceneUniforms` is only defined in `rayMarchGBufferPreamble`, which is not injected for direct (non-ray-march) presets. Solution: `#ifndef SCENE_UNIFORMS_DEFINED / #define SCENE_UNIFORMS_DEFINED` guard in both preambles — the `mvWarpPreamble` defines it for direct presets; the ray-march preamble guards its own definition to prevent redefinition when both preambles compile together (ray-march + mv_warp combos).

3. **Starburst birds removed intentionally.** Starburst previously used `["feedback", "particles"]`. The MV-2 design decision was to replace both with `["mv_warp"]` only. The murmuration particle system's murmuration-like motion is now created by the feedback warp accumulating and smearing the sky backdrop — different mechanism, similar emergent cloud-like behavior. The explicit bird silhouettes were dropped.

### MV-3 (2026-04-17)

Three sub-increments landed together (D-028):

**MV-3a — Richer per-stem metadata.** `StemFeatures` expanded 32→64 floats (128→256 bytes). Per-stem `{onsetRate, centroid, attackRatio, energySlope}` computed in `StemAnalyzer.computeRichFeatures()`. AttackRatio uses fast (τ=50ms) vs slow (τ=500ms) RMS EMA — a transient/sustained discriminator that works without any beat detection. OnsetRate uses a leaky integrator (τ=0.5s) on half-wave-rectified RMS flux. EnergySlope is a simple FPS-independent finite difference on attenuated energy.

**MV-3b — Beat phase predictor.** New `BeatPredictor` class. Detects onset rising edges from `max(beatBass, beatMid, beatComposite)`. Measures inter-beat intervals and applies IIR smoothing (period = 0.3×old + 0.7×measured). Exposes `beatPhase01` (0 at last beat → 1 at next predicted beat) in `FeatureVector` floats 35–36. Bootstrap from metadata BPM seeds the period before the first onset. VolumetricLithograph now ramps zoom starting at `beat_phase01 > 0.80` for anticipatory pre-beat compression.

**MV-3c — Vocal pitch tracking (YIN).** New `PitchTracker` (YIN autocorrelation, vDSP_dotpr). Critical implementation finding: the standard "find first τ below threshold" implementation causes catastrophic parabolic extrapolation — the first sub-threshold crossing falls on the descending slope of the CMNDF, not the valley floor. Fix: after the threshold crossing, advance forward while CMNDF keeps decreasing to find the local minimum before interpolating. This single fix converted 35-cent error to <5-cent error for pure tones. Exposes `vocalsPitchHz`/`vocalsPitchConfidence` in `StemFeatures`. VolumetricLithograph uses pitch to shift the IQ cosine palette hue ±0.15 (cooler on rising pitch, warmer on falling).

## 8. Related Decisions

- **D-026** — "Drive preset shaders from deviation, not absolute energy" (MV-1)
- **D-027** — "Adopt Milkdrop-style per-vertex feedback warp as an opt-in render pass" (MV-2)
- **D-028** — "Extend Milkdrop's model with Apple-Silicon-only capabilities only after MV-2 proves out" (MV-3)

## 8. Sources consulted

- [Milkdrop Preset Authoring Guide](https://www.geisswerks.com/milkdrop/milkdrop_preset_authoring.html) — Ryan Geiss's authoritative documentation.
- [Milkdrop 2 Preset Authoring Guide](https://www.geisswerks.com/hosted/milkdrop2/milkdrop_preset_authoring.html) — updated with pixel-shader details.
- [projectM GitHub](https://github.com/projectM-visualizer/projectm) — LGPL reimplementation.
- [projectM `Loudness.cpp`](https://github.com/projectM-visualizer/projectm/blob/master/src/libprojectM/Audio/Loudness.cpp) — confirmed the AGC normalization formula.
- [presets-cream-of-the-crop](https://github.com/projectM-visualizer/presets-cream-of-the-crop) — Jason Fletcher's curated preset pack.
- Matt's product-vision research document ("Architectural Framework for Phosphene"): cross-referenced; noted its aspirational claims (sub-millisecond latency, HTDemucs swap, Basic Pitch port) that are not part of this plan.
- [`BandEnergyProcessor.swift`](../PhospheneEngine/Sources/DSP/BandEnergyProcessor.swift) — confirmed our existing Milkdrop-style AGC.
- [`Common.metal`](../PhospheneEngine/Sources/Renderer/Shaders/Common.metal) — confirmed our existing feedback warp is global, not per-vertex.
- Preset `.json` descriptors in [`PhospheneEngine/Sources/Presets/Shaders/`](../PhospheneEngine/Sources/Presets/Shaders/) — confirmed 9 of 11 presets do not use feedback.
