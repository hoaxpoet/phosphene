# LFSTEM — Local-file stems land on the beat

**Status:** scoped, decisions taken, not started. Costs measured 2026-08-26
(`LocalFilePrepCostHarness`). **Two increments:** LFSTEM.1 (the series, §1–§8) and LFSTEM.2
(retire live separation on the local path, §9) — sequential, each with its own M7.
**Origin:** Matt, 2026-08-26 — *"i don't understand why we can't have stems land on the beat for
local files vs streaming audio"*. The answer is that we can; nothing structural prevents it.

---

## 1. The problem, in one line

Stem features reach presets **~2.5 s late** — every stem-driven behaviour in Skein, Glaze, Dragon
Bloom, Filigree, Mitosis, Nimbus and the rest follows the music by about a bar. For a **local
file** that latency is not physics. It is an artefact of analysing audio we have already decoded
as though we were hearing it for the first time.

## 2. Why streaming genuinely cannot have this, and local files can

**Streaming**: the audio arrives through a system-audio tap. We only ever have what has already
played; there is no future to analyse, and no reliable position inside the real track. The 2 s
window plus inference is irreducible there.

**Local files**: the whole file is on disk and we already decode all of it during preparation.
`PreviewAudio.fromLocalFile` ([`SessionTypes.swift:222`](../../PhospheneEngine/Sources/Session/SessionTypes.swift))
reads `AVAudioFile` to its full `file.length` and averages to mono — **no truncation**. This is
the same asymmetry Matt already accepted for `DYN.1c`: `CachedTrackData.loudnessProfile` is
measured "over the FULLY DECODED file during local-file preparation" and is `nil` for streaming.

## 3. What actually happens today (verified in the tree, not inferred)

1. **The cached stem snapshot describes the first ten seconds of the track — and nothing else.**
   `StemSeparator.requiredMonoSamples = 440320` (9.98 s at 44.1 kHz) and `separate()`
   pads-or-truncates its input to exactly that
   ([`StemSeparator.swift:160`](../../PhospheneEngine/Sources/ML/StemSeparator.swift)). Local-file
   prep hands it the entire file; the model sees the intro. That is where
   `CachedTrackData.stemFeatures` — **one `StemFeatures` value, not a series** — comes from.
2. **It is installed once and immediately demoted.** `pipeline.setStemFeatures(cached.stemFeatures,
   live: false)` at track change, after which everything comes from live separation.
3. **Live separation is what costs the 2.5 s.** `stemSeparationPeriodSeconds = 2.0`, plus
   inference; session `2026-08-26T22-04-58Z` logs `nominal_latency=2.5s` with inference
   270–474 ms under live contention.
4. **The mechanism we need is already shipped, for a different signal.**
   `CachedTrackData.instrumentFamilySeries` (IFC.4 / D-177) is a pre-analysed per-window series
   in playback order, and the live frame **samples it by playback position**. Zero latency,
   persisted to disk (schema v6), in production today.

**So the gap is exactly this: stems were cached as one number where they could have been cached
as a series.** Everything else — the full decode, the persistent per-file cache, the
sample-by-position pattern — is already built.

## 4. Measured costs

`LocalFilePrepCostHarness` (env-gated, `PHOSPHENE_PREP_COST=1`), three real 30 s fixtures through
the production `StemSeparator` / `StemAnalyzer` / `MoodClassifier` / `DefaultBeatGridAnalyzer`,
Mac mini, 2026-08-26:

| | love_rehab | so_what | there_there |
|---|---|---|---|
| Today's full `analyzePreview` (30 s clip) | **3.71 s** | **2.81 s** | **2.86 s** |
| Separation, per model window | 127 ms | 125 ms | 126 ms |
| `StemAnalyzer` sweep, per analysis frame | 1.59 ms | 1.58 ms | 1.60 ms |

Extrapolated to a 4-minute track at a 2 s series hop — the arithmetic, not a measurement:

- separation: 120 windows × ~126 ms ≈ **15 s**
- feature sweep: 10,335 frames × ~1.58 ms ≈ **16 s**
- **≈ 31 s of added preparation per track, once per file, ever** (persisted by content hash).

Two notes on reading these:

- **Offline inference is ~2× faster than live** (120–160 ms vs the 270–474 ms in the live log),
  because preparation is not competing with the renderer. Use the offline number for prep
  planning and the live one for playback.
- **The 2.8–3.7 s baseline is for a 30 s clip.** The stages that scale with length (decode, Beat
  This! grid, MIR, family sweep) would grow roughly linearly on a 4-minute file, so the *baseline*
  for a real track is an extrapolation this harness did not measure. If that number matters to
  the decision, measure it before quoting it.

## 5. Design

**Preparation.** Step the model's 10 s window across the whole decoded file at a 2 s hop. For
each window, run `StemAnalyzer` over the newest hop's worth of separated waveforms at the 1024
analysis hop, exactly as `VisualizerEngine+Audio` does live. Result: a dense
`[StemFeatures]` at ~43 Hz in playback order.

**Storage.** ~10,335 frames × ~220 B ≈ **2.3 MB per 4-minute track**, against stem waveforms
already persisted. Needs a `PersistentStemCache` schema bump.

**Playback.** Sample the series by playback position and feed `pipeline.setStemFeatures(…,
live: true)`. This is `InstrumentFamilyActivity.sample`'s pattern; follow it rather than inventing
a second one.

**The live path stays** — for streaming, and as the fallback when a local file has no series yet.

## 6. Decisions for Matt

**A. Does preparation block the music?** Today it does: `SessionManager.startLocalFiles` awaits
`prepareLocalFiles` before the `.ready` transition, and playback follows `.ready`. So the +31 s
lands *before the first note* on a file's first play.

- **(1) Block.** Simplest, and honest about what it is doing. First play of a new file waits
  ~30 s longer; every play after is instant (cached).
- **(2) Progressive.** Start immediately on live stems, compute the series in the background, swap
  when it is ready — the same progressive-readiness idea the session pipeline already uses. No
  waiting, but the first ~30 s of a new file plays with today's 2.5 s lag and then tightens
  mid-track, which is a visible change the viewer may notice.
- **DECIDED — Matt, 2026-08-26: (1) block.** The existing preparation progress UI carries it. The
  wait is once per file, it is honest, and a visible mid-track change in coupling is the kind of
  thing that reads as a bug rather than an improvement. No progressive path is to be built as a
  fallback "just in case" — if the wait turns out to be intolerable in use, that is a new
  decision with the real number in hand, not a second code path shipped on speculation.

**B. Should local-file playback stop running live separation once the series is installed?**
**DECIDED — Matt, 2026-08-26: yes, and it gets its own increment.** See §9 (**LFSTEM.2**). It is
kept out of LFSTEM.1 deliberately: LFSTEM.1's risk is *alignment* and LFSTEM.2's is *removal*, and
folding them together would mean a single M7 that cannot tell "the series is misaligned" from
"something else needed the live separator".

## 7. Risks

- **Every stem-driven preset's feel changes.** Their routes were tuned against values that arrive
  late and smoothed. Zero-latency stems will be materially snappier — expected better, but it is
  a real change across ~10 certified presets. **This lands as an M7 on Skein** (21 of 28 routes
  are stems, with `flick_trigger` an accent on all four) and a second look at Glaze.
- **The series must be time-aligned to playback, not to analysis order.** A one-window offset here
  is exactly the class of defect BUG-096 and the render-clock/musical-clock confusion produced.
  Assert alignment with a test, not by inspection.
- **Cache invalidation.** The series is keyed by content hash like the rest of the entry; a schema
  bump must invalidate old entries rather than half-read them.

## 8. Done-when (LFSTEM.1)

- A local file plays with `stem_*` columns advancing from frame 1, sampled by playback position,
  with no 2.5 s settling ramp at track start.
- An alignment test: a synthetic file whose stems change at a known second produces the change at
  that second ±1 analysis frame in the series.
- Preparation cost measured on a real 4-minute file, before and after, and recorded — not
  extrapolated from 30 s fixtures.
- Streaming behaviour byte-identical (the live path is untouched).
- M7 on Skein at 1080p and 4K: does the paint now follow the music, and did anything get worse?

---

## 9. LFSTEM.2 — retire live separation on the local-file path

**Decided 2026-08-26 (Matt). Runs after LFSTEM.1 has landed and been M7'd, not alongside it.**
**✅ IMPLEMENTED 2026-08-27 — the live 4K before/after is owed.**

**The three consumers, checked before removing anything, as this section required:**

1. `latestSeparatedStems` → `runPerFrameStemAnalysis` → `setStemFeatures` — **replaced.**
   `runPerFrameStemAnalysis` already stood down for a series at LFSTEM.1c, so the separator's
   output was being computed and discarded.
2. **The stem WAV dump** (`stems/` in a session directory) — **lost on tracks with a series, and
   said so out loud.** It is written from live separation output; there is no substitute that
   means the same thing (`CachedTrackData.stemWaveforms` holds only the track's first ~10 s, so
   dumping it would label the intro as though it were the passage being played). The session log
   now carries `STEM_SOURCE: live separation SUPPRESSED for this track (LFSTEM.2) — no stems/ WAV
   dump`. To listen to separation quality on a local file, play one whose series is absent, or use
   the streaming path. This is the "state plainly that it is streaming-only now" option this
   section pre-authorised.
3. `chain_health.json` / the ASH monitors — **clear, with evidence.** `ChainAnalyzer` contains
   **zero** stem references; `SignalHealthMonitor` has six, all sample-rate comments, and it
   ingests raw tap samples rather than stems. Neither can read "no separations happening" as a
   fault, so the BUG-070 shape is not reachable here.

**The gate is on the SERIES, never on the source** — `separationSupersededBySeries()`. A cache
miss, a schema mismatch or a failed analysis all leave the series empty and keep the live path
exactly as it was; gating on "is this a local file" would strand those tracks with no stems at
all. `StemSeriesWiringTests` asserts the gate, its condition, and that the suppression count
reaches the artifact.

**Owed:** the before/after this section demands — a 4K local-file session showing the
`frame_gpu_ms` delta, with zero `STEM_SEPARATION` lines and a rising `stem_suppressed`.

Once a local file plays from a pre-analysed series, the 2 s live separation timer on that path is
computing something nothing reads. Stopping it is worth an increment of its own for what it gives
back, not just for the tidiness:

- **A 142 ms MPSGraph job every 2 s comes off the GPU** for the whole of local playback. That is
  the same GPU the renderer is on, and it lands directly on the 4K frame budget that BUG-100 and
  BUG-106 have both been circling. **The payoff must be measured, not asserted** — a 4K local-file
  session before and after, `frame_gpu_ms` p50 either side, on the same file and preset.
- **The ML dispatch gate becomes moot on the local path**, which is where BUG-106's defect was
  most visible.
- It removes a whole class of latency and cadence bug (BUG-086's family) from local playback by
  removing the mechanism, not by tuning it.

**Verify before removing — the live separator's output has more than one consumer.** Named here so
the increment starts from a list rather than a grep:

1. `latestSeparatedStems` → `runPerFrameStemAnalysis` → `setStemFeatures`. This is the one the
   series replaces.
2. **The diagnostic stem WAV dump** (the `stems/` directory in a session folder) is written from
   live separation output. It is how separation quality gets listened to against real audio.
   Losing it silently on the local path would be a real regression in diagnostic capability —
   either write it from the prepared series instead, or state plainly that it is streaming-only now.
3. `chain_health.json` / the ASH signal-health monitors: confirm neither treats "no separations
   happening" as a fault before the timer stops firing. A health monitor that starts reporting a
   dead pipeline because the pipeline was deliberately switched off is the BUG-070 shape.

**Fallback policy is part of the increment, not an afterthought.** If a local file has no series
(cache miss, schema mismatch, a file whose analysis failed), live separation must still run. The
switch is "series installed for THIS track", not "the source is a local file".

**Done-when.** Local playback with a series installed logs zero `STEM_SEPARATION` lines; a
local file without a series still logs them at the old cadence; a 4K before/after shows the
`frame_gpu_ms` delta the increment claims; the stem WAV dump is either preserved or its loss is
documented and accepted.
