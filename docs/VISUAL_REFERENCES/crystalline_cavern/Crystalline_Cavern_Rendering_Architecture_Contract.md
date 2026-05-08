# Crystalline Cavern Rendering Architecture Contract

## Purpose

This contract defines the required rendering architecture for Crystalline Cavern. It translates the design spec into implementation constraints, pass responsibilities, debug outputs, acceptance gates, and sequencing rules.

This file is authoritative for implementation. `CRYSTALLINE_CAVERN_DESIGN.md` remains authoritative for visual intent.

> **Visual target reframe (D-096).** All "must read as ..." acceptance gates below are aesthetic-family bars, not pixel-match contracts. A render that reads as belonging in the same visual conversation as the references — real photographic geode interior, biological-not-stylized emission, weathered cavern walls, large soft caustic cells, biological-not-neon palette — passes the gate. A render that reads like the named anti-reference (`09_anti_videogame_crystal_cave.jpg`) fails it. Pixel-fidelity to a particular reference image is an explicit non-goal. Real-time constraints (Tier 2 ~6.5 ms p95) are inviolable; if a fidelity feature cannot be achieved in budget, document the gap and pick the nearest achievable approximation.

## Required passes

`passes: ["ray_march", "post_process", "ssgi", "mv_warp"]` — the D-029-preserved combination with no current consumer. Crystalline Cavern is the first consumer and validates the static-camera ray-march + mv_warp handoff.

| Pass | Name | Required output | Depends on | Debug view required |
|---|---|---|---|---|
| 1 | SCENE_GEOMETRY | G-buffer (depth, normal, albedo, materialID) via `sceneSDF` + `sceneMaterial` | scene uniforms, FeatureVector | Yes |
| 2 | LIGHTING + IBL | Direct-lit + IBL-ambient color buffer, with valence-tinted IBL multiplier (`iblAmbient *= scene.lightColor.rgb`, D-022 path) | SCENE_GEOMETRY + bass/valence audio uniforms | Yes |
| 3 | SSGI | Half-res indirect bounce, additively composited | LIGHTING + IBL | Yes (Tier 2 only; disabled at Tier 1) |
| 4 | ATMOSPHERE | Volumetric height fog + screen-space light shafts + dust mote field + screen-space caustic projection on lit surfaces | SCENE_GEOMETRY + SSGI + audio uniforms (drums, vocals pitch) | Yes |
| 5 | POST_PROCESS | Tone-mapped composite written to `warpState.sceneTexture` | ATMOSPHERE | Yes |
| 6 | MV_WARP_COMPOSE | 32×24 grid feedback accumulator with current scene composited and presented to drawable | POST_PROCESS output (= scene texture) + previous-frame accumulator | Yes |

## Minimum viable milestone (Session 1 scope)

Before any audio routing, materials, or atmosphere, the implementation must support:

- SCENE_GEOMETRY-only debug output (white-on-grey rendering of cavern + crystal cluster + floor crystals + hanging tips, no materials);
- static camera framing matching `01_macro_geode_interior_cathedral.jpg` composition (looking *into* a cathedral cavity);
- SDF tree compiles cleanly: `sd_cavern_walls`, `sd_crystal_cluster` (5 hex-prisms with hash-driven per-instance jitter), `sd_floor_crystals`, `sd_hanging_tips`;
- `worley_fbm(p * 0.6) * 0.08` displacement on cavern walls is visible in normals;
- visual harness contact sheet showing the geometry from the fixed camera position.

`CrystallineCavernSilenceTest` placeholder exists at this milestone; full silence-form-complexity test passes after Session 3 atmosphere wiring.

## Blockers

Crystalline Cavern cannot be certified if any of the following are missing:

- no `ray_march` + `mv_warp` combined render path wired (D-027 mv_warp infrastructure + D-029 preserved-combination handoff via `warpState.sceneTexture`);
- no `mat_pattern_glass` recipe in V.4 cookbook (D-067(b) — pattern variant explicitly chosen over fbm-frost);
- no `mat_polished_chrome`, `mat_frosted_glass`, `mat_wet_stone` recipes in V.3 cookbook;
- no `triplanar_detail_normal` (3-param procedural form) in V.3 MaterialResult;
- no `worley_fbm`, `fbm8`, `ridged_mf` in V.1 noise tree;
- no `ls_radial_step_uv` + `ls_intensity_audio` in V.2 light shafts;
- no `vol_density_height_fog` + `vol_density_fbm` + `vol_sample` in V.2 volume tree;
- no `caustic_pattern` consumer-callable utility in `Volume/Caustics.metal` (V.2, D-055);
- no `SpectralHistoryBuffer` access at fragment buffer(5) for `vocalsPitchNorm` trail;
- no `sceneParamsB.w` repurposing for caustic refraction angle uniform (D-021 boundary classification stability);
- no IBL `iblAmbient *= scene.lightColor.rgb` D-022 path (without it, valence tint shows only on direct-lit surfaces, not propagated through scene);
- no way to capture pass-separated debug output (SCENE_GEOMETRY only / LIGHTING only / ATMOSPHERE only / final composite);
- no anti-reference rejection gate against `09_anti_videogame_crystal_cave.jpg`.

## Certification fixtures

Each acceptance phase must be rendered against the standard fixture set:

- **silence** (`totalStemEnergy == 0`, all `*_rel` and `*_dev` at zero) — verifies §5.8 fallback;
- **steady mid-energy** (`f.mid_att_rel ≈ 0.3`, `f.bass_att_rel ≈ 0.3`, no drum onsets) — verifies continuous primary drivers;
- **beat-heavy** (drum onsets every ~500 ms, `stems.drums_energy_dev` peaks at 0.4) — verifies caustic flash gating ≤ 2× continuous;
- **sustained bass** (`f.bass_att_rel` held high for ≥ 4 s) — verifies IBL breath does not saturate;
- **vocal pitch sweep** (`vocalsPitchNorm` swept 0 → 1 over 4 s with confidence 0.6) — verifies caustic refraction angle modulation reads as continuous pattern shift, not jitter;
- **high-valence** (`f.valence ≈ 0.8`) — IBL skews warm amber;
- **low-valence** (`f.valence ≈ 0.2`) — IBL skews cool magenta-violet;
- **stem warmup** (`totalStemEnergy` ramping 0 → 1 over first 8 s of fixture) — verifies D-019 blend through `smoothstep(0.02, 0.06, totalStemEnergy)`.

## Stop conditions

Stop implementation and report a blocker if:

- `caustic_pattern` utility output is unworkable at the design's specified parameters (cells too small, drift wrong, brightness distribution unmatched against `03_specular_water_caustics.jpg`). Mitigation per design §11.2: fall back to `fbm8(p * 4.0 + time * 0.3)` overlay sampled at floor projection. Document the fallback in commit message and re-evaluate utility in a separate increment.
- Static-camera ray-march + mv_warp produces ghosting at the design's `disp_amplitude = 0.002`. The preserved-combination is unvalidated until Crystalline Cavern ships; if ghosting is observed, reduce amplitude before reducing other features. The 0.003 hard ceiling per D-029 must not be exceeded.
- Material boundary stability test (`CrystallineCavernMaterialBoundaryTest`) fails — sweeping camera across material boundaries produces flicker. This indicates `sceneMaterial` `matID` classification is unstable across SDF iso-distance ties; fix with explicit epsilon ordering in the cluster SDF before continuing.
- Per-frame `vocalsPitchNorm` modulation rate produces visible jitter on rapid melodic phrases (open question — same mitigation as Aurora Veil: 5-frame smoothing window on the SpectralHistoryBuffer read).
- The visual harness cannot capture pass-separated outputs (SCENE_GEOMETRY only / LIGHTING only / ATMOSPHERE only) — required for diagnostic review at each session boundary.
- Performance exceeds Tier 2 budget at the specified scene complexity (5 cluster crystals + ~20 floor crystals + 4 cavern walls + 32-step march + SSGI). Mitigation order: (1) reduce SSGI to half-rate, (2) drop dust motes, (3) reduce cluster count to 4, (4) drop SSGI entirely (Tier 1 path).

## Acceptance gates per phase

**Session 1 — Scene structure (no materials).**
- SCENE_GEOMETRY-only debug renders cavern + crystal cluster + floor + hanging tips correctly.
- Static camera composition reads as "looking into a cavity" against `01_macro_geode_interior_cathedral.jpg`.
- `worley_fbm` wall displacement visible in normals.
- Per-instance hash-driven jitter on hex-prism cluster (no two crystals identical).
- `mv_warp` accumulating without smearing at conservative parameters.

**Session 2 — Materials pass.**
- `mat_pattern_glass` wired on foreground crystals — cellular voronoi pattern reads against `06_specular_pattern_glass_closeup.jpg`.
- `mat_wet_stone(0.4)` on walls + `mat_wet_stone(0.55)` on floor base — surface character reads against `04_micro_wet_limestone_wall.jpg`.
- `mat_polished_chrome` on sparse floor accents with anisotropic streaks visible in highlights.
- `mat_frosted_glass` on hanging tips — milky-cloudy character distinct from clear pattern glass.
- `triplanar_detail_normal` on cavern walls — no uniplanar stretching on oblique faces.
- `CrystallineCavernMaterialBoundaryTest` passes (no flicker on material boundary sweeps).

**Session 3 — Lighting + atmosphere + caustics.**
- §5.3 bioluminescent recipe wired — minimal direct light + IBL ambient + emission carries the work.
- `iblAmbient *= scene.lightColor.rgb` (D-022 path) verified by valence-tint propagating across all surfaces, not only direct-lit.
- `vol_density_height_fog` ground fog visible at floor altitude.
- `ls_radial_step_uv` light shafts visible from upper-right at sun UV (0.7, 0.95).
- Dust mote field accumulating along view ray, visible mainly inside shaft volume.
- `caustic_pattern` projection on cavern walls + floor — cell scale and drift speed read against `03_specular_water_caustics.jpg`.
- Caustic gated by `surface_lighting` so caustics only appear on lit surfaces (not in shadow).
- Crystal emission visible against dark IBL ambient — emission character reads against `05_palette_bioluminescent_cave.jpg` (biological, not neon).

**Session 4 — Audio routing + mv_warp + cert.**
- All audio routes wired per design §5.6 — `f.bass_att_rel`, `f.mid_att_rel`, `f.valence`, `f.beat_phase01`, `stems.drums_energy_dev`, `stems.vocalsPitchNorm`, `stems.vocalsPitchConfidence`.
- `CrystallineCavernSilenceTest` passes (form complexity ≥ 4 at `totalStemEnergy == 0`).
- `CrystallineCavernCausticBeatRatioTest` passes (peak caustic luma ≤ 2× steady caustic luma).
- `CrystallineCavernMvWarpStaticityTest` passes (sequential frame mean-luma drift < 5% at constant audio — warp is shimmer, not motion drift).
- D-019 stem warmup verified — first ~10 s of every fixture renders with FeatureVector fallbacks for `vocalsPitchNorm` and `drums_energy_dev`.
- D-026 deviation primitives verified by `FidelityRubricTests` — no absolute thresholds anywhere in shader.
- Performance profile: p95 ≤ Tier 2 6.5 ms / Tier 1 4.85 ms across all fixtures.
- M7 review against `01`, `02`, `04`, `05`, `06` — passes aesthetic-family bar per D-096.
- Anti-reference gate: rendered output does NOT read like `09_anti_videogame_crystal_cave.jpg`. If it does, return to Session 3 emission/caustic palette tuning (likely cause: emission saturation too high, or caustic colors not picking up valence tint from IBL).
- `certified: true` flipped in JSON sidecar after all gates pass.

## Preset-specific tests (per design §8)

| Test | Verifies | Passes when |
|---|---|---|
| `CrystallineCavernSilenceTest` | §5.8 silence fallback | At zero audio, luma histogram has ≥ 4 distinct bins above noise floor (cavern + cluster + floor + shaft + motes) |
| `CrystallineCavernCausticBeatRatioTest` | Audio Data Hierarchy continuous-vs-accent ratio | With steady mid energy + pulsed drums, peak caustic luma ≤ 2× steady caustic luma |
| `CrystallineCavernMaterialBoundaryTest` | D-021 boundary classification stability | Camera swept across material boundaries shows no flicker between adjacent material IDs |
| `CrystallineCavernMvWarpStaticityTest` | D-029 static-camera mv_warp behavior | At constant audio, sequential frame mean-luma drift < 5% (warp produces shimmer, not drift) |
