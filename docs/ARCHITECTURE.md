# Phosphene — Architecture

## Overview

Phosphene is a native Swift/Metal macOS application with a modular engine architecture. Its major subsystems are:

- Audio capture and routing
- Buffering and FFT
- MIR / DSP analysis
- ML-powered stem separation
- Metadata and playlist preparation
- Renderer and preset system
- Orchestrator and session planning (increments 4.1–4.3 complete: scorer, transition policy, session planner; golden fixtures and live adaptation forthcoming)
- App shell and UI

## Architectural Principles

**Native macOS stack only.** Swift, Metal, Accelerate, Core Audio, and Apple system frameworks. No third-party audio capture, no virtual audio drivers, no cross-platform abstractions.

**Local-only processing.** Audio analysis, stem separation, preference learning, and all adaptation remain on-device. No cloud, no telemetry.

**Protocol-oriented design.** Cross-module dependencies are injected via protocols (`AudioCapturing`, `AudioBuffering`, `FFTProcessing`, `Rendering`, `MetadataProviding`, `MetadataFetching`, `StemSeparating`, `MoodClassifying`, `PlaylistConnecting`, `PreviewResolving`, `PreviewDownloading`). All tests use doubles from `Tests/TestDoubles/`.

**UMA-first memory model.** All shared buffers between CPU, GPU, and ML use `MTLResourceOptions.storageModeShared` (zero-copy). Never `.storageModePrivate` or `.storageModeManaged` unless GPU-exclusive.

**Non-blocking render path.** Rendering must never wait on network calls, metadata fetches, or ML inference.

## System Diagram

```
Playlist / streaming source
→ SessionManager (idle → connecting → preparing → ready → playing → ended)
  → PlaylistConnector (AppleScript / Spotify Web API)
  → PreviewResolver (iTunes Search API) → PreviewDownloader (AVAudioFile decode)
  → SessionPreparer (stem separation + MIR per track)
  → StemCache + TrackProfile → Session plan

Live audio capture (Core Audio tap)
→ AudioInputRouter → AudioBuffer (UMARingBuffer)
→ LookaheadBuffer (2.5s analysis/render split)
→ FFTProcessor (vDSP 1024-point → 512 bins)
→ MIRPipeline (BandEnergy + BeatDetector + Chroma + Spectral + Structural)
→ StemSeparator (MPSGraph, background 5s cadence)
→ AnalyzedFrame (FeatureVector + StemFeatures + EmotionalState)

→ Orchestrator (session mode or ad-hoc mode)
→ RenderPipeline (Metal)
→ Preset output
```

## Audio Capture

Phosphene uses a provider-oriented capture architecture. The current default provider is Core Audio taps via `AudioHardwareCreateProcessTap` (macOS 14.2+).

Supported capture modes (abstracted by `AudioInputRouter`):

- `.systemAudio` — system-wide tap (default)
- `.application(bundleIdentifier:)` — per-app tap
- `.localFile(URL)` — file playback for testing/offline use

Operational requirements:

- Screen capture permission is required for non-zero audio delivery. `AudioHardwareCreateProcessTap` succeeds without permission but delivers silence.
- Capture must not allocate or block on the real-time audio thread.
- DRM silence detection via `SilenceDetector` monitors for sustained zero-energy frames and transitions to ambient visual mode.
- Tap input quality is continuously assessed by `InputLevelMonitor`: rolling peak dBFS (21 s window) and 3-band spectral balance EMAs → `SignalQuality` (green/yellow/red). Classification is peak-only — treble-ratio thresholds were removed after they produced false positives on bass-heavy tracks. Quality transitions are logged to session.log with 30-frame hysteresis to prevent flapping.

**Tap recovery on prolonged silence.** Streaming-app scrubs frequently break the process tap — the tap stays alive but delivers permanent silence after the source process tears down and reopens its audio session on seek. `AudioInputRouter` watches the silence detector and, after `.silent` persists, schedules a tap reinstall on a backoff schedule (3 s → 10 s → 30 s, three attempts). Each attempt destroys the existing tap + aggregate device and creates a fresh one for the active capture mode. If audio resumes (either on the existing tap or a freshly-installed one) the silence detector transitions through `.recovering → .active` and the reinstall sequence is cancelled. After three exhausted attempts, prolonged silence is treated as a real pause and reinstall stops until the next active → silent transition.

## Audio Analysis Hierarchy

This ordering is the most important design rule in the project. Continuous-energy-dominant designs feel locked to the music. Beat-dominant designs feel out of sync.

1. **Continuous energy bands** (primary visual driver) — bass/mid/treble (3-band) and 6-band equivalents. Zero detection delay.
2. **Spectrum and waveform buffers** (richest data) — 512 FFT magnitude bins + 1024 waveform samples sent to GPU as buffer data.
3. **Spectral features** (derived characteristics) — centroid, flux, rolloff, MFCCs, chroma.
4. **Beat onset pulses** (accent only, never primary) — discrete accent events with ±80ms jitter. Feedback amplifies this jitter.
5. **Stems** — ML-separated vocals/drums/bass/other. Pre-analyzed from preview clips (available from first frame in session mode). Replaced by time-aligned live stems after ~10s.

**MIR pipeline components** (`DSP` module):

- `BandEnergyProcessor` — Milkdrop-style AGC (output = raw / runningAverage × 0.5). 3-band and 6-band per frame. Deviation primitives `xRel`/`xDev` exposed in `FeatureVector` (D-026).
- `BeatDetector` — 6-band onset detection with per-band cooldowns and grouped pulses; tempo via IOI histogram autocorrelation.
- `BeatPredictor` (MV-3b) — IIR period smoother on onset rising edges. Writes `beatPhase01` (0→1 per inter-beat interval) and `beatsUntilNext` to `FeatureVector`. Enables anticipatory pre-beat animation.
- `ChromaExtractor` — 12-bin chroma with bin-count normalization; Krumhansl-Schmuckler key estimation.
- `SpectralAnalyzer` — centroid, rolloff, flux via vDSP.
- `StemAnalyzer` — per-stem `BandEnergyProcessor` + `BeatDetector` on drums + rich metadata (onset rate, centroid, attack ratio, energy slope) via fast/slow RMS EMAs + `PitchTracker` on vocals. Runs at audio-callback rate (~94 Hz) on a sliding 1024-sample window.
- `PitchTracker` (MV-3c) — YIN autocorrelation (vDSP_dotpr, 2048-sample window). Key implementation detail: after finding the first CMNDF crossing below threshold, the algorithm advances to the local minimum before parabolic interpolation — stopping at the crossing causes catastrophic extrapolation on the descending slope. Exposes `vocalsPitchHz`/`vocalsPitchConfidence` in `StemFeatures`.
- `MIRPipeline` — coordinator: builds `FeatureVector` from all the above each frame.

**`StemFeatures` layout** (GPU buffer(3), 64 floats = 256 bytes):
- Floats 1–16: per-stem energy, band0, band1, beat (four stems).
- Floats 17–24: MV-1 deviation primitives (`{vocals,drums,bass,other}EnergyRel/Dev`).
- Floats 25–40: MV-3a rich metadata (`{vocals,drums,bass,other}{OnsetRate,Centroid,AttackRatio,EnergySlope}`).
- Floats 41–42: MV-3c vocal pitch (`vocalsPitchHz`, `vocalsPitchConfidence`).
- Floats 43–64: padding.

Rule: `base_zoom` and `base_rot` (continuous energy) should be 2–4× larger than `beat_zoom` and `beat_rot` (onset pulses).

## Session Lifecycle

`SessionManager` (`@MainActor ObservableObject`, `Session` module) owns the session lifecycle and coordinates `PlaylistConnector`, `SessionPreparer`, and `StemCache`.

**States:** `idle` → `connecting` → `preparing` → `ready` → `playing` → `ended`

**Degradation:** if the playlist connection fails, the manager transitions directly to `ready` with an empty plan (live-only reactive mode). If individual track preparation fails, `ready` is reached with a partial plan — uncached tracks fall back to real-time stem separation.

**Ad-hoc mode:** `startAdHocSession()` transitions directly to `playing`, skipping playlist preparation entirely.

## Session Preparation

When a playlist is available, `SessionManager.startSession(source:)` drives:

1. Read the ordered track list via `PlaylistConnector`.
2. Resolve preview clip URLs via iTunes Search API (`PreviewResolver`).
3. Download and decode preview clips (AAC/MP3 → PCM via `AVAudioFile`, `PreviewDownloader`).
4. Run stem separation (MPSGraph Open-Unmix HQ, ~142ms per track).
5. Run MIR pipeline (BPM, key, mood, spectral features, structural analysis).
6. Cache all results in `StemCache` keyed by `TrackIdentity`.
7. Orchestrator plans the visual session using per-track `TrackProfile`s.

On track change, `VisualizerEngine.resetStemPipeline(for:)` loads pre-separated stems from `StemCache` immediately — no warmup gap. `StemSampleBuffer` keeps accumulating for live refinement, which crossfades in after ~10s.

## Renderer

The renderer manages the Metal pipeline: device, command queue, triple-buffered semaphore, shader compilation, and frame scheduling. It supports multiple render paths dispatched via a data-driven render graph.

**Render passes** (`RenderPass` enum): `direct`, `feedback`, `particles`, `mesh_shader`, `post_process`, `ray_march`, `icb`, `ssgi`, `mv_warp`. Each preset declares its required passes in JSON metadata.

**Compute kernel buffer layout for particle presets:** `buffer(0)` = particle state, `buffer(1)` = FeatureVector, `buffer(2)` = ParticleConfiguration, `buffer(3)` = StemFeatures. `ProceduralGeometry.update(features:stemFeatures:commandBuffer:)` binds `StemFeatures` at index 3 on the compute encoder. The `stemFeatures` parameter defaults to `.zero` so callers that don't have live stems still compile and run correctly.

**Stem routing warmup pattern for particle presets:** When `StemFeatures` are unavailable (first ~10s of a track in ad-hoc mode), the kernel detects zero stems via `totalStemEnergy = smoothstep(0.02, 0.06, sum_of_all_stem_energies)` and crossfades from FeatureVector 6-band fallback to true stem routing. Zero total stem energy → pure FeatureVector routing (identical behavior to pre-stem implementation). This pattern is reusable for any compute preset that needs to handle the live-stem warmup window.

**Render path priority:** mesh → postProcess → ICB → rayMarch → feedback → direct.

**Per-frame ray-march modulation.** The shared `drawWithRayMarch` path applies preset-agnostic, audio-reactive modulation to `SceneUniforms` each frame — driven by `FeatureVector` values that the lighting / composite passes consume. Modulations:

- **Light intensity** = `baseIntensity × (0.4 + max(beatBass, beatMid, beatComposite) × 2.6)` — pulses on any-band beat onset; cross-genre by reading the strongest of the three onset signals.
- **Light colour** = `baseColor × tint(valence)` — warm amber tint on positive valence, cold blue on negative; used both as direct light tint and as IBL ambient multiplier (see Renderer/Shaders/RayMarch.metal `iblAmbient *= scene.lightColor.rgb`) so colour shift is visible across the whole scene, not only on light-facing surfaces.
- **Fog far plane** = `baseFogFar × (calmFactor or franticFactor)` — calm arousal expands the visible horizon, frantic arousal closes it in.
- **Camera dolly** = `baseCameraZ + features.time × cameraDollySpeed` — constant-speed wall-clock advance, per-preset speed (Glass Brutalist 2.5 u/s; others 0). Decoupled from `accumulatedAudioTime` so motion feels like travel, not energy-tied.
- **`SceneUniforms.cameraForward.w`** is repurposed as a preset-specific scalar for SDF deformation that needs to be visible to both `sceneSDF` and `sceneMaterial` (Glass Brutalist uses it as the glass-fin X-position). The preamble passes `FeatureVector` and `SceneUniforms` to `sceneMaterial` so material classification stays consistent with deformed geometry.

Baselines for these modulations are captured in `RayMarchPipeline.BaseSceneSnapshot` at preset apply time so per-frame modulation is additive on the preset's intent, not destructive.

**Fragment buffer binding layout (direct-pass presets):**

| Index | Content | Notes |
|-------|---------|-------|
| 0 | `FeatureVector` (192 bytes) | All fragment encoders |
| 1 | FFT magnitudes (512 Float32) | All fragment encoders |
| 2 | Waveform (2048 Float32) | All fragment encoders |
| 3 | `StemFeatures` (256 bytes) | All fragment encoders |
| 4 | `SceneUniforms` (128 bytes) | Ray march G-buffer, lighting, SSGI **only** |
| 5 | `SpectralHistory` (4096 Float32, 16 KB) | Direct-pass fragment encoders; see D-030 |
| 6–7 | Future use | — |

`SpectralHistoryBuffer` (Shared module) maintains 5 ring buffers of 480 samples (≈8s at 60 fps): valence, arousal, `beat_phase01`, `bass_dev`, and log-normalized vocal pitch (80→800 Hz mapped to 0→1). Updated once per frame in `RenderPipeline.draw(in:)` before any render encoder; reset on track change. Enables `instrument`-family presets to render recent MIR history without per-preset plumbing.

**Key subsystems:**

- `FrameBudgetManager` — Pure-state frame timing governor attached to `RenderPipeline`. Receives one `FrameTimingSample` per completed frame (via `commandBuffer.addCompletedHandler` → `@MainActor` hop) and walks a `QualityLevel` ladder: `full → noSSGI → noBloom → reducedRayMarch → reducedParticles → reducedMesh`. Downshifts after 3 consecutive overruns; upshifts after 180 consecutive sub-budget frames (asymmetric hysteresis). Per-tier configuration: tier1 (M1/M2) 14ms target, tier2 (M3+) 16ms target. `reset()` is called on every preset change so the governor starts optimistic. Disabled when `QualityCeiling` is `.ultra`. (D-057)
- `PostProcessChain` — HDR bloom + ACES tone mapping. `bloomEnabled` gates the bright-pass + blur stages; composite always runs for ACES tone-mapping.
- `RayMarchPipeline` — Deferred 3-pass: G-buffer → PBR lighting → composite. `reducedMotion` is an OR-gate of `a11yReducedMotion` (accessibility) and `governorSkipsSSGI` (budget governor), ensuring the governor cannot clear a user's accessibility preference. `stepCountMultiplier` is written to `sceneParamsB.z` each frame and consumed in the ray-march preamble loop.
- `IBLManager` — Image-based lighting (irradiance + prefiltered environment + BRDF LUT).
- `ProceduralGeometry` — GPU compute particle system. `activeParticleFraction` scales compute dispatch count for governor-level particle reduction.
- `MeshGenerator` — Hardware mesh shaders (M3+) with vertex fallback (M1/M2). `densityMultiplier` is passed at object/mesh buffer(1) for M3+ opt-in density reduction; no-op on M1/M2 vertex path.
- `TextureManager` — 5 pre-computed noise textures generated via Metal compute at init.
- `RenderPipeline+MVWarp` — Milkdrop-style per-vertex feedback warp: `MVWarpPipelineBundle`, `MVWarpState`, `setupMVWarp`, `drawWithMVWarp` (3-pass warp/compose/blit), `clearMVWarpState`, `reallocateMVWarpTextures`.

**Binding layout:**

- Textures: 0=feedback read, 1=feedback write, 2–3=reserved, 4=noiseLQ, 5=noiseHQ, 6=noiseVolume, 7=noiseFBM, 8=blueNoise, 9=IBL irradiance, 10=IBL prefiltered, 11=BRDF LUT.
- Buffers: 0=FFT, 1=waveform, 2=FeatureVector, 3=StemFeatures, 4–7=future.

## Presets

Each preset consists of one or more Metal shaders plus a JSON sidecar declaring visual behavior, render passes, audio routing, and orchestration metadata. Presets are discovered automatically at runtime and compiled with a shared preamble (FeatureVector struct, ShaderUtilities library, noise samplers).

**Three architectural patterns coexist:**

- **Milkdrop-style per-vertex feedback warp (`mv_warp`):** 32×24 vertex grid warps the previous frame at per-vertex displaced UVs. Three passes per frame — warp (previous frame → composeTexture via displaced UVs × decay), compose (alpha-blend current scene onto composeTexture), blit (composeTexture → drawable). Motion accumulates across frames; simple audio inputs compound into organic motion. The scene can be pre-rendered by a preceding `.rayMarch` pass (into `warpState.sceneTexture`) or rendered directly by the preset's fragment shader for direct presets (e.g. Starburst). Presets implement `mvWarpPerFrame()` + `mvWarpPerVertex()` Metal functions to author the per-vertex UV displacement. `MVWarpPipelineBundle` holds the three per-preset compiled pipeline states; `MVWarpState` holds the three off-screen textures (warpTexture, composeTexture, sceneTexture).
- **Thin global feedback (`feedback`):** read previous frame → single global zoom+rot → composite. Kept for Membrane. Semantically narrower than `mv_warp`.
- **Photorealistic ray march:** SDF scene → G-buffer → PBR lighting → IBL → post-process. Ray-march presets can also opt into `mv_warp` for temporal feedback; in that case the lighting pass renders to `warpState.sceneTexture` instead of the drawable, and `mv_warp` handles drawable presentation.

## Orchestrator

The Orchestrator is the decision layer responsible for selecting visualizers, sequencing transitions, adapting to live analysis, and balancing novelty, continuity, and performance cost.

**Two modes:**

- **Session mode** (playlist connected): Plans the full visual arc before playback using pre-analyzed TrackProfile data. Adapts in real time as live MIR reveals structural details.
- **Ad-hoc mode** (no playlist): Reactive decision-making under uncertainty. Heuristic preset selection based on live MIR data as it accumulates.

The Orchestrator is the product's key differentiator and is implemented as an explicit scoring and policy system with testable golden-session fixtures.

**Implemented (Phase 4, Increments 4.1–4.3):**

- **`DefaultPresetScorer`** — stateless, deterministic preset ranker. Produces a `PresetScoreBreakdown` with four weighted sub-scores (mood 30 %, stemAffinity 25 %, sectionSuitability 25 %, tempoMotion 20 %) and two multiplicative penalties (family-repeat 0.2×; fatigue via smoothstep over 60/120/300 s cooldowns by `FatigueRisk`). Hard exclusions gate the currently-playing preset and any preset whose `ComplexityCost` exceeds the device frame budget. `PresetScoringContext` is a fully Sendable value snapshot; `DefaultPresetScorer` contains no mutable state and calls no `Date.now()`, guaranteeing determinism across all tests.
- **`DefaultTransitionPolicy`** — implements `TransitionDeciding`. Structural boundary (confidence ≥ 0.5, 2.5 s lookahead) fires before the duration-expired timer fallback. Style negotiated from the current preset's `transitionAffordances` and energy (`.cut` preferred at energy > 0.7, `.crossfade` otherwise). Crossfade duration scales linearly 2.0 s → 0.5 s with energy. Fully inspectable `TransitionDecision` value type.
- **`DefaultSessionPlanner`** — implements `SessionPlanning`. Greedy forward-walk over the playlist: for each track, scores the full catalog given accumulated history and picks the top eligible preset. Transition decisions reuse `DefaultTransitionPolicy` via synthetic `StructuralPrediction` at each track boundary (confidence 1.0). Output is a `PlannedSession` with `PlannedTrack` entries each carrying score breakdown, transition decision, and planned timing. `planAsync` accepts a precompile closure — the Orchestrator module carries no Renderer dependency. Deterministic: same inputs → byte-identical plan.
- Session-mode planning is now implemented end-to-end (score → select → transition → plan). Render-loop consumption (Increment 4.5), live adaptation (Increment 4.5), ad-hoc mode (Increment 4.6), and golden-session regression fixtures (Increment 4.4) remain forthcoming.

**Forthcoming (4.4+):**

- **Golden-session fixtures (4.4)** — curated playlists with expected family sequences and forbidden choices; become the regression gate for all future Orchestrator changes.
- **SessionManager app-layer wiring (4.5)** — `Session` module cannot import `Orchestrator` (circular dependency). The app layer observes `SessionManager.state == .ready` and calls `DefaultSessionPlanner.plan(...)`.
- **Live adaptation (4.5)** — adapt the running plan as live MIR reveals structural details.
- **Ad-hoc reactive mode (4.6)** — heuristic preset selection without pre-analysis.

## UI Layer

The app shell routes `SessionManager.state` to one top-level SwiftUI view per session state. No view owns more than one state.

**`SessionStateViewModel`** (`@MainActor ObservableObject`, `PhospheneApp` module) — Bridges `SessionManager.state` into the view layer via a Combine `.assign` subscription. Also surfaces `reduceMotion` (from `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification`), which caps beat-pulse amplitude and disables `mv_warp` feedback in reduced-motion mode. Lives in `PhospheneApp/ViewModels/`.

**State-to-view mapping:**

| `SessionState` | View | `accessibilityIdentifier` |
|---|---|---|
| `.idle` | `IdleView` | `phosphene.view.idle` |
| `.connecting` | `ConnectingView` | `phosphene.view.connecting` |
| `.preparing` | `PreparationProgressView` | `phosphene.view.preparing` |
| `.ready` | `ReadyView` | `phosphene.view.ready` |
| `.playing` | `PlaybackView` | `phosphene.view.playing` |
| `.ended` | `EndedView` | `phosphene.view.ended` |

**`ContentView`** layers a permission gate above the session-state switch. When `PermissionMonitor.isScreenCaptureGranted` is `false`, `PermissionOnboardingView` renders regardless of `SessionManager.state` — this catches both fresh installs and mid-session permission revocations. When permission flips to `true` (detected via `NSApplication.didBecomeActiveNotification`), the view tree re-renders and routes to the current `SessionState`. Permission plumbing lives under `PhospheneApp/Permissions/`, not `Views/`, because it is a routing-layer concern.

**`PlaybackView`** hosts the full-bleed `MetalView`, preset-name badge, `NoAudioSignalBadge` (DRM silence), and `DebugOverlayView`. It calls `engine.startAudio()` on appear and handles all keyboard shortcuts (`→` / `←` / `Space` = next/prev/next preset; `D` = debug overlay; `C` = capture; `R` = MIR record; `G` = G-buffer debug).

**`VisualizerEngine`** is injected into the SwiftUI environment as an `@EnvironmentObject`. `ContentView` and `PhospheneApp.swift` do not own layout — they exist solely to wire the VM and inject the engine.

## Support Tiers

**Tier 1 — M1 / M2:** Baseline feature set. Mesh shaders use vertex fallback. Stricter budgets for geometry, post-process, and advanced shaders.

**Tier 2 — M3 / M4:** Enhanced feature set. Hardware mesh shaders enabled. Mesh/ray-heavy presets allowed. Higher complexity ceilings.

## ML Inference

No CoreML dependency. All ML runs on MPSGraph (GPU) or Accelerate (CPU).

- **Stem separator** (MPSGraph): Open-Unmix HQ, Float32 throughout, 142ms warm predict for 10s audio. STFT/iSTFT via Accelerate/vDSP. The 5s background timer fires every 5 seconds; actual dispatch may be deferred up to 2 s (Tier 1) or 1.5 s (Tier 2) if recent frames are over budget — see Dispatch Scheduling below.
- **Mood classifier** (Accelerate): 4-layer MLP (10→64→32→16→2) via `vDSP_mmul`. 3,346 hardcoded Float32 params from DEAM training.

### Dispatch Scheduling (Increment 6.3)

`MLDispatchScheduler` (`Renderer` module) coordinates the 5s stem separation cycle with render-loop frame timing. When a heavy ray-march+SSGI frame is in flight, a 142ms MPSGraph burst landing on top causes visible double-jank.

**Algorithm:** on each 5s timer fire, the scheduler checks:
1. If `QualityCeiling == .ultra` → dispatch immediately (recording mode, D-059d).
2. If the dispatch has been pending ≥ `maxDeferralMs` → force-dispatch to prevent stem freeze (D-059c).
3. If fewer than `requireCleanFramesCount` frames have been observed → defer (startup warmup).
4. If `recentMaxFrameMs > currentTierBudgetMs` → defer 100 ms and retry.
5. Else → dispatch now.

**Budget signal:** the scheduler reads `FrameBudgetManager.recentMaxFrameMs` — the worst frame in the last 30-frame rolling window, not `currentLevel`. The level has 180-frame upshift hysteresis; the rolling max reflects the current render state immediately (D-059a).

**Deferral caps:** Tier 1 (M1/M2): `maxDeferralMs = 2000`, `requireCleanFramesCount = 30`. Tier 2 (M3+): 1500 ms / 20 frames. Stems already lag real audio by 5–10 s (per-frame analysis from cached waveforms runs continuously regardless — Increment 3.5.4.9), so a 2 s extra lag is within acceptable routing freshness bounds (D-059b).

**Testability:** `FrameTimingProviding` protocol (`recentMaxFrameMs`, `recentFramesObserved`) is conformed to by both `FrameBudgetManager` and test stubs. Single source of truth — no parallel timing buffer in the scheduler (D-059e).

**Mood injection into the renderer.** Mood (`valence`, `arousal`) is computed on the analysis queue, attenuated by feature-stability, and pushed to the renderer via `RenderPipeline.setMood(valence:arousal:)`. The renderer's `setFeatures` preserves the most recent mood values across MIR-driven feature updates so the slower-cadence mood signal is not overwritten every frame. Without this dedicated path, mood values stay at zero in the GPU-bound `FeatureVector` even though the classifier is running.

## Session Recording (Diagnostics)

`SessionRecorder` (`Shared` module, public) writes a continuous diagnostic capture for every running session to `~/Documents/phosphene_sessions/<ISO-timestamp>/`. Created at `VisualizerEngine.init`, finalized via `NSApplication.willTerminateNotification` so the MP4 `moov` atom is written before process exit.

**Artifacts per session:**

- `video.mp4` — H.264 capture of the rendered output, throttled to 30 fps. Writer is locked once the drawable size has been observed for 30 consecutive same-size frames; later frames at a different size are skipped (preventing corner-rendered video from transient launch-time drawable sizes). MetalView sets `framebufferOnly = false` so the drawable is blit-readable.
- `features.csv` — per-frame `FeatureVector` (22 columns: bass/mid/treble, 6-band, beat onsets, spectral, valence/arousal, accumulatedAudioTime).
- `stems.csv` — per-frame `StemFeatures` (vocals/drums/bass/other × {energy, band0, band1, beat, energyRel/Dev, onsetRate, centroid, attackRatio, energySlope}; plus vocalsPitchHz/Confidence).
- `stems/<NNNN>_<title>/{drums,bass,vocals,other}.wav` — 16-bit mono PCM dump of each stem-separation cycle output, listenable in any audio editor.
- `session.log` — startup banner (recorder version + macOS + GPU + hostname), state transitions (signal `.active/.suspect/.silent/.recovering`), track changes, preset changes, video-writer locked dimensions, and any frame-skip reasons.

**Render-loop integration:** `RenderPipeline` exposes `onFrameRendered: (drawableTex, features, stems, commandBuffer) -> Void`. `VisualizerEngine` sets this closure to blit the drawable into the recorder's capture texture inside the same command buffer, then schedule the readback in `commandBuffer.addCompletedHandler`. CSV rows are written every render frame; video frames are throttled to 30 fps.

**Test surface:** `SessionRecorderTests` validates round-trip correctness against known inputs (CSV column-by-column, WAV PCM sample-by-sample within 16-bit quantization, MP4 readable by `AVURLAsset`). A passing session that shows wrong data tells you the upstream pipeline is wrong, not the recorder.

## Soak Test Infrastructure (Increment 7.1, D-060)

`SoakTestHarness` (`Diagnostics` module) drives `AudioInputRouter` in `.localFile` mode for a configurable duration (default 2 hours) and produces a structured `Report` with memory growth, frame timing percentiles, dropped frames, quality-level transitions, signal-state transitions, and ML force-dispatch counts.

### Components

**`MemoryReporter`** (enum, stateless): Wraps the `task_info(TASK_VM_INFO)` Mach call. Returns `MemorySnapshot { residentBytes: phys_footprint, virtualBytes, purgeableBytes, timestamp }`. Uses `phys_footprint` — the same metric as Activity Monitor and jetsam — rather than `resident_size` which includes purgeable pages. Returns `nil` on Mach failure (counted as a hard failure if > 5 consecutive nils).

**`FrameTimingReporter`** (class, `@unchecked Sendable`, NSLock-guarded): Records per-frame effective timing (`max(cpuMs, gpuMs)`). Maintains two views: a 100-bucket fixed-width histogram (0.5 ms/bucket, 0–50 ms) for run-wide cumulative percentiles and a 1000-frame circular ring buffer for rolling percentiles and dropped-frame counts. O(1) record, O(buckets) percentile via histogram scan. Wired into `RenderPipeline.onFrameTimingObserved`.

**`SoakTestHarness`** (`@available(macOS 14.2, *)`, `@MainActor`): Orchestrates the run. Starts audio, installs signal-state and frame-timing observers, runs a 0.25s-slice polling loop for cancel responsiveness, fires periodic sampling tasks, and at completion writes a JSON + Markdown report to `reportBaseDirectory/<ISO-timestamp>/`. Does not require a live Metal render pipeline — GPU timing is optional and wired in by callers with a `RenderPipeline`.

**`SoakRunner`** (executable target): CLI entry point using `swift-argument-parser`. Options: `--duration`, `--sample-interval`, `--audio-file`, `--report-dir`. Generates a synthetic audio fixture automatically when `--audio-file` is omitted (10 s sine sweep + noise + 120 BPM kicks, written to `tmp/`). Use `Scripts/run_soak_test.sh` for 2-hour production runs; the script wraps `caffeinate -i` to prevent App Nap.

### Frame Timing Fan-out (D-060c)

`RenderPipeline.onFrameTimingObserved` is an optional `(cpuMs: Float, gpuMs: Float?) -> Void` closure fired inside the `commandBuffer.addCompletedHandler` Task, before `FrameBudgetManager`. Setting it to `harness.frameTimingRecorder` gives the soak harness GPU-accurate timings from the same source as the frame governor with zero additional overhead in production (nil closure = no call).

### Report Structure

```json
{
  "finalAssessment": "pass | passWithSoftAlerts | hardFailure",
  "snapshots": [{ "elapsedSeconds": 60, "residentBytes": ..., "cumulativeP50Ms": ..., ... }],
  "signalTransitions": [{ "elapsedSeconds": 0.5, "state": "active" }],
  "qualityLevelTransitions": [{ "elapsedSeconds": 120, "from": "full", "to": "no-SSGI" }],
  "mlForceDispatches": 0,
  "alerts": ["Memory grew 52 MB from baseline (threshold: 50 MB)"]
}
```

Soft alerts: memory growth > 50 MB, dropped frames > 60/h, quality downshifts > 3, ML force dispatches > 10/h. Hard failure: `MemoryReporter` nil > 5 times.

---

## Long-Session Resilience (Increment 7.2, D-061)

Three coordinator classes handle disruptions that arise during extended sessions without touching `SessionManager.state` or `livePlan` except where explicitly required.

### DisplayChangeCoordinator

Owned by `PlaybackView` as `@State`. Subscribes to `DisplayManager.$allScreens` and `.$currentScreen` via Combine. When the active display is removed (or the window moves to a different screen), it calls `FrameBudgetManager.resetRecentFrameBuffer()` — clearing only the 30-slot rolling timing window so the post-reparent jitter frames don't poison `MLDispatchScheduler`'s "recent frames over budget" signal. `currentLevel` is preserved (D-061(a)). Screen-added events fire a toast via `MultiDisplayToastBridge` and take no governor action.

### CaptureModeSwitchCoordinator

Owned by `PlaybackView` as `@State`. Subscribes to `SettingsStore.captureModeChanged`. On every non-`.localFile` mode switch, it opens a 5-second grace window by:
- Setting `VisualizerEngine.captureModeSwitchGraceWindowEndsAt = Date() + 5s`
- Raising `PlaybackErrorBridge.effectiveThresholdSeconds` to 20 s (from the normal 15 s)

`applyLiveUpdate` in `VisualizerEngine+Orchestrator.swift` checks `isCaptureModeSwitchGraceActive` and discards `presetOverride` events while the window is open; `updatedTransition` (boundary rescheduling) still fires normally. After 5 seconds a `Task` calls `closeGraceWindow()` which restores both values. Consecutive `openGraceWindow()` calls cancel the prior task. `.localFile` mode gets no grace window (D-052 path, D-061(b,c)).

### NetworkRecoveryCoordinator

Owned by `PreparationProgressView` as `@State`. Subscribes to `ReachabilityMonitor.isOnlinePublisher`. On a `false → true` transition (network restored), it waits an additional 2 seconds (composing to 3 s total with the monitor's existing 1 s debounce) then calls `SessionManager.resumeFailedNetworkTracks()` — which retries only network-class failures (`.noPreviewURL`, `.downloadFailed`); stem-separation failures stay failed. Guards: state must be `.preparing` (tracked from an injected `sessionStatePublisher`); attempt count must be below 3 (cap per preparation session). `resetForNewSession()` resets the counter and cancels any pending debounce task (D-061(d,e)).

---

## Module Map

Per-file behavioural reference for every Swift source file in `PhospheneApp/` and `PhospheneEngine/`, every Metal shader, and every test target. Read it when you need to locate functionality before `grep`ing the codebase.

Per-preset design history (Arachne V.7.x evolution; LumenMosaic LM.3 → LM.7 iteration; etc.) currently lives inline in the per-preset entries below. A future pruning pass will split those history blocks out into `docs/presets/<preset>_DESIGN.md` per the 2026-05-13 doc-refactor plan's borderline-call B (see `docs/diagnostics/DOC-REFACTOR-PLAN-2026-05-13.md`).

```
PhospheneApp/               → SwiftUI shell, views, view models
  ContentView.swift         → Pure switch on SessionManager.state; no layout logic
  PhospheneApp.swift        → App entry point; wires SessionStateViewModel + startAdHocSession()
  VisualizerEngine.swift    → Audio→FFT→render pipeline owner; owns SessionManager (non-optional).
                               `diagnosticPresetLocked: Bool` (DSP.3.1): when true, `applyLiveUpdate`
                               strips `presetOverride` (mood-derived switch) but passes `updatedTransition`
                               (structural-boundary reschedule) through unchanged. Manual preset selection
                               via `applyPresetByID(_:)` is always allowed. Planned-session state (`livePlan`,
                               BeatGrid in `mirPipeline`) is never cleared by the hold — diagnostic hold
                               pins the visual surface, not the planner. Prepared BeatGrid is authoritative;
                               reactive beat tracking (`BeatPredictor`) is fallback only.
  VisualizerEngine+Audio.swift → Audio routing, MIR analysis, mood classification, signal state callbacks
  VisualizerEngine+Stems.swift → Background stem separation pipeline, 5s cadence, track-change reset. Increment 6.3: dispatch gated by MLDispatchScheduler — runStemSeparation() hops to @MainActor, consults scheduler, then fires performStemSeparation() on stemQueue when frame window is clean. DSP.3.5: runLiveBeatAnalysisIfNeeded() uses liveBeatAnalysisAttempts counter (max 2) — first attempt at 10 s, retry at 20 s; halvingOctaveCorrected() applied before offsetBy(); inference body extracted to performLiveBeatInference(). DSP.3.6: source-tagged BEAT_GRID_INSTALL logging at all three BeatGrid install sites (preparedCache/liveAnalysis/none); prepared-cache guard in runLiveBeatAnalysisIfNeeded logs and caps counter when hasGrid true; sessionRecorder?.log() one-time per-track events in both install sites.
  VisualizerEngine+Presets.swift → makeSceneUniforms(from:) for ray march camera/light setup
  Permissions/
    ScreenCapturePermissionProvider.swift → Protocol + CGPreflightScreenCaptureAccess-backed impl (never prompts)
    PermissionMonitor.swift               → @MainActor ObservableObject; refreshes isScreenCaptureGranted on foreground (U.2)
    PhotosensitivityAcknowledgementStore.swift → UserDefaults-backed first-run flag; key phosphene.onboarding.photosensitivityAcknowledged (U.2)
  Services/
    DelayProviding.swift    → Protocol for injectable sleep (RealDelay + InstantDelay); makes retry loops unit-testable without wall-clock waits
    SpotifyURLKind.swift    → Enum: .playlist(id:) / .track / .album / .artist / .invalid
    SpotifyURLParser.swift  → Pure enum; static parse(_ input:) → SpotifyURLKind; handles HTTPS, spotify: URI, @-prefix, query params, podcasts
    DisplayChangeCoordinator.swift → @MainActor; subscribes to DisplayManager publishers; calls FrameBudgetManager.resetRecentFrameBuffer() on active-screen removal or window move. No session-state changes. D-061(a).
    CaptureModeSwitchCoordinator.swift → @MainActor; opens 5s grace window on non-.localFile mode switches; suppresses presetOverride in applyLiveUpdate; raises silence threshold to 20s. CaptureModeSwitchEngineInterface protocol for testability. D-061(b,c).
    NetworkRecoveryCoordinator.swift → @MainActor; wires ReachabilityMonitor to SessionManager.resumeFailedNetworkTracks(); 2s additional debounce (3s total); 3-attempt cap per session; state guard via injected sessionStatePublisher. D-061(d,e).
  ViewModels/
    SessionStateViewModel.swift → @MainActor ObservableObject bridging SessionManager.state → SwiftUI; publishes state + reduceMotion
    ConnectorPickerViewModel.swift → @MainActor ObservableObject; NSWorkspace observers (nonisolated(unsafe)) for AM launch/terminate; 250ms debounce
    AppleMusicConnectionViewModel.swift → State machine (idle→connecting→noCurrentPlaylist/notRunning/permissionDenied/error/connected); 2s auto-retry via DelayProviding
    SpotifyConnectionViewModel.swift → State machine (empty→parsing→preview/rejectedKind/invalid→rateLimited/notFound/error); 300ms debounce; [2s,5s,15s] rate-limit retry
  Views/
    MetalView.swift         → NSViewRepresentable wrapping MTKView
    DebugOverlayView.swift  → Developer debug overlay (D key). Bottom-leading SwiftUI surface — raw diagnostics complementary to the top-trailing SwiftUI dashboard cards (BEAT/STEMS/PERF). Tempo / standalone QUALITY / standalone ML rows removed in DASH.6 (now in PERF/BEAT cards); MOOD V/A, Key, SIGNAL block, MIR diag, SPIDER, G-buffer, REC remain. Both surfaces are gated on `if showDebug`; the `D` shortcut toggles the same SwiftUI `@State` that drives both layers (DASH.7, D-087).
  Views/Dashboard/             → SwiftUI dashboard overlay (DASH.7 / DASH.7.1 / DASH.7.2, supersedes Renderer/Dashboard's Metal composer + DASH.6).
    DashboardOverlayView.swift → Top-trailing single panel containing three `DashboardCardView` typographic sections separated by `border` dividers. Per-card chrome retired in DASH.7.1. Surface is `DarkVibrancyView` (NSVisualEffectView pinned to `.vibrantDark` + `.hudWindow`) + `Color.surface` tint at **0.96α** + 1px `border` stroke + `.environment(\.colorScheme, .dark)` lock — guarantees the panel renders dark regardless of macOS Appearance setting (DASH.7.2, D-089). Sits as PlaybackView Layer 6, conditionally rendered on `showDebug` with a spring-damped fade+offset transition. Width fixed at 320pt.
    DashboardCardView.swift    → Renders one `DashboardCardLayout` as a typographic section (no chrome of its own). Title in **Clash Display Medium @ 15pt** (or system semibold fallback), resolved via `DashboardFontLoader.resolveFonts()`. Rows stack at `layout.rowSpacing`.
    DashboardRowView.swift     → Switches over the 4 row variants (`.singleValue` / `.bar` / `.progressBar` / `.timeseries`). **DASH.7.2 (D-089) inlined `.singleValue`** — label-LEFT + Spacer + value-RIGHT at 13pt mono, matching `.bar` and `.progressBar` row rhythm; the 24pt hero-numeric was retired. `.progressBar` value column widened to 110pt with `.fixedSize(horizontal: true)` so FRAME `"20.0 / 14ms"` no longer truncates. Sparkline rendered via SwiftUI `Canvas` (filled area + stroked line + centre baseline). Labels use **Epilogue Medium @ 11pt** (or system medium fallback) with `labelTracking`. Numeric values stay SF Mono. **No SF Symbols** — status reads through value-text colour only (D-088). When `valueText.isEmpty` (STEMS rows), the right-side numeric column collapses entirely.
    DarkVibrancyView.swift     → `NSViewRepresentable` wrapping `NSVisualEffectView` with `.appearance = NSAppearance(named: .vibrantDark)`, `.material = .hudWindow`, `.blendingMode = .withinWindow`. Used as the dashboard panel backdrop so the surface stays dark on macOS Light appearance (DASH.7.2, D-089). Replaces SwiftUI's appearance-adaptive `.regularMaterial`.
    DashboardOverlayViewModel.swift → `@MainActor ObservableObject`. Subscribes to `VisualizerEngine.$dashboardSnapshot`, throttles to ~30 Hz (`.throttle(for: .milliseconds(33))`), maintains private `MutableStemHistory` rings for the timeseries STEMS card, publishes `[DashboardCardLayout]`. `ingestForTest(_:)` test seam bypasses the throttled subscription.
    ConnectorType.swift     → Enum: .appleMusic/.spotify/.localFolder; title/subtitle/systemImage
    ConnectorTileView.swift → Reusable tile: icon + title/subtitle; disabled state with alt caption + optional secondary action button
    ConnectorPickerView.swift → NavigationStack in sheet; three tiles; navigationDestination(for: ConnectorType.self)
    AppleMusicConnectionView.swift → Five-state connection view (connecting/noCurrentPlaylist/notRunning/permissionDenied/error); onConnect fires on .connected
    SpotifyConnectionView.swift → URL paste field; preview card; rejectedKind copy; rate-limit retry indicator; error body
    Onboarding/PermissionOnboardingView.swift → Screen-capture permission explainer; "Open System Settings" CTA (U.2)
    Onboarding/PhotosensitivityNoticeView.swift → One-time photosensitivity sheet on IdleView first appearance (U.2)
    Idle/IdleView.swift     → .idle state; "Connect a playlist" sheet CTA + "Start listening now" ad-hoc CTA (U.3)
    Connecting/ConnectingView.swift → .connecting state (QR.4): per-connector spinner (Apple Music / Spotify / Local Folder / generic), localized headline (no trailing ellipsis per UX_SPEC §8.5), per-connector subtext, cancel CTA wired to sessionManager.cancel(). Takes `source: PlaylistSource?` + `onCancel: () -> Void`.
    Preparation/PreparationProgressView.swift → .preparing state: per-track status + partial-ready CTA
    Ready/ReadyView.swift   → .ready state: "Press play in your music app" + first-audio autodetect
    Playback/PlaybackView.swift → .playing state: full-bleed Metal + preset badge + signal badge + debug overlay + keyboard shortcuts
    Ended/EndedView.swift   → .ended state (QR.4): session-summary card. Takes `trackCount: Int`, `sessionDuration: TimeInterval?` (nil → em-dash placeholder; full plumbing deferred per D-091.8), `onStartNewSession: () -> Void` (wired to sessionManager.cancel() — the documented .ended → .idle path), `onOpenSessionsFolder: () -> Void`. Coral primary CTA, secondary "Open sessions folder" via NSWorkspace.

PhospheneEngine/
  Audio/
    SystemAudioCapture      → Core Audio tap: system-wide or per-app
    AudioInputRouter        → Unified source: .systemAudio/.application/.localFile → callbacks + dual analysis/render frames
    LookaheadBuffer         → Timestamped ring buffer, dual read heads (analysis + render), configurable 2.5s delay
    AudioBuffer             → IO proc → UMARingBuffer<Float> bridge for GPU
    FFTProcessor            → vDSP 1024-pt FFT → 512 magnitude bins in UMABuffer
    SilenceDetector         → DRM silence state machine: .active → .suspect (1.5s) → .silent (3s) → .recovering → .active (0.5s hold)
    InputLevelMonitor       → Continuous tap-quality assessment: rolling peak dBFS (21s window) + 3-band spectral EMAs → SignalQuality (green/yellow/red) with reason string. Peak-only classification after session 2026-04-17T21-05-47Z showed treble-ratio thresholds fired false positives on bass-heavy tracks. Hysteresis (30-frame hold) prevents log flapping. Logged to session.log on quality transitions via VisualizerEngine+Audio.
    StreamingMetadata       → AppleScript polling of Apple Music/Spotify, track change detection
    MetadataPreFetcher      → Parallel async queries, LRU cache, merge partial results, 3s per-fetcher timeouts
    MusicBrainzFetcher      → Free API, genre tags + duration
    SpotifyFetcher          → Client credentials, search-only track matching
    SoundchartsFetcher      → Optional commercial API (SOUNDCHARTS_APP_ID/SOUNDCHARTS_API_KEY env vars)
    MusicKitBridge          → Optional MusicKit catalog enrichment, graceful no-op
    Protocols               → AudioCapturing, AudioBuffering, FFTProcessing, MoodClassifying, MetadataProviding, MetadataFetching
  DSP/
    SpectralAnalyzer        → Spectral centroid, rolloff, flux via vDSP
    BandEnergyProcessor     → 3-band + 6-band energy, AGC, FPS-independent smoothing
    ChromaExtractor         → 12-bin chroma, Krumhansl-Schmuckler key estimation, bin-count normalized
    BeatDetector            → 6-band onset detection, grouped beat pulses, tempo via autocorrelation. recordOnsetTimestamps sources from result.onsets[0] (sub_bass per-band events), never fuses bands (D-075).
    BeatDetector+Tempo      → IOI-based tempo via computeStableTempo: trimmed-mean IOI over the trailing 10 s window (median, drop outliers outside [0.5×, 2×], mean of inliers, BPM = 60/meanIOI). Histogram still built but consumed only by the diagnostic dump (D-075). Plus estimateTempo (autocorrelation fallback).
    BeatDetector+TempoDiagnostics → DSP.1 baseline-capture instrumentation. dumpHistogram + dumpEarly + dumpTempoTimestamp gated behind BEATDETECTOR_DUMP_HIST=1; optional file output via BEATDETECTOR_DUMP_FILE=<path>. Silent in production.
    MIRPipeline             → Coordinator: all analyzers → FeatureVector for GPU; owns BeatPredictor (D-028)
    BeatPredictor           → IIR beat-phase predictor: rising-edge onset → period estimate → beatPhase01/beatsUntilNext in FeatureVector (MV-3b, D-028)
    PitchTracker            → YIN autocorrelation pitch detector (vDSP_dotpr, 2048-sample window, 80–1000 Hz, local-minimum refinement) → vocalsPitchHz/Confidence in StemFeatures (MV-3c, D-028)
    SelfSimilarityMatrix    → Ring buffer of feature vectors, vDSP cosine similarity
    NoveltyDetector         → Checkerboard kernel boundary detection, adaptive threshold
    StructuralAnalyzer      → Section boundary prediction, repetition detection
    StemAnalyzer            → Per-stem energy (4× BandEnergyProcessor) + beat (1× BeatDetector on drums) + rich metadata (MV-3a) + PitchTracker (MV-3c) → StemFeatures (64 floats, 256 bytes)
  ML/
    StemSeparator.swift      → STFT → MPSGraph → iSTFT pipeline, StemSeparating protocol
    StemSeparator+Reconstruct → iSTFT reconstruction + mono averaging
    StemModel.swift          → MPSGraph Open-Unmix HQ engine, pre-allocated UMA I/O buffers
    StemModel+Graph         → MPSGraph construction: per-stem subgraph, LSTM, FC, BN helpers
    StemModel+Weights       → Weight manifest parsing, .bin loading, BN fusion (12 fusions at init)
    MoodClassifier.swift    → vDSP_mmul MLP → valence/arousal, MoodClassifying protocol
    MoodClassifier+Weights  → Hardcoded Float32 weight arrays (3,346 params)
  Renderer/
    MetalContext            → MTLDevice, command queue, triple-buffered semaphore, shared-texture helper
    ShaderLibrary           → Auto-discover .metal files, runtime compilation, cache
    RenderPipeline          → Render graph dispatch, feedback ping-pong, activePasses guarded by passesLock
    RenderPipeline+Draw     → Draw paths: direct, mesh, postProcess, feedback, warp, blit, particles
    RenderPipeline+MeshDraw → Mesh shader draw: drawWithMeshShader, offscreen pass
    RenderPipeline+PostProcess → HDR post-process: drawWithPostProcess, lazy texture allocation
    RenderPipeline+RayMarch → Ray march draw: drawWithRayMarch + per-frame audio-reactive SceneUniforms modulation (light intensity from any-band beat, lightColor from valence, fogFar from arousal, camera dolly from features.time, glass-fin position from bass). Reads BaseSceneSnapshot for additive-on-baseline behaviour.
    RenderPipeline+MVWarp   → MV-2 per-vertex feedback warp: MVWarpPipelineBundle, MVWarpState, setupMVWarp, drawWithMVWarp (3-pass: warp grid → compose → blit), clearMVWarpState, reallocateMVWarpTextures
    RenderPipeline+ICB      → Indirect command buffer: drawWithICB, populate compute + execute render
    FrameBudgetManager      → Pure-state frame timing governor: QualityLevel ladder (full→noSSGI→noBloom→reducedRayMarch→reducedParticles→reducedMesh), asymmetric hysteresis (3 overruns down / 180 frames up), per-tier Configuration factories, reset() on preset change. Exposes recentMaxFrameMs/recentFramesObserved (30-slot rolling window) via FrameTimingProviding for ML scheduling. D-057, D-059.
    MLDispatchScheduler     → Pure-state ML dispatch controller: gates stem separation dispatch onto frame-timing-clean moments. Decision enum (dispatchNow/defer/forceDispatch), DispatchContext value type, decide(context:) algorithm. Tier defaults: 2000ms/30-frame (Tier 1), 1500ms/20-frame (Tier 2). FrameTimingProviding protocol for testability. D-059.
    RayMarchPipeline        → Deferred 3-pass: G-buffer textures, lighting pipeline, composite pipeline. reducedMotion is an OR-gate: a11yReducedMotion || governorSkipsSSGI (D-054, D-057). stepCountMultiplier written to sceneParamsB.z each frame.
    RayMarchPipeline+Passes → SSGI pass extraction for file-length compliance
    PostProcessChain        → HDR scene texture, bloom ping-pong, 4 pipeline states, ACES composite. bloomEnabled gates bright-pass + blur; composite always runs for ACES tone-mapping.
    IBLManager              → Irradiance cubemap (32²) + prefiltered env (128², 5 mips) + BRDF LUT (512²)
    TextureManager          → 5 noise textures via Metal compute at init, bound at texture(4–8)
    Geometry/ParticleGeometry → Protocol for per-preset particle compute+render pipelines (D-097). Three members: update(features:stemFeatures:commandBuffer:), render(encoder:features:), activeParticleFraction. AnyObject + Sendable. `RenderPipeline.particleGeometry` storage and `setParticleGeometry(_:)` API are typed as `(any ParticleGeometry)?`. Future particle presets each ship their own conformer rather than parameterizing a shared pipeline.
    Geometry/ProceduralGeometry → GPU compute particle system for Murmuration: UMA buffer + compute + render pipelines. activeParticleFraction scales compute dispatch count (governor gate). Conforms to `ParticleGeometry` (D-097); the conformance is the only Murmuration-side change in DM.0 — kernel names, particle count, drag, decay rate are unchanged.
    Geometry/MeshGenerator  → M3+ mesh shader + M1/M2 vertex fallback, draw dispatch abstraction. densityMultiplier passed at object/mesh buffer(1) for M3+ opt-in; no-op on M1/M2 vertex path.
    RayTracing/BVHBuilder   → MTLPrimitiveAccelerationStructure, blocking + non-blocking paths
    RayTracing/RayIntersector → Compute-pipeline intersector, nearest-hit + shadow kernels
    Dashboard/DashboardFontLoader → Resolves Epilogue TTF from bundle Fonts/ subdir; falls back to system sans; OSAllocatedUnfairLock cache; resetCacheForTesting() (DASH.1).
    Dashboard/DashboardTextLayer → Zero-copy MTLBuffer→CGContext→MTLTexture text rasterizer; .bgra8Unorm; permanent CTM flip + textMatrix scaleY=-1; beginFrame()/drawText(...)/commit(into:)/resize. `internal var graphicsContext` exposes the underlying CGContext to DashboardCardRenderer (DASH.2, D-082).
    Dashboard/DashboardCardLayout → Pure value type: title + ordered Row enum (.singleValue / .bar / .progressBar) + fixed width + padding/title size/row spacing. Stacked rows — label on top, value below — heights single=39 (11pt label + 4pt gap + 24pt value), bar=32 (11pt label + 4pt gap + 17pt bar+value band), progressBar=32 (matches bar — same visual mass). `.bar` is signed-from-centre (D-082). `.progressBar` is unsigned 0–1 left-to-right fill, used for ramps (beat phase, bar phase, frame budget) — DASH.3, D-083. `height` computed from `padding + titleSize + (rowSpacing + rowHeight)×N + padding`; titleSize term contributes 0 when title is empty. DASH.2 + DASH.2.1 + DASH.3, D-082, D-083.
    Dashboard/DashboardCardRenderer → Stateless Sendable struct. Composes DashboardTextLayer.drawText + direct CGPath geometry into the same shared CGContext. Painting order: chrome (rounded `Color.surfaceRaised`@0.92α + 1px `Color.border` stroke) → bar geometry → text. Stacked rows: 11pt UPPERCASE label (`Color.textBody` — passes WCAG AA at ~10:1 over the surface; textMuted was ~3.3:1 and failed AA) above the value (singleValue) or above bar+right-aligned value text (bar / progressBar). Bar geometry is centred on its own mid-x (NOT the card centre — the bar reserves a 56pt right-side column for value text). Progress bars share the bar chrome path (`drawBarChrome` is `internal` so the `+ProgressBar` extension can reuse it) and fill left-to-right from `barLeft` to `barLeft + clamp(value, 0, 1) × barWidth` — kept as a separate helper from `.bar` rather than collapsing into a `signed:` Boolean (D-083). The 0.92α chrome is the only sanctioned glassmorphic surface in the dashboard (.impeccable.md "purposeful glassmorphism" exception). DASH.2 + DASH.2.1 + DASH.3, D-082, D-083.
    Dashboard/BeatCardBuilder → Pure Sendable struct mapping `BeatSyncSnapshot` → `DashboardCardLayout` for the BEAT card. 4 rows in display order: MODE / BPM / BAR / BEAT. Lock-state colour mapping (DASH.7.2, D-089 — AAA contrast on dark surface): REACTIVE / UNLOCKED `textBody`, LOCKING `coral`, LOCKED `teal`. BAR fill `purple` (DASH.7.2, was `purpleGlow` which failed 3:1 on dark). BEAT fill `coral` (D-083). No-grid (`gridBPM <= 0`) emits `—` placeholders with bars at zero. BEAT phase derived as `barPhase01 × beatsPerBar − (beatInBar − 1)` clamped to [0, 1]. DASH.3 → DASH.7.1 → DASH.7.2, D-083 + D-088 + D-089.
    Dashboard/StemsCardBuilder → Pure Sendable struct mapping `StemEnergyHistory` → `DashboardCardLayout` for the STEMS card. **DASH.7 supersedes DASH.4; DASH.7.1 corrects colour**: 4 `.timeseries` rows (sparklines) in percussion-first order DRUMS / BASS / VOCALS / OTHER, range `-1.0 ... 1.0`, uniform `Color.teal` (stem indicators are MIR data per `.impeccable.md`). `valueText` is empty — the sparkline IS the readout (Sakamoto-liner-note discipline, D-088). Empty samples render baseline only — stable absence-of-signal state. DASH.4 → DASH.7 → DASH.7.1, D-084 + D-087 + D-088.
    Dashboard/PerfSnapshot → Sendable value type wrapping renderer governor (`FrameBudgetManager.recentMaxFrameMs` / `currentLevel` / `targetFrameMs`) + ML dispatch state (`MLDispatchScheduler.lastDecision` / `forceDispatchCount`) for the PERF card. Decision/quality enums encoded as `Int + displayName: String` so the snapshot is trivially `Sendable` without importing the manager enums. `.zero` neutral default. DASH.5, D-085.
    Dashboard/PerfCardBuilder → Pure Sendable struct mapping `PerfSnapshot` → `DashboardCardLayout` for the PERF card. **Dynamic row count** (DASH.7) + **brand-aligned, AAA-contrast status colours** (DASH.7.1 → DASH.7.2): FRAME always present (`.progressBar`, `"{recent} / {target}ms"` compact value text, status colour `teal` (healthy) / `coral` (stressed) at 70% budget threshold via `warningRatio` constant); QUALITY hides when governor is `full` AND warmed up — surfaces in `coral` when downshifted; ML hides on idle / `dispatchNow` — surfaces in `coral` only on `defer` / `forceDispatch`. Card collapses to one row in steady-state happy path. Uses only the project's brand palette (purple/coral/teal + neutrals); the `statusGreen` / `statusYellow` tokens are retired from this builder, and DASH.7.2 promoted `coralMuted` → `coral` for AA contrast on the dark surface. DASH.5 → DASH.7 → DASH.7.1 → DASH.7.2, D-085 + D-087 + D-088 + D-089.
    Dashboard/StemEnergyHistory → Sendable value type holding up to 240 recent samples per stem (drums / bass / vocals / other), oldest first. Capacity ≈ 8 s at 30 Hz. Held privately by `DashboardOverlayViewModel` as a mutable ring; snapshotted into this immutable form for `StemsCardBuilder.build(from:)` per redraw. DASH.7, D-087.
    Dashboard/DashboardSnapshot → Sendable bundle of `(BeatSyncSnapshot, StemFeatures, PerfSnapshot)` for one frame. Published from `VisualizerEngine.@Published dashboardSnapshot` on each rendered frame; consumed by `DashboardOverlayViewModel` via Combine with `.throttle(for: .milliseconds(33))` (~30 Hz). `Equatable` synthesized for `PerfSnapshot`; `BeatSyncSnapshot` + `StemFeatures` use private `bytewiseEqual<T>` (no Equatable conformance broadened on shared types — D-086 Decision 4 stands). DASH.7, D-087.
    Shaders/Common.metal    → FeatureVector / FeedbackParams / StemFeatures / SceneUniforms MSL structs, hsv2rgb, fullscreen_vertex, feedback shaders. `FeatureVector` is 192 bytes / 48 floats and `StemFeatures` is 256 bytes / 64 floats — byte-identical to the preset preamble in `PresetLoader+Preamble.swift`. The first 32 / 16 floats match the pre-MV-1/MV-3 layout exactly so existing engine-library readers (Murmuration's `particle_update`, MVWarp shaders, feedback shaders) are byte-identical; the extended tail (MV-1 deviation primitives, MV-3a per-stem rich metadata, MV-3b beat phase, MV-3c vocals pitch) is locked for future engine kernels and currently unused after Drift Motes' removal (D-102) — see D-099 for the rationale.
    Shaders/MVWarp.metal    → Default engine-library mvWarp implementations (mvWarp_vertex_default, identity warpPerFrame/Vertex); fixed fragment shaders shared by all presets (mvWarp_fragment, mvWarp_compose_fragment, mvWarp_blit_fragment)
    Shaders/MeshShaders.metal → Mesh pipeline structs, object/mesh/fragment + fallback vertex shaders
    Shaders/Particles.metal → Murmuration compute kernel (`particle_update`) + bird silhouette vertex/fragment (`particle_vertex` / `particle_fragment`). Declares the shared `Particle` (64 bytes, `packed_float4 color`) and `ParticleConfig` (32 bytes) MSL structs once for the engine library.
    Shaders/PostProcess.metal → Bright pass, Gaussian blur H/V, ACES composite
    Shaders/RayTracing.metal → RT structs, nearest-hit kernel, shadow kernel, camera ray utils
    Shaders/RayMarch.metal   → Cook-Torrance PBR deferred lighting (IBL ambient tinted by lightColor), composite fragment, depth/G-buffer debug pipelines
    Shaders/SSGI.metal       → Screen-space global illumination (8-sample spiral, half-res, additive blend)
    Shaders/NoiseGen.metal   → Compute kernels: gen_perlin_2d, gen_perlin_3d, gen_fbm_rgba, gen_blue_noise
    Shaders/IBL.metal        → IBL generation kernels + sampling utilities
  Presets/
    PresetLoader            → Auto-discover, compile standard + additive + mesh + ray march pipelines, skip utility files
    PresetLoader+Preamble   → Shared preamble: FeatureVector struct → V.1 Noise utility tree → V.1 PBR utility tree → ShaderUtilities → noise samplers → preset code. Forwards `sceneSDF(p, FeatureVector& f, SceneUniforms& s, StemFeatures& stems)` and `sceneMaterial(p, matID, f, s, stems, albedo, roughness, metallic)` so ray-march presets can do per-stem routing (Milkdrop-style) directly in sceneSDF/sceneMaterial. StemFeatures plumbed through G-buffer fragment call sites. Presets should apply the D-019 warmup fallback `smoothstep(0.02, 0.06, totalStemEnergy)` to mix between FeatureVector proxies and stem direct reads (see VolumetricLithograph for reference implementation). Also contains `mvWarpPreamble` (MV-2, D-027): MVWarpPerFrame struct, WarpVertexOut, warpSampler, forward declarations for preset `mvWarpPerFrame`/`mvWarpPerVertex`, and the `mvWarp_vertex` 32×24 grid shader. SceneUniforms defined via `#ifndef SCENE_UNIFORMS_DEFINED` guard so direct (non-ray-march) mv_warp presets compile correctly.
    PresetDescriptor        → JSON sidecar: passes, feedback params, scene camera/lights, stem affinity, certified/rubric_profile/rubric_hints (V.6)
    PresetDescriptor+SceneUniforms → Constructs SceneUniforms from descriptor (camera basis, light, fog, near/far). FOV converted from JSON degrees → radians exactly once.
    PresetCategory          → 10 cream-of-crop aesthetic themes + transition slot (D-123). `family` is optional on PresetDescriptor; diagnostic presets carry no family.
    Certification/RubricResult → Value types: RubricCategory (mandatory/expected/preferred), RubricItemStatus (pass/fail/exempt/manual), RubricItem, RubricProfile (full/lightweight), RubricResult, RuntimeCheckResults. (V.6)
    Certification/FidelityRubric → DefaultFidelityRubric: pure static + runtime rubric evaluator for SHADER_CRAFT.md §12. FidelityRubricEvaluating protocol. Heuristics: M1 cascade (scale markers/scale-literal count), M2 octave (fbmN/warped_fbm/ridged_mf), M3 materials (V.3 mat_* callsites ≥3), M4 deviation (D-026 fields present + no absolute-threshold anti-patterns), M5 silence (runtime), M6 perf (complexity_cost gate), M7 frame match (always manual). E1–E4 expected, P1–P4 preferred. Lightweight L1–L4 profile. (V.6)
    Certification/PresetCertificationStore → actor; loads and caches RubricResult for all production presets. Reads .metal + .json from Bundle.module Shaders dir. setResults(_:) for test injection. (V.6)
    Shaders/ShaderUtilities.metal → 55 reusable functions: noise, SDF, PBR, ray march, UV, color, atmosphere (legacy camelCase names)
    Shaders/Utilities/Noise/  → V.1 Noise utility tree (9 files, snake_case, D-045). Load order: Hash → Perlin → Simplex → FBM → RidgedMultifractal → Worley → DomainWarp → Curl → BlueNoise. Provides: hash_u32/f01 family, perlin2d/3d/4d, simplex3d/4d, fbm4/8/12/fbm_vec3, ridged_mf, worley2d/3d/fbm, warped_fbm/vec, curl_noise, blue_noise_sample/ign/ign_temporal.
    Shaders/Utilities/PBR/    → V.1 PBR utility tree (9 files, snake_case, D-045). Load order: Fresnel → NormalMapping → BRDF → Thin → DetailNormals → Triplanar → POM → SSS → Fiber. Provides: fresnel_schlick/roughness/dielectric/f0_conductor, ggx_d/g_schlick/g_smith, brdf_ggx/lambert/oren_nayar/ashikhmin_shirley/cook_torrance, decode_normal_map/dx, ts_to_ws/ws_to_ts, tbn_from_derivatives, combine_normals_udn/whiteout, triplanar_blend_weights/sample/normal, parallax_occlusion/shadowed (POMResult), sss_backlit/wrap_lighting, fiber_marschner_lite/trt_lobe (FiberBRDFResult), thinfilm_rgb/hue_rotate.
    Shaders/Utilities/Geometry/ → V.2 Geometry utility tree (6 files, snake_case, D-045/D-055). Load order: SDFPrimitives → SDFBoolean → SDFModifiers → SDFDisplacement → RayMarch → HexTile. Provides: 30 sd_* SDF primitives (sd_sphere/box/torus/cylinder/capsule/gyroid/schwarz_p/d/helix/mandelbulb_iterate/etc.), op_union/subtract/intersect/smooth_union/subtract/intersect/chamfer/blend, mod_repeat/mirror/twist/bend/scale/round/onion/extrude/revolve, displace_lipschitz_safe/fbm/perlin/beat_anticipation/energy_breath, ray_march_adaptive/normal_tetra/soft_shadow/ao (RayMarchHit struct), hex_tile_uv/weights (HexTileResult struct).
    Shaders/Utilities/Volume/   → V.2 Volume utility tree (5 files, snake_case, D-055). Load order: HenyeyGreenstein → ParticipatingMedia → Clouds → LightShafts → Caustics. Provides: hg_phase/schlick/dual_lobe/mie/transmittance/phase_audio, VolumeSample/vol_sample_zero/vol_density_*/vol_accumulate/vol_composite/vol_inscatter, cloud_density_cumulus/stratus/cirrus/cloud_march/cloud_lighting, ls_radial_step_uv/ls_shadow_march/ls_sun_disk/ls_intensity_audio, caust_wave/fbm/animated/audio.
    Shaders/Utilities/Texture/  → V.2 Texture utility tree (5 files, snake_case, D-055). Load order: Voronoi → ReactionDiffusion → FlowMaps → Procedural → Grunge. Provides: VoronoiResult/voronoi_f1f2/voronoi_3d_f1/voronoi_cracks/leather/cells, rd_pattern_approx/animated/spots/stripes/worms/rd_step/rd_colorize_tri, flow_sample_offset/blend_weight/curl_advect/noise_velocity/audio/layered, proc_stripes/checker/grid/hex_grid/dots/weave/brick/fish_scale/wood, grunge_scratches/rust/edge_wear/fingerprint/dust/dirt_mask/crack/composite (GrungeResult).
    Shaders/Utilities/Color/    → V.3 Color utility tree (4 files, snake_case, D-062). Load order: Palettes → ColorSpaces → ChromaticAberration → ToneMapping. Provides: palette/palette_warm/palette_cool/palette_neon/palette_pastel, gradient_2/3/5, lut_sample, rgb_to_hsv/hsv_to_rgb, rgb_to_lab/lab_to_rgb, rgb_to_oklab/oklab_to_rgb, chromatic_aberration_radial/directional, tone_map_aces/aces_full/reinhard/reinhard_extended/filmic_uncharted. Legacy palette() deleted from ShaderUtilities.metal; toneMapACES/toneMapReinhard retained as superseded aliases (D-062).
    Shaders/Utilities/Materials/ → V.3 Materials cookbook (5 files, snake_case, D-062). Load order: MaterialResult → Metals → Dielectrics → Organic → Exotic. Provides: MaterialResult struct, FiberParams, material_default, triplanar_detail_normal (3-param procedural, distinct from V.1 texture form), triplanar_normal (3-param overload), mat_polished_chrome, mat_brushed_aluminum, mat_gold, mat_copper, mat_ferrofluid, mat_ceramic, mat_frosted_glass, mat_wet_stone, mat_bark, mat_leaf, mat_silk_thread, mat_chitin, mat_ocean, mat_ink, mat_marble, mat_granite, mat_velvet, mat_sand_glints, mat_concrete. 19 surface-material recipes returning MaterialResult; callers unpack into sceneMaterial() out-params (D-062(c)). V.4 additions: mat_velvet (Organic — retro-reflective fuzz via pow(1-NdotV,2) fuzz term), mat_sand_glints (Exotic — hash-lattice sparkle via hash_f01), mat_concrete (Dielectrics — worley_fbm variation + fbm8 height-gradient normal + grunge). D-063.
    Shaders/Waveform.metal  → Spectrum bars + oscilloscope
    Shaders/Plasma.metal    → Demoscene plasma
    Shaders/Nebula.metal    → Radial frequency nebula
    Shaders/Starburst.metal → Murmuration sky backdrop (MV-2: mv_warp pass replaces feedback+particles; bass_att_rel drives zoom breath, mid_att_rel drives slow rotation, decay=0.97 for long cloud smear)
    Shaders/GlassBrutalist.metal → Brutalist corridor — static architecture; only the glass-fin X-position deforms with bass (Option A design, see DECISIONS D-020). Light/fog/colour modulated in shared Swift path.
    Shaders/KineticSculpture.metal → Interlocking lattice of Brushed Aluminum + Frosted Glass + Liquid Mercury, abstract ray march. FOV in degrees (post-fix; was radians, see commit history).
    Shaders/TestSphere.metal → Minimal pipeline-verification SDF (sphere + floor); used for end-to-end ray-march compile/render test.
    Shaders/SpectralCartograph.metal → Instrument-family diagnostic preset. Four-panel real-time MIR visualiser: TL=FFT spectrum (log-freq, centroid-coloured), TR=3-band deviation meters (D-026 compliant), BL=valence/arousal phase plot with 8s trail, BR=scrolling graphs for beat_phase01/bass_dev/bar_phase01 (BAR φ). Reads SpectralHistoryBuffer at buffer(5). Direct pass only; no feedback, no warp. V2 (DSP.2 sign-off): per-panel header labels via inline 3×5 bitmap font (no texture atlas); centered beat orb at (0.5,0.5) with amber fill keyed to beat_phase01 + white ring flash at onset + BPM digits above + session-mode label below; BR panel beat_phase01 row overlaid with cached-BeatGrid tick marks from SpectralHistoryBuffer[2402..2417] so zero-crossings can be visually verified against ground truth. Reactive mode: orb pulses via BeatPredictor fallback, ticks hidden (Float.infinity sentinel). DSP.3.1: session-mode label reads SpectralHistoryBuffer[2420] — `○ REACTIVE` (grey, no grid), `◐ PLANNED · UNLOCKED` (muted amber, grid present <4 matched onsets), `◑ PLANNED · LOCKING` (yellow-green, approaching lock), `● PLANNED · LOCKED` (bright green, locked). Diagnostic hold via `L` shortcut suppresses LiveAdapter mood-override; `is_diagnostic: true` in sidecar suppresses auto-selection.
    Shaders/Arachne.metal → V.7.7C.2: foreground hero web is build-aware via webs[0] Row 5 BuildState (`build_stage` / `frame_progress` / `radial_packed` / `spiral_packed`). The "Foreground hero web" block in `arachne_composite_fragment` maps Row 5 to the legacy `(stage, progress)` signature `arachneEvalWeb` already understands: `.frame` → stage=0u + progress=frame_progress; `.radial` → stage=1u + progress=radial_packed/13.0; `.spiral` → stage=2u + progress=spiral_packed/104.0; `≥ .stable` → stage=3u + progress=1.0. Pool loop starts at wi=1 so the foreground slot doesn't double-render; pool webs[1..3] continue under V.7.5 spawn/eviction (background depth context). Hub knot stays `fbm4`-min threshold-clipped (NOT concentric rings, §5.4); spiral winds INWARD (chord radius DECREASES with k, §5.6); chord-segment SDF stays `sd_segment_2d` (Failed Approach #34 lock). Staged WORLD + COMPOSITE fragments use shared `drawWorld()` + `arachneEvalWeb()` free functions. WORLD stage `arachne_world_fragment` reads `webs[0].row4` for mood and `f.mid_att_rel` for shaft engagement; renders the §4 atmospheric abstraction (full-frame `mix(botCol, topCol, …)` sky band with low-frequency fbm4 modulation + aurora ribbon at high arousal + volumetric atmosphere — beam-anchored fog `0.15 + 0.15 × midAttRel` inside cones / ambient outside, 1–2 mood-driven god-ray light shafts at brightness `0.30 × val`, dust motes confined inside shaft cones only) into a per-stage `.rgba16Float` offscreen texture. V.7.7C.5 (D-100) retired the previous six-layer dark close-up forest + §5.9 anchor-twig SDF loop; `kBranchAnchors[6]` constants stay as polygon vertex sources but no longer render as visible twigs. **V.7.7C.5.1 (D-100 follow-up — visual craft pass)**: silk line widths halved + halo sigmas/magnitudes halved + silk luminescence dimmed (silkTint 0.85 → 0.55, hub knot 1.20 → 0.70, ambient 0.40 → 0.20, axial 0.6 → 0.3); per-segment macro-shape variation via `ancSeed = arachHashU32(webs[0].rng_seed ^ 0xCA51u)` (new `arachHashU32` helper) so each Arachne instance has unique spoke count/aspect/sag/jitter; §4.3 palette pumped (sat 0.25–0.65 → 0.55–0.95, val 0.10–0.30 → 0.30–0.70) with accumulated-audio-time hue cycle ±0.15 swing on top of the Q10 valence-driven base; cross-preset silence anchor re-keyed on raw mood product `arousalNorm × valenceNorm < 0.05`; shaft engagement gate reformulated to floor+scale `0.25 + 0.75 × smoothstep(-0.20, 0.10, midAttRel)` so shafts are visible at 25 % baseline always. COMPOSITE stage `arachne_composite_fragment` samples WORLD at `[[texture(13)]]` on original `uv`, applies §8.2 12 Hz vibration UV jitter (`vibUV = uv + (sin, cos) × ampUV` with `ampUV = 0.0030 × max(f.bass_att_rel, 0) × length(uv − 0.5)`; coherent 8×8 phase quantization via `hash_f01_2(uv × 8)`; `accumulated_audio_time` phase so motion pauses at silence), walks the 4-slot ArachneWebGPU pool at fragment buffer(6) on `vibUV` (foreground hero from Row 5, pool webs via `arachneEvalWeb` chord-segment outside-in capture spiral, ±22% spoke jitter, gravity sag), accumulates strands + photographic dewdrops via the §5.8 Snell's-law recipe (refraction sampling `worldTex` at `2.5 × rDrop` with `eta = 0.752`; Schlick fresnel rim; pinpoint warm specular at the half-vector cap position; dark edge ring; audio gain `(baseEmissionGain + beatAccent)`), then ray-marches the **3D SDF spider** in a `0.15 UV` screen-space patch around the spider's UV anchor (riding the same `vibOffset`): cephalothorax + abdomen ellipsoids smooth-unioned with petiole cut (`op_smooth_subtract`), 8 IK legs with outward-bending analytic knees, 6 eye spheres with per-eye specular at half-vector alignment (V.7.7D §6.1). Spider chitin material inlined per §6.2: `(0.08, 0.05, 0.03)` brown-amber base + thin-film `hsv2rgb(0.55+0.3·NdotV) × 0.15` (biological strength; ≤ 0.20 invariant) + Oren-Nayar fuzz + body shadow + warm rim. Listening pose lifts `tip[0]` / `tip[1]` clip-space Y by `0.5 × kSpiderScale × listenLiftEMA` CPU-side (`ArachneState+ListeningPose.swift`) when sustained low-attack-ratio bass holds for ≥ 1.5 s. **`ArachneWebGPU` is 96 bytes** (Row 5 added V.7.7C.2 — buffer(6) docstring 320→384). `ArachneSpiderGPU` stays at 80 bytes (V.7.7D contract). `mat_frosted_glass` retired V.7.7C from drops; `mat_chitin` (V.3 cookbook) retired V.7.7D from the spider path. Mv_warp helpers retired V.7.7A; legacy `arachne_fragment` + V.7.7A placeholders deleted V.7.7B. **V.7.7C.3 (D-095 follow-up — manual-smoke remediation)**: per-chord spiral visibility gate (chords lay one-at-a-time outside-in, no longer entire rings as complete ovals); pool loop changed to `for (int wi = 1; wi < 1; wi++)` so V.7.5 spawn/eviction churn no longer reaches the shader (foreground hero is the only rendered web); polygon-from-`branchAnchors` path active (decoded from `webs[0].rng_seed` packed by `ArachneState.packPolygonAnchors`; new shader helpers `decodePolygonAnchors` + `rayPolygonHit` + `findBridgeIndex` above `arachneEvalWeb`; spokes ray-clipped to polygon perimeter, frame thread polygon vertices from `polyV[]` with bridge-first stage-0 reveal, spiral chord positions scaled along polygon-clipped spoke lengths via `fracR`); squash transform bypassed in polygon mode. V.7.5 fallback path preserved bytewise when `polyCount = 0` (drawBackgroundWeb dead-reference + PresetRegression unbound buffers). **Remaining V.7.10 deferred sub-items**: per-chord drop accretion via chord-age side buffer; anchor-blob discs at polygon vertices (§5.9 part 2); background-web migration crossfade rendered visual (CPU `backgroundWebs` array still not flushed to GPU). D-019/D-026/D-040/D-041/D-072/D-092/D-093/D-094/D-095 compliant.
    Arachnid/ArachneState.swift → V.7.7C.2: single-foreground build state machine on top of the legacy 4-web pool. `ArachneBuildState` struct (CPU-only) tracks the foreground hero web's progression through `.frame → .radial → .spiral → .stable → .evicting` over ~50–55 s of music, with audio-modulated TIME pacing (`pace = 1.0 + 0.18 × midAttRel + max(0, 0.5 × drumsEnergyDev)`, D-026 ratio ≈ 3.6×). Polygon (4–6 of 6 `kBranchAnchors`) selected at `reset()` via Fisher-Yates + bridge-pair largest-angular-gap; alternating-pair radial draw order computed `[0, n/2, 1, n/2+1, …]` (§5.5); spiral chord radii precomputed strictly INWARD; per-chord birth times appended at lay-down for §5.8 accretion. Pause guard evaluated BEFORE `effectiveDt` so spider trigger freezes accumulators and resume picks up exactly where it paused. `presetCompletionEvent` fires once at `.stable` via `PresetSignaling` conformance defined in `Sources/Orchestrator/ArachneStateSignaling.swift` (Presets cannot import Orchestrator without a module cycle — D-095 documents the placement deviation). `_presetCompletionEvent` is `public let` for the cross-module conformance to reach. `spiderFiredInSegment: Bool` per-segment cooldown replaces V.7.5's 300 s session lock (§6.5); reset on `arachneState.reset()`. `WebGPU` 96 bytes (Row 5 = packed BuildState; written only for `webs[0]`, background webs zero it). 1–2 saturated `ArachneBackgroundWeb` entries in `ArachneState+BackgroundWebs.swift` with migration crossfade timers (foreground 1 → 0.4 joins pool; oldest 1 → 0 evicts; 1 s ramp). V.7.5 pool spawn/eviction kept running additively but **no longer reaches the shader** (V.7.7C.3 / D-095 follow-up retired the pool loop visually). `branchAnchors` two-source-of-truth with MSL `kBranchAnchors[6]` regression-locked by `ArachneBranchAnchorsTests`. V.7.7D listening-pose state (`listenLiftAccumulator` / `listenLiftEMA`) lifts `tip[0]` / `tip[1]` CPU-side; `ArachneSpiderGPU` stays at 80 bytes. **V.7.7C.3 polygon flush**: `writeBuildStateToWebs0` packs `bs.anchors[]` (4-bit count + 6 × 4-bit indices) into `webs[0].rngSeed` (byte offset 28) via the new `Self.packPolygonAnchors(_:)` static helper. Shader decodes via `decodePolygonAnchors` to drive ray-clipped spoke tips + irregular frame thread + polygon-aware spiral chord positions. `webs[0].rngSeed` repurposing is safe — Fix 2 retired V.7.5 pool rendering, so `rngSeed` is no longer consumed by the spawn driver's per-spoke jitter on the shader side. `applyPreset .staged` for "Arachne" calls `arachneState.reset()` immediately after init (canonical polygon-seeding entry point). **BUG-011 round 8 (2026-05-12) — three behavioural changes**: (1) `ArachneBuildState.frameDurationSeconds 3.0 → 2.775` / `radialDurationSeconds 1.5 → 1.389` per radial; new `ArachneBuildState.spiralChordsPerBeat = 3.24` + `spiralChordAccumulator: Float` field carrying fractional residual across rising-edge beats. Total build ~100 s → ~92 s. (2) New `ArachneBuildState.stemEnergySilenceThreshold = 0.02`; `advanceBuildState` zeros `effectiveDt` when `vocalsEnergy + drumsEnergy + bassEnergy + otherEnergy < 0.02` — Arachne no longer constructs during silence / prep / source-app paused. `pausedBySpider` flag is set BEFORE the silence check so the spider-pause guard still latches correctly. (3) `Arachne.json` now sets `"wait_for_completion_event": true`; `PresetDescriptor.waitForCompletionEvent` short-circuits `maxDuration(forSection:)` to `.infinity` (same path as `isDiagnostic`) so segments are no longer capped at ~72 s by the V.7.6.C formula. Mood-override suppression added in `applyLiveUpdate` (active segment located by track-relative position; flagged presets get `presetOverride` stripped, `updatedTransition` honoured). The existing `wirePresetCompletionSubscription` path now delivers the transition trigger — Arachne builds reach `.stable` and emit `presetCompletionEvent`, which calls `nextPreset()`. Section boundaries still hard-stop segments (`remainingInSection` cap unchanged) — known limitation, acceptable for sections ≥ 60 s. (Increments 3.5.5 / V.7.7C.2 / V.7.7C.3 / D-095 / BUG-011 round 8)
    Shaders/Gossamer.metal → Bioluminescent hero-web sonic resonator (Increment 3.5.6, v3 geometry). Direct fragment + mv_warp. 17 explicitly-defined irregular spoke angles (spacing 0.27–0.77 rad, one 0.77 rad open sector lower-right). Hub at (0.465, 0.32) — upper screen — clips top spiral rings into asymmetric arcs naturally. No formula, no hash-jitter. Up to 32 propagating color waves emitted when vocalsPitchConfidence > 0.35 OR |vocalsEnergyDev| > 0.05; wave hue baked from YIN pitch, saturation from other-stem density. mv_warp trails accumulate wave echoes. Ambient drift floor keeps ≥2 waves at silence. D-026/D-019 compliant.
    Gossamer/GossamerState.swift → Per-preset world state: 32-wave pool, Wave structs with birthTime/hue/saturation/amplitude, GossamerGPU buffer (528 bytes) at fragment buffer(6). Vocal confidence gate + FV fallback. Retirement when age > maxWaveLifetime=6s. (Increment 3.5.6)
    Shaders/Stalker.metal → Bioluminescent spider silhouette mesh shader (Increment 3.5.7). 2-threadgroup dispatch: threadgroup 0 = dim static background web (hub + anchors + radials + spiral), threadgroup 1 = articulated spider body + 8 legs. Listening pose (raised front legs) fires on sustained low-attack-ratio bass. Additive blend; near-black silhouette reads against dark background via rim emissive. Organic family. Completes the Arachnid Trilogy.
    Stalker/StalkerGait.swift → Pure alternating-tetrapod gait solver: 8 Leg structs with hip/tip/knee, 2-segment IK with outward knee bend, beat phase-lock with soft pull (not snap), free-run fallback at 2.5 cycles/sec, listening-pose front-leg raise blend. (Increment 3.5.7)
    Stalker/StalkerState.swift → Per-preset world state: GaitSolver + scene mode state machine (.entering→.crossing→.listening→.exiting→.pausing), sustained-bass accumulator (0.75s threshold, low bassAttackRatio gate), StalkerGPU buffer (352 bytes) at object/mesh buffer(1). FV fallback via sub_bass + bass_att_rel heuristic. (Increment 3.5.7)
    Shaders/VolumetricLithograph.metal → Psychedelic linocut terrain (MV-2 / v4.1). fbm3D heightfield swept by `s.sceneParamsA.x` at slow rate 0.015; melody-primary blend `0.75 × (0.5 + f.mid_att_rel) + 0.35 × (0.3 + f.bass_att_rel × 0.7)` — deviation-driven, genre-stable across AGC shifts (MV-1 / D-026). Stem-accurate drivers blend in via `smoothstep(0.02, 0.06, totalStemEnergy)` warmup (D-019). Forward camera dolly at 1.8 u/s (configured in VisualizerEngine+Presets.swift). Three strata with narrow linocut coverage (~15% peaks): palette-tinted near-black valleys, razor-thin emissive ridge-line seam, polished-metal peaks. Peaks use IQ cosine `palette()` driven by terrain noise + audio time + `0.5 + f.mid_att_rel × 0.5` (melody-modulated hue) + valence. Accent/strobe from `smoothstep(0.30/0.70, stems.drums_beat)` with FV fallback `smoothstep(0.35, 0.70, f.spectral_flux)`. `f.mid_dev × 1.5` polishes peak roughness. `scene_fog: 0` truly disables fog. Miss/sky pixels tinted by `scene.lightColor.rgb`. SSGI omitted. MV-2: mv_warp pass adds temporal feedback accumulation — melody-driven zoom breath (mid_att_rel × 0.003), valence-driven rotation, decay=0.96; per-vertex UV ripple from bass (horizontal) and melody (vertical) at 0.004 UV amplitude. Passes: ray_march + post_process + mv_warp.
    Shaders/LumenMosaic.metal → Vibrant backlit pattern-glass panel (Phase LM CLOSED, **certified 2026-05-12 at LM.7**; `LumenMosaic.json` `certified: true`; `"Lumen Mosaic"` ∈ `FidelityRubricTests.certifiedPresets`). Three landed layers stack in `sceneMaterial` (in evaluation order): LM.4.6 per-cell palette → LM.6 cell-depth gradient + optional hot-spot → frost diffusion → LM.7 per-track tint inside `lm_cell_palette`. **LM.7 (per-track aggregate-mean RGB tint, latest, 2026-05-12)**: inside `lm_cell_palette`, a per-track tint vector `trackTint = (rawTint - meanShift) × kTintMagnitude (0.25)` derived from `lumen.trackPaletteSeed{A,B,C}` (∈ [−1, +1] from FNV-1a hash of "title | artist") is added to the per-cell uniform random RGB before `saturate(...)`. `meanShift` is the average of the three seed components — subtracting it projects the tint onto the chromatic plane perpendicular to (1,1,1)/√3, so achromatic-aligned seeds (all-positive → toward-white wash; all-negative → toward-black mud) collapse to zero tint instead of washing the panel. Result: each track plays at a visibly distinct panel-aggregate mean (warm / cool / amber / teal / etc.); achromatic-aligned tracks land at LM.4.6-neutral. Per-cell freedom preserved in spirit — every cell still rolls a colour from the full uniform RGB cube; only the sampling window slides per track. Trade-off accepted by Matt 2026-05-12: most colours remain reachable on every track, but the most-extreme cube corners are forfeit at seedA/B/C = ±1 (clamp pile-up at the cube faces). **LM.6 (cell-depth gradient + optional hot-spot, 2026-05-12)**: between palette lookup and frost diffusion in `sceneMaterial`, two albedo-only modulations on `cell_hue`. (1) depth gradient — `cellRadius = cellV.f2 × kDepthGradientFalloff (1.0)`, `depth01 = 1 - smoothstep(0, cellRadius, cellV.f1)`, `cell_hue *= mix(kCellEdgeDarkness (0.55), 1.0, depth01)`: full brightness at cell centre, 0.55 × hue at cell boundary; gives each cell a "domed" 3D-glass read instead of flat-painted. (2) optional hot-spot — `hotSpot = pow(1 - smoothstep(0, kHotSpotRadius (0.15) × cellV.f2, cellV.f1), kHotSpotShape (4.0))`, `cell_hue += hotSpot × kHotSpotIntensity (0.30) × cell_hue`: 30 % brightness boost at the inner 15 % of each cell, additive on the cell's own hue (not toward white — palette character preserved), sharp pow^4 falloff. **The SDF normal stays flat (`kReliefAmplitude = 0`, `kFrostAmplitude = 0`); LM.6 is albedo modulation, not a geometric perturbation, and the matID==1 lighting fragment still skips Cook-Torrance entirely** (per the LM.3.2 round-7 / Failed Approach lock that retired normal-driven specular after the per-pixel dot artifacts). Driven by the Voronoi `f1/f2` field already computed for cell ID + frost; zero extra cost. **LM.4.6 (pure uniform random RGB per cell — supersedes LM.4.5.x's HSV-with-rules and the briefly-attempted anchor-distribution model):** `lm_cell_palette(cellHash, lumen)` returns three bytes of `lm_hash_u32(cellHash ^ (uint(step) × 0x9E3779B9u) ^ trackSeed ^ (sectionSalt × 0xCC9E2D51u))` mapped to RGB ∈ [0, 1]. Each (cell, beat, track, section) tuple → unique colour from the 16M-colour RGB cube. No HSV indirection, no coupling rule, no mood gamma, no sat floor, no anchors, no zones. Per-cell INDEPENDENCE is the contract — Matt 2026-05-11 explicit ask: "EVERY CELL CAN BE INDEPENDENT OF ITS NEIGHBORS... I literally want ANY possible color to be possible within ANY cell." **Section salt** is `lumen.bassCounter / kSectionBeatLength (64)` — every ~32 s on 120 BPM (resets on track change because bassCounter resets); replaces the broken LM.4.5.3 `accumulatedAudioTime / 25` proxy that maxed at ~10 over 100 s of music (audio-energy accumulator, not seconds). **Per-cell brightness** in `lm_cell_intensity` lives in `[kCellBrightnessMin (0.85), kCellBrightnessMax (1.15)] × bar pulse` — narrow range so every cell reads as "lit" (LM.4.5.3's wide [0.30, 1.60] produced ~30 % dim/gray cells). `kLumenEmissionGain (RayMarch.metal)` is back at 1.0. The team/period beat-step ratchet (LM.3.2 carry-over: 30/35/25/10 % bass/mid/treble/static teams × Pareto period 1/2/4/8) is preserved — drives the per-beat colour change. Slot-8 GPU ABI unchanged (`LumenPatternState` stride still 376); `trackPaletteSeed{A,B,C,D}` plumbing unchanged. **Honest math caveat documented in the file header**: uniform random sampling produces statistically similar panel-aggregates across tracks (law of large numbers — different specific colours per cell, same distribution shape). Visual track-to-track distinction at the panel level requires biasing the per-cell distribution somehow, which Matt rejected after extensive iteration through anchor-distribution / per-track hue region / coupling rules / sat floors (each rejected for restricting "any colour possible per cell"). LM.4.6 is the agreed-on contract: per-cell freedom over panel-level distinction. **Constants retired across LM.4.5.x → LM.4.6**: `kCardSize (48)`, `kCardValMin/Max (0.08, 0.95)`, `kSatFloor (0.70)`, `kPastelSatCutoff (0.30)`, `kPastelValCap (0.50)`, `kValSatCouplingMargin (0.05)`, `kMoodGammaLowArousal/HighArousal (1.8, 0.55)`, `kAnchorJitterMagnitude (0.20)`, `kSectionPeriodSeconds (25.0)`, plus the LM.3.2 IQ-palette block (8 endpoints + `kPaletteMoodPhaseShift` + `kSeedMagnitude{A,B,C,D}` + `kPaletteStepSize`). **Active constants**: `kCellBrightnessMin/Max (0.85, 1.15)`, `kBarPulseMagnitude/Shape (0.20, 8.0)`, `kBassTeamCutoff/MidTeamCutoff/TrebleTeamCutoff (30, 65, 90)`, `kSectionBeatLength (64)`, **LM.6**: `kCellEdgeDarkness (0.55)`, `kDepthGradientFalloff (1.0)`, `kHotSpotRadius (0.15)`, `kHotSpotShape (4.0)`, `kHotSpotIntensity (0.30)`, **LM.7**: `kTintMagnitude (0.25)`. PresetRegression Lumen Mosaic golden hash unchanged at `0xF0F0C8CCCCC8F0F0` (regression harness leaves slot 8 zero-bound; dHash 9×8 luma quantization at 64×64 dominated by Voronoi cell structure, not palette algorithm — real visual divergence visible via `RENDER_VISUAL=1 PresetVisualReviewTests` 9-fixture set). **Tuning surface (M7 review knobs)**: `kSectionBeatLength` (lower → faster section turnover; raise → more stable per-section palette), `kCellBrightnessMin/Max` (widen for more dramatic dim/bright variation, narrow to keep all cells equally lit), `kBarPulseMagnitude` (downbeat flash strength). **LM.4.6.1 hotfix (commit `888bb856`)**: removed underscore digit separators in MSL hex literals (`0x9E37_79B9u` → `0x9E3779B9u`) — Metal/C++ doesn't allow `_` in numeric literals (only the C++14 `'` separator); the underscored form silently dropped Lumen Mosaic from the loader (Failed Approach #44, caught by `PresetLoaderCompileFailureTest`). Swift mirror in `LumenPaletteSpectrumTests` keeps the `_` form (Swift allows it). Original LM.3.2 tuning history follows below.

      **LM.3.2 history (LM.4.5 supersedes the palette section but the team/period/intensity machinery is preserved verbatim).** Single planar `sd_box` at `z = 0`, half-extents = `cameraTangents.xy × 1.50` so panel bleeds 50% past frame on every side (Decision G.1, contract §P.1) — viewer never sees a panel boundary. Voronoi domed-cell relief (`voronoi_f1f2(panel_uv, 30)` height-gradient + smoothstep ridge per SHADER_CRAFT.md §4.5b) and `fbm8` in-cell frost are baked into `sceneSDF` as Lipschitz-safe displacements (kReliefAmplitude = 0.004, kFrostAmplitude = 0.0008) so the G-buffer central-differences normal picks them up; D-021 sceneMaterial signature has no normal channel. **LM.3.2 (D.5 — band-routed beat-driven dance; supersedes LM.3's continuous time-driven cycling and LM.3.1's agent-position backlight, both rejected in production):** Single planar `sd_box` at `z = 0`, half-extents = `cameraTangents.xy × 1.50` so panel bleeds 50% past frame on every side (Decision G.1, contract §P.1) — viewer never sees a panel boundary. Voronoi domed-cell relief (`voronoi_f1f2(panel_uv, 30)` height-gradient + smoothstep ridge per SHADER_CRAFT.md §4.5b) and `fbm8` in-cell frost are baked into `sceneSDF` as Lipschitz-safe displacements (kReliefAmplitude = 0.004, kFrostAmplitude = 0.0008) so the G-buffer central-differences normal picks them up; D-021 sceneMaterial signature has no normal channel. **LM.3.2 (D.5 — band-routed beat-driven dance; supersedes LM.3's continuous time-driven cycling and LM.3.1's agent-position backlight, both rejected in production):** `sceneMaterial` runs `voronoi_f1f2(panel_uv, kCellDensity)` to obtain `v.id` (per-cell deterministic hash). The shader mixes `cell_id ^ lm_track_seed_hash(lumen)` and runs a Murmur-style avalanche `lm_hash_u32(...)` to get a single 32-bit hash that drives team / period / base-phase / jitter assignments — same hash for all four so the cell's identity is one stable bit-pattern. **Team assignment** (`cellHash % 100`): 30 % bass team (counter = `lumen.bassCounter`), 35 % mid team (counter = `lumen.midCounter`), 25 % treble team (counter = `lumen.trebleCounter`), 10 % static team (counter = 0; never advances). **Period assignment** (`(cellHash >> 8) & 0x7`): Pareto-distributed ≈37.5 % period 1 / 25 % period 2 / 25 % period 4 / 12.5 % period 8. The shader does `step = floor(team_counter / period)` and the cell's palette phase = `cell_t + step × kPaletteStepSize (0.137 ≈ 1/φ²) + smoothedValence × kPaletteMoodPhaseShift (0.10)`. **Calibration round 8 (LM.3.2 2026-05-10) — beat envelope removed.** Round 6 dimmed cells to ~0 between beats with a fade-in / fade-out envelope shape; live-session review (Matt 2026-05-10, session `2026-05-10T14-48-52Z`) flagged the dark "pulse off" state between beats as too frequent and visually distracting. Round 8 removes the envelope entirely — cells hold their previous state (palette index from the most recent team-counter step) until the next beat advances the step. The `lm_cell_envelope` helper and `kBeatDecayEnd / kBeatAttackStart` constants are deleted. Per-beat colour change is the only rhythm-coupled visual signal, plus the bar-pulse `1 + 0.30 × pow(saturate(f.bar_phase01), 8.0)` brightness flash on each downbeat preserved in `lm_cell_intensity`. **Calibration round 4 (LM.3.2 2026-05-10) — HSV palette.** `lm_cell_palette` was rewritten to use direct `hsv2rgb()` instead of the V.3 IQ cosine `palette()`. Diagnosis: the IQ form `a + b * cos(2π * (c*t + d))` is structurally pastel-prone — with `a ≈ 0.5` and per-channel `c` rates desynchronising the three cosines, most cells land at mid-saturated mid-tones (pure jewel hues require simultaneous channel extremes which rarely happen). Compounding: `kLumenEmissionGain = 4.0` was multiplying saturated cells above 1.0 where the harness float→Unorm conversion clipped them, destroying saturation. Round 4 ships HSV (saturated hue per cell by construction) + reduces `kLumenEmissionGain` 4.0 → 1.0 (HSV palette is vivid without HDR boost; production output now uniformly bright, no bloom kick on individual cells — correct for stained-glass jewel-tone aesthetic where every cell is equally vivid). Hue = `moodHueCentre + (cell_t - 0.5) × 0.40 + step × kPaletteStepSize + (seedA × 0.30 + seedD × 0.50)` where `moodHueCentre = mix(0.65, 0.02, warm)` (cool → blue, warm → red-orange). Saturation `mix(0.85, 0.98, arousal) ± 0.05 × seedB` floored at 0.78. Value `mix(0.85, 1.00, arousal) ± 0.03 × seedC` floored at 0.80. The legacy IQ palette constants (`kPaletteACool/AWarm/BSubdued/BVivid/CUnison/COffset/DComplementary/DAnalogous` + `kSeedMagnitudeA/B/C/D`) are retained on the file for ABI continuity / round-5+ revisits but unused by the round-4 HSV path. **Round 3 (2026-05-09) — superseded by round 4.** Per-channel sum-balanced perturbations `(sX, sY, -(sX+sY)/2) × magnitude` on IQ `a` and `d` parameters with magnitudes 0.20/0.05/0.20/0.50. `lm_cell_intensity(cellHash, f.bar_phase01)` returns uniform brightness with hash jitter `[0.85, 1.0]` plus a global bar pulse `1.0 + kBarPulseMagnitude (0.30) × pow(saturate(bar_phase01), kBarPulseShape (8.0))` — brief +30 % flash in the last ~8 % of each bar; collapses to no-op when no BeatGrid is installed (`bar_phase01` stays at 0). The four light agents on `LumenPatternState` are still ticked CPU-side for ABI continuity but the `lights[i].intensity / lights[i].colorR/G/B` fields are unused by the LM.3.2 shader. `albedo = clamp(frosted_hue × cell_intensity, 0, 1)`. `outMatID = 1` flags the hit as emission-dominated dielectric (D-LM-matid); the lighting fragment dispatches on `gbuf0.g` to skip Cook-Torrance + screen-space shadows and emit `albedo × kLumenEmissionGain (1.0) + irradiance × kLumenIBLFloor (0.05) × ao` instead. Passes: `ray_march` + `post_process` (SSGI intentionally omitted — emission dominates, SSGI invisible). `certified: false` until LM.9. New helper functions: `lm_hash_u32(uint) → uint` (Murmur-style xor-shift mixer), `lm_track_seed_hash(constant LumenPatternState&) → uint`. **LM.4 pattern engine RETIRED at LM.4.4.** The ripple/sweep accent layer was deleted (helpers `lm_pattern_radial_ripple` / `lm_pattern_sweep` / `lm_evaluate_active_patterns` and constants `kPatternBoost` / `kPatternMaxSum` / `kRippleMaxRadius` / `kRippleSigmaBase` / `kSweepSigma` all removed). Reason: wavefronts were invisible against the simultaneous bar pulse (both events fired on the downbeat; panel-wide pulse dominated the local +20% Gaussian band by area) — see LM.4.4 landed-work entry. The LM.3.2 cell-color dance driven by LM.4.3 grid-wrap counters + the bar pulse are now the entire visual story. `state.patterns[4]` tuple stays zeroed in `LumenPatternState` for GPU ABI continuity; the shader does not read those slots. Passes: `ray_march` + `post_process` (SSGI intentionally omitted — emission dominates, SSGI invisible). `certified: false` until LM.9. **Tuning surface (M7 review knobs):** `kPaletteStepSize` (per-step palette advance), `kBarPulseMagnitude / kBarPulseShape` (bar pulse character), `kBassTeamCutoff / kMidTeamCutoff / kTrebleTeamCutoff` (team distribution: 30 / 65 / 90), `kCellIntensityBase / kCellIntensityJitter` (uniform brightness floor + jitter range), `kPaletteACool/AWarm/BSubdued/BVivid/CUnison/COffset/DComplementary/DAnalogous` (palette character endpoints — **widened at LM.3.2 calibration follow-up 2026-05-09**: ACool/AWarm = (0.25, 0.50, 0.75) / (0.75, 0.50, 0.25); BVivid = (0.65, 0.65, 0.65); DComplementary/DAnalogous = (0, 0.50, 1.00) / (0, 0.05, 0.15). The original LM.3 narrow endpoints (≤ 0.10 per-channel diff) only rotated which cell got which colour, not which colours appeared — moods looked identical. The widened endpoints produce genuinely different colour regions of palette-space at HV-HA vs LV-LA), `kSeedMagnitudeA/B/C/D` (per-track perturbation magnitudes), `kCellDensity` (cells across panel — **15 at LM.3.2 calibration**, gives ~30 cells across visible frame; was 30 in LM.3 / LM.3.1 but read as confetti); **LM.4 / LM.4.1 / LM.4.3 constants RETIRED at LM.4.4** — `kPatternBoost`, `kPatternMaxSum`, `kRippleMaxRadius`, `kRippleSigmaBase`, `kSweepSigma`, and the Swift-side `LumenPatternFactory.radialRippleDuration` / `sweepDuration` / `defaultPeakIntensity` are all gone. `kBarPulseMagnitude (0.20)` is the only LM.4-era survivor — the bar pulse stays (it's the downbeat accent for the LM.3.2 cell field). **LM.4.3 trigger source still applies to the LM.3.2 cell-dance counters:** `bassCounter / midCounter / trebleCounter` advance on `f.beatPhase01` wraps from the BeatGrid drift tracker (DSP.2 S7); FFT-band rising-edge detectors (`f.beatBass / beatMid / beatTreble`) are no longer consumed by any path. `f.barPhase01` wraps are also no longer consumed — the pattern-spawn trigger that read them was deleted with the pattern engine. See the LumenPatternEngine entry for the wrap-detection thresholds and the bass/mid/treble rate semantics. Engine-side rising-edge gate parameters: `beatTriggerHigh (0.5)`, `beatDebounceSeconds (0.08)`, `barFallbackBassBeats (4)`. **Retired LM.3 / LM.3.1 constants:** `kCellHueRate`, `kAgentStaticIntensity`, `kCellMinIntensity`. `defaultAttenuationRadius` stays on `LumenPatternEngine` for ABI continuity but is unused by LM.3.2 sceneMaterial.
    Lumen/LumenPatternEngine.swift → LM.4.4 per-preset world state. `LumenLightAgent` (32 B), `LumenPattern` (48 B), `LumenPatternState` (**376 B** — was 360 B at LM.3, 336 B at LM.2; LM.3.2 added the four band counters; LM.4.3 reinterpreted bass/mid/treble as rate-of-advance buckets, not FFT-band semantics; LM.4.4 keeps the same struct layout but the `patterns[4]` tuple and `barCounter` are no longer written by the engine — kept for GPU ABI continuity only) value types byte-identical to the matching MSL structs in `PresetLoader+Preamble.swift`. `LumenPatternEngine` final class (`@unchecked Sendable`): owns the 376-byte UMA buffer (`patternBuffer`) bound at fragment slot 8 of the ray-march G-buffer + lighting passes via `RenderPipeline.setDirectPresetFragmentBuffer3` while LumenMosaic is the active preset. Per-frame `tick(features:stems:)` (called from `RenderPipeline.meshPresetTick`) does two jobs (LM.4 pattern-spawn pool retired at LM.4.4): (1) advance the four light agents (drift + figure-8 dance + inset clamp — kept for ABI continuity, unused by LM.3.2+ shader), (2) call `updateBandCounters(features:)` which detects `f.beatPhase01` wraps (`prev > 0.85 && now < 0.15` → each grid beat); on each beat wrap `bassCounter += 1`, on every 2nd beat wrap `midCounter += 1`, on every 4th beat wrap `trebleCounter += 1` — all advances uniform `+1.0`, no energy modulation. `barCounter` no longer advances (it had no consumer outside the deleted pattern-spawn path). The wrap-edge state — `prevBeatPhase01` plus the `gridBeatsSinceMidStep / gridBeatsSinceTrebleStep` subdivision counters — lives on the engine. **`reset()` and `setTrackSeed(_:)` both call a private `resetBeatTrackingState()` helper** that zeroes the cell-dance counters + the wrap-edge state + the (now-permanently-zero) `state.patterns` snapshot. The `setTrackSeed` reset is load-bearing for cell colour identity: without the band-counter zero, the new track's cells would jump to a far-off palette index on beat 1. `setTrackSeed(fromHash:)` derives the seed from a 64-bit hash (FNV-1a over `title + artist` in `VisualizerEngine+Stems.resetStemPipeline(for:)`); the seed persists across all subsequent frames in that track (`_tick` does **not** clear it). `setAgentBasePositionForTesting(_:_:)` is the inset-clamp test seam (kept for ABI continuity even though agent positions are unused by the LM.3.2+ shader). **Known limitation (LM.4.3 carry-over):** no FFT fallback. If `f.beatPhase01` never wraps (pure silence, or before the live BeatGrid lands in reactive sessions ~10 s in), no counters advance and the panel is visually static. Acceptable for prepared sessions (grid is installed at session start). LM.4.5 may add an FFT fallback if reactive ad-hoc sessions surface the gap.
    Lumen/LumenPatterns.swift → **DELETED at LM.4.4** (was the LM.4 stateless pattern factory namespace). Pattern engine retired entirely after the third M7 review confirmed ripples/sweeps were invisible against the simultaneous bar pulse. See the LM.4.4 landed-work entry below for the full diagnosis.
  Orchestrator/             → AI VJ: preset selection, transitions, session planning (Increments 4.1–4.3 complete — see ENGINEERING_PLAN.md Phase 4)
    PresetScorer            → DefaultPresetScorer: 4 weighted sub-scores (mood/tempoMotion/stemAffinity/sectionSuitability) + 2 multiplicative penalties (family-repeat, fatigue). PresetScoring protocol. PresetScoreBreakdown for inspection. (D-032)
    PresetScoringContext    → Immutable Sendable snapshot: deviceTier, frameBudgetMs, recentHistory, currentPreset, elapsedSessionTime, currentSection. PresetHistoryEntry for session history.
    TransitionPolicy        → DefaultTransitionPolicy: structural boundary (confidence≥0.5, 2.5s window) beats duration-expired timer. TransitionDecision: trigger/scheduledAt/style/duration/confidence/rationale. Style from transitionAffordances + energy. Crossfade duration scales 2.0s→0.5s with energy. TransitionDeciding protocol. (D-033)
    PlannedSession          → Output types for SessionPlanner: PlannedSession, PlannedTrack, PlannedTransition, PlanningWarning. PlannedSession.track(at:)/transition(at:) for playback-time O(N) lookups. (D-034)
    SessionPlanner          → DefaultSessionPlanner: greedy forward-walk composes PresetScorer + TransitionPolicy. SessionPlanning protocol. Synchronous plan() + async planAsync() with precompile closure. SessionPlanningError. (D-034)
  Session/
    SessionManager          → Lifecycle state machine (idle→connecting→preparing→ready→playing→ended), @MainActor ObservableObject; degrades gracefully on connector/preparation failure. startSession(preFetchedTracks:source:) variant skips the connect phase for sources (e.g. Spotify OAuth) that already fetched tracks in the app layer.
    PlaylistConnector       → Apple Music (AppleScript) / Spotify (Web API) / URL parsing
    TrackIdentity           → Stable cache key: title, artist, album, duration, catalog IDs. spotifyPreviewURL: URL? is a resolution hint (excluded from Equatable/Hashable/Codable) populated by SpotifyWebAPIConnector from the /items preview_url field; PreviewResolver short-circuits to it.
    SessionTypes            → SessionState enum, SessionPlan stub (expanded by Orchestrator in Phase 4)
    PreviewResolver          → Resolves 30-second preview URLs. Primary: TrackIdentity.spotifyPreviewURL (inline from Spotify /items, no network call). Fallback: iTunes Search API (free, 20/60s rate limit) for non-Spotify tracks or tracks where Spotify returns null. In-memory cache (URL?? semantics).
    PreviewDownloader        → Batch download + format-sniff + AVAudioFile decode to mono Float32, withTaskGroup concurrency ceiling (default 4)
    SessionPreparer          → Download → separate → analyze → cache per track, @MainActor ObservableObject with @Published progress
    StemCache                → Thread-safe per-track: stem waveforms + StemFeatures + TrackProfile, NSLock-guarded
    TrackProfile             → BPM, key, mood, spectral centroid avg, genre tags, stem energy balance, estimated section count.
                               NOTE: no `fullDuration` field — full track duration comes from TrackIdentity.duration (Double?, nil = unknown). SessionPlanner defaults to 180 s when nil.
  Diagnostics/
    MemoryReporter          → `phys_footprint` via TASK_VM_INFO Mach API → MemorySnapshot{residentBytes, virtualBytes, purgeableBytes, timestamp}. Matches Activity Monitor. D-060(a).
    FrameTimingReporter     → 100-bucket 0.5ms histogram (cumulative) + 1000-frame rolling ring buffer. O(1) record, O(buckets) percentile. `droppedFrameThresholdMs = 32.0 ms`. @unchecked Sendable, NSLock-guarded. D-060(b).
    SoakTestHarness         → @MainActor, @available(macOS 14.2, *). Headless soak orchestrator: drives AudioInputRouter (localFile mode), samples memory + frame timing every sampleInterval, observes signal/quality transitions, writes JSON+Markdown report. cancel() via 0.25s polling slice. generateSyntheticAudioFile() for no-fixture procedural audio (10s sine sweep + noise + 120 BPM kicks). D-060.
  SoakRunner/               → CLI executable (swift-argument-parser). --duration, --sample-interval, --audio-file, --report-dir. Prints JSON report summary. Use Scripts/run_soak_test.sh for 2-hour runs with caffeinate -i. D-060(d).
  TempoDumpRunner/          → CLI executable (swift-argument-parser). --audio-file, --label, --out, --metadata-bpm. Decodes audio to mono Float32, runs FFTProcessor + BeatDetector at 1024-sample hops, dumps top-5 IOI bins + autocorrelation BPM + per-band onset events to a plain-text file. Sets BEATDETECTOR_DUMP_HIST=1 + BEATDETECTOR_DUMP_FILE before any BeatDetector access. Use with Scripts/dump_tempo_baselines.sh (3-track driver) and Scripts/analyze_tempo_baselines.py (per-band IOI + grid-fit analyzer). Permanent regression infrastructure for DSP.1/DSP.2. D-075.
  Shared/
    UMABuffer               → Generic .storageModeShared MTLBuffer + UMARingBuffer
    AudioFeatures           → @frozen SIMD-aligned structs (see Key Types below)
    AnalyzedFrame           → Timestamped container: AudioFrame + FFTResult + StemData + FeatureVector + EmotionalState
    StemSampleBuffer        → Interleaved stereo PCM ring buffer for stem separation input (15s)
    RenderPass              → Enum: direct, feedback, particles, mesh_shader, post_process, ray_march, icb, ssgi, mv_warp
    Logging                 → Per-module os.Logger instances (subsystem: "com.phosphene")
    SessionRecorder         → Continuous diagnostic capture per app launch: video.mp4 (H.264, 30 fps) + features.csv + stems.csv + stems/<N>_<title>/{drums,bass,vocals,other}.wav + session.log. Writes to ~/Documents/phosphene_sessions/<timestamp>/. Writer locks after 30 stable drawable frames; if a different size arrives consistently for ≥90 frames after lock (bad initial lock from transient Retina→logical-point resize), tears down and relocks — logs "video writer relocking". Finalised on NSApplication.willTerminateNotification. Validated by SessionRecorderTests.
    SpectralHistoryBuffer   → Per-frame MIR history ring buffer. 5 rings × 480 samples (≈8s at 60fps) in a 16 KB UMA MTLBuffer bound at fragment index 5 in direct-pass encoders. Tracks valence, arousal, beat_phase01, bass_dev, bar_phase01 (phrase-level sawtooth; 0 = no BeatGrid). Updated once per frame in RenderPipeline.draw(in:); reset on track change.
    DeviceTier              → .tier1 (M1/M2) / .tier2 (M3/M4). frameBudgetMs getter. Used by PresetScoringContext for complexity-cost exclusion gate.
    Smoother                → @frozen Sendable value type wrapping `pow(rate30, 30/fps)` for FPS-independent EMA / decay. Used by BeatDetector (pulse decay rate30=0.6813) and BandEnergyProcessor (per-band rates 0.65/0.75/0.95). Centralised in [QR.5] C.1 from previously-inlined `powf` calls.
Tests/
  Audio/                    → AudioBufferTests, FFTProcessorTests, StreamingMetadataTests, MetadataPreFetcherTests, LookaheadBufferTests, SilenceDetectorTests
  DSP/                      → SpectralAnalyzerTests, BandEnergyProcessorTests, ChromaExtractorTests, BeatDetectorTests, MIRPipelineUnitTests, SelfSimilarityMatrixTests, NoveltyDetectorTests, StructuralAnalyzerTests, BeatPredictorTests, PitchTrackerTests, StemAnalyzerMV3Tests
  ML/                       → StemSeparatorTests, StemFFTTests, StemModelTests, MoodClassifierTests, BeatThisFixturePresenceGate (QR.3 — supply-chain gate for love_rehab.m4a + python-activations.json), BeatThisLayerMatchTests, BeatThisBugRegressionTests, BeatThisStemReshapeTests (QR.3 — DSP.2 S8 Bug 2), BeatThisRoPEPairingTests (QR.3 — DSP.2 S8 Bug 4 spec), MoodClassifierGoldenTests (QR.3 — 10-input output anchor)
  Renderer/                 → MetalContextTests, ShaderLibraryTests, RenderPipelineTests, ProceduralGeometryTests, MeshGeneratorTests, BVHBuilderTests, RayIntersectorTests, PostProcessChainTests, ShaderUtilityTests, TextureManagerTests, RayMarchPipelineTests, SceneUniformsTests, FeatureVectorExtendedTests, SSGITests, RenderPipelineICBTests, MVWarpPipelineTests, SpectralCartographTests
  Utilities/                → NoiseTestHarness (compute-pipeline harness), NoiseUtilityTests (~30 @Test, 10 suites), PBRUtilityTests (~45 @Test, 8 suites) — V.1 utility tests. V.2: SDFPrimitivesTests (2 suites), SDFBooleanTests, SDFModifiersTests, SDFDisplacementTests, RayMarchAdaptiveTests, HexTileTests; HenyeyGreensteinTests, ParticipatingMediaTests, CloudsTests, LightShaftsTests, CausticsTests; VoronoiTests, ReactionDiffusionTests, FlowMapsTests, ProceduralTests, GrungeTests.
  Diagnostics/              → MemoryReporterTests (5), FrameTimingReporterTests (7), SoakTestHarnessTests (7 always-run + 2 SOAK_TESTS=1 gated). Run soak tests: SOAK_TESTS=1 swift test --filter SoakTestHarnessTests
  Shared/                   → AudioFeaturesTests, UMABufferExtendedTests, EmotionalStateTests, AnalyzedFrameTests, SpectralHistoryBufferTests
  Session/                  → SessionManagerTests, PlaylistConnectorTests, PreviewResolverTests, PreviewDownloaderTests, SessionPreparerTests, StemCacheTests, SpotifyWebAPIConnectorTests, SpotifyTokenProviderTests, SpotifyItemsSchemaTests (QR.3 — fixture-driven Failed Approach #45 / #47 lock)
  Presets/                  → ArachneStateTests, GossamerStateTests, ArachneSpiderRenderTests, MurmurationStemRoutingTests, LumenPatternEngineTests, LumenPaletteSpectrumTests (LM.4.6 — pure uniform random RGB per cell, 7 tests / 5 suites mirror the shader algorithm in Swift), PresetLoaderCompileFailureTest (QR.3 — production-count gate, 15 presets; verified by breaking Plasma.metal AND caught the LM.4.6 underscore-literal silent drop, hotfix `888bb856`). LumenPatternsTests was deleted at LM.4.4 along with the pattern engine.
  Integration/              → AudioToFFTPipelineTests, AudioToRenderPipelineTests, MetadataToOrchestratorTests, AudioToStemPipelineTests, MIRPipelineIntegrationTests, LookaheadIntegrationTests, StemsToRenderPipelineTests, SessionPreparationIntegrationTests, BeatGridIntegrationTests, PreparedBeatGridAppLayerWiringTests, PreparedBeatGridWiringTests, LiveDriftValidationTests (QR.3 — closed-loop musical-sync test on love_rehab.m4a)
  Regression/               → FFTRegressionTests, MetadataParsingRegressionTests, ChromaRegressionTests, BeatDetectorRegressionTests, StructuralAnalysisRegressionTests + golden fixtures
  Performance/              → FFTPerformanceTests, RenderLoopPerformanceTests, StemSeparationPerformanceTests, DSPPerformanceTests
  TestDoubles/              → MockAudioCapture, StubFFTProcessor, FakeStemSeparator, MockMoodClassifier, FakePreparationProgressPublisher, AudioFixtures, MockMetadataProvider, MockMetadataFetcher (Mock/Stub/Fake taxonomy standardised [QR.5] C.2)
```


---

## Audio Analysis Tuning

These constants were validated across genres. Do not re-tune from scratch.

### Frequency Bands

**3-band:** Bass 20–250 Hz, Mid 250–4000 Hz, Treble 4000–20000 Hz.

**6-band:** Sub Bass 20–80 Hz, Low Bass 80–250 Hz, Low Mid 250–1000 Hz, Mid High 1000–4000 Hz, High Mid 4000–8000 Hz, High 8000+ Hz.

### AGC (Automatic Gain Control)

Milkdrop-style average-tracking. Output = `raw / runningAverage * 0.5`. Two-speed warmup: fast (0.95 rate, ~1s) then moderate (0.992, ~2s settling). 6-band AGC normalizes against total energy (not per-band) to preserve relative differences.

**Authoring implication (D-026):** AGC-normalized outputs like `f.bass` are **centered around 0.5**, not raw amplitudes. The kick that reads `0.35` in a sparse section and `0.22` in a busy one is equally loud acoustically — only the running-average divisor moved. Preset shaders must drive visuals from **deviation primitives** added in MV-1:

- **xRel** = `(x - 0.5) * 2.0` — centered at 0, typical range ±0.5. Use for continuous motion drivers: `zoom = base + 0.1 * f.bass_att_rel`.
- **xDev** = `max(0, xRel)` — positive-only, zero at or below AGC average. Use for accent/threshold drivers: `smoothstep(0.0, 0.3, f.bass_dev)`.

Available fields: `f.bass_rel/dev`, `f.mid_rel/dev`, `f.treb_rel/dev`, `f.bass_att_rel`, `f.mid_att_rel`, `f.treb_att_rel` (FeatureVector); `stems.vocals_energy_rel/dev`, `stems.drums_energy_rel/dev`, `stems.bass_energy_rel/dev`, `stems.other_energy_rel/dev` (StemFeatures). Patterns like `smoothstep(0.22, 0.32, f.bass)` are an anti-pattern: they fail on track changes and on section changes within a single track. See `docs/MILKDROP_ARCHITECTURE.md` for the research establishing this and `docs/DECISIONS.md` D-026 for the rule.

### Smoothing

FPS-independent via `pow(rate, 30/fps)`:
- **Instant** (`bass`, `mid`, `treble`): bass 0.65, mid/treble 0.75.
- **Attenuated** (`bass_att`, `mid_att`, `treb_att`): 0.95 rate for slow motion.

### Onset Detection

Spectral flux on 6-band IIR RMS: `max(0, currentRMS - previousRMS)`. 50-frame circular buffer. Threshold: `median(buffer) × 1.5`. Per-band cooldowns: low 400ms, mid 200ms, high 150ms. Grouped pulses: `beat_bass` (sub_bass OR low_bass, 400ms), `beat_mid` (low_mid OR mid_high, 200ms), `beat_treble` (high_mid OR high, 150ms). Decay: `pow(0.6813, 30/fps)` → 0.1 in ~200ms at 60fps.

### Validated Onset Counts (Reference — per 5-second window)

| Track | Genre | sub_bass | low_bass | low_mid | mid_high | high_mid | high |
|-------|-------|----------|----------|---------|----------|----------|------|
| Love Rehab (Chaim) | Electronic ~125 BPM | 11 | 10 | 20 | 4 | 0 | 1 |
| So What (Miles Davis) | Jazz ~136 BPM | 5 | 2 | 5 | 6 | 2 | 1 |
| There There (Radiohead) | Rock, syncopated | 6 | 7 | 21 | 18 | 16 | 5 |

### Tempo (BPM estimation)

Two parallel paths feed `BeatDetector.Result`:

**IOI-based (primary, post-DSP.1).** `recordOnsetTimestamps` records timestamps from `result.onsets[0]` — sub_bass per-band onset events from `detectOnsets`, which has a 400 ms cooldown. **Single-band only — never fuse with low_bass:** independent per-band cooldowns + FFT-hop quantization make OR-of-bands produce alternating 18/19-frame IOIs (418/441 ms) for a true 441 ms beat, which then bias the histogram. `computeStableTempo` runs at 1 Hz over the trailing 10 s window and computes BPM via **trimmed-mean IOI** — median IOI, drop outliers outside [0.5×, 2×] median, mean of inliers, BPM = `60 / meanIOI`. The 80–160 octave clamp is preserved for deep doubling/halving guard. The histogram is still built (cheap) but only consumed by the diagnostic dump; never by the BPM picker. Picking the histogram mode systematically biased toward faster BPMs because BPM bucket widths grow with BPM in period space. See D-075.

**Autocorrelation (secondary, fallback).** `estimateTempo` runs every frame on the composite-flux onset history. Returns `(tempo, confidence)` for tracks where sub_bass IOI evidence is sparse or absent (a cappella, solo acoustic guitar). Same 80–160 clamp. Used by the live engine when `instantBPM`/`stableBPM` haven't converged; the post-DSP.2 path will instead drive `FeatureVector.beatPhase01` analytically from the pre-cached `BeatGrid` (Beat This! offline) plus a live drift tracker.

**Reference-track results (post-DSP.1):** love_rehab 122–126 (true 125), so_what 135–138 (true 136), there_there 137–140 (true ~86 syncopated — kick is not on every beat; histogram correctly reads kick rate, not meter). DSP.2 (Beat This! transformer via MPSGraph offline + drift-tracker live, planned, D-077; pivoted from the BeatNet path D-076 reserved-but-abandoned) is the answer for the syncopated case and for irregular meters (Pyramid Song 16/8, Money 7/4) the IOI method cannot reach by construction. See `docs/diagnostics/DSP.1-baseline*.txt` for the diagnostic captures and `Scripts/dump_tempo_baselines.sh` to reproduce.

### Chroma

Bin-count normalized: weight = `1/binsInPitchClass`. Skip bins below 65 Hz. At 48kHz/1024-point FFT, pitch classes get 31–55 bins — without normalization, key estimation is biased.

### Mood Classifier Inputs

10 features: 6-band energy, centroid, flux, major/minor key correlations. NOT raw 12-bin chroma (a tiny MLP cannot learn the Krumhansl-Schmuckler function from raw bins). Spectral flux normalized via running-max AGC (0.999 decay). Centroid normalized by Nyquist (24000 Hz).

---


---

## Key Types (Shared Module)

```swift
struct FeatureVector          // 48 floats = 192 bytes (SIMD-aligned). GPU buffer(2). MV-3.
                              // Floats 1–24: energy bands, smoothed bands, beat pulses, spectral features,
                              //   mood valence/arousal, structural prediction fields, camera uniforms.
                              // Float 25: accumulatedAudioTime.
                              // Floats 26–34: MV-1 deviation primitives (D-026):
                              //   bassRel, bassDev, midRel, midDev, trebRel, trebDev,
                              //   bassAttRel, midAttRel, trebAttRel.
                              // Floats 35–36: MV-3b beat phase (D-028): beatPhase01, beatsUntilNext.
                              // Floats 37–48: padding.
struct FeedbackParams         // 32 bytes (8 floats): decay, baseZoom, baseRot, beatZoom, beatRot,
                              //   beatSensitivity, beatValue, padding.
struct StemFeatures           // 256 bytes (64 floats). GPU buffer(3). MV-3.
                              //   Floats 1–16: 4 per stem (vocals/drums/bass/other): energy, band0, band1, beat.
                              //   Floats 17–24: MV-1 deviation primitives: vocalsEnergyRel/Dev,
                              //     drumsEnergyRel/Dev, bassEnergyRel/Dev, otherEnergyRel/Dev.
                              //   Floats 25–40: MV-3a rich metadata (4 per stem): onsetRate, centroid, attackRatio, energySlope.
                              //   Floats 41–42: MV-3c vocalsPitchHz, vocalsPitchConfidence.
                              //   Floats 43–64: padding.
struct AudioFrame             // PCM samples, timestamp, sample rate
struct FFTResult              // 512 magnitude bins, phase bins, dominant frequency
struct BandEnergy             // 3-band + 6-band, instant + attenuated
struct StemData               // Four stems as AudioFrames
struct SpectralFeatures       // centroid, flux, rolloff, MFCCs, chroma, ZCR
struct OnsetPulses            // beat_bass, beat_mid, beat_treble, composite (0–1 decaying)
struct EmotionalState         // valence (-1…1), arousal (-1…1), quadrant
struct StructuralPrediction   // sectionIndex, sectionStartTime, predictedNextBoundary, confidence
struct AnalyzedFrame          // Timestamped bundle of all above
struct TrackMetadata          // title, artist, album, genre, duration, artwork URL, source
struct PreFetchedTrackProfile // External BPM, key, energy, valence, danceability, genre tags
struct PresetDescriptor       // id, family, tags, passes: [RenderPass], scene metadata, stem affinity
struct TrackIdentity          // title, artist, album, duration, catalog IDs (Sendable+Hashable+Codable)
struct TrackProfile           // BPM, key, mood, spectral centroid avg, genre tags, stem energy balance, section count
struct CachedTrackData        // stemWaveforms [[Float]], stemFeatures, trackProfile
struct SceneUniforms          // 8× SIMD4<Float> = 128 bytes. Camera basis, light, fog/ambient.
struct Particle               // 64 bytes: position, velocity, color, life, size, seed, age
enum SessionState             // idle, connecting, preparing, ready, playing, ended
enum AudioSignalState         // .active, .suspect, .silent, .recovering
enum RenderPass               // direct, feedback, particles, mesh_shader, post_process, ray_march, icb, ssgi
class SpectralHistoryBuffer   // 16 KB UMA ring buffer at buffer(5). 480-sample trails for
                              // valence, arousal, beat_phase01, bass_dev, bar_phase01.
                              // Reserved section [2402..2419]: beat_times[16] (Float.infinity=unused),
                              // bpm, lock_state — written by analysisQueue via updateBeatGridData()
                              // (separate beatGridLock, non-overlapping with ring-buffer writes).
                              // Conforms to SpectralHistoryPublishing for test injection.
enum DeviceTier               // .tier1 (M1/M2), .tier2 (M3/M4). frameBudgetMs = 16.6ms.
struct PresetScoringContext   // Sendable session snapshot: deviceTier, frameBudgetMs, recentHistory,
                              // currentPreset, elapsedSessionTime, currentSection. .initial(deviceTier:) factory.
struct PresetHistoryEntry     // One past preset appearance: presetID, family, startTime, endTime. Sendable+Hashable.
struct PresetScoreBreakdown   // Per-(preset,track,context) score breakdown: mood, tempoMotion, stemAffinity,
                              // sectionSuitability, familyRepeatMultiplier, fatigueMultiplier, excluded, total.
protocol PresetScoring        // score(preset:track:context:) → Float; breakdown(…) → PresetScoreBreakdown;
                              // rank(presets:track:context:) default extension. Sendable.
struct DefaultPresetScorer    // Concrete PresetScoring. Pure/stateless/deterministic. Weights in static lets.
enum FatigueRisk              // .low / .medium / .high. Controls fatigue-penalty cooldown (60/120/300s).
enum TransitionAffordance     // .crossfade / .cut / .morph. Transition styles a preset tolerates.
enum SongSection              // .ambient / .buildup / .peak / .bridge / .comedown. Section suitability filter.
struct ComplexityCost         // tier1: Float, tier2: Float (ms at 1080p). Scalar or {tier1,tier2} JSON.
                              // .cost(for: DeviceTier) → Float. Exclusion gate in DefaultPresetScorer.
struct TransitionContext      // Sendable snapshot for TransitionDeciding: currentPreset, elapsedPresetTime,
                              // prediction (StructuralPrediction), energy (0–1), captureTime (Float, seconds
                              // since capture start — shared coordinate with StructuralPrediction timestamps).
struct TransitionDecision     // Fully-inspectable transition directive: trigger (structuralBoundary/
                              // durationExpired), scheduledAt (Float), style (TransitionAffordance),
                              // duration (TimeInterval, 0 for cut), confidence (Float), rationale (String).
protocol TransitionDeciding   // evaluate(context: TransitionContext) → TransitionDecision?. Sendable.
struct DefaultTransitionPolicy // Concrete TransitionDeciding. Constants in static lets. Structural boundary
                              // beats timer fallback; energy scales crossfade duration and style selection.
struct PlannedTransition      // fromPreset, toPreset, style (TransitionAffordance), duration, scheduledAt
                              // (session-relative TimeInterval), reason (String).
struct PlannedTrack           // track (TrackIdentity), trackProfile, preset, presetScore, scoreBreakdown,
                              // plannedStartTime, plannedEndTime, incomingTransition (PlannedTransition?).
struct PlannedSession         // deviceTier, tracks: [PlannedTrack], totalDuration, warnings: [PlanningWarning].
                              // track(at: TimeInterval) → PlannedTrack?; transition(at:tolerance:) → PlannedTransition?.
struct PlanningWarning        // kind (noEligiblePresets/forcedFamilyRepeat/budgetExceeded/missingSectionData),
                              // trackIndex (Int), message (String). Sendable, Hashable, Codable.
protocol SessionPlanning      // plan(tracks:catalog:deviceTier:) → PlannedSession. Sendable.
struct DefaultSessionPlanner  // Concrete SessionPlanning. Greedy forward-walk. planAsync() adds precompile.
                              // Accepts scorer: PresetScoring + transitionPolicy: TransitionDeciding + closure.
enum SessionPlanningError     // emptyPlaylist / emptyCatalog / precompileFailed(presetID:underlying:).
```

---


---

## GPU Contract Details

### Texture Binding Layout
```
texture(0)  = feedback read
texture(1)  = feedback write
texture(2–3)= reserved
texture(4)  = noiseLQ    (256² .r8Unorm tileable Perlin FBM)
texture(5)  = noiseHQ    (1024² .r8Unorm Perlin FBM)
texture(6)  = noiseVolume (64³ .r8Unorm 3D FBM)
texture(7)  = noiseFBM   (1024² .rgba8Unorm R=Perlin G=shifted B=Worley A=curl)
texture(8)  = blueNoise  (256² .r8Unorm IGN dither)
texture(9)  = IBL irradiance cubemap (32² .rgba16Float)
texture(10) = IBL prefiltered env (128² .rgba16Float, 5 mip levels)
texture(11) = BRDF LUT (512² .rg16Float)
```

### Buffer Binding Layout
```
buffer(0) = FeatureVector (192 bytes, 48 floats)        ← all fragment encoders
buffer(1) = FFT magnitudes (512 floats)
buffer(2) = waveform samples (1024 floats)
buffer(3) = StemFeatures (256 bytes, 64 floats)
buffer(4) = SceneUniforms (128 bytes) — ray march G-buffer, lighting, SSGI passes ONLY
buffer(5) = SpectralHistory (4096 Float32, 16 KB) — direct-pass fragment encoders
              [0..479]    valence trail (-1..1)
              [480..959]  arousal trail (-1..1)
              [960..1439] beat_phase01 history (0..1)
              [1440..1919] bass_dev history (0..1)
              [1920..2399] bar_phase01 history (0..1, phrase-level sawtooth; 0 = no BeatGrid)
              [2400] write_head  [2401] samples_valid
              [2402..2417] beat_times[16] — relative beat times in seconds (positive=upcoming).
                           Float.infinity sentinel = unused slot. Written by analysisQueue via
                           updateBeatGridData(). Used by SpectralCartograph tick overlay.
              [2418] bpm — BPM from cached BeatGrid (0 = no grid / reactive mode)
              [2419] lock_state — drift-tracker lock: 0=unlocked, 1=locking, 2=locked
              [2420] session_mode — orchestrator state: 0=reactive, 1=planned+unlocked,
                     2=planned+locking, 3=planned+locked. Written by analysisQueue via
                     updateBeatGridData(). Read by SpectralCartographText.drawModeLabel.
              [2421..4095] reserved (zeroed)
buffer(6) = per-preset fragment buffer #1 — bound by setDirectPresetFragmentBuffer.
              Reserved for: Gossamer wave pool (GossamerGPU), Arachne web pool
              (ArachneWebGPU[kArachWebs] — 96 bytes/web post-V.7.7C.2,
              4 webs × 96 = 384 bytes total).
              ArachneWebGPU layout: Row 0 = (hub_x, hub_y, radius, depth);
              Row 1 = (rot_angle, anchor_count, spiral_revolutions, rng_seed);
              Row 2 = (birth_beat_phase, stage, progress, opacity);
              Row 3 = (birth_hue, birth_sat, birth_brt, is_alive);
              Row 4 = (smoothedValence, smoothedArousal, accTime, reserved) —
                       written identically to all slots each frame; drawWorld()
                       reads webs[0].row4 for the V.7.7 WORLD palette;
              Row 5 (V.7.7C.2 / D-095) = (build_stage, frame_progress,
                       radial_packed, spiral_packed) — packed BuildState for the
                       foreground hero web; written only to webs[0]
                       (background webs zero this row). Four individual Floats
                       (NOT a SIMD4<Float> — that 16-byte alignment would push
                       stride past 96).
              The legacy mv_warp / direct paths AND the V.7.7B+ staged path
              bind this slot per-frame uniformly across every stage of a
              staged preset (RenderPipeline+MVWarp.swift +
              RenderPipeline+Staged.swift). Other presets that need additional
              buffers must use slot 8 (setDirectPresetFragmentBuffer3) or
              extend RenderPipeline with directPresetFragmentBuffer4 / 5;
              never overload 6/7.
buffer(7) = per-preset fragment buffer #2 — bound by setDirectPresetFragmentBuffer2.
              Reserved for: Arachne spider state (ArachneSpiderGPU — 80 bytes,
              V.7.7D contract). Same per-frame uniform binding contract as
              slot 6.
buffer(8) = per-preset fragment buffer #3 — bound by setDirectPresetFragmentBuffer3.
              First consumer (LM.2): Lumen Mosaic's `LumenPatternState`
              (LM.2: 336 B → LM.3: 360 B after adding smoothedValence/Arousal
              + 4 × trackPaletteSeed{A,B,C,D} fields → LM.3.2: 376 B after
              adding the four band counters bassCounter / midCounter /
              trebleCounter / barCounter).
              Slot is shared — any future preset that needs a third per-frame
              state buffer binds here. Same per-frame uniform binding contract
              as slots 6 / 7 in the staged + mv_warp + direct paths.
              **LM.2 widened the ray-march binding contract**: slot 8 is bound
              at BOTH `RayMarchPipeline.runGBufferPass` AND `runLightingPass`
              for every ray-march preset. The preamble's
              `raymarch_gbuffer_fragment` declares `[[buffer(8)]]`
              unconditionally (every ray-march preset compiles against the
              same fragment), so when a preset has not called the setter the
              zero-filled `RayMarchPipeline.lumenPlaceholderBuffer` is bound
              instead — Metal validation requires every declared fragment
              buffer to be bound at draw time. The `sceneMaterial` D-021
              signature gained a trailing `constant LumenPatternState& lumen`
              parameter; non-Lumen presets receive the zero placeholder and
              silence it via `(void)lumen;`. (D-LM-buffer-slot-8)
```

**Authoring note:** buffer(0) is `FeatureVector`, not FFT — the old documentation was wrong. All existing presets (Starburst, VolumetricLithograph, etc.) bind in this order. New preset fragment functions must declare `constant FeatureVector& fv [[buffer(0)]]`. The `SpectralHistory` buffer(5) is available in direct-pass presets; ray march presets currently skip it.

### Preamble Compilation Order
`FeatureVector struct` → `V.1 Noise utility tree (9 files)` → `V.1 PBR utility tree (9 files)` → `V.2 Geometry utility tree (6 files)` → `V.2 Volume utility tree (5 files)` → `V.2 Texture utility tree (5 files)` → `V.3 Color utility tree (4 files)` → `ShaderUtilities.metal functions` → `V.3 Materials cookbook (5 files)` → `constexpr sampler declarations` → preset shader code.

Color loads before ShaderUtilities so palette() is canonical (legacy deleted). Materials loads after ShaderUtilities for additive safety (D-062(d)).

Ray march presets get a separate `rayMarchGBufferPreamble` (includes `raymarch_gbuffer_fragment` which calls preset-defined `sceneSDF`/`sceneMaterial`). This must NOT appear in the shared preamble — standard presets never define those functions.

### G-Buffer Layout (Ray March)
```
gbuffer0: .rg16Float   (R = depth_normalized, G = preset matID — D-LM-matid)
gbuffer1: .rgba8Snorm  (normals + AO)
gbuffer2: .rgba8Unorm  (albedo + packed roughness/metallic)
litTexture: .rgba16Float (lighting output)
```

**`gbuffer0.g` — preset matID dispatch (LM.1 / D-LM-matid).** Half-float
written by the G-buffer fragment as `float(outMatID)` (preset's `sceneMaterial`
out-param); read by `raymarch_lighting_fragment` and dispatched on:

- `matID == 0` (default) — standard dielectric: full Cook-Torrance + screen-space
  soft shadows + IBL ambient + IBL specular + atmospheric fog. Existing presets
  (Glass Brutalist, Kinetic Sculpture, Volumetric Lithograph) all stay on this
  path; their `sceneMaterial` bodies leave `outMatID` at the caller's default 0.
- `matID == 1` — frosted backlit glass dielectric (Lumen Mosaic). Albedo
  carries the backlight intensity AND the frosted-glass surface
  character; the lighting path is the round-4 baseline simplified:
  `albedo × kLumenEmissionGain + irradiance × kLumenIBLFloor × ao`,
  skipping Cook-Torrance + screen-space shadow march. **LM.3.2 round 7
  (2026-05-10) moved frost diffusion from the lighting frag into
  sceneMaterial**: frost is now driven by the Voronoi `f2 - f1`
  cell-edge distance (a large-scale, smooth signal) rather than by
  the SDF relief geometry's normal. Cell centres stay fully vivid;
  cell boundaries get a clean white halo via `mix(cell_hue, white,
  frostiness × kFrostStrength = 0.60)` where
  `frostiness = 1 - smoothstep(0, kFrostBlendWidth = 0.04, f2 - f1)`.
  No more per-pixel dot artifacts (round 5/6 had visible white dots
  inside cells from sub-pixel normal noise in central-differences
  sampling). `kReliefAmplitude` and `kFrostAmplitude` in LumenMosaic.metal
  are both 0 at round 7 — the panel's geometric normal is a clean
  flat `(0, 0, -1)` per pixel. **`kLumenEmissionGain` reduced 4.0 → 1.0
  at LM.3.2 round 4** because the HSV palette is vivid without HDR
  boost and the prior 4× was clipping saturated channels in the
  harness's float→Unorm conversion (production with ACES tonemap
  would handle, harness without tonemap did not). Bloom no longer
  engages on individual cells — correct for the uniformly-vivid
  stained-glass aesthetic. The 0.05 IBL ambient floor keeps the panel
  coloured at silence (D-019). `kLumenEmissionGain` and `kLumenIBLFloor`
  are file-scope `constexpr constant` in `Renderer/Shaders/RayMarch.metal`.

The `sceneMaterial` D-021 signature was extended in two steps:

1. **LM.1 (D-LM-matid)** — added `thread int& outMatID` as the trailing
   parameter. Default behaviour for existing presets is to leave it
   untouched (the preamble's `raymarch_gbuffer_fragment` pre-zeros it
   before the call).

2. **LM.2 (D-LM-buffer-slot-8)** — added `constant LumenPatternState& lumen`
   as the new trailing parameter (after `outMatID`). Bound at fragment
   slot 8 in both the G-buffer and lighting passes. Non-Lumen presets
   receive the zero-filled `RayMarchPipeline.lumenPlaceholderBuffer` and
   silence the parameter via `(void)lumen;`. Lumen Mosaic's
   `sceneMaterial` reads it to compute the cell-quantized 4-light
   backlight (contract §P.3 / §P.4). The preamble defines the
   `LumenLightAgent` (32 B) / `LumenPattern` (48 B) / `LumenPatternState`
   (336 B) MSL structs once for every ray-march preset.

### SSGI
Half-res `.rgba16Float`. 8-sample blue-noise-rotated spiral. `kIndirectStrength = 0.3`. Sky pixels (depth ≥ 0.999) early-exit. Additive blend (src=one, dst=one). `sceneParamsB.w` overrides sample radius (0 → default 0.08 UV).

### AccumulatedAudioTime
`_accumulatedAudioTime += max(0, energy) * deltaTime` where energy = `(bass + mid + treble) / 3.0`. Reset on track change via `pipeline.resetAccumulatedAudioTime()`. Written to `sceneUniforms.sceneParamsA.x` each frame for ray march presets. Exposed as `FeatureVector.accumulated_audio_time` (float 25) for all presets.

### Mesh Shader Architecture
Hardware gated: `device.supportsFamily(.apple8)` (M3+). On M3+: `MTLMeshRenderPipelineDescriptor` + `drawMeshThreadgroups`. On M1/M2: standard vertex pipeline + `drawPrimitives`. `MeshGenerator` owns both and abstracts dispatch. MSL: `[[thread_index_in_threadgroup]]` is correct; `[[thread_index_in_mesh]]` does not exist. `ObjectPayload` uses `object_data` address space.

### ICB Architecture
`icb_populate_kernel` reads FeatureVector, activates slots based on cumulative energy thresholds. `setFragmentBytes` is NOT inherited by ICB commands — use `setFragmentBuffer` bindings. Pipelines must set `supportIndirectCommandBuffers = true`. Use `useResource(_:usage:stages:)` (stages-aware API, macOS 13+).

---


