# Increment MEN.2a — Meniscus: feasibility spike + wired stub

**Increment type:** preset (with an infrastructure spike)
**Preset:** Meniscus — `milkdrop_inspired`, inspired by `Martin - QBikal - Surface Turbulence IIb`

## Objective

After this session, Phosphene can draw a serpentine projected line-strip surface on
screen through the production render path, and we know — from rendered evidence, not
from reasoning — whether the sideways line glow that keeps the raster open is reachable
with existing pass surfaces or needs new work. Meniscus exists as a registered,
selectable, `certified: false` preset rendering a procedurally-animated surface with no
audio coupling.

**No audio routing and no palette work happen this session.** Tuning is bounded to what
tasks 5 and 6 require to reach a credible non-black resting state, and only *after* task
5's contact sheet exists — nothing beyond that.

The design is already settled. This session does not redesign anything; it answers one
architectural question and lands the stub that MEN.2b's faithful base fills in.

**Increment series — faithful base first, uplift second** (the Nacre / Floret / Glaze
shape; see `MENISCUS_PLAN.md` §2 "Sequencing"):

| | |
|---|---|
| **MEN.1** | Design + curated references. **Done** — authored in the prep seat, 2026-08-03. |
| **MEN.2a** | *This session.* Spike the glow question; wire and register a renderable stub. |
| **MEN.2b** | **The faithful base.** The full wave sim driven the way the source drives it, with the source's own camera behaviour. Deliverable is a side-by-side against the butterchurn render on the same track — the oracle everything after this is judged against. |
| **MEN.3** | **The Phosphene uplift.** Stems strike regions; mood-driven dolly. Each uplift A/B'd against the MEN.2b oracle. |
| **MEN.4** | Polish, flash safety, M7, cert. |

**Why this order matters for *this* session.** MEN.2b needs to reproduce the source's
behaviour to serve as an oracle. So every choice you make here — sim placement, grid
resolution, how the height field is addressed, what the geometry stage can express —
must leave that reachable. If a decision would make the faithful base harder to build,
it is the wrong decision even if it is more elegant.

---

## 1. Skills to invoke

- **`preset-session`** — before opening any `.metal` file or preset sidecar. Mandatory.
- **`shader-authoring`** — before writing any MSL, render pass, or GPU-facing Swift.
  Read the reference-porting rules (FA #64 / #65 / #73) even though this is an
  inspired-by preset rather than a port; the decode-correction discipline applies.
- **`closeout`** — at the end. 8-part report.

---

## 2. Read first (in order)

1. `docs/presets/MENISCUS_PLAN.md` — cover to cover. §3 (source decode) and §7 (risks)
   are the load-bearing sections for this increment.
2. `docs/VISUAL_REFERENCES/meniscus/README.md` — cover to cover, including every
   per-image annotation and the anti-reference list.
3. The seven reference images in `docs/VISUAL_REFERENCES/meniscus/`. Look at them.
4. `docs/ARCHITECTURE.md` §GPU Contract Details — texture and buffer slot layout.
5. `docs/ARCHITECTURE.md` §Module Map — the entries for `RenderPipeline+SceneGeometry`,
   `RenderPipeline+MVWarpScene` (the Dragon Bloom strands branch),
   `Geometry/CymaticSandGeometry.swift`, and `ParticleGeometryRegistry`. These four are
   the precedent surfaces for this preset.
6. `PhospheneEngine/Sources/Presets/Shaders/DragonBloom.metal` — read specifically the
   `DragonStrandVertexOut` path; it is the closest existing thing to what Meniscus needs
   to draw. (This path is recorded from the §Module Map as of 2026-08-03 and was not
   verified against the tree by the prep seat; if it has moved, resolve it from the
   §Module Map entry you just read and note the correction in the closeout.)
7. `docs/presets/NEW_PRESET_CHECKLIST.md` — every registration point, lifecycle-ordered.
8. `docs/SHADER_CRAFT.md` §17 — sidecar schema.

**On the three prior Milkdrop-inspired plans** (`NACRE_PLAN.md`, `FLORET_PLAN.md`,
`GLAZE_PLAN.md`): do **not** read them for *architecture* — they are all `mv_warp`
feedback presets and Meniscus is deliberately not one, so their architecture will pull
you toward the wrong register. Do read `NACRE_PLAN.md` for *process*: its 2a-stub →
2b-faithful-base → 3-uplift sequence is the one Meniscus follows, and NACRE.2b's three
corrected source-decode errors are the model for what MEN.2b is expected to produce.

---

## 3. Pre-flight invariants

Two groups. **Group 1 failures stop the session — report and stop, do not work around.
Group 2 failures have exactly one defined remedy each, which task 0 performs; anything
beyond that remedy is also a stop.**

**Group 1 — hard stops:**

- [ ] You are on a fresh branch off `main`.
- [ ] `swift test --package-path PhospheneEngine` is green at the branch point.
- [ ] `swiftlint lint --strict --config .swiftlint.yml` reports 0 violations.
- [ ] `docs/presets/MENISCUS_PLAN.md` and `docs/VISUAL_REFERENCES/meniscus/` (README +
      7 images) **exist in the working tree**. If they are absent, stop — this increment
      cannot proceed without the design (D-064).
- [ ] You can locate `expectedProductionPresetCount` and the certified count. Record
      both; you will increment the production count by exactly one.

**Group 2 — task 0 resolves these, and only these:**

- [ ] `git status` is clean **except** possibly for the untracked prep-seat design
      artifacts above. Remedy: task 0(a) commits them verbatim. Any *other* dirty path
      is a group 1 stop.
- [ ] `DocIntegrityTests` is green, **or** red solely from date-relative doc-rotation
      debt. Remedy: task 0(b) runs the standard rotation. Any other `DocIntegrityTests`
      failure — a broken D-number citation, a missing index entry — is a group 1 stop.

---

## 4. Tasks

### Task 0 — Housekeeping, before anything else

(a) If `docs/presets/MENISCUS_PLAN.md` and `docs/VISUAL_REFERENCES/meniscus/` are
present but uncommitted, commit them **verbatim**. Do not author them, do not edit
them, do not reformat them — they are prep-seat artifacts.

(b) If `DocIntegrityTests` was red at the pre-flight check **solely** from date-relative
doc-rotation debt, run the standard rotation and commit it as its own commit before task
1. If it is red for any other reason, stop and report.

**Done when:** `git status` is clean, `DocIntegrityTests` passes, and the design plan +
reference set are in `HEAD`.

### Task 1 — Decide the glow treatment from evidence, not from reasoning

Read `MENISCUS_PLAN.md` §3 and §7 R1. The question: how does Meniscus get a **sideways**
glow spread on the drawn lines, given that the existing bloom is isotropic and will
close the raster gaps (reference README anti-reference 5)?

Two sub-questions, both of which must be answered:

**1a — which axis does the glow spread along?** Screen-space X, or the line's local
tangent direction? These are not the same thing: the rows are traversed in serpentine
order and the camera rotates, so a row's screen-space direction changes with the camera
attitude. The source spreads along screen-space X (see `MENISCUS_PLAN.md` §3). Whether
tangent-aligned looks better under camera rotation is an open question — decide it from
a render, and say which you chose and why.

**1b — where does the spread happen?** Enumerate the candidate chains against the
existing GPU contract. At minimum: `direct` + scene-geometry overlay + `post_process`;
the `staged` path with an explicit dilation stage; and building the spread into the line
geometry itself (wide, stretched quads per segment) so no separate pass is needed.

**1c — does the wave step run on CPU or GPU?** It is trivially parallel and belongs on
the GPU; the source ran it on the CPU only because Milkdrop had nowhere else
(`MENISCUS_PLAN.md` §6). The chain chosen in 1b constrains this — a compute-based sim
implies a different lifecycle and registry than a CPU runtime — so decide it here rather
than discovering it in task 3. Precedents to weigh: `CymaticSandGeometry` (compute) vs
the CPU-side `MitosisGen2Geometry`.

**Done when:** a written comparison exists in the closeout naming, for each candidate,
which existing surfaces it reuses, what new surface it requires (if any), and its
frame-budget shape at Tier 1 and Tier 2 — and one is chosen with a stated reason, with
1a and 1c answered explicitly. **If the chosen chain requires a new render pass or a new
GPU contract surface, stop and report before building it** — infrastructure additions
are confirmed with Matt, not assumed (concept bar item 3).

### Task 2 — Multi-frame harness first

Per the production-pipeline testing obligation: write the multi-frame harness for the
chosen dispatch path **before** any shader work, and verify the live path is reachable
from a test. Adapt the existing pattern (`AuroraVeilMVWarpAccumulationTest` is the
reference shape for env-gated multi-frame capture; adapt, do not reinvent).

**Name it `MeniscusMultiFrameRenderTest`.** The rest of this prompt refers to it by that
name.

**Done when:** `MeniscusMultiFrameRenderTest` exists, drives the chosen dispatch path for
≥ 60 frames at silence, captures per-frame output, and asserts both (a) no frame is
black and (b) the mean absolute inter-frame delta exceeds a stated threshold. It is
expected to FAIL at this point — there is no preset yet, which is the point: it proves
the harness is wired to something real.

**Do not commit it red.** Hold it in the working tree and land it in task 3's commit,
once the geometry makes it meaningful. Every commit on this branch is green.

### Task 3 — The serpentine strip geometry

Build the surface geometry: a height field, stepped by a standard two-buffer wave
propagation, projected through a rotation and perspective divide, emitted as **one
continuous line strip in serpentine row order** (alternate rows traversed in opposite
directions, joined at the margins). Per-vertex: screen position, a slope-derived
brightness, and a height-derived colour parameter.

Grid resolution is your call (`MENISCUS_PLAN.md` §6) — start at the source's ~45×45 and
record what you observe as you raise it. Sim placement (CPU or GPU) was settled in task
1c; build to that answer.

**Done when:** the strip renders through the production path, and a rendered frame shows
reference traits **T1** (serpentine polyline with visible turnaround caps at the
margins) and **T2** (low-oblique perspective, near rows spaced, far rows compressed).
Not "the test passes" — a frame you have looked at, attached to the session output.

### Task 4 — Slope shading and the two-layer composition

Add the slope-derived brightness term (crest near-white, trough near-black, sharp
transition — reference `07`) and the separate dark textured ground plane below the
floating surface (**T5**), with a single cool directional light (**T6**).

**Done when:** traits T3, T5, T6 are visible in a rendered frame attached to the session
output.

### Task 5 — HARD STOP: contact sheet before any tuning

Produce a `RENDER_VISUAL=1` contact sheet of the silence state — at minimum 6 frames
spanning ≥ 4 seconds. **Stop and report.** Do not tune, do not adjust constants, do not
proceed to task 6 until this contact sheet exists and is in the session output.

This is the checklist's render-early rule and it is the single highest-value gate in
this increment. The heaviest historical preset sessions burned 85 %+ of their output
tokens before any rendered evidence existed.

**Done when:** the contact sheet exists, is attached to the session output, and you have
written one sentence comparing it against reference images `01`, `02`, and `07` by
filename — and against anti-reference `06`.

### Task 6 — A non-black resting state (placeholder, not the designed one)

Drive the surface with a slow procedural swell so the stub renders something alive and
non-black. **This is a placeholder to satisfy D-037 and give the harness a signal, not
the designed silence state.** The real silence-state design is decided at MEN.2b/MEN.3,
once the faithful base has shown how the surface actually behaves — deciding it now
would be inventing a deviation before the thing being deviated from exists.

Keep it cheap and keep it removable. Do not tune it beyond "credibly alive and clearly
not black." If you find yourself on a third iteration of it, stop — that is the signal
you are designing rather than stubbing.

**Done when:** `MeniscusMultiFrameRenderTest` **passes** — both the non-black assertion
and the inter-frame-delta threshold — and a fresh contact sheet shows visible motion
across the frames and does not resemble anti-reference `06`. Additionally: identify the
codebase's standard non-black-at-silence acceptance assertion, confirm Meniscus is
covered by it (or state why it is exempt, with the precedent preset named), and name
that test in the closeout.

### Task 7 — Registration and sidecar

Register Meniscus everywhere `NEW_PRESET_CHECKLIST.md` enumerates. Sidecar per
`MENISCUS_PLAN.md` §8: `family: "milkdrop_inspired"`, `motion_paradigm:
"mesh_animation"`, `concept_tags`, `inspired_by` provenance block, `rubric_profile:
"full"`, `certified: false`.

**Provenance, precisely.** The source available on the dev machine is the butterchurn
JSON conversion, not an original `.milk` — the same situation as the Nacre / Floret /
Glaze provenance. Record it honestly: filename
`Martin - QBikal - Surface Turbulence IIb.json`, note the butterchurn-JSON form in the
CREDITS row, original artists Martin and QBikal (from the filename pattern —
best-effort, per the D-111 schema), and this SHA-256, computed 2026-08-03 from
`~/mdrender/builtins/` (9,527 bytes):

```
90297c2c0794cac783be111e6d7479aa87ce4e54b4c7f120f13a5d2e9e9d7ec7
```

Re-verify it on the dev machine before committing; if it differs, the file changed and
the recorded hash must be the one you verified. **Do not copy the source file into the
repo** (D-116 bullet 4).

Extend `docs/CREDITS.md` with the attribution row.

**Done when:** `expectedProductionPresetCount` is incremented by exactly one; the full
engine and app suites are green; and the regression-coverage question is answered
explicitly — either a golden-hash entry exists, or Meniscus is exempted with the
precedent preset named and the reason stated in the closeout. Do not add an exemption
silently.

### Task 8 — Closeout

Per §8 below.

---

## 5. Do NOT

- **Do not use `mv_warp` or any feedback accumulation.** The source has none
  (`MENISCUS_PLAN.md` §3 — its warp shader returns black, which wipes the buffer every
  frame). Meniscus is `mesh_animation`, one paradigm, D-029. If a feedback layer starts
  to look attractive for the trails, re-read §3 — the trails in the reference are
  sideways glow spread, not accumulation.
- **Do not author the dense sheet as a material.** No BRDF, no environment map, no
  SSGI, no PBR. Reference `03` looks like brushed chrome because a hundred slope-shaded
  lines are adjacent, not because of a material. This is the failure path that retired
  Kinetic Sculpture (D-188) and Glass Brutalist (D-186). If you find yourself reaching
  for a material, that is the escalation trigger — stop and report.
- **Do not add any audio coupling.** Not the stems, not loudness, not beat, not mood.
  The source's own audio path lands at MEN.2b; the Phosphene stem routing lands at
  MEN.3. A stub with no audio is the correct output of this session.
- **Do not invent Phosphene-native behaviour of any kind.** No stem regions, no mood
  coupling, no designed silence state, no palette. Every deviation from the source is
  earned *after* the faithful base exists and can be A/B'd against
  (`MENISCUS_PLAN.md` §2 "Sequencing"). Aurora Veil is the precedent for what happens
  otherwise: five rounds of accretion, deleted, rebuilt as a faithful port, then
  certified.
- **Do not foreclose the faithful base.** If a design choice here would make the
  source's own drop-placement path or camera behaviour hard to reproduce at MEN.2b,
  choose differently and say why in the closeout.
- **Do not touch palette or hue.** MEN.3.
- **Do not use absolute thresholds on AGC-normalized energy** anywhere, ever — though
  this should not come up at all, because there is no audio coupling (D-026 / FA #31).
- **Do not add isotropic bloom to the line surface.** It closes the raster gaps and
  destroys T1.
- **Do not use a top-down or orthographic camera.** T2. Note that the Cymatic Resonance
  CR.1.2 correction moved *to* top-down for a different preset — that lesson does not
  transfer.
- **Do not transcribe equations from the source JSON.** The decode in
  `MENISCUS_PLAN.md` §3 is prose for exactly this reason (D-116 bullet 1). Write the
  wave step and the projection from first principles.
- **Do not restructure `MENISCUS_PLAN.md` or the reference README.** Append findings to
  plan §9; propose amendments in the closeout.
- **Do not push.** Local commits only, unless Matt says "yes, push".

---

## 6. Verification

```
swiftlint lint --strict --config .swiftlint.yml
xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build 2>&1
swift test --package-path PhospheneEngine 2>&1
```

Increment-specific:

```
swift test --package-path PhospheneEngine --filter MeniscusMultiFrameRenderTest 2>&1
swift test --package-path PhospheneEngine --filter PresetAcceptanceTests 2>&1
swift test --package-path PhospheneEngine --filter DocIntegrityTests 2>&1
RENDER_VISUAL=1 swift test --package-path PhospheneEngine --filter PresetVisualReview 2>&1
```

---

## 7. Commits

Format `[MEN.2a] <component>: <description>`. Small commits per logical step:

```
[MEN.2a] Geometry: serpentine height-field strip + projection, with MeniscusMultiFrameRenderTest
[MEN.2a] Shaders: slope shading, ground plane, single directional light
[MEN.2a] Geometry: placeholder procedural swell, non-black resting state (D-037)
[MEN.2a] Presets: register Meniscus, sidecar + provenance + CREDITS
```

Task 0's doc commits, if any, land first with their own `[MEN.2a] Docs:` messages.
**Every commit on this branch is green** — the task-2 harness is written before the
geometry but lands with it, not before it.

---

## 8. Closeout

Invoke the `closeout` skill; produce the 8-part report with the verbatim
`Scripts/closeout_evidence.sh` block as §2.

Increment-specific additions:

- **Which dispatch path the tests exercised**, named explicitly. "Tests pass" is not
  evidence of correctness. If any test hits only `preset.pipelineState`, say so and say
  what that does and does not verify.
- **The task-1 comparison**, with the reason for the choice and an explicit answer to
  1a (screen-space X vs line tangent).
- **The task-5 and task-6 contact sheets**, with the per-image comparison sentences,
  and how many iterations the placeholder resting state took (more than two is a signal
  you were designing rather than stubbing — say so if it happened).
- **Trait checklist status**: T1, T2, T3, T5, T6 from the reference README, each marked
  present / absent / partial with the frame it is judged from. **T4 (localized
  disturbance on a calm field) is not assessable this increment** — it depends on drop
  impacts, which arrive at MEN.2b. Mark it `deferred — MEN.2b`, do not guess.
- **Anti-reference check**: explicitly confirm the silence frame does not resemble `06`.
- **Grid resolution findings**: what you observed as resolution rose, and where the
  raster stopped reading as a raster (`MENISCUS_PLAN.md` §6, risk R4).
- **What MEN.2b now needs from you.** Name the seams the faithful base will use: where
  drop impacts get injected into the height field, where camera angles come from, and
  what shape the audio input needs to arrive in. If anything you built makes the
  faithful base harder, say so plainly — that is cheaper to hear now than at MEN.2b.
- **"What I now believe about why this preset is hard"** — one sentence. It will be
  compared against the same sentence at MEN.2b; if it hasn't changed, the iteration has
  gone mechanical.
- **Anything in `MENISCUS_PLAN.md` §3 that the implementation proved wrong.** The decode
  was done from the source file without running it; if reality disagrees, that
  correction is the most valuable thing in the report (the Nacre `mv_x`/`mv_a`
  precedent).
- **Cannot-verify list.** Anything asserted without a diagnostic to back it.

---

## 9. DECISION-NEEDED

**Question:** how soft should the lines look, if the softest version costs an extra
increment before Meniscus responds to music at all?

**Options — what Matt would see:**

- **A — Soft, one increment later.** The lines carry a smooth sideways bleed, so the
  surface reads as light lying on water. Meniscus sits one increment longer before it
  responds to music.
- **B — Crisper, now.** Sharper, more diagrammatic lines — closer to a sonar plot than
  to a lit water surface, and arguably a cleaner look in its own right. Meniscus reaches
  a music-reactive state one increment sooner; softening becomes a later polish pass
  once we know the preset works.

**Recommendation: A, if it can be reached without delay; otherwise B.** Task 1 will
establish whether there is a way to get the soft look at no extra cost. If there is,
take the soft look. If the soft look would genuinely add an increment, take B — the
preset's identity is in the shape of the surface and the way light picks out the crests,
not in the glow, and we should find out whether the concept works against real music
before polishing it.

**Default if no reply:** follow the recommendation as task 1's evidence resolves it. Do
not build new engine surface for the glow without asking, in either case.

---

## Appendix — D-number placeholders

This increment will file one decision entry recording the Meniscus register, the
faithful-base-first sequencing, and the declared D-121 divergence axis. **Fill the number at run time** from the next available in
`docs/DECISIONS.md` §Index — do not assume. As of 2026-08-03 the highest filed was
**D-199** (CR.2 Cymatic Resonance rebuild), so **D-200** is the likely number, but
verify against the file; parallel sessions file concurrently and the auto-memory "next
number" notes have been stale before (D-096 precedent).
