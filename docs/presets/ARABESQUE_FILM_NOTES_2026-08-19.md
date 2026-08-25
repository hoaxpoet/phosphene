# *Arabesque* (1975) — observed motion notes

**Source:** Matt's screen recording of the film, 2026-08-19 (`Screen Recording 2026-08-19 at
12.15.43 PM.mov`, 1970×1470 @ 60 fps, 379.7 s = 6:19; a YouTube capture, player chrome visible
in the first and last ~10 s). Staged to
`docs/VISUAL_REFERENCES/_incoming/frames/`.

**Why this document exists.** `WHITNEY_PROGRAM.md` was first drafted from Whitney's published
BASIC/Pascal listings without anyone having watched a frame of the films — recorded as the
program's primary unverified risk (§11.4). This is that risk being retired. **These notes are
observation and they supersede the program doc's inferences wherever the two disagree.** They
disagree in four material places.

**Method.** Frames extracted with ffmpeg and read as sequences (D-064 — the reader is the eyes):
a 10 s macro sweep across the whole film (38 frames, two contact sheets), then two 2 s-interval
sequences over the passages the macro sweep flagged as distinct.

**Evidence sheets**

| Sheet | Coverage | What it establishes |
|---|---|---|
| `sheet_1.png` | t = 5–195 s, 10 s steps | the macro arc, first half |
| `sheet_2.png` | t = 205–375 s, 10 s steps | the macro arc, second half; the rosette passage |
| `rosette_build.png` | t = 268–298 s, **2 s steps** | the closed-curve morph — the film's central mechanism |
| `dot_band.png` | t = 100–130 s, **2 s steps** | the tiled dotted frieze — the modulo-wrap section |

---

## 1. The four findings that change the program

### F1 — *Arabesque* is a LINE film, not a dot film. ⚠ Contradicts program §8.

The overwhelming majority of screen time is **a single continuous closed luminous curve**: a
thin, bright, white-to-pale-lavender stroke with soft halation on near-black. Dots appear as a
secondary texture — curves *sampled* into beads, and one extended passage of genuinely dotted
fields — but the film's iconic image is a **drawn line**, not a point cloud.

The program doc characterised Arabesque as the shear-wrap point figure from `ARABESQUE.BAS`.
The listing is presumably still correct about the arithmetic; it is **wrong about what the film
looks like**, and the program was about to build the wrong thing.

**Consequence:** the lead preset should be a `line_strip` figure, which is Dragon Bloom's
shipped and proven marks-on-top path (1536 verts / 3 instances) — not the `"point"` primitive,
which the program flagged as plumbed-but-never-shipped. **This retires the program's one
engine-risk item rather than confronting it.**

### F2 — The symmetry order HOLDS while the figure MORPHS. ⚠ Contradicts program §1, §5.

`rosette_build.png` is one continuous 30 s passage. Across all 16 frames the figure keeps
**5-fold symmetry**. What changes is the figure's *character*, cycling through a family:

> loose open tangle → 5-spoke splay → five broad petals → petals with inner loops →
> petals inside a closing circle → sharp star inside the ring → **pentagon with straight edges**
> → clean pentagon → star again → arcs break apart → reforms → petals → splay → tangle

So there is a genuine order↔disorder axis — and it is **not** the ray-collapse the program built
its musical claim on. The program predicted "the arm count changes"; the film shows **the arm
count is stable and the tightness changes**. The emblem tightens into a crisp, closed,
straight-edged figure and then unravels into open arcs.

**Consequence, and it is an improvement:** map consonance to **how tight and closed the figure
is**, not to the arm count. A tangle is still a drawing — legible, attractive, on-concept. A
scattered point cloud in the dissonant regime is just noise. The line figure degrades gracefully
where the dot field degrades to hash, which directly answers the program's §12 DECISION-NEEDED #2
("what happens when the music is unharmonic").

### F3 — Colour is compositional, not indexical. ⚠ Contradicts program §5, F8.

The central figure is **white / pale lavender, essentially always**. Saturated hue lives in a
separate element: thin mirrored arcs at the left and right frame edges — a cartouche or pair of
"wings," each carrying a small ellipse. Those wings change hue between passages (blue, red,
yellow, magenta, teal, green) and are visibly a *different, simpler figure* than the central one.

Whitney's Music Box convention of `hue = 360·(i+1)/N` — a rainbow across the harmonic index —
**is not what this film does.** Importing it would produce something that looks like a modern
generative-art demo rather than like Arabesque.

**Consequence:** figure white, hue in the frame elements. This also solves a Phosphene problem
for free: a white-cored stroke with HDR bloom is the "one modern layer" Matt already chose
(§11.1), and it is period-honest — the halation is what filming a vector CRT produces.

### F4 — The composed frame is a persistent design element. Not in the program doc at all.

Nearly every frame in the film has bilateral structure: a central figure plus mirrored
elements at the edges — arcs, small ellipses, occasionally top-and-bottom as well. Islamic
ornament is Whitney's stated motivation for this film and it shows up as **composition**, not
just as motif. The frame is never edge-to-edge scatter; there is always negative space and
always a border.

**Consequence:** cheap to implement, high value, and it is most of the difference between "a
parametric plot" and "a picture." This is a direct answer to the program's thinness worry
(§11.1).

---

## 2. The three distinct on-screen characters

One film, three visual registers. This is a better basis for a family of siblings than the
program's original three-source split, because all three are *watched*, not inferred.

### Character A — the morphing emblem (t ≈ 255–305, and much of 15–55)

A single closed luminous curve, n-fold symmetric, morphing continuously through
tangle → petals → star → polygon → tangle. Thin bright white stroke, soft halation, near-black
ground with a faint blue-violet vignette. Coloured mirrored wings at the frame edges. Stroke
reads roughly 2–3 px at 400 px wide, so genuinely fine at 1080p.

**This is the film's headline image and the strongest preset candidate.**

### Character B — the tiled frieze (t ≈ 60–130, 155–235)

A horizontally repeating band of ~5 identical cells, each holding vertical ellipses and rings,
built from **dotted / beaded curves** in saturated yellow, orange, magenta, cyan, blue and white.
Layered: a faint dotted background lattice, mid-layer ellipse outlines, bright foreground rings
with bloom. Occupies the middle ~60 % of frame height; top and bottom stay dark.

Across `dot_band.png` the cells **breathe** — tall thin ellipses widen toward circles and back —
and the repeat phase drifts horizontally. This is the modulo-wrap of `ARABESQUE.BAS` doing its
work, and the on-screen result is **a frieze**, an ornamental border repeat. It is *not*
"a circle shearing into diagonal strands," which is what the program doc predicted.

Densest and most colourful imagery in the film.

### Character C — the near-empty composition (t ≈ 315–345)

One or two glowing strokes on an otherwise black frame — a single shallow arc with curled ends,
a cusp, a lone ellipse. Extremely sparse and completely confident.

**Worth dwelling on**, because it falsifies the program's stated fidelity risk. These frames are
not thin. They work because the *stroke* is beautiful — bright core, controlled halation,
decisive curvature — and because the composition is deliberate. Sparseness was a choice Whitney
made repeatedly, not a budget he was stuck with.

---

## 3. Motion character — the details that only a sequence shows

- **The morph is continuous, not cut.** At 10 s sampling the film looks shot-based; at 2 s it is
  clearly one figure evolving. Anyone reading the macro sheets alone would mis-specify this.
  Hard cuts do exist between the three characters above, roughly every 30–60 s.
- **Rate is constant.** No easing, no ramp-in, no settle. Consistent with the servo-driven
  analog machine, and with program §9.4's "do not ease."
- **No long trails.** The glow is **halation around a stroke drawn complete each frame**, not a
  decaying comet-tail behind moving points. The figure is fully present in every frame.
- **A whole 30 s passage without the figure leaving the screen.** It never blanks, never resets,
  never restarts. It is continuously *there*, continuously changing.
- **Density range within a single film is enormous** — from one arc (character C) to a dense
  five-cell multi-layer frieze (character B).

---

## 4. What this means for the trail/legibility constraint (program §9.2)

The program derived **(1 − decay) ≳ q·N·Δf** by running the dot-field law with feedback trails,
and made it a load-bearing design constraint. The relation is still arithmetically true, but
**the film does not operate in that regime**, because it does not use decaying feedback at all.

For a line-figure preset the equivalent question is not "how long is the trail" but "how does the
stroke glow." That is bloom on a bright-cored stroke, which Phosphene does natively
(`rgba16Float` + `PostProcessChain`), with no accumulation buffer and none of the conflict.

**§9.2 therefore demotes from a design constraint on the lead preset to a constraint on the dot
field**, if and when the dot field is built. It should not be deleted — it is a real finding —
but it should stop driving the architecture.

---

## 5. Still unverified

- *Permutations* (1968) and *Matrix III* (1972) — **still not watched.** These notes are
  *Arabesque* only. The dot-field character the program's lead preset was built on is most
  associated with *Permutations*, so if the dot field is revived, that film is its gate.
- The recording is a YouTube capture: colour has been through an unknown encode chain twice.
  Treat hue as indicative, and value/contrast as indicative-only. Stroke width and composition
  are trustworthy; exact chroma is not.
- Whether the three characters are three *programs* or one program under different parameter
  sets is not determinable from the film.

---

*Written 2026-08-19 from Matt's recording. Supersedes `WHITNEY_PROGRAM.md` inferences on
sibling character, colour, render path and the trail constraint.*
