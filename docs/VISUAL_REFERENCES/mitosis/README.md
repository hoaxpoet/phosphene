# Mitosis — visual references

Reaction–diffusion (Gray–Scott) cell colony. Abstract glowing cells on dark that
visibly divide (mitosis) and merge in time with the music (Matt's locked look,
2026-06-29). See `docs/presets/MITOSIS_DESIGN.md` for the full design + musical role.

> **Two generations.** Gen-1 (the rest of this README) is the **certified abstract**
> spot-field version. **Gen-2** is the **detailed / "realistic" fluorescence-microscopy**
> version — a few LARGE procedurally-detailed dividing cells. Gen-2's reference and traits
> are the **§ Gen-2** section at the bottom; read it for any gen-2 work.

## Status of this reference set

Mitosis is an **original-look** preset — the cell *form* is canonical Gray–Scott
(grounded, below), but the cyan-on-dark grade + the audio coupling are
Phosphene-original, grounded empirically by the sketch's rendered evidence rather
than a single prior-art demo (same situation as Filigree's web-dominant grade).
The **palette is not yet locked** — it's a curation step with Matt (MITOSIS.3).

## Grounding references (the cell form — port, don't derive, FA #73)

- **pmneila jsexp GrayScott** — https://pmneila.github.io/jsexp/grayscott/ — clean
  reference implementation; the "paint reactant with the mouse" interaction is the
  model for the onset burst (paint B nuclei into open space).
- **Karl Sims RD tutorial** — https://www.karlsims.com/rd.html — the model + the
  feed/kill regime intuition.
- **mrob "Xmorphia" parameter atlas** — http://mrob.com/pub/comp/xmorphia/ — the
  regime map. NB: the canonical "mitosis" F=0.0367/k=0.0649 *decays to extinction*
  in our r16Float discretisation (measured); we run F=0.034/k=0.063 (u-skate), which
  self-sustains discrete dividing cells. Source images of the atlas to add here.

## Rendered evidence (the trustable in-engine reference for now)

Regenerate with `RENDER_VISUAL=1 swift test --package-path PhospheneEngine --filter MitosisSketchRenderTests`.
Frames land under `tools/mitosis_sketch/frames/` (gitignored):

- `mito_0_quiet_merged.png` — sparse resting state (few cells, a colony dividing into a dot-grid).
- `mito_2_loud_teeming.png` — packed field of discrete round cells; some elongated mid-division.
- `mito_4_onset_divide2.png` — dense field with many dumbbell/rod shapes = cells caught mid-division.
- `motion/` — continuous sequence for a GIF (the division must read in motion, not just stills).

## Mandatory traits (the cells must read as)

1. **Discrete cells**, not a connected labyrinth/maze. (Lower kill-rate slides into
   worms/coral — that is the **anti-reference**: a maze of connected channels is NOT
   a cell colony.)
2. **Visible division** — cells elongate and pinch into two (dumbbell → two nuclei).
   Division events should land on drum onsets.
3. **A living resting field** — sparse but alive when quiet, teeming when loud; never
   a single lonely cell (the canonical-F/k extinction failure) and never an all-on /
   all-off saturated field.

## Anti-references (what Mitosis must NOT look like)

- A connected **labyrinth / Turing maze** (wrong RD regime — see `holes`/`bubbles` in
  the regime probe). Cells must stay discrete.
- A frozen lattice — the field must be visibly, continuously reorganising.
- A literal membrane-shaded organism — Matt locked the **abstract glowing** look, not
  representational cells.

---

# Gen-2 — detailed fluorescence-microscopy cell division

Gen-2 is a **separate preset** (siblings, not subclasses — D-097): a small number of
**LARGE, procedurally-detailed dividing cells**, rendered like confocal immunofluorescence
microscopy. Locked concept (Matt 2026-06-30): **few large cells, always** — the preset
lives in the early-growth / first-division phase so the per-cell detail stays legible; it
never crowds down to tiny dots (that is gen-1's job). Substrate: **explicit per-cell
objects** (position / size / orientation / division phase), NOT Gray–Scott. See
`docs/presets/MITOSIS_GEN2_KICKOFF.md`.

## Reference image — `gen2_cytokinesis_confocal.png` (locked, Matt 2026-06-29)

A confocal triple-stain of a cell in **cytokinesis** (the late-division frame). Per the
checklist, the trait-by-trait annotation with trust/disregard notes:

| What's in the frame | Trust as a target? |
|---|---|
| **Central dividing cell = a dumbbell.** Two round lobes joined by a pinched neck (the **cleavage furrow** — one cell becoming two). Tilted ~20–30° off horizontal. | **TRUST — the signature.** The dumbbell + furrow pinch is the unmistakable "a cell is dividing" read. The whole sketch hinges on this shape. |
| **Two green asters.** A radial burst of fine green microtubule fibres exploding from a bright core (the centrosome / spindle pole) in *each* lobe. | **TRUST — co-signature.** Two asters = two forming daughters. The radial fibre burst from a bright point is the most recognizable single feature; nail the fibres-from-a-point look. |
| **Red/orange cortical rim.** A reddish membrane outline tracing the entire dumbbell perimeter, *including* the furrow notch. | **TRUST.** Thin bright rim band at the cell boundary; reads as the membrane. Follows the furrow pinch inward. |
| **Blue/purple chromatin.** A mottled blue DNA mass sitting around / between each aster core. | **TRUST.** One blue blob per lobe in late division. Mottled, not a clean disk. |
| **Dense green filament background.** The whole frame is a web of fine electric-green cytoskeletal filaments (neighbour cells' microtubules) on near-black, with partial bright asters of *other* cells at the corners. | **TRUST as a FIELD texture, not as tracked cells.** It establishes the figure-ground (bright detailed cell on a busy dark-green web) and stops the frame feeling empty. The corner cells are context, not individually animated. |
| **Colour assignment: green fibres + red rim + blue chromatin on black.** | **TRUST as the canonical stain**, but **MUSIC-TUNABLE** — gen-1's MITOSIS.5 hue coupling (centroid → palette, energy → vividness, drum → glow pulse) is reused, so this green/red/blue is the *neutral* palette the music swings around, not a fixed grade. |
| It is a **single still frame**. | **DISREGARD as the whole story.** A preset is a behaviour over time: the cell must *progress* interphase → metaphase → anaphase → cytokinesis → split, and the *snap* of division is the on-the-music event. The reference is the **cytokinesis keyframe**, not the only frame. |
| Literal biological accuracy (exact organelle counts, real stain chemistry). | **DISREGARD.** The goal is "psychedelic AND unmistakably a dividing cell," not a textbook plate. |

## Mandatory traits (the gen-2 sketch must read as)

1. **A dumbbell mid-division** — two lobes + a pinched furrow neck, unmistakably one cell becoming two.
2. **Radial green asters from two bright poles** — fine fibres bursting from a point, one per daughter. The single most important "this is mitosis" cue.
3. **A red cortical rim** tracing the membrane, following the furrow.
4. **Blue chromatin** mottled inside each lobe.
5. **Large + detailed** — the cell fills a meaningful fraction of the frame; the detail is legible, not a dot.
6. **Additive glow on a busy dark-green filament field** — bright cell, dark textured ground, high figure-ground contrast.

## Anti-references (what gen-2 must NOT look like)

- **Gen-1's abstract dots** — if the cells are small featureless blobs with no asters/furrow, gen-2 has failed its reason to exist.
- **A flat clip-art cell diagram** — the textbook "circle with a nucleus" with hard vector edges. Must be glowing, fibrous, fluorescent.
- **A crowded field of tiny cells** — the arc is locked to *few large cells*; crowding kills the detail.
- **A smeared / wobbling RD blob** — the explicit-cell substrate was chosen precisely so the dividing cell stays crisp.
