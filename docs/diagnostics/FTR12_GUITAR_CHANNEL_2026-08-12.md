# FTR.12 — Does a guitar channel exist at all?

**Date:** 2026-08-12 · **Type:** engine measurement · **No preset behaviour changed.**

**Verdict, in one sentence:**
**No per-stem feature separates guitar from drums on any of the 7 tracks** — and on the
sharpest test in the corpus, `otherOnsetRate`'s correlation with `drumsOnsetRate` is
**highest (+0.792) on a solo piano recording that contains neither a guitar nor a drum kit**,
and lowest (+0.492) on Seven Nation Army.

The one thing that did separate guitar from not-guitar is not a stem feature: the PANNs
527-class probabilities Phosphene already computes carry guitar classes that read **0.52–0.58**
on clean guitar against **0.004–0.096** on the guitarless controls. That channel is real but
weak exactly where Fractal Tree needs it — on distorted rock guitar it reads 0.07–0.09, inside
the guitarless range, and a dense player-piano recording false-positives at p95. §6.

---

## 1. What was asked, and why

Fractal Tree's tips have read `other_onset_rate` since FTR.8, justified by **one** measurement
on **one** track: r = +0.14 against `drums_onset_rate` on Cherub Rock (session
`2026-08-11T01-07-17Z`), recorded in the shader as *"a genuinely INDEPENDENT channel, not a
re-spelling of the drums."* FTR.11 then measured the same feature on Seven Nation Army and got
**+0.71** — the same route reading the drums under a label that says guitar. Matt, seeing it
live: *"Guitar is barely registering."* His call, taken 2026-08-11, was to **measure across
material first, before touching the preset**.

A "no" is a complete result for this increment. It retires the guitar ambition on measured
grounds instead of funding a fourth attempt at it.

## 2. Method

`Scripts/ftr12_guitar_channel.sh` → `GuitarChannelReportTests` (`--filter GuitarChannel`).

Decode mono at the target rate (ffmpeg, so no resampler sits between the corpus and the
measurement) → `StemSeparator.separate` in 441 000-sample chunks, the separator's output-buffer
capacity and the model's fixed ~10 s window (`modelFrameCount = 431`) → `StemAnalyzer.analyze`
per 1024-sample hop. That hop loop is `SessionPreparer.warmUpAndAnalyze`'s exact framing,
capturing every frame instead of only the warmed-up last one. **Production objects, no proxy.**
First 120 s of each track; 5 090–5 160 analysis frames per track at 43.07 Hz.

**Offline, not capture replay, and that is the point.** The ten sessions on disk are four rock
tracks Matt happened to play; they cannot answer a question about whether a feature
*generalises*. Offline selection costs no live-session time and lets the corpus carry the
guitarless negative controls that make the question decidable.

**These numbers survive BUG-086.** Stem-vs-stem correlation is lag-immune: both series come out
of the same separation pass, so the ≈2.9 s preset-facing latency cancels exactly. No comparison
against a non-stem series (a `FeatureVector` field, the beat grid) is made anywhere here — those
would need an explicit lag sweep, as the FTR.11 trunk-vs-stem numbers did.

**Statistics.** Whole-series Pearson r per stem pair; p05/p50/p95; distinct-value count; and
CHR.1's common-mode share `1 − var(x − mean₄)/var(x)`, read against the **≈22 % null** CHR.1
§1.1 measured with a timing-destroyed control.

**Analysis rate.** `analyze(fps:)` sets every internal EMA's time constant, so it is a real
knob. This harness passes 43.07 Hz, matching the production **offline** path; the live path
calls `analyze` once per render frame. `onsetRate`'s decays are `exp(-dt/τ)` with real τ and its
refractory is `0.100/dt` frames, i.e. the feature is dt-correct by construction — and the
rate-sensitivity check in §5 confirms r moves only 0.04–0.09 between 43 Hz and 60 Hz.

## 3. The corpus, with the role of each track

| label | role | track | why this slot |
|---|---|---|---|
| `brouwer` | **positive** | Leo Brouwer, *El Decameron Negro: El Arpa del guerrero* (John Williams, 1997) | **Solo classical guitar, nothing else on the record.** The decisive positive: the `other` stem *is* the guitar and the other three stems are pure separation residue. |
| `wesmont` | **positive** | Wes Montgomery, *Four On Six* (1960) | Clean electric guitar lead, prominent, **with real drums and bass** — so the drums control stem carries actual audio, which `brouwer` cannot provide. |
| `nancarrow` | **negative** | Conlon Nancarrow, *Study for Player Piano No. 3a* (1999) | Solo player piano. **The adversarial negative:** dense plucked/struck transients in the guitar's own register, no guitar, no drums. If `otherOnsetRate` is reading "mid-register attacks" rather than guitar, this track looks exactly like a guitar track. |
| `autechre` | **negative** | Autechre, *13x0 step* (2016) | Pure synthesis with heavy programmed percussion. **Guitarless but with a real drums channel** — the only negative where the other-vs-drums comparison has two live stems. |
| `beethoven` | **negative** | Beethoven, Sonata No. 8 *Pathétique*, Rondo (Barenboim, 1989) | Sparse solo piano; the low-density guitarless case. |
| `sna` | **hard** | The White Stripes, *Seven Nation Army* (2003) | Distorted guitar in a **sparse** mix. Continuity with FTR.11 (+0.71). |
| `cherub` | **hard** | Smashing Pumpkins, *Cherub Rock* (1993) | Distorted guitar in a **dense** mix. Continuity with FTR.8, the single track that justified the route (+0.14). |

**How guitarlessness was established, honestly.** Not by genre bucket, and **not by ear** — it
rests on the works' *definitional* instrumentation: a Nancarrow player-piano study, a Beethoven
piano sonata movement and an Autechre synthesis piece admit no guitar by construction, which is
a stronger basis than a listening pass would give. The one thing this does not exclude is a
mislabelled file; the PANNs panel in §6 is consistent with all three being guitarless
(p50 ≤ 0.096 against 0.52–0.58 on the positives), but that panel is *reported*, not used to
validate the controls it is then judged against.

## 4. The measurement

`other` stem, all four features, `r` against the **same feature on another stem**. Null is 0.00.

### `otherOnsetRate` — the feature Fractal Tree's tips actually read

| track | role | r : drums | r : bass | r : vocals | p05 | p50 | p95 | distinct | cm |
|---|---|---|---|---|---|---|---|---|---|
| `brouwer` | pos | +0.675 | +0.605 | **+0.895** | 1.90 | 4.46 | 6.22 | 5117 | 83 % |
| `wesmont` | pos | +0.647 | +0.535 | +0.935 | 2.36 | 4.21 | 6.10 | 5158 | 82 % |
| `nancarrow` | **neg** | +0.578 | +0.264 | +0.939 | 3.31 | 4.86 | 6.51 | 5160 | 78 % |
| `autechre` | **neg** | +0.547 | +0.559 | +0.665 | 3.13 | 5.33 | 7.30 | 5160 | 74 % |
| `beethoven` | **neg** | **+0.792** | +0.707 | +0.926 | 2.13 | 4.53 | 6.52 | 5147 | 88 % |
| `sna` | hard | **+0.492** | +0.519 | +0.631 | 2.01 | 4.06 | 5.86 | 5110 | 72 % |
| `cherub` | hard | +0.606 | +0.557 | +0.734 | 3.15 | 5.00 | 6.52 | 5115 | 75 % |

### The envelope features — worse, and uniformly so

`r(other, drums)` on the same feature:

| track | role | `energyRel` | `energyDev` | `energySlope` | cm (energyRel) |
|---|---|---|---|---|---|
| `brouwer` | pos | **+0.987** | +0.985 | +0.986 | **99 %** |
| `wesmont` | pos | +0.933 | +0.941 | +0.911 | 96 % |
| `nancarrow` | neg | +0.935 | +0.948 | +0.873 | 95 % |
| `autechre` | neg | +0.918 | +0.896 | +0.864 | 97 % |
| `beethoven` | neg | +0.945 | +0.925 | +0.934 | 94 % |
| `sna` | hard | +0.906 | +0.887 | +0.893 | 97 % |
| `cherub` | hard | +0.894 | +0.890 | +0.813 | 97 % |

Every value is +0.81…+0.99 and common mode is 91–99 % against a ≈22 % null. **This is CHR.1's
finding reproduced at the extreme**: the `other` trace is very nearly a redundant redraw of the
mix, and on solo classical guitar it is that redraw to three decimal places.

### The two rows that settle it

1. **`beethoven` scores the corpus's HIGHEST other-vs-drums onset-rate correlation (+0.792)** —
   on a recording with no guitar and no drum kit — while **`sna` scores the LOWEST (+0.492)**.
   The statistic that was supposed to say "this stem is independent of the drums" ranks a solo
   piano as *more* drum-like than a rock track. It is not reading instrumentation.

2. **On `brouwer` the drums stem, which contains nothing but separation residue, produces a
   HIGHER onset rate than the guitar does.** `drumsOnsetRate` p50 = **4.71** against
   `otherOnsetRate` p50 = **4.46**; and `otherOnsetRate` correlates **+0.895 with
   `vocalsOnsetRate`** on a record with no voice, while `otherEnergyRel` correlates **+0.998**
   with it. On a recording containing exactly one instrument, all four stems' features are the
   same series.

### And the distributions are interchangeable

`otherOnsetRate` p50 across the whole corpus spans **4.06 … 5.33** — solo classical guitar
(4.46) sits between pure synthesis (5.33) and distorted rock (4.06), and every track's `other`
p50 tracks its own `drums` p50 within ≈0.3. A feature that reads the same on a Nancarrow player
piano and on Cherub Rock is not a guitar channel at any coefficient. This is FTR.11's
"all four stems share one distribution" observation confirmed across seven tracks and three
genres it had never seen.

## 5. Why — the mechanism, read from the code not inferred

`StemAnalyzer+RichMetadata.computeRichFeatures` derives `onsetRate` from **broadband RMS flux
against an adaptive relative threshold**: `flux = max(0, rms − prevRMS)`, `fluxEMA` a 0.9/0.1
EMA of it, and an onset fires on a rising edge past `fluxEMA * 1.5` with a 100 ms refractory.

A *relative* threshold on a stem's own recent flux fires at a broadly similar rate on **any**
signal with transient content — which is precisely what the table shows. The 100 ms refractory
caps it at 10 /s and the corpus sits at 4–5 /s, so the detector runs near-saturated on
everything. `otherOnsetRate` measures *"how often does this stem's RMS rise 1.5× above its own
recent average flux"*, which is a property of the detector, not of the instrument.

**MEL.1 is not contradicted, it is extended.** MEL.1 measured that per-*note* guitar onset
detection fails under distortion (31 % grid coherence against a 41 % drums control), and FA #68
generalises that to the spectral-onset family. FTR.12 asked the deliberately weaker
rate-and-envelope question and finds the weaker question fails too — for a different reason.
The rate does not fail because attacks are smeared; it fails because an adaptive-threshold rate
is content-independent.

**Rate-sensitivity check** (`FTR12_FPS=60`, the live path's cadence): `cherub` +0.606 → +0.700,
`sna` +0.492 → +0.529. r moves 0.04–0.09, so the verdict is not an artifact of the offline
analysis rate.

## 6. The recognizer — the one thing that did separate, and its limit

**IFC.4 cannot answer this question by construction, and that is a structural fact worth
recording.** Its four families resolve to AudioSet indices `strings [189–194, 199]` (bowed
strings + harp), `brass [185–188]`, `woodwinds [195–198]`, `percussion [161…182]`. **No family
contains any guitar class.** The series is reachable offline and reports nothing about guitars.

The 527-class probabilities the same model already computes *do* carry them
(`139` Plucked string, `140` Guitar, `141` Electric guitar, `143` Acoustic guitar, `144`
Steel/slide, `146` Strum — indices resolved from `~/panns_data/class_labels_indices.csv` and
cross-checked against the repo's committed `family_indices` fixture; `142` Bass guitar excluded,
that is the bass line). Max over those classes, per 1 s window:

| track | role | guitar p50 | guitar p95 | IFC.4 strings p50 | IFC.4 percussion p50 |
|---|---|---|---|---|---|
| `brouwer` | pos | **0.582** | 0.792 | 0.088 | 0.004 |
| `wesmont` | pos | **0.517** | 0.727 | 0.038 | 0.094 |
| `nancarrow` | neg | 0.096 | **0.390** | 0.092 | 0.009 |
| `autechre` | neg | 0.006 | 0.035 | 0.001 | 0.036 |
| `beethoven` | neg | 0.004 | 0.149 | 0.014 | 0.007 |
| `sna` | hard | 0.071 | 0.460 | 0.003 | 0.073 |
| `cherub` | hard | 0.086 | 0.270 | 0.002 | 0.040 |

**It separates clean guitar decisively — 0.52–0.58 against ≤ 0.096, a 5–150× margin — and it
does not separate the material Fractal Tree needs.** On the two distorted rock tracks it reads
0.071 / 0.086 at p50, *inside* the guitarless range and below `nancarrow`'s 0.096. Only p95
distinguishes them (0.460 / 0.270 against `beethoven` 0.149, `autechre` 0.035), i.e. the
recognizer catches distorted guitar intermittently, not continuously. And `nancarrow`'s p95 of
**0.390** is a false positive comparable to `sna` — a dense player piano reads as guitar to this
model about as strongly as an actual distorted guitar does.

So the recognizer is a real channel for *clean, prominent* guitar and not a usable one for
distorted rock guitar. It is reported here because it changes what the options are, not because
it is a solution.

## 7. What this invalidates in the repo

| claim | where | status after this measurement |
|---|---|---|
| `other_onset_rate` r = **+0.14** with drums, therefore *"a genuinely INDEPENDENT channel, not a re-spelling of the drums"* | `FractalTree.metal` FTR.8 routing note; `ENGINEERING_PLAN.md` §FTR.8 | **Retired.** It is a **single-track** figure and it does not reproduce: offline on Cherub Rock the same feature reads **+0.606** at 43 Hz and **+0.700** at 60 Hz. The two capture figures behind the route (+0.14 Cherub, +0.71 SNA) disagree by 0.57 on the same feature, so a single-capture r on this quantity is not a stable number regardless of which is closer to right. |
| the tips *"follow the guitar patterns"* / `other_onset_rate` = *"how many guitar attacks per second"* | `FractalTree.metal` §THE TIPS ← THE GUITAR | **Not supported.** The feature reads 4.46 /s on solo classical guitar and 4.86 /s on a guitarless player piano. |
| *"the finest branches … flickering in and out with the guitar"* | `FractalTree.json` `description` | **Not supported** on measured material. Matt's *"Guitar is barely registering"* is the same fact observed live. |
| the **+0.973** guitar/drums correlation repeated since FTR.6, *"corrected"* at FTR.8 to +0.68 (energy) / +0.65 (energy-dev) | `ENGINEERING_PLAN.md` §FTR.8 | **The correction is itself unreliable.** This corpus reads `otherEnergyRel` vs drums at **+0.89…+0.99** on all seven tracks — above FTR.8's capture figures and consistent with the +0.973 they replaced. Which path is right is not settled here; the point is that both are single-path readings and the capture-vs-offline gap (also seen on `otherOnsetRate`, §5) is unexplained. |
| IFC.4's family series could carry guitar activity | FTR.12's own spec | **Structurally impossible** — no family contains a guitar class (§6). |

**Not invalidated:** FTR.10 and FTR.11's beat-stepping work, which is about *how much* motion
there is, not which stem drives it. Fractal Tree remains **not certified** and FTR.11 remains
**unverified live** — Matt's M7 on the stepped frame is still outstanding, and nothing here
changes or waits on it.

## 8. Limitations, stated

1. **Seven tracks, three genres.** Enough to retire a claim that rested on one track; not a
   census. The negatives were chosen to be decisive rather than representative.
2. **Guitarlessness rests on definitional instrumentation, not a listening pass** (§3).
3. **The absolute p05/p50/p95 figures are offline-path values.** They are not comparable to
   `stems.csv` columns from a live capture — FTR.8's live Cherub Rock reading spanned
   0.53…3.30 across 374 distinct values where this harness reads 3.15…6.52 across 5115.
   Correlation is scale-invariant and is what §4 relies on; §5's rate check bounds its
   sensitivity at 0.04–0.09.
4. **First 120 s per track.** A guitar solo later in a track is outside the window. This makes
   the negative result *weaker*, not stronger — but the positives were also measured on 120 s
   and separated fine on the recognizer, so the window is not what suppressed the stem features.
5. **No lag sweep, because no non-stem comparison was made** (§2). Any follow-up that compares a
   stem feature to a `FeatureVector` field or the beat grid must add one.

## 9. Cross-references

- **CHR.1** `docs/diagnostics/CHR1_STEM_DECORRELATION_2026-08-11.md` §1.1 (the ≈22 % common-mode
  null), §4 (`other` is 88.8–97.6 % common mode, `r ≥ 0.96` against the full-mix envelope on
  every track). FTR.12 reproduces this on three genres CHR.1 did not cover and on a solo
  single-instrument recording, where it is starkest.
- **BUG-086** `docs/QUALITY/KNOWN_ISSUES.md` — ≈2.9 s preset-facing stem latency, local-file
  path. Cancels in every statistic here (§2).
- **MEL.1** — per-note guitar onset detection, 31 % grid coherence vs a 41 % drums control.
  Extended, not contradicted (§5).
- **FA #68** — the spectral-onset family. §5 adds the adaptive-threshold mechanism that makes
  the *rate* variant content-independent, which is a different failure from the smearing FA #68
  records.
