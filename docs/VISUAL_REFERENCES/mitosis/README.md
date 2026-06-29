# Mitosis — visual references

Reaction–diffusion (Gray–Scott) cell colony. Abstract glowing cells on dark that
visibly divide (mitosis) and merge in time with the music (Matt's locked look,
2026-06-29). See `docs/presets/MITOSIS_DESIGN.md` for the full design + musical role.

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
