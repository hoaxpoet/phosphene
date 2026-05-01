# Starburst (Murmuration) — Visual References

**Family:** `particles`
**Passes:** `["feedback", "particles"]` (per D-029)
**Rubric profile:** full-rubric
**Last curated:** 2026-05-01

---

## What this preset depicts

A 500K-particle starling murmuration rendered against a sunset sky. The flock is the
entire scene — not decoration over a backdrop. Cohesive silhouette, dense core,
fluttering periphery, continuous shape morphing, drum-driven turning waves that sweep
across the body, and a sky gradient that warms slightly with vocal energy.

The preset's compound motion comes from the particle integrator itself, not from
`mv_warp` (per D-029). The `feedback` pass provides trail decay for the particle
render; it is not an independent motion source.

---

## Reference images

| File | What this teaches |
|---|---|
| `01_macro_archetypal_silhouette.jpg` | The canonical murmuration shape: large rounded mass, dense core, feathered edge against sunset. Defines the at-rest silhouette the particle field should approximate. |
| `02_meso_ribbon_elongation.jpg` | Bass-driven shape morphology: ribbon/comma elongation with bulbous leading head and trailing wisp. Shape stretches and reshapes under sustained low-frequency energy. |
| `03_micro_periphery_dispersion.jpg` | Density gradient across the body: dense core fading to ghostly stippled edge, with a detached trailing cluster. The periphery-vs-core flutter weighting (1.0× edge, 0.25× core) made visible. |
| `06_palette_pastel_baseline.jpg` | Sky envelope at low vocal energy: cloudless indigo → lavender → peach gradient. The neutral target. |
| `06_palette_saturated_peak.jpg` | Sky envelope at peak vocal energy: saturated red-orange ceiling. Pairs with the baseline to define the warmth-shift range (≤10% per current routing). |
| `05_anti_countable_individuals.jpg` | **NOT this.** Birds resolved as countable individuals with no emergent silhouette. Failure mode if particle density goes uniform, particle sprites get too detailed, or the camera frames too tight. |
| `05_anti_dispersed_no_shape.jpg` | **NOT this.** Scattered points with no cohesive silhouette and no negative space. Failure mode for cohesion/alignment forces being too weak — flock fails to form a shape. |

**Actively disregard** in the reference images:
- The horizon foreground (trees, reeds, water) in 01/02. Starburst has no ground plane; the flock is the sole subject. These elements appear in the references because real murmurations are photographed at dusk over wetlands, not because the preset depicts terrain.
- The bird-shape detail visible in 02/03. At Starburst's particle scale and density, individual birds are sub-pixel dots, not the wing-readable silhouettes seen in reference photography. The references teach *flock-level* behavior, not bird anatomy.
- The cloud striations in 06_palette_pastel_baseline. The preset's sky is a plain vertical gradient with no cloud structure; the reference teaches the color stack, not the cloud shapes.

---

## Mandatory rubric (SHADER_CRAFT §12.1)

| # | Item | Status | Notes |
|---|---|---|---|
| M1 | Detail cascade present | ⚠ partial | Macro (silhouette), meso (shape morphology), micro (core/periphery density gradient) are well-defined for a particle field. "Specular breakup" maps awkwardly — Starburst has no surfaces; the closest analogue is per-particle size/alpha variation. Flag for Matt: rubric M1 may need a particle-preset interpretation. |
| M2 | ≥4 noise octaves | N/A | No hero surface to apply noise to. The sky gradient is a vertical color stack; the particles are integrated dots. Rubric item assumes surface shading. |
| M3 | ≥3 distinct materials | N/A | No PBR materials. Render layers (particle dots, sky gradient, feedback trail) are not "materials" in the cookbook sense. Same argument as Nebula's lightweight classification. |
| M4 | Deviation-primitive audio | ✗ | Currently routes on absolute stem energy (`drums_beat`, `bass_energy`, `other_energy`, `vocals_energy`) and FeatureVector 6-band fallback. Per D-026, should use `*_rel`/`*_dev` primitives. **Flag for next uplift session.** |
| M5 | Graceful silence fallback | ✓ | `smoothstep(0.02, 0.06, totalStemEnergy)` crossfades from stem routing to FeatureVector 6-band routing as stems warm up. Zero stems → identical behavior to pre-3.5.2 implementation. Tested in `MurmurationStemRoutingTests`. |
| M6 | p95 frame time ≤ tier budget | pending | Empirical; verify via `PresetPerformanceTests` on Tier 1 / Tier 2 fixtures. |
| M7 | Matt-approved reference frame match | pending | These reference images are the input contract for that gate. |

**Rubric tension flag.** Starburst is classified full-rubric per D-064 but the rubric's
M1–M3 assume surface-shaded geometry. Three rubric items are N/A or partial purely
because particle presets don't have the structural primitives the rubric checks for.
This is the same tension D-064 acknowledged for Nebula (resolved by lightweight
classification). Recommend either (a) reclassify Starburst lightweight with a
particle-specific stylization contract, or (b) extend the rubric with a particle
profile that replaces M1–M3 with cohesion/density/shape items. Decision deferred to
Matt; this README does not assume the resolution.

---

## Expected (≥2/4 — SHADER_CRAFT §12.2)

- [ ] Triplanar texturing on all non-planar surfaces — N/A (no surfaces)
- [ ] Detail normals — N/A
- [ ] Volumetric fog or aerial perspective — *not currently implemented; could add atmospheric haze to the sky gradient at low altitudes for depth*
- [ ] SSS / fiber BRDF / anisotropic specular — N/A

**Currently 0/4** that meaningfully apply. The same particle-preset rubric tension
flagged above. Aerial perspective is the only realistic candidate.

---

## Strongly preferred (≥1/4 — SHADER_CRAFT §12.3)

- [ ] Hero specular highlight ≥60% of frames — N/A
- [ ] POM on at least one surface — N/A
- [ ] Volumetric light shafts or dust motes — *not currently; god rays at sunset would be on-genre*
- [ ] Chromatic aberration or thin-film — *not currently; mild CA on bright peaks could enhance the dawn/dusk feel without competing with the silhouette*

**Currently 0/4** that meaningfully apply.

---

## Audio routing

Stem-driven routing landed in Increment 3.5.2. Current behavior:

- **Drums (`drums_beat` decay)** → turning wave that sweeps across the flock over
  ~200 ms (not instantaneous). Direction alternates per beat epoch. The drum onset
  is an *accent*, never the primary visual driver — continuous energy carries the
  base motion.
- **Bass (`bass_energy`)** → macro drift velocity and shape elongation. This is what
  produces the ribbon/comma silhouettes shown in `02_meso_ribbon_elongation.jpg`.
- **Other (`other_energy`)** → surface flutter weighted by `distFromCenter` —
  periphery 1.0×, core 0.25×. Produces the dense-core / fluttering-edge contrast
  shown in `03_micro_periphery_dispersion.jpg`.
- **Vocals (`vocals_energy`)** → density compression
  (`densityScale = 1 - vocals * 0.22`) applied to `halfLength` and `halfWidth`,
  plus sky gradient shifts up to ~10% warmer.

**Warmup fallback:** `smoothstep(0.02, 0.06, totalStemEnergy)` crossfades from
FeatureVector 6-band routing to stem routing. At zero stems the behavior is
identical to the pre-3.5.2 implementation.

**Outstanding work for next uplift session:**
1. Convert all four routings from absolute energy to deviation primitives
   (`drumsEnergyDev`, `bassEnergyDev`, etc.) per D-026. Currently violates the
   absolute-threshold anti-pattern.
2. Consider routing `bassAttackRatio` (transient vs sustained) into shape
   morphology — sustained bass should produce different elongation behavior than
   kick-drum bass, which the current `bass_energy` routing cannot distinguish.
3. Evaluate `vocalsPitchHz` for sky-gradient hue shift in addition to or instead
   of `vocals_energy`-driven warmth. Pitch-keyed sky tint would give the preset
   a Phosphene-exclusive capability not available to Milkdrop.

---

## Provenance

All reference images are sourced from Unsplash. Verify license terms before commit
— several are credited to the Unsplash+ contributor account (`getty-images`),
which has different usage rules than the standard Unsplash license.

| File | Source | Photographer / contributor | Original Unsplash filename |
|---|---|---|---|
| `01_macro_archetypal_silhouette.jpg` | Unsplash+ | getty-images | `getty-images-dQwtywaBuV0-unsplash.jpg` |
| `02_meso_ribbon_elongation.jpg` | Unsplash+ | getty-images | `getty-images-f4zfFW-a928-unsplash.jpg` |
| `03_micro_periphery_dispersion.jpg` | Unsplash+ | getty-images | `getty-images-AqpHtXS2Clc-unsplash.jpg` |
| `06_palette_pastel_baseline.jpg` | Unsplash | Ferdinand Stöhr | `ferdinand-stohr-iW1WzbuWMcA-unsplash.jpg` |
| `06_palette_saturated_peak.jpg` | Unsplash | Ahmed | `ahmed-vVrZs0aJ8Go-unsplash.jpg` |
| `05_anti_countable_individuals.jpg` | Unsplash | Don Coombez | `doncoombez-PMyM6yuq2fk-unsplash.jpg` |
| `05_anti_dispersed_no_shape.jpg` | Unsplash+ | getty-images | `getty-images-cbP9fGjFZQQ-unsplash.jpg` |

All images cropped and re-encoded to JPEG quality 80, max 2560 px on the long edge,
≤ 500 KB per the size limit in `_NAMING_CONVENTION.md`. Committed via Git LFS per
`.gitattributes`.

No `_AIGEN` images. The carve-out in D-065 was not invoked — both anti-references
are real photography depicting non-murmuration flock states.

---

## Cross-references

- `MILKDROP_ARCHITECTURE.md §7 (MV-2)` — why mv_warp was reverted on this preset (D-029)
- `DECISIONS.md D-026` — deviation-primitive audio routing requirement
- `DECISIONS.md D-029` — preset motion-source paradigms; Starburst uses `feedback + particles`
- `ENGINEERING_PLAN.md §Increment 3.5.2` — Murmuration Stem Routing Revision
- `SHADER_CRAFT.md §12` — fidelity rubric this README maps to
- `SHADER_CRAFT.md §2.3` — reference-image discipline
