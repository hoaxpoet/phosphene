# PREP.1 — where the preparation minutes go

**Date:** 2026-09-04 · **Increment:** PREP.1 (measurement only; nothing optimised) · **Decision it feeds:** [D-242]

---

## The headline, before anything else

Two findings, and everything else in this report is a rounding error beside them.

**1. The 50 s/track was measured on a `-Onone` build.** Every app bundle in DerivedData on this
machine is a **Debug** build — 35 of them, zero Release — and Debug sets
`SWIFT_OPTIMIZATION_LEVEL = -Onone` (`UzumeApp.xcodeproj/project.pbxproj:1222`). The bundle whose
build and access times match the start of Matt's D-242 session is
`UzumeApp-dcaulglwfskxnqcjhmawykzaxizg/Build/Products/Debug/Uzume.app`. Running the identical
pipeline over the identical 11 files costs **54.4 s/track compiled `-Onone`** and **14.3 s/track
compiled `-O`** — a **3.8× factor that is purely build configuration**. D-242's "~6.7× over budget"
is ~2.2× over on an optimised build of today's code, before a line of it changes.

**2. Of what remains, one stage is 89 % and everything else is noise.** The LFSTEM.1 whole-file
stem sweep is **140.5 s of a 157.6 s optimised run**. The next largest stage is MIR at 3.2 %. There
is no second bottleneck to find; there is one stage, and it costs what it costs for a structural
reason.

The sweep is not slow code. It separates every second of the track **about five times**: the
separator's window is 9.985 s (`StemSeparator.requiredMonoSamples` = 440,320 at 44.1 kHz) and the
sweep keeps `hopSeconds = 2.0` s of each window. That is ~1,164 separations for this album's
2,328.6 s, and 140.5 s ÷ 1,164 = **121 ms each** — the same price as the single separation
`analyzePreview` makes (`stem_separation`, 1.5 s across 11 tracks = 136 ms). The cost is the 5×
redundancy, not the model, and that redundancy is deliberate: it is what gives every frame the same
~8 s of preceding context live separation has (`SessionPreparer.analyzeStemSeries`, "Window
placement, which is the part that matters").

---

## 1. Reproduction

Matt's figure had to be reproduced before it was explained, and it was — twice, from two
directions.

**His own session is the first reproduction.** `~/Documents/uzume_sessions/2026-09-03T21-38-45Z/session.log`
is the D-242 run itself: David Bowie, *Low* (1977), 11 FLAC files, cold cache.

```
[2026-09-03T21:40:38Z] WIRING: SessionPreparer.prepareLocalFiles ENTER count=11 …
[2026-09-03T21:52:15Z] WIRING: SessionPreparer.prepareLocalFiles DONE cached=11 failed=0 total=11
[2026-09-03T21:52:15Z] WIRING: SessionManager.startLocalFiles→ready count=11
```

**697 s for 11 tracks = 63.4 s/track**, against D-242's 50 s/track on a different 12-file folder.
`.ready` follows `DONE` in the same second, so the walk *is* the wait (see §7).

**The second reproduction is mine**, on the same files, through the same code, with the timing
probe on. Each configuration was run twice; the artifact kept in `docs/diagnostics/PREP1/` is the
second of the pair, and both figures are given so the spread is visible.

| run | build | tracks at once | wall clock | per track | per second of audio |
|---|---|---|---|---|---|
| Matt, in-app, `2026-09-03T21-38-45Z` | Debug (`-Onone`) | 1 | 697 s | **63.4 s** | 0.299 |
| B — headless | Debug (`-Onone`) | 1 | **598.7 s** (593.2 s) | **54.4 s** | 0.257 |
| A — headless | Release (`-O`) | 1 | **157.6 s** (163.6 s) | **14.3 s** | 0.068 |
| C2 — headless | Release (`-O`) | 2 | 96.3 s | 8.8 s | 0.041 |
| C4 — headless | Release (`-O`) | 4 | killed — see §5 | — | — |

Run-to-run spread is ~4 %. Run B lands within 14 % of Matt's in-app number; the residue is the
app's own render loop (his session drew 148,842 frames) plus a second preparation walk that
overlapped his track 1. **The number reproduces, and the 50 s/track is real** — for the build it
was measured on.

**Corpus.** `/Volumes/Extreme SSD/B/Bowie, David/[1977] - Low`, 11 FLAC, 2,328.6 s (38.8 min) of
audio, 112.9 s shortest to 383.7 s longest, mean 211.7 s. These are the exact files Matt ran.
Machine: Mac mini, Apple M2 Pro, macOS 26.5.1 (from the session log's `host` line). Cache state:
cold — every run got a fresh scratch cache directory. **Matt's real stem cache at
`~/Library/Application Support/Uzume/StemCache` (396 MB) was never read, written, moved or
deleted**; `PrepTimingRunner` refuses a `--cache` path inside Application Support.

---

## 2. Where the time goes — per stage

Release, serial, 11 tracks, 2,328.6 s of audio (`runA-release-serial.csv`). `cores` is CPU-seconds
burned per wall second: 1.00 is one saturated core of ten, below 1.00 means the process spent time
waiting.

| stage | wall (s) | share | cores | ms per second of audio |
|---|---|---|---|---|
| **`stem_series_sweep`** (LFSTEM.1) | **140.5** | **89.2 %** | 0.71 | **60.3** |
| `mir` | 5.0 | 3.2 % | 1.10 | 2.1 |
| `instrument_family` (IFC.4) | 3.5 | 2.2 % | 0.94 | 1.5 |
| `decode` | 2.6 | 1.6 % | 1.71 | 1.1 |
| `beat_grid` | 2.5 | 1.6 % | 0.77 | 1.1 |
| `stem_separation` | 1.5 | 0.9 % | 0.93 | 0.6 |
| `grid_onset_calibration` | 0.7 | 0.4 % | 1.00 | 0.3 |
| `content_hash` | 0.6 | 0.3 % | 0.26 | 0.2 |
| `stem_warmup` | 0.4 | 0.2 % | 1.24 | 0.2 |
| `loudness_profile` (DYN.1c) | 0.2 | 0.2 % | 1.24 | 0.1 |
| `cache_write` | 0.2 | 0.1 % | 0.63 | 0.1 |
| `metadata_artwork` | 0.0 | 0.0 % | 1.21 | 0.0 |
| `cache_probe` | 0.0 | 0.0 % | 1.00 | 0.0 |
| **sum of stages** | **157.6** | | | |

The stage durations account for **100.0 %** of the summed per-track wall clock (`TRACK_TOTAL`
157.6 s), so no stage is missing from the list.

**The same run compiled `-Onone`** (`runB-debug-serial.csv`, 598.7 s) — worth printing because it
says *which* stages the build configuration punishes, and therefore which are Swift and which are
model dispatch:

| stage | wall (s) | share | ms per second of audio | Debug ÷ Release |
|---|---|---|---|---|
| `stem_series_sweep` | 338.7 | 56.6 % | 145.5 | 2.4× |
| `mir` | 119.2 | 19.9 % | 51.2 | **23.8×** |
| `grid_onset_calibration` | 54.5 | 9.1 % | 23.4 | **79.6×** |
| `instrument_family` | 31.0 | 5.2 % | 13.3 | 8.9× |
| `decode` | 28.7 | 4.8 % | 12.3 | 11.1× |
| `loudness_profile` | 13.5 | 2.3 % | 5.8 | **54.7×** |
| `stem_warmup` | 7.8 | 1.3 % | 3.4 | 20.8× |
| `beat_grid` | 2.7 | 0.5 % | 1.2 | 1.1× |
| `stem_separation` | 1.8 | 0.3 % | 0.8 | 1.2× |
| hash / cache write / metadata / probe | 0.7 | 0.1 % | 0.3 | ~1.0× |

The pure-Swift DSP stages (`mir`, `grid_onset_calibration`, `loudness_profile`) run 24–80× slower
unoptimised; the MPSGraph stages (`beat_grid`, `stem_separation`) barely move, because the work is
on the GPU either way. **A Debug build does not merely slow preparation down — it changes which
stage looks like the problem.** On `-Onone` the profile reads "sweep 57 %, MIR 20 %"; optimised it
reads "sweep 89 %, everything else 11 %".

---

## 3. Cost per second of audio, and the 40-track projection

Costing per track hides the fact that a 6-minute track is three times the work of a 2-minute one.
Per second of decoded audio (run A, Release, serial):

| track | audio (s) | prepare (s) | sweep (s) | ms per second of audio | sweep share |
|---|---|---|---|---|---|
| 02 Breaking Glass | 112.9 | 7.6 | 6.8 | 67.3 | 89.4 % |
| 03 What In The World | 143.1 | 9.5 | 8.6 | 66.6 | 89.9 % |
| 01 Speed Of Life | 167.2 | 12.1 | 10.1 | 72.3 | 83.7 % |
| 07 A New Career In A New Town | 173.3 | 11.5 | 10.3 | 66.1 | 90.2 % |
| 06 Be My Wife | 176.6 | 11.8 | 10.6 | 66.8 | 89.9 % |
| 04 Sound And Vision | 183.4 | 12.2 | 11.0 | 66.5 | 89.9 % |
| 10 Weeping Wall | 208.2 | 13.9 | 12.5 | 66.6 | 90.3 % |
| 05 Always Crashing In The Same Car | 213.7 | 14.2 | 12.8 | 66.7 | 90.1 % |
| 09 Art Decade | 227.2 | 15.2 | 13.6 | 67.0 | 89.3 % |
| 11 Subterraneans | 339.3 | 23.0 | 20.3 | 67.8 | 88.2 % |
| 08 Warszawa | 383.7 | 26.5 | 23.8 | 69.2 | 89.9 % |

**Flat.** 66.1 to 72.3 ms per second of audio across a 3.4× range of track length. Nothing scales
badly; the pipeline is linear in duration and the per-track fixed cost is about 0.07 s (hash +
cache probe + metadata + cache write together are 0.8 s across all 11 tracks). The one outlier is
track 1 at 72.3 — the cold MPSGraph compile, the same ~1 s tax PREPPERF.1 found on the streaming
path.

**Projection to the budget.** D-242's budget is 40 tracks in 300 s. At a 4-minute mean track
(9,600 s of audio — the album's own mean is 211.7 s, which is kinder):

| configuration | s per second of audio | 40 × 4 min | vs 300 s |
|---|---|---|---|
| today, Debug, serial (**what D-242 measured**) | 0.257 | 2,467 s (41 min) | **8.2× over** |
| today, Release, serial | 0.068 | 650 s (10.8 min) | **2.17× over** |
| Release, 2 tracks at once (measured, §5) | 0.041 | 397 s (6.6 min) | 1.32× over |
| Release + sweep hop 2 s → 4 s (arithmetic) | 0.038 | 360 s | 1.20× over |
| Release + 2 at once + sweep hop 4 s (arithmetic) | 0.023 | 220 s | **inside** |
| Release + sweep redundancy removed (arithmetic) | 0.020 | 187 s (3.1 min) | **inside** |

Only the first three rows are measurements. The last three recompute the measured per-stage costs
under a changed sweep hop, and they are estimates until PREP.2 measures them.

---

## 4. Format: a null result

Same three tracks (680.0 s of audio), FLAC as ripped versus AAC 256 kbps transcoded with
`afconvert`. Release, serial, cold cache.

| format | wall clock | per track | per second of audio | `decode` stage |
|---|---|---|---|---|
| FLAC | 48.1 s | 16.0 s | 0.071 | 0.8 s (1.1 ms per audio-s) |
| AAC (m4a) | 47.2 s | 15.7 s | 0.069 | 0.4 s (0.6 ms per audio-s) |

**FLAC decoding costs 0.4 s more across 11.3 minutes of audio — under 1 % of preparation.** The
FLAC files in Matt's run are not why it took ten minutes. Container and codec are not a lever.

## 4b. Track length: also a null result

Covered by the per-track table in §3 — the corpus already spans 112.9 s (under 2 min) to 383.7 s
(over 6 min) and the cost per second of audio is flat across it. No stage scales worse than
linearly with length. This separates the two hypotheses the prompt named: **the pipeline is
uniformly heavy; no single stage scales badly.**

---

## 5. Saturated, or waiting? — the serial-loop question

The sweep holds **0.71 cores** of ten. It is not CPU-bound; it is a chain of one MPSGraph
separation per 2 s of audio, each ~121 ms, with the process waiting on the GPU between dispatches.
That predicts spare capacity, but a prediction is not a finding, so it was measured directly: the
same 11 tracks, the same build, prepared **2 at a time**.

| tracks at once | wall clock | speedup | note |
|---|---|---|---|
| 1 (the shipping loop) | 157.6 s / 163.6 s | — | two runs |
| 2 | **96.3 s** | **1.64–1.70×** | model instances not shared between workers |
| 4 | — | — | **killed** by macOS `memorystatus` |

**~1.7× at two workers. The stages overlap; they do not merely contend.** That is the answer to the
question D-242 left open, with the measurement behind it.

**But four workers is not two more of the same.** The 4-way run was killed three times:

```
memorystatus: killing largest compressed process PrepTimingRunner [3307] 23642 MB
memorystatus: killing largest compressed process PrepTimingRunner [3684] 45070 MB
```

Peak resident size on the serial run is already **3.08 GB** for four tracks (2.65 GB at two
workers). Preparation has a large transient memory footprint per in-flight track, and four
whole-file analyses at once — two of them the album's 6-minute pieces — exceeded what the machine
would give. **This is a lead, not a diagnosis**: 23–45 GB is far more than the audio and the stems
account for, and something in the sweep's loop or in MPSGraph's caching is holding memory across
separations. PREP.2 must measure that before it picks a worker count, and should share model
instances rather than duplicating them per worker as this runner does.

---

## 6. The streaming control

Streaming prepares a 30 s preview through `SessionPreparer.analyzePreview` — the same call the
local path makes. Running that call on 30 s windows of the same 11 tracks isolates the shared
analysis from the whole-file extras (`runE-streaming-control.csv`, Release):

| path | per track | per second of audio |
|---|---|---|
| shared `analyzePreview`, 30 s window | **0.39 s** | 13.1 ms |
| local, whole file | **14.3 s** | 67.7 ms |

Per track the local path costs **37× the shared analysis**, and **12.8 s of the 13.9 s difference
is the LFSTEM.1 sweep alone**. Per second of audio the shared analysis is actually the *dearer* of
the two (13.1 vs 7.4 ms for the local path's non-sweep stages) because its per-track fixed costs —
one separation, one beat-grid — amortise over 30 s instead of 200 s.

**So the local path is not heavy because it is the local path.** It is heavy because of one stage
that streaming structurally cannot run.

(Caveat: the runner decodes the whole file and truncates, where streaming downloads 30 s. The
`decode` stage is excluded from the 0.39 s above for that reason. PREPPERF.2's live streaming
figure — 12 tracks in 29 s, 2.4 s/track — includes network fetch and was itself taken on a Debug
build.)

---

## 7. What the listener is actually waiting for

`SessionManager.startLocalFiles` awaits the entire walk before `_completeLocalFilesReady`, and
Matt's log shows `prepareLocalFiles DONE` and `startLocalFiles→ready` in the same second. **On the
local path the listener waits for all 40 tracks, not for the first one.**

The affordance to not do that already exists: `_runLocalFilePreparation` sets
`trackStatuses[placeholder] = .ready` per track as it goes, which drives
`progressiveReadinessLevel`, and `SessionManager.startNow()` transitions `.preparing → .ready` from
any source with "background prep continues" in its own log line. Whether local playback then starts
correctly from a `startNow` transition — the plan is built by `_completeLocalFilesReady`, which
`startNow` does not call — is **unverified**, and it is the first thing PREP.2 would have to check.

The arithmetic is worth stating because it is stark: preparation costs **0.068 s per second of
audio**, so it runs about **15× faster than playback**. Once the first track is ready, the walk can
never be caught by the music.

---

## 8. Options

Ranked by measured payoff. Nothing here is implemented.

### Option 1 — Measure and ship against a Release build. Payoff: **3.8×**, measured.

**What it costs the listener: nothing.** No behaviour changes at all.

54.4 s/track becomes 14.3 s/track on the same code and the same files. This is not a fix — the
budget is still missed by 2.2× at 40 tracks — but every other number in this report is unreadable
until it is applied, and D-242's headline should be re-stated against an optimised build before
anything is cut. The practical change is a habit, not code: the run a performance claim is made
from is built `-configuration Release`. Development continues in Debug.

### Option 2 — Spend less of the sweep on re-separating the same audio. Payoff: **up to 5× on 89 % of the run**, arithmetic from measured per-separation cost.

**What the listener could lose: stem character at the start of each kept span.** This is a product
decision, and it is Matt's.

The sweep keeps 2 s out of each 9.985 s separation window, so every second of audio is separated
about five times. `hopSeconds` is a parameter. Raising it to 4 s halves the sweep (67.7 → 37.5 ms
per second of audio); raising it to the full window removes the redundancy entirely (67.7 → 19.5
ms, which lands a 40-track playlist at ~187 s, inside the budget, with no concurrency at all).

The redundancy is not waste — it is the design. The kept span sits at the *end* of its window on
purpose so every frame has ~8 s of preceding context, "deliberately the same relative position the
live path reads from … so the series carries the same character as the values presets were tuned
against". Widen the span and frames near its start see less preceding context than live does. At
hop 4 s the worst-case frame still has ~6 s of context; at hop 10 s the first frame of each span
has almost none, and the stem values would step at every span boundary — every 10 s, for the whole
track. Whether that is visible in a stem-led preset is a listening question. **If this option is
taken it wants an A/B on Skein or Aurora Veil before it is believed**, not an arithmetic argument.

### Option 3 — Prepare two tracks at once. Payoff: **~1.7×**, measured.

**What the listener loses: nothing directly**, provided the walk still completes in playlist order
so the first track is genuinely first.

The stages overlap. Two caveats, both from §5: four workers was killed by the OS at 23–45 GB, so
the worker count must be bounded and the memory footprint understood first; and the workers here
each built their own `StemSeparator` / beat-grid / PANNs instances, which a real implementation
should not do (`StemSeparator` serialises internally — BUG-031 — so sharing one would serialise the
sweep and give the win straight back).

### Option 4 — Stop making the listener wait for track 40. Payoff: the wait becomes ~15 s instead of ~10 minutes; a [D-242] amendment rather than an optimisation.

**What the listener loses: nothing, unless they skip forward past the prepared prefix** — and
`.partial` handling already exists for tracks that arrive without stems.

Preparation runs 15× faster than playback. "Time to `.ready`" and "time to fully prepared" are
different numbers and only the first is a wait. The mechanism is mostly built — per-track
`trackStatuses`, `progressiveReadinessLevel`, `startNow()` — and the local path simply does not use
it for the `.ready` transition. This is the cheapest option on the list and the only one that
changes what the listener experiences rather than what the machine does.

It does not remove the need for the others: the walk still has to finish before a 40-track playlist
is fully planned, and the Orchestrator's whole proposition is a session planned in advance.

### Not recommended: cutting the sweep or the loudness profile.

Deleting the sweep would take the local path to ~1.6 s/track. It would also put local-file stems
back ~2.5 s behind the music, which is the latency LFSTEM.1 and LFSTEM.2 were built to remove and
that passed an M7. The loudness profile costs 0.2 s across the whole album (0.2 %) — cutting it
buys nothing. **The expensive thing here is not a mistake; it is a feature with a price tag, and
Option 2 is a way to negotiate the price rather than stop paying it.**

---

## 9. What was not measured

Stated so the report is not read as more than it is.

- **No in-app run.** Every number of mine comes from `PrepTimingRunner`, which drives
  `LocalFilePreparationPipeline` — the same code `VisualizerEngine.prepareLocalFile(url:)` calls,
  moved into the engine at PREP.1 for exactly this reason. What it does not carry is the app around
  it: the render loop, the preparation UI, the session recorder. Matt's own session log is the
  in-app measurement, and it is 14 % above my headless Debug figure.
- **The Release-build claim has not been confirmed in-app.** The 3.8× is measured headless on
  identical inputs, and the build configuration of Matt's session is established from DerivedData
  and `project.pbxproj`. A single Release-configuration app run over the same folder would settle
  it in five minutes and is the one measurement still owed.
- **The 23–45 GB at four workers is unexplained.** Reported, not diagnosed.
- **`--concurrency` is a property of the measurement runner only.** The shipping loop in
  `SessionPreparer._runLocalFilePreparation` is untouched and still strictly serial.
- **No behavioural change to beat sync.** `computeBeatGrids` is timed and nothing else; no
  `BeatGridResolver` / `BeatActivationDecoder` / `DefaultBeatGridAnalyzer` edit.

## 10. Reproducing this

```bash
swift build -c release --package-path UzumeEngine --product PrepTimingRunner

# the headline run
UZUME_PREP_TIMING=1 ./UzumeEngine/.build/release/PrepTimingRunner \
  --cache /tmp/prep-cold --out /tmp/prep-A \
  --folder "/Volumes/Extreme SSD/B/Bowie, David/[1977] - Low"

# the streaming control
UZUME_PREP_TIMING=1 ./UzumeEngine/.build/release/PrepTimingRunner \
  --preview-seconds 30 --cache /tmp/prep-cold-e --out /tmp/prep-E --folder "…"

# two tracks at once
UZUME_PREP_TIMING=1 ./UzumeEngine/.build/release/PrepTimingRunner \
  --concurrency 2 --cache /tmp/prep-cold-c --out /tmp/prep-C --folder "…"
```

Each run writes `preparation.csv` (one row per track per stage: wall ms, CPU ms, cores, decoded
duration, ms per second of audio) and `summary.txt`. The same sidecar is written by a real session
when `UZUME_PREP_TIMING=1` is set in the app's environment — it lands beside `features.csv` in the
session directory.

**The gate costs nothing.** Four tracks, Release, probe on versus probe off, alternating:

| probe | runs (s) |
|---|---|
| off | 41.71, 43.30, 43.84 |
| on | 43.79, 43.26 |

The two conditions are inside the spread of the closed-gate runs alone. With `UZUME_PREP_TIMING`
unset the sink is `nil` and every stage boundary is one `guard let` — the "off" column above is
exactly that path (`--disable-probe`).

**Artifacts:** `docs/diagnostics/PREP1/` — `runA-release-serial.csv`, `runB-debug-serial.csv`,
`runC2-release-concurrency2.csv`, `runE-streaming-control.csv`, `runD-flac.csv`, `runD-m4a.csv`,
each with its `.summary.txt`.
