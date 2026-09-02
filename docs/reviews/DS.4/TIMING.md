# DS.4 — preparation wall time, before and with each view live

The GPU runs MPSGraph stem separation during exactly this screen. The overture must not
tax the work it describes. Task 2 measured the wait on the unmodified build; task 10 repeats
it with each view live on the DS.4 build and states the deltas.

## Method

- **Playlist:** Tunes Club "TC 29" (Spotify `4O0LIYH5LV34EDOvHnd0Sy`), **40 tracks** — a real
  playlist at the scale the design was paced against. Same playlist for every run.
- **Path:** the shipped Spotify flow (paste link → Continue), so preparation runs through
  `PreviewResolver` → `PreviewDownloader` → stem separation → MIR → beat grid → cache. Streaming
  preview data has no disk backing (`StemCache.swift:158`), so every launch is cache-cold.
- **Clock:** the unified log (`/usr/bin/log show --info --predicate 'subsystem BEGINSWITH "io.uzume"'`).
  `prepare ENTER` is t = 0; each `Cached:` line is a track landing; `startSession→ready` is the
  end. All three are emitted by the engine on every build, so the columns are comparable.
- **Conditions:** nothing else compiling or testing on the machine during a run; the same
  window size; the app launched fresh from its built binary.
- **Noise:** the three tracks with no iTunes preview each cost a ~31–36 s stall (the resolver's
  fallback path), so end-to-end is dominated by which tracks lack previews, not by the view.
  Per-track median is the steadier number; first-ready and three-ready are the ones the user
  feels.

## Results

| | baseline (`main` 67c42092) | mysterious | detailed |
|---|---|---|---|
| tracks cached / failed | 37 / 3 | 37 / 3 | 37 / 3 |
| first track ready | 6.9 s | 6.6 s | 4.4 s |
| three ready ("Start now" unlocks) | 13.2 s | 13.1 s | 10.7 s |
| fully prepared (`→ready`) | 207.1 s (3:27) | 205.7 s (3:26) | 206.2 s (3:26) |
| per-track landing interval, median | 3.06 s | 3.09 s | 3.11 s |
| per-track landing interval, mean | 5.56 s | 5.53 s | 5.61 s |
| stalls > 6 s (no-preview tracks) | 3 (30.8 s, 35.5 s, 32.5 s) | 3 (29.3 s, 35.9 s, 31.6 s) | 3 (32.2 s, 37.7 s, 29.4 s) |

**Deltas:** mysterious vs baseline — first ready −0.3 s, three ready −0.2 s, fully prepared −1.4 s, per-track median +0.04 s; detailed vs baseline — first ready −2.5 s, three ready −2.5 s, fully prepared −0.9 s, per-track median +0.05 s. Every delta is inside the run-to-run noise of the no-preview stalls (each ±3 s on its own) and of the per-track landing interval (median moves by hundredths of a second). **No measurable regression in either view.**

## What the baseline says about the design's pacing

The design was paced against **3–5 minutes** end to end. Measured: **3:27 for 40 tracks**, of
which ~99 s is the three no-preview stalls. Without them the same playlist would land in
~1:50. So the figure holds at Tunes Club scale, and the shape is as the design assumed: three
tracks are ready inside the first quarter minute, and the overwhelming majority of the wait
happens after the listener could already have started.

**Per-stage split for a representative track.** Read from the unified log of the mysterious run
(the BUG-031 `separate() enter/exit` audit, `MIRPipeline created`, and the landing), so it is a
property of the pipeline, not of either view. Resolve and download run ahead in the prefetch
window (`prefetchWindow = 4`) and overlap the previous track's analysis, so they are off the serial
path except at the no-preview stalls. Track 10 of the mysterious run; medians over all 37 in
parentheses:

| stage (serial, per track) | track 10 | median of 37 |
|---|---|---|
| stem separation (MPSGraph, 30 s preview) | 0.13 s | 0.12 s (0.11–0.17) |
| stem AGC warm-up → `StemFeatures` | 0.79 s | 0.80 s |
| MIR (BPM / key / mood / centroid) + two beat grids + grid-onset calibration + family sweep + cache | 2.13 s | 2.16 s (2.04–2.26) |
| **separate → landed** | **3.05 s** | **3.07 s** |

The stem model is not the bottleneck any more — the post-separation analysis is 70 % of the
serial cost, and the three no-preview stalls (~30 s each, the resolver's fallback wait) cost
more than thirty tracks' worth of analysis. Making preparation faster is a different increment;
this one only had to not make it slower.
