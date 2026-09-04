# PR.3 — the bar-line estimator's analysis window (BUG-114), and two arms that did not ship

**Probe:** `BarLineWindowProbe`, env-gated `UZUME_BARLINE_WINDOW_PROBE=1`. Seven beatbench
fixtures; beats come from the production `DefaultBeatGridAnalyzer` at 44.1 kHz, so only the
estimator's own feature window varies between arms. Threshold `declineThreshold = 1.24`.

**Caveat that bounds every number here: the probe counts ANSWERS, not CORRECT answers.** It has no
downbeat ground truth. Only FT.3's labelled set establishes correctness, and re-deriving the
threshold against it is outstanding work.

## The defect (BUG-114)

`nFFT = 2048` is fixed in samples, so the per-beat window's duration scales with input rate:
92.9 ms at the 22050 Hz FT.3 calibrated on, 46.4 ms at the 44.1 kHz production passed straight
through. `BarLineEstimatorParityTests` calls `estimate(beats:audio:)` on the default
`sampleRate: 22050`, so it proves the port matches Python and says nothing about production.

## All arms, margin per track

| track | legacy @22050 | legacy @44100 (was shipping) | A: resample | B: beat-avg all | A+C: beat-avg chroma only |
|---|---|---|---|---|---|
| billie_jean | 2.840 ✔ | 2.051 ✔ | 2.840 ✔ | **1.204 ✗** | **2.901 ✔** |
| around_the_world | 1.265 ✔ | **0.147 ✗** | **1.265 ✔** | 3.512 ✔ | 1.913 ✔ |
| dance_yrself_clean | 3.859 ✔ | 3.127 ✔ | 3.859 ✔ | 3.547 ✔ | **3.980 ✔** |
| bohemian_rhapsody | 0.397 ✗ | 0.361 ✗ | 0.396 ✗ | 0.850 ✗ | 0.642 ✗ |
| clair_de_lune | 0.225 ✗ | −0.052 ✗ | 0.225 ✗ | 0.436 ✗ | 0.224 ✗ |
| bleed | 0.518 ✗ | 0.645 ✗ | 0.518 ✗ | 0.418 ✗ | 0.204 ✗ |
| girl_from_ipanema | −0.190 ✗ | −0.432 ✗ | −0.190 ✗ | −0.554 ✗ | −0.213 ✗ |
| **answered** | 3 | **2** | **3** | 2 | 3 |

## What shipped, and what did not

**Arm A — resample to the reference rate. SHIPPED.** Every margin returns to its calibrated value
(bit-comparable to the 22050 column), around_the_world crosses back from decline to answer, and
nothing is lost. Justified independently of the answer count: a ported algorithm should run at the
window its threshold was derived on.

**Arm B — average the spectrum across the whole inter-beat interval. NOT SHIPPED.** The hypothesis
was that `harmonic_change` is starved by a 46 ms window on a ~500 ms beat, and it is *half* right:
around_the_world gains 0.147 → 3.512 and bohemian_rhapsody 0.361 → 0.850. But billie_jean **loses**
its answer, 2.051 → 1.204, and bleed and girl_from_ipanema get worse. Averaging over the beat
dilutes the transient that `low_energy` / `rms` / `flux` depend on. Net answers: 2, worse than A.

**Arm C — average the chroma only, transient features on the attack frame. NOT SHIPPED.** The
refinement Arm B's split implies, and it behaves as predicted: every answered track strengthens
(billie_jean 2.901, dance 3.980, both the best of any arm) with no losses. But it **converts no
decline that A does not already convert** — 3 answers, same as A alone. Kept behind
`BarLineEstimator.Options.beatAveragedChromaOnly` for whoever picks this up with a labelled set.

**The finding worth keeping:** the four features have different natural windows. Harmony wants the
beat; the attack features want the attack. Arm C is the shape of that, and it is measurably better
on margin — it just has not been shown to buy an answer.

## What is still not fixed

bleed, bohemian_rhapsody, clair_de_lune and girl_from_ipanema decline at every window tested. bleed
and bohemian_rhapsody are D-210's wrong-metrical-level cases, where bar phase is unrecoverable
regardless of the feature front-end. **The objective Matt set — "the correct downbeat is
identified" — is not met by this increment.** It removes a mis-calibration and recovers one track
of seven. The next honest step is a labelled re-derivation of `declineThreshold` on the corrected
distribution, which needs ground-truth downbeats the probe does not have.
