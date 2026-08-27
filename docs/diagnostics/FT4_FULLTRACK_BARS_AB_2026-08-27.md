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
