# Visual References — Stave

**Family:** waveform — beat-ruled plotting register
**Render pipeline:** particles (CPU history rings → line/ribbon strips) + feedback
**Rubric:** lightweight — a flat 2D plot with no lighting, no G-buffer and no material
stack, so the full rubric's ≥3-distinct-materials gate is unreachable by construction.
Same reclassification and reasoning as Fractal Tree (D-212 / FTR.1) and the
Waveform / Plasma / Spectral Cartograph precedent.
**Last curated:** 2026-08-14 (CHR.1.3, rendered by Claude Code from the butterchurn
built-in against real music). Matt's read comes at M7, on a render — not on these
annotations.

**Target:** a Phosphene uplift inspired by the Milkdrop preset **`Martin - charisma`**
(butterchurn built-in, 1 of 100 in the curated legends set). MD.6 inspired-by uplift #8.

## Target read

A **beat-ruled plotting field**. Dotted luminous traces wander across a field ruled in both
axes, under a hazy atmosphere, with star sparkles scattered through it and the whole field's
colour drifting slowly. The traces are the fast, literal channel — they plot the music now.
Everything behind them is slow.

**The concept sentence, post-D-216:** *low against high, ruled by the beat, in a room the
stems tint.* Two traces — rhythm (`subBass+lowBass`) against melodic
(`midHigh+highMid+high`) — plot band energy in time on a grid whose vertical rules are the
actual beat. The stems do **not** touch the traces; they tint the field. See
`target_animated.gif` for the source's motion (real-music-driven, 12 s of Dance Yrself
Clean from the `beat-match-test-session` tap).

## Reference images

Numbered in priority order. See `../_NAMING_CONVENTION.md`. Images are **gitignored
repo-wide** (0 tracked under `docs/VISUAL_REFERENCES/`), so a fresh checkout has the
annotations but not the pictures — regenerate them with the §Provenance commands.

| File | Annotation (what to learn from this image) |
|---|---|
| `01_macro_dotted_traces_on_grid.png` | The composition. A **horizon**: hazy atmosphere in the upper half, traces inhabiting a band across the lower-middle, near-black beneath. The field is ruled in **both axes** — warm/orange horizontals, violet verticals — and star sparkles are scattered through the whole frame. Note the traces are **many** in the source (4–8 overlapping); Stave draws **two** (CHR.1 re-scope). ⚠ Trust this for *composition and layering*, not for trace count. |
| `02_meso_bead_spacing.png` | The hero detail: traces are **discrete beads, not solid lines**. Both bead **size** and **spacing** vary along a single trace, beads carry soft glow halos, and several traces overlap and cross freely. This is the single trait that most separates the target from a plain line plot — see the anti-reference. |
| `03_palette_field_hue_drift.png` | Four frames across the clip. The **field** hue drifts (teal → violet/magenta → warm orange → green) while the **traces stay cyan** throughout. Colour lives in the field and the sparkles, not in the traces. ⚠ This is why D-216 lands *closer* to the source, not further: the source has no per-trace colour identity either. |
| `04_specular_star_sparkle_field.png` | Sparkle detail — 4-point star flares with soft halos, in **both warm and cool** hues, over the ruled field, plus soft out-of-focus blobs and a faint cloud texture behind. ⚠ **Corrected during curation:** the sparkles are **scattered**, NOT locked to grid intersections. An earlier reading of the macro frame claimed they sat on grid crossings; the crop refutes it. Do not build a preset that places sparkles at grid nodes. |
| `05_anti_solid_line_plot.png` | **NOT this.** Our own CHR.2 spike flat control: two thin solid polylines on a bare dark ground with pale verticals. Legible, correctly beat-aligned, and completely lifeless — no beads, no atmosphere, no sparkle, no depth, no colour. This is the accidental output of building the geometry and stopping, and it is the exact gap CHR.3 exists to close. |

## Stylization contract

What DOES matter for this preset (substitute for the full rubric):

- [ ] **Beaded traces, never solid lines.** Bead size and spacing both vary along the trace;
      beads carry a soft halo. A solid polyline fails this preset (`05_anti`).
- [ ] **Layered depth.** Atmosphere/haze above, ruled field behind, traces in front,
      sparkles distributed through. A single flat plane fails.
- [ ] **Colour lives in the field, not the traces.** Traces hold a near-constant cool hue;
      the field tint drifts. Per **D-216** the field tint is the **stem** channel
      (`drums+bass` vs `vocals+other`, ~3.0 s latency — invisible at this timescale).
- [ ] **The grid is the beat.** Vertical rules land on cached `BeatGrid` beats (CHR.2
      measured median trace-to-beat offset **0 ms** on the band driver). Horizontal rules
      are the *stave* and are static. This is Stave's divergence from the source, whose
      grid is decorative — and it is the D-121 axis the source structurally cannot have.
- [ ] **Readability at silence (D-037).** Field, haze, grid and sparkles persist and drift;
      the traces flatten toward the centreline but the frame is never black and never frozen.
      **No autonomous trace motion** — a quiet passage flatlining IS the design.
- [ ] **Readability at peak energy.** Traces excurse without leaving the frame — CHR.2
      measured a fixed gain clipping on Dance Yrself Clean, so per-trace normalisation is
      required — and the field must not white out.

## Anti-references

What this preset must NOT look like:

- **A solid-line oscilloscope or graph** (`05_anti_solid_line_plot.png`). The failure mode
  a shader session produces by default. Beads and atmosphere are the difference.
- **Graph paper.** CHR.2 measured Bleed at 22.9 gridlines per 8 s window (172 bpm) — above
  roughly 150 bpm the beat rules stop reading as a pulse and start reading as ruling.
  Needs a density treatment, decided in CHR.3.
- **Sparkles pinned to grid intersections** — see the `04` annotation. Scattered, not nodal.
- **Per-trace instrument colour-coding.** Retired by **D-216**: the colour is ~3 s behind
  the mark it would be labelling, and hue assigned by frequency band asserts instrument
  identity even on material where those instruments do not exist. The source does not do
  this either.
- **A moving/drifting field that animates on its own.** The traces' motion is the signal.
  Adding ambient motion "so it isn't boring" is the failure this source was chosen to avoid.

## Audio routing notes

Per **D-216**, one primitive per visual layer (FA #67), split by timescale:

| Visual layer | Driver | Timescale | Evidence |
|---|---|---|---|
| Rhythm trace position | `subBass + lowBass`, each EMA-centred (FA #31) | ~0.3 s | CHR.2: median trace-to-beat offset 0 ms |
| Melodic trace position | `midHigh + highMid + high`, each EMA-centred | ~0.3 s | as above; needs **per-trace gain**, std is 4.4–17.5× below rhythm |
| Vertical rules | cached `BeatGrid` beat times | in-time | CHR.2: derived rate matches `grid_bpm` exactly (71/71, 97/98, 172/174.6) |
| Field tint | stems — `drums+bass` vs `vocals+other` | ~3.0 s | D-216; latency-invisible on a slow surface, fatal on a mark |

**Never on a trace:** any per-stem quantity. CHR.2 measured `r(position, colour)` at
**−0.15…+0.25** at the moment a mark is drawn.

**Known unfixable:** Bleed collapses the two traces into one band (`r +0.695`). It is what
the material does; do not spend rounds on it.

## Provenance

**Source:** `Martin - charisma`, a **butterchurn built-in** (`butterchurn-presets` npm
package, 1 of 100 in the curated legends set). `source_form: butterchurn_builtin`.
**sha256 of the artifact actually read:**
`c8d00412887028bb4b4a6ae79c818c89634a270625aced9584cb1cd04a11c30e`
(SHA-256 of the extracted `{"preset": …}` JSON, 9 073 bytes.)

The source JSON is committed as `source_preset.json`, **following the Nacre precedent**
(`docs/VISUAL_REFERENCES/nacre/` commits its own, as do the other shipped inspired-by sets).
D-116 bullet 4 names `.milk` files and the pack at its source URL; a butterchurn built-in is
MIT-licensed npm package content, and D-215 requires the sha256 *of the artifact actually
read*, which presumes the artifact stays identifiable. Consistency across reference sets
beats a one-off conservative reading.

**Regenerate the reference renders:**

```sh
cd tools/milkdrop-render
npm install butterchurn butterchurn-presets milkdrop-preset-converter puppeteer
# real music — 12 s of Dance Yrself Clean from the corpus tap (render clock t = tap t + 231.5)
ffmpeg -ss 3150 -t 12 -i ~/Documents/phosphene_sessions/beat-match-test-session/raw_tap.wav \
  -ac 1 -ar 22050 -y music.wav
# extract the built-in to a scratch file (do NOT write it into the repo), then:
node render-gif.js /tmp/stave_refs "<scratch>/Martin - charisma.json"
```

Frames used: `01` = n28, `02` = n24 cropped `210:110:20:150`, `03` = n5/22/40/57 tiled 2×2,
`04` = n30 cropped `190:150:120:20`. `05` is our own CHR.2 spike
(`StaveLookSpike`, `STAVE_COLOUR=0`), not source-derived.

## Curation notes

- **Trace count.** The source runs 4–8 overlapping traces, but they are one undifferentiated
  cyan mass — a *texture*, not voices. Stave draws **two driven traces** (the most CHR.1
  measured as separable) plus optional non-semantic ghost companions for density. See
  `STAVE_DESIGN.md` D2.
- **One reading corrected during curation** — the `04` annotation. Recorded rather than
  silently fixed, because the macro frame really does suggest nodal sparkles and the next
  reader will make the same mistake.
