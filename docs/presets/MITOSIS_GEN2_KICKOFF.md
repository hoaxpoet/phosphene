# Mitosis gen-2 — detailed / "realistic" psychedelic cell division (kickoff)

**Start this in a fresh session.** Read `docs/PRESET_SESSION_CHECKLIST.md` first (mandatory
opener), then `docs/presets/MITOSIS_DESIGN.md` (the certified gen-1) and the memory note
`project_mitosis_preset` (the full gen-1 arc + lessons).

## What this is

Mitosis gen-1 (MITOSIS.2c, **certified**) is the *abstract* version: a Gray–Scott spot
field where cells read as glowing fluorescent dots that divide, crowd, dissolve, and
regrow, with music-tied colour. Matt wants a **second, higher-fidelity version** where
individual dividing cells render at *detail* — the way real fluorescence microscopy of
mitosis looks. His words: the reference image "is a good representation of what could be
displayed after a few seconds of playback — the first set of cell divisions." So the
**showcase moment is the early growth phase**: a few LARGE, detailed cells visibly
dividing, before the field crowds and cells get small.

## The reference (locked — curate it first)

A confocal fluorescence-microscopy image Matt attached (2026-06-29): a cell in
**cytokinesis** — the **dumbbell cleavage furrow** (one cell pinching into two), **two
green microtubule asters** radiating from the centrosomes (the spindle poles), a
**red/magenta cortical rim** (membrane/actin), **blue chromatin** in each forming
daughter, and neighbour cells as **green cytoskeletal filament networks** filling the
field. **Action:** curate this image (and 2–3 comparable confocal-mitosis references)
into `docs/VISUAL_REFERENCES/mitosis/` with per-image annotations, per the checklist —
ask Matt to drop the attached file in, or source equivalents. The signature trait to hit:
the **radial aster burst from two poles + the furrow** = "a cell dividing," unmistakably.

## The technical reality (read before scoping)

**Gray–Scott RD cannot draw cell internals** (radiating spindle fibres, asters,
chromatin) — that's why gen-1 is abstract dots. Gen-2 needs a **different renderer**:

- **Layer 1 — cell tracking:** keep an RD field (or an agent/particle layer) that tracks
  each cell's **position, size, and division PHASE** (interphase → metaphase → anaphase →
  cytokinesis). The RD field already produces dividing spots; the job is to *detect* each
  cell + its phase (e.g. local-maxima detection + a per-cell state machine, or a fresh
  agent system seeded/divided on the RD events).
- **Layer 2 — per-cell procedural detail pass:** for each tracked cell, render a procedural
  "fluorescent cell" keyed to its phase — radiating aster fibres (procedural lines/noise
  from the centrosome(s)), the cleavage furrow (the dumbbell pinch in cytokinesis), the
  cortical membrane rim, chromatin blobs. Likely instanced sprites or an SDF/raymarch per
  cell, composited additively on black.

This is a **significant rendering increment**, possibly a new render path — **surface the
substrate choice to Matt early** (RD-field-driven cell detection + per-cell detail pass
vs. a fresh agent/particle cell system) before building. Borderline representational
(`[[feedback_representational_presets]]`), but it's 2D microscopy, so procedural detail is
feasible without 3D.

## Reuse from gen-1

The grow→crowd→dissolve→regrow **cycle** structure, the **fluorescence palette + the
music-tied hue** (MITOSIS.5: centroid→palette, energy→vividness, drum→glow pulse), the
**certification pattern** (rubric `certifiedPresets`/`expectedAutomatedGate`,
`PhotosensitivityCertificationTests.multiPassMeasured`, a `renderMitosisGen2` flash
harness). Gen-2 is a **separate preset/geometry**, not an edit of the certified gen-1 —
don't destabilise the shipped one (D-097 siblings, not subclasses).

## Process (mirror gen-1)

1. **Throwaway sketch first:** prove the per-cell detail rendering on a *few* cells (the
   early-growth showcase) — can you draw a convincing dividing cell (asters + furrow +
   membrane + chromatin) procedurally, music-coloured, at 60 fps? `RENDER_VISUAL=1`
   contact sheet vs the reference.
2. Gate to a real increment only if the sketch reads as "a detailed dividing cell."
3. Graduate → certify like gen-1.

## The carried lesson (don't repeat the gen-1 arc)

Gen-1 burned **three live M7s** building a per-beat *churn* before Matt's one-line concept
("psychedelic cell division") pointed at the natural growth transient. **Lock the concept
and the reference with Matt before mechanics**, and prove the showcase look (a detailed
dividing cell) on rendered evidence early.
