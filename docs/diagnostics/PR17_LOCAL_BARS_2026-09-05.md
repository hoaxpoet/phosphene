# PR.17 — bar position recorded per window, not averaged into one answer per track

**Date:** 2026-09-05
**Increment:** PR.17 (Phase PR)
**Matt's instruction:** *"Proceed with the BeatGrid work after the merge."* — and, asked to choose
between sparse-and-correct and dense-with-fallback bars, **"Sparse and correct."**

---

## 1. What changed

`BarLineEstimator.estimateWindowed` scores bar position once per ~80 beats (~40 s) instead of once
per track, and emits downbeats **only from windows that answer**. A declined window emits nothing —
it is never backfilled from the model's downbeat head.

That is the same correction PR.12 made to tempo, applied to the bar. Matt's words on tempo were
*"you should not be averaging BPM / tempo, you should be recording it over the duration of the
track"*. A single global meter-and-phase has to describe an intro, a chorus and an outro at once,
and PR.15 measured that it is worse at it than the old 30 s clip was.

Wired behind `UZUME_BARLINE_LOCAL=1`, default **off**, per the program's env-flag house rule.

---

## 2. The reversal this represents, stated plainly

FT.2's wiring of `BarLineEstimator` was **rejected on product grounds on 2026-09-04** (Matt: *"B is
not a viable option and I don't know why you would even suggest it"*), and the plan records *"do not
re-propose wiring; revisit only with a materially lower decline rate."* PR.3d then tried default-on
and was reverted the same day (*"the failure rate here is too high"*).

Two things changed since:

1. **The decline rate was an artifact of the input, not the music.** Every one of those measurements
   fed the estimator ~40–60 beats from a 30 s clamped grid when its own documentation specifies a
   full-track grid of 300–700. PR.12 removed the clamp.
2. **The output shape was wrong.** One answer per track is all-or-nothing; a track either gets bars
   everywhere or nowhere. Per window, a track can have bars through the sections where the evidence
   carries them.

This is not a re-proposal of the rejected thing. It is a different output shape measured on Matt's
own material first, which is what PR.3d's standing rule requires.

---

## 3. Bowie's *Low* — the album the review was made against

Whole-track grid (post-PR.12). `head` = today's shipped behaviour, the model's downbeat head.
`global` = one estimate per track. `windowed` = this change.

| track | head | global | windowed | cover | verdict |
|---|---|---|---|---|---|
| 01 Speed Of Life | 4 ✓ | 4 | 2/3 → 4 ✓ | 75 % | kept |
| 02 Breaking Glass | 2 ✗ | 4 | 0/2 → silent | 0 % | wrong bar removed |
| 03 What In The World | 2 ✗ | decline | 1/3 → 4 ✓ | 27 % | **fixed** |
| 04 Sound And Vision | 4 ✓ | 4 | 4/4 → 4 ✓ | 100 % | kept |
| 05 Always Crashing | 4 ✓ | 4 | 1/4 → 4 ✓ | 31 % | kept, sparser |
| 06 Be My Wife | 4 ✓ | decline | 0/4 → silent | 0 % | **correct bar LOST** |
| 07 A New Career | 4 ✓ | 4 | 2/4 → 4 ✓ | 55 % | kept |
| 08 Warszawa | 4 ✗ | decline | 0/5 → silent | 0 % | wrong bar removed |
| 09 Art Decade | 4 ? | 4 | 3/3 → 4 ? | 100 % | unresolved (see below) |
| 10 Weeping Wall | 1 (collapsed) | decline | 0/7 → silent | 0 % | collapse removed |
| 11 Subterraneans | 3 ✗ | decline | 0/4 → silent | 0 % | wrong bar removed |

**Head: 5 correct, 5 wrong, 1 collapsed. Windowed: 5 correct, 0 wrong, 1 unresolved, 5 silent.**

The trade is one-for-one at the top line and better underneath: windowed swaps Be My Wife (correct,
now silent) for What In The World (wrong, now correct), and removes every wrong bar on the record.

**Two honest caveats.**

- **Be My Wife is a real loss.** PR.3d measured it as the clean counterexample: correct meter *and*
  the tightest phase on the album (p50 39 ms, 28 % of frames outside the perceptual window). Its bar
  accents work today and this change removes them. It is not a threshold problem — no threshold that
  keeps zero-confident-wrong on the benchmark recovers it.
- **Art Decade is unresolved, not a win.** It is an ambient instrumental; PR.3d marked the head's
  answer there as wrong on the grounds that the side-two pieces have no meaningful bar. Windowed
  answers 4 on 3 of 3 windows. Whether that is a real slow 4 or a confident-wrong is a question for
  Matt's ears, not for this table.

---

## 4. Ground-truthed fixtures — the shipped function, not a probe reimplementation

`estimateWindowed` run directly on every ground-truthed fixture, whole-track grid, threshold 1.54.

| track | tapped | global | windowed | cover | answers |
|---|---|---|---|---|---|
| billie_jean | 4 | 4 | 6/7 | 84 % | 4,4,4,4,4,4 |
| bleed | 4 | decline | 0/12 | 0 % | — |
| bohemian_rhapsody | 4 | decline | 1/6 | 15 % | 4 |
| clair_de_lune | — | decline | 0/4 | 0 % | — |
| money | 7 | decline | 2/10 | 20 % | 7,7 |
| pyramid_song | — | decline | 0/5 | 0 % | — |
| solsbury_hill | 7 | decline | 0/5 | 0 % | — |
| take_five | 5 | decline | 11/11 | 100 % | 5,5,5,5,5,5,5,5,5,5,5 |
| yyz | — | 4 | 4/8 | 51 % | 4,4,4,4 |

**20 correct, 0 incorrect, 4 unscoreable, 44 declined.** The four unscoreable are yyz, whose ground
truth records *"no clean meter; unresolved"* — its four 4s are very likely right and are counted
neither way rather than scored as failures.

Two results carry the programme:

- **money answers 7.** Four separate levers failed on this track (TRK.2, DBN.2, MDL.1, FT.1) and
  D-210 recorded it as the wrong-metrical-level dead end. It answers correctly, twice, per window.
- **take_five answers 5 on 11 of 11 windows** — total coverage on a 5/4 track.

And the two that decline are the right ones to decline: **clair_de_lune** (true rubato; suite 5's
whole point is that declining honestly beats a confident wrong beat) and **pyramid_song** (meter
recorded as undetermined; Matt's own downbeat pass was rejected as unfindable by ear).

**solsbury_hill is the miss** — tapped 7, silent on all 5 windows. Missed, not wrong.

---

## 5. BeatBench — five suites, both arms over identical spans

Both arms decode the whole track (`UZUME_FULLTRACK_DECODE=1`), so this does **not** repeat the
span-trimming artifact PR.12 exposed: the reference is trimmed to the same span on both sides.

- **A (baseline):** full-track decode, bars from the model's downbeat head — today's shipped local behaviour.
- **B:** full-track decode, bars from the windowed estimator — `UZUME_BARLINE_LOCAL=1`.

| suite | track | beat F | Cemgil | CMLt | AMLt | meter A | meter B | **dbF A** | **dbF B** |
|---|---|---|---|---|---|---|---|---|---|
| 1 | billie_jean | 0.99 | 0.96 | 0.97 | 0.97 | 4 | 4 | 0.37 | **0.43** |
| 2 | pyramid_song | 0.22 | 0.17 | 0.21 | 0.21 | 2 | 1 | — | — |
| 2 | solsbury_hill | 0.98 | 0.96 | 0.94 | 0.94 | 1 | 1 | 0.15 | — |
| 2 | take_five | 1.00 | 0.93 | 1.00 | 1.00 | 1 | **5** | 0.34 | **0.89** |
| 2 | yyz | 0.41 | 0.31 | 0.05 | 0.19 | 4 | 4 | 0.14 | **0.15** |
| 3 | bohemian_rhapsody | 0.52 | 0.41 | 0.36 | 0.36 | 4 | 4 | 0.29 | **0.47** |
| 3 | money | 0.24 | 0.18 | 0.17 | 0.17 | 1 | **7** | 0.08 | **0.53** |
| 4 | bleed | 0.76 | 0.68 | 0.56 | 0.56 | 2 | 1 | 0.09 | — |
| 5 | clair_de_lune | 0.06 | 0.04 | 0.01 | 0.03 | 1 | 1 | 0.00 | — |

**Beat F, Cemgil, CMLt and AMLt are identical in both arms on every track.** Beats are never
touched — only `downbeats`, `beatsPerBar` and `barConfidence` change. Suite-1 no-regression holds
by construction, not by luck.

**Downbeat F improves on every track that keeps bars** (5 of 5), and the two odd meters the
programme was built around are decoded for the first time: **take_five 1 → 5** and **money 1 → 7**.
Mean downbeat F over the eight scoreable tracks, counting a silent track as 0.00:
**0.18 → 0.31**.

**Reported as the claim rules require:** three tracks lose their downbeats entirely — solsbury_hill
(0.15 → silent), bleed (0.09 → silent), clair_de_lune (0.00 → silent). All three were scoring at or
near zero, so nothing that worked was lost; but solsbury_hill is a genuine 7/4 miss, and it is a
miss, not a decline that was unavoidable. Clair de Lune emitting no downbeats at all is suite 5's
stated target rather than a loss.

---

## 6. What it costs to run

**0.89 s/track**, measured over *Low*'s eleven files (9.7 s total) — the estimator alone, excluding
the grid inference it reads. D-242 puts **all** of preparation on a 7.5 s/track budget, so this one
stage is ~12 % of the whole budget, and it is net-new: today's downbeat head is free, being a second
output of an inference that already runs.

Nearly all of it is the front-end, not the windowing — the whole file is resampled to 22050 Hz and
an STFT runs at every beat. A global `estimate` costs about the same, so scoring per window is not
what makes it expensive. Not optimised here; flagged because PREP is actively working that budget.

---

## 6. Recommendation

**Adopt on the local path** — `barLineLocal` default-on wherever the grid is whole-track — and leave
the streaming path alone, where a 30 s grid is one short window and the estimator would only decline.

What Matt sees if it goes on: on *Low*, bar-locked motion becomes correct wherever it appears and
disappears on five of eleven tracks, including Be My Wife, where it currently works. On the
odd-meter material the programme has failed on for months, bars appear for the first time.

**This is a default that changes what he sees, so it is his call, and the code ships flag-gated
until he makes it** (PR.3d's standing rule: a change to what the listener sees is not recommended
until measured on Matt's own material — that measurement is §3, and it is what this recommendation
rests on).

**Not yet established:** no live M7. Every number here is offline. Whether sparse bars read as
*responsive* or as *flickering* when a bar accent stops mid-song is a felt question that only
playback answers.
