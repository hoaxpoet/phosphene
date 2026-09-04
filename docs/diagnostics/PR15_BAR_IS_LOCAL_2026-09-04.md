# PR.15 — the bar problem was mis-shaped, not unsolvable

**Matt, 2026-09-04: *"The beat and bar issue is not resolved … why are we abandoning it?"***

Correct challenge. The answer is that it should not have been abandoned, and the reason it looked
unsolvable was the shape of the question, not the difficulty of the problem.

## 1. The confound behind "four failed attempts"

`BarLineEstimator.estimate`'s own doc comment reads:

> *beats: Beat times in seconds, ascending. Typically `BeatGrid.beats` from a **full-track decode**
> (`BeatThisTiledInference`), **not a 30 s window**.*

**In production it has never had that.** `applyBarLineEstimate` receives `grid.beats` from the
clamped predict, so FT.3's calibration, FT.4's A/B, FT.4.1's split and PR.3d's adoption attempt all
fed it ~40–60 beats when it was designed for ~300–700. The four "failed attempts" on the bar share
that confound, and PR.12 removed it.

## 2. First hypothesis — more beats — is FALSIFIED

Whole-track beats, same audio, same options:

| track | 30 s (~50 beats) | whole track (~600 beats) |
|---|---:|---:|
| billie_jean | 2.603 → **4** ✓ | 2.940 → **4** ✓ |
| bleed | 1.348 | **0.075** |
| solsbury_hill | 0.699 | **−0.186** |
| take_five | 1.735 → **5** ✓ | 1.428 → **decline** |
| yyz | 0.095 | 1.599 → 4 |

**Correct answers went 2 → 1.** More evidence made it worse. The margin is a contrast against a
permutation null computed over the whole span, so scoring ONE bar-phase across 900 beats blends
verse, chorus and bridge — a pattern clear over 85 beats washes out over 900.

## 3. The finding: bar structure is LOCAL

Scored over successive 80-beat (~40 s) windows of the same whole-track beat sequence:

| track | tapped | one global answer | per-window |
|---|---:|---|---|
| billie_jean | 4 | 2.940 → 4 ✓ | **6 of 7 windows → 4** ✓ |
| **take_five** | **5** | 1.428 → **decline** | **11 of 11 windows → 5** ✓ |
| **money** | **7** | 0.240 → **decline** | **2 windows → 7** ✓ |
| bleed | 4 | 0.075 → decline | 0 answered, best margin **1.179** |
| bohemian_rhapsody | 4 | 0.107 → decline | 0 answered, best **1.419** |
| solsbury_hill | 7 | −0.186 → decline | 0 answered, best **1.412** |
| yyz | — | 1.599 → 4 | 4 windows → 4 |
| clair_de_lune | — | −0.131 → decline | 0 answered, best 0.172 |
| pyramid_song | — | 0.064 → decline | 0 answered, best 0.327 |

**money answers 7.** That is the defining hard case of the whole beat-sync programme — BUG-001's
ceiling, BUG-013's workaround, D-207's motivating example, four failed attempts — and per window the
estimator gets it right. take_five is unanimous across all eleven windows where the global answer
declines.

**The confident-wrong protection survives.** The two genuinely meterless tracks (clair_de_lune,
pyramid_song) peak at 0.17 and 0.33 — nowhere near answering. Nothing here trades honesty for
coverage.

**Three tracks sit just under the gate** — bleed 1.179, bohemian_rhapsody 1.419, solsbury_hill 1.412
against `declineThreshold = 1.54`. That threshold was fitted to a *global* margin distribution (FT.3,
then re-derived at PR.3d, both on one-answer-per-track margins). It is the wrong operating point for
per-window margins and must be re-derived on the new distribution before any of those three is
claimed.

## 4. Why this is the same lesson as the tempo fix

Matt on tempo: *"you should not be averaging BPM / tempo, you should be recording it over the
duration of the track."* PR.12 acted on that and `BeatGrid.beats` turned out to already be exactly
that record. **The bar needs the identical treatment** — and PR.15's first hypothesis went the wrong
way, making the bar MORE global rather than less. One meter-and-phase per track is the wrong output
shape for music whose sections differ.

## 5. What is NOT done

- **No code ships from this.** This is a measurement; `BeatGrid` still carries one `beatsPerBar` and
  one bar phase, and no consumer can express a per-section bar yet.
- **The threshold is wrong for the new distribution** and must be re-derived against the labelled
  set before per-window answers are trusted.
- **money answers on only 2 of 10 windows.** Under D-207's decline-when-unsure that is the desired
  shape rather than a shortfall, but it is not "money is solved".
- **Nine fixtures.** The whole finding rests on a small catalogue, and three of the nine have
  unsettled ground truth.
