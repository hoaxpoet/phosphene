# Visual References — Truchet Loom

**Family:** geometric
**Render pipeline:** direct_fragment (no feedback — crisp)
**Rubric:** lightweight (stylized 2D) — recommended; see `docs/presets/psychedelic_geometry/PG_4_TRUCHET_LOOM.md §9`
**Last curated:** 2026-07-20 by Matt

## Target (read first)

A woven **op-art labyrinth of curved Truchet tiles** that subdivide into smaller tiles of the same weave when the music gets busier (rising spectral flux → nested sub-tiles) and merge into large arcs when it thins. Crisp flat frames (no feedback). **Palette direction: colour** (per curation — bold duotone/azulejo, not mono). **Port multiscale Truchet (IQ / Carlson), don't derive (FA #73).** Full design: `docs/presets/psychedelic_geometry/PG_4_TRUCHET_LOOM.md`.

## Reference images

| File | What to learn from it |
|---|---|
| `01_macro_labyrinth_floor.jpg` **(HERO)** | Flowing scallop/arc op-art — the core aesthetic: curved arcs overlapping into a flowing, multi-scale weave field. Read for the arc-flow + overlap (this is line art; palette comes from `04`). |
| `02_meso_woven_textile.jpg` | White 3D interlocking-Y relief — curved units interlocking into a woven lattice with real depth (tiles connecting into a weave). |
| `03_micro_moire_mesh.jpg` | Diagonal fine mesh throwing moiré — emergent large structure from small repeats (the nesting intuition). |
| `04_palette_op_art_tile.jpg` | Blue/white/yellow interlocking-circle azulejo — the **colour** palette + a curved-arc (overlapping-circle) motif on-concept for Truchet. |
| _(prose only — no image)_ | NOT this — a static single-scale black-and-white Truchet checker (no subdivision/colour/motion), or a flicker strobe. No committed `05_anti` image by design; the rule lives in the Anti-references section below. A v1-baseline capture may be added later (D-065). |

## Stylization contract

- [ ] **Nested detail cascade (mandatory):** macro = weave field + path flow · meso = the Truchet tiles/arcs · micro = subdivided sub-tiles of the same motif (the nesting) · breakup = AA path edges + glow + per-path hue + grain.
- [ ] **Color:** bold colour palette (azulejo-derived); `f.spectral_centroid` per-path hue; pale-tone ≤ 30 % (avoid pure #000/#fff — the base is a deep colour).
- [ ] **Silence (D-037):** a coarse large-arc weave (minimum subdivision) drifting slowly — non-black; no flips.
- [ ] **Hero reference:** `01_macro_labyrinth_floor.jpg`.

## Anti-references

Static single-scale checker Truchet (no subdivision/colour/motion); seizure-risk flicker/strobe; any feedback-style smear (this preset is crisp `direct`).

## Audio routing (cite D-026; full table in PG_4 §A4)

Subdivision density ← **smoothed** `f.spectral_flux` (hero — measures busyness; drive from variation, never a fixed threshold); global drift ← `f.arousal`; per-beat tile flips ← `f.beat_phase01` wrap (cached grid), bounded subset; path hue ← `f.spectral_centroid`. One primitive per layer (FA #67); no absolute thresholds (FA #31); no feedback (D-029).

## Provenance

Curated by: Matt. Sources: op-art line-art (`01`, `04`-motif) + real photography (`02` 3D relief, `03` mesh moiré, `04` azulejo tilework). All ≤500 KB (compressed in-session 2026-07-20). Confirm the line-art graphics (`01`) are yours or licensed. Mono B/W palette alternate + extra weave/mesh shots held in `docs/VISUAL_REFERENCES/_pg_spares/truchet_loom/`.
