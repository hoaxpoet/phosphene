# CS.1.y Kickoff — Cold-Start Grid-Phase Fix (BUG-017)

**Hand this to a new Claude Code session verbatim. Do not summarise it.**

---

## Read these first, before doing anything else

1. **`docs/QUALITY/KNOWN_ISSUES.md` → BUG-017** — the full defect record: root cause, evidence, fix scope, verification criteria. This is the load-bearing reference.
2. **`docs/ENGINEERING_PLAN.md` → Phase CS section**, especially **Increment CS.1.y**. CS.1 and CS.1.x are ✅ complete; you are doing CS.1.y.
3. **`docs/COLD_START_SYNC_DESIGN_2026-05-20.md`** — §4 (what cold-start infrastructure already exists), §5 (what was unverified), §6 (risks — §6.1 on the drift tracker is directly relevant).
4. **`CLAUDE.md`** — the whole file. Particularly: the **Defect Handling Protocol** (CS.1.y is the Fix + Validation stages of a P1 multi-increment defect — CS.1.x was the Diagnosis stage); the **Audio Data Hierarchy**; the **Authoring Discipline** section ("design is upstream of testing", the **Grounding priority** soft-rule, "stop and report").
5. **The code**, read end to end before designing:
   - `PhospheneApp/VisualizerEngine+Stems.swift` — the cold-start grid-install path (~line 485, `cached.beatGrid.offsetBy(0)`) and `recalibrateGridFromTapAudio` (BUG-007.9).
   - `PhospheneEngine/Sources/DSP/LiveBeatDriftTracker.swift` — the whole file: `setGrid(_:initialDriftMs:)` (~:408), the BUG-007.x lock state machine, the drift EMA.
   - `PhospheneEngine/Sources/Session/GridOnsetCalibrator.swift` — note `maxMatchWindow = 0.200` (:41).
   - `PhospheneEngine/Sources/DSP/BeatGrid.swift` — `offsetBy`.

## What CS.1 found and CS.1.x diagnosed

Phase CS exists because Matt's bar is "beat-synced from frame 1 of every track." **CS.1** built a verification harness (`ColdStartVerifier`) and found **only 3 of 10 tracks pass** the ±50 ms bar. **CS.1.x** diagnosed the root cause (BUG-017):

The cold-start grid is installed `cached.beatGrid.offsetBy(0)` — Beat This! run on the 30 s Spotify **preview clip**, with the preview's timeline used as the track's timeline verbatim. The preview is an arbitrary excerpt; its position in the full track is unknown; so the grid's beat phase, applied from track t=0, is off by an arbitrary per-track amount that folds to **±½-beat**. Nothing corrects it in the 10 s cold-start window: `GridOnsetCalibrator` runs on the preview (never the live track start); the live drift EMA makes no gross phase jump; the BUG-007.9 recalibration fires only after ~15 s and its ±200 ms cap discards large offsets. Per-track failures span −128 to +338 ms, within-track tight (MAD ~15 ms — a clean phase error, not jitter).

## The task — CS.1.y

Fix BUG-017. **This is design-first** — produce a fix design and surface its risks to Matt **before writing any code** (CLAUDE.md "design is upstream"). Then implement, then validate. Likely splits into design → implement → validate sub-increments.

**Fix direction** (from BUG-017 — refine it in the design, do not treat it as final):
- A cold-start phase acquisition: in the first ~1–2 s of playback, phase-lock the grid to the first live sub-bass onsets. The grid's **tempo** is reliable (Beat This!); only the **phase** is wrong — a few live onsets + the known tempo pin the phase.
- Widen or replace the ±200 ms `GridOnsetCalibrator.maxMatchWindow` — the true error folds to ±½-beat, so a correction up to ±half-the-beat-period is needed (≈ ±395 ms at 76 BPM).

**Design questions you must resolve (do not skip):**
- **Beat-phase ambiguity.** A few onsets at a known tempo can lock ½-beat-off, especially on sparse/syncopated tracks (HUMBLE — 76 BPM hip-hop — was the worst failure, +338 ms). What confidence gate prevents a wrong-phase lock?
- **Interaction with the BUG-007.x lock state machine** (`lockState`, the auto-rotate bar-phase logic, the EMA). The cold-start acquisition must not destabilise steady-state tracking.
- **Budget.** Matt accepts "~1 s of wonky performance while the transition occurs" — the correction should land within ~1–2 s.
- **Grounding** (CLAUDE.md soft-rule). Is there a working reference for cold-start beat-phase acquisition? Surface "no precedent for X" risks to Matt before implementing.

## The verification tool already exists — use it, don't rebuild it

`ColdStartVerifier` (`PhospheneEngine/Sources/ColdStartVerifier/`) was built and verified in CS.1. **Trust it** — its measurement design (Beat This! one-beat-per-beat reference; clock offset pinned via a precise raw-tap-start timestamp) cost CS.1 significant iteration to get right; do not re-litigate it.
- Run: `cd PhospheneEngine && swift run ColdStartVerifier --session <session-dir>` → writes `<session>/cold_start_report.md`.
- Self-test the harness math: `swift run ColdStartVerifier --self-test`.
- It requires a capture made with `PHOSPHENE_FULL_RAW_TAP=1` (already in Matt's Xcode scheme). Verify a capture: `session.log`'s "raw tap capture started" line must read `max=86400s wallclock=<number>`.
- Verifying the fix needs a **fresh full-session capture from Matt taken after the fix is built** — plan for that re-capture.

## Verification / done-when

- `ColdStartVerifier` on a fresh post-fix capture reports **≥ 90 % of tracks passing** the ±50 ms / 90 % bar.
- Engine suite green: `swift test --package-path PhospheneEngine` (1265-test baseline).
- BUG-007.x lock machinery + steady-state tracking preserved — add/extend a regression test.
- **Matt's M7 perceptual review on a real listening-party playlist** — the load-bearing close criterion.
- Closeout: update BUG-017 (`Resolved` field + commit hash), `docs/RELEASE_NOTES_DEV.md`, `ENGINEERING_PLAN.md` (mark CS.1.y done).

## Hard rules

- **Design before code.** Surface the design + risks to Matt before implementing.
- This touches `LiveBeatDriftTracker` — **high regression risk**. The engine suite must stay green; a passing harness verdict is necessary but not sufficient (Matt's M7 is the gate).
- **Do not fall into CS.1's failure mode** — CS.1 burned many solo iterations on the harness measurement design. If a design or fix attempt is not converging, **stop and report** rather than iterating blind.
- Commit format `[CS.1.y] component: description`; small commits; **do not push without Matt's explicit "yes, push."**
- Stop and report instead of forging ahead when tests fail, scope expands beyond the fix, or the change would require broader architectural work than authorised.

## Status on entry

- Branch `main`. ~13 commits ahead of `origin` (unpushed) — SR.1 + CS.1 + CS.1.x.
- CS.1 ✅ (harness built, verdict FAIL 3/10). CS.1.x ✅ (diagnosis, BUG-017 filed Open).
- `ColdStartVerifier` is built and committed; `SessionRecorder` records the precise raw-tap-start (`1e2e47fa`).
- CS.1's reference capture: `~/Documents/phosphene_sessions/2026-05-22T16-57-36Z/` (+ its `cold_start_report.md`).
- Per-track CS.1 result: pass — Around the World / Get Lucky / Royals; fail — Billie Jean +69 ms, Seven Nation Army +93, Superstition −28, Everlong −66, B.O.B. +10 (jittery), HUMBLE +338, Money −128.

If you find this prompt is wrong or stale, update it before working against it.

— Matt + Claude (2026-05-22, CS.1.x closeout)
