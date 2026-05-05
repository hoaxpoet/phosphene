# DSP.3.3 — Beat Sync Observability: Latency & Phase Calibration Notes

**Date:** 2026-05-05  
**Status:** Implementation complete. Runtime calibration in progress.

---

## Goal

Make beat-sync timing errors quantifiable so a human can say "the flash fires N ms late" rather than "something feels off." This is a calibration problem, not an algorithm problem — the algorithm (LiveBeatDriftTracker + Beat This!) produces correct beat positions; the question is whether the visual flash is in the right phase relationship to those positions.

---

## New Diagnostic Surfaces

### 1. Spectral Cartograph text overlay (runtime)

Four new text elements appear when Spectral Cartograph is active:

| Element | Position | Meaning |
|---------|----------|---------|
| Beat-in-bar counter | Center, below mode label | `"3 / 4"` — current beat index + meter. Amber on downbeat (beat 1), white otherwise. Only shown when lockState ≥ 1 (grid present). |
| Drift readout | Center, below beat counter | `"Δ drift = +12 ms"` — current drift-tracker correction. Muted green. Zero in reactive mode. |
| Phase offset | Center, below drift | `"offset = +10 ms"` — developer visual phase offset (if non-zero). Amber. |

The beat orb + BPM + mode label (from DSP.3.1) are unchanged and remain the primary indicators.

### 2. `[` / `]` developer shortcuts (runtime calibration)

While Spectral Cartograph is visible in the debug hold state (`L` key):
- `[` — decrease visual phase offset by 10 ms
- `]` — increase visual phase offset by 10 ms

Phase offset is clamped to ±500 ms. It shifts the displayed `beatPhase01` / `barPhase01` only — onset matching and drift estimation are unaffected. Offset is reset to 0 on process restart (not persisted).

**Calibration workflow:**
1. Start playback on a track with a known kick-drum on every beat.
2. Press `D` to show debug overlay. Press `L` to pin Spectral Cartograph.
3. Observe the amber beat orb flash. If it fires late relative to what you hear, press `[` to shift the phase earlier. If it fires early, press `]`.
4. Read the `Δ drift` value — if the drift is large and noisy, the tracker hasn't locked yet (wait for `● PLANNED · LOCKED` mode label).
5. Once locked, the `offset = ` readout shows your calibration value. If it's consistently non-zero, that's the pipeline latency.

### 3. SessionRecorder CSV columns (offline analysis)

New columns appended to `features.csv` in every session under `~/Documents/phosphene_sessions/<timestamp>/`:

| Column | Type | Description |
|--------|------|-------------|
| `barPhase01_permille` | int | `barPhase01 × 1000` as integer (avoids float precision noise in CSV diff) |
| `beatsPerBar` | int | Time-signature numerator (4 for 4/4, 7 for 7/4, etc.) |
| `beat_in_bar` | int | 1-indexed beat within bar. 1 = downbeat. |
| `is_downbeat` | int | 1 when `beat_in_bar == 1`, else 0 |
| `beat_sync_mode` | int | 0=reactive, 1=planned+unlocked, 2=planned+locking, 3=planned+locked |
| `lock_state` | int | 0=unlocked, 1=locking, 2=locked |
| `grid_bpm` | float | BPM from cached BeatGrid. 0 = no grid. |
| `playback_time_s` | float | Track-relative elapsed seconds (MIRPipeline.elapsedSeconds) |
| `drift_ms` | float | Drift-tracker correction in ms. Positive = beats arrive earlier than nominal. |

**Example offline analysis:**  
Load `features.csv` into pandas. Look at the `beat_in_bar == 1` rows and compare their `playback_time_s` against the BeatGrid's known downbeat positions. The difference is the pipeline clock offset.

```python
import pandas as pd

df = pd.read_csv('features.csv')
downbeats = df[df['is_downbeat'] == 1]
# downbeats['playback_time_s'] contains the playback time at each detected downbeat frame
# Compare against df['drift_ms'] — when drift_ms is stable (+/- 5ms), the tracker is locked.
```

---

## Clock Alignment Audit

### Sources of latency in the beat flash pipeline

```
Audio tap callback                      → t=0 (reference)
  ↓ LookaheadBuffer (2.5s delay)       → audio frames delayed by 2.5s for render alignment
  ↓ FFTProcessor (1024-pt window)       → ~11ms window at 48kHz (frame quantization)
  ↓ BeatDetector (onset detection)      → 0ms additional (per-frame)
  ↓ LiveBeatDriftTracker.update()       → 0ms additional (per-frame)
  ↓ FeatureVector.beatPhase01           → computed at analysis callback rate (~94Hz = 10.6ms)
  ↓ RenderPipeline.setFeatures()        → 0ms (shared memory write)
  ↓ SpectralCartograph.metal draw()     → GPU executes on next frame (~16ms at 60fps)
  ↓ Screen output                       → display pipeline (~8ms at 120Hz ProMotion)
```

**Total pipeline latency estimate:** The LookaheadBuffer is the dominant term — it is intentionally 2.5s so the render and analysis frames are aligned. Within that window, the relative timing of beat events is preserved. The question for calibration is whether `beatPhase01 = 0` (the sawtooth's zero crossing) is at the right phase offset from the heard beat.

### Why drift ≠ phase error

`drift_ms` in the CSV is the LiveBeatDriftTracker's estimate of the clock offset between the audio playback timeline and the BeatGrid's nominal beat positions. It is NOT the visual display latency. When `drift_ms` is stable and small (< 20ms), the tracker is correctly estimating beat positions. If the visual flash still feels late, the issue is the `visualPhaseOffsetMs` calibration.

### When to use each tool

- **Drift readout** (`Δ drift`): diagnose whether the tracker has converged. Large drift = tracker still locking. Stable drift but wrong visual timing = use phase offset.
- **Phase offset** (`[ / ]`): shift the visual phase to match perception. If you need more than ±50ms, something structural is wrong (e.g., wrong playback time domain, wrong BeatGrid offset).
- **CSV `drift_ms` + `playback_time_s`**: offline analysis of systematic bias across a full track.

---

## Known Limitations

1. **No video-audio sync measurement**: The CSV records `wallclock_s` (CFAbsoluteTime at command buffer completion), not screen presentation time. Screen presentation latency (~8ms at 120Hz, ~16ms at 60Hz) is not captured. Use `CMTime` video timestamps from `SessionRecorder+Video.swift` for a tighter bound.

2. **LookaheadBuffer alignment not exposed**: The 2.5s delay is hardcoded in `LookaheadBuffer`. If the delay is changed, `playback_time_s` in the CSV is still derived from `MIRPipeline.elapsedSeconds` (analysis-side clock), not the render-side clock. They should track together but a systematic offset would be invisible in the CSV alone.

3. **Bar phase in reactive mode**: `barPhase01` and `beat_in_bar` are both 0/1 in reactive mode (no BeatGrid). The beat-in-bar counter is hidden in the overlay when `lockState == 0`.

---

## Increment Status

| Task | Status |
|------|--------|
| Core Text mirroring fix (DynamicTextOverlay) | ✅ |
| SpectralCartographText extended draw() API | ✅ |
| Beat-in-bar counter in overlay | ✅ |
| Drift + phase offset readout in overlay | ✅ |
| FeatureVector threaded to textOverlayCallback | ✅ |
| `[`/`]` shortcuts for ±10ms phase offset | ✅ |
| downbeatTimes + driftMs in SpectralHistoryBuffer | ✅ |
| BeatSyncSnapshot struct | ✅ |
| SessionRecorder CSV new beat-sync columns | ✅ |
| Engine tests (22 new) | ✅ |
| App build clean | ✅ |
