# BUG-107 — money window sweep (2026-08-27, BUG107.1)

The BUG-076 method (30 s windows via `ffmpeg` + `BeatBench --audio`) applied to money, to answer
the question BUG-107 was filed with: is the grid's 116.19 BPM a fixed error, or window-position
instability appearing on a second track?

**Neither. money has real tempo drift, and the analyzer emits one constant tempo per file.**

## Method

```bash
for off in 0 30 60 90 120 150 180 210 240 270 300 330 350; do
  ffmpeg -v error -y -ss $off -t 30 -i ~/phosphene_beatbench_fixtures/money.wav /tmp/w.wav
  swift run BeatBench --audio /tmp/w.wav
done
```

Reference backends measured over the same spans from their committed annotations
(`Tests/Fixtures/beatbench/reference/money.{librosa,madmom}.json`); Matt's taps from
`taps/money.beats.json` (the BUG102.2 re-tap), first 13.5 s dropped as intro.

## Phosphene, per 30 s window

| offset | grid BPM | beatsPerBar | barConfidence |
|---|---|---|---|
| 0 s | 116.19 | 1 | 0.77 |
| 30 s | 121.05 | 2 | 0.26 |
| 60 s | 124.25 | 1 | 0.60 |
| 90 s | 125.59 | 2 | 0.44 |
| 120 s | 126.27 | 1 | 0.57 |
| 150 s | 125.68 | 1 | 0.85 |
| 180 s | 134.24 | 4 | 0.88 |
| 210 s | 136.27 | 3 | 0.08 |
| 240 s | 135.37 | 1 | 0.55 |
| 270 s | 140.19 | 4 | 1.00 |
| 300 s | 129.73 | 1 | 0.81 |
| 330 s | 129.82 | 2 | 0.67 |
| 350 s | 132.44 | 2 | 0.97 |

## All three sources agree the track accelerates

| span | librosa | madmom | Phosphene window |
|---|---|---|---|
| 0–60 s | 119.68 | 120.00 | 116.19 / 121.05 |
| 60–120 s | 125.00 | 125.00 | 124.25 / 125.59 |
| 120–180 s | 125.00 | 125.00 | 126.27 / 125.68 |
| 180–240 s | 133.93 | 136.36 | 134.24 / 136.27 |
| 240–300 s | 137.20 | 139.53 | 135.37 / 140.19 |
| 300–360 s | 130.81 | 130.43 | 129.73 / 129.82 |

Matt's taps corroborate independently — 20-tap blocks across the tapped span read 120.32,
118.01, 121.06, 121.44, 120.52, 122.68, 122.32 BPM: rising.

Range ~120 → ~140 → ~130, a ~17 % swing. This is a 1973 analog recording played without a click;
drift of this size is musically ordinary.

## What that means

**Windowed, Phosphene tracks the references closely at every point.** The defect is not a fixed
4 % error. Three things combine instead:

1. `DefaultBeatGridAnalyzer` returns a **single scalar BPM per file**. On money's 380 s it
   returns **116.19 — exactly the 0–30 s window value**, the opening tempo rather than a
   mid-range compromise.
2. money's ground truth spans only **4.39–89.97 s**, so the reference describes the opening
   tempo, not the track. (bleed's truth was extended full-length by an agreeing backend; money's
   could not be, because the backends disagree on phase and the taps were kept — BUG102.2.)
3. `offline-grid` scores that one constant grid wherever both exist. A constant grid over a
   track that accelerates 17 % can only be right for part of it — which is what CMLt 0.43 looks
   like: tracked early, lost later.

## Same method, opposite diagnosis to BUG-076

BUG-076 found *window-position instability* on bleed: a third of windows give a wrong tempo,
spread 2.11×, no musical trend — the windows disagree with each other and with the truth.
money's windows **agree with the references and with each other**, and disagree only with the
single whole-file scalar. Worth remembering before assuming the two are the same class.

## Not determined here

Whether the emitted grid lays uniformly-spaced beats or adapts within the file. The sweep only
observes the reported scalar. That is the first thing a diagnosis increment should establish: it
decides whether the fix is "emit a time-varying grid" or "re-scope what the benchmark compares".
