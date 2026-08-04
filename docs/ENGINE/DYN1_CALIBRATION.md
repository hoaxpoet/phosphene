# DYN.1 / DYN.1b — spectral density and section surge, and how they were calibrated

Two `FeatureVector` fields added so a preset can express **"the mix just arrived"**, which
nothing else in the vector could. Written up because both were calibrated wrong first, in
ways that are easy to repeat.

## What they are

| field | float | what it is |
|---|---|---|
| `spectral_density` | 49 | Energy fraction above 1.5 kHz, from RAW FFT magnitudes, EMA τ ≈ 0.8 s |
| `spectral_density_slow` | 50 | Same, τ ≈ 45 s — the track's own normal |
| `spectral_surge` | 51 | Pre-AGC LEVEL through an asymmetric follower: attack ≈ 0.25 s, release τ ≈ 10 s |

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
