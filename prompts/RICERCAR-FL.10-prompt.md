# RICERCAR-FL.10 — build the "visual fantasia": audio-reactive glowing particle flow-field

Continue the **Ricercar Fantasia rebuild** on branch **`claude/ricercar-rework`** (FL.0→FL.9 live there,
LOCAL/unpushed). Do **NOT** start a fresh branch off main. This increment **builds a new technique** —
read the "Settled" and "Rejected" sections before touching code so you don't repeat a whole session of
dead ends.

## MANDATORY OPENER
Read **`docs/PRESET_SESSION_CHECKLIST.md`** and follow it. This is preset-facing VISUAL work authored
BLIND (no live view). The load-bearing rule: **validate against real audio EARLY and OFTEN via the video
harness (below), never iterate blind on stills, and hold output against the reference SPIRIT.** The entire
prior session (FL.7–FL.9) was Matt rejecting hand-invented primitives one after another — do not add to
that list.

## THE GOAL (Matt's words, 2026-07-08)
- **"A visual fantasia set to music."** INSPIRED BY *Fantasia*'s Toccata & Fugue in D minor segment —
  **NOT copying it.** Abstract, luminous forms that **appear and move in time with the music**, an abstract
  expression of how the music feels and moves, with **real craft**.
- **"The most important thing is how the visuals appear in RESPONSE to musical signals."** The music-driven
  motion IS the product, not a pretty still frame. A static contact sheet cannot judge it — a rendered
  VIDEO against real audio can (harness below).

## THE TECHNIQUE — DETERMINED, don't relitigate (this was the whole point of the prior session's research)
Build an **audio-reactive glowing particle flow-field** — the lineage of **Robert Hodgin's *Magnetosphere***
(the iTunes visualizer) + the **curl-noise glowing-particle** standard. Thousands of particles rendered as
**points / streaks / ribbons of LIGHT**, advected through **curl-noise turbulence + audio force fields**,
each carrying an instrument-family colour, **additive-blended** into an HDR light-trail (the deposit-and-fade
trail IS the glow and the weaving ribbons), luminous over a **deep ground**.
- Calm music → smooth flowing streams; energy → vigorous swirling; beats → outward scatter bursts; sustained
  passages → flowing rivers of light. *"Dots, ribbons and lights sent dancing"* (the Magnetosphere writeup).
- **Why this and not another invention:** it's a *proven craft* technique (the benchmark beloved visualizer),
  genuinely music-driven at zero lag, and **ports onto infra Phosphene already has** (see Substrate).
- Sources: https://roberthodgin.com/project/magnetosphere ·
  https://discourse.libcinder.org/t/audio-reactive-visuals-with-trails-and-gpu-curl-noise/1833

## SUBSTRATE — port onto this, don't build new infra
Phosphene has a compute-particle **`ParticleGeometry`** pattern (D-097) driving Murmuration (3D boids) and
**Filigree (`PhysarumGeometry` + `Renderer/Shaders/Physarum.metal`)**. Physarum is the closest sibling:
per-frame compute advances thousands of agents that **deposit into an additive trail map**, ping-ponged and
drawn fullscreen from the live `FeatureVector` stream. **Port that pattern**, changing:
- **Motion:** swap the physarum sensing rule for **curl-noise flow + audio force fields** (energy → flow
  speed/turbulence; beats → radial scatter impulse; family/register → force direction or spawn region).
- **Colour:** Physarum's trail is scalar `r16Float` + an `atomic_uint` count. You need **colour**. Recommended
  (avoids atomic-RGB races and matches the Magnetosphere approach): render particles as **additive glowing
  sprites** (point primitives / small quads) into an **HDR `rgba16Float` trail texture** with additive
  blending + a per-frame decay/feedback, rather than a compute atomic deposit. Family colour per particle.
- **Display:** tonemap the HDR trail → luminous over a **deep ground** (T&F is dark/deep, not the light canvas
  the curated refs 01/02 implied — see Reference note).
- Wire it as a new `ParticleGeometry` conformer (sibling; do NOT parameterise a shared pipeline). The existing
  `RicercarFluidGeometry` (fluid + drawn voices) is the REJECTED approach — replace it (keep git history).
  Update the app factory `makeRicercarGeometry` + `ParticleGeometryRegistry` + `resolveParticleGeometry` if
  you rename the geometry; the FL.5 preset wiring (`Ricercar.json` passes `[feedback, particles]`,
  `ricercar_ground_fragment` backdrop) already exists on main.

## AUDIO MAPPING (Audio Data Hierarchy + FA #67 — one primitive per layer)
- **Motion (PRIMARY, zero-lag):** `bass/mid/trebDev` → flow vigour / particle speed / turbulence;
  `beatComposite` → scatter bursts (accents). Motion must NEVER be driven by the laggy family signal (that
  was the IFC.6 "lag" failure).
- **Colour / identity (lag-tolerant):** instrument-family capture (`StemFeatures` floats 48–55, IFC.4/D-177 —
  `strings/brass/woodwinds/percussion Activity/ActivityDev`) → particle colour. Family colour lagging a beat
  reads fine; motion lagging does not.
- **Feel:** mood (valence/arousal) → palette warmth / character.
- The live app already feeds `particles.update(features:stemFeatures:)` with populated family fields
  (`RenderPipeline+Draw` → the IFC series, preserved across live stem pushes) — no app change needed to drive it.

## VALIDATION — the harness is BUILT; use it (this is the "closest to real" Matt demanded)
`PhospheneEngine/Tests/PhospheneEngineTests/Diagnostics/RicercarFluidVideoHarness.swift` (env-gated). It
decodes a REAL track, runs the PRODUCTION analysis (`FFTProcessor`→`MIRPipeline` + `InstrumentFamilyAnalyzer`),
drives the geometry with that per-frame stream exactly as the live app does, renders every frame, encodes an
MP4 via ffmpeg, AND prints a quantitative **sync report** (INTENSITY: coverage vs energy + lag; VERTICAL:
centroidY vs energy). Run it, point it at the new geometry, and **watch the video + read the sync numbers**:
```
RICERCAR_VIDEO=1 RICERCAR_SECONDS=18 RICERCAR_AUDIO=/path/to/track swift test \
  --package-path PhospheneEngine --filter RicercarFluidVideoHarness
```
- Environment (Matthews-Mac-mini): ffmpeg present; PANNs family model loads here (family capture fires); the
  27,639-track corpus SSD is mounted at `/Volumes/Extreme SSD` (use a **classical/orchestral** track so the
  family-colour path exercises; the in-repo default `pyramid_song.m4a` is bass-heavy → underexercises voices).
- Output: `/tmp/ricercar_fluid_diag/ricercar_response_<track>.mp4` + frames. Extract frames (Read the PNGs)
  to judge, and **show Matt the video + frames EARLY, before polishing.**
- **Refine the sync metric** to per-particle-region if the whole-frame centroid is too confounded to be useful
  (it was, for the multi-voice drawn-lines).
- Green tests + lint-0 are necessary, NOT sufficient. The gate is **Matt's eye against the Fantasia SPIRIT**,
  and the **felt music-response is his live/video call** — you cannot self-certify it.

## SETTLED — do NOT relitigate
- The paradigm is **audio-reactive glowing particle flow-field** (above). Not fluid dye, not fixed ribbons,
  not drawn contour "voices" — all rejected (below).
- "Inspired by, not copying" — a visual fantasia, not a shot-by-shot port of the film.
- The video harness is the validation loop. Use real audio, never synthetic-for-fidelity (FA #27).

## REJECTED THIS SESSION (FL.6→FL.9, 2026-07-08) — do NOT repeat
Each was a **simple procedural primitive invented blind**, and each was rejected. The meta-lesson (FA #64/#73):
**stop inventing primitives; port a proven craft technique** (which is why FL.10 = Magnetosphere-lineage).
- **FL.8 fluid blooms** (music-summoned ink-in-water masses): Matt "soft blobs that grow and fade — pretty
  basic shit." Also: the fluid medium has an **inherent ~233 ms accumulation lag** (measured) and static
  position — a dye field physically cannot move/snap with the music. This is *why* particles (direct,
  zero-lag) were chosen.
- **FL.9 drawn "voices"** (scrolling audio-height contour lines): Matt "the ribbons are now waveforms? …
  basic shit, not at all aligned with Fantasia." Oscilloscope scan-lines ≠ weaving luminous ribbons.
- Earlier (FL.1–FL.5, on main): fluid dye sim + fixed sine ribbons → "muddy vertical curtains / spiky /
  plastic." R.2/IFC.6/RW (pre-FL): paint-marks-on-flat-canvas, rejected 3×.
- **Reference note:** the curated `docs/VISUAL_REFERENCES/ricercar/01` (weaving ribbons) + `02` (ink-in-water)
  pushed toward FLAT/LIGHT and MISLED the fluid work. The operative reference is the **SPIRIT of the T&F film
  segment**: luminous abstract forms of light dancing in **deep/dark space**, dramatic, flowing, music-
  choreographed. Treat 01/02 as loose mood, not targets.

## GIT / DOC STATE (important)
- Branch `claude/ricercar-rework`: FL.7 (video harness + quantitative sync metric — KEEP, it's the validation
  loop), FL.8 (fluid "music paints" flip), FL.9 (drawn voices) committed LOCAL/unpushed. **FL.7–FL.9 design/
  plan/registry docs were NOT finalized** (the aesthetic was still moving) — record the outcomes when FL.10
  lands, or note them superseded.
- `main` (pushed, origin `c963e46`+): has FL.0–FL.5 — the OLD fluid Ricercar is the selectable in-app preset
  (⌘] reaches it). FL.10 replaces the geometry behind it.
- **Parallel-session noise (leave untouched, keep out of your commits):** `docs/ENGINEERING_PLAN.md` carries an
  uncommitted CENSUS edit on main; `prompts/CENSUS.*`, `HG_SDF_VENDORING_SPEC.md`, `*.premerge-bak`, etc. are
  untracked. Worktree tempo-fixture absence → ~21 engine fixture tests fail environmentally (app/lint/your-own
  tests + the render harness are the trustworthy signals).

## Read first (in this order)
- `docs/presets/RICERCAR_DESIGN.md` §FANTASIA REBUILD (+ the FL/IFC failure history) — the arc and why each
  attempt failed.
- Memory `[[ricercar-and-instrument-capture]]` — full status + lessons.
- `PhospheneEngine/Sources/Renderer/Geometry/PhysarumGeometry.swift` + `Renderer/Shaders/Physarum.metal` — the
  compute-particle + additive-trail substrate to port (agent buffer, per-frame kernels, ping-pong, fullscreen
  colorize). Also `Murmuration3DGeometry` for the ParticleGeometry contract.
- `RicercarFluidVideoHarness.swift` — the real-audio → analysis → drive → video + sync-report loop.
- CLAUDE.md §Audio Data Hierarchy.

## Protocol
Preset session checklist + Increment Completion Protocol closeout. Commit locally on `claude/ricercar-rework`
with `[RICERCAR-FL.10]` messages via a commit-message FILE (`git commit -F`, NOT `-m` with backticks — they
shell-interpret). Pushing needs Matt's explicit OK. Update RICERCAR_DESIGN §FANTASIA REBUILD, ENGINEERING_PLAN,
RENDER_CAPABILITY_REGISTRY, and memory when it lands.

## Stop and report instead of forging ahead if
- the first real-audio render reads primitive / not-Fantasia and you can't articulate why — bring Matt the
  video + your one-sentence read, do NOT grind another blind round (this is the failure that consumed the
  prior session);
- the particle-flow technique itself can't reach the craft bar after a genuine prototype — surface it, don't
  invent a fallback primitive;
- a decision about what the visual IS (deep/dark vs light ground; particles-only vs particles+wash; how the
  families read) needs Matt's eye — bring frames, recommend, let him pick.
