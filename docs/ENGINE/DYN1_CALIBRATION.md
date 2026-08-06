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

## DYN.1d — the usability gate pointed the wrong way

`isUsable` required **4 dB** of inner range before a measured profile would replace the
fixed band. That threshold rejects a brickwalled master — and a brickwalled master is
exactly the case a FIXED absolute band serves worst. The guard was backwards, and it failed
silently: `measure()` returned nil, the entry persisted at schema v7 with the field absent,
and every subsequent play was a cache HIT that logged nothing.

Measured on Matt's Cherub Rock capture `2026-08-05T21-21-03Z`:

| | fixed band (what shipped) | ranked (after the fix) |
|---|---|---|
| inner range | 1.46 dB — refused | 1.46 dB — accepted |
| pinned | **93.6 %** | **0.6 %** |
| surge @25 s → @60 s | 1.000 → 1.000 | **0.237 → 0.887** |

Matt's report was *"the tree grows a bit too much BEFORE the distorted guitar comes in and
then does not jump up again when the distorted guitar enters."* **Both halves are this one
threshold** — the surge was already saturated at 30 s, so there was no headroom left for the
arrival to step into.

**Narrowness was never the hazard.** Ranked at 1.46 dB the surge lands in the same regime as
the Hummer capture Matt approved as reading musical: 2.87 turns/s against Hummer's 2.41, and
*less* pinning (0.5 % vs 1.4 %). What the gate should catch is a distribution with no shape
at all — digital silence, a test tone — so the floor is now 0.5 dB.

Schema **v8**: a v7 entry holding a nil profile would keep it forever behind a cache hit.

The install breadcrumb now prints `loudness=none (fixed band)` explicitly. An absent suffix
was indistinguishable from a line predating the field, which is why this ran for a whole
session unnoticed — a silent fallback to the defect being fixed is the worst failure shape
available.

## DYN.2 — the trunk needed RANGE, and on a limited master only shape has it

DYN.1e pointed the trunk at a blend of arousal and the ranked surge. Matt's review:
*"Tree trunk neither grew nor receded when the distorted guitar came in … Did not recede
after the chorus."* Measured on `2026-08-06T14-59-37Z`, he is right, and the cause is
**range, not direction**: that blend traverses **0.83…0.92 across the whole body** — a 10 %
band — and climbs over ~50 s, so nothing in the music registers.

**Level cannot do better on this material.** Cherub Rock has 1.4 dB of inner range: verse
and chorus are the same loudness, so no level-derived signal separates them.

**Spectral content does** — DYN.1's founding observation, applied to sections rather than
arrivals. Density τ10 s sits at 0.13 through the verse and 0.21 through the chorus.

`spectral_density_section` (float 52, τ ≈ 10 s) divided by `spectral_density_slow` is that
quantity against the track's OWN running average: self-normalising, no fitted per-track
constant — the mistake DYN.1c/.1d exist to avoid. Mapped `smoothstep(0.40, 1.05)`:

| | intro 20 s | guitar 30 s | verse 50–70 s | chorus 90–110 s | after 130 s |
|---|---|---|---|---|---|
| DYN.1e (rejected) | 0.198 | 0.379 | 0.80 / 0.92 | 0.83 / 0.83 | 0.886 |
| **DYN.2** | **0.00** | 0.06 | **0.30 / 0.46** | **0.92 / 1.00** | **0.88** |

**Smooth, not stepped — an explicit requirement.** A quantised version was built and
rejected before shipping: *"I just want it to grow and recede with the energy of the music
and do so smoothly - not in visible jumps."* Measured motion **0.0198/s**, BELOW the
0.0221/s of the surge the trunk read at DYN.1e, and a fifth of the raw density that caused
FTR.3f. **The τ10 s leg is what makes density trunk-safe** where the shipped τ0.8 s leg was
not; that one stays confined to the branch count.

Two guards: an arousal floor so the tree never collapses mid-song, and a surge gate so a
bright QUIET intro cannot inflate it (§3 — a clean intro is brighter than a pre-distortion
passage, so shape alone would grow the tree before the band arrives).

**Replay caveat.** `spectral_density_section` did not exist when earlier captures were
recorded, so `PresetSessionReplay` / the `FT_SESSION` harness feed **0** for it on any
session before 2026-08-06 — the trunk will read flat-zero there. That is the harness's
unmapped-field behaviour, not a route defect. Judge this route only on a fresh capture.
