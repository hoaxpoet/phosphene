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
| V.9 Session 3 | §5.8 stage-rig lighting recipe (implements D-125: slot-9 buffer + `matID == 2` dispatch + FerrofluidStageRig Swift class) | ⏳ Not started |
| V.9 Session 4 | Audio routing (meso domain warp + micro detail noise + droplet beading + all D-026 deviation routing finalized) | ⏳ Not started |
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

## V.9 Session 3 — §5.8 stage-rig lighting (D-125 end to end)

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

## V.9 Session 4 — Audio routing + meso/micro detail layers (placeholder)

Implements:

- Meso: `warped_fbm` domain-warp of spike-center positions per §3.4 + §10.3.2; flow velocity driven by `stems.drums_beat` rising edges. References `02_meso_lattice_defects.jpg` + `02c_meso_excited_water_specular.jpg`.
- Micro: `fbm8(p * 15.0)` normal perturbation amplitude 0.02 per §10.3.3; hash-lattice micro-droplets at spike tips on high amplitude per `03_*` / `03b_*` (Cassie-Baxter beading).
- Audio routing finalization: nine-route mapping documented in [`docs/VISUAL_REFERENCES/ferrofluid_ocean/README.md`](../VISUAL_REFERENCES/ferrofluid_ocean/README.md) "Audio routing notes" — all D-026 deviation primitives or D-022 mood-valence; no absolute-threshold patterns; no `*_beat` rising edges except where explicitly accent-only.
- Triplanar texturing on non-planar spike walls per §12.2 (`triplanar_normal` from `Utilities/PBR/Triplanar.metal`).
- Detail normals via `combine_normals_udn` from `Utilities/PBR/DetailNormals.metal`.

Full prompt authored at Session 4 start.

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
