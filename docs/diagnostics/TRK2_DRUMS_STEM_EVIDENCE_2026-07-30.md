# TRK.2 — drums-stem onset evidence: premise measured, NOT proven

**Increment:** TRK.2 (beat-sync program, D-202) · **Defect:** BUG-065 (`dsp.beat`, P3)
**Date:** 2026-07-30 · **Outcome:** stopped at task 1's hard-stop gate. No runtime behaviour changed.

---

## 1. What TRK.2 assumed

From `docs/BEAT_SYNC_PROGRAM_PLAN.md` §TRK.2:

> Once live stems stabilize (~10 s), the tracker matches against drums-stem onsets instead of raw
> sub_bass … This is the category-4 live lever: Bleed's palm-muted 16ths saturate sub-bass flux;
> the drums stem carries the actual pulse.

The session prompt made this conditional, and correctly so:

> **Done-when:** a printed comparison exists showing, for the same capture, per-onset
> |offset-to-nearest-grid-beat| distributions for both sources. If drums-stem onsets are *not*
> measurably better aligned, **stop and report** — TRK.2's premise is unproven.

That gate fired. Tasks 2–5 were not started.

---

## 2. The instrument

`PhospheneEngine/Tests/PhospheneEngineTests/Integration/DrumsOnsetEvidenceTests.swift` —
env-gated (`PHOSPHENE_TRK2_EVIDENCE=1`), asserts nothing, prints the comparison.

For one capture it runs the **production** components end to end:

- `BeatDetector` on the full mix at the real 1024-sample FFT-hop cadence → today's evidence.
- `StemSeparator` (MPSGraph, the shipping model) tiled over the whole capture in its fixed
  ~10 s window → drums stem → a **second `BeatDetector` instance** on that stem (D-075: a separate
  detector, not a fused band). All six bands are measured, not just sub_bass, so
  "you tested the wrong band" is closed.
- Both onset sets are matched against the same `BeatGrid` with `GridOnsetCalibrator`'s ±200 ms
  window, then **bias-corrected** by each source's own median — the per-track grid-vs-detector
  offset is documented at ±50–150 ms and BUG-007.8's `initialDriftMs` already removes it in
  production, so scoring inside ±50 ms would only re-measure the bias.

Reported per source: onset count, matched count, share of **all** onsets landing within ±50 ms
(the tracker's search window) and ±30 ms (its tight gate) after calibration, the fitted drift
slope and R², the residual MAD about that fit, and a 12-bin histogram of where onsets sit in the
beat cycle.

**Separation cross-check.** The offline stem was validated against the live path's own dump:
RMS-envelope correlation **r = 0.82** between this harness's drums output and
`2026-07-30T15-39-21Z/stems/0005_Hummer/drums.wav`, at the correct 25.2 s lag. The offline
separation reproduces what the engine produces live.

---

## 3. Results — four captures

Share of all onsets within ±50 ms of a grid beat, bias-corrected. Higher is better.

| capture | full-mix sub_bass (today) | drums-stem sub_bass | Δ | best drums band |
|---|---|---|---|---|
| `love_rehab.m4a` (118 BPM; its histogram shows a single sharp on-beat peak — kick already locked to the grid) | **42.2 %** | 16.9 % | **−25.3** | low_mid 28.0 % (still −14.2) |
| `raw_tap.wav`, session `2026-07-30T15-39-21Z` (Hummer, 80.4 BPM — the BUG-065 capture) | 14.4 % | 11.0 % | −3.4 | low_mid 14.9 % (+0.5) |
| `bleed.wav` first 120 s (115 BPM — **the category-4 case TRK.2 was built on**) | 22.3 % | 22.4 % | +0.1 | high 24.8 % (+2.5) |
| `billie_jean.mp3` first 120 s (117 BPM, unambiguous backbeat) | 24.5 % | **25.5 %** | +1.0 | sub_bass 25.5 % (+1.0) |

Residual MAD (ms) about each source's own drift trend — the jitter no controller can learn away:

| capture | full-mix sub_bass | drums-stem sub_bass |
|---|---|---|
| love_rehab | 58.9 | 69.7 |
| Hummer | 101.5 | 95.6 |
| Bleed | 103.8 | 105.3 |
| Billie Jean | 92.7 | 84.8 |

**Verdict: drums-stem onsets are worse on two captures and a wash on two.** No capture shows a
meaningful gain, including Bleed — the single track the plan's category-4 argument rests on.
The best drums band anywhere beats the full mix by 2.5 percentage points, inside run-to-run noise.
Swapping the evidence source would not have fixed the TRK.1 controller.

### 3.1 The larger finding

The ceiling matters more than the comparison. **On every capture and every band, only ~15–25 % of
detected onsets land within ±50 ms of a beat** (love_rehab's full-mix 42 % is the outlier — its
histogram is the only one with a single sharp on-beat peak, i.e. a kick already locked to the
grid). Everywhere else the beat-cycle histograms show onsets piling up on the beat *and* on the
off-beat and 16ths, on both sources.

FA #68 says sub-bass onsets are events, not beats. This measurement generalises it: **the spectral
onset-detector family is weak beat evidence regardless of which band or which stem it runs on.**
Isolating drums removes bassline notes but adds hats, ghost notes and 16ths — it changes *which*
non-beat events fire, not *how many*.

That is a program-level result, not a TRK.2 result: any tracker whose evidence is an onset flag
inherits a ~75–85 % off-beat rate. It is why the tracker's ±50 ms search window exists, and why an
integrating controller fed that stream runs away (TRK.1: maxAbsDrift 101.5 ms, alignment 0.05).

---

## 4. A second, independent blocker in the delivery path

Even had the premise held, tasks 2–3 as specified would not have worked.

`PhospheneApp/VisualizerEngine+Audio.swift:300-355` (`runPerFrameStemAnalysis`) states its own
contract:

> Features carry ~5-10s of latency (we're always analyzing audio that's already been heard),
> which is acceptable because musical sections persist longer than that.

The live drums stem is a 10 s snapshot separated every ~5 s; the per-frame analyzer scans it from
the 5 s mark forward at wall-clock rate and re-anchors on each new separation. So the drums
waveform reaching `StemAnalyzer` at frame *t* is audio from *t* − 5…10 s, with a sawtooth reset.

That is fine for the energy and deviation fields it was built for. It is fatal for timing evidence:
`LiveBeatDriftTracker.processOnsetLocked(pt:)` timestamps every onset with the *current*
playback time. A drums onset delivered through this path would be stamped 5–10 s late, with a
discontinuity every 5 s. Task 3's "crossfade mirroring the stem pipeline's own live handoff" would
mirror exactly the mechanism that destroys the timestamp.

Making drums-stem onsets usable as timing evidence requires threading each onset's **true tap-time
timestamp** (derivable: separation anchor + window offset) through the analyzer into the tracker,
and accepting that the evidence is 5–10 s stale. That is a different, larger design than TRK.2
describes — and given §3 there is no measured reason to build it.

---

## 5. What was and was not changed

- **Added:** the diagnostic test above. Default-skipped; no production code touched.
- **Not changed:** `LiveBeatDriftTracker`, `MIRPipeline`, `StemAnalyzer`, any runtime behaviour.
- `PHOSPHENE_BEAT_PLL` remains default-off and unmodified.

### Pre-flight invariants (all confirmed before any work)

| check | result |
|---|---|
| `main` at `07dd3bd9` or later, tree clean | `3e63c0b1`, clean |
| `swiftlint --strict` | 0 violations |
| `swift test` with `PHOSPHENE_BEAT_PLL` unset | 1691 tests / 235 suites pass |
| `PHOSPHENE_BEAT_PLL=1 … --filter LiveDriftValidation` **must still fail** | fails: maxAbsDrift **101.54 ms** (limit 50), alignment **0.05** (limit 0.80) — the TRK.1 finding reproduces exactly |
| BeatBench fixtures at `~/phosphene_beatbench_fixtures` | 13 present incl. `bleed.wav` |

### BeatBench

**No behavioural change to beat sync ships in this increment**, so no before/after BeatBench table
is due. (The harness is also still unbuilt — GT.3.)

---

## 6. Reproduce

```bash
PHOSPHENE_TRK2_EVIDENCE=1 swift test --package-path PhospheneEngine --filter DrumsOnsetEvidence
```

Against a recorded session or another fixture:

```bash
PHOSPHENE_TRK2_EVIDENCE=1 \
PHOSPHENE_TRK2_AUDIO=~/phosphene_beatbench_fixtures/bleed.wav \
PHOSPHENE_TRK2_SECONDS=120 \
swift test --package-path PhospheneEngine --filter DrumsOnsetEvidence
```

`PHOSPHENE_TRK2_BEATS` takes a JSON `{"beats":[…],"bpm":…}` (e.g. extracted from a StemCache
`metadata.json`) and `PHOSPHENE_TRK2_GRID_OFFSET` shifts the grid into the audio's time base;
without them the grid is computed from the audio by `DefaultBeatGridAnalyzer`.
`PHOSPHENE_TRK2_DUMP_DRUMS` writes the separated drums stem as raw f32le mono 44.1 kHz for
cross-checking against a session's own stem dumps.
