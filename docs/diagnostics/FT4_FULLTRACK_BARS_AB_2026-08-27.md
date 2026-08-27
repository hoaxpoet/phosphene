# FT.4 — full-track decode + `BarLineEstimator`, A/B'd behind `PHOSPHENE_FULLTRACK_BARS`

**Verdict: DO NOT ADOPT as built.** Matt approved wiring it (2026-08-27) on the strength of
FT.3's "answers 2 of 9, gets both right, declines 7". Measured end-to-end through the real
analyzer, it does not reproduce that: it regresses the layer that works and, on the one track it
most needed to leave alone, answers confidently and wrongly.

The flag defaults **OFF**, so nothing ships. This is attempt 1 on this premise
(`beat-sync-session` two-strikes rule) — **no second attempt without a changed premise.**

## What the arm does

- **OFF:** one `predict` over a fixed 1500-frame (~30 s) window; bar position from the model's
  downbeat head.
- **ON:** FT.1's `BeatThisTiledInference.predictFullTrack` decodes the whole track; bar position
  from FT.3's `BarLineEstimator`, which scores beat-synchronous accent features at known beat
  times. Declines are carried as `beatsPerBar = 1` + empty downbeats.

## Only four tracks can be compared fairly

`BeatBench` trims the *reference* to the grid's span but not the estimate to the reference's.
That is right when the grid is a 30 s preview and the taps cover more — it is wrong here, where
the ON arm's grid spans the whole track and five ground truths do not. FT.3's report flagged the
same asymmetry. So the five short-GT tracks (money, pyramid_song, yyz, bohemian_rhapsody,
clair_de_lune) are **excluded** — their ON-arm numbers are dominated by false positives for beats
the estimator was never shown.

| track | GT span | truth BPM | grid OFF | grid ON | F OFF→ON | CMLt OFF→ON | dbF OFF→ON |
|---|---|---|---|---|---|---|---|
| take_five | 0–327 s | 167.07 | 169.24 | 171.44 | 0.99 → **1.00** | 1.00 → 1.00 | 0.26 → **0.68** |
| billie_jean | 1–286 s | 117.44 | 116.88 | 117.13 | 0.97 → 0.99 | 0.97 → 0.97 | **0.90 → 0.37** |
| solsbury_hill | 0–261 s | 102.44 | 102.68 | 104.80 | 0.97 → 0.98 | 1.00 → 0.94 | 0.13 → declined |
| bleed | 0–442 s | 114.67 | **115.00** | **123.62** | **0.99 → 0.76** | **1.00 → 0.56** | 0.08 → declined |

## Two independent failures, either of which is disqualifying

**1. The estimator answered confidently and WRONGLY on billie_jean — suite 1.** It returned 4/4,
which is correct, on the wrong bar phase, taking downbeat F from **0.90 to 0.37**. billie_jean is
the reference working case and suite-1 no-regression is a stated hard gate. **This is exactly the
failure the decline threshold exists to prevent, and the threshold did not catch it.** FT.3's own
task-5 finding predicted the mechanism: labelled by *bar* rather than by *meter*, correct and
incorrect margins overlap. A margin that clears 1.24 is not evidence the phase is right.

**2. FT.1's tiler degrades beat tracking.** On bleed — full-length ground truth, the cleanest
comparison in the set — the grid moves **115.00 → 123.62** against a truth of 114.67, and F falls
0.99 → 0.76 with CMLt 1.00 → 0.56. That is the beat layer, which was the one thing working
(F 0.97–0.99 across the trusted grids). It is consistent with FT.1's own negative result rather
than a surprise.

## The one real win, recorded

**take_five: meter 5/2 → 5/5 and downbeat F 0.26 → 0.68.** The accent-based method genuinely
recovers an odd meter the downbeat head collapses. The mechanism is not worthless — it is
mis-thresholded and it is riding on a decode that costs more than it returns.

## What a changed premise would have to address

Not proposals, just what the evidence says any next attempt must handle:

- **The decline threshold cannot separate right phase from wrong phase.** It was calibrated on
  margin, and billie_jean shows margin clearing while phase is wrong. A phase-aware confidence,
  or a decline that abstains unless phase is independently corroborated, is the gap.
- **Full-track decode and bar estimation are separable and should be separated.** The estimator's
  win on take_five and the tiler's loss on bleed are independent; bundling them means one cannot
  be adopted without the other. `BarLineEstimator` accepts any `beats` array.
- **The benchmark's asymmetric trimming needs fixing before any full-track arm is scored again**,
  or five of nine tracks stay unmeasurable and every future A/B repeats this exclusion.

## Kept, not deleted

The wiring stays behind `PHOSPHENE_FULLTRACK_BARS` (default OFF, no shipped behaviour change).
It is the sanctioned one-increment A/B path (plan §4), and it makes re-running this measurement
after any of the above a single command rather than a re-implementation.

---

# FT.4.1 — the estimator alone, on the existing 30 s beats

Matt's call after the FT.4 result: isolate the two halves. The flag is split —
`PHOSPHENE_FULLTRACK_DECODE` (tiler) and `PHOSPHENE_BARLINE` (estimator) are now independent;
`PHOSPHENE_FULLTRACK_BARS` still sets both so the FT.4 arm stays reproducible.

**Verdict: ADOPT the estimator. Do not adopt the tiler.** Every failure in FT.4 belonged to the
tiler; every win belonged to the estimator, and unbundling recovers the wins at zero cost to the
beat layer.

## Arm C — `PHOSPHENE_BARLINE=1`, beats unchanged

| track | beat F OFF→C | CMLt OFF→C | meter t/g OFF→C | downbeat F OFF→C |
|---|---|---|---|---|
| billie_jean | 0.97 → **0.97** | 0.97 → 0.97 | 4/4 → 4/4 | **0.90 → 0.90** |
| take_five | 0.99 → **0.99** | 1.00 → 1.00 | 5/**2** → 5/**5** | **0.26 → 0.97** |
| solsbury_hill | 0.97 → **0.97** | 1.00 → 1.00 | 7/1 → 7/1 | 0.13 → declined |
| bleed | 0.99 → **0.99** | 1.00 → 1.00 | 4/4 → 4/1 | 0.08 → declined |
| money | 0.44 → **0.44** | 0.43 → 0.43 | 7/1 → 7/1 | 0.21 → declined |
| pyramid_song | 0.52 → **0.52** | 0.75 → 0.75 | —/1 → —/1 | — |
| yyz | 0.58 → **0.58** | 0.21 → 0.21 | —/2 → —/1 | 0.15 → declined |
| bohemian_rhapsody | 0.47 → **0.47** | 0.48 → 0.48 | 4/2 → 4/1 | 0.25 → declined |
| clair_de_lune | 0.14 → **0.14** | 0.00 → 0.00 | —/3 → —/1 | 0.00 → declined |

**Every beat-layer figure is identical to OFF, on all nine tracks** — F, Cemgil, CMLt, AMLt. The
estimator never touches `grid.beats`, and without the tiler nothing else does either. Suite-1
no-regression holds exactly, not approximately.

## It reproduces FT.3's figure that the bundled arm destroyed

**Answers 2 of 9, gets both right, declines 7.**

- **take_five** — meter 5/**2** → 5/**5**, downbeat F 0.26 → **0.97**. The odd meter the downbeat
  head collapses is recovered, near-perfectly. Better than the tiled arm's 0.68.
- **billie_jean** — answers 4/4 on the right phase, **downbeat F 0.90 preserved**. In the bundled
  arm this same estimator answered wrongly here and dropped it to 0.37. **That failure was the
  tiler moving the beats underneath it, not a mis-calibrated threshold.** FT.4's first
  disqualifying finding is therefore withdrawn: the threshold was not the problem.

## What the 7 declines actually cost

They replace a *wrong* bar with *no* bar. The declined tracks had downbeat F of 0.08–0.26 — at or
below what a random bar-1 guess scores — so nothing of value is lost. One honest caveat: on bleed
and bohemian_rhapsody the OFF arm had the **meter** right (4) while the phase was wrong, and a
decline gives up the meter too. For a consumer needing only `beatsPerBar` and not phase, that is a
small regression. D-205 makes bar *position* the hard gate because Nacre's and Glaze's downbeat
pushes consume phase, so the trade is the right way round — but it is a trade, not a free win.

## Consequence for the tiler and for BUG-107

The tiler stays unwired and unadopted: on bleed it moved the grid 115.00 → 123.62 against a truth
of 114.67. That is a separate finding from BUG-107's ~30 s cap — **more context is available and
measurably makes beat tracking worse**, so BUG-107 should not be "fixed" by switching the decode
on. Any future attempt owns that number first.
