# The downbeat question — what the corrected references made visible (2026-08-27, PLAN.1)

BUG-102's resolution made the benchmark citable again, and the first thing it showed is that
**downbeats are the weak layer**, not beats. This is the survey; it proposes no fix.

## The measurement

| track | truth meter | grid meter | downbeat F | what it means |
|---|---|---|---|---|
| billie_jean | 4 | 4 | **0.90** | working |
| bleed | 4 | 4 | **0.08** | meter right, bar phase wrong — *worse than the ~0.25 a random guess scores on 4/4* |
| money | 7 | **1** | 0.21 | meter collapsed |
| solsbury_hill | 7 | **1** | 0.13 | meter collapsed |
| take_five | 5 | **2** | 0.26 | meter collapsed |
| bohemian_rhapsody | 4 | **2** | 0.25 | meter collapsed |

Beat F on the same tracks is 0.97–0.99 where the grid is trusted. **The beats are fine; the bars
are not.**

## Why: the downbeat head over-fires

Added to `BeatBench --audio` (diagnostic only, no behaviour change) because a low downbeat F is
ambiguous without it — too few downbeats and a wrong bar phase score identically:

| track | beats | downbeats emitted | bars actually implied | barConfidence |
|---|---|---|---|---|
| bleed | 58 | **19** | ~14 (58 ÷ 4) | 0.50 |
| money | 51 | **40** | ~7 (51 ÷ 7) | 0.77 |

On money the downbeat head fires on **78 % of beats**. `computeMeter` then takes
`round(median_downbeat_IOI / beat_period)` and gets **1** — the meter collapse is a direct
consequence of the over-firing, not a separate bug.

`BeatGridResolver.peakPick` is a faithful port of the reference postprocessing (`sigmoid > 0.5`
AND local max over 7 frames, then dedup), verified against its own doc comment. **This is the
model's raw output, correctly post-processed** — not a Phosphene defect.

## This confirms the program's existing diagnosis rather than adding to it

Four independent levers have already failed to get bar position out of this activation stream —
TRK.2 (different onset source), DBN.2 (unbiased decoder), MDL.1 (10× checkpoint), FT.1 (13–25×
context). The over-firing measured here is *why*. **Do not propose a fifth lever on the same
stream** (`beat-sync-session` dead-end map).

FT.3's answer was to bypass the stream: score beat-synchronous accent features at already-known
beat times (`BarLineEstimator`, ported at FT.3 tasks 4–6, parity 1.6e-7, **built and not wired**).

## The decision this leaves — and it is a product call, not an engineering one

From `FT3_BARLINE_PORT_2026-08-19.md`: at its calibrated threshold of 1.24 the estimator
**answers 2 of the 9 ground-truthed tracks, gets both right, and declines the other 7**. The
threshold is that high because, labelled by *bar* rather than by *meter*, correct and incorrect
margins overlap — the same wall DBN.2 hit.

So the choice is between two failure modes, not between broken and fixed:

- **Today:** every track gets a bar position, and on 5 of 6 surveyed tracks it is wrong. Nacre's
  and Glaze's downbeat pushes fire on the wrong beat.
- **Wired with decline:** ~2 in 9 tracks get a correct bar; the rest get none, and presets fall
  back to their no-bar path.

The program has already ratified the principle that decides this, for suite 5: *"a confident
beat that is wrong is worse than declining to beat"* — success there is defined as **declining
honestly**. D-205 applies the same logic to meter/downbeat by making it a hard gate precisely
because certified presets consume bar position.

**Not decided here.** Whether to wire it is DBN.3's satisfied-but-unresolved gate and belongs to
Matt. If wired: behind an env flag with a one-increment A/B path (plan §4), and with a five-suite
before/after BeatBench table (benchmark obligation).

## Scope caveat

Every number above is over the grid's ~30 s window (BUG-107 / BUG107.2 — the offline grid only
ever analyses the first ~30 s of any input). FT.3's own A/B used FT.1's full-track tiler instead,
so its 2-of-9 figure is not measured on the same footing as this table.
