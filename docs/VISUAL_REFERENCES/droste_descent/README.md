# Visual References — Droste Descent

**Family:** geometric
**Render pipeline:** direct_fragment + mv_warp
**Rubric:** lightweight (stylized 2D) — recommended; see `docs/presets/psychedelic_geometry/PG_2_DROSTE_DESCENT.md §9`
**Last curated:** 2026-07-20 by Matt

## Target (read first)

An **infinite self-similar zoom tunnel** (log-polar / Droste) — the frame contains a smaller copy of itself forever, each ring holding the next. It descends one ring inward per beat (cached-grid `beat_phase01`); the bass sets throat width; a slow twist turns the log-spiral. Full design: `docs/presets/psychedelic_geometry/PG_2_DROSTE_DESCENT.md`.

## Reference images

| File | What to learn from it |
|---|---|
| `01_macro_light_tunnel.jpg` **(HERO)** | A real photographed light tunnel (cropped to remove foreground figures + wall signage) — receding light bands into a bright blue throat, real depth. The "endless well" composition. |
| `02_meso_droste_photo.jpg` | The literal Droste effect — a picture containing a smaller copy of itself, receding to infinity. The self-similar nesting. |
| `03_micro_spiral_staircase.jpg` | Log-spiral self-similar nesting (nautilus / spiral staircase) — the twist + per-ring ornament (rings as little tunnels). |
| `04_palette_neon_corridor.jpg` | Emissive jewel palette receding to a throat (neon corridor / nested neon frames). Palette + throat glow. |
| _(prose only — no image)_ | NOT this — flat concentric rings scrolling with no self-similar depth (a pipe, not a well), or a strobe tunnel. No committed `05_anti` image by design; the rule lives in the Anti-references section below. A v1-baseline capture may be added later (D-065). |

## Stylization contract

- [ ] **Nested detail cascade (mandatory):** macro = tunnel + throat/vanishing point · meso = self-similar log-spaced rings · micro = per-ring ornament + nested ring-motif · breakup = emissive edges + throat bloom + chromatic aberration rising toward the throat.
- [ ] **Color:** `f.spectral_centroid` per-ring hue drift; pale-tone ≤ 30 %.
- [ ] **Silence (D-037):** slow gentle free-fall, dim tunnel, calm palette, soft non-black throat glow; no hard beat steps.
- [ ] **Hero reference:** `01_macro_light_tunnel.jpg`.

## Anti-references

Flat 2D rings scrolling (a pipe, not a Droste well); nauseating strobe/flicker tunnel; feedback smear that erases the ring structure.

## Audio routing (cite D-026; full table in PG_2 §A4)

Descent ← `f.beat_phase01` (cached grid; ramps per beat = ride + cadence; fallback `f.arousal` on no-grid/irregular tracks, D-154); throat width ← `f.bass_att_rel`; twist ← `f.mid_att_rel` (larger gain); hue ← `f.spectral_centroid`. `base_zoom` ≥ 2–4× `beat_zoom` (Layer-4). One primitive per layer (FA #67); no absolute thresholds (FA #31).

## Provenance

Curated by: Matt. Sources: real photography (light tunnel, Droste-effect photo, nautilus/spiral). `01_macro_light_tunnel.jpg` was cropped (foreground figures + SKANSKA signage removed) + compressed in-session (2026-07-20); `02_meso_droste_photo.jpg` was converted from `.webp`. `04_palette_neon_corridor.jpg` may be a 3D render — confirm its licence. Note: **do not use the Kusama infinity-room shots** (held aside as copyrighted artworks). Alternates in `docs/VISUAL_REFERENCES/_pg_spares/droste_descent/`.
