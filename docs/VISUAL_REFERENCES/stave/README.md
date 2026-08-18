# Visual References — Stave

**Family:** waveform — spectral dispersion of the live signal
**Render pipeline:** particles (CPU band split → one fullscreen dispersion pass) + feedback
**Rubric:** lightweight — a 2D luminous plot with no lighting, no G-buffer and no material
stack, so the full rubric's ≥3-distinct-materials gate is unreachable by construction. Same
reclassification as Fractal Tree (D-212 / FTR.1) and the Waveform / Plasma precedent.
**Last curated:** 2026-08-17 (CHR.3f) — **fully recurated after the CHR.3b rebuild.**

> ## ⚠ This set replaces the one curated at CHR.1.3, which described a different preset
>
> The original set was five renders of the Milkdrop source `Martin - charisma` — beaded cyan
> traces on a ruled field — and it was the target for a Stave that scrolled an 8 s history
> plot. Matt's M7 rejected that preset outright (*"deeply boring"*), and the rebuild replaced
> its subject entirely. Comparing the current preset against those images produced FAILs by
> design, which makes the gate useless rather than strict.
>
> **Every image here is now an in-engine capture of the shipped build** (D-065 permits real
> photography or in-engine capture), and **every anti-reference is a real measured failure**
> from CHR.3b–e with the exact config that reproduces it. None is hypothetical.

## Target read

**The visible light spectrum aligned to the frequency spectrum.** The live waveform is split
into eight bands and each is drawn in the colour of its own frequency — 82 Hz at 662 nm deep
red, through amber, green and cyan, to ~11 kHz at 404 nm violet. One pass across the visible
band, compressed rather than octave-wrapped. The colour is never a label: a red curve **is**
low frequency, instantaneously and by construction.

Bands are offset by wavelength so the spectrum separates the way a prism separates light — red
deviating least, violet most — and **that separation is driven by how much signal is on
screen**, so the spectrum opens and closes with the music.

Concept in Matt's words, 2026-08-16: *"align the visible light spectrum to the frequency
spectrum for this preset."*

## Reference images

Numbered in priority order. See `../_NAMING_CONVENTION.md`. Images are **gitignored repo-wide**
(0 tracked under `docs/VISUAL_REFERENCES/`), so a fresh checkout has the annotations but not
the pictures — regenerate with the §Provenance commands.

| File | Annotation (what to learn from this image) |
|---|---|
| `01_macro_dispersed_wave.png` | The composition, and the agreed look — this frame is from the build Matt signed off. A near-black ground; a heavy red bass gesture low in the frame; an amber/yellow body through the middle; a fine cyan-violet crest on top. The wave fills most of the vertical area and **touches but never crosses** the frame edge. ⚠ Trust this for overall weight distribution and framing. |
| `02_meso_band_separation.png` | The hero detail: the bands are **individually legible** and stacked in wavelength order, red lowest through violet highest, each carrying its own copy of the wave. Where they overlap, colour **adds toward white** — that is mixed light, not a blend mode chosen for looks. This separation is what distinguishes the preset from a coloured oscilloscope. |
| `03_palette_frequency_to_wavelength.png` | Four materials, same mapping: M7 session (guitar rock) / Clair De Lune (solo piano) / Bleed (metal) / Take Five (jazz). ⚠ **The spectrum is weighted, not even.** Reds and ambers dominate every frame because that is where music's energy is; violet arrives as occasional glints. An evenly-lit rainbow means the tilt compensation is wrong — see `06_anti`. Note Clair De Lune's near-flat red band: solo piano genuinely has little below 100 Hz, and the image saying so is correct. |
| `04_atmosphere_converged_vs_open.png` | The driven dispersion. **Top: Take Five** — quiet, smooth, no transients; the bands converge to a tight bright ribbon. **Bottom: Bleed** — dense; the spectrum opens to full spread. Same code, same settings; only the music differs. If both look alike the spread has stopped responding, which is the `05_anti` failure. |
| `05_anti_rainbow_layer_cake.png` | **NOT this.** A *fixed* band spacing on quiet material: evenly spaced parallel stripes with barely any wave in them. On smooth quiet audio the wave excursions go small next to the gaps and the dispersion stops being an effect of the music and becomes permanent decoration. Reproduce with `STAVE_RENDER_FANMIN=0.34 STAVE_RENDER_FANMAX=0.34` on Take Five. |
| `06_anti_equalised_fringe_comb.png` | **NOT this.** Full spectral-tilt compensation (exponent 1.0): every band equalised to the same level, so the top bands arrive as a dense spiky comb and the frame reads as cheap rainbow hair. Reproduce with `STAVE_RENDER_TILT=1.0`. |
| `07_anti_clipped_off_frame.png` | **NOT this.** No frame knee: peaks run past the viewport and are cut off. Measured 1.42 NDC peak with 27/180 frames overflowing on this clip alone, and 1.53–1.98 across the corpus. Matt's M7 called this out directly. Reproduce with `STAVE_RENDER_KNEE=0`. |
| `08_anti_no_dispersion.png` | **NOT this.** Zero spread — every band on one axis. It still reads as a coloured waveform, and it is genuinely pretty, but the spectrum no longer separates and the preset loses the thing that makes it what it is. Kept because it is a *tempting* failure, not an ugly one. Reproduce with `STAVE_RENDER_FANMIN=0 STAVE_RENDER_FANMAX=0`. |

`target_animated.gif` — 4 s of the shipped build on the M7 session audio. **Motion is the
point**: the wave reforms every frame at audio rate. A still cannot show that, and the preset
this replaced passed still-review while being rejected in motion.

## Stylization contract

What DOES matter for this preset (substitute for the full rubric):

- [ ] **Colour is frequency, always.** Red is low, violet is high, by construction and with no
      lag. Nothing else may drive hue — a second colour channel would corrupt the one rule that
      makes the image readable. (This is why the stem tint was removed, not merely cut.)
- [ ] **The bands separate, and the separation breathes.** Quiet converges, dense opens. A
      fixed spread is `05_anti`.
- [ ] **The spectrum is weighted toward the red end.** Bass-dominant core, top end present but
      subordinate. An even rainbow is `06_anti`.
- [ ] **The wave fills the frame without leaving it.** Peaks reach the edge and fold; the body
      keeps its size. Both halves matter — shrinking the image to fit is as wrong as clipping.
- [ ] **It is the actual signal.** Drawn from the live waveform buffer every frame, not a
      smoothed envelope. The preset's own history is the warning: it was `family: waveform` and
      read no waveform at all.
- [ ] **Readability at silence (D-037).** The ground persists; the wave flattens to a line and
      the spread returns to rest. Silence is flat *and* not black — no autonomous motion.

## Anti-references

What this preset must NOT look like:

- **A static rainbow layer cake** (`05_anti`) — the dispersion stops responding.
- **An equalised fringe comb** (`06_anti`) — cheap rainbow, the failure mode a naive
  frequency→hue mapping produces by default.
- **Clipped, running off-frame** (`07_anti`) — rejected at M7.
- **Flat, undispersed** (`08_anti`) — pretty, and still wrong.
- **A scrolling plot on a ruled field.** The retired preset: an 8 s history window, beat
  verticals, static horizontals, star sparkles, a stem-tinted field. Rejected at M7 on
  2026-08-16 (*"deeply boring"*, *"what is the purpose of the horizontal and vertical grid
  lines?"*, *"why the starry background"*). No image is kept — the code is deleted and it is not
  worth resurrecting to photograph — but nothing here should ever scroll, rule the field, or
  decorate it.

## Audio routing notes

| Visual layer | Driver | Timescale |
|---|---|---|
| The wave itself, all eight bands | the raw waveform buffer (slot 2), band-split on the CPU | per frame |
| Band spread (the dispersion) | `waveformOccupancy` (CHR.3c) | ~0.12 s smoothing over a 20 s per-band envelope |
| Band colour | **not audio-driven** — fixed by physics, `centreHz → nm` | constant |

⚠ **`audio_routes` is empty and that is deliberate.** The preset's driver is the waveform
buffer, and `waveformOccupancy` — created for exactly this — cannot be asserted by QG.1. **The
original reason (BUG-090, frozen fixtures) is now fixed and was the wrong reason**: the fixtures
were regenerated on 2026-08-17 and carry the column, but it is **0.0000 on all three tracks with
zero variance**, because `WaveformOccupancy` is ticked in the *render path* and
`FixtureSessionCaptureGenerator` runs only the MIR pipeline. This is the QG.1.1 limitation
(offline fixtures cannot reach render-path-derived values), not a fixture-staleness problem.
Declaring a route the gate cannot prove would be worse than declaring none, so certification
stays blocked until the generator ticks the occupancy model — a generator change, not a preset
change.

## Provenance

**Source lineage:** `Martin - charisma`, a butterchurn built-in (`butterchurn-presets` npm,
1 of 100 in the curated legends set). `source_form: butterchurn_builtin`, sha256
`c8d00412887028bb4b4a6ae79c818c89634a270625aced9584cb1cd04a11c30e`, committed as
`source_preset.json` following the Nacre precedent.

**Divergence (D-121).** The rebuild moved *toward* the source on one axis and far away on
another. The source's traces are waveform-driven per-frame geometry, and so are Stave's now —
the first Stave's scrolling history ring was the anomaly. Stave diverges on **palette
character** (frequency mapped to physical wavelength, which the source does not do) and on
**primary feature stack** (the amplitude-driven dispersion). Both are measurable side by side.

**Regenerate every image in this set** — all are in-engine captures of the shipped build:

```sh
STAVE_RENDER_WAV=~/Documents/phosphene_sessions/2026-08-17T16-19-13Z/raw_tap.wav \
STAVE_RENDER_OUT=/tmp/ref/m7 STAVE_RENDER_START=12 STAVE_RENDER_SECONDS=4 \
STAVE_RENDER_W=1280 STAVE_RENDER_H=720 \
  swift test --package-path PhospheneEngine --filter renderStaveSequence
```

`03` tiles frame 0150 from four clips (M7 session t=12, Clair De Lune t=150, Bleed t=200, Take
Five t=120); the corpus clips are cut from `beat-match-test-session/raw_tap.wav` at offsets
5011 / 3703 / 1283 s. `04` stacks Take Five over Bleed. Anti-references use the same command
plus the one override named in each row above.

## Curation notes

- **The whole set is in-engine, and that is a deliberate choice.** The concept is a physical
  mapping rather than an imitation of an artwork, so the honest target is the agreed render.
  Matt's M7 sign-off on 2026-08-17 is what makes `01`/`02` authoritative rather than
  self-referential.
- **Anti-references are reproducible failures, not sketches.** Each is a state this preset
  actually passed through and was measured in, and the harness keeps env overrides
  (`STAVE_RENDER_TILT` / `_FANMIN` / `_FANMAX` / `_KNEE`) specifically so they can be
  regenerated rather than remembered.
- **One image was deliberately not made:** the retired scrolling plot. Its code is deleted, and
  rebuilding it to photograph a preset nobody should imitate is not worth the increment.
