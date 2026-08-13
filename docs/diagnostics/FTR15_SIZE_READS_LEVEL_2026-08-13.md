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
