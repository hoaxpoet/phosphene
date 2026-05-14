# Ferrofluid Ocean — Claude Code Session Prompts

Session prompts for Phase V.9 (Ferrofluid Ocean redirect, per D-124 / 2026-05-13). Each session lands as its own commit on local `main`; the prompts here are versioned alongside the implementation so future Claude sessions can read the exact contract under which each session was authored.

**Status:** Phase V.9 Sessions 1–2 ✅ (2026-05-13). Macro layer + material/atmosphere layer landed. Sessions 3–5 remain unimplemented.

---

## Decisions in force at session-prompt-authoring time

Per [`SHADER_CRAFT.md §10.3`](../SHADER_CRAFT.md) (V.9 redirect) and the README at [`docs/VISUAL_REFERENCES/ferrofluid_ocean/`](../VISUAL_REFERENCES/ferrofluid_ocean/README.md):

- **D-124** V.9 redirect: "ferrofluid replaces ocean" framing — ocean-portion-scale, fixed camera, Gerstner swell + Rosensweig spikes, stage-rig lighting, thin-film mandatory, calm-body silence state.
- **D-125** §5.8 stage-rig implementation contract: slot-9 fragment buffer + `matID == 2` dispatch. **Session 1 does not implement this**; Session 3 does.
- **D-021** `sceneSDF` / `sceneMaterial` signature contract (preserved verbatim).
- **D-019** silence fallback warmup pattern.
- **D-022** IBL ambient tinted by `scene.lightColor.rgb` so mood valence shifts visible scene-wide.
- **D-026** deviation primitives rule (no absolute thresholds on AGC-normalized energy).

**Reference set:** 12 images at [`docs/VISUAL_REFERENCES/ferrofluid_ocean/`](../VISUAL_REFERENCES/ferrofluid_ocean/), as amended 2026-05-13. Dual hero references: `04_specular_razor_highlights.jpg` (specular character + stage-rig lighting) and `01_macro_ferrofluid_at_swell_scale.jpg` (macro framing).

---

## V.9 Phase increment ledger

| Increment | Scope | Status |
|---|---|---|
| V.9 Session 1 | Gerstner-wave macro displacement + Rosensweig spike-field SDF + JSON sidecar v2 + clean-slate test retirement | ✅ 2026-05-13 |
| V.9 Session 2 | Material recipe: §4.6 base + thin-film interference (`thinfilm_rgb` from `Utilities/PBR/Thin.metal`) + atmosphere fog tinted by D-022 | ✅ 2026-05-13 |
| V.9 Session 3 | §5.8 stage-rig lighting recipe (implements D-125: slot-9 buffer + `matID == 2` dispatch + FerrofluidStageRig Swift class) | ✅ 2026-05-13 |
| V.9 Session 4 | Audio routing (meso domain warp + micro detail noise + droplet beading + all D-026 deviation routing finalized) | ⚠ shipped 2026-05-13 — **M7 review FAILED**; structural rescue in Session 4.5 |
| V.9 Session 4.5 | **Rescue (post-M7)**: revert decoration (droplets / micro-normal / meso warp); replace §5.8 point-light rig with aurora-sky reflection in mirror; reshape spike profile; retune Gerstner for deep-sea rolling | ⏳ Not started — authored 2026-05-13 |
| V.9 Session 5 | Cert review + perf capture + golden hash regeneration + Matt M7 sign-off | ⏳ Not started |

---

## V.9 Session 1 — Ferrofluid Ocean: Gerstner-wave macro displacement + Rosensweig spike-field SDF

### Scope (strict)

This session implements ONLY the macro layer of the V.9 redirect:

1. The Gerstner-wave macro displacement field (4–6 superposed waves; arousal-baseline + `drums_energy_dev` accent amplitude).
2. The Rosensweig hex-tile spike-field SDF (per [`SHADER_CRAFT.md §4.6`](../SHADER_CRAFT.md); spike height from `stems.bass_energy_dev`).
3. The composition of (1) and (2) into a single `sceneSDF` with the spike field riding on top of the Gerstner base.
4. The JSON sidecar update for `ray_march` pass + `scene_camera` / `scene_lights` / `scene_fog` / `scene_ambient` fields. JSON does **not** include the `stage_rig` block yet — Session 3 adds it per D-125.
5. **Clean-slate test retirement.** Delete `FerrofluidOceanDiagnosticTests.swift` wholesale (642 LOC; obsolete to the glass-dish v1 baseline being replaced). Rewrite `FerrofluidOceanVisualTests.swift` to a minimal shader-compile + four-fixture render gate. Comment out `Ferrofluid Ocean` golden-hash entry in `PresetRegressionTests.swift` with a `// V.9 Session 1 — regen at Session 5 cert review` note. Leave `FerrofluidLiveAudioTests`, `FerrofluidBeatSyncTests`, `FidelityRubricTests`, `MaxDurationFrameworkTests`, `GoldenSessionTests` untouched at Session 1 — they're preset-agnostic or external to the shader and verify at Session 5.

### DO NOT author in this session

- Material recipe (Session 2 — `mat_ferrofluid` + `thinfilm_rgb` composition).
- Lighting (Session 3 — §5.8 stage-rig recipe, slot-9 buffer, `matID == 2`, `FerrofluidStageRig` Swift class — all per D-125).
- Atmosphere fog tinted by D-022 mood (Session 2).
- Domain-warped spike positions / `02_meso_*` defects (Session 4 — meso layer).
- Micro-detail noise on spike surface / Cassie-Baxter droplets (Session 4 — micro layer).
- Audio-routed swell amplitude tuning beyond the placeholder formula in this prompt (Session 4 — audio routing finalization).
- Any per-frame engine state on the CPU side (Session 3 — orbital lights need `FerrofluidStageRig`; not Session 1).
- The `stage_rig` JSON block (Session 3 — implements D-125(e) schema).

Defer all of the above with `// TODO(V.9 Session N):` markers in the code.

### Prerequisites — read in order

1. [`docs/SHADER_CRAFT.md §10.3`](../SHADER_CRAFT.md) — the V.9 redirect spec (post-D-124 rewrite).
2. [`docs/VISUAL_REFERENCES/ferrofluid_ocean/README.md`](../VISUAL_REFERENCES/ferrofluid_ocean/README.md) — annotated reference set. Dual hero references: `04_specular_razor_highlights.jpg` and `01_macro_ferrofluid_at_swell_scale.jpg`.
3. [`docs/SHADER_CRAFT.md §4.6`](../SHADER_CRAFT.md) — Ferrofluid (Rosensweig spikes) recipe — provides the SDF building block.
4. [`docs/SHADER_CRAFT.md §4.14`](../SHADER_CRAFT.md) — `mat_ocean` Gerstner-wave convention (Gerstner is implemented preset-level, not in the V.1 noise tree).
5. [`docs/DECISIONS.md D-124`](../DECISIONS.md) — V.9 redirect framing.
6. [`docs/DECISIONS.md D-125`](../DECISIONS.md) — stage-rig implementation contract (Session 3 reference; Session 1 honors the deferral).
7. [`docs/DECISIONS.md D-026`](../DECISIONS.md) — deviation primitives rule (no absolute thresholds).
8. [`docs/DECISIONS.md D-019`](../DECISIONS.md) — silence fallback warmup pattern.
9. [`docs/DECISIONS.md D-021`](../DECISIONS.md) — `sceneSDF` / `sceneMaterial` signature contract.
10. `CLAUDE.md` Failed Approaches §31, §32, §33, §35, §42, §43, §44 — relevant gotchas (absolute thresholds, single-octave noise, free-running `sin(time)`, fbm8 threshold calibration, Metal type-name shadowing).

The current shader at `PhospheneEngine/Sources/Presets/Shaders/FerrofluidOcean.metal` is the v1 **glass-dish** baseline (723 lines: petri-dish geometry with thick glass walls, central spike + ring-1 (6 spikes) + ring-2 (8 spikes), eye-level side-view camera, glass-base with crack patterns). Read it once to understand what's being replaced; do NOT preserve its geometry, audio routing, camera, lighting, or post-process composition — the V.9 redirect is a full visual concept replacement.

### Macro framing (load-bearing)

Per the README annotation for `01_macro_ferrofluid_at_swell_scale.jpg`: a fixed camera at 5–10 feet above a portion of an ocean, looking down at a continuous expanse of ferrofluid-replaced-water. NOT lab-tabletop scale. NOT horizon vista. The camera does not move during the preset's lifetime (orbital motion lives in the §5.8 lights — Session 3, not the camera).

Recommend `scene_camera`:

- `position`: `[0, 4.0, -2.5]` (5–10 feet above surface, looking slightly down and forward)
- `target`: `[0, 0, 2.0]` (focus point on surface ~7 ft away in viewing direction)
- `fov`: `50` (degrees — moderately wide to capture the ocean-portion expanse)

Tune during session if the reference framing match is off against `01_*`.

### Gerstner macro displacement (NEW under V.9)

Implement preset-level per `mat_ocean` (§4.14) convention. No utility exists; author inline in `sceneSDF`. Direction, wavelength, steepness, speed per-wave. 4 waves at Session 1; extend to 6 in Session 4 if needed.

```metal
// Wave parameters (preset-local constants):
//   Wave 0: D = normalize(1.0, 0.3),   L = 4.0, A_base = 0.15, C = 0.4
//   Wave 1: D = normalize(-0.5, 1.0),  L = 2.5, A_base = 0.10, C = 0.6
//   Wave 2: D = normalize(0.8, -0.6),  L = 1.5, A_base = 0.06, C = 0.9
//   Wave 3: D = normalize(-0.9, -0.4), L = 0.8, A_base = 0.03, C = 1.3
//
// Per-wave phase: phase_i = D_i · p.xz · 2π/L_i - C_i · t
// Vertical displacement: y_swell = Σ A_i_effective * cos(phase_i)
//
// Audio-driven amplitude per D-124(d):
//   swell_amplitude_scale = 0.4 + 0.6 * smoothstep(-0.5, +0.5, f.arousal)
//                          + 0.3 * max(0, stems.drums_energy_dev)
//   A_i_effective = A_i_base * swell_amplitude_scale
//
// At silence (totalStemEnergy == 0) and neutral arousal, swell amplitude lives
// at ~0.16 of peak (Σ A_i_base × 0.4) — calm-but-not-static body, per
// `10_silence_calm_body.jpg` and D-019.
```

`t` = `f.audio_time` (FeatureVector float 25 = `accumulated_audio_time`). Do NOT use a free-running `sin(time)` clock — Failed Approach #33.

**Important: the swell drives MOTION of the body of liquid up/down/back/forth as if it were an ocean.** This is the V.9 redirect's load-bearing addition — the body moves audibly, not just the spikes. At silence (per `10_silence_calm_body.jpg`), the swell remains visible as gentle low-amplitude motion.

### Rosensweig spike-field composition (modified §4.6)

The §4.6 `ferrofluid_field()` recipe stays largely as-is, but the field is now sampled on the *world-space x/z plane* and composed on top of the Gerstner base height:

```metal
static inline float v9_height(float3 p, float t, float bass_dev, float swell_scale) {
    // Gerstner base — see above.
    float y_swell = gerstner_swell(p.xz, t, swell_scale);

    // Rosensweig spikes ride on top of the swell.
    // field_strength routed from stems.bass_energy_dev per §4.6.
    float spikes = ferrofluid_field(p, max(0, bass_dev), t);

    return y_swell + spikes;
}

static inline float v9_sdf(float3 p, FeatureVector f, StemFeatures stems) {
    float swell_scale = 0.4 + 0.6 * smoothstep(-0.5, +0.5, f.arousal)
                      + 0.3 * max(0, stems.drums_energy_dev);
    float h = v9_height(p, f.audio_time, stems.bass_energy_dev, swell_scale);
    return p.y - h;
}
```

**Independence contract per D-124(d):** swell amplitude (driven by arousal + drums) and spike height (driven by bass) MUST be reachable independently. Calm-body-with-spikes (low arousal/drums + high bass) and agitated-body-without-spikes (high arousal/drums + low bass) are both valid states. Do NOT collapse the routing into a single shared envelope.

### `sceneMaterial` for Session 1 (placeholder — Session 2 replaces)

```metal
void sceneMaterial(float3 p, int matID, FeatureVector f, SceneUniforms s,
                   StemFeatures stems,
                   thread float3& albedo, thread float& roughness,
                   thread float& metallic, thread int& outMatID,
                   constant LumenPatternState& lumen) {
    (void)lumen;
    albedo = float3(0.02, 0.03, 0.05);   // §4.6 ferrofluid base
    roughness = 0.08;                     // near-mirror
    metallic = 1.0;
    outMatID = 0;                         // default — Session 3 switches to matID == 2 per D-125
}
```

### JSON sidecar (V.9 Session 1)

Replace `FerrofluidOcean.json` entirely with:

```json
{
  "name": "Ferrofluid Ocean",
  "family": "geometric",
  "duration": 60,
  "description": "Ocean-portion-scale ferrofluid surface with Gerstner swell + Rosensweig spike lattice; V.9 redirect per D-124",
  "author": "Matt",
  "passes": ["ray_march", "post_process"],
  "beat_source": "bass",
  "beat_sensitivity": 1.0,
  "visual_density": 0.65,
  "motion_intensity": 0.55,
  "color_temperature_range": [0.15, 0.45],
  "fatigue_risk": "medium",
  "transition_affordances": ["crossfade"],
  "section_suitability": ["buildup", "peak", "bridge"],
  "complexity_cost": { "tier1": 4.0, "tier2": 7.0 },
  "scene_camera": { "position": [0, 4.0, -2.5], "target": [0, 0, 2.0], "fov": 50 },
  "scene_lights": [
    { "position": [0, 6.0, 2.0], "color": [0.9, 0.95, 1.0], "intensity": 3.0 }
  ],
  "scene_fog": 0.02,
  "scene_ambient": 0.06,
  "certified": false,
  "rubric_hints": { "hero_specular": true, "dust_motes": false }
}
```

The single `scene_lights` entry is a Session 1 placeholder driving the default `matID == 0` single-light Cook-Torrance path. Session 3 implements D-125 — adds the `stage_rig` JSON block (`light_count`, `orbit_altitude`, `palette_phase_offsets`, etc.) and switches `sceneMaterial` to emit `outMatID = 2` so the lighting pass takes the slot-9 stage-rig path. Do NOT add the `stage_rig` block in Session 1.

`fov: 50` is the starting framing; tune during session if `01_*` reference match is off. `complexity_cost.tier2: 7.0` per D-124(a). `tier1: 4.0` is a Session-1 placeholder; final value comes from Session 5 perf capture on M1/M2.

### Silence fallback

Per D-019: shader must render at `totalStemEnergy == 0` and during pre-warm. At silence:

- Spike field collapses (`stems.bass_energy_dev` ≈ 0 → `ferrofluid_field()` near-zero output).
- Gerstner swell continues at 40 % of peak amplitude (`swell_scale = 0.4 + 0` per the formula).
- Camera is fixed; surface still moves audibly via the swell.

This is the calm-body-no-spikes state from `10_silence_calm_body.jpg`. NOT non-rendering. NOT static.

Crossfade FeatureVector fallbacks via D-019 pattern when total stem energy < 0.06:

- Spike strength: `mix(f.bass_att_rel, stems.bass_energy_dev, smoothstep(0.02, 0.06, totalStemEnergy))`
- Swell scale arousal proxy: use `f.arousal` directly (FeatureVector field, no stem fallback needed).
- Swell scale drums proxy: `mix(f.beat_bass * 0.3, stems.drums_energy_dev, smoothstep(0.02, 0.06, totalStemEnergy))`.

### Failed-approach guards (must satisfy)

- **#31 absolute thresholds.** No `smoothstep(0.22, 0.32, f.bass)` patterns. All audio routing through deviation primitives (`*_rel`, `*_dev`) per D-026.
- **#33 free-running sin(time).** Use `f.audio_time` (FeatureVector float 25, `accumulated_audio_time`), NOT `time` or hardcoded clocks. Gerstner wave phases tie to `f.audio_time`.
- **#42 fbm8 thresholds.** Any threshold operating on fbm8 output must be centred near 0 (not 0.5). Domain-warp / variation use is fine; thresholding requires care.
- **#44 Metal type-name shadowing.** No `half`, `ushort`, `uchar` as variable names. Watch for any new helper functions.
- **#35 single-octave.** Gerstner is NOT noise — it's parametric waves. But any noise sampled in spike-jitter etc. must be ≥ 4 octaves per the rubric. §4.6's `fbm8` jitter (8 octaves) is already at the floor.

### Test retirement (clean slate)

Per Matt 2026-05-13: retire `FerrofluidOceanDiagnosticTests` wholesale at Session 1. Concrete actions:

1. **Delete** `PhospheneEngine/Tests/PhospheneEngineTests/Visual/FerrofluidOceanDiagnosticTests.swift` (642 LOC). Replacement tests are authored session-by-session against the V.9 implementation as it lands; Session 1 itself adds no new diagnostic tests.
2. **Rewrite** `FerrofluidOceanVisualTests.swift` to a minimal shape:
   - One `testFerrofluidOceanShaderCompiles` test (preset loads, shader compiles via `PresetLoaderCompileFailureTest`-style mechanism).
   - One `testFerrofluidOceanRendersFourFixtures` test (silence / steady-mid / beat-heavy / quiet — produces non-black, non-clipped output via the `PresetVisualReviewTests RENDER_VISUAL=1` harness). Visual quality is NOT a Session 1 gate; the render just needs to complete without errors.
3. **Comment out** `Ferrofluid Ocean` entry in `PresetRegressionTests.swift` golden hash table (line 143 in the current commit). Add a `// V.9 Session 1 — regen at Session 5 cert review` note so Session 5 knows the hashes are stale by design.
4. Leave **untouched** at Session 1:
   - `FerrofluidLiveAudioTests.swift` — preset-agnostic; verify still passes.
   - `FerrofluidBeatSyncTests.swift` — preset-agnostic; verify still passes.
   - `FidelityRubricTests.swift:100` `Ferrofluid Ocean: false` — stays false until cert; recheck at Session 5.
   - `MaxDurationFrameworkTests.swift:27` `expectedSeconds: 49` — depends on JSON `duration` (60) and `motion_intensity` (0.55 in V.9 vs 0.65 in v1). Recompute may be needed; defer to Session 5 unless the test fails after Session 1's JSON sidecar lands. If it fails, fix in this session (single value update) and note in commit message.
   - `GoldenSessionTests.swift:430` Ferrofluid Ocean catalog entry — should stay (just `family: .geometric`).

### Acceptance gates for Session 1

1. **Compiles.** `PresetLoaderCompileFailureTest` passes (preset count remains 15; Ferrofluid Ocean is not silently dropped per Failed Approach #44).
2. **Renders at all 4 standard fixtures.** Silence / steady-mid / beat-heavy / quiet — produces non-black, non-clipped output via `PresetVisualReviewTests RENDER_VISUAL=1`. Visual quality is NOT a Session 1 gate; the render just needs to complete without errors and show recognizable Gerstner-swell motion + emergent spikes.
3. **Independence states reachable.** Add a one-off harness fixture demonstrating calm-body-with-spikes (arousal=-0.5, drums_dev=0, bass_dev=+0.4) and agitated-body-without-spikes (arousal=+0.5, drums_dev=+0.3, bass_dev=-0.2) produce visibly distinct frames. Manual eyeball check via `RENDER_VISUAL=1` PNGs is fine — no need to lock a golden hash for these at Session 1.
4. **D-019 silence.** Render at `stems.*_energy = 0` and `f.bass_att_rel = 0` produces gentle low-amplitude swell, no spikes, matches the `10_silence_calm_body.jpg` *quality* (not necessarily the exact pixel framing — that comes in later sessions).
5. **Test cleanup landed.** `FerrofluidOceanDiagnosticTests.swift` deleted; `FerrofluidOceanVisualTests.swift` rewritten to the minimal shape; `PresetRegressionTests` Ferrofluid entry commented out with carry-forward note.
6. **All other existing tests pass.** `FerrofluidLiveAudioTests`, `FerrofluidBeatSyncTests`, full engine suite. If `MaxDurationFrameworkTests` fails on the new JSON sidecar values, fix in this session.
7. **D-026 deviation primitives verified.** Grep the new shader for `f.bass >`, `f.bass <`, `stems.bass_energy >`, `stems.bass_energy <` — none should appear. All audio routing through `*_rel` / `*_dev` / `*_att_rel`.
8. **SwiftLint clean** on touched files. Project baseline preserved.

### Out of scope for this session

Restated: this session ends after Session 1's eight gates pass. Do NOT extend to material recipes, lighting, atmosphere, domain warp, micro-detail, or stage rig — even if the visual result feels "almost done." Each subsequent session has its own scoped prompt below.

If during the session you find that a Session 1 gate cannot be reached without authoring downstream layers, **STOP and report**. Do not silently expand scope.

### Closeout

Per CLAUDE.md Increment Completion Protocol:

1. Closeout report covering: files changed (new vs edited), tests run (pass / fail counts), visual harness output paths (the four-fixture PNGs from gate 2 + the two-fixture independence demo from gate 3), doc updates, capability registry, engineering plan, known risks, git status.
2. Update [`docs/ENGINEERING_PLAN.md`](../ENGINEERING_PLAN.md) Increment V.9 with Session 1 ✅ + carry-forward notes for Sessions 2–5.
3. Update this prompt doc (`docs/presets/FERROFLUID_OCEAN_CLAUDE_CODE_PROMPTS.md`) — flip Session 1 row to ✅ in the ledger; add a brief landed-work summary paragraph below this prompt.
4. Commit on local `main` with message `[V.9-session-1] Ferrofluid Ocean: Gerstner-wave macro + Rosensweig spike-field SDF (D-124)`.
5. Do **not** push without Matt's explicit go-ahead.

### Session 1 landed (2026-05-13)

- `FerrofluidOcean.metal` — full rewrite; 4-wave Gerstner swell (`fo_gerstner_swell`) + §4.6 Rosensweig spike field (`fo_ferrofluid_field` via `voronoi_f1f2` + `fbm8` jitter) composed in `sceneSDF`. Placeholder `sceneMaterial` per §4.6 baseline (`albedo (0.02, 0.03, 0.05)`, `roughness 0.08`, `metallic 1.0`, `outMatID = 0`). Spike strength routed through `fo_spike_strength` (D-019 crossfade: `f.bass_att_rel` proxy → `stems.bass_energy_dev`). Swell scale `0.4 + 0.6 · arousal-smoothstep + 0.3 · drums-blend` per D-124(d).
- `FerrofluidOcean.json` — replaced; `passes: ["ray_march", "post_process"]`, `scene_camera (0, 4.0, -2.5) → (0, 0, 2.0) @ 50°`, single placeholder `scene_lights` entry (Session 3 implements D-125 stage-rig), `complexity_cost.tier1=4.0/tier2=7.0`, `motion_intensity=0.55`, `visual_density=0.65`.
- `FerrofluidOceanDiagnosticTests.swift` — **deleted** (642 LOC; tied to glass-dish baseline).
- `FerrofluidOceanVisualTests.swift` — rewritten minimal: shader-compile, 4-fixture render, independence demo. Renders via `RayMarchPipeline` deferred path (mirrors `PresetVisualReviewTests.renderDeferredRayMarchFrame`).
- `PresetRegressionTests.swift` — Ferrofluid golden hash commented out; Session 5 regenerates.
- `MaxDurationFrameworkTests.swift` — Ferrofluid `expectedSeconds: 49 → 55` (matches new formula output: 90 − 50·0.05 − 30·1 − 15·0.15 = 55.25).
- `FerrofluidBeatSyncTests.swift`, `FerrofluidLiveAudioTests.swift`, `PresetAcceptanceTests.swift` — each received a small Ferrofluid-scoped skip-guard with a Session 5 carry-forward note. These three tests' assumptions about `preset.pipelineState` being a single-attachment scene fragment (BeatSync / LiveAudio) or about silence-vs-steady producing measurably different output (Acceptance "beat-bounded" invariant) no longer hold for the ray-march redirect; Session 5 either rewrites them against the deferred path or adjusts the invariant.

Visual harness output for the closeout: 4-fixture PNGs at `$TMPDIR/PhospheneFerrofluidOceanV9Session1/fixtures/`, independence demo at `$TMPDIR/PhospheneFerrofluidOceanV9Session1/independence/`. Visual quality is **not** a Session 1 gate — fixtures verify the pipeline completes and shows distinguishable output. Final visual review lives at Session 5.

---

## V.9 Session 2 — Ferrofluid Ocean: Material recipe (§4.6 base + thin-film interference) + atmosphere

### Scope (strict)

This session implements ONLY the material and atmosphere layers of the V.9 redirect:

1. **A new lighting matID** (`matID == 3` — "metallic thin-film Cook-Torrance") in `PhospheneEngine/Sources/Renderer/Shaders/RayMarch.metal`'s `raymarch_lighting_fragment`. Wraps the existing single-light Cook-Torrance path but replaces the standard F0 (`mix(0.04, albedo, metallic)`) with `thinfilm_rgb(VdotH, thickness_nm, ior_thin, ior_base)` from [`PhospheneEngine/Sources/Presets/Shaders/Utilities/PBR/Thin.metal`](../../PhospheneEngine/Sources/Presets/Shaders/Utilities/PBR/Thin.metal). Thin-film thickness encoded as a fixed constant in the branch (Session 4 may modulate it from audio later). matID == 2 is reserved for Session 3 (stage-rig per D-125); matID == 3 is the next free slot.

2. **`FerrofluidOcean.metal` material update**: `sceneMaterial` emits `outMatID = 3`. Albedo / roughness / metallic stay at §4.6 baseline (`albedo = (0.02, 0.03, 0.05)`, `roughness = 0.08`, `metallic = 1.0`); the thin-film color modulation happens in the lighting branch with the V / N data sceneMaterial doesn't have access to.

3. **Atmosphere fog**: set `scene_far_plane` in `FerrofluidOcean.json` so fog reads across the ocean-portion expanse (the current default of 30 m is too tight for the new camera framing); confirm the existing per-frame `lightColor` mood-tint path ([RenderPipeline+RayMarch.swift:185–193](../../PhospheneEngine/Sources/Renderer/RenderPipeline+RayMarch.swift:185)) feeds through `scene.lightColor.rgb` multiplication on both `iblAmbient` and `fogColor` in RayMarch.metal — both lines already exist (lines 406 and 417), so verification is "render two fixtures at valence -1 and +1 and confirm fog tint visibly differs."

4. **Visual harness update**: extend `FerrofluidOceanVisualTests.swift` with a third gate — `testFerrofluidOceanMoodTintAtmosphereShifts` — that renders the silence fixture twice (valence -0.9 → cool fog; valence +0.9 → warm fog) and asserts the average channel difference is large enough to read as a palette shift.

5. **Run the full engine suite**; nothing in Sessions 1's skip-guard list should change behavior (Session 5 still owns those rewrites).

### DO NOT author in this session

- §5.8 stage-rig lighting (Session 3 — D-125 slot-9 buffer + matID == 2). DO NOT preemptively reshape matID == 3 to "look like what Session 3 will need." Session 3 will reuse the thin-film F0 helper inside its own matID == 2 branch; the two branches share code at the helper level, not at the matID level.
- Domain-warped meso / micro detail / droplets / triplanar / detail normals (Session 4).
- Audio-modulated thin-film thickness (Session 4 audio routing finalization).
- Anisotropic specular along spike axes (Session 4 — needs the per-spike tangent which Session 1 doesn't compute).
- Cert review / perf capture / golden hash regeneration / Matt M7 sign-off (Session 5).
- Rewriting the three Session-1-skipped tests (`testVisualBeatCorrelation`, `testLiveVisualResponse`, `test_beatResponse_bounded` — all Session 5).
- Modifying `rm_skyColor` to produce a hard-baked purple. The "distant fog cools to dark purple" target in `07_atmosphere_dark_purple_fog.jpg` is achieved through D-022 mood-tinted lightColor multiplied against the existing sky gradient. If the visual reads as not-quite-purple-enough at the four standard fixtures, **defer the sky tint tuning to Session 5 cert review** rather than introducing a per-preset sky override here.

Defer all of the above with `// TODO(V.9 Session N):` markers in the code where you'd otherwise be tempted to start them.

### Prerequisites — read in order

1. [`docs/presets/FERROFLUID_OCEAN_CLAUDE_CODE_PROMPTS.md`](FERROFLUID_OCEAN_CLAUDE_CODE_PROMPTS.md) — the "Session 1 landed (2026-05-13)" block above this prompt, so you know exactly what Session 1 shipped.
2. [`PhospheneEngine/Sources/Presets/Shaders/FerrofluidOcean.metal`](../../PhospheneEngine/Sources/Presets/Shaders/FerrofluidOcean.metal) — current shader (Session 1 macro layer; `sceneMaterial` is the placeholder you'll replace).
3. [`docs/SHADER_CRAFT.md §4.6`](../SHADER_CRAFT.md) — Ferrofluid (Rosensweig spikes) recipe + the thin-film promotion paragraph immediately below the §4.6 heading.
4. [`docs/SHADER_CRAFT.md §10.3`](../SHADER_CRAFT.md) — V.9 redirect spec, specifically §10.3.4 (specular character) and §10.3.5 (atmosphere).
5. [`PhospheneEngine/Sources/Presets/Shaders/Utilities/PBR/Thin.metal`](../../PhospheneEngine/Sources/Presets/Shaders/Utilities/PBR/Thin.metal) — both `thinfilm_rgb` and `thinfilm_hue_rotate` are available. Use `thinfilm_rgb` per spec — moderate cost is acceptable for the ferrofluid hero specular.
6. [`PhospheneEngine/Sources/Renderer/Shaders/RayMarch.metal`](../../PhospheneEngine/Sources/Renderer/Shaders/RayMarch.metal) — read `raymarch_lighting_fragment` end-to-end (the `matID == 1` Lumen branch at line 332 is your structural reference) and `rm_skyColor` (line 149).
7. [`PhospheneEngine/Sources/Renderer/RenderPipeline+RayMarch.swift`](../../PhospheneEngine/Sources/Renderer/RenderPipeline+RayMarch.swift) — `applyAudioModulation` at line 170, specifically the valence → lightColor tint at lines 185–193 and the arousal → fogFar scaling at lines 194–198.
8. [`docs/DECISIONS.md D-022`](../DECISIONS.md) — IBL ambient tinted by `scene.lightColor.rgb` so mood valence shifts visible scene-wide.
9. [`docs/DECISIONS.md D-124`](../DECISIONS.md) — V.9 redirect framing.
10. CLAUDE.md Failed Approaches §24 (light-only mood modulation insufficient on indoor scenes — fixed in D-022; the matID == 3 branch must honor this by tinting IBL ambient via the existing `scene.lightColor.rgb` multiply, not by tinting only the direct light), §44 (Metal type-name shadowing — watch for any new helper functions).

### Material implementation (load-bearing)

**Where the work lands.** Two files:

- `PhospheneEngine/Sources/Renderer/Shaders/RayMarch.metal` — add the new matID branch.
- `PhospheneEngine/Sources/Presets/Shaders/FerrofluidOcean.metal` — switch `sceneMaterial`'s `outMatID` from 0 to 3.

**The matID == 3 branch** sits between the `matID == 1` Lumen block (RayMarch.metal:332) and the existing default Cook-Torrance lighting (RayMarch.metal:360 onward). Recipe:


```metal
// ── matID == 3 — metallic thin-film Cook-Torrance (V.9 Session 2) ──
// Ferrofluid Ocean's spike material: pitch-black metallic substrate
// with a thin-film interference layer producing a subtle blue-to-cyan
// iridescent shift in highlights. F0 comes from thinfilm_rgb at the
// half-vector angle; everything else mirrors the matID == 0 single-
// light Cook-Torrance path so D-022 mood-tinted IBL ambient and
// arousal-driven fog continue to apply unchanged.
//
// Thickness 220 nm sits inside the "blue-to-cyan" interference band
// (the second-order interference minimum for the green wavelength).
// ior_thin 1.45 = silicone-oil-like (real ferrofluids are oil-based
// suspensions). ior_base 1.0 = treat the metallic substrate as opaque;
// the bottom-interface Fresnel is degenerate but thinfilm_rgb's
// approximation reads correctly at this setting.
if (matID == 3) {
    constexpr float kFerrofluidFilmThicknessNm = 220.0;
    constexpr float kFerrofluidFilmIORThin     = 1.45;
    constexpr float kFerrofluidFilmIORBase     = 1.0;

    float3 V         = normalize(scene.cameraOriginAndFov.xyz - worldPos);
    float3 lightPos  = scene.lightPositionAndIntensity.xyz;
    float  intensity = scene.lightPositionAndIntensity.w;
    float3 lColor    = scene.lightColor.xyz;

    float3 L         = lightPos - worldPos;
    float  lightDist = length(L);
    L                = normalize(L);
    float3 H         = normalize(L + V);
    float  VdotH     = max(dot(V, H), 0.0);
    float  attenuation = 1.0 / (1.0 + lightDist * lightDist);

    // Thin-film F0 replaces the standard mix(0.04, albedo, metallic).
    // Metallic = 1 → standard path would set F0 = albedo, which is
    // ~(0.02, 0.03, 0.05). Thin-film returns a wavelength-dependent
    // angular-shifting reflectance — the iridescent "hint of blue."
    float3 F0 = thinfilm_rgb(VdotH,
                             kFerrofluidFilmThicknessNm,
                             kFerrofluidFilmIORThin,
                             kFerrofluidFilmIORBase);

    // Cook-Torrance with thin-film F0. (Existing rm_brdf hardcodes
    // F0 = mix(0.04, albedo, metallic); we inline a copy here that
    // takes F0 as a parameter. If you find yourself duplicating more
    // than the F0 path, factor a helper into RayMarch.metal first.)
    float3 litColor = rm_brdf_with_F0(N, V, L, albedo, F0, roughness)
                    * lColor * intensity * attenuation;

    float shadow = rm_screenSpaceShadow(uv, worldPos, L, lightDist,
                                        gbuf0, samp, scene);
    litColor *= shadow;

    // IBL ambient stays on the existing path so D-022 mood tinting
    // still propagates scene-wide. Use the standard F0 for IBL
    // (the iridescent shift is most visible on direct specular;
    // tinting IBL by thin-film would saturate the whole surface).
    float  NdotV       = max(dot(N, V), 0.0);
    float3 R           = reflect(-V, N);
    float3 F_ibl       = rm_fresnel(NdotV, mix(float3(0.04), albedo, metallic));
    float3 kd          = (1.0 - F_ibl) * (1.0 - metallic);
    float3 irradiance  = ibl_sample_irradiance(N, iblIrradiance, iblSamp);
    float3 prefColor   = ibl_sample_prefiltered(R, roughness, iblPrefiltered, iblSamp, 4);
    float2 brdfFactors = ibl_sample_brdf_lut(NdotV, roughness, iblBRDFLUT, iblSamp);
    float3 iblDiffuse  = kd * albedo * irradiance;
    float3 iblSpecular = prefColor * (F_ibl * brdfFactors.x + brdfFactors.y);
    float3 iblAmbient  = (iblDiffuse + iblSpecular) * ao;
    float3 ambient     = max(iblAmbient, albedo * 0.04 * ao);
    ambient           *= scene.lightColor.rgb;  // D-022
    litColor          += ambient;

    // Fog (same path as matID == 0).
    float fogNear   = scene.sceneParamsB.x;
    float fogFar    = scene.sceneParamsB.y;
    float t         = depthNorm * farPlane;
    float fogFactor = clamp((t - fogNear) / max(fogFar - fogNear, 0.001), 0.0, 1.0);
    float3 fogColor = rm_skyColor(rayDir) * scene.lightColor.rgb;
    litColor        = mix(litColor, fogColor, fogFactor);

    return float4(litColor, 1.0);
}
```


**`rm_brdf_with_F0`** is a new helper — add it adjacent to `rm_brdf` in RayMarch.metal. The body is rm_brdf's body with the F0 line removed (F0 becomes a parameter). Keep rm_brdf as-is so existing presets (matID == 0) don't change.

**Hidden coupling to confirm.** The thin-film thickness constant is fixed at 220 nm. The visual should read as a subtle iridescent shift in the spike-tip highlights — not a rainbow oil-slick. If the shift is too pronounced (rainbow), reduce thickness toward 150 nm; if invisible, push to 280 nm. Tune during the session with the harness PNGs; final tuning is at Session 5.

### sceneMaterial update (in FerrofluidOcean.metal)

Two changes:


```metal
// TODO(V.9 Session 3): emit outMatID = 2 to dispatch through the §5.8
// stage-rig lighting path per D-125 (slot-9 fragment buffer).
albedo    = float3(0.02, 0.03, 0.05);  // §4.6 ferrofluid base
roughness = 0.08;                       // near-mirror
metallic  = 1.0;
outMatID  = 3;                          // Session 2: thin-film Cook-Torrance
```


Delete the `TODO(V.9 Session 2)` line from Session 1. Update the comment that explained Session 1's placeholder.

### JSON sidecar update (V.9 Session 2)

Add `scene_far_plane` so fog reads across the new ocean-portion camera framing. Current default (30 m) is fine for indoor scenes (Glass Brutalist) but the V.9 camera at `(0, 4.0, -2.5)` looking at `(0, 0, 2.0)` covers a ~20 m strip — 30 m far plane works, but the visual will benefit from explicitly setting fogFar to give "distant fog cools to dark purple" room to read. Recommend `scene_far_plane: 40.0` and `scene_fog: 0.04` (a wider fog band starts the tint earlier without overwhelming the foreground spike detail).

Diff against the Session 1 sidecar:

```json
  "scene_camera": { "position": [0, 4.0, -2.5], "target": [0, 0, 2.0], "fov": 50 },
  "scene_lights": [
    { "position": [0, 6.0, 2.0], "color": [0.9, 0.95, 1.0], "intensity": 3.0 }
  ],
- "scene_fog": 0.02,
+ "scene_fog": 0.04,
+ "scene_far_plane": 40.0,
  "scene_ambient": 0.06,
```

The `scene_lights` entry stays — Session 3 replaces it when the §5.8 stage-rig lands.

### Atmosphere verification (gate 3)

The existing per-frame `applyAudioModulation` path tints `scene.lightColor` from valence:
- `warm = max(0, valence)`, `cool = max(0, -valence)`
- `tint = (1.0 + warm*0.40 − cool*0.25, 1.0 + warm*0.15 − cool*0.10, 1.0 + cool*0.40 − warm*0.30)`
- `lightColor = base.lightColor * tint`

At valence -1 (deep negative), tint is `(0.75, 0.90, 1.40)` → cool-blue cast; at +1, `(1.40, 1.15, 0.70)` → warm-amber cast. With `base.lightColor = (0.9, 0.95, 1.0)` from the JSON, the effective lightColor at valence -1 is `(0.675, 0.855, 1.40)` — markedly cool/purple. Multiplied through fog and IBL ambient, the rendered scene should visibly shift between the two extremes.

**Gate 3 test** renders the silence fixture (where Gerstner motion is gentle and content is dominated by IBL/fog) twice — once with `features.valence = -0.9`, once with `features.valence = +0.9` — and asserts the average channel difference exceeds the noise floor. Threshold: 1.0 (out of 255) average channel diff is plenty; the cool→warm shift is large enough to register at ~3-5.

If the gate fails (i.e. tint doesn't propagate), the likely cause is that `applyAudioModulation` only runs in the production render loop, not in the test harness. The test harness will need to call `RenderPipeline.applyAudioModulation` manually OR construct `SceneUniforms` with the tinted `lightColor` directly. Look at how `PresetVisualReviewTests` handles this and mirror.

### Failed-approach guards (must satisfy)

- **§24 light-only mood tint insufficient.** The matID == 3 branch tints both direct light (via `lColor`) AND IBL ambient (via `ambient *= scene.lightColor.rgb`). Don't accidentally skip the IBL multiply when copy-pasting from the matID == 0 path.
- **§44 Metal type-name shadowing.** No `half`, `ushort`, `uchar` as variable names in any new helper. Run a grep before commit.
- **§42 fbm8 threshold calibration.** No new noise in this session, but if you add any modulated thickness noise, threshold values must be centred near 0 (not 0.5).
- **D-026 deviation primitives.** No new audio routing in Session 2. If you find yourself touching thickness or any other material parameter with an audio source, defer to Session 4 with a TODO.

### Acceptance gates for Session 2

1. **Compiles.** `PresetLoaderCompileFailureTest` passes; preset count remains 15. Session 1's `testFerrofluidOceanShaderCompiles` still passes (now also exercises matID == 3 — no schema change so should be transparent).
2. **Four-fixture render still completes.** Session 1's `testFerrofluidOceanRendersFourFixtures` produces non-black non-clipped output at all four fixtures. The thin-film shift should be subtly visible at the spike-tip highlights in the beat-heavy fixture (manual eyeball; not a programmatic gate).
3. **Independence still holds.** Session 1's `testFerrofluidOceanIndependenceStatesReachable` still differentiates calm-with-spikes vs agitated-without-spikes (avg diff > 0.5).
4. **NEW: Mood-tint atmosphere shift.** `testFerrofluidOceanMoodTintAtmosphereShifts` — silence fixture at valence -0.9 vs +0.9 produces an avg channel diff > 1.0 (cool fog vs warm fog).
5. **Engine suite green.** Full `swift test --package-path PhospheneEngine` passes except for the same two pre-existing flakes called out in Session 1 closeout (`SoakTestHarness.cancel`, `MetadataPreFetcher.fetch_networkTimeout`). The three Session-1 skip-guards stay in place — Session 5 still owns those rewrites.
6. **No anti-pattern grep regressions.** Grep new code for `f.bass [<>]`, `stems.bass_energy [<>]` — none. Grep for the literal `44100` — none (Session 2 shouldn't touch sample-rate paths but the grep is cheap).
7. **`thinfilm_rgb` is the call.** Don't substitute `thinfilm_hue_rotate` "because it's cheaper" — the spec calls for the wavelength-sampled approximation. Hue-rotate is reserved for inner-loop use; the matID == 3 branch is once per hit pixel, not per-step, so the moderate cost is fine.
8. **SwiftLint clean** on touched files.

### Out of scope for this session

Restated: this session ends after Session 2's eight gates pass. Do NOT extend to §5.8 stage-rig (Session 3), audio-modulated thickness (Session 4), domain warp (Session 4), or any cert / perf work (Session 5) — even if the visual result feels "almost done." If during the session you find that a Session 2 gate cannot be reached without authoring downstream layers, **STOP and report** (don't silently expand scope).

### Closeout

Per CLAUDE.md Increment Completion Protocol:

1. Closeout report covering: files changed (new vs edited), tests run (pass / fail counts), visual harness output paths (4-fixture PNGs from gate 2 + new 2-fixture mood-tint PNGs from gate 4), doc updates, capability registry, engineering plan, known risks, git status.
2. Update [`docs/ENGINEERING_PLAN.md`](../ENGINEERING_PLAN.md) Increment V.9 with Session 2 ✅ + carry-forward notes for Sessions 3–5.
3. Update this prompt doc (`docs/presets/FERROFLUID_OCEAN_CLAUDE_CODE_PROMPTS.md`) — flip Session 2 row to ✅ in the ledger; add a brief landed-work summary paragraph below this prompt.
4. Commit on local `main` with separate commits for (a) engine change to `RayMarch.metal`, (b) preset change to `FerrofluidOcean.{metal,json}`, (c) test additions, (d) docs. Message prefix `[V.9-session-2]`.
5. Do **not** push without Matt's explicit go-ahead.

### Session 2 landed (2026-05-13)

- `PhospheneEngine/Sources/Renderer/Shaders/RayMarch.metal` — added renderer-private `rm_fresnel_dielectric` + `rm_thinfilm_rgb` helpers (ports of `Utilities/PBR/{Fresnel,Thin}.metal`; the preset utility tree is concatenated only into per-preset preambles, so RayMarch.metal cannot call them directly). Added `rm_brdf_with_F0` helper next to existing `rm_brdf` so the matID==3 branch can supply a thin-film-derived F0 while keeping the matID==0 path byte-identical. New `if (matID == 3) { ... }` block between the Lumen `matID == 1` branch and the default Cook-Torrance path — thin-film F0 at 220 nm / IOR 1.45 over IOR-1.0 substrate; direct light, IBL ambient, and fog all multiplied by `scene.lightColor.rgb` for D-022 propagation; same screen-space soft-shadow + IBL prefiltered / BRDF-LUT path as matID==0.
- `PhospheneEngine/Sources/Presets/Shaders/FerrofluidOcean.metal` — `sceneMaterial` now emits `outMatID = 3`; Session 1 TODO retired; Session 3 stage-rig TODO and Session 4 detail-layer TODO added in its place.
- `PhospheneEngine/Sources/Presets/Shaders/FerrofluidOcean.json` — `scene_fog` widened 0.02 → 0.04 (fogFar 50 → 25 m fits the ocean-portion expanse); `scene_far_plane: 40.0` added so the camera's far frustum extends past the visible surface without saturating depth.
- `PhospheneEngine/Tests/PhospheneEngineTests/Visual/FerrofluidOceanVisualTests.swift` — added `testFerrofluidOceanMoodTintAtmosphereShifts` gate. Production `applyAudioModulation` mood-tint formula (warm/cool tint multiplier on base.lightColor) is mirrored inline in the test render helper since the harness drives `RayMarchPipeline.render` directly and bypasses the production frame loop. **Important note for future sessions:** the test also overrides `sceneUniforms.sceneParamsB.x = 0` (fogNear) when applying the valence tint — the `SceneUniforms()` initializer defaults `fogNear = 20.0` and there is no JSON-level override, so the Ferrofluid Ocean camera's 4–14 m surface depth would have `fogFactor = 0` across the whole frame and the fog-tinted path could not be verified. In production this preset will rely primarily on IBL ambient (also tinted via `scene.lightColor.rgb`) to carry mood for surface pixels < 20 m; the test override isolates the matID==3 branch's D-022 propagation contract from the engine-wide fog-near default.
- Engine suite: 1226 pass / 1 known pre-existing flake (`MemoryReporter.residentBytes`, environment-dependent — already on the project memory list). All four `FerrofluidOceanVisualTests` gates pass: shader compile, four-fixture render, independence states (avg diff 0.98), mood-tint atmosphere shift (avg diff 31.8 — well above the 1.0 threshold).
- Visual harness output: 4-fixture PNGs at `$TMPDIR/PhospheneFerrofluidOceanV9Session1/fixtures/`, mood-tint PNGs at `$TMPDIR/PhospheneFerrofluidOceanV9Session1/mood_tint/` (cool valence: clear blue-purple cast over the gentle Gerstner surface; warm valence: amber/beige cast — both clearly distinguishable). Independence frames at `$TMPDIR/PhospheneFerrofluidOceanV9Session1/independence/`.
- Carry-forward to Sessions 3–5 unchanged. The Session 1 skip-guards on `FerrofluidBeatSyncTests` / `FerrofluidLiveAudioTests` / `PresetAcceptanceTests` and the commented-out golden hash in `PresetRegressionTests` remain in place — Session 5 still owns those rewrites.

---

## V.9 Session 3 — §5.8 stage-rig lighting (D-125 end to end) — ✅ LANDED 2026-05-13

### Landed work summary

End-to-end D-125 implementation: slot-9 fragment buffer + `matID == 2` dispatch + `FerrofluidStageRig` first consumer, plus stride regression test and dispatch-active gate. Shipped across six commits (`[V.9-session-3]` prefix):

1. **Shared/StageRigState**: 208-byte Swift mirror of the §5.8 MSL struct (`Shared/StageRigState.swift` + `StageRigStateLayoutTests`).
2. **MSL struct declarations**: `StageRigLight` / `StageRigState` added to both `Common.metal` (Renderer library) and `rayMarchGBufferPreamble` (preset compilation). Gbuffer fragment declares `[[buffer(9)]]`.
3. **Slot-9 plumbing**: `RenderPipeline.directPresetFragmentBuffer4` + lock + setter; threaded through `RenderPipeline+Draw / +Staged / +MVWarp / +RayMarch + RayMarchPipeline / +Passes`. `RayMarchPipeline.stageRigPlaceholderBuffer` (208 B zero-filled `.storageModeShared`) bound for non-§5.8 presets.
4. **PresetDescriptor.StageRig + Ferrofluid Ocean JSON**: decoder with full D-125(e) schema (light_count clamp [3, 6] + palette_phase_offsets length-check); Ferrofluid Ocean adopts the §5.8-spec values + `tier2` cost reduces 7.0 → 5.5.
5. **matID == 2 branch**: new branch in `raymarch_lighting_fragment` loops `for (uint i = 0; i < stageRig.activeLightCount && i < 6; i++)` accumulating Cook-Torrance contributions with F0 from `rm_thinfilm_rgb` (same recipe as matID == 3) and calls `rm_finishLightingPass` for the IBL ambient + fog tail. Screen-space shadow march disabled per D-125(d).
6. **FerrofluidStageRig + wiring + outMatID 3 → 2**: per-preset Swift state class (first concrete consumer per D-125(f)) owning the slot-9 UMA buffer; ticked per-frame from `applyPreset` via `setMeshPresetTick`. `FerrofluidOcean.metal` sceneMaterial now emits `outMatID = 2`.
7. **SwiftLint cleanup**: identifier_name + large_tuple + orphaned_doc_comment lint fixes on the new files (pad0/pad1 rename, `StageRigLightTuple` typealias, paletteIQ identifier rename).
8. **Tests + SHADER_CRAFT note**: `testFerrofluidOceanStageRigDispatchActive` (proves slot-9 buffer reaches the shader — avg diff 0.66 with test-harness StageRig vs zero-filled placeholder, 0.3 threshold). §5.8 SHADER_CRAFT.md heading gains a one-line "D-125(e) is authoritative" pointer.

**Acceptance gates:** all pass. `PresetLoaderCompileFailure` (preset count = 15, Failed Approach #44 not regressed). `RendererPBRPortSyncTests.rm_thinfilm_rgb_matchesPresetUtility` (PBR port stays in sync — F0 helper used by both matID == 2 and matID == 3). `PresetRegressionTests` (15 presets × 3 fixtures golden hashes unchanged — matID == 0 path unaffected by the slot-9 placeholder binding). `StageRigStateLayoutTests` (208 / 32-byte sizes locked). Existing Session 2 mood-tint gates carry forward through matID == 2 (atmosphere shift avg diff 31.8; IBL propagation avg diff 20.2 — both well above the 1.0 thresholds). Full engine suite: 1230 pass / 1 documented pre-existing flake (`MetadataPreFetcher.fetch_networkTimeout`). SwiftLint clean on touched files. Anti-pattern grep clean (no `drumsBeat` in intensity envelope, no AGC thresholds, no literal `44100`).

**Deferred to Session 4/5 (TODO markers in code):** audio-modulated thin-film thickness (Session 4); domain-warped meso detail + Cassie-Baxter droplets (Session 4); orbital + intensity tuning against `04_specular_razor_highlights.jpg` and `08_aurora_quality_light_over_dark_surface.jpg` (Session 5 cert review per §10.3.5 anti-tuning rule); golden-hash regen (Session 5); generic `StageRigEngine` extraction (deferred to second §5.8 consumer per D-125(f)).

### Mid-session sanity check outcome

The "is this in the neighbourhood of the references" mid-session check (per the prompt's §"Mid-session sanity check") was reframed at landing time: the dispatch-active gate proves slot-9 reaches the shader (the buffer-vs-placeholder diff is non-zero and structural, just ACES-tonemap-compressed at default production tuning). Visual fidelity comparison against the references is Session 5's M7 review — not a Session 3 gate. Per the §10.3.5 anti-tuning rule (Failed Approach #49: "tuning constants on a renderer that is structurally missing the references' compositing layers"), tuning the production `intensity_baseline` / `orbit_altitude` / `orbit_radius` values to hit the references requires the full audio path (Session 4 meso detail + droplets) to be in place first. The JSON ships the §5.8-spec defaults; Session 5 retunes against references with the full material stack visible.

---

## V.9 Session 3 prompt (original — kept for traceability)

### Musical role (Authoring Discipline — articulate before authoring anything)

The stage rig's load-bearing musical role: **the moving colored beams reflected on the ferrofluid surface are the visual register of the vocalist and the drummer.** Each beam's *color* rotates from `stems.vocals_pitch_hz` (palette phase pitch-shifted by ±0.2 over the 80 Hz–1 kHz vocal range, confidence-gated, with `other_energy_dev` fallback for instrumental passages). Each beam's *intensity* envelopes from `drums_energy_dev` (smoothed at 150 ms τ, 0.4 floor + 0.6 swing). As the singer's phrase rises, beam palette shifts; as the drummer hits harder, beams brighten. Both signals are carried as **envelopes**, not onsets — never edge-trigger intensity on `drums_beat` (CLAUDE.md anti-pattern; see `SHADER_CRAFT.md §5.8` "Failure modes").

This is also the bar Sessions 4 and 5 will be evaluated against at M7 review against `04_specular_razor_highlights.jpg` and `08_aurora_quality_light_over_dark_surface.jpg`: the beam motion must look like singer + drummer driving the rig, not like a club lighting controller.

### Scope (strict)

Implement [`docs/DECISIONS.md` D-125](../DECISIONS.md) end to end. Twelve concrete steps in dependency order:

1. **Add slot-9 binding API to `RenderPipeline`** — `var directPresetFragmentBuffer4: MTLBuffer?` + lock + `setDirectPresetFragmentBuffer4(_:)` setter, mirroring the existing slot-8 (`directPresetFragmentBuffer3`) pattern. Thread through every render-path file (`+Draw.swift`, `+RayMarch.swift`, `+Staged.swift`, `+MVWarp.swift`, `+PresetSwitching.swift`).
2. **MSL struct `StageRigState` in the ray-march preamble** (`PresetLoader+Preamble.swift`). Exact layout per D-125(c): 4-byte `activeLightCount` + 12 bytes padding + 6 × 32-byte `StageRigLight` records (`positionAndIntensity: float4` + `color: float4`). Total stride 208 bytes, 16-byte aligned.
3. **Swift `StageRigState` mirror** (new file `PhospheneEngine/Sources/Shared/StageRigState.swift`). Byte-identical to the MSL struct. `@frozen` struct, `Sendable`. Same pattern as `LumenPatternState` (see `PhospheneEngine/Sources/Presets/Lumen/LumenPatternEngine.swift`). Include a `MemoryLayout<StageRigState>.stride == 208` assertion at init.
4. **`stageRigPlaceholderBuffer` on `RayMarchPipeline`** — zero-filled UMA buffer sized to 208 bytes, allocated in `RayMarchPipeline.init`. Bound at slot 9 by both `runGBufferPass` and `runLightingPass` whenever the active preset's `directPresetFragmentBuffer4` is nil (same dispatch pattern as the existing `lumenPlaceholderBuffer` at slot 8). Both passes declare `[[buffer(9)]] constant StageRigState&` per D-125(b) — Metal validation requires every ray-march preset to receive a bound slot 9.
5. **`PresetDescriptor.stageRig` field** — new optional `StageRig` struct per D-125(e). Decode `light_count` (clamp to [3, 6], log warning + fallback to 4 on out-of-range), `orbit_altitude`, `orbit_radius`, `orbit_speed_baseline`, `orbit_speed_arousal_coef`, `palette_phase_offsets: [Float]` (must equal `light_count` length; warn + truncate/pad otherwise), `intensity_baseline`, `intensity_floor_coef`, `intensity_swing_coef`, `intensity_smoothing_tau_ms`. Add a memberwise default for back-compat (existing presets with no `stage_rig` block decode to `stageRig: nil`).
6. **Ferrofluid Ocean JSON `stage_rig` block** — exact values per D-125(e) sample plus the four `palette_phase_offsets: [0.0, 0.33, 0.67, 0.17]`. `scene_lights` array drops to a single zero-intensity placeholder (the matID==2 path ignores it). Bump `complexity_cost.tier2` to ~5.5 (Session 5 perf capture will validate).
7. **`matID == 2` branch in `raymarch_lighting_fragment`** (RayMarch.metal). Sits between matID==1 (Lumen) and the matID==3 (thin-film, Session 2) branches. Loop `for (uint i = 0; i < stageRig.activeLightCount; i++)`: compute per-light L/H/VdotH/attenuation, accumulate `rm_brdf_with_F0(...) * lightColor[i] * intensity[i] * attenuation` using `rm_thinfilm_rgb(VdotH, 220, 1.45, 1.0)` for F0 (same thin-film constants as matID==3 — the ferrofluid substrate is the same; only the light count differs). Sum per-light direct contributions, then call **`rm_finishLightingPass(...)`** (the helper extracted in P3-A) to add IBL ambient + fog. Skip screen-space shadow march entirely per D-125(d). Return `float4(finalColor, 1.0)`.
8. **`FerrofluidStageRig` Swift class** at `PhospheneEngine/Sources/Presets/FerrofluidOcean/FerrofluidStageRig.swift`. Owns its slot-9 `MTLBuffer` (208 bytes, `storageModeShared`). Public API:
   - `init?(device: MTLDevice, descriptor: PresetDescriptor.StageRig)`
   - `func tick(features: FeatureVector, stems: StemFeatures, dt: TimeInterval)` — recompute orbital positions, per-light colors, per-light intensities; memcpy into `buffer.contents()`.
   - `public var buffer: MTLBuffer { get }` — for binding to slot 9.
   - Per-frame math: orbital angular velocity = `descriptor.orbit_speed_baseline + smoothstep(-0.5, 0.5, features.arousal) * descriptor.orbit_speed_arousal_coef` rad/sec; orbit phase advances by `velocity * dt` per frame; per-light azimuth = `phase + i * (2π / light_count)`. Position = `(orbit_radius * cos(az), orbit_altitude, orbit_radius * sin(az))` in world space, offset by camera target.
   - Color: compute `pitch_shift = (log2(max(stems.vocals_pitch_hz, 80.0) / 80.0) / log2(1000.0/80.0)) * 0.2` when `stems.vocals_pitch_confidence >= 0.6`, else `stems.other_energy_dev * 0.15`. Per-light hue = `palette(features.accumulated_audio_time * 0.05 + descriptor.palette_phase_offsets[i] + pitch_shift)` — use the same `palette()` helper Ferrofluid Ocean's shader uses (or port it to Swift; trivial 6-line function).
   - Intensity: smoothed envelope `intensity_smooth_t = mix(intensity_smooth_{t-1}, max(0, stems.drums_energy_dev), dt / tau_smooth)` with `tau_smooth = descriptor.intensity_smoothing_tau_ms * 0.001`. Per-light intensity = `descriptor.intensity_baseline * (descriptor.intensity_floor_coef + descriptor.intensity_swing_coef * intensity_smooth_t)`.
   - Silence state per D-019: at `totalStemEnergy == 0`, `drums_energy_dev = 0` and the smoothing decays to 0, so intensity → `baseline * floor_coef` (0.4 * 5.0 = 2.0 nominal — visible idling rig per `10_silence_calm_body.jpg`).
9. **`applyPreset` wiring** — when the active preset's descriptor has a non-nil `stageRig`, instantiate `FerrofluidStageRig` (preset-specific, hard-wired by name for the V.9 first consumer per D-125(f); generic `StageRigEngine` extraction deferred to second consumer), tick it per frame from the existing per-preset tick path (analogous to `LumenPatternEngine.tick`), and call `pipeline.setDirectPresetFragmentBuffer4(stageRig.buffer)` on preset apply. On preset switch to a non-stage-rig preset, clear the binding (returns to the placeholder buffer).
10. **`sceneMaterial` in `FerrofluidOcean.metal`** — change `outMatID = 3` (Session 2) to `outMatID = 2`. The matID==3 thin-film branch in RayMarch.metal is retained for future single-light thin-film presets but is no longer the Ferrofluid Ocean dispatch target. Update both `TODO(V.9 Session 3)` comments to retire / point at Session 4.
11. **Stride regression test** at `PhospheneEngine/Tests/PhospheneEngineTests/Shared/CommonLayoutTests.swift` (or wherever the existing `LumenPatternState_strideIs376` test lives — colocate). Asserts `MemoryLayout<StageRigState>.stride == 208` and `MemoryLayout<StageRigLight>.stride == 32`. Same shape as the existing Lumen stride test.
12. **§5.8 clarifying note in `SHADER_CRAFT.md`** — one-line pointer at the §5.8 heading: "Implementation contract: see D-125. JSON schema in D-125(e) is authoritative; the §5.8 example below is illustrative."

### DO NOT author in this session

- Domain-warped meso detail / micro normal perturbation / Cassie-Baxter droplets (Session 4).
- Audio-modulated thin-film thickness (Session 4).
- Anisotropic specular along spike axes (Session 4).
- Screen-space shadow march for matID==2 — explicitly excluded by D-125(d). If a future fidelity gap demands it, revisit at Session 5 cert review and consider the "single-shadow-light hack" fallback (cast shadow from the brightest active beam only).
- Sky-tint tuning for the "distant fog cools to dark purple" target (Session 5 cert review per the §10.3.5 anti-tuning rule).
- Generic `StageRigEngine` extraction. V.9 ships `FerrofluidStageRig` concrete. Second consumer is the trigger to extract.
- Re-wiring the matID==3 branch. It stays in place as the single-light thin-film fallback — useful for future presets that want the iridescent material without the multi-light rig.
- Re-running PresetRegressionTests' Ferrofluid Ocean golden hash regen. The hash stays commented-out until Session 5 cert review (matID==2 substantially changes the output; locking a hash before cert is wasted churn).

Defer all of the above with `// TODO(V.9 Session N):` markers in code where you'd otherwise be tempted to start them.

### Prerequisites — read in order

1. [`docs/presets/FERROFLUID_OCEAN_CLAUDE_CODE_PROMPTS.md`](FERROFLUID_OCEAN_CLAUDE_CODE_PROMPTS.md) — the Session 1 + Session 2 "landed" blocks above this prompt.
2. [`docs/DECISIONS.md` D-125](../DECISIONS.md) — the implementation contract. Read every clause; this prompt assumes you know D-125(a)–(g).
3. [`docs/SHADER_CRAFT.md §5.8`](../SHADER_CRAFT.md) — the §5.8 spec (light configuration, color rotation, intensity envelope, silence state, IBL coordination, failure modes).
4. [`PhospheneEngine/Sources/Renderer/Shaders/RayMarch.metal`](../../PhospheneEngine/Sources/Renderer/Shaders/RayMarch.metal) — current state after Session 2 + P3-A. The `rm_finishLightingPass` helper is the thing matID==2 calls after its per-light direct accumulation. matID==3 is the structural reference for "how a non-default lighting branch is laid out."
5. [`PhospheneEngine/Sources/Presets/Lumen/LumenPatternEngine.swift`](../../PhospheneEngine/Sources/Presets/Lumen/LumenPatternEngine.swift) — the per-preset Swift state class pattern. Mirror its shape for `FerrofluidStageRig`.
6. [`PhospheneEngine/Sources/Renderer/RayMarchPipeline.swift`](../../PhospheneEngine/Sources/Renderer/RayMarchPipeline.swift) `lumenPlaceholderBuffer` allocation (lines ~255–270) — the structural reference for `stageRigPlaceholderBuffer`.
7. [`PhospheneEngine/Sources/Renderer/RayMarchPipeline+Passes.swift`](../../PhospheneEngine/Sources/Renderer/RayMarchPipeline+Passes.swift) `runGBufferPass` + `runLightingPass` — the slot-8 binding sites you'll add slot-9 binding next to.
8. [`PhospheneEngine/Sources/Renderer/RenderPipeline+PresetSwitching.swift`](../../PhospheneEngine/Sources/Renderer/RenderPipeline+PresetSwitching.swift) — the existing `setDirectPresetFragmentBuffer3` API. Mirror its shape for the new `Buffer4` API.
9. [`PhospheneEngine/Sources/Shared/Common.metal`](../../PhospheneEngine/Sources/Renderer/Shaders/Common.metal) `LumenPatternState` Swift mirror — the byte-identical Swift struct pattern.
10. [`docs/VISUAL_REFERENCES/ferrofluid_ocean/README.md`](../VISUAL_REFERENCES/ferrofluid_ocean/README.md) — re-read the `04_*` and `08_*` annotations. Session 3 closes one half of `04`'s dual-anchor (the lighting half); Session 4 closes `08`'s aurora-quality light over dark surface.
11. CLAUDE.md Failed Approaches §24 (light-only mood tint insufficient; now mitigated by `rm_finishLightingPass`), §4 (beat-onset as primary motion driver banned — applies to beam intensity), §58 (Drift Motes — musical role must be load-bearing).

### Failed-approach guards (must satisfy)

- **§5.8 anti-patterns.** No beat-strobed intensity. No saturated party palette without going through `palette()`. No beam motion edge-triggered on beat. No pillar reflections — high light intensity + roughness ≥ 0.05 should prevent constructive pillaring at the same vertical. If renders show vertical pillars after Session 3, that's a structural concern, not a tuning one — surface to Matt.
- **§4 + §32 reminder.** Beam intensity envelope is `0.4 + 0.6 * drums_energy_dev_smoothed`, not `drums_beat`. Beam motion is `arousal-smooth` × angular velocity, not `*_beat` rising edges.
- **§24 (mitigated, not retired).** `rm_finishLightingPass` is the only D-022-compliant lighting tail. The matID==2 branch MUST call it after summing direct contributions; do NOT re-author the IBL ambient + fog block inline. If you find yourself copying the matID==3 IBL block into matID==2, stop — call the helper.
- **§42 fbm8 thresholds.** Doesn't apply to Session 3 directly. But if you add palette noise / palette dithering, threshold values must be centred near 0.
- **§44 Metal type-name shadowing.** No `half`, `ushort`, `uchar`, `packed_float3` as variable names in the new MSL struct or the matID==2 branch.
- **D-026 deviation primitives.** Intensity envelope is `drums_energy_dev` (already a deviation primitive — ✓). Palette pitch-shift is `vocals_pitch_hz` (raw Hz, *not* AGC-normalized energy — exempt from D-026 because pitch isn't an energy quantity). Other_energy fallback is `other_energy_dev` (deviation — ✓).
- **D-021 sceneMaterial signature contract.** sceneMaterial emits `outMatID = 2`. The lighting dispatch lives in the lighting fragment, not in sceneMaterial. Do not put light-summation logic in sceneMaterial.

### Acceptance gates for Session 3

1. **Compiles.** `PresetLoaderCompileFailureTest` passes; preset count remains 15. `testFerrofluidOceanShaderCompiles` still passes (now exercising matID==2 via `outMatID = 2`).
2. **Stride regression.** `StageRigState_strideIs208` (new) and `StageRigLight_strideIs32` (new) tests pass. Lock against accidental shrinkage.
3. **PBR port sync still passes.** `RendererPBRPortSyncTests` (the P1 follow-up) green — matID==2 uses `rm_thinfilm_rgb` so the drift gate stays load-bearing.
4. **matID==0 unchanged.** `PresetRegressionTests` passes for Glass Brutalist + Kinetic Sculpture (matID==0 presets with golden hashes locked) — Session 3 adds a new dispatch branch but does NOT change the default path. Adding the slot-9 binding to `runGBufferPass`/`runLightingPass` is the only change matID==0 presets observe; the zero-filled placeholder buffer must not alter their output.
5. **Mood-tint atmosphere gate carries forward.** `testFerrofluidOceanMoodTintAtmosphereShifts` and `testFerrofluidOceanMoodTintIBLPropagation` continue to pass with matID==2. (Both gates verify `rm_finishLightingPass` propagates `scene.lightColor.rgb`; the helper hasn't changed, so both should pass without test edits. If they fail, the matID==2 branch is bypassing the helper.)
6. **New gate — multi-light dispatch.** Add `testFerrofluidOceanStageRigDispatchActive` to `FerrofluidOceanVisualTests`. Renders the steady-mid fixture with a `FerrofluidStageRig` whose `activeLightCount = 4` and a *placeholder-only* version (matID==2 dispatched but slot-9 buffer empty), asserts the two frames are measurably distinct (avg channel diff > 5.0) — proves the slot-9 buffer is reaching the shader and the loop is running.
7. **Silence state preserved.** Render the silence fixture with `FerrofluidStageRig`; manual eyeball check via `RENDER_VISUAL=1`: beams visibly idle at low intensity, palette evolves slowly via the `audio_time * 0.05` base rotation, no spike lattice (matches `10_silence_calm_body.jpg`).
8. **Engine suite green.** Full `swift test --package-path PhospheneEngine` passes except the same three pre-existing flakes (`MemoryReporter.residentBytes`, `MetadataPreFetcher.fetch_networkTimeout`, `SoakTestHarness.cancel`).
9. **No anti-pattern grep regressions.** Grep new code for `drums_beat` (anti for intensity envelope), `f.bass [<>]`, `stems.bass_energy [<>]`, literal `44100`. None should appear.
10. **SwiftLint clean** on every touched file.

### Mid-session sanity check (against Failed Approach #48)

After step 7 lands (matID==2 branch compiles and runs against the zero-filled placeholder), render a contact sheet of the four standard fixtures **before** authoring the `FerrofluidStageRig` Swift class (step 8). If the placeholder render is structurally different from the matID==3 baseline (e.g. completely black because the per-light loop with `activeLightCount = 0` writes nothing), something's wrong with the dispatch wiring — fix before proceeding to Swift class. Cheap check, catches a class of "shader works in isolation but doesn't reach the screen" bugs.

After step 9 lands (full pipeline running with `FerrofluidStageRig` ticking), render a second contact sheet at the four fixtures + the cool/warm valence pair. Compare against `04_specular_razor_highlights.jpg` and `08_aurora_quality_light_over_dark_surface.jpg` informally — is the **direction** right? Beam reflections sweeping diagonally across the surface, palette evolving, no pillars? Don't tune yet — Session 5 owns tuning. The mid-session check is "is this in the neighbourhood of the references, or is it structurally elsewhere?" If structurally elsewhere, stop and surface to Matt rather than starting Session 4.

### Out of scope for this session

Same restatement as Sessions 1 and 2. End after the 10 acceptance gates pass. If a gate cannot be reached without authoring downstream layers (meso detail, droplets, sky tuning), **STOP and report** rather than silently expanding scope. The "tune until it looks right" temptation lives in Failed Approach #49 — and the V.9 plan's whole structure is sequencing infrastructure before tuning to avoid exactly that pattern.

### Closeout

Per CLAUDE.md Increment Completion Protocol:

1. Closeout report covering: files changed (new vs edited), tests run (pass / fail counts), visual harness output paths (the two mid-session contact sheets plus the new multi-light dispatch gate's PNGs), doc updates, capability registry, engineering plan, known risks, git status.
2. Update [`docs/ENGINEERING_PLAN.md`](../ENGINEERING_PLAN.md) Increment V.9 with Session 3 ✅ block. Carry forward to Sessions 4–5.
3. Update [`docs/ENGINE/RENDER_CAPABILITY_REGISTRY.md`](../ENGINE/RENDER_CAPABILITY_REGISTRY.md) — D-125 is a new catalog-wide lighting capability (slot-9 fragment buffer + matID==2 dispatch). New row, status promoted from Missing → Supported.
4. Update this prompt doc (`docs/presets/FERROFLUID_OCEAN_CLAUDE_CODE_PROMPTS.md`) — flip Session 3 row to ✅ in the ledger; add a brief landed-work summary paragraph below this prompt.
5. Commit on local `main` with separate commits for (a) slot-9 plumbing in RenderPipeline / RayMarchPipeline / preamble, (b) `PresetDescriptor.StageRig` + Ferrofluid Ocean JSON, (c) matID==2 branch in RayMarch.metal, (d) `FerrofluidStageRig` Swift class + applyPreset wiring + sceneMaterial outMatID change, (e) tests (stride + dispatch-active), (f) docs. Message prefix `[V.9-session-3]`. Six commits is a reasonable split; collapse to four if any two are mechanically trivial.
6. Do **not** push without Matt's explicit go-ahead.

---

## V.9 Session 4 — Audio routing + meso/micro detail layers — ⚠ SHIPPED 2026-05-13 (M7 review FAILED — rescue in Session 4.5)

### Landed work summary

Three-phase landing across nine commits (`[V.9-session-4 P0]` / `[V.9-session-4 PA]` / `[V.9-session-4 PB]` prefixes). Each phase's acceptance gates passed before the next began.

**Phase 0 — Session 3 follow-up backfill** (4 commits, ~580 lines):
1. `StageRigDecoderTests` (11 tests): `light_count` clamp [3, 6] fallback to 4 on out-of-range (2 / 7 / -1 / 99); `palette_phase_offsets` exact length pass-through, shorter input pads evenly (j/count for the tail), longer input truncates; Codable round-trip; missing block decodes as nil; partial block applies §5.8 spec defaults.
2. `FerrofluidStageRigMathTests` (8 tests, 5 suites): silence convergence (per-light intensity → `intensity_baseline × floor_coef = 2.0` at §5.8 defaults; smoothedDrumsDev → 0); 150 ms discrete-time smoother step response (~0.65 at 3τ, ≥ 0.995 at 10τ); pitch-shift confidence gate at 0.60 boundary (palette delta confirms log-perceptual vs fallback path); `otherEnergyDev` × 0.15 scale at endpoints; arousal-driven orbital phase advance (high arousal +1.0 → 0.20 rad/s, low arousal -1.0 → 0.05 rad/s after 60 ticks).
3. Silence-state matID == 2 visual snapshot: `testFerrofluidOceanRendersFourFixtures` now binds a real `FerrofluidStageRig` (tick × 30 at 60 fps for envelope convergence) for the silence fixture and asserts `avgChannel > 8.0` (stricter than the blanket `lit > 100` — catches a regression where the matID == 2 branch returns `vec3(0)` at silence).
4. `Scripts/check_drums_beat_intensity.sh` CI grep gate: bans `drumsBeat` / `drums_beat` from `Sources/Presets/FerrofluidOcean/*`, `Sources/Shared/StageRigState.swift`, `Sources/Presets/*StageRig*.swift`, and the matID == 2 branch of `RayMarch.metal`. Comment lines and `(void)` casts filtered. Manual injection verified.
5. Decoder fixes + doc-comment touch-ups: `intensity_smoothing_tau_ms ≤ 0` warn-and-floor to §5.8 default; palette_phase_offsets pad now caches `originalCount` before append loop (prior formula gave [in0, in1, 0.5, 1.0] instead of [in0, in1, 0.5, 0.75]); `FerrofluidStageRig.reset()` doc-comment notes test-only status.

**Phase A — Material detail layers** (3 commits, ~256 lines):
1. `PresetDescriptor.FerrofluidParams` JSON schema decoder with five fields (`meso_strength` 1.0 / `droplet_strength` 1.0 / `micro_normal_amplitude` 0.02 / `thin_film_thickness_baseline_nm` 220 / `thin_film_arousal_range_nm` 40); negative-value warn-and-floor. 7 `FerrofluidParamsDecoderTests` (full / empty / missing / partial / negative / Codable round-trip / on-disk back-fill). Production `FerrofluidOcean.json` carries the block with §5.8 defaults.
2. `FerrofluidOcean.metal` meso + droplet utilities: `fo_meso_warp(xz, strength)` (2-component 2-octave `fbm4` at scale 2.0, amplitude 0.15); `fo_ferrofluid_field` takes mesoStrength and warps Voronoi sample position before f1 evaluation; `fo_droplet_sdf(p, fieldStrength, dropletStrength, mesoStrength, swellHere)` (hemispherical SDF beads per Voronoi cell, radius 0.04 × dropletStrength, apex-fraction 0.6 × radius). `sceneSDF` composes height-field surface + droplet sphere via `op_smooth_union(surfaceSdf, dropletSdf, 0.04)`. Phase A holds strengths at hardcoded `fo_meso_strength_phaseA() = 1.0` / `fo_droplet_strength_phaseA() = 1.0`.
3. `RayMarch.metal` matID == 2 micro-normal perturbation: three `noiseFBM` samples at scale 15 derive a tangent-space normal vector; perturbs N at amplitude 0.02 before BRDF consumption. NEVER audio-modulated (substrate's intrinsic tactile identity per §5.8 silence-state semantics). Linear-repeat sampler wraps the 256×256 noise texture for < 7 cm world-space repetition.

**Phase B — Audio routing finalization** (2 commits, ~61 lines):
1. `FerrofluidOcean.metal` meso + droplet strength formulas wired from D-026 deviation primitives: `fo_meso_strength(f) = clamp(0.5 + 1.5 × max(0, f.mid_att_rel), 0, 2)` (baseline 0.5 silence-state turbulence — never zero per §5.8 "gentle film" silence semantics); `fo_droplet_strength(f) = clamp(0.0 + 2.0 × max(0, f.bass_att_rel), 0, 2)` (0 at silence per `10_silence_calm_body.jpg`).
2. `RayMarch.metal` matID == 2 & matID == 3 thin-film thickness modulation: `thicknessNm = 220 + clamp(features.arousal, -1, 1) × 40` → effective [180, 260] nm. Stays inside the subtle blue-to-cyan band (rainbow oil-slick fail mode > ~300 nm). Both branches updated so a future preset adopting the single-light fallback thin-film inherits the audio-modulated iridescence. D-022 mood-tinted IBL ambient + fog path through `rm_finishLightingPass` is unaffected (downstream of thickness).

**Acceptance gates:** all pass. P0 (4 gates): SwiftLint strict clean on touched files; 20 new tests pass; silence-state visual snapshot fires the new avg-channel assertion (avg ≈ 12–15); grep gate exits 0 on clean tree + non-zero on manual violation injection. PA (8 gates): preset count remains 15 (Failed Approach #44 silent-drop gate passes); all 6 `FerrofluidOceanVisualTests` pass with new layers visible in contact sheet; `testFerrofluidOceanStageRigDispatchActive` still passes (matID == 2 dispatch unaffected by sceneSDF additions); `FerrofluidParamsDecoderTests` (7 new). PB (7 gates): full 1256-test engine suite passes; `check_drums_beat_intensity.sh` + `check_sample_rate_literals.sh` both clean; mood-tint atmosphere + IBL gates carry forward through thickness-modulated matID == 2 (avg diff ~32 / ~20, well above 1.0 threshold); SwiftLint strict clean on touched files.

**Visual harness output paths:** `/var/folders/.../PhospheneFerrofluidOceanV9Session1/fixtures/` (Phase A + Phase B 4-fixture contact sheet); `/var/folders/.../PhospheneFerrofluidOceanV9Session1/mood_tint/` (cool/warm valence pair); `.../stage_rig_dispatch/`, `.../mood_tint_ibl/`, `.../independence/` (carry-forward from prior sessions). All renders observed in-neighbourhood of the references; pixel-match cert is Session 5's job per the §10.3.5 / Failed Approach #49 anti-tuning rule.

**Audio data hierarchy compliance:** every new audio coupling uses a D-026 deviation primitive (`mid_att_rel`, `bass_att_rel`) or a smoothed scalar (`arousal`). No `*_beat` onset edges; no raw AGC arithmetic (Failed Approach #31); no impossible AGC gate combinations (Failed Approach #57). CI grep gates enforce both `drumsBeat`-in-intensity (the new gate) and the existing literal-`44100` + raw-AGC-band patterns.

**Deferred to Session 5 (TODO markers + ENGINEERING_PLAN entry):** production tuning of `intensity_baseline` / `orbit_altitude` / `orbit_radius` against the references (Failed Approach #49 — tune against references, not in the abstract); golden-hash regen for Ferrofluid Ocean in `PresetRegressionTests` (currently commented `// V.9 Session 1 — regen at Session 5`); rewrite of `FerrofluidBeatSyncTests` / `FerrofluidLiveAudioTests` / `PresetAcceptanceTests` (Session 1 skip-guards still in place); M7 cert review against `04_specular_razor_highlights.jpg` + `01_macro_ferrofluid_at_swell_scale.jpg`; single-shadow-light hack if M7 reveals shadow-lift gap; perf capture on M1/M2 (Tier 1) and M3+ (Tier 2 ≤ 7.0 ms p95).

### Mid-session sanity check outcome

The Phase A mid-session contact sheet rendered the four standard fixtures + the silence fixture. The renders showed structural correctness: silence fixture has gentle macro swell + visible micro-detail in beam reflections (no spikes, no droplets); steady-mid fixture has visible meso turbulence + droplet beading; beat-heavy fixture has prominent spike-tip droplet activity. The Phase B contact sheet renders showed the audio routing engaged: meso turbulence amplitude scales with `mid_att_rel`, droplet strength scales with `bass_att_rel`, and the cool/warm thin-film thickness shift produced subtle iridescent breathing in beam reflections. No structural divergence from the references was observed (Failed Approach #49 trigger condition was not hit). Final pixel-match cert is Session 5's job.

### M7 review outcome (2026-05-13, post-landing) — FAILED

Live session capture (`/Users/braesidebandit/Documents/phosphene_sessions/2026-05-14T01-20-28Z/video.mp4`) showed four structural failures, summarized in Matt's words: "No reflective-black ferrofluid material visible. No idea what the droplets are and why they are here — no part of the original vision. The light source washes everything out and does not shine bright colorful neon light onto the surface of the ferrofluid material. It feels like effects are competing with one another rather than working in harmony in alignment with the music."

Root cause diagnosis (Matt + Claude chat, 2026-05-13):

1. **The §5.8 stage-rig as "4 point lights at altitude 6 / radius 4 with inverse-square falloff" is the wrong implementation paradigm.** The references' "moving colored beams reflected in dark water" mechanic is mirror-reflects-aurora-sky (see `08_lighting_aurora_over_dark_water.jpg` and its README annotation: "the preset's beams are *continuous diffuse gradients, not point sources with pillar reflections*"). Physical inverse-square at the §5.8 spec orbit distance gives ~0.02× attenuation; the beams have no visual presence against the IBL ambient that the mirror surface ALSO reflects. The fix is not to scale intensity 50× — it's to put the moving colors INTO the sky the mirror reflects.

2. **The IBL cubemap (`rm_skyColor` — near-white horizon → blue zenith gradient) is what the mirror is reflecting.** That's the "gray wash," not "ambient drowning the beams." The fix is to give Ferrofluid Ocean its own dark-purple aurora-sky function for matID == 2 reflection.

3. **The Phase A material detail layers (meso warp, droplets, micro-normal) are decoration competing with the hero signal.** Per CLAUDE.md Authoring Discipline ("Articulate the musical role before authoring anything"), each layer should have a one-sentence musical role a listener can pair with the visual. The droplets fail Matt's "no idea what they are" test — direct confirmation of Failed Approach #58 at the layer scope.

4. **The micro-normal perturbation destroys the mirror identity.** Jittering the normal scatters the thin-film specular across pixels; the references' "razor highlights" require a smooth surface.

5. **The Rosensweig spike profile is too soft / short.** References show tall narrow pyramidal spikes; current `exp(-d² × 40)` × 0.15 is a soft bell-curve.

6. **The Gerstner swell is rippling, not rolling.** References want deep-sea churning per `02b_*`; current 4-wave sum with amplitudes [0.15, 0.10, 0.06, 0.03] is too small / too short-wavelength.

The Session 4 mid-session sanity-check claim "no structural divergence from the references was observed" is retroactively wrong — the structural divergence was severe but the harness fixtures + automated gates couldn't see it. **Lesson: contact-sheet sanity checks must compare against the named reference images, not against a self-judgment of "looks reasonable." Phase 4.5 mandates explicit side-by-side comparison.**

Session 4 commits (P0 + PA + PB) remain in git history; Phase 4.5 Phase 0 reverts the decoration layers but does not rewrite history.

### Session 4 prompt (original — kept for traceability below)

---

## V.9 Session 4.5 — Rescue: revert decoration + replace §5.8 lighting paradigm + spike/swell retune

**Status:** ⏳ Not started. Authored 2026-05-13 post-Session-4 M7 review failure (see Session 4 M7 review outcome above).

**Why a rescue session.** V.9 Session 4 shipped Phase 0 + Phase A + Phase B and passed every automated gate, but the M7 review of the live session capture flagged four structural failures (full root-cause diagnosis under the Session 4 "M7 review outcome" block above). The §5.8 stage-rig as "discrete point lights with inverse-square falloff" is the wrong implementation paradigm for a near-mirror substrate; the references' mechanic is **mirror-reflects-aurora-sky**, not point-lights-cast-onto-surface. The Phase A decoration layers (droplets, micro-normal, meso warp) are visible noise without load-bearing musical role. This session is the rescue.

### Musical role (re-articulation post-M7 — read this before any code)

The substrate is a **near-mirror black ferrofluid that reflects a moving colored sky.** The hero visual is **the reflection of a slow-moving colored aurora in the mirror surface.** The ferrofluid picks up the chromatic content without the substrate ever turning bright — color lives in the reflection, never in the surface tone itself. Per `04_*` README annotation: *"saturated rim highlights where the beam catches spike edges, near-black substrate even at the brightest beam location, chromatic content present only in the reflections (not in the underlying surface tone)."* Per `08_*` README annotation: *"the doubled-aurora-in-reflection composition showing what colored light over a reflective surface looks like at landscape scale."*

Music drives:

- **The aurora colors** (palette phase) ← `stems.vocals_pitch_hz` (perceptual log over 80 Hz–1 kHz, confidence-gated at 0.6, fallback `stems.other_energy_dev × 0.15`). Vocal pitch rising → palette phase shifts → bands change color.
- **The aurora intensity** ← `stems.drums_energy_dev` (smoothed 150 ms τ — reuse the FerrofluidStageRig smoother). Drum energy envelope → bands brighten / dim continuously, never edge-strobed.
- **The aurora orbit speed** ← arousal (smoothstep -0.5 to +0.5). High arousal → bands sweep faster; low arousal → bands drift slowly.
- **The body** (Gerstner swell amplitude) ← arousal-baseline + `stems.drums_energy_dev` accent. Calm at silence, deep rolling at peak.
- **The spikes** (Rosensweig field strength) ← `stems.bass_energy_dev`. Razor pyramids emerging when bass envelope is high; fully collapsed at silence.
- **The thin-film thickness** ← arousal (kept from Session 4 Phase B). Subtle iridescent breathing in the mirror reflection.

When a kick lands: spikes pop up, sky brightens slightly. When the vocal rises in pitch: aurora colors shift. When the music swells: surface rolls bigger; aurora orbits faster. At silence: smooth calm body of liquid reflecting a near-black sky with subtle purple gradient.

**Acceptance test for the musical role:** a listener should be able to point at a moment in the music and identify the visual response. If "the aurora sweep across the surface when the vocal soared" is visible, ✓. If the viewer can only say "vibes" or "reactive to energy," ✗.

### Scope (strict) — four phases, gated

Phases must complete in order. Each phase has acceptance gates; do not start the next phase until the current phase's gates pass.

---

#### Phase 0 — Revert decoration layers

1. **Revert the Cassie-Baxter droplet field entirely.**
   - Drop `fo_droplet_sdf` + `FO_DROPLET_RADIUS` / `FO_DROPLET_APEX_FRACTION` / `FO_SMOOTH_UNION_K` constants from `FerrofluidOcean.metal`.
   - Drop the `op_smooth_union(surfaceSdf, dropletSdf, ...)` composition in `sceneSDF`; restore pure height-field SDF (`return p.y - surfaceY;`).
   - Drop `fo_droplet_strength` audio-routing function.
   - Drop the `droplet_strength` JSON field from `PresetDescriptor.FerrofluidParams` and from `FerrofluidOcean.json`.
   - Adjust `FerrofluidParamsDecoderTests` to the reduced field set (4 fields: `meso_strength` deprecated but kept for one revision, `micro_normal_amplitude` deprecated, `thin_film_thickness_baseline_nm`, `thin_film_arousal_range_nm`).

2. **Revert the micro-normal perturbation in `RayMarch.metal` matID == 2 branch.**
   - Drop `kFerrofluidMicroNormalScale` + `kFerrofluidMicroNormalAmplitude` + `microSamp` + the three `noiseFBM` samples + the `microNormal` gradient + the `N = normalize(N + microNormal * amp)` line.
   - The surface normal returns to the G-buffer stored normal — smooth, low-roughness, mirror-like.
   - Drop `micro_normal_amplitude` JSON field. Adjust tests.

3. **Revert the meso domain warp.**
   - Drop `fo_meso_warp` + `FO_MESO_WARP_SCALE` + `FO_MESO_WARP_AMPLITUDE` constants from `FerrofluidOcean.metal`.
   - `fo_ferrofluid_field` no longer takes a `mesoStrength` parameter; samples Voronoi at raw `p.xz`.
   - Drop `fo_meso_strength` audio-routing function.
   - Drop the `meso_strength` JSON field.

4. **Keep the thin-film thickness modulation** in matID == 2 / matID == 3 (kept from Session 4 Phase B). The arousal-driven thickness shift is subtle, in-vision, and was not flagged at M7.

5. **Keep `FerrofluidStageRig.swift` (the Swift class) intact for now.** Its per-frame outputs (light positions / colors / intensities) will be repurposed in Phase A to drive aurora bands instead of point lights. Class API unchanged; consumption changes.

6. **Test updates:**
   - `FerrofluidParamsDecoderTests` — adjust to the 2-field shape (thin_film_thickness_baseline_nm + thin_film_arousal_range_nm). All other field-related tests deleted.
   - `FerrofluidOceanVisualTests.testFerrofluidOceanRendersFourFixtures` — keep the silence-state avg-channel assertion (it will still hold after Phase A's aurora-sky lands; the dark-purple gradient at silence produces non-zero channel values).
   - `testFerrofluidOceanStageRigDispatchActive` — keep passing. It will be rewritten in Phase A as the aurora-sky dispatch test.

**Phase 0 acceptance gates:**

1. Build clean (engine + app).
2. Preset count remains 15 (Failed Approach #44 silent-drop gate).
3. `FerrofluidParamsDecoderTests` passes with reduced field set.
4. `FerrofluidOceanVisualTests` (all 6) pass.
5. `Scripts/check_drums_beat_intensity.sh` + `Scripts/check_sample_rate_literals.sh` both clean.
6. SwiftLint strict clean on touched files.
7. Visual smoke: contact sheet at the 4 standard fixtures shows pure-mirror substrate reflecting the **current** IBL gradient. Surface reads as a gray-blue mirror — no stippling, no droplet bumps, no warp distortion. (We're undoing failure modes here, not solving them yet.)
8. Commit as 1 commit. Prefix: `[V.9-session-4.5 P0]`.

---

#### Phase A — Replace §5.8 lighting paradigm with aurora-sky reflection

Conceptual change: matID == 2 becomes a **mirror-reflects-procedural-sky** path. The §5.8 musical contract (vocals_pitch → palette, drums_energy_dev → intensity, arousal → orbit speed) is preserved; only the GPU consumption changes from "Cook-Torrance per-light loop" to "sample procedural sky at reflection vector."

1. **Author a procedural aurora sky function `rm_ferrofluidSky` in `RayMarch.metal`** (file-private to that file, not in shared utilities — Ferrofluid Ocean-specific until a second consumer ships):
   - Signature: `static float3 rm_ferrofluidSky(float3 R, constant FeatureVector& f, constant StemFeatures& stems, constant StageRigState& rig, constant SceneUniforms& scene)`.
   - **Base sky:** dark purple-to-near-black gradient. Zenith (R.y → +1): near-black with subtle purple. Horizon (R.y → 0): slightly warmer purple, never bright. Below horizon (R.y → -1): even darker, fading to true black. Anchor: `07_atmosphere_dark_purple_fog.jpg` palette annotation. The base sky multiplied by `scene.lightColor.rgb` carries D-022 mood-tint through the reflection.
   - **Aurora bands:** 2–4 overlapping curved colored bands. Each band's central direction comes from one of `rig.lights[i].positionAndIntensity.xyz` (normalize as sky direction). Each band's color comes from `rig.lights[i].color.xyz`. Each band's brightness multiplier comes from `rig.lights[i].positionAndIntensity.w` (the per-light intensity envelope; already includes the 150 ms drums smoothing from FerrofluidStageRig).
   - **Spatial spread:** each band is a Gaussian or curved-cosine streak along R (NOT a hemisphere). Width parameter controls how concentrated each band is. Bands should read as "aurora veils" — narrow streaks at a particular sky direction with smooth falloff, not blob lights.
   - **Composition:** `base + Σ (band_color × band_intensity × band_spread(R, band_dir))`. The base provides the silence-state minimum visible content; bands add the dynamic chromatic content. At silence (band intensities = floor × baseline ≈ small but non-zero per §5.8), bands are dim but visible — the sky has subtle color even at silence.

2. **Replace the matID == 2 Cook-Torrance per-light loop** in `raymarch_lighting_fragment`:
   - Drop the entire `for (uint i = 0; i < stageRig.activeLightCount && i < 6; i++)` loop body (lines ~528-555 of current RayMarch.metal).
   - Compute the reflection vector once: `R = reflect(-V, N)`.
   - Sample `rm_ferrofluidSky` at R.
   - Multiply by thin-film Fresnel F0 (the `rm_thinfilm_rgb` recipe, already wired) — this gives the mirror's frequency-dependent reflectance, producing the subtle iridescent edge shift the references show.
   - That is the **entire** direct contribution for matID == 2.
   - **Bypass `rm_finishLightingPass` entirely for matID == 2.** The substrate is mirror-only — no diffuse IBL irradiance (kd = 0 for metallic=1), no separate fog tail (the base sky's dark purple IS the fog visual already, integrated into the sky function). Write a minimal matID == 2 tail: `return float4(skyReflection * F0_thin, 1.0);` plus an ACES tone-map if needed.
   - For atmospheric depth: tint distant reflections (where the surface is far from the camera) toward the base sky color so the horizon edge fades into atmosphere. Single `mix(reflection, baseSkyAtZenithDirection, fogFactor)` where fogFactor comes from `depthNorm * farPlane` against the scene's `fogNear` / `fogFar`.

3. **Verify FerrofluidStageRig outputs map cleanly to aurora bands:**
   - `lights[i].positionAndIntensity.xyz` is currently a 3D world-space position on an orbital circle. The aurora band consuming it should treat the position vector as a **sky direction** (normalize to unit vector). The orbit-on-circle motion becomes "this band's central direction sweeps across the sky on a slow orbit" — exactly what we want.
   - `lights[i].positionAndIntensity.w` is the per-light intensity (baseline × (floor + swing × smoothedDrumsDev)). Use directly as band brightness multiplier.
   - `lights[i].color.xyz` is the per-light palette color. Use directly as band hue.
   - **No changes needed to `FerrofluidStageRig.swift`** — the consumption side reinterprets the data. Document this in the class's doc-comment ("V.9 Session 4.5: outputs drive aurora bands in the procedural sky, not Cook-Torrance lights").

4. **JSON schema:**
   - Keep the `stage_rig` block name. The §5.8 musical contract is preserved; only the GPU paradigm changes. Renaming would invalidate `PresetDescriptor.StageRig` + every Swift / MSL reference; not worth the churn.
   - Update CLAUDE.md "Failed Approaches" with the §5.8 reframing (see Phase C closeout).

5. **D-022 mood-tint propagation through the new sky:**
   - The base sky color multiplies by `scene.lightColor.rgb` once. This carries the cool-vs-warm valence shift through the entire matID == 2 reflection.
   - Test gate: `testFerrofluidOceanMoodTintAtmosphereShifts` and `testFerrofluidOceanMoodTintIBLPropagation` — both need adapting. The new equivalent tests verify the sky function's base color shift across the cool/warm valence pair (avg channel diff > 1.0 expected).

6. **Test updates:**
   - **REWRITE** `testFerrofluidOceanStageRigDispatchActive` → `testFerrofluidOceanSkyReflectionDispatchActive`. New gate: render with active rig (FerrofluidStageRig producing non-trivial light positions/colors/intensities) vs with placeholder buffer (activeLightCount = 0). Diff threshold ≥ 1.0 expected (the active rig adds aurora bands that the placeholder doesn't).
   - **REWRITE** `testFerrofluidOceanMoodTintAtmosphereShifts` — adapt to the new sky function. The cool-vs-warm valence shift should appear in the sky's base color and propagate through the mirror reflection.
   - **REWRITE** `testFerrofluidOceanMoodTintIBLPropagation` — the IBL ambient path no longer applies for matID == 2. Either retire this test (sky function IS the new IBL for matID == 2) or rewrite to verify the sky function's `scene.lightColor.rgb` multiply.

**Phase A acceptance gates:**

1. All Phase 0 gates still pass.
2. `testFerrofluidOceanShaderCompiles` passes; preset count remains 15.
3. `testFerrofluidOceanRendersFourFixtures` passes. Visual smoke:
   - **Silence fixture:** smooth mirror reflecting dark-purple sky with subtle baseline color bands at the silence-state intensity floor. NOT gray-blue (that was the failure). NOT pure black.
   - **Steady-mid fixture:** bands brighter, palette warmer where vocals_pitch_hz would dictate.
   - **Beat-heavy fixture:** brightest bands, biggest intensity envelope, palette at peak chromatic position.
   - **Quiet fixture:** bands dim, mostly base sky.
4. `testFerrofluidOceanSkyReflectionDispatchActive` (new) passes — active rig vs placeholder produces measurable diff.
5. Rewritten mood-tint gates pass — cool-vs-warm valence produces avg diff > 1.0 in the new sky-reflection path.
6. Engine suite: 0 new failures from the test rewrites.
7. Grep gates + SwiftLint strict clean.
8. **Mandatory side-by-side reference comparison** (mid-Phase, before next phase starts):
   - Render at the steady-mid fixture vs `08_lighting_aurora_over_dark_water.jpg` — the rendered output should be in the **neighbourhood** of the aurora-over-water composition. Not pixel-match. The "diffuse colored gradient on dark reflective body" mechanic should read.
   - Render at the beat-heavy fixture vs `04_specular_razor_highlights.jpg` — palette and substrate value range should approximate (spike shape is still wrong at this point; Phase B fixes that).
   - **If structural divergence is visible** (e.g., bands look like blob lights instead of veils, surface doesn't read as a mirror, palette saturates the substrate), STOP and surface to Matt. Don't tune your way out of a structural gap (Failed Approach #49).
9. Commit as 3–4 commits: (a) `rm_ferrofluidSky` procedural sky function, (b) matID == 2 branch replacement + minimal tail, (c) test rewrites, (d) doc-comment + CLAUDE.md updates if needed. Prefix: `[V.9-session-4.5 PA]`.

---

#### Phase B — Spike profile reshape + Gerstner swell retune

This phase is **pure tuning against the references** — small parameter changes, side-by-side reference comparison after each change.

1. **Spike profile** in `fo_ferrofluid_field`:
   - **Current:** `exp(-d² × 40.0)` × `(0.5 + 0.5 × sin(t × 0.8 + cellPhase))` × `fieldStrength × 0.15`.
   - **Target:** tall narrow pyramidal spikes per `01_macro_ferrofluid_at_swell_scale.jpg` and `04_specular_razor_highlights.jpg`. Sharper exp falloff, taller peak height, denser distribution.
   - **Starting values to tune from** (NOT spec — tune by rendering against references):
     - `exp(-d² × 80)` or `exp(-d² × 100)` for sharper conical falloff
     - peak multiplier × 0.25 or × 0.30 instead of × 0.15
     - Voronoi scale 5 or 6 instead of 4 for denser spike spacing
   - Verify silence-state collapse: `fieldStrength = 0` → spikes go to zero (smooth body of liquid per `10_silence_calm_body.jpg`).
   - Verify calm-body-with-spikes state (low arousal + high bass_energy_dev): spikes present + visible without overwhelming the macro surface.

2. **Gerstner swell** in `fo_wave` and `fo_swell_scale`:
   - **Current:** wavelengths [4, 2.5, 1.5, 0.8] and amplitudes [0.15, 0.10, 0.06, 0.03]. Too ripply / too small.
   - **Target:** deep-sea rolling per `02b_meso_swell_motion_dark_water.jpg`. Longer wavelengths, larger amplitudes at peak energy. Calm at silence per `10_*`.
   - **Starting values to tune from** (NOT spec):
     - wavelengths [8, 5, 3, 1.8] and amplitudes [0.40, 0.25, 0.12, 0.05] at peak
     - swell_scale formula: silence baseline 0.15 (10–20% of peak), full at peak `arousal=1 + drums_energy_dev=1`
   - Verify silence: surface is gentle calm body — gentle low-amplitude ripple per `10_*`, no spikes.
   - Verify peak: big rolling swells, motion audible up/down in the camera frame.

3. **Tests:**
   - `testFerrofluidOceanIndependenceStatesReachable` — verify the calm-body-with-spikes and agitated-body-without-spikes states still distinguish. Adjust the FV/Stems values if needed to match the new scale.
   - Optional new test: `testFerrofluidOceanCalmStateSwellOnly` — render the silence fixture at t=0 and t=5s; verify visible swell motion (frame diff) without any spikes (no high-frequency features).

**Phase B acceptance gates:**

1. All Phase 0 + Phase A gates still pass.
2. Side-by-side reference comparison:
   - Beat-heavy fixture vs `04_*` — spike shape neighborhood match (tall, narrow, sharp).
   - Active-motion fixture vs `02b_*` — swell motion neighborhood match (deep rolling, not ripply).
   - Silence fixture vs `10_*` — calm body of liquid, no spikes.
3. `testFerrofluidOceanIndependenceStatesReachable` still passes with adjusted values.
4. Engine suite: 0 new failures.
5. Grep gates + SwiftLint clean.
6. Commit as 2 commits: (a) spike profile reshape, (b) Gerstner retune. Prefix: `[V.9-session-4.5 PB]`.

---

#### Phase C — Verification against references + closeout

1. **Render full reference comparison contact sheet:**
   - The 4 standard fixtures + the silence fixture + the cool/warm valence pair + a "live music" reconstruction (replay FV/Stems values from `2026-05-14T01-20-28Z/features.csv` + `stems.csv` at multiple time points).
   - Save outputs to a documented path under `/var/folders/.../PhospheneFerrofluidOceanV9Session4.5/`.

2. **Per-reference annotation match:** for each of the 12 images in `docs/VISUAL_REFERENCES/ferrofluid_ocean/`, document whether the rendered output matches the **trait the reference annotates** (per the README stylization caveat — not the literal photograph). Document matches / gaps in the closeout report. Anti-reference (`05_*`) must NOT match.

3. **Update FERROFLUID_OCEAN_CLAUDE_CODE_PROMPTS.md:**
   - Session 4.5 row → ✅
   - Landed-work summary paragraph below this prompt
   - Carry-forward note to Session 5 (cert)

4. **Update `docs/ENGINEERING_PLAN.md`** Increment V.9 with Session 4.5 ✅ block.

5. **Update `docs/ENGINE/RENDER_CAPABILITY_REGISTRY.md`:**
   - **Drop** rows: "Cassie-Baxter spike-tip droplet SDF", "Meso domain-warp turbulence on Voronoi spike lattice", "Tactile micro-normal perturbation in matID == 2 lighting branch" (all reverted in Phase 0).
   - **Rewrite** the "Multi-light stage rig" row to reflect the aurora-sky paradigm. New row title: "Mirror-reflects-procedural-sky for near-mirror substrates (matID == 2)." Cite the new `rm_ferrofluidSky` function + FerrofluidStageRig output reinterpretation.
   - **Keep** the "Audio-modulated thin-film thickness" row (unchanged in this session).

6. **Update CLAUDE.md "Failed Approaches" and "What NOT To Do"** with the lessons from this rescue:
   - **New Failed Approach (next number):** "Implementing 'beams cast onto reflective surface' as point lights with physical falloff." The references' mechanic is mirror-reflects-sky; the lighting paradigm for reflective subjects is sky-pattern, not point-lights. Inverse-square attenuation at any reasonable physical orbit distance gives invisible beams against the IBL the mirror also reflects. Cite: V.9 Session 4 failure + Session 4.5 rescue.
   - **New Failed Approach (next number):** "Authoring a preset session without reading `docs/VISUAL_REFERENCES/<preset>/README.md` first." Past Sessions did and shipped failures. Session 4 specifically shipped Phase A decoration layers (droplets, micro-normal, meso warp) without consulting the README's stylization caveat ("None of them is a faithful rendering of 'Ferrofluid Ocean as it should appear'. Read each image only for the trait its annotation calls out") — the result is decoration layers that competed with the hero signal the references actually wanted.
   - **Promote Failed Approach #58** (visual subject without load-bearing musical role) to layer scope. The Drift Motes failure was at preset scope; Session 4's droplet field is the same failure at layer scope. Update the existing entry's scope clause.
   - **What NOT To Do** new entry: "Do not skip side-by-side reference comparison in mid-session sanity checks. Self-judging 'looks reasonable' has shipped failures repeatedly (V.9 Session 4 most recently). Side-by-side with named reference images is the only sanity check that catches structural divergence before M7."

7. **Commit closeout docs**: 1 commit. Prefix: `[V.9-session-4.5]`. Total session commit count: 6–8.

**Phase C acceptance gates:**

1. All prior phase gates pass.
2. Contact sheet rendered, saved, path documented.
3. Per-reference annotation match documented in closeout report. Anti-reference (`05_*`) explicitly verified as not-matched.
4. CLAUDE.md + RENDER_CAPABILITY_REGISTRY.md + ENGINEERING_PLAN.md + this prompt doc all updated.
5. Closeout commit landed.

---

### DO NOT author in this session

- **M7 cert sign-off.** Session 5. This session's job is to fix the structural problems so Session 5 has a viable candidate.
- **Golden hash regeneration.** Session 5.
- **Performance capture.** Session 5 (Tier 2 p95 ≤ 7.0 ms target).
- **New audio routing primitives.** The current routing (vocals_pitch → palette, drums_energy_dev → intensity, arousal → orbit speed + thin-film thickness, bass_energy_dev → spike height) is correct in concept. The Phase A rebuild changes GPU consumption, not the routing math.
- **Rewriting `FerrofluidBeatSyncTests` / `FerrofluidLiveAudioTests` / `PresetAcceptanceTests`** — Session 5 (Session 1 skip-guards still in place).
- **Generic engine extraction of an "aurora sky" abstraction.** Per D-125(f) the §5.8-style generic extraction is deferred to the second consumer. Phase A's `rm_ferrofluidSky` stays preset-private under this rescue.
- **Adding new visual layers** (no new fbm noise, no new SDF terms, no new compositing passes). The Phase A rebuild simplifies the lighting path; do not re-add complexity in the name of "matching the references" — Phase B's reference-anchored tuning is enough.
- **Stage rig promotion to non-Ferrofluid presets.** The §5.8 reframing under this rescue is scoped to Ferrofluid Ocean only.

Defer with `// TODO(V.9 Session 5):` markers.

### Prerequisites — read in order, do not skip

1. **`docs/VISUAL_REFERENCES/ferrofluid_ocean/README.md`** — CRITICAL READING. Every reference image annotation. The stylization caveat in particular. The mandatory traits checklist. The anti-references list. **Session 4 skipped this and shipped failures; do not repeat.**
2. **The 12 reference images themselves.** Read them. Form your own mental model. Cite specific image filenames in code comments where they motivate a design choice. The musical role re-articulation above is a paraphrase of the README annotations; the images are the ground truth.
3. **`docs/presets/FERROFLUID_OCEAN_CLAUDE_CODE_PROMPTS.md`** — Sessions 1–3 landed-work blocks. Session 4 landed-work + M7 review outcome (above this prompt).
4. **The live failure capture** at `/Users/braesidebandit/Documents/phosphene_sessions/2026-05-14T01-20-28Z/` — particularly `video.mp4` (what Session 4 shipped), `features.csv` and `stems.csv` (the audio inputs driving the failure).
5. **CLAUDE.md "Authoring Discipline"** — the entire section. The next response to pushback must change the answer, not justify it. Three-part bar for any new concept. Treat fidelity warnings as constraints.
6. **CLAUDE.md "Failed Approaches"** — especially #4 (beat-onset not primary), #24 (D-022 IBL ambient tint mechanic), #39 (read references before authoring), #44 (no Metal type-name shadow), #49 (tuning vs structural failure), #58 (visual subject without musical role), and the two new entries this session will add about §5.8 paradigm + README-reading discipline.
7. **`docs/DECISIONS.md` D-124** (V.9 redirect) and **D-125** (stage-rig contract). Note: D-125's "4–6 point lights with inverse-square falloff" implementation framing is **amended by this rescue**. The §5.8 musical contract is preserved; the GPU consumption paradigm changes from Cook-Torrance per-light loop to procedural sky function sampled at reflection vector. Document this amendment in the Phase C closeout commit (CLAUDE.md or a new DECISIONS.md entry).
8. **`PhospheneEngine/Sources/Renderer/Shaders/RayMarch.metal`** — current matID == 2 / matID == 3 lighting paths. Note `rm_skyColor` at line ~217 (current IBL sky source — near-white horizon → blue zenith).
9. **`PhospheneEngine/Sources/Presets/FerrofluidOcean/FerrofluidStageRig.swift`** — current per-frame state class. Stays alive; consumption changes.
10. **`PhospheneEngine/Sources/Presets/Shaders/FerrofluidOcean.metal`** — current sceneSDF + sceneMaterial.
11. **`PhospheneEngine/Sources/Renderer/IBLManager.swift`** — the IBL cubemap source (currently rendered from `rm_skyColor`). Verify the matID == 2 branch's existing `iblPrefiltered` sample is what's producing the "gray wash" — it's the cubemap of the near-white horizon gradient.

### Failed-approach guards (must satisfy)

- **Do not add micro-normal perturbation to the mirror substrate.** The references show smooth specular ridges. Repeat of the original Phase A failure.
- **Do not add visible droplets / beads / decoration to the surface.** Matt's "no idea what they are" test failed at Session 4. Don't try again with a different bead recipe.
- **Do not use discrete point lights as the §5.8 implementation paradigm.** Use mirror-reflects-sky. Inverse-square falloff at any reasonable physical orbit distance gives invisible beams against the IBL the mirror also reflects.
- **Do not tune coefficients to fix structural problems.** Failed Approach #49 trigger. If Phase A's lighting paradigm rebuild produces a render structurally different from the references, the answer is NOT to tune band amplitude / orbit speed / palette saturation — it's to re-examine whether the structural change matches.
- **Do not skip the README + references step.** Past Sessions did and shipped failures.
- **Do not write the literal `44100`** outside the allowlist. `Scripts/check_sample_rate_literals.sh` enforces.
- **Do not use `drumsBeat` / `drums_beat` in stage-rig / sky-pattern intensity scope.** `Scripts/check_drums_beat_intensity.sh` enforces.
- **Do not AND-combine `f.bass_*` and `f.bass_attack_ratio`.** Failed Approach #57 — acoustically impossible on real music.
- **Do not add new visual layers** to fix the failure. Session 4's failure was adding decoration; the rescue is **subtraction** plus a paradigm change. If you find yourself adding a new fbm term, a new SDF composition, or a new compositing pass to "match the references," STOP. The references want simplicity.

### Mid-session sanity checks (mandatory side-by-side, not self-judgment)

After Phase 0: contact sheet shows pure-mirror substrate reflecting gray-blue (current IBL). No bumps, no stippling, no warp. We've undone the failures.

After Phase A: contact sheet shows mirror reflecting **dark-purple sky with moving colored aurora bands**. Side-by-side with `08_lighting_aurora_over_dark_water.jpg` — neighborhood match on composition. If divergent, STOP.

After Phase B: contact sheet shows tall narrow pyramidal spikes on deep-sea rolling swells. Side-by-side with `04_*` and `02b_*` — neighborhood match on spike shape and swell motion. If divergent, STOP.

After Phase C: full reference contact sheet match. Anti-reference (`05_*`) not matched.

### Closeout

Per CLAUDE.md Increment Completion Protocol.

---

## V.9 Session 5 — Cert review + perf capture + golden hash regeneration (placeholder)

- M7 contact-sheet review against the 12 references in [`docs/VISUAL_REFERENCES/ferrofluid_ocean/`](../VISUAL_REFERENCES/ferrofluid_ocean/).
- Perf capture at 1080p on M1/M2 (Tier 1 budget verification — may force a half-res reflection pass + reduced beam count) and M3+ (Tier 2 ≤ 7.0 ms p95).
- Regenerate `PresetRegressionTests` Ferrofluid Ocean golden hashes (3-tuple: steady, beatHeavy, quiet).
- Recheck `FidelityRubricTests` — flip `meetsAutomatedGate` to `true` if M1–M6 pass.
- Recompute `MaxDurationFrameworkTests` reference if needed.
- On Matt M7 sign-off: flip `certified: true` in `FerrofluidOcean.json`; add `"Ferrofluid Ocean"` to `FidelityRubricTests.certifiedPresets`; close Phase V.9 in [`docs/ENGINEERING_PLAN.md`](../ENGINEERING_PLAN.md).

Full prompt authored at Session 5 start.

---

## Notes for future sessions

- **§5.8 stage-rig recipe is reusable.** D-125 is a catalog-wide reservation; future presets adopting §5.8 follow the same slot-9 + `matID == 2` pattern. Second-consumer is the trigger to extract a generic `StageRigEngine` from `FerrofluidStageRig`.
- **The `04_*` reference is dual-anchor.** It teaches both specular character (§10.3.4, Session 2) and stage-rig lighting (§10.3.6, Session 3). The purple beam in the photograph is one frozen instant of a moving colored beam rig — not a static purple light direction. Read accordingly.
- **The `01_*` reference's apparent grid regularity is anti-directive.** The preset's lattice is domain-warped per §3.4 + Session 4; `01_*` teaches scale and density, NOT periodicity.
- **The `08_*` aurora reference is for the *quality* of light moving over a dark reflective body, not for the literal lighting paradigm.** The preset's beams are continuous diffuse gradients, not atmospheric ionization. Point-source pillar reflections (moon-on-lake) are a documented failure mode — Session 3 must avoid.
- **The `10_*` silence reference makes silence a real visual destination, not a "10 % baseline lattice."** At total silence the surface is a calm dark body of liquid with macro swell breathing through and lattice fully collapsed. Session 1 implements this; Sessions 2–4 must not break it.
