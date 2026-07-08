# RICERCAR-FL.3 — glowing weaving ribbons + look-lock (Ricercar Fantasia rebuild)

Continue the **Ricercar Fantasia rebuild** on branch **`claude/ricercar-rework`** (FL.0→FL.2 live there,
LOCAL/unpushed; head `5f32d1e`). Do **NOT** start a fresh branch off main. Do **NOT** revive the old
paint-marks / Skein-recolour approach — it was rejected three times.

## MANDATORY OPENER
Read **`docs/PRESET_SESSION_CHECKLIST.md`** and follow it. This is preset-facing VISUAL work and you
author BLIND (no live view). The checklist's load-bearing rule: **mid-session sanity checks are
side-by-side comparisons against the named reference IMAGES, never self-judgment.** All three prior
Ricercar failures came from NOT holding the output next to the references — do not repeat that.

## Read first (in this order)
- **`docs/presets/RICERCAR_DESIGN.md` §FANTASIA REBUILD** (+ the M7-failure history just above it): the
  corrected paradigm, why R.2 / IFC.6 / RW all failed (all were opaque paint on a flat canvas), and the
  FL plan. This is the load-bearing context.
- **LOOK at the curated reference IMAGES** (open the .jpg files, don't just read annotations):
  - `docs/VISUAL_REFERENCES/ricercar/01_macro_weaving_lines.jpg` — **THIS increment's target**: clean,
    **glowing luminous RIBBONS** weaving and crossing on a soft gradient. Light-lines with soft halos,
    NOT paint strokes.
  - `docs/VISUAL_REFERENCES/ricercar/02_meso_flowing_colour_masses.jpg` — the ink-in-water flowing colour
    masses (already built in FL.2).
  - `docs/VISUAL_REFERENCES/ricercar/README.md` — trait annotations + anti-references.
- **The built fluid sim** (FL.1/FL.2 — reuse, do not re-derive):
  - `PhospheneEngine/Sources/Renderer/Shaders/RicercarFluid.metal` — the Stam stable-fluids kernels
    (splat → curl → vorticity → divergence → pressure Jacobi → gradient-subtract → advect) + the luminous
    display fragment `ricercar_fluid_fragment`.
  - `PhospheneEngine/Sources/Renderer/Geometry/RicercarFluidGeometry.swift` — the `ParticleGeometry`
    conformer (Mitosis sibling). Hand-animated family-colour section sources in `proceduralSplats(time:)`.
  - `PhospheneEngine/Tests/PhospheneEngineTests/Renderer/RicercarFluidRenderTests.swift` — the gate +
    `RENDER_VISUAL=1` contact sheet (→ `/tmp/ricercar_fluid_diag/ricercar_fluid_contact_sheet.png`).
- **Memory**: `[[ricercar-and-instrument-capture]]` — the whole arc + the key lesson: *when output ≠ the
  reference IMAGE, the fix is NOT tuning — check the PARADIGM against the image.*
- CLAUDE.md §Audio Data Hierarchy (for FL.4 later — not this increment).

## Settled — do NOT relitigate
- The paradigm is **fluid dye (ink-in-water, ref 02) + glowing ribbons (ref 01)** — NOT paint marks.
  Confirmed by Matt after three marks-based rejections ("just Skein, I want Fantasia").
- **FL.1/FL.2 built the fluid sim and it RENDERS the ref-02 look** (soft luminous flowing colour masses,
  family-coloured: strings violet / brass gold / woodwinds russet / percussion teal). Baked-in fixes —
  do not undo: **clear the pressure field each frame** (stale pressure → chaotic velocity → dye torn into
  dots); velocities in **texels/frame (~1–3)**; **small vorticity (~0.4)**. Do not re-derive the fluid sim.
- The conformer is a `ParticleGeometry` (like Mitosis). It is **NOT yet a real selectable preset** — no
  factory wiring, no `passes: particles` JSON, no `pipeline.setParticleGeometry`. It is driven only by the
  render test. That preset integration is FL.5, not now.
- Reach the render: `RENDER_VISUAL=1 swift test --package-path PhospheneEngine --filter RicercarFluidRenderTests`.

## FL.3 scope — VISUAL ONLY (still NO audio, still NO preset wiring)
1. **First, render the current FL.2 fluid state and bring it to Matt** (it may have shifted; and Matt may
   want to steer the masses' composition/density/palette before ribbons are added).
2. **Glowing weaving ribbons (ref 01).** Add a small set (~3–5) of smooth, continuous, **glowing** ribbons
   — Bézier/sine-path **SDF + additive glow/bloom** (the researched technique; IQ 2D distance functions) —
   weaving and crossing gracefully across the frame, one per family colour, luminous, **composited
   additively over the fluid dye masses** so they read as light. Match ref 01 exactly: clean glowing
   light-lines with soft halos, weaving/crossing — NOT paint strokes, NOT the old capsule marks. Implement
   in the display fragment (or a second additive overlay pass) reading the ribbon paths.
3. **Look refinement** toward ref 02 + any Matt steer: composition (mass placement — currently they enter
   from the top and are fairly wispy), density (denser billows if too thin), luminosity, palette. Still
   hand-animated (no audio).
4. **Render against BOTH 01 and 02** (extend `RicercarFluidRenderTests`' contact sheet). **Show Matt the
   frames BEFORE any further work.** The combined look (masses + ribbons) must clear Matt's eye vs the two
   references — that is the gate, not green tests.

## Product decisions for Matt (bring in product terms — what he SEES — before/while building)
- **Ribbon count + weave** — how many voices, how much they cross/braid (ref 01 shows ~3 crossing).
- **How ribbons relate to the masses** — float above / emerge from / thread through the ink.
- **Composition + palette** of the combined look (mass placement, density, ground tone).

## Non-scope (defer — do NOT do this increment)
- **Audio wiring (FL.4):** family → which sources bloom + colour; zero-lag energy (`bass/mid/treble_dev`)
  → flow vigour + ribbon undulation + splat force; beats → splat impulses. Lock the visual FIRST.
- **Preset integration (FL.5):** the `makeRicercarFluidGeometry` factory (mirror
  `VisualizerEngine.makeMitosisGeometry`), `passes: ["particles"]` in a Ricercar sidecar, app-side
  `setParticleGeometry`, then live M7 (⌘] to Ricercar). Not now.

## Validation
BLIND visual work → **render early + often against 01/02, never self-judge** (the checklist rule + the
root cause of 3 prior failures). The `RENDER_VISUAL` contact sheet is the deliverable; show Matt before
proceeding to audio. Green fluid gate + lint-0 are necessary but NOT sufficient — the reference comparison
is the gate. A visual/temporal preset is "code-complete, pending Matt's eye" until Matt confirms the look.

## Protocol
Preset session checklist + Increment Completion Protocol closeout (files changed, evidence, contact-sheet
paths, doc updates — RICERCAR_DESIGN §FANTASIA REBUILD FL.3 status, RENDER_CAPABILITY_REGISTRY if a new
render capability lands, e.g. the fluid-sim / glow-overlay path). Commit locally on
`claude/ricercar-rework` with `[RICERCAR-FL.3]` messages. **Use a commit-message FILE (`git commit -F`),
NOT `-m` with backticks — backticks in `-m` get shell-interpreted (bit me in FL/RW).** Pushing needs
Matt's explicit OK.

## Known environmental noise (NOT yours — annotate, don't fix)
- The branch is off local `main`, which carries a **parallel-session CENSUS change** (`docs/ENGINEERING_PLAN.md`
  modified + `prompts/CENSUS.*` untracked). **Leave it untouched; keep it out of your commits.**
- Worktree tempo-fixture absence (love_rehab.m4a → ~21 engine fixture tests fail environmentally); Mitosis
  lint (MITOSIS.0 sketch); Module Map gate listing Mitosis/prior files. App tests + your own new tests +
  lint-0-on-your-files are the trustworthy signals.

## Stop and report instead of forging ahead if
- the combined masses+ribbons look reads wrong and you can't articulate why after one render round (don't
  spiral — bring the render + your one-sentence read to Matt);
- adding ribbons needs infrastructure the fluid/particle path lacks (surface the scope);
- a product decision (ribbon weave / relation to masses) shapes what Ricercar depicts and Matt hasn't
  weighed in.
