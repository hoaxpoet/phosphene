# CHR.1 — Per-stem decorrelation measurement (2026-08-11)

**Increment:** CHR.1 (MD.6 uplift #8 candidate, source `Martin - charisma`).
**Status: direction A (two traces, rhythm vs melodic) picked by Matt and gated
pass. Then blocked again on a latency finding — see §7b.** No design doc written,
no references curated, no decision filed. This file is the measurement, kept
because it is register-general and outlives whichever concept Matt picks next.

**What was being tested.** The proposed preset ("Stave") draws four luminous
traces, one per stem, each plotting that stem's `x_energy_rel`, so the listener
sees drums / bass / vocals / other as four separate voices. That concept
requires the four series to be visually separable on real music. The CHR.1
prompt made this the load-bearing measurement and specified the stop condition:
*"If drums/bass/other track each other above ~0.9 through most of a dense mix,
four traces collapse into one visually."*

**Verdict: they do not separate. 3 of 3 captures, 8 of 8 tracks, 6 registers.**

---

## 1. Method

Measured on recorded production-pipeline output only — `stems.csv` /
`features.csv` written by `SessionRecorder` during real playback. No synthetic
audio and no hand-authored envelopes (FA #27).

`energyRel` is defined in `PhospheneEngine/Sources/DSP/StemAnalyzer.swift` as
`(energy - runningEMA) * 2.0`, with `energyDev = max(0, energyRel)` (D-026).
That file has **no commits since 2026-07-01**, so the 2026-07-27 capture and the
2026-08-11 capture measure the same code path — the July session is not stale
for this purpose.

Windows of 8.0 s (the trace scroll window the concept proposed), hop 4.0 s,
Pearson r per window, medians across windows. Whole-track correlation was not
used: a chorus correlates everything, and the question is whether *sections*
exist where the voices separate.

Scripts are stdlib-only and read-only; they are reproducible from this file's
description and were not committed (no production code changed this increment).

### 1.1 The control — why the numbers below mean something

Three statistics are reported, with different built-in biases. Each was run
against a control in which every stem's series is circularly rotated by a
different large offset: cross-stem timing is destroyed, each series' own
distribution, autocorrelation and burstiness are preserved.

| Statistic | Bias | Predicted null | **Measured control** |
|---|---|---|---|
| pairwise `r(x_rel, y_rel)` | none | 0.00 | **−0.15 … +0.07** |
| common-mode share `1 − var(x−mean4)/var(x)` | x is ¼ of `mean4` | ~25 % | **18.8 – 23.0 %** |
| `r(x_rel, mean4)` | x is ¼ of `mean4` | ~0.50 | **+0.465 … +0.498** |

The controls land on the predicted nulls, so the pairwise r is the primary
artifact-free statistic and the other two are read against ~22 % / ~0.49.

---

## 2. Captures selected (task 1)

| Capture | Duration | Source type | Register | Why chosen |
|---|---|---|---|---|
| `2026-08-11T01-07-17Z` | 255 s, 15 288 frames | local file | dense full-band alt-rock (*Cherub Rock*, Smashing Pumpkins) | most recent capture; post-DYN.7, so it is the current-code control |
| `2026-08-07T20-20-07Z` | 68 s, 4 087 frames | local playlist (`normal.m3u`) | rock → free jazz (*Trail of Dead*, *Machine Gun* / Brötzmann) | a real multi-track playlist session with a register change inside it |
| `beat-match-test-session` | 88 min, 318 383 frames, 16 tracks | local files (BeatBench corpus, 2026-07-27) | electronic, jazz, sparse acoustic, metal, pop, prog | the only capture carrying full-length tracks across every register |

**Note on the corpus shape.** The prompt assumed three comparable captures
spanning registers. The actual corpus is seven repeats of *Cherub Rock*, two
short playlist fragments, three 30 s fixture clips, and one 88-minute 16-track
session. The register spread therefore comes from within
`beat-match-test-session`, and results are reported per track, not per capture.
`fixturegen-*` clips were excluded: 30 s yields ~6 usable windows.

---

## 3. Per-stem liveness (task 3a)

No stem is dead. Every stem carries usable excursion in every register, so the
concept does **not** fail on liveness.

`x_energy_rel`, p5 / p50 / p95 over the track:

| Track (register) | drums | bass | vocals | other |
|---|---|---|---|---|
| Cherub Rock (dense rock) | −0.179 / 0.001 / 0.340 | −0.213 / 0.010 / 0.392 | −0.210 / −0.011 / 0.502 | −0.162 / −0.024 / 0.390 |
| Around the World (electronic) | −0.383 / 0.022 / 0.361 | −0.442 / 0.009 / 0.458 | −0.346 / −0.008 / 0.477 | −0.321 / 0.005 / 0.370 |
| Take Five (jazz) | −0.268 / −0.016 / 0.355 | −0.327 / −0.022 / 0.452 | −0.289 / −0.047 / 0.535 | −0.240 / −0.036 / 0.423 |
| Bleed (metal) | −0.221 / −0.009 / 0.314 | −0.247 / −0.014 / 0.339 | −0.188 / −0.008 / 0.305 | −0.161 / −0.007 / 0.270 |
| Clair De Lune (sparse acoustic) | −0.324 / −0.051 / 0.507 | −0.350 / −0.044 / 0.492 | −0.337 / −0.008 / 0.409 | −0.297 / −0.014 / 0.372 |
| Billie Jean (pop) | −0.296 / −0.059 / 0.567 | −0.352 / −0.084 / 0.700 | −0.294 / −0.056 / 0.575 | −0.276 / −0.051 / 0.525 |
| Giorgio by Moroder (electronic, quiet) | −0.142 / 0.007 / 0.160 | −0.169 / 0.005 / 0.186 | −0.139 / 0.000 / 0.198 | −0.115 / 0.005 / 0.148 |

**Median is ~0.00 on every stem in every register.** That is the D-026
definition working as designed and it is genuinely good news for a plotting
concept: the rest line is zero by construction, and silence flatlines without
any gating. *Giorgio by Moroder* is the low-excursion case (p95−p5 ≈ 0.26–0.36),
about half the corpus norm — a trace-amplitude floor would be needed there.

---

## 4. Cross-stem decorrelation (task 3b) — the failing measurement

Median windowed pairwise r. Null is 0.00 (§1.1).

| Track | dru~bas | dru~voc | dru~oth | bas~voc | bas~oth | voc~oth | all 6 pairs >0.9 |
|---|---|---|---|---|---|---|---|
| Cherub Rock | **+0.905** | +0.426 | +0.751 | +0.463 | +0.760 | **+0.899** | 3.3 % |
| Trail of Dead | +0.865 | **+0.990** | **+0.986** | +0.819 | +0.826 | **+0.998** | 20.0 % |
| Billie Jean | **+0.961** | +0.624 | +0.828 | +0.610 | +0.911 | **+0.984** | 6.2 % |
| Around the World | **+0.983** | +0.731 | **+0.900** | +0.765 | **+0.919** | **+0.946** | — |
| Take Five | **+0.983** | +0.847 | **+0.919** | +0.853 | **+0.911** | **+0.984** | — |
| Pyramid Song | **+0.969** | +0.504 | +0.731 | +0.503 | +0.730 | **+0.945** | 0.0 % |
| Bleed | **+0.940** | +0.528 | +0.804 | +0.618 | +0.849 | **+0.926** | 4.6 % |
| Giorgio by Moroder | +0.810 | +0.200 | +0.765 | +0.437 | +0.770 | +0.801 | 0.0 % |
| Girl From Ipanema | **+0.957** | +0.485 | **+0.907** | +0.575 | +0.897 | +0.857 | 5.2 % |
| Clair De Lune | **+0.949** | +0.519 | +0.831 | +0.571 | +0.858 | **+0.900** | 2.5 % |

And the share of each trace's motion that is simply the mix's overall loudness
envelope (null ~22 % / ~0.49):

| Track | common-mode share (mean of 4) | mean `r(trace, mix envelope)` |
|---|---|---|
| Cherub Rock | 75.8 % | +0.878 |
| Trail of Dead | 85.1 % | +0.968 |
| Billie Jean | 86.2 % | +0.921 |
| Around the World | 89.9 % | +0.952 |
| Take Five | **93.0 %** | **+0.968** |
| Bleed | 87.6 % | +0.911 |
| Giorgio by Moroder | 88.8 % | +0.858 |
| Clair De Lune | 84.7 % | +0.912 |

Per-stem, `other` is the worst offender everywhere: 88.8 – 97.6 % common mode,
`r ≥ 0.96` against the full-mix envelope on every track measured. The `other`
trace is very nearly a redundant redraw of the mix.

---

## 5. The failure shape

Not "the stems are dead" and not "all four collapse to exactly one line". The
measured shape is specific and consistent:

1. **Between two-thirds and ninety-three percent of each trace's vertical
   motion is the mix's shared loudness envelope** (vs a ~22 % null). Four traces
   plotting `x_energy_rel` draw four near-parallel copies of the same curve at
   different amplitudes. The differences are real but ride on top of a dominant
   shared gesture.
2. **The four voices are really two.** `drums~bass` is +0.81…+0.98 and
   `vocals~other` is +0.80…+0.99 on every track in every register. The
   rhythm-section pair and the melodic pair each move together. The axis that
   *does* separate is rhythm-vs-melodic: `drums~vocals` and `bass~vocals` sit at
   +0.20…+0.85, well clear of the pairs above.
3. **No register escapes it.** Sparse solo piano (Clair De Lune, 84.7 %) and
   dense metal (Bleed, 87.6 %) fail the same way. Jazz is the *worst*
   (Take Five, 93.0 %, all four traces `r ≥ 0.95` against the mix), which is the
   opposite of the intuition that sparse material would separate best.
4. **Two plausible mechanisms, not separated here.** Shared musical dynamics
   (a band gets louder together) and Demucs bleed between stems both predict
   this. Distinguishing them was not attempted and is not needed for the gate —
   the preset-facing consequence is identical either way.

Per the CHR.1 prompt's task 4 and `SHADER_CRAFT.md §2.0`, the response to a
failed concept gate is re-scope with Matt, not iteration. No amplitude mapping
was tuned to force separation (that is the D-102 / FA #58 pattern).

---

## 6. Re-scope directions — material for Matt's call, not a recommendation

**A. Two traces, on the axis that measurably separates.** Rhythm
(`drums+bass`) against melodic (`vocals+other`). This is the one grouping the
data supports: within-pair r is +0.8…+0.99, across-pair r is +0.20…+0.85. Two
traces that converge in a chorus and diverge in a breakdown is a real, readable,
music-driven picture. Cost: "four instruments" becomes "two voices", which is a
weaker version of the pitch but a true one.

**B. Plot the residual, not the level.** Keep four traces, but each plots its
stem's departure *from* the mix envelope rather than its own energy — so the
common mode is subtracted rather than drawn four times. The shared gesture then
becomes one thing (e.g. the grid's brightness, or a baseline that rides the
mix). Needs its own measurement round before it is believed: residuals about a
common mean are constrained to sum to zero, so an apparent decorrelation is
partly forced, and the visual consequence of that constraint is unknown.

**C. Different per-stem quantities, not four copies of one.** The four traces
plot four *different* features — e.g. drums `onset_rate`, bass `energy_rel`,
vocals `centroid`, other `attack_ratio`. These are not four measurements of
loudness, so the common-mode problem does not arise by construction. Costs the
concept's clean "same plot, four instruments" legibility, and each candidate
column needs the §3 liveness pass first (this increment measured only
`energy_rel` / `energy_dev`).

**D. Drop the concept.** The source (`Martin - charisma`) has not been read for
mechanics yet and no other candidate was worked up, so this is a real option and
not a null one.

---

## 7. Beat-grid surface (task 2), for whoever picks this up

Measured while the concept was still live; kept because it is concept-independent.

- `grid_bpm > 0` on **99.8–100 %** of frames in every capture, on the local-file
  planned-session path. `lock_state` reaches its maximum observed value on all
  captures. Reactive-mode fallback was **not** exercised — no live-capture
  session exists in the corpus, so the `bpm 0` path in the prompt's task 2
  remains unverified.
- `beatsPerBar` is **not stable within a track**: *Pyramid Song* reports 1,
  *Bleed* 2, *Giorgio* 2 and 3 in one track, and *Billie Jean* reports 4 in one
  capture segment and 3 in another. Any design weighting downbeats more heavily
  than beats must not assume a fixed bar length.
- `beatPhase01` advances on **98.7–99.0 %** of frames in the 2026-07-27 capture
  but only **13.4–16.7 %** in the 2026-08-07/08-11 captures, which also report
  `beat_sync_mode` 0 alongside 1/2/3 where July reports only 1/2/3. This was not
  chased down. **It is a discrepancy worth a look before any preset derives
  gridlines from `beatPhase01`** — one of the two behaviours is wrong.

---

## 7a. Direction A gated (Matt picked A, 2026-08-11)

**A passes.** Direction A's traces are averages of tightly-correlated pairs, so
`r(drums,vocals) = +0.43…+0.85` does not settle `r(R, M)` — averaging inside a
pair barely shrinks that pair's variance while preserving the shared envelope.
Measured directly, on 17 tracks:

    R = mean(drumsEnergyRel, bassEnergyRel)
    M = mean(vocalsEnergyRel, otherEnergyRel)

| | median across 17 tracks | range | rotation control |
|---|---|---|---|
| `r(R, M)` | **+0.756** | +0.558 … +0.950 | ≈ 0.00 |
| divergence ratio `std(R−M) / mean(std(R), std(M))` | **0.75** | 0.485 … 0.961 | ≈ 1.45 |

The divergence ratio is the design-relevant one: the gap between the two traces
is 49–96 % of the motion scale each trace makes, i.e. plainly visible. Weakest
full-length cases are *Dance Yrself Clean* 0.485 and *Take Five* 0.493 — still
half the motion scale. And `r(R,M)` swings **within** tracks (*Giorgio* p10 +0.32
→ p90 +0.91; *Bohemian Rhapsody* +0.39 → +0.91), so converge-and-diverge is
measured behaviour, not an aspiration. That swing is direction A's central
visual event.

## 7b. Preset-facing latency (task 3c) — the finding that outranks the above

**The per-stem features run a fixed ≈5.4 s behind the real-time band features.**
This contradicts the CHR.1 prompt's assumption that the lag was a live-capture
problem and the local-file path would be clean. It is not: every measurement
below is a local-file session.

Three independent measurements, escalating in cleanliness:

1. **Tap cross-correlation, cold start** (`2026-08-11T01-07-17Z`, 30 s tap):
   FFT bands `bass`/`mid`/`treble` peak at −0.30 … +0.08 s. Every stem
   `energyRel` has *no* peak inside ±3 s; widening to ±20 s finds a single broad
   unimodal peak at **≈10 s** (r +0.58), rising monotonically from r −0.05 at
   lag 0. No secondary peaks, so not aliasing.
2. **Tap cross-correlation, steady state** (`beat-match-test-session`, full
   2.04 GB tap, four 60 s windows ≥ 90 s into a track, long past the ~10 s
   crossfade): control `bass` peaks at **0.20–0.40 s** — alignment confirmed —
   while every stem peaks at **5.61 / 5.81 / 5.61 / 5.61 s**. So the lag is
   steady state, not a cold-start artifact.
3. **CSV-internal, no WAV at all** — each stem feature against the time-aligned
   `bass+mid` band sum, both recorded at 60 Hz, which removes any
   envelope-matching concern: **5.4 s on 39 of 40 stem × track measurements**,
   with r up to +0.94. The single outlier is the *Cherub Rock* capture, whose
   correlations are weak throughout (r 0.19–0.36).

This agrees with TRK.2's independent 5–10 s finding and with the documented
Layer-5a behaviour ("pre-analyzed from preview clips … **not time-aligned**").

**Why it outranks the decorrelation result for this concept specifically.** The
beat grid this preset rules its field with *is* time-aligned (`grid_bpm`,
`beatPhase01`). Traces 5.4 s late against in-sync gridlines contradict each other
on screen: trace peaks land visibly off the lines, and with an ~8 s scroll window
the listener's current moment is not on screen at all. For a preset whose premise
is "the marks on screen are the audio", that is a defect in the premise, not a
footnote.

**A time-aligned alternative exists and separates better.** Same two statistics,
on a 6-band spectral stand-in for the same rhythm-vs-melodic axis
(`R_spec = mean(subBass, lowBass)`, `M_spec = mean(midHigh, highMid, high)`, each
band EMA-centred per FA #31), lag ≈ 0.3 s:

| | stem split (5.4 s late) | spectral split (0.3 s) |
|---|---|---|
| median `r` | +0.756 | **+0.055** |
| median divergence | 0.75 | **1.88** |

The spectral traces are effectively uncorrelated — divergence *above* the 1.45
independence null means mildly anti-correlated, i.e. a legible see-saw between
low and high register. Cost: they are registers, not instruments (a low piano
chord reads as "rhythm"; a broadband snare splits across both), and there is no
converge/diverge story to replace the one the stem split has.

**This is a product decision and is with Matt.** Not resolved here.

## 8. Root cause of the 5.4 s (Matt: "chase the 5.4 s first", 2026-08-11)

Filed as **BUG-086**. Read from source, not inferred — three lines do it:

| Where | What it says |
|---|---|
| `PhospheneApp/VisualizerEngine+Stems.swift:49` | `timer.schedule(deadline: .now() + 10, repeating: 5.0)` — separation every **5 s** |
| `PhospheneApp/VisualizerEngine+Stems.swift:166` | `stemSampleBuffer.snapshotLatest(seconds: 10, …)` — the chunk is the latest **10 s**, so its start is 10 s old and its end is "now" |
| `PhospheneApp/VisualizerEngine+Audio.swift:333` | `let startSample = Int(5.0 * sampleRate)` — the per-frame read window starts **5 s into** the chunk, then advances at real time |

Reading at 5 s into a chunk whose end is "now" means reading audio that is 5 s
old. The window then advances at real time, so the lag *holds* at 5 s until it
reaches the chunk's end — which takes exactly `chunkLength − startOffset` = 5 s,
i.e. one separation period, at which point a fresh chunk resets it.

> **lag = chunkLength − startOffset, and that quantity must be ≥ the separation
> period, or the read clamps at the chunk end and the features freeze between
> separations. So lag ≥ separationPeriod.**

The 5 s head start is not slack — it is the runway. Measured 5.4 s against a
predicted 5.0 s; the extra ≈0.4 s is inference time, scheduler deferral, the
1024-sample window and EMA smoothing.

**Chunk length is not a lever.** `StemSeparator.modelFrameCount = 431` is
commented "Fixed number of STFT frames the model expects", giving
`requiredMonoSamples = 440320` ≈ 10 s at 44.1 kHz. A shorter chunk needs a
re-exported Open-Unmix model.

**So the only lever is the separation period**, at one full inference per period
(cost fixed — the model always consumes 10 s regardless of how much is used):

| period | resulting lag | inference duty |
|---|---|---|
| 5 s (today) | ≈5 s | ≈2.8 % |
| 2 s | ≈2 s | ≈7.1 % |
| 1 s | ≈1 s | ≈14.2 % |

`startSample` moves to `chunkLength − period` in the same change, or the freeze
described above replaces the lag.

Two caveats, both flagged rather than resolved:

- The **142 ms inference figure is a code comment** (`VisualizerEngine+Stems.swift:211`),
  not a measurement. No session artifact records separation cost — `stem_analyzer_ms`
  is the per-frame analyzer, not the MPSGraph call. Measuring it is step 1 of a fix.
- `MLDispatchScheduler` (D-059) already defers when frames run over budget, with a
  2 s ceiling, so worst-case lag is `period + deferral`. Short periods make
  deferral common, which is the risk the table above does not price.

**Scope note.** This is the diagnosis increment per the `defect-handling`
multi-increment process: instrumentation and root cause, no fix code. The fix is
its own increment with its own verification, and it touches every stem-driven
preset, so it is not bundled into a preset increment.

## 9. What was not done

Tasks 5–8 of the CHR.1 prompt (history-mechanism confirmation, reference
curation, `STAVE_DESIGN.md`, the `DECISIONS.md` entry) were **not started**, per
the task-4 hard stop. Task 3c (preset-facing latency against `raw_tap.wav`) was
also not run: it measures how well a concept tracks the audio, which is not
worth spending before the concept is settled.
