# Visual References — Mandala Engine

**Family:** geometric
**Render pipeline:** direct_fragment + mv_warp
**Rubric:** lightweight (stylized 2D) — recommended; see `docs/presets/psychedelic_geometry/PG_1_MANDALA_ENGINE.md §9`
**Last curated:** 2026-07-20 by Matt

## Target (read first)

A living **radial kaleidoscopic mandala** — concentric rings of self-similar motifs built by a 2–3 level recursive mirror-fold (a petal made of petals). It breathes radially with the sustained bass and blooms a fresh concentric ring on each downbeat. Jewel palette, feedback depth, crisp vector symmetry — not photoreal. Full design: `docs/presets/psychedelic_geometry/PG_1_MANDALA_ENGINE.md`.

## Reference images

| File | What to learn from it |
|---|---|
| `01_macro_kaleidoscope.jpg` **(HERO)** | A genuine through-the-scope kaleidoscope view — true N-fold mirror symmetry, motifs repeated cell-to-cell, warm faceted-glass optical depth. Match this composition + depth. Read for the radial nesting + jewel palette + optical depth; the specific purple/red/bead motifs are incidental. |
| `02_meso_rose_window.jpg` | Gothic rose window — concentric rings of roundel motifs around a central boss, jewel-on-black. The meso ring banding; the figurative saints are incidental. |
| `03_micro_sand_mandala.jpg` | Tibetan sand mandala (cropped to the disk) — petal-within-petal recursion: central 8-petal lotus inside concentric palace rings. The load-bearing "shapes inside shapes" reference. |
| `04_palette_stained_glass.jpg` | Backlit jewel-glass — the emissive palette + fine leadline breakup; per-ring hue variation. |
| _(prose only — no image)_ | NOT this — a flat, bilaterally-symmetric clipart/logo mandala, uniform saturation, no depth or nesting. No committed `05_anti` image by design; the rule lives in the Anti-references section below. A v1-baseline in-engine capture may be added later (D-065). |

## Stylization contract (substitutes for full detail-cascade / material rubric)

- [ ] **Nested detail cascade (mandatory):** macro = N-fold disk silhouette · meso = concentric motif rings · micro = recursive sub-fold (petal-of-petals) · breakup = emissive edges + radial chromatic aberration + grain. ≥ 4 octaves of variation.
- [ ] **Color:** `f.spectral_centroid` drives palette phase; per-ring hue offset; pale-tone share ≤ 30 % (FA #45).
- [ ] **Silence (D-037):** slowly-rotating dim mandala at rest radius, calm cool palette, vignette to deep indigo — non-black; no blooms.
- [ ] **Hero reference:** `01_macro_kaleidoscope.jpg`.

## Anti-references

Flat clipart symmetry with no depth/nesting; over-blended feedback smear (mush); uniform-saturation "cartoon" palette.

## Audio routing (cite D-026; full table in PG_1 §A4)

Radial breath ← `f.bass_att_rel`; global rotation ← `f.arousal`; downbeat ring bloom ← `f.bar_phase01` wrap (cached BeatGrid, never raw onsets; cold-start suppressed ~3 s); palette phase ← `f.spectral_centroid`. One primitive per layer (FA #67); no absolute thresholds (FA #31).

## Provenance

Curated by: Matt. Sources: real photography (kaleidoscope, rose window, stained glass) + a photographed Tibetan sand mandala. `03_micro_sand_mandala.jpg` was cropped to the disk + compressed in-session (2026-07-20); confirm the kaleidoscope shot is your own. Backup/alternate images (a second rose window) are held in `docs/VISUAL_REFERENCES/_pg_spares/mandala_engine/`.
