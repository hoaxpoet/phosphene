# Visual References — Glaze (source: "Flexi + stahlregen - jelly showoff parade")

**Family:** hypnotic (feedback) — glossy fluid/gel register
**Render pipeline:** direct_fragment + mv_warp (same substrate as Nacre / Dragon Bloom / Fata Morgana)
**Rubric:** lightweight — stylized 2D feedback (exempt from full detail-cascade + material-count requirements)
**Last curated:** 2026-06-26 (rendered by Claude Code from the faithful butterchurn built-in; name **Glaze** + scope greenlit by Matt — design increment GLAZE.1; live M7 confirms the port at GLAZE.2b+)

**Target:** a faithful Phosphene uplift of the Milkdrop preset `Flexi + stahlregen - jelly showoff parade`
(cream-of-the-crop legends set; butterchurn built-in, renders faithfully). Distinct from Nacre
(`$$$ Royal (431)`, translucent *cells*): this one is **glossy concentric contour "jelly,"** built from a
**spring-physics warp** rather than a lens-cell field.

## Target read

A frame of **thick, glossy, wet "jelly"**: nested **concentric contour-ring striations** (a topographic /
fingerprint texture) with a heavy **embossed gel sheen** — bright specular highlights + dark rim definition,
like light raking across gelatin. A **bright chromatic frame border** pipes the edge. The palette is
**saturated neon** and **rotates** (red → green → teal → violet) across a slow cycle while the contour
structure **persists and accretes** (decay 1.0 — the field never fades, it builds). The whole field **flows,
wobbles and settles** as an audio-driven **spring-mass "jelly"** drags a swirl-poke across it — bass yanks it
one way, treble flicks it the other, energy lifts it, gravity + bounce bring it back. See
`target_animated.gif` for motion (real-audio-driven, seed → first bounce). The literal source shaders +
spring equations are decoded in `source_shaders.txt` (the artifact to port — port it, don't re-derive; FA #73).

## Reference images

| File | Annotation (what to learn from this image) |
|---|---|
| `01_glossy_jelly_blobs.png` | The hero **material**: corner mounds that read as thick translucent **gel** — glossy specular highlights, dark embossed rims, a wet refractive body. This sheen (from the blur-pyramid emboss in both shaders) is the signature; the contour shapes alone don't sell it. Note the white-hot blooming frame edge. |
| `02_contour_striation_field.png` | The developed **structure**: dense **nested concentric rings** ("fingerprint" / topographic striations) filling the frame, with neon hot-spots. This is what the accreting feedback (decay 1.0 + inward zoom) builds toward over ~12 s from the seed. |
| `03_palette_rotation.png` | Four frames across the cycle (red → green → green-spread → neon-violet). The contour **structure persists and accretes** while the **hue rotates** — palette drift is slow and global; the geometry does **not** reset between hues. |

## Stylization contract

What DOES matter for this preset (substitute for the full rubric):

- [ ] **The gel sheen is the headline.** Embossed specular highlight + dark rim on every contour. If the
  contours render flat/matte, the preset has failed — it must read as *wet glossy jelly*, not line-art.
- [ ] **Spring-jelly motion is the musical hook.** The field's flow/wobble/overshoot/settle is a damped
  spring mass driven by bass (lateral one way), treble (lateral the other) and total energy (lift). The
  motion must read as *physical* — momentum and bounce — not as a direct twitch on each beat.
- [ ] **Palette rotates on a slow time base** (faithful to the source hue field), red→green→teal→violet;
  energy/beats change motion, **not** hue.
- [ ] **Readability at silence (D-019 warmup):** the field is present and **alive** — slow time-driven roam +
  palette rotation continue, the spring idles with a gentle gravity sway, structure visible. Never black,
  never frozen. (NB: the source seeds only from a volume-gated waveform, so a literal port goes black at
  silence — Phosphene must add a silence-floor seed, exactly as Nacre did.)
- [ ] **Readability at peak energy:** the spring swings wide, contours flow fast, sheen flares — but the
  field must **not white-out** (accumulator stays sub-saturated; cf. Dragon Bloom / Nacre test gates).

## Anti-references

What this preset must NOT look like (the failure modes a shader session is most likely to produce):

- **Flat / matte contour lines.** Concentric rings with no embossed sheen → reads as a topographic map or
  line-art, not jelly. The blur-pyramid emboss (`01_glossy_jelly_blobs.png`) is non-negotiable.
- **Direct per-beat twitch.** Routing bass/treble straight into warp displacement (skipping the spring) →
  jittery, mechanical, the FA #4/#31 failure. The spring's job is to *integrate* the audio into momentum.
- **Nacre.** Translucent depth-stacked *lens-cells* with chromatic rims on a near-black ground. If it reads
  as discrete see-through bubbles rather than a continuous glossy gel sheet, it has drifted into the sibling.
- **Hue-strobing.** Palette hue jumping on beats. Hue is slow + time-driven; audio drives motion and sheen,
  not colour.
- **White-out mush.** decay 1.0 + unclamped feedback blooms to white (Nacre learned this — the source stores
  8-bit and clamps each frame; a float buffer needs an explicit clamp).

## Audio routing notes (proposed — full table in the plan doc)

The spring-mass is a natural rhythm integrator; route audio into the **anchor**, let physics do the motion.

- **Bass envelope → spring anchor X (one direction)** — source `xx1 = .9*xx1 + .01*bass; x1 = .5 + 1.5*(xx1-xx2)`.
  Map to `f.bassRel`/`f.bassDev` (D-026), feed the anchor; the spring lag/bounce is automatic.
- **Treble envelope → spring anchor X (other direction)** — source `xx2`. Map to `f.trebleDev`. Bass/treble
  decorrelation is what makes the jelly swing laterally (not just bob).
- **Total energy → spring anchor Y (lift)** — source `yy1 = .94*yy1 + .0075*(treb+bass)`. Map to avg energy.
- **Spring tail position/speed → warp swirl-poke center** — source `q4`/`q5` → pixel_eqs vortex. Pure physics
  output; no extra audio.
- **Chroma / centroid → small palette-phase nudge** (optional, Nacre precedent) on top of the time rotation.
- **Time → palette rotation + gravity idle** (no audio; runs at silence).

One-primitive-per-layer holds: bass and treble drive *opposite directions of one anchor* (one physical input),
energy drives a *different axis*, and all visible motion is the spring's single integrated response.

## Provenance

Curated by: Claude Code (2026-06-26). Target + name (Glaze) + scope (faithful base + uplifts A/B/C) greenlit by Matt 2026-06-26 (GLAZE.1).
Image sources: faithful butterchurn render of the built-in `Flexi + stahlregen - jelly showoff parade`,
driven by a loud beat-structured test signal (`tools/milkdrop-render/render-stills.js` + `render-gif.js`;
real copyrighted-clip render deferred to a confirmed-scope increment, per Nacre's flow).
Source preset captured verbatim in `source_preset.json`; shaders + spring equations decoded in `source_shaders.txt`.
