# Visual References — Rosette

**Family:** `geometric`
**Render pipeline:** `direct + mv_warp`, marks-on-top overlay (`strandsOnTop` — a fullscreen-triangle
SDF-in-fragment pass, Skein's pattern). See `docs/presets/WHITNEY_PROGRAM.md` §6 and the WHIT.0
look-spike (`docs/ENGINEERING_PLAN.md`, Phase WHIT).
**Rubric:** lightweight — a single luminous line figure on a near-black ground; the §12 3D-surface /
material-count matrix does not apply. The load-bearing gates are the two-term epicycle's fit to the
observed state family (WHIT.0 task 2) and Matt's live M7.
**Last curated:** 2026-08-25 (WHIT.1a), by Claude from Matt's own screen recording of the source film.

> **Single-source preset.** Rosette is not a mood-board synthesis — it is a direct port of one
> specific, named film: John Whitney Sr.'s *Arabesque* (1975). Every positive reference below is a
> frame of that film (Matt's recording, `docs/VISUAL_REFERENCES/_incoming/Screen Recording
> 2026-08-19 at 12.15.43 PM.mov`, 1970×1470 @ 60 fps, 379.7 s). There is no external stock-photo
> mood board because none is needed: the target is not "an aesthetic family," it is this film.
> Read `docs/presets/ARABESQUE_FILM_NOTES_2026-08-19.md` before this folder — it is the primary
> source and records four ways the original program doc's inferences were wrong before anyone had
> watched a frame.

---

## How to read this folder

None of these is a pixel-target for a single frame (D-064) — the film is one continuously morphing
curve, and every reference below is one instant of that continuum. What is trustworthy across all
of them: **5-fold symmetry, a thin bright white-to-pale-lavender stroke with soft halation, a
near-black ground, and mirrored coloured wing arcs at the frame edges.** What changes frame to
frame — and is the entire point — is the curve's *tightness*: loose open tangle at one extreme,
crisp straight-edged pentagon at the other, with petals and cusped stars in between (F2). Reading
any single image as "the" Rosette look is the mistake this folder is here to prevent; read the five
macro images **in the order presented** as one morph, not as five candidate designs.

**5-fold symmetry, verified, not assumed.** `03_macro_broad_petals` was checked by a radial
brightness-crossing count (a circle at mid-radius crosses each of 5 petal loops twice = 10
crossings; measured 10 at R=250px). The two open/splayed states (`01`, `02`) resisted the same
check — a mid-radius circle crosses their long trailing arms at inconsistent counts depending on
radius, because the arms extend to very different radii from each other in the open state. This
matches `ARABESQUE_FILM_NOTES` and WHIT.0 task 1's own read: **the compact states (pentagon, star,
petals) are unambiguously 5-fold by eye and by measurement; the open tangle/splay states are the
same curve family but resist a simple automated count from a still.** Do not force a fold-count
claim on `01`/`02` beyond "five-ish, consistent with the rest of the sequence."

## Reference images

| File | Trustworthy — read this | Actively disregard |
|---|---|---|
| `01_macro_tangle_open.jpg` | **One extreme of the morph.** Loose, open, self-intersecting loops with small hook terminals — the "unravelled" end of the tighten/unravel axis (F2). Note the loops do not touch or overlap the frame edges; there is always negative space. | The exact fold count (see note above — hard to verify from a still at this state). |
| `02_macro_five_spoke_splay.jpg` | **A distinct named state between tangle and petals**: radiating spoke arms meeting at a shared centre crossing, each arm ending in a small hooked terminal. Read the crossing structure at centre — six line-segments meet at one point, which is what makes this read as a "splay" rather than a "flower." | Exact fold count, as `01`. |
| `03_macro_broad_petals.jpg` | **The clearest 5-fold state** (verified by measurement, see above). Five broad, symmetric petal loops meeting at a small central pentagon of negative space. This is the mid-morph anchor — closer to "flower" than either extreme. | — |
| `04_macro_star_in_ring.jpg` | **A cusped 5-point star inscribed inside a near-circular outer envelope** — the outer boundary is not a separately-drawn circle, it is the same curve's outer lobes forming an implicit ring. This is the state the two-term epicycle hypothesis (WHIT.0 task 2) reproduces closely. | — |
| `05_macro_pentagon_straight_edges.jpg` | **THE reference for the generator's known limitation.** A genuinely straight-edged pentagon — flat sides, not curved. WHIT.0's two-term epicycle `z(t)=e^{it}+a·e^{-i(n-1)t}` never produces true flats at any `a`; it rounds this corner into a Reuleaux-like bulge. Compare directly against a WHIT.1c render at low `a` — if the sides are visibly convex, this is the miss task 2 predicted, not a new defect. The fainter parallel echo along each edge is an analog-recording artifact (interlacing / double-trace), not part of the drawn figure — do not reproduce it. | The faint ghost/echo line paralleling each edge. |
| `06_specular_stroke_core_halo.jpg` | **The stroke's cross-section, at real scale.** A tight, bright near-white core with a soft, narrower-than-you'd-guess halation — tighter than WHIT.0's first-pass estimate (halo ≈ 3–5× core width; this crop reads closer to 1.5–2×, per the WHIT.0 closeout finding). Use this crop, not the macro images, to calibrate halation width. | The second, dimmer parallel line crossing the frame — the same interlacing artifact as `05`. |
| `07_atmosphere_ground_vignette.jpg` | **How dark "near-black" actually is.** A genuinely unlit corner of frame — no visible vignette gradient at this exposure, just a very faint blue-violet undertone in the darkest corner. If a render's "near-black" ground reads as any shade of visible grey, it is too bright (WHIT.0 found its own first-pass value displayed ~20% grey after sRGB encoding — see the ENGINEERING_PLAN WHIT.0 entry). | The sliver of red wing-arc stroke at the frame edge — included only for scale reference. |
| `08_palette_wing_arc_ellipse.jpg` | **F4: the mirrored coloured wing arc + its small ellipse, together.** A thin, gently bowed arc in one hue running near-vertically at the frame edge, with a small closed ellipse loop nearby at a different point along its length — not touching, not concentric, a separate small closed shape. The central white figure never enters this crop; wing colour and figure colour are always spatially and chromatically distinct (F3). | The specific hue (blue here; the film cycles blue/red/yellow/magenta/teal/green across passages, per `ARABESQUE_FILM_NOTES` §1 F3). |

## Stylization contract

- [ ] **Colour modulation:** the central figure is white / pale lavender **always** — never apply
  `hue = 360·(i+1)/N` or any per-arm rainbow to it (that is the Whitney *Music Box* convention, a
  different film, and reads as a modern generative-art demo — `WHITNEY_PROGRAM.md` §5.1). Saturated
  hue lives only in the wing arcs + ellipses (`08`).
- [ ] **Audio coverage:** none at WHIT.0/WHIT.1a — the morph is clock-driven only (a deliberate
  scope cut so the look-spike answered "does the morph read" without a second variable). The
  harmony coupling is WHIT.1d, per `WHITNEY_PROGRAM.md` §5.
- [ ] **Readability at silence:** N/A this phase — no audio route exists yet to gate on silence.
  Once WHIT.1d lands, D-037 applies: the figure must render at zero input, not just at rest.
- [ ] **Readability at peak energy:** N/A this phase, same reason.

## Anti-references

No dedicated anti-reference image files — the failure modes below are documented in prose because
each is either (a) a named convention from a *different* Whitney film/program that must not leak in,
or (b) an engine-specific defect already found, fixed, and documented in this session, not a
generic aesthetic risk worth a stock photo:

- **The Whitney Music Box rainbow** (`WHITNEY_PROGRAM.md` §5.1, `ARABESQUE_FILM_NOTES` F3) — a
  per-arm hue sweep across the figure. Wrong film, wrong preset; see the Stylization contract above.
- **A raw, aliased `line_strip`** — Metal's hardware line rasterization has no antialiasing and no
  variable width. WHIT.0 avoided this from the start (chose an SDF-in-fragment approach instead of
  DragonBloom's raw `line_strip`), so it was never rendered, but it is the most likely accidental
  regression if a future session "simplifies" the geometry back to a GPU line primitive.
- **The beaded/dashed stroke** — found live at WHIT.0: a distance-to-nearest-discrete-sample-point
  computation (rather than nearest-point-on-segment) produces visible gaps at the midpoint between
  samples, reading as a dotted line instead of a continuous stroke. Fixed with a standard
  point-to-segment (capsule) SDF; documented in `docs/ENGINEERING_PLAN.md` Phase WHIT / WHIT.0.
- **The concentric-ring kaleidoscope artifact** — found live at WHIT.0: an unbound shader buffer
  (`mvWarp_fragment`'s fragment `buffer(0)`, distinct from the vertex-table `FeatureVector` at the
  same index) reads undefined GPU memory and drives a runaway hue-zoom feedback loop. Fixed by
  binding it explicitly; documented in the same ENGINEERING_PLAN entry.
- **Long comet-tails / accumulating trails** — the film draws the figure complete every frame
  (`ARABESQUE_FILM_NOTES` §4); the glow is halation around a stroke, never a decaying trail behind
  motion. A canvas-hold or heavy-decay implementation would be a different film's technique
  (Dragon Bloom's / Skein's), not this one.

## Audio routing notes

No routes exist yet — WHIT.0/WHIT.1a are clock-driven only (see *Stylization contract* above). The
proposed manifest, audited before being declared (QG.1, FA #67 — one primitive per layer), is
`WHITNEY_PROGRAM.md` §5.1 / §7: `tonalConsonance` → figure tightness (SETS the sweep position,
not additive to a free clock — the Nacre lesson, §5.3); `tonalPhaseFifths` → morph-family position;
`harmonicFlux` → symmetry-order step (discrete, held tens of seconds, never per-beat);
`bassDev`/`midAttRel` → stroke presence / floor rate. This is WHIT.1d scope, not this folder's.

## Provenance

| File | Source | Timestamp in source | Notes |
|---|---|---|---|
| `01_macro_tangle_open.jpg` | Matt's recording of *Arabesque* (1975), `_incoming/*.mov` | t=268.0 s | Frame extracted via `ffmpeg -ss`; downscaled to 1280px wide, JPEG q82. |
| `02_macro_five_spoke_splay.jpg` | as above | t=298.0 s | as above |
| `03_macro_broad_petals.jpg` | as above | t=272.0 s | as above; 5-fold verified by radial crossing count (this file) |
| `04_macro_star_in_ring.jpg` | as above | t=280.0 s | as above |
| `05_macro_pentagon_straight_edges.jpg` | as above | t=284.0 s | as above |
| `06_specular_stroke_core_halo.jpg` | as above | t=284.0 s | crop of the same frame as `05`, vertex/crossing region |
| `07_atmosphere_ground_vignette.jpg` | as above | t=284.0 s | crop of the same frame as `05`, empty upper-right region |
| `08_palette_wing_arc_ellipse.jpg` | as above | t=270.0 s | crop of the left wing arc + its ellipse |

The source recording itself is **not committed** (~1.5 GB; gitignored per D-211/LFS.2, already
covered by the repo's existing `docs/VISUAL_REFERENCES/**/*.mov` rule). It lives at
`docs/VISUAL_REFERENCES/_incoming/` in the primary checkout. All crops originate from full-resolution
(1970×1470) frame extracts; see `docs/presets/ARABESQUE_FILM_NOTES_2026-08-19.md` for the
recording's own provenance (Matt, 2026-08-19, a YouTube capture — colour is indicative only, not
exact; stroke width and composition are trustworthy, per that document's §5).

**None of the 8 `.jpg` files in this folder are tracked by git either** — `docs/VISUAL_REFERENCES/**/*.jpg`
(and `.jpeg`/`.png`/`.gif`/`.mov`/`.mp4`) are repo-wide gitignored (the LFS cutover, D-211). Only
this README is committed. The images live as real files in the **primary checkout**
(`/Users/braesidebandit/Documents/Projects/phosphene/docs/VISUAL_REFERENCES/rosette/`) and reach a
worktree via `Scripts/link_fixtures.sh` (WTFIX.1), which symlinks them in — run it after `git
worktree add` if this folder shows only a README. A worktree-only copy (real files, not placed in
the primary) does not survive past that session; this is the same CHR.1-class trap WHIT.0's
pre-flight hit with the program docs, applied to images instead.

**Naming note:** `CheckVisualReferences` only validates folders for presets currently registered in
`PhospheneEngine/Sources/Presets/Shaders/` (`discoverPresets`, `main.swift:99`). Rosette is
deliberately unregistered at this stage (WHIT.0/WHIT.1a), so this folder is not yet scanned by the
tool — it was hand-verified against `_NAMING_CONVENTION.md`'s regex and this README's required
lightweight sections instead, matching what the tool will enforce once WHIT.1c registers the preset.
