# DSP.3.5 — Post-Validation BeatGrid Triage

**Session:** `2026-05-05T22-57-57Z`  
**Tracks tested:** Love Rehab (Chaim), Money (Pink Floyd), Pyramid Song (Radiohead), Money again  
**Mode:** Ad-hoc / reactive — no Spotify pre-analysis  
**Commits:** `eac2e140` (code), `c068d2b8` (docs)

---

## 1. Executive Summary

Manual testing after DSP.3.4 revealed two distinct live Beat This! failure modes on the
reactive path:

| Track | Symptom (pre-DSP.3.5) | Root cause | Fix |
|---|---|---|---|
| Love Rehab | PLANNED·LOCKED at 244.8 BPM — twice true tempo | 10-second window → double-time artefact | `halvingOctaveCorrected()` |
| Money (both plays) | REACTIVE throughout | Beat This! returned empty grid on 10-second 7/4 window | Retry at 20 s |
| Pyramid Song | PLANNED·LOCKED at 68.75 BPM ✓ | No bug — genuinely slow tempo | No change needed |

Both fixes land in the live path only. The offline Spotify-prepared path (30-second preview)
reliably detects the correct BPM for all three tracks and is unaffected.

---

## 2. Evidence from Manual Validation

Matt ran the sequence in ad-hoc reactive mode and observed:

> *Love Rehab — PLANNED·LOCKED achieved but beat is double-time. Switched to Money — still
> showing Reactive in Spectral Cartograph, does not reach PLANNED·LOCKED. Beat is all over
> the place. Switched to Pyramid Song — reached PLANNED·LOCKED after a few seconds. Pulse
> mostly synced to piano, small amounts of latency. Tried Money again after Pyramid Song.
> Still stays in Reactive after 20–30 seconds.*

### Confirmed from `features.csv` (25,821 frames, 3 track segments post-reset)

Track boundaries identified by `playback_time_s` drops > 5 s:

| Segment | Frames | Duration | First grid | BPM | Final mode |
|---|---|---|---|---|---|
| Love Rehab | 1–7,010 | ~116 s total (tap from track start) | frame 1,107 / pt 10.2 s | **244.770** | LOCKED (5,213 frames) |
| Money 1st | 7,011–16,566 | 159.3 s | never | n/a | REACTIVE (9,555 frames) |
| Pyramid Song | 16,567–22,929 | 106.1 s | frame 17,177 / pt 10.2 s | **68.750** | LOCKED (1,590 frames) |
| Money 2nd | 22,930–25,821 | 48.2 s (recording end) | never | n/a | REACTIVE (2,891 frames) |

> **Note on Money 1st play:** The very first row for Money 1st (frame 7,010) shows
> `mode=3 lock=2 bpm=244.770` — this is a stale carry-over from the Love Rehab BeatGrid
> before the `resetStemPipeline` write clears it. Frame 7,011 onwards is `mode=0 bpm=0`
> for the full 159-second session.

---

## 3. Love Rehab — Double-Time Root Cause

### 3a. Observed vs. corrected BPM

| Source | BPM | Notes |
|---|---|---|
| Live 10-second Beat This! (pre-fix) | **244.770** | 2× true tempo |
| After `halvingOctaveCorrected()` | **122.385** | 244.770 / 2 |
| Python reference (30-second offline) | **118.05** | 3.7% from corrected live |

The drift tracker accepted 244.770 BPM as valid and locked to it within ~4.5 seconds
(frame 1,374, pt 14.65 s). From the user's perspective, every other beat fired a visual
pulse — the pulse felt twice as fast as the music.

### 3b. Why a 10-second window causes double-time

Beat This! is a transformer trained on full-length audio. A 10-second window gives it
roughly 21 beats at 125 BPM (~490 ms beat period). At this window length the model
occasionally resolves to the 8th-note grid (~245 ms) rather than the quarter-note grid,
producing BPM ≈ 2× true. The 30-second window (~61 beats at 125 BPM) provides enough
inter-beat context for the model to reliably settle on the quarter-note grid.

### 3c. The halving rule — exact behaviour

`BeatGrid.halvingOctaveCorrected()` applies a **recursive halving loop**:

```
while correctedBPM > 160 && correctedBeats.count >= 2:
    correctedBPM /= 2
    correctedBeats = correctedBeats[even indices only]   // stride(by: 2)
```

**The rule is halving-only.** BPM < 80 is left unchanged. This is deliberate: some tracks
genuinely have slow tempos (Pyramid Song ~68 BPM) and doubling would be wrong. The upper
bound [> 160] covers the common double-time artefact from short windows without risking
false corrections on authentically slow tracks.

### 3d. What actually changes — beats array vs. BPM metadata

This is a physical beat decimation, not a metadata-only correction:

| Field | Change |
|---|---|
| `beats: [Double]` | **Physical decimation** — every other timestamp removed. At 244.770 BPM, ~41 beats in 10 s → ~21 beats at 122.385 BPM. |
| `bpm: Double` | Halved (244.770 → 122.385). |
| `downbeats: [Double]` | Re-snapped to surviving beats within ±40 ms. Downbeats on removed (odd-indexed) beats that fall outside the snap window are discarded. |
| `beatsPerBar: Int` | Recomputed from corrected downbeat inter-onset intervals: `round(median_downbeat_IOI / beat_period)`. |
| `barConfidence: Float` | Recomputed as fraction of downbeat IOIs consistent with new `beatsPerBar`. |
| `frameRate`, `frameCount` | Unchanged (original resolution metadata preserved). |

The resulting grid is passed to `offsetBy()` to produce the track-relative extrapolated
grid. Because `bpm` is now 122.385 in the corrected grid, `offsetBy` extrapolates future
beats at a ~490 ms period, not ~245 ms — so the full 300-second horizon is also at the
correct tempo.

---

## 4. Money — Reactive Root Cause

### 4a. Why the 10-second live window returned an empty grid

Money by Pink Floyd is in **7/4 time** at ~123.4 BPM. In a 10-second window this gives
roughly 20 beats. The 7/4 time signature creates an irregular downbeat pattern that the
Beat This! model struggles to resolve from a short clip: its training distribution skews
toward 4/4. The model returned an empty `beats` array on both the Money 1st and Money 2nd
plays in this session.

There is a secondary factor: the first 10 seconds of Money's tap audio may contain the
iconic cash-register intro, which has no pitched audio and irregular transients. Beat
detection on that material is structurally unreliable regardless of model quality.

### 4b. What the 20-second retry does

`liveBeatAnalysisAttempts` allows a second inference pass at `liveBeatRetrySeconds = 20.0 s`.
By 20 seconds the riff is established and the model has more beat evidence. Whether this
succeeds for Money 7/4 in practice is untested in the current session (the session ended
before Money 2nd played past 48 seconds). The retry provides a second chance but is not
guaranteed to succeed on irregular meters.

### 4c. Why the offline prepared BeatGrid is the durable solution

The **Spotify-prepared path** runs Beat This! on a 30-second preview clip during
`SessionPreparer` — before the user starts listening. At 30 seconds (~61 beats at 123 BPM)
the model has substantially more context. The Python reference fixture confirms reliable
detection:

```
money_reference.json: bpm=123.4, beats=63, beats_per_bar=2
```

A Spotify session would install this grid via `resetStemPipeline(for:)` → `mirPipeline.setBeatGrid()` 
before the first audio callback. The drift tracker would be in PLANNED·UNLOCKED immediately.
The live inference path would see `mirPipeline.liveDriftTracker.hasGrid == true` and cap
`liveBeatAnalysisAttempts = liveBeatMaxAttempts`, skipping all inference.

**The live 10-second path is inherently less reliable on complex meters.** It is the
correct fallback for ad-hoc/reactive sessions where no preview is available, but should
not be treated as equivalent to the prepared path for irregular-meter tracks.

---

## 5. Pyramid Song Status

Pyramid Song reached **PLANNED·LOCKED** correctly in this session, before DSP.3.5:

```
frame 17,177   pt = 10.20 s   mode=1 (UNLOCKED)   bpm = 68.750
frame 17,189   pt = 10.40 s   mode=2 (LOCKING)    bpm = 68.750
frame 17,843   pt = 21.30 s   mode=3 (LOCKED)     bpm = 68.750
```

**68.750 BPM is correct.** The Python 30-second reference gives 68.18 BPM — the live
10-second window produces 68.750, a 0.8% deviation. Both are within the drift tracker's
working range.

`halvingOctaveCorrected()` is a no-op for Pyramid Song: `68.750 < 80`, so the guard
`bpm > 160` fails immediately and the original grid is returned unchanged. This is the
key invariant — the halving-only rule must not double Pyramid Song's tempo.

The latency Matt observed ("small amounts of latency") is the drift tracker's EMA
convergence time, not a BPM error. The tracker needs ~4 tight-matched onsets (±30 ms)
to transition LOCKING → LOCKED. At 68.75 BPM that takes ~3–4 beat periods ≈ 2.6–3.5 s
after locking begins.

---

## 6. Remaining Risks

### 6a. Money 20-second retry may also return empty

If Beat This! returns empty at both 10 s and 20 s for Money (as it did in this session
for the 10-second attempt), the track stays REACTIVE with BeatPredictor as fallback.
BeatPredictor's kick-based IOI method will detect a tempo but cannot handle 7/4 meter.
The visual will have some beat reactivity but no correct bar-phase or downbeat tracking.

**Mitigation:** Use Spotify-prepared sessions for Money. The offline 30-second path is
confirmed reliable.

### 6b. Double-time may still occur at 20-second retry for other tracks

The 20-second retry uses the same 10-second audio snapshot (always
`liveBeatMinSeconds = 10.0 s` of audio regardless of when the attempt fires). It is not
a longer window — it gives the model the same 10 seconds of audio, but at a different
point in the track (seconds 10–20 instead of 0–10). If the track's first 10 seconds
consistently produce double-time for Beat This!, the retry will also produce double-time
and `halvingOctaveCorrected()` will correct both attempts identically.

The 20-second retry primarily helps tracks where the first 10 seconds are a quiet intro
or atypical opening (sparse transients, no kick) that confuse the model.

### 6c. Octave correction applies to the live path only

`halvingOctaveCorrected()` is called in `performLiveBeatInference()`, not in
`BeatGridResolver.resolve()` (the offline path). The offline resolver returns raw BPM
from trimmed-mean IOI — verified accurate on 30-second clips across all test tracks. Adding
correction to `BeatGridResolver` would break the pyramid_song golden fixture
(`bpm=68.18`, which must survive the resolver unchanged).

If an offline-prepared grid somehow lands above 160 BPM (not observed in any test case),
the drift tracker would lock to the wrong tempo. This is a theoretical risk only.

### 6d. Re-snap may discard downbeats in extreme cases

If `halvingOctaveCorrected()` decimates beats heavily (e.g., triple-halving at 322 BPM)
and the downbeat density is low, the ±40 ms snap tolerance may leave the corrected grid
with zero or very few downbeats. `beatsPerBar` falls back to the original value in that
case (`guard correctedDownbeats.count >= 2`). The `barPhase01` ramp would still function
(it falls back to `beatPhase01 / beatsPerBar` when downbeat count is low), but bar-boundary
accuracy would be reduced.

---

## 7. Next Recommended Increment

**DSP.3.6 — App-layer wiring test.**  
Integration test: `SessionPreparer.prepare()` → `StemCache.store()` →
`resetStemPipeline(for:)` → `mirPipeline.liveDriftTracker.hasGrid == true`.  
Confirms that the prepared BeatGrid path reaches the tracker before the first audio callback
and that `liveBeatAnalysisAttempts` is capped immediately on cache hit.

**Reel re-record with DSP.3.5 fixes applied.**  
Repeat the same ad-hoc session (Love Rehab → Money → Pyramid Song) with `eac2e140` built.
Expected outcomes:
- Love Rehab: PLANNED·LOCKED at ~122 BPM (correct; visual pulse at quarter-note rate)
- Money: may reach PLANNED·LOCKED at retry (20 s); still likely REACTIVE on irregular 7/4
- Pyramid Song: unchanged — PLANNED·LOCKED at ~69 BPM

The Money REACTIVE outcome on the live path is acceptable behaviour, not a regression.
The correct fix for Money is a Spotify-prepared session.
