## Increment WL.10 — Witchlight: the camera comes back in

**Type:** preset (framing / view property — no new audio route)

**Objective.** After this session the auto-fit responds to what the pen is drawing *now*, not only to the widest thing it has drawn in the last thirty seconds. Concretely: when the ribbon returns to tighter shapes, the framed radius shrinks and the drawing grows back in frame, and that recovery is measurable on Matt's recorded sessions. Head-in-frame stays at 0.0 % and bead legibility does not regress.

---

### Matt's words, verbatim (2026-08-06, session `2026-08-06T19-36-40Z`)

> "Does the camera ever zoom back in when the ribbon is back to making tighter shapes and forms? Other than this one question, the preset looks good and follows the music pretty well, so we are close to the next increment of development."

That is the whole scope. **The preset is otherwise passing his review** — do not open anything else.

### The measurement that motivates it (already taken, do not re-derive)

`viewScale` by 10 s window on that session:

```
1.78  3.07  3.68  1.77  1.45  1.53  1.21  0.82  0.73  0.74
```

One direction after the opening: **3.68 → 0.73, a ~5× zoom-out over two minutes, one recovery event >5 % in the whole session and it is inside the first 20 s.**

**Two candidate causes were tested at WL.9b. One is already falsified — do not spend the session on it.**

1. ~~The asymmetric shrink constant~~ — **FALSIFIED.** Sweeping the shrink τ 4.0 → 2.0 → 1.0 → 0.5 s leaves the minimum `viewScale` at 0.72 on both sessions tested. It is not the limit.
2. **The fit window.** `rmsRadius` is measured over the WHOLE trail, so the wide part of the figure keeps the target large for a full 30 s after the pen tightens. There is nothing smaller to frame yet. This is the real cause and this increment addresses it.

**A malformed experiment to not repeat:** windowing the fit RADIUS while still measuring distances from the whole-trail `centroidX/centroidY` moves the scale the WRONG way — recent beads sit far from an old centroid, so the measured radius grows. **The fit window and the centroid it measures from must move together.**

### Why this is newly viable, and not a WL.6 retry

WL.6 tried "fit/centre on the newest 40 % of beads" and it collapsed bead legibility (23 → 4 distinct cores across the three attempts). At that time **the camera aim and the scale fit were the same point**, so any change to the fit also moved the framing, and shrinking the drawing to fit more in was the only lever available.

WL.7 separated them: `cameraX/cameraY` (head-biased aim) is independent of `centroidX/centroidY` + `rmsRadius` (scale fit), and head-off-frame is independently gated at 0.0 % on three real sessions. **That is a changed premise, not a retry.** The WL.6 result is still the warning: if distinct beads fall, stop.

---

### 1. Skills to invoke

- **`preset-session`** — before touching any Witchlight source. Mandatory for preset increments.
- **`closeout`** — at the end, before committing.
- `shader-authoring` is **not** required: this increment should not need to touch `.metal` at all (see Do-NOT).

### 2. Read first

1. `docs/presets/WITCHLIGHT_DESIGN.md` §3.3 (how the trail ages), §3.3.1 (WL.7 framing — the aim/fit split), §3.5.2 (WL.9b — the startup transient and the falsified speed hypothesis).
2. `PhospheneEngine/Sources/Renderer/Geometry/WitchlightPath+Events.swift` — `reframe()` only. Everything in scope is in that one function.
3. `PhospheneEngine/Tests/PhospheneEngineTests/Presets/WitchlightSpeedSweep.swift` — the real-session harness; this increment extends it.
4. `PhospheneEngine/Tests/PhospheneEngineTests/Presets/WitchlightHeadFramingTests.swift` — the ≤ 2 % head-off-frame gate that must not regress.
5. `docs/ENGINEERING_PLAN.md` §WL.9b entry — the numbers above, in context.

### 3. Pre-flight invariants

Each of these must hold before task 1. A failure stops the session and is reported, not worked around.

1. `git log --oneline -1 origin/main` contains the WL.9/WL.9b merge (PR #52, `5914f861` or later).
2. `swift test --package-path PhospheneEngine --filter Witchlight` → **25 tests pass**.
3. `swiftlint lint --strict --config .swiftlint.yml` → 0 violations.
4. At least two recorded sessions are readable for the sweep. Known-good: `2026-08-06T19-36-40Z`, `2026-08-06T17-27-21Z`, `2026-08-05T21-48-13Z`. If Matt's `phosphene_sessions` directory is not reachable from the worktree, **stop and ask** — this increment cannot be validated on the 21 s fixtures (they are shorter than the phenomenon; that is the WL.9b lesson).

### 4. Tasks

**Task 1 — extend the real-session harness to report recovery, before changing any production code.**
Add to `WitchlightSpeedSweep` a reported metric for what Matt asked about: how much the framed scale RECOVERS after a wide passage. Suggested (choose and justify in the closeout): `viewScale` p90/p10 ratio, plus a count of recovery events where the scale rises ≥ 20 % within a 15 s span, plus the by-window trajectory already printed.
**Done when:** the harness prints a recovery figure for each session and the baseline numbers for current `main` are recorded in the closeout. The baseline must reproduce the trajectory above on `2026-08-06T19-36-40Z`.

**Task 2 — implement the windowed fit, with the centroid moving with it.**
In `reframe()`, fit BOTH the centroid and `rmsRadius` over the same recent-age subset of beads. Add one tuning constant (`fitWindowSeconds`, seconds of bead age included in the fit; whole-trail behaviour must remain expressible). The camera aim (`cameraX/cameraY`) keeps its existing head-biased derivation — **do not change the aim in this task.**
**Done when:** the code builds, and with the window set to the full trail length the harness reproduces the Task 1 baseline to within noise (proving the change is a no-op at that setting).

**Task 3 — sweep the window on at least three real sessions and choose a value from the measurement.**
Report, per session and per window: recovery figure, `viewScale` p10/p50/p90, head-off-frame %, and distinct-bead count.
**Done when:** a table exists in the closeout and the chosen value is justified by it — not by preference.

**Task 4 — HARD STOP. Do not proceed past this point without reporting.**
If ANY of the following is true at the chosen value, stop and report rather than tuning around it:
- head-off-frame > 2 % on any real session (WL.7 contract), or
- distinct bright cores < 13 (the WL.9b shipped value; **the WL.6 failure signature is this number collapsing**), or
- ribbon share < 0.40 %, or
- the scale visibly pumps on section boundaries in the rendered sequence.
**Done when:** either all four are clear and the session continues, or the report is written and the session ends.

**Task 5 — regression gates and a render.**
Run the full Witchlight suite, the §5 flash budget, and a `RENDER_VISUAL=1` motion sequence. Watch the sequence for pumping — a metric will not catch it.
**Done when:** 25+ Witchlight tests green, flash budget unmoved, and the rendered sequence reviewed by eye with a written verdict.

**Task 6 — docs.**
`WITCHLIGHT_DESIGN.md` gains a §3.3.2 for the windowed fit (what it measures, why the centroid must move with the window, the falsified shrink-τ hypothesis, and the WL.6-vs-WL.7 premise change). `ENGINEERING_PLAN.md` gains the WL.10 entry with the before/after recovery table. `RENDER_CAPABILITY_REGISTRY.md` — extend the existing WL.7 auto-framing row rather than adding a new one.
**Done when:** `swift test --filter DocIntegrity` passes and both numbers in the plan entry are the measured ones.

### 5. Do NOT

- **Do not touch the camera AIM.** Head-in-frame is at 0.0 % and it is the WL.7 contract; this increment moves the scale only.
- **Do not re-open the shrink time constant.** Falsified at WL.9b across 4.0 / 2.0 / 1.0 / 0.5 s.
- **Do not shorten `trailSeconds`.** It is a concept constant — "the drawing is the last 30 seconds" — and changing it is Matt's call, not this increment's.
- **Do not scale bead size with `viewScale`** (rejected at WL.2-f: beads went sub-pixel exactly as the trail filled).
- **Do not raise `framedRadius`** to fit more in. Three WL.6 attempts died there.
- **Do not add an audio route.** Matt's report is that the preset already follows the music; this is a view property.
- **Do not touch `.metal`.** If the fix appears to need shader work, that is a signal the approach is wrong — stop and report.
- **Do not validate on the 21 s route-coverage fixtures alone.** They are shorter than the phenomenon.

### 6. Verification commands

```
swiftlint lint --strict --config .swiftlint.yml
swift test --package-path PhospheneEngine
xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build
swift test --package-path PhospheneEngine --filter Witchlight
WITCHLIGHT_FLASH_BUDGET=1 swift test --package-path PhospheneEngine --filter WitchlightFlashBudget
WITCHLIGHT_SESSIONS=<dirA>:<dirB>:<dirC> swift test --package-path PhospheneEngine --filter WitchlightSpeedSweep
RENDER_VISUAL=1 swift test --package-path PhospheneEngine --filter WitchlightMotionSequence
```

Note: `xcodebuild … test` (as opposed to `build`) SIGTERMs a running `PhospheneApp`. Check `pgrep PhospheneApp` first; if Matt is testing, skip it and say so.

### 7. Commits

`[WL.10] Witchlight: <description>` — small commits per logical step (harness, implementation, docs). **Push only on Matt's explicit "yes, push".** Open a PR; never push to `main` directly.

### 8. Closeout

Invoke the `closeout` skill and produce the 8-part report with the verbatim `Scripts/closeout_evidence.sh` block as §2. Increment-specific additions:

- The Task 3 sweep table (all sessions, all windows).
- Before/after recovery figure and `viewScale` trajectory on `2026-08-06T19-36-40Z`.
- Distinct-bead count and ribbon share before and after — **stated even if unchanged**, because they are the WL.6 failure signature.
- The eyeball verdict from Task 5 on pumping.

---

### DECISION-NEEDED — for Matt, at Task 3

**How quickly should the camera come back in when the ribbon tightens up?**

The camera frames the drawing, and the drawing is the last thirty seconds — so "how fast it recovers" is really "how much of the recent past it frames."

- **Option A — frames roughly the last half-minute (today).** The whole drawing always fits. A wide passage keeps the view pulled back until it ages out, which is what you noticed.
- **Option B — frames roughly the last ten to fifteen seconds.** The view follows what the pen is doing now: it pulls back through a sprawling passage and comes back in within a few seconds of the shapes tightening. The oldest, dimmest end of the trail spends more time outside the frame.
- **Option C — in between, around twenty seconds.** A gentler version of B; recovers, but slowly enough that it reads as drift rather than as the camera reacting.

**Recommendation: B.** It is the direct answer to the question, and the cost — the faded tail leaving frame — is the same trade WL.7 already made deliberately when it aimed the camera at the burning head.

**Default if no reply:** implement B, and report the A/B/C numbers in the closeout so the choice can be changed on one constant.
