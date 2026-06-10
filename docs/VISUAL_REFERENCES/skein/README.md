# Visual References — Skein

**Family:** `painterly`
**Render pipeline:** `direct_fragment + mv_warp` — *canvas-hold accumulation*: the no-decay / identity configuration of Dragon Bloom's brush-on-feedback paradigm (D-135 / D-138). A sibling of Dragon Bloom, **not** a paradigm-stack, so D-029-clean (see `docs/presets/SKEIN_DESIGN.md §5.1`).
**Rubric:** **RESOLVED at Skein.6 (2026-06-10, D-159): `rubric_profile: "lightweight"`** — the expected landing, matching sibling Dragon Bloom (D-064 precedent; the §12.2/§12.3 3D-surface items are N/A-by-paradigm for a 2D painterly feedback preset). The automated lightweight gate reads `false` on L2 by construction (Skein's deviation primitives are consumed CPU-side in `SkeinState`, invisible to the MSL-source heuristic — the Lumen Mosaic precedent); the load-bearing gate is Matt's M7, per `SHADER_CRAFT.md §12.1`. The full-rubric section scaffold below is retained for `CheckVisualReferences` conformance and historical structure.
**Last curated:** 2026-06-05 — six positives curated by Matt (Unsplash, see *Provenance*). **Trait matrix + anti-reference set approved by Matt 2026-06-05 (Skein.0 sign-off).** The five anti-references, the wet/dry *specular* pair, and the restrained *palette* pole are still to source (see *Still to source*).

> **Architectural reminder.** Skein is a **2D-fragment marks accumulated through feedback** preset. All mark geometry (pour capsules, droplet discs, filaments) is 2D SDF compositing on a persistent canvas; there is no ray-march scene, no particle physics, no mesh, no PBR-shaded surface. Every reference and trait below assumes a flat field viewed straight down — read **morphology and palette**, never perspective or 3D surface lighting. The canvas is a *temporal integral*: paint lands and stays, so the finished frame is the song's visual fingerprint (`SKEIN_DESIGN.md §1.4`).

---

## How to read this folder

*(Read cover-to-cover before authoring — CLAUDE.md FA #63. Authoring from the prompt text alone, or against self-judgment instead of these images, is the V.9 Session 4 failure mode.)*

**None of these images is a faithful rendering of "Skein as it should appear."** Each is read *only* for the trait its annotation calls out. They define the **aesthetic family** — poured / dripped paint, looping skeins, satellite spatter, ragged wet-edge marks, layered accumulation — not a pixel-match target (D-064). A Skein frame should look like it belongs in the same visual conversation as these, never identical to any one of them: "same world, different rendering," never "photograph next to clipart."

Do not author a Skein session against the prompt text alone. Read this README and every per-image annotation, and cite specific reference filenames in code comments where they motivate a design choice. Mid-session sanity checks must be **side-by-side comparisons against the named images**, not self-judgments of "looks reasonable."

**Two disciplines apply across *every* image in this folder (the global annotation discipline):**

1. **Trustworthy = morphology + palette *range*; everything else is illustrative.** What you may trust in any reference is the *morphology* — skein looping, pour pooling, satellite dispersion, filament stringing, ragged organic edges, wet gloss, layered depth — and the *palette range* (saturated through restrained). The palette itself is **open**: Skein is *inspired by* drip painting broadly and is **not limited to any one artist's palette**. The specific hues in any reference are illustrative, never a target. The single binding colour constraint is **legibility: one stable, well-separated colour per stem**, with valence shifting warmth / saturation and arousal shifting vigour across whatever gamut a palette defines.
2. **Coverage ranges with the music — never read a single image's coverage as the target.** The canvas fills over a song: sparse passages stay open, dense passages work up toward full (the §5.7 coverage bound lands a typical track at 60–80 %, never solid). The **resting state must keep negative space** so individual marks and the wet edge stay legible. Several references below are fully-worked patches; that is their *dense end*, not the baseline. The trait to **actively disregard** in any single image is therefore its coverage-as-a-target.

---

## Reference images

Six curated positives, each isolating a distinct trait. Per D-065(a) the "3–5 typical" target is exceeded by **per-image trait justification, not padding**; the three `03_micro_*` files and the single `06_palette_*` share an ordinal by descriptor (the Murmuration duplicate-ordinal pattern). All filenames conform to `../_NAMING_CONVENTION.md`. Annotations carry the three D-065(c) categories: **mandatory** (trustworthy — read this), **decorative** (present, no weight), and **actively disregard**.

| File | Mandatory — trustworthy, read this | Decorative — present, not required | Actively disregard |
|---|---|---|---|
| `01_macro_allover_field.jpg` | Allover, edge-to-edge composition with **no focal point**; the ground reading through at moderate coverage (negative space present); long interlaced **looping skein lines** that cross and double back. The macro target. | The particular balance of the three colours. | The specific hues (dark ground, teal / purple / cream) — one illustrative register, **not** a palette target. |
| `02_meso_pour_pools.jpg` | **Elongated pour lobes** where the stream lingered (the lingering-pour mark); **thick-pour-vs-thin-filament contrast**; pooling / blob morphology. | Pool sizes and positions. | The raking **camera angle** — Skein is flat overhead; read morphology, not perspective. The palette. |
| `03_micro_satellite_spatter.jpg` | **Satellite-droplet dispersion** (dense near the parent line, sparse with distance); droplet **size variation**; wet gloss; the radiating halo around a flick point. | — | Camera angle; **near-total coverage** (a fully-worked patch, not the resting coverage); the palette. |
| `03_micro_filament_threads.jpg` | **Thin filament / thread skeins**; **ragged, bleeding / feathered mark edges** (never clean circles); fine speckle spatter; marks reading over a **visible ground**. | The pink blooms. | The green / maroon palette. |
| `03_micro_layered_buildup.jpg` | **Wet colour layering and depth** (under-layers showing through glossy upper marks); marbled wet-on-wet blend; **bright marks over a darker accumulated base** (the accumulation read). | — | **Near-total coverage** as a baseline (this is the *dense end*); the palette. |
| `06_palette_saturated_peak.jpg` | The **saturated / high-energy ceiling** of the palette range; **thick, viscous, high-impasto paint** (the low-centroid / thick end of the viscosity axis); thick-pour-vs-fine-thread contrast. | — | Near-total coverage as a baseline; camera angle. Defines the **upper palette pole only** — the restrained pole is still to source. |

---

## Trait matrix

Ported from `docs/presets/SKEIN_DESIGN.md §2` (Gate 1). This is the substance contract; the rubric-tier sections below adapt it to `SHADER_CRAFT.md §12`.

| Trait class | Traits |
|---|---|
| **Macro composition** | Allover, edge-to-edge, no focal point; rectangular field; layered depth from overlapping skeins; coverage ranges with the music (open for sparse passages, fully-worked for dense ones) but the resting state keeps negative space so the ground reads through. |
| **Meso structure** | Long looping curvilinear lines that double back; pools where the pour lingered; halos of satellite droplets around lines and at flick points; thin connecting filaments / threads. |
| **Micro detail** | Fine satellite spatter (dense near a mark, sparse far); ragged organic mark edges (not clean circles); thread tendrils; slight bleed / feathering at edges of thin paint. |
| **Material** | Matte-to-glossy enamel / house paint; wet paint glistens, dry paint is flat; opaque thick paint occludes, thin paint is semi-translucent; subtle canvas-weave texture beneath. |
| **Lighting** | Flat overhead illumination; the only specular event is *wet* paint catching light; no dramatic directional shadows (a flat field viewed head-on). |
| **Motion** | New paint *arrives* (the act of landing); accumulation only grows; no global motion of laid paint; the live edge is wherever the painter currently is. |
| **Audio-reactive** | Continuous pour ← energy deviation (primary); splatter ← onsets (accent); colour ← stem identity; viscosity ← centroid; vigour / density ← arousal; palette ← valence; section shifts ← structural prediction; painter wind-up ← beat phase. |

---

## Mandatory traits (per SHADER_CRAFT.md §12.1)

The 3D-surface cascade is reinterpreted for a 2D painterly canvas (the Nebula / Murmuration particle-preset precedent — items that assume surface-shaded geometry are marked N/A with the analogue named).

- [ ] **Detail cascade (paint-mark cascade, not surface cascade):**
  - macro = allover edge-to-edge skein field, no focal point, ground reading through (`01_macro_allover_field.jpg`)
  - meso = elongated pour pools + satellite halos + thin connecting filaments (`02_meso_pour_pools.jpg`)
  - micro = fine satellite spatter (dense→sparse) + ragged feathered mark edges + thread tendrils (`03_micro_satellite_spatter.jpg`, `03_micro_filament_threads.jpg`)
  - specular = the wet-sheen highlight on freshly-landed paint — the wet-now / dry-past legibility device (`SKEIN_DESIGN.md §1.4` / §5; authored at Skein.4, the cut-line — matte-only still certifies)
- [ ] **Hero noise / procedural functions:** ergodic painter path (curl-noise flow field or sum of incommensurate sinusoids) for allover coverage with no focal point; `fbm`-driven ragged mark edges + satellite-spatter jitter (≥4 octaves on the edge / spatter fields, the 2D analogue of the hero-surface octave floor); `hash` family seeded per-track for the determinism property (§5.7; shipped as FNV-1a `title|artist` — D-159 amendment).
- [ ] **Material count (≥3, by paint identity not PBR):** one stable, well-separated colour per stem over a cream ground — drums, bass, vocals, harmonic / other are ≥3 distinct paint "materials" by colour **and** viscosity (centroid-driven thin-translucent ↔ thick-opaque). Wet vs dry is an additional material-state axis. PBR `mat_*` recipes are N/A (no shaded 3D surface).
- [ ] **Audio reactivity (D-026 deviation primitives only):** per the *Audio routing notes* below. **No absolute thresholds** — reject any `smoothstep(0.22, 0.32, f.bass)` pattern.
- [ ] **Silence fallback (D-019 / D-037):** at `totalStemEnergy == 0` the painter rests and the held painting remains; the cream canvas + accumulated paint is bright by construction, so silence-non-black passes trivially with no collapse choreography (`SKEIN_DESIGN.md §1.5`). All `stems.*` reads blend through `smoothstep(0.02, 0.06, totalStemEnergy)`.
- [ ] **Performance ceiling:** 60 fps at 1080p including M1. Skein is *lighter* than Dragon Bloom — the mark pass is scissored to this frame's marks (cost ∝ new marks, not total marks ever laid; §6). `complexity_cost` is written into `Skein.json` at Skein.1+.
- [ ] **Hero reference images (dual):** `01_macro_allover_field.jpg` for the allover composition + negative-space read; `06_palette_saturated_peak.jpg` for the viscosity / saturation ceiling. A session matches the *composition* of `01` and the *paint character* of `06`.

## Expected traits (per §12.2 — at least 2 of 4)

These four assume ray-march / 3D-surface rendering; for a flat 2D painterly canvas most are structurally N/A (the D-064 Plasma / Nebula tension — see the rubric-tension flag below).

- [ ] **Triplanar texturing on non-planar surfaces** — **N/A.** No 3D surfaces; all marks are evaluated in screen UV.
- [ ] **Detail normals** — **N/A.** No 3D normals; the 2D analogue (ragged / feathered mark edges) is carried under the micro cascade above.
- [ ] **Volumetric fog / aerial perspective** — **N/A.** Flat overhead view by design (§2 Lighting — a flat field viewed head-on, no atmospheric depth).
- [ ] **SSS / fiber BRDF / anisotropic specular** — **partial / candidate.** The wet-sheen GGX specular on fresh paint (Skein.4) is the single specular event the references call for (`03_micro_layered_buildup.jpg` glossy upper marks); it is *specular highlight*, not SSS or fiber BRDF.

**Currently 0–1/4 meaningfully apply.** This is expected for a 2D painterly preset; see the rubric-tension flag.

## Strongly preferred traits (per §12.3 — at least 1 of 4)

- [ ] **Hero specular highlight in ≥60 % of frames** — **applicable (cut-line).** The wet-now sheen on freshly-landed paint is a specular event present wherever the painter is currently working; while music plays there is always a live wet edge. Delivered at Skein.4; if Skein.4 defers to V2 (the explicit cut-line), Skein certifies **matte-only** and this trait is waived.
- [ ] **Parallax occlusion mapping** — **N/A.** 2D canvas.
- [ ] **Volumetric light shafts / dust motes** — **N/A.** Flat head-on view, no volume.
- [ ] **Chromatic aberration / thin-film interference** — **N/A.** Paint, not iridescent material.

**Score target:** 1/4 (wet-sheen hero specular), waived to 0/4 if the Skein.4 cut-line fires.

**Rubric-tension flag — RESOLVED at Skein.6 (2026-06-10, D-159).** Skein is classified **lightweight** with a painterly stylization contract (the expected outcome, matching sibling Dragon Bloom per D-064): §12.2 / §12.3 assume surface-shaded geometry a 2D painterly feedback preset does not have, so those items are N/A-by-paradigm. `Skein.json` carries `rubric_profile: "lightweight"`; the L2 false-negative (CPU-side deviation routing) is documented in `FidelityRubricTests.expectedAutomatedGate`.

---

## Anti-references

Five failure modes that disqualify a frame from the visual conversation (ported from `SKEIN_DESIGN.md §2` failure modes + anti-references). Staying out of these is the certification bar, **not** pixel-equivalence with any positive. To author / source (sourced photography or illustration preferred; AI-generation only under the D-065(b) carve-out noted below).

- `05_anti_particle_burst.(jpg|png)` — a **neon / sci-fi particle burst** → guards: the frame must read as **poured paint, not particles**. Mark morphology + matte material is the whole game (§2 failure mode (b)).
- `05_anti_polka_dots.(jpg|png)` — **clean geometric polka-dots** → guards: **ragged organic mark edges**, never clean circles.
- `05_anti_brush_stroke.(jpg|png)` — a **literal paintbrush stroke** → guards: **pour / drip only** — no brush ever contacts the canvas.
- `05_anti_dead_mat.(jpg|png)` — an **over-covered, overworked dead mat** with no negative space → guards: **coverage ranges with the music and the resting state stays open**; composite **opaque-overwrite, never additive** so layers occlude rather than average to brown / mud (§2 failure modes (a) + (e)).
- `05_anti_kaleidoscope.(jpg|png)` — a **kaleidoscopic / symmetric** layout → guards: **asymmetric allover**, no symmetry or mirroring (drip painting is asymmetric by nature).

**AIGEN carve-out (D-065(b)).** AI generation is permitted *only* in the `05_anti_*` slot. Any such file must carry the `_AIGEN` suffix, its annotation must state that **every** trait of the image is anti (no partial-trust read of any property), and Provenance must record the generator + prompt and a replacement plan (a v1-baseline Skein frame from the `RENDER_VISUAL=1` harness, substituted once the first implementation ships).
**⚠ Lint caveat (verified Skein.0):** the uppercase `_AIGEN` suffix does **not** match `_NAMING_CONVENTION.md`'s lowercase descriptor class `[a-z0-9_]+`, so a file whose name carries the uppercase suffix (descriptor ending `_AIGEN`) is rejected by `CheckVisualReferences` Rule 3 — descriptor `05_anti_kaleidoscope_AIGEN` fails the regex; the lowercase `05_anti_kaleidoscope_aigen` form passes. This is a pre-existing conflict between D-065(b)'s example filename and the naming regex. **Prefer real photography / illustration for the five anti slots to stay lint-clean**; if an AIGEN anti-reference is introduced, resolve the suffix-case question first (do not silently lowercase the suffix — surface it, since `_AIGEN` provenance visibility is the point of D-065(b)). Out of scope for Skein.0.

---

## Audio routing notes

The §5.4 routing contract — **one audio primitive per visual layer** (`feedback_audio_layer_one_primitive`), all **deviation-normalised** (D-026), all `stems.*` reads gated by the **stem warmup blend** `smoothstep(0.02, 0.06, totalStemEnergy)` (D-019). **No absolute thresholds.** Continuous energy is the primary driver; onsets are accents only (CLAUDE.md §Audio Data Hierarchy — Layer 1 primary, Layer 4 accent).

| Visual layer | Single audio primitive | Channel |
|---|---|---|
| Pour flow rate (per stem colour) | that stem's energy **deviation** (`stem.xRel` / `xAttRel`) | primary / continuous |
| Painter speed | broadband energy deviation + arousal | primary / continuous |
| Painter local jitter | high-band energy / onset rate | primary / continuous |
| Painter wind-up & flick timing | `beatPhase01` (phase, **not** raw onset — FA #33) | anticipation |
| Splatter burst intensity (per stem) | onset pulse for that stem's band | accent |
| Paint viscosity → mark morphology | that stem's spectral **centroid** | character |
| Flick sharpness (spray tightness) | that stem's **attackRatio** | character |
| Paint colour selection | stem identity | structural |
| Palette warmth / saturation | valence / arousal (smoothed **in state**, never via `setFeatures` — FA #25) | slow global |
| Section palette / density shift | `StructuralPrediction` boundary | slow global |
| Vocal-line hue / position nuance (optional) | vocals pitch (YIN) | character |

The colour logic is the core: each stem owns one stable, distinct paint; the canvas's colour balance at any instant mirrors the stem balance of the mix, and its colour history over the song mirrors the arrangement. **Legibility, not specific hues, is the binding constraint** — the palette is open and tunable. The painter seed is per-track FNV-1a `title|artist` (the determinism property, §5.7; wired at Skein.3, ratified at Skein.6 / D-159 — the original SHA-256 wording was amended, see `SKEIN_DESIGN.md §1`).

---

## Still to source

Tracked so the folder's gaps are explicit. **Neither blocks the Skein.0 lint pass** — the lint enforces conformant filenames + a populated folder + this README's required sections, not a slot-completeness count (D-065(a): no count ceiling, no minimum beyond non-empty).

- **The five `05_anti_*` anti-references** above. **Matt unable to source — decision (2026-06-05): the textual anti-reference spec above is the binding contract** and is what gates the Skein.2 / Skein.3 manual anti-reference checks; the automated anti-reference dHash gate is a *Missing* engine capability regardless, so anti-refs are an M7 manual judgement either way. The anti-reference **images** are therefore **deferred, not blocking** — D-065(b)'s own preferred replacement is a v1-baseline Skein frame capture (`RENDER_VISUAL=1`) once Skein.1 renders, so the failure-mode frames are best captured from the preset itself; a separate AIGEN image-gen step is the alternative if they are wanted sooner (resolve the `_AIGEN` lint-conflict above first). None of this gates Skein.0, Skein.ENGINE.1, or Skein.1.
- **`04_specular_*` — the wet/dry pair.** All six positives are glossy / wet, so the *wet* pole is well covered but the matte / dry counterpart is missing. Skein.4's wet-now / dry-past sheen device needs **both** poles — source a matte / dried-paint reference and file the pair under `04_specular_*` (e.g. `04_specular_dry_matte_paint.(jpg|png)`).
- **`06_palette_restrained_baseline.(jpg|png)`** — the restrained / low-energy pole of the palette axis. All six positives are vivid (`06_palette_saturated_peak.jpg` is the upper pole); source or hand-build a swatch so the valence / arousal axis has **both** ends.

None of these gate Skein.0. They gate the downstream sessions that consume the slot they fill: the anti-references gate the Skein.2 / Skein.3 manual anti-reference checks; the wet/dry pair gates Skein.4; the restrained palette gates Skein.5 mood routing.

---

## Provenance

The six positives are sourced from **Unsplash**, used under the Unsplash License (free for commercial and non-commercial use; attribution optional but recorded here for provenance and re-licensing audits). They are photographs that *are* paint — original abstract / fluid photography, **no people, no logos, no photographs of copyrighted artworks** — so no underlying-artwork rights are implicated.

| File | Source | Photographer (Unsplash) |
|---|---|---|
| `01_macro_allover_field.jpg` | Unsplash | familyarttess |
| `02_meso_pour_pools.jpg` | Unsplash | jene-stephaniuk |
| `03_micro_satellite_spatter.jpg` | Unsplash | paul-blenkhorn |
| `03_micro_filament_threads.jpg` | Unsplash | paul-blenkhorn |
| `03_micro_layered_buildup.jpg` | Unsplash | paul-blenkhorn |
| `06_palette_saturated_peak.jpg` | Unsplash | tiago-francisco |

*(Record the specific photographer against each renamed file — the original Unsplash download filename carries the credit; the reference-library name `NN_<scale>_<descriptor>` replaces it. The pairing above follows the curation note; verify per-file before any re-licensing audit.)*

All six are ≤ 500 KB per the `_NAMING_CONVENTION.md` size limit (largest on disk ≈ 497 KB).

**No `_AIGEN` images present.** The D-065(b) carve-out is not yet invoked. Any `05_anti_*_AIGEN` image records its generator + prompt here when added, plus the replacement-with-v1-frame plan noted in *Anti-references*.

---

## Certification

**Resolved at Skein.6 (2026-06-10, D-159): `rubric_profile: "lightweight"`** — following sibling Dragon Bloom (`direct + mv_warp` feedback, D-064 precedent). The automated cert gates landed at Skein.6: track-length coverage bound + §5.7 determinism dHash (`SkeinCanvasHoldTest`), golden dHash entry (`PresetRegressionTests`), and the §5.5 two-hour canvas soak (`SKEIN_SOAK=1`). Regardless of profile, the binding bar is the **M7 manual gate** (`SKEIN_DESIGN.md §5.7`): Matt, live, on real music across ≥ 5 tracks plus a local file — the drip painting must read as **poured paint**, the painter must **perform**, the canvas must stay **legibly temporal** (wet-now / dry-past), and no frame may match an anti-reference. No automated metric substitutes.

The automated anti-reference dHash gate is itself a *Missing* engine capability (the same gap Arachne has), so the anti-reference check stays an M7 manual judgement until that capability lands.

---

## Cross-references

- `docs/presets/SKEIN_DESIGN.md` — creative architecture (§1), trait matrix + failure modes + anti-references (§2), rendering contract (§5), acceptance criteria (§5.7).
- `docs/presets/SKEIN_PLAN.md` — increment breakdown; Skein.0 is the reference-lock gate, Skein.6 sets the rubric profile.
- `../_NAMING_CONVENTION.md` — authoritative filename regex + size / format limits.
- `DECISIONS.md` D-064 (reference library structure + full / lightweight rubric split + lint), D-065 (image count softening + `_AIGEN` anti-slot carve-out + three-category "actively disregard" annotation), D-066 (reel-source decision).
- `DECISIONS.md` D-026 (deviation-primitive audio), D-019 (stem warmup), D-037 (silence-non-black), D-135 / D-138 (Dragon Bloom brush-on-feedback paradigm Skein inherits).
- `SHADER_CRAFT.md §2.1 / §2.3` (reference-image discipline), `§12` (fidelity rubric this README maps to).
