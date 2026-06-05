# Nimbus — Continuity Prompt for NB.9 (Certification)

**Written 2026-06-05 at the end of a long session that took Nimbus from a static
energy-only blob to a fully-featured, live-validated preset. All feature work
(NB.1 → NB.6 + the smoke/motion/perf/reactivity work) is DONE, committed, and
PUSHED to `main` (`cd4ae7ec..902955be`). The ONLY thing left is NB.9 —
certification.** This prompt hands that off.

---

## What Nimbus is

The first `volumetric`-family preset (D-140): a single coherent mass of glowing
**cool gas in a black void that moves with the music** — a single-pass 2D
direct-fragment volumetric ray-march that composes the preamble-injected V.2
Volume tree. `passes: []` (a `direct` preset). Contract of record:
`docs/presets/NIMBUS_DESIGN.md`; plan: `docs/presets/NIMBUS_PLAN.md`; rationale:
`DECISIONS.md` D-140 / D-141.

## Read first

- `docs/presets/NIMBUS_DESIGN.md` — the full contract. Especially **§1.2** (motion
  character — rising/curling smoke, with the 2 Matt-provided motion-reference
  links), **§1.3** (how it answers the music — the model, REVISED at NB.5 to add
  the beat), **§5.4** (audio routing table + the NB.5 reactivity-fixes note),
  **§5.7** (acceptance criteria — the NB.9 gate), **§6.1–§6.8** (the budget
  history + durable perf lessons), **§7** (the increment ledger, all ✅ except
  NB.9).
- `docs/VISUAL_REFERENCES/nimbus/README.md` — the trait matrix + anti-references.
  Read it cover-to-cover before any visual judgement (FA #63).
- The memory note `project_nimbus_volumetric.md` — the condensed history + the
  durable lessons from this session.
- `git log --oneline cd4ae7ec..902955be` — the 21 commits of this session's work.

## Key files

- `PhospheneEngine/Sources/Presets/Nimbus/NimbusState.swift` — all CPU-side state:
  the bloom follower, 4 stem followers (kickPunch + bass/vocals/other lobes), the
  flowPhase accumulator, the cold-start time-gate, the mood smoothers. 32-byte
  `NimbusStateGPU` bound at fragment buffer(6).
- `PhospheneEngine/Sources/Presets/Shaders/Nimbus.metal` — the shader. Density
  (Perlin-Worley billows from `noiseVolume` + interior carve), motion (rise +
  twist + 2-octave swirl), per-stem envelope heave (star-convex bulge), backlit
  lighting + cone self-shadow (cheap `nimbus_density_shadow`), mood tint +
  agitation, non-black haze floor. ~480 lines.
- `PhospheneEngine/Sources/Presets/Shaders/Nimbus.json` — sidecar.
  `complexity_cost {tier1: 9.0 (excludes M1/M2), tier2: 4.0 (half-res worst-case)}`,
  `certified: false` (flip this at cert), `rubric_profile: full`.
- `PhospheneEngine/Sources/Renderer/RenderPipeline+DirectDraw.swift` +
  `RenderPipeline+Draw.swift` + `RenderPipeline.swift` — the NB.8 half-res render
  path (`setDirectRenderScale(0.5)`, `drawDirect` branch, `halfResTarget`,
  `encodePresetVisualization`).
- `PhospheneApp/VisualizerEngine+Presets.swift` — the live wiring (`if desc.name
  == "Nimbus"`): NimbusState alloc + reset + slot-6 bind + tick + `setDirectRenderScale(0.5)`.
- Tests: `PhospheneEngine/Tests/.../Presets/NimbusBloomFollowerTest.swift`
  (the big one — follower feel, render-tracks-bloom, stem lobes, cold-start gate,
  half-res upscale, motion strip [NB_MOTION=1], mood travel [NB_MOOD=1]);
  `NimbusBudgetProbeTests.swift` (NIMBUS_BUDGET=1, worst-case); the Nimbus arms in
  `Renderer/PresetVisualReviewTests.swift` (RENDER_VISUAL=1).

## How Nimbus works (the model)

One coherent gas body. Audio routing (one primitive per visual layer):

| Layer | Primitive | Driver |
|---|---|---|
| Whole-body beat punch + brightness pop | `kickPunch` ← anticipatory `smoothstep(0.82,1,beatPhase01)` (peaks ON the beat) ∥ `max(beatBass,beatComposite)` fallback | Beat — drums |
| Down/up/side heave | `bass/vocals/otherLobe` ← stem `…EnergyDev` (smoothstep [0.12,0.55]) | Beat — per stem |
| Body size + brightness + flow rate (slow swell) | `bloom` ← mean of the 4 stem ENERGIES (FV bass proxy during cold-start) | Energy |
| Body colour cool↔warm | `valence` (smoothed ~4 s) | Mood |
| Flow agitation smooth↔torn | `arousal` (smoothed ~4 s) → detail-erosion strength | Mood |

The per-stem heaves are a **star-convex** envelope deformation (`rr/(1+kick+Σ
lobe·cos²)`) — the body CANNOT fragment. Cold-start: a self-tracked `trackTime`
gate drives the kick/bloom from the live beat until the live stems converge
(~9–13 s; the cached stems are a constant snapshot before that). Budget: the body
swells to fill the frame at full energy, so it renders at **half resolution +
bilinear upscale** (NB.8) — ~4× cheaper, worst-case ~3 ms.

## Live-validation status (Matt's sign-offs so far)

- Texture + rising/curling motion: **approved** ("looks good, proceed").
- Cold-start + beat-sync + half-res budget: **approved** (3rd live test — "musical,"
  beats from frame 1, better synced, blob "a little soft but probably fine for v1").
- **Mood (NB.6): NOT yet live-tested.** Verified by `test_moodTravel` + the
  cool/warm/calm/wild contact strip only. On a single track the classifier's
  valence/arousal are ~constant, so to see the cool↔warm + agitation travel live
  you want a couple of tracks with different moods (calm/sad vs upbeat).

## NB.9 — what certification requires (§5.7 + NIMBUS_PLAN NB.9)

1. **Acceptance invariants** (§5.7) — silence-non-black (D-037), energy-primacy +
   NO `beat_*`-as-primary (beat is accent — FA #4), body coherence (one mass,
   negative space, not `05_anti_uniform_fog`), flow-is-alive, mood travel,
   anti-reference rejection, performance (Tier-2 budget). Most of these have
   automated proxies already (`NimbusBloomFollowerTest`, `NimbusBudgetProbeTests`,
   `PresetVisualReviewTests`); audit which §5.7 bullets still need a gate.
2. **Golden-hash registration** — register Nimbus in `PresetRegressionTests` (if
   it isn't already) so future renderer changes are caught. NB: Nimbus's GPU
   output is animated (flowPhase) — register at a FIXED state (e.g., a converged
   silence or mid fixture) for determinism.
3. **Anti-reference manual check** — the 4 `05_anti_*` images; M7 judgement (no
   automated dHash gate exists — same as Arachne/Skein).
4. **Matt M7** — live review on ≥5 tracks + a local file. **Non-bypassable, Matt's
   call.** This is the gate; you prepare the artifacts, Matt signs off.
5. On pass: flip `Nimbus.json` `certified: false → true`; update
   `RENDER_CAPABILITY_REGISTRY.md`, `KNOWN_ISSUES.md` if any, the design §7 + plan,
   and the increment closeout per the CLAUDE.md protocol.

## Durable learnings from this session (don't relearn these)

- **Profile a volumetric preset at its WORST on-screen body (full swell), not the
  steady state** — the steady-mid budget probe under-measured by ~4× (live max 14.5
  ms vs probe 3.78 ms). The worst-case probe is now in `NimbusBudgetProbeTests`.
- **The cone self-shadow march is the cost centre** (~6×/in-body step) — give it a
  cheap density (`nimbus_density_shadow`, 1 sample). Never `pow()`/transcendentals
  in a per-march-step falloff (a cos^1.5 lobe falloff once DOUBLED the budget; use
  cos²/polynomial). Match step count to the finest octave you keep (>64 just
  aliased a dropped octave). On-screen area is a linear budget lever.
- **noiseVolume texture-sample, never per-step computed fbm** (~20 ms vs ~1.4 ms).
- **Cold-start: cached stems are a CONSTANT snapshot for ~10 s** — gate the
  stem-vs-FV blend on TIME (self-tracked `trackTime`), not stem energy.
- **Deviation primitives sit at ~0.3–0.4 mean and cross 0.8 on only 1–3 % of
  frames** — calibrate thresholds to that (Nimbus uses smoothstep [0.12,0.55]),
  not to an assumed ~±1 range. When a coupling "barely responds," read the SESSION
  (features/stems.csv distribution) before assuming the wiring is wrong.
- **Smoke/cloud is defined by MOTION** (curl/rise/billow), not static texture; and
  **stills can't encode the temporal contract** — get motion references.
- **MetalFX is NOT wired** anywhere; MetalFX Temporal needs motion vectors a
  procedural volume lacks (→ ghosting), so it's the wrong tool. A bilinear upscale
  is appropriate for soft gas. If softness ever needs fixing: raise the render
  scale 0.5→0.65 (one line, still fits budget ~4–5 ms) or wire MetalFX **Spatial**.
- The big `*State.swift` slot-6 pattern, the FA-#72 snake-case MSL rule, the
  golden-hash discipline for `Common.metal` struct edits — all apply.

## Deferred (do NOT block cert)

- **Per-track-distinct gas seed** (the body looks the same starting pattern every
  track; would re-seed the noise from track identity). NB.1 SHA hook exists.
- **PresetSessionReplay route registration** (for the diagnostic replay report).
- The **irregular-silhouette lever** (perturb the envelope boundary for a more
  sprawling cloud — Matt was OK with the current contained-mass read for v1).

## How to run the harnesses

- Budget: `NIMBUS_BUDGET=1 swift test --package-path PhospheneEngine --filter NimbusBudgetProbe`
- Visual contact sheet: `RENDER_VISUAL=1 swift test --package-path PhospheneEngine --filter renderPresetVisualReview` → `/tmp/phosphene_visual/<ts>/Nimbus_*.png`
- Motion strip: `NB_MOTION=1 swift test --package-path PhospheneEngine --filter NimbusBloomFollower` → `/tmp/nimbus_motion/`
- Mood strip: `NB_MOOD=1 swift test --package-path PhospheneEngine --filter NimbusBloomFollower` → `/tmp/nimbus_mood/`
- Full suite baseline: **1385 engine tests** (`swift test --package-path PhospheneEngine`), SwiftLint `--strict` clean, app build clean, `PresetLoaderCompileFailureTest` count **19**.

## All the tuning constants are starting points

Every magnitude in `NimbusState.swift` (follower taus, thresholds, bloom/flow
ranges, mood agitation range) and `Nimbus.metal` (size/bright/lobe/kick
amplitudes, mood poles, motion rates, render scale) is a starting value — Matt's
eye/ear sets the finals. They're all single-line knobs, documented inline.

## Working discipline (from CLAUDE.md — applies to the next session too)

Matt is product/design lead. Articulate the musical role before authoring;
integrate feedback into the model (don't decorate the old answer); verify against
the artifact (render it, read the session csv) before asserting; surface
structural gaps rather than tuning across them; manual/live validation is the gate
for musical feel + visual fidelity (no automated metric substitutes); commit
small with `[NB.9] nimbus: …`; **do not push without Matt's explicit "yes, push."**
