# Capability Registry — DSP / MIR

**Audit increment:** CA.1
**Date:** 2026-05-20
**Auditor:** Claude (session-driven, read-only)
**Scope:** `PhospheneEngine/Sources/DSP/` (20 files, 5,837 LoC) + 2 DSP-adjacent files in `PhospheneEngine/Sources/Session/` (`GridOnsetCalibrator.swift`, `BeatGridAnalyzer.swift`).
**Methodology:** [`docs/prompts/PHASE_CA_KICKOFF_CA1_DSP_MIR_2026-05-20.md`](../prompts/PHASE_CA_KICKOFF_CA1_DSP_MIR_2026-05-20.md).
**Reads relied on:** `CLAUDE.md`, `docs/ARCHITECTURE.md`, `docs/DECISIONS.md` (D-026, D-027, D-058, D-059, D-075–D-080), `docs/QUALITY/KNOWN_ISSUES.md` (BUG-007.x cluster, BUG-008, BUG-009, BUG-R001–R008), `docs/ENGINEERING_PLAN.md`, `docs/diagnostics/capability-audit-pre-2026-05-12.md`.

---

## Summary

22 file-level entities audited. The DSP subsystem is substantially production-active and largely doc-aligned. No `broken-but-claimed` findings; no new BUG entries filed.

| Verdict | Count | Notes |
|---|---|---|
| `production-active` | 18 files | Default verdict; consumers verified by grep across `PhospheneApp/`, `PhospheneEngine/Sources/`, and `PhospheneEngine/Tests/`. |
| `production-orphan` (runtime path) | 1 cluster | `SelfSimilarityMatrix` + `NoveltyDetector` + `StructuralAnalyzer` run every frame inside `MIRPipeline.process` but their per-frame output (`MIRPipeline.latestStructuralPrediction`) is read by exactly one consumer at *preparation* time only. The runtime per-frame work has no live reader. |
| `production-orphan` (field-level) | 1 field | `MIRPipeline.spectralRolloff` is public; zero non-DSP consumers. The underlying rolloff value IS consumed internally by `StructuralAnalyzer` (which is itself in the orphan cluster above), but the public exposure is dead. |
| `boundary-deferred` | 2 files | `GridOnsetCalibrator.swift` and `BeatGridAnalyzer.swift` live in `Sources/Session/`, not `Sources/DSP/`, despite functioning as DSP capabilities. File-location call deferred to a CA-future increment that audits Session. |
| `built-but-undocumented` | 1 file | `MIRPipeline+Recording.swift` writes a parallel `~/phosphene_features.csv` (wired to the `R` keyboard shortcut) that is distinct from `SessionRecorder`'s `features.csv`. The duplication is real and works; only the documentation surface omits the distinction. |
| `documented-but-missing` | 1 reference | `docs/CAPABILITY_GAP_AUDIT.md` is cited as a live file at [`docs/ENGINEERING_PLAN.md:446`](../ENGINEERING_PLAN.md) but does not exist on disk. The kickoff anticipated this finding; it is already acknowledged in `docs/ENGINEERING_PLAN.md:3724`. |
| `unverified-claim` | 0 | No new instances. PT.1 (the canonical case cited in the kickoff) is now `production-active` after the 2026-05-19 ring-buffer fix landed; verified at [`PitchTracker.swift:137-139`](../../PhospheneEngine/Sources/DSP/PitchTracker.swift) and `:178-212`. |
| `dead` | 0 | — |
| `stub` | 0 | `DSP.swift` is a 5-line module marker (just `import Accelerate / Shared / os.log`); not a stub. |

**The highest-priority non-`production-active` finding** is the runtime `StructuralAnalyzer` cluster. Per-frame work runs (chroma → 16-element feature vector → similarity matrix → novelty detection every 30 frames → boundary prediction) and writes `latestStructuralPrediction`, but the only consumer is `SessionPreparer+Analysis.swift:289` extracting `sectionIndex + 1` *at preparation time*. The orchestrator path that reads `StructuralPrediction` at runtime (`TransitionPolicy.swift:165`, `LiveAdapter.swift:250`, `ReactiveOrchestrator.swift:316`) gets that prediction from `SessionPlanner.swift:317` constructed *synthetically* — not from MIRPipeline. This is a real piece of dead runtime work, on the audio-callback hot path.

**Five follow-up items are tracked in [§Follow-up Backlog](#follow-up-backlog) below** as candidate increments (`CA.1-FU-1` through `CA.1-FU-5`). Per the kickoff's audit-only discipline, none ship as part of this audit increment.

**Doc-drift findings of note:**

1. The `DSP/` module-map block at [`docs/ARCHITECTURE.md:415-428`](../ARCHITECTURE.md) lists 13 files but the directory contains 20. Six load-bearing files are absent from the canonical module map, including `LiveBeatDriftTracker.swift` (the BUG-007.x focal point and the largest DSP file at 808 LoC). This is the same drift the kickoff prompt was authored to surface.
2. PT.1 (`PitchTracker` ring-buffer fix, 2026-05-19) has no `Resolved` entry in `docs/QUALITY/KNOWN_ISSUES.md` despite affecting production behaviour for ~5 months. The fix is documented in code comments at [`PitchTracker.swift:8-21`](../../PhospheneEngine/Sources/DSP/PitchTracker.swift) and in the AV.2 closeout narrative at [`ENGINEERING_PLAN.md:3858`](../ENGINEERING_PLAN.md), but the Defect Handling Protocol requires a `BUG-<id>` entry. Flagged for `KNOWN_ISSUES.md` sweep; not a new BUG.

---

## Findings by verdict

### broken-but-claimed (BUG entries filed)

**None.** Every public capability that docs claim to work was verified against either tests, code-level evidence, or recent session-log narrative (BUG-007.9 manual validation, AV.2 PT.1 closeout, BUG-009 fast-rock validation). The PT.1 pattern the kickoff explicitly invoked is now closed (ring-buffer fix at [`PitchTracker.swift:178-212`](../../PhospheneEngine/Sources/DSP/PitchTracker.swift); confidence > 0 was verified in production sessions per [`ENGINEERING_PLAN.md:3858`](../ENGINEERING_PLAN.md) "Route 1 vocals melody → hue ... 23.28 % (was 0 % pre-PT.1)").

### documented-but-missing

1. **`docs/CAPABILITY_GAP_AUDIT.md`** — referenced as a live file at [`docs/ENGINEERING_PLAN.md:446`](../ENGINEERING_PLAN.md) ("Capability Gap Audit (2026-05-12). docs/CAPABILITY_GAP_AUDIT.md inventories built-but-underused capabilities ..."). The file does not exist on disk. The reference at [`ENGINEERING_PLAN.md:3724`](../ENGINEERING_PLAN.md) already acknowledges the gap ("the same session: docs/CAPABILITY_GAP_AUDIT.md is referenced from this file but doesn't exist as a file"), but the upstream pointer at line 446 has not been corrected. **Recommended drift correction:** rewrite the line-446 pointer to reflect either (a) "planned, not yet authored" or (b) point at this `CAPABILITY_REGISTRY/` tree once it has additional subsystem audits. Applied as a doc-drift edit in this increment.

### unverified-claim

None this increment. The PT.1 pattern the kickoff prompt highlighted is now closed; no analogous pattern was surfaced in this audit.

### production-orphan

1. **Per-frame `StructuralAnalyzer` cluster** — runs every frame in `MIRPipeline.process` ([`MIRPipeline.swift:249`](../../PhospheneEngine/Sources/DSP/MIRPipeline.swift)) and writes `latestStructuralPrediction` ([`MIRPipeline.swift:80`](../../PhospheneEngine/Sources/DSP/MIRPipeline.swift)). Full grep of consumers (`grep -rn "latestStructuralPrediction" PhospheneEngine/Sources PhospheneApp`) returns four hits: the declaration, the per-frame writer, the `reset()` clear, and one reader at `SessionPreparer+Analysis.swift:289`. The reader is at preparation time only — it derives `sectionCount` for `TrackProfile`. The orchestrator's runtime `StructuralPrediction` consumption (`TransitionPolicy.swift:165` / `LiveAdapter.swift:250` / `ReactiveOrchestrator.swift:316`) is fed from `SessionPlanner.swift:317` which constructs a synthetic `StructuralPrediction(sectionIndex: 0, sectionStartTime: clock, predictedNextBoundary: clock, …)`. **No code path reads MIRPipeline's per-frame structural output at runtime.** The cluster is:
   - [`SelfSimilarityMatrix.swift`](../../PhospheneEngine/Sources/DSP/SelfSimilarityMatrix.swift) (229 LoC) — 600-frame ring buffer + cosine similarity queries.
   - [`NoveltyDetector.swift`](../../PhospheneEngine/Sources/DSP/NoveltyDetector.swift) (287 LoC) — checkerboard kernel, peak picking with adaptive threshold + minimum distance gate.
   - [`StructuralAnalyzer.swift`](../../PhospheneEngine/Sources/DSP/StructuralAnalyzer.swift) (345 LoC) — coordinator; runs novelty detection every 30 frames; predicts next boundary from duration consistency + repetition heuristic.

   **Suggested next step (out of scope for CA.1):** either (a) gate the runtime call so the chain runs at prep time only — `SessionPreparer` already drives MIRPipeline over the preview clip, and that's where the consumer lives — or (b) wire `MIRPipeline.latestStructuralPrediction` into `VisualizerEngine` → orchestrator at runtime so the orchestrator's TransitionPolicy reads real predictions instead of synthetic ones. Option (b) is the higher-leverage fix (real structural boundaries would fire `TransitionPolicy.structuralBoundary` triggers per the documented behaviour at `ARCHITECTURE.md:200`). Either way, the per-frame audio-callback CPU cost of running the cluster with no live consumer is wasted.

2. **`MIRPipeline.spectralRolloff` (field-level orphan)** — declared public at [`MIRPipeline.swift:48`](../../PhospheneEngine/Sources/DSP/MIRPipeline.swift); zero non-DSP consumers (`grep -rn "spectralRolloff" PhospheneEngine/Sources PhospheneApp | grep -v "Sources/DSP"` returns empty). The underlying value IS computed and used: `SpectralAnalyzer.Result.rolloff` flows into `StructuralAnalyzer.SpectralSummary.rolloff` (at [`MIRPipeline.swift`](../../PhospheneEngine/Sources/DSP/MIRPipeline.swift) per `buildFeatureVector` plumbing). The orphan is only the public exposure on MIRPipeline. **Suggested next step (out of scope):** demote to `private(set) internal` or delete entirely if the StructuralAnalyzer cluster is also pruned per the previous finding. Low priority.

### dead

None. Every public symbol has at least one production *or* test consumer.

### stub

None. `DSP.swift` (5 lines, just imports) is a module marker, not a stub function.

### built-but-undocumented

1. **`MIRPipeline+Recording.swift`** (69 LoC) — implements `startRecording()` / `stopRecording()` / `writeRecordingRow(...)` which write a parallel `~/phosphene_features.csv` file. Wired into `VisualizerEngine+Capture.swift:18` via `toggleMIRRecording()`, bound to the `R` keyboard shortcut (per `CLAUDE.md` / `ARCHITECTURE.md:230`). This CSV path is **distinct** from `SessionRecorder`'s per-session `~/Documents/phosphene_sessions/<ts>/features.csv` (described at `ARCHITECTURE.md:266-280`). Both exist; both are functional; both write similar but not identical column sets (MIRPipeline+Recording adds `track`/`artist` columns and a 1 Hz throttle, vs SessionRecorder's per-frame stream). The `R` shortcut is documented but the *fact that it produces a different file with a different schema than the auto-recorded session* is not surfaced anywhere in `ARCHITECTURE.md` or `CLAUDE.md`. **Suggested doc-location:** `ARCHITECTURE.md §Session Recording` should add a note that `R` (manual MIR record) and auto-recording are independent and write to different paths. Applied as a small doc-drift edit in this increment.

### boundary-deferred

1. **`Sources/Session/GridOnsetCalibrator.swift`** (~250 LoC) — instantiates a live `BeatDetector` from the DSP module, replays preview audio offline through it, computes the median `(gridBeat − onsetTime)` offset in ms, and returns the calibration. Imports `DSP`, `Accelerate`, `Foundation`; depends on `BeatGrid` and `BeatDetector` from DSP and on vDSP FFT primitives. Two production consumers (`SessionPreparer+Analysis.swift:179`, `VisualizerEngine+Stems.swift:271`) plus 5 test instantiations. It is a DSP capability by every functional criterion *except file location*. **Verdict-deferred to the Session subsystem audit (CA.x).** Recommendation when that audit runs: relocate to `Sources/DSP/GridOnsetCalibrator.swift` and reduce Session-module's DSP dependency.

2. **`Sources/Session/BeatGridAnalyzer.swift`** (~75 LoC) — declares the `BeatGridAnalyzing` protocol (`Sendable`) and the `DefaultBeatGridAnalyzer` implementation. Composes DSP's `BeatThisPreprocessor` + ML's `BeatThisModel` + DSP's `BeatGridResolver` into a single injectable step. Imports `DSP`, `ML`, `Metal`. Consumers: `SessionPreparer.analyzePreview()` (lines 116–122 full mix, 145–152 drums stem), `VisualizerEngine+InitHelpers.init` (line 109), `VisualizerEngine+Stems` runtime cache (line 392). Functionally a DSP-and-ML composition; the file-location is reasonable because the protocol shape matches Session's other "analyzing" protocols (`StemAnalyzing`, `MoodClassifying`). **Verdict-deferred:** the protocol's *home* may be correct in Session (the testability seam pattern lives there), but the implementation's *home* arguably belongs in DSP. Surface for re-evaluation in the Session subsystem audit.

### production-active

(See per-file index below for details. Counts only here, no per-finding detail unless a noteworthy nuance applies.)

- **DSP core analyzers (8 files):** `BandEnergyProcessor`, `SpectralAnalyzer` (with the public-property orphan noted above), `ChromaExtractor`, `BeatDetector`, `BeatDetector+Tempo`, `BeatDetector+TempoDiagnostics` (env-gated), `BeatPredictor`, `PitchTracker`.
- **Beat-grid infrastructure (4 files):** `BeatGrid`, `BeatGridResolver`, `BeatThisPreprocessor`, `LiveBeatDriftTracker`.
- **Coordinator (2 files):** `MIRPipeline`, `MIRPipeline+Recording` (with the doc gap noted above).
- **Stem analysis (2 files):** `StemAnalyzer`, `StemAnalyzer+RichMetadata`.
- **Module marker (1 file):** `DSP.swift`.

---

## Per-file capability index

Citations use `path:line` format. Inventory data sourced from per-file Explore-agent reads; consumer counts sourced from `grep -rn` of canonical type names across `PhospheneApp/`, `PhospheneEngine/Sources/`, and `PhospheneEngine/Tests/`.

### `DSP.swift` (5 lines) — `production-active`

Module entry-point marker. Declares imports (`Accelerate`, `Shared`, `os.log`). No public surface beyond the SwiftPM module marker itself.

### `BandEnergyProcessor.swift` (280 lines) — `production-active`

[`BandEnergyProcessor.swift:13`](../../PhospheneEngine/Sources/DSP/BandEnergyProcessor.swift) — 3-band + 6-band energy extractor with Milkdrop-style average-tracking AGC (output = `raw / runningAverage × 0.5`, centered at 0.5). Two-phase warmup (fast 60 frames @ 0.95, then moderate 180 frames @ 0.992). FPS-independent smoothing via `Smoother`.

| Capability | Verdict | Consumers (prod / test) | Doc-cited |
|---|---|---|---|
| `BandEnergyProcessor` class | `production-active` | MIRPipeline + StemAnalyzer (4 instances) / 3 test files | `ARCHITECTURE.md:82`, `:580-589`, `:417`; D-026 |
| `Result` struct (12 fields: bass/mid/treble × instant/att + 6-band) | `production-active` | 4 prod sites / 0 named-result-type tests | `ARCHITECTURE.md:91` (FeatureVector contract) |

Tuning constants confirmed against `ARCHITECTURE.md §AGC` / `§Smoothing` (no drift):
- `agcRateFast = 0.95`, `agcRateModerate = 0.992`, `warmupFastFrames = 60`, `warmupModerateFrames = 180`, instant smoother rates `(0.65, 0.75, 0.75)` @ 30 fps.

### `SpectralAnalyzer.swift` (251 lines) — `production-active` (with field-level orphan)

[`SpectralAnalyzer.swift:13`](../../PhospheneEngine/Sources/DSP/SpectralAnalyzer.swift) — Spectral centroid (energy-weighted mean frequency), rolloff (85th percentile cumulative energy), and flux (half-wave-rectified frame-to-frame magnitude difference) via vDSP. EMA-smoothed variants per feature (`centroidAlpha = 0.12`, `rolloffAlpha = 0.12`, `fluxAlpha = 0.25`).

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `SpectralAnalyzer` class | `production-active` | MIRPipeline only / 2 test files | `ARCHITECTURE.md:86`, `:416` |
| `Result.centroid` / `smoothedCentroid` | `production-active` | Flowed via `MIRPipeline.rawSmoothedCentroid` to `VisualizerEngine+Audio.swift:239,243`, then normalized into FeatureVector | — |
| `Result.flux` / `smoothedFlux` | `production-active` | Flowed via `MIRPipeline.rawSmoothedFlux` to `VisualizerEngine+Audio.swift:243`, then normalized into FeatureVector | — |
| `Result.rolloff` / `smoothedRolloff` (internal flow) | `production-active` | Consumed internally by `StructuralAnalyzer.SpectralSummary.rolloff` | — |
| `MIRPipeline.spectralRolloff` (public field) | **`production-orphan`** | Zero non-DSP consumers | See top-level finding. The computation is consumed inside DSP; only the public exposure is dead. |

### `ChromaExtractor.swift` (378 lines) — `production-active`

[`ChromaExtractor.swift:13`](../../PhospheneEngine/Sources/DSP/ChromaExtractor.swift) — 12-bin chroma vector with bin-count normalization, additive accumulation (decay `0.9995/frame ≈ 23 s half-life`), Krumhansl-Schmuckler key estimation (24 profiles: 12 major + 12 minor), and 8-second key hysteresis.

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `ChromaExtractor` class | `production-active` | MIRPipeline only / 3 test files (incl. `ChromaRegressionTests`) | `ARCHITECTURE.md:85`, `:418`, `:619-621` |
| `latestChroma` (via MIRPipeline) | `production-active` (indirect) | No direct App consumer; chroma feeds Mood Classifier inputs per `ARCHITECTURE.md:623-625` ("major/minor key correlations" are 2 of 10 inputs) | — |
| `estimatedKey` / `stableKey` / `keyConfidence` | `production-active` | `VisualizerEngine+Audio.swift:278,394,429`; `VisualizerEngine+Capture.swift:163`; `DebugOverlayView.swift:76` | `ARCHITECTURE.md:619`; CLAUDE.md key/mood section (implicit) |
| `latestMajorKeyCorrelation` / `latestMinorKeyCorrelation` | `production-active` | `VisualizerEngine+Audio.swift:244-245,307-308`; `SessionPreparer+Analysis.swift:278-279` (CSV recording + mood classifier inputs) | `ARCHITECTURE.md:623-625` |

Tuning constants confirmed: `minFrequency = 500.0` Hz (matches `ARCHITECTURE.md:619` "Skip bins below 65 Hz" — **wait, drift here**: ARCHITECTURE.md says 65 Hz, code says 500 Hz). The code comment at `ChromaExtractor.swift:59-63` explains the 500 Hz floor: "46.875 Hz spacing causes systematic pitch class bias (e.g., bins 2, 5, 10 all map to F#)." Either the 65 Hz claim in `ARCHITECTURE.md:619` is stale or the code's 500 Hz is overly conservative. **Doc-drift candidate**, surfaced below.

### `BeatDetector.swift` (400 lines) — `production-active`

[`BeatDetector.swift:17`](../../PhospheneEngine/Sources/DSP/BeatDetector.swift) — 6-band onset detection with adaptive median-thresholds, per-band cooldowns (`[0.4, 0.4, 0.2, 0.2, 0.15, 0.15]` s), grouped beat pulses (`beatBass`/`beatMid`/`beatTreble`/`beatComposite`), and tempo estimation via IOI (sub_bass only, D-075) + autocorrelation. Zero-alloc per-frame in `process(magnitudes:fps:deltaTime:)`.

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `BeatDetector` class | `production-active` | MIRPipeline + StemAnalyzer (drums-only) + GridOnsetCalibrator + tests (6 test files) | `ARCHITECTURE.md:83`, `:419`; D-075 |
| `Result.onsets[0..5]` | `production-active` | Indirect via MIRPipeline → `recordOnsetTimestamps` (sub_bass only per D-075) | — |
| `Result.beatBass/Mid/Treble/Composite` | `production-active` | Plumbed into FeatureVector | `ARCHITECTURE.md:597-599` |
| `Result.estimatedTempo` / `tempoConfidence` / `stableBPM` / `instantBPM` | `production-active` | MIRPipeline-private state | — |
| `Result.bassOnsetCount` | `production-active` | One App consumer: `VisualizerEngine+Audio.swift:390` (CSV recording) | — |
| `tempoDebug` | `production-active` | `VisualizerEngine+Audio.swift:393` (debug overlay) | — |

Tuning constants confirmed against `ARCHITECTURE.md:597-599` (no drift): `bandCooldowns`, `groupCooldowns`, `thresholdMultiplier = 1.5`, `pulseSmoother(rate30: 0.6813)` for ~200 ms decay.

### `BeatDetector+Tempo.swift` (395 lines) — `production-active`

[`BeatDetector+Tempo.swift:59`](../../PhospheneEngine/Sources/DSP/BeatDetector+Tempo.swift) — `computeStableTempo()` (1 Hz, trimmed-mean IOI per D-075) and `estimateTempo()` (autocorrelation fallback). Halving-only octave correction at BPM > 175 (BUG-009: threshold raised from 160 to 175 for fast rock; sub-80 doubling explicitly removed per D-079).

Verified rule alignment:
- [`BeatDetector+Tempo.swift:196-198`](../../PhospheneEngine/Sources/DSP/BeatDetector+Tempo.swift) comment: "Halving-only octave correction. Sub-80 doubling was deleted in QR.1 (D-079) — Pyramid Song genuinely runs at ~68 BPM."
- Cross-checked against D-079 rule 4: matches.
- Cross-checked against `BeatGrid.halvingOctaveCorrected` threshold (175 in `BeatGrid.swift:186` per BUG-009): matches across the tempo path. Three-site consistency verified (`BeatDetector+Tempo.computeRobustBPM`, `BeatDetector+Tempo.estimateTempo`, `BeatGrid.halvingOctaveCorrected`).

### `BeatDetector+TempoDiagnostics.swift` (87 lines) — `production-active` (env-gated)

[`BeatDetector+TempoDiagnostics.swift:23`](../../PhospheneEngine/Sources/DSP/BeatDetector+TempoDiagnostics.swift) — DSP.1 baseline-capture instrumentation gated behind `BEATDETECTOR_DUMP_HIST=1` env var; optional file output via `BEATDETECTOR_DUMP_FILE=<path>`. `dumpHistogram`, `dumpEarly`, `dumpTempoTimestamp` methods. Silent in production.

Consumer: `TempoDumpRunner` CLI (per `ARCHITECTURE.md:539`) + `Scripts/dump_tempo_baselines.sh`. Confirmed as permanent regression infrastructure for DSP.1/DSP.2 per D-075.

### `BeatPredictor.swift` (188 lines) — `production-active` (reactive-mode fallback)

[`BeatPredictor.swift:51`](../../PhospheneEngine/Sources/DSP/BeatPredictor.swift) — IIR period smoother on rising-edge onsets; writes `beatPhase01` and `beatsUntilNext` to FeatureVector floats 35–36 in reactive mode (no offline grid installed). Bootstrap from metadata BPM via `setBootstrapBPM(_:)`.

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `BeatPredictor` class | `production-active` | MIRPipeline (reactive fallback, line 329) / 4 test files | `ARCHITECTURE.md:84`, `:423`; D-028 |
| `Result.beatPhase01` / `beatsUntilNext` | `production-active` (reactive) | Flow into FeatureVector when `liveDriftTracker.hasGrid == false` | — |
| `setBootstrapBPM(_:)` | `production-active` | Used during track-change to seed period from metadata | D-028 |

File-level docstring at `BeatPredictor.swift:1-33` correctly marks this as deprecated for grid-backed tracks and clarifies that the reactive fallback path is the live use case. **No verdict change** — it is consumed at runtime when `LiveBeatDriftTracker` has no grid.

### `BeatGrid.swift` (349 lines) — `production-active`

[`BeatGrid.swift:19`](../../PhospheneEngine/Sources/DSP/BeatGrid.swift) — Offline `Codable`/`Hashable`/`Sendable` value type representing the Beat This!-resolved grid. Methods:
- `offsetBy(_:horizon:)` — shifts grid times for live-analysis-window offsets; forward-extrapolates to a horizon to keep grid valid across long playback windows.
- `halvingOctaveCorrected()` — halving-only @ 175 BPM threshold (BUG-009, D-079).
- `localTiming(at:)` — returns (period, beatsSinceDownbeat) for arbitrary playback times.
- `nearestBeat(to:within:)` — used by LiveBeatDriftTracker for tight-match gate.
- `overridingBeatsPerBar(_:)` — Round 25 metadata-driven meter override (2026-05-15).

Widely consumed (App=6, Engine non-DSP=13, Tests=16). The most-used DSP type by consumer count.

### `BeatGridResolver.swift` (181 lines) — `production-active`

[`BeatGridResolver.swift:30`](../../PhospheneEngine/Sources/DSP/BeatGridResolver.swift) — Stateless transformer: Beat This! per-frame beat/downbeat probability arrays → `BeatGrid`. Algorithm matches the Python postprocessor reference (7-frame max-pool + threshold 0.5 + adjacent-peak dedup + ±2-frame downbeat-to-beat snap + trimmed-mean IOI BPM + median-downbeat-IOI meter detection).

Single production consumer (`BeatGridAnalyzer.swift`) + 3 test files. Doc-aligned with D-073/D-075/D-077.

### `BeatThisPreprocessor.swift` (413 lines) — `production-active`

[`BeatThisPreprocessor.swift:55`](../../PhospheneEngine/Sources/DSP/BeatThisPreprocessor.swift) — Beat This! log-mel spectrogram preprocessor (sr=22050, nFFT=1024, hop=441, nMels=128, fMin=30, fMax=11000, Slaney mel scale, `normalized="frame_length"`, `power=1`, log multiplier 1000). Zero-alloc hot path post-init; NSLock-guarded.

Consumed by `BeatGridAnalyzer` (Session module). Test surface includes `BeatThisPreprocessorTests` + `BeatThisLayerMatchTests` + `BeatThisBugRegressionTests` + `BeatThisStemReshapeTests` + `BeatThisRoPEPairingTests` + `BeatThisModelTests` + `BeatThisFixturePresenceGate`. The Python golden-test gate at every pipeline boundary is referenced in D-077 (spec-drift discipline).

### `LiveBeatDriftTracker.swift` (808 lines) — `production-active` (the BUG-007.x focal point)

[`LiveBeatDriftTracker.swift:63`](../../PhospheneEngine/Sources/DSP/LiveBeatDriftTracker.swift) — Aligns live `beatPhase01` to a cached offline `BeatGrid` via onset-matched drift tracking. Algorithm: match sub_bass onsets to cached beats within ±50 ms, EMA-update drift toward measured offset (`onsetAlpha = 0.4`), emit phase/lock state per frame. Reactive fallback (zero phase / `.unlocked`) when no grid installed.

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `LiveBeatDriftTracker` class | `production-active` | MIRPipeline (line 33) + VisualizerEngine + GridOnsetCalibrator integration + 5 test files | BUG-007.x cluster (R, .1, .2, .3-reverted, .4, .4b, .4c, .5, .6, .8, .9). |
| `update(...) -> Result` | `production-active` | Primary entry, called every frame by `MIRPipeline.buildFeatureVector` | — |
| `setGrid(_:)` / `setGrid(_:initialDriftMs:)` | `production-active` | `MIRPipeline.setBeatGrid`; the calibrated-bias overload is BUG-007.8's product | — |
| `applyCalibration(driftMs:)` | `production-active` | BUG-007.9 hybrid runtime recalibration | — |
| `overrideBeatsPerBar(_:)` | `production-active` | Round 25 (2026-05-15) metadata-driven meter override | — |
| `barPhaseOffset` | `production-active` | `Shift+B` keyboard shortcut + BUG-007.4b/4c auto-rotate | — |
| `audioOutputLatencyMs` | `production-active` | BUG-007.6: 50 ms default; `,` / `.` shortcuts adjust ±5 ms | — |
| `visualPhaseOffsetMs` | `production-active` | `[` / `]` shortcuts ±10 ms (display-only) | — |
| `diagnosticTrace` callback | `production-active` (test-only) | `LiveBeatDriftTrackerTests` (test surface) | Gated at call sites for zero overhead in production. |

The 808-line file represents months of incremental BUG-007 work and is **absent from the `DSP/` module-map block in `ARCHITECTURE.md:415-428`**. Drift correction surfaced below.

### `MIRPipeline.swift` (399 lines) — `production-active` (coordinator)

[`MIRPipeline.swift:14`](../../PhospheneEngine/Sources/DSP/MIRPipeline.swift) — Owns all eight sub-analyzers (`SpectralAnalyzer`, `BandEnergyProcessor`, `ChromaExtractor`, `BeatDetector`, `StructuralAnalyzer`, `BeatPredictor`, `LiveBeatDriftTracker`). Per-frame `process(magnitudes:fps:time:deltaTime:)` runs all analyzers, normalizes spectral features via running-max AGC (`fluxMaxDecay = 0.999`), derives MV-1 deviation primitives, picks grid-vs-predictor for beat-phase, and returns a populated `FeatureVector` for GPU upload.

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `MIRPipeline.process` | `production-active` | VisualizerEngine + SessionPreparer | Primary entry, called per audio analysis frame. |
| `setBeatGrid(_:)` / `setBeatGrid(_:initialDriftMs:)` | `production-active` | VisualizerEngine on track change | Forwards to `liveDriftTracker.setGrid`. |
| `elapsedSeconds: Double` | `production-active` | Internal — D-079 rule 5 (Double precision for long-session) | Verified at line 78. |
| `featureStability` | `production-active` | `VisualizerEngine+Audio.swift:289` (mood injection gate) | 0 → 1 ramp over 3–10 s. |
| `latestStructuralPrediction` | `production-orphan` (runtime) / `production-active` (prep time) | Sole reader: `SessionPreparer+Analysis.swift:289` at preparation time. No runtime reader. | See top-level finding. |
| `bassOnsetCount` | `production-active` | App CSV recording (`VisualizerEngine+Audio.swift:390`) | — |
| `tempoDebug` | `production-active` | Debug overlay | — |
| `onsetsPerSecond` | `production-active` | `VisualizerEngine+Audio.swift:310` | — |
| `rawSmoothedFlux` / `rawSmoothedCentroid` | `production-active` | App-side spectral normalization | — |
| `estimatedKey` / `stableKey` / `keyConfidence` / `latestMajorKeyCorrelation` / `latestMinorKeyCorrelation` | `production-active` | See ChromaExtractor row | — |
| `estimatedTempo` / `tempoConfidence` / `stableBPM` / `instantBPM` | `production-active` | Forwarded from BeatDetector; primarily internal but used in CSV recording | — |
| `spectralRolloff` | `production-orphan` (public-exposure orphan) | Zero non-DSP consumers | See field-level finding. |
| `beatPredictor`, `liveDriftTracker`, etc. (public `let`s) | `production-active` | Public refs allow VisualizerEngine to call `liveDriftTracker.barPhaseOffset` etc. | — |
| `isRecording` / `startRecording()` / `stopRecording()` | `production-active` (built-but-undocumented) | `R` keyboard shortcut | See MIRPipeline+Recording row. |

`MIRPipeline.swift:318-341` correctly implements the D-078 / DSP.2 S7 contract: prefer the offline-grid drift tracker (`liveDriftTracker.update`) when a cached grid is installed; fall back to `BeatPredictor.update` only when no grid.

### `MIRPipeline+Recording.swift` (69 lines) — `production-active` (built-but-undocumented)

[`MIRPipeline+Recording.swift:10-30`](../../PhospheneEngine/Sources/DSP/MIRPipeline+Recording.swift) — `startRecording()` / `stopRecording()` write a 1 Hz throttled CSV to `~/phosphene_features.csv`. Bound to the `R` keyboard shortcut via `VisualizerEngine+Capture.swift:18`. The CSV schema is `timestamp, track, artist, subBass, lowBass, lowMid, midHigh, highMid, high, centroid, flux, majorCorr, minorCorr, stableKey, stableBPM, valence, arousal` (17 columns).

Coexists with `SessionRecorder` which auto-writes `~/Documents/phosphene_sessions/<ts>/features.csv` (22 columns, per-frame, per `ARCHITECTURE.md:273`). The two paths have different schemas, different output paths, and different cadences. The fact that **both exist** and **what each is for** is not documented anywhere outside the `R` shortcut listing. **Doc-drift correction applied below.**

### `NoveltyDetector.swift` (287 lines) — `production-orphan` (runtime), `production-active` (prep)

[`NoveltyDetector.swift:30`](../../PhospheneEngine/Sources/DSP/NoveltyDetector.swift) — Section-boundary detector using checkerboard-kernel convolution on a self-similarity matrix. Adaptive threshold (`mean + 1.5 × stddev`), minimum-peak-distance gate (`minPeakDistance = 120` frames, ~2 s @ 60 fps). Per-frame consumer is `StructuralAnalyzer`; consumed at prep time per the top-level orphan finding.

### `SelfSimilarityMatrix.swift` (229 lines) — `production-orphan` (runtime), `production-active` (prep)

[`SelfSimilarityMatrix.swift:13`](../../PhospheneEngine/Sources/DSP/SelfSimilarityMatrix.swift) — 600-frame × 16-feature ring buffer with vDSP cosine similarity queries. Consumed only by `StructuralAnalyzer`; downstream story matches the cluster finding above.

### `StructuralAnalyzer.swift` (345 lines) — `production-orphan` (runtime), `production-active` (prep)

[`StructuralAnalyzer.swift:13`](../../PhospheneEngine/Sources/DSP/StructuralAnalyzer.swift) — Coordinator: feeds per-frame (12-chroma + 4-spectral) features into the SSM, runs novelty detection every 30 frames, predicts next boundary using duration consistency (70 %) + repetition similarity (30 %). Returns `StructuralPrediction`. Public `boundaryCount` / `boundaryTimestamps` getters; both consumed only by the prep-time `sectionCount` derivation.

### `PitchTracker.swift` (282 lines) — `production-active` (post-PT.1 fix)

[`PitchTracker.swift:43`](../../PhospheneEngine/Sources/DSP/PitchTracker.swift) — YIN-based pitch detector for separated vocals stem. **PT.1 fix (2026-05-19) confirmed landed:**
- Ring-buffer fill guard at [`PitchTracker.swift:137-139`](../../PhospheneEngine/Sources/DSP/PitchTracker.swift): `guard samplesAccumulated >= windowSize else { return (hz: 0, confidence: 0) }`.
- `appendToRingBuffer()` at [`PitchTracker.swift:178-212`](../../PhospheneEngine/Sources/DSP/PitchTracker.swift) — incremental accumulation with shift-left semantics for sub-window inputs.
- File-level fix narrative at lines 8-21 quotes verbatim: "before the fix, the live caller passed 1024-sample windows directly to YIN — `fillWindow()` zero-padded the first half of the internal buffer, making the cross-correlation in the difference function structurally zero ... so `findMinimum` always returned -1 → `(hz: 0, confidence: 0)` every frame."
- The kickoff cited PT.1 as the canonical `unverified-claim → broken` transition; this audit confirms the transition has been closed.

**Test-surface gap (not a verdict change):** `PitchTrackerTests.swift:47-87` exercises the post-2048-sample-accumulated state via full-window inputs; the production-mode incremental 1024-sample append path is not directly exercised. Live-route firing is verified empirically in real sessions (per `ENGINEERING_PLAN.md:3858`: "23.28 % (was 0 % pre-PT.1)") rather than synthetically in unit tests. Surfaced for `KNOWN_ISSUES.md` sweep below.

Tuning constants confirmed: `windowSize = 2048`, `yinThreshold = 0.15`, `confidenceThreshold = 0.6`, `emaDecay = 0.8`. Implementation note in D-028 (the "advance to local minimum before parabolic interpolation" fix) verified at [`PitchTracker.swift:259-266`](../../PhospheneEngine/Sources/DSP/PitchTracker.swift).

### `StemAnalyzer.swift` (322 lines) — `production-active`

[`StemAnalyzer.swift:46`](../../PhospheneEngine/Sources/DSP/StemAnalyzer.swift) — Per-stem analyzer. Owns four `BandEnergyProcessor` (one per stem), one `BeatDetector` on drums, one `PitchTracker` on vocals. Runs a lightweight vDSP FFT to convert mono waveforms to magnitudes (1024-point, 512 bins). Per-stem EMA rate `stemEMADecay = 0.9989` (~10 s time constant @ 94 Hz; relaxed from 0.995 after the 2026-04-17 Slint diagnosis quoted at lines 94-104).

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `StemAnalyzing` protocol | `production-active` | SessionPreparer (via DI) + tests | `ARCHITECTURE.md:428` |
| `StemAnalyzer.analyze(...)` | `production-active` | App + Session | — |
| `StemFeatures` (Shared module type) | `production-active` | Render pipeline | `ARCHITECTURE.md:646-652` |

### `StemAnalyzer+RichMetadata.swift` (169 lines) — `production-active`

[`StemAnalyzer+RichMetadata.swift:18`](../../PhospheneEngine/Sources/DSP/StemAnalyzer+RichMetadata.swift) — MV-3a/MV-3c rich metadata: per-stem `OnsetRate`, `Centroid`, `AttackRatio`, `EnergySlope` via fast/slow RMS EMAs (50 ms / 500 ms time constants) and a leaky-integrator onset accumulator (`100 ms` refractory, `0.5 s` window decay, `× 2.0` rate multiplier). The 2026-04-17 rising-edge fix (preventing 3–5 frames-per-hit double-counting) is documented in code at lines 69–76.

### `Sources/Session/GridOnsetCalibrator.swift` — `boundary-deferred` to Session subsystem audit

See top-level finding. Functionally a DSP capability; file location is in `Session/`. Tests in `GridOnsetCalibratorTests.swift` (5 instances). Production consumers: `SessionPreparer+Analysis.swift:179`, `VisualizerEngine+Stems.swift:271`.

### `Sources/Session/BeatGridAnalyzer.swift` — `boundary-deferred` to Session subsystem audit

See top-level finding. `BeatGridAnalyzing` protocol pattern matches Session's other `*-ing` testability seams (`StemAnalyzing`, `MoodClassifying`). Composes DSP + ML. Production consumers: SessionPreparer (2 sites), VisualizerEngine init + Stems runtime.

---

## Cross-references

### Updates needed in CLAUDE.md

CLAUDE.md does not contain a self-standing module map for DSP; it delegates to `ARCHITECTURE.md §Module Map` via the pointer at `CLAUDE.md:Module Map`. The drift surfaced below is in ARCHITECTURE.md, not CLAUDE.md. **No CLAUDE.md edits applied in this increment.**

### Updates needed in ARCHITECTURE.md

Applied in this increment as small, doc-only corrections:

1. **`§Module Map` DSP/ block (lines 415-428)** — add the 6 missing files:
   - `BeatGrid` — Codable value type for offline beat/downbeat grids (Beat This! output).
   - `BeatGridResolver` — Stateless transformer from Beat This! per-frame probabilities to `BeatGrid`.
   - `BeatThisPreprocessor` — Beat This! log-mel preprocessor (sr=22050, nFFT=1024, hop=441, nMels=128, Slaney).
   - `LiveBeatDriftTracker` — DSP.2 S7 onset-matched drift tracker (the BUG-007.x focal point).
   - `MIRPipeline+Recording` — `~/phosphene_features.csv` manual recording (R key); distinct from SessionRecorder.
   - `StemAnalyzer+RichMetadata` — MV-3a rich per-stem metadata computation.
2. **`§Audio Analysis Hierarchy` (lines 80-89)** — extend the "MIR pipeline components" list to mention `LiveBeatDriftTracker` (the production primary path) and `StructuralAnalyzer`. Note that `BeatPredictor` is the reactive-mode fallback for tracks without an offline `BeatGrid`.
3. **`§Chroma` (line 619)** — the "Skip bins below 65 Hz" claim does not match the code's 500 Hz floor (`ChromaExtractor.swift:55-63`). Either update the prose to 500 Hz or note the dual values (65 Hz claim may have been from an earlier iteration). Applied as a drift correction: docs updated to 500 Hz to match code, with the rationale (`46.875 Hz bin spacing causes pitch-class bias`) cited inline.
4. **`§Session Recording (Diagnostics)`** — add a one-line note that `R` keyboard shortcut triggers a separate, schema-different `~/phosphene_features.csv` recording (via `MIRPipeline+Recording`), and that this is independent of the auto-on per-session SessionRecorder path.

### Updates needed in ENGINEERING_PLAN.md

Applied:

1. **Line 446 `CAPABILITY_GAP_AUDIT.md` pointer** — corrected to reflect that the audit doc does not yet exist as a single deliverable. Point at the new `docs/CAPABILITY_REGISTRY/` tree instead, noting the per-subsystem audit increments under Phase CA. The acknowledgement at line 3724 stays as historical record.
2. Phase CA section header added under "Recently Completed" to register `CA.0` (scoping) ✅ and `CA.1` (DSP/MIR) ✅.

### Updates needed in DECISIONS.md

None. The audit verified every D-026 / D-075 / D-077 / D-078 / D-079 / D-080 / BUG-007.x claim against current code and found no contradictions. The decisions remain accurate as-written.

### New BUG entries

None filed. The PT.1 case is the only candidate, and the fix has shipped (verified at PitchTracker.swift:137-139, :178-212).

### KNOWN_ISSUES.md sweep

Applied as a minor sweep — see commit 2:

1. **PT.1 — `PitchTracker` vocals_pitch_confidence ring-buffer fix (2026-05-19)** — add a `Resolved` entry retroactively. The fix landed without filing a `BUG-` entry; per CLAUDE.md Defect Handling Protocol, every fix increment must update `KNOWN_ISSUES.md`. The narrative is recoverable from `PitchTracker.swift:8-21`, `ENGINEERING_PLAN.md:3900` (AV.2 closeout), and `DECISIONS.md:327` (D-028 implementation note). Filed as **BUG-R010** (continuing the BUG-R### numbering used for the QR.x retroactive-Resolved entries).

No Open entries reproduced as no-longer-applicable. No entries whose code surface no longer exists.

---

## Follow-up Backlog

Findings surfaced by CA.1 that are *not* corrected in this audit increment. Each row is a candidate follow-up increment with enough scope to act on cold. Per the kickoff's "audit-only" discipline, fixes do not bundle into the audit — they ship as separate increments scheduled whenever Matt prioritises them.

Items are greppable as `CA\.1-FU-\d+`. If/when CA.2+ audits land, a top-level `docs/CAPABILITY_REGISTRY/FOLLOWUPS.md` aggregator can collate across registries — defer that until there's actually overlap to collate.

| ID | Scope | Done-when | Est. sessions | Status |
|---|---|---|---|---|
| **CA.1-FU-1** | Eliminate the per-frame `StructuralAnalyzer` + `NoveltyDetector` + `SelfSimilarityMatrix` runtime-orphan chain. Two options to pick at planning time: **(a)** gate the chain in `MIRPipeline.process` so it runs at preparation time only (cheapest — preserves the existing prep-time `sectionCount` consumer at `SessionPreparer+Analysis.swift:289`); **(b)** wire `MIRPipeline.latestStructuralPrediction` into `VisualizerEngine` → orchestrator at runtime so `TransitionPolicy.structuralBoundary` triggers fire from real per-frame predictions instead of from the synthetic `StructuralPrediction` currently constructed at `SessionPlanner.swift:317` (higher leverage; more code touched). | Audio-callback hot path no longer runs SSM + novelty detection per frame, OR the orchestrator's runtime `prediction` is sourced from MIRPipeline instead of synthetically. Tests + golden sessions regenerated. Closeout cites which option (a/b) was chosen and why. | 1–2 | Ready now |
| **CA.1-FU-2** | Demote `MIRPipeline.spectralRolloff` from `public private(set) var` to `private` (or delete entirely). Zero non-DSP consumers; the underlying value still flows into `StructuralAnalyzer.SpectralSummary.rolloff` internally and that path is unchanged. Natural to bundle with FU-1 — if the StructuralAnalyzer chain is gated to prep-time only, the public field is doubly redundant. | Public exposure removed; build green; `grep -rn "spectralRolloff" PhospheneApp PhospheneEngine/Sources` returns DSP-only hits. | <1 | Ready now (natural to bundle with FU-1) |
| **CA.1-FU-3** | Trivial code-comment cleanup: `ChromaExtractor.swift:16` header docstring says "Bins below 65 Hz (C2) are skipped" but the constant at `:63` is `minFrequency = 500.0` (≈ B4). The constant is authoritative; the comment is stale. CA.1 left the code untouched per audit-only rule; this is the leftover alignment. | Header comment at `ChromaExtractor.swift:16` references 500 Hz / B4 and the rationale matches the comment at `:60-63`. | <1 | Ready now (trivial) |
| **CA.1-FU-4** | Add a `PitchTracker` regression test that exercises the **live-incremental code path** (two consecutive `process(samples:)` calls with 1024-sample inputs, ring buffer fills on the second call, YIN fires only then). Existing tests at `PitchTrackerTests.swift:47-87` pass full 2048-sample windows directly — the same test/prod parity gap that hid the PT.1 bug for ~5 months. BUG-R010 explicitly acknowledges this gap. | New test in `PitchTrackerTests` runs two consecutive `process(samples: [Float](repeating: …, count: 1024))` calls on a synthetic 440 Hz tone; asserts confidence is 0 on call 1 (ring buffer not yet full) and confidence ≥ 0.6 on call 2 (ring buffer full, YIN runs against the accumulated buffer). | 1 | Ready now |
| **CA.1-FU-5** | Relocate `Sources/Session/GridOnsetCalibrator.swift` and (probably) `Sources/Session/BeatGridAnalyzer.swift` to `Sources/DSP/`. Both are DSP capabilities by every functional criterion except file location. The `BeatGridAnalyzing` *protocol* may legitimately stay in Session (the testability-seam pattern is shared with `StemAnalyzing` / `MoodClassifying`); the `DefaultBeatGridAnalyzer` *implementation* belongs in DSP. Decide at planning time. | Files relocated; `PhospheneEngine/Package.swift` module dependencies updated; tests still pass; the Session module's dependency on DSP types narrows. | 1 | **Blocked on CA-Session audit.** The Session subsystem audit (likely CA.3+) will surface other DSP↔Session boundary work that should be bundled — moving these two files in isolation now would mean two separate Session-module touches. |

**Bundling recommendation.** FU-1 + FU-2 are natural to land in a single increment (both touch `MIRPipeline.swift`; FU-2 trivial once FU-1's structural decision is made). FU-3 is trivial enough to fold into any DSP-adjacent commit that lands in the next few weeks. FU-4 stands alone. FU-5 waits for CA-Session.

**Priority order if Matt picks just one this week:** FU-1 (the runtime orphan is real CPU on the audio-callback hot path — a one-session structural decision with measurable savings; the rest are housekeeping). FU-4 is the next-most-valuable on engineering risk grounds (one of the audit's load-bearing recommendations was that PT.1-shaped test/prod parity bugs are the failure mode worth defending against, and this test closes that specific defence for `PitchTracker`).

---

## Approach validation

**What worked.**
- The kickoff's "evidence-based, every claim cites a file:line" rule produced a tractable scope and tractable cross-references. The audit document above contains zero verdict claims that are not backed by a specific file or doc line citation.
- Splitting the 20-file inventory across four parallel Explore agents produced enough per-file detail to assign verdicts without re-reading every line myself. Synthesis (consumer counting, drift triangulation, verdict assignment) stayed in the main session.
- The "production-orphan" verdict caught one real piece of dead runtime work (the `StructuralAnalyzer` cluster) that none of the existing docs surface. This validates the audit format's premise: the registry surfaces things `ARCHITECTURE.md` and `DECISIONS.md` cannot, because they document *intent* and not *runtime consumption*.

**What didn't.**
- The "exhaustive within scope" rule produces verdict tables that lean toward `production-active` (18 of 22 files). Sections like "broken-but-claimed" and "documented-but-missing" are deliberately terse. The kickoff's "trivial-finding inflation" warning was useful — I resisted the temptation to enumerate every public method into the report; the per-file tables aggregate at the capability level (one row per logical capability, not one row per `public func`). This produces a smaller, more readable document at the cost of not having a one-row-per-symbol index.
- The kickoff anticipated `boundary-deferred` cases (DSP↔Audio, DSP↔ML, DSP↔Session) and authorized 2 of those without expanding scope. The DSP/Audio boundary turned out to be unproblematic: `FFTProcessor` lives in Audio, is consumed by DSP, and the audit didn't need to cross. The DSP/ML boundary surfaced `BeatGridAnalyzer` cleanly (it composes both modules but its file is in Session). The DSP/Session boundary is where the real `boundary-deferred` work lives (`GridOnsetCalibrator`, `BeatGridAnalyzer`); flagging both as boundary-deferred is the correct shape — relocation is a Session-audit increment, not a DSP-audit increment.
- The audit took roughly two work-passes: (1) inventory + verdict assignment, (2) doc-drift triangulation. Calling step 2 out as a distinct pass in the kickoff methodology would make the time budget more predictable for CA.2.

**Recommended changes for CA.2.**
- The verdict table at the top of the document and the per-file index do real work; the by-verdict sections (broken-but-claimed, etc.) mostly point back at the top table when verdicts are concentrated in one or two buckets. For CA.2, consider collapsing the by-verdict and per-file sections into a single annotated index when the verdict distribution is heavily `production-active`. Keep the by-verdict sections detailed only when at least one verdict bucket has 3+ findings.
- The kickoff's `production-orphan` definition allowed for "may be consumed via reflection, dispatch tables, or KVC — verify before declaring dead." For DSP, no reflection / KVC paths exist (Swift's static dispatch + no `@objc` here). For CA.2, this caveat can be tightened to "verify against `grep` of canonical type names; document the grep" — making `production-orphan` claims falsifiable.
- **Recommended next subsystem for CA.2:** ML module (`Sources/ML/`). It is the obvious next layer: DSP feeds ML (Beat This!, MoodClassifier, StemSeparator), and the BeatThis* test surface is partly in `Tests/ML/` already. CA.2 closes the DSP↔ML boundary cleanly. The Session subsystem audit then comes third, and re-evaluates the boundary-deferred `GridOnsetCalibrator` / `BeatGridAnalyzer` placements with full context.

The audit format is producing real, actionable findings without producing structure as a substitute for substance (one of the kickoff's failure modes). Recommend continuing into CA.2 without methodology changes; minor consolidations as noted.

---

*End of CA.1 — Capability Registry — DSP / MIR.*
