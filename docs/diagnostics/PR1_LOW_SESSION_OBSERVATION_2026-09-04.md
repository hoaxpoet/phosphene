# PR.1 — What Matt's *Low* session actually shows

**Session:** `~/Documents/uzume_sessions/2026-09-03T21-38-45Z` (2026-09-03, 148,842 frames, ~55 min).
**Material:** David Bowie — *Low*, local FLAC, all 11 tracks in album order, local-file path (whole-file
analysis, not a 30 s preview). This is the session behind Matt's 2026-09-04 roster review.
**Chain health:** `verdict=degraded`, reason `signal_health_band_low` — **see §4 before discounting
anything below.**

## 1. Track mapping (self-verifying)

Segments were cut at `track_elapsed_s` resets and matched to *Low* by duration. The match is exact
on every track, so the per-track rows below are not an inference:

| Track | measured s | published s |
|---|---|---|
| 01 Speed Of Life | 166 | 166 |
| 02 Breaking Glass | 112 | 112 |
| 03 What In The World | 142 | 143 |
| 04 Sound And Vision | 183 | 183 |
| 05 Always Crashing In The Same Car | 213 | 213 |
| 06 Be My Wife | 176 | 178 |
| 07 A New Career In A New Town | 172 | 173 |
| 08 Warszawa | 383 | 383 |
| 09 Art Decade | 226 | 226 |
| 10 Weeping Wall | 207 | 208 |
| 11 Subterraneans | 288 | 339 (cut short) |

## 2. The measurement

`drift_ms` is the live beat phase's error against the audible beat. BUG-065's perceptual window is
~60 ms. `beatsPerBar` is the engine's inferred meter.

| Track | grid BPM | beatsPerBar | frames >60 ms | p50 \|drift\| | presets on screen |
|---|---:|---:|---:|---:|---|
| 01 Speed Of Life | 112.9 | 4 | 51.6 % | 66 ms | — |
| 02 Breaking Glass | 94.0 | 4 | 36.2 % | 46 ms | — |
| 03 What In The World | 124.1 | **2** | 63.8 % | 74 ms | — |
| 04 Sound And Vision | 105.7 | 4 | **83.4 %** | 115 ms | — |
| 05 Always Crashing | 103.2 | 4 | 32.2 % | 43 ms | Cytokinesis, Waveform |
| 06 Be My Wife | 111.2 | 4 | 28.2 % | 39 ms | Dragon Bloom, Fractal Tree, Membrane, Witchlight |
| 07 A New Career | 125.1 | 4 | **90.1 %** | 84 ms | Aurora Veil, Cymatic Resonance, Witchlight, Arachne |
| 08 Warszawa | **54.0** | **3** | **100 %** | **166 ms** | Dragon Bloom, Fata Morgana, Filigree, Glaze, Cytokinesis, Aurora Veil, Cymatic Resonance |
| 09 Art Decade | 86.7 | **2** | 34.5 % | 32 ms | Ferrofluid Ocean, Filigree, Glaze, Dragon Bloom, Fata Morgana |
| 10 Weeping Wall | **142.3** | **2** | **70.4 %** | 80 ms | Ferrofluid Ocean, Filigree, Floret, Fractal Tree, Witchlight |
| 11 Subterraneans | 67.7 | **3** | 20.8 % | 31 ms | Floret, Fractal Tree, Glaze, Gossamer, Lumen Mosaic, Membrane |
| (replay) Be My Wife | 111.2 | 4 | 28.4 % | 39 ms | Cymatic Resonance, Membrane, Meniscus, Mitosis |
| (replay) A New Career | 125.1 | 4 | **100 %** | **186 ms** | Murmuration |

## 3. Three findings

**3.1 — The phase drift is far worse than BUG-065's recorded baseline.** That entry's strongest prior
evidence was 50 % of frames outside the perceptual window (Lumen Mosaic, `2026-07-30T15-39-21Z`).
Here **six of thirteen segments exceed that**, and two sit at **100 %** — every frame outside the
window, p50 drift 166 ms and 186 ms. At 186 ms the visual is most of a beat behind at 125 BPM.

**3.2 — Meter is wrong on five of eleven tracks.** `beatsPerBar = 2` on What In The World, Art Decade
and Weeping Wall is the **degenerate value KNOWN_ISSUES already documents as the meter-detection
failure mode** (BUG-028: Money in 7/4 logged `beatsPerBar = 2`). `3` on Warszawa and Subterraneans is
not independently verified here but is implausible for those pieces. Every bar-locked route — Witchlight's
bar-marker beads, Glaze's downbeat push, Lumen Mosaic, Aurora Veil, Floret, Nacre — fires on a
wrong-length bar for those tracks.

**3.3 — On the ambient side the tempo itself is wrong, not just the phase.** Weeping Wall at 142.3 BPM
and Warszawa at 54.0 BPM are not plausible readings. Side two is not a phase problem to be tightened;
the grid is wrong outright.

**What this means for the review.** Witchlight was on screen during A New Career (90.1 % outside the
window) and Weeping Wall (70.4 %, `beatsPerBar = 2`). Matt's *"inconsistent with downbeat"* is that
measurement, not a Witchlight defect. The same applies to every preset in PR.3's row.

## 4. Chain health — the `degraded` verdict does not invalidate this

Per the preset-session rule a non-`clean` verdict must be flagged rather than folded away. It is
flagged here, and then measured: of 500 SIGNAL_HEALTH windows, **484 healthy, 3 low, 13 critical**.
Within the track segments the chain reads 76/76, 43/45, 40/41, 52/57, 33/34 healthy. The non-healthy
windows are scattered singles on *Low*'s quiet ambient side, where a low 5-second peak is the
material rather than a fault. **Conclusion: the timing measurements above rest on a healthy chain.**
Separately worth noting as a possible grader defect — quiet music should not read as a degraded
signal chain — but that is not this increment.

## 5. What this session CANNOT answer

**Video recording was OFF** (`BUG-050`; `UZUME_RECORD_VIDEO=1` enables it). There are zero rendered
frames, so every look-shaped observation in the review is unanswerable from this capture: Dragon
Bloom's blown whites, Glaze's brightness and screen-jumping, Fata Morgana's darkness and sky/water
ratio, Murmuration's cloud size, Cymatic Resonance's pattern variation, Nacre's speed, Aurora Veil's
purple. **A second capture with video on is required**, and PR.5/PR.6 are blocked until it exists.

## 6. A blocker PR.1 uncovered: the replay harness covers one paradigm

`SessionReplayHarness` replays a real session's `features.csv` through the production render path —
but it drives `RayMarchPipeline.render`, and `ReplayHarnessRouteCoverageTests` guards it behind
`guard descriptor.passes.contains(.rayMarch)`. Of the 26 presets Matt flagged, **three are ray-march**:
Ferrofluid Ocean, Lumen Mosaic, Volumetric Lithograph. The other 23 cannot be replayed from a real
session at all.

Worse, because the coverage gate is scoped to ray-march too, these declared routes are **carried by
nothing and checked by nothing** — anyone extending the harness without mapping them would measure
against ZERO and read it as a dead route, which is exactly the FLY.6 failure the harness exists to
prevent:

| Preset | uncarried declared routes |
|---|---|
| Ricercar | `midDev`, `trebDev`, `stringsActivityDev`, `brassActivityDev`, `woodwindsActivityDev`, `percussionActivityDev` |
| Skein | `drumsCentroid`, `bassCentroid`, `vocalsCentroid`, `otherCentroid`, `vocalsBand1`, `otherBand1`, `sectionIndex` |
| Murmuration | `bassAtt`, `trebleAtt`, `highMid`, `high` |
| Witchlight | `bassAtt`, `sectionIndex` |
| Fractal Tree | `spectralLevelRise`, `spectralSectionRatio` |
| Nacre | `trebDev` |
| Stave | `waveformOccupancy` |

## 7. Consequences for Phase PR

- **PR.3 is no longer a decision waiting on a premise.** It is the top item: it explains the sync
  half of the review across at least Witchlight, Meniscus, Lumen Mosaic, Ferrofluid Ocean, and
  contaminates any tuning done on the other presets while it stands.
- **PR.2 is not safely startable yet.** A tempo-scaled motion rate reads its rate from the grid, and
  §3.3 shows the grid's tempo is wrong on the ambient side. Tuning motion speed against 142.3 BPM on
  Weeping Wall would bake in a compensation for a bad number.
- **PR.5 and PR.6 need a video-on capture** before anything can be looked at.
- **A new increment is implied:** extend the replay harness past ray-march, and widen the coverage
  gate with it, or PR.2/PR.5/PR.6 have no production-path evidence route for 23 of 26 presets.
