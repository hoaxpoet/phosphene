# BPM-Anchored Phase Acquisition — Design + Adversarial Review

**Date:** 2026-05-24
**Phase:** BSAudit.3 (design)
**Status:** Pre-implementation design. No code changes have landed.
**Prior art:** [`docs/COLD_START_SYNC_DESIGN_2026-05-20.md`](COLD_START_SYNC_DESIGN_2026-05-20.md) (Phase CS); [`docs/CAPABILITY_REGISTRY/BEAT_SYNC.md`](CAPABILITY_REGISTRY/BEAT_SYNC.md) (BSAudit + BSAudit.2 empirical falsification of Beat This!-on-tap reproducibility). Read those first.
**CLAUDE.md anchors:** Failed Approach #68 (sub-bass onsets as beat-phase reference); Authoring Discipline §"Articulate the musical role"; §"Grounding priority"; §"Diagnostic infrastructure precedes fidelity claims"; §"Verify Matt's current intent before trusting any 'what stays unchanged' claim."

## 1. Problem statement

Matt's reframed product bar (2026-05-24):

> The analysis phase can be the length of a pop song (3:00-3:30) and we build a new UX around building anticipation and setting the vibe for the visual playlist experience. During playback, some kind of beat / rhythm should be present from the start; this can be purely reactive until Phosphene knows enough about the character of the song to accurately follow its tempo / rhythm, to serve as true accompanist. **The goal is to have some kind of CREDIBLE pairing of the visual and music.** Viewers will tolerate some kind of ramp-up period, but only if there is a credible and COMPETENT form of synchronicity within the first 3 s of playback. **We need to get the perception of sync right from the jump, not necessarily the ACTUAL sync.**

This is a strict relaxation of the Phase CS bar:

- The original bar required ±50 ms phase from frame 1. BSAudit + BSAudit.2 showed this is structurally unachievable in the streaming-only world (preview is 30 s mid-song; Beat This!-on-tap is position-sensitive within one capture and 10/10 cross-capture-unstable).
- The reframed bar requires *perceptual* sync within ~3 s, achieved via a credible-looking warmup rather than instantaneous lock.
- "Credible" means: at no point in playback does the visual appear to be *trying and failing* to be on-beat. Either it's clearly on-beat (in the user's perception, ±100 ms is sufficient — see §4 below) or it's gracefully not claiming beat-lock (continuous-energy modulation, no beat-rate accents).

## 2. Why previous approaches failed

| Approach | What it tried | Why it failed | Reference |
|---|---|---|---|
| CS.1 baseline | Trust cached BeatGrid phase from frame 1 (`offsetBy(0)`) | Preview is mid-song; preview-time grid ≠ track-time grid; 7/10 tracks fail by 100-338 ms | [BUG-017](QUALITY/KNOWN_ISSUES.md), CS.1.x |
| CS.1.y.2 | Phase-lock from first live sub-bass onsets | Sub-bass detector fires on sub-bass *events*, not beats — off-beat on syncopated tracks | CLAUDE.md FA #68 |
| CS.1.y re-diagnosis | Beat This! on 3-5 s of live tap → derive phase | 3-5 s windows unstable on real-music tracks (1-3/10 viable) | [`KNOWN_ISSUES.md`](QUALITY/KNOWN_ISSUES.md) BUG-017 addendum |
| CS.1.y.2-redo | Beat This! at +15 s on tap → phase-correct cached grid | Within-slice reproducible, cross-capture unstable on 10/10 — measurement-design gap | [`RELEASE_NOTES_DEV.md`](RELEASE_NOTES_DEV.md) `[dev-2026-05-24-a]` |
| BSAudit.2 Path A | Run Beat This! at sliding 25 s positions; cross-capture compare | Beat This! is position-sensitive within one capture (7/10 tracks span 100-410 ms across positions); cross-capture-unstable 10/10 | [`BEAT_SYNC.md` Addendum](CAPABILITY_REGISTRY/BEAT_SYNC.md#addendum--bsaudit2-path-a-findings-2026-05-24) |

**The structural insight from five failed iterations:** Beat This!-on-tap is not a reliable phase reference at any window configuration. Sub-bass-onset-as-phase-reference (FA #68) is not a reliable phase reference. There is no automated phase reference available at frame 1 of a novel track. *Stop trying to find one.*

## 3. Hard constraints

These are externally imposed and non-negotiable:

- **30 s Spotify preview clip per track, mid-song excerpt.** No full-track audio available before playback.
- **No automated phase reference at frame 1.** Empirically established by the five failed iterations + BSAudit.2 falsification.
- **No user input required.** Listening-party use case features novel tracks; users will not manually calibrate.
- **Live tap audio arrives from frame 1.** Phosphene captures Core Audio tap from the moment playback starts.
- **Cached BPM from Beat This! on preview is reliable.** Empirically verified — across all 4 captures, cached BPM is byte-identical for every track ([`BEAT_SYNC.md` Component 1a](CAPABILITY_REGISTRY/BEAT_SYNC.md#component-1a)).
- **Visual perception tolerance is ±100 ms, not ±50 ms.** Standard psychoacoustic threshold for audio-visual sync; below this listeners do not reliably perceive misalignment. The audit's ±50 ms bar was inherited from CS.1; the reframed product bar relaxes it.

## 4. Bar to clear

Quantitative criteria a verification test can evaluate:

| Criterion | Threshold | Notes |
|---|---|---|
| Continuous-energy visual modulation | Active from frame 1 | Always — never a "dead" visual at track start |
| Beat-rate accent presence | First accent within ≤ 1.5 s of broadband peak detection | Phase acquired from broadband peak (see §6) |
| Perceptual phase alignment | Accent fires within ±60 ms of audible beat *when an accent fires* | Hard gate: accents only fire when broadband peak ↔ BPM prior agree within ±60 ms |
| Graceful degradation | Accents fade to 0 when confidence drops below threshold | No "obviously misaligned" frames |
| Lock acquisition | Confidence-locked within 3 s on clean tracks (≥ 90 % of catalog) | Pre-analysis metadata flags the difficult minority |
| Hard-track behavior | Continuous-energy-only, no spurious accent firing | Tracks pre-flagged as "hard" use restrained thresholds |

**The bar is perceptual, not technical.** A track where the visual is continuous-energy-only the whole way through is acceptable if continuous energy alone reads as musical (Milkdrop / G-Force baseline). A track where beat-rate accents fire on perceived strong beats with ±60 ms alignment is full success. A track where accents fire at the wrong moments is failure — that's the only outcome we engineer to prevent.

## 5. What is already in production

This list isolates exactly what changes and what stays. Per CLAUDE.md "Verify Matt's current intent before trusting any 'what stays unchanged' claim" — each item below was verified against the code at design time.

### 5.1 Cached `BeatGrid` (Beat This! on preview)

- Computed at preparation time on the 30 s preview. Cached on `CachedTrackData.beatGrid`.
- BPM is reliable. Beat *positions* are in preview-time and unrelated to track-time.
- **Decision:** continue computing as today. Only the BPM is consumed at runtime; beat positions become *advisory* (used only for octave-correction tiebreakers — see §6.4).

### 5.2 `GridOnsetCalibrator` → `gridOnsetOffsetMs`

- Runs at preparation time. Sub-bass-onset-based — CLAUDE.md Failed Approach #68 root cause still live at prep.
- Empirical magnitude on the 4 captures: 0-60 ms; mostly deterministic with sporadic re-prep non-determinism.
- **Decision: retire entirely.** The seed is small, sub-bass-event-aligned (not beat-aligned), and is bypassed by the new phase-acquisition mechanism. No code path needs the value after this design lands. Frees up a contributing source of FA #68 contamination from the system.

### 5.3 `VisualizerEngine+Stems.swift:484` — cold-start grid install

```swift
mirPipeline.setBeatGrid(
    cached.beatGrid.offsetBy(0),
    initialDriftMs: cached.gridOnsetOffsetMs
)
```

- Currently installs the cached grid with a phase seed. Per §5.1 and §5.2: phase is wrong; seed is broken-by-design.
- **Decision: replace with BPM-only install** (see §6.1). The new call passes only the BPM + the new rhythm-character metadata; the cached grid's beat positions are not consumed for phase.

### 5.4 `LiveBeatDriftTracker.update(...)`

- Current behaviour: sub-bass onset → match to cached grid within ±50 ms → EMA-update drift. Lock state machine progresses based on tight matches.
- The ±50 ms hard match window structurally prevents gross corrections (CLAUDE.md FA #68 analysis).
- The whole approach is wrong for the new model.
- **Decision: substantial rework** (§6). The lock-state machinery is preserved at the API surface (existing consumers like `SpectralCartograph` continue to display lock state); internally it's driven by the new confidence accumulator.

### 5.5 `BeatDetector` (6-band onset detector + tempo estimator)

- Computes per-band spectral flux, per-band onsets with cooldowns, grouped beat pulses.
- The grouped beat pulses (`beatBass`, `beatMid`, `beatTreble`, `beatComposite`) drive the existing visual accent contract used by presets.
- **Decision: preserve, extend.** Add a broadband flux peak detector path alongside the existing per-band detector. The existing per-band onset stream continues to drive visual accents (continuous-energy reactivity) — that's not the same role as phase reference.

### 5.6 `BeatPredictor` (reactive-mode IIR phase predictor)

- Used when no cached `BeatGrid` is installed (reactive mode). IIR-based phase tracking from `beatComposite`.
- **Decision: preserve as-is for the no-cached-grid fallback path.** Not on the critical path for the BUG-017 use case.

### 5.7 BUG-007.x lock state machine + bar-rotation (Shift+B) + visual phase offset ([/])

- BUG-007.4 (bar-phase rotation, `Shift+B`)
- BUG-007.4b/c (auto-rotate bar phase from kick-density histogram)
- BUG-007.5 (variance-adaptive tight gate, BPM-aware lock-release)
- BUG-007.6 (`audioOutputLatencyMs` — display path latency compensation)
- BUG-007.8 (`setGrid(_:initialDriftMs:)` — the seed entry point retired in §5.3)
- BUG-007.9 (hybrid runtime recalibration — already retired in [`dev-2026-05-24-a`])
- **Decision:**
  - BUG-007.4 (`Shift+B`) preserved — user override of bar phase still available.
  - BUG-007.4b/c (auto-rotate) preserved — runs on the new confidence-locked phase instead of the cached grid. Same intent, new substrate.
  - BUG-007.5 (variance-adaptive gate) — the gate's role changes; see §6.5.
  - BUG-007.6 (`audioOutputLatencyMs`) preserved — display-time latency compensation is orthogonal to phase acquisition.
  - BUG-007.8 entry point retired (§5.3).
  - BUG-007.9 already retired.

### 5.8 Existing preset accent contract

- Presets read `f.beatComposite`, `f.beatBass`, `f.beatMid`, `f.beatTreble`, `f.beatPhase01`, `f.barPhase01` etc.
- **Decision: backward-compatible.** New `accentConfidence: Float` field added to `FeatureVector` [0, 1]. `MIRPipeline` multiplies the beat-related fields by `accentConfidence` before writing to FeatureVector. Presets see "the beat field has lower amplitude when confidence is low" — no preset code changes required.

### 5.9 Stems separation + D-019 warmup

- Live stem separation (drums isolated) is available ~10 s after track start.
- **Decision: optional future enhancement (§9.1 — out of scope for BSAudit.3).** The drums stem is a cleaner beat signal than full-mix broadband flux and could refine phase after warmup. Not load-bearing for the first-3-s perceptual sync goal.

## 6. The proposed mechanism

### 6.1 Overview

At frame 1, the system has:
- Cached BPM (reliable).
- New rhythm-character metadata (computed during the rehearsal phase — §7).
- A live tap audio stream starting to flow.

The system does NOT know the audible beat phase. It does not try to extract one before playback. Instead:

1. **Frame 1:** Visual fires continuous-energy modulation immediately. `accentConfidence = 0` → no beat-rate accents.
2. **t = 0 to first broadband peak (typically 100-700 ms):** Wait. `accentConfidence` stays at 0.
3. **First broadband peak detected (T₀):** Anchor the BPM prior's phase to T₀. Predict the next beat at T₀ + period. `accentConfidence` starts ramping.
4. **Each predicted beat:** Open an expectation window of ±60 ms around the prediction. If a broadband peak fires in-window, confirm (small EMA correction to phase, confidence increment). If no peak in window, decrement confidence.
5. **Confidence-locked (typically 1-3 s):** `accentConfidence` reaches 1.0. Visual beat-rate accents are at full amplitude.
6. **Confidence drift:** If confidence drops below a threshold (track entered a quiet section, or the cached BPM was wrong), accents fade smoothly to 0. Acquisition resumes when peaks return.

The key mathematical property: **accents only fire when both the BPM prior AND the live audio agree.** Either alone is unreliable; the AND-gate produces perceptual sync.

### 6.2 State machine

Internal states (the existing public `LockState` API maps onto these):

```
              ┌──────────────────────────┐
              │ coldStart                │  ← visible LockState: .unlocked
              │ (waiting for first peak) │
              └────────────┬─────────────┘
                           │ broadband peak detected
                           ▼
              ┌──────────────────────────┐
              │ acquiring                │  ← visible LockState: .locking
              │ (1-2 predicted beats     │
              │  confirmed)              │
              └────────────┬─────────────┘
                           │ confidence ≥ lockThreshold
                           ▼
              ┌──────────────────────────┐
              │ locked                   │  ← visible LockState: .locked
              │ (sustained confirmations)│
              └────────────┬─────────────┘
                           │ confidence < dropThreshold
                           ▼
              ┌──────────────────────────┐
              │ degraded                 │  ← visible LockState: .locking
              │ (predictions firing but  │
              │  confidence faded)       │
              └──────────────────────────┘
                  ▲                     │
                  └─── peaks return ────┘
                  (back to acquiring)
```

**Public `LockState` mapping** (backward compatibility — existing consumers including `SpectralCartograph` see this):
- `coldStart` → `.unlocked`
- `acquiring` / `degraded` → `.locking`
- `locked` → `.locked`

### 6.3 Broadband peak detector

The signal source needs to be perceptually correlated with beats, not just any audio event. Sub-bass alone is wrong (FA #68). The right signal is **broadband spectral flux** — the across-the-band sum of half-wave-rectified frame-to-frame magnitude differences.

Phosphene's `SpectralAnalyzer.smoothedFlux` already computes this for the FeatureVector's `spectralFlux` field. The peak detector consumes this:

```
input:   smoothedFlux per frame (60 Hz update rate)
state:   adaptive median over the last ~1 s (60 frames)
trigger: smoothedFlux > median × 1.8 AND smoothedFlux is local maximum
         AND time since last detected peak ≥ minBeatPeriod * 0.4
output:  peak timestamp (frame-quantized to ±8 ms at 60 Hz)
```

Tunables (initial values, will be calibrated against the 4 captures during impl):
- Threshold multiplier: `1.8 × adaptive_median` (more sensitive than BeatDetector's 1.5 for the per-band path — broadband flux is noisier).
- Refractory period: `0.4 × (60 / cachedBPM)` seconds — prevents double-firing on the same beat.
- Adaptive median window: 60 frames (1 s at 60 fps).

**Why broadband, not sub-bass:**
- Sub-bass fires on bassline events (often off-beat on syncopated tracks — FA #68).
- Snare-only tracks have weak sub-bass content but clear snare events.
- Broadband flux integrates kick + snare + claps + vocal accents + chord changes — anything that adds new energy. This correlates with perceived beats across rhythmic styles.

**Why not just `beatComposite`:** `beatComposite` is the max of per-band onset pulses with cooldowns. Same sub-band-onset limitation but smeared. We want raw broadband flux peaks, not the pulse-shaped output of the existing detector.

### 6.4 BPM prior + phase EMA

State per frame:
- `phaseT₀: Double?` — time of the most recent anchored beat (nil if pre-acquisition).
- `period: Double` — `60.0 / cachedBPM`, immutable per track.
- `confidence: Float ∈ [0, 1]`.

Per-frame update:
```
if phaseT₀ is nil:
    if broadband peak detected this frame at time T:
        phaseT₀ = T
        confidence = 0.1  (initial seed, slightly above 0)
else:
    next_predicted = phaseT₀ + period
    if currentTime in [next_predicted - window, next_predicted + window]:
        # We're in the expectation window.
        if broadband peak detected this frame:
            phase_residual = peakTime - next_predicted
            phaseT₀ = next_predicted + alpha * phase_residual
            confidence = min(1.0, confidence + gain)
    elif currentTime > next_predicted + window:
        # Expectation window passed without a peak.
        phaseT₀ = next_predicted  # advance the predictor without phase correction
        confidence = max(0.0, confidence - decay)
```

Initial tunables (calibrated during impl):
- `window`: ±60 ms.
- `alpha` (phase EMA gain): 0.3 (one third of the residual is absorbed per confirmation — fast enough for live drift tracking, slow enough that off-beat false-positives don't destabilise lock).
- `gain` (confidence increment per match): 0.25 → 4 matches to reach 1.0.
- `decay` (confidence decrement per miss): 0.10.
- `lockThreshold` (state transition `acquiring` → `locked`): 0.7.
- `dropThreshold` (state transition `locked` → `degraded`): 0.3.

**Per-track tunable scaling.** Pre-analysis metadata (§7) modulates these:
- `phaseAcquisitionDifficulty` ∈ [0, 1]:
  - 0 = clean four-on-the-floor: `gain = 0.30`, `window = ±50 ms`, `lockThreshold = 0.8`.
  - 1 = sparse half-time / syncopated: `gain = 0.15`, `window = ±80 ms`, `lockThreshold = 0.5`.
  - Linear interpolation.
- `octaveRisk` flag: if set, the predictor maintains TWO phase candidates (at cachedBPM and at 2×cachedBPM); confidence is computed per-candidate; after 4 confirmed predictions the higher-confidence candidate wins, the other is discarded.

### 6.5 Confidence-gated accent contract

`accentConfidence` is the gating scalar [0, 1] propagated to presets via the FeatureVector.

In `MIRPipeline.buildFeatureVector`:

```swift
// New: gate beat-rate accent fields by acquisition confidence.
let conf = liveDriftTracker.accentConfidence
fv.beatBass     *= conf
fv.beatMid      *= conf
fv.beatTreble   *= conf
fv.beatComposite *= conf
// beatPhase01 / barPhase01 are NOT gated — presets can still use them for
// continuous phase-driven motion (e.g., vocal pitch contour tracking),
// only their amplitudes go to zero via the gated `beatComposite` etc.
```

**Why gating only the beat pulses, not the phase fields:** `beatPhase01` is the continuous-phase output used by some presets for non-pulsed motion (e.g., vocal pitch ribbon following barPhase01). That motion should continue smoothly even at low confidence — it's not an "accent" claim, just a phase-driven motion. The gating zeros out the *pulse-shape* accent fields specifically.

The "soft ramp" (§Recommendation in conversation) is the natural consequence — `accentConfidence` ramps smoothly via the EMA, so accent amplitudes follow smoothly without a visible "snap into place" moment.

### 6.6 What happens on hard tracks

A "hard" track from pre-analysis is one with high `phaseAcquisitionDifficulty`: sparse onset density, syncopated bass, half-time perception, polyrhythmic.

On these tracks:
- Phase acquisition is slower (smaller `gain`, wider `window`).
- Confidence may never reach `lockThreshold`. The track stays in `acquiring` indefinitely.
- Accent amplitudes are correspondingly low — the visual is dominated by continuous-energy modulation throughout.
- This is *graceful failure* — the visual is musical but never claims an inaccurate beat. No "obviously wrong" moments.

**Empirical expectation from the 4 captures:**

| Track | Expected outcome |
|---|---|
| Around the World | Lock fast (clean four-on-the-floor, dense onsets) |
| Get Lucky | Lock fast (clean groove) |
| Royals | Acquire patiently (sparse — half-step hip-hop) |
| Billie Jean | Lock fast despite syncopated bass (broadband peaks on the kick are clear) |
| Seven Nation Army | Lock fast |
| Superstition | Lock fast (clavinet hits are broadband peaks) |
| Everlong | Lock fast |
| B.O.B. | Lock fast (fast rock kit) |
| HUMBLE. | Acquire patiently or stay in degraded (sparse 808 hits) — pre-analyzed `octaveRisk=true` triggers half-time candidate |
| Money | Acquire — odd meter doesn't affect beat acquisition (bar phase is BUG-013 separately); accent on 4-on-the-4-of-7 cadence |

The hard cases (HUMBLE, Money) stay in graceful-degradation mode rather than visibly mis-firing. That is the win.

## 7. Pre-analysis metadata extensions

New schema on `TrackProfile`:

```swift
public struct RhythmCharacter: Sendable, Codable, Hashable {
    /// Per-bar beat-slot mean energy profile. For 4/4 tracks, a 4-element array
    /// [slot 1, slot 2, slot 3, slot 4]. Higher = stronger accent typically at
    /// that slot. Drives per-slot visual emphasis at runtime.
    public let beatStrengthProfile: [Float]

    /// Average sub-bass onsets per beat over the preview. ~1.0 = sparse,
    /// 4+ = dense. Used to tune phase-acquisition patience.
    public let onsetsPerBeat: Float

    /// 0.0–1.0 score for "this BPM might be the half or double of the true tempo."
    /// Computed from cachedBPM vs broadband-flux peak rate over the preview.
    public let octaveRisk: Float

    /// 0.0–1.0 score for "this track will be hard to phase-lock at runtime."
    /// Composed from onsetsPerBeat (low = harder), syncopation index (high = harder),
    /// and meter regularity (irregular = harder).
    public let phaseAcquisitionDifficulty: Float

    /// Syncopation index — fraction of detected onsets that fall *outside* the
    /// nearest cached beat by > ¼ beat. High = syncopated; low = on-beat.
    public let syncopationIndex: Float
}
```

Computed by extending `SessionPreparer+Analysis.swift` with a new helper. All five fields are derivable from the existing 30 s preview audio + Beat This! output + `BeatDetector` per-band onsets on the preview. No new ML inference; only signal processing.

**Storage:** `CachedTrackData` gains a `rhythmCharacter: RhythmCharacter?` field, persisted alongside the existing `beatGrid`, `stemFeatures`, etc.

**Backward compatibility:** the field is Optional; older cache entries return nil. Runtime treats nil as "neutral character" — default tunables, mid-confidence acquisition. Caches refresh organically as users re-prep their playlists.

## 8. Architecture changes — file-level summary

| File | Change |
|---|---|
| `PhospheneEngine/Sources/DSP/LiveBeatDriftTracker.swift` | Substantial rework. New state machine (§6.2), new phase-acquisition algorithm (§6.4), new `accentConfidence` output. BUG-007.4 / .5 / .6 internal machinery preserved at the API surface; semantics map onto new state. `setGrid(_:initialDriftMs:)` deprecated in favor of new `installBPMPrior(bpm:character:)`. |
| `PhospheneEngine/Sources/DSP/BeatDetector.swift` | Add a broadband peak detector (§6.3). Existing per-band onset path preserved unchanged. |
| `PhospheneEngine/Sources/DSP/MIRPipeline.swift` | `buildFeatureVector` multiplies `beatBass/beatMid/beatTreble/beatComposite` by `accentConfidence` (§6.5). New `installBPMPrior` setter path. |
| `PhospheneEngine/Sources/Session/CachedTrackData.swift` | Add `rhythmCharacter: RhythmCharacter?` Optional field. |
| `PhospheneEngine/Sources/Session/SessionPreparer+Analysis.swift` | Compute `RhythmCharacter` during prep. |
| `PhospheneEngine/Sources/Session/GridOnsetCalibrator.swift` | **Delete.** Retired per §5.2. |
| `PhospheneApp/VisualizerEngine+Stems.swift:484` | Replace `setBeatGrid(_:initialDriftMs:)` call with `installBPMPrior(bpm:character:)`. The cached `beatGrid.beats` is no longer consumed for phase; the BPM is read directly from `cached.beatGrid.bpm`. |
| `PhospheneEngine/Sources/Shared/FeatureVector.swift` (or wherever defined) | Add `accentConfidence: Float` field. Increment Common.metal struct size if needed; per CLAUDE.md "Engine MSL struct extension pattern" — additive at the tail, no existing field offsets shift. |
| `PhospheneEngine/Tests/PhospheneEngineTests/DSP/LiveBeatDriftTrackerTests.swift` | Heavy rework — most existing tests cover the cached-grid-anchored behavior that's being replaced. New tests cover the §6.2 state machine, §6.3 peak detector, §6.4 prior/EMA, §6.5 gating. |
| `PhospheneEngine/Tests/PhospheneEngineTests/Session/SessionPreparer*Tests.swift` | New tests for `RhythmCharacter` computation. |
| `PhospheneApp/Tests/PhospheneAppTests/...` | App-side regression tests verifying the install path uses the new method. |
| `PhospheneEngine/Sources/ColdStartVerifier/` | Verifier semantics extend — new mode `--accent-window-pass-rate` that scores "% of audible beats where an accent fired within ±60 ms" rather than "% of audible beats where visual phase aligned within ±50 ms." The old mode stays for back-compat measurement. |
| Preset shaders | **No changes.** §5.8 backward-compat at the FeatureVector layer. |
| `docs/QUALITY/KNOWN_ISSUES.md` BUG-017 | Closeout addendum when BSAudit.3 lands. |
| `docs/ENGINEERING_PLAN.md` | New BSAudit.3 increment marked ✅. |
| `docs/RELEASE_NOTES_DEV.md` | `[dev-2026-05-XX]` entry. |
| `CLAUDE.md` | New "Cold-Start Phase Contract" section under §Audio Data Hierarchy documenting the BPM-prior + broadband-peak + accent-confidence architecture. |

This is a substantial change. The good news is most of the touch surface is one file (`LiveBeatDriftTracker.swift`); the rest is mostly small wiring or additive (new metadata, new test files).

## 9. Adversarial review

Each item below is a risk or failure mode that could break the design. Honest unknowns flagged.

### 9.1 The first broadband peak might not be beat 1

If the first detectable broadband peak is not actually on a beat (e.g., a sub-beat hi-hat, a vocal entry off-beat, a transient before the track's first beat), the BPM prior locks to the wrong phase. All subsequent predictions are shifted by some fraction of a beat.

**Mitigation:** the confidence accumulator is the back-pressure. If the predicted beats consistently miss broadband peaks (because we're predicting at off-beat moments), confidence will not climb. The system stays in `acquiring` → no accents fire → visual stays continuous-energy. The visual never makes a wrong claim.

**Open question:** what's the actual hit rate of "first broadband peak is a beat" on the test catalog? Estimated >80 % on pop/rock/electronic but not measured. Will be measured during BSAudit.3.validate against the 4 reference captures.

### 9.2 The cached BPM might be wrong

Beat This! has known octave-error failure modes (CLAUDE.md FA #17 amended) — half-time or double-time mis-detection on syncopated drums or odd-meter tracks. If `cachedBPM` is 76 but the true tempo is 152, the predictor's predicted beats land every other audible beat.

**Mitigation:** `octaveRisk` flag in `RhythmCharacter`. Computed at prep by comparing the broadband flux peak rate against `cachedBPM`. If they disagree by ~2×, the flag fires. Runtime maintains TWO BPM candidates (cachedBPM and 2×cachedBPM); the higher-confidence one wins.

**Open question:** is the peak-rate-vs-BPM comparison robust enough to flag octave-risk reliably? Needs empirical calibration against HUMBLE (where the issue is real) and Around the World (where it isn't).

### 9.3 Broadband flux could itself be off-beat on some tracks

Tracks with prominent off-beat content above the kick band (e.g., off-beat synth chords, off-beat hi-hat patterns) could produce broadband flux peaks that don't correspond to listener-perceived beats. This would be FA #68 reincarnated at the broadband layer.

**Mitigation 1:** The confidence accumulator. If the broadband peaks are systematically off-beat, the BPM prior will lock to them initially but subsequent peaks will reinforce the off-beat alignment — that's actually the SAME alignment. The visual would accent on the off-beat content (e.g., the synth chord rhythm) which IS what listeners hear in that section. **The "wrong" alignment may actually be musically correct for that track.**

**Mitigation 2:** Beat strength profile. Pre-analysis identifies which slots in the bar carry energy. If runtime acquires phase that lands on the lowest-energy slot per the preview profile, that's a half-beat mis-alignment — re-test the offset-by-period/2 candidate.

**Open question:** how often does the broadband-peak phase disagree with the listener-perceived beat phase in a *perceptually wrong* way (vs a "different but valid" interpretation)? Hard to answer without listening tests. The BSAudit.3.validate step includes M7 listening review on the 4 captures + a few harder novel tracks.

### 9.4 Quiet intros — no broadband peaks for 5+ seconds

Some tracks start with a long quiet intro (sustained pad, ambient texture, no percussion). Broadband flux might not exceed the threshold for several seconds. The visual stays in `coldStart` (continuous-energy only) the whole time.

**Acceptable.** This IS what the music is doing — there is no beat yet. Visual being beat-less during a beat-less intro is *correct*. The risk is users perceiving "the visualizer isn't working" — but Matt's reframed product position ("ramp-up tolerated") explicitly accepts this.

**Mitigation:** Pre-analysis could detect quiet intros and signal "expect late acquisition" in the rhythm character metadata. The UX could surface a subtle "warming up" indicator during long acquisition phases. Out of scope for the engine work; UX-team concern.

### 9.5 Tempo-changing tracks

Tracks with tempo accelerandos / ritards / time-signature changes would drift away from the cached BPM. The phase EMA's `alpha = 0.3` would track small live drift (~5 % BPM change over 10 s) but couldn't handle large structural changes.

**Acceptable for the target use case.** Listening-party music is mostly tempo-stable. Tempo-changing tracks (classical, prog, some jazz) are out-of-distribution; degrade to continuous-energy via confidence-fade.

### 9.6 Cross-fade between tracks (DJ-style transitions)

If the user plays through a Spotify playlist with crossfade enabled, the audio at the start of track N+1 overlaps with the tail of track N. Broadband peaks are present (from both tracks). The new track's cached BPM is loaded; the predictor anchors to a peak that might be from the outgoing track.

**Mitigation:** the existing per-track `mir.reset()` happens on track change. The new track's `coldStart` waits for a peak under the *new* BPM hypothesis. Confidence-building filters out wrong-tempo peaks (they won't align to the new BPM's expectations).

### 9.7 The lock state public API map could break consumers

Existing `SpectralCartograph` diagnostic display + tests check `LockState` values. If I get the mapping wrong, those break.

**Mitigation:** the mapping in §6.2 is conservative — `unlocked` / `locking` / `locked` semantically preserved. The new state machine is internal; the external enum stays. Regression tests cover the API surface.

### 9.8 Pre-analysis metadata computation might be slow

`RhythmCharacter` adds new processing to `SessionPreparer`. If it adds significant time per track, the rehearsal phase elongates.

**Mitigation:** all the metadata is derivable from data already computed during prep. The marginal cost is small (~50-100 ms per track for the rhythm-character signal processing). Matt's 3-minute rehearsal budget easily accommodates 10 tracks × 1 s additional prep each.

### 9.9 Existing presets don't gate beat accents on confidence

§5.8's claim is that gating happens at the `FeatureVector` layer (MIRPipeline multiplies before write). Presets see lower-amplitude `beatComposite` etc. and don't need changes.

**But:** some presets use `beatPhase01` to drive non-pulse motion (e.g., a slow color cycle that wraps at every beat). Those won't be gated. That's intentional (§6.5) but could surface a preset where the unmodulated phase motion + the gated beat pulses interact weirdly. Audit-required per preset before BSAudit.3 lands.

**Risk level:** medium. The audit happens during impl.

### 9.10 The "perception of sync" claim itself

The whole design rests on the claim: "accents firing within ±60 ms of audible beats are perceived as in-sync." This is well-established in psychoacoustics (audio-visual sync window is typically ~80-120 ms; ±60 ms is solidly inside it). But Matt's explicit threshold was "credible and competent within 3 s" — perceptual, not numeric.

**Mitigation:** BSAudit.3.validate includes M7 listening review on the 4 captures + a few harder novel tracks. The numeric verifier (`ColdStartVerifier --accent-window-pass-rate`) is necessary but not sufficient; Matt's M7 verdict is the load-bearing close criterion.

## 10. Open empirical questions

Honest unknowns. None block the design; all will be answered during impl + validate.

1. **First-broadband-peak hit rate per track** (§9.1). Estimated >80 % but unmeasured.
2. **Cross-capture stability of the broadband peak detector itself** (§9.3). The detector is deterministic, but per-capture acoustic variability could shift peak timestamps by 10-30 ms. Is that within the ±60 ms acceptance window in practice?
3. **Pre-analysis octave-risk classifier accuracy** (§9.2). Needs calibration on HUMBLE (true positive) + Around the World / Royals (true negative).
4. **`phaseAcquisitionDifficulty` score calibration** (§7). The formula is judgment-call now; needs to be validated against the catalog's actual acquisition behavior.
5. **Preset-level interaction with confidence gating** (§9.9). One-time per-preset audit during impl.

## 11. Sequencing — sub-increments

BSAudit.3 splits into three sub-increments per CLAUDE.md "design-first" + "stop-and-report" disciplines.

### BSAudit.3.design ✅ (this document)

**Status:** ready for Matt sign-off. Sub-increment is just the design doc.

**Done-when:** Matt approves direction; flag any concerns; surface any "what stays unchanged" claims I got wrong.

### BSAudit.3.impl (estimated 2-3 sessions)

Engine + app + tests. Sequencing within the increment:

1. **Day 1 — Foundation layer.**
   - Add `BroadbandPeakDetector` to `BeatDetector` (or as sibling module).
   - Add `RhythmCharacter` schema to `Shared` module; extend `CachedTrackData`.
   - Extend `SessionPreparer+Analysis.swift` to compute `RhythmCharacter`. Tests.
   - **Build green, lint clean, no behavior change yet (no consumer of the new fields).**

2. **Day 2 — `LiveBeatDriftTracker` rework.**
   - Implement new state machine + phase-acquisition algorithm.
   - Add `accentConfidence` output. Add `installBPMPrior(bpm:character:)` entry point.
   - Map internal states to external `LockState` per §6.2.
   - Heavy test rework: new tests for the §6.2 state machine, §6.4 acquisition, §9.x edge cases.
   - **Build green, lint clean, the new tracker tested in isolation.**

3. **Day 3 — Integration + retirement.**
   - `MIRPipeline.buildFeatureVector` multiplies beat fields by `accentConfidence`.
   - `VisualizerEngine+Stems.resetStemPipeline` switches from `setBeatGrid(_:initialDriftMs:)` to `installBPMPrior`.
   - **Delete `GridOnsetCalibrator.swift`** and its prep-time invocation.
   - Per-preset audit (§9.9): any preset with non-gated `beatPhase01` reliance? Document any required preset changes (likely none).
   - **Engine suite green, app suite green, swiftlint --strict 0 violations.**

### BSAudit.3.validate (estimated ½-1 session)

Run the new architecture against the 4 reference captures + a fresh capture from Matt's listening party playlist.

- Extend `ColdStartVerifier` with the new `--accent-window-pass-rate` mode (§8 table).
- Per-track verdict: "what % of audible beats had a visual accent within ±60 ms?"
- M7 listening review on the captures: does it look credibly synced to Matt?
- Closeout: BSAudit.3 ✅, BUG-017 Resolved with the commit hash, RELEASE_NOTES + ENGINEERING_PLAN updates.

## 12. Verification criteria (write before the fix)

Per CLAUDE.md Defect Handling Protocol — verification gates defined before code lands:

- [ ] **Automated:** `ColdStartVerifier --accent-window-pass-rate` reports ≥ 80 % of audible beats in the first 10 s of each track had an accent fire within ±60 ms, OR the track stayed in `acquiring` with accentConfidence < 0.3 throughout (graceful degradation — accents didn't fire wrong).
- [ ] **Automated:** Engine suite remains at 1265 tests pass (or higher with new tests added). No pre-existing tests regress.
- [ ] **Automated:** Project-wide `swiftlint --strict` remains at 0 violations.
- [ ] **Manual:** Matt M7 listening review on a real listening-party playlist confirms the perceptual sync is credible from frame 1 (with the ramp-up phase acceptable as designed).
- [ ] **Regression:** the BUG-007.x lock-state API surface is preserved — existing consumers (`SpectralCartograph` diagnostic display, regression tests) work unchanged.

## 13. Anti-patterns to avoid

From CLAUDE.md + the five-iteration history:

1. **Don't trust cached grid phase.** §5.1 retires its phase use entirely. Anywhere phase is read from cached beats during runtime is a bug.
2. **Don't use sub-bass onsets as a phase reference.** §5.5 + §6.3 use broadband flux. FA #68.
3. **Don't extend the EMA's ±50 ms window to make gross corrections.** The new architecture doesn't need the EMA to make gross corrections — phase is acquired fresh from broadband peaks. The EMA's role is small live drift only.
4. **Don't add fix code before the design surfaces to Matt.** This document is the surface step.
5. **Don't bypass the pre-analysis metadata extensions.** The §7 metadata is what makes the system perceptually robust on hard tracks — without it, the runtime defaults are mediocre across the catalog.
6. **Don't iterate further on Beat This!-on-tap as a phase reference.** BSAudit + BSAudit.2 falsified this. Closed.
7. **Don't claim "the visual is on-beat" when the system is in `acquiring`.** UX implication: any debug overlay / lock-state indicator should distinguish "system is trying" from "system has locked." Existing `SpectralCartograph` already does this; verify after impl.
8. **Don't bundle BUG-013 (odd-meter / time-signature) into BSAudit.3.** That's a separate defect; BSAudit.3 handles BEAT phase, not BAR phase. Money will lock to beats; its bar interpretation stays a known limitation.

## 14. Sign-off

This document is the BSAudit.3.design deliverable. **No code changes have landed.** **Matt sign-off received 2026-05-24** on the design + the three open decisions:

| Decision | Resolution |
|---|---|
| Soft vs hard accent amplitude ramp | **Soft.** `accentConfidence` ramps smoothly via the EMA; accent amplitudes follow without a snap-into-place moment. Already the default in §6.5. |
| `phaseAcquisitionDifficulty` calibration | **Default formula, validate empirically.** Use the §7 composition (`onsetsPerBeat`, `syncopationIndex`, meter regularity) at prep time; calibrate against actual lock behavior in BSAudit.3.validate. No manual per-track tuning before impl. |
| Octave-risk handling | **Dual-candidate at runtime.** When `octaveRisk` ≥ 0.5, `LiveBeatDriftTracker` maintains two phase candidates (cachedBPM and 2×cachedBPM); confidence is computed per-candidate; after 4 confirmed predictions the higher-confidence candidate wins. Already the default in §6.4 + §9.2. |

BSAudit.3.impl is clear to start. Kickoff prompt: [`docs/prompts/BSAUDIT_3_IMPL_KICKOFF.md`](prompts/BSAUDIT_3_IMPL_KICKOFF.md).

---

— Claude (2026-05-24, BSAudit.3.design)
