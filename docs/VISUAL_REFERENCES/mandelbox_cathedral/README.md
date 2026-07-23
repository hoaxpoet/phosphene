# Visual References — Fractal Descent (Mandelbox cathedral, camera-flight)

**Preset:** Fractal Descent (working name) — supersedes the shelved PG.3 Mandelbox Cathedral (static-camera concept, retired at the design stage; Matt 2026-07-23). Same Mandelbox, same cathedral reference set — the camera **falls** instead of holding.
**Family:** geometric (fractal)
**Render pipeline:** ray_march (**camera_flight** — a continuous descent) + post_process
**Rubric:** full
**Last curated:** 2026-07-20 by Matt · **README retargeted for the fall:** 2026-07-23

## Target (read first)

A vast **3D fractal cathedral you fall INTO** — a Mandelbox distance estimator building endless architecture from self-similar copies of itself. The **identity trait (untradeable):** the sensation of an unending fall into an infinite, self-elaborating fractal world — you are always descending, and the biggest musical moments are arrivals in somewhere vast. The descent is a *scale* descent, not a translation (a Mandelbox is bounded, so a downward dolly would exit it): `zoom = |Scale|^fract(phase)` sweeps one self-similar octave and wraps seamlessly onto itself. **Port the published DE (Syntopia / Knighty / IQ Rrrola form) — do not derive (FA #73).** The FD design of record was the FD session prompt (Part A — not committed as a doc); the nearest committed sibling is the superseded static-camera `docs/presets/psychedelic_geometry/PG_3_MANDELBOX_CATHEDRAL.md`. Authoritative FD build history: `git log` (grep `FD.1`/`FD.2`/`RMPERF.1`) + `ENGINEERING_PLAN.md`; the shipped behaviour is documented in `docs/ARCHITECTURE.md` (Module Map → `FractalDescent.metal`).

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
- [ ] **Materials (≥ 3):** via matID region dispatch — jewelled stone (`04`/`08`, dominant, carries 3D form) + thin-film iridescent fold-edge rims (`thinfilm_rgb`) + emissive backlit-glass votives in the deepest recesses (`06`). Shipped at FD.2.
- [ ] **Audio (D-026):** descent SPEED ← the music's energy (`accumulatedAudioTime`, energy×dt); fold-open / chamber breakthrough ← `f.bass_att_rel`. Secondary (FD.3): hue ← `f.spectral_centroid`; god-ray incandescence ← `f.spectral_flux`; forward-surge accent ← `f.beat_phase01` (bounded).
- [ ] **Silence (D-037):** near-stationary drift (energy≈0 → the energy-time phase barely advances), non-black legible fractal chamber at rest.
- [ ] **Perf:** p95 ≤ 7 ms @ 1080p Tier 2 (DE iteration cap 8 + RMPERF.1 preamble; ~4.4 ms measured at FD.2).
- [ ] **Motion coherence (camera_flight):** the seamless octave wrap must not pop, and thin filaments must not shimmer/boil under the fall — gate with `motion_gate.sh`, never stills alone.
- [ ] **Hero:** `01_macro_fan_vault.jpg` (+ `04`/`08` for material).

## Anti-references

Flat 2D fractal (no 3D depth/lighting); over-iterated mush with no readable architecture; grey fog (FA #39 — fog matches palette); a recurring full-frame bright flash (D-157 — e.g. the descent ramming the central sphere so its face fills the frame; the off-axis pre-zoom offset dodges this).
**NOTE (2026-07-23):** the earlier "moving/dolly camera is forbidden" anti-reference is RETIRED — it belonged to the shelved static-camera PG.3 concept. The camera **flight IS the concept** here (the fall). What's forbidden is a *translation* through the bounded object (it exits into empty sky); the descent is a scale-zoom.

## Audio routing (cite D-026 / D-019)

Descent speed ← `accumulatedAudioTime` (energy-integrated time — the animation time base, so it is NOT a declared audio_route; it reads constant on the offline QG.1 fixtures — QG.1.1 boundary); fold-open ← `f.bass_att_rel` (soft-saturated, widens the box-fold limit within a Lipschitz-safe band). Camera is static in world space (`cameraDollySpeed` 0) — the fall is entirely the in-shader scale-zoom, so no collision with the preset-agnostic camera dolly (FA #67). Secondary routes land at FD.3.

## Provenance

Curated by: Matt. Sources: real photography (fan vault, stone vault, amethyst geode, chrome facet, stained glass, forest god-rays, marble slabs — all confirmed real photos, 2026-07-20). All compressed to ≤500 KB in-session. Alternate geode held in `docs/VISUAL_REFERENCES/_pg_spares/mandelbox_cathedral/`.
