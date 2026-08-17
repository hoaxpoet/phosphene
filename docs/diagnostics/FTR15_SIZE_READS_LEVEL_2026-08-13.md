# FTR.15 — why the tree's growing and shrinking feels divorced from the music

**Date:** 2026-08-13 · **Type:** diagnosis, no code change · **Capture:** `2026-08-13T16-29-44Z`
(*Carry The Zero*, local file, single track, 4394 frames / 74 s)

Matt's M7 on FTR.14: *"movement is synced to the bar and generally looks good. but the growing and
shrinking of the trunk and canopy feels random, completely divorced from what's going on in the
music."* The first clause closes the FTR.10→FTR.14 motion arc. The second is a separate defect on
a separate axis — not *how* the size moves, but *what decides it*.

**Finding, one sentence: the trunk and canopy read LEVEL, and on a limited master level moves
OPPOSITE to the thing a listener notices — `r(trunk, spectral_density) = −0.641`.**

---

## 1. What actually drives the size

`fractal_growth` (FractalTree.metal) produces the only two size terms, and the trunk is
`0.27 + reach·0.13 + surge·0.32`:

| term | expression | reduces to |
|---|---|---|
| `surge` | `saturate(spectral_surge)` | **level rank** |
| `musicGate` | `smoothstep(0.05, 0.30, spectral_surge)` | **level rank** |
| `fullness` | `saturate(spectral_section_ratio × 0.5)` | density rank — but see §4 |
| `arousalReach` | `(arousal − 0.10) / 0.58`, ×0.10 | mood, weighted 10 % |

`surge` carries the largest coefficient (0.32 against `reach`'s 0.13) **and** gates `reach`
through `musicGate`. So level rank decides the size twice and everything else is trim.

## 2. It is not uncoupled from the audio, and it is not jittery

Both of my first two hypotheses were wrong and are recorded so they are not re-run.

Against **true loudness measured from `raw_tap.wav`** (100 ms RMS in dB — ground truth, unlike the
AGC-normalised band and stem fields, see §3):

| loudness smoothing | r(trunk, loudness) |
|---|---|
| none | +0.605 |
| τ 1 s | +0.716 |
| **τ 5 s** | **+0.863** |
| τ 15 s | +0.831 |
| τ 30 s | +0.715 |

The trunk crosses its own median **0.10 times/s — one full grow/shrink cycle every ~20 s**, and a
full excursion spans **8.2 dB** of real loudness. By every one of those measures it is a
well-behaved, section-scale loudness follower. "Random" is not describing noise.

## 3. ⚠ AGC-normalised fields are not a loudness reference, and using them inverted the answer

My first pass correlated the trunk against `bass + mid + treble` and the per-stem energies and got
**−0.47 to −0.52** on every one — "the tree shrinks when the music gets louder." That was an
artifact: those fields are AGC-normalised, so their denominator moves with mix density and their
sum is not a level proxy. Decoding `raw_tap.wav` reversed the sign to **+0.61…+0.86**.

**Any future "is this driver connected?" question measures against the raw tap or against the
pre-AGC fields (`spectral_density`, `spectral_surge`), never against a band or stem energy.**

## 4. The actual mechanism — level is the one quantity a limiter destroys

`spectral_density` is the HF-energy fraction, computed from raw magnitudes upstream of the AGC;
the capability registry calls the DYN.1 fields *"the only fields that survive normalisation."* It
rises when distortion, cymbals and a fuller arrangement arrive — DYN.1's founding observation was
that **distortion adds harmonics, not amplitude**.

| pair | r |
|---|---|
| `trunk` vs `spectral_density` | **−0.641** |
| `spectral_surge` vs `spectral_density` | **−0.473** |
| `trunk` vs density smoothed 5 s | −0.323 |
| `trunk` vs density smoothed 15 s | +0.149 |

**On this master level and density move in opposite directions.** When the band comes in the
limiter holds the level flat or pulls it down while density climbs — so the tree *shrinks as the
song gets bigger*. That is worse than random: it is anti-correlated with the event the listener
actually registers. The `BeatGrid` log puts this track's **`musicRange` at 3.6 dB**, which is the
whole problem in one number — there is almost no level range left to express structure with.

**And the one density term in the expression is inert.** `spectral_section_ratio` reads p05 0.395 /
p50 1.773 / p95 2.000 and sits at its 2.0 ceiling on **19 %** of frames, so
`fullness = saturate(ratio × 0.5)` is near-saturated most of the time. It contributes rare large
dives rather than continuous shape, which is its own contribution to "random".

## 5. What this does and does not invalidate

- **FTR.14 stands.** Matt's *"synced to the bar and generally looks good"* is the motion arc
  closed. Nothing here is about the glide.
- **DYN.1c's ranked surge is not wrong, it is mis-assigned.** A level rank is the right way to ask
  "how loud is this moment for this track"; it is the wrong question for "how big should the tree
  be" on material whose level is limited flat.
- **FTR.3f's rule needs revisiting, not overriding.** It says the fast density leg goes to a
  QUANTISED count, never to a length, because raw density was too restless for continuous
  geometry. That constraint was written *before* FTR.14 — the render-rate glide now smooths any
  driver, so a density-driven length is newly viable in a way it was not then. This is a reason to
  re-measure it, not a licence to ignore the rule.

## 6. Not done

No code changed. Which signal should decide the tree's size is a routing decision with visible
consequences, so it is Matt's call and is put to him with these numbers.

---

## 7. Addendum 2026-08-14 — two failed candidates, and the measurement error under both

**Status: the complaint in §1 is still OPEN. The shipped build is FTR.14 (level-driven size).**

### 7.1 ★★★ Every statistic in §1–§6 measured TRUNK LENGTH. The branch COUNT is 26× more sensitive to the same term.

`trunkLen = 0.27 + reach·0.13 + size·0.32` but `count = 7 + base + (lift·8 + size·**26**) · amp`.
So the size term reaches the canopy with a coefficient **81× larger** than it reaches the trunk.
Every span, turn-rate and burstiness figure quoted through FTR.16 was computed on the trunk —
the *least* sensitive consumer of the number being tuned. That is why span numbers kept failing
to predict what Matt saw, and it is the fourth measurement-blind-spot of the same family in this
program (after turn-rate-vs-step-size, float-vs-pixel identity, and analysis-rate-vs-render-rate).

**Any future candidate is measured on the branch count first, the trunk second.**

### 7.2 Candidate A — `max(level, density)`: rejected by Matt on a rendered A/B

Rationale: level DIPS as the band enters on a limited master (§4), so roughly a third of the
tree's growth range on *Carry The Zero* is motion in the wrong direction; `max` removes the
backwards dips and is a no-op wherever level is already honest. Measured on the reviewed capture:

| | trunk span | trunk sig-turns/s | count span | mean count @6.7 s | @35.2 s |
|---|---|---|---|---|---|
| APPROVED (level) | 0.252 | 0.50 | 27.6 | **14.4** | 45.0 |
| `max(level, density)` | 0.148 | 0.53 | 17.8 | **31.4** | 45.0 |

It fixes the band entry (14.4 → 31.4 branches) and is numerically identical at the agreement
window. Matt's read of the render: band entry *"yes, I suppose"*; the agreement window
**"looks too active"**. Rejected.

**⚠ Unreconciled:** the rendered agreement window looked visibly fuller under the candidate, yet
the count measures 45.0 in both. Either the render window and the measured window differ, or a
consumer other than trunk/count carries the difference. **Do not build on candidate A until that
is explained** — an unexplained gap between a render and a metric is how FTR.16 shipped.

### 7.3 Candidate B — `level + w·densityLift`: fails at the start of a track, by construction

The deviation-primitive form (D-026), which should have been the first thing tried:
`densityLift = density / density_slow − 1`, zero at steady state, so quiet passages are untouched
by construction and only a density JUMP lifts the tree. It does not work here:

| | mean count @6.7 s | @35.2 s |
|---|---|---|
| APPROVED | 14.4 | 45.0 |
| `level + 0.5·densityLift` | **14.4** | 45.0 |
| `level + 1.0·densityLift` | **14.4** | 45.0 |

No lift at all at the band entry. Cause: `spectral_density_slow` has **τ ≈ 10.5 s**, so 6.7 s into
a track it is still seeded near the current value and the ratio is ≈ 1. **A deviation against a
10.5 s baseline cannot detect an event in the first ~15 s of a track** — which is exactly where
the arrangement usually arrives. Any deviation-based correction needs a faster baseline than
`density_slow`, and that is a new engine field, not a shader change.

### 7.4 Where this leaves the problem

Confirmed by Matt: correcting the band-entry lie is the right direction. Ruled out by
measurement: single-field swaps (§FTR.16 — absolute density matches the motion rate but not the
span; the per-track rank matches the span but barely moves), `max()` blending (too active), and
deviation-against-`density_slow` (blind for the first 15 s). The remaining untried directions are
a faster density baseline (new field) or a correction bounded so it cannot compress count span.
Neither has been measured.

### 7.5 Candidate C — the ARRANGEMENT (how many stems are playing): six formulations, all worse

Matt, when told the next step was a faster density baseline: *"why is the fast density baseline the
next most important work? I don't understand how this fixes the preset in alignment with my
feedback."* He was right — that plan was four inferences deep, each fixing the previous fix's
problem. Level and density are both **physics**; his words were about **music**. So: the size
should follow the arrangement — how much is playing — which is the stems.

That is the most literal reading of his complaint and it was worth trying. It does not work, and
the reason is now measured rather than guessed.

**Two implementation facts learned, both worth keeping:**

1. **★ Order matters: map each stem FIRST, then smooth.** `*EnergyDev` is a D-026 deviation whose
   median is ~0 by construction. Smoothing it and *then* thresholding yields a small number that
   any threshold maps to zero, so the term comes out **constant**. Caught because the burstiness
   figure was byte-identical across two different thresholds. The per-stem mapping therefore
   cannot live in the shader downstream of a glide — it has to be a CPU scalar.
2. **The signal saturates.** "All four stems above their own average" happens ~25 % of the time, so
   the scalar hits 1.0 at p95 on both captures.

**Every formulation trades something material away from the approved build:**

| size driver | trunk span | max height | count span | pin |
|---|---|---|---|---|
| **level (APPROVED)** | **0.252 / 0.361** | **0.61 / 0.72** | **27.6 / 22.6** | 2–5 % |
| arrangement, raw | 0.130 / 0.111 | 0.53 | 25.5 / 28.6 | 0 |
| arrangement, rescaled 0.05–0.55 | 0.272 / 0.263 | 0.72 | — | **22–26 %** |
| arrangement, soft knee (best) | 0.216 / 0.216 | 0.53 | 17.6 / 17.6 | 0 |

Raw loses the trunk's height range; rescaling recovers it and **flat-tops a quarter of the time**
(the failure the reference README names explicitly); a soft knee cannot pin but caps both span and
maximum height well below the approved build.

**And it is not even consistently better on the coupling it was chosen for:** on *Carry The Zero*
the arrangement flips `r` against density from −0.46 to +0.62, but on *Seven Nation Army* it goes
the other way, +0.55 → −0.17. It fixes the reviewed track and inverts another.

### 7.6 The characterisation this program now has, and the one job that comes next

Six formulations across FTR.16–FTR.17, all measured, all worse than the approved build on at least
one axis Matt has already objected about. The pattern is consistent enough to be a finding:

> **Level rank has the dynamic range but the wrong sign on a limited master. Every
> deviation-derived alternative has the right meaning but too little range — deviations sit at
> zero most of the time and saturate when everything fires at once. No field Phosphene currently
> computes has both.**

That is why five shader-level attempts failed: it is not a mapping problem.

**The next job is NOT another driver.** It is to explain the one unresolved contradiction, because
everything else is downstream of it: under candidate A the rendered agreement window looked
visibly fuller while the branch count measured **45.0 in both** builds. Either the render window
and the measured window differ, or a consumer other than trunk/count carries the difference. Until
that is explained there is no trustworthy instrument for judging the next candidate — and an
unexplained render/metric gap is exactly how FTR.16 shipped a regression.

### 7.7 The render/metric contradiction, resolved: the METRIC was wrong

§7.6 named this as the blocking job. It is answered, and the answer reverses the assumption the
whole investigation rested on.

**The pixel difference is real.** Mean luma of the rendered strip at playback ≈35 s:
**3.68 (approved) → 5.29 (candidate A)**, +44 %. Not a perception artifact.

**It is caused only by the shader's `max()` term.** Two bisections, each rendering the same window:

| build | mean luma |
|---|---|
| approved | **3.67966** |
| Swift side only — slot 6 bound, shader unchanged | **3.67966** (byte-identical) |
| shader structural change, size term arithmetically identical | **3.67966** (byte-identical) |
| full candidate A | **5.28972** |

So neither the extra binding nor the shader edit perturbs anything; the value of `max()` does.

**And the metric that said "45.0 in both" was computed from a wrong model of the build.** Probing
the harness at the same rows:

| quantity at playback 35.0 | my python model | actual |
|---|---|---|
| beat-glided `spectral_surge` (the "level" term) | 0.613 – 0.646 | **0.515 – 0.530** |

**The error: I modelled the glide as an EMA of the LIVE signal. It is a chase toward a target
LATCHED AT THE LAST BEAT.** Those differ by up to a beat of lag plus the glide's own τ, and the
gap was ~0.1 — enough to flip every level-vs-density comparison toward "level is larger, so
`max()` is a no-op." That model has been behind every level figure quoted since FTR.14.

**Two further modelling errors found in passing, both the same species:**
- Two of my ad-hoc scripts used *different* branch-count formulas (one included `reach·18` and the
  density lift, the other did not), which is why the same window was reported as both "29" and
  "45.0". Neither included `amp` or the tips.
- `applyRecomputedDensity` indexes its table with `Int(time · 10)` where `time` carries the
  13 s app-startup offset, so on any capture where that path is active it reads the recomputed
  density/surge ~13 s late. Not active in these renders (the table is empty when `FT_RECOMPUTE`
  is unset) but a live trap for the next session that enables it.

### 7.8 ★★★ The transferable rule: when a render and a metric disagree, the RENDER is right

The render is the actual pipeline. A metric is a MODEL of the pipeline, and every model in this
program has now been wrong at least once — turn rate, step size, float-vs-pixel identity,
analysis-vs-render rate, trunk-vs-count sensitivity, and now glide-as-EMA. §7.6 recorded this
contradiction as "an unexplained gap that blocks the next candidate"; that framing had it exactly
backwards, treating the render as the suspect party.

**Consequence for candidate A: Matt's *"too active"* was a judgement on a real, correctly-rendered
difference. It was not confounded, and it stands.** What was wrong was my claim that the candidate
would be a no-op in quiet passages — the build genuinely was fuller there, and the metric that said
otherwise was modelling a glide it did not understand.

**Consequence for anything next:** a candidate is judged from a render, and a metric is only
admissible after it has reproduced that render's verdict on a known-good and a known-bad build.

### 7.9 FTR.18 — the correction, BOUNDED, and the harness bug that hid everything

Matt: *"bound the correction so it can't lift quiet passages."*

**Shipped form.** Level rank stays the driver — it has the dynamic range and six alternatives each
lost span, height or pacing. Its one defect is corrected and nothing else:

```
level    = saturate(fHeld.spectral_surge)
density  = knee(fSection.spectral_density)          // ~2 s glide, buffer(6)
inverted = 1 - smoothstep(0.15, 0.40, level)        // the gate
size     = saturate(level + max(0, density - level) * inverted)
```

Both conditions must hold, so it fires only on the limiter signature — level LOW while density
HIGH. Observed, via the harness:

| window | level (beat-glided) | density → knee | lift |
|---|---|---|---|
| band entry, playback 6.7 s | **0.088** | 0.665 → **0.751** | **+0.663** |
| quiet passage, 35.0 s | **0.515** | 0.174 → 0.442 | **0.000** |

**Verified on the RENDER, like-for-like** (mean luma of an 8-frame strip):

| window | approved | bounded |
|---|---|---|
| 6.5 s | 1.738 | **3.400** (+96 %) |
| 35.0 s | **5.36295** | **5.36295** — byte-identical |

### 7.9.1 ★★★ The harness bug that invalidated every rendered A/B before this

`MeshGenerator.advanceBeatHold` — the path for capture rows that are fed to the holds but NOT
drawn — passed `renderDeltaTime: 0`, on the documented reasoning that *"a subsampled strip would
otherwise glide at the wrong rate."* **That reasoning is backwards.** A glide is a WALL-CLOCK
filter; it must advance with elapsed time on every frame whether or not that frame is rasterised.
Passing 0 meant a strip rendered with `FT_SKIP=N` arrived at its first drawn row with both glides
still sitting on their **frame-0 seed**.

Three things previously mistaken for something else, all this one bug:

1. A rendered A/B looked **+44 % fuller** in a window whose measured correction was exactly 0.000
   (§7.7 blamed the metric; the metric was right and the RENDER was broken).
2. The gate above appeared not to shut — because the `level` the shader saw was near its seed, not
   the 0.515 it actually is at that moment.
3. **Matt's *"row 4 looks too active"* was graded on a render whose baseline AND candidate were
   both wrong.** §7.8 concluded that judgement "stands, unconfounded". It does not; it was
   confounded, and §7.8's confident reversal was itself wrong.

**So §7.8's rule needs its own correction.** "When a render and a metric disagree, the render is
right" is *not* the lesson. Both are models — the render is only ground truth if the harness
feeding it is. The real rule is narrower and duller:

> **When a render and a metric disagree, neither is trustworthy until the disagreement is
> explained. Bisect until one of them is proven wrong on a control.** Three bisections did it here
> (Swift-only, structural-only-with-identical-term, and approved-with-the-harness-fix); reasoning
> from either number alone produced the wrong answer twice.

Every harness figure quoted for FTR.14–FTR.17 that came through a subsampled render path was
computed on the buggy glide. The trunk-report figures (which advance every row) are unaffected.

---

## 8. Addendum 2026-08-17 (FTR.23) — the size driver is *inversely* correlated with audible events, and flux does not fix it

Matt's seventh rejection of the same complaint (*"the tree still grows and shrinks with no clear
connection to the music"*) finally has a number attached to it that is about **events** rather than
about correlation with a smooth loudness curve.

### 8.1 The event criterion

§1–§7 measured *correlation with loudness*, and the trunk scores **+0.86** against true loudness at
5 s smoothing — a faithful section-scale follower, which is why every previous round could produce a
green number for a build Matt rejected. That statistic answers the wrong question. What "connection
to the music" means perceptually is **the moment you notice something, the visual moves**.

So: 49 audible events detected in `2026-08-17T12-47-58Z` directly from `raw_tap.wav` — a > 3 dB rise
in the 50 ms RMS envelope over the previous 2 frames, above −40 dBFS, de-duplicated at 300 ms
(1.63 events/s). For each candidate field, the mean of its **max z-score within ±120 ms** of an event.

| field | z at audible events |
|---|---|
| `beatMid` | **+1.00** |
| `beatBass` | +0.99 |
| `spectralFlux` | +0.94 |
| `bassDev` | +0.91 |
| `spectral_section_ratio` | +0.71 |
| `arousal` | +0.05 |
| `spectral_density` | −0.41 |
| **`spectral_surge` — the shipped size driver** | **−0.52** |

**The size term moves DOWN when the ear notices something.** This is §4's limiter mechanism, but at
transient rather than section scale: `spectral_surge` is this moment's rank in the track's own
loudness distribution, and a limited mix *drops* in rank exactly when a band arrives. FTR.18
corrected the section-scale case and bounded the correction deliberately; the transient case was
never in scope and is still there.

### 8.2 ❌ `spectralFlux` onto size — measured, NOT shipped

Matt's instruction (2026-08-17) was *"ship it and take flux off branch spread"* — flux being the
best-scoring field not already spoken for. Measured through the real shipped pipeline (FTR.23 glide,
`saturate` ceiling, section-glide density), against the §8.1 criterion:

| size formulation | z@events | span (p95−p05) | total travel | pinned at 1.0 |
|---|---|---|---|---|
| level base — SHIPPED | −0.49 | 0.472 | 8.04 | 0 % |
| base + 0.15·flux | −0.48 | 0.520 | 13.08 | 0 % |
| base + 0.25·flux | −0.46 | 0.554 | 17.84 | 1 % |
| base + 0.35·flux | −0.45 | 0.546 | 21.35 | **11 %** |
| base + 0.50·flux | −0.40 | 0.479 | 26.68 | **15 %** |
| flux alone (knee 0.22–0.55) | **+0.15…+0.19** | **0.12–0.15** | 16–20 | 0 % |
| `max(base, flux)` | +0.17 | 0.427 | **52.43** | 0 % |
| 0.45·base + 0.55·flux | −0.20 | 0.424 | 32.68 | 0 % |

**Additive flux does not flip the sign at any usable weight** — the negative base dominates, and by
the time the weight is large enough to matter the term is pinned at the ceiling 11–15 % of the time
and the span has started collapsing. **Replacing** the base with flux does flip the sign, but only
to +0.17, and then either the span falls to a quarter of shipped (DYN.1e: a band too small to see)
or total travel goes up 6.5× — which is *"the trunk is moving too much"*, the FTR.9 complaint that
opened this whole arc.

### 8.3 ★★ The structural finding

> **Event alignment requires a fast response; low travel requires smoothing. One term on one visual
> layer cannot deliver both.** Any formulation that marks 1.6 events/s must move at least that fast,
> and anything moving that fast on the size term reads as restless.

This is why the size problem has survived seven rejections while the *motion* problem was solvable:
motion had two layers available (target and glide τ, separated at FTR.22), and size has one. A fix
therefore has to either split size into two layers — a slow base that carries the section and a
fast, small, decaying accent that marks events — or take the event marking off the size term
entirely and put it on a different visual property. Neither is a tuning change, and both alter what
Matt sees, so neither was shipped on inference.

The only fields that mark events cleanly (`beatBass`/`beatMid`, z ≈ +1.00) are beat-locked: they
carry the Layer-4 accent-only constraints **and** Matt's twice-stated rejection of beat-driven
growth at FTR.3. That route needs his explicit call, not my recommendation.

---

## 9. Addendum 2026-08-17 (FTR.24) — the size gets a second layer, and the metric that made §8 look impossible

§8 concluded that one term on one visual layer cannot be both event-aligned and low-travel,
and offered Matt two ways out. He chose **option 1: split size into a slow base plus a small
fast accent.** Building it turned up two measurement errors in §8 itself.

### 9.1 ⚠ A GLOBAL z-SCORE CANNOT SEE A SMALL ACCENT — §8's flux verdict was measured wrong

§8 ranked candidates by mean z-score at event times, where z is against the WHOLE signal's
standard deviation. That statistic is structurally blind to the design it was being used to
evaluate: the base's slow section swing dominates the standard deviation, so a deliberately
small accent moves z by almost nothing no matter how well aligned it is. Worse, maximising a
noisy signal over a ±120 ms window **rewards variance**, so §8's ranking put the highest
scores on the fastest, noisiest fields.

Both §8 tables should be read with that in mind. The corrected criterion is a **local rise
with a specificity control**: the value at the event minus its own value 100–300 ms earlier,
divided by the same statistic at 250 random NON-event times (≥ 0.6 s from any event). Ratio
> 1 means the visual moves more when a sound lands than when one does not.

That bar is admissible because it separates known-good from known-bad, which is the test §7.8
says a new metric must pass before it is trusted:

| build | evt/rand |
|---|---|
| ORACLE — a perfect event detector as the accent | **3.08×** |
| FTR.23 shipped — the build Matt rejected 7× | 1.53× |
| a RANDOM accent at matched travel (specificity control) | 1.11× |

### 9.2 The §8 field ranking, re-measured with the control

The order changes completely, and the fields §8 nominated turn out to be the worst of them:

| field | §8 rank (z) | corrected (evt/rand) |
|---|---|---|
| `spectral_section_ratio` | +0.71 | 1.80× *(but rise/sd 0.016 — negligible amplitude)* |
| `bassDev` | +0.91 | **1.75×** |
| `spectralFlux` | +0.94 | 1.50× |
| `arousal` | +0.05 | 1.31× |
| `beatBass` | **+0.99** | 1.02× |
| `beatMid` | **+1.00** | **0.83× — BELOW CHANCE** |
| `spectral_density` | −0.41 | 0.32× |
| `spectral_surge` *(the driver)* | −0.52 | 0.25× |

**★★ The beat fields are not event markers at all.** They scored top on z purely because they
are high-variance saturating pulses — which this project's own notes already said (`beat_mid`
is *"a CLOCK, not music"*). §8's closing recommendation — that the only remaining candidates
were `beatBass`/`beatMid` and needed Matt's call on beat-driven growth — was therefore wrong,
and no such call is needed. `pulse_amp01` appeared to score 46× and is a near-zero-denominator
artefact: its mean rise at random times is ~0 because it is periodic, so the ratio explodes.
Always read the numerator before believing a ratio.

Through the full composition, **every existing-field accent scored WORSE than the base it was
added to** (`bassDev` 1.14–1.22×, flux 1.26–1.40×, the mix 1.18–1.24×, against 1.53×): a driver
that also fires between events dilutes specificity rather than adding it. §8's structural
conclusion survives its own broken metric — no existing field can drive this layer.

### 9.3 What the accent needed was a new primitive, and it was one line of DSP away

The oracle is not exotic: it is a fast rise in pre-AGC level. `SpectralAnalyzer` already
computes that level every frame (`LoudnessProfile.levelDB`, Parseval, pre-AGC) — it was simply
never exposed unsmoothed. Every existing consumer reads `smoothedLevelDB`, **τ 0.76 s**, and
that follower is precisely what erases a transient; `spectral_surge` ranks it, which is the
whole mechanism behind its 0.25×.

`spectral_level_rise` (FeatureVector float 53): rise of the UNSMOOTHED level over a 0.15 s
trailing MINIMUM, mapped through a 4→12 dB smoothstep, instant attack, 0.20 s release.

Validated on four tracks chosen offline for different production, plus two captures:

| material | evt/rand | detector fires |
|---|---|---|
| Seven Nation Army (sparse rock) | 20.5× | 1.32/s |
| Brouwer — solo classical guitar | 6.8× | 1.04/s |
| Beethoven Op. 13 Rondo — solo piano | 4.1× | 1.17/s |
| Autechre *13x0 step* — dense limited electronica | **1.2× — near chance** | 0.64/s |

⚠ Two honest caveats. The detector and the criterion are the same quantity, so this is a
DEFINITION of "audible event", not a proxy validated against one. And it fails on dense limited
electronica — the FTR.15 limiter mechanism at transient scale — which is a real coverage hole,
not a tuning gap.

### 9.4 ★★★ DUTY CYCLE, NOT GAIN, IS WHAT MAKES AN ACCENT AN ACCENT

The first calibration (2–6 dB band, 0.35 s release) fired 1.47/s and was non-zero **75 % of the
time**, so it stopped being an accent and became a DC LIFT: the size term's p05 floor rose 46 %
(0.281 → 0.409) and its span fell 25 %. That is the FTR.16 defect Matt rejected as *"you fed
the preset ambien"*, arriving by a new route.

Every attempt to fix it at the consumer failed in the same shape — headroom scaling, `×base`
weighting, `×(0.4+0.6·base)`, and gain sweeps all traded event alignment against the floor
**monotonically**, because what lifts a floor is how OFTEN the accent is non-zero, not how big
it is. Tightening the detector inverted the trade at a stroke:

| calibration | duty | evt/rand | span |
|---|---|---|---|
| 2–6 dB, 0.35 s release | 75 % | 4.16× | 0.292 (−38 %) |
| 3–9 dB, 0.20 s | 64 % | 5.19× | 0.392 (−17 %) |
| **4–12 dB, 0.20 s (shipped)** | **48 %** | see below | **0.425 (−10 %)** |

### 9.5 The shipped build

`size = saturate(base + 0.45 · spectral_level_rise · (1 − base))`, accent read LIVE from
buffer(0) inside the held evaluation (an accent that latches to the beat grid is not an accent),
applied to the trunk and canopy scale but **not** to the branch count, which is quantised and
whose popping is the "stuttering" FTR.13 was spent on.

| | evt/rand | total travel | span |
|---|---|---|---|
| FTR.23 shipped | 1.53× | 8.04 | 0.472 |
| + accent 0.30 | 2.72× | 8.99 (+12 %) | 0.437 (−7 %) |
| **+ accent 0.45 (shipped)** | **3.77×** | 10.06 (+25 %) | 0.425 (−10 %) |
| + accent 0.55 | 4.57× | 10.88 (+35 %) | 0.418 (−11 %) |

**2.5× the event alignment for 25 % more motion and 10 % less span**, and the extra motion is
spent ON events rather than between them. Rendered, the accent moves 2.7 mean |Δpixel| between
`spectral_level_rise` 0 and 1 on an otherwise identical frame (canopy width 0.173 → 0.339),
which is a sustained accent — an upper bound no real 0.20 s event reaches.

### 9.6 ⚠ TWO OPEN CONFLICTS FOR MATT, both left red rather than tuned

1. **The accent breaks FTR.10's trunk-hold contract.** Fed on Matt's own capture, the trunk's
   held turn rate is **1.80 turns/beat against the gate's 0.38 bar**. An event accent cannot be
   beat-latched and still mark events, so the FTR.10 contract ("the trunk holds between beats
   and steps on them", his choice, twice) and the FTR.24 accent (his choice) are mutually
   exclusive on the trunk. The gate is LEFT UNCHANGED and red under `FT_ACCENT_FROM_TAP=1` —
   changing a metric in the increment it goes red is the FTR.6 move. **Note the committed suite
   is GREEN only because the captures predate the column**; that green is not evidence.
2. **`spectral_flux` is still on branch spread**, against Matt's instruction, pending his call.
   Removing it was measured: drive-range response falls from **1.067 to 0.119** mean |Δpixel|
   p05→p95 — the spread carries **89 % of this preset's measured response across its own energy
   range** — and the preset's own dead-route gate fails. His instruction was given to free flux
   for the size term, which measurement then ruled out, so the trade it was making no longer
   exists. A static canopy makes "no clear connection to the music" worse, not better.
