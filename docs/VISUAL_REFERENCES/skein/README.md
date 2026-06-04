# Skein — Visual Reference Library

**Preset:** Skein · **Family:** `painterly` · **Role:** "painting the music" — a drip/pour painting that accumulates a record of the track on a persistent canvas (see `docs/presets/SKEIN_DESIGN.md`).

---

## How to read this folder (read cover-to-cover before authoring — CLAUDE.md FA #63)

**None of these images is a faithful rendering of "Skein as it should appear."** Each is read *only* for the trait its annotation calls out. They define the **aesthetic family** — poured/dripped paint, looping skeins, satellite spatter, wet gloss — not a pixel-match target (D-064 #6). A Skein frame should look like it belongs in the same visual conversation as these, not identical to any one of them: "same world, different rendering," never "photograph next to clipart."

Do not author a Skein session against the prompt text alone. Read this README and every per-image annotation, and cite specific reference filenames in code comments where they motivate a design choice. Mid-session sanity checks must be side-by-side comparisons against the named images, not self-judgments of "looks reasonable."

**Two disciplines apply across *every* image in this folder:**

1. **Palette is open.** Skein is *inspired by* drip painting, not limited to any one artist's palette. The specific hues in any reference are illustrative. The only binding colour rule is **one stable, well-separated colour per stem** (legibility), with valence shifting warmth/saturation and arousal shifting vigour across whatever gamut a palette defines.
2. **Coverage ranges with the music — never read a single image's coverage as the target.** The canvas fills over a song: sparse passages stay open, dense passages work up toward full. The *resting* state must keep negative space so individual marks and the wet edge stay legible. Several references below are fully-worked patches; that is their *dense end*, not the baseline.

---

## Reference manifest

Six curated positives, each isolating a distinct trait (per `SHADER_CRAFT.md §2.1`, the 3–5 default is exceeded by per-image trait justification, not padding; the `03_micro_*` files and the single `06_palette_*` share a number by descriptor, the Murmuration pattern). Filenames conform to `_NAMING_CONVENTION.md`.

| File | Mandatory (read this) | Decorative (present, not required) | Actively disregard |
|---|---|---|---|
| `01_macro_allover_field.jpg` | Allover edge-to-edge composition, no focal point; ground reading through (negative space present); long interlaced looping skein lines that cross and double back. | The particular balance of the three colours. | The specific hues (dark ground, teal/purple/cream) — one example register, **not** a palette target. |
| `02_meso_pour_pools.jpg` | Elongated pour lobes where the stream lingered (the lingering-pour mark); thick-pour-vs-thin-overlaid-filament contrast. | Pool sizes and positions. | The raking camera angle — Skein is flat overhead; read morphology, not perspective. The palette. |
| `03_micro_satellite_spatter.jpg` | Satellite-droplet dispersion (dense near the parent line, sparse with distance); droplet size variation; the radiating halo around a flick. | Wet gloss on the droplets. | Camera angle; near-total coverage (a fully-worked patch, not the resting coverage); the palette. |
| `03_micro_filament_threads.jpg` | Thin filament/thread skeins; ragged, bleeding/feathered mark edges (not clean circles); fine speckle spatter; marks reading over a visible ground. | The pink blooms. | The green/maroon palette. |
| `03_micro_layered_buildup.jpg` | Wet colour layering and depth (under-layers showing through glossy upper marks); bright marks sitting over a darker accumulated base (the accumulation read). | The marbled wet-on-wet blend. | Near-total coverage as a baseline (this is the dense end); the palette. |
| `06_palette_saturated_peak.jpg` | The saturated / high-energy **ceiling** of the palette range; thick, viscous, high-impasto paint (the low-centroid / thick end of the viscosity axis). | Thick-pour-vs-fine-thread contrast. | Near-total coverage as a baseline; camera angle. Defines the *upper* palette pole only — the restrained pole is still to source (see below). |

---

## Mandatory traits checklist

A Skein frame is on-target when it satisfies these. (This is the trait contract; the formal certification rubric tiers and `rubric_profile` are set at V.6 — see *Certification* below.)

- **Macro:** allover, edge-to-edge, no focal point; coverage ranges with the music and the resting state keeps negative space (ground reads through).
- **Meso:** long looping curvilinear lines that double back; pour pools where the stream lingered; satellite halos around lines and flick points; thin connecting filaments.
- **Micro:** fine satellite spatter, dense near a mark fading to sparse; ragged organic mark edges (never clean circles); thread tendrils; slight bleed/feathering at the edges of thin paint.
- **Material / specular:** wet paint glistens (a specular highlight), dry paint is matte; opaque thick paint occludes, thin paint is semi-translucent.
- **Lighting:** flat overhead; the only specular event is *wet* paint catching light; no dramatic directional shadows (a flat field viewed head-on).
- **Motion:** new paint *arrives* and accumulates; no global motion of paint already laid; the live edge is wherever the painter currently is.
- **Colour:** one stable, well-separated colour per stem; palette open (saturated through restrained); valence → warmth/saturation, arousal → vigour.
- **Audio-reactive:** continuous pour ← per-stem energy deviation (primary); splatter ← onset pulses (accent); colour ← stem identity; viscosity ← spectral centroid; section shifts ← structural prediction; painter wind-up ← beat phase.

---

## Anti-references

Failure modes that disqualify a frame from the visual conversation. Staying out of these is the certification bar, not pixel-equivalence with any positive. To author (sourced or, where noted, AI-generated under the D-065(b) carve-out):

- `05_anti_particle_burst` — neon/sci-fi particle burst → must read as **poured paint, not particles**.
- `05_anti_polka_dots` — clean geometric dots → guards **ragged organic edges**, not clean circles.
- `05_anti_brush_stroke` — a literal brush stroke → guards **pour/drip only**; no brush ever contacts the canvas.
- `05_anti_dead_mat` — an over-covered, overworked field with no negative space → guards that **coverage ranges with the music and the resting state stays open**; opaque-overwrite compositing, never additive mud.
- `05_anti_kaleidoscope` — a symmetric/kaleidoscopic layout → guards **asymmetric allover**, no symmetry or mirroring.

**AIGEN anti-references (D-065(b) carve-out):** AI generation is permitted *only* in the `05_anti_*` slot. Any such file must carry the `_AIGEN` suffix (e.g. `05_anti_kaleidoscope_AIGEN.jpg`), and its annotation must state that **every** trait of the image is anti — there is no partial-trust read of any property. Each `_AIGEN` anti-reference is to be replaced with a v1-baseline Skein frame capture (`RENDER_VISUAL=1` harness) once the first Skein implementation ships.

---

## Still to source

Tracked here so the folder's gaps are explicit; neither blocks the Skein.0 lint pass (the lint enforces conformant filenames + a populated folder + this README, not a slot-completeness count).

- **`04_specular_*` — the wet/dry pair.** All six positives are glossy/wet, so the *wet* trait is well covered, but the matte/dry counterpart is missing. Skein.4's wet-now/dry-past sheen device needs both poles. Source a matte/dried-paint reference and file the pair under `04_specular_*`.
- **`06_palette_restrained_baseline`.** All six positives are vivid; the saturated pole is covered (`06_palette_saturated_peak`), the restrained / low-energy pole is not. Source or hand-build a swatch so the valence/arousal axis has both ends.

---

## Provenance

The six positives are sourced from **Unsplash**, used under the Unsplash License (free for commercial use, attribution optional; recorded here for provenance and good practice). They are photographs that *are* paint — original abstract/fluid photography, no people, no logos, no photographs of copyrighted artworks — so no underlying-artwork rights are implicated.

Contributing photographers (Unsplash): familyarttess, jene-stephaniuk, paul-blenkhorn (×3), tiago-francisco. Record the specific photographer against each renamed file — the original Unsplash download filename carries the credit; the reference-library name (`NN_<scale>_<descriptor>`) replaces it.

Any `05_anti_*_AIGEN` images record their generator and prompt here when added, plus the replacement-with-v1-frame plan noted above.

---

## Certification

The formal rubric tiers (mandatory / expected / strongly-preferred per `SHADER_CRAFT.md §12`) and the `rubric_profile` field in `Skein.json` are set at V.6. Skein's closest sibling, Dragon Bloom (`direct + mv_warp` feedback), certified on the **lightweight** profile; Skein is expected to follow unless V.6 review decides otherwise. Regardless of profile, the binding bar is the **M7 manual gate** — Matt, live, on real music across ≥5 tracks plus a local file: the drip painting must read as poured paint, the painter must perform, and no frame may match an anti-reference.
