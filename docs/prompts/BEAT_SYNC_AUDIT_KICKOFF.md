# Beat-Sync Audit Kickoff — BUG-017 broader scope (2026-05-24)

Hand this to a new Claude Code session verbatim. Do not summarise it.

## Read these first, before doing anything else

1. `docs/QUALITY/KNOWN_ISSUES.md` → **BUG-017** — read every addendum in order, including the trailing 2026-05-24 revert addendum. This is the load-bearing reference for what's known and what's been tried.
2. `docs/RELEASE_NOTES_DEV.md` → `[dev-2026-05-22-a]`, `[dev-2026-05-22-b]`, `[dev-2026-05-22-c]`, `[dev-2026-05-24-a]` — the chronological narrative of CS.1 → CS.1.y.2-redo → revert.
3. `docs/ENGINEERING_PLAN.md` → Phase CS / Increment CS.1.y (current state) and Phase CA — Capability Audit (the methodology pattern this audit follows).
4. `docs/COLD_START_SYNC_DESIGN_2026-05-20.md` — original design + adversarial review.
5. `CLAUDE.md` — the whole file. Particularly:
   - The **Defect Handling Protocol** — this audit is the Diagnosis stage of a P1 defect, not the Fix stage.
   - The **Authoring Discipline** section — "design is upstream," the **Grounding priority** soft-rule, "diagnostic infrastructure precedes fidelity claims," "stop and report."
   - **Failed Approach #68** — sub-bass onset detector is not a beat-phase reference. The audit must check whether this root cause has been adequately retired in *all* places it was used, or whether it's still seeding prep-time `gridOnsetOffsetMs`.
   - **Failed Approach #58** — the Drift Motes pattern. Five fix increments on the same defect without convergence is what got us here.
6. The code, end to end:
   - `PhospheneEngine/Sources/DSP/LiveBeatDriftTracker.swift` — drift EMA, lock state machine, `setGrid(_:initialDriftMs:)`, `applyCalibration`.
   - `PhospheneEngine/Sources/DSP/BeatGrid.swift` — `offsetBy`, `halvingOctaveCorrected`, `nearestBeat`, `localTiming`.
   - `PhospheneEngine/Sources/Session/GridOnsetCalibrator.swift` — the prep-time onset-based calibrator that is **still in production** at prep time (only its runtime use was reworked and then reverted).
   - `PhospheneApp/VisualizerEngine+Stems.swift` — the cold-start grid-install path (`cached.beatGrid.offsetBy(0)`, `cached.gridOnsetOffsetMs`).
   - `PhospheneEngine/Sources/DSP/MIRPipeline.swift` — `setBeatGrid`, `liveDriftTracker.update(...)` call site.
   - `PhospheneEngine/Sources/ColdStartVerifier/` — the entire verifier (especially `ColdStartAnalysis.swift` for the clock-offset path and `BeatThisGrid.swift` for the reference measurement).
   - `PhospheneEngine/Sources/DSP/BeatDetector*.swift` — the sub-bass onset detector and tempo/grid resolver.

## What's known on entry (2026-05-24)

Five fix increments on cold-start beat sync (CS.1 → CS.1.y.1 → CS.1.y.2 → CS.1.y.2-redo redo.1 → redo.2 → redo.3 rounds 1-2) have not produced perceptual convergence. The CS.1.y.2-redo fix was reverted 2026-05-24 after three validation captures (2026-05-23T02-17-24Z, 2026-05-23T02-39-54Z, 2026-05-24T15-07-31Z) showed:

- **Cross-capture non-reproducibility on multiple tracks.** Same cached grids, snap values varying ≥ 100 ms between captures (Billie Jean −6/+79; SNA +88/−160; Get Lucky −109/−7; Everlong +44/−116; Superstition −181/+63).
- **The pre-fix "approx now" baseline itself degraded** between CS.1 and capture 3 — 3/10 PASS → 1/10 PASS on identical cached grids. Either `gridOnsetOffsetMs` is non-deterministic across preps, the verifier's clock-offset is noise-coupled, or there's a regression elsewhere.
- **EMA drift bouncing 200-300 ms within single steady-state tracks.** HUMBLE only 43 % locked post-snap.
- **Matt's M7 (SpectralCartograph diagnostic):** "drift very much real across tracks"; "rarely snaps to the beat and does not follow downbeat."

Matt's framing of the broader symptom: **"beat-sync infrastructure is not perceptually aligned across the catalog."** This is bigger than BUG-017's original scope (preview-clip vs track phase offset). The audit's job is to characterise the *whole* beat-sync surface and find what's actually broken — not to start fixing.

## The task — Beat-Sync Audit

This is the Diagnosis stage of a P1 multi-increment defect, following the Phase CA / DSP audit methodology pattern. **No fix code in this increment.** The audit's deliverable is a per-component verdict document with empirical grounding, plus ranked root-cause hypotheses for follow-up fix increments.

### Scope (the beat-sync wiring, in dependency order)

1. **Prep-time grid + onset-offset seeding.** `BeatGridResolver` (Beat This! offline on the 30 s preview), `GridOnsetCalibrator` (sub-bass onset detector vs prep-time grid → `gridOnsetOffsetMs`). The calibrator was reworked-then-reverted for runtime use but is **still in production at prep time** — its onset-based measurement is Failed Approach #68 still live in the system.
2. **Cold-start grid install.** `VisualizerEngine+Stems.swift:resetStemPipeline` → `mirPipeline.setBeatGrid(cached.beatGrid.offsetBy(0), initialDriftMs: cached.gridOnsetOffsetMs)`. The `offsetBy(0)` treats preview-clip timeline as track timeline (this is what BUG-017 originally identified).
3. **Live drift EMA.** `LiveBeatDriftTracker.update(...)` — matches sub-bass onsets to nearest cached beats within ±50 ms, EMA-updates drift toward `nearestBeat − pt`. The lock state machine (BUG-007.x), the adaptive tight gate (BUG-007.5), the auto-rotate bar-phase logic (BUG-007.4b/c).
4. **Live drift behaviour under a wrong-phase grid.** When the cached grid is off by ½-beat, onsets within ±50 ms of the wrong-phase grid are *off-beat* onsets the EMA may track. Same shape as Failed Approach #68 at a different scope.
5. **Verifier clock-offset estimation.** `ColdStartAnalysis.resolveAudibleBeats` uses sub-bass onsets to pin the raw-tap ↔ playback-time offset. The verifier is the only automated ground truth for "is the visual on the beat," but its clock-offset estimate uses the same noisy sub-bass signal — capacity for the verifier itself to drift between captures.
6. **`BeatDetector` sub-bass onset feed.** Producer for both `LiveBeatDriftTracker` and the verifier's clock-offset estimator. Per-track onset stability across captures.

### Methodology (Phase CA pattern)

For each capability in scope:

1. **Read the code end to end.** Document what it actually does, vs what its doc comment says it does, vs what the surrounding code assumes it does.
2. **Verdict per capability** — one of: `production-active`, `production-active-but-broken`, `documented-but-broken`, `unverified-claim`, `correct`.
3. **Empirical grounding per verdict.** Run measurements against the three existing reference captures (`2026-05-22T16-57-36Z`, `2026-05-22T19-03-59Z`, `2026-05-23T02-39-54Z`, `2026-05-24T15-07-31Z` — the last three already have raw_tap.wav and features.csv). Where measurements aren't possible from existing artifacts, document the gap as a needed instrument-and-recapture step.
4. **Ranked root-cause hypotheses** at the end — for each of the empirical observations (cross-capture non-reproducibility, EMA bouncing, baseline degradation), list candidate causes with the evidence that supports/contradicts each, ranked by likelihood given the data.
5. **Per-component fix scope estimates** — for each component that's broken, a one-paragraph sketch of what a fix would touch and an honest risk estimate.

### Specific empirical questions to answer

The audit must address each of these from artifact evidence (or document the gap):

- **`gridOnsetOffsetMs` reproducibility across preps.** Is the prep-time onset-offset seed deterministic given the same preview audio? Re-run prep on the existing fixtures and compare. Failed Approach #68 says onset-based phase isn't a reliable signal — does the prep-time use of it produce values stable enough to be load-bearing?
- **Why did approx-now baseline drift from CS.1's 3/10 PASS to capture-3's 1/10 PASS?** Same cached grids by construction. Either preps re-ran (with different `gridOnsetOffsetMs`), the verifier's clock-offset estimate is per-capture noisy, or there's a regression. Evidence from features.csv frame-1 drift columns and session.log BeatGrid install lines.
- **EMA behaviour under a wrong-phase grid.** Inject a synthetic ½-beat-off cached grid into the tracker with realistic onset streams (replay from a tap capture); measure where the EMA converges. Does it lock to the off-beat onsets within ±50 ms of the wrong-phase grid, or stay near the seed?
- **Cross-capture Beat This!@15s reproducibility on a single track.** redo.1 measured 15s-vs-25s same-slice. Now measure: 15 s from capture A's tap vs 15 s from capture B's tap on the same song. How big are the differences? On which tracks? Is it correlated with track properties (BPM, syncopation, intro quietness)?
- **Verifier clock-offset sensitivity.** If the verifier's clock-offset estimate uses sub-bass onsets, how stable is it across captures? Independently measure clock offset by raw-tap-start timestamp (the precise one added in CS.1) and compare.
- **`BeatDetector.onsets[0]` (sub-bass) reliability per track.** For each reference track, how often does the sub-bass onset detector fire on the beat vs off-beat (per Failed Approach #68)? Use full-window Beat This! beats as the audible reference; measure the per-onset distance distribution.

### Stop-and-report criteria for the audit

- If reading the code reveals the audit needs to grow beyond the six components listed in §Scope, stop and report — get scope approval before expanding.
- If empirical measurement requires new captures or new instrumentation, surface the request rather than write fix code.
- If a clear root-cause hypothesis emerges with strong evidence early in the audit, document it but **complete the audit** — Failed Approach #58 says don't optimise for a single hypothesis when the symptom may be compound.
- If the verdicts come out "everything looks fine" but the symptom persists, the audit's job is to surface that anomaly clearly — not to claim closure.

### Deliverable

A new document: `docs/CAPABILITY_REGISTRY/BEAT_SYNC.md` (or similar — choose what fits the existing pattern). Plus updates to:
- `docs/QUALITY/KNOWN_ISSUES.md` — refine BUG-017's symptom statement based on findings; file follow-up bugs for specific root causes if the audit isolates them.
- `docs/ENGINEERING_PLAN.md` — Phase CS / CS.1.y updated to point at the audit document; new increment IDs scoped (one per fix the audit recommends).
- `docs/RELEASE_NOTES_DEV.md` — entry describing the audit's findings.

### Done-when

- Per-component verdicts published with empirical grounding.
- Each of the six specific empirical questions in §Specific empirical questions either answered or surfaced as a gap requiring new captures.
- Ranked root-cause hypotheses table.
- Per-component fix scope sketches.
- Matt sign-off on which root causes to address next (and in what order).

### Hard rules

- **No fix code in this audit increment.** Audit-only. Surface every root-cause candidate before committing to any of them. Failed Approach #58 — five fix increments without convergence is the warning. The remediation isn't a sixth fix; it's understanding what's actually wrong.
- **Empirical grounding per verdict.** No "this looks right" without a measurement. CLAUDE.md "diagnostic infrastructure precedes fidelity claims" applies — extend it from preset fidelity to system fidelity.
- **Verify Matt's current intent before trusting any "what stays unchanged" claim** in the codebase or in prior planning docs. The CS.1.y.2-redo cycle had multiple instances of "we assumed X, the measurement covered case Y." Check assumptions against measurement.
- **Stop and report when scope expands.** The audit's six-component scope is the boundary. If the wiring touches outside it, surface the expansion before pursuing it.
- **Commit format** `[BSAudit.N] <component>: <description>` where N is a sub-increment number; small commits; **do not push without Matt's explicit "yes, push."**

## Status on entry

- Branch `main`. ~21 commits ahead of `origin` (unpushed).
- CS.1.y.2-redo (engine + app) reverted; the diagnostic tooling (`ColdStartVerifier --rediagnose-windows` + `--window-start-s`) stays in tree.
- Engine suite: 1265 / 1265 pass (back to pre-redo.2 baseline).
- BUG-017: Open with broader scope per the 2026-05-24 revert addendum.
- Pre-existing uncommitted out-of-scope items in the tree (leave alone unless Matt asks): `PhospheneApp.xcscheme`, `default.profraw`, `docs/CS_1_Y_KICKOFF.md` → `docs/prompts/CS_1_Y_KICKOFF.md` move.
- Reference captures available:
  - `~/Documents/phosphene_sessions/2026-05-22T16-57-36Z/` — CS.1 baseline, full raw_tap.wav.
  - `~/Documents/phosphene_sessions/2026-05-22T19-03-59Z/` — CS.1.y onset-fix attempt.
  - `~/Documents/phosphene_sessions/2026-05-23T02-39-54Z/` — CS.1.y.2-redo round 2 (extrapolation fixed).
  - `~/Documents/phosphene_sessions/2026-05-24T15-07-31Z/` — round 3 / Matt's M7, SpectralCartograph diagnostic. The capture Matt called the broader concern on.

If you find this prompt is wrong or stale, update it before working against it.

— Matt + Claude (2026-05-24, post-revert)
