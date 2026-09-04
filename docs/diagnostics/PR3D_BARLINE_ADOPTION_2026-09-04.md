# PR.3d — adopting `UZUME_BARLINE`, and the threshold that had to be re-derived first

**Directive:** Matt, 2026-09-04, "yes, adopt it" — `BarLineEstimator` on by default, after PR.3c
established the live defect is the **meter**, not the metrical level.

**Adoption did not go through unchanged.** Measuring the arm post-BUG-114 showed it would have
shipped a confidently-wrong bar. The threshold was re-derived first; the sequence is below because
the reason matters more than the result.

## 1. Why the threshold moved: 1.24 → 1.54

FT.3 fitted `declineThreshold = 1.24` to margins measured at 22050 Hz. FT.4.1 then A/B'd the arm
through the production analyzer — which, per **BUG-114**, was running the estimator at *half* that
analysis window and producing systematically smaller margins. **FT.4.1's headline result, "answers
2 of 9, both right, zero confident-wrong", was itself a product of that mis-calibration.**

With BUG-114 fixed the margins rise, and one of them rises across the line:

| answered track | margin | meter answered | tapped meter | |
|---|---:|---:|---:|---|
| **bleed** | **1.348** | **3** | **4** | **INCORRECT** |
| take_five | 1.735 | 5 | 5 | correct |
| billie_jean | 2.603 | 4 | 4 | correct |

Adopting at 1.24 would have put a 3-beat bar on a 4/4 track — the precise failure D-207's decline
rule exists to prevent. Re-derived by FT.3's own method (midpoint of the empty interval in the
objective's plateau): the empty interval is **(1.348, 1.735)**, midpoint **1.54**.

**Honest bound: three answers over nine fixtures is a thin basis** — far thinner than FT.3's, whose
empty region spanned (0.226, 2.254). This wants re-deriving whenever the catalogue grows or the
feature front-end moves.

### A measurement trap worth recording

Two instruments disagreed on bleed — BeatBench said it answered meter 3, an early probe said it
declined at 0.518. Neither was buggy: the probe downmixed stereo→mono with `AVAudioConverter` while
BeatBench averages channels manually, **which is what production does** (`AudioDecode.monoFloat32`,
and `SessionTypes`' local-file decode). A different downmix changes the beats, which changes the
features, which moved the margin across the threshold. **A probe that does not decode the way
production decodes is not measuring production.**

## 2. Before / after — all five suites

Both columns post-BUG-114. `t/g` = tapped meter / grid meter; `—` in the grid column is a decline.

| suite | track | meter t/g OFF | meter t/g ON | dbF OFF | dbF ON | F | Cemgil | CMLt | AMLt |
|---|---|---|---|---:|---:|---:|---:|---:|---:|
| 1 | billie_jean | 4/4 | 4/4 | 0.90 | **0.90** | 0.97 | 0.96 | 0.97 | 0.97 |
| 2 | pyramid_song | —/1 | —/— | — | — | 0.52 | 0.37 | 0.75 | 0.75 |
| 2 | solsbury_hill | 7/1 | 7/— | 0.13 | — | 0.97 | 0.95 | 1.00 | 1.00 |
| 2 | **take_five** | 5/**2** | 5/**5** | 0.26 | **0.97** | 0.99 | 0.91 | 1.00 | 1.00 |
| 2 | yyz | —/2 | —/— | 0.15 | — | 0.58 | 0.43 | 0.21 | 0.21 |
| 3 | bohemian_rhapsody | 4/2 | 4/— | 0.25 | — | 0.47 | 0.32 | 0.48 | 0.48 |
| 3 | money | 7/1 | 7/— | 0.21 | — | 0.44 | 0.31 | 0.43 | 0.43 |
| 4 | **bleed** | 4/**4** | 4/**—** | 0.08 | — | 0.99 | 0.96 | 1.00 | 1.00 |
| 5 | clair_de_lune | —/3 | —/— | 0.00 | — | 0.14 | 0.08 | 0.00 | 0.02 |

**The beat layer is byte-identical on all nine tracks** — F, Cemgil, CMLt and AMLt are unchanged in
every row, because the estimator never touches `grid.beats`. Suite-1 no-regression holds exactly.

## 3. What was won and what was paid

**Won.** take_five goes 5/2 → 5/5 with downbeat F **0.26 → 0.97**. Zero confident-wrong answers:
every track that answers is right. Five tracks that were emitting a wrong bar now emit none, and
each was at or below a random bar-1 guess (dbF 0.13 / 0.15 / 0.21 / 0.25 / 0.00).

**Paid, and it is a real loss, not a rounding.** **bleed had the meter RIGHT under OFF** (4/4) and
now declines. What it did not have was the phase — dbF 0.08, effectively a wrong bar-1 on every
bar — so the trade is a correct bar *length* on an arbitrary beat, for nothing. D-207 and D-210
both call that trade the right way round, and it is still a track where we knew something and now
say nothing.

**Against the D-205 ratified gates:**

| suite | gate | before | after |
|---|---|---|---|
| 1 | F ≥ 0.95 offline | 0.97 ✓ | 0.97 ✓ (unchanged) |
| 2 | AMLt ≥ 0.85 **+ meter correct ≥ 3/4** | AMLt 0.75/1.00/1.00/0.21; meter **0/4 correct** | AMLt unchanged; meter **1/4 correct, 3 declined** |
| 3 | deferred | — | — |
| 4 | AMLt ≥ 0.80 | 1.00 ✓ | 1.00 ✓ (unchanged) |
| 5 | confident-wrong ≈ 0 | wrong bar emitted (meter 3) | **declines ✓** |

**Suite 2's meter gate is still not met.** It asks for ≥ 3 of 4 correct; this is 1 correct and 3
honest declines, up from 0 correct. Better than baseline, not a pass — do not read the take_five
win as suite 2 cleared.

## 4. What ships

`UZUME_BARLINE` defaults **on**; `UZUME_BARLINE=0` is the kill switch. Rolling back only restores
wrong bars — the beat layer is unaffected either way.

---

## 5. REVERTED the same day

Matt, 2026-09-04: *"the failure rate here is too high and you should not have recommended it in the
first place."* `UZUME_BARLINE` is back to default-off. Correct call, and the reason is that the
recommendation above was made against the wrong evidence.

**What the recommendation was based on:** nine benchmark fixtures, headlined by take_five's
downbeat F 0.26 → 0.97. **What it was never checked against:** the album Matt had actually reviewed,
which was on disk and had already been analysed in PR.1. Running it there takes five minutes.

## 6. What it does to *Low* — the measurement that should have come first

`LowBarLineProbe`, production-faithful decode, `UZUME_BARLINE=0` vs `=1`:

| track | before | after | |
|---|---|---|---|
| 01 Speed Of Life | 4 ✓ | 4 ✓ | unchanged |
| 02 Breaking Glass | 4 ✓ | 4 ✓ | unchanged |
| **03 What In The World** | **2 ✗** | **4 ✓** | **fixed** |
| 04 Sound And Vision | 4 ✓ | 4 ✓ | unchanged |
| 05 Always Crashing | 4 ✓ | 4 ✓ | unchanged |
| **06 Be My Wife** | **4 ✓** | **decline** | **correct bar LOST** |
| **07 A New Career** | **4 ✓** | **decline** | **correct bar LOST** |
| 08 Warszawa | 3 ✗ | decline | wrong → silent |
| 09 Art Decade | 2 ✗ | decline | wrong → silent |
| 10 Weeping Wall | 2 ✗ | decline | wrong → silent |
| 11 Subterraneans | 3 ✗ | decline | wrong → silent |

**Bar coverage 11/11 → 5/11. One track fixed, two working tracks broken.** Be My Wife is the clean
counterexample: correct meter *and* the tightest phase on the record (28 % of frames outside the
perceptual window, p50 39 ms, best of the eleven). Its bar accents worked, and adoption removed them.

It is not a threshold problem — Be My Wife sits at margin 0.507 and A New Career at 0.766, far below
even the old 1.24. No threshold that keeps zero-confident-wrong on the benchmark recovers them.

**Side benefit of running this: it independently confirms PR.1.** The true OFF meters are
`4,4,2,4,4,4,4,3,2,2,3` — exactly the values Matt's session logged.

## 7. What stays, and the standing rule

**Kept** (both are correct independent of adoption): the **BUG-114** window fix, a genuine defect —
a ported algorithm was running at half its calibrated window — and the **1.24 → 1.54** threshold
re-derivation, which is the correct operating point *given* that fix, and without which any future
adoption would ship bleed's wrong meter 3.

**Reverted:** `UZUME_BARLINE` default-on.

**Standing rule, from this failure:** *a change to what the listener sees is not recommended until
it has been measured on Matt's own material.* Benchmark fixtures gate regressions; they do not
establish that something is an improvement to Uzume. take_five is not on Bowie's *Low*, and leading
with it was measuring the wrong thing and reporting the result as if it were the right one.

## 8. Where bar position actually stands

Neither available option is good enough, and that — not a recommendation — is the finding:

| option | correct bars | wrong bars | silent |
|---|---:|---:|---:|
| shipping (model downbeat head) | 6/11 | **5/11** | 0 |
| estimator, decline to silence | 5/11 | 0 | **6/11** |
| estimator, fall back to head | **7/11** | 4/11 | 0 |

A 45 % wrong-bar rate, a 55 % silence rate, or a 36 % wrong-bar rate. None of these is a feature
worth shipping on, and no threshold move changes that — the failure is upstream, in how bar position
is estimated at all.
