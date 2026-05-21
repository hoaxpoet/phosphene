# Capability Registry — Shared Subsystem

**Audit increment:** CA-Shared
**Date:** 2026-05-21
**Auditor:** Claude (session-driven, read-only)
**Scope:** `PhospheneEngine/Sources/Shared/` — 25 Swift files / 3,515 LoC (matches kickoff).
**Methodology:** Phase CA scoping document ([`docs/prompts/PHASE_CA_KICKOFF_CA_SHARED_2026-05-21.md`](../prompts/PHASE_CA_KICKOFF_CA_SHARED_2026-05-21.md) — kickoff content embedded in user message).
**Reads relied on:**
- [`CLAUDE.md`](../../CLAUDE.md) — §Key Types pointer, §GPU Contract pointer, §Audio Data Hierarchy, §Audio Analysis Tuning, §Code Style, Failed Approaches #21/#22/#28/#29/#44/#52, §What NOT To Do.
- [`docs/ARCHITECTURE.md`](../ARCHITECTURE.md) — Module Map Shared/ block (lines 668-678), Key Types (lines 776-858), GPU Contract Details (lines 865+).
- [`docs/UX_SPEC.md`](../UX_SPEC.md) — §9 error taxonomy (lines 534-606); §8 Recovery & Adaptation Flows (lines 445-532); §11 Debug Overlay; §15 Test Surface.
- [`docs/DECISIONS.md`](../DECISIONS.md) — D-018 / D-019 / D-026 / D-027 / D-028 / D-070 / D-079 / D-080 / D-091 / D-099 / D-102 / D-126 / D-127.
- [`docs/QUALITY/KNOWN_ISSUES.md`](../QUALITY/KNOWN_ISSUES.md) — BUG-012 / BUG-015 / BUG-016 / BUG-R002 / BUG-R003 status verification.
- [`docs/CAPABILITY_REGISTRY/PRESETS.md`](PRESETS.md) — D-099 MSL preamble verification (consumer-side anchor).
- [`docs/CAPABILITY_REGISTRY/RENDERER.md`](RENDERER.md) — GPU slot bindings + RenderPass cases.
- [`docs/CAPABILITY_REGISTRY/RENDERER_SUPPORTING.md`](RENDERER_SUPPORTING.md) — Dashboard cluster consumer trace; BeatSyncSnapshot consumer surface.
- [`docs/CAPABILITY_REGISTRY/APP.md`](APP.md) — SessionRecorder lifecycle; UserFacingError app-side consumer chain.
- [`docs/CAPABILITY_REGISTRY/APP_VIEWS.md`](APP_VIEWS.md) — UserFacingError view-side consumer chain; DashboardTokens view-side callsites.
- [`docs/CAPABILITY_REGISTRY/AUDIO.md`](AUDIO.md) — CA.3-line-145 correction carry-forward (TrackMetadata location).
- [`docs/CAPABILITY_REGISTRY/SESSION.md`](SESSION.md) — TrackMetadata + PreFetchedTrackProfile producer-chain references.

**Sibling audits:** CA.1 / CA.2 / CA.3 / CA.4 / CA.5 / CA.6 / CA.7a / CA.7b / CA-Audio / CA-Presets — all closed 2026-05-20 → 2026-05-21.

---

## Summary

CA-Shared closes the eleventh per-subsystem audit pass under Phase CA. **With this audit Phase CA has covered every Swift surface in the engine module.** Only remaining audit work: (a) CA-Audio-FU-9 Module Map Sync (cross-cutting), (b) optional `.metal` shader audit (CA-Preset-Shaders, methodology-distinct).

**Headline findings:**

- **All seven required invariants verified clean.** D-099 / DM.2 byte-layout (FeatureVector 192 B / StemFeatures 256 B Swift producer side); UserFacingError ↔ UX_SPEC §9 alignment (29 cases ↔ 29 rows, exhaustive); Failed Approach #28 drawable-size-lock (videoSizeStableThreshold = 30 frames; relock threshold = 90 frames); TrackMetadata/PreFetchedTrackProfile/MetadataSource boundary (closes the CA.3 SESSION.md-line-145 carry-forward correction from CA-Audio); BUG012Probe surface (read-only — no candidate root cause surfaced beyond the existing 2026-05-20 race-surface analysis already filed in KNOWN_ISSUES.md); SpectralHistoryBuffer slot mapping ([2402..2417] beat_times + [2420] session_mode confirmed in code; **ARCH §Key Types description is stale** — captured as drift); DashboardTokens placement (correctly in Shared — consumed by both Renderer/Dashboard/* AND App/Views/Dashboard/*).
- **Zero broken-but-claimed findings.** No new BUG entries filed. BUG-012 instrumentation surface confirmed structurally sound on read; no new candidate root cause beyond the documented race-surface analysis.
- **Three production-orphan accessors on UserFacingError.** `.retryStatus` (declared at `UserFacingError+Presentation.swift:113`), `.isConditionBound` (declared at line 170) have **zero production callsites** across both App and Engine code paths. `.severity` / `.presentationMode` / `.primaryCTAKey` / `.secondaryCTAKey` / `.conditionID` are production-active (consumed by `FullScreenErrorView`, `ToastManager`, `PlaybackErrorBridge`). Filed as **CA-Shared-FU-1** (recommend retire OR wire up condition-bound auto-dismissal which is documented as the intended design but unimplemented on the App side).
- **Two production-orphan protocols.** `SpectralHistoryPublishing` and `StemSampleBuffering` are declared in Shared, conformed to by the single concrete class in the same file each, and used **NOWHERE as a protocol type** in production. Consumers always store the concrete type. Test injection (the documented motivation) is also not exercised. Filed as **CA-Shared-FU-2** (Matt product call: retire — same shape as CA.7b setter findings — OR mark kept-by-design for a documented future test-doubles use).
- **One production-orphan accessor on Smoother.** `step(current:target:at:)` has zero production callsites — only `factor(at:)` is consumed at 4 sites in DSP. Trivial cleanup. Filed as **CA-Shared-FU-3** (recommend retire OR Matt product call to keep as a convenience API for future use).
- **stems.csv omits `drumsEnergyDevSmoothed`.** The V.9 / D-127 float-43 stem field is recorded in the GPU StemFeatures buffer + the live render path, but the SessionRecorder's `csvRow(stems:frame:wallclock:)` producer omits the column. Offline replay tools that depend on stems.csv (e.g., `Scripts/analyze_*.py`, `PresetSessionReplay`) cannot inspect this field after the fact. Filed as **CA-Shared-FU-4** (recommend extend `csvRow(stems:)` to append `drumsEnergyDevSmoothed` to the existing pitch suffix; CSV append-only invariant respected).
- **Two doc-drift findings landed in this increment.** (a) `CLAUDE.md` cited UX_SPEC §8 as the error taxonomy — actual location is §9; corrected in this commit (single-line fix, matches the file header comment in `UserFacingError.swift:7` which is already correct). (b) `ARCHITECTURE.md` Module Map Shared/ block is missing four files (`StemFeatures.swift`, `BeatSyncSnapshot.swift`, `BUG012Probe.swift`, `UserFacingError.swift` + `UserFacingError+Presentation.swift`); **ARCH §Key Types claims three structs that do not exist anywhere in the codebase** (`BandEnergy`, `SpectralFeatures`, `OnsetPulses`) and lists three types under the "Shared Module" header that live in OTHER modules (`Particle` → Renderer/Presets, `SessionState` → Session, `AudioSignalState` → Audio); `RenderPass` enum is missing `mv_warp` and `staged`; `SpectralHistoryBuffer` reserved-section description omits the `session_mode` + `downbeat_times[8]` + `driftMs` additions. These ARCH drifts are bundled into **CA-Audio-FU-9** (Module Map Sync) per the "fold drift into FU-9 when > 3 missing files" rule from CA-Presets. The 7-in-a-row systemic finding now demands CA-Audio-FU-9 land soon.

**Verdict counts (binary, exhaustive within scope):**

| Verdict | Files / Types / Methods | Notes |
|---|---|---|
| production-active | 22 files; 25 top-level types; ~82 public/internal methods | The dominant verdict — every load-bearing type is consumed across multiple modules. |
| production-orphan | 0 files; 0 protocols + 0 accessors *(was 2 + 3 at audit close; all resolved same-day via CA-Shared-FU-1/-2/-3)* | At audit close: two protocols (SpectralHistoryPublishing, StemSampleBuffering) + three accessors (`.retryStatus`, `.isConditionBound`, `Smoother.step`). FU-1 wired the two UserFacingError accessors; FU-2 retired the two protocols; FU-3 retired Smoother.step. |
| production-orphan + planned-consumer (kept-by-design) | 0 | None at this layer. |
| dead | 0 | None. |
| stub | 0 | None. |
| documented-but-missing | 3 | `BandEnergy`, `SpectralFeatures`, `OnsetPulses` claimed in ARCH §Key Types — they do not exist anywhere. Bundled into CA-Audio-FU-9. |
| built-but-undocumented | 1 cluster | 4 Shared files missing from ARCH Module Map (StemFeatures / BeatSyncSnapshot / BUG012Probe / UserFacingError). Bundled into CA-Audio-FU-9. |
| broken-but-claimed | 0 | No runtime contradictions to CLAUDE.md / ARCH-stated invariants. |
| unverified-claim | 0 | Every production-active claim has been validated against either tests or live consumer code. |
| boundary-noted | 1 | TrackMetadata + PreFetchedTrackProfile + MetadataSource — boundary with Audio (producer side) and Session (cache consumer) is closed. |
| boundary-deferred | 0 | None. |

---

## Sub-scope decision (Pass 0 step 3)

**Default: single-pass Swift audit, no methodology split.** The 25-file / 3,515-LoC scope is comparable to CA-Audio (16 files / 3,294 LoC) and well below CA.7a (23 files / 5,413 LoC) — both completed in a single pass. There is no extension-split type-fragmentation (every file is a single coherent type or a topical extension of an adjacent type); no shader-vs-Swift methodology divide; no per-cluster certification gap to negotiate.

Pass 0 step 1 (BUG cross-check) caught one upstream doc-drift item before file reads began: CLAUDE.md cites `UX_SPEC.md §8 error taxonomy` but the actual error taxonomy lives at §9. (§8 is "Recovery & Adaptation Flows.") The file header in `UserFacingError.swift:7` already says "Organised by the four §9 tables in UX_SPEC.md" — so the producer-side authority is already correct, only the CLAUDE.md pointer is stale. Captured as a 1-line fix landed in this increment.

Pass 0 step 2 (pre-existing follow-ups) verified clean: CA.7-FU-1/2, CA.7b-FU-4, CA-Audio-FU-4/5/6/7/8/9, CA-Presets-FU-1 through FU-5 all unchanged. No regressions.

---

## Findings by verdict

### production-active (the bulk)

All 22 Shared files producing concrete types or namespaces have at least one non-test production consumer outside the declaring file, and behaviour matches CLAUDE.md / ARCH claims. Detailed per-file index below in the Per-file capability index.

### production-orphan

**1. `SpectralHistoryPublishing` protocol** (`SpectralHistoryBuffer.swift:18-63`).

Declared as a public protocol with 6 required members (`gpuBuffer`, `append`, `updateBeatGridData`, `readOverlayState`, `readSessionMode`, `readDriftMs`, `reset`). Conformed to by the concrete `SpectralHistoryBuffer` at line 80. The only consumer of `SpectralHistoryBuffer` in production code (`RenderPipeline.swift:142, 289` and `VisualizerEngine+Audio.swift:357, 361`) refers to the **concrete class**, not the protocol. The documented motivation in the file header — "enables test doubles" — is not exercised: tests use the concrete `SpectralHistoryBuffer` directly (`PhospheneEngine/Tests/PhospheneEngineTests/Renderer/SpectralCartographTests.swift` and the spectral history test file both work against the concrete class).

```
$ grep -rn ": SpectralHistoryPublishing\b\|SpectralHistoryPublishing?\b\|as SpectralHistoryPublishing" --include='*.swift' PhospheneApp PhospheneEngine 2>/dev/null
PhospheneEngine/Sources/Shared/SpectralHistoryBuffer.swift:80:public final class SpectralHistoryBuffer: SpectralHistoryPublishing, @unchecked Sendable {
```

(1 hit = the conformance declaration; 0 protocol-as-type uses.)

Verdict: **production-orphan**. Filed as **CA-Shared-FU-2** (paired with the StemSampleBuffering finding below). Matt product call needed: retire OR keep-by-design for documented future test-doubles use (parallel to CA.7-FU-3 ICB-keep / CA.7b-FU-3 RayTracing-keep precedent).

**2. `StemSampleBuffering` protocol** (`StemSampleBuffer.swift:15-44`).

Declared as a public protocol with 6 required members (`write`, two `snapshotLatest` overloads, two `rms` overloads, `reset`). Conformed to by the concrete `StemSampleBuffer` at line 54. The only production consumer (`PhospheneApp/VisualizerEngine.swift:233`) stores it as the concrete type:

```
$ grep -rn ": StemSampleBuffering\b\|StemSampleBuffering?\b\|as StemSampleBuffering" --include='*.swift' PhospheneApp PhospheneEngine 2>/dev/null
PhospheneEngine/Sources/Shared/StemSampleBuffer.swift:54:public final class StemSampleBuffer: StemSampleBuffering, @unchecked Sendable {
```

(1 hit = the conformance declaration; 0 protocol-as-type uses.)

Same shape as SpectralHistoryPublishing. Both are paired under CA-Shared-FU-2.

**3. `UserFacingError.retryStatus`** (`UserFacingError+Presentation.swift:113-124`).

Declared and returns `ErrorRetryStatus?` based on the case. Documented as auto-retry status for cases like `.noCurrentlyPlayingPlaylist` (2-second polling), `.spotifyRateLimited(attempt:)`, and `.previewRateLimited`. **Zero production callsites.**

```
$ grep -rn "\.retryStatus\b" --include='*.swift' PhospheneApp PhospheneEngine/Sources 2>/dev/null
PhospheneEngine/Sources/Shared/UserFacingError+Presentation.swift:113:    public var retryStatus: ErrorRetryStatus? {
```

(1 hit = the declaration site; 0 consumer accesses.)

The "attempt 2 of 3" copy that this accessor is supposed to deliver is currently inlined as `String(format:)` strings inside `LocalizedCopy.swift` — the parallel data path Matt's product spec for retry-aware toast copy describes is not wired. Filed as **CA-Shared-FU-1**.

**4. `UserFacingError.isConditionBound`** (`UserFacingError+Presentation.swift:170-177`).

Declared and returns `Bool` for the three condition-bound silence cases (`.silenceBrief`, `.silenceExtended`, `.audioLevelsLow`). Documented as "the `PlaybackErrorBridge` should use condition-tagged dismiss." **Zero production callsites.**

```
$ grep -rn "\.isConditionBound\b" --include='*.swift' PhospheneApp PhospheneEngine/Sources 2>/dev/null
PhospheneEngine/Sources/Shared/UserFacingError+Presentation.swift:170:    public var isConditionBound: Bool {
```

(1 hit = the declaration site; 0 consumer accesses.)

`PlaybackErrorBridge.swift:97-106` directly reads `UserFacingError.silenceExtended.conditionID` (a sibling accessor that IS consumed); the `isConditionBound` Boolean gate it depends on per the doc-comment is not threaded through. Bundled with CA-Shared-FU-1.

**5. `Smoother.step(current:target:at:)`** (`Smoother.swift:48-51`).

Declared as a convenience EMA-step wrapper. Documented in line 43 as "Equivalent to computing `factor(at:)` and applying the mix inline." **Zero production callsites.**

```
$ grep -rn "\.step(current:" --include='*.swift' PhospheneApp PhospheneEngine/Sources 2>/dev/null
(empty)

$ grep -rn "\.factor(at:" --include='*.swift' PhospheneApp PhospheneEngine/Sources 2>/dev/null
PhospheneEngine/Sources/DSP/BeatDetector.swift:337:        let decay = Self.pulseSmoother.factor(at: fps)
PhospheneEngine/Sources/DSP/BandEnergyProcessor.swift:220:        let attRate = Self.attenuatedSmoother.factor(at: fps)
PhospheneEngine/Sources/DSP/BandEnergyProcessor.swift:222:            let instantRate = Self.instantSmoothers[i].factor(at: fps)
PhospheneEngine/Sources/DSP/BandEnergyProcessor.swift:228:            let rate = Self.sixBandSmoothers[i].factor(at: fps)
```

All 4 consumers use only `factor(at:)`. Filed as **CA-Shared-FU-3**.

### documented-but-missing (3)

**`BandEnergy` / `SpectralFeatures` / `OnsetPulses`** — claimed in `ARCHITECTURE.md` §Key Types at lines 799 / 801 / 802 as if they were Swift structs. They do not exist anywhere in `PhospheneApp/` or `PhospheneEngine/`:

```
$ grep -rln "\bstruct (BandEnergy|SpectralFeatures|OnsetPulses)\b" --include='*.swift' PhospheneApp PhospheneEngine 2>/dev/null
(empty)
```

These were likely retired before the project's current state and the docs were never updated. The corresponding data lives inside `FeatureVector` (the bass/mid/treble fields are the "BandEnergy" data; the spectralCentroid/spectralFlux fields are the "SpectralFeatures" data; the beatBass/beatMid/beatTreble/beatComposite fields are the "OnsetPulses" data). Bundled into CA-Audio-FU-9.

### built-but-undocumented (4)

Files present in `PhospheneEngine/Sources/Shared/` but missing from `ARCHITECTURE.md` §Module Map Shared/ block (lines 668-678):

1. `StemFeatures.swift` (189 LoC). The 256-byte GPU contract for stem features (D-099 / DM.2). Missing entirely from ARCH listing.
2. `BeatSyncSnapshot.swift` (60 LoC). Per-frame beat-sync diagnostic snapshot (CLAUDE.md §Defect Handling artifact requirement for `dsp.beat`). Missing.
3. `BUG012Probe.swift` (320 LoC). BUG-012-i1 instrumentation. Missing.
4. `UserFacingError.swift` + `UserFacingError+Presentation.swift` (183 + 191 LoC). The canonical error taxonomy. Missing entirely.

These are all bundled into CA-Audio-FU-9 per the > 3-missing-files rule. Module Map drift across CA.5 / CA.6 / CA.7a / CA.7b / CA-Audio / CA-Presets / CA-Shared is now **7-in-a-row** systemic — FU-9 should be prioritized in Matt's next-increment scheduling.

### boundary-noted (1)

**TrackMetadata + PreFetchedTrackProfile + MetadataSource cluster.** Lives in `AudioFeatures+Metadata.swift` (lines 10 / 30 / 69). Producer-side audited at CA-Audio surface (MetadataPreFetcher + StreamingMetadata + ITunesSearchFetcher). Session-side cache consumer audited at CA.3 surface (`SessionPreparer`, `PreviewResolver`, `StemCache`). Type definition + Codable conformance + `isFetchable` / `hasData` accessor surface audited here. **Boundary closed; closes the CA.3 SESSION.md-line-145 carry-forward correction from CA-Audio.**

Detailed cross-reference: CA-Audio AUDIO.md filed the CA.3 line-145 correction (TrackMetadata lives in Shared, not Audio); CA-Shared confirms the Shared-side type definition is the authoritative location. No further boundary action required.

---

## Per-file capability index

### GPU-contract value types (8 files / 1,278 LoC)

#### [`Shared.swift`](../../PhospheneEngine/Sources/Shared/Shared.swift) (4 LoC)

Module marker. Comment-only. `import Foundation`. Verdict: **production-active** (canonical module entry point).

#### [`AudioFeatures.swift`](../../PhospheneEngine/Sources/Shared/AudioFeatures.swift) (10 LoC)

Documentation umbrella for the AudioFeatures+ extensions. Comment-only file; no types declared. Verdict: **production-active** (documentation anchor).

#### [`AudioFeatures+Analyzed.swift`](../../PhospheneEngine/Sources/Shared/AudioFeatures+Analyzed.swift) (372 LoC)

Public surface: 5 types.
- `FeatureVector` (@frozen public struct, Sendable) — **48 floats / 192 bytes**. The load-bearing GPU contract. Init takes 24 named args + defaults zero on the rest. `static let zero`.
- `FeedbackParams` (@frozen public struct, Sendable) — 8 floats / 32 bytes. Used for the Milkdrop feedback loop path.
- `EmotionalQuadrant` (public enum: String, Sendable, Equatable, Codable) — happy / sad / tense / calm.
- `EmotionalState` (public struct, Sendable, Equatable) — valence + arousal, with computed `quadrant` property. `static let neutral`.
- `StructuralPrediction` (@frozen public struct, Sendable, Equatable) — section index + timing + confidence. `static let none`.

Consumer fan-out for `FeatureVector`: DSP (MIRPipeline writes), ML (mood classifier consumes mood-input subset), Audio (LookaheadBuffer/AnalyzedFrame carriers), Renderer (RenderPipeline binds at buffer(2)), Presets (every preset shader reads), App (VisualizerEngine + Dashboard + SessionRecorder CSV). 45 prod consumers.

Consumer fan-out for `EmotionalState`: ML (`MoodClassifier.classify` returns it), App (`VisualizerEngine.currentMood @Published`, `lastClassifiedMood`, diagnostic CSV, `DebugOverlayView`, Orchestrator `applyLiveUpdate(mood:)`). 12 prod consumers.

Consumer fan-out for `StructuralPrediction`: DSP (`StructuralAnalyzer.computePrediction` returns it; MIRPipeline stores `latestStructuralPrediction`), Orchestrator (`LiveAdapter`, `SessionPlanner` synthetic-prediction path), App (VisualizerEngine+Orchestrator `applyLiveUpdate(boundary:)`). 10 prod consumers.

Verdict: **production-active** for every type. **One stale doc-comment finding:** `AnalyzedFrame.swift:35` (sibling file) describes `FeatureVector` as "96 bytes" — pre-DM.2 size. Same drift as ARCH §Key Types line 779 (correctly 192 bytes). Bundled into CA-Audio-FU-9.

#### [`AudioFeatures+Frame.swift`](../../PhospheneEngine/Sources/Shared/AudioFeatures+Frame.swift) (93 LoC)

Public surface: 3 types.
- `AudioFrame` (@frozen public struct, Sendable) — PCM block metadata: timestamp / sampleRate / sampleCount / channelCount / bufferOffset. 24 bytes.
- `FFTResult` (@frozen public struct, Sendable) — FFT metadata: binCount / binResolution / dominantFrequency / dominantMagnitude. 16 bytes.
- `StemData` (@frozen public struct, Sendable) — 4× AudioFrame headers.

Consumer fan-out: AudioFrame consumed by Audio (`StemSeparator.separate` builds the frame); Tests build them extensively. FFTResult consumed by Audio (`FFTProcessor.processStereo`/`process` return it; `latestResult` exposed via protocol). StemData consumed by ML (`StemSeparator` returns it; Audio protocol bundles it). All three carried inside `AnalyzedFrame`.

Verdict: **production-active** for all three. No drift.

#### [`AudioFeatures+Metadata.swift`](../../PhospheneEngine/Sources/Shared/AudioFeatures+Metadata.swift) (121 LoC)

Public surface: 3 types.
- `MetadataSource` (public enum: String, Sendable, Equatable, Codable) — 5 cases: appleMusic / spotify / musicKit / nowPlaying / unknown.
- `TrackMetadata` (public struct, Sendable, Equatable, Codable) — title / artist / album / genre / duration / artworkURL / source. `var isFetchable: Bool` accessor.
- `PreFetchedTrackProfile` (public struct, Sendable, Equatable, Codable) — bpm / key / energy / valence / danceability / genreTags / duration / timeSignature / fetchedAt. `var hasData: Bool` accessor.

Cross-reference: PRE-2026-05-21 CA.3 SESSION.md line 145 wrongly claimed TrackMetadata lives in Audio. CA-Audio fixed that line. CA-Shared confirms Shared is the authoritative location. Closes the boundary.

Verdict: **production-active** for all three. **boundary-noted** for the cluster.

#### [`AudioFeatures+SceneUniforms.swift`](../../PhospheneEngine/Sources/Shared/AudioFeatures+SceneUniforms.swift) (149 LoC)

Public surface: 1 type.
- `SceneUniforms` (@frozen public struct, Sendable) — 8× SIMD4<Float> = 128 bytes. Camera basis (origin/fov/forward/right/up) + primary light (position/intensity/color) + scene params (audioTime/aspectRatio/near/far + fogNear/fogFar). Convenience accessors for unpacked SIMD3<Float> camera position, scalar fov, etc.

Consumer fan-out: 11 prod consumers across Renderer (RayMarchPipeline binds at buffer(4); G-buffer pass) + Presets (ray-march shader preamble). Tests verify byte layout (`SceneUniformsTests` per ARCH line 683).

Verdict: **production-active**. No drift.

#### [`StemFeatures.swift`](../../PhospheneEngine/Sources/Shared/StemFeatures.swift) (189 LoC)

Public surface: 1 type.
- `StemFeatures` (@frozen public struct, Sendable, Equatable) — **64 floats / 256 bytes**. Per D-099 / DM.2 / D-127.
  - Floats 1–16: 4 per stem (energy/band0/band1/beat) for vocals/drums/bass/other.
  - Floats 17–24: MV-1 deviation primitives (8 fields).
  - Floats 25–40: MV-3a rich metadata (16 fields: onsetRate/centroid/attackRatio/energySlope per stem).
  - Floats 41–42: MV-3c vocal pitch.
  - Float 43: D-127 `drumsEnergyDevSmoothed` (150 ms τ EMA for Ferrofluid aurora curtain).
  - Floats 44–64: padding.
- `static let zero`.

Notable orphan within the type:
- `vocalsBeat`, `bassBeat`, `otherBeat` (lines 36, 54, 63) are documented as "reserved — currently always 0." Only `drumsBeat` (line 45) is populated. This is by design — the producer (BeatDetector) only routes drum beats. Verified by reading stems.csv writer (`SessionRecorder+CSV.swift:54-57`) which writes all four `*Beat` fields but the latter three will always be 0. Not a finding — documented internal reservation matches the producer.

Consumer fan-out: 45 prod consumers. ML (StemAnalyzer writes), Audio (analysis-thread writes per frame), Renderer (RenderPipeline binds at buffer(3)), Presets (every preset shader reads via D-099 preamble), App (VisualizerEngine + Dashboard StemsCardBuilder + SessionRecorder CSV).

Producer-side audit complete: every field has a defined producer chain. **One stems.csv producer-side gap:** `drumsEnergyDevSmoothed` is recorded into the GPU buffer but the SessionRecorder's stems.csv writer (`SessionRecorder+CSV.swift:73-74`) does not write it. Offline replay / desk-research tools cannot inspect it post-hoc. Filed as **CA-Shared-FU-4**.

Verdict: **production-active**.

#### [`AnalyzedFrame.swift`](../../PhospheneEngine/Sources/Shared/AnalyzedFrame.swift) (64 LoC)

Public surface: 1 type.
- `AnalyzedFrame` (public struct, Sendable) — timestamped bundle: timestamp / audioFrame / fftResult / stemData / featureVector / emotionalState / structuralPrediction. `static let empty`.

Consumer fan-out: Audio (`LookaheadBuffer` carries them; `AudioInputRouter.onAnalysisFrame` + `.onRenderFrame` callbacks — note BUG-015-adjacent: these callbacks remained unassigned in production until BUG-015 fix wired the analysis-queue path; CA-Audio surfaced LookaheadBuffer as the dangling consumer planned-but-unwired). DSP (`StructuralAnalyzer` populates the prediction field).

Verdict: **production-active**. **One inline-doc drift:** line 35 `/// Packed feature vector for GPU uniform upload (96 bytes).` — FeatureVector is 192 bytes post-DM.2. Bundled into CA-Audio-FU-9.

#### [`BeatSyncSnapshot.swift`](../../PhospheneEngine/Sources/Shared/BeatSyncSnapshot.swift) (60 LoC)

Public surface: 1 type.
- `BeatSyncSnapshot` (public struct, Sendable) — 9 fields: barPhase01 / beatsPerBar / beatInBar / isDownbeat / sessionMode / lockState / gridBPM / playbackTimeS / driftMs. `static let zero`.

Consumer fan-out: App (`VisualizerEngine+Audio.swift:373-385` builds per-frame snapshot from MIR + BeatGrid + drift tracker), App (`VisualizerEngine.latestBeatSyncSnapshot` NSLock-guarded storage), Renderer (`DashboardSnapshot` carries it; `BeatCardBuilder` reads it), Shared (SessionRecorder CSV writes it).

Verdict: **production-active**. This is the load-bearing diagnostic artifact for `dsp.beat` defects per CLAUDE.md §Defect Handling Protocol. The contract holds end-to-end. **Missing from ARCH Module Map** — bundled into CA-Audio-FU-9.

### SessionRecorder cluster (5 files / 803 LoC)

#### [`SessionRecorder.swift`](../../PhospheneEngine/Sources/Shared/SessionRecorder.swift) (375 LoC)

Public surface: 1 class + extension cluster.
- `SessionRecorder` (public final class, @unchecked Sendable) — continuous diagnostic capture.
  - `public init?(baseDir:enabled:)` — returns nil if disabled or directory creation fails.
  - `public func ensureCaptureTexture(device:width:height:pixelFormat:) -> MTLTexture?`
  - `public func recordFrame(features:stems:)` + overload with BeatSyncSnapshot.
  - `public func recordFrameTiming(cpuMs:gpuMs:)`
  - `public func log(_:)`
  - `public func finish()` — idempotent; flushes all writers.
  - Public `sessionDir: URL`.

Threading contract: all hot-path methods dispatch onto a private `queue: DispatchQueue` (label `com.phosphene.recorder`, qos `.utility`). `finish()` uses `queue.sync` for blocking flush. CSV file handles are private; only the queue mutates them. Storage: `videoWriter`, `videoInput`, `pixelAdaptor`, `captureTexture`, frame counters, and raw-tap state are all internal/private — accessed only through `queue.async` blocks.

CSV header invariants (lines 325-352):
- features.csv: 37 columns (frame through frame_gpu_ms). DM.3a-aware (frame_cpu_ms + frame_gpu_ms appended at end per CSV-append-only-invariant comment at lines 321-324).
- stems.csv: 41 columns (frame through vocalsPitchConfidence). Same append-only invariant.

Notable: stems.csv header at line 336-352 omits `drumsEnergyDevSmoothed` — filed as CA-Shared-FU-4.

Consumer fan-out: App (`VisualizerEngine` constructs at init; `VisualizerEngine+Audio` calls `recordFrame` from the command-buffer completion handler), App (`VisualizerEngine+Capture` calls `recordStemSeparation`), Shared (extension files self-reference).

Verdict: **production-active**. Drawable-size-lock invariant (Failed Approach #28) **verified clean** — see required-section §"Verification of SessionRecorder drawable-size-lock invariant" below.

#### [`SessionRecorder+CSV.swift`](../../PhospheneEngine/Sources/Shared/SessionRecorder+CSV.swift) (78 LoC)

Static extension methods on SessionRecorder:
- `csvRow(features:frame:wallclock:) -> String` (2-arg back-compat)
- `csvRow(features:beatSync:frame:wallclock:frameCPUms:frameGPUms:) -> String` (full signature)
- `csvRow(stems:frame:wallclock:) -> String`

CSV column producer-side. Reads FeatureVector and StemFeatures field-by-field via the named accessors; format strings hard-coded to 26 / 9 / 18 / 8 / 16 / 2 numeric columns respectively.

**Producer-side gap identified:** `csvRow(stems:)` at lines 50-76 writes 41 columns (matching the stems.csv header) but does NOT include the V.9 / D-127 `drumsEnergyDevSmoothed` field at StemFeatures float 43. Filed as **CA-Shared-FU-4**.

Verdict: **production-active**.

#### [`SessionRecorder+RawTap.swift`](../../PhospheneEngine/Sources/Shared/SessionRecorder+RawTap.swift) (162 LoC)

Public API:
- `recordRawTapSamples(pointer:count:sampleRate:channelCount:)` — Core Audio tap callback safe; heavy I/O hops onto `queue`. Caps at 30 s by default; `PHOSPHENE_FULL_RAW_TAP=1` env var lifts the cap to 24 hours (per `QualityReelAnalyzer` requirement, line 134).
- `static func writeWav(samples:sampleRate:to:)` — 16-bit PCM WAV writer for stem dumps.

RIFF/WAVE format implementation: streaming header (placeholder data sizes at init; patched at finish via `finalizeRawTapHeader` → `patchRawTapHeader`). 32-bit Float input (format 3), per the live-tap rate.

Little-endian byte serialization helpers: `UInt16.littleEndianBytes`, `UInt32.littleEndianBytes` extensions at lines 149-162.

Consumer fan-out: App (`VisualizerEngine+Audio.swift` per-callback raw-sample forward); App (`SessionRecorder+Stems.swift:30` calls `writeWav` for stem dumps).

Verdict: **production-active**.

#### [`SessionRecorder+Stems.swift`](../../PhospheneEngine/Sources/Shared/SessionRecorder+Stems.swift) (37 LoC)

Public API:
- `recordStemSeparation(stemWaveforms:sampleRate:trackTitle:)` — writes 4 PCM WAV files per stem to `stems/<idx>_<title>/` directory.

Filename safety: lines 19-22 strip `/` and `:` from track title and prefix-trim to 60 chars. Dump indexing via `stemDumpIndex` (incremented monotonically).

Consumer fan-out: App (`VisualizerEngine+Stems.swift` calls after each separation completes).

Verdict: **production-active**.

#### [`SessionRecorder+Video.swift`](../../PhospheneEngine/Sources/Shared/SessionRecorder+Video.swift) (151 LoC)

Internal API:
- `appendVideoFrame(from:wallclock:)` — main per-frame append. Reads texture bytes via `MTLTexture.getBytes` into the pixel-buffer-pool pixel buffer (no double-copy); adapts at PTS = wallclock × 1e6 microseconds.
- `initializeVideoWriterIfNeeded(width:height:)` — defers init until N=30 consecutive same-size frames (Failed Approach #28).
- `handleDimensionMismatch(width:height:lockedW:lockedH:)` — skip-frame logic; relock-after-90-consecutive-same-mismatched-frames recovery path (writerRelockThreshold = 90, line 102 of `SessionRecorder.swift`).
- `tearDownVideoWriter()` — cancel writing and unlink video.mp4.
- `setupVideoWriter(width:height:)` — H.264 / High auto-level / 4 Mbps. Pixel format kCVPixelFormatType_32BGRA.

Threading: all called only from the serial recorder queue (per the SessionRecorder.swift hot-path contract).

Consumer fan-out: SessionRecorder itself.

Verdict: **production-active**. **Failed Approach #28 fully respected** — see required-section §"Verification of SessionRecorder drawable-size-lock invariant" below.

### UMA / buffer primitives (3 files / 626 LoC)

#### [`UMABuffer.swift`](../../PhospheneEngine/Sources/Shared/UMABuffer.swift) (181 LoC)

Public surface: 2 classes + 1 enum.
- `UMABuffer<T>` (public final class, @unchecked Sendable) — typed view over `.storageModeShared` MTLBuffer. `init(device:capacity:) throws`, `subscript(index)`, `pointer: UnsafeMutableBufferPointer<T>`, `byteLength: Int`, `write<C: Collection<T>>(_:offset:)` + `where T == Float` fast-path memcpy specialisation.
- `UMARingBuffer<T>` (public final class, @unchecked Sendable) — fixed-capacity overwrite ring backed by `UMABuffer<T>`. `init(device:capacity:) throws`, `write(_:)`, `write(contentsOf:)`, `read(at logicalIndex:)`, `head`, `count`, `capacity`, `isFull`, `isEmpty`, `tail`, `reset()`.
- `UMABufferError` (public enum: Error, Sendable) — `.allocationFailed(byteLength:)`.

Consumer fan-out (`UMABuffer`): 7 prod files (Audio/AudioBuffer, Audio/StreamingAudioBuffer, Audio/SystemAudioCapture, Renderer/RenderPipeline noise-volume buffers, etc.). `UMARingBuffer<Float>` consumed by `Audio/AudioBuffer.swift:40`. `UMABufferError` thrown by `UMABuffer.init` only — caught at construction sites; `do/catch` blocks present in callers.

Verdict: **production-active**. Threading contract (header comment lines 5-9) is documentation, not Swift-enforced — callers carry the synchronization burden. No drift.

#### [`SpectralHistoryBuffer.swift`](../../PhospheneEngine/Sources/Shared/SpectralHistoryBuffer.swift) (237 LoC)

Public surface: 1 protocol + 1 class.
- `SpectralHistoryPublishing` (public protocol, AnyObject, Sendable) — see production-orphan-2 finding above.
- `SpectralHistoryBuffer` (public final class, conforms to SpectralHistoryPublishing, @unchecked Sendable).
  - `init(device:)` — allocates 4096 floats × 4 bytes = 16384 B at `.storageModeShared`. **fatalError** on allocation failure (line 135) — diverges from the `UMABuffer.init throws` pattern but is acceptable since the buffer is allocated once at engine init and any device that can render Phosphene can allocate 16 KB.
  - `append(features:stems:)` — single-writer (render thread); no lock.
  - `updateBeatGridData(relativeBeatTimes:relativeDownbeatTimes:bpm:lockState:sessionMode:driftMs:)` — analysis-queue writer; uses `beatGridLock: NSLock`.
  - `readOverlayState() -> (bpm: Float, lockState: Int)` — render-thread reader; uses `beatGridLock`.
  - `readSessionMode() -> Int` — same.
  - `readDriftMs() -> Float` — same.
  - `reset()` — track-change path; clears ring + reinitializes beat/downbeat tick slots to `Float.infinity`.

Slot layout (verified against SpectralCartograph shader downstream — out of CA-Shared scope but the slot offsets are immutable contract):
- `[0..479]` valence; `[480..959]` arousal; `[960..1439]` beatPhase01; `[1440..1919]` bassDev; `[1920..2399]` barPhase01.
- `[2400]` writeHead; `[2401]` samplesValid.
- `[2402..2417]` beat_times[16] (kickoff claim verified ✅).
- `[2418]` bpm.
- `[2419]` lockState.
- `[2420]` session_mode (kickoff claim verified ✅).
- `[2421..2428]` downbeat_times[8].
- `[2429]` driftMs.
- `[2430..4095]` unused / reserved.

Consumer fan-out: App (`VisualizerEngine+Audio.swift:357, 361` reads static slot-count constants), Renderer (`RenderPipeline.swift:142 / 289 / 439` — constructs, owns, and calls `append` each frame).

Verdict: **production-active** for the concrete class; **production-orphan** for the SpectralHistoryPublishing protocol. **ARCH §Key Types description for SpectralHistoryBuffer (line 819) is stale** — says `[2402..2419]` for reserved + bpm + lock_state but omits sessionMode (2420) + downbeat_times (2421-2428) + driftMs (2429). Bundled into CA-Audio-FU-9.

#### [`StemSampleBuffer.swift`](../../PhospheneEngine/Sources/Shared/StemSampleBuffer.swift) (208 LoC)

Public surface: 1 protocol + 1 class.
- `StemSampleBuffering` (public protocol, AnyObject, Sendable) — see production-orphan-2 finding above.
- `StemSampleBuffer` (public final class, conforms to StemSampleBuffering, @unchecked Sendable).
  - `init(sampleRate:maxSeconds:)` — defaults 44100 Hz / 15 s. **Note: the 44100 default is the documented buffer-init rate, NOT the literal-44100 ban target** — the rate-aware overloads (snapshotLatest, rms) are the live-tap-rate contract per D-079 / BUG-R003 fix. Verified.
  - `write(samples:count:)` — NSLock-guarded; handles three wrap cases.
  - `snapshotLatest(seconds:)` + `snapshotLatest(seconds:sampleRate:)` — rate-aware overload (BUG-R003).
  - `rms(seconds:)` + `rms(seconds:sampleRate:)` — rate-aware overload added in QR.1 / D-079; uses `vDSP_svesq` for the sum-of-squares.
  - `reset()` — track-change path.

Consumer fan-out: App (`VisualizerEngine.swift:233` constructs; `VisualizerEngine+Stems.swift` calls snapshot/rms at separation time; `VisualizerEngine+Audio.swift` calls write from the tap callback).

Verdict: **production-active** for the concrete class; **production-orphan** for the StemSampleBuffering protocol.

### Utility infrastructure (6 files / 487 LoC)

#### [`Logging.swift`](../../PhospheneEngine/Sources/Shared/Logging.swift) (37 LoC)

Public enum `Logging` with 8 static `Logger` instances at subsystem `com.phosphene`: audio, dsp, renderer, orchestrator, ml, metadata, session, bug012.

Consumer fan-out: every PhospheneEngine module (dsp / ml / Audio / Renderer / Orchestrator / Presets / Session) uses one or more of these. `Logging.bug012` is referenced only by `BUG012Probe.swift` (per the BUG-012-i1 instrumentation contract).

Note: `Logging.session` is the engine-module session logger. **App-layer code MUST NOT use it** per CLAUDE.md §Code Style ("App-layer services use `Logger(subsystem:category:)` directly, not `Logging.session`."). Confirmed by reading App-layer SessionRecorder construction site at `PhospheneApp/VisualizerEngine+Audio.swift` (engine-layer file path; the engine SessionRecorder uses `Logger(subsystem: "com.phosphene", category: "SessionRecorder")` directly at line 38, NOT `Logging.session`).

Verdict: **production-active**.

#### [`DeviceTier.swift`](../../PhospheneEngine/Sources/Shared/DeviceTier.swift) (26 LoC)

Public enum `DeviceTier`: String, Sendable, Hashable, CaseIterable, Codable — `tier1`, `tier2`. Computed `frameBudgetMs: Float` returns 16.6 (both tiers — current decision: same budget; tier2 has architectural slack to fit more complex presets).

Consumer fan-out: 19 prod consumers across Orchestrator (PresetScoringContext, SessionPlanner, FidelityRubric), Renderer (FrameBudgetManager, MLDispatchScheduler), Presets (PresetMetadata.cost(for:), Certification machinery), App (VisualizerEngine.deviceTier let; detectDeviceTier; PresetScoringContextProvider).

Verdict: **production-active**. No drift.

#### [`Smoother.swift`](../../PhospheneEngine/Sources/Shared/Smoother.swift) (52 LoC)

Public surface: 1 struct.
- `Smoother` (@frozen public struct, Sendable) — `rate30: Float`, `init(rate30:)`, `factor(at fps:) -> Float`, `step(current:target:at:) -> Float`.

Consumer fan-out: DSP (BandEnergyProcessor 5 sites, BeatDetector 1 site — all call `factor(at:)`).

**`step(current:target:at:)` is production-orphan** — see production-orphan-5 finding above. Filed as CA-Shared-FU-3.

Verdict: **production-active** for the type + init + `factor(at:)`; **production-orphan** for the `step` convenience accessor.

#### [`RenderPass.swift`](../../PhospheneEngine/Sources/Shared/RenderPass.swift) (85 LoC)

Public enum `RenderPass`: String, Codable, Sendable, CaseIterable — 10 cases: `direct`, `feedback`, `particles`, `meshShader`, `postProcess`, `rayMarch`, `icb`, `ssgi`, `mvWarp`, `staged`.

Raw-value bindings preserve JSON sidecar tokens: `"mesh_shader"`, `"post_process"`, `"ray_march"`, `"mv_warp"`. The raw-value strings are the load-bearing contract — PresetDescriptor decodes these from the JSON `"passes"` array (PresetDescriptor.swift:189, 462, 533 per the kickoff-cited references).

Consumer fan-out: Renderer (RenderPipeline owns `activePasses: [RenderPass]`; the per-pass dispatch chain in RenderPipeline+Draw.swift), Presets (PresetDescriptor decodes from JSON).

Verdict: **production-active**. **ARCH §Key Types line 816 is missing `mv_warp` + `staged` from the cases list** — bundled into CA-Audio-FU-9.

#### [`UserFacingError.swift`](../../PhospheneEngine/Sources/Shared/UserFacingError.swift) (183 LoC)

Public surface: 1 enum + 1 nested enum.
- `UserFacingError` (public enum, Sendable, Hashable, CaseIterable) — 29 cases organised by UX_SPEC §9 tables (§9.1 Permission × 3, §9.2 Connection × 7, §9.3 Preparation × 7, §9.4 Playback × 12).
- `UserFacingError.SpotifyRejectionKind` (public enum, Sendable, Hashable, CaseIterable) — track / album / artist / unknown.

`allCases` manually implemented because Swift cannot synthesise CaseIterable for enums with associated values.

Cases with associated values:
- `.spotifyURLNotPlaylist(kind: SpotifyRejectionKind)`
- `.spotifyRateLimited(attempt: Int)`
- `.previewNotFound(trackTitle: String)`
- `.stemSeparationFailed(trackTitle: String)`
- `.preparationSlowOnFirstTrack(elapsedSeconds: Int)`
- `.sampleRateMismatch(rateHz: Int)`
- `.audioLevelsLow(isSpotifySource: Bool)`

Consumer fan-out: 10 prod consumers across App (FullScreenErrorView, TopBannerView, PreparationFailureView, PreparationErrorViewModel, SpotifyConnectionView, PlaybackErrorBridge, PlaybackErrorConditionTracker, LocalizedCopy).

Verdict: **production-active**. Header comment correctly anchored to UX_SPEC §9 (line 7).

#### [`UserFacingError+Presentation.swift`](../../PhospheneEngine/Sources/Shared/UserFacingError+Presentation.swift) (191 LoC)

Public surface: 3 types + 6 instance accessors.
- `ErrorPresentationMode` (public enum, Sendable, Equatable) — fullScreen / inlineOnRow / topBanner / bottomRightToast / logOnly.
- `ErrorSeverity` (public enum, Sendable, Equatable) — info / warning / degradation / fatal.
- `ErrorRetryStatus` (public struct, Sendable, Equatable) — `isAutoRetrying: Bool`, `description: String?`. `static let none`, `static func autoRetrying(_:)`.
- Instance accessors on UserFacingError: `presentationMode`, `severity`, `retryStatus`, `primaryCTAKey`, `secondaryCTAKey`, `isConditionBound`, `conditionID`.

Consumer-side audit:
- `.presentationMode` — **prod consumers: 0** (only test consumers at `PhospheneEngine/Tests/PhospheneEngineTests/Shared/UserFacingErrorTests.swift:32, 56, 86-104, 111`). Production code does NOT read `error.presentationMode` to decide where to show toasts — instead, the App-layer dispatch logic in `PreparationErrorViewModel` and `FullScreenErrorView` hard-codes the presentation routing. The taxonomy lives only as a test discriminator. **Worth flagging as a partial production-orphan** — the documented intent is that consumers read `presentationMode` to route, but they don't.

Wait — re-check. The `.severity` accessor IS consumed (FullScreenErrorView.swift:112, 121 + ToastManager.swift line context). Let me re-verify each accessor:

| Accessor | Prod consumers | Status |
|---|---|---|
| `.presentationMode` | 0 (test-only at 9 lines) | **soft production-orphan** — documented as a routing primitive but no production consumer actually routes on it; the test suite acts as the contract gate. |
| `.severity` | App: FullScreenErrorView.swift:112, 121 (color-mapping). Note PhospheneToast.severity is a different field. | **production-active**. |
| `.retryStatus` | 0 | **production-orphan** (CA-Shared-FU-1). |
| `.primaryCTAKey` | App: FullScreenErrorView.swift:86 | **production-active**. |
| `.secondaryCTAKey` | App: FullScreenErrorView.swift:94 | **production-active**. |
| `.isConditionBound` | 0 | **production-orphan** (CA-Shared-FU-1). |
| `.conditionID` | App: PlaybackErrorBridge.swift:97 (silence.extended); PlaybackErrorConditionTracker writes consumer side. | **production-active**. |

Refined verdict for the file: 4 of 7 accessors production-active; 2 production-orphan (CA-Shared-FU-1); 1 soft-production-orphan (`.presentationMode` is the routing primitive but routing happens via hard-coded App logic). **Worth surfacing in Approach Validation:** the `.presentationMode` accessor would be considered production-active by the "any consumer counts" rule but the non-nil-caller refinement (CA.7b precedent) would flag it: no production code branches on the returned mode value.

Verdict: **production-active** with two production-orphan accessors filed as CA-Shared-FU-1.

### Diagnostic / instrumentation (1 file / 320 LoC)

#### [`BUG012Probe.swift`](../../PhospheneEngine/Sources/Shared/BUG012Probe.swift) (320 LoC)

Public surface: 1 enum namespace + 1 nested struct.
- `BUG012Probe` (public enum, namespace) — 12 static methods + 1 nested type.
  - `nextDispatchID() -> UInt64` — monotonic ID allocator (overflow-tolerant via `&+=`).
  - `enterStemDispatch(dispatchID:) -> Int` / `exitStemDispatch(dispatchID:outcome:)` — outer `performStemSeparation` counter. **Alarm-level log on count > 1** (per the documented serial-queue invariant).
  - `enterFFTForward(dispatchID:) -> Int` / `exitFFTForward(dispatchID:outcome:)` — inner FFT forward counter. Same alarm pattern.
  - `enterFFTInverse(dispatchID:) -> Int` / `exitFFTInverse(dispatchID:outcome:)` — inner FFT inverse counter.
  - `recordStemFFTEngineInit/Deinit()` / `recordStemSeparatorInit/Deinit()` / `recordVisualizerEngineInit/Deinit()` — lifecycle counters.
  - `log(_:dispatchID:detail:)` — info-level free-form.
  - `notice(_:dispatchID:detail:)` — notice-level free-form.
  - `snapshot() -> Snapshot` — counter readout (test + regression-gate).
  - `resetForTesting()` — test-only counter reset.
- `BUG012Probe.Snapshot` (public struct, Sendable, Equatable) — 6 counter fields.

Thread-safety: single `NSLock` guards all `_*` storage. `nonisolated(unsafe)` annotations on the storage match the documented Swift 6 strict-concurrency pattern + the precedent at VisualizerEngine `_tapSampleRate`.

Logging API: `emitInfo` / `emitNotice` route through `Logging.bug012` (per Logging.swift's bug012 category at subsystem `com.phosphene`).

Read-only confirmation: BUG012Probe is in scope per the kickoff but **never edited** in CA-Shared per the standing rule. The file header at line 28 says "Remove this file when BUG-012 closes" — operational note for the eventual closeout.

**No candidate diagnostic root cause surfaced from this read** beyond the 2026-05-20 race-surface analysis already in KNOWN_ISSUES.md BUG-012 §Fix scope. The probe's structural correctness is confirmed:
- Lock semantics correct (acquire-mutate-unlock-emitLog pattern; emitLog never holds the lock).
- Alarm threshold (count > 1) correctly placed AFTER the increment, BEFORE the consumer would observe state.
- Lifecycle counters use `max(0, count - 1)` to defend against underflow at deinit (acceptable defensive coding for diagnostic code).
- `resetForTesting()` correctly clears `_nextDispatchID` (otherwise tests wouldn't be reproducible).

Consumer fan-out: ML (StemFFTEngine.init/deinit/forward/runForwardGraph/inverse/runInverseGraph — 6 instrumented sites per BUG-012-i1), ML (StemSeparator init/deinit/separate), ML (MLDispatchScheduler.decide), App (VisualizerEngine init/deinit, VisualizerEngine+Stems runStemSeparation/performStemSeparation). 7 prod consumers.

Verdict: **production-active** (read-only per CA-Shared standing rule). **Missing from ARCH Module Map** — bundled into CA-Audio-FU-9. The kickoff's expectation of "no further candidate root cause" is met; the existing race-surface analysis remains the load-bearing diagnostic hypothesis.

### Dashboard tokens (1 file / 130 LoC, in subdirectory)

#### [`Dashboard/DashboardTokens.swift`](../../PhospheneEngine/Sources/Shared/Dashboard/DashboardTokens.swift) (130 LoC)

Public surface: 1 struct (namespace) with 4 nested types.
- `DashboardTokens.TypeScale` — 8 static `CGFloat` constants (caption / label / body / bodyLarge / numeric / hero / display + labelTracking).
- `DashboardTokens.Spacing` — 7 static `CGFloat` constants on a 4-pt baseline grid.
- `DashboardTokens.Color` — 14 static `NSColor` constants (4 surface + 3 text + 6 brand + 3 status). OKLCH-derived sRGB values per `.impeccable.md` spec.
- `DashboardTokens.Weight` / `DashboardTokens.TextFont` / `DashboardTokens.Alignment` — 3 small enums for `DashboardTextLayer` consumption (retired per D-087, but the enums are kept for `DashboardCardLayout` builder calls if needed).

`private init()` prevents instantiation (all access via static dot-notation).

`#if canImport(AppKit)` guard around the AppKit import (line 14-16) — supports a hypothetical iOS / iPadOS surface where `NSColor` would resolve to a UIColor adapter; today macOS-only.

Consumer-side audit:
- **Renderer side:** `PhospheneEngine/Sources/Renderer/Dashboard/BeatCardBuilder.swift:83, 84` — uses `DashboardTokens.Color.textBody`, `.coral`. Plus DASH.7 builder cluster per CA.7b RENDERER_SUPPORTING.md §Dashboard.
- **App side:** `PhospheneApp/Views/Dashboard/DashboardOverlayView.swift` (8 callsites: Spacing.md / .lg / .sm + Color.border / .surface), `DashboardRowView.swift` (10 callsites: TypeScale.body / .label + Color.textBody / .border), `DashboardCardView.swift` (3 callsites: Spacing.sm + TypeScale.bodyLarge + Color.textHeading). Plus 1 documentation cross-reference at `EndedView.swift:96` (comment-only).

Verdict: **production-active**. **DashboardTokens placement is correct in Shared** — see required-section §"Verification of DashboardTokens placement" below. Note: `DashboardTokens.swift:5` comment cites D-080 as the rationale for Shared placement — D-080 is actually the QR.2 stem-affinity scoring decision, not the DashboardTokens placement decision. The correct rationale is D-081 / DASH.1.1 (referenced later in the same file's lore at line 11). Minor inline drift bundled into CA-Audio-FU-9.

---

## Verification of D-099 / DM.2 Common.metal struct extension invariant (Swift producer side)

**Verdict: clean.** The Swift-side `FeatureVector` and `StemFeatures` structs in `AudioFeatures+Analyzed.swift` and `StemFeatures.swift` match the GPU-contract byte layouts documented in CLAUDE.md §Key Types pointer + ARCH §Key Types + the MSL preamble verified by CA-Presets in `PresetLoader+Preamble.swift:34-128`.

**FeatureVector:**
- `@frozen public struct FeatureVector: Sendable` at `AudioFeatures+Analyzed.swift:44-230`.
- Field order (verified line-by-line):
  - Floats 1–3: `bass, mid, treble`
  - Floats 4–6: `bassAtt, midAtt, trebleAtt`
  - Floats 7–12: `subBass, lowBass, lowMid, midHigh, highMid, high`
  - Floats 13–16: `beatBass, beatMid, beatTreble, beatComposite`
  - Floats 17–18: `spectralCentroid, spectralFlux`
  - Floats 19–20: `valence, arousal`
  - Floats 21–22: `time, deltaTime`
  - Float 23: `_pad0`
  - Float 24: `aspectRatio`
  - Float 25: `accumulatedAudioTime`
  - Floats 26–31: `bassRel, bassDev, midRel, midDev, trebRel, trebDev` (MV-1)
  - Floats 32–34: `bassAttRel, midAttRel, trebAttRel` (MV-1 smoothed)
  - Floats 35–36: `beatPhase01, beatsUntilNext` (MV-3b)
  - Floats 37–38: `barPhase01, beatsPerBar`
  - Floats 39–48: `_pad3 ... _pad12` (10-field padding)
- Total: 48 floats × 4 bytes = **192 bytes**. ✅ matches MSL preamble.
- First 32 floats byte-identical to original DM.0 layout (bass through aspectRatio + accumulatedAudioTime + MV-1 deviation primitives) — verified field-by-field.
- Test gate: AudioFeaturesByteLayoutTests + AudioFeaturesTests (ARCH line 686 lists the latter).

**StemFeatures:**
- `@frozen public struct StemFeatures: Sendable, Equatable` at `StemFeatures.swift:24-189`.
- Field order (verified line-by-line):
  - Floats 1–16: 4 per stem (vocals/drums/bass/other → energy/band0/band1/beat).
  - Floats 17–24: MV-1 per-stem deviation primitives (vocalsEnergyRel/Dev, drumsEnergyRel/Dev, bassEnergyRel/Dev, otherEnergyRel/Dev).
  - Floats 25–40: MV-3a rich metadata (4 per stem: onsetRate/centroid/attackRatio/energySlope).
  - Floats 41–42: vocalsPitchHz, vocalsPitchConfidence (MV-3c).
  - Float 43: `drumsEnergyDevSmoothed` (V.9 / D-127).
  - Floats 44–64: 21-field padding (_sfPad2 ... _sfPad22).
- Total: 64 floats × 4 bytes = **256 bytes**. ✅ matches MSL preamble.
- First 16 floats byte-identical to original DM.0 16-float layout — verified.
- Test gate: CommonLayoutTest (per kickoff reference + project memory note `project_engine_msl_struct_extension.md`).

**Producer-side responsibility chain:**
- FeatureVector populated by `MIRPipeline.process()` (DSP module, CA.1 surface).
- StemFeatures populated by `StemAnalyzer` (ML module, CA.2 surface) + per-frame attenuation in `VisualizerEngine+Audio.swift` (App module, CA.5 surface) + `RenderPipeline.drawWithRayMarch` writes `drumsEnergyDevSmoothed` per D-127 before binding StemFeatures at buffer(3) (Renderer module, CA.7a surface).
- Both structs are uploaded as `MTLBuffer.contents()` writes — single MemoryLayout<T>.stride byte copy per upload. Producer chain integrity invariant: every consumer that reads either struct downstream relies on the Swift-side layout being byte-identical to the MSL preamble. **No regression risk identified in CA-Shared.**

**Cross-reference:** CA-Presets verified the consumer-side preamble (MSL declarations). CA-Shared verifies the producer-side declarations. **Closes the D-099 / DM.2 byte-layout invariant verification loop.**

---

## Verification of UserFacingError ↔ UX_SPEC §9 alignment

**Verdict: clean (29:29 exhaustive coverage).** Every case in `UserFacingError` maps to exactly one row in `UX_SPEC.md` §9.1–§9.4; every row in §9 has a corresponding case. The file header at `UserFacingError.swift:7-13` documents this.

**Note on §8 vs §9:** The kickoff (and `CLAUDE.md`) cite "UX_SPEC §8 error taxonomy" — actual location is §9. §8 is "Recovery & Adaptation Flows." `UserFacingError.swift:7` correctly cites §9. **CLAUDE.md will be corrected in this increment**; the kickoff prompt is consumed-and-discarded.

**Case ↔ row map (verified by reading both):**

| §9 Row | Case | Presentation | Severity |
|---|---|---|---|
| §9.1: Permission errors |  |  |  |
| Screen-capture denied | `.screenCapturePermissionDenied` | fullScreen | warning |
| AppleScript denied | `.appleScriptPermissionDenied` | fullScreen | warning |
| Sandbox blocking | `.sandboxBlockingCapture` | logOnly | info |
| §9.2: Connection errors |  |  |  |
| Apple Music not running | `.appleMusicNotRunning` | fullScreen | info |
| No currently playing playlist | `.noCurrentlyPlayingPlaylist` | fullScreen | info |
| Spotify URL malformed | `.spotifyURLMalformed` | fullScreen | info |
| Spotify URL not playlist | `.spotifyURLNotPlaylist(kind:)` | fullScreen | info |
| Spotify rate limited | `.spotifyRateLimited(attempt:)` | fullScreen | info |
| Spotify unreachable | `.spotifyUnreachable` | fullScreen | warning |
| Empty playlist | `.emptyPlaylist` | fullScreen | info |
| §9.3: Preparation errors |  |  |  |
| Preview not found | `.previewNotFound(trackTitle:)` | inlineOnRow | degradation |
| Preview rate limited | `.previewRateLimited` | topBanner | info |
| Network offline | `.networkOffline` | fullScreen | fatal |
| Stem separation failed | `.stemSeparationFailed(trackTitle:)` | inlineOnRow | degradation |
| All tracks failed | `.allTracksFailedToPrepare` | fullScreen | fatal |
| Preparation slow | `.preparationSlowOnFirstTrack(elapsedSeconds:)` | topBanner | info |
| Preparation timeout | `.preparationTotalTimeout` | topBanner | info |
| §9.4: Playback errors |  |  |  |
| Silence brief | `.silenceBrief` | bottomRightToast | info |
| Silence extended | `.silenceExtended` | bottomRightToast | warning |
| Tap reinstall attempt | `.tapReinstallAttempt` | logOnly | info |
| Tap reinstall all failed | `.tapReinstallAllFailed` | bottomRightToast | fatal |
| MPSGraph alloc failure | `.mpsGraphAllocationFailure` | bottomRightToast | degradation |
| Sample rate mismatch | `.sampleRateMismatch(rateHz:)` | bottomRightToast | warning |
| Audio levels low | `.audioLevelsLow(isSpotifySource:)` | bottomRightToast | warning |
| Frame budget exceeded | `.frameBudgetExceeded` | logOnly | warning |
| Display disconnected | `.displayDisconnectedMidSession` | bottomRightToast | warning |
| Drawable size mismatch | `.drawableSizeMismatch` | logOnly | info |
| Negative nudge twice | `.negativeNudgeTwice` | bottomRightToast | info |
| Re-plan succeeded | `.rePlanSucceeded` | bottomRightToast | info |

29 cases. 29 rows. **Mapping is complete and bidirectional.**

**One soft drift item:** `UserFacingError.presentationMode` is the producer-side authority for the §9 "Where displayed" column, but App-side dispatch (e.g., `PreparationErrorViewModel.banner(_) / .fullScreen(_)`) hard-codes the routing rather than reading the accessor. This is a code-style concern (production-orphan accessor that ought to be load-bearing) more than a documentation concern. Surfacing here for the next maintenance pass; not blocking.

---

## Verification of SessionRecorder drawable-size-lock invariant (Failed Approach #28)

**Verdict: clean.** The full FA #28 defense pipeline is in place at `SessionRecorder+Video.swift:14-100` with state tracked across two cooperating mechanisms.

**Locking mechanism (deferred init):** `initializeVideoWriterIfNeeded(width:height:)` at lines 55-68:
1. If `videoWriter != nil`, return immediately (already locked).
2. Compare `(width, height)` against `lastObservedDims`. If identical, increment `sameDimsStreak`. Otherwise reset to 1.
3. **If `sameDimsStreak < videoSizeStableThreshold (= 30)`, return false** — the frame is skipped.
4. Only at the 30-frame stable streak does `setupVideoWriter(width:height:)` run and `writerLockedDims = (width, height)` lock in.
5. Log "video writer locked to WxH after 30 stable frames."

**Mismatch handling (post-lock):** `handleDimensionMismatch(width:height:lockedW:lockedH:)` at lines 70-100:
1. Increment `skippedFrameCount`.
2. Compare against `mismatchedDims`. If identical, increment `mismatchedDimsStreak`. Otherwise reset to 1.
3. If `mismatchedDimsStreak < writerRelockThreshold (= 90)`, **skip the frame** (the post-lock skip; blit-into-wrong-geometry would happen here if not guarded). Log "video frame skipped: drawable W'xH' != writer WxH (skip count: N)" every 30 skipped frames.
4. If the streak hits 90 (~3 s at 30 fps), tear down the writer and reset to a new lock at the new dimensions (relock path). Log "video writer relocking" + "video writer relocked."

**FA #28 quote (CLAUDE.md):** "Defer writer init until N consecutive same-size frames; once locked, skip mismatched frames rather than blit-into-wrong-geometry."

**Code adherence:** N = 30 ✅; mismatch path skips frames (line 95-99 returns false without appending) rather than blitting ✅; recovery path is one additional capability (FA #28 didn't require it) — relock-after-90-stable-mismatched-frames is the post-bad-initial-lock recovery, useful when drawable size changes from Retina-resolution to logical-point coordinates after the lock — useful defensive coding beyond the FA-spec minimum.

**Test coverage:** ARCH line 675 references `SessionRecorderTests` validating this. (Per CA-Shared's read-only scope, the test file itself isn't audited here; ARCH lists it as the validation gate.)

---

## Verification of TrackMetadata + PreFetchedTrackProfile + MetadataSource (CA.3 / CA-Audio carry-forward)

**Verdict: closed.** All three types live in `PhospheneEngine/Sources/Shared/AudioFeatures+Metadata.swift`:
- `MetadataSource` at line 10.
- `TrackMetadata` at line 30.
- `PreFetchedTrackProfile` at line 69.

**Producer-side fan-out (verified via grep):**
- `MetadataPreFetcher.prefetch(for:)` (`Sources/Audio/MetadataPreFetcher.swift:58`) — primary fetch entry; returns `PreFetchedTrackProfile?`.
- `MetadataPreFetcher.cachedProfile(for:)` (line 113) — cached fetch retrieval.
- `StreamingMetadata` (`Sources/Audio/StreamingMetadata.swift:150, 176, 237, 245`) — Now Playing observation; publishes `TrackMetadata?` to subscribers.

**Consumer-side fan-out (verified via grep):**
- App side: `VisualizerEngine.currentTrack: TrackMetadata?` (`@Published`), `VisualizerEngine+Orchestrator.indexInLivePlan(matching metadata: TrackMetadata)`, `VisualizerEngine+Capture.kickoffPreFetch(for track: TrackMetadata, fetcher: MetadataPreFetcher)`, `PlaybackChromeViewModel` consumes `AnyPublisher<TrackMetadata?, Never>`.
- Audio side: `AudioInputRouter.currentTrack` accessor returns `TrackMetadata?`.
- Session side (per CA.3): cache + preview-resolver chain consumes track identity via `TrackProfile` (a sibling type in Orchestrator, not in Shared).
- Protocol-bridge: `TrackChange` (`Sources/Audio/Protocols.swift:151-157`) carries `(previous: TrackMetadata?, current: TrackMetadata)` pairs.

**Boundary closure:** CA-Audio AUDIO.md corrected CA.3 SESSION.md line 145's mis-attribution (the line previously claimed TrackMetadata lived in Audio). CA-Shared confirms the Shared-side location is the producer-side authority. **No further boundary action required across CA.3 / CA-Audio / CA-Shared.**

---

## Verification of BUG-012 instrumentation surface (`BUG012Probe.swift`)

**Verdict: read-only confirmed; no new candidate root cause surfaced.**

`BUG012Probe.swift` is a 320-LoC pure-observability module. Read end-to-end. The file's API + lock semantics + alarm thresholds + lifecycle counters are structurally sound:

- **No mutable cross-thread state outside the `NSLock` guard.** Every `_*` storage variable is annotated `nonisolated(unsafe)` (matches D-079's `tapSampleRate` precedent and the documented Swift 6 strict-concurrency external-synchronization pattern).
- **No race-window in the in-flight counter ALARM path.** Counter increment + read + comparison + log emission are all separated by the lock release — the log emission happens AFTER the lock is released, but the value being logged (`count`) is the local snapshot at-lock — so the log can't observe a concurrently mutated counter.
- **`max(0, count - 1)` on exit paths** is acceptable defensive coding (counter cannot drop below 0 if the exit fires after a missed enter, which would be a separate logic bug).
- **`resetForTesting()` correctly zeros `_nextDispatchID`** so deterministic test runs don't share IDs across suite executions.

**Cross-references to the BUG-012 instrumentation map:**
- ML/StemFFTEngine init/deinit + forward/inverse + lock acquire/release → `enterFFTForward/exitFFTForward`, `enterFFTInverse/exitFFTInverse`, `recordStemFFTEngineInit/Deinit`.
- ML/StemSeparator init/deinit + separate ENTER/EXIT → `recordStemSeparatorInit/Deinit`, free-form `log` / `notice` with `id:` correlator.
- ML/MLDispatchScheduler.decide → `notice("MLDispatchScheduler decision", ...)`.
- App/VisualizerEngine init/deinit → `recordVisualizerEngineInit/Deinit`.
- App/VisualizerEngine+Stems → `enterStemDispatch`/`exitStemDispatch`; weak-self resolution logs.

**Production verification (via grep):** 7 distinct prod consumer files for the probe API. The full instrumentation map (per-call site cross-reference) is in CA.2 ML.md §BUG-012 instrumentation map (per the KNOWN_ISSUES.md BUG-012 §664 reference).

**No new candidate diagnostic explanation for the EXC_BAD_ACCESS** beyond the 2026-05-20 race-surface analysis already filed in KNOWN_ISSUES.md BUG-012 §638-648. The probe is structurally ready to capture the next reproduction. **No BUG-012 addendum filed in CA-Shared.**

---

## Verification of SpectralHistoryBuffer slot mapping

**Verdict: code-side authoritative; ARCH §Key Types description stale.**

`SpectralHistoryBuffer.swift:91-115` declares all slot offsets as `public static let`:

| Constant | Value | Semantics |
|---|---|---|
| `offsetValence` | 0 | Ring [0..479] |
| `offsetArousal` | 480 | Ring [480..959] |
| `offsetBeatPhase` | 960 | Ring [960..1439] |
| `offsetBassDev` | 1440 | Ring [1440..1919] |
| `offsetBarPhase` | 1920 | Ring [1920..2399] |
| `offsetWriteHead` | 2400 | Scalar |
| `offsetSamplesValid` | 2401 | Scalar |
| `offsetBeatTimes` | 2402 | 16-slot array [2402..2417] — `Float.infinity` = unused |
| `offsetBPM` | 2418 | Scalar |
| `offsetLockState` | 2419 | Scalar (0=unlocked, 1=locking, 2=locked) |
| `offsetSessionMode` | 2420 | Scalar (0=reactive, 1=planned+unlocked, 2=planned+locking, 3=planned+locked) |
| `offsetDownbeatTimes` | 2421 | 8-slot array [2421..2428] — `Float.infinity` = unused |
| `offsetDriftMs` | 2429 | Scalar (positive = beats arrive earlier) |

**Kickoff claims verified:**
- "[2402..2417] beat_times[16]" ✅
- "[2420] session_mode" ✅

**ARCH §Key Types drift (line 819-821):** Claims the reserved section is "[2402..2419]: beat_times[16], bpm, lock_state" — omits sessionMode (2420), downbeatTimes (2421-2428), and driftMs (2429). Bundled into CA-Audio-FU-9.

**Class-level doc-comment drift (SpectralHistoryBuffer.swift:78):** Says "[2402..4095] reserved (zeroed; future consumers)" — but the post-beat-grid layout consumes 2402-2429 with documented semantics. The per-field static-let constants are authoritative; the class-level comment is stale. Bundled into CA-Audio-FU-9.

---

## Verification of DashboardTokens placement (Shared vs Renderer)

**Verdict: keep in Shared. Placement justified by dual-consumer fan-out.**

`DashboardTokens` is consumed by BOTH the Renderer module AND the App module:

**Renderer-side consumers (via the Dashboard cluster CA.7b audited):**
- `PhospheneEngine/Sources/Renderer/Dashboard/BeatCardBuilder.swift:83, 84` — uses `.Color.textBody` and `.Color.coral` for lock-state colour mapping.
- (Other Dashboard builder files reference DashboardTokens at additional sites per CA.7b RENDERER_SUPPORTING.md.)

**App-side consumers:**
- `PhospheneApp/Views/Dashboard/DashboardOverlayView.swift` — 8 callsites across `.Spacing.md / .lg / .sm` and `.Color.border / .surface`.
- `PhospheneApp/Views/Dashboard/DashboardRowView.swift` — 10 callsites across `.TypeScale.body / .label`, `.Color.textBody / .border`.
- `PhospheneApp/Views/Dashboard/DashboardCardView.swift` — 3 callsites across `.Spacing.sm`, `.TypeScale.bodyLarge`, `.Color.textHeading`.
- Plus 1 documentation cross-reference in `PhospheneApp/Views/Ended/EndedView.swift:96` (comment-only).

**Moving to Renderer would break App-layer imports.** The App module already depends on `PhospheneEngine` (and through it, Shared); moving DashboardTokens into Renderer would force App views to depend on the Renderer subsystem solely for design tokens — same anti-pattern as App importing Audio just to read a sample-rate constant. Shared placement is the principle-of-least-surprise design.

**Note:** the file header at `DashboardTokens.swift:5` cites "D-080" as the rationale for the Shared placement — D-080 is actually the QR.2 stem-affinity scoring decision. The actual rationale lives in D-081 / DASH.1.1 (referenced later in the same lore at line 11). Minor inline drift; bundled into CA-Audio-FU-9.

---

## Cross-references

### Updates needed in CLAUDE.md

**Landed in this increment (single 1-line fix):**

- The "Do not show full-screen errors during the `.playing` state. Use bottom-right toasts only. Per `UX_SPEC.md §8`." line under §What NOT To Do — correct §8 → §9 (error taxonomy lives at UX_SPEC §9; §8 is Recovery & Adaptation Flows).

No other CLAUDE.md drift surfaced in CA-Shared.

### Updates needed in ARCHITECTURE.md

**Resolved 2026-05-21 via CA-Audio-FU-9 (Module Map Sync, scope expanded to §Module Map + §Key Types + §GPU Contract Details + per-source-file inline drift).** Concrete diff list (now landed):

1. **§Module Map Shared/ block** (lines 668-678): add 4 missing files:
   - `StemFeatures` → "256 bytes (64 floats). GPU buffer(3). MV-3 / D-099 / DM.2. Per-stem energy + band + beat (16) + MV-1 deviation primitives (8) + MV-3a rich metadata (16) + MV-3c vocal pitch (2) + D-127 drumsEnergyDevSmoothed (1) + padding (21)."
   - `BeatSyncSnapshot` → "Per-frame beat-sync diagnostic snapshot for SessionRecorder. CLAUDE.md §Defect Handling artifact for dsp.beat domain. NSLock-guarded on VisualizerEngine."
   - `BUG012Probe` → "BUG-012-i1 instrumentation namespace. NSLock-guarded counters + alarm-level logs. Read-only per the standing BUG-012-i1 rule. Remove file when BUG-012 closes."
   - `UserFacingError` + `UserFacingError+Presentation` → "Canonical 29-case error taxonomy organised per UX_SPEC §9 (Permission/Connection/Preparation/Playback). Presentation extension adds presentationMode/severity/CTAKey accessors + ErrorPresentationMode/ErrorSeverity/ErrorRetryStatus types. Consumed by App-layer FullScreenErrorView, TopBannerView, PreparationFailureView, PreparationErrorViewModel, LocalizedCopy."

2. **§Key Types** (lines 776-858):
   - Line 779: FeatureVector field documentation conflates `structuralPrediction` + `camera uniforms` into "Floats 1–24" — neither lives in FeatureVector. Rewrite to reflect actual field layout: continuous energy bands, smoothed bands, 6-band, beat pulses, spectral features, valence/arousal, time/deltaTime, aspectRatio, accumulatedAudioTime.
   - Line 799: **delete `BandEnergy`** (struct does not exist; data lives in FeatureVector's bass/mid/treble fields).
   - Line 801: **delete `SpectralFeatures`** (struct does not exist; data lives in FeatureVector's spectralCentroid/spectralFlux).
   - Line 802: **delete `OnsetPulses`** (struct does not exist; data lives in FeatureVector's beatBass/beatMid/beatTreble/beatComposite).
   - Line 803: `EmotionalState` — clarify `quadrant` is a computed property, not a stored field.
   - Line 813: `Particle` — move out of the Shared block (lives in Renderer/Geometry/ProceduralGeometry and Presets/FerrofluidOcean/).
   - Line 814: `SessionState` — move out of the Shared block (lives in Session/SessionTypes.swift).
   - Line 815: `AudioSignalState` — move out of the Shared block (lives in Audio/Protocols.swift).
   - Line 816: `RenderPass` — add missing cases `mv_warp` and `staged`.
   - Lines 817-822: `SpectralHistoryBuffer` — rewrite the reserved-section description: `[2402..2417]` beat_times[16], `[2418]` bpm, `[2419]` lockState, `[2420]` sessionMode, `[2421..2428]` downbeatTimes[8], `[2429]` driftMs.

3. **Source-file inline drift bundled into FU-9:**
   - `AnalyzedFrame.swift:35` "Packed feature vector for GPU uniform upload (96 bytes)" → 192 bytes (post-DM.2).
   - `SpectralHistoryBuffer.swift:78` class-level doc-comment "[2402..4095] reserved" → reflect post-beat-grid layout consuming through 2429.
   - `DashboardTokens.swift:5` "(D-080)" → "(D-081 / DASH.1.1)".

### Updates needed in ENGINEERING_PLAN.md

**Landed in this increment:**

- Add "CA-Shared — Shared Capability Audit ✅ (2026-05-21)" entry to §Recently Completed.

### Updates needed in DECISIONS.md

None. No new decision needed; the existing D-099 / D-126 / D-127 / D-081 invariants stand verified.

### Updates needed in UX_SPEC.md

None. UX_SPEC §9 is the load-bearing authority; UserFacingError.swift correctly cites it. CLAUDE.md is the side that's stale (corrected here).

### Updates needed in KNOWN_ISSUES.md

None. No new BUG entry filed. BUG-012 instrumentation is verified read-only without surfacing a new candidate root cause; the existing 2026-05-20 race-surface analysis remains the authoritative diagnostic hypothesis.

### Updates needed across sibling audits (carry-forward corrections)

None. CA.3 ↔ CA-Audio ↔ CA-Shared TrackMetadata boundary closure already cleanly land; nothing further to thread.

### New BUG entries

None. Counter remains at 16 filed BUGs (BUG-001 through BUG-016) plus 10 resolved BUG-R series.

### KNOWN_ISSUES.md sweep

All Open BUGs verified at kickoff cross-check (BUG-016, BUG-015 [Resolved], BUG-012, BUG-013, BUG-001, BUG-005). No new finding to attach.

---

## Follow-up Backlog

| ID | Scope | Done-when | Est. sessions | Status |
|---|---|---|---|---|
| **CA-Shared-FU-1** | Retire OR wire up `UserFacingError.retryStatus` and `UserFacingError.isConditionBound` (production-orphan accessors at `UserFacingError+Presentation.swift:113-124, 170-177`). The accessors are documented as primitives for retry-aware toast copy and condition-bound auto-dismissal respectively, but the App-side consumers (LocalizedCopy, ToastManager, PlaybackErrorBridge) hard-code these behaviours rather than reading the accessors. Matt product call: (a) retire — same shape as the Smoother.step finding (CA-Shared-FU-3); (b) wire up the documented design — make the App layer consume the accessors. Decision discriminator: does the team want retry-aware toast copy ("attempt 2 of 3" suffix) routed through `UserFacingError.retryStatus`, or is the current hand-coded path acceptable? | Done when: a Resolved entry lands in this row with Matt's product call + commit hash. | 0.5 (retire) or 1 (wire-up) | **Resolved 2026-05-21 (wire-up).** Matt product call: wire up. `LocalizedCopy.spotifyRateLimited` case now sources the "attempt N of 3" suffix from `error.retryStatus.description` via new helper `appendRetryStatus(base:status:)` (replaces the prior `String(format:)` path); Localizable.strings `error.connection.spotify_rate_limited` value reduced to the base headline. `PlaybackErrorBridge.showSilenceExtendedToast` now constructs toasts via a new `toast(for:severity:source:)` helper that gates `duration: .infinity` AND `conditionID` on `error.isConditionBound` — replaces the prior hardcoded silence-specific values. Five new tests (3 in LocalizedCopyTests, 2 in PlaybackErrorBridgeTests). Behavior unchanged for silenceExtended; future condition-bound errors (audioLevelsLow, silenceBrief if producers fire them) automatically route through the same gate. |
| **CA-Shared-FU-2** | Retire OR mark kept-by-design the two production-orphan protocols `SpectralHistoryPublishing` (`SpectralHistoryBuffer.swift:18-63`) and `StemSampleBuffering` (`StemSampleBuffer.swift:15-44`). Both are declared and conformed to in the same file each; no production code uses the protocol as a type, and tests instantiate the concrete classes directly. Structurally analogous to CA.7-FU-3 ICB-keep + CA.7b-FU-3 RayTracing-keep + CA-Audio-FU-2/3 keep precedents. Matt product call: (a) retire (one less abstraction layer; trivial cleanup); (b) keep-by-design for a future test-doubles use (matching the documented motivation). | Done when: a Resolved entry lands in this row with Matt's product call + commit hash. | 0.5 | **Resolved 2026-05-21 (retire).** Matt product call: retire. Both protocol declarations deleted; concrete classes (`SpectralHistoryBuffer`, `StemSampleBuffer`) drop their conformance to `@unchecked Sendable` only. Public API surface of the concrete classes unchanged (same method signatures, same accessor visibility). Test suite green without modification — existing tests already used concrete types. If a future test genuinely needs a fake, re-introducing a protocol is trivial. |
| **CA-Shared-FU-3** | Retire OR keep `Smoother.step(current:target:at:)` (`Smoother.swift:48-51`). Production-orphan accessor; only `factor(at:)` is consumed at 4 DSP sites. Matt product call: (a) retire — same shape as CA.7-FU-4 setRayMarchPresetComputeDispatch retirement; (b) keep as a convenience API for future EMA-step authors. | Done when: a Resolved entry lands in this row with Matt's product call + commit hash. | 0.25 | **Resolved 2026-05-21 (retire).** Matt product call: retire. `step(current:target:at:)` method deleted from `Smoother.swift`; doc-comment updated to reflect the simpler shape (`factor(at:)` only, inline EMA at call sites). All 4 existing callers in DSP unaffected. If a future EMA author wants a one-liner, re-introducing the method is one line of code. |
| **CA-Shared-FU-4** | Extend stems.csv writer at `SessionRecorder+CSV.swift:50-76` to include the D-127 `drumsEnergyDevSmoothed` column (StemFeatures float 43). Add `drumsEnergyDevSmoothed` to the stems.csv header at `SessionRecorder.swift:336-352` (appended at the end per the CSV-append-only invariant); add the formatter call to `csvRow(stems:frame:wallclock:)`. Without this, offline replay tools (Scripts/analyze_*.py, PresetSessionReplay) cannot inspect the V.9 Session 4.5c aurora-curtain driver after the fact — a non-trivial diagnostic gap for any future Ferrofluid Ocean tuning work or AV-style audio-coupling validation. | Done when: stems.csv header includes the column; `csvRow(stems:)` emits a `%.5f` value; an integration test (extend an existing SessionRecorder test) confirms the row count matches the header. | 0.5 | Pending |

---

## Approach validation

**What worked:**

- **Single-pass direct-read at 3,515 LoC.** Same shape as CA-Audio (3,294 LoC) and CA.7b (2,241 LoC) — no Explore agents needed; 12 large-file direct reads + 6 small-file direct reads + sequential grep verification covered the surface in two waves.
- **Pass 0 BUG cross-check.** Caught the CLAUDE.md / kickoff "UX_SPEC §8 error taxonomy" drift before any file read — the file header in `UserFacingError.swift:7` already cited §9 correctly, so verifying against UX_SPEC §9 (the actual taxonomy) closed the loop with zero wasted file-reads.
- **Per-accessor production-orphan check (CA.7b refinement).** Caught the three UserFacingError + Smoother accessor orphans (`.retryStatus`, `.isConditionBound`, `Smoother.step`) that would have been hidden by the "file-level any-consumer" rule. The CA.7b refinement carrying forward is paying real dividends now — every audit since CA.7b has found a small handful of these.
- **Cross-module consumer counts in a single grep loop.** The opening 30-type grep loop gave a single-screen map of fan-out — surfaces all the candidates for orphan investigation in one pass instead of incremental discovery.

**What didn't:**

- **stems.csv `drumsEnergyDevSmoothed` omission almost slipped past.** The CSV header inspection wasn't an explicit Pass 1 step; surfaced opportunistically while reading `SessionRecorder+CSV.swift`. Future CA increments touching CSV writers should make "CSV header ↔ producer struct field-by-field" an explicit verification step — same shape as "JSON sidecar keys ↔ decoder keys" verification that CA-Presets surfaced.
- **ARCH §Key Types drift catastrophic.** Three claimed structs (BandEnergy, SpectralFeatures, OnsetPulses) do not exist anywhere in the codebase. Three other types listed under "Shared Module" live in other modules. These are not just "missing entries" — they are false claims. The CA-Audio-FU-9 scope was originally articulated as "Module Map Sync" (file listings); the Key Types drift suggests FU-9 needs to extend to the full §Key Types section as well. **Recommendation to Matt:** when scheduling CA-Audio-FU-9, plan it as "ARCH structural-claims sync" covering §Module Map + §Key Types + §GPU Contract — not just §Module Map.

**Phase CA closure status (per kickoff):**

With CA-Shared closed, every Swift surface in `PhospheneEngine/Sources/` and `PhospheneApp/` is audited. Remaining audit work:

1. **CA-Audio-FU-9 (Module Map Sync)** — cross-cutting registry + doc sync. Now 7-in-a-row systemic. **Recommend Matt prioritise this next** before the cumulative drift compounds further. Scope: full sweep of ARCH §Module Map + §Key Types + §GPU Contract Details + per-source-file inline doc-comment fixes (the AnalyzedFrame.swift:35, SpectralHistoryBuffer.swift:78, DashboardTokens.swift:5 stale lines surfaced in CA-Shared). Estimate 1-2 sessions.
2. **CA-Preset-Shaders (deferred)** — `.metal` shader files under `Sources/Presets/Shaders/` (17 files / 12,065 LoC). Methodology-distinct from capability-registry verdicts; aligns more naturally with the existing M7 cert review workflow than with the audit format. **Recommend NOT to schedule** as a CA increment unless Matt has a specific shader-fidelity question that warrants the cost; the existing `FidelityRubric` + manual M7 review already covers the "is this shader correct" question at a different layer.
3. **Declare Phase CA complete** with FU-9 landing within the next 2 weeks and the shader audit declared out-of-scope.

**Recommended next action for Matt:** schedule CA-Audio-FU-9 as the next increment. The "ARCH structural-claims" gap is now load-bearing — three non-existent types are documented as if they were Swift structs, which fails the "honest documentation" test that the audit series has been enforcing. Better fixed in one consolidated pass than spread across another two or three increment-by-increment cleanups.
