# DSP.3 — Beat Sync + Diagnostic Environment Architecture Audit

**Date:** 2026-05-05  
**Status:** Planning / Audit only — no code changes in this increment  
**Scope:** Beat This! BeatGrid lifecycle, live drift tracking, reactive-mode failure, Spectral Cartograph diagnostic surface, product FeatureVector contract for complex meters, test fixture coverage

---

## 1. Executive Summary

Beat This! is wired correctly in production. `DefaultBeatGridAnalyzer` is injected into `SessionPreparer` at engine init (`VisualizerEngine+InitHelpers.swift:82–95`). Prepared Spotify sessions do produce BeatGrids per track. The `LiveBeatDriftTracker` is loaded per track-change from `StemCache` and wired into `MIRPipeline`.

**The observed "Phosphene shifts into Reactive mode" when switching to Spectral Cartograph is not a session mode change.** It is the `lockState=0` path in `SpectralCartographText`: when `LiveBeatDriftTracker` has not yet matched enough onsets to leave UNLOCKED state, the orb overlay reads "REACTIVE" (lockState=0 is labeled as reactive in `SpectralCartographText.draw(in:size:bpm:lockState:)`, line 48). The session plan (`livePlan`) is still present; the orchestrator is still in planned mode; only the beat-phase display is in reactive/unlocked state.

There are, however, **two structural problems** that make Spectral Cartograph unusable as a sustained diagnostic surface:

1. **No diagnostic hold mechanism.** The `DefaultLiveAdapter` mood-override fires approximately every 60 seconds if the current preset (SpectralCartograph, score=0.0) diverges from what the plan scores higher. The user cannot hold SpectralCartograph without the engine fighting them.

2. **BeatGrid not installed before first track change.** In the `.ready` state (preparation complete, music not yet started), `resetStemPipeline(for:)` has not fired. `setBeatGrid()` has not been called. The drift tracker is empty. Spectral Cartograph correctly shows "REACTIVE" — but from the user's perspective this looks like Beat This! is broken, when the BeatGrid simply hasn't been loaded yet.

**Stop/go: CONDITIONAL GO.** Two focused changes required before Beat This! is production-testable via Spectral Cartograph. See §11 for details.

---

## 2. Current BeatGrid Lifecycle

```
[SessionPreparer.prepare()]
  ↓ for each track:
  ↓ download 30s preview → decode PCM
  ↓ StemSeparator.separate() → [[Float]] waveforms
  ↓ MIRPipeline.process() → TrackProfile
  ↓ DefaultBeatGridAnalyzer.analyze() → BeatGrid        ← Beat This! offline
  ↓ StemCache.store(CachedTrackData{stemWaveforms, stemFeatures, trackProfile, beatGrid})

[VisualizerEngine+Capture.swift:133 — on track metadata change]
  ↓ resetStemPipeline(for: identity)                      ← track change trigger
  ↓   stemCache.loadForPlayback(track) → CachedTrackData?
  ↓   if hit:  mirPipeline.setBeatGrid(cached.beatGrid)  ← installs BeatGrid
  ↓   if miss: mirPipeline.setBeatGrid(nil)              ← forces reactive fallback

[MIRPipeline.setBeatGrid(_:)]
  ↓ liveDriftTracker.setGrid(grid)
  ↓ liveDriftTracker.hasGrid = (grid != nil && !grid.beats.isEmpty)

[Per-frame: MIRPipeline.buildFeatureVector()]
  ↓ if liveDriftTracker.hasGrid:
  ↓   liveDriftTracker.update(playbackTime, onsets) → Result
  ↓   fv.beatPhase01  = result.beatPhase01
  ↓   fv.beatsUntilNext = result.beatsUntilNext
  ↓   fv.barPhase01   = result.barPhase01
  ↓   fv.beatsPerBar  = Float(result.beatsPerBar)
  ↓ else (reactive):
  ↓   beatPredictor.update() → result
  ↓   fv.beatPhase01  = result.beatPhase01
  ↓   fv.beatsUntilNext = result.beatsUntilNext
  ↓   fv.barPhase01   = 0   // no downbeat info
  ↓   fv.beatsPerBar  = 4   // assumes 4/4

[RenderPipeline.draw(in:)]
  ↓ SpectralHistoryBuffer.append(beatPhase01=..., barPhase01=...)    ← ring buffer update
  ↓ SpectralHistoryBuffer.updateBeatGridData(
  ↓   relativeBeatTimes: liveDriftTracker.relativeBeatTimes,
  ↓   bpm: liveDriftTracker.currentBPM,
  ↓   lockState: liveDriftTracker.lockStateInt             ← 0=reactive, 1=locking, 2=locked
  ↓ )

[SpectralCartograph.metal fragment shader]
  ↓ reads SpectralHistoryBuffer.ring[960..1439]  (beatPhase01 history)
  ↓ reads SpectralHistoryBuffer[2402..2417]      (beat_times[16])
  ↓ reads SpectralHistoryBuffer[2418]            (bpm)
  ↓ reads SpectralHistoryBuffer[2419]            (lock_state → SpectralCartographText)
  ↓ draws: BR panel scrolling graphs, center orb, BPM label, lock-state text
```

### Known fragility points

| Point | Risk | Severity |
|---|---|---|
| `resetStemPipeline(for:)` only on track-change | BeatGrid not loaded before first track plays | **High** — root of observed "REACTIVE" display |
| `stemCache` may be nil if wired late | `loadForPlayback()` returns nil → `setBeatGrid(nil)` | Medium — timing-dependent |
| `liveBeatAnalysisDone` reset on track-change | If track-change fires before 10 s buffer, live analysis deferred correctly | Low — acceptable delay |
| No explicit `BeatGrid.empty` guard in `setBeatGrid(nil)` path | Both `setBeatGrid(nil)` and `setBeatGrid(.empty)` fall through to reactive | Low — same behavior |
| `elapsedSeconds` used as playback clock in drift tracker | Resets on `mir.reset()` at track-change — correct | Low — already handled |
| Drift tracker needs 4 tight-match onsets before LOCKED | 1–5 second LOCKING window at track start | Medium — displays as REACTIVE until locked |

---

## 3. Reactive-Mode Failure Hypothesis

**Primary hypothesis (confirmed by code inspection):**

The displayed "REACTIVE" is `SpectralCartographText.drawLockState(0, ...)`. This fires when `LiveBeatDriftTracker.lockState == .unlocked` (`lockState=0`). The engine is NOT in ad-hoc/reactive orchestration mode — `livePlan` is non-nil and `reactiveSessionStart` is nil.

**Why the drift tracker is UNLOCKED when the user switches to Spectral Cartograph:**

1. The user is in `.ready` state (preparation complete, Spotify not yet playing). `resetStemPipeline(for:)` has not been called. `setBeatGrid()` has not been called. `liveDriftTracker.hasGrid == false`. SpectralCartograph shows "REACTIVE."

2. The user switches to Spectral Cartograph immediately after the first track starts. The drift tracker is in UNLOCKED state — correctly, because it needs time to match 4 onsets against the grid (typically 1–5 seconds at 125 BPM).

3. In either case, the label "REACTIVE" is accurate as a drift-tracker state, but misleads the user into thinking the entire beat-sync pipeline has fallen back to the IIR predictor.

**Secondary problem (structural):**

After the user manually switches to Spectral Cartograph, `DefaultLiveAdapter.evaluate()` runs each frame via `applyLiveUpdate()`. The mood-override condition fires when `|Δv| > 0.4 || |Δa| > 0.4`, elapsed < 40%, and an alternative preset scores > 0.15 higher than the current preset. Spectral Cartograph scores 0.0 (diagnostic-excluded). Every other preset scores higher. Within 60 seconds of the mood-override cooldown, the engine will switch away from Spectral Cartograph to a planned or reactive-selected preset. The user cannot hold Spectral Cartograph as a persistent diagnostic surface.

**What is NOT happening:**

- `applyPresetByID()` does NOT clear `livePlan`. Confirmed: the planned-session state is preserved across manual preset overrides.
- `DefaultBeatGridAnalyzer` IS injected in production (`VisualizerEngine+InitHelpers.swift:82–95`). The Beat This! offline path is active.
- `setBeatGrid()` IS wired in `resetStemPipeline(for:)`. The grid loads on track-change.

---

## 4. Mode/State Findings

### 4.1 What triggers Reactive mode

True reactive mode (session-orchestration level) has exactly two entry points:

| Trigger | Code location | Effect |
|---|---|---|
| `SessionManager.startAdHocSession()` | `IdleView.swift:42` — "Start listening now" CTA | `state = .playing`, `progressiveReadinessLevel = .reactiveFallback`, `livePlan` stays nil |
| `applyLiveUpdate()` detects `livePlan == nil` | `VisualizerEngine+Orchestrator.swift:218` | `reactiveSessionStart = Date()`, calls `applyReactiveUpdate()` |

Neither fires during a normal Spotify-prepared session with a manual Spectral Cartograph switch.

### 4.2 Does manual preset override switch into reactive mode?

**No.** `applyPresetByID()` → `applyPreset()`. Does not touch `livePlan`, `reactiveSessionStart`, or `SessionManager.state`. The planned session continues uninterrupted in the orchestrator. Only the rendered preset changes.

### 4.3 Does selecting Spectral Cartograph clear BeatGrid or MIRPipeline state?

**No.** Preset change does not call `resetStemPipeline()`, `setBeatGrid()`, or `mirPipeline.reset()`. The BeatGrid installed on the last track-change persists through preset switches.

### 4.4 Does `resetStemPipeline(for:)` run on preset change?

**No.** It runs on track-change only, triggered by `StreamingMetadata` track-identity changes in `VisualizerEngine+Capture.swift:133`.

### 4.5 Where is `MIRPipeline.setBeatGrid(_:)` called?

| Call site | File | Condition |
|---|---|---|
| Cache hit | `VisualizerEngine+Stems.swift:298` | `stemCache.loadForPlayback(track)` returns non-nil with non-empty `beatGrid` |
| Cache miss | `VisualizerEngine+Stems.swift:302` | `loadForPlayback()` returns nil |
| Live Beat This! completes | `VisualizerEngine+Stems.swift:258` | 10+ seconds buffered tap audio, `!liveDriftTracker.hasGrid` |

`setBeatGrid(nil)` is the only path that clears the grid. It fires on cache miss. It does NOT fire on preset change, session start, or ad-hoc session start.

### 4.6 Is the playback clock still track-relative after manual preset override?

**Yes.** `MIRPipeline.elapsedSeconds` accumulates from `mir.reset()` which fires on `resetStemPipeline(for:)` (track-change), not on preset change. The clock does not reset on Spectral Cartograph switch.

### 4.7 Is Spectral Cartograph reading cached grid data or FeatureVector fallback?

Both, depending on lock state:

- **BPM label and lock-state text**: Read from `SpectralHistoryBuffer[2418..2419]` via `readOverlayState()`. Written each frame by `updateBeatGridData()` from `liveDriftTracker.currentBPM` and `lockStateInt`. If tracker has no grid, BPM=0 → label is "0" → lock=0 → "REACTIVE."

- **Beat-grid tick overlay** (BR panel): Reads `SpectralHistoryBuffer[2402..2417]` (relative beat times). Written by `updateBeatGridData(relativeBeatTimes:)`. If no grid, all slots are `Float.infinity` and ticks are not drawn.

- **beatPhase01 history** (BR panel row 0): Reads `SpectralHistoryBuffer.ring[960..1439]`. Written from `fv.beatPhase01` each frame. If reactive fallback is active, this plots `BeatPredictor` output, not drift-tracker output. The difference is visible: reactive output is a noisy sawtooth with variable period; drift-tracker output is a smooth locked sawtooth with period matching the grid's beat period.

---

## 5. Diagnostic Environment Capability Matrix

| Scenario | Status | Notes |
|---|---|---|
| Local-file prepared session with BeatGrid in Spectral Cartograph | **Partial** | Works once music starts and first track-change fires. Before first track-change: REACTIVE display. |
| Spotify-prepared session with manual Spectral Cartograph override, BeatGrid retained | **Partial** | BeatGrid retained on override. But: (a) "REACTIVE" until drift tracker locks (1–5 s), (b) LiveAdapter fights override every 60 s. |
| Fixture-based pipeline replay (cached BeatGrid + synthetic onset stream) | **Missing** | No harness exists. Unit tests use fake grids; no harness runs real prepared-session → BeatGrid → drift tracker → FeatureVector end-to-end. |
| Visual harness capture with beat-grid ticks visible | **Partial** | `PresetVisualReviewTests` exists and captures Spectral Cartograph. Tick overlay requires `updateBeatGridData()` to have been called, which requires `LiveBeatDriftTracker` to be wired. The visual harness binds SpectralHistoryBuffer but does not currently populate beat-grid section with real data — ticks will be absent (all `Float.infinity`). |
| CSV export of beat phase, bar phase, downbeats, drift, confidence, mode | **Missing** | `SessionRecorder` exports `features.csv` with `beatPhase01` and `barPhase01`. Does NOT export: drift (ms), lock state, session mode (planned/reactive), beat-in-bar, downbeat flag, BeatGrid source. |
| Side-by-side ground-truth annotations vs. rendered state | **Missing** | `BeatGridResolverGoldenTests` validates offline BeatGrid accuracy. No runtime comparison harness exists. |
| Irregular-meter BeatGrid accuracy (Pyramid Song, Money) | **Supported** | 24 golden fixture tests in `BeatGridResolverGoldenTests`; meter assertions for 7/4, 16/8. |
| Live drift tracker validation with real audio | **Missing** | `LiveBeatDriftTrackerTests` use synthetic grids and fake onset streams. No test runs the drift tracker against a real Spotify prepared session. |
| Stem-processing validation (per-stem energy, pitch, beat during playback) | **Partial** | `SessionRecorder` exports `stems.csv`. Values are frame-by-frame per-stem energy. No per-stem onset rate, attack ratio, or live-analysis window information exported. |
| Preset iteration against real prepared session data | **Partial** | Local-file playback via `AudioInputRouter(.localFile)` works. Session data (BeatGrid, stems) loaded from cache. But no fixture-playback mode that skips live audio and replays cached FeatureVectors. |

---

## 6. Product Contract Gaps

### 6.1 Current FeatureVector beat fields

| Field | Floats | Available | Source |
|---|---|---|---|
| `beatPhase01` | 35 | ✅ | Drift tracker / BeatPredictor |
| `beatsUntilNext` | 36 | ✅ | Drift tracker / BeatPredictor |
| `barPhase01` | 37 | ✅ (S9) | Drift tracker / 0 in reactive |
| `beatsPerBar` | 38 | ✅ (S9) | Grid meter / 4 in reactive |

### 6.2 What complex meters require

For Pyramid Song (16/8 ≈ 3+3+2+2+3+2 / 8), Money (7/4), and comparable tracks:

| Requirement | Current status | Gap |
|---|---|---|
| Correct beat phase within the bar | `beatPhase01` resets each beat | ✅ — sufficient for accent timing |
| Bar-level phrase phase | `barPhase01` added in S9 | ✅ — sufficient for slow modulation |
| Which beat of the bar (integer 0..N-1) | Derivable: `floor(barPhase01 × beatsPerBar)` | ✅ — computable in shader, no gap |
| Downbeat flag (hard accent at bar start) | No dedicated field; approximated by `barPhase01 < ε` | **Partial** — ε threshold is arbitrary; a boolean or decayed pulse would be cleaner |
| Meter change detection | No field | **Missing** — in practice, Beat This! produces a single meter per grid; meter changes mid-track are not tracked |
| Drift amount in ms (confidence proxy) | Not in FeatureVector | **Missing** — useful for reducing beat-accent intensity while locking, but not required for correct visuals |

**Assessment:** The current contract is sufficient for the product requirement on complex meters. `barPhase01` and `beatsPerBar` together cover phrase-level sync. The missing `downbeatPulse` field is a nice-to-have for visual drama, not a blocker. Meter changes mid-track are rare in the test corpus and can be deferred.

### 6.3 Minimal contract extension (if needed)

If downbeat accents are required before a dedicated field is added, the shader can compute:
```metal
float beatInBar = floor(fv.barPhase01 * fv.beatsPerBar);
float downbeatPhase = fv.barPhase01 * fv.beatsPerBar - beatInBar; // 0..1 within beat
bool isDownbeat = (beatInBar < 0.5); // first beat of bar
```

No new FeatureVector fields are needed for this. Reserve floats 39–48 remain available.

---

## 7. Spectral Cartograph Gaps

### 7.1 What it currently shows

| Signal | Panel | Status |
|---|---|---|
| FFT spectrum (log-freq, centroid color) | TL | ✅ |
| 3-band deviation meters (bass/mid/treble) | TR | ✅ |
| Valence/arousal phase plot with trail | BL | ✅ |
| beatPhase01 scrolling history | BR row 0 | ✅ |
| bassDev scrolling history | BR row 1 | ✅ |
| barPhase01 scrolling history | BR row 2 | ✅ (added S9) |
| Beat-grid tick marks (upcoming beats) | BR row 0 overlay | ✅ |
| BPM label | Center orb above | ✅ |
| Lock state ("REACTIVE"/"LOCKING"/"LOCKED") | Center orb below | ✅ |
| Beat orb (phase-driven, amber fill) | Center | ✅ |

### 7.2 Missing diagnostic overlays

| Signal | Importance | Notes |
|---|---|---|
| **Session mode** (PLANNED vs. AD-HOC) | **Critical** | Currently no way to distinguish "reactive display" from "reactive session." User cannot tell if the engine has a plan. |
| **Downbeat tick marks** (vertical lines at bar boundaries) | High | Rhythm-diagnostic: verifies meter interpretation on irregular tracks. |
| **Drift amount in ms** | High | Shows whether LiveBeatDriftTracker is correcting forward or back, and by how much. Useful for quantifying grid alignment error. |
| **Beat-in-bar label** (e.g., "3 / 7") | High | Integer beat index within bar. Essential for complex-meter verification (Pyramid Song, Money). |
| **BeatGrid source** (CACHE vs. LIVE) | Medium | Did the grid come from offline preparation or from the 10-second live tap buffer? Important for diagnosing preparation failures. |
| **Confidence / match count** | Medium | How many tight-match onsets were needed to reach LOCKED (0..4+). Shows trajectory toward lock. |
| **Current beat index** (absolute) | Low | Not critical; beat-in-bar covers the common case. |
| **Time-signature label** (e.g., "7/4") | Medium | Shows `beatsPerBar` in human-readable form alongside BPM. Verifies meter detection without code. |

### 7.3 Most impactful single addition

**Session mode label** is the highest-priority missing overlay. Without it, the user cannot distinguish:
- "REACTIVE" = drift tracker hasn't locked yet (engine in planned mode, grid installed)
- "REACTIVE" = no BeatGrid exists, BeatPredictor is driving (engine in reactive fallback)
- "REACTIVE" = ad-hoc session started with no preparation

The SpectralHistoryBuffer reserved section has room for a session-mode byte. The overlay text ("PLANNED / LOCKING" vs. "REACTIVE / FALLBACK") would immediately resolve the ambiguity Matt observed.

---

## 8. Test Fixture Gaps

### 8.1 Current coverage

| Track | Genre | Meter | Coverage | Test level |
|---|---|---|---|---|
| Love Rehab | Electronic ~125 BPM | 4/4 | Full golden + layer-match + end-to-end | Unit + Integration |
| So What | Jazz ~136 BPM | Free/4/4 | BeatGridResolver golden | Unit (golden) |
| There There | Syncopated rock ~86 BPM | 4/4 (kick not on beat) | BeatGridResolver golden | Unit (golden) |
| Pyramid Song | Radiohead 16/8 | Complex | BeatGridResolver golden — meter=3 gate | Unit (golden) |
| Money | Pink Floyd 7/4 | 7/4 | BeatGridResolver golden — beatsPerBar=7 gate | Unit (golden) |
| If I Were With Her Now | (unknown) | (unknown) | BeatGridResolver golden | Unit (golden) |

### 8.2 Fixture gaps

| Coverage gap | Impact | Priority |
|---|---|---|
| **Live drift tracker with real audio onsets** | Cannot validate that LOCKED is reached within 5 s on real tracks | **Critical** |
| **Drift accumulation over >4 minutes** | Cannot validate that drift doesn't runaway on long tracks | High |
| **7/8 track** (e.g., Schism, Lopsided) | No odd-meter track with 7-subdivision to verify against 7/4 | High |
| **5/4 track** (e.g., Take Five, Mars) | No quintuple track in fixture set | Medium |
| **Swing track** (jazz, triplet feel) | Swing eighth notes create non-uniform IOIs; meter detection may vary | Medium |
| **Sparse-onset track** | Vocal ballad with no kick drum — only `autocorrelation` fallback path | Medium |
| **Accelerando / decelerando** | tempo-change handling not tested | Low |
| **Multi-session replay** | Same prepared session replayed twice → BeatGrid reused, no re-analysis | Medium |
| **App-layer wiring test** (preparer → cache → stemCache → setBeatGrid path) | End-to-end wiring is only validated by `BeatGridIntegrationTests` (engine only) | High |

### 8.3 Test classification

| Test suite | Type | Count | Notes |
|---|---|---|---|
| `BeatThisPreprocessorTests` | Unit | 5 | Golden match; no real-time path |
| `BeatThisModelTests` | Unit + Integration | 9 | Model output only; no downstream wiring |
| `BeatThisLayerMatchTests` | Integration | per-stage | Regression lock on 4 S8 bugs |
| `BeatThisBugRegressionTests` | Regression | 4 | Individual bug gates |
| `BeatGridResolverTests` | Unit | 8 | Synthetic activations |
| `BeatGridResolverGoldenTests` | Regression | 24 (6×4) | Gold-standard; Pyramid Song / Money load-bearing |
| `LiveBeatDriftTrackerTests` | Unit | 15 | Synthetic grids + synthetic onset streams |
| `BeatGridUnitTests` | Unit | 4 | BeatGrid geometry |
| `MIRPipelineDriftIntegrationTests` | Integration | 3 | MIRPipeline with fake grid + fake onsets |
| `BeatGridIntegrationTests` | Integration | 4 | SessionPreparer → StemCache wiring |
| App-layer drift wiring | **Missing** | 0 | No test verifies stemCache → setBeatGrid → FeatureVector |
| Live drift + real audio | **Missing** | 0 | No end-to-end live-lock test |
| Spectral Cartograph visual | Partial | 1 | `PresetVisualReviewTests`; no beat-grid tick visible |

---

## 9. Required Architecture Changes

Ordered by severity. None of these are code-only improvements — each requires a deliberate design decision.

### 9.1 [Critical] Diagnostic preset hold mechanism

**Problem:** `DefaultLiveAdapter` mood-override fires every ~60 seconds when the current preset is diagnostic (score=0.0), switching back to a planned preset. User cannot hold Spectral Cartograph for more than 60 seconds.

**Required change:** Add a `diagnosticPresetLocked: Bool` flag to `VisualizerEngine`. When true, `applyLiveUpdate()` skips the mood-override emission path entirely (similar to how `CaptureModeSwitchCoordinator` suppresses overrides during capture-mode transitions). Toggle via keyboard shortcut (e.g., `L` in debug mode, or automatically when the user manually selects a diagnostic preset).

**Scope:** `VisualizerEngine+Orchestrator.swift` (suppress override), `DefaultPlaybackActionRouter` (toggle flag), `PlaybackShortcutRegistry` (register shortcut). 1–2 hours.

### 9.2 [Critical] Session-mode signal in SpectralHistoryBuffer

**Problem:** SpectralCartograph cannot distinguish "drift tracker unlocked (BeatGrid present, waiting for onsets)" from "no BeatGrid at all (pure reactive fallback)." The displayed "REACTIVE" label is ambiguous.

**Required change:** Add a session-mode byte to `SpectralHistoryBuffer` reserved section. Encode: 0=reactive (no grid), 1=planned+unlocked (grid installed, waiting for match), 2=planned+locking, 3=planned+locked. Write from `updateBeatGridData()`. Read in `SpectralCartographText` and display as "PLANNED (locking)" vs. "REACTIVE." Reserve `SpectralHistoryBuffer[2420]` (currently reserved/zeroed, per GPU contract).

**Scope:** `SpectralHistoryBuffer.swift`, `SpectralCartographText.swift`, `VisualizerEngine+Audio.swift` (pass session mode into `updateBeatGridData`). 1–2 hours.

### 9.3 [High] Pre-fire `resetStemPipeline` on session start

**Problem:** In the `.ready` state and during the first few seconds of playback, `resetStemPipeline(for:)` has not fired. `setBeatGrid()` has not been called. The drift tracker is empty. Spectral Cartograph shows "REACTIVE" even though preparation produced a valid BeatGrid.

**Required change:** In `SessionManager` (or `VisualizerEngine`) on `.ready` → `.playing` transition, call `resetStemPipeline(for: firstPlannedTrack.identity)` if `livePlan?.tracks.first` is available. This pre-loads the BeatGrid for the first track before audio arrives.

**Scope:** `VisualizerEngine+Stems.swift`, `VisualizerEngine+Orchestrator.swift` (hook into `buildPlan()` or the `.ready` state callback). 1 hour.

### 9.4 [High] Spectral Cartograph overlay additions

Add four overlays to close the diagnostic gap (see §7.2):
1. **Session mode label** — "PLANNED" vs. "AD-HOC" in small text near lock-state. Reads `SpectralHistoryBuffer[2420]` once 9.2 is implemented.
2. **Downbeat tick marks** — Vertical lines at barPhase01 zero-crossings in BR panel row 2.
3. **Drift display** — "±N ms" below BPM. Requires a new SpectralHistoryBuffer slot for current drift value.
4. **Time-signature label** — "7/4" / "4/4" etc. below BPM. Reads `beatsPerBar` from FeatureVector.

**Scope:** `SpectralCartograph.metal`, `SpectralCartographText.swift`. 2–3 hours for all four.

### 9.5 [Medium] `SessionRecorder.features.csv` beat-sync columns

Add to per-frame CSV export: `lock_state`, `session_mode`, `drift_ms`, `beat_in_bar`, `downbeat`, `beats_per_bar`, `bar_phase01`. This enables offline ground-truth comparison without requiring the visual review harness.

**Scope:** `SessionRecorder.swift`. 1 hour.

### 9.6 [Medium] App-layer wiring test for `setBeatGrid` end-to-end

Add an integration test that: creates a real `VisualizerEngine` instance with a mock audio source, prepares a short synthetic track, and verifies that `MIRPipeline.liveDriftTracker.hasGrid == true` after the first track-change fires. This is the only end-to-end test that validates the chain: `SessionPreparer → StemCache → resetStemPipeline → setBeatGrid → MIRPipeline`.

**Scope:** `Tests/Integration/` or `Tests/App/`. 2–3 hours.

---

## 10. Recommended Implementation Increments

### DSP.3.1 — Diagnostic Hold + Session Mode Signal (2–3 hours)

Implement §9.1 and §9.2 together.

- Add `diagnosticPresetLocked: Bool` to `VisualizerEngine`; wire into `applyLiveUpdate()` suppression path.
- Add `SpectralHistoryBuffer[2420]` session-mode slot; write from `updateBeatGridData()`; read in `SpectralCartographText`.
- Update `PlaybackShortcutRegistry` with `L` shortcut (dev mode only) to toggle hold.
- Update `SpectralCartographText` to show "PLANNED (LOCKING)" / "PLANNED (LOCKED)" / "REACTIVE" based on session-mode byte.

**Done when:** User can switch to Spectral Cartograph, press `L` to hold, and observe that the engine does not switch away. The displayed mode text correctly distinguishes "REACTIVE" (no grid) from "PLANNED+UNLOCKED" (grid present, awaiting lock).

### DSP.3.2 — Pre-fire BeatGrid on Session Start (1 hour)

Implement §9.3.

- In `buildPlan()` or the `sessionManager.state == .ready` observer in `VisualizerEngine`, if `livePlannedSession?.tracks.first` is non-nil, call `resetStemPipeline(for: firstTrack.track)`.
- Gate on `stemCache != nil` to avoid a nil-deref before the cache is wired.

**Done when:** Switching to Spectral Cartograph in `.ready` state shows "PLANNED (UNLOCKED)" instead of "REACTIVE."

### DSP.3.3 — Spectral Cartograph Diagnostic Overlays (2–3 hours)

Implement §9.4 once DSP.3.1 and DSP.3.2 are complete.

- Downbeat tick marks in BR panel.
- Drift ±N ms below BPM (requires one SpectralHistoryBuffer reserved slot for current drift).
- Time-signature label.
- Session mode label (uses slot from DSP.3.1).

**Done when:** Full diagnostic state visible in one screen: lock state, session mode, BPM, meter, drift, beat-in-bar, downbeat ticks.

### DSP.3.4 — CSV Export Beat-Sync Columns (1 hour)

Implement §9.5. Low risk, high payoff for offline analysis.

**Done when:** `features.csv` has `lock_state`, `session_mode`, `drift_ms`, `beat_in_bar`, `downbeat` columns.

### DSP.3.5 — App-Layer End-to-End Wiring Test (2–3 hours)

Implement §9.6. Closes the test gap between `BeatGridIntegrationTests` (engine only) and actual production behavior.

**Done when:** A single test confirms: `SessionPreparer.prepare(tracks:)` with a `DefaultBeatGridAnalyzer` stores a non-empty `BeatGrid` in `StemCache`, `resetStemPipeline(for:)` loads it into `MIRPipeline`, and `mirPipeline.liveDriftTracker.hasGrid == true`.

### DSP.3.6 — Live Drift Validation with Real Audio (3–4 hours)

Add a soak-style test or scripted run that:
1. Loads `love_rehab` prepared data from fixture.
2. Replays raw audio through `AudioInputRouter(.localFile)`.
3. Captures `lock_state` transitions and drift values over a 30-second window.
4. Asserts: LOCKED reached within 5 seconds; drift magnitude < 50 ms after LOCKED; `beatPhase01` zero-crossings align with ground-truth beat times within ±30 ms.

**Done when:** Test passes for love_rehab and so_what. Manual inspection for Pyramid Song / Money.

---

## 11. Stop/Go Recommendation

**CONDITIONAL GO.**

### What's working correctly

- Beat This! offline analysis is wired in production. `DefaultBeatGridAnalyzer` is injected into `SessionPreparer` (`VisualizerEngine+InitHelpers.swift:82–95`). Prepared Spotify sessions produce BeatGrids. Cache storage and retrieval are correct. `setBeatGrid()` is called on track-change. `MIRPipeline` selects the drift-tracker path when `hasGrid == true`. `barPhase01` and `beatsPerBar` are in the FeatureVector. Golden fixture tests cover Love Rehab, So What, There There, Pyramid Song, Money.

- `applyPresetByID()` does not disturb the session plan or the BeatGrid. Planned-mode orchestration survives manual preset overrides.

### What must be fixed before Beat This! is testable in the app

**Fix 1 — Diagnostic hold (DSP.3.1).** Without it, the engine evicts Spectral Cartograph within 60 seconds. Matt cannot observe the drift tracker locking across a full track.

**Fix 2 — Session-mode signal (DSP.3.1 + DSP.3.2).** Without it, "REACTIVE" on screen is ambiguous — could mean the planned+unlocked state (grid present, waiting for onsets) or the true reactive state (no grid). Matt cannot tell if Beat This! is engaged. This is the root of the reported issue.

### What can be deferred

- Drift ms display, downbeat ticks, time-signature label, CSV columns — valuable but not required to begin validation.
- App-layer wiring test — the engine integration tests cover the chain; the wiring is confirmed by inspection.
- Live drift validation test — valuable, but the QA reel approach (watch `beatPhase01` in Spectral Cartograph across irregular tracks) is acceptable for initial validation.
- 7/8, 5/4, swing, sparse-onset fixtures — good-to-have, not blockers.

### Gating assertion for GO

> After implementing DSP.3.1 and DSP.3.2: Matt connects a Spotify playlist, preparation completes, presses `L` to hold Spectral Cartograph, starts music, and observes the center orb transition from "PLANNED (UNLOCKED)" → "PLANNED (LOCKING)" → "PLANNED (LOCKED)" within 5 seconds. The BPM label matches the track's true tempo. The beat-grid tick marks in the BR panel align with perceived beat events. The orb stays on Spectral Cartograph for the full track without the engine switching away.

Until that observation is made and confirmed, Beat This! is not production-validated in the app regardless of how many unit tests pass.
