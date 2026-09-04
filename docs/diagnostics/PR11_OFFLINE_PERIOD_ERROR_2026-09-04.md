# PR.11 — the offline period error is NOT recoverable, and the reason names the instrument

**Question (Matt, 2026-09-04):** *"measure whether the offline period error is recoverable. figure
out how to close the gap on BUG-065."*

**Answer: not recoverable offline. The period error being chased is 10–100× SMALLER than the
precision of any offline tempo estimator we have.** The negative result is decisive and the reason
generalises, so it also says what *would* work.

## 1. The physics being tested

If the cached grid's period `P_g` differs from the track's true period `P_t`, phase error accumulates
linearly:

    drift_rate (ms/s) = 1000 × (P_g/P_t − 1) = 1000 × (BPM_t/BPM_g − 1)

PR.1 measured exactly that shape on Bowie's *Low*: a linear ramp on **11 of 13 segments**, R²
0.63–0.91, both signs, implying a constant **0.04–0.20 %** period error. So the mechanism is not in
doubt. The question is whether a better offline estimate of `P_t` can null it.

D-206 parked **online phase tracking** (a PI controller fed per-onset evidence, where 75–85 % of
onsets are off-beat). It said nothing about **offline period refinement**, which has a different
evidence layer and which the local-file path can afford because it holds the whole track at
preparation time. That is the gap this probe tests.

## 2. A measurement error caught by the cross-check

The first run reported predicted drifts of 8–28 ms/s against PR.1's measured 0.08–2.0 ms/s — two
orders out. The fault was the estimator, not the physics: BPM was taken from the **median
inter-beat interval**, and Beat This! emits beats on a 50 fps grid, so every IBI is quantised to
20 ms and the median can only land on discrete values (115.38 BPM is exactly 26 frames). At ~117 BPM
that quantisation is **±3.9 %** — it swamps the 0.04–0.20 % being measured.

Replaced with a least-squares fit of beat time against beat index over the longest clean run, which
averages the quantisation away. **The cross-check against an independently measured quantity is what
exposed it**; internal consistency would not have.

## 3. Ground-truthed fixtures — multi-window helps, conditionally

Production takes one decode; "multi" is the median of five independent 30 s decodes at 0/20/40/60/80 %
through the track (**not** the FT.4.1 tiler — each window is a separate clean predict, so it cannot
inherit the tiler's beat regression).

| track | status | truth BPM | prod err | multi err | window spread |
|---|---|---:|---:|---:|---:|
| billie_jean | confirmed | 117.15 | +0.18 % | **+0.05 %** | 0.37 % |
| bleed | confirmed | 115.00 | −0.03 % | −0.03 % | **239.8 %** |
| solsbury_hill | confirmed | 102.46 | +0.05 % | +0.05 % | 0.38 % |
| take_five | confirmed | 172.27 | +1.75 % | **−0.76 %** | 5.39 % |
| money | arbitrated | 121.61 | +2.65 % | **−3.84 %** | 15.2 % |
| pyramid_song | metrical_review | 65.55 | **+0.07 %** | **−4.86 %** | 66.2 % |

Read narrowly this looks like a win — billie_jean 0.18 → 0.05, take_five 1.75 → 0.76. But it makes
**pyramid_song 70× worse** and flips money's sign without improving it. The discriminator is the
window spread: where windows agree the median is safe, where they disagree it is noise. That is
BUG-076's window-position instability, now quantified across the catalogue.

## 4. The decisive test — and it fails

Ground truth cannot say whether correcting the period nulls the *drift*, because drift is a live
quantity. So the prediction was tested against PR.1's **independently measured** per-track ramp
slopes on *Low*. If the ramp is a recoverable constant period error, a better offline period must
differ from production's by that fraction, in that direction.

| track | predicted ms/s | measured ms/s | |
|---|---:|---:|---|
| 01 Speed Of Life | +28.93 | −0.697 | sign wrong |
| 02 Breaking Glass | +3.95 | −1.382 | sign wrong |
| 03 What In The World | −6.72 | −0.852 | sign ok, 8× |
| 04 Sound And Vision | +1.20 | −1.073 | sign wrong |
| 05 Always Crashing | +20.09 | +0.626 | sign ok, 32× |
| 06 Be My Wife | +22.54 | −0.437 | sign wrong |
| 07 A New Career | +5.66 | +0.357 | sign ok, 16× |
| 08 Warszawa | +366.18 | +0.529 | sign ok, 692× |
| 09 Art Decade | 0.00 | +0.708 | predicts nothing |
| 10 Weeping Wall | −1.06 | −0.082 | sign ok, 13× |
| 11 Subterraneans | +6.47 | +0.142 | sign ok, 46× |

**Sign agrees on 6 of 11 — chance. Magnitudes are 8–690× too large.** The offline estimate does not
predict the measured drift, so it cannot correct it.

## 5. Why it fails, and what that means

The window-to-window scatter of the offline tempo estimator is **0.14–99.9 %**, and ~0.5–4 % even on
stable tracks. The period error being chased is **0.04–0.20 %**. *The signal is one to two orders of
magnitude below the instrument's noise floor.* No amount of window averaging fixes that: the
disagreement between windows is not quantisation noise (the within-window regression over ~58 beats
resolves ~0.02 %) but genuine content-dependent variation in what the model calls the tempo.

**The instrument that CAN see 0.1 % is the drift measurement itself.** It integrates the error over
minutes — 0.1 % across 300 s is 300 ms of accumulated signal, far above noise, which is exactly why
PR.1's ramps come out at R² 0.91. Any approach that estimates tempo from 30 s of audio is working
with a 10–100× worse instrument than the one already running.

That reframes BUG-065: **the system already measures the period error more precisely than it can
estimate it.** The gap is not in measurement, it is that nothing consumes the measurement — TRK.1
tried, with an online per-onset PI controller, and D-206 killed that on the onset evidence layer. A
batch fit of the accumulated drift is a different estimator from an online integrator in the way a
regression differs from a running sum, and this probe did not test it.

**No mechanism is proposed here.** Two levers have already failed on this defect, the beat-sync
two-strikes rule applies, and a third attempt needs Matt's sign-off on a changed premise. What is
established is narrower and firmer: *offline period refinement is dead, for a measured reason.*

## 6. Honest bounds

Nine fixtures (four with confirmed truth) and eleven *Low* tracks. The *Low* half has no ground
truth — the measured ramp is the reference, which is legitimate for testing a prediction but cannot
establish the true tempo. Warszawa's 28 % and Weeping Wall's 99.9 % window spread mean their rows
carry almost no information either way.
