# D-B proposal — ratify or revise the per-suite BeatBench targets

Decision D-B (BEAT_SYNC_PROGRAM_PLAN.md §5) arrives after the GT.3 baseline. This is
the evidence and the proposal; the decision is Matt's.

Baseline: [`BEATBENCH_BASELINE_2026-07-30.md`](BEATBENCH_BASELINE_2026-07-30.md).
Ground truth: GT.2 (Matt's taps + madmom + librosa).

## What this baseline can and cannot settle

**It measures the offline / prep-time grid only.** Every live-path target in §1 —
phase error p90, re-lock latency, lock %, confident-wrong rate — has **no baseline
yet**; those need session-replay mode (unbuilt) and, for confidence, Phase CNF.

**Coverage is thin.** 9 of 17 tracks are ground-truthed, and only suites 2 has more
than one: suite 1 = 1 track, suite 3 = 1, suite 4 = 1, suite 5 = 1. A target set from
one track is a target set from an anecdote.

So D-B can honestly ratify the **offline** targets for suites 1 and 2 now, and should
**defer** the rest until they are measurable.

## The measured baseline

| suite | track | grid BPM | truth | F | CMLt | AMLt | beatsPerBar | barConf |
|---|---|---|---|---|---|---|---|---|
| 1 | Billie Jean | 116.88 | 117.4 | 0.97 | 0.97 | 0.97 | 4 ✓ | 1.00 |
| 2 | Take Five | 169.24 | 167.1 | 0.99 | 1.00 | 1.00 | 2 ✗ (5) | 0.79 |
| 2 | Solsbury Hill | 102.68 | 102.4 | 0.97 | 1.00 | 1.00 | 1 ✗ (7) | 0.73 |
| 2 | Money | 116.19 | 61.0 | 0.58 | 0.00 | 0.88 | 1 ✗ (7) | 0.77 |
| 2 | Pyramid Song | 65.08 | 66.6 | 0.52 | 0.75 | 0.75 | 1 ✗ (?) | 0.58 |
| 2 | YYZ | 233.61 | 272.3 | 0.58 | 0.21 | 0.21 | 2 ✗ (?) | 0.37 |
| 3 | Bohemian Rhapsody | 78.18 | 71.1 | 0.47 | 0.48 | 0.48 | 2 ✗ (4) | 0.29 |
| 4 | Bleed | 115.00 | 226.7 | 0.61 | 0.03 | 0.84 | 4 ✓ | 0.50 |
| 5 | Clair de Lune | 128.63 | 49.9 | 0.14 | 0.00 | 0.02 | 3 — | 0.55 |

## Three findings that should shape the targets

**1. Tempo is in better shape than assumed; METER is the weak axis.**
`beatsPerBar` is plausible on **2 of 9** tracks. Take Five reads 2 (is 5), Solsbury
Hill and Money read 1 (are 7). Downbeat F is 0.13–0.26 everywhere except Billie Jean's
0.90. Meanwhile beat-level tempo is excellent on the clean cases. The plan's §1 targets
lead with beat F, which measures the thing that is mostly working.

**2. Where F looks bad, it is often a metrical-level difference, not an error.**
Money: F 0.58 but **AMLt 0.88** — the grid is at 116 where Matt tapped 61, a clean 2:1.
Bleed: F 0.61 but **AMLt 0.84** — same story. Both are musically defensible readings.
Whether that counts as success is a *product* question, not a measurement question
(see Decision 1 below).

**3. `barConfidence` is informative but does not yet separate right from wrong.**
Sorted: Bohemian Rhapsody 0.29 (wrong), YYZ 0.37 (wrong), Bleed 0.50 (right),
Clair de Lune 0.55 (**wrong — and should be near zero**), Pyramid Song 0.58 (right),
Solsbury 0.73, Money 0.77, Take Five 0.79, Billie Jean 1.00 (all right). The two worst
tracks do sit lowest, but **Clair de Lune — true rubato, where the honest answer is
"no grid" — scores higher than Bleed, where the grid is correct.** Suite 5's whole
premise is that confidence must be trustworthy; today it is not. That is a concrete
starting number for Phase CNF, and a reason not to gate suite 5 on it yet.

## Proposal, suite by suite

### Suite 1 — baseline 4/4 · RATIFY AS WRITTEN
Plan: beat F ≥ 0.95 offline; live p90 < 30 ms; downbeat correct.
Measured: F 0.97, downbeat F 0.90 on Billie Jean. **Offline bar is met — keep it
absolute** (the plan's own default). The live p90 < 30 ms bar stays as written and is
the hardest open target in the program: TRK's evidence on main has drift reaching
119 ms late-track (BUG-065). Add 2–3 more suite-1 tracks before treating 0.97 as
representative.

### Suite 2 — odd meters · SPLIT THE TARGET
Plan: meter correct on ≥ 3/4; beat F ≥ 0.85.
Measured: beat F is **0.99 and 0.97** on the two tracks with unambiguous ground truth,
and meter is correct on **0 of 5**.
Proposal: **raise the beat bar to ≥ 0.90** (already exceeded where ground truth is
clean, so it costs nothing and stops a solved axis reading as at-risk), and **keep the
meter target but treat it as the real suite-2 work**. Splitting these stops a good
tempo number from masking a broken meter number.

### Suite 3 — tempo changes · DEFER
Plan: re-lock ≤ 20 s; phase error < 50 ms after re-lock; no confident wrong-tempo pulse.
**None of these are measurable offline** — the prep grid emits a single BPM for the
whole track, so "re-lock" has no meaning in this mode. Bohemian Rhapsody's F 0.47 is
that structural fact, not a tuning gap. Defer D-B for suite 3 until FT (full-track
tiling) and session-replay exist.

### Suite 4 — dense transients · ADD A STABILITY TARGET
Plan: quarter-note grid tracked, beat F ≥ 0.80.
Measured: Bleed F 0.61 / AMLt 0.84 — passes on metrical-level terms, fails on strict.
But the single-number target misses what BUG-076 found: across nine 30 s windows the
grid spans **2.11×** (six read ~115, three read 121 / 166 / 243). A target that scores
one excerpt cannot see that.
Proposal: **add "grid stability: ≥ 8/9 windows within 5 % of a valid metrical level,
spread < 1.1×"** as a suite-4 target. Baseline 6/9 and 2.11×. Control: Billie Jean is
flat with barConfidence 1.00 at every window, so this is achievable, not aspirational.

### Suite 5 — ambiguous / rubato · DEFER, BUT RECORD THE NUMBER
Plan: Ipanema F ≥ 0.80; Clair de Lune confident-wrong ≈ 0, confidence below the accent
threshold ≥ 90 % of duration.
Ipanema is not yet ground-truthed. Clair de Lune's target is about *confidence*, which
needs Phase CNF and the live path. Record the starting point — **barConfidence 0.55 on
a track that should read near zero** — and defer the gate.

## Summary of the ask

| suite | now | proposed |
|---|---|---|
| 1 | F ≥ 0.95 | **ratify unchanged** (met: 0.97) |
| 2 | F ≥ 0.85, meter ≥ 3/4 | **F ≥ 0.90** (met on clean truth) + keep meter as the real work |
| 3 | re-lock ≤ 20 s etc. | **defer** — not measurable until FT + replay |
| 4 | F ≥ 0.80 | keep + **add stability: ≥ 8/9 windows, spread < 1.1×** |
| 5 | confident-wrong ≈ 0 | **defer** to CNF; record barConfidence 0.55 as the start |
