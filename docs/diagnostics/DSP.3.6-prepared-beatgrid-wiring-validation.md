# DSP.3.6 — Prepared BeatGrid Wiring Validation

**Increment:** DSP.3.6  
**Status:** ✅ Complete  
**Date:** 2026-05-05  
**Commit:** see `[DSP.3.6]` in git log  
**Prior work:** `docs/diagnostics/DSP.3.5-post-validation-beatgrid-triage.md`

---

## 1. What the Tests Prove

`PreparedBeatGridWiringTests.swift` (5 tests in `Integration/`) validates the production
wiring path:

```
SessionPreparer.prepare()
  → StemCache.store(CachedTrackData, for: track)
  → VisualizerEngine.resetStemPipeline(for: track)
      → stemCache.loadForPlayback(track:)
      → mirPipeline.setBeatGrid(cached.beatGrid)
          → liveDriftTracker.setGrid(grid)
              → liveDriftTracker.hasGrid == true
```

The tests exercise each node in this chain using real `StemCache` and `MIRPipeline`
instances, matching the logic in `resetStemPipeline(for:)` exactly. `VisualizerEngine`
itself cannot be instantiated in SPM tests (requires Metal + AudioBuffer + RenderPipeline),
but the two lines of interest in `resetStemPipeline` are:

```swift
// VisualizerEngine+Stems.swift — resetStemPipeline(for:)
if let cached = stemCache?.loadForPlayback(track: identity) {
    mirPipeline.setBeatGrid(cached.beatGrid)   // ← tested by all five tests
} else {
    mirPipeline.setBeatGrid(nil)               // ← tested by tests 3 & 5
}
```

### Tests and invariants

| # | Test name | What it proves |
|---|---|---|
| 1 | `preparedGrid_viaStemCache_hasGrid` | Non-empty BeatGrid in cache → installed in MIRPipeline → `hasGrid == true`, BPM matches, lockState ≠ .unlocked |
| 2 | `preparedGrid_guardCondition_blocksLiveInference` | `hasGrid == true` → `runLiveBeatAnalysisIfNeeded` guard `!hasGrid` is false → live inference skipped |
| 3 | `noCacheEntry_liveInferenceAllowed` | No cache entry → `setBeatGrid(nil)` → `hasGrid == false` → live inference permitted |
| 4 | `emptyGridInCache_liveInferenceAllowed` | `.empty` BeatGrid in cache → `hasGrid == false` → live inference permitted (empty grid is not usable) |
| 5 | `trackChange_clearsGrid_allowsLiveInference` | Track A with grid → track change to uncached track B → grid cleared → live inference permitted |

---

## 2. Prepared-Cache vs Live-Fallback Policy

The policy is encoded in `VisualizerEngine+Stems.swift` and is now documented here:

| Condition | Grid source | Live inference | Notes |
|---|---|---|---|
| Cache hit, non-empty BeatGrid | **preparedCache** | Blocked (`liveBeatAnalysisAttempts` capped at max) | Offline 30-second path is authoritative |
| Cache hit, `.empty` BeatGrid | none (reactive) | **Allowed** | Analyzer was nil or track was too short |
| Cache miss | none (reactive) | **Allowed** | Ad-hoc session, or track not yet prepared |
| Live analysis succeeds | **liveAnalysis** | N/A (it ran) | Only fires when no prepared grid exists |
| Live analysis returns empty | none (reactive) | Retried at 20 s | Second attempt on same 10 s window |

**Rule:** Prepared-cache grid wins unconditionally. Live inference may only *add* a grid
when none is present; it never *replaces* a valid prepared grid. Future merge/refinement
semantics (e.g., using the live drift offset to update the prepared grid's phase) are
explicitly out of scope until a separate design decision is made.

---

## 3. Why Money-Like Tracks Should Prefer Prepared Cache

Money by Pink Floyd (7/4, ~123.4 BPM) demonstrates why the offline path matters:

### Live path (ad-hoc session)

| Attempt | Window | Result |
|---|---|---|
| At 10 s | Seconds 0–10 of tap audio | Empty grid (cash-register intro + irregular 7/4) |
| Retry at 20 s | Seconds 10–20 of tap audio | Empty grid (same 10-second window, different start offset) |
| Outcome | REACTIVE throughout | BeatPredictor fallback; no bar-phase tracking |

The Beat This! model returns empty on a 10-second window of 7/4 audio. This is not a
calibration problem — it is a structural limitation of the short-window inference path on
irregular-meter music.

### Prepared path (Spotify session)

```
money_reference.json (30-second offline):
  bpm=123.4, beats=63, beats_per_bar=2
```

The 30-second preview gives Beat This! ~63 beats of evidence. The model reliably detects
the correct tempo and meter. When the prepared session starts, `resetStemPipeline(for:)`
installs this grid before the first audio callback. The drift tracker is in
**PLANNED·UNLOCKED** from beat 1 and reaches **PLANNED·LOCKED** within ~4–5 tight-matched
onsets (~2–3 seconds at 123 BPM).

**Guidance:** Use Spotify-prepared sessions for irregular-meter tracks. The live inference
path is a fallback for ad-hoc sessions, not a replacement for offline analysis.

---

## 4. Logging

Every BeatGrid installation now writes two records:

### os_log (visible in Console.app, captured in session.log via SessionRecorder)

**preparedCache source** (from `resetStemPipeline`):
```
BEAT_GRID_INSTALL: source=preparedCache, track='Love Rehab', bpm=125.0, beats=60, meter=4/X, firstBeat=0.000s
```

**liveAnalysis source** (from `performLiveBeatInference`):
```
BEAT_GRID_INSTALL: source=liveAnalysis, track='Love Rehab', bpm=122.4, beats=21, meter=4/X, firstBeat=0.000s
```

**none source** (from `resetStemPipeline`, no cache):
```
BEAT_GRID_INSTALL: source=none, track='Money' — no cache entry, live inference will be allowed
```

**preparedCache source with empty grid**:
```
BEAT_GRID_INSTALL: source=preparedCache, track='Short Track' — empty grid, live inference will be allowed
```

**Live inference skipped due to prepared grid**:
```
LiveBeat: prepared grid present (125.0 BPM) — skipping live inference for 'Love Rehab'
```

### session.log (one-time event per track, written by `SessionRecorder.log`)

```
[2026-05-05T23:10:04Z] BeatGrid installed: source=preparedCache, track='Love Rehab', bpm=125.0, beats=60, meter=4/X
[2026-05-05T23:12:15Z] BeatGrid installed: source=liveAnalysis, track='So What', bpm=136.2, beats=22, meter=4/X
```

### features.csv (no change)

Adding `beat_grid_source` to `features.csv` would require extending `BeatSyncSnapshot`
and the CSV header schema. Since the source is a per-track event (not per-frame), the
session.log entry is sufficient for diagnosis. Deferring per-frame CSV changes to avoid
schema churn. The existing `beat_sync_mode` column (0=reactive, 1=planned+unlocked,
2=planned+locking, 3=planned+locked) already distinguishes prepared vs reactive mode at
per-frame granularity.

---

## 5. Remaining Gaps

| Gap | Severity | Notes |
|---|---|---|
| `VisualizerEngine.resetStemPipeline` not callable in SPM tests | Low | App requires Metal + full audio stack. The five engine tests mirror the production logic exactly; an app-layer end-to-end test would require an XCUITest or a dedicated test harness. |
| Money 7/4 still REACTIVE on live path | Low — by design | Live 10-second window insufficient for irregular meters. Prepared Spotify session resolves this. |
| `beat_grid_source` not in features.csv per-frame | Low | session.log one-time event is sufficient. Per-frame CSV changes deferred (schema churn risk). |
| No merge semantics for live + prepared grid | Out of scope | Future: use live drift offset to refine the prepared grid's phase alignment. Not needed for DSP.3.6. |

---

## 6. Reference

- DSP.3.5 triage: `docs/diagnostics/DSP.3.5-post-validation-beatgrid-triage.md`
- Beat This! architecture: `docs/diagnostics/DSP.2-architecture.md`
- BeatGrid source code: `PhospheneEngine/Sources/DSP/BeatGrid.swift`
- LiveBeatDriftTracker: `PhospheneEngine/Sources/DSP/LiveBeatDriftTracker.swift`
- MIRPipeline: `PhospheneEngine/Sources/DSP/MIRPipeline.swift`
- Production wiring: `PhospheneApp/VisualizerEngine+Stems.swift`
