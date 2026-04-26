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
