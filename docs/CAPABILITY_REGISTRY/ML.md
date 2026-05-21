# Capability Registry — ML

**Audit increment:** CA.2
**Date:** 2026-05-20
**Auditor:** Claude (session-driven, read-only)
**Scope:** `PhospheneEngine/Sources/ML/` — 16 Swift files, 4,507 LoC. Boundary annotations for ML↔DSP, ML↔Session, ML↔Renderer, ML↔App.
**Methodology:** [`docs/prompts/PHASE_CA_KICKOFF_CA2_ML_2026-05-20.md`](../prompts/PHASE_CA_KICKOFF_CA2_ML_2026-05-20.md).
**Reads relied on:** `CLAUDE.md`, `docs/ARCHITECTURE.md`, `docs/CAPABILITY_REGISTRY/DSP_MIR.md` (CA.1), `docs/DECISIONS.md` (D-009, D-010, D-059, D-077, D-079, D-098, D-099), `docs/QUALITY/KNOWN_ISSUES.md` (BUG-012 + race-surface analysis, BUG-013, BUG-R001–R010), `docs/ENGINEERING_PLAN.md`, `docs/diagnostics/DSP.2-architecture.md`, `docs/diagnostics/DSP.2-beatnet-archive.md`.

---

## Summary

16 files audited (BeatThis! transformer × 5, StemSeparator + StemModel + StemFFT × 9, MoodClassifier × 2, module marker × 1). The ML subsystem is structurally healthy: every capability has a real consumer; behaviour is validated by golden tests at every model boundary (`BeatThisLayerMatchTests`, `BeatThisBugRegressionTests`, `MoodClassifierGoldenTests`, `StemModelTests`, `StemFFTTests`); no runtime work has zero consumers; no `broken-but-claimed` defects in production behaviour. Three categories of findings:

| Verdict | Count | Notes |
|---|---|---|
| `production-active` | 14 files | Default verdict. All BeatThis* (5), Stem* (8 — StemSeparator, +Reconstruct, StemModel, +Graph, +Weights, StemFFT, +CPU, +GPU), MoodClassifier (2), ML.swift module marker. |
| `production-orphan` (field-level) | 4 capabilities | (a) `StemFFTEngineProtocol` (only conformer = `StemFFTEngine`; no DI consumer in production or tests). (b) `StemSeparator.stft(mono:)` + `.istft(magnitude:phase:nbFrames:originalLength:)` (public methods with zero external consumers — tests bypass the wrapper and call `fftEngine.forward/inverse` directly). (c) `BeatThisModel.numHeads` / `.headDim` / `.numBlocks` / `.ffnDim` / `.outputClasses` (public static lets with zero external consumers — `inputMels` + `embedDim` are consumed by tests, the rest are exposed for symmetry but not read). (d) Five `MoodClassifier.featureCount` / `.emaAlpha` and three error types (`BeatThisModelError`, `StemFFTError`, `StemModelError`) — declared public, thrown internally, never caught at any external call site. |
| `built-but-undocumented` | 2 large gaps | (a) The entire **Beat This! transformer** (`BeatThisModel` family, 1,748 LoC, 5 files, D-077) has no entry in `ARCHITECTURE.md §ML Inference` (lines 242–247) — that section describes only `StemSeparator` and `MoodClassifier`. (b) The `ARCHITECTURE.md` `ML/` module-map block at lines 440–447 lists 7 entries — the directory has 16 files; 9 are absent (all 5 `BeatThisModel*`, all 3 `StemFFT*`, `ML.swift`). Same shape as CA.1's DSP/ 6-of-20 drift. |
| `documented-but-missing` | 1 | `ARCHITECTURE.md §Mood Classifier Inputs` (line 636) claims "Spectral flux normalized via running-max AGC (0.999 decay)" as a mood-classifier input. The production caller (`VisualizerEngine+Audio.swift:240–249`) passes `mir.rawSmoothedFlux` — the **un-AGC-normalized** smoothed flux. `MoodClassifier.swift:14–19` confirms via its own input-vector docstring: `[7]: spectralFlux (raw sum, NOT normalized)`. The ARCHITECTURE.md prose is stale. The actual classifier-input is the value the model was trained against; no behaviour change is needed — only the doc is wrong. |
| `unverified-claim` | 0 | — |
| `boundary-deferred` | 0 (new) | `BeatGridAnalyzer` was boundary-deferred in CA.1; this audit re-confirms the deferral and adds nothing new. |
| `dead` | 0 | — |
| `stub` | 0 | `ML.swift` (4 lines) is a module marker, not a stub. |
| `broken-but-claimed` | 0 | No new BUG entries filed. **BUG-012 (Open, P1) is the active open defect in this subsystem.** It is `broken-but-claimed` in the sense that the code claims to dispatch MPSGraph safely; in practice an EXC_BAD_ACCESS has been observed once. BUG-012-i1 instrumentation (commit `23bbb825`) is already in place; step 2 (diagnosis) waits on the next reproduction. The audit does not file a new BUG entry because BUG-012 already exists. The audit's read of every BUG-012-adjacent code path produced one suggested diagnostic enrichment surfaced as `CA.2-FU-2` below; no audit edit was made to any instrumented file. |

**Highest-priority findings, ranked.**

1. **ARCHITECTURE.md gap on Beat This!** — the largest single ML capability (D-077, 4-month effort across DSP.2 S1–S9 + DSP.3.x) has no architectural narrative in the load-bearing doc. The DSP↔ML boundary is partially closed via the CA.1 update to `BeatThisPreprocessor` / `BeatGridResolver` / `LiveBeatDriftTracker`, but the ML side ("what runs *inside* `BeatThisModel`") has never made it into `ARCHITECTURE.md`. Doc-drift correction applied in this increment.
2. **`ML/` module-map drift** — 9 of 16 files absent from the canonical map. Same failure mode as CA.1's `DSP/` block (6 of 20 missing). Doc-drift correction applied.
3. **`StemFFTEngineProtocol` is dead infrastructure** — declared `public protocol`, zero conformers other than the concrete class, zero DI consumers. Either wire it up (so tests can mock `StemFFT` in `StemSeparator`) or delete it. Registered as `CA.2-FU-1`.
4. **`MoodClassifier` input-vector spec drift** — code's input contract says raw smoothed flux; `ARCHITECTURE.md` says AGC-normalized flux. The training matched the code, so the result is correct; the doc lies. Doc-drift correction applied.
5. **BUG-012 race-surface re-read** — the audit read every code path on the StemSeparator → StemFFTEngine → MPSGraph dispatch chain. No new race surfaced. The existing race-surface analysis (`KNOWN_ISSUES.md §BUG-012 race-surface analysis`) remains the most current understanding. One small diagnostic enrichment is suggested for the next instrumentation round (FU-2).

Five follow-up items are tracked in [§Follow-up Backlog](#follow-up-backlog).

---

## Findings by verdict

### broken-but-claimed (BUG entries filed)

**None filed.** BUG-012 (Open, P1) is the active defect in this subsystem; its instrumentation landed 2026-05-20 as a parallel increment (`BUG-012-i1`). The audit's read of every BUG-012-adjacent code path did not surface a new candidate root cause. No edit was made to any of the eight BUG-012-i1-instrumented files (per Hard Rules §BUG-012).

The audit's BUG-012-adjacent reads, for the record:

- `StemSeparator.swift` — `separate(...)` is the only public entry to the dispatch chain. Confirmed: `stemQueue` enqueue ordering, NSLock-guarded buffer writes, deinit instrumentation. Nothing visible to the audit contradicts the race-surface analysis.
- `StemFFT.swift` / `+GPU.swift` — `forward(mono:)` / `inverse(...)` acquire the internal NSLock before reaching `gpuForward` / `gpuInverse`. The dispatch ID is allocated once per call inside the lock and threaded into `runForwardGraph` / `runInverseGraph` via `currentDispatchID` (StemFFT.swift:354, 372). Buffer-summary log fires immediately before `MPSGraph.run`. The lock-release log fires in a `defer` after the unlock. All instrumentation is consistent with a serial-queue + lock-serialized model; no audit-visible re-entry.
- `StemModel.swift` — `predict()` is NSLock-guarded with a `defer { lock.unlock() }`. The MPSGraph dispatch is `graphBundle.graph.run(with: commandQueue, ...)`. Same single-thread-at-a-time contract as StemFFT.
- `MLDispatchScheduler` (Renderer module, boundary-noted) — the scheduler's `decide(context:)` is pure-state and does not own any resource that could be torn down. The forceDispatch fires the closure that re-enters `stemQueue` — by construction the closure executes on the serial queue and cannot overlap a prior `performStemSeparation`.

The surviving hypothesis from the race-surface analysis (teardown race during MainActor scheduler hop) is unchanged by this audit.

### documented-but-missing

1. **`ARCHITECTURE.md §Mood Classifier Inputs` — stale "AGC-normalized flux" claim.** [`docs/ARCHITECTURE.md:634-636`](../ARCHITECTURE.md): *"10 features: 6-band energy, centroid, flux, major/minor key correlations. … Spectral flux normalized via running-max AGC (0.999 decay). Centroid normalized by Nyquist (24000 Hz)."* But the production caller at [`PhospheneApp/VisualizerEngine+Audio.swift:240-249`](../../PhospheneApp/VisualizerEngine+Audio.swift) builds the 10-float vector as:
   ```swift
   let frameFeatures: [Float] = [
       fv.subBass, fv.lowBass, fv.lowMid,
       fv.midHigh, fv.highMid, fv.high,
       centroidNorm, mir.rawSmoothedFlux,   // ← raw, NOT AGC-normalized
       mir.latestMajorKeyCorrelation,
       mir.latestMinorKeyCorrelation
   ]
   ```
   `MIRPipeline.rawSmoothedFlux` ([`MIRPipeline.swift:66`](../../PhospheneEngine/Sources/DSP/MIRPipeline.swift)) is `ctx.spectral.smoothedFlux` written at line 230; `normalizedFlux` (line 161, written into FeatureVector at line 299) is a separate value the mood classifier never sees. `MoodClassifier.swift:14-19` documents this verbatim: *"[7]: spectralFlux (raw sum, NOT normalized)"*. The model was trained against raw smoothed flux per `tools/extract_mood_weights.py` (matching the docstring). **The training and the runtime path agree; the documentation is wrong.** Doc-drift correction applied in this increment. Centroid normalization claim matches code.

### unverified-claim

None this increment.

### production-orphan

Production-orphan claims at the **file** level: zero. Every file in `Sources/ML/` has at least one production consumer (the four executable targets `BeatThisActivationDumper` and `QualityReelAnalyzer` count as production code per Phase CA scope).

Production-orphan claims at the **field / type / method level**: four clusters. Each is backed by an exhaustive grep.

1. **`StemFFTEngineProtocol`** ([`StemFFT.swift:45`](../../PhospheneEngine/Sources/ML/StemFFT.swift)) — declared `public protocol`. Sole conformer: `StemFFTEngine` itself (same file, line 84). No DI seam consumes the protocol abstraction.

   **Grep:**
   ```
   $ grep -rn ": StemFFTEngineProtocol\|any StemFFTEngineProtocol\|StemFFTEngineProtocol\." \
            PhospheneApp PhospheneEngine --include="*.swift"
   PhospheneEngine/Sources/ML/StemFFT.swift:84:public final class StemFFTEngine: StemFFTEngineProtocol, @unchecked Sendable {
   ```
   One hit — the declaration of the class itself. Zero consumers expecting the protocol type. `StemSeparator.fftEngine` is typed `private let fftEngine: StemFFTEngine` (concrete class, not protocol — `StemSeparator.swift:86`). Tests construct concrete `StemFFTEngine` directly (`BUG012ConcurrencyTest.swift:49`, `StemFFTTests.swift:46`, etc.).

   **Suggested next step (out of scope for CA.2):** either wire `StemFFTEngineProtocol` through `StemSeparator` so tests can inject a mock (closes the test-only-via-`fftEngine.forward` gap noted under §production-active below) or delete the protocol entirely. Registered as `CA.2-FU-1`.

2. **`StemSeparator.stft(mono:)` + `.istft(magnitude:phase:nbFrames:originalLength:)`** ([`StemSeparator.swift:261, 281`](../../PhospheneEngine/Sources/ML/StemSeparator.swift)) — declared `public func`. Documented as the engine's externally-visible STFT pair. Both delegate to `fftEngine.forward(mono:)` / `fftEngine.inverse(...)`.

   **Grep:**
   ```
   $ grep -rn "separator\.stft\|separator\.istft\|stemSeparator\.stft\|stemSeparator\.istft" \
            PhospheneApp PhospheneEngine --include="*.swift"
   (no results)
   ```
   Zero external consumers. The wrappers exist; nothing in App, Engine non-ML, or tests calls them. The tests that need an STFT (`StemModelTests.swift:113`, `:149`) construct their own `StemFFTEngine` and call `fftEngine.forward(...)` directly, bypassing the `StemSeparator.stft` wrapper.

   **Suggested next step (out of scope for CA.2):** either delete the two wrapper methods (the engine still works via `fftEngine.forward/inverse` for internal use within `separate(...)`) or repoint the tests at the wrapper. The wrapper itself adds no useful semantic over the engine API. Registered as `CA.2-FU-3`.

3. **`BeatThisModel` model-dimension constants — partial orphan.** `BeatThisModel.inputMels` and `BeatThisModel.embedDim` are consumed by tests (`BeatThisModelTests.swift:24, 29, 38, 50, 62, 84, 97`; `BeatThisBugRegressionTests.swift:66`; `BeatThisStemReshapeTests.swift:39`) and so are production-active. The other five public static lets are not.

   **Grep:**
   ```
   $ grep -rn "BeatThisModel\.numHeads\|BeatThisModel\.headDim\|BeatThisModel\.numBlocks\|BeatThisModel\.ffnDim\|BeatThisModel\.outputClasses" \
            PhospheneApp PhospheneEngine --include="*.swift"
   (no results)
   ```
   Zero external consumers for the five remaining constants. They are exposed for documentation/symmetry — the model's hyperparameters being introspectable from outside is a reasonable design choice — but no live consumer reads them. Counterpart of CA.1's `MIRPipeline.spectralRolloff` finding.

   **Suggested next step (out of scope for CA.2):** retain as-is (low-cost public-exposure for documentation) OR move to a single `BeatThisModelDimensions` namespace and demote model-internal accesses to `internal`. Not registered as a follow-up — the cost/benefit doesn't justify a separate increment.

4. **`MoodClassifier.featureCount` (line 41) and `.emaAlpha` (line 44)** — declared `public static let`.

   **Grep:**
   ```
   $ grep -rn "MoodClassifier\.featureCount\|MoodClassifier\.emaAlpha" \
            PhospheneApp PhospheneEngine --include="*.swift"
   (no results)
   ```
   Zero external consumers. Internal-only access via `Self.featureCount` (MoodClassifier.swift:86). Same shape as the BeatThisModel-dimension finding; same recommendation (low-cost field-level orphan; not worth a dedicated increment).

5. **Error types — `BeatThisModelError`, `StemFFTError`, `StemModelError`** ([`BeatThisModel.swift:5`](../../PhospheneEngine/Sources/ML/BeatThisModel.swift), [`StemFFT.swift:70`](../../PhospheneEngine/Sources/ML/StemFFT.swift), [`StemModel.swift:26`](../../PhospheneEngine/Sources/ML/StemModel.swift)) — declared `public enum: Error, Sendable`. Thrown internally; never caught externally with type-specific matching.

   **Grep:**
   ```
   $ grep -rn "StemFFTError\." PhospheneApp PhospheneEngine --include="*.swift" \
        | grep -v "PhospheneEngine/Sources/ML/StemFFT.swift"
   (no results)

   $ grep -rn "StemModelError\." PhospheneApp PhospheneEngine --include="*.swift" \
        | grep -v "PhospheneEngine/Sources/ML/StemModel.swift"
   (no results)

   $ grep -rn "BeatThisModelError\." PhospheneApp PhospheneEngine --include="*.swift" \
        | grep -v "PhospheneEngine/Sources/ML/BeatThisModel.swift"
   (no results)
   ```
   External callers catch the parent `Error` type (e.g. `BeatGridAnalyzer.swift:77` logs `error.localizedDescription`; `StemSeparator.swift:116` wraps `StemFFT` failures into `StemSeparationError.modelLoadFailed`). The detail enums add no signal to external callers. Not worth a follow-up; cited for completeness.

### dead

None. Every public, internal, or fileprivate symbol in `Sources/ML/` has at least one live caller. The five-method nested helpers in `BeatThisModel+Frontend.swift` (`buildStemConv`, `buildPartialFTBlock`, etc.) are all consumed by `buildFrontend`. The eight helpers in `BeatThisModel+Graph.swift` are all consumed by `buildGraph`. The 161 weight-tensor accessors generated by `BeatThisModel+Weights.loadWeights()` are all consumed by the graph builders.

### stub

None. `ML.swift` (4 lines) is a module marker (`import Foundation`); not a stub.

### built-but-undocumented

1. **The entire Beat This! transformer.** `BeatThisModel` (1,748 LoC across 5 files; D-077, 2026-05-04 → DSP.2 S9, 2026-05-05) is the second-largest ML capability in Phosphene by LoC and the load-bearing offline beat-detection path. `ARCHITECTURE.md §ML Inference` (lines 242–247) describes only:
   - "Stem separator (MPSGraph): Open-Unmix HQ, Float32, 142 ms warm predict for 10 s."
   - "Mood classifier (Accelerate): 4-layer MLP (10→64→32→16→2), 3,346 hardcoded Float32 params."

   There is no architectural narrative for the Beat This! transformer in that section. The reader who hits `BeatThisModel.swift` from `BeatGridAnalyzer.swift:52` has to reconstruct the model's structure (128-dim, 4 heads, 6 blocks, 512 FFN, 1500-frame fixed window, PartialFT frontend with 3 blocks, RoPE attention with paired-adjacent rotation, manual SDPA for macOS 14 compat) from the source. CA.1 added Beat This! references on the DSP side (`BeatThisPreprocessor`, `BeatGridResolver`) but did not extend `§ML Inference` itself. **Doc-drift correction applied** — `§ML Inference` extended with a Beat This! subsection.

2. **`ML/` module-map block — 9 of 16 files absent.** [`ARCHITECTURE.md:440-447`](../ARCHITECTURE.md) lists:
   ```
   StemSeparator.swift            ✓ present
   StemSeparator+Reconstruct      ✓ present
   StemModel.swift                ✓ present
   StemModel+Graph                ✓ present
   StemModel+Weights              ✓ present
   MoodClassifier.swift           ✓ present
   MoodClassifier+Weights         ✓ present
   ```
   **Missing:**
   - `ML.swift` (module marker)
   - `BeatThisModel.swift` (inference engine — D-077)
   - `BeatThisModel+Frontend.swift` (PartialFT frontend)
   - `BeatThisModel+Graph.swift` (transformer backbone)
   - `BeatThisModel+Ops.swift` (RMSNorm / GELU / linear helpers)
   - `BeatThisModel+Weights.swift` (161 tensors / 8.4 MB loader)
   - `StemFFT.swift` (STFT/iSTFT engine — Increment 3.1a)
   - `StemFFT+CPU.swift` (vDSP fallback)
   - `StemFFT+GPU.swift` (MPSGraph path — BUG-012 crash site)

   Same failure shape as CA.1's DSP/ 6-of-20 drift; same correction applied here — module-map updated.

3. **BUG-012-i1 instrumentation surface (2026-05-20).** The instrumentation landed in 8 files (`StemFFT.swift`, `StemFFT+CPU.swift`, `StemFFT+GPU.swift`, `StemSeparator.swift`, `Shared/BUG012Probe.swift`, plus 3 App-layer / test files). The probe semantics are partially documented inline (`BUG012Probe.swift:1-26`) and in `KNOWN_ISSUES.md §BUG-012 race-surface analysis`, but the **complete BUG-012 instrumentation map** — every call site labelled with its dispatch-ID semantics — does not live anywhere yet. Surfaced below as a CA.2 doc-drift addition (small note in `KNOWN_ISSUES.md §BUG-012 → Instrumentation installed`, pointing readers at this audit doc's §BUG-012 instrumentation map).

4. **Open-Unmix HQ window-size constants.** `StemSeparator.modelFrameCount = 431`, `requiredMonoSamples = 440320`, `nFFT = 4096`, `hopLength = 1024` are the load-bearing window-shape constants for the model. `ARCHITECTURE.md §ML Inference` says "10 s audio" prose but does not state the numbers. The values appear in `ARCHITECTURE.md §Module Map` at line 441 in a different form (per the model-architecture line) but the canonical numeric values are in code only. Low-priority drift; folded into the `§ML Inference` doc-correction in this increment.

5. **`MoodClassifier.scalerMeans` / `scalerStds`** ([`MoodClassifier.swift:49-58`](../../PhospheneEngine/Sources/ML/MoodClassifier.swift)) — 20 hardcoded z-score scaler constants. The file docstring says they "MUST match `tools/data/mood_scaler.json`" — but `ARCHITECTURE.md §Mood Classifier Inputs` describes the input set, not the scaler. Code is self-documenting on this; not worth its own doc entry.

### boundary-deferred

The audit produced **no new `boundary-deferred` findings**. Boundaries touched:

- **ML ↔ DSP** — CA.1's audit covered `BeatThisPreprocessor` and `BeatGridResolver` on the DSP side. CA.2 confirms the ML-side integration is consistent: `BeatGridAnalyzer.swift:58` calls `preprocessor.process(...)` (DSP-side) → `BeatGridAnalyzer.swift:67` calls `model.predict(spectrogram:frameCount:)` (ML-side) → caller in `SessionPreparer+Analysis.swift:116` calls `analyzer.analyze(...)` which composes both. The DSP↔ML boundary is closed cleanly. Same for stems: `SessionPreparer+Analysis.swift:76` calls `separator.separate(...)` (ML-side); the mono waveforms in `separator.stemBuffers` are consumed by `analyzer.analyze(stemWaveforms:fps:)` (DSP-side, `StemAnalyzer.swift:171`).

- **ML ↔ Session** — `BeatGridAnalyzer.swift` is in `Sources/Session/`; CA.1 boundary-deferred it. This audit re-confirms the deferral. The protocol pattern (`BeatGridAnalyzing`) matches Session's other `*-ing` testability seams (`StemAnalyzing`, `MoodClassifying`, both declared in `Sources/Audio/Protocols.swift`). Recommendation when CA-Session lands: leave the protocol in Session, evaluate whether the `DefaultBeatGridAnalyzer` *implementation* belongs in ML or DSP.

- **ML ↔ Renderer** — `MLDispatchScheduler` (`Sources/Renderer/MLDispatchScheduler.swift`, D-059) reads `FrameBudgetManager.recentMaxFrameMs` and emits a `Decision` consumed by `VisualizerEngine+Stems.runStemSeparation`. CA.2 reads but does not audit `MLDispatchScheduler`. Noted for a future Renderer audit. No new boundary-deferred verdict.

- **ML ↔ App** — `VisualizerEngine+Stems.swift` orchestrates `separator.separate(...)` on `stemQueue` (utility QoS, serial); `VisualizerEngine+Audio.swift:264-292` calls `mood.classify(features:)` per analysis frame and pushes through `RenderPipeline.setMood`. CA.2 reads but does not audit `VisualizerEngine+*`. Noted for a future App audit.

### production-active

The default verdict. Aggregate counts (per-file detail in §Per-file index):

- **Beat This! transformer (5 files, 1,748 LoC, D-077):** `BeatThisModel`, `+Frontend`, `+Graph`, `+Ops`, `+Weights`. One production consumer (`Session/BeatGridAnalyzer.swift`), two production executable consumers (`BeatThisActivationDumper`, `QualityReelAnalyzer`), 6 test files exercising layer-match + bug-regression + RoPE + stem-reshape + shape/finiteness + golden behaviour.
- **Stem separator (3 files, 540 LoC, D-009 / D-010):** `StemSeparator`, `+Reconstruct`, plus `StemSeparating` protocol in Audio. Production consumers: App (`VisualizerEngine+Stems`), Session (`SessionPreparer+Analysis`). Test consumers: 8 files including the BUG-012 concurrency test.
- **Stem model (3 files, 859 LoC):** `StemModelEngine`, `+Graph`, `+Weights`. One in-module consumer (`StemSeparator.stemModel`); test surface exercises the engine directly (4 test functions in `StemModelTests`, plus the model is what `StemSeparator`'s separate(...) ends up calling).
- **Stem FFT (3 files, 896 LoC):** `StemFFTEngine`, `+CPU`, `+GPU`. One in-module consumer (`StemSeparator.fftEngine`); 3 dedicated test files (`StemFFTTests`, `BUG012ConcurrencyTest`, plus indirect via `StemModelTests`). **The GPU path is the BUG-012 crash site**; the entire file family is under BUG-012-i1 instrumentation and is off-limits to edits.
- **Mood classifier (2 files, 531 LoC, D-009):** `MoodClassifier`, `+Weights`. Production consumers: App (`VisualizerEngine+Audio.runMoodClassifier`), Session (`SessionPreparer+Analysis.analyzePreview`). Test consumers: `MoodClassifierTests`, `MoodClassifierGoldenTests`, plus `MockMoodClassifier` doublings across Session tests.
- **Module marker (1 file, 4 LoC):** `ML.swift`. Just `import Foundation`.

---

## Per-file capability index

Citations use `path:line` format. Inventory data from per-file Explore-agent reads; consumer counts from `grep -rn` of canonical type names across `PhospheneApp/`, `PhospheneEngine/Sources/`, and `PhospheneEngine/Tests/`. The audit consolidates into the per-file index per CA.2 §Consolidation-allowed (14 of 16 files concentrate on `production-active`).

### `ML.swift` (4 lines) — `production-active`

Module entry-point marker. Just `import Foundation`. No public surface. Consumed implicitly by every `import ML` (9 sites: 4 App, 2 Session, 2 executable targets, 1 InitHelpers).

### Beat This! family

#### `BeatThisModel.swift` (258 lines) — `production-active`

[`BeatThisModel.swift:39`](../../PhospheneEngine/Sources/ML/BeatThisModel.swift) — Top-level model class. `public final class BeatThisModel: @unchecked Sendable`. Owns: MPSGraph build, `BeatThisWeights` load, NSLock-guarded inference. File-level docstring at lines 1–8: *"128-dim transformer, 4 heads, 6 blocks, 512 FFN. Input: log-mel spectrogram [T, 128]. Output: beat + downbeat probabilities [T]."*

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `BeatThisModel` class | `production-active` | `Session/BeatGridAnalyzer.swift:45` (prod, 1 site) + `BeatThisActivationDumper/Dumper.swift:53` (executable, 1 site) + `QualityReelAnalyzer/QualityReelAnalyzer.swift:138` (executable, 1 site) + 5 test files | D-077 |
| `BeatThisModel.init(device:)` | `production-active` | Same 3 production sites + tests | line 75 |
| `BeatThisModel.predict(spectrogram:frameCount:)` | `production-active` | `BeatGridAnalyzer.swift:67` + `QualityReelAnalyzer.swift` + 1 test (`BeatThisModelTests:48`) | line 114 |
| `BeatThisModel.predictDiagnostic(spectrogram:frameCount:)` | `production-active` | `BeatThisActivationDumper/Dumper.swift:56` (executable) + 3 test files (`BeatThisLayerMatchTests`, `BeatThisBugRegressionTests`, `BeatThisStemReshapeTests`) | line 135. DSP.2 S8 layer-diff anchor. |
| `predictIncludingFrontendOutput(spectrogram:frameCount:)` | `production-active` (test-only) | `BeatThisModelTests.swift:25` | line 123 — internal access, no `public`. Used to verify `[frameCount, embedDim]` frontend output shape. |
| `BeatThisModel.inputMels` (= 128, public) | `production-active` | 3 test files (BeatThisModelTests, BeatThisBugRegressionTests, BeatThisStemReshapeTests) | line 48 |
| `BeatThisModel.embedDim` (= 128, public) | `production-active` | `BeatThisModelTests.swift:29` | line 43 |
| `BeatThisModel.numHeads/.headDim/.numBlocks/.ffnDim/.outputClasses` (public) | `production-orphan` (field-level) | Zero external consumers. Cited grep above. | Internal use only — graph builders read via `Self.numBlocks` etc. |
| `BeatThisModel.tMax` (= 1500, internal) | `production-active` (test-only cross-module) | `BeatThisModelTests.swift:96` (uses `@testable import`) | line 52 |
| `BeatThisModelError` enum (public) | `production-orphan` (public-exposure) | Thrown internally at 4 sites; never caught with type-specific match externally | line 5 |
| `BeatThisGraphBundle` (internal struct) | `production-active` | All graph builders + `Dumper.swift:4` (referenced in comment only — actual access is via `predictDiagnostic`'s return shape) | line 23 |
| `CorePrediction` (internal struct) | `production-active` | `predictIncludingFrontendOutput` return type | line 39 |

Tuning constants confirmed at file-level — all match the file docstring and the Python reference: `embedDim=128`, `numHeads=4`, `headDim=32`, `numBlocks=6`, `ffnDim=512`, `inputMels=128`, `outputClasses=2`, `tMax=1500` (~30 s at 50 fps, hop=441, sr=22050). BN1d pad-value computation (lines 76–79 narrative) implements PyTorch's "padding is zeros" downstream of BN1d correctly per the DSP.2 S8 root-cause analysis.

#### `BeatThisModel+Frontend.swift` (647 lines) — `production-active`

PartialFTTransformer frontend: `BN1d → Conv2d(4×3) stem → 3× PartialFTBlock → BN2d → GELU → Conv2d(2×3) downsampling → Linear projection → (tMax, 128)`. Entry point: `buildFrontend(graph:input:weights:cosTable:sinTable:name:intermediates:)`. All internal access; consumed by `buildGraph` in the sibling file.

Notable: lines 286–290 quote verbatim the DSP.2 S8 frontend-block ordering bug fix narrative (*"PyTorch frontend block ordering: partial → conv2d(in→out) → norm(out_dim) → GELU"*). Lines 593–600 document the RoPE paired-adjacent rotation contract — the same bug class as the 3D RoPE in `+Graph.swift`. Lines 121–124 document the NHWC reshape (transpose-T↔F first, then reshape) — fixing a different DSP.2 S8 root cause.

#### `BeatThisModel+Graph.swift` (444 lines) — `production-active`

MPSGraph construction: `buildGraph(weights:) → BeatThisGraphBundle`. Frontend → 6 transformer blocks → post-norm → 2-class head. Three macOS-14 workarounds documented at lines 1–8: manual RMSNorm (line 22 in `+Ops`), manual SDPA at lines 264 (scale `1/√headDim`), precomputed RoPE cos/sin tables at lines 114–142 (`base = 10000`).

Head logits computation (lines 90–95) implements the PyTorch spec's `beatLogits = col0 + col1` (downbeat counted into beat) per the reference; flagged with explicit "weird but intentional" code comment.

#### `BeatThisModel+Ops.swift` (119 lines) — `production-active`

Primitive MPSGraph helpers — all internal: `BeatLinearSpec` struct, `buildRMSNorm` (eps=1e-6, manual `x/√(mean(x²) + ε) × γ`), `buildGELU` (tanh-approximation with PyTorch constants), `buildLinear`, `makeZerosConst` / `makeOnesConst` / `makeConst`. Consumed by both `+Frontend` and `+Graph` builders.

#### `BeatThisModel+Weights.swift` (280 lines) — `production-active`

Weight loader: 161 Float32 tensors from `Sources/ML/Weights/beat_this/<name>.bin`, indexed by `manifest.json`; 8.4 MB total. `loadWeights() → BeatThisWeights` (internal static method). BN fusion at load time (lines 172–182 narrative, eps=1e-5): pre-computes `fusedScale = γ/√(σ² + ε)`, `fusedShift = β - μ × fusedScale`. Conv-weight rearrangement OIHW→HWIO at lines 211–213. All internal access; consumed by `BeatThisModel.init` via `Self.loadWeights()`.

Weight files themselves (`Sources/ML/Weights/beat_this/*.bin`) are out of scope per CA.2 §Explicit-exclusions (vendored data, not code).

### Stem separator family

#### `StemSeparator.swift` (399 lines) — `production-active`

[`StemSeparator.swift:43`](../../PhospheneEngine/Sources/ML/StemSeparator.swift) — Top-level orchestration: resample → deinterleave → STFT → MPSGraph → iSTFT → mono-average → write to UMA `stemBuffers`. `public final class StemSeparator: StemSeparating, @unchecked Sendable`. Conforms to the `StemSeparating` protocol in `Sources/Audio/Protocols.swift:105`.

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `StemSeparator` class | `production-active` | App: `VisualizerEngine+Stems.swift:30`, `VisualizerEngine.swift:225` / `:575`; Session: `SessionPreparer+Analysis.swift:76` (via `any StemSeparating`); plus 4 test files | D-009 / D-010 |
| `init(device:)` | `production-active` | App init helper; tests | line 97 |
| `separate(audio:channelCount:sampleRate:)` | `production-active` | `VisualizerEngine+Stems.swift:190`, `SessionPreparer+Analysis.swift:76`, 6 test files | line 141 |
| `stft(mono:)` / `istft(magnitude:phase:nbFrames:originalLength:)` | `production-orphan` | Zero external consumers (cited grep) | lines 261, 281. Wrapper delegating to `fftEngine.forward/inverse`. |
| `nFFT/hopLength/nBins/modelSampleRate/stemCount/modelFrameCount/requiredMonoSamples` | `production-active` | App (`VisualizerEngine.swift:234,246,250,543,546`, `VisualizerEngine+Stems.swift:220`, `VisualizerEngine+Audio.swift:205`) + tests | lines 48–63. `modelSampleRate = 44100` is the canonical literal allowed by D-079 sample-rate guard. |
| `stemLabels: [String]` (= `["vocals", "drums", "bass", "other"]`) | `production-active` | `SessionPreparer+Analysis.swift:142` (drums stem index) + tests | line 73 |
| `stemBuffers: [UMABuffer<Float>]` | `production-active` | `VisualizerEngine+Stems.swift:198`, `SessionPreparer+Analysis.swift:85`, 5 test files | line 76 |
| BUG-012-i1 instrumentation | `production-active` | `BUG012Probe.recordStemSeparatorInit/Deinit` at lines 124–126 (+ deferred ENTER/EXIT inside `separate(...)`) | Off-limits per CA.2 Hard Rules. |

The two stft/istft wrappers are the only field-level orphan in this file. Everything else is `production-active`.

#### `StemSeparator+Reconstruct.swift` (70 lines) — `production-active`

Internal extension: `reconstructStemWaveforms(allStemMagL:allStemMagR:phaseL:phaseR:nbFrames:) → [[Float]]` and `averageToMono(left:right:) → [Float]`. vDSP-vectorised (`vDSP_vadd` + `vDSP_vsmul`). Consumed by `StemSeparator.separate` on every dispatch.

#### `StemModel.swift` (246 lines) — `production-active`

[`StemModel.swift:45`](../../PhospheneEngine/Sources/ML/StemModel.swift) — MPSGraph inference engine for Open-Unmix HQ. `public final class StemModelEngine: @unchecked Sendable`. Loads 172 tensors (43/stem × 4) totalling ~136 MB at init; pre-allocated UMA I/O buffers; single MPSGraph hosts all 4 stems.

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `StemModelEngine` class | `production-active` | `StemSeparator.stemModel` at `StemSeparator.swift:68` (1 prod site, same-module) + 4 test functions in `StemModelTests` | line 45 |
| `init(device:)` | `production-active` | StemSeparator init; tests | line 105 |
| `predict()` (NSLock-guarded) | `production-active` | `StemSeparator.swift:170-180` region (within `separate`); tests directly call | line 166 |
| `inputMagLBuffer / inputMagRBuffer / outputBuffers` (public MTLBuffer) | `production-active` | StemSeparator writes inputs / reads outputs; `StemModelTests` exercises directly | lines 76, 79, 83 |
| `modelFrameCount / nBins / bandwidthBins / stemCount` (public static lets) | `production-active` | StemSeparator + `StemModelTests.swift:30, 31, 73, 74, 117, 118, 242` | lines 50–59 |
| `StemModelError` enum | `production-orphan` (public-exposure) | Thrown internally at 4 sites; no external catch | line 26 |

The class is `public` for cross-module access from `Tests/`. Its public exposure outside ML+Tests is unused — `StemSeparator` is the only production consumer and it lives in the same module. Could be `internal` if `Tests` used `@testable import ML`. Same pattern as `StemFFTEngine` below. Not a blocking finding; noted.

#### `StemModel+Graph.swift` (317 lines) — `production-active`

MPSGraph construction for one stem (replicated × 4 sharing the input placeholder): input slice → norm → FC1(2974→512) + BN1 + Tanh → 3-layer bidirectional LSTM (hidden=256) → concat → FC2(1024→512) + BN2 + ReLU → FC3(512→4098) + BN3 + denorm → ReLU(mask) × input. Architecture matches the Open-Unmix HQ reference exactly (post-3.7b weight extraction). Entry: `static func buildGraph(allWeights:) -> StemModelGraphBundle`. All internal.

`StemModelGraphBundle` and `LinearConfig` are internal structs — the agent's initial report claimed `public`; verified at source (`StemModel+Graph.swift:23, 32`) they are internal.

#### `StemModel+Weights.swift` (296 lines) — `production-active`

Weight manifest parser + raw `.bin` loader + BN fusion + bidirectional-LSTM weight assembly. `loadAllStemWeights() throws -> [StemWeights]` (internal). PyTorch → MPSGraph bidirectional-LSTM packing documented at lines 163–171 (`inputWeight [8H, I]`, `recurrentWeight [2, 4H, H]`, `bias [8H]`). BN fusion at lines 247–258 (eps=1e-5). Naïve concatenation for fwd/rev LSTM weight halves at lines 201–207; relies on the export format being correct (validated empirically by `StemModelTests`).

### Stem FFT family — under BUG-012-i1 instrumentation; READ-ONLY

#### `StemFFT.swift` (386 lines) — `production-active`

[`StemFFT.swift:84`](../../PhospheneEngine/Sources/ML/StemFFT.swift) — MPSGraph-backed STFT/iSTFT engine. `public final class StemFFTEngine: StemFFTEngineProtocol, @unchecked Sendable`. CPU vDSP fallback (`+CPU.swift`) preserved behind `forceCPUFallback` for cross-validation.

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `StemFFTEngine` class | `production-active` | `StemSeparator.fftEngine` at line 86 (1 prod, same-module) + `BUG012ConcurrencyTest:49`, `StemFFTTests:46/86/117/138/174/184`, `StemModelTests:109` | Crash site for BUG-012. |
| `StemFFTEngineProtocol` (public protocol) | **`production-orphan`** | Sole conformer = StemFFTEngine itself; zero DI consumers (cited grep above) | line 45 |
| `init(device:)` | `production-active` | StemSeparator + tests | line 171 |
| `forward(mono:)` | `production-active` | `StemSeparator.swift:262`, `StemModelTests.swift:113,114,149`, `StemFFTTests.swift:48,82,etc.`, `BUG012ConcurrencyTest:53` | line 336 |
| `inverse(...)` | `production-active` | `StemSeparator.swift:287` + `StemFFTTests.swift:95,145,152,161` | line 359 |
| `forceCPUFallback: Bool` | `production-active` (test-only) | `StemFFTTests.swift:50,54,90` (cross-validation toggle); not flipped in production | line 110 |
| `nFFT/hopLength/nBins/modelFrameCount/requiredMonoSamples` (public static lets) | `production-active` | `StemFFTTests`, `StemModelTests`, `BUG012ConcurrencyTest:53,115` | lines 89–101 |
| `StemFFTError` enum | `production-orphan` (public-exposure) | Thrown internally at 3 sites; no external catch | line 70 |
| BUG-012-i1 instrumentation | `production-active` | 13 BUG012Probe call sites (see §BUG-012 instrumentation map below) | Off-limits per Hard Rules. |

#### `StemFFT+CPU.swift` (157 lines) — `production-active`

Internal extension; `cpuForward(mono:)` and `cpuInverse(...)`. vDSP `fft_zrip` with DC/Nyquist packing. Two use cases: cross-validation (`forceCPUFallback=true`) and non-431-frame inputs (fallback in `StemFFT+GPU.swift:26, 177-179`). Consumed only inside StemFFT.

#### `StemFFT+GPU.swift` (353 lines) — `production-active`

Internal extension; `gpuForward(mono:)` / `gpuInverse(...)` + helpers. Contains the documented BUG-012 crash site at `runForwardGraph` lines 112–117 (`forwardGraph.run(with:feeds:targetOperations:resultsDictionary:)`) and the analogous inverse crash potential at lines 275–280. Both wrapped in BUG-012-i1 buffer-summary CALL/RETURN log lines (notice level), see §BUG-012 instrumentation map below.

vDSP-vs-MPSGraph amplitude convention narrative at lines 124–132 (verbatim): *"vDSP's `fft_zrip` returns twice the standard DFT across all bins (including DC and Nyquist), so we multiply MPSGraph's output by 2 before dividing by `nFFT`."*

### Mood classifier family

#### `MoodClassifier.swift` (150 lines) — `production-active`

[`MoodClassifier.swift:36`](../../PhospheneEngine/Sources/ML/MoodClassifier.swift) — `public final class MoodClassifier: MoodClassifying, @unchecked Sendable`. 4-layer MLP (10 → 64 → 32 → 16 → 2) via `vDSP_mmul` + `vDSP_vadd` + `vDSP_vmax` + `vvtanhf`. EMA smoothing (`α = 0.1`, ~0.7 s time constant at 94 Hz). Z-score scaler hardcoded.

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `MoodClassifier` class | `production-active` | App (`VisualizerEngine.swift:186, 547, 723-725`, `VisualizerEngine+Audio.swift:175, 264-265`, `VisualizerEngine+InitHelpers.swift:102, 120`) + Session (`SessionPreparer+Analysis.swift:295`) + 6 test files | D-009 |
| `init()` (no-arg) | `production-active` | App + tests | line 71 |
| `classify(features:) throws -> EmotionalState` | `production-active` | App `runMoodClassifier`; tests | line 83 |
| `currentState: EmotionalState` (public private(set)) | `production-active` | `SessionPreparer+Analysis.swift:295` (read at end of preparation); tests | line 63 |
| `featureCount` / `emaAlpha` (public static lets) | `production-orphan` (field-level) | Zero external consumers; cited grep above | lines 41, 44 |
| `scalerMeans` / `scalerStds` (private static lets) | `production-active` | Internal-only — `classify` reads | lines 49–58 |

**Architecture verified against ARCHITECTURE.md / CLAUDE.md claims:**

- `10 → 64 → 32 → 16 → 2` — confirmed at lines 98–101 (4 layer calls with explicit dimensions).
- `vDSP_mmul`, no CoreML, no MPSGraph — confirmed at lines 129, 144 (`vDSP_mmul` + `vDSP_vadd` + `vDSP_vmax` + `vvtanhf`); no `import CoreML` anywhere; no MPSGraph in this file.
- 3,346 hardcoded Float32 params — verified: 640 + 64 + 2048 + 32 + 512 + 16 + 32 + 2 = 3,346.
- Input vector — 10 floats: 6-band energy + spectralCentroid + spectralFlux + majorKey + minorKey correlations. Confirmed via the input-vector docstring at lines 14–19 and the production caller's `frameFeatures` array at `VisualizerEngine+Audio.swift:240-249`.

**Doc-drift surfaced (§documented-but-missing above):** ARCHITECTURE.md says input flux is AGC-normalized; code passes `mir.rawSmoothedFlux`. Doc-correction applied in this increment.

#### `MoodClassifier+Weights.swift` (381 lines) — `production-active`

Eight `static let` arrays (extension on `MoodClassifier`, all internal): `w0` (640) / `b0` (64) / `w1` (2048) / `b1` (32) / `w2` (512) / `b2` (16) / `w3` (32) / `b3` (2). Total 3,346 — matches the file-header claim. Extracted by `tools/extract_mood_weights.py` from a Float16 CoreML model and stored as Float32. Consumed by `MoodClassifier.classify` via `Self.w0` … `Self.b3`.

---

## BUG-012 instrumentation map

This section is the missing centralised reference noted under §built-but-undocumented finding 3. Cross-linked from `KNOWN_ISSUES.md §BUG-012` in this increment.

The instrumentation lives in 8 files; this audit's read of every probe call site is summarised below. Off-limits to edits per CA.2 Hard Rules; this is a reading aid only.

### Engine probes (in ML/StemFFT* and ML/StemSeparator)

| File | Line | Probe call | Severity | Meaning |
|---|---|---|---|---|
| `StemFFT.swift` | 214 | `BUG012Probe.recordStemFFTEngineInit()` | `.info` | "[BUG-012] StemFFTEngine init — live={count}" — engine birth marker. |
| `StemFFT.swift` | 218 | `BUG012Probe.recordStemFFTEngineDeinit()` | `.notice` | "[BUG-012] StemFFTEngine deinit — live={count} thread={label}" — engine death marker. |
| `StemFFT.swift` | 337 | `BUG012Probe.nextDispatchID()` | — | Allocate monotonic dispatch ID for the forward call. |
| `StemFFT.swift` | 338–342 | `BUG012Probe.log("fft forward await-lock", ...)` | `.info` | Before lock acquire. |
| `StemFFT.swift` | 343 | `lock.lock()` | — | Serial entry to GPU path. |
| `StemFFT.swift` | 346 | `BUG012Probe.log("fft forward lock-released", ...)` | `.info` | After `defer { lock.unlock() }`. |
| `StemFFT.swift` | 348 | `BUG012Probe.enterFFTForward(dispatchID:)` | `.info` / **ALARM** if count > 1 | Forward in-flight counter +1. |
| `StemFFT.swift` | 349 | `BUG012Probe.exitFFTForward(dispatchID:, outcome:)` | `.info` | Forward in-flight counter -1 (deferred). |
| `StemFFT.swift` | 351 | `BUG012Probe.log("fft forward path=cpu", ...)` | `.info` | If `forceCPUFallback == true`. |
| `StemFFT.swift` | 354 | `currentDispatchID = dispatchID` | — | Hand-off to GPU extension. |
| `StemFFT.swift` | 362–372 | Analogous calls for `inverse`: `nextDispatchID`, `enterFFTInverse`, `exitFFTInverse`, `currentDispatchID =` | various | Same pattern, inverse path. |
| `StemFFT+GPU.swift` | 102 | `let dispatchID = currentDispatchID` | — | Read forward dispatch ID. |
| `StemFFT+GPU.swift` | 103–111 | `BUG012Probe.notice("MPSGraph.run forward CALL", ..., detail: bug012BufferSummary(...))` | `.notice` | **Pre-crash log.** Buffer addresses + lengths + storage modes. |
| `StemFFT+GPU.swift` | 112–117 | `forwardGraph.run(...)` | — | **DOCUMENTED BUG-012 CRASH SITE** (EXC_BAD_ACCESS at 0x8). |
| `StemFFT+GPU.swift` | 118–121 | `BUG012Probe.notice("MPSGraph.run forward RETURN", ...)` | `.notice` | Post-crash log (fires on success only). |
| `StemFFT+GPU.swift` | 265–284 | Same CALL / RETURN pattern for inverse graph | `.notice` | Inverse-path twin of the forward crash site. |
| `StemSeparator.swift` | (init) | `BUG012Probe.recordStemSeparatorInit()` | `.info` | "[BUG-012] StemSeparator init — live={count}". |
| `StemSeparator.swift` | (deinit) | `BUG012Probe.recordStemSeparatorDeinit()` | `.info` | "[BUG-012] StemSeparator deinit — live={count} thread={label}". |
| `StemSeparator.swift` | (separate ENTER/EXIT) | `BUG012Probe.enterStemDispatch / .exitStemDispatch`, plus ENTER/EXIT log lines | `.info` / ALARM | In-flight counter for top-level dispatch. |

### App probes (out of scope file-locations, in scope conceptually)

`PhospheneApp/VisualizerEngine.swift` (init/deinit lifecycle), `PhospheneApp/VisualizerEngine+Stems.swift` (`runStemSeparation` timer-fire, MainActor `self?` resolution, scheduler decision, queued `performStemSeparation`, weak-self resolution log lines including the explicit `self == nil` branch), `Renderer/MLDispatchScheduler.swift` (`decide(...)` decision log). Documented in `KNOWN_ISSUES.md §BUG-012 → Instrumentation installed`.

### How the next reproduction should read

Per `KNOWN_ISSUES.md` (unchanged by this audit):

```
log show --predicate 'subsystem == "com.phosphene" AND category == "bug012"' \
         --info --last 30m | grep '[BUG-012]'
```

- Last `MPSGraph.run forward CALL id=N input=…` before crash → buffer-validity inspection.
- Any `[BUG-012][ALARM]` → serial-queue or lock contract violated.
- `VisualizerEngine deinit` near crash → teardown race.
- `stemQueue.async self=nil` → engine was already nil at queue pickup.

### Audit's reading

Every probe site is consistent with the race-surface analysis. The audit surfaced no new candidate root cause. One small diagnostic enrichment for the next reproduction is registered as `CA.2-FU-2` (see §Follow-up Backlog).

---

## Cross-references

### Updates needed in CLAUDE.md

CLAUDE.md's ML pointer (the line under §ML Inference) currently delegates to `ARCHITECTURE.md §ML Inference`. The drift surfaced below is entirely in ARCHITECTURE.md, not CLAUDE.md. **No CLAUDE.md edits applied in this increment.**

### Updates needed in ARCHITECTURE.md

Applied in this increment as doc-only corrections:

1. **`§ML Inference` (lines 242–247)** — extend with a Beat This! subsection covering: model class (`BeatThisModel`), transformer dimensions (128-dim, 4 heads, 6 blocks, 512 FFN, 1500-frame fixed window), input contract (log-mel spectrogram [T, 128] from `BeatThisPreprocessor`), output contract (per-frame beat/downbeat sigmoid probabilities consumed by `BeatGridResolver`), library / framework (MPSGraph + Accelerate, no CoreML per D-009 / D-077), and weight bundle (161 tensors / 8.4 MB / Float32, BN-fused at load). Quote the D-077 pivot rationale briefly. The `§Mood Classifier Inputs` flux-normalization claim is corrected in the same block (see #2 below).

2. **`§Mood Classifier Inputs` (line 636)** — change "Spectral flux normalized via running-max AGC (0.999 decay)" → "Spectral flux as `mir.rawSmoothedFlux` (the un-AGC-normalized smoothed flux — note that the un-normalized value, not `normalizedFlux`/`FeatureVector.spectralFlux`, is what the classifier was trained against and what the runtime path passes; see `VisualizerEngine+Audio.swift:240-249` and the `MoodClassifier.swift:14-19` input-vector docstring)."

3. **`§Module Map` ML/ block (lines 440–447)** — add the 9 missing files:
   - `ML.swift` (module marker).
   - `BeatThisModel.swift` — top-level model wrapper + public API + lock.
   - `BeatThisModel+Frontend.swift` — PartialFTTransformer frontend (stem conv + 3 frontend blocks + projection).
   - `BeatThisModel+Graph.swift` — encoder graph builder (6 transformer blocks, RoPE attention, FFN, head).
   - `BeatThisModel+Ops.swift` — RMSNorm / GELU / linear primitives (manual macOS 14 path).
   - `BeatThisModel+Weights.swift` — 161-tensor loader from bundled `.bin` files, 8.4 MB, BN-fused at load.
   - `StemFFT.swift` — `StemFFTEngine` STFT/iSTFT entry + NSLock + BUG-012-i1 instrumentation.
   - `StemFFT+CPU.swift` — vDSP fallback (cross-validation + non-431-frame inputs).
   - `StemFFT+GPU.swift` — MPSGraph forward/inverse + BUG-012 crash site at `runForwardGraph`.

### Updates needed in ENGINEERING_PLAN.md

Applied:

1. Phase CA section: register `CA.2 (ML)` as ✅ Landed under the existing Phase CA block.
2. Recently Completed: add the CA.2 entry mirroring the CA.1 shape — file count, verdict counts, top findings, doc-drift corrections applied.

### Updates needed in DECISIONS.md

None. The audit verified every D-009, D-010, D-059, D-077, D-079, D-098, D-099 claim against current code and found no contradictions.

### New BUG entries

None filed. BUG-012 already covers the active defect; no new candidate root cause was surfaced by the audit. No retroactive `Resolved` entries needed.

### KNOWN_ISSUES.md sweep

One small addition: **BUG-012 → Instrumentation installed paragraph** gets a one-line pointer to this audit doc's §BUG-012 instrumentation map for the centralised reading-aid. Applied in this increment.

---

## Follow-up Backlog

Findings surfaced by CA.2 that are *not* corrected in this audit increment. Each row is a candidate follow-up increment with enough scope to act on cold. Per the kickoff's audit-only discipline, fixes ship as separate increments scheduled whenever Matt prioritises them.

Items are greppable as `CA\.2-FU-\d+`.

| ID | Scope | Done-when | Est. sessions | Status |
|---|---|---|---|---|
| **CA.2-FU-1** | Decide the fate of `StemFFTEngineProtocol` (`StemFFT.swift:45`): either (a) wire it through `StemSeparator.fftEngine` (private let `fftEngine: any StemFFTEngineProtocol`) so tests can substitute a mock during `StemSeparator` integration tests, OR (b) delete the protocol and demote `StemFFTEngine` to a concrete-only class. The protocol exists with one conformer and no DI consumer — pick a side. **Note:** changing `StemSeparator.swift` and `StemFFT.swift` is OFF-LIMITS while BUG-012-i1 is in flight; this follow-up should wait until BUG-012 closes. | Either (a) tests have a `MockStemFFTEngine` exercising at least one `StemSeparator` integration path, OR (b) the protocol is deleted and `BUG012ConcurrencyTest`/`StemFFTTests` still pass. | <1 | **Blocked on BUG-012 closure.** |
| **CA.2-FU-2** | Add one diagnostic enrichment to BUG-012-i1 for the next reproduction: in `StemFFT+GPU.swift`'s `bug012BufferSummary()`, include a snapshot of `BUG012Probe.snapshot()` (the cross-engine live-count snapshot at lines 262–271 of `BUG012Probe.swift`) so the buffer-summary log line carries the engine-live / separator-live / FFT-in-flight counts at the moment of every `MPSGraph.run` call. This makes the pre-crash log self-sufficient — readers do not have to grep backwards for the most-recent counter state. **Off-limits while BUG-012-i1 is open** — this is a hand-off to whoever lands the next BUG-012 instrumentation tranche. | The pre-crash CALL log line includes `snapshot=...` field listing the four lifecycle counters; verified by re-running `BUG012ConcurrencyTest` and reading the captured log lines. | <1 | **Blocked on BUG-012 closure.** |
| **CA.2-FU-3** | Either delete `StemSeparator.stft(mono:)` and `StemSeparator.istft(magnitude:phase:nbFrames:originalLength:)` (`StemSeparator.swift:261, 281`) or fold them into the engine's protocol so they have at least one external caller. Today they are dead public wrappers around `fftEngine.forward/inverse`; the engine itself owns the STFT API, the wrappers add no semantic. Same BUG-012-blocked status as FU-1. | Either the two methods are deleted from `StemSeparator.swift` (build green, tests pass), OR a production caller is identified and documented in the per-file index. | <1 | **Blocked on BUG-012 closure.** |
| **CA.2-FU-4** | Trivial: demote `MoodClassifier.featureCount` and `MoodClassifier.emaAlpha` (MoodClassifier.swift:41, 44) from `public static let` to `static let` (default internal). Zero external consumers. Same for `BeatThisModel.numHeads / .headDim / .numBlocks / .ffnDim / .outputClasses` (BeatThisModel.swift:43-49) if a future increment is touching the file anyway. Skip for now — not worth its own session. | Optional bundle with any future ML-touching increment. | <1 | Ready now (low-priority — fold into an unrelated commit when convenient). |
| **CA.2-FU-5** | Audit the `MoodClassifier` golden-test surface for a known limitation: `MoodClassifierGoldenTests` validates output behaviour against 10 deterministic inputs but does not verify the production `accumulateMoodFeatures` pipeline (the App-side EMA + scaling that produces the actual 10-float vector). The classifier-as-MLP is golden-tested; the App's input-construction is not. If `tools/extract_mood_weights.py` is ever re-run or the scaler regenerated and the App side falls out of sync, the model output will silently drift. Add a small integration test exercising `accumulateMoodFeatures(fv:mir:)` against a synthetic `FeatureVector` and `MIRPipeline` snapshot and assert the 10-float vector matches the expected layout. | Test asserts: position [0..5] = 6-band energies; [6] = centroid / 24000; [7] = `mir.rawSmoothedFlux` (raw — explicit assertion, regression-locks the doc-drift correction landing in this increment); [8] = `latestMajorKeyCorrelation`; [9] = `latestMinorKeyCorrelation`. | 1 | Ready now |

**Bundling recommendation.** FU-1 / FU-2 / FU-3 are all BUG-012-blocked and natural to land in a single increment after BUG-012 closes (they all touch StemFFT / StemSeparator instrumentation surfaces). FU-4 is trivial enough to fold into any ML-touching commit. FU-5 stands alone and is the highest engineering-value follow-up of the five.

**Priority order if Matt picks just one this week:** FU-5. The other four are housekeeping on dead-but-low-cost public exposure; FU-5 closes a real test/prod parity gap of the kind CA.1 surfaced as a recurring class (the PT.1 ring-buffer bug shape — diagnostic exists for one layer of the pipeline but the production-grade end-to-end is not covered). Two of CLAUDE.md's Failed Approaches (#39, #58) and one Defect Handling Protocol rule ("Diagnostic infrastructure precedes fidelity claims") all point at this category as the failure mode most likely to bite next.

---

## Approach validation

**What worked.**

- The kickoff's "evidence-based, every claim cites file:line" rule continues to produce tractable scope. Every verdict in the per-file index above is backed by a citation or a cited grep. Production-orphan claims (5 distinct ones, four cluster-level and one field-level) all carry their grep commands inline.
- Splitting the 16-file inventory across four parallel Explore agents (BeatThis × 5 files, Stem-separator × 5 files, Stem-FFT × 3 files, Mood × 2 + ML.swift × 1) produced enough per-file material to assign verdicts without re-reading every line myself. The agents over-asserted public visibility on several internal types (`BeatThisGraphBundle`, `StemModelGraphBundle`, etc.); I caught the over-assertion via a separate visibility-pattern grep before assigning verdicts. Worth flagging for CA.3: agents reporting "public" should be cross-checked at file-level via the visibility grep.
- The CA.2-new `production-orphan` cited-grep rule fired four times and surfaced four distinct findings (`StemFFTEngineProtocol`, `StemSeparator.stft/.istft` wrappers, `BeatThisModel.numHeads/etc.`, `MoodClassifier.featureCount/.emaAlpha`). The rule had real bite — without it I'd have hand-waved on at least the two minor field-level ones.

**What didn't.**

- The `§Consolidation allowed` carve-out from the CA.2 template was tempting (14 of 16 files are `production-active`), but I kept the by-verdict and per-file sections split because four distinct production-orphan findings + two large built-but-undocumented findings + one documented-but-missing finding crossed the "at least one bucket has ≥ 3 findings" threshold. The result is longer than CA.1; whether it's better or worse is open to Matt's read.
- The Beat This! transformer's `production-active` finding has so much in it (5 files, 1,748 LoC, the entire D-077 effort) that the per-file rows are dense. I resisted the temptation to put a separate model-architecture explainer in this audit — that belongs in `ARCHITECTURE.md §ML Inference`, which is the doc-drift correction applied in this increment.
- BUG-012 was hard to handle. The kickoff said "read freely, don't modify", which I observed. But the audit's read of every BUG-012-adjacent path produced no new finding; it could have produced none and still been a valid audit pass. The §BUG-012 instrumentation map section is the audit's load-bearing contribution here: a centralised reading-aid that didn't exist before, cross-linked from `KNOWN_ISSUES.md`.

**Recommended changes for CA.3.**

- **Pre-grep visibility verification:** Explore agents reporting "public struct X" or "public class X" should have their claims cross-checked via a single visibility grep before being trusted. Three of the four Explore agents in CA.2 over-asserted publicness on internal types. A 30-second `grep -nE "^public\|^[[:space:]]*public" ` invocation against each agent's claimed-public types catches this.
- **Boundary-noted vs. boundary-deferred.** CA.1 distinguished these clearly. CA.2 used "boundary-noted" loosely for ML↔Renderer (MLDispatchScheduler) and ML↔App (VisualizerEngine+Stems / +Audio). For CA.3, recommend formalising "boundary-noted" as a separate verdict-eligible state — distinct from `boundary-deferred` (which carries a re-audit obligation when the other subsystem lands).
- **Recommended next subsystem for CA.3:** the audit-driven recommendation is **Session** (it owns `SessionPreparer`, `SessionManager`, `BeatGridAnalyzer`, `GridOnsetCalibrator`, `TrackProfile`, `CachedTrackData`, and the pre-analyzed-stem cache pipeline). The CA.1 and CA.2 audits between them flagged three boundary-deferred Session-module placements (`GridOnsetCalibrator`, `BeatGridAnalyzer`, plus the `MoodClassifier.currentState` read-at-end-of-prep pattern that CA.2 surfaced) — Session is the obvious next layer to close out before moving to Renderer / Orchestrator / App. **Alternative recommendation:** if BUG-012 reproduces in the next week and Step-2 diagnosis lands, the diagnosis may surface a different priority — defer CA.3 scope decision until that's known.

The audit format continues to produce real, actionable findings without sliding into structure-as-substance. Recommend continuing into CA.3 with the pre-grep visibility-verification tweak above and no other methodology changes.

---

*End of CA.2 — Capability Registry — ML.*
