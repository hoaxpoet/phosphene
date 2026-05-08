# Drift Motes Rendering Architecture Contract

## Purpose

This contract defines the required rendering architecture for Drift Motes. It translates the design spec into implementation constraints, pass responsibilities, debug outputs, and acceptance gates.

This file is authoritative for implementation. `DRIFT_MOTES_DESIGN.md` remains authoritative for visual intent.

> **Visual target reframe (D-096).** All "must read as ..." acceptance gates below are aesthetic-family bars, not pixel-match contracts. A render that reads as belonging in the same visual conversation as the reference — real photographic god-ray with mote-laden volumetric, force-field motion (not flocking), cinematographic backdrop — passes the gate. A render that reads like the called-out failure modes (flock repetition, generic particle.js dust demo, beat-pulsing motes) fails it. Pixel-fidelity is an explicit non-goal. Real-time constraints (Tier 2 ~2.1 ms / Tier 1 ~1.6 ms p95) are inviolable; if a feature cannot be achieved in budget, document the gap and pick the nearest achievable approximation.

## Required passes

`passes: ["feedback", "particles"]` — same pass set as Murmuration (mv_warp is incompatible with particle systems per D-029). Drift Motes is the second consumer of this pipeline and the first non-flock consumer.

| Pass | Name | Required output | Depends on | Debug view required |
|---|---|---|---|---|
| 1 | SKY_BACKDROP | Warm-amber vertical gradient written to scene texture (top `(0.05, 0.03, 0.02)`, bottom `(0.10, 0.07, 0.04)`, valence-tinted) | scene uniforms + valence | Yes |
| 2 | PARTICLE_COMPUTE | Particle buffer state advanced one frame: positions, velocities, ages, recycled hues | particle buffer (previous frame) + FeatureVector + StemFeatures + uniforms (dt, time) | No (state buffer; debug via PARTICLE_RENDER) |
| 3 | PARTICLE_RENDER | Soft Gaussian sprite (~6 px) per particle, additively blended onto scene texture, brightness scaled by shaft-density-at-position × per-particle hue | SKY_BACKDROP + particle buffer | Yes |
| 4 | VOLUMETRIC_OVERLAY | Light shaft (`ls_shadow_march`) + floor fog (`vol_density_height_fog`) composited onto scene texture | PARTICLE_RENDER + audio uniforms (mid, bass, beat_phase01) | Yes |
| 5 | FEEDBACK_COMPOSE | Alpha-blend current scene with previous-frame accumulator at `decay = 0.92`, presented to drawable | VOLUMETRIC_OVERLAY + previous-frame accumulator | Yes |

## Minimum viable milestone (Session 1 scope)

Before any audio routing, light shaft, or per-particle hue baking, the implementation must support:

- particle compute kernel integrating wind + curl_noise + lifecycle recycle (no flocking, no audio coupling beyond the warmup-blend stem reads);
- particle render path drawing soft Gaussian sprites at `default_warm_hue()` (no per-particle hue baking yet);
- sky backdrop drawn as warm-amber gradient;
- 800 particles spawned at the top of the shaft volume, recycled when age > life or position out of bounds;
- visual harness contact sheets for the bare-minimum render (compute + sprite + backdrop, no shaft, no fog, no feedback).

`DriftMotesNonFlockTest` passes at this milestone — render 200 frames, sample 50 random particle pairs, assert pairwise distance distribution does NOT contract (no cohesion).

## Blockers

Drift Motes cannot be certified if any of the following are missing:

- no particle compute kernel infrastructure (Murmuration's `Particles.metal` path is the precedent);
- no `Particle` struct with sufficient capacity for `(position, velocity, age, life, color)` — verify the existing `color` slot (4× Float32) can carry baked hue or extend if not (open question §11.1 in design doc);
- no sprite render path with additive blending (existing in `PresetLoader` for Murmuration);
- no `ls_shadow_march` or `ls_radial_step_uv` from `Volume/LightShafts.metal` (V.2);
- no `vol_density_height_fog` from `Volume/ParticipatingMedia.metal` (V.2);
- no `curl_noise` from `Noise/` utility tree (V.1);
- no `feedback` pass with tunable `decay` parameter;
- no `StemFeatures.vocalsPitchHz` + `vocalsPitchConfidence` access in the compute kernel (per design §5.2 — emission-time pitch read into `Particle.color`);
- no `stems.drums_energy_dev` access for dispersion shock (D-026 deviation primitive);
- no way to capture pass-separated debug output (sprite-only / shaft-only / fog-only / final composite) — required for diagnostic review.

## Certification fixtures

Each acceptance phase must be rendered against the standard fixture set:

- **silence** (`totalStemEnergy == 0`, all `*_rel` and `*_dev` at zero) — verifies §5.8 fallback;
- **steady mid-energy** (`f.mid_att_rel ≈ 0.3`, `f.bass_att_rel ≈ 0.3`, no drum onsets) — verifies continuous primary drivers and emission rate scaling;
- **beat-heavy** (drum onsets every ~500 ms, `stems.drums_energy_dev` peaks at 0.4) — verifies dispersion shock fires and bounds, no runaway dispersion;
- **sustained bass** (`f.bass_att_rel` held high for ≥ 4 s) — verifies wind force ramps up smoothly and motes carry through field without escaping bounds;
- **vocal pitch sweep** (`vocalsPitchHz` swept 80 Hz → 800 Hz over 4 s with confidence 0.6) — verifies emission-time hue baking and per-particle hue persistence;
- **high-valence** (`f.valence ≈ 0.8`) — backdrop skews warm;
- **low-valence** (`f.valence ≈ 0.2`) — backdrop skews cool (within `color_temperature_range: [0.55, 0.85]`);
- **stem warmup** (`totalStemEnergy` ramping 0 → 1 over first 8 s of fixture) — verifies D-019 blend through `smoothstep(0.02, 0.06, totalStemEnergy)` for hue baking and shock gate.

## Stop conditions

Stop implementation and report a blocker if:

- particles exhibit ANY flocking behavior (cohesion, alignment, neighbor-seeking) — root cause is curl_noise turbulence too weak relative to inter-particle interaction; remove any neighbor query from the compute kernel and re-tune turbulence amplitude. The non-flock property is the preset's identity per design §1; if it fails, return to compute-kernel design before any other work.
- `Particle` struct cannot carry baked hue + saturation + value separately AND extending the struct breaks Murmuration (the shared particle path). Mitigation: pack hue into a single Float32 (16-bit hue + 16-bit value) and reconstruct in the sprite shader; document the packing in CLAUDE.md alongside the WaveGPU pattern reference.
- `ls_shadow_march` cone half-angle ~12° is too tight at the design's sun position `(2.5, 5.0, 1.0)` — the shaft visibly clips the scene or doesn't intersect the mote field. Mitigation: widen cone to ~18° or move sun position closer; document in commit message.
- Dispersion shock produces runaway particle velocity (particles escape bounds or oscillate at high velocity after impulse). Mitigation: stronger velocity damping (current `0.97` per frame) or cap velocity magnitude post-shock. Verified by `DriftMotesShockBoundsTest`.
- Per-frame `vocalsPitchHz` reads produce visible hue jitter on rapid melodic phrases. Same mitigation precedent as Aurora Veil/Crystalline Cavern: 5-frame smoothing window on the SpectralHistoryBuffer read.
- The visual harness cannot capture pass-separated outputs (sprite-only / shaft-only / fog-only) — required for diagnostic review at session boundaries.
- Performance exceeds Tier 1 budget at the specified scene complexity (800 particles + 32-sample shaft + fog + feedback). Mitigation order: (1) reduce particle count to 600, (2) reduce shaft samples to 24, (3) drop to Tier 1 path (400 particles + 24 samples).

## Acceptance gates per phase

**Session 1 — Compute kernel + particle render + backdrop.**
- Particle compute integrates wind + curl_noise + lifecycle recycle correctly.
- Particles spawn at top of shaft volume, drift in force field, recycle when age exceeds life or position exits bounds.
- Sprite render produces 6-px soft Gaussian blobs at `default_warm_hue()`.
- Sky backdrop renders warm-amber gradient.
- `DriftMotesNonFlockTest` passes (no cohesion).

**Session 2 — Light shaft + atmosphere + per-particle hue baking.**
- `ls_shadow_march` shaft visible from upper-left (sun position `(2.5, 5.0, 1.0)`, direction `(-0.4, -0.85, 0.0)`, cone half-angle ~12°).
- `vol_density_height_fog` floor fog visible at floor altitude.
- Per-particle hue baking from `vocalsPitchNorm` at emission time, gated by `vocalsPitchConfidence > 0.4`, falls back to `default_warm_hue()` when confidence low or pre-warmup.
- Sprite brightness scaled by shaft density at particle position — particles inside shaft volume read ≥ 1.5× brighter than outside.
- `DriftMotesPitchHueBakeTest` passes (pitch sweep produces lockstep hue distribution shift).
- `DriftMotesShaftIntersectionTest` passes (≥ 1.5× brightness ratio inside vs outside shaft).

**Session 3 — Audio routing + drum shock + cert.**
- All audio routes wired per design §5.6 — `f.bass_att_rel`, `f.mid_att_rel`, `f.valence`, `f.beat_phase01`, `stems.vocalsPitchHz`, `stems.vocalsPitchConfidence`, `stems.drums_energy_dev`.
- Dispersion shock fires only when `stems.drums_energy_dev > 0.3`, applies radial impulse from shaft center.
- Anticipatory shaft pulse on `f.beat_phase01` approach curve adds subtle shaft brightness ramp (NOT per-mote brightness flashing).
- `DriftMotesShockBoundsTest` passes (post-shock max particle velocity bounded; no runaway dispersion).
- D-019 stem warmup verified — first ~10 s of every fixture renders with `default_warm_hue()` and shock disabled.
- D-026 deviation primitives verified by `FidelityRubricTests` — no absolute thresholds anywhere except the explicit deviation-form `drums_energy_dev > 0.3` shock gate.
- Performance profile: p95 ≤ Tier 2 2.1 ms / Tier 1 1.6 ms across all fixtures.
- M7 review against `01_atmosphere_dust_motes_light_shaft.jpg` — passes aesthetic-family bar per D-096 (shaft composition, mote density, shaft-mote interaction brightness ratio).
- Anti-reference gate: rendered output does NOT exhibit flocking, beat-pulsing motes, or shaft-less mote drift. If any of these are observed, return to the relevant session for re-tuning (flocking → Session 1; beat-pulsing → Session 3 audio routing; shaft-less → Session 2 atmosphere).
- `certified: true` flipped in JSON sidecar after all gates pass.

## Preset-specific tests (per design §8)

| Test | Verifies | Passes when |
|---|---|---|
| `DriftMotesNonFlockTest` | Force-field motion, NOT flocking (preset identity per design §1) | 200 frames rendered; 50 random particle pairs sampled; pairwise distance distribution does NOT contract over time (no cohesion) |
| `DriftMotesPitchHueBakeTest` | Per-mote hue baking from `vocalsPitchNorm` at emission time | `vocalsPitchHz` swept 80→800 Hz over 4 s; emitted-particle hues sampled over time; hue distribution shifts in lockstep with pitch (with one-second lag for emission cadence) |
| `DriftMotesShockBoundsTest` | Dispersion shock bounded; no runaway dispersion | `drums_energy_dev` pulsed 0 → 0.6 → 0; post-shock max particle velocity bounded (specific bound TBD during Session 3 — likely ~3.0 units/sec) |
| `DriftMotesShaftIntersectionTest` | Mote brightness modulated by shaft intersection (mandatory must-have per design §6) | 100 particles sampled by position; particles inside shaft volume have brightness ≥ 1.5× particles outside |
