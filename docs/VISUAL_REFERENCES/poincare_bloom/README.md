# Visual References — Poincaré Bloom

**Family:** geometric
**Render pipeline:** direct_fragment (no feedback — crisp curved detail)
**Rubric:** lightweight (stylized 2D) — recommended; see `docs/presets/psychedelic_geometry/PG_5_POINCARE_BLOOM.md §9`
**Last curated:** 2026-07-20 by Matt

## Target (read first)

A **hyperbolic Circle-Limit tiling** in the Poincaré disk — shapes nesting and shrinking infinitely toward a boundary circle — that the four separated stems slide, spin, ripple, and tint through itself via Möbius flow. **Port the {p,q} fold + Möbius maps (Bulatov / Nelson / Coxeter / Shadertoy); Escher's *Circle Limit* is the concept touchstone — name only, do NOT ship the plates (FA #73).** Full design: `docs/presets/psychedelic_geometry/PG_5_POINCARE_BLOOM.md`.

## Reference images

| File | What to learn from it |
|---|---|
| `01_macro_hyperbolic_diagram.jpg` | Clean {p,q} Poincaré-disk tiling diagram — the geometric ground truth: tiles shrinking to the boundary. |
| `02_meso_islamic_dome.jpg` **(HERO)** | Muqarnas dome / star-tiling — a real-world hyperbolic-rosette analog: nested symmetry, jewel palette, cells nesting toward a centre. |
| `03_micro_boundary_nesting.png` | B/W hyperbolic pinwheel tiling — "motifs shrinking infinitely toward the edge" (the boundary nesting). |
| `04_palette_rose_window.jpg` | Zellige / rose-window jewel palette + emissive tile character. |
| `08_meso_hyperbolic_tiling.png` | Colour {3,7} hyperbolic tiling on black — the literal coloured tiling the author will **port** (geometry + colour target). |
| _(prose only — no image)_ | NOT this — a flat Euclidean tiling (same-size tiles, not hyperbolic), or a Möbius flow blowing tiles up at the boundary. No committed `05_anti` image by design; the rule lives in the Anti-references section below. A v1-baseline capture may be added later (D-065). |

## Stylization contract

- [ ] **Nested detail cascade (mandatory):** macro = Poincaré disk + {p,q} symmetry · meso = primary central tiles · micro = infinitely shrinking boundary tiles (the nesting) · breakup = edge glow + chromatic fringe rising toward the boundary + AA fade.
- [ ] **Color:** jewel per-tile scheme; `stems.other_energy_dev` tint; `f.valence` warm/cool baseline; pale-tone ≤ 30 %.
- [ ] **The concept:** all four stems visibly independent — bass slide, vocals spin, drum ripple, other tint.
- [ ] **Boundary stability:** the accumulated Möbius transform is renormalized so a long session never blows tiles past the boundary or freezes.
- [ ] **Silence (D-037):** slow Möbius idle-drift of a dim tiling — non-black; no ripples.
- [ ] **Hero reference:** `02_meso_islamic_dome.jpg` (+ `01`/`08` for geometry).

## Anti-references

Flat Euclidean tiling (same-size tiles — not hyperbolic); Möbius flow that blows tiles up / freezes them at the boundary; reproducing Escher's copyrighted plates (name only).

## Audio routing (cite D-026 / D-019 — per-stem, clean by construction; full table in PG_5 §A4)

Möbius translation ← `stems.bass_energy_dev`; rotation ← `stems.vocals_pitch_hz` (gated ≥ 0.6, fallback `stems.vocals_energy_dev`); radial ripple ← `stems.drums_energy_dev` (bounded, decaying); per-tile tint ← `stems.other_energy_dev`; palette baseline ← `f.valence`. `smoothstep(0.02,0.06,totalStemEnergy)` warmup from FeatureVector proxies (D-019). One primitive per channel (FA #67); no absolute thresholds (FA #31); no feedback (D-029).

## Provenance

Curated by: Matt. Sources: public-domain / computer-generated hyperbolic-tiling math figures (`01`, `03`, `08`) + real photography (`02` muqarnas dome, `04` zellige/rose window). All ≤500 KB (compressed in-session 2026-07-20). Escher *Circle Limit* referenced by name only (not committed). Alternate islamic dome + the source `.svg` held in `docs/VISUAL_REFERENCES/_pg_spares/poincare_bloom/`.
