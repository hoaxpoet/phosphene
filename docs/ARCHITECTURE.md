# Phosphene — Architecture

## Overview

Phosphene is a native Swift/Metal macOS application with a modular engine architecture. Its major subsystems are:

- Audio capture and routing
- Buffering and FFT
- MIR / DSP analysis
- ML-powered stem separation
- Metadata and playlist preparation
- Renderer and preset system
- Orchestrator and session planning (in development)
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

**Tap recovery on prolonged silence.** Streaming-app scrubs frequently break the process tap — the tap stays alive but delivers permanent silence after the source process tears down and reopens its audio session on seek. `AudioInputRouter` watches the silence detector and, after `.silent` persists, schedules a tap reinstall on a backoff schedule (3 s → 10 s → 30 s, three attempts). Each attempt destroys the existing tap + aggregate device and creates a fresh one for the active capture mode. If audio resumes (either on the existing tap or a freshly-installed one) the silence detector transitions through `.recovering → .active` and the reinstall sequence is cancelled. After three exhausted attempts, prolonged silence is treated as a real pause and reinstall stops until the next active → silent transition.

## Audio Analysis Hierarchy

This ordering is the most important design rule in the project. Continuous-energy-dominant designs feel locked to the music. Beat-dominant designs feel out of sync.

1. **Continuous energy bands** (primary visual driver) — bass/mid/treble (3-band) and 6-band equivalents. Zero detection delay.
2. **Spectrum and waveform buffers** (richest data) — 512 FFT magnitude bins + 1024 waveform samples sent to GPU as buffer data.
3. **Spectral features** (derived characteristics) — centroid, flux, rolloff, MFCCs, chroma.
4. **Beat onset pulses** (accent only, never primary) — discrete accent events with ±80ms jitter. Feedback amplifies this jitter.
5. **Stems** — ML-separated vocals/drums/bass/other. Pre-analyzed from preview clips (available from first frame in session mode). Replaced by time-aligned live stems after ~10s.

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

**Render passes** (`RenderPass` enum): `direct`, `feedback`, `particles`, `mesh_shader`, `post_process`, `ray_march`, `icb`, `ssgi`. Each preset declares its required passes in JSON metadata.

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

**Key subsystems:**

- `PostProcessChain` — HDR bloom + ACES tone mapping.
- `RayMarchPipeline` — Deferred 3-pass: G-buffer → PBR lighting → composite.
- `IBLManager` — Image-based lighting (irradiance + prefiltered environment + BRDF LUT).
- `ProceduralGeometry` — GPU compute particle system.
- `MeshGenerator` — Hardware mesh shaders (M3+) with vertex fallback (M1/M2).
- `TextureManager` — 5 pre-computed noise textures generated via Metal compute at init.

**Binding layout:**

- Textures: 0=feedback read, 1=feedback write, 2–3=reserved, 4=noiseLQ, 5=noiseHQ, 6=noiseVolume, 7=noiseFBM, 8=blueNoise, 9=IBL irradiance, 10=IBL prefiltered, 11=BRDF LUT.
- Buffers: 0=FFT, 1=waveform, 2=FeatureVector, 3=StemFeatures, 4–7=future.

## Presets

Each preset consists of one or more Metal shaders plus a JSON sidecar declaring visual behavior, render passes, audio routing, and orchestration metadata. Presets are discovered automatically at runtime and compiled with a shared preamble (FeatureVector struct, ShaderUtilities library, noise samplers).

**Two architectural patterns coexist:**

- Milkdrop-style feedback loop: read previous frame → warp/decay → composite new elements.
- Photorealistic ray march: SDF scene → G-buffer → PBR lighting → IBL → post-process.

## Orchestrator

The Orchestrator is the decision layer responsible for selecting visualizers, sequencing transitions, adapting to live analysis, and balancing novelty, continuity, and performance cost.

**Two modes:**

- **Session mode** (playlist connected): Plans the full visual arc before playback using pre-analyzed TrackProfile data. Adapts in real time as live MIR reveals structural details.
- **Ad-hoc mode** (no playlist): Reactive decision-making under uncertainty. Heuristic preset selection based on live MIR data as it accumulates.

The Orchestrator is the product's key differentiator and is being implemented as an explicit scoring and policy system with testable golden-session fixtures.

## Support Tiers

**Tier 1 — M1 / M2:** Baseline feature set. Mesh shaders use vertex fallback. Stricter budgets for geometry, post-process, and advanced shaders.

**Tier 2 — M3 / M4:** Enhanced feature set. Hardware mesh shaders enabled. Mesh/ray-heavy presets allowed. Higher complexity ceilings.

## ML Inference

No CoreML dependency. All ML runs on MPSGraph (GPU) or Accelerate (CPU).

- **Stem separator** (MPSGraph): Open-Unmix HQ, Float32 throughout, 142ms warm predict for 10s audio. STFT/iSTFT via Accelerate/vDSP.
- **Mood classifier** (Accelerate): 4-layer MLP (10→64→32→16→2) via `vDSP_mmul`. 3,346 hardcoded Float32 params from DEAM training.

**Mood injection into the renderer.** Mood (`valence`, `arousal`) is computed on the analysis queue, attenuated by feature-stability, and pushed to the renderer via `RenderPipeline.setMood(valence:arousal:)`. The renderer's `setFeatures` preserves the most recent mood values across MIR-driven feature updates so the slower-cadence mood signal is not overwritten every frame. Without this dedicated path, mood values stay at zero in the GPU-bound `FeatureVector` even though the classifier is running.

## Session Recording (Diagnostics)

`SessionRecorder` (`Shared` module, public) writes a continuous diagnostic capture for every running session to `~/Documents/phosphene_sessions/<ISO-timestamp>/`. Created at `VisualizerEngine.init`, finalized via `NSApplication.willTerminateNotification` so the MP4 `moov` atom is written before process exit.

**Artifacts per session:**

- `video.mp4` — H.264 capture of the rendered output, throttled to 30 fps. Writer is locked once the drawable size has been observed for 30 consecutive same-size frames; later frames at a different size are skipped (preventing corner-rendered video from transient launch-time drawable sizes). MetalView sets `framebufferOnly = false` so the drawable is blit-readable.
- `features.csv` — per-frame `FeatureVector` (22 columns: bass/mid/treble, 6-band, beat onsets, spectral, valence/arousal, accumulatedAudioTime).
- `stems.csv` — per-frame `StemFeatures` (drums/bass/vocals/other × {energy, beat, band0, band1}).
- `stems/<NNNN>_<title>/{drums,bass,vocals,other}.wav` — 16-bit mono PCM dump of each stem-separation cycle output, listenable in any audio editor.
- `session.log` — startup banner (recorder version + macOS + GPU + hostname), state transitions (signal `.active/.suspect/.silent/.recovering`), track changes, preset changes, video-writer locked dimensions, and any frame-skip reasons.

**Render-loop integration:** `RenderPipeline` exposes `onFrameRendered: (drawableTex, features, stems, commandBuffer) -> Void`. `VisualizerEngine` sets this closure to blit the drawable into the recorder's capture texture inside the same command buffer, then schedule the readback in `commandBuffer.addCompletedHandler`. CSV rows are written every render frame; video frames are throttled to 30 fps.

**Test surface:** `SessionRecorderTests` validates round-trip correctness against known inputs (CSV column-by-column, WAV PCM sample-by-sample within 16-bit quantization, MP4 readable by `AVURLAsset`). A passing session that shows wrong data tells you the upstream pipeline is wrong, not the recorder.
