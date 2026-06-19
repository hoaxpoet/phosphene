# Kickoff — LFPLAN: make the AI plan visibly drive the visuals (timing-quality follow-ups)

Run this in a FRESH session (Matt's preference — a clean read avoids stale-context drift). **Build/validate live from the PRIMARY checkout, not a worktree** — the app can only be exercised live (no app-test harness for `VisualizerEngine`), worktrees lack the gitignored Spotify client id + tempo fixtures, and the changes are app-layer.

## Why this exists (the arc so far — 2026-06-19)

Matt's recurring symptom across several live sessions: **"the visuals don't respond to the song's structure."** Tracing it went four layers deep, each fix revealing the next. All of the below is **done and on LOCAL `main`** (tip `45ae765`, ahead of origin by 17, **NOT pushed**); worktree `youthful-tesla-87bd53` is clean:

1. **BUG-042 (the structural detector) — ✅ RESOLVED.** It emitted note-scale junk (~a "section" every 1.5 s). Fixed by 2 Hz time-bucketed decimation + `minNoveltyFloor` recalibrated 0.02→0.01. Live-validated (SMTS: 5 sections, conf to 0.91). *Don't reopen this — it works.*
2. **Reactive scoreGap** — in reactive mode the orchestrator only switches to a *higher-scoring* preset, so on uniform material it switched once then sat. (Noted, not the path we took.)
3. **LFPLAN.1/.2** — local-file sessions ran in reactive *fallback* because `buildPlan()` was disabled (a 2026-05-28 BUG-021 revert that cited preset-cycling "one every ~5 s" with a 2-preset catalog). Root cause of *that* cycling was BUG-042's junk count inflating `estimatedSectionCount` → ~180 tiny planner segments. With BUG-042 fixed (`PlannerSectionCountScalingTests` pins 180→9), catalog 2→7, and the Next-lockup separately fixed (BUG-059), **re-enabled `buildPlan()` for local files**.
4. **LFPLAN.3** — re-enabling gave "planned" mode but presets *still* didn't auto-switch: **automatic plan execution was never wired engine-wide** (`currentPreset(at:)`/`currentTransition(at:)` had zero callers; `applyLiveUpdate` only *adapted* the plan). Wired it: the ~3 Hz orchestrator tick now applies the active segment's planned preset via a new `applyPlannedSegment` (with a manual override held until the next track, Matt's choice).

**Where it stands now (the reason for this brief):** the full chain works — detector → plan → execution — but the plan's *timing quality* is off. Matt's live test (session `2026-06-19T19-21-39Z`, SMTS + In Bloom) showed **two distinct problems**, both diagnosed last session, neither fixed:

- **(A) Rapid cold-start cycling** — 8 different presets in the first ~24 s (~every 3 s), then it locks. It's a TRANSIENT (stops at ~24 s = the stem/mood/detector convergence window), so the **LiveAdapter re-patches the plan rapidly during volatile cold-start** (mood-override + boundary-reschedule) and `applyPlannedSegment` faithfully applies every churn. This is the historical cycling symptom returning through a new door.
- **(B) Not section-aligned ("premature")** — `SessionPlanner+Segments.makeSections` slices each track into **equal durations** (`track_length / estimatedSectionCount`); it uses the section *count* but discards *where* the real sections are. So transitions land at even ~32–40 s intervals, not on the music's actual chorus/verse boundaries. The detector knows the real times (`features.csv` records them); they never reach the planner — `TrackProfile` carries only the count.

## The two increments

Recommended order: **LFPLAN.4 first** (small, kills the regression-risk cycling), then **LFPLAN.5**.

### LFPLAN.4 — stop the cold-start cycling (small, ~app-layer)

Add a **min-dwell** + a **cold-start gate** to plan-execution so the cold-start churn can't machine-gun presets.

- File: `PhospheneApp/VisualizerEngine+Orchestrator.swift` — the `applyPlannedSegment(_:waitsForCompletion:)` helper (added in LFPLAN.3, `b116e98`) and `applyLiveUpdate`.
- Pattern to mirror: the reactive path already has a 60 s cooldown (`lastReactiveSwitchTime`, same file). Plan-execution should have a shorter **~15–20 s** min-dwell (section-scale) between *auto* applies, plus suppress applies in roughly the **first ~10–15 s** of a track (the volatile window).
- **Subtlety to design around:** the *first* planned preset of each track should still apply promptly (you want the track to start on its planned visual — this also kills the ~0.5 s default-preset flash noted in LFPLAN.3). So the dwell must not block the first apply per track; only subsequent ones. Track-change already resets `lastAppliedPlannedPresetID = nil` + `manualPresetOverrideThisTrack = false` at both sites (`+Capture.swift` streaming, `+LocalFilePlayback.swift` `applyLocalFileTrackState`) — add a per-track "last plan-apply time" reset there too. Cleanest is likely: apply the planned first segment at track start (promptly), then min-dwell every subsequent auto-apply.
- Don't suppress *manual* picks (the `manualPresetOverrideThisTrack` path) — only the plan's auto-applies.
- Validation: a live playlist (Matt) — the early burst should be gone; transitions feel deliberate (≥15 s apart). Read `session.log` `preset →` lines (count + spacing in the first 30 s).

### LFPLAN.5 — segment at the real section times (moderate; analysis → profile → planner)

Make the planned segment boundaries land on the detected sections instead of equal slices.

- `PhospheneEngine/Sources/Session/SessionPreparer+Analysis.swift:287` currently passes `estimatedSectionCount: Int(mir.latestStructuralPrediction.sectionIndex) + 1` — i.e. only the count. The real times are in `mir.structuralAnalyzer.boundaryTimestamps`.
- Add an **optional** section-times field to `TrackProfile` (`PhospheneEngine/Sources/Session/TrackProfile.swift`) — optional so persisted/cached profiles (which lack it) decode and fall back gracefully.
- `PhospheneEngine/Sources/Orchestrator/SessionPlanner+Segments.swift` `makeSections` uses the real times when present, else the current equal-slice behaviour (back-compat). Keep a sane minimum segment length so two close boundaries don't make a tiny segment.
- Watch: the planner is engine-side and well-tested (`GoldenSessionTests`, `MultiSegmentSmokeTest`, `MaxDurationFrameworkTests`); changing `makeSections` will move golden expectations — re-express them deliberately. Cached profiles for a re-played track won't have times until re-analyzed (note it; not a blocker).
- Validation: live (Matt) — transitions land on real section changes (chorus drops), confirmed against `features.csv` `section_start_s` (cols 53–55).

## Read first (authoritative — don't trust this brief over them)

- `docs/QUALITY/KNOWN_ISSUES.md` §BUG-042 — the full resolved arc + the "two downstream preset-variety follow-ups → LFPLAN" framing.
- `docs/RELEASE_NOTES_DEV.md` — `[dev-2026-06-19-182557]` (LFPLAN.3 plan execution), `[dev-2026-06-19-171552]` (re-enable + BUG-042 resolved), `[dev-2026-06-19-153439]` (recalibration).
- `docs/ENGINEERING_PLAN.md` §Phase CLEAN — the `LFPLAN.1/.2/.3` bullet (top of the CLEAN list).
- Memory `project_clean_audit_2026_06_13.md` — the four-layer narrative + the LFPLAN.4/.5 diagnosis + fix sketches (the most detailed running record).
- Session artifact: `~/Documents/phosphene_sessions/2026-06-19T19-21-39Z/` — `session.log` (the `preset →` burst), `features.csv` (section cols), `raw_tap.wav` (the real audio).

## Constraints / guardrails

- **The 2026-05-28 cycling/lockup is the failure mode to avoid.** The LFPLAN.4 dwell IS the guard against reintroducing it. If a live test ever shows rapid cycling or a Next-button lockup, that's the regression — back out, don't push through.
- App behaviour can't be unit-validated (`VisualizerEngine` isn't constructible in the app-test sandbox); the gate is Matt's live session. Land "code-complete, pending Matt's live validation."
- Closeout per CLAUDE.md: `Scripts/closeout_evidence.sh` block (engine + app build + lint + doc), docs (KNOWN_ISSUES is closed for BUG-042 — update EP + RELEASE_NOTES under LFPLAN), commit with `[LFPLAN.4]` / `[LFPLAN.5]` ids.
- **Nothing is pushed** — 17 commits sit on local `main`. Pushing needs Matt's explicit "yes, push."

## Suggested opening prompt for the fresh session

> Start LFPLAN.4 (per `docs/prompts/LFPLAN_KICKOFF.md`): add a min-dwell + cold-start gate to plan-execution so local-file planned sessions stop cycling presets at track start. Read the brief's "Read first" surfaces, confirm the diagnosis against the `2026-06-19T19-21-39Z` session, then implement from the PRIMARY checkout and land code-complete pending my live test.
