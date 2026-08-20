# FT.3 tasks 4–6 — `BarLineEstimator`: the port, its threshold, and what it costs

**Date:** 2026-08-19 · **Status:** engine component + measurement; **not wired into playback**
**Code:** `PhospheneEngine/Sources/DSP/BarLineEstimator{,+Features}.swift`
**Reference:** `tools/barline_parity.py` · **Basis:** `BARLINE_PROBE_2026-07-31.md`,
`FT3_BARLINE_TASKS_1_3_2026-07-31.md`

Tasks 1–3 (unseen tracks, phase, combination rule) landed at `35f2d68b` and stopped before
the port by the spec's own task-2 rule. Matt's call on the §10 decision was **build it**, so
this is tasks 4–6: the Swift port and its parity gate, the decline threshold, and the A/B.

**Headline.** The port is exact — worst |Δmargin| **1.6e-7** against the Python reference on
all 17 tracks, four orders of magnitude inside the 1e-3 gate, with meter agreeing on 17/17
and phase on every undeclined track. The threshold, set from the measured distribution,
lands at **1.24**, and the reason it is that high is the finding: **labelled by *bar* rather
than by *meter*, the correct and incorrect margins overlap**, exactly as DBN.2's did. At the
operating point the estimator answers 2 of the 9 ground-truthed tracks, gets both right, and
declines the other 7.

---

## Pre-flight — two spec invariants failed, both stale rather than broken

- **`main` is `6d20c9e9`, not `7dc822e6`.** `7dc822e6` is not a valid object in this repo at
  all; it was the tip of the unmerged `claude/ft3-barline-spec` branch when the spec was
  written, and that work has since landed through `main` (`5cbc9e03`, `afa3b6be`,
  `35f2d68b`, `b4c11b02`). Every artifact the spec depends on is present.
- **Tasks 1–3 were already complete** when this session opened — commit `35f2d68b`,
  2026-07-31, together with `docs/diagnostics/FT3_BARLINE_TASKS_1_3_2026-07-31.md`, the
  FT.3.1 follow-on spec, and D-210. This session did not redo them.

Lint 0/519, engine suite green, fixtures and ground truth present. `Scripts/link_fixtures.sh`
was needed to bring the gitignored fixtures into the worktree.

---

## Task 4 — the port, and why the parity gate needed a new null

### The problem with the gate as specified

The spec asks the Swift port to reproduce "the Python probe's per-track margins to within
1e-3". That is unachievable against `barline_probe.py` / `barline_combine.py` as written, and
not because of anything a port does. Their permutation null is a **200-draw Monte-Carlo
estimate** consumed from one numpy PCG64 stream in whatever order tracks and features happen
to be visited. Measured, over 5 seeds:

| track | m3 range | m4 range | m5 range | m7 range | worst vs the 1e-3 gate |
|---|---|---|---|---|---|
| billie_jean | 0.0110 | 0.0065 | 0.0187 | 0.0294 | **29×** |
| money | 0.0192 | 0.0181 | 0.0097 | 0.0115 | **19×** |

Reproducing that number in Swift would mean reimplementing PCG64 *and* numpy's
`Generator.shuffle` *and* the exact call ordering — and the result would still be a
Monte-Carlo sample rather than a value.

So the null was made **deterministic on both sides**: a 15-line SplitMix64 plus Fisher–Yates,
specified in `tools/barline_parity.py` and reimplemented identically in
`BarLineEstimator.swift`, with a known-answer test on both the raw stream and a reference
permutation so the two cannot drift apart silently. Both languages now compute the *same*
null instead of two samples of it, and the estimator gains run-to-run determinism, which an
engine component wants regardless. Everything else — features, contrast statistic,
`sum_margin` — is unchanged.

**One thing this is NOT.** The jitter above does not mean the method was unstable. Within a
seed the noise is correlated across meters, so the *ranking* survives it: over 25 seeds under
the original stochastic null, money picks 7 **25/25**, bohemian_rhapsody picks 4 **25/25**,
solsbury_hill picks 7 **25/25**. The deterministic null was needed for the *gate*, not to
rescue the result.

### Parity result — 1.6e-7 worst case, 17/17 tracks

`PHOSPHENE_BARLINE_PARITY=… swift test --filter BarLineEstimatorParityTests`, comparing all
four per-meter margins (not just the winner — a port can pick the same meter for the wrong
reasons):

| track | meter swift/py | phase swift/py | max &#124;Δmargin&#124; |
|---|---|---|---|
| around_the_world | 4 / 4 | declined / 3 | 1.1e-08 |
| billie_jean | 4 / 4 | 2 / 2 | 1.3e-08 |
| bleed | 4 / 4 | declined / 3 | 1.2e-08 |
| bohemian_rhapsody | 4 / 4 | declined / 3 | 9.0e-09 |
| clair_de_lune | 3 / 3 | declined / 2 | 1.2e-08 |
| dance_yrself_clean | 4 / 4 | 3 / 3 | 9.7e-09 |
| giorgio_by_moroder | 4 / 4 | declined / 1 | 6.2e-09 |
| girl_from_ipanema | 4 / 4 | 2 / 2 | 7.5e-09 |
| money | 7 / 7 | declined / 5 | 3.0e-08 |
| pyramid_song | 7 / 7 | declined / 5 | 2.7e-08 |
| so_what | 4 / 4 | 3 / 3 | 3.0e-08 |
| solsbury_hill | 7 / 7 | declined / 4 | 1.7e-08 |
| stayin_alive | 4 / 4 | 3 / 3 | 2.5e-08 |
| superstition | 4 / 4 | 3 / 3 | 4.6e-08 |
| take_five | 5 / 5 | 0 / 0 | 4.8e-09 |
| there_there | 4 / 4 | 1 / 1 | **1.6e-07** |
| yyz | 4 / 4 | 2 / 2 | 3.0e-08 |

Both arms decode through the identical `ffmpeg -ac 1 -ar 22050 -f f32le` invocation, so the
gate measures the port and not two decoders. Residual is float64 FFT and summation-order
noise.

The reference reproduces **6/6** on the ground-truthed meters and **8/8** on the unseen set
under `sum_margin` with the deterministic null, so the basis did not move under the change.

---

## Task 5 — the decline threshold, and the overlap it has to live with

Margins on the nine ground-truthed tracks, labelled two ways. The labelling is the whole
question: FT.3's own spec says a correct meter on the wrong phase is "visually identical to
being wrong", so **bar** (meter AND phase ≥ 50 % of downbeat taps) is the label that matters
and **meter** alone is the flattering one.

| labelling | correct | incorrect | verdict |
|---|---|---|---|
| METER only | −0.024, +0.106, +0.136, +0.226, +2.254, +2.930 (6) | none (0) | trivially separable |
| **BAR (meter AND phase)** | +0.136, +2.254, +2.930 (3) | −0.024, +0.106, +0.226 (3) | **OVERLAP** |

**Stated plainly, as the spec requires: correct and incorrect margins overlap.** Incorrect
reaches +0.226 (money — meter 7 right, phase off by exactly one beat) while correct starts at
+0.136 (bohemian_rhapsody). No threshold both keeps every correct bar and admits no wrong
one. This is DBN.2's situation, and pretending otherwise would be worse than declining.

### The sweep, so the operating point is visible rather than asserted

`kept dbF` averages only undeclined tracks; `all dbF` charges every decline a 0.00 the way a
consumer would experience it.

| threshold | kept | bar OK | conf-wrong | kept dbF | all dbF |
|---|---|---|---|---|---|
| −0.024 | 5 | 3 | **2** | 0.50 | 0.41 |
| 0.106 | 4 | 3 | **1** | 0.58 | 0.38 |
| 0.136 | 3 | 2 | **1** | 0.60 | 0.30 |
| 0.226 | 2 | 2 | 0 | 0.90 | 0.30 |
| **1.240** | **2** | **2** | **0** | **0.90** | **0.30** | ← operating point |
| 2.254 | 1 | 1 | 0 | 0.97 | 0.16 |

**Derivation of 1.24.** The objective *(correct kept − incorrect admitted)* has **two equal
maxima**: the interval (0.106, 0.136] and the interval (0.226, 2.254], both scoring 2.
D-207's product call breaks the tie — "decline when unsure", because a wrong bar-1 fires the
accent on an arbitrary beat of *every* bar — so the interval that admits **zero**
confident-wrong answers wins. 1.24 is that interval's midpoint, placing it as far as the data
allows from both observed edges. **The nine tracks put no observation anywhere between 0.226
and 2.254**, so every threshold in that band is equally supported; 1.24 is not a tuned value,
it is the middle of the empty region.

**Decline rate.** 7/9 on the ground-truthed catalogue (78 %) and 2/8 on the unseen set (25 %).
The catalogue is deliberately the hard material — three odd meters, one rubato, one
polyrhythm — so those two rates are not in conflict; ordinary 4/4 material is answered three
times out of four.

---

## Task 6 — the local-path A/B

Both arms read the **same full-track grid** (FT.1's tiler), so this isolates FT.3's method
change from FT.1's window change; it is deliberately not a comparison against the 30 s
`BEATBENCH_BASELINE_2026-07-30.md` rows.

**One deviation from `Metrics.fMeasure`, applied identically to both arms.**
`BeatBench.swift` trims only the *reference* to the grid's span, which is right when the grid
is a 30 s preview and the taps cover more. Here the grid is the whole track and the taps
cover part of it (billie_jean: 34 downbeats over 1.6–69.1 s of a ~294 s track), so an
untrimmed estimate is charged on precision for every bar outside the tapped region —
billie_jean scores **0.37 with a perfect bar line** that way. Both sides are trimmed to the
tapped span instead.

| track | truth | inc. meter | inc. dbF | our meter | margin | our dbF | phase | ceiling |
|---|---|---|---|---|---|---|---|---|
| billie_jean | 4 | 4 ✓ | 0.97 | **4 ✓** | 2.930 | **0.97** | 100 % | 100 % |
| bleed | 4 | 2 ✗ | 0.37 | declined | 0.106 | 0.00 | 16 % | 37 % |
| bohemian_rhapsody | 4 | 3 ✗ | 0.66 | declined | 0.136 | 0.00 | 68 % | 68 % |
| clair_de_lune | — | 2 | 0.00 | declined | 0.133 | 0.00 | 33 % | 42 % |
| money | 7 | 2 ✗ | 0.27 | declined | 0.226 | 0.00 | 0 % | 79 % |
| pyramid_song | — | 3 | 0.00 | declined | −0.056 | 0.00 | 0 % | 0 % |
| solsbury_hill | 7 | 1 ✗ | 0.15 | declined | −0.024 | 0.00 | 14 % | 16 % |
| take_five | 5 | 2 ✗ | 0.33 | **5 ✓** | 2.254 | **0.82** | 85 % | 85 % |
| yyz | — | 4 | 0.29 | 4 | 1.788 | 0.27 | 50 % | 50 % |

| metric | incumbent | BarLineEstimator |
|---|---|---|
| meter correct (of 6 truthed) | 1/6 | **2/6** |
| bar correct — meter AND phase, undeclined | — | **2/6** |
| mean downbeat F, all 6 truthed | **0.459** | 0.298 |
| mean downbeat F, the 2 tracks it answers | 0.651 | **0.895** |
| meter emitted but wrong | 5 | **0** |
| decline rate | 0/9 (no decline path) | 7/9 |

**Reported as a regression, per the beatbench claim rules: mean downbeat F over all six
truthed tracks drops 0.459 → 0.298.** Every point of that drop is a decline scoring 0.00.
The incumbent emits a downbeat *stream* straight from the model's activations, so it can
score 0.66 on bohemian_rhapsody while deriving the wrong `beatsPerBar` (3) — its downbeat F
and its bar position are not the same claim. On the two tracks this estimator answers it is
better (0.895 vs 0.651), and it emits **zero** wrong meters against the
incumbent's five. Which of those matters is a product call, not an engineering one.

**In fairness to the incumbent, its `barConfidence` is not blind either** —
1.00 on the one track it gets right, 0.28–0.73 on the five it gets wrong
(money 0.28, take_five 0.35, bohemian 0.38, bleed 0.42, solsbury_hill 0.73). `BeatGridResolver`
simply has no decline path, so it emits the wrong meter regardless. That signal is not a rival
to this estimator on the evidence here — with only one correct track in the set it separates
nothing that can be measured — but it should not be described as absent.

**No five-suite BeatBench before/after table is included, and none is owed:** nothing calls
`BarLineEstimator`. `BeatGridResolver`, `BeatActivationDecoder`, `LiveBeatDriftTracker` and
every playback path are untouched — **no behavioral change to beat sync**. Integration is
FT.2's, after its re-scope.

---

## What this does and does not establish

- The port is **exact**, and the parity gate is a real test rather than a comparison of two
  Monte-Carlo draws.
- The threshold is **derived**, and the overlap it cannot remove is stated rather than hidden.
- **Meter is not the deliverable; the bar is.** The estimator answers 2 of 9 truthed tracks —
  and the reason the other 7 decline is the wrong-metrical-level gap D-210 already records:
  on 4 of 6 the engine grid is not at the ground truth's beat, so a global beat index does
  not name the bar line. **No accent-feature work closes that**, which is FT.3.1's question.
- **Nothing the user sees changes.** With no consumer wired up, this increment's product
  value is entirely contingent on FT.2 and FT.3.1.

## Reproduce

```bash
Scripts/link_fixtures.sh
mkdir -p /tmp/barprobe
PHOSPHENE_FT1_FULLTRACK=1 PHOSPHENE_BEATS_DUMP=/tmp/barprobe \
  swift test --package-path PhospheneEngine --filter FullTrackMeter

~/phosphene-ml-env/bin/python tools/barline_parity.py \
  --beats-dir /tmp/barprobe --fixtures ~/phosphene_beatbench_fixtures \
  --ab --out /tmp/barprobe/parity.json

PHOSPHENE_BARLINE_PARITY=/tmp/barprobe/parity.json PHOSPHENE_BEATS_DUMP=/tmp/barprobe \
  swift test --package-path PhospheneEngine --filter BarLineEstimatorParityTests
```
