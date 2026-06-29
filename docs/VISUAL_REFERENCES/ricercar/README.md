# Visual References — Ricercar

**Family:** `painterly` (sibling of Skein)
**Render pipeline:** `direct + mv_warp` (flowing-field config) **+ compute-agent voices** — Skein's canvas-hold mv_warp reconfigured to a curl-noise flow warp + slow decay (the colour *flows and merges*, it does not permanently accumulate), carrying a small set of Filigree-class agent "voices." See [`docs/presets/RICERCAR_DESIGN.md`](../../presets/RICERCAR_DESIGN.md).
**Rubric:** expected `rubric_profile: "lightweight"` (matching sibling Skein/Dragon Bloom — a 2D painterly feedback preset; the §12.2/§12.3 3D-surface items are N/A-by-paradigm). Confirm at the certification increment.
**Last curated:** 2026-06-29 — `01_macro_weaving_lines.jpg` is a hand-authored synthetic **anchor** (SVG → `qlmanage` raster; see *Reference images* / *Provenance*). Matt sourced photographic candidates for `02` (ink-in-water plume) and `04` (tulip-field colour bands), 2026-06-29 — **pending file handoff** to place + annotate. Remaining slots in *Still to source*.

> **Architectural reminder.** Ricercar is **abstract visual music**, not depiction. The subject is a small set of independent **lines** (the voices), each owned by a frequency register and carrying a stable colour family, drawn on a **flowing colour-field ground**. There is no orchestra, no scene, no representational object. Every reference below is read for *morphology, colour-as-identity, and flow* — never for any literal imagery.

---

## How to read this folder

*(Read cover-to-cover before authoring — PRESET_SESSION_CHECKLIST.md. Authoring from the prompt text alone, or against self-judgment instead of these images, is the failure mode.)*

**None of these images is a faithful rendering of "Ricercar as it should appear."** Each is read *only* for the trait its annotation calls out. They define the **aesthetic family** — independent music-tied lines, colour-as-identity, flowing/merging colour masses, accents as sprays — not a pixel-match target. A Ricercar frame should belong in the same visual conversation as Fischinger's studies and the color-organ tradition, never identical to any one image.

**Two disciplines apply across every image:**

1. **Trustworthy = morphology + colour-identity logic; everything else is illustrative.** Trust the *idiom* — independent weaving lines, distinct stable colour per voice, drifting/merging colour ground, spray accents. The specific hues in any reference are illustrative. The single binding colour constraint is **legibility: one stable, well-separated colour family per register-lane** (dark-low / warm-mid / bright-high), with valence shifting warmth/saturation and arousal shifting vigour.
2. **Density ranges with the music — never read a single image's density as the target.** Voice count = active-lane count = how many registers sound at once. Sparse passages light few lanes; dense counterpoint lights all three and braids. The resting state keeps the field open. The trait to **actively disregard** in any single image is its density-as-a-target.

---

## Reference images

| File | Mandatory — read this | Actively disregard | Provenance |
|---|---|---|---|
| `01_macro_weaving_lines.jpg` | **The headline composition.** ≥3 **distinct register-coloured lines** (indigo LOW / amber MID / cyan HIGH) that **weave and cross** — voices enter banded in their registers at the left, interweave through the centre (the counterpoint), a second high voice enters from the right. Colour = register identity; soft **painterly** edges on a flowing, merging light colour ground. Read for: line *multiplicity*, *crossing/braiding*, register→colour, ground reading through. | The **smoothness / cleanliness** — a schematic anchor, **not** a fidelity target; the live preset's lines are more organic, varied-width, pigment-textured, and braid more densely. The specific hues (tunable). The exact crossing count/placement. | **Hand-authored synthetic anchor** (not photographic, not AI-gen): SVG composed by Claude + rasterised via macOS `qlmanage`, 2026-06-29. **Replacement plan (D-065(b) spirit):** swap for a real `RENDER_VISUAL=1` frame once Ricercar.3/.4 renders weaving voices. |

*(Photographic positives for `02` / `04` chosen by Matt 2026-06-29 — ink-in-water plume + one tulip-field aerial — pending file handoff; their annotations land when the files are placed.)*

---

## Trait matrix (the substance contract — ported from RICERCAR_DESIGN.md §1–§2)

| Trait class | Traits |
|---|---|
| **The voices (subject)** | A small set of independent weaving **lines**, each tied to one register; lines enter one at a time, braid, and converge; each line a stable colour family (low=indigo, mid=amber/gold, high=cyan/bright). The headline subject — never a single reactive texture. |
| **The ground (substrate)** | A **flowing, merging colour field** — divergence-free (curl-noise) advection so deposited colour drifts and bleeds wet-into-wet; slow decay so the field is a moving present with fading memory (not an ever-filling archive). |
| **Character** | Line crispness reads register character: bright/high-centroid → thin, fast, fine filament; dark/low-centroid → broad, slow, smeared wash. |
| **Accents** | Voice-entry **flares** (a brief bright announcement at a line's head on its register's onset); sparse **splatter-sprays** on composite beats — punctuation, never the primary motion. |
| **Colour logic** | Colour = register identity. The canvas's colour balance mirrors the registral balance of the music; its colour history mirrors the arrangement. Palette open and tunable; **legibility is the binding constraint**, not specific hues. |
| **Motion** | Continuous-energy-primary: voices wake and steer on register energy **deviation**; onsets announce/accent only. Slow global swirl + density arc on arousal/section. |

---

## Anti-references (the certification bar — what a frame must NOT look like)

Staying out of these is the bar, not pixel-equivalence with any positive. Shared failure-mode list with Skein/Arachne, plus the *Fantasia*-specific ones. **To source** (sourced photography/illustration/film-still preferred; AI-gen only under the D-065(b) `_aigen` carve-out — resolve the lowercase-suffix lint note in Skein's README first if used).

- `05_anti_neon_spaghetti` — **glowing neon line-tangle / sci-fi tron-grid** → guards: the lines must read as **painterly voices on a colour ground**, not glowing wireframe.
- `05_anti_particle_fountain` — a **neon particle burst / fountain** → guards: voices are continuous weaving lines depositing paint, not a particle spray.
- `05_anti_kaleidoscope` — **kaleidoscopic / mirror-symmetric** layout → guards: asymmetric, free counterpoint; no symmetry.
- `05_anti_single_blob` — a **single reactive blob / one pulsing shape** → guards: ≥3 independent lines on a contrapuntal passage; the subject is *many* voices.
- `05_anti_representational` — **recognisable clouds / landscapes / comets / orchestra silhouettes** (the Disney softening Fischinger objected to; the faithful-homage path Matt declined) → guards: pure abstraction — colour, line, flow, accent only.

---

## Audio routing notes

The §3.2 contract — **one audio primitive per visual layer** (FA #67), all **deviation-normalised** (D-026). Continuous energy is primary; onsets are accents only (CLAUDE.md §Audio Data Hierarchy).

| Visual layer | Single audio primitive | Channel |
|---|---|---|
| LOW / MID / HIGH voice wake & steer | `bassDev` / `midDev` / `trebDev` | primary / continuous |
| Voice vertical position within lane | that lane's 6-band split | character |
| Substrate flow / decay | broadband deviation + arousal | slow global |
| Voice-entry flare | per-lane onset (`beatBass`/`beatMid`/`beatTreble`) | accent |
| Global splatter | `beatComposite` | accent |
| Line crispness | `spectralCentroid` | character |
| Colour family per lane | register identity | structural |
| Palette warmth / saturation | valence / arousal (smoothed in state, FA #25) | slow global |
| Density / convergence arc | section boundary + arousal + active-lane count | slow global |

---

## Still to source (pending Matt — does NOT block Ricercar.1; gates Ricercar.2 authoring)

Ricercar.1 is the design + scaffold; the curated image set is the second half of the reference lock and is **Matt's to source** (as the Skein positives were). Target idiom — copyright-safe stills/photography preferred, original abstract imagery, no photographs of copyrighted artworks:

- ✅ **`01_macro_weaving_lines.jpg` — independent weaving lines on a colour ground.** Placed as a hand-authored synthetic anchor (2026-06-29); replace with a real preset frame post-Ricercar.3/.4.
- ⏳ **`02_meso_*` — flowing/merging colour masses.** **Chosen by Matt** (ink-in-water multicolour plume — distinct colours bleeding wet-into-wet side by side); pending file handoff to place + annotate. *Disregard when placed:* the upward-plume directionality + pure-white ground.
- **`03_micro_*` — line crispness range.** A fine, crisp filament pole and a broad, smeared wash pole (the centroid axis). *(The `02` plume half-covers this — wisp tendrils vs broad billows; a dedicated micro is optional.)*
- ⏳ **`04_palette_*` — register colour legibility.** **Chosen by Matt** (one tulip-field aerial — well-separated colour bands read as distinct parts); pending file handoff. *Disregard when placed:* the **ruler-straight parallel rows** (voices weave, never run straight) + perspective/horizon. Keep one tulip shot, not both (D-065(a) — no padding).
- **The five `05_anti_*`** above.
- ***Fantasia* Bach segment — annotated INSPIRATION, not a positive.** If a still is included, its annotation must mark **every** representational property (clouds, comets, orchestra silhouettes, the blue-and-gold live-action opening) as **disregard** — take only the idea of independent music-tied lines on a flowing colour ground.

---

## Cross-references

- [`docs/presets/RICERCAR_DESIGN.md`](../../presets/RICERCAR_DESIGN.md) — creative architecture (§1), reference decomposition (§2), musical contract (§3), rendering (§4), acceptance (§8).
- [`docs/presets/SKEIN_DESIGN.md`](../../presets/SKEIN_DESIGN.md) — the canvas-hold mv_warp + marks-on-top + per-track-seed stack Ricercar reuses.
- [`docs/presets/FILIGREE_DESIGN.md`](../../presets/FILIGREE_DESIGN.md) — the compute-agent trail loop the voices port.
- [`../_NAMING_CONVENTION.md`](../_NAMING_CONVENTION.md) — filename regex + size/format limits.
- `DECISIONS.md` D-026 (deviation audio), D-037 (silence-non-black), D-064/D-065 (reference library structure + `_aigen` carve-out), D-142/D-143/D-149 (Skein canvas-hold paradigm).
</content>
