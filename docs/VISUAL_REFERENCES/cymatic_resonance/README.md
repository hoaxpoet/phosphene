# Visual References — Cymatic Resonance

**Family:** `geometric`
**Render pipeline:** `direct_fragment + post_process` — a square-plate **Chladni nodal figure** rendered as a strong-oblique-tilt displaced relief, jewel-emissive ridges on a deep-black plate. `direct_time_modulation` (D-029): camera holds, the figure is the motion.
**Rubric:** lightweight — single-plate 2D-derived relief; the §12 3D-surface/material-count items are held to the multi-octave / non-pale / nested-detail bar via CR.2, not the full-rubric matrix. Load-bearing gate is Matt's M7.
**Last curated:** 2026-07-22 (CR concept gate). Four license-verified positives (Flickr, see *Provenance*).

> **Primary look-authority is Matt's real-Chladni-plate footage** (`brusspup`, screen-recorded 2026-07-22, kept private/uncommitted — copyrighted). The concept gate compared the shader model frame-by-frame against that footage; it is the ground truth for symmetry, mode-transition behaviour, and tilt. The committed stills below are the CC/PD supporting set. **The single most important thing the footage taught:** real plates show ONE clean 4-fold-symmetric eigenmode per frequency (image `01`), snapping finer as pitch rises (toward `02`) — **not** a continuous superposition of many modes (which reads as squiggle-soup). This forced the **plus** eigenmode basis and the **brightness→single-dominant-mode** mapping — see `docs/presets/psychedelic_geometry/PG_CR_CYMATIC_RESONANCE.md`.

---

## How to read this folder

None of these is a pixel-target. Each is read only for the trait its annotation names — the **aesthetic family** (resonant nodal geometry, 4-fold symmetry, emissive standing-wave palette), never a photograph-match (D-064). A Cymatic Resonance frame should belong in the same visual conversation as `01`/`02`, lit and glowing in jewel tones rather than white sand.

## Reference images

| File | Trustworthy — read this | Actively disregard |
|---|---|---|
| `01_macro_chladni_plate.jpg` | **The macro target.** A single clean 4-fold-symmetric (axis + diagonal) nodal figure with a concentric central cell — the resonant-plate read at low/mid brightness. High-contrast white-on-black rhymes with our emissive-on-dark render. | It is a flat top-down capture; our framing is a strong oblique tilt. The white colour (we stylize jewel/iridescent). |
| `02_micro_chladni_filigree.jpg` | **The high-brightness pole.** Dense high-frequency nodal grid — the fine filigree the figure resolves into as the track brightens (top of the mode-complexity ladder). Nested finer cells inside the macro symmetry. | Colour; flat framing. Read the *density increase with pitch*, not this exact cell layout. |
| `03_palette_rubens_tube.jpg` | **Palette anchor.** Emissive gold/amber standing-wave flames on black — a self-luminous acoustic figure. The jewel/HDR-bloom warm pole; ridges are the light source. | The literal flame morphology (we render nodal ridges, not fire). |
| `04_anti_static_mandala.jpg` | **Anti-reference — NOT this.** A fixed radial mosque-dome mandala: looks cymatic, but it is decorative symmetry with **zero frequency response**. If the figure stops reorganizing with the music and reads as static ornament, it has failed. | — (whole image is the failure mode). |

## Stylization contract

- **Geometry = the sound's pitch.** Spectral centroid (brightness) selects one dominant plate eigenmode (crossfading up a fixed low→high complexity ladder); a bass drop snaps to a low simple figure. The figure IS the live pitch made solid — reading `01` at low brightness, `02` at high.
- **Plus basis, 4-fold symmetry.** `cos(mξ)cos(nη) + cos(nξ)cos(mη)`. Every figure is axis- and diagonal-symmetric with concentric central cells (per `01`). No spurious dominant diagonal (the minus basis is forbidden — it railroads every figure onto ξ=η).
- **Jewel-emissive on deep black.** Ridges are the light source; derived-normal GGX relief gives the depth cue; thin-film iridescence + HDR bloom on crests. Real sand is white; we stylize to the Phosphene jewel signature (Matt's call, 2026-07-22). Pale-tone ≤ 30 %.
- **Strong oblique tilt**, camera held. No `mv_warp` (would smear the crisp nodal lines).

## Anti-references

- `04_anti_static_mandala.jpg` — decorative radial symmetry with no music response (static ornament).
- **Squiggle-soup** — a continuous sum of many modes at comparable weight: asymmetric glowing contour-worms with no clean symmetry. Verified in the concept spike; the reason for the single-dominant-mode mapping. Do not reintroduce a 12-band amplitude superposition.
- **Jitter-on-beat** — discrete per-frame structure-pop that reads "like a bug" (the Truchet Loom D-194 failure). Transitions must crossfade between clean figures; the only permitted snap is the intentional bass-drop.

## Audio routing notes

- **HERO** — `f.spectral_centroid` (EMA-smoothed, slot-6 state) → mode-ladder position → which nodal figure. Level-independent and always alive (tracks timbre), unlike raw FFT magnitude (§14.1).
- **Snap event** — `f.bassDev` (deviation, D-026) drop → fast-EMA yank down the ladder to a simple figure.
- **CR.3** — `f.arousal` → excitation gain; `f.spectral_centroid` → valence IBL hue (D-022); `stems.drums_energy_dev_smoothed` → bounded ridge shimmer (steady global luminance, D-157).
- One primitive per visual layer (FA #67); deviation/centroid only, never absolute thresholds on AGC-normalized energy (FA #31).

## Provenance

| File | Source | Author | License (verified 2026-07-22 against source page) |
|---|---|---|---|
| `01_macro_chladni_plate.jpg` | [flickr.com/photos/nonlin/3861695253](https://www.flickr.com/photos/nonlin/3861695253) | Stephen Morris | CC BY 2.0 |
| `02_micro_chladni_filigree.jpg` | [flickr.com/photos/nonlin/3861695163](https://www.flickr.com/photos/nonlin/3861695163) | Stephen Morris | CC BY 2.0 |
| `03_palette_rubens_tube.jpg` | [flickr.com/photos/comedynose/3724359284](https://www.flickr.com/photos/comedynose/3724359284) | comedynose | Public Domain Mark |
| `04_anti_static_mandala.jpg` | [flickr.com/photos/seier/2034873075](https://www.flickr.com/photos/seier/2034873075) | seier+seier | CC BY 2.0 |

All four verified by fetching the source page and confirming the license tag (`creativecommons.org/licenses/by/2.0` / `publicdomain/mark`) at curation. Attribution (CC BY) satisfied here + in `docs/CREDITS.md` at commit. **Ground-truth footage** (`brusspup`, copyrighted) is NOT committed. **Still to source (optional, CR.2/CR.3):** a `meso` mid-complexity figure (Faraday-wave lattice, MDPI CC BY) and Chladni's 1787 PD engravings.
