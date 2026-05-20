# Phase CS Kickoff — Cold-Start Sync (2026-05-20)

**Hand this to a new Claude Code session verbatim. Do not summarise it.**

---

## Read these first, before doing anything else

1. **`CLAUDE.md`** — the entire file. Particularly the Audio Data Hierarchy section, the D-019 / D-026 rules, the Authoring Discipline section, and the Defect Handling Protocol. **All work in this phase is governed by those rules.**
2. **`docs/COLD_START_SYNC_DESIGN_2026-05-20.md`** — the full design + adversarial review for this phase. §4 (existing infrastructure), §5 (unverified claims), §6 (risks) are mandatory reading. The design document is the load-bearing context for every CS increment.
3. **`docs/ENGINEERING_PLAN.md` — section "Phase CS — Cold-Start Sync (2026-05-20)"** — the increment-level roadmap.

If you finish reading those three sources and the work doesn't make sense, stop and ask Matt. Do not improvise.

## Why Phase CS exists

Phosphene's product viability depends on delivering visually-synced visuals from frame 1 of every track. Matt's bar (2026-05-20):

> The product should be at least beat-synced from frame 1, having 1s of wonky performance while the transition occurs is acceptable but this should be the only session wonkiness. The standard is pretty high.

The 2026-05-20 design conversation surfaced that **most of the cold-start beat-sync infrastructure already exists in production code** (BUG-007.x series), but **has never been empirically verified to meet the bar**. The design document is the result of stepping back, reading the actual code, and producing an honest assessment of what exists, what's unverified, and what additional work is needed.

The phase is structured to:

1. **Verify the existing infrastructure works** before adding to it (CS.1).
2. **Close one specific orchestrator gap** that allows the cold-start window to be undermined by short first segments (CS.2).
3. **Audit the preset catalog for data-hierarchy compliance** that cold-start sync depends on (CS.3).
4. **Fix any violations** the audit surfaces (CS.4, scope variable).
5. **Document the contract** so it doesn't drift (CS.5).

Final close is Matt's manual M7 validation on a real listening-party playlist.

## Hard rules for this phase

Lifted from CLAUDE.md and the design document's anti-patterns section:

- **No new architecture before measurement.** CS.1 measures. Do not skip it. Do not propose new infrastructure based on a hypothesis the verification has not yet confirmed.
- **No claim without evidence.** "The infrastructure exists therefore it works" is a hypothesis. The measurement is the test. Closeout reports must cite the measurement, not the hypothesis. (See CLAUDE.md "Diagnostic infrastructure precedes fidelity claims".)
- **Audit precedes fix.** CS.3 produces findings. CS.4 scope follows from findings. Do not start CS.4 before CS.3 has published the audit document.
- **Preset-touching work is high-risk.** Matt's documented assessment: "B or C will be botched by you because you won't be able to achieve the level of visual fidelity needed. I have literally watched this happen for the last several preset designs." CS.4 sub-increments must be tightly scoped (one preset, minimum change, M7 review). If a CS.4 sub-increment starts to grow scope, stop and escalate.
- **Stop and report instead of forging ahead** when (CLAUDE.md): tests fail; preset acceptance gates fail; documentation conflicts with code that just changed; the commit would include unrelated files; the increment would require broader architectural changes than authorized.
- **Commit messages: `[CS.X] component: description`.** Multiple small commits per increment preferred over one large commit. Push only with Matt's explicit approval.

## How to start: CS.1

CS.1 is empirical verification. The design document §6 documents risks ranging from "almost certainly fine" to "could break the bar entirely." Without measurement we cannot tell where the actual production behavior sits.

### CS.1 step-by-step

1. **Read all three references** at the top of this prompt. Confirm understanding of:
   - The Cold-Start Phase Contract (existing infrastructure: `BeatGrid.offsetBy`, `GridOnsetCalibrator`, `setGrid(_:initialDriftMs:)`, BUG-007.9 hybrid recalibration, D-019 stem warmup blend).
   - The defect handling protocol — even though CS.1 is not strictly a defect-fix, the protocol's discipline applies.
   - The list of risks in design document §6 — these are what the measurement should be designed to surface.

2. **Decide where the verification harness should live.** The existing `PresetSessionReplay` target from SR.1 is the strongest candidate base — it already parses `features.csv` and `stems.csv` and emits Markdown evidence packs. The design document §7.1 explicitly suggests extending it. Alternative: a new sibling target. Justify the choice in the increment scope before writing code.

3. **Identify the ground-truth signal.** The hard question is: what counts as "audible beat time" for the verification? Options:
   - **Re-run `BeatDetector` on the captured tap audio offline.** Produces sub-bass onset timestamps that should align with the audible beats. Per-track distribution of `(visual_beat_time − sub_bass_onset_time)` is the measurement.
   - **Re-run Beat This! on the captured tap audio offline.** Produces a full beat grid; per-track distribution of `(visual_beat_time − beat_this_beat_time)` is the measurement.
   - **Both, and report agreement.** Highest evidence quality.
   - Pick one (or both) and document the choice.

4. **Define the per-track verdict.** Suggested from design document §3:
   - `pass`: ≥ X % of beats in the first 10 s within ±50 ms of the chosen ground truth.
   - `fail`: < X % of beats meet the bar.
   - `degenerate`: rhythmless track — bar does not apply; mark and skip.

   Choose X (e.g. 90 %) and the window thresholds (±50 ms baseline; ±30 ms aspirational); document the rationale.

5. **Run against a real session.** Matt will provide a captured Spotify-prepared session directory (likely under `~/Documents/phosphene_sessions/<timestamp>/`). Don't fabricate test data. Real-session evidence is the only evidence that matters.

6. **Report per-track and aggregate verdicts.** Suggested deliverable:
   - Markdown report appended to (or sibling to) the SR.1 evidence pack.
   - Per-track row: `(track title, BPM, gridOnsetOffsetMs prep, gridOnsetOffsetMs runtime, frame-1-phase-delta-ms, first-10s-pass-rate, verdict)`.
   - Aggregate: percentage of tracks meeting bar.
   - Failure-case dive: for any track that fails, dump the per-beat delta timeline and a short narrative.

7. **Closeout decision.**
   - If pass-rate ≥ 90 %: CS.1 closes; proceed to CS.2.
   - If pass-rate < 90 %: CS.1 surfaces the failure cases. Do **not** propose fixes in the CS.1 commit; that's a follow-up increment (`CS.1.x`) whose scope depends on what the failures look like. Report and stop.

8. **Per CLAUDE.md increment closeout protocol**, produce a closeout report covering: files changed, tests run, harness output, doc updates, plan updates, known risks. Cite the actual verification output, not claims about it.

## How to start: CS.2 (only after CS.1 passes or its failure mode is resolved)

CS.2 is small and well-scoped — a first-segment minimum duration constraint in `SessionPlanner.planOneSegment`. The design document §6.5 covers the risk surface.

Key questions to answer before writing code:

1. What is the exact threshold (10 s? 12 s? 15 s?)? Lean toward 10 s — the live stem analyzer's warmup is ~10 s per Increment 3.5.4.9.
2. How are tracks shorter than the threshold handled? (Allow violation; first segment is the full track.)
3. How are section boundaries inside the threshold handled? (Push to next bar boundary at-or-after threshold; the existing bar-aligned transition logic in `TransitionPolicy` is the model.)
4. Are there interactions with `wait_for_completion_event` presets (Arachne)? These bypass `maxDuration` already — does CS.2's first-segment minimum interact cleanly?

Then implement, regenerate golden sessions, document the score-decision changes in the commit message and inline test comments.

## How to start: CS.3 (after CS.2 lands)

CS.3 is the catalog audit. The output is a document, not code.

Per-preset checklist for the audit (design document §6.4):

1. Open the preset's `.metal` file.
2. Locate every audio-reactive driver — every read of `f.X`, `stems.X`, `features.X`, etc.
3. For each driver, classify:
   - **Primary motion** = the driver causes visible motion users will notice frame-to-frame.
   - **Accent** = the driver causes brief response on top of primary motion.
   - **Proxy fallback** = the driver provides cold-start value via D-019 blend.
4. Check compliance against:
   - Audio Data Hierarchy: continuous primary, stems accent.
   - D-019: stem reads have warmup blend OR have explicit FeatureVector proxy fallback.
   - D-026: no absolute thresholds on raw AGC-normalised values.
5. Verdict per preset: `compliant` / `non-compliant` / `borderline (needs M7 judgement)`.

Output file: `docs/PRESET_DATA_HIERARCHY_AUDIT_2026-05-XX.md` matching the structure of existing audit / design docs in `docs/`.

CS.3 does not modify code. The fix work is CS.4.

## How to start: CS.4 (after CS.3 publishes)

CS.4 is preset-touching work — the highest-risk category. **Read the Authoring Discipline section of CLAUDE.md before scoping any CS.4 sub-increment.** Then per non-compliant preset:

1. Read the existing `.metal` file end to end.
2. Read the relevant `docs/VISUAL_REFERENCES/<preset>/` directory and its README (CLAUDE.md Failed Approach #63).
3. Scope the minimum change to bring the preset into compliance without altering visual intent.
4. Surface the scope to Matt before authoring. Get explicit approval to proceed.
5. Implement; regenerate goldens; M7 review per CLAUDE.md.

If the minimum change is not minimum — if implementing compliance requires a substantial visual character change — stop and report. The right answer in that case may be to retire the preset (D-102 precedent: Drift Motes was retired rather than tuned).

## How to start: CS.5

CS.5 promotes the cold-start contract into durable docs. Specifically:

1. Add a new section to CLAUDE.md (under "Audio Data Hierarchy") titled "Cold-Start Phase Contract." Three paragraphs:
   - What's calibrated and seeded at track install (`gridOnsetOffsetMs`).
   - What's expected of presets during the cold-start window (D-019 blend; no stem-primary motion without proxy).
   - What's expected of the orchestrator (first-segment minimum duration).

2. Add a short cross-reference in SHADER_CRAFT.md pointing authors at the CS.3 audit checklist.

3. File a new decision record `D-128 — Cold-start sync architecture (Phase CS, 2026-05-XX)` documenting what was verified, what was added.

## Failure modes to watch for in this phase specifically

Promoted from CLAUDE.md and prior session learnings:

- **Forging ahead past a failed measurement.** If CS.1 surfaces failures and you skip to CS.2 anyway, the phase is broken. Stop and report at every gate.
- **Hand-waving about code paths you haven't read.** This is the failure mode that produced the original superficial pass on 2026-05-20. Cite line numbers; verify claims against the actual code.
- **Bundling unrelated work into a CS.X increment.** Out of scope per the design document: BUG-013, audio output latency UX, section-aware visuals, mood arc, full-track audio access.
- **Pretending Matt's M7 review can be skipped.** The phase's exit criterion is Matt's perceptual validation on a real listening-party playlist. Automated measurement passing is necessary but not sufficient.
- **Generating structure as a substitute for substance.** If a section of a closeout report has more headers than findings, the work isn't done. The Authoring Discipline rule applies.

## Status on entry (2026-05-20)

- Branch: `main`. 5 commits ahead of `origin/main`.
- Local `main` includes the BUG-012 instrumentation increment (commits `94a55a29`, `a57c79fa`, `23bbb825`).
- Working tree is clean except for `default.profraw` (build artifact). Aurora Veil carry-over from prior session has been stashed (`stash@{0}` titled "AV.2.h.1 carry-over").
- No CS-phase code has landed. This is the kickoff.

## Sign-off

This prompt is the canonical entry point for Phase CS work. If you find the prompt is wrong or stale, **update the prompt** before doing the work — do not work against a prompt you know is wrong.

The design document and engineering plan entry are the load-bearing references. The prompt is just the orientation map.

— Matt + Claude (2026-05-20 design session)
