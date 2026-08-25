# Increment WHIT.0 — Rosette: motion-gated look spike

**Type:** preset (throwaway spike; `.metal` only, **no sidecar, no registration**)
**Phase:** WHIT — three visual-music presets after John Whitney Sr.
**Plan:** `docs/presets/WHITNEY_PROGRAM.md` — read the **⚠ REVISED 2026-08-19 banner first**; it
supersedes the pre-revision text wherever they disagree.
**Primary source:** `docs/presets/ARABESQUE_FILM_NOTES_2026-08-19.md` + the evidence frames in
`docs/VISUAL_REFERENCES/_incoming/frames/`.

> **⚠ This prompt was rewritten 2026-08-19.** Its first version specified a *dot-field* spike
> using the `"point"` primitive, with "watch the films" as task 1. Matt then supplied a recording
> of *Arabesque*, watching it falsified four of the program's inferences, and the lead preset
> changed from a point cloud to a closed luminous **line** figure. If you are holding a version
> of this prompt that asks you to render dots, it is stale — stop and get the current one.

**Objective.** After this session there is a rendered, motion-gated answer — in writing, with
frames — to whether Phosphene can draw *Arabesque*'s morphing emblem at the quality the film
sets, and Matt has said go or re-scope. **The verdict is the deliverable; the code may be
discarded.** Preset count unchanged. No sidecar, no golden, no `certified` flag, nothing
registered.

Artifacts 1–3 of the `preset-concept` gate are now in hand (a watched moving source; the look
verified across sequences, not one frame; a three-sentence checkable story). Artifact 4 — a
running look-spike Matt has seen — is this session.

---

## 1. The questions this session exists to answer

Answer all four, in writing, with frames. A hedge is a fail.

1. **Does the morph read?** `rosette_build.png` shows one continuous 30 s passage cycling
   tangle → petals → star-in-a-ring → straight-edged pentagon → back out, at constant 5-fold
   symmetry. Can Phosphene produce that arc, continuously, at constant rate, and does a viewer
   see a figure *tightening and unravelling* rather than a shape wobbling? **This is the gate.**
2. **Is the stroke right?** The film's authority is entirely in stroke quality — thin bright
   white-to-pale-lavender core, soft controlled halation, decisive curvature, near-black ground
   with a faint blue-violet vignette. Program §11.1 names this as the thing that must be
   delivered. If the stroke reads as a flat aliased polyline, nothing else matters.
3. **Does the composed frame do the work?** Mirrored coloured arcs at the left and right edges,
   each carrying a small ellipse (`FILM_NOTES` F4). Cheap to build, and program §12 #1 says it is
   most of the difference between a picture and a plot. Render with and without, and compare.
4. **Which generator?** See §5 task 2 — there is a specific hypothesis to test, not an open
   search.

**Question 1 is the gate; 2 and 3 are what make it worth passing.** If 1 fails, stop and report
rather than tune.

---

## 2. Skill invocations

- **`preset-session`** — at session start, before any `.metal`. Mandatory for preset work.
- **`shader-authoring`** — before writing MSL.
- **`closeout`** — at the end.

Note for `preset-session` Part 1 step 1: **no curated reference set exists yet**, and that is
expected at spike stage — the raw material is in `_incoming/frames/` and curating it properly is
WHIT.1a, gated on this session's verdict. Do not curate it here and do not escalate the absence;
the program doc records the decision.

---

## 3. Read first

1. `docs/presets/ARABESQUE_FILM_NOTES_2026-08-19.md` — **all of it, first.** This is the primary
   source and the reason the spike is what it is.
2. The four evidence sheets in `docs/VISUAL_REFERENCES/_incoming/frames/`. **Read
   `rosette_build.png` as a sequence, not as a grid of stills** — the morph is the concept.
3. `docs/presets/WHITNEY_PROGRAM.md` — the revision banner, then §5 (the coupling), §6 (the port
   surfaces with file:line evidence), §8 WHIT.A, §9.3–9.4.
4. `PhospheneEngine/Sources/Presets/Shaders/DragonBloom.json` lines 19–26 — the `marks` block
   being copied (1536 verts / 3 instances / `line_strip`).
5. `PhospheneEngine/Sources/Presets/Shaders/Skein.metal` — `skein_geometry_vertex` (~line 309)
   for the overlay vertex signature, and `mvWarpPerFrame` (~line 771) for the canvas-hold config.
6. `PhospheneEngine/Tests/PhospheneEngineTests/Presets/AuroraVeilMVWarpAccumulationTest.swift`
   — the QG.4 / D-182 harness template for this paradigm. Adapt it; do not reinvent it.
7. `Scripts/motion_gate.sh` and `Scripts/compare_render.sh` — headers only.

Do **not** read `MILKDROP_STRATEGY.md`, `SHADER_CRAFT.md` §§1–16, or any TONAL source. **There is
no audio coupling in this session** (§6).

---

## 4. Pre-flight invariants

Each failed check stops the session before task 1.

1. Fresh branch off current `origin/main`: `claude/whit0-look-spike`. Tree clean.
2. Full suite green at the branch point. Re-run any GPU-timing failure in isolation before
   calling it red.
3. `docs/presets/WHITNEY_PROGRAM.md` **and** `docs/presets/ARABESQUE_FILM_NOTES_2026-08-19.md`
   both exist in **this working tree**, and the program doc carries the 2026-08-19 revision
   banner. If either is missing, or the banner is absent, **stop and report — do not reconstruct
   them from this prompt.** (CHR.1 ran without its plan: the doc was delivered untracked to the
   primary checkout while the session ran in a worktree.)
4. `docs/VISUAL_REFERENCES/_incoming/frames/` contains the four evidence sheets.
5. **`docs/VISUAL_REFERENCES/_incoming/*.mov` is NOT staged for commit.** It is ~1.5 GB. Confirm
   it is gitignored or LFS-tracked before the first commit — D-211 / LFS.2 exist because this
   class of mistake already cost this repo a reclaim runbook. If it is neither, add the ignore
   rule as commit 1 of this session.
6. Preset count unchanged from `origin/main` (`expectedProductionPresetCount`).

---

## 5. Tasks

### Task 1 — Read the film notes and the sequences. No code yet.

The films were watched in the shaping seat; you are not repeating that. What you are doing is
forming your own read of `rosette_build.png` **as motion**, because you are about to reproduce it.

Write, before any code:

- the sequence of figure states you observe, in order, with the frame each transition lands on;
- whether the symmetry order changes anywhere in the 30 s (the notes claim it does not — check);
- your estimate of stroke width relative to frame height, and of halation radius relative to
  stroke width. These two numbers are the spike's quality target and you will be judged against
  them in task 4.

**Done when:** that written read exists. If it contradicts `FILM_NOTES` §1 or §2, say so —
the notes are one pass by one reader and are not sacred.

### Task 2 — Test the generator hypothesis, on CPU or in a scratch render, before any engine work

There is a specific hypothesis, and it is cheap to falsify.

**Hypothesis:** the film's morph family is a **two-term epicycle** —

> z(t) = e^{i·t} + a · e^{−i·(n−1)·t},  t ∈ [0, 2π)

with n the symmetry order (n = 5 through the `rosette_build` passage) and **a the single morph
parameter**. This is the hypotrochoid/epitrochoid family, and it produces, as `a` sweeps from 0
upward: circle → n-fold undulation → n broad petals → cusped n-point star → petals with inner
loops → open tangle. **That is the observed sequence, in the observed order, from one scalar.**

If it holds, the preset's entire morph is one number — which makes `tonalConsonance → a` the
cleanest possible coupling and makes program §5 nearly free.

The alternative is the chained-polyline reading (the `IMAGINARY/whitney` `?showLines=1` mode):
N points from the differential law connected in index order. Cheaper to reason about, but it
produces straight-edged star polygons rather than the film's smooth cusped curves.

**Do not search beyond these two.** Test the epicycle first; it is the one the film's curvature
argues for.

**Done when:** a sweep of `a` at n = 5 rendered as a strip, placed beside `rosette_build.png`,
with a written verdict: does one scalar reproduce the film's family? Name which observed states
it hits and which it misses. **A miss is the finding** — report it rather than adding terms until
it fits.

### Task 3 — Get it on the engine's proven path

Port to a `line_strip` marks-on-top overlay: copy Dragon Bloom's `marks` configuration, compute
the curve in the overlay **vertex** stage from `vid [[vertex_id]]` and `FeatureVector& f`
(`Skein.metal:309`), canvas cleared to black, canvas-hold or light decay per program §6.

Drive the morph parameter from a plain clock. **No audio.**

**Done when:** the figure runs live through the production scene → warp → compose → swap path,
with the multi-frame harness adapted from `AuroraVeilMVWarpAccumulationTest` written **first**
(`PRESET_SESSION_CHECKLIST` Part 2 — three Aurora Veil increments shipped green against
`preset.pipelineState` while smearing in live playback).

### Task 4 — Answer question 2: the stroke

This is where the spike is most likely to fail, and it is a rendering problem, not a maths one.

Establish, with frames, against your task-1 numbers:

- line width and antialiasing at 1080p — a `line_strip` at 1 px is not automatically a beautiful
  stroke, and Metal line rasterization is not antialiased. If a raw `line_strip` cannot deliver
  the film's stroke, say so and state what would (an SDF-swept capsule in the fragment stage, the
  Skein pour-line pattern, a triangle-strip ribbon).
- halation: HDR bloom via `feedback_pixel_format: "rgba16Float"` + `PostProcessChain`. Tune to
  your task-1 halation-to-width ratio, not to taste.
- the near-black ground with the faint blue-violet vignette.

**Done when:** a side-by-side of your stroke against a crop from `rosette_build.png`, and a
written verdict on whether the stroke is at the film's standard, close, or not close.

### Task 5 — Answer question 3: the frame

Add the mirrored edge arcs (`FILM_NOTES` F4) — a second low-vertex instance of the same overlay,
carrying the saturated hue, on its own slower clock. Render the best morph moment **with and
without** them.

**Done when:** the paired renders exist and there is a written answer to whether the frame is
carrying real compositional weight or is decoration. Program §12 #1 is decided on this evidence.

### Task 6 — Motion gate, and answer question 1

Run `motion_gate.sh` over a ≥ 300-frame contiguous sequence covering a full morph cycle. **Read
the sampled frames as a sequence.**

**Done when:** a written answer to question 1 with the frame sequence, naming which figure states
were legible and which were mushy.

⚠ Read the gate's verdict with care: a symmetry-order step is a large abrupt frame-to-frame
change by construction and will score as a spike — the same false-positive class the FTR
beat-stepping work hit. State the verdict, then state whether each flagged spike **is the morph
or is a defect**, justified from the frames rather than by dismissing the tool.

### Task 7 — HARD STOP. Report; Matt's gate.

Do not proceed to audio coupling, reference curation, sidecar authoring, or any WHIT.1 work.

If question 1 fails, the prescribed response is **re-scope with Matt, not tuning rounds** (the
PHYS escalation rule; D-102 precedent). Bring 2–3 re-scope directions — §10 below has candidates.

### Task 8 — Closeout

---

## 6. Do NOT

- **No sidecar, no registration, no golden, no `certified`.** Preset count unchanged.
- **No audio coupling of any kind.** Not energy, not tonal, not beat. The harmony coupling is
  WHIT.1d. A figure moving for two reasons cannot answer whether one of them reads.
- **Do not commit the `.mov`.** ~1.5 GB. See pre-flight 5.
- **Do not apply `hue = 360·(i+1)/N` to the figure.** That is the Whitney *Music Box* convention,
  not *Arabesque*. The figure is white/pale; hue lives in the frame elements (`FILM_NOTES` F3).
  This is the single easiest way to make the spike look like a generative-art demo instead of
  like the film.
- **Do not add long trails.** The film draws the figure complete each frame; the glow is halation,
  not a comet-tail (`FILM_NOTES` §4). Program §9.2's decay relation governs the *dot field*, which
  is not this preset.
- **No easing, no keyframes, no ambient drift** (§9.4). The film shows no ramp-in, no settle
  anywhere. Adding motion "so it isn't boring" is the failure this reference was chosen to avoid.
- **Do not add generator terms to make the fit better** (task 2). If a two-term epicycle misses
  states, that is the finding.
- **Do not chase the dot field.** `"point"`, the Music Box spiral, and the §9.2 trail relation all
  belong to WHIT.C, which is gated on *Permutations* being watched — a film nobody has seen.
- **No engine source changes.** Everything needed is per-preset config or per-preset shader code
  (§6). If that turns out to be false — most plausibly at task 4, if `line_strip` cannot deliver
  the stroke — **stop and report**. An engine touch discovered mid-spike is a scope finding, not
  a change to make.
- **More than one session.** If the spike cannot answer question 1 in one, that is the finding.

---

## 7. Verification

```
swiftlint lint --strict --config .swiftlint.yml
xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build 2>&1
swift test --package-path PhospheneEngine 2>&1
```

Plus the visual instruments. **Both required; stills alone are not sufficient** (D-181 + D-195):

```
Scripts/motion_gate.sh <slug>          # temporal verdict — load-bearing here
Scripts/compare_render.sh <slug>       # still sheet, for the task-2 and task-4 comparisons
```

Engine + app suites must pass unchanged: this session registers nothing, so any test movement is
a scope violation rather than a regression to fix.

---

## 8. Commit message templates

Local-only. Push requires Matt's explicit "yes, push", to a branch and a PR — never to `main`.

```
[WHIT.0] Repo: gitignore the Arabesque source recording (D-211)
[WHIT.0] Docs: independent read of the rosette morph sequence
[WHIT.0] Spike: two-term epicycle morph family — hypothesis test
[WHIT.0] Spike: line_strip marks-on-top overlay + multi-frame harness
[WHIT.0] Spike: stroke quality — width, antialiasing, halation
[WHIT.0] Spike: mirrored frame arcs, with/without comparison
[WHIT.0] Docs: WHIT.0 verdict — <morph pass/fail>, <stroke verdict>
```

---

## 9. Closeout format

Invoke `closeout`; 8-part report with the verbatim `Scripts/closeout_evidence.sh` block as §2.
Additionally:

- **the generator verdict (task 2)** — does one scalar reproduce the film's family, and which
  states does it miss? This is the finding most likely to shape WHIT.1;
- the stroke comparison against the film crop, with the width and halation numbers from task 1;
- the with/without frame comparison, which decides program §12 #1;
- the `motion_gate.sh` verdict **plus** the morph-or-defect judgement per flagged spike (§7);
- which dispatch path the harness exercised, named explicitly ("tests pass" is not evidence);
- whether the spike code is proposed as WHIT.1c's skeleton or discarded — either is fine;
- any grounding rating ≤ 3 on the `shader-authoring` scale, surfaced for Matt rather than
  resolved in-session;
- **any place your own read of the film contradicts `ARABESQUE_FILM_NOTES`** — and if so, amend
  the notes in the same commit. They are a primary source, so they should be corrected, not
  worked around.

---

## 10. DECISION-NEEDED

**#1 — Carried from the program doc: how ornate should the frame be?** Task 5 produces the
evidence. Recommendation there is the full cartouche. Bring the paired renders and let Matt look
rather than describing them.

**#2 — Only if question 1 fails: which way does the program re-scope?**

Ask this **only** if the morph does not read; do not pre-empt it.

- **A — lead with Frieze instead.** The tiled ornamental band (`dot_band.png`) is the film's
  densest, most colourful imagery, and its headline motion — cells breathing, the repeat drifting
  — is coarser and may read more reliably than a morphing outline.
- **B — hold the figure, change the event.** Keep the emblem but drive the *symmetry order* as
  the primary visible change rather than the tightness, so the event is "the figure becomes a
  six-pointed thing" rather than "the figure tightens."
- **C — drop the program.** If the morph does not read and the stroke cannot reach the film's
  standard, the honest answer may be that *Arabesque* depends on a seven-minute film's patience
  that a 45-second preset scene does not have. That is a legitimate outcome and should be said
  rather than worked around.

**No default** — if question 1 fails, that is a genuine product fork and Matt picks.
