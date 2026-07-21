# Phase PG — Visual Reference Shopping List

Everything Matt needs to source to unblock the five session prompts. Each session's pre-flight gate (D-064) requires `docs/VISUAL_REFERENCES/<slug>/` populated + a written `README.md` — **the READMEs are already drafted and committed** (filled from the design docs); you only need to drop in the images and fill each README's "Last curated" + "Provenance" lines.

## Rules (from `docs/VISUAL_REFERENCES/_NAMING_CONVENTION.md`)

- **Filename:** `NN_<scale>_<descriptor>.<ext>` — `NN` = 01–99 (lower = higher priority), `<scale>` ∈ {`macro`, `meso`, `micro`, `specular`, `atmosphere`, `lighting`, `palette`, `anti`}, `<descriptor>` = 2–4 words `lowercase_underscored`, `<ext>` = `jpg` for photos / `png` for renders & line-art.
- **Lint** (`swift run --package-path PhospheneTools CheckVisualReferences`) enforces `^[0-9]{2}_(macro|meso|micro|specular|atmosphere|lighting|palette|anti)_[a-z0-9_]+\.(jpg|png)$`.
- **Size:** ≤ 500 KB each. A 960×540 or full-frame 1080p JPEG q85 is fine. No uncompressed PNGs.
- **⚠️ `_AIGEN` gotcha:** `SHADER_CRAFT.md §2.3` suggests an `_AIGEN` suffix for AI-generated anti-refs, but that uppercase would **fail the lowercase lint regex**. So: keep the filename lowercase (e.g. `05_anti_flat_clipart.jpg`) and record the AI provenance + planned v1-capture replacement in the README's **Provenance** section (per D-065). Only the `05_anti_*` slot may be AI-generated; every other slot must be **real photography** (or a public-domain diagram / in-engine render as noted).
- **Two kinds of reference:** *IMAGES TO SOURCE* (commit these to the folder) vs *REFERENCES TO READ* (Shadertoy/paper/art the author reads and ports per FA #73 — **not** committed, just cited in the shader header). Both are listed per preset.

---

## PG.1 — Mandala Engine → `docs/VISUAL_REFERENCES/mandala_engine/` (rubric: lightweight)

**IMAGES TO SOURCE** (real photos except the anti):

| File | What to find/shoot |
|---|---|
| `01_macro_kaleidoscope.jpg` **(HERO)** | An actual **kaleidoscope** view — nested rings of mirror-folded motifs with real optical depth. The single "must match" frame. |
| `02_meso_rose_window.jpg` | A gothic **rose window** or an **Islamic/Moorish star-tiling** panel — concentric symmetric banding, jewel palette, backlit. |
| `03_micro_sand_mandala.jpg` | A Tibetan **sand mandala** or a Persian miniature **medallion** — petal-within-petal recursion (the sub-fold nesting). |
| `04_palette_stained_glass.jpg` | Backlit **stained glass** — jewel-tone palette + emissive character. |
| `05_anti_flat_clipart.jpg` | NOT this: a flat, bilaterally-symmetric **clipart/logo mandala**, uniform saturation, no depth, no nesting, no motion. (AI-gen OK; note provenance.) |

**REFERENCES TO READ (don't commit):** a clean polar **mirror-fold kaleidoscope** Shadertoy (cite its ID in the shader); Inigo Quilez articles on **domain repetition / folding** and **2D SDFs**.

---

## PG.2 — Droste Descent → `docs/VISUAL_REFERENCES/droste_descent/` (rubric: lightweight)

**IMAGES TO SOURCE:**

| File | What to find/shoot |
|---|---|
| `01_macro_light_tunnel.jpg` **(HERO)** | An **LED / mirror light-tunnel** or **infinity-mirror** installation (generic, not a specific copyrighted artwork) — receding rings into a bright throat. |
| `02_meso_droste_photo.jpg` | A photo exhibiting the **Droste effect** (a picture containing a smaller copy of itself) — the self-similar nesting. |
| `03_micro_spiral_staircase.jpg` | Looking up/down a **spiral staircase**, or a **nautilus** cross-section — the log-spiral twist + per-ring ornament. |
| `04_palette_neon_corridor.jpg` | A **neon / jewel-lit corridor** — emissive palette + throat glow. |
| `05_anti_flat_rings.jpg` | NOT this: flat concentric **rings scrolling** with no self-similar depth (a pipe, not a well); or a nauseating strobe tunnel. (AI-gen OK.) |

**REFERENCES TO READ:** Lenstra & de Smit, *"Escher and the Droste effect"* (the conformal log-polar math); a **log-polar / Droste tunnel** Shadertoy; IQ **log-polar** articles.

---

## PG.3 — Mandelbox Cathedral → `docs/VISUAL_REFERENCES/mandelbox_cathedral/` (rubric: FULL)

**IMAGES TO SOURCE** (this is the full-rubric 3D preset — richer set):

| File | What to find/shoot |
|---|---|
| `01_macro_fan_vault.jpg` **(HERO)** | Gothic **fan-vaulting** / a cathedral interior looking up into the vault — the macro architectural read. |
| `02_meso_muqarnas.jpg` | Islamic **muqarnas** (honeycomb vaulting) or **Sagrada Família** columns — literally fractal architecture; nested niches. |
| `03_micro_geode.jpg` | A crystal **geode** / cave interior — self-similar micro sub-chambers + material character. |
| `04_specular_polished_stone.jpg` | Polished **stone / marble** specular highlight + finish. |
| `06_palette_stained_glass_light.jpg` | Cathedral **jewel light** — palette + emissive-through-glass. |
| `07_atmosphere_god_rays.jpg` | **Light shafts** through a cathedral — aerial perspective / volumetric light. |
| `05_anti_flat_fractal.jpg` | NOT this: a flat 2D **Mandelbrot-zoom** look with no 3D depth/lighting; or over-iterated noisy mush with no readable architecture. (AI-gen OK.) |

**REFERENCES TO READ (READ AND PORT — FA #73):** Mikael Hvidtfeldt Christensen (**Syntopia**) Mandelbox/Mandelbulb writeups + **Fragmentarium**; **Knighty's KIFS**; Inigo Quilez *"Rendering fractals with distance estimation"* + the **Mandelbulb** article; a canonical **Mandelbox/KIFS Shadertoy** (cite ID). The DE is exact and published — do not derive it.

---

## PG.4 — Truchet Loom → `docs/VISUAL_REFERENCES/truchet_loom/` (rubric: lightweight)

**IMAGES TO SOURCE:**

| File | What to find/shoot |
|---|---|
| `01_macro_labyrinth_floor.jpg` **(HERO)** | A cathedral **labyrinth floor** (Chartres-style) or a **Celtic / Islamic interlace** panel — the continuous-path weave. |
| `02_meso_woven_textile.jpg` | A woven **basket / textile / brocade** — tiles connecting into paths; the ribbon character. |
| `03_micro_moire_mesh.jpg` | Overlaid **mesh screens / sheer fabric** showing moiré — emergent large structure from small repeats (the nesting intuition). |
| `04_palette_op_art_tile.jpg` | A bold geometric **floor mosaic / azulejo** — high-contrast duotone palette. |
| `05_anti_flat_checker.jpg` | NOT this: a static single-scale **black-and-white Truchet checker** (no subdivision, no colour, no motion); or a flickering high-contrast strobe. (AI-gen OK.) |

**REFERENCES TO READ:** Inigo Quilez **"Truchet tiles"** + his **multiscale Truchet** Shadertoy; Christopher Carlson **"Multi-scale Truchet Patterns"** (cite the Shadertoy ID).

---

## PG.5 — Poincaré Bloom → `docs/VISUAL_REFERENCES/poincare_bloom/` (rubric: lightweight)

**IMAGES TO SOURCE:**

| File | What to find/shoot |
|---|---|
| `01_macro_hyperbolic_diagram.png` | A **public-domain Poincaré-disk {p,q} tiling diagram** (a math figure) — ground-truth geometry: tiles shrinking to the boundary. (`png` — line art.) |
| `02_meso_islamic_dome.jpg` **(HERO)** | An Islamic **muqarnas dome / star-tiling** that *approximates* a hyperbolic rosette — nested symmetry, jewel palette. |
| `03_micro_kaleidoscope_edge.jpg` | A **kaleidoscope / curved-mirror** view where motifs shrink toward an edge. |
| `04_palette_rose_window.jpg` | A **rose window / stained glass** — jewel palette + emissive tile character. |
| `05_anti_flat_euclidean.png` | NOT this: a **flat Euclidean** tiling where tiles are the same size everywhere (no boundary-nesting → not hyperbolic); or a Möbius flow where tiles blow up at the boundary. (AI-gen OK.) |

**REFERENCES TO READ (READ AND PORT — FA #73):** M.C. Escher's **Circle Limit I–IV** as the **named concept touchstone** — **cite by name only; do NOT ship or reproduce the copyrighted plates**; **Coxeter** on the Circle Limit geometry; **Vladimir Bulatov** and **Roice Nelson** hyperbolic-tiling / Möbius references; a canonical **Poincaré-disk hyperbolic-tiling Shadertoy** (cite ID).

---

## Sourcing tips

- **Where copyright is a risk** (Escher plates, specific installation artworks, named op-art works): reference by *name* in the shader header and README, and source a *different, licensable* real photo of the same phenomenon for the committed image. The committed images anchor palette/contrast/"does it read as a real thing"; the published works are read-only design targets.
- **Diagrams** (PG.5 `01`, PG.5 `05`): public-domain math figures / Wikimedia hyperbolic-tiling diagrams are ideal and license-clean; save as `png`.
- **Priority:** the `01_*` (hero) and `05_anti_*` slots matter most — if you're short on time per preset, get those two first; the meso/micro/palette slots refine fidelity but the hero + anti gate the session.
- **When images land:** drop them in the folder, update the README's `Last curated:` line + `Provenance` section, run the lint, and the session's pre-flight gate passes. Send them to me and I'll review each against its README's mandatory-traits + anti-references before you run the prompt.
