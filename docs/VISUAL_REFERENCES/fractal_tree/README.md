# Visual References — Fractal Tree

**Family:** fractal
**Render pipeline:** `["mesh_shader"]` — object → mesh → fragment via `MeshGenerator.draw`; flat HSV, no lighting, no G-buffer
**Rubric:** lightweight — stylized 2D graphic (exempt from full detail-cascade + material-count requirements)
**Last curated:** 2026-08-03 by Matt (FTR.1 / D-212)

> **Read this before the checklist trips you up.** The painterly reference set that used to live here — 14 images of bark, translucent foliage, golden-hour light and autumn palettes — **moved to `../goldengrove/`** when the V.10 uplift was cancelled at D-212. It described a preset Fractal Tree is deliberately not becoming. Do not go looking for it here and do not port it back.
>
> **There is currently no curated image set for this preset, and FTR.2 was built without one.** `PRESET_SESSION_CHECKLIST.md` Part 1 §1 offers two routes — curate first, or escalate to Matt. It was escalated and **Matt resolved it on 2026-08-03: build without reference images, live review at M7 (FTR.5).** The stylization contract and the five anti-references below were the visual authority for the FTR.2 routing rebuild; the look verdict is deferred to that live review. Do not add image files here under version control — LFS.2 untracked them deliberately to stop the Git-LFS bill.

## Reference images

| File | Annotation (what to learn from this image) |
|---|---|
| *(none yet)* | Curation pending — FTR.2 prerequisite. |

### What a reference set here would need to show

The register is **flat, graphic, diagrammatic** — closer to a botanical plate, a Milkdrop line-figure, or a plotter drawing than to a photograph of a tree. Slots worth filling, in priority order:

1. **Graphic branch-fan silhouette** — a recursive tree read as *line and shape*, not as surface. The whole subject in one flat value range.
2. **Asymmetric L-system parameter card** — branching angle and proportional reduction, same role as the old `02_macro_branching_params.jpg`. This one trait survives the redirect: **branching angle ∈ [15°, 25°], proportional reduction ∈ [0.62, 0.68]** matched the crown form we want and the current shader sits at 22° / 0.62.
3. **Flat-colour palette anchor** — a limited palette that stays legible when branches overlap at 60 % alpha.
4. **Anti-reference: bilateral symmetry** — the retired `14_anti_reference.png` (`symmetric-fractal-tree.png`) is still exactly right for this preset. Perfect mirror symmetry, uniform thickness, identical sub-trees. Triggers Failed Approach #44.
5. **Anti-reference: accidental realism** — anything with rendered bark, volumetric light, or foliage mass. That is Goldengrove's job; here it is a failure.

## Stylization contract

What DOES matter for this preset (substitute for the full rubric):

- [x] **Color modulation:** leaf/tip hue tracks harmonic movement (`tonal_phase_fifths`), not a wall clock. ✅ FTR.2 — the `fract(t * 0.006)` term is gone; hue now swings 41.9°–87.4° on harmony alone.
- [x] **Audio coverage:** each visual layer on its own *distinct* primitive (FA #67). ✅ FTR.2 — five layers, five primitives, replacing three-layers-on-`bass_att`.
- [x] **Readability at silence:** a sparse, still, non-black tree — trunk plus the first two generations, legible and clearly alive (D-037). ✅ FTR.2 — `bass_dev` is 0 at silence → the 7-branch rest tree; mean luma 0.0046, gated in `FractalTreeMeshRenderTest`.
- [x] **Readability at peak energy:** a full canopy that still reads as a *tree*, not a solid mass. Branch count must not flat-top. ✅ FTR.2 — the soft knee `bd/(bd+0.12)` is asymptotic, so the 63 ceiling is unreachable by construction; measured max 48. Was pinned at 63 on 1.24 % of frames.

*(Every box above is an automated or measured check. The one thing no box can carry is whether it LOOKS right — that is L4, and it is Matt's live M7 call at FTR.5.)*

## Anti-references

What this preset must NOT look like:

- **Perfect bilateral symmetry** — mirror-image sub-trees at every recursion (FA #44). Break with per-branch hash jitter.
- **Uniform branch thickness** at a given depth — vary per-branch.
- **A rendered/painterly tree** — bark texture, leaf mass, volumetric light. That register belongs to Goldengrove; producing it here is the failure, not the goal.
- **A colour-cycling wallpaper** — hue drifting on a timer while the music does something else.
- **A tree that flat-tops** — visibly pinned at maximum branch count through a whole chorus.

## Audio routing notes

**Shipped routing — MEASURED, as rebuilt at FTR.2.** Five visual layers, five distinct primitives (FA #67). Swing figures are p05→p95 on four sources: session `2026-08-03T20-05-13Z` (*Hummer*, 7260 frames after warmup, chain verdict `clean`) plus the three `route_coverage` fixtures.

| Layer | Primitive | Measured swing (Hummer / love_rehab / so_what / there_there) | Was |
|---|---|---|---|
| canopy reach — branch count + trunk length + thickness, one coupled gesture | `bass_dev` | footprint +48 %; branch count 7→48, never pinned; blooms 1.91/s | three layers on `bass_att`; pinned at 63 for 1.24 % of frames |
| branch spread | `spectral_flux` | **8.97° / 10.77° / 8.23° / 7.72°** | `mid_att`, 0.42° of a promised 7° — dead |
| leaf hue | `tonal_phase_fifths` | **85.2° / 87.4° / 51.6° / 41.9°** of hue | `spectral_centroid`, 4.1° against a 76° wall clock — dead |
| global brightness | `arousal` | **+54.0 % / +14.2 % / +28.1 % / +22.8 %** | *did not exist* — the preset had no section-scale route |
| beat accent | `beat_bass` | live on 15.7–18.2 % of frames, firing 1.88–2.32/s at full amplitude | live on 99.2–100 % — read as a glow, not an accent |

**Changed at FTR.6 — the melodic tips moved off `beat_mid` onto `melodic_tips`.** Matt, after DYN.1c: *"The tips are too active. If possible, I would want only one tip per note of music."* Measured on `2026-08-07T18-53-30Z` the tips fired **7.62/s with a mean jump of 4.6 branches**, against a guitar note rate of **3.29/s**. The rate is not reachable from `beat_mid` at any coefficient — it turns 6.9 times a second, and a stateless shader has no memory of the last event — so the minimum inter-event interval moved into the engine as `MelodicNoteGate` (`FeatureVector.melodicTips`, float 53).

| Layer | Primitive | Measured (Hummer / Cherub Rock, full tracks through the real `MIRPipeline`) | Was |
|---|---|---|---|
| melodic tips — how many fine branches exist | `melodic_tips` | **2.92 / 2.87 note events per second, 1.00 branch per change**; count-changes 5.47 / 5.37 per second, down from 31.6 / 31.5 on identical audio | `beat_mid` through a soft knee — 7.62/s, mean jump 4.6 branches |
| melodic reach — how far each branch travels | `beat_mid` | unchanged; the per-branch travelling wave Matt called *"better overall and probably satisfactory"* at FTR.3e | — |

**Two things the gate does NOT fix, stated rather than implied.** (1) *Instrument separation* — Matt's *"heavily favors the drums vs. guitars"* survives it. The trigger is still mid-band, which in a rock mix is snare AND guitar (correlated **+0.973** here), and per-note guitar onsets do not survive distortion (§MEL.1: grid coherence 31 % for guitar against 41 % for the drums control). (2) *Total transition count* — a tip that appears must also disappear, so the branch count changes about **twice** per note event. That is arithmetic at equilibrium, not a tuning miss; what the gate removes is the SIZE of each change, 4.6 branches → 1.

**Removed at FTR.2:** tip shimmer ← `treb_att`, which delivered +0.002 of a promised +0.12. Not re-homed — that visual layer belongs to FTR.3's per-branch activation, and a dead route is deleted rather than left declared as a false manifest.

**Still to come:** per-branch activation (HERO) ← `beat_phase01` + `pulse_beat_index`, hash-selected bounded subset — FTR.3. Percussive accent ← `stems.drums_energy_dev` — FTR.4, which needs the object/mesh-stage stem binding (the *fragment* stage is already bound at buffer(3) by `drawWithMeshShader`; only the object/mesh half is missing).

**Coefficient rule:** size every coefficient against the primitive's measured p05→p95 span on a real capture, never against a notional 0→1. Applied throughout the table above — and it changed a primitive choice: D-212 named `bass_dev` for canopy reach without measuring it, and the measurement (zero on 66–89 % of frames) is what made the soft-knee `bd/(bd+0.12)` mapping necessary rather than a linear gain.

## Provenance

Curated by: Matt
Image sources: *(none yet — curation pending at FTR.2)*
Painterly predecessor set: `../goldengrove/README.md` (transferred intact at D-212)

## Cross-references

- `docs/presets/FRACTAL_TREE_REACTIVITY_REVIEW.md` — the measured review behind this redirect
- `DECISIONS.md` D-212 — keep the low-fi look; V.10 cancelled; reference set transferred
- `ENGINEERING_PLAN.md` Phase FTR — the reactivity + certification arc
- `SHADER_CRAFT.md §14` — primitive liveness rule (the rule these dead routes broke)
- `SHADER_CRAFT.md §13` Failed Approach #44 — per-instance variation
- ~~`SHADER_CRAFT.md §10.4`~~ — superseded (painterly uplift plan; cancelled at D-212)
