# BSAudit.3.diag — Root-Cause Dive on the 2026-05-25T15-20-49Z Fresh Capture

> **AMENDED 2026-05-26 — diagnostic findings preserved.** The BSAudit.3.impl runtime characterized by these findings was reverted on 2026-05-25 evening (`33cd57e9` / `6758a617` / `002b5f2b` / `35305b5e`). The findings stand as the empirical evidence that motivated both Matt's Choice A decision and the subsequent revert — the three structural failures characterized here (wrong-anchor lock on broadband flux; confidence accumulator doesn't back-pressure; metric is gameable by over-firing) apply to any short-window automated signal source, not just to the specific BSAudit.3.impl mechanism. The diagnostic infrastructure that produced these findings was retained through the revert per Matt's "yes, keep the tools" sign-off. See [CLAUDE.md §Cold-Start Phase Contract](../../CLAUDE.md#cold-start-phase-contract) for the current production-state description.

**Date:** 2026-05-25
**Capture under analysis:** `~/Documents/phosphene_sessions/2026-05-25T15-20-49Z/`
**Build state:** `30d032ea` (BSAudit.3.impl.3) + validate.1 schema addition staged. **Note 2026-05-26:** the impl runtime that produced this capture's behavior was subsequently reverted same evening; the capture and findings are preserved as historical record of the architecture that was attempted.
**Scope:** read-only diagnostic. Per CLAUDE.md Defect Handling Protocol, post-validation-failure work returns to the **Diagnosis** stage. No fix code in this increment.
**Tool extension:** the `--accent-window-pass-rate` mode gained a per-track diagnostic block (`AccentWindowDiagnostic.swift`) so future post-mortems start from data, not speculation. Shipped alongside this doc.

## TL;DR

The BSAudit.3.impl architecture is **firing as wired** — `accent_confidence` ramps `0 → 0.1 → 0.3 → … → 1.0`, `lock_state` advances, the gating multiplication is correct. But the perceptual contract design §1 set ("credible pairing of visual and music within ~3 s") is not met on **8 of 10 catalog tracks**. Two distinct failure modes:

- **Failure A (wrong anchor + confidence climbs anyway).** First broadband peak anchors phase to off-beat content (snare, vocal entry, pad swell), confidence still reaches ≥ 0.9 because periodic content at any musically-related cadence (quarter-note rate) reinforces the wrong phase. The verifier may still score this PASS-firing because the accent layer over-fires (25+ accents in 10 s for 19 audible beats) so every audible beat gets covered by *some* accent — but the per-fire residual distribution shows most individual accents are off the beat by 100+ ms. **Billie Jean, Around the World** (both PASS-firing) and **HUMBLE., B.O.B.** (both FAIL) fall here.
- **Failure B (correct anchor + confidence never climbs cleanly).** First peak lands within ±25 ms of a real beat, but subsequent broadband content is inconsistent enough that confidence plateaus at 0.39–0.58, gating keeps composite below the 0.3 threshold most of the window, and the few accents that fire are wide in residual. **Get Lucky, Superstition, Everlong** fall here.

Only **2 tracks** (Seven Nation Army, Money) hit `pass-degraded` correctly — confidence never crossed 0.30, accents never fired, graceful degradation works as designed. Both have low/sparse onset density in the first 10 s; HUMBLE was supposed to land here too but didn't.

The design's promised mitigation — *"the confidence accumulator is the back-pressure; if the BPM prior is anchored wrong, confidence will not climb"* (§9.1) — **does not hold empirically**. The accumulator climbs even on demonstrably-off-anchor tracks because periodic broadband content at the right *period* reinforces *any* phase, not just the on-beat one.

This is iteration #6 territory per Failed Approach #58. Below is the per-track evidence, the ranked hypotheses, and the open decision tree.

## Per-track diagnostic table

All values from `~/Documents/phosphene_sessions/2026-05-25T15-20-49Z/cold_start_accent_window.md` (regenerated with the new diagnostic block). Window = first 10 s of each track at default `--accent-window-pass-rate` tunables.

| # | Track | Verdict | hits/aud | max conf | 1st peak residual (ms) | 1st accent residual (ms) | confidence ≥ 0.30 at | locked at | median \|residual\| (ms) | Mode |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | Billie Jean | `pass-firing` | 18/19 | 1.00 | **−212** | −125 | 0.652 s | 1.857 s | 109 | A |
| 2 | Around the World | `pass-firing` | 19/20 | 1.00 | **−231** | −219 | 0.639 s | 1.621 s | 113 | A |
| 3 | Seven Nation Army | `pass-degraded` | 0/20 | 0.24 | −291 | (none) | never | never | n/a | (graceful) |
| 4 | Get Lucky | `fail` | 4/19 | 0.39 | −0 (✓) | +47 | 0.853 s | never | 83 | B |
| 5 | Superstition | `fail` | 4/17 | 0.58 | −18 (✓) | +33 | 1.280 s | never | 151 | B |
| 6 | Everlong | `fail` | 15/27 | 0.98 | −25 (✓) | +82 | 4.322 s | 4.706 s | 97 | B |
| 7 | Royals | `fail` | 2/14 | 0.49 | **−516** | +264 | 7.787 s | never | 174 | A (extreme) |
| 8 | HUMBLE. | `fail` | 4/13 | 0.90 | −68 | −68 | 0.011 s | 8.864 s | 201 | A |
| 9 | B.O.B. | `fail` | 15/25 | 1.00 | **−309** | −156 | 0.011 s | 5.195 s | 101 | A |
| 10 | Money | `pass-degraded` | 0/4 | 0.25 | −5383 (SFX intro) | (none) | never | never | n/a | (graceful) |

`(✓)` marks tracks where the first broadband peak landed within ±25 ms of a real audible beat. **Only 3 of 10 tracks anchored cleanly**, and all 3 still failed because confidence climbed too slowly to fire accents inside the 10 s window.

Cached/installed BPMs were verified against approximations of true tempo per the BSAudit BeatGrid table; all numerically correct (Billie Jean 117, Royals 85, HUMBLE 76, etc.). **The BPM-prior is right; the phase anchor is wrong.**

## The BPM-prior+broadband-peak architecture's actual behaviour

### 1. The first broadband peak is rarely on a beat

5 of 10 tracks anchored to broadband content > 100 ms off the nearest audible beat:
- Billie Jean (−212), Around the World (−231), Seven Nation Army (−291), Royals (−516), B.O.B. (−309).

3 of 10 anchored within ±25 ms (Get Lucky, Superstition, Everlong). HUMBLE landed at −68 ms. Money's "first peak" came 5+ s before the first audible beat, in the SFX intro.

The negative residuals are consistent with what the design §9.1 + §9.3 warned about: **broadband flux fires on pre-beat events** — pad swells, vocal entries, hi-hat lead-ins, claps off-beat. The detector is not a beat detector; it's an "interesting transient" detector.

### 2. The confidence accumulator does not back-pressure

Design §9.1 mitigation: *"If the predicted beats consistently miss broadband peaks (because we're predicting at off-beat moments), confidence will not climb. The system stays in `acquiring` → no accents fire → visual stays continuous-energy."*

Empirically, the accumulator climbs on **every track with sustained broadband content**, regardless of whether the anchor was on-beat:
- Billie Jean (anchor −212 ms) → conf 1.0 by ~3 s
- Around the World (anchor −231 ms) → conf 1.0 by ~2 s
- B.O.B. (anchor −309 ms) → conf 1.0 by ~5 s
- HUMBLE (anchor −68 ms) → conf 0.9 by ~9 s

The mechanism: after an off-beat anchor, the predictor predicts beats every `60/BPM` seconds from the anchor. Pop/rock catalog has broadband content at *quarter-note rates* (kicks on 1/3, snares on 2/4, hi-hats on every 8th). Some of those events land within the predictor's ±60 ms acceptance window of the (wrong-phase) predictions by accident of period matching, and the accumulator increments. The accumulator can't distinguish "actually-on-beat reinforcement" from "any-periodic-content-at-the-period reinforcement."

### 3. The verifier metric is gameable by over-firing

Billie Jean's verifier reading: `18/19 hits (95% pass-firing)`. Hand-counted accent fires (rising edges of `beatComposite > 0.3`) in the first 10 s: **25+** (sample at 0.69, 0.77, 0.89, 1.04, 1.11, 1.15, 1.27, 1.51, 1.91, 2.10, 2.29, 2.44, 2.92, 3.07, 3.34, 3.60, 3.75, 4.04, 4.37, 4.88, 5.11, 5.38, 5.61, 5.83, 6.66, …). Audible beat count: 19. Over-firing rate ≈ 1.3×.

The `--accent-window-pass-rate` metric counts "audible beats with ≥ 1 accent within ±60 ms." When the accent layer over-fires (because composite is high most of the time), every beat trivially gets covered, even when the individual accents are mostly off-beat. **PASS-firing does not mean perceptually-locked.** It means "the accent layer was loud enough often enough." Median |residual| per accent fire is 109 ms — perceptually well outside the ±60 ms threshold the design picked.

### 4. Two distinct failure modes have different root causes

| Mode | What happens | Tracks | Implication |
|---|---|---|---|
| **A** | Wrong anchor + confidence climbs anyway (periodic-reinforcement) | Billie Jean, ATW, Royals, HUMBLE, B.O.B. | The confidence accumulator can't act as the back-pressure §9.1 specified. Need a different gate. |
| **B** | Right anchor + confidence plateaus (sparse onset density) | Get Lucky, Superstition, Everlong | Even with a correct anchor, the climb is too slow on tracks with non-dense early-window onsets. EMA gain (`0.25`) or threshold (`0.7`) tuning may help, but won't fix mode A. |
| **(graceful)** | Confidence never crosses 0.30 | SNA, Money | Working as designed. Confirms the architecture *can* land here when broadband density is genuinely low. |

Both A and B are real and need separate consideration. Tuning won't fix A; A is structural to the design.

## Ranked root-cause hypotheses

### Hypothesis 1 — Broadband-flux-as-phase-anchor is unsound (dominant)

**Supporting evidence:**
- 5 of 10 tracks anchored > 100 ms off the nearest audible beat.
- Consistently negative residuals (−212, −231, −291, −309, −516) indicate broadband flux fires on *pre-beat* content (pad swells, vocal entries, hi-hat lead-ins).
- The pre-impl baseline used `beatBass` and `beatComposite` (gated to 0) for accent firing — and those were the BeatDetector's per-band onsets, which fire on actual transient events. Pre-impl PASS-firing wasn't because the beat detector was good; it was because no gating meant any event triggered an accent (the older verifier scored "accent near beat" trivially).
- The new architecture's anchor uses `SpectralAnalyzer.smoothedFlux` peak detection. Smoothed broadband flux peaks on the *envelope* of the highest-energy transient near a beat, which is often the snare or hi-hat lead-in, NOT the kick.

**Contradicting evidence:**
- 3 of 10 tracks did anchor within ±25 ms (Get Lucky, Superstition, Everlong). So the anchor isn't *always* wrong.
- The 3 on-anchor tracks tend to have a strong kick on beat 1 of the track.

**Verdict.** Dominant root cause. The architecture's perceptual contract requires a beat-phase reference, and broadband flux is not one — same shape as Failed Approach #68 ("sub-bass onsets are not a beat-phase reference") at the broadband layer.

### Hypothesis 2 — Confidence accumulator doesn't filter periodic-but-off-beat reinforcement

**Supporting evidence:**
- HUMBLE: anchor −68 ms, confidence climbed to 0.90 by 9 s, accents fired at 0.011 s with conf=0.1 seed, residuals span [−68, +201, +287, +383, −259, −162, −76, +72]. Wide spread + high confidence = a confidence system that doesn't notice it's wrong.
- Billie Jean: anchor −212 ms, conf reaches 1.0 inside 3 s. Periodic content reinforced the wrong phase.

**Contradicting evidence:**
- Get Lucky / Superstition (mode B) — confidence DOESN'T climb cleanly on these. So the accumulator IS sensitive to *something*; just not to "is the anchor on the beat."

**Verdict.** Real architectural flaw. The accumulator increments on any predicted-beat ↔ broadband-peak match within ±60 ms, which periodic content trivially satisfies regardless of phase correctness. Tightening the EMA acceptance window (`window: ±60ms` → `±30ms`) might help but would shift mode B (Get Lucky, etc.) further toward never-locking.

### Hypothesis 3 — The verifier metric is gameable by accent over-firing

**Supporting evidence:**
- Billie Jean: 25+ accent fires in 10 s for 19 audible beats; per-fire median |residual| = 109 ms; metric says PASS-firing 95%.
- The 100% pre-impl baseline on cap2/3/4 (validate.2 doc) is now retrospectively understood: pre-impl had no gating, composite fired constantly, "any accent within ±60 ms of any beat" was trivially true. The metric was insensitive to actual perceptual sync there too.

**Contradicting evidence:**
- The metric does distinguish PASS-firing / PASS-degraded / FAIL meaningfully on the FAIL tracks — Get Lucky's 4/19 vs Billie Jean's 18/19 IS a real differentiator under the architecture's gating.

**Verdict.** Metric design issue. The original kickoff (validate.1) speced this gate by counting "any accent in window" which is the correct measure of accent-presence, not accent-correctness. A perceptually-tuned metric would look at the per-fire residual distribution — e.g., `pass-firing` requires `median |residual| ≤ 30 ms` AND `audible coverage ≥ 80%`. Under that gate Billie Jean would not pass.

### Hypothesis 4 — Pre-analysis `RhythmCharacter` calibration is wrong

**Supporting evidence:**
- The design §7 specified `phaseAcquisitionDifficulty` and `octaveRisk` flags pre-computed at prep time. These should have scaled the EMA gain, acceptance window, and dual-candidate handling per track.
- The fresh capture's tracks land on default tunables — the prep-time calibration wasn't visible-from-log to have made any per-track adjustments. The `BPM prior installed:` lines show no `character=` field. Either the values were all default-neutral or the per-track scaling isn't being applied.

**Contradicting evidence:**
- Can't currently verify what `phaseAcquisitionDifficulty` / `octaveRisk` values the cache loaded vs what the runtime used. Need a log line or a CSV column for this.

**Verdict.** Possible contributor. Cannot characterize from current artifacts; would need an instrumentation increment to dump the per-track `RhythmCharacter` values at install time.

### Hypothesis 5 — The fresh capture itself is anomalous

**Supporting evidence:**
- None. Captures from earlier today (`2026-05-25T04-34-02Z` through `2026-05-25T14-57-23Z`) were all empty (1 frame each) — exploratory runs.
- The pre-impl baseline (validate.2) ran cleanly against the same 10-track playlist; this capture's DSP signals (`beatComposite`, `accent_confidence`, `lock_state`) are well-formed.

**Contradicting evidence:**
- N/A — capture looks healthy.

**Verdict.** Not the cause.

## What this implies for the BSAudit.3 architecture

The architecture has three failures stacked:

1. **The anchor signal (broadband flux peak) is unreliable** — same class of failure as Failed Approach #68. The design recognized this risk in §9.3 ("Broadband flux could itself be off-beat on some tracks") and proposed mitigation via confidence accumulator + beat strength profile. Neither mitigation works.
2. **The confidence accumulator does not back-pressure off-anchor lock** — periodic broadband content at the right period reinforces any phase, not just the right one.
3. **The verifier metric is too lenient** — gameable by accent over-firing.

Taken together: the BSAudit.3.impl architecture **does not deliver the design §1 perceptual contract** ("credible pairing of visual and music"). It substitutes a less-credible contract: "an accent fires near each beat, regardless of whether the accents are individually on-beat."

This is the **Failed Approach #58 iteration #6 signal**. Previous five iterations:
- CS.1 baseline (no runtime correction) → 7/10 fail M7
- CS.1.y.2 (sub-bass-onset snap) → 0/10 pass verifier; reverted
- CS.1.y.2-redo round 1 (Beat This!@15s snap, engine bug) → bug, refixed
- CS.1.y.2-redo round 2 (Beat This!@15s snap, snap-drift cross-capture-unstable) → reverted
- BSAudit.3.impl (BPM-prior + broadband-peak + confidence-gated accents) → 6/10 FAIL on verifier

Per CLAUDE.md Authoring Discipline "iteration converges only when each step integrates feedback into the model" — the model that's been wrong upstream across all 5 (now 6) iterations is **the premise that an automated mechanism can identify the audible beat phase from live tap audio inside the first ~3 s of a novel track**. CS.1.y.2 tried sub-bass onsets; BSAudit found those wrong. CS.1.y.2-redo tried Beat This! @15s; BSAudit.2 found that cross-capture unstable. BSAudit.3 tried broadband flux peaks; this diagnostic finds *those* off-beat on 5/10 catalog tracks.

## Direction options (Matt's call)

These are not recommendations — they're framed alternatives so the decision has structure. Each one has different blast radius.

**Option 1 — Accept the structural limit; reframe the product contract.**
- Drop the BPM-prior phase acquisition. Cold-start contract becomes: continuous-energy modulation from frame 1; beat accents firing on the pre-analysis cached grid (off-beat by per-track amount per BUG-017 original; ~7/10 tracks "approximately synced" within ±130 ms per CS.1 baseline) OR not firing at all.
- M7 close gate: "does this read as musical?" — no claim of beat sync. Milkdrop/G-Force baseline.
- Smallest blast radius. Retires the BPM-prior architecture entirely; preserves the BSAudit.3 work as an experimental dead-end documented in HISTORICAL_DEAD_ENDS.md.

**Option 2 — Tighten the metric; iterate on the architecture once with the tighter metric as the close gate.**
- Change `--accent-window-pass-rate` to gate on `median |residual| ≤ 30 ms` AND `audible coverage ≥ 80%`. Under that, Billie Jean would fail; the metric and perceptual reality would align.
- Architectural change: replace first-broadband-peak anchor with a delayed-confirmation anchor that requires N (e.g., 4) consecutive predicted-beat ↔ broadband-peak matches within ±30 ms before claiming any phase lock. Confidence climbs only on those confirmations.
- Higher blast radius. Iteration #7 on the same defect. Failed Approach #58 territory; risk that this iteration also doesn't converge.

**Option 3 — Switch to a different anchor signal entirely.**
- Drums stem energy deviation (`drums_energy_dev`) — fires on the kick specifically, not on broadband transients. Available after the ~10 s stem warmup (D-019 blend), so the cold-start contract changes: 0–10 s continuous-energy-only; 10 s+ kick-anchored accents.
- Highest blast radius. Major architectural rewrite of the cold-start state machine. New design doc needed.

**Option 4 — Diagnostic-only increment: instrument `RhythmCharacter` install logs.**
- One-line log addition so we can see what `phaseAcquisitionDifficulty`, `octaveRisk`, `syncopationIndex` values were computed for each track. Re-run today's capture analysis with that data.
- Closes Hypothesis 4. Doesn't fix anything; just confirms whether per-track calibration was being applied.
- Smallest blast radius after Option 1.

## What I am NOT doing without your direction

- No fix code.
- No closeout commit.
- No `KNOWN_ISSUES.md` → Resolved.
- No `RELEASE_NOTES_DEV.md` closeout entry.
- No `ENGINEERING_PLAN.md` flip.
- No CLAUDE.md "Cold-Start Phase Contract" section.
- Not pushing the validate commits.

## Stop and report

Per the kickoff §Stop-and-report and CLAUDE.md "Defect Handling Protocol":

> *"M7 PARTIAL with no clear next-step root cause. Don't file BSAudit.3.fix-1; file an audit-scope increment to characterise what M7 is reading."*

This diagnostic IS the audit-scope increment. The root cause is identified (Hypotheses 1–3). The decision is yours.

— Claude (2026-05-25, BSAudit.3.diag.1)
