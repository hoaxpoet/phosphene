# Visual References — Floret (source: "Sunflower Passion")

**Family:** hypnotic (feedback) — radial/iridescent bloom register
**Render pipeline (proposed):** direct_fragment + mv_warp (same substrate as Nacre / Dragon Bloom / Fata Morgana)
**Rubric (proposed):** lightweight — stylized 2D feedback (exempt from full detail-cascade + material-count requirements)
**Last curated:** 2026-06-26 (rendered by Claude Code from the faithful butterchurn built-in; Phosphene name **Floret** + scope **faithful base + uplifts** greenlit by Matt). Plan: `docs/presets/FLORET_PLAN.md`.

**Source:** the Milkdrop preset
`suksma - Rovastar - Sunflower Passion (Enlightment Mix)_Phat_edit + flexi und martin shaders - circumflex in character classes in regular expression`
(projectM cream-of-the-crop legends set; butterchurn built-in — pick #1 on Matt's
`docs/presets/MILKDROP_UPLIFT_PICKS.md` top-ten). A heavily-edited mashup; the name is loose.

## Target read

**Not a literal sunflower.** A **breathing, color-cycling fractal bloom** on a near-black ground:
a delicate **3-fold rotationally-symmetric** filament-mandala that **swells outward in ~2 s waves**
from sparse glowing tendrils into a dense **iridescent soap-bubble foam**, then recedes. Populated
with slow color-cycling **seed-orbs** (green ↔ magenta ↔ violet) and **crystalline sparkle clusters**
(the "circumflex" `^` tips). The whole field **swirls slowly** (a 1/r² vortex) and **spins on bass**.
Strong dark→bright breathing. See `target_animated.gif` for motion (real-music-driven).

The literal source shaders + equations are in `source_shaders.txt` — the artifact to port, not
re-derive (FA #73). Mechanic, in brief:
- **Seed:** 4 soft radial-gradient discs near center, slow color-cycle (the only "shapes"; the 4 custom waves are disabled).
- **Per-vertex warp:** 1/r² vortex swirl + bass→rotation + radial bulge.
- **Warp shader:** `z → z²` complex-conformal fold (the petal/2-fold symmetry) + slight decay.
- **Comp shader (the signature look):** 4 layers at 120° rotation, each a radial-pulse `fract(3·uv·dist)`
  tiling with an **unsharp high-pass** (`main − blur`), `max`-combined, ×4 brightness → the
  3-fold pulsing bubble-foam kaleidoscope.
- **Coupling (source):** total energy⁶ accelerates an accumulator `q8` (→ swirl/jitter speed);
  `bass` → rotation. The 2 s radial pulse is pure time (not audio) in the source.

## Reference images

Numbered in cycle order (the preset breathes through all three over ~2 s). See `../_NAMING_CONVENTION.md`.

| File | Annotation (what to learn from this image) |
|---|---|
| `02_midcycle_fractal_bloom.png` | **The hero frame.** The 3-fold rotational symmetry is explicit (the motif repeats at 120° in the corners). Sinuous magenta/white/green filaments branch on a **black ground**, tipped with glowing green/violet **seed-orbs** and white **sparkle clusters**. This is the "sunflower/fractal bloom" character to preserve. |
| `01_peak_bubble_foam.png` | The pulse at **peak**: filaments have swelled into large **translucent iridescent bubbles** with bright white rims (greenish sheen), small orbs nestled among them. This is the dense end of the breath — note it is bright but the rims, not flat fills, carry the light. |
| `03_orb_seed_field.png` | A frame emphasizing the **seed-orbs**: discrete glowing green/violet pods on dark ground with sparse sparkle. Shows the color-cycling discs that seed the feedback before the comp blooms them. |

## Stylization contract

What DOES matter for this preset (substitute for the full rubric):

- [ ] **3-fold radial symmetry + outward radial pulse** — the structural signature. Bloom expands from center outward; the motif repeats at 120°.
- [ ] **Dark ground, light-on-black** — the bloom is luminous filaments/bubbles/orbs on near-black; never a flat-filled frame.
- [ ] **Iridescent rims, not flat fills** — bubbles/cells read by their chromatic bright rims (greenish-white sheen), like Nacre's refractive rims.
- [ ] **Slow color-cycle** — seed-orbs and field hue drift slowly (green ↔ magenta ↔ violet) on a time base, not per-beat.
- [ ] **Readability at silence (D-019):** filament-mandala present + slowly swirling + color-cycling; orbs dim-but-visible. Never black, never frozen.
- [ ] **Readability at peak:** bloom inflates to the bubble-foam, sparkle flares — but **must not white-out / strobe** (see anti-references; flash-safety is the headline constraint).

## Anti-references

- **Full-field dark↔bright strobing.** The source breathes hard to near-black troughs and bright peaks on a ~2 s cycle. A faithful copy of that **global luminance swing is a flash-safety failure** (the cert gate measures flashes/s). Phosphene must hold a **steady global luminance floor (D-157)** and carry the "pulse" through expansion/motion + local rim intensity, not full-frame brightness. (This is exactly Nacre's NACRE.3 lesson: brightness is the wrong connection medium for a bright field → drive the read through motion.)
- **Rigid mechanical kaleidoscope.** If the 3-fold symmetry reads as a hard mirror-tiled mandala with no organic swirl, it has lost the vortex/`z²` character that makes it a *bloom* and not a *gif kaleidoscope*.
- **Opaque blobs / mud.** Bubbles lose translucency + rim-light → lava-lamp lumps.
- **Literal botanical sunflower.** It is abstract; do not chase petals/disc realism (representational-preset trap — needs 3D + scene; out of register).
- **Hue-strobing.** Palette jumping on every beat. Hue is slow + time-driven; energy changes the bloom's size/sparkle, not its color.

## Audio routing notes (proposed — confirm at plan stage)

Phosphene re-routes the source's loose coupling onto the Audio Data Hierarchy (continuous energy primary; D-026 deviation primitives; D-019 warmup):

- **Continuous mid/overall energy → bloom inflation** (swell of the filament→bubble expansion + rim intensity). The source uses energy⁶→`q8`→motion speed; we map sustained energy to bloom radius/brightness-of-rims via an EMA envelope. Primary driver.
- **Bass onset → swirl spin-up / field rotation** (source `rot = bass·rad`). Map `f.bassDev`; bounded (D-157), Layer-4 accent.
- **Treble → crystalline sparkle** at the filament tips (the "circumflex" clusters). Map `f.trebleDev`; fast, fast-decay.
- **Time → 3-fold radial pulse + slow color-cycle + slow vortex roam** (no audio). Faithful, runs at silence.

(One-primitive-per-layer audit, FA #67, to be tabled in the plan doc.)

## Provenance

Curated by: Claude Code (2026-06-26); source picked by Matt (MILKDROP_UPLIFT_PICKS pick #1).
Image sources: faithful butterchurn render of the built-in preset, real-music-driven
(`tools/milkdrop-render/render-gif.js`; same `music.wav` clip as the Nacre curation).
Source preset + shaders captured verbatim in `source_preset.json` + `source_shaders.txt`.
