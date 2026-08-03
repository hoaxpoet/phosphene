# Visual References — Fractal Tree

**Family:** fractal
**Render pipeline:** `["mesh_shader"]` — object → mesh → fragment via `MeshGenerator.draw`; flat HSV, no lighting, no G-buffer
**Rubric:** lightweight — stylized 2D graphic (exempt from full detail-cascade + material-count requirements)
**Last curated:** 2026-08-03 by Matt (FTR.1 / D-212)

> **Read this before the checklist trips you up.** The painterly reference set that used to live here — 14 images of bark, translucent foliage, golden-hour light and autumn palettes — **moved to `../goldengrove/`** when the V.10 uplift was cancelled at D-212. It described a preset Fractal Tree is deliberately not becoming. Do not go looking for it here and do not port it back.
>
> **There is currently no curated image set for this preset.** `PRESET_SESSION_CHECKLIST.md` Part 1 §1 says: curate one as part of the session, or escalate to Matt before authoring. **Curating a low-fi / graphic reference set is an explicit prerequisite of FTR.2** — see "What a reference set here would need to show" below.

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

- [ ] **Color modulation:** leaf/tip hue tracks harmonic movement (`tonal_phase_fifths`), not a wall clock. The current `fract(t * 0.006)` term out-drives the audio term **18.6 : 1** and is removed at FTR.2.
- [ ] **Audio coverage:** six visual layers, six *distinct* primitives (FA #67). The shipped preset runs three layers off `bass_att` alone — the defect FTR.2 fixes.
- [ ] **Readability at silence:** a sparse, still, non-black tree — trunk plus the first two generations, legible and clearly alive (D-037). Never an empty frame.
- [ ] **Readability at peak energy:** full 63-branch canopy that still reads as a *tree*, not a solid mass. Branch count must not flat-top: the shipped preset saturates at 63 for 5.1 % of frames.

## Anti-references

What this preset must NOT look like:

- **Perfect bilateral symmetry** — mirror-image sub-trees at every recursion (FA #44). Break with per-branch hash jitter.
- **Uniform branch thickness** at a given depth — vary per-branch.
- **A rendered/painterly tree** — bark texture, leaf mass, volumetric light. That register belongs to Goldengrove; producing it here is the failure, not the goal.
- **A colour-cycling wallpaper** — hue drifting on a timer while the music does something else.
- **A tree that flat-tops** — visibly pinned at maximum branch count through a whole chorus.

## Audio routing notes

**Shipped routing (as of D-212) is the defect, recorded here so the FTR.2 diff is legible.** Measured on session `2026-08-03T15-05-43Z` (*Hummer*, 2114 frames after warmup):

| Layer | Primitive | Measured swing | Verdict |
|---|---|---|---|
| branch count | `bass_att` | 21 → 63 | alive |
| trunk length | `bass_att` | 0.434 → 0.558 | alive — same primitive |
| thickness | `bass_att` | 11.7 % | alive — same primitive |
| canopy spread | `mid_att` | **0.42°** of a promised 7° | dead |
| tip shimmer | `treb_att` | **+0.002** of a promised +0.12 | dead |
| leaf hue | `spectral_centroid` | **4.1°** vs a 76° clock term | dead |
| beat flash | `beat_bass` | non-zero 90.4 % of frames | reads as glow, not accent |

**Target routing (FTR.2 — one primitive per layer):**

- Per-branch activation (HERO) ← `beat_phase01` + `pulse_beat_index` hash-selected bounded subset — per-beat
- Canopy reach / branch length ← `bass_dev` — continuous
- Branch spread angle ← `spectral_flux` — continuous
- Leaf / tip hue ← `tonal_phase_fifths` — slow harmonic
- Global brightness envelope ← `arousal` — section-level
- Percussive accent ← `stems.drums_energy_dev` — per-onset *(needs the mesh-path stem binding, FTR.4)*

**Coefficient rule:** size every coefficient against the primitive's measured p05→p95 span on a real capture, never against a notional 0→1. That is the discipline that would have caught all three dead routes above.

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
