# BSAudit.3.validate Kickoff — Validating the BPM-Anchored Phase Acquisition (2026-05-25)

Hand this to a new Claude Code session verbatim. Do not summarise it.

## Read these first, before doing anything else

1. **[`docs/BPM_ANCHORED_PHASE_ACQUISITION_DESIGN_2026-05-24.md`](../BPM_ANCHORED_PHASE_ACQUISITION_DESIGN_2026-05-24.md)** — the design that BSAudit.3.impl just shipped. Read §8 (verifier extension), §12 (verification criteria), §6.5 (`accentConfidence` gating), §9.x (open empirical questions to answer in validation).
2. **[`docs/CAPABILITY_REGISTRY/BEAT_SYNC.md`](../CAPABILITY_REGISTRY/BEAT_SYNC.md)** — the BSAudit deliverable + BSAudit.2 Path A falsification addendum. The empirical basis for why the design is what it is. The **§Component 5b finding** (Beat This!-on-tap is per-capture-stable but cross-capture-unstable) is load-bearing for the verifier scope below: this validate increment scores **within-capture** only, never cross-capture.
3. **[`docs/QUALITY/KNOWN_ISSUES.md`](../QUALITY/KNOWN_ISSUES.md)** → **BUG-017**, every addendum through 2026-05-24. Read in order. This is the historical chain. BSAudit.3.impl is the fix; this increment is the validation step before resolution.
4. **[`docs/RELEASE_NOTES_DEV.md`](../RELEASE_NOTES_DEV.md)** → `[dev-2026-05-24-a]`, `[dev-2026-05-24-b]`, `[dev-2026-05-24-c]` — the chronological narrative. BSAudit.3.impl closeout adds the next entry (`[dev-2026-05-XX]`) at the end of this increment.
5. **[`docs/prompts/BSAUDIT_3_IMPL_KICKOFF.md`](BSAUDIT_3_IMPL_KICKOFF.md)** — the impl kickoff that just shipped. The "What's settled on entry" section there tells you what now exists in the tree.
6. **[`CLAUDE.md`](../../CLAUDE.md)** — the whole file. Particularly:
   - **Defect Handling Protocol** → "Validation" stage. This increment is that stage of P1 BUG-017.
   - **Authoring Discipline** — "diagnostic infrastructure precedes fidelity claims" is the rule that drives sub-commit 1 of this kickoff (add `accent_confidence` to features.csv and the verifier mode *before* claiming the architecture works).
   - **Failed Approach #58** — Drift Motes pattern (five failed iterations on the same defect). This increment's M7 verdict is what stops or extends the chain. If M7 fails, **stop and report** — do not file a sixth fix without surfacing the gap first.
   - **Failed Approach #68** — sub-bass onsets are not a beat-phase reference. The verifier metric should NOT score against sub-bass-onset alignment.
7. The code, end to end (focal points for this increment):
   - `PhospheneEngine/Sources/ColdStartVerifier/` — the harness that will gain `--accent-window-pass-rate`. Pattern after the existing `--rediagnose` / `--position-sweep` / `--cross-capture` modes (each is one new file + one CLI flag).
   - `PhospheneEngine/Sources/Shared/SessionRecorder+CSV.swift` + `SessionRecorder.swift:325-335` (CSV header) — extend the schema with an `accent_confidence` column.
   - `PhospheneEngine/Sources/Shared/AudioFeatures+Analyzed.swift` `FeatureVector` — the new `accentConfidence` field is already there (BSAudit.3.impl.3); the validate increment surfaces it in the CSV.
   - `PhospheneEngine/Sources/DSP/LiveBeatDriftTracker.swift` — `currentAccentConfidence` is already exposed; just propagate it through the CSV writing path.
   - `PhospheneEngine/Sources/ColdStartVerifier/ColdStartAnalysis.swift` + `BeatThisGrid.swift` — the existing within-capture Beat This! audible-beat reference. Verifier reuses it.

## What's settled on entry (2026-05-25)

- **BSAudit.3.impl is shipped on `main`** (3 commits: `efaf8cb4`, `13d0f456`, `30d032ea`). The BPM-prior architecture is the production runtime. `GridOnsetCalibrator` is deleted. `MIRPipeline.installBPMPrior(bpm:character:beatsPerBar:)` is the install entry point.
- **`accentConfidence` is already populated** in the `FeatureVector` per frame by `MIRPipeline.buildFeatureVector` (design §6.5). The `beatBass` / `beatMid` / `beatTreble` / `beatComposite` accent fields are already multiplied by it before write.
- **Engine + app suites + lint + `--self-test` are all green** at HEAD. 1252 engine tests; 333 app tests; 0 swiftlint violations; 7/7 self-test.
- **The 4 reference captures predate BSAudit.3.impl.** They show the OLD (pre-fix) behavior. They are useful as a *historical baseline* for the new verifier mode — not as evidence that BSAudit.3.impl works.
- **A fresh capture from Matt is required** to evaluate the new architecture. The verifier metric is necessary but not sufficient; **M7 is the load-bearing close criterion** per CLAUDE.md "Defect Handling Protocol" + design §12.
- **Path A is closed.** Beat This!-on-tap is *per-capture-stable* (within one capture, slice-position-invariant when run on the canonical 25 s window — BeatThisGrid does this) but *cross-capture-unstable* (BSAudit.2 finding). The validate metric scores **within-capture** only — comparing the same-capture features.csv accents vs the same-capture raw_tap.wav Beat This! grid. Cross-capture comparisons are out of scope.

## The task — BSAudit.3.validate

This is the **Validation** stage of P1 BUG-017 per CLAUDE.md's Defect Handling Protocol. Multi-step process; design + impl already done. **Ships in three sub-commits**, with engine + lint + tests green at each step.

### Sub-commit 1 — Diagnostic instrumentation (BSAudit.3.validate.1)

**Goal:** add `accent_confidence` to the CSV schema; add `--accent-window-pass-rate` to `ColdStartVerifier`; verify both with `--self-test`. No closeout claims yet.

Per CLAUDE.md "diagnostic infrastructure precedes fidelity claims" — the verifier itself, and its inputs (the CSV column), must exist and self-test before any claim that the architecture works.

- **CSV schema extension.** Append `accent_confidence` to `features.csv` per the append-only invariant in `SessionRecorder.swift:319-335` ("Existing columns stay in their existing positions so positional parsers keep working. New columns go at the end."). Source: `fv.accentConfidence` written by `MIRPipeline.buildFeatureVector`. Update `SessionRecorder+CSV.swift` `csvRow(features:...)` to append the new column, and update both header constants.
- **Verifier mode.** New `--accent-window-pass-rate` flag on `ColdStartVerifierCommand`. New file `PhospheneEngine/Sources/ColdStartVerifier/AccentWindowPassRate.swift` (sibling to `ReDiagnosis.swift`, `PositionSweep.swift`, etc.) implementing the per-track scoring:
  1. For each track segment in the session, slice the first `--first-window-s` (default 10 s) of features.csv frames.
  2. Use BeatThisGrid.beats from raw_tap.wav as the audible-beat ground truth (within-capture stable — Path A finding).
  3. For each audible beat at time `t_beat` in the window, scan the CSV rows whose `playback_time_s ∈ [t_beat − accept_ms, t_beat + accept_ms]` (default `accept_ms = 60`). Per design §6.5, the accent fired if `beatComposite > accent_threshold` (default 0.3) on any row in that window — the gating multiplies `beatComposite` by `accentConfidence`, so a rising edge above threshold means *both* the underlying onset fired AND confidence was high enough to pass it through.
  4. Per-track pass rate = `accent_hits / audible_beat_count`.
  5. **Per-track verdict** (design §12):
     - **PASS-firing** if `pass_rate ≥ 0.80` (default `--per-track-pass-rate 0.80`).
     - **PASS-degraded** if max `accent_confidence` across the window stayed below `--degraded-conf-threshold` (default 0.3) AND no `beatComposite > 0.3` row fired — i.e., the system never claimed sync, and didn't accent-pulse wrong. Graceful degradation per design §6.6.
     - **FAIL** otherwise — system claimed sync but missed.
- **Report.** Markdown table per track: `audible_beats`, `accent_hits`, `pass_rate`, `max_confidence`, `verdict`. Aggregate: `% PASS-firing`, `% PASS-degraded`, `% FAIL`. Write to `<session>/cold_start_accent_window.md` (mirror `cold_start_report.md` pattern). The aggregate gate per design §12 + §4: ≥ 90 % of catalog reaches PASS-firing OR PASS-degraded.
- **Self-test.** Extend `SelfTest.swift` with a synthetic-input case: a CSV with 4 audible beats at known timestamps, accent rows at 3 of them (one missed by > 60 ms), and an accentConfidence ramp from 0 → 1. Expected verdict: 3/4 = 75 % → FAIL (under the 80 % threshold). A second case with accentConfidence stuck at 0.1 and no accents firing should return PASS-degraded.
- **No production code path changes.** This sub-commit is verifier + CSV only. Production runtime behaviour unchanged.

**Done-when:** engine suite passes (1252 baseline + new self-test cases — at least 2 new tests, document the delta); `swiftlint --strict` 0 violations project-wide; app build clean; `ColdStartVerifier --self-test` PASS (9/9 or however many checks now exist).

**Commit:** `[BSAudit.3.validate.1] Verifier: accent_confidence in features.csv + --accent-window-pass-rate mode`

### Sub-commit 2 — Historical baseline against the 4 reference captures (BSAudit.3.validate.2)

**Goal:** run `--accent-window-pass-rate` against the 4 pre-BSAudit.3.impl reference captures and document the results. These captures predate the fix, so the report tells us **how the OLD architecture performed under the new metric** — useful as a before-snapshot. They cannot validate that the impl works.

- Run the new mode against each of:
  - `2026-05-22T16-57-36Z/` — CS.1 baseline.
  - `2026-05-22T19-03-59Z/` — CS.1.y.2 onset-fix attempt (since reverted).
  - `2026-05-23T02-39-54Z/` — CS.1.y.2-redo round 2 (since reverted).
  - `2026-05-24T15-07-31Z/` — M7 capture (CS.1.y.2-redo, since reverted).
- For each capture, the `features.csv` does **not** contain an `accent_confidence` column (it predates the schema extension). The verifier mode should treat missing column as `accent_confidence = 1.0` (no gating in effect — the raw `beatComposite` field is what the architecture wrote, so the rising-edge check still tells us "did an accent fire" for that build).
- Write a short markdown file `docs/diagnostics/BSAUDIT_3_HISTORICAL_BASELINE_2026-05-XX.md` (the dev-tree diagnostics drawer — sibling to existing per-session reports) summarising: per-capture per-track verdicts; aggregate pass-rates; comparison across captures. This is the empirical "before" snapshot.
- No production code path changes. No closeout claims about BUG-017.

**Done-when:** the 4 reports exist in their session directories (`cold_start_accent_window.md` in each); the summary doc cross-references them; engine + lint + tests still green (no code changes from sub-commit 1).

**Commit:** `[BSAudit.3.validate.2] Historical baseline: --accent-window-pass-rate against 4 pre-impl reference captures`

### Sub-commit 3 — Fresh capture + M7 + closeout (BSAudit.3.validate.3)

**Goal:** the load-bearing validation. Surface to Matt for a fresh capture against the BSAudit.3.impl build; run the verifier; conduct M7 listening review; close BUG-017 on M7 PASS.

This sub-commit cannot complete autonomously — it requires Matt's action twice (capture + M7). The agent does the parts that can be automated; **stops and surfaces to Matt** at the human-loop points.

1. **Surface to Matt** with a brief summary of where validate.1 + validate.2 left things. Request:
   - Fresh build of the app at HEAD (BSAudit.3.impl is in tree).
   - Capture a session with `PHOSPHENE_FULL_RAW_TAP=1` against the 10-track reference playlist. The same playlist Matt used for the BSAudit reference captures so cross-build comparison is apples-to-apples.
   - Save the capture under `~/Documents/phosphene_sessions/<timestamp>/`. Communicate the timestamp back.
2. **Run the verifier** against the fresh capture:
   - `ColdStartVerifier --session <fresh-capture> --accent-window-pass-rate`.
   - Also run the legacy `--first-window-s 10` mode for cross-reference (it's still informative even though the metric has changed).
   - Embed the resulting `cold_start_accent_window.md` numbers in the validate.3 closeout writeup.
3. **M7 listening review on Matt's hardware.** Matt watches the capture playback (or a fresh live session on the BSAudit.3.impl build) and surfaces the perceptual verdict. **M7 is the load-bearing close criterion** — per CLAUDE.md "Defect Handling Protocol" + design §12 + design §10. Possible outcomes:
   - **M7 PASS.** Visual reads as credibly synced from frame 1 with the soft-ramp warmup. Proceed to closeout.
   - **M7 PARTIAL.** Some tracks read credibly, others surface a perceptual gap not captured by the automated metric. Stop and report — do not file a sixth iteration without surfacing the gap to Matt (Failed Approach #58 + design §13 anti-pattern #4).
   - **M7 FAIL.** Stop entirely. Surface to Matt. Open a follow-up audit increment if needed.
4. **On M7 PASS — closeout** (and only then):
   - `docs/QUALITY/KNOWN_ISSUES.md` → BUG-017 status `Open → Resolved`; fill in `Resolved:` field with the commit hash range `efaf8cb4..30d032ea` (the three BSAudit.3.impl commits) + this validate increment's commits.
   - `docs/RELEASE_NOTES_DEV.md` → new entry `[dev-2026-05-XX]` with the full BSAudit.3 narrative (impl + validate); cite captures, verifier numbers, M7 verdict.
   - `docs/ENGINEERING_PLAN.md` → BSAudit.3 increment marked ✅; cite both the impl commit range and the validate commits.
   - `CLAUDE.md` updates per design §8 (the table mentions a new "Cold-Start Phase Contract" section). Author it under §Audio Data Hierarchy: short paragraph describing the BPM-prior + broadband-peak + accent-confidence architecture, with a pointer to the design doc for details.
   - `docs/CAPABILITY_REGISTRY/BEAT_SYNC.md` → closeout addendum citing the validate results.
5. **Commit:** `[BSAudit.3.validate.3] Validation closeout: fresh capture + M7 PASS → BUG-017 Resolved`. Include the M7 verdict in the commit body.

**Done-when:** all closeout doc updates landed; M7 PASS recorded in the commit body and `KNOWN_ISSUES.md`; engine + app suites + lint green; full BSAudit.3 (impl + validate) closed out as one resolution.

## After BSAudit.3.validate lands

BUG-017 is **Resolved**. The Drift Motes (Failed Approach #58) pattern is broken: a five-iteration chain of failed fixes converged on the design-first + audit-first + diagnostic-first pattern that produced a perceptually-correct close.

Possible next-increment candidates (none of these block validate; surface to Matt for prioritisation):

- **Spotify-cache invalidation for older entries.** Pre-BSAudit.3 cache entries on disk have `gridOnsetOffsetMs > 0` and `rhythmCharacter = nil`. They still load correctly (the field is preserved, nil is treated as `.neutral`), but they don't get the per-track tunable scaling. A one-line bump of the cache version OR a "re-prep stale entries on first use" path would close that. Matt's call.
- **`audioOutputLatencyMs` per-output-device calibration** (BUG-007.6 follow-up) — preserved through BSAudit.3 but never auto-calibrated against measured tap-to-speaker delay. Listening-party use case wants this.
- **Long-form M7 across the catalog.** The Phase CS bar was "10 tracks". A broader catalog M7 (50+ tracks) on the BPM-prior architecture would surface tracks the difficulty-scaling formula needs calibration on. Tied to the `phaseAcquisitionDifficulty` calibration open question in design §10.4.

## Verification criteria (write before the fix — already specified in design §12)

- [ ] **Automated:** Engine suite passes (1252 baseline + new self-test cases; document delta).
- [ ] **Automated:** Project-wide `swiftlint --strict` 0 violations.
- [ ] **Automated:** App build clean.
- [ ] **Automated:** `ColdStartVerifier --self-test` PASS (every check, including the new accent-window-pass-rate self-tests).
- [ ] **Automated:** `ColdStartVerifier --session <fresh-capture> --accent-window-pass-rate` reports ≥ 90 % of catalog PASS-firing OR PASS-degraded (per design §4 + §12). Tracks pre-flagged as hard via `RhythmCharacter.phaseAcquisitionDifficulty` are expected to PASS-degraded; non-hard tracks should PASS-firing.
- [ ] **Manual (load-bearing):** Matt M7 listening review on a fresh real-listening-party session confirms perceptually credible sync from frame 1 with the soft-ramp warmup. **M7 is the close gate.** Verifier PASS is necessary but not sufficient (verifier-circularity caveat per BSAudit §5b — the verifier's reference is Beat This! on the same raw tap that produced the features.csv, so it cannot detect a class of failures M7 catches).
- [ ] **Regression:** BUG-007.x lock-state API surface preserved (`SpectralCartograph` diagnostic display unchanged; existing regression tests pass).

## Stop-and-report criteria

Per CLAUDE.md "stop and report" — stop and surface to Matt before pushing through if any of these fire:

- Sub-commit 1's self-test reveals the metric is gameable (false-pass when accents fire on every audible beat regardless of phase, or false-fail when graceful degradation is in effect). Don't ship a metric that lies about correctness.
- Sub-commit 2's historical baseline shows the metric is *insensitive* to the BSAudit.3.impl change — i.e., old captures and new captures score identically. That means the metric isn't catching what it should.
- Matt's fresh capture cannot be produced (build failure, capture tooling broken). Don't fabricate a substitute.
- Verifier PASS at sub-commit 3 followed by M7 FAIL. This is the BSAudit-pattern failure mode at validate scope (Hypothesis 1 from BEAT_SYNC.md: verifier doesn't detect what M7 catches). Open a follow-up rather than landing a false-positive closeout.
- M7 PARTIAL with no clear next-step root cause. Don't file BSAudit.3.fix-1; file an audit-scope increment to characterise what M7 is reading.
- The "diagnostic infrastructure precedes fidelity claims" rule (CLAUDE.md Authoring Discipline) is at risk of being skipped — e.g., closeout doc updates landed before the verifier mode self-tested. Back the commit out.

The cost of pausing is small. The cost of an unauthorized scope expansion, a six-iteration failure pattern, or a false-positive closeout is high.

## Hard rules

- **Sub-commits ship in order.** validate.1 (diagnostic) → validate.2 (historical baseline) → validate.3 (fresh capture + M7 + closeout). Engine + lint + tests green at each step.
- **Per CLAUDE.md commit format:** `[BSAudit.3.validate.N] <component>: <description>` where N ∈ {1, 2, 3}.
- **No closeout language until M7 PASS.** validate.1 and validate.2 are diagnostic / measurement; their commit messages cite numbers, not verdicts. Closeout language ("Resolved", "shipped", "fix lands") only appears in validate.3 *after* Matt's M7 verdict is recorded.
- **Do not push without Matt's explicit "yes, push."** Local-only until M7 PASS + closeout, then push the validate commit range alongside the BSAudit.3.impl range.
- **Do not bundle out-of-scope work.** No CLAUDE.md re-architecture, no `audioOutputLatencyMs` calibration work, no Spotify-cache invalidation, no preset shader changes. If those come up, file as candidate next-increment per the "After BSAudit.3.validate lands" section.
- **Do not touch the pre-existing out-of-scope tree state** (the `PhospheneApp.xcscheme` modification, `default.profraw`, `docs/CS_1_Y_KICKOFF.md` → `docs/prompts/` move). Matt's call when those land.
- **The verifier is within-capture-only.** Do not extend the new mode to do cross-capture comparison — Path A is closed, and cross-capture references aren't reliable. If a closeout argument depends on cross-capture agreement, it's the wrong argument.

## Status on entry

- **Branch `main`.** HEAD is `30d032ea` ([BSAudit.3.impl.3]). Already pushed to `origin/main`.
- **Engine suite green:** 1252 / 1252 (1 pre-existing intermittent known issue, `MemoryReporter.residentBytes`).
- **App suite green:** 333 / 333.
- **`swiftlint --strict`:** 0 violations across 388 files.
- **`ColdStartVerifier --self-test`:** PASS (7/7).
- **BUG-017:** Open. Fix implemented (BSAudit.3.impl); awaiting validation.
- **Reference captures available** for testing (in `~/Documents/phosphene_sessions/`):
  - `2026-05-22T16-57-36Z/` — CS.1 baseline (pre-fix).
  - `2026-05-22T19-03-59Z/` — CS.1.y.2 onset-fix attempt (since reverted, pre-fix).
  - `2026-05-23T02-39-54Z/` — CS.1.y.2-redo round 2 (since reverted, pre-fix).
  - `2026-05-24T15-07-31Z/` — M7 capture (CS.1.y.2-redo, since reverted, pre-fix).
- **`ColdStartVerifier` binary:** at `PhospheneEngine/.build/arm64-apple-macosx/release/ColdStartVerifier` (built during BSAudit.3.impl.3 verification). Rebuild on each sub-commit's verification step with `swift build --package-path PhospheneEngine --product ColdStartVerifier -c release`.
- **Pre-existing uncommitted out-of-scope items** in the tree (leave alone): `PhospheneApp.xcscheme`, `default.profraw`, `docs/CS_1_Y_KICKOFF.md` → `docs/prompts/` move pending.

If you find this prompt is wrong or stale, update it before working against it.

— Matt + Claude (2026-05-25, BSAudit.3.impl shipped; validate next)
