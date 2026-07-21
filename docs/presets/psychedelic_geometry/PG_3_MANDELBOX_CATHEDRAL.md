# PG.3 — Mandelbox Cathedral

**One combined doc: Part A is the committed design; Part B is the runnable Claude Code session prompt.** Read `PG_0_OVERVIEW.md §3 (audio contract)` and `§4 (JSON conventions)` alongside this. Working name — rename freely.

> **This is the highest-fidelity, highest-risk preset in the phase.** It is `full`-rubric 3D ray-march. It carries its own risk budget: the arc in §A9 is deliberately multiple increments (macro → materials → lighting/atmosphere → secondary audio → cert), like Ferrofluid Ocean. Part B scopes **only the macro geometry + hero audio** increment (PG.3.1). Do not attempt the whole preset in one session.

---
---

# PART A — DESIGN

## A0. Identity

- **Name (working):** Mandelbox Cathedral
- **Family:** `geometric` (or `fractal`) · **concept_tags:** `["fractal","geometric","cavern"]` · **motion_paradigm:** `ray_march_static`
- **Passes (target):** `["ray_march","ssgi","post_process"]` (SSGI and full lighting arrive in later increments; PG.3.1 may ship `["ray_march","post_process"]` and add SSGI in PG.3.3)
- **One-line pitch:** A vast 3D fractal cathedral — fold-and-scale iteration builds endless architecture out of self-similar copies of itself — that unfolds deeper chambers as the bass swells and turns with the melody, while the camera holds perfectly still.

## A1. Concept-viability gate (`SHADER_CRAFT.md §2.0`)

**Gate 1 — Musical role (the sentence):**
> *As the sustained bass swells, the fractal's fold-scale opens, revealing deeper nested chambers; and the vocal melody's pitch twists the fold rotation so the whole cathedral turns with the tune — the listener pairs the low-end sustain with the architecture opening up, and the melodic line with the structure rotating.*

Two specific features (sustained bass envelope; vocal pitch contour) each paired with a specific behaviour (chambers unfolding; the structure rotating). It passes. The camera is fixed — **the geometry itself is the motion**, which is the whole point of this preset and the reason it belongs to the harmonic-morph strategy rather than to a fly-through.

**Gate 2 — Iconic subject deliverable at fidelity (be honest here):** Reachable, but this is the fidelity-risk preset of the phase, so it is scoped and referenced accordingly. In favour: (a) 3D distance-estimated fractals (Mandelbox / KIFS / Mandelbulb) are a *heavily solved* register with canonical published distance estimators and rendering recipes — this is exactly the "read and port the reference, do not derive" case (FA #73); (b) Phosphene already ships ray-march SDF presets with PBR + IBL (Glass Brutalist, Kinetic Sculpture) and the utility tree already contains `sd_mandelbulb_iterate` and the material cookbook; (c) fractals give the four-scale detail cascade *for free* — self-similarity is detail at every octave. The honest constraint: this needs its own increment budget and disciplined reference-porting, not one heroic session. We build to the achievable bar — a legible fractal architecture with real lighting and 2–3 materials — not to "a specific artist's Fragmentarium masterpiece."

**Gate 3 — Infrastructure-feasible:** Yes. `ray_march` + G-buffer + PBR lighting + SSGI + `post_process` are all shipped; `sceneSDF`/`sceneMaterial` with matID dispatch is the standard authoring surface; the slot-8 `LumenPatternState` placeholder contract is handled by the engine for non-Lumen presets. No new passes or contract. The only "new" thing is the Mandelbox DE, which is a `sceneSDF` body.

## A2. Visual target & the four-scale nested detail cascade (natural for a fractal)

The "smaller shapes making larger shapes" is the *definition* of the object: a distance-estimated fractal builds macro architecture out of self-similar folded copies.

1. **Macro.** The fractal's gross silhouette — cathedral-scale chambers, arches, and vaults formed by the Mandelbox/KIFS fold. Readable composition: a central chamber the camera looks into, walls receding into fractal depth.
2. **Meso (box-fold ledges / chambers).** The second-iteration structures — ledges, niches, repeating architectural motifs that tile the chamber walls (think muqarnas / fan-vault ribs).
3. **Micro (deeper iteration).** Self-similar sub-chambers and filigree from the deeper DE iterations (capped for budget). This is where the "shapes inside shapes" reads at close range.
4. **Specular / breakup.** PBR materials from the cookbook (`mat_polished_chrome` / `mat_frosted_glass` / `mat_wet_stone` / `mat_marble`), **thin-film iridescence on the fold edges** (`thinfilm_rgb`) for the psychedelic shimmer, roughness variation, specular breakup, and atmospheric aerial perspective into the depths.

This is a **full-rubric** preset: ≥ 4 noise octaves (the fractal supplies self-similar octaves; add a `fbm`/triplanar detail wash on surfaces), ≥ 3 distinct materials, detail cascade on every primary surface, atmosphere, mood-tinted IBL.

**Mechanic (author's guide — PORT, don't derive; FA #73):** implement the **Mandelbox distance estimator** (box fold → sphere fold → scale, iterated) as the `sceneSDF` body, porting a canonical published DE (Syntopia / Knighty). KIFS (fold + rotate + scale, producing temple/cathedral forms) is an equally valid alternative; the author may prototype both and pick the one that reads more "cathedral." `sd_mandelbulb_iterate` in the Geometry tree is a related reference. The fractal's `scale`/`minRadius` parameters are the ones the bass morphs; a fold-rotation matrix is what the melody twists.

## A3. Motion & 30-second temporal contract

- **Camera holds still.** No dolly, no flythrough (D-029 `ray_march_static`). The motion the viewer sees is the *fractal transforming*: it unfolds, turns, and shimmers in place.
- **Bass unfolds structure (hero).** `bass_att_rel` drives the Mandelbox `scale`/fold parameter slowly: a bass swell opens the fold, revealing deeper nested chambers; a lull closes it toward a simpler form. This is a genuine *geometric* morph, not a colour trick.
- **Melody turns the cathedral (hero #2).** `vocals_pitch_hz` (confidence-gated) rotates the fold — the whole structure turns with the melodic contour. On instrumental passages it falls back to a slow `other_energy_dev`/time drift so it never freezes.
- **Emission breathes with arousal; edges shimmer on drum accents** (bounded, thin-film shimmer on fold edges only — steady global luminance, D-157).
- **Over 30 s:** a still cathedral that is clearly *listening* — opening on the sustained low end, turning with the tune, glinting on the beat. Distinct from every other preset in the phase because *the geometry itself is the instrument's mirror*.

## A4. Audio-routing table (one primitive per layer — FA #67)

| Visual layer | Primitive | Timescale | Role |
|---|---|---|---|
| **Fold scale / unfold depth** | `f.bass_att_rel` | continuous / slow | **HERO** — bass opens deeper chambers |
| **Fold rotation / twist** | `stems.vocals_pitch_hz` (gate `vocals_pitch_confidence ≥ 0.6`; **fallback** `stems.other_energy_dev`) | melodic / medium | **HERO #2** — the cathedral turns with the tune |
| **Emission / IBL breath + bloom** | `f.arousal` | slow | energy brightens the space |
| **Material hue / thin-film phase** | `f.spectral_centroid` (valence tints IBL, D-022) | slow | colour temperature |
| **Fold-edge shimmer accent** | `stems.drums_energy_dev_smoothed` | per-beat (enveloped, bounded) | glint on edges only; steady global luminance |

**Self-check:** five layers, five distinct primitives. `bass_att_rel` and `arousal` are both slow-continuous but are different primitives on different channels (geometry vs light) — allowed. Only one onset-envelope layer (drum shimmer), bounded. The pitch layer is gated with a fallback so it is never dead. No two layers share a primitive/timescale. (`valence` on the hue layer is the standard D-022 mood tint on IBL ambient — a slow secondary colour modulation on top of the `spectral_centroid` phase, not a competing motion driver; it is colour-only, so it does not violate one-primitive-per-*motion*-layer.)

**Liveness:** `bass_att_rel`, `arousal`, `spectral_centroid` reliably alive. `drums_energy_dev_smoothed` alive (non-strobing). **`vocals_pitch_hz` only when `vocals_pitch_confidence ≥ 0.6`** — the fallback (`other_energy_dev`) covers instrumental/low-confidence audio. Apply the `smoothstep(0.02, 0.06, totalStemEnergy)` stem-warmup crossfade (D-019) so the first ~10 s (pre-live-stems) still routes sensibly.

## A5. Silence state (D-037)

At `totalStemEnergy == 0`: a **dim ambient cathedral at rest fold-scale**, cool mood-tinted IBL, a slow ambient glow and gentle fog into the depths, non-black (fog + IBL floor). The fractal holds a legible resting form; nothing strobes.

## A6. Palette & lighting

Single-directional key + strong mood-tinted IBL (`SHADER_CRAFT.md §5.2`), `scene_ambient ≈ 0.06`, IBL ambient multiplied by `lightColor.rgb` so D-022 mood valence shifts the whole scene (FA #47). Thin-film iridescence on fold edges is the psychedelic-colour signature. Aerial-perspective fog matched to palette (not grey — FA #39). Keep pale-tone share ≤ 30 %.

## A7. Reference sourcing (curate before Part B runs — Matt-owned)

Populate `docs/VISUAL_REFERENCES/mandelbox_cathedral/` and write its `README.md`. Shopping list:

- `01_macro_fan_vault.jpg` — **real photo** of gothic fan-vaulting or a cathedral interior looking up into the vault (the macro architectural read).
- `02_meso_muqarnas.jpg` — **real photo** of Islamic muqarnas (honeycomb vaulting) or Sagrada Família columns — literally fractal architecture; the meso nested-niche read.
- `03_micro_geode.jpg` — **real photo** of a crystal geode / cave interior — self-similar micro sub-chambers + material character.
- `04_specular_polished_stone.jpg` and `06_palette_stained_glass_light.jpg` — **real photos** for material specular + the jewel/light palette.
- `07_atmosphere_god_rays.jpg` — **real photo** of light shafts through a cathedral (aerial perspective / god rays).
- **Porting references (READ AND PORT before coding — FA #73):** Mikael Hvidtfeldt Christensen (Syntopia) Mandelbox/Mandelbulb writeups + Fragmentarium; Knighty's KIFS; Inigo Quilez "Rendering fractals with distance estimation" + the Mandelbulb article; a canonical Mandelbox/KIFS Shadertoy (cite its ID in the shader header). These define the DE — do not first-principles it.
- `05_anti_flat_fractal_AIGEN.jpg` (`_AIGEN` only here) — the failure mode: a flat 2D Mandelbrot-zoom look with no 3D depth or lighting; also anti: over-iterated noisy mush with no readable architecture.

## A8. Performance & tier

Heaviest preset in the phase. Mandelbox DE cost scales with iteration count and march steps; SSGI is half-res; `post_process` bloom. Target ≤ 7 ms p95 Tier-2. **Tier-1 degradation plan:** fewer DE iterations, reduced march steps, SSGI off (the `FrameBudgetManager` ladder does the last two automatically; the DE iteration cap is a preset-side `stepCountMultiplier`-style parameter). Profile early and often. Full rubric.

## A9. Fidelity-uplift arc (multi-increment — this is expected)

- **PG.3.1 (Part B, this session) — macro geometry + hero motion:** Mandelbox DE `sceneSDF` + one clay-maquette material + basic key+IBL lighting + `bass_att_rel` fold-scale morph + `vocals_pitch_hz` fold-rotation (gated + fallback) + non-black silence. Renders, reads as a fractal cathedral, morphs with bass, turns with melody. This is a "clay maquette" per `SHADER_CRAFT.md §2.2` — not yet pretty, but structurally correct and musically alive.
- **PG.3.2 — materials + thin-film:** matID dispatch across ≥ 3 cookbook materials + thin-film iridescence on fold edges + roughness/detail-normal breakup.
- **PG.3.3 — lighting + atmosphere + SSGI:** mood-tinted IBL, aerial-perspective fog, god-rays, SSGI; the "2026 test" pass.
- **PG.3.4 — secondary audio + cert:** arousal emission breath, drum edge-shimmer, centroid hue, perf tuning, Tier-1 degradation, M7 + cert.

## A10. JSON sidecar sketch

```jsonc
{
  "name": "Mandelbox Cathedral", "family": "geometric",
  "concept_tags": ["fractal","geometric","cavern"], "motion_paradigm": "ray_march_static",
  "passes": ["ray_march","post_process"],            // add "ssgi" at PG.3.3
  "duration": 30,
  "scene_camera": { "position": [0, 0, -3.2], "target": [0, 0, 0], "fov": 60 },  // FIXED
  "scene_lights": [{ "position": [3, 4, -2], "color": [1.0, 0.95, 0.9], "intensity": 3.0 }],
  "scene_fog": 0.02, "scene_ambient": 0.06,
  "stem_affinity": { "bass": "fold_scale", "vocals": "fold_rotation", "drums": "edge_shimmer", "other": "rotation_fallback" },
  "certified": false, "rubric_profile": "full",
  "complexity_cost": { "tier1": 5.0, "tier2": 7.0 },   // measure and correct at implementation
  "visual_density": 0.8, "motion_intensity": 0.5,
  "color_temperature_range": [0.2, 0.8], "fatigue_risk": "medium",
  "transition_affordances": ["crossfade","morph"],
  "section_suitability": ["ambient","buildup","peak","bridge","comedown"]
}
```

---
---

# PART B — SESSION PROMPT (PG.3.1)

## Increment PG.3.1 — Mandelbox Cathedral macro geometry + hero audio (preset increment)

**Objective:** After this session, Phosphene has a new `ray_march` preset "Mandelbox Cathedral" whose `sceneSDF` is a ported Mandelbox distance estimator rendered as a single-material clay maquette with basic key + IBL lighting and a fixed camera; the fractal fold-scale unfolds with `bass_att_rel` and the fold rotation twists with `vocals_pitch_hz` (confidence-gated, with an `other_energy_dev` fallback); a non-black ambient cathedral renders at silence. Registered, compiling, loading, golden-hashed, perf-profiled. `certified` stays `false`. Later increments (PG.3.2–PG.3.4 in `§A9`) add materials, thin-film, SSGI, atmosphere, secondary audio, and cert. This is the "clay maquette" stage of `SHADER_CRAFT.md §2.2`.

## 1. Skills to invoke (in order)
- **`preset-session`** — before any `.metal` / sidecar edit.
- **`shader-authoring`** — before any GPU code. **Heed FA #73 hard:** read and port the published Mandelbox DE; do not derive it from first principles or tune your way to it.
- **`closeout`** — at the end.

## 2. Read-first (exact, ordered)
1. `PG_3_MANDELBOX_CATHEDRAL.md` (this doc — Part A is the design of record; §A2 mechanic + §A7 porting refs are mandatory).
2. `docs/VISUAL_REFERENCES/mandelbox_cathedral/README.md` and every image; the cited porting references (Syntopia/Knighty/IQ + the Shadertoy DE).
3. `docs/ARCHITECTURE.md §GPU Contract Details` — G-buffer layout, matID dispatch, `sceneSDF`/`sceneMaterial` signatures, the slot-8 `LumenPatternState` placeholder contract (non-Lumen presets receive the zero placeholder and `(void)lumen;`).
4. `docs/SHADER_CRAFT.md §7` (SDF craft — displacement Lipschitz safety §7.2, tetrahedral normals §7.3, adaptive march §7.4, per-primitive matID §7.5), `§4` (materials, for the maquette material), `§5.1/§5.2` (lighting), `§9` (perf budget).
5. `PhospheneEngine/Sources/Presets/Shaders/KineticSculpture.metal` and `GlassBrutalist.metal` — reference ray-march presets (`sceneSDF`/`sceneMaterial` structure, FOV-in-degrees convention).
6. `PhospheneEngine/Sources/Renderer/Shaders/RayMarch.metal` (the shared deferred lighting/composite) and `PresetLoader+Preamble.swift` (the `rayMarchGBufferPreamble`, `sceneSDF`/`sceneMaterial` forwarding).
7. The Geometry utility tree entry for `sd_mandelbulb_iterate` (a related DE reference) and `op_blend`/`ray_march_adaptive`/`ray_march_normal_tetra`.

## 3. Pre-flight invariants (a failed check stops the session)
- `git status` clean on `main`; `swift test --package-path PhospheneEngine` green.
- `docs/VISUAL_REFERENCES/mandelbox_cathedral/` populated per `§A7` + `README.md` written. **If not, curate first (Matt-owned) or stop.**
- `docs/ENGINEERING_PLAN.md` has a Phase PG / PG.3.1 row.
- Confirm the production preset count for `PresetLoaderCompileFailureTest` to bump by exactly 1.
- Confirm `TestSphere`-style ray-march compile/render harness is reachable (you will test the DE in it first, per §2.2 coarse-to-fine).

## 4. Tasks (each has a done-when)
1. **Plan + scaffold.** Add the PG.3.1 row to `ENGINEERING_PLAN.md`. Create `Shaders/MandelboxCathedral.metal` + `MandelboxCathedral.json` (sidecar per `§A10`, `passes: ["ray_march","post_process"]`) + register + bump `expectedProductionPresetCount`. Provide `sceneSDF` and `sceneMaterial` (single matID 0, one maquette material). **Done-when:** app + engine build; `PresetLoaderCompileFailureTest` passes at the new count; preset loads and renders *something* in the ray-march path.
2. **Port the Mandelbox DE.** Implement the Mandelbox distance estimator in `sceneSDF` by porting the cited reference (§A7). Static fold parameters for now. Fixed camera per sidecar. **Done-when:** a `RENDER_VISUAL=1` contact sheet shows a legible 3D fractal cathedral (readable chambers/arches with depth), non-black, correct normals (no faceting/holes — verify with the tetrahedral-normal path and a Lipschitz-safe DE, §7.2/§7.3).
3. **Maquette material + basic lighting.** One cookbook material (e.g. `mat_wet_stone` or `mat_marble`) via `sceneMaterial`; single key light + IBL ambient at `scene_ambient 0.06`; palette/mood tint on IBL (FA #47). No thin-film/SSGI yet. **Done-when:** the contact sheet reads as a lit stone/marble cathedral, not a flat silhouette; shadowed depth is visible.
4. **Hero motion — fold-scale morph.** Drive the Mandelbox `scale`/fold parameter from `f.bass_att_rel` (slow, sustained). Apply the `smoothstep(0.02,0.06,totalStemEnergy)` warmup (D-019). **Done-when:** a contact sheet across low vs high bass shows the fractal visibly unfolding deeper chambers at high bass and simplifying at low bass; the change is *geometric*, verified in a multi-frame ray-march test (G-buffer → lighting → composite path, per `PRESET_SESSION_CHECKLIST.md` Part 2).
5. **Hero motion — fold rotation.** Drive a fold-rotation matrix from `stems.vocals_pitch_hz`, gated at `vocals_pitch_confidence ≥ 0.6`, fallback to `stems.other_energy_dev` (or a slow time drift) below the gate. **Done-when:** on a vocal fixture the structure rotates with pitch; on an instrumental/low-confidence fixture it still turns slowly (fallback), never freezes; verified in the multi-frame test.
6. **Silence state.** Verify `§A5`: dim ambient cathedral at rest fold-scale, non-black, no strobe. **Done-when:** the silence contact sheet is non-black and shows a legible resting fractal.
7. **Audio routing review.** Deviation primitives + gated pitch only; one primitive per layer; liveness note in the shader header. **Done-when:** `grep` finds no absolute-threshold pattern; routing matches the PG.3.1 subset of `§A4` (fold-scale + fold-rotation only — emission/hue/shimmer are PG.3.4).
8. **Performance.** `PresetPerformanceTests` on silence/steady/beat-heavy; record p50/p95/p99; confirm the DE iteration cap keeps Tier-1 within budget (or note the required cap). **Done-when:** Tier-2 p95 ≤ 7 ms (or a documented plan to reach it in PG.3.3 when SSGI lands); numbers recorded.
9. **Golden hash — STOP AND REPORT.** Register the golden 3-tuple; do NOT touch other goldens. Produce the M7 "clay maquette" contact sheet. **Done-when:** new golden passes; then **stop and report** — explicitly noting this is the maquette stage and materials/lighting/atmosphere are PG.3.2–PG.3.3.
10. **Closeout.** Invoke `closeout`; 8-part report with the verbatim evidence block, the ray-march dispatch-path statement, the fold-scale/fold-rotation firing evidence, perf numbers, and the PG.3.1 plan-row status.

## 5. Do-NOT
- **Do not first-principles the DE** (FA #73/#64) — port the cited published Mandelbox/KIFS reference. Iterating tuning constants toward a fractal the literature already specifies is the forbidden pattern.
- **No absolute thresholds** (D-026 / FA #31); **gate `vocals_pitch_hz` at confidence ≥ 0.6** with a fallback (it was structurally 0 for months pre-PT.1; never trust it ungated).
- **No camera dolly / flythrough** (D-029 `ray_march_static`) — the camera is fixed; the geometry is the motion. Do not add `mv_warp` in this increment (it may smear fractal detail; it is a *later* optional exploration, and only valid because the camera is static).
- Do not route two visual motion layers to the same primitive/timescale (FA #67) — hold the PG.3.1 subset of `§A4` (fold-scale + fold-rotation) cleanly.
- Do not build materials beyond the one maquette material, thin-film, SSGI, atmosphere, or the secondary audio layers — those are PG.3.2–PG.3.4. Keep this increment to macro geometry + hero motion.
- Do not flip `certified`; do not regenerate other goldens; do not commit out-of-scope files.

## 6. Verification commands
```
swiftlint lint --strict --config .swiftlint.yml
xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build 2>&1
swift test --package-path PhospheneEngine 2>&1
swift test --package-path PhospheneEngine --filter "PresetLoaderCompileFailureTest|MandelboxCathedral|RayMarchPipeline|PresetRegressionTests"
RENDER_VISUAL=1 swift test --package-path PhospheneEngine --filter PresetVisualReview 2>&1
swift test --package-path PhospheneEngine --filter PresetPerformanceTests 2>&1
```

## 7. Commit message templates (small commits; local `main`; push only on Matt's "yes, push")
- `[PG.3.1] Presets: scaffold Mandelbox Cathedral (ray_march) + JSON + registration`
- `[PG.3.1] Mandelbox Cathedral: port Mandelbox distance estimator into sceneSDF (ref <shadertoy/Syntopia>)`
- `[PG.3.1] Mandelbox Cathedral: maquette material + key/IBL lighting`
- `[PG.3.1] Mandelbox Cathedral: bass_att_rel fold-scale morph (D-019 warmup)`
- `[PG.3.1] Mandelbox Cathedral: vocals_pitch fold-rotation (conf-gated ≥0.6 + fallback)`
- `[PG.3.1] Mandelbox Cathedral: golden hash + perf profile + ENGINEERING_PLAN row`

## 8. Closeout format
Invoke `closeout`; 8-part report with the verbatim `Scripts/closeout_evidence.sh` block as §2. Increment-specific additions: (a) the ray-march dispatch path the multi-frame tests exercised (G-buffer → lighting → composite); (b) fold-scale + fold-rotation firing evidence (low-vs-high-bass geometry delta; pitch-vs-fallback rotation on a vocal vs instrumental fixture); (c) perf p50/p95/p99 + the DE iteration cap and Tier-1 plan; (d) the maquette-stage M7 contact-sheet path; (e) explicit statement that materials/thin-film/SSGI/atmosphere/secondary-audio are deferred to PG.3.2–PG.3.4.

## 9. DECISION-NEEDED (surface to Matt at review, product-level)
- **Which fractal reads more "cathedral"?** *Options:* **Mandelbox** (boxy chambers/ledges — architectural, recommended) vs **KIFS** (folded temple/spire forms — more ornamental). *Recommendation:* prototype both cheaply in the maquette, show Matt a frame of each, pick at review. *Default if silent:* Mandelbox.
- **Camera: dead-still vs. a very slow auto-orbit.** *Options:* **Dead-still** (purest "geometry is the motion," recommended, safest under D-029) vs **a very slow orbit** (more hypnotic, but edges toward fly-through). Note: choosing the orbit is not an in-paradigm tuning knob — camera motion reclassifies the preset out of `ray_march_static` toward `camera_flight`, so it must be justified as a paradigm change, not slipped in. *Recommendation/default:* dead-still for v1; revisit only if the still frame feels inert at M7.
- **Fidelity scope acknowledgement.** This is the multi-increment preset. Confirm the PG.3.1 deliverable is understood as a *clay maquette* (structurally correct + musically alive, not yet beautiful) so the M7 review judges it on that bar, not the final bar.
