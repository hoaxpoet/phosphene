# DBN decoder spec — bar-pointer decoding over Beat This! activations

**Increment:** DBN.1 (beat-sync program, D-202) · **Status:** spec only, no decoder code exists
**Date:** 2026-07-30 · Implements: DBN.2 · Wires in: DBN.3 · Generalises `BeatGrid`: DBN.4

This document specifies a bar-pointer-model decoder that replaces `BeatGridResolver`'s
independent peak-picking with a jointly-decoded metrical path. Every constant below is either
cited to a paper equation or explicitly marked as a Phosphene tunable with a default.

---

## 0. License gate (checked before any reference was read to port)

| Source | License | May it inform code? |
|---|---|---|
| Krebs, Böck & Widmer, *An Efficient State-Space Model for Joint Tempo and Meter Tracking*, ISMIR 2015 | **CC BY 4.0** (stated on the paper's first page) | **Yes** — implement from the paper with attribution. This is the primary source. |
| Böck, Krebs & Widmer, *A Multi-model Approach to Beat Tracking Considering Heterogeneous Music Styles*, ISMIR 2014 | ISMIR proceedings paper | **Yes** — implement the published equations with attribution. Source of the observation model. |
| Foscarin, Schlüter & Widmer, *Beat this! Accurate beat tracking without DBN postprocessing*, ISMIR 2024 (arXiv 2407.21658) | arXiv preprint | **Yes** — already Phosphene's grid model (MIT, D-077). Used here for its DBN A/B evidence. |
| madmom implementation | Restricted; CC-NC model weights | **No.** Offline annotation tool only, per `reference-port` §1 and the precedent already recorded in `tools/beatbench/README.md`. No madmom code is read to port; no madmom weights ship. |

Clean-room from the papers. Nothing in DBN.2 may be derived by reading madmom source.

---

## 1. What the decoder must fix — stated in baseline numbers

From `docs/diagnostics/BEATBENCH_BASELINE_2026-07-30.md` and the targets ratified as D-205:

| axis | baseline | target | verdict |
|---|---|---|---|
| suite-1 beat F | **0.97** | ≥ 0.95 | already met — **must not regress** |
| suite-2 beats (AMLt) | 1.00 / 1.00 / 0.88 / 0.75 / 0.21 | ≥ 0.85 | 3 of 5 pass — **must not regress** |
| **`beatsPerBar`** | correct on **2 of 9** | ≥ 3/4 on suite 2 | **the work** |
| **downbeat F** | **0.13–0.26**, except billie_jean 0.90 | (implied by meter gate) | **the work** |

The grid reads meter **1 or 2 on eight of nine tracks** (money 7→1, solsbury_hill 7→1,
take_five 5→2, bohemian 4→2, yyz →2, clair_de_lune →3). Every design choice below traces to
one of those two bolded rows. **Beat times are not the target** — D-205 says it directly: "the
program's §1 targets led with beat F — the axis that was mostly already working."

---

## 2. The premise, tested against the model's own authors

Beat This! is titled *"Accurate beat tracking **without** DBN postprocessing"*. Its authors
measured a DBN on top of the same model we ship, on GTZAN (§Table 2):

| | beat F1 | downbeat F1 | CMLt downbeat |
|---|---|---|---|
| minimal post-processing | **89.1 ± 0.3** | **78.3 ± 0.4** | 67.3 |
| with DBN | 88.1 ± 0.3 | 77.4 ± 0.2 | **73.3** |

**A DBN made their F1 worse.** It helped only continuity, and they explain why in one sentence:
"Using a DBN increases our CMLt downbeat performance by correcting some of the (wrongly)
non-periodic outputs."

That sentence is the whole justification for this increment, and it is narrower than the program
plan assumed. The DBN's one measured benefit is repairing **non-periodic downbeat output** — and
DBN.1's task-7 measurement shows that is exactly, and only, our failure mode.

### 2.1 Task-7 measurement — where the downbeat signal actually dies

`DownbeatStreamDiagnosticTests` (env-gated, `PHOSPHENE_DBN1_DOWNBEAT=1`) peak-picks the model's
raw beat and downbeat streams with the reference's own rule (±3-frame max-pool, prob > 0.5):

| track | truth meter | downbeat:beat ratio | mean peak prob | median downbeat gap | → `beatsPerBar` |
|---|---|---|---|---|---|
| billie_jean | 4 | 0.24 | 1.000 | 3.92 beats | **4** ✓ |
| money | 7 | **0.90** | 0.805 | 1.00 beats | 1 ✗ |
| solsbury_hill | 7 | **0.69** | 0.866 | 1.03 beats | 1 ✗ |
| take_five | 5 | 0.41 | 0.883 | 2.00 beats | 2 ✗ |

**Two hypotheses were killed by this measurement, and both deserve recording.**

1. *"The resolver's ±40 ms downbeat-snap gate discards downbeats the reference keeps."*
   `BeatGridResolver.snapToBeats` does diverge from the reference — Beat This! moves **all**
   downbeats to the closest beat unconditionally, while we drop any beyond 40 ms. But the
   measurement shows **100 % of candidates survive the gate** (median distance 0.0 ms). The
   divergence is real and worth fixing for correctness, but it explains none of the defect.
2. *"Too few downbeats survive, inflating the median IOI."* The opposite is true: on the failing
   tracks the model emits a **confident downbeat on 69–90 % of beats**.

So the signal does not die in post-processing. **The model's downbeat stream is itself
near-degenerate on odd meters** — it marks most beats as candidate bar lines, with high
confidence. Independent peak-picking has no mechanism to choose which subset is the true bar
line, because that choice is a *global periodicity* question and peak-picking is local.

That is precisely the "wrongly non-periodic output" the Beat This! authors say a DBN corrects.
**The premise holds — for the specific reason their own A/B measured, not the reason the plan
assumed.**

### 2.2 The constraint this puts on DBN.3

Beat This!'s A/B is also a warning: on clean 4/4 material where the stream is already sparse and
periodic (our billie_jean: ratio 0.24, all peaks prob 1.000, meter 4 ✓), a DBN *cost* them F1.
DBN.3 must therefore gate on **no regression to suite 1 and to the three passing suite-2 AMLt
scores**, not only on meter improvement. If the decoder cannot beat the incumbent on the broken
tracks without damaging the working ones, the honest outcome is a confidence-gated hybrid — decode
only where the downbeat stream is non-periodic — not a wholesale replacement.

---

## 3. State space

Bar-pointer model of Krebs et al. 2015 §2.1, with the efficient discretisation of §2.3.

**Hidden state** (Krebs §2.1): `x_k = [Φ_k, Φ̇_k]` where `Φ_k ∈ {1,…,M}` is position within the bar
and `Φ̇_k ∈ {Φ̇_min,…,Φ̇_max}` is tempo in bar-positions per frame. `M` is total positions per bar;
`N = Φ̇_max − Φ̇_min + 1` is the number of distinct tempi.

**Inference** (Krebs Eq. 1–2):

```
x*_1:K = argmax_x P(x_1:K | y_1:K)                                        (Krebs Eq. 1)
P(y_1:K | x_1:K) ∝ P(x_1) ∏_{k=2}^{K} P(x_k | x_{k−1}) · P(y_k | x_k)     (Krebs Eq. 2)
```

solved by Viterbi. Downbeats are read off the decoded path (Krebs Eq. 3):

```
D = {k : Φ*_k = 1}                                                        (Krebs Eq. 3)
```

and beats are the frames whose bar position matches a beat position.

**Position resolution** (Krebs Eq. 7), generalised from the paper's 4-beat bar to `B` beats:

```
M(T) = round(B × 60 / (T × Δ))          Δ = audio frame length            (Krebs Eq. 7)
N_max = M(T_min) − M(T_max) + 1                                           (Krebs Eq. 8)
```

Exactly one bar-position state per audio frame — this is the property that makes the model
efficient, and it means position resolution automatically tracks tempo (Krebs §2.3.1).

**Our numbers.** Beat This! emits at 50 fps (hop 441 @ 22050 Hz), so `Δ = 0.02 s`; a `tMax = 1500`
window is `K = 1500` frames (30 s). For `B = 4` over a 60–180 BPM range: `M(180) = 67`,
`M(60) = 200`, so `N_max = 134` (Krebs Eq. 8).

For `N < N_max`, tempo states are distributed **logarithmically** across the range of beat
intervals to mimic auditory JNDs (Krebs §2.3.2). Computed cost per meter hypothesis:

| N (tempo states) | states S | transitions/frame | Viterbi ops (K=1500) | backpointer memory @16-bit |
|---|---|---|---|---|
| 134 (`N_max`) | 16,306 | 88,130 | 132.2 M | 48.9 MB |
| 55 (Krebs's tuned value) | 6,703 | 18,803 | 28.2 M | 20.1 MB |
| 40 | 4,876 | 11,276 | 16.9 M | 14.6 MB |
| **11 (tempo-conditioned, §3.1)** | **1,351** | **1,835** | **2.8 M** | **4.1 MB** |

These are per-meter-hypothesis. `M` scales linearly with `B`, so a 7/4 decode costs 7/4× the
`B = 4` row.

### 3.1 Design decision — condition on the tempo we already have

**Decode each meter hypothesis separately over a narrow tempo band centred on the existing
trimmed-mean-IOI estimate, rather than jointly over the full tempo range.**

Justification is our own baseline, not the paper: grid BPM already tracks truth closely wherever
beats work (billie_jean 116.88 vs 117.44; solsbury_hill 102.68 vs 102.44; take_five 169.24 vs
167.07), and suite-1 beat F is 0.97. **Tempo is not the broken axis; meter is.** Spending state
space rediscovering a tempo we already estimate well is the wrong allocation.

Consequences, all favourable:

- N drops from 55 to ~11 (a ±10 % band at JND spacing), and per-meter cost drops to 2.8 M Viterbi
  operations and 4.1 MB.
- Meter hypotheses become **independent decodes**, comparable by total path log-likelihood, and
  embarrassingly parallel. Peak memory is one decode, not the sum.
- A joint state space over all of {3,4,5,6,7,9,12} would be ≈ 77 k states and ≈ 231 MB of
  backpointers — the naive design, and it does not fit a 50 ms budget.

**Tunable — `dbnTempoBandFraction`.** Default **0.10** (±10 % around the incumbent BPM estimate).
Phosphene tunable, no paper source. Range [0.05, 0.30]. Wider bands re-admit tempo error that the
incumbent does not currently make; narrower bands risk excluding the true tempo when the
incumbent's estimate is itself wrong (yyz 233.61 vs 272.27 truth is the cautionary case, and is
also a track whose beats already fail — see §7).

**Tunable — `dbnMeterHypotheses`.** Default **{3, 4, 5, 7}**. Covers every meter in the ground-truth
catalogue (4, 5, 7) plus waltz. {6, 9, 12} are omitted by default because they are ambiguous with
{3, 4} at a different metrical level and each one multiplies decode cost; see the DECISION-NEEDED
in §8.

---

## 4. Transition model

Factorised (Krebs Eq. 4):

```
P(x_k | x_{k−1}) = P(Φ_k | Φ_{k−1}, Φ̇_{k−1}) · P(Φ̇_k | Φ̇_{k−1})            (Krebs Eq. 4)
```

**Position advance** is deterministic and cyclic (Krebs Eq. 5):

```
P(Φ_k | Φ_{k−1}, Φ̇_{k−1}) = 1_x,
  where 1_x = 1 iff Φ_k = (Φ_{k−1} + Φ̇_{k−1} − 1) mod M + 1                (Krebs Eq. 5)
```

**Tempo transition — use the *proposed* model, not the original.** Krebs Eq. 6 (the original bar
pointer) permits a tempo change at every frame, which the paper shows yields unstable tempo
trajectories (§2.2.3). The proposed model restricts changes to beat positions (Krebs Eq. 9):

```
if Φ_k ∈ B:  P(Φ̇_k | Φ̇_{k−1}) = f(Φ̇_k, Φ̇_{k−1})
else:        P(Φ̇_k | Φ̇_{k−1}) = 1 if Φ̇_k = Φ̇_{k−1}, else 0                (Krebs Eq. 9)
```

where `B` is the set of bar positions corresponding to beats, and

```
f(Φ̇_k, Φ̇_{k−1}) = exp(−λ × |Φ̇_k / Φ̇_{k−1} − 1|),  λ ∈ Z≥0                 (Krebs Eq. 10)
```

Krebs evaluated Gaussian, log-Gaussian and Gaussian-mixture alternatives and found this
exponential best (§2.3.3). `λ = 0` makes all tempi equally probable; the paper states "for music
with roughly constant tempo, we set λ ∈ [1, 300]" (§2.3.3) and measures the optimum at **λ = 125**
for the RNN-based tracker and λ = 95 for the GMM tracker (§4.1). Restricting tempo change to beat
positions is credited with up to 20 % relative CMLt improvement (§4.2).

**Tunable — `dbnTempoChangePenalty` (λ in Krebs Eq. 10). This is the category-3 lever.**

| field | value |
|---|---|
| default | **125** (Krebs §4.1, optimum for the RNN-activation tracker — the closest published analogue to our setup) |
| range | [1, 300] (Krebs §2.3.3) |
| low λ (→1) | the visuals chase the music's tempo closely; a band that drifts or a rubato passage is followed, at the cost of jitter on steady material |
| high λ (→300) | the visuals hold a near-constant pulse; steady tracks are rock-solid, but a genuine tempo change is followed late or not at all |

**Validation is deferred, deliberately.** D-205 marked suite 3 (tempo changes) **DEFERRED — "not
measurable offline"**, with a single track (bohemian_rhapsody, F 0.47). So λ ships at the paper's
default and is tuned when suite 3 becomes measurable, not now. Recording this prevents a future
session from "tuning" λ against a suite that cannot evaluate it.

---

## 5. Observation model

Böck et al. 2014 §2.4.2 define the state-conditional observation likelihood directly from the
network activation `a_k ∈ [0,1]`:

```
                   ⎧ a_k,                1 ≤ φ_k ≤ Φ/λ_o
P(a_k | φ_k)   =   ⎨                                                        (Böck Eq. 3)
                   ⎩ (1 − a_k)/(λ_o − 1), otherwise
```

`λ_o ∈ [Φ/(Φ−1), Φ]` controls what proportion of the beat interval counts as "beat" versus
"non-beat" (Böck §2.4.2). Modelling both beat and non-beat states is reported as superior to
modelling beat states alone.

Note the scope difference: Böck's DBN models **one beat period** (`φ` = position inside a beat,
Φ = 640 cells, Ω = 23 tempo cells over 55–215 BPM, `p_ω = 0.002`, `f_r = 100` fps) and therefore
produces no downbeats. Krebs's bar-pointer model gives bar position and hence downbeats via
Eq. 3. **We need the bar-pointer state space with Böck's observation form applied to it.**

### 5.1 Two streams, one likelihood — our derivation, marked as such

Böck Eq. 3 assumes a **single** activation. Beat This! gives us **two** (beat and downbeat), and
neither paper specifies how to combine them for a bar-pointer state space. The following is a
Phosphene derivation, not a ported equation, and is flagged accordingly:

- At bar position **1** (the downbeat), the state is simultaneously a beat and a downbeat. Its
  likelihood uses the downbeat activation `d_k` in the beat branch of Böck Eq. 3.
- At the other beat positions, the state is a beat but *not* a downbeat: likelihood uses `a_k` in
  the beat branch and `(1 − d_k)` as a factor penalising a downbeat firing off the bar line.
- At non-beat positions, both branches take the non-beat form.

**This is the single least-supported part of the spec and DBN.2 must treat it as such.** It is
also where the leverage is: §2.1 shows the failing tracks are exactly those where `d_k` fires on
most beats, so how strongly the model penalises an off-bar-line downbeat determines whether the
decoder can pick the right subset.

**Tunable — `dbnObservationLambda` (λ_o in Böck Eq. 3).** Default **16**, the value madmom exposes
as its `observation_lambda` default and the one the Böck-family literature uses; marked as
*adopted-by-convention rather than derived*, because the ISMIR 2014 paper states the admissible
range but not the tuned value. Range [2, 64]. Higher λ_o narrows the beat window, sharpening
placement at the risk of missing slightly-off beats.

**Tunable — `dbnDownbeatWeight`.** Default **1.0** (downbeat evidence weighted equally with beat
evidence). Phosphene tunable, no source. This is the direct control on §2.1's failure mode and the
first thing DBN.2 should sweep.

---

## 6. Output contract

| decoder output | today's `BeatGrid` field | status |
|---|---|---|
| beat times (frames whose `Φ` ∈ B) | `beats: [Double]` | direct |
| downbeat times (Krebs Eq. 3, `Φ = 1`) | `downbeats: [Double]` | direct |
| `beatsPerBar` = winning meter hypothesis | `beatsPerBar: Int` | direct — **replaces** `round(median_downbeat_IOI / beat_period)` |
| single BPM | `bpm: Double` | direct, but lossy — see below |
| **per-segment tempo** (the decoded `Φ̇` trajectory) | **no field exists** | **→ DBN.4 requirement** |
| **posterior confidence** | `barConfidence: Float` exists | see §6.1 |

**DBN.4 requirement, recorded here so it is not lost.** The decoder's `Φ̇` trajectory is a
per-frame tempo curve. `BeatGrid` carries one `bpm` plus a 300 s constant-tempo extrapolation, so
collapsing the trajectory to a scalar discards exactly the information that makes suite 3
tractable. DBN.4 generalises `localTiming` / `nearestBeat` / `beatIndex(at:)` to tempo segments;
until then the decoder reports the median of `Φ̇` and DBN.3's A/B is scored on meter and downbeats
only.

### 6.1 Confidence — what it may and may not claim

The Viterbi path carries a total log-likelihood, and the margin between the best and runner-up
**meter hypotheses** is a natural confidence: it answers "how sure are we this is 7/4 rather than
4/4?", which is exactly the quantity `beatsPerBar` needs and today's `barConfidence` does not
provide.

D-205 recorded that today's `barConfidence` is untrustworthy — sorted by it, "Clair de Lune 0.55
(wrong — and should read near zero)" outranks tracks with correct grids. The decoder's
meter-margin confidence should be *better calibrated for the meter question specifically*.

**It must not be claimed to solve suite 5.** Rubato confidence is Phase CNF's job, and D-205
deferred suite 5 to CNF precisely because gating on a broken instrument gates on nothing. DBN.3
may report the margin; only CNF may gate on it.

---

## 7. Known limits, stated before implementation

- **The 30 s window.** `BeatThisModel.tMax = 1500` means the decoder sees only the first 30 s.
  Money's 380 s decodes from 51 beats. Full-track decoding is FT.1, and the plan is explicit that
  a single decode over a stitched full-track activation timeline "is where DBN pays off". DBN.2/.3
  operate inside the clamp; do not treat full-track behaviour as measured.
- **yyz is not a meter problem.** Grid BPM 233.61 vs truth 272.27, AMLt 0.21, downbeat F 0.15 —
  the beats themselves are wrong, so no amount of bar-pointer decoding will fix it, and the
  tempo-conditioned band of §3.1 will inherit the wrong centre. Excluded from DBN's target set;
  it belongs to MDL (model headroom) or FT.
- **clair_de_lune is out of scope by decision.** Suite 5 deferred to CNF (D-205).
- **A decoder cannot invent signal.** §2.1 shows `d_k` is high on most beats for money and
  solsbury_hill. The decoder imposes periodicity on an ambiguous stream; if the true bar line is
  not *among* the candidates at all, it will pick a wrong-but-periodic one confidently. DBN.3 must
  therefore report meter accuracy **and** downbeat F, never meter alone.

---

## 8. Verification plan for DBN.2

Synthetic activation cases (unit-testable without audio):

| case | asserts |
|---|---|
| clean 4/4, constant tempo | recovers beats, downbeats, `beatsPerBar = 4` |
| clean 7/4 | recovers `beatsPerBar = 7` — the money/solsbury_hill case in isolation |
| **downbeat stream firing on every beat** | picks a *periodic* subset; this is §2.1's failure mode reduced to a fixture |
| tempo ramp | `Φ̇` trajectory follows; no beat dropped |
| tempo step | re-locks; latency recorded |
| silence / noise floor | no crash, low confidence, empty-or-flagged grid |
| activation shorter than one bar | no crash, degenerate output flagged |

**Performance budget:** < 50 ms for a 30 s activation window on M1, asserted in
`DSPPerformanceTests`. §3's table says this is only reachable with the tempo-conditioned design —
at N = 55 across 4 meters the cost is ≈ 113 M Viterbi operations, which will not fit. If DBN.2
measures otherwise, the budget or the design changes; do not quietly widen the budget.

**BeatBench cells DBN.3 will A/B** (offline-grid mode, all 9 ground-truthed tracks):

- *primary*: `beatsPerBar` correct count (baseline 2/9), downbeat F on money / solsbury_hill /
  take_five / bohemian_rhapsody (baseline 0.14 / 0.13 / 0.26 / 0.25)
- *regression guards*: billie_jean F 0.97 and downbeat F 0.90; suite-2 AMLt on take_five (1.00),
  solsbury_hill (1.00), money (0.88)

Per the `beatbench` skill: no category is claimed won without a number, and a regression on any
suite is reported even when the target suite improves.

---

## 9. Decisions — RESOLVED (Matt, 2026-07-30, recorded as D-207)

**Both answered: "decline when unsure, keep {3,4,5,7}".** The binding consequences for DBN.2:

1. **`dbnMeterHypotheses` = {3, 4, 5, 7}** — fixed, not a tunable to be widened casually. Adding a
   hypothesis is now a product decision, not an implementation one.
2. **The decoder must be able to decline.** Its output is not "a meter" but "a meter *or* no
   confident bar". That makes the meter-margin confidence of §6.1 **load-bearing rather than
   diagnostic**, and it puts a new field on the output contract (§6): a bar-confidence flag that
   consumers can gate on. `beatsPerBar` alone can no longer express the result.
3. **DBN.2 must therefore ship the decline path and its threshold**, not defer them. The threshold
   itself is a tunable (`dbnMeterMarginThreshold`, default TBD at DBN.2 once the margin's
   distribution across the 9 ground-truthed tracks is measured — set it from data, not taste).
4. **DBN.3's A/B gains a metric:** how often "unsure" fires, per track. A decoder that declines on
   everything is not a win, and meter-correct-count alone would not catch that. Report
   decline-rate alongside meter accuracy and downbeat F.
5. **Preset-side fallback is explicitly out of scope** (option 3 was not chosen). Presets that lose
   the bar accent keep their beat-level motion and nothing substitutes for it. If that reads as too
   plain on odd-meter material, the graded version belongs to CNF.2, which already owns
   binary-gate → graded-scaling.

Original framing, retained for the record:

### D-1 — When the decoder is unsure of the bar, should the visuals guess or decline?

Carried forward unresolved from the DBN.1 session prompt; §6.1 makes it concrete because the
decoder now has a meter-margin confidence to gate on.

Bar position drives Nacre's and Glaze's downbeat camera pushes (D-171, D-173), and the meter is
currently wrong on 7 of 9 measured tracks — so a wrong bar-1 is already firing, invisibly.

- **Always commit to a best guess (today's behaviour).** Every track gets a downbeat accent; on
  the tracks where meter is wrong it lands on an arbitrary beat — a push that feels
  almost-but-not-quite tied to the music, the "connected but not tight" complaint already on file
  for GLAZE.7.
- **Decline when unsure — no bar accent until the margin is clear.** On ambiguous material the
  downbeat push does not fire; those presets keep beat-level motion and lose only the bar-level
  gesture. Nothing lands wrong; some tracks read plainer than today.
- **Decline, and let each preset choose a fallback** (e.g. an every-4-beats push). More
  expressive, but per-preset work landing after DBN.

**Recommendation: decline when unsure**, matching D-205's product call that meter is a hard gate
because a wrong bar-1 degrades visuals users see, and the program's stated position for category 5
that "success = declining honestly".

**→ CHOSEN (Matt, 2026-07-30): decline when unsure.**

### D-2 — Should {6, 9, 12} be in the meter hypothesis set?

`dbnMeterHypotheses` defaults to {3, 4, 5, 7}, covering every meter in the ground-truth catalogue
plus waltz. Adding {6, 9, 12} would let compound meters be labelled as such — but each is
ambiguous with {3, 4} at a different metrical level, so the risk is a 4/4 track confidently
relabelled 12/8, and each hypothesis multiplies decode cost.

- **Keep {3, 4, 5, 7}** — cheaper, and no ground-truth track needs more.
- **Add {6, 9, 12}** — future-proof for compound-meter material, at the cost of decode budget and
  a new confusion mode on ordinary 4/4.

**Recommendation: keep {3, 4, 5, 7}** and revisit only when a ground-truthed track needs a
compound meter. This is close to an engineering call; it is surfaced only because "12/8 instead of
4/4" changes where the visual accent lands, which is user-visible.

**→ CHOSEN (Matt, 2026-07-30): keep {3, 4, 5, 7}.**

---

## 9.5 DBN.2 outcome — what implementation changed about this spec

Recorded here so DBN.3 does not re-derive it.

| spec said | DBN.2 measured | resolution |
|---|---|---|
| `dbnDownbeatWeight` default 1.0 | at 1.0 the decoder picks the **wrong** meter on the degenerate fixture; margin 0.0012 (indistinguishable) | **5.0**; correct from 2.0 up, margin grows monotonically |
| `dbnMeterMarginThreshold` "set from data" | correct-margin min 0.1439 vs wrong-margin max 0.2677 — **the distributions overlap** | **0.10**, a tradeoff not a boundary; margin is necessary but not sufficient |
| §8 budget "< 50 ms, assert in DSPPerformanceTests" | none — measured **17.9 ms** in release (BUG079.1, 2026-08-07) | asserted at 50 ms in release; debug runs keep a 4000 ms regression ceiling |
| §3.1 "the naive joint state space does not fit a 50 ms budget" | correct, but the first *tempo-conditioned* implementation still took 17 s — the cost was per-state-frame recomputation, not state count | precompute observation classes and per-frame terms; 12.6× faster |

**The finding DBN.3 has to plan around:** on real activations the decoder **collapses every odd meter to 4**. Correct on 3 of 6 truth-bearing tracks (all 4/4) against the incumbent's 2, but money (7), solsbury_hill (7) and take_five (5) all decode as 4. Most of the gain is from *declining*, not from reading odd meters — confidently-wrong drops from 7 tracks to 2. §2 argued the premise holds because the DBN's one measured benefit is repairing non-periodic downbeat output; that mechanism demonstrably works on the synthetic fixture but does not yet recover odd meters on real audio, and **why** is the open question DBN.3 inherits. Candidates not yet separated: the tempo hint being wrong for money (incumbent 116.19 vs truth 60.97, roughly 2×, so the ±10 % band excludes the true tempo entirely); the ±10 % band being too narrow generally; or the two-stream observation model of §5.1 under-weighting bar-line evidence relative to beat evidence at every weight that keeps clean 4/4 safe.

---

## 9.6 The odd-meter collapse is a flaw in §5.1, not the tempo hint (DBN.2 follow-up)

Investigated on money at Matt's direction. **The tempo hint is exonerated; §5.1's two-stream
observation model has a structural bias toward small meters.**

### The hint is not the cause

money's ground truth records `tap_bpm 60.97`, which made the incumbent's ~116–123 look like a
2× error. It is not. Both reference backends independently put the real pulse at **~122 BPM** and
label the taps `METRICAL — "reference is double the tapped pulse (×2.01)"`, and the file's own
`meter_note` says *"beats tapped at HALF the bar pulse, so the bar is 7"*. The incumbent hint is
already on the true pulse and the ±10 % band contains it.

Forcing the hint to the half-time pulse (60.97) makes things **worse**, not better — the decode
returns meter 3 with 7 ranked last. The hint is not the lever.

### The actual mechanism, with a closed form

§5.1 applies `w · log(1 − d)` at **every non-downbeat beat position**. Meter `B` labels `(B−1)/B`
of its beats as non-downbeat, so the expected penalty per beat is

```
w · log(1 − d) · (B − 1)/B          — monotonically increasing in B
```

Larger meters are penalised **purely for being larger**, independently of whether they are correct.
The predicted log-likelihood gap between two meters over `N` beats is

```
Δ = N · w · (−log(1 − d)) · [ (B₁−1)/B₁ − (B₂−1)/B₂ ]
```

Measured on money (Δ of meter 7 relative to meter 3, full decode window):

| `downbeatWeight` | 1 | 2 | 5 | 10 |
|---|---|---|---|---|
| Δ (nats) | 18 | 36 | 89 | 180 |
| Δ / w | 18.0 | 18.0 | 17.8 | 18.0 |

Exactly linear in `w`. Substituting DBN.1's independently-measured mean downbeat peak
probability for money (**d = 0.805**), N = 58 beats and `(6/7 − 2/3) = 0.1905`, the closed form
predicts **18.1 nats per unit weight** against a measured **18.0**. At `w = 0` all four meters sit
within 9 nats, as they must when the meter is unobserved.

### Why no single weight can work

The two requirements are in direct opposition:

* **`w` must be high** or the downbeat evidence does not register at all — below 2.0 the decoder
  picks the wrong meter even on the clean synthetic fixture (§9.5).
* **`w` must be low** or the `(B−1)/B` bias swamps the evidence and every track collapses to the
  smallest viable meter.

That is why 5.0 passes the synthetic cases and still collapses every real odd meter to 4. **It is
not a tuning problem and further sweeping is wasted effort.**

### Root cause and fix direction

`P(a_k | φ_k)` in Böck Eq. 3 is a *normalised* distribution over the beat/non-beat partition of a
single stream. The §5.1 extension multiplies in a second, **unnormalised** downbeat term whose
accumulated mass over a bar depends on `B`. Comparing meters by total path log-likelihood then
compares differently-normalised models, which is not a valid model selection.

Candidate fixes for DBN.3, none yet tried:

1. **Normalise the downbeat term per bar** rather than per beat, so its expectation is independent
   of `B`.
2. **Make the downbeat evidence asymmetric** — reward `log(d)` at the bar line, but do not penalise
   `log(1 − d)` at every other beat position. Removes the `(B−1)/B` term entirely.
3. **Subtract the analytic bias** `N · w · log(1 − d) · (B−1)/B` per hypothesis before comparing.
   Exact for constant `d`, approximate otherwise; the cheapest to test, and the closed form above
   is already validated well enough to try it.

Option 2 is the most principled — the model should say "a bar line is here", not "a bar line is
*not* here" once per beat — and it is the one to attempt first.

---

## 9.7 §5.1 fixed — the bias is gone, and the evidence turns out to be thin

Implemented at Matt's direction after §9.6. Three versions, each diagnosed from a measured
mechanism rather than swept.

| version | downbeat evidence | raw meter correct | margin usable? |
|---|---|---|---|
| A — as specified in §5.1 | `w·log(d)` at the bar line, `w·log(1−d)` at every other beat | 3/6 | yes (correct min 0.144) |
| B — centred log-odds, whole beat window | `w·(L−L̄)` across beat 0's window | 3/6 | yes (correct min 0.199) |
| **C — centred log-odds, bar position only** | `w·(L−L̄)` at the bar position | **4/6** | **no — fully overlapping** |

`L = log(d/(1−d))`, `L̄` its mean over frames with `beatProb > 0.5`.

**Why centring.** A constant downbeat stream must score every meter identically — only
*variation* in `d` may discriminate. A raises `w·log(1−d)` on `(B−1)/B` of beats, so larger
meters pay more for being larger (§9.6, 18 nats per unit weight). Naively deleting that term
inverts the bias, because `w·log(d)` at the bar line is negative and fewer bar lines is then
cheaper. Centring on `L̄` makes constant `d` contribute exactly zero at any `B`.

**Why bar position only.** B still lost. The beat window is ~2 frames wide and its second frame
is a non-beat frame where the downbeat activation has already collapsed (`d ≈ 0.02`, so
`L − L̄ ≈ −5.7`). Charging that to every bar line reintroduced a count bias — this time favouring
*large* meters. Measured: on the degenerate fixture meter 4 placed **11/11** bar lines correctly
and still lost to meter 7's **1/6** by 78 nats, against 74 predicted by exactly this effect. C
samples the bar-line term at the bar position only; meter 4 then places 12/12 and wins.

**What the fix bought, and what it exposed.**

* **First odd meter ever recovered:** solsbury_hill's raw winner is now **7** (−3871, beating 4's
  −3885). Raw accuracy 3/6 → 4/6.
* **But the margins collapsed.** Correct now spans 0.0097–0.5534 and wrong spans 0.0155–0.1085 —
  a *wrong* answer (money) outscores a *right* one (solsbury_hill). With the model bias removed,
  what is left is the evidence itself, and it is thin: the decoder is right by a hairline when it
  is right at all.

That is the honest state. **The remaining gap is evidence quality, not model bias** — consistent
with DBN.1's finding that the downbeat stream is near-degenerate on exactly these tracks. money
and take_five still decode as 4 and no threshold rescues them.

**Stopping here per the two-strikes rule.** Three observation-model iterations in one increment,
each an improvement with a measured mechanism, ending in a model with no known bias. Continuing
would be tuning against thin evidence, which is the pattern the rule exists to stop. DBN.3
inherits two questions that need a changed premise rather than another sweep: whether a better
confidence signal than the raw margin exists, and whether the downbeat stream can be improved at
source (MDL's `final0` A/B is the obvious candidate — the plan already expects it to help
suites 2 and 4).

---

## 10. Sources

- Krebs, Böck & Widmer. *An Efficient State-Space Model for Joint Tempo and Meter Tracking.*
  ISMIR 2015, pp. 72–78. CC BY 4.0. https://www.cp.jku.at/research/papers/Krebs_etal_ISMIR_2015.pdf
- Böck, Krebs & Widmer. *A Multi-model Approach to Beat Tracking Considering Heterogeneous Music
  Styles.* ISMIR 2014, pp. 603–608. https://zenodo.org/records/1415240
- Foscarin, Schlüter & Widmer. *Beat this! Accurate beat tracking without DBN postprocessing.*
  ISMIR 2024. arXiv:2407.21658. https://arxiv.org/abs/2407.21658
- Whiteley, Cemgil & Godsill. *Bayesian Modelling of Temporal Structure in Musical Audio.*
  ISMIR 2006 — the original bar pointer model, cited by Krebs as [20]; consulted only via Krebs's
  description, **not read directly**. Any DBN.2 detail that depends on it must go back to the
  source rather than to Krebs's summary.
