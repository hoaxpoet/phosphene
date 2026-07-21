# Visual References — Mandelbox Cathedral

**Family:** geometric (fractal)
**Render pipeline:** ray_march (static camera) + post_process (+ ssgi from PG.3.3)
**Rubric:** full (gated by V.6 certification)
**Last curated:** 2026-07-20 by Matt

## Target (read first)

A vast **3D fractal cathedral** — a Mandelbox/KIFS distance estimator building endless architecture from self-similar copies of itself. The camera holds still; the geometry is the motion: sustained bass unfolds deeper nested chambers, vocal pitch twists the fold. **Port the published DE (Syntopia / Knighty / IQ) — do not derive (FA #73).** Full design + multi-increment arc: `docs/presets/psychedelic_geometry/PG_3_MANDELBOX_CATHEDRAL.md`.

## Reference images

| File | What to learn from it |
|---|---|
| `01_macro_fan_vault.jpg` **(HERO)** | Gothic fan-vaulting (looking up into the crossing) — the macro architectural read: cathedral-scale chambers/arches/ribs radiating to a central boss. |
| `02_meso_muqarnas.jpg` | Stone petal/rib vault — self-similar nested cells (the meso "shapes inside shapes" at the second iteration). |
| `03_micro_geode.jpg` | Amethyst geode cavity — self-similar micro sub-chambers + crystalline material character. |
| `04_specular_polished_stone.jpg` | Chrome/faceted mirror material — metallic specular finish (one of the ≥3 materials). |
| `06_palette_stained_glass_light.jpg` | Cathedral jewel light — palette + mood-tinted IBL target. |
| `07_atmosphere_god_rays.jpg` | Volumetric light shafts (forest god-rays) — aerial perspective / god-ray behaviour. |
| `08_specular_marble_veining.jpg` | Dark blue+gold veined marble — a rich `mat_marble` material reference (pairs with jewel light). |
| `09_specular_marble_white.jpg` | White Carrara marble — a light-stone counterpart material. |
| _(prose only — no image)_ | NOT this — a flat 2D Mandelbrot-zoom look (no 3D/lighting), or over-iterated mush with no readable architecture. No committed `05_anti` image by design; the rule lives in the Anti-references section below. A v1-baseline capture may be added later (D-065). |

## Mandatory traits (per `SHADER_CRAFT.md §12.1` — full rubric)

- [ ] **Detail cascade:** macro = fractal architecture silhouette · meso = box-fold ledges/chambers · micro = deeper-iteration sub-chambers · specular = PBR material breakup + thin-film on fold edges.
- [ ] **Materials (≥ 3):** chrome (`04`) + marble (`08`/`09`) + geode/stone, via matID dispatch + `thinfilm_rgb` on edges. (PG.3.1 ships ONE maquette material; ≥3 land in PG.3.2.)
- [ ] **Audio (D-026):** `f.bass_att_rel` → fold scale; `stems.vocals_pitch_hz` (gated ≥ 0.6, fallback `stems.other_energy_dev`) → fold rotation; `f.arousal` → emission; `stems.drums_energy_dev_smoothed` → edge shimmer.
- [ ] **Silence (D-037):** dim ambient cathedral at rest fold-scale, cool mood-tinted IBL, gentle fog — non-black.
- [ ] **Perf:** p95 ≤ 7 ms @ 1080p Tier 2 (DE iteration cap; Tier-1 degradation).
- [ ] **Hero:** `01_macro_fan_vault.jpg` (+ `04`/`08` for material).

## Anti-references

Flat 2D fractal (no 3D depth/lighting); over-iterated mush; grey fog (FA #39 — fog matches palette); a moving/dolly camera (D-029 — the camera is fixed).

## Audio routing (cite D-026 / D-019; full table in PG_3 §A4)

Fold scale ← `f.bass_att_rel`; fold rotation ← `stems.vocals_pitch_hz` (gated + fallback); emission/IBL ← `f.arousal`; hue ← `f.spectral_centroid` (+ valence tints IBL, D-022); edge shimmer ← `stems.drums_energy_dev_smoothed`. `smoothstep(0.02,0.06,totalStemEnergy)` warmup (D-019). One primitive per motion layer (FA #67).

## Provenance

Curated by: Matt. Sources: real photography (fan vault, stone vault, amethyst geode, chrome facet, stained glass, forest god-rays, marble slabs — all confirmed real photos, 2026-07-20). All compressed to ≤500 KB in-session. Alternate geode held in `docs/VISUAL_REFERENCES/_pg_spares/mandelbox_cathedral/`.
