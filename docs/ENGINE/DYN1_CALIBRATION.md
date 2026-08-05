# DYN.1 / DYN.1b — spectral density and section surge, and how they were calibrated

Two `FeatureVector` fields added so a preset can express **"the mix just arrived"**, which
nothing else in the vector could. Written up because both were calibrated wrong first, in
ways that are easy to repeat.

## What they are

| field | float | what it is |
|---|---|---|
| `spectral_density` | 49 | Energy fraction above 1.5 kHz, from RAW FFT magnitudes, EMA τ ≈ 0.8 s |
| `spectral_density_slow` | 50 | Same, τ ≈ 45 s — the track's own normal |
| `spectral_surge` | 51 | Pre-AGC LEVEL through an asymmetric follower, then mapped: per-track RANK (DYN.1c) for local files, fixed −24…−15 dB band otherwise |

Both are computed in `SpectralAnalyzer` from the raw magnitudes — upstream of the
total-energy AGC and of `BandDeviationTracker`'s per-band EMA. That placement is the whole
point: those two flatten absolute level **and** the ratios between bands (measured,
`treble/(bass+mid+treble)` correlates −0.229 with real HF content, i.e. it moves the wrong
way), so nothing downstream could carry either quantity.

## Three calibration errors worth not repeating

**1. Density was smoothed at τ 6 s and swallowed the event.** Swept against a real capture
(`2026-08-04T17-17-01Z`, distorted guitar at ~20 s, independent time-domain reference
showing a 3.22× rise):

| fast leg | response |
|---|---|
| τ 6.0 s | 1.15× — looked like the field was broken |
| τ 1.5 s | 2.22× |
| **τ 0.8 s** | **2.98× — 93 % of reference, count turns only 0.41/s** |
| τ 0.45 s | 3.36× — no better, 50 % more restless |

τ 6 s had been chosen while the *trunk* read this field and was bouncing. Once density was
confined to the quantised branch count, that smoothing protected nothing and only destroyed
the signal.

**2. The surge band was calibrated on the wrong scale.** The band was derived from **RMS
dBFS** measured offline and applied unchanged to `10·log10(Σ magnitude²)`. Those scales
differ; the surge saturated at 6 s and the visual was already at full size before the
event. The correct band was found by printing the analyzer's own `levelDB` over a capture.

**3. Shape alone cannot detect an arrival.** An obvious design is to drive the surge from
`spectral_density` — brighter mix, bigger moment. It fails: a clean intro is BRIGHTER
(HF 0.22) than the passage before a distorted guitar (HF 0.03), so shape confuses a bright
quiet intro with a loud arrival. Level separates them 20.4× on the same capture.

Related: the reasoning that first ruled level out was that the BODY of a limited master is
flat — true, and irrelevant. The intro→body transition is 26 dB. Limiting flattens the
body, not the arrival.

## Why the surge is asymmetric

An arrival is a **step that persists**. Every other field here is instantaneous or averaged,
so a preset can only scale it, and scaling a proportional signal cannot produce a step —
which is why eight rounds of proportional tuning on Fractal Tree never produced the effect
Matt asked for. Fast attack lets the step land; slow release stops it pumping between
phrases, and makes it slow enough (0.58 turns/s) that continuous geometry can safely read
it where the restless density ratio could not.

## Testing

`SpectralDensityRealAudioTests` runs the real analyzer over a real capture's `raw_tap.wav`
through a real vDSP FFT, cross-checked against an independent time-domain measure:

```
FT_SESSION=~/Documents/phosphene_sessions/<id> FT_EVENT=<seconds> \
  swift test --package-path PhospheneEngine --filter SpectralDensityRealAudio
```

It is env-gated (a session capture is not a committed fixture) and asserts the reference
contains an event before judging the field, so a wrong `FT_EVENT` fails loudly rather than
passing vacuously.

**The always-on companion uses a BROADBAND spectrum, not single peaks.** Five synthetic
single-peak density tests passed throughout the entire period the field was broken on real
audio; real music is broadband and behaves nothing like two spikes.

## DYN.1c — the fixed band is per-song wrong, and two edges are not enough

A fixed band saturates at whatever point in a given track first crosses it, and can never
rise again. Measured on `2026-08-04T20-23-15Z` (Hummer): `spectral_surge` pins for **63.3 %**
of the capture and reads **1.000 at both** the 31 s arrival and the 4 dB-louder 63 s
section. Matt: *"the tree had grown to full size before the full band kicked in later in
the song. there are also louder / fuller sections later."*

For a local file the whole thing is decoded during preparation, so the track's own loudness
distribution is measurable up front (`LoudnessProfile.measure`, `Audio` module). Streaming
keeps the fixed band — a 30 s preview describes the preview, not the track.

**A fourth calibration error, avoided by measuring:** the obvious fix is to map the surge
onto the track's p10→p95 instead of the fixed edges. It does not work — 63.3 % → 46 % —
because the follower rides peaks, so any two-edge band whose top is a percentile
re-saturates on a transient. Sweeping the edges finds a pair that does work (p30→p99,
13.5 % pinned), and **taking it would repeat the original mistake one level up**: p30 is
fitted to one track's intro length. What ships instead maps the level through the track's
own CDF (33 quantiles, `rank(ofLevelDB:)`) — no fitted constant, and only the top few per
cent of a track can pin by construction.

| mapping | pinned | surge @31 s | surge @63 s |
|---|---|---|---|
| fixed −24…−15 dB | 63.3 % | 1.000 | 1.000 |
| track p10→p95 | 45.9 % | 0.988 | 0.999 |
| track p30→p99 (fitted) | 13.5 % | 0.919 | 0.994 |
| **track CDF rank** | **0.9 %** | **0.613** | **0.945** |

`isUsable` gates on the p12.5→p87.5 **inner** span, not min→max: the minimum quantile is
routinely −200 dB (the silent frame before the first note), so min→max makes a constant
source look dynamic.

Gate: `SurgeLoudnessProfileRealAudioTests`, env-gated on `FT_SESSION` like the density one.

## Analysis rate — the ~10 Hz in these comments is wrong (~47 Hz)

Every τ in this document and in `SpectralAnalyzer` was derived assuming a ~10 Hz MIR rate.
The live rate is the tap buffer size: mean `deltaTime` across the distinct analysis frames
of `2026-08-04T20-23-15Z` is **0.021 s — 1024 samples at 48 kHz, ≈47 Hz**. Every quoted τ is
therefore ~4.7× too long (density fast leg τ 0.18 s not 0.8 s; level smoothing τ 0.7 s not
3 s). The shipped **alphas are unaffected** — they were swept for measured response against
real captures, not derived from a target τ — so this is a comment-accuracy defect. It is
recorded rather than corrected because fixing it touches the stated rationale of every DYN
constant. `LoudnessProfile.measure` hops 1024 samples per frame for this reason: it matches
the live rate by construction rather than by an assumed number.
