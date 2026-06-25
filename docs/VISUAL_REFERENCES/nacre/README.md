# Visual References — Nacre

**Family:** hypnotic (feedback) — fluid/iridescent register
**Render pipeline:** direct_fragment + mv_warp
**Rubric:** lightweight — stylized 2D feedback (exempt from full detail-cascade + material-count requirements)
**Last curated:** 2026-06-25 (rendered by Claude Code from the faithful butterchurn reference; target confirmed by Matt)

**Target:** a faithful Phosphene uplift of the Milkdrop preset `$$$ Royal - Mashup (431)`
(projectM cream-of-the-crop legends set; butterchurn built-in). Sibling of `(220)` =
the shipped **Dragon Bloom** and `(197)` = a neon-glowstick variant — Nacre is the
**translucent refractive "jello-mirror"** member of the family, visually unrelated to
either. Distinctness confirmed by side-by-side render (see `tools/milkdrop-render/renders/`).

## Target read

A field of **translucent, overlapping refractive cells** — soap-bubble / mother-of-pearl
membranes — with **chromatic-fringed rims** (red/cyan/green edge dispersion) and a **bright
pulsing central core**, on a near-black ground. The field **breathes and slowly roams**, and
the **palette rotates** (green → teal → violet → red) across a slow cycle. Calm, liquid,
luminous — the opposite of Dragon Bloom's hot bilateral symmetry. See `target_animated.gif`
for motion (real-music-driven). The literal source shaders + equations are in
`source_shaders.txt` (the artifact to port — port it, don't re-derive; FA #73).

## Reference images

Files in this folder, numbered in priority order. See `../_NAMING_CONVENTION.md`.

| File | Annotation (what to learn from this image) |
|---|---|
| `01_macro_translucent_cells.png` | The macro composition: many overlapping **translucent** lens-cells of varied size, depth-stacked (you see through the front cells to those behind), with one **bright luminous core**. The ground is near-black; cells are tinted, never opaque. |
| `02_palette_hue_rotation.png` | Four frames across the cycle — the cell-field structure **persists** while the **hue rotates** green → teal → violet → red. Palette drift is slow and global; the geometry does not reset between hues. |
| `03_specular_chromatic_rims.png` | The hero detail: cell rims carry **red/cyan/green chromatic dispersion** (a refraction/edge-emboss signature, not a uniform outline), and the bright core reads as light seen *through* the lenses. This rim treatment is what sells "refractive glass," not the cell shapes alone. |

## Stylization contract

What DOES matter for this preset (substitute for the full rubric):

- [ ] **Color modulation:** palette **rotates on a slow time base** (faithful to the source's `wave_r/g/b` multi-sine), green→teal→violet→red; continuous mid-band energy must not change hue, only swell. Optional slow arousal nudge toward warmth is a tuning lever, not a requirement.
- [ ] **Audio coverage:** at all times the viewer must be able to read **mid-band energy** (cell-field swell/zoom) and **bass onsets** (field displacement-kick); treble adds rim sparkle; the central core tracks waveform/overall energy.
- [ ] **Readability at silence (D-019 warmup):** the cell-field is present and **alive** — slow time-driven roam + palette rotation continue, zoom at baseline, core dim-but-visible. Never black, never frozen.
- [ ] **Readability at peak energy:** cells inflate and crowd the frame, core flares, rims sparkle — but the field must **not white-out** (the accumulator stays sub-saturated; cf. Dragon Bloom test gate #2).

## Anti-references

What this preset must NOT look like (the failure modes a shader session is most likely to produce by accident):

- **Opaque blobs / mud.** Cells lose translucency and depth-stacking → reads as a lava-lamp of solid lumps. Translucency + see-through layering is the whole point.
- **Uniform white outlines.** Rims drawn as a flat 1px stroke instead of chromatic dispersion → looks like cel-shaded cartoon bubbles, not refractive glass. The rim must carry R/C/G separation (`03_specular_chromatic_rims.png`).
- **Dragon Bloom.** Warm fiery, bilaterally symmetric, feathered. If it looks hot or mirror-symmetric, it has drifted into the `(220)` sibling.
- **Hue-strobing.** Palette hue jumping on every beat (coupling hue to bass/mid). Hue is slow + time-driven; energy changes volume, not color.

## Audio routing notes

(Cite D-026 deviation primitives + D-019 warmup. Full table in `docs/presets/NACRE_PLAN.md §6`.)

- **Mid-band continuous energy → cell-field zoom/inflation** (primary motion; source eq `rg = max(.77*rg, .5*max(0,mid_att-1)); zoom += .1*rg`). Map to `f.midRel`/`f.midDev` with EMA memory.
- **Bass onset (thresholded) → bounded warp displacement-kick** (source eq `bass_thresh` gate → `dx/dy_residual`). Map to `f.bassDev` over a threshold; keep the spatial footprint bounded (D-157) — it is a Layer-4 accent, never the primary driver.
- **Treble → rim sparkle / micro-grain** (source warp-shader noise term scaled by `treb_att`). Map to `f.trebleDev`.
- **Waveform + overall energy → central-core brightness.** Map to `waveformData` (buffer 2) + total energy.
- **Time → palette rotation + slow field roam** (no audio). Faithful, runs at silence.

## Provenance

Curated by: Claude Code (2026-06-25), target picked + confirmed by Matt.
Image sources: faithful butterchurn render of the built-in `$$$ Royal - Mashup (431)`, real-music-driven
(`tools/milkdrop-render/render-gif.js`; music clip = a 15 s cut of Cindy Lee — "Golden Microphone").
Source preset + shaders captured verbatim in `source_preset.json` + `source_shaders.txt`.
