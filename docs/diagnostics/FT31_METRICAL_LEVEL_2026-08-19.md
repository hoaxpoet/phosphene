# FT.3.1 — the grid is not the thing at the wrong metrical level

**Date:** 2026-08-19 · **Status:** measurement; **task 4 (the Swift detector) deliberately NOT built**
**Tool:** `tools/metrical_level_probe.py` · **Basis:** `FT3_BARLINE_TASKS_1_3_2026-07-31.md`,
`BEATBENCH_BASELINE_2026-07-30.md`

**Headline.** The increment's two positives do not survive contact with their own ground
truth. On **both** money and bleed, the two independent reference annotators used at GT.2
(librosa and madmom) say the **taps** are an octave off, not the grid — and Phosphene's grid
sits in the backends' octave, not the taps'. Both tracks carry `status: metrical_review`,
which is the ground-truth pipeline's own flag for exactly this. The label set is perfectly
confounded with that status: **every `confirmed` track is a "right level" negative and every
large AMLt−CMLt gap is a `metrical_review` track.**

So `AMLt − CMLt` does not name a wrong *grid*. It names a **grid-vs-tap level disagreement**
and is silent about which side is wrong. FT.3.1's premise — "the two tracks where phase
failed are the two where the grid is at the wrong level" — is not established.

The detector built for task 3 works on synthetic wrong-level material (11/12 on verified
bases) and says "already at the notated level" on 8 of 9 real tracks, **agreeing with both
reference backends on both disputed tracks and disagreeing only with the taps.** Task 4 was
not started: a detector validated against labels that do not hold would be measuring the
label error.

---

## Pre-flight — passed, including the hard gate

`swift run BeatBench --self-test` all checks pass. `--mode offline-grid` reproduces
`BEATBENCH_BASELINE_2026-07-30.md` **row for row** — the label set had not moved, so building
on it was legitimate at the time. Lint 0/519, engine suite green, fixtures linked.

Two spec IDs are stale and neither matters: `de2c126a` / `d24d1163` are not valid objects in
this repo; FT.3 tasks 1–3 landed as `35f2d68b`.

---

## Task 1 — the label set, and how small it is

Level = grid BPM ÷ truth BPM snapped to an octave, cross-checked against the baseline's
AMLt−CMLt gap. Tracks whose ratio is *not* an octave are excluded: their grid is not at a
wrong level, it is on no stable pulse, which is a different failure.

| track | level | justification |
|---|---|---|
| billie_jean | 1.0 | ratio 0.995; CMLt 0.97 = AMLt 0.97, gap 0.00 |
| take_five | 1.0 | ratio 1.013; gap 0.00 |
| solsbury_hill | 1.0 | ratio 1.002; gap 0.00 |
| pyramid_song | 1.0 | ratio 0.977, gap 0.00; CMLt 0.75 is grouped-16/8 ambiguity, not a level error — **weak** negative |
| **money** | **2.0** | ratio 1.906; CMLt 0.00 vs AMLt 0.88, gap 0.88 |
| **bleed** | **0.5** | ratio 0.507; CMLt 0.03 vs AMLt 0.84, gap 0.81 |
| yyz | EXCL | ratio 0.858 — not an octave; gap 0.00 (0.21/0.21) = grid on no real pulse |
| bohemian_rhapsody | EXCL | ratio 1.100 — not an octave; gap 0.00; tempo changes |
| clair_de_lune | EXCL | ratio 2.577 — not an octave; AMLt 0.02 = no pulse at all |

**2 positives and 4 negatives.** The spec said a detector can be fitted to two positives and
that this is the exact failure the increment exists because of. What it did not anticipate is
that the two positives would turn out not to be positives.

## Task 2 — the synthetic control, built before any detector

**Re-gridding, not resampling.** The audio is untouched and only the grid moves, which is
exactly the real failure (Phosphene's grid at the wrong level over correct audio); resampling
would change spectral content and confound the measurement. From a base grid: `2.0` inserts
midpoints (double-time), `0.5` drops every other beat (half-time), `1.0` is the unchanged
negative control. True level is known **by construction**.

Bases: the 4 right-level tracks (**verified** — a ground-truth right-level label) plus the 8
FT.3 unseen tracks (**unverified** — assumed right-level). Verified bases support an absolute
accuracy claim; unverified bases support only the weaker within-track ordering claim, which
survives the base's true level being wrong.

## Task 3 — no absolute threshold works; a within-track comparison does

Two signals, both read from FT.3's existing accent features, both physically motivated:

- **`A_double`** — period-2 accent contrast *across grid beats*, null-corrected. High means
  alternate grid beats are weak ⇒ the grid is **double-time**. This is not a new idea: it is
  the meter-2 signal `barline_probe.py` deliberately *excluded* ("kick-on-alternate-beats is a
  genuine periodicity that is NOT the bar"). That excluded signal is the double-time detector.
- **`A_half`** — contrast between accent at grid beats and accent at the **midpoints between
  them**. Low means real events sit between grid beats ⇒ the grid is **half-time**. No null is
  needed: one fixed phase, so no max-over-phase inflation to subtract.

**Absolute distributions overlap badly**, across every pair:

| signal | factor 0.5 (median) | 1.0 | 2.0 | verdict |
|---|---|---|---|---|
| `A_double` | +0.754 | +0.783 | +2.028 | **OVERLAP** both pairs |
| `A_half` | +0.042 | +2.233 | +2.394 | **OVERLAP** both pairs |

But the **within-track ordering is correct on 9/10 bases**. So the formulation changed: rather
than threshold, re-grid the track's own beats to ½× and 2× and pick whichever candidate looks
most like the notated beat (`levelness = A_half − A_double`). That is a comparison against the
track's own baseline — the axis the data supports.

| set | correct |
|---|---|
| synthetic, **verified** bases (absolute claim) | **11/12** |
| synthetic, all bases | 25/34 |
| **real labelled tracks** | **4/6 — and it fails on both positives** |

Named synthetic confounds, not hidden: `girl_from_ipanema` 0/3 (bossa's strong two-beat
surdo/bass pattern is a genuine half-note accent, not a wrong grid), `around_the_world` 0/3
(four-on-the-floor house, where half-time and full-time readings are both musically valid),
`there_there` 0/2 (a 30 s clip, one tiler window).

## The finding — the ground truth, not the grid

The detector says "already at the notated level" for money (margin 3.431) and bleed (0.526).
Two checks say it is right and the label is wrong.

**1. Re-gridding money cannot reach the notated beat at all.** Its full-track grid period is
460 ms against a tapped 984 ms — ratio **2.139**, not 2. Halving gives 920 ms, and the share
of tapped beats landing within ±70 ms of *some* candidate beat is:

| candidate | money | bleed | billie_jean |
|---|---|---|---|
| 0.5× | 32 % | 24 % | 50 % |
| 1.0× (as-is) | **94 %** | 47 % | **100 %** |
| 2.0× | 94 % | **91 %** | 100 % |

Money's grid already covers 94 % of the tapped beats; **halving it, the correction its label
demands, drops that to 32 %.** bleed is a genuine octave case (91 % at 2×) — but its grid also
matches both backends, see below.

**2. Both independent GT.2 backends say the TAPS are the octave-off side.**

| track | status | tap BPM | librosa | madmom | Phosphene grid |
|---|---|---|---|---|---|
| billie_jean | `confirmed` | 117.44 | AGREE F=1.00 | AGREE F=0.96 | 116.88 |
| solsbury_hill | `confirmed` | 102.44 | DISAGREE ×1.00 | AGREE F=0.92 | 102.68 |
| take_five | `confirmed` | 167.07 | DISAGREE ×0.77 | AGREE F=0.88 | 169.24 |
| **money** | **`metrical_review`** | 60.97 | **METRICAL — "reference is double the tapped pulse (×2.01)"** | **METRICAL ×2.01** | 116.19 (×1.91) |
| **bleed** | **`metrical_review`** | 226.72 | **METRICAL — "reference is half the tapped pulse (×0.51)"** | **METRICAL ×0.51** | 115.00 (×0.51) |

On bleed, Phosphene's 115.00 sits between the backends' 114.80 and 115.38. On money,
Phosphene is in the backends' octave (≈2× the taps), not the taps'. `money.groundtruth.json`
says so in its own words: *"beats tapped at HALF the bar pulse"*.

**The confound is total.** Across all 9 ground-truthed tracks, every large AMLt−CMLt gap is a
`metrical_review` track and every `confirmed` track has gap 0.00. The label set is a
restatement of the ground truth's own unresolved-metrical-disagreement flag.

## Task 5 — confusion matrix, and a margin that carries no information

Synthetic, all bases:

| want \ got | 0.5 | 1.0 | 2.0 |
|---|---|---|---|
| **0.5** | **9** | 3 | 0 |
| **1.0** | 1 | **9** | 2 |
| **2.0** | 2 | 1 | **7** |

| | n | min | median | max |
|---|---|---|---|---|
| correct | 29 | +0.013 | +1.741 | +5.107 |
| incorrect | 11 | +0.255 | +2.910 | **+5.695** |

**Total overlap — the incorrect margins are on average *larger* than the correct ones.** The
decline sweep confirms the margin is not a confidence signal at all:

| threshold | answered | correct | **confident-wrong** |
|---|---|---|---|
| 0.00 | 40 | 29 | 11 |
| 1.00 | 27 | 21 | 6 |
| 2.00 | 17 | 11 | 6 |
| 3.00 | 10 | 6 | **4** |

**This settles D-210's open clause.** D-210 says level *correction* "returns as an option only
if FT.3.1 task 5 shows a near-zero confident-wrong rate". It does not, at any operating point.
Correction stays off the table, and D-210's decline-the-bar decision is unaffected — but its
evidence table, which cites money and bleed's gap as showing the **grid** is at the wrong
level, needs the correction above.

## Task 6 — five suites

**No behavioral change to beat sync.** Nothing was wired; no engine source was touched. The
detector's verdict against each track's gap:

| track | gap | detector | margin | GT status | backends on the taps |
|---|---|---|---|---|---|
| billie_jean | 0.00 | 1.0 ✓ | 0.013 | confirmed | AGREE |
| bleed | 0.81 | 1.0 | 0.526 | metrical_review | METRICAL |
| bohemian_rhapsody | 0.00 | 1.0 ✓ | 1.437 | metrical_review | DISAGREE/METRICAL |
| clair_de_lune | 0.02 | 1.0 ✓ | 0.694 | needs_arbitration | DISAGREE |
| money | 0.88 | 1.0 | 3.431 | metrical_review | METRICAL |
| pyramid_song | 0.00 | 1.0 ✓ | 0.759 | metrical_review | DISAGREE/METRICAL |
| solsbury_hill | 0.00 | 1.0 ✓ | 1.741 | confirmed | AGREE/DISAGREE |
| take_five | 0.00 | 1.0 ✓ | 1.460 | confirmed | AGREE/DISAGREE |
| yyz | 0.00 | 2.0 ✗ | 0.124 | metrical_review | METRICAL |

8 of 9 read "already at the notated level"; yyz's 2.0 is a near-tie (margin 0.124).

## Why task 4 was not built

Two formulations were tried on the premise "the level is recoverable blind" — absolute
thresholds (overlap) and within-track argmax (fails on both real positives). The
`beat-sync-session` two-strikes rule stops there. Building the Swift detector would validate
it against a label set that the ground truth's own status field and both reference backends
contradict.

## What is worth keeping

- **`AMLt − CMLt` is a disagreement metric, not a grid-error metric.** It cannot say which
  side is at the wrong level. Anywhere it is read as "the grid is wrong", that is an
  assumption, not a measurement.
- **The `status` field is load-bearing and was not being read.** `confirmed` vs
  `metrical_review` vs `needs_arbitration` separates the catalogue exactly along the axis this
  increment tried to detect.
- **The synthetic re-grid control works** and is reusable: 11/12 on verified bases says the
  method detects a deliberately wrong level, whatever the real labels turn out to be.
- **Level correction is dead on this evidence** (D-210's clause), independently of the label
  question.

## Resolution — Matt, 2026-08-19

> *"I would not trust my tapping on these tracks, especially Bleed."*

So the taps are the unreliable side, and the consequence is stated exactly: **there are
currently ZERO established real wrong-level tracks.** FT.3.1 has no positives to detect and
closes — not because the method failed, but because the thing it was built to find was never
shown to exist.

Note what this does **not** license. Matt distrusting the taps is not the same as the backends
being right; the correct status for money's and bleed's metrical level is **unknown**, pending
re-annotation. Filed as **BUG-101** (P1, `test.groundtruth / dsp.beat`), which carries the list
of contaminated numbers and the fix path. Ground truth changes only through the tap + reconcile
pipeline — no JSON was edited.

The one piece of corroboration worth repeating, because it was already in the repo: **BUG-076's
body states bleed's ~115 BPM is "correct — matches madmom 115.0, librosa 115.0, drums-stem
115.1"** — a third independent source — while `bleed.groundtruth.json` asserts 226.72 and
BeatBench scores bleed against it. Both are live in the repo and cannot both be right.

## Reproduce

```bash
swift run --package-path PhospheneEngine BeatBench --self-test
swift run --package-path PhospheneEngine BeatBench --mode offline-grid
~/phosphene-ml-env/bin/python tools/metrical_level_probe.py \
  --beats-dir /tmp/barprobe --fixtures ~/phosphene_beatbench_fixtures --synthetic
```
