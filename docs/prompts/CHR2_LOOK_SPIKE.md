# Increment CHR.2 — Stave: motion-gated look spike

**Type:** preset (throwaway spike; `.metal` + CPU geometry, **no sidecar, no registration**)
**Phase:** MD.6 · inspired-by uplift #8 of 10 toward the D-114 first-release bundle
**Plan:** `docs/presets/STAVE_PLAN.md` — read the **⚠ CHR.1 AMENDMENT block first**; it
supersedes §0 and the CHR.2 body below it wherever they disagree.

**Objective.** After this session there is a rendered, motion-gated answer — in writing, with
frames — to the concept question, and Matt has said go or re-scope. **The verdict is the
deliverable; the code may be discarded.** Preset count stays 28. No sidecar, no golden, no
`certified` flag, nothing registered.

---

## 1. The question this session exists to answer

CHR.1 established by measurement that four per-stem traces collapse (65–93 % of each trace's
motion is the mix's shared loudness envelope). Matt re-scoped to **two traces**, and then on
2026-08-13 settled the driver as **split the job**:

| layer | driver | latency |
|---|---|---|
| trace **position** | band split — rhythm `subBass+lowBass`, melodic `midHigh+highMid+high`, each EMA-centred (FA #31, never absolute AGC values) | ≈0.3 s |
| trace **colour + weight** | per-stem — `drums+bass` vs `vocals+other` | ≈3.0 s |

**The gate has two halves and BOTH must pass:**

1. **Geometry.** Do the two band-driven traces read as two *voices*, or as two parallel copies
   of one line? Measured inputs say they should: `r` +0.055 with divergence **1.88** against a
   1.45 independence null — mildly anti-correlated, i.e. a low-vs-high see-saw.
2. **Colour.** Does the stem-driven colour legibly carry instrument identity, or is it
   decoration a viewer cannot decode?

**Half 2 is where this decision's cost lands and is the more likely to fail.** Choosing
band-driven position bought marks that land on the beat, at the price of moving instrument
identity out of the geometry and into hue — a weaker read by construction. Say so honestly.

---

## 2. Skill invocations

- **`preset-session`** — at session start, before any `.metal`. Mandatory for preset work.
- **`shader-authoring`** — before writing MSL.
- **`closeout`** — at the end.

---

## 3. Read first

1. `docs/presets/STAVE_PLAN.md` — the **amendment block**, then §CHR.2.
2. `docs/diagnostics/CHR1_STEM_DECORRELATION_2026-08-11.md` — §2 capture table, §3 liveness,
   §4 decorrelation. **Read its correction banner**: 13 of 15 track labels were shifted in an
   earlier version, so cite only the corrected tables.
3. `PhospheneEngine/Sources/Renderer/Geometry/WitchlightStroke.swift` +
   `WitchlightPath.swift` — the CPU history-ring + stroke pattern this spike copies.
4. `docs/PRESET_SESSION_CHECKLIST.md` — Part 1, the session-start steps.
5. `Scripts/motion_gate.sh` and `Scripts/compare_render.sh` — headers only; these are the
   instruments, and §7 states how their verdicts are read for this preset specifically.

Do **not** read `MILKDROP_STRATEGY.md` §§1–12, or any CHR.3/CHR.4 material.

---

## 4. Pre-flight invariants

Each failed check stops the session before task 1.

1. Fresh branch off current `origin/main`: `claude/chr2-look-spike`. Tree clean.
2. Full suite green at the branch point. **Three GPU timing tests flake under the loaded
   parallel suite** — re-run any failure in isolation before calling it red
   (`KNOWN_ISSUES.md` names the class).
3. `docs/presets/STAVE_PLAN.md` exists in **this working tree** and its amendment block records
   the driver as resolved. **If it is missing, stop and report — do not reconstruct it from
   this prompt.** (CHR.1 ran without it: it was delivered untracked to the primary checkout
   while the session ran in a worktree.)
4. Preset count is 28 (`expectedProductionPresetCount`). If it is 29, something registered a
   Stave preset early — stop.

---

## 5. Tasks

### Task 1 — Pick the capture set, from measured worst cases

Use CHR.1's corrected numbers, not intuition. The set must include:

- **Bohemian Rhapsody (93.4 %)** or **Superstition (93.0 %)** — the corpus's genuine worst
  common-mode cases, i.e. where two traces are most at risk of collapsing.
- **Bleed** — the low-excursion case (p95 0.16–0.19), where a trace-amplitude floor is needed.
- **Dance Yrself Clean** — the opposite extreme (p95 1.05–1.23). With Bleed it bounds a ~7×
  trace-gain span that one fixed gain has to survive.
- One sparse track (**Clair De Lune**) for legibility at the easy end.

⚠ **Do not pick "a jazz track because jazz is hardest"** — that was a label-shift artifact,
corrected 2026-08-12. Jazz (Take Five, 82.9 %) is among the *easiest*.

**Done when:** the set is named with its measured common-mode / excursion figures.

### Task 2 — Minimal geometry, flat colour, control render FIRST

CPU history rings → **2** line-strip traces, position from the band split, on a `ParticleGeometry`
following the `WitchlightStroke` pattern. Beat gridlines as plain verticals.

**Flat colour. No glow, no backdrop, no echo, no stem colour yet.** This render is the control
for half 2 of the gate — without it there is nothing to compare the coloured version against,
and "the colour helps" becomes an assertion rather than an observation.

**Done when:** flat-colour renders exist for every task-1 capture.

### Task 3 — Answer gate half 1 (geometry), in writing

Per capture: do the two traces read as two voices? Does the measured divergence (1.88) actually
*look* like a see-saw at trace scale? Does the grid read as **the beat** rather than as graph
paper? Do the traces land on the gridlines — this is what the driver decision bought, so verify
it rather than assume it.

**Done when:** a per-capture verdict table with frames.

### Task 4 — Add stem-driven colour, and answer gate half 2

Only now add colour and weight from `drums+bass` vs `vocals+other`.

**Done when:** coloured renders beside the flat controls, and a written answer to: *can a
viewer tell which trace is carrying which instrument group from the colour alone?* If the
honest answer is "not really", say that — it is the finding this session most needs to
surface, and it is a re-scope trigger, not a tuning prompt.

### Task 5 — HARD STOP. Report; Matt's gate.

Do not proceed to shading, palette, echo, or any CHR.3 work. If either half fails, §2.0's
prescribed response is **re-scope with Matt, not tuning rounds** (D-102 / FA #58). Bring
2–3 re-scope directions as material for his call.

### Task 6 — Closeout

---

## 6. Do NOT

- **No sidecar, no registration, no golden, no `certified`.** Count stays 28.
- **No shading, bloom, echo, or palette work** — that is CHR.3. Resist making the spike pretty;
  a pretty spike answers the wrong question.
- **No autonomous motion.** No drift, no ambient animation, no self-running background life.
  The traces' motion *is* the signal, and a quiet passage flatlining is the design. Adding
  motion "so it isn't boring" is the movie failure this source was chosen to avoid.
- **No absolute thresholds on AGC-normalised band values** (FA #31) — the position drivers are
  EMA-centred, always.
- **Do not switch the driver.** It is settled (amendment item 3). If the spike suggests the
  other driver, that is a finding for Matt, not a change to make mid-session.
- **More than one session.** If the spike cannot answer the gate in one, that is itself the
  finding.

---

## 7. Verification

```
swiftlint lint --strict --config .swiftlint.yml
xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build 2>&1
swift test --package-path PhospheneEngine 2>&1
```

Plus the visual instruments — **both are required, stills alone are not sufficient**
(D-181 + D-195; stills hid the Truchet jitter):

```
Scripts/compare_render.sh <preset>     # still contact sheet + per-trait verdict table
Scripts/motion_gate.sh <preset>        # temporal verdict
```

⚠ **Read `motion_gate.sh`'s verdict with care for this preset.** It scores a beat-stepped
preset as jitter — the spikes *are* the beats (the FTR finding). Stave's gridlines and any
beat-locked element will trip the same heuristic. State the motion verdict, then state whether
the flagged motion is the signal or a defect, and justify it from the render rather than
dismissing the tool.

Engine + app suites must pass unchanged: this session registers nothing, so any test movement
is a scope violation rather than a regression to fix.

---

## 8. Commit message templates

Local-only; push requires Matt's explicit approval.

```
[CHR.2] Spike: two band-driven traces on a beat grid (flat colour control)
[CHR.2] Spike: stem-driven colour on the traces
[CHR.2] Docs: look-spike verdict — <geometry pass/fail>, <colour pass/fail>
```

---

## 9. Closeout format

Invoke `closeout`; 8-part report with the verbatim `Scripts/closeout_evidence.sh` block as §2.
Additionally:

- the per-capture verdict table for **both** gate halves, with frames;
- the flat-colour vs coloured comparison, which is the whole evidence for half 2;
- the `motion_gate.sh` verdict **plus** the signal-or-defect judgement (§7);
- whether the spike code is proposed as CHR.3's skeleton or discarded — either is fine;
- any grounding rating ≤ 3, surfaced for Matt rather than resolved.

---

## 10. DECISION-NEEDED

**#1 — Only if gate half 2 fails: what should carry instrument identity instead?**

Ask this **only** if the stem-driven colour turns out to be undecodable; do not pre-empt it.

- **A — drop the identity claim.** Two traces, band-driven, no instrument story. Honest and
  simple; the preset becomes "low against high" and the concept sentence changes to match.
- **B — move identity to trace weight or texture** rather than hue — dotted vs solid, thick vs
  thin. Cheap to try, and the source's own register is a *dotted* trace, so it is in keeping.
- **C — revisit the driver.** Stem-driven position restores identity to the geometry at the
  cost of 3.0 s against in-time gridlines. Matt weighed this on 2026-08-13 and chose against
  it; reopening needs the spike's evidence, not an argument.

**No default** — if half 2 fails, that is a genuine product fork and Matt picks.
