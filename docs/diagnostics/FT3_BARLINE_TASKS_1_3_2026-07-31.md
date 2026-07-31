# FT.3 tasks 1–3 — the meter survives unseen tracks; the PHASE does not

**Date:** 2026-07-31 · **Status:** measurement, no engine code · **Feeds:** the FT.3 port decision
**Script:** `tools/barline_combine.py` · **Basis:** `docs/diagnostics/BARLINE_PROBE_2026-07-31.md`

FT.3's spec ran tasks 1–3 (unseen tracks, phase, combination rule) as the honest test of the
probe's 6/6 before any Swift port, and stopped there by its own task-2 rule. This is that
measurement.

**Headline: meter holds up. Phase does not.** The probe's 6/6 on meter survives eight unseen
tracks at 8/8. But phase — never measured before — is correct on **3 of the 6** tracks where
the meter is correct, and the two clean failures are not tuning problems. On `money` the phase
is off by exactly one beat against an unambiguous ground truth; on `bleed` the whole
one-phase-for-the-whole-track model does not fit the data.

Per FT.3 §5 task 2 — *"If phase is wrong where meter is right, that is the headline finding of
this increment"* — the port (tasks 4–6) was not started.

---

## Pre-flight

The probe reproduces **6/6** on the ground-truthed catalogue before anything was changed, so
the basis has not moved. Two deviations from the spec's §4 invariants, both environmental:

- **`main` is `72bc1fd6`, not `7dc822e6`.** The probe and this spec live on
  `claude/ft3-barline-spec` (`7dc822e6`, `6423ed6c`), which is unmerged and a clean
  fast-forward from `main`. This work branched from that, not from `main`.
- **Beat This! weights were unsmudged Git LFS pointers in the worktree** (~128 B each),
  failing model construction with `BeatThisWeightError error 4`. `git lfs checkout` fixed it.
  This is the LFS analogue of the known gitignored-fixtures-don't-reach-worktrees trap.

---

## Task 1 — the unseen tracks: 8 / 8

Caveat 1 of the probe doc was that the meter set was narrowed to {3,4,5,7} *after* seeing the
first table, which is how a result gets tuned into existence. These eight tracks have no
ground truth and so played no part in that. Their meters are **published / by-ear, not tapped
truth**, and are bracketed accordingly.

| track | published | rule pick | margin (sum) | margin (common-phase) |
|---|---|---|---|---|
| around_the_world | [4] | 4 ~ | +0.591 | +0.286 |
| dance_yrself_clean | [4] | 4 ~ | +1.445 | +1.456 |
| giorgio_by_moroder | [4] | 4 ~ | +0.678 | +0.423 |
| girl_from_ipanema | [4] | 4 ~ | +3.315 | +3.561 |
| so_what | [4] | 4 ~ | +1.751 | +2.431 |
| stayin_alive | [4] | 4 ~ | +1.515 | +1.620 |
| superstition | [4] | 4 ~ | +2.073 | +2.329 |
| there_there | [4] | 4 ~ | +4.022 | +3.216 |

**8/8, on all three combination rules**, with margins mostly far healthier than the
ground-truthed set's. Compared to the 6/6 measured on the designing set, the meter result does
**not** degrade on unseen material.

**Two limits on how much this proves.**

1. **Every one of the eight is in 4.** So this tests only the false-positive side — does the
   method invent a 3, 5 or 7 where there is a 4? It does not, eight times, and that *is* the
   specific worry caveat 1 raised about the meter-set restriction. But it puts no new evidence
   under the odd-meter recoveries, which are the whole reason this lever is interesting. An
   unseen odd-meter track with tapped ground truth would be the test that matters.
2. **`so_what` and `there_there` are 30 s clips** (1499 / 1497 frames, one tiler window), not
   full tracks. They are weak evidence for a method whose premise is that the whole track exists.

---

## Task 2 — PHASE, the finding that stops this increment

Scored against `downbeats_s` in the ground-truth JSON: each tapped downbeat is snapped to its
nearest grid beat and asked whether that beat's index mod the meter is the phase we chose.

The **ceiling** column is the share of taps landing on the taps' *own* modal phase — the best
score any method could achieve on that track under a single global (meter, phase). It is what
separates "our phase is wrong" from "no single phase describes this track".

| track | truth | meter | our p | tap mode p | agree | ceiling | n | verdict |
|---|---|---|---|---|---|---|---|---|
| billie_jean | 4 | 4 ✓ | 2 | 2 | **100 %** | 100 % | 34 | meter + phase |
| take_five | 5 | 5 ✓ | 0 | 0 | **85 %** | 85 % | 175 | meter + phase |
| bohemian_rhapsody | 4 | 4 ✓ | 3 | 3 | **68 %** | 68 % | 44 | meter + phase |
| money | 7 | 7 ✓ | 5 | **6** | **0 %** | **79 %** | 19 | METER RIGHT, PHASE WRONG |
| bleed | 4 | 4 ✓ | 3 | 0 | **16 %** | **37 %** | 76 | METER RIGHT, PHASE WRONG |
| solsbury_hill | 7 | 7 ✓ | 4 | 1 | **14 %** | **16 %** | 37 | METER RIGHT, PHASE WRONG |

**Phase correct where meter is correct: 3 / 6** (identical under all three combination rules).

Note what the ceiling does to the three failures — they are three *different* failures:

- **`money` — a real, clean, off-by-one error.** Ceiling 79 %: the taps agree on phase 6 and
  hold it for 15 consecutive bars before the 4/4 sax section breaks it. The truth is
  unambiguous and we picked the beat before it. This is the method being wrong, and it is the
  one a port would have shipped.
- **`bleed` — the model doesn't fit.** Ceiling 37 %: the taps themselves never settle. Their
  phase alternates `2,0,2,0,2,0…` — consecutive downbeat taps sit **2 grid beats apart**, so
  the bar is 2 grid beats, which is deliberately outside D-207's {3,4,5,7}. The probe's "4 ✓"
  on bleed is a period-2 signal winning at its own multiple, not the bar being found.
- **`solsbury_hill` — unmeasurable.** Ceiling 16 % against a 14 % uniform floor over 7 phases.
  The taps land on a different phase almost every time. This track carries no phase evidence
  either way.

### Why: the grid's beat is not the ground truth's beat

Bar length measured in *engine grid beats* — median downbeat-tap gap ÷ median grid beat period:

| track | truth | grid BPM | tap BPM | grid/tap | bar (s) | **bar in grid beats** |
|---|---|---|---|---|---|---|
| billie_jean | 4 | 115.4 | 117.4 | 0.98 | 2.054 | **3.95** ✓ |
| take_five | 5 | 166.7 | 167.1 | 1.00 | 1.750 | **4.86** ✓ |
| bohemian_rhapsody | 4 | 81.1 | 71.1 | 1.14 | 3.390 | 4.58 |
| money | 7 | 130.4 | 61.0 | 2.14 | 3.481 | 7.57 |
| bleed | 4 | 120.0 | 226.7 | **0.53** | 1.039 | **2.08** |
| solsbury_hill | 7 | 103.4 | 102.4 | 1.01 | 7.030 | **12.12** |
| yyz | — | 142.9 | 272.3 | **0.52** | 3.393 | 8.08 |
| clair_de_lune | — | 107.1 | 49.9 | 2.15 | 5.312 | 9.49 |

Only **billie_jean and take_five** put an integer from {3,4,5,7} in the last column — and they
are exactly two of the three tracks where phase is right. The ground truth is internally
consistent (its own `meter_note` ratios are 4.02 / 4.97 / 4.02 / 3.54 / 3.93 / 7.00 against
its own tapped beats); the mismatch is between the **engine grid** and the **tapped beat**.
On `bleed` and `yyz` the grid runs at half the tapped rate; on `money` and `clair_de_lune` at
roughly double it.

This is the structural point. Meter search over `i % B` only has to find the right *period*,
and a period-8 pattern still shows period-4 structure, so a half-time grid can score a
plausible meter. Phase has no such slack: it needs the grid beat to be the notated beat and it
needs the index to survive the whole track without gaining or losing one. Suite-1 F 0.97 says
the beats are in the right *places*; it does not say the grid is at the right metrical *level*
or that a global beat index is meaningful. **The phase result is a measurement of that gap, and
no amount of accent-feature work closes it.**

`solsbury_hill`'s ground truth is additionally suspect: `meter_from_taps` is 7 and
`meter_note` says "ratio 7.00", but its downbeat taps are ~12 tapped beats apart
(7.03 s at 102 BPM). Those two cannot both be right. Flagged as a ground-truth question, not
used as evidence here.

---

## Task 3 — the combination rule, and its no-bar-information control

Three rules were implemented and all three were run against the control the spec asked for:
synthetic feature sets carrying **no** bar information, 200 trials each, under two generators —
Gaussian noise, and shuffled real features (which keeps the heavy tails and is the stricter of
the two). A clean rule picks each meter ~25 % of the time and shows no trend of margin against
meter.

| rule | meter (tapped) | meter (published) | phase | control: noise | control: shuffled real |
|---|---|---|---|---|---|
| `max_feature` — per-feature margin, take the max (**what the probe did**) | 6/6 | 8/8 | 3/6 | 3:18 4:24 5:24 **7:33 %**, slope +0.0039 | 3:18 4:18 5:29 **7:36 %**, slope +0.0052 → **FAIL** |
| `sum_margin` — sum the four per-feature margins per meter | **6/6** | **8/8** | 3/6 | 3:24 4:25 5:25 7:26 %, slope −0.0038 | 3:22 4:24 5:29 7:26 %, slope +0.0004 → **PASS** |
| `common_phase` — sum contrasts at a shared phase, one null on the sum | 5/6 | 8/8 | 3/5 | 3:24 4:26 5:18 7:32 %, slope +0.0043 | 3:22 4:24 5:21 **7:33 %**, slope +0.0018 → PASS |

**Chosen rule: `sum_margin`.** Sum the four features' null-corrected margins per meter, take
the argmax; confidence is the gap to the runner-up. It is the only rule that is both unbiased
under the strict control and retains 6/6 + 8/8.

**The incumbent rule carries the DBN.2 bias.** `max_feature` takes a maximum over four
features and never subtracts that inflation — only the per-feature max-over-phase inflation.
Its no-information picks skew to 7 under both generators (33 %, 36 %) and its mean margin rises
monotonically with meter in both. The uniformity miss is marginal on its own (35.5 % against a
10 %-deviation threshold), but the direction is consistent across both controls and both
statistics, and **two of the probe's six correct answers are 7**. The 6/6 is not thereby void —
`sum_margin` reproduces it without the bias — but the headline was measured with a statistic
that leans the way the interesting answers lie. That is precisely the failure that derailed
DBN.2 twice (D-208 §9.6/§9.7), present in this method's first published number.

`common_phase` is the theoretically cleanest formulation (one statistic, one null, phase falls
out of it, both inflations subtracted) and it does pass. It loses `solsbury_hill` — which,
given that track's 16 % phase ceiling, may be the rule declining to invent structure rather
than a regression. Not enough evidence to call it either way on one track.

---

## Where this leaves the port

The spec's §10 recommendation was to run tasks 1–3 and re-decide. Task 1 came back positive;
task 2 came back negative on the axis that decides whether the output is usable.

`beatsPerBar` alone changes nothing a user sees — Nacre's and Glaze's downbeat pushes need the
bar *line*. A correct meter on the wrong phase puts every accent on the wrong beat of every
bar, which is visually indistinguishable from being wrong, at 3 of 6 measured. And the reason
is upstream of this method: on 4 of 6 tracks the engine grid is not at the ground truth's
metrical level, so a global beat index does not name the bar line.

Options, product-level:

- **Stop here.** Bank tasks 1–3 as the result. The meter finding is real and recorded; the
  phase finding says the accent-feature lever cannot deliver a usable bar line on its own.
- **Re-scope FT.3 to the grid-level question first** — does the engine grid sit at the notated
  beat, and can that be detected? That is the actual blocker, and it is a different premise
  from "which beat is the bar line", so it does not fall under the two-strikes rule.
- **Port meter only, declining on phase.** Delivers `beatsPerBar` with no bar line. Given no
  consumer uses `beatsPerBar` without the phase, this ships nothing visible.

Ground truth for an unseen odd-meter track would sharpen all three.

---

## Reproduce

```bash
git lfs checkout                       # if the Beat This! weights are LFS pointers
mkdir -p /tmp/barprobe2
PHOSPHENE_FT1_FULLTRACK=1 PHOSPHENE_BEATS_DUMP=/tmp/barprobe2 \
  swift test --package-path PhospheneEngine --filter FullTrackMeter

~/phosphene-ml-env/bin/python tools/barline_combine.py \
  --beats-dir /tmp/barprobe2 --fixtures ~/phosphene_beatbench_fixtures --control 200
```
