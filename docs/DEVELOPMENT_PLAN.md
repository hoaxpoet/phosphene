# Phosphene — Development Plan for Claude Code Implementation

## Project Overview

**Phosphene** is a next-generation, AI-driven music visualization engine built exclusively for Apple Silicon (M3/M4). It succeeds ProjectM/Milkdrop by combining Metal rendering, real-time ML-powered audio stem separation on the Apple Neural Engine, Music Information Retrieval (MIR), and an AI Orchestrator that autonomously curates visual playlists matched to the emotional arc of the music.

**Primary audio source:** System audio capture via Core Audio taps (`AudioHardwareCreateProcessTap`, macOS 14.2+). Phosphene visualizes whatever the user is streaming — Apple Music, Spotify, Tidal, YouTube Music, or any other audio source — by tapping the system audio output directly. It enriches the experience with track metadata from MusicKit and the macOS Now Playing API. Local file playback is supported as a fallback but is not the primary workflow. ScreenCaptureKit was originally planned but abandoned because it silently fails to deliver audio callbacks on macOS 15+/26.

**Streaming Anticipation Architecture:** Because streaming audio arrives without a pre-scannable file, Phosphene employs three complementary systems to recover the anticipatory capability that pre-scanning would otherwise provide:

1. **Analysis Lookahead Buffer** — A configurable 2–3 second delay between audio analysis and visual rendering. The audio pipeline processes frames ahead of what the renderer displays, giving the Orchestrator a genuine lookahead window to prepare for upcoming musical moments (drops, builds, transitions). This latency is imperceptible in a visualizer context where viewers do not expect sample-accurate video sync.
2. **Metadata Pre-Fetching** — When Now Playing reports a new track, Phosphene queries external music databases (MusicBrainz, Apple Music catalog, Spotify Web API) for pre-analyzed audio features: BPM, key, energy, danceability, genre, and duration. This metadata typically arrives within the first second of a track change, giving the Orchestrator immediate context before the MIR pipeline has accumulated enough audio to estimate these features independently.
3. **Progressive Structural Analysis** — After hearing 15–20 seconds of a track, a self-similarity analysis identifies section boundaries (intro, verse, chorus, bridge) and predicts when future transitions will occur based on the repetitive structure inherent in virtually all popular music. After the first chorus, the system can predict when the second chorus will arrive.

Combined, these three systems give the Orchestrator roughly the same decision-making information as a pre-scanned local file after a brief ramp-up period at the start of each track.

This plan decomposes the architectural blueprint into **Claude Code-safe increments** — discrete tasks that can each be completed within a single context window without risk of truncation or loss of coherence.

---

## Required Software & Dependencies

Before any coding begins, the following must be installed on the development Mac (Apple Silicon required).

### System-Level Prerequisites

| Software | Purpose | Install Method |
|----------|---------|----------------|
| **Xcode 16+** | Metal API, Swift compiler, CoreML, Instruments, GPU debugger | Mac App Store |
| **Xcode Command Line Tools** | `xcodebuild`, `xcrun`, `metal` CLI compiler | `xcode-select --install` |
| **Homebrew** | Package manager for CLI dependencies | `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"` |
| **Python 3.11+** | CoreML model conversion toolchain | `brew install python@3.11` |
| **FFmpeg** | Audio decoding, format conversion, PCM extraction | `brew install ffmpeg` |
| **Git LFS** | Large file storage for ML models and preset archives | `brew install git-lfs && git lfs install` |

### Python Environment (for ML model pipeline)

```bash
python3 -m venv ~/phosphene-ml-env
source ~/phosphene-ml-env/bin/activate
pip install coremltools torch torchaudio onnx onnxruntime librosa numpy scipy
```

| Package | Purpose |
|---------|---------|
| **coremltools** | Convert PyTorch/ONNX models to `.mlpackage` for ANE deployment |
| **torch + torchaudio** | Load and test pre-trained stem separation models (e.g., Demucs, HTDemucs) |
| **onnx / onnxruntime** | Intermediate model format for conversion pipelines |
| **librosa** | Reference MIR feature extraction (spectral centroid, chroma, MFCCs, tempo) |
| **numpy / scipy** | Signal processing and FFT utilities |

### Swift Package Dependencies (added via SPM in Xcode)

| Package | Purpose |
|---------|---------|
| **swift-argument-parser** | CLI interface for headless/debug modes |
| **swift-collections** | High-performance data structures (deques, ordered sets) for preset management |
| **swift-numerics** | Optimized math for MIR feature calculations |
| **swift-async-algorithms** | Async audio buffer streaming |

### Additional Tools

| Tool | Purpose | Install |
|------|---------|---------|
| **Metal Shader Converter** | Transpile HLSL to Metal IR (for legacy preset support) | Download from developer.apple.com/metal |
| **Blender** (optional) | Test mesh export for ray-tracing scene validation | `brew install --cask blender` |
| **SwiftLint** | Code quality enforcement | `brew install swiftlint` |

---

## Architecture Overview (For Claude Code Context)

When working on any increment, Claude Code should understand this high-level module map:

```
Phosphene/
├── PhospheneApp/              # SwiftUI application shell
│   ├── App.swift
│   ├── Views/                 # SwiftUI views
│   └── ViewModels/            # Observable state
├── PhospheneEngine/           # Core Swift package (library)
│   ├── Audio/                 # Audio capture, buffering, PCM pipeline
│   │   ├── SystemAudioCapture.swift   # Core Audio tap (AudioHardwareCreateProcessTap)
│   │   ├── AudioInputRouter.swift     # Selects source: system audio, app-specific, or file
│   │   ├── AudioBuffer.swift
│   │   ├── LookaheadBuffer.swift      # Deliberate analysis-to-render delay pipeline
│   │   ├── FFTProcessor.swift
│   │   ├── StreamingMetadata.swift    # MusicKit / Now Playing info integration
│   │   └── MetadataPreFetcher.swift   # External DB queries (MusicBrainz, catalog APIs)
│   ├── DSP/                   # MIR feature extraction
│   │   ├── SpectralAnalyzer.swift
│   │   ├── BeatDetector.swift
│   │   ├── ChromaExtractor.swift
│   │   ├── StructuralAnalyzer.swift   # Progressive section detection & prediction
│   │   └── FeatureVector.swift
│   ├── ML/                    # CoreML model management
│   │   ├── StemSeparator.swift
│   │   ├── MoodClassifier.swift
│   │   └── Models/            # .mlpackage files (Git LFS)
│   ├── Renderer/              # Metal rendering engine
│   │   ├── MetalContext.swift
│   │   ├── RenderPipeline.swift
│   │   ├── ShaderLibrary.swift
│   │   ├── Shaders/           # .metal shader files
│   │   │   ├── Particles.metal
│   │   │   ├── Fractal.metal
│   │   │   ├── Waveform.metal
│   │   │   ├── PostProcess.metal
│   │   │   └── MeshShaders.metal
│   │   ├── Geometry/
│   │   │   ├── MeshGenerator.swift
│   │   │   └── ProceduralGeometry.swift
│   │   └── RayTracing/
│   │       ├── BVHBuilder.swift
│   │       └── RayIntersector.swift
│   ├── Presets/               # Preset loading, parsing, management
│   │   ├── PresetLoader.swift
│   │   ├── PresetCategory.swift
│   │   └── LegacyTranspiler.swift
│   ├── Orchestrator/          # AI VJ logic
│   │   ├── Orchestrator.swift
│   │   ├── EmotionMapper.swift
│   │   ├── TransitionEngine.swift
│   │   ├── TrackChangeDetector.swift
│   │   └── AnticipationEngine.swift   # Fuses lookahead buffer + metadata + structural predictions
│   └── Shared/                # Shared types, UMA buffer wrappers
│       ├── UMABuffer.swift
│       └── AudioFeatures.swift
└── Tests/
```

---

## Phase 0 — Project Scaffolding

### Increment 0.1: Xcode Project & Swift Package Setup

**Goal:** Create the Xcode workspace, app target, and `PhospheneEngine` Swift package with correct build settings for Metal and CoreML.

**Claude Code instructions:**
- Create a new Xcode project `PhospheneApp` (macOS, SwiftUI App lifecycle, deployment target macOS 14.0+)
- Create a local Swift package `PhospheneEngine` with the directory structure above (empty placeholder files)
- Configure `Package.swift` with all SPM dependencies listed above
- Add `PhospheneEngine` as a dependency of `PhospheneApp`
- Set build settings: enable Metal API Validation in debug, link `Metal.framework`, `MetalKit.framework`, `CoreML.framework`, `AVFoundation.framework`, `Accelerate.framework`, `ScreenCaptureKit.framework` (retained but not used for audio — see Increment 1.3 notes), `MusicKit.framework`
- Configure entitlements: `NSScreenCaptureUsageDescription` in Info.plist (retained for potential future ScreenCaptureKit use). Core Audio taps do not require additional entitlements.
- Create a `.swiftlint.yml` with sensible defaults
- Create a `README.md` stub

**Verification:** Project builds and launches an empty window. All frameworks link without error.

**Estimated scope:** ~200 lines of config + stubs. Well within context.

---

## Phase 1 — Core Foundation & Metal Rendering (Blueprint Release 0.1)

### Increment 1.1: Metal Context & Render Loop ✅

**Goal:** Initialize a Metal device, command queue, and CAMetalLayer-backed rendering loop in a SwiftUI view via `MTKView` / `NSViewRepresentable`.

**Files to create/edit:**
- `Renderer/MetalContext.swift` — `MTLDevice`, `MTLCommandQueue`, pixel format selection, triple-buffered semaphore
- `Renderer/RenderPipeline.swift` — Basic render pass descriptor, clear color, drawable presentation
- `PhospheneApp/Views/MetalView.swift` — `NSViewRepresentable` wrapping `MTKView` with delegate
- `PhospheneApp/Views/ContentView.swift` — Host the MetalView

**Verification:** Window displays a solid color that changes per-frame (proves render loop is active at 60/120 fps).

### Increment 1.2: UMA Shared Buffer Infrastructure ✅

**Goal:** Build the zero-copy UMA buffer abstraction that allows CPU, GPU, and ANE to share memory.

**Files to create/edit:**
- `Shared/UMABuffer.swift` — Generic wrapper around `MTLBuffer` with `.storageModeShared`, typed pointer access, ring-buffer support for audio frames
- `Shared/AudioFeatures.swift` — Structs for `AudioFrame`, `FFTResult`, `StemData`, `FeatureVector` (all `@frozen` and SIMD-aligned for GPU consumption)

**Verification:** Unit test that writes data on CPU, reads it in a trivial compute shader — no copy, same pointer.

### Increment 1.3: System Audio Capture via Core Audio Taps ✅

**Goal:** Capture live system audio output (i.e., whatever the user is streaming via Apple Music, Spotify, Tidal, YouTube, etc.) and fill the UMA ring buffer with PCM float32 samples. Local file playback is a secondary fallback, not the primary input.

**Design rationale:** Most users consume music through streaming services. Phosphene cannot and should not attempt to integrate with each service's SDK — streaming services do not expose raw PCM audio to third parties. Instead, Phosphene taps the system audio mix (or a specific application's audio) using Core Audio taps (`AudioHardwareCreateProcessTap`, macOS 14.2+). This creates a process tap that feeds an aggregate device, whose IO proc delivers interleaved float32 PCM on a real-time audio thread. ScreenCaptureKit was originally planned but abandoned because it silently fails to deliver audio callbacks on macOS 15+/26 despite video frames arriving.

**Files created:**
- `Audio/SystemAudioCapture.swift` — Creates a `CATapDescription` (system-wide via `stereoGlobalTapButExcludeProcesses: []`, or per-app via `stereoMixdownOfProcesses: [pid]`), builds an aggregate device, and delivers audio via a callback on the real-time IO thread.
- `Audio/AudioInputRouter.swift` — Unified callback-based interface over three input modes: (1) system audio via Core Audio taps (default), (2) specific-app audio via Core Audio taps, (3) local file via `AVAudioFile` (fallback).
- `Audio/AudioBuffer.swift` — Writes interleaved float32 PCM into `UMARingBuffer<Float>` via pointer-based `write(from:count:)` for zero-copy from the IO thread. Exposes latest N samples for FFT and Metal buffer for GPU binding.
- `Audio/FFTProcessor.swift` — vDSP-based 1024-point FFT with Hann window, writes 512 magnitude bins into `UMABuffer<Float>` for GPU consumption. All working buffers pre-allocated (zero per-frame allocation).
- `Tests/PhospheneEngineTests/AudioTests.swift` — 12 tests covering AudioBuffer and FFTProcessor.
- `tools/audio-tap-test.swift` — Standalone test binary for live audio verification.

**Verification:** Play a song in Spotify. `./tools/audio-tap-test` captures 468 audio callbacks in 5 seconds, prints per-frame RMS levels (~-26dB) and FFT histograms showing energy concentrated in low frequencies. Verified on macOS 26.4.0.

**Implementation notes (completed 2026-04-06):**
- **ScreenCaptureKit abandoned for audio capture.** On macOS 26, `SCStream` with `capturesAudio = true` delivers video frames but zero audio callbacks, even with screen capture permission confirmed working. Root cause unknown — may be macOS 26 regression.
- **Core Audio taps adopted as primary capture method.** `AudioHardwareCreateProcessTap` (macOS 14.2+) works perfectly. System-wide: `CATapDescription(stereoGlobalTapButExcludeProcesses: [])`. Per-app: `CATapDescription(stereoMixdownOfProcesses: [pid])`. Tap feeds an aggregate device whose IO proc delivers interleaved float32 PCM on a real-time audio thread.
- **Critical: `stereoMixdownOfProcesses: []` with empty array means "mix zero processes" = silence.** Must use `stereoGlobalTapButExcludeProcesses: []` for system-wide capture.
- Sample rate: 48kHz stereo float32, matching the tap's reported format.
- `AudioInputRouter` uses callback-based API (`onAudioSamples`) — the IO proc delivers a raw float pointer on a real-time thread.
- `AudioBuffer.write(from:count:)` takes a raw pointer for zero-copy writing from the IO proc.
- 23 unit tests cover AudioBuffer (write, RMS, ring overwrite, GPU binding, reset) and FFTProcessor (bin count, silence, 440Hz detection, stereo mixdown, short input, GPU readability).
- Standalone test script: `tools/audio-tap-test.swift` — compile with `swiftc` and run to verify live audio capture with RMS + FFT histogram.

### Increment 1.4: Basic Fragment Shader Visualizer ✅

**Goal:** Render a full-screen quad driven by FFT data — proving the audio-to-GPU-to-pixel pipeline works end to end.

**Files created/edited:**
- `Renderer/ShaderLibrary.swift` — Auto-discovers `.metal` files from SPM bundle resources (`Shaders/` directory), compiles at runtime via `device.makeLibrary(source:options:)`, caches `MTLRenderPipelineState` by name.
- `Renderer/Shaders/Waveform.metal` — Full-screen fragment shader: 64-bar FFT frequency spectrum (bottom half, purple→cyan→green gradient), mirrored reflection (top), oscilloscope waveform line (centered, anti-aliased via distance field), glow effects, vignette. Reads all 512 FFT magnitude bins and 2048 PCM waveform samples directly on the GPU.
- `Renderer/RenderPipeline.swift` — Rewritten to accept FFT and waveform `MTLBuffer` references at init, bind as fragment shader buffers alongside `FeatureVector` timing uniforms, draw a full-screen triangle (3 vertices, no vertex buffer — generated from `vertex_id`).
- `PhospheneApp/ContentView.swift` — `VisualizerEngine` class (held via `@StateObject`) owns the complete pipeline: `AudioInputRouter` → `AudioBuffer` → `FFTProcessor` → `RenderPipeline`. Requests screen capture permission via `CGRequestScreenCaptureAccess()` before starting capture.
- `PhospheneEngine/Package.swift` — Added `resources: [.copy("Shaders")]` to Renderer target.
- `Audio/AudioInputRouter.swift` — Added `public init()`.

**Verification:** Play music in any streaming app. 64-bar spectrum and waveform respond in real time. Verified on macOS 26.4.0.

**Implementation notes (completed 2026-04-06):**
- **Screen capture permission is required for Core Audio taps to deliver non-zero audio.** `AudioHardwareCreateProcessTap` succeeds without permission, but the IO proc delivers all-zero samples. The tap reports correct format (48kHz, 2ch, 32bit), the aggregate device starts, callbacks fire at the expected rate — but every sample is 0.0. Call `CGPreflightScreenCaptureAccess()` / `CGRequestScreenCaptureAccess()` before starting capture. If denied, log a message directing the user to System Settings → Privacy & Security → Screen Recording.
- **SwiftUI lifecycle requires `@StateObject` for the engine.** A `private let` property in a SwiftUI struct is re-created on every view re-init. The old engine is deallocated (tearing down audio capture) while the `MTKView` still holds the old `RenderPipeline` delegate. `@StateObject` with `ObservableObject` preserves the engine across SwiftUI view reconstructions.
- **Metal shaders are SPM bundle resources.** `.metal` files live in `Sources/Renderer/Shaders/` and are included via `.copy("Shaders")` in Package.swift. `ShaderLibrary` loads them from `Bundle.module` and compiles at runtime. This keeps shaders in the engine package (not the app target) while supporting auto-discovery.
- **Full-screen triangle, not quad.** A single oversized triangle (3 vertices from `vertex_id`) is more efficient than a 6-vertex quad. The rasterizer clips to the viewport; fragment shader sees uv ∈ [0,1].

### Increment 1.5: Basic Preset Abstraction & Hot-Reloading

**Goal:** Define a `Preset` protocol and loader so that shaders can be swapped at runtime.

**Files to create/edit:**
- `Presets/PresetCategory.swift` — Enum for categories: `waveform`, `fractal`, `geometric`, `particles`, `hypnotic`, `supernova`, `reaction`, `drawing`, `dancer`, `transition`
- `Presets/PresetLoader.swift` — Discovers `.metal` files in a presets directory, compiles pipeline states, caches them, supports hot-reload via `DispatchSource.FileSystemObject`
- Write 2-3 simple native presets as separate `.metal` files to prove the loader works

**Verification:** Press a key to cycle through presets. New `.metal` files dropped into the presets folder appear without restarting.

---

## Phase 2 — Audio Intelligence & ML Pipeline (Blueprint Release 0.3)

### Increment 2.1: Streaming Metadata Integration & Pre-Fetching

**Goal:** Enrich the audio pipeline with track metadata from streaming services and external music databases, giving the Orchestrator immediate context about each track before the MIR pipeline has had time to analyze the audio itself.

**Design rationale:** When Core Audio taps capture system audio, Phosphene gets raw PCM but no metadata (track title, artist, album, duration, artwork). This metadata is crucial for the Orchestrator — knowing track boundaries, durations, and artist/genre context dramatically improves visual selection. Three complementary sources provide this:

1. **MPNowPlayingInfoCenter / MediaRemote** — A system-level API that reports what any app is currently playing (works with Spotify, Tidal, YouTube Music, etc.). Provides title, artist, album, duration, elapsed time, and playback state. No special authorization required beyond standard entitlements.
2. **MusicKit / Apple Music API** — If the user is an Apple Music subscriber, MusicKit provides deep metadata: track title, artist, album, genre, duration, artwork, and even catalog-level mood/genre tags. Requires user authorization.
3. **External Music Database Pre-Fetching** — When a track change is detected via Now Playing, Phosphene queries external databases to retrieve pre-analyzed audio characteristics. This provides the Orchestrator with BPM, key, energy, danceability, and genre within 1–2 seconds of a track starting — far faster than the 15–20 seconds the MIR pipeline needs to estimate these independently from raw audio.

**External data sources (queried in parallel on track change):**
- **MusicBrainz API** (free, no key required) — Track metadata, genre tags, release information, linked recordings
- **Apple Music Catalog API** (via MusicKit, requires Apple Music subscription) — Genre, editorial mood tags, tempo hints, preview URLs
- **Spotify Web API** (free tier, requires developer registration) — Audio features endpoint: `danceability`, `energy`, `valence`, `tempo`, `key`, `mode`, `loudness`, `speechiness`, `acousticness`. This is extremely valuable — Spotify has pre-computed the exact features Phosphene needs for mood mapping. Works even when the user is listening in a different app, as long as the track can be matched by title/artist.
- **AcousticBrainz** (community, best-effort) — Pre-computed MIR features including mood, genre, BPM, key, tonal/atonal classification

**Files to create/edit:**
- `Audio/StreamingMetadata.swift` — Polls `MPNowPlayingInfoCenter` for current track info. Detects track changes by monitoring title/artist transitions. Emits `TrackChangeEvent` with metadata payload.
- `Audio/MusicKitBridge.swift` — Optional MusicKit integration: request authorization, query Apple Music catalog for richer metadata (genre, mood tags, tempo hints) when available. Graceful no-op if user declines or isn't subscribed.
- `Audio/MetadataPreFetcher.swift` — On each `TrackChangeEvent`, fires parallel async queries to MusicBrainz, Spotify Web API, and AcousticBrainz. Matches tracks by title + artist string similarity. Returns a `PreFetchedTrackProfile` struct that consolidates all available external data. Uses local caching (in-memory LRU + optional disk cache) so repeated plays of the same track don't re-query. Handles network failures gracefully — pre-fetched data is always optional enrichment, never a hard dependency.
- `Shared/AudioFeatures.swift` — Add `TrackMetadata` struct (title, artist, album, genre, duration, artwork URL, source service) and `PreFetchedTrackProfile` struct (external BPM, key, energy, valence, danceability, genre tags, confidence scores)
- `Audio/AudioInputRouter.swift` — Integrate metadata alongside the audio callback. Add an `onTrackChange` callback or expose a metadata stream parallel to `onAudioSamples`.

**Verification:** Play a song in Spotify, then switch to Apple Music. Phosphene's debug overlay shows the correct track title, artist, and duration from both services. Within 2 seconds of a track change, the debug overlay also shows pre-fetched data: "Spotify API: BPM 128, Key Cm, Energy 0.82, Valence 0.34" (or "Pre-fetch: unavailable" if the track can't be matched). Track change events fire accurately within 1 second of an actual track change.

### Increment 2.2: CoreML Stem Separation Model Conversion

**Goal:** Convert an open-source stem separation model (HTDemucs or Open-Unmix) to CoreML `.mlpackage` targeting the ANE.

**This is a Python-side task.** Claude Code will:
- Write a Python script `tools/convert_stem_model.py` that:
  - Loads the pre-trained PyTorch model
  - Traces/exports to ONNX
  - Converts via `coremltools` to `.mlpackage` with `compute_units=.cpuAndNeuralEngine`
  - Validates output shape: input `[1, 2, T]` → output `[4, 2, T]` (4 stems x stereo x samples)
- Write a companion test script that runs inference on a sample WAV and writes 4 output WAVs

**Verification:** Four output WAV files (vocals, drums, bass, other) sound correct when played individually.

### Increment 2.3: Swift CoreML Stem Separator Integration

**Goal:** Load the `.mlpackage` in Swift, run inference on the ANE, write separated stems into UMA buffers.

**Files to create/edit:**
- `ML/StemSeparator.swift` — Load `MLModel`, configure for `.cpuAndNeuralEngine`, accept `UMABuffer<Float>` input, write 4 stem `UMABuffer<Float>` outputs
- Update `Audio/AudioBuffer.swift` to provide chunked audio windows (e.g., 4096 samples) suitable for model input
- Provide an async pipeline: audio chunk → stem separation → stem buffers updated

**Verification:** In debug overlay, show per-stem RMS levels that independently react (e.g., drums spike on kick hits while vocals remain stable).

### Increment 2.4: MIR Feature Extraction Pipeline

**Goal:** Implement real-time Music Information Retrieval feature extraction on the CPU using Accelerate.

**Files to create/edit:**
- `DSP/SpectralAnalyzer.swift` — Spectral centroid, spectral rolloff, spectral flux (all via vDSP)
- `DSP/ChromaExtractor.swift` — 12-bin chroma vector from FFT, key estimation
- `DSP/BeatDetector.swift` — Onset detection via spectral flux thresholding, tempo estimation via autocorrelation
- `DSP/FeatureVector.swift` — Combines all features into a single SIMD-aligned struct written to UMA buffer

**Verification:** Console logs: "BPM: 128, Key: Am, Centroid: 3400Hz, Brightness: 0.72" updating in real time.

### Increment 2.5: Mood Classification Model

**Goal:** Train or convert a lightweight valence/arousal classifier and deploy on ANE.

**Claude Code tasks (Python side):**
- Write `tools/train_mood_classifier.py` — A small feedforward network that takes the MIR feature vector and outputs (valence, arousal) in [-1, 1]
- Train on a labeled dataset (or use a pre-annotated one like MusicMood or DEAM)
- Convert to `.mlpackage`

**Swift side:**
- `ML/MoodClassifier.swift` — Load model, run inference on feature vectors, expose `EmotionalState` (valence, arousal, quadrant label)
- `Shared/AudioFeatures.swift` — Add `EmotionalState` struct

**Verification:** App displays "Mood: Happy/Energetic (V:0.7 A:0.8)" in debug overlay, updating per segment.

### Increment 2.6: Analysis Lookahead Buffer

**Goal:** Introduce a configurable delay between audio analysis and visual rendering so that the Orchestrator can see upcoming musical moments before the renderer needs to respond to them.

**Design rationale:** In a streaming context, the audio signal arrives in real time with no ability to peek ahead in the file. However, Phosphene can create its own lookahead window by introducing a deliberate delay between analysis and rendering. The audio pipeline analyzes incoming PCM immediately as it arrives, but the *visual rendering* of those analyzed frames is delayed by a configurable duration (default: 2.5 seconds, range: 0–5 seconds). This means that when the Orchestrator sees a massive energy spike from a drop or a sudden silence from a breakdown, it has 2.5 seconds of lead time to prepare — pre-loading the next preset, initiating a transition, or ramping visual parameters.

This delay is imperceptible to the user because there is no reference signal to synchronize against. The music is playing from their speakers in real time, and the visuals appear to be perfectly reactive. A 2.5-second visual latency in a music visualizer is effectively invisible — this is standard practice in professional VJ software and concert lighting systems.

**Pipeline architecture:**
```
Core Audio Tap → PCM frames → [Analysis Pipeline: FFT, Stems, MIR, Mood] → Analyzed Frames Queue
                                                                                      │
                                                                            ┌─────────┘
                                                                            │ 2.5s delay
                                                                            ▼
                                                              Orchestrator decisions ──→ Metal Renderer
```

**Files to create/edit:**
- `Audio/LookaheadBuffer.swift` — A timestamped ring buffer that sits between the analysis pipeline and the Orchestrator/renderer. Analyzed frames (containing FFT, stem data, MIR features, and mood classification results) are enqueued immediately. The renderer dequeues frames from the buffer after a configurable delay. The Orchestrator has access to *both* the current analysis head (for lookahead decisions) and the render head (for current visual state).
- `Audio/AudioInputRouter.swift` — Updated to expose two callback paths: `onAnalysisFrame` (real-time, for the Orchestrator's lookahead window) and `onRenderFrame` (delayed, for the renderer and the Orchestrator's "current frame" decisions). Note: the router currently uses callback-based API (`onAudioSamples`), not AsyncStream — this dual-tap extension should follow the same pattern.
- `Shared/AnalyzedFrame.swift` — A timestamped container struct that bundles all analysis outputs for a single audio window: `AudioFrame` + `FFTResult` + `StemData` + `FeatureVector` + `EmotionalState`. This is the unit that flows through the lookahead buffer.

**Verification:** Enable a debug visualization that renders two small oscilloscopes: one driven by the analysis head (real-time) and one by the render head (delayed). Confirm the render oscilloscope lags the analysis oscilloscope by exactly the configured duration. Play a track with a dramatic drop — confirm the Orchestrator's debug log shows it detected the drop 2.5 seconds before the visual transition fires.

### Increment 2.7: Progressive Structural Analysis

**Goal:** Implement a real-time structural segmentation system that progressively learns the song's form (intro, verse, chorus, bridge, outro) and predicts when future section changes will occur.

**Design rationale:** Popular music is overwhelmingly repetitive in structure. After hearing a verse and a chorus, the system can predict with high confidence when the next chorus will arrive, because verses and choruses tend to have consistent durations within a track. This prediction gives the Orchestrator advance notice of major structural transitions — exactly the kind of anticipation that pre-scanning a local file would have provided.

**Algorithm overview:**
1. Continuously compute a **self-similarity matrix** from MIR feature vectors. Each new frame is compared against all previously observed frames using cosine similarity of the chroma + MFCC feature vectors.
2. Apply a lightweight **novelty detection** function along the diagonal of the self-similarity matrix. Peaks in the novelty function indicate section boundaries (e.g., verse → chorus, chorus → bridge).
3. Once two or more boundaries have been detected, estimate **section durations** and look for **recurring patterns** (e.g., "the last two sections were each 16 bars long, and the current section sounds like the first section, so it will probably also be 16 bars long").
4. Combine section predictions with BPM (from the MIR pipeline) to generate a **predicted next boundary timestamp** with a confidence score.
5. If `PreFetchedTrackProfile` from Increment 2.1 includes a track duration, use it to estimate how much of the song remains and improve boundary predictions near the expected end of the track.

**Files to create/edit:**
- `DSP/StructuralAnalyzer.swift` — Maintains the growing self-similarity matrix (ring buffer capped at ~5 minutes of history). Computes novelty function. Detects section boundaries. Estimates section type labels (repetition = same section type, novelty = new section type). Predicts next boundary timestamp. Exposes `StructuralPrediction` struct: `currentSectionStarted: TimeInterval`, `predictedNextBoundary: TimeInterval?`, `confidence: Float`, `sectionIndex: Int`, `isRepeatOfSection: Int?`.
- `DSP/SelfSimilarityMatrix.swift` — Efficient computation and storage of frame-by-frame cosine similarity. Uses Accelerate/vDSP for vectorized dot products. Ring-buffer-based to cap memory usage.
- `DSP/NoveltyDetector.swift` — Checkerboard kernel convolution along the self-similarity diagonal. Peak picking with adaptive threshold. Outputs detected boundary timestamps.
- `Shared/AnalyzedFrame.swift` — Add `StructuralPrediction` to the analyzed frame struct.

**Verification:** Play a pop song with clear verse-chorus structure. After the first chorus ends (~60–90 seconds in), the debug overlay shows: "Section 3 started at 1:32. Predicted next boundary: ~2:15 (confidence: 0.78). Current section similar to Section 1 (verse)." The predicted boundary should be within ±5 seconds of the actual structural change. For a second test, play an ambient/drone track with no clear structure — the system should report low confidence predictions rather than hallucinating false boundaries.

---

## Phase 3 — Advanced Metal Rendering (Blueprint Release 0.5)

### Increment 3.1: Compute Shader Particle System

**Goal:** GPU compute pipeline that simulates millions of particles driven by stem-separated audio.

**Files to create/edit:**
- `Renderer/Shaders/Particles.metal` — Compute kernel: read drum stem buffer → emit particles on transients, read bass stem → apply gravity/attraction fields, velocity integration, lifetime management
- `Renderer/Geometry/ProceduralGeometry.swift` — Manage particle buffer (position, velocity, color, life), dispatch compute, draw as point sprites or instanced quads
- Bind particle render into the main render pass

**Verification:** Millions of particles on screen. Kick drum triggers burst emission. Bass drives swirling gravity well. Visually confirms stem routing.

### Increment 3.2: Mesh Shader Pipeline (Object + Mesh Shaders)

**Goal:** Implement Metal mesh shading for procedural fractal and geometric generation.

**Files to create/edit:**
- `Renderer/Shaders/MeshShaders.metal` — Object shader for culling/LOD, Mesh shader outputting meshlets (max 256 verts / 512 prims per threadgroup)
- `Renderer/Geometry/MeshGenerator.swift` — Configure mesh render pipeline state with `MTLMeshRenderPipelineDescriptor`, dispatch mesh draws
- Write a fractal preset: recursive branching tree whose depth and angle respond to audio features

**Verification:** 3D fractal structure renders, branches sway/grow in response to music. Frame rate stays above 60 fps.

### Increment 3.3: Hardware Ray Tracing Integration

**Goal:** Add ray-traced reflections and shadows to geometric presets using `MPSRayIntersector`.

**Files to create/edit:**
- `Renderer/RayTracing/BVHBuilder.swift` — Build `MPSAccelerationStructure` from mesh-shader-generated geometry each frame (or rebuild on significant change)
- `Renderer/RayTracing/RayIntersector.swift` — Cast shadow rays and reflection rays, write results to a lighting texture
- `Renderer/Shaders/PostProcess.metal` — Composite ray-traced lighting with rasterized output, apply bloom and tone mapping

**Verification:** Geometric preset shows glossy reflections and soft shadows that shift with the music. Toggle ray tracing on/off to see the visual difference.

### Increment 3.4: Indirect Command Buffers for GPU-Driven Rendering

**Goal:** Eliminate CPU draw-call encoding by having a compute shader populate an ICB based on audio state.

**Files to create/edit:**
- `Renderer/RenderPipeline.swift` — Create `MTLIndirectCommandBuffer`, configure with max command count
- Write a compute shader that evaluates current audio features and encodes draw commands (bind vertex buffers, set pipeline states, issue draws) into the ICB
- Execute the ICB in the render pass

**Verification:** CPU frame time drops dramatically. GPU Debugger shows draw calls originating from compute, not CPU. Preset with thousands of distinct objects renders smoothly.

---

## Phase 4 — AI Orchestrator & VJ Logic (Blueprint Release 0.7)

### Increment 4.1: Preset Categorization & Metadata System

**Goal:** Build the data layer that tags every preset with its category, visual characteristics, and optimal mood match.

**Files to create/edit:**
- `Presets/PresetCategory.swift` — Expand with metadata: color temperature (warm/cool), geometric complexity (low/med/high), motion intensity, bloom level
- `Presets/PresetLoader.swift` — Parse embedded metadata from preset files or a sidecar JSON manifest
- Create `presets_manifest.json` with entries for all native presets and their properties

**Verification:** `PresetLoader.presets(forMood: .highValenceHighArousal)` returns the correct subset.

### Increment 4.2: Emotion-to-Visual Semantic Mapper

**Goal:** Implement the mapping matrix from the blueprint — emotional quadrant to visual parameters.

**Files to create/edit:**
- `Orchestrator/EmotionMapper.swift` — Takes `EmotionalState` and returns `VisualDirective` (target preset category, color palette, camera speed, bloom intensity, particle emission rate, ray-trace bounce limit)
- `Shared/VisualDirective.swift` — The struct that parameterizes the renderer

**Verification:** Unit tests covering all four quadrants produce expected directives. E.g., (V:-0.8, A:0.2) → fractal category, cool blues, slow dissolve.

### Increment 4.3: Transition Engine

**Goal:** Smooth crossfading between two active presets using dual render targets and interpolation.

**Files to create/edit:**
- `Orchestrator/TransitionEngine.swift` — Maintains two `RenderPipeline` instances, alpha-blends their output textures over a configurable duration, supports dissolve / morph / wipe transition styles
- `Renderer/Shaders/Transition.metal` — Fragment shader that blends two input textures with various transition functions (linear dissolve, radial wipe, noise-driven morph)
- `Renderer/RenderPipeline.swift` — Support rendering to offscreen texture (not directly to drawable) for transition composition

**Verification:** Press a key to trigger a transition. Two presets blend smoothly over 2 seconds with no frame drops.

### Increment 4.4: Streaming-Aware Orchestrator Core

**Goal:** The main Orchestrator that fuses all three anticipation systems (lookahead buffer, metadata pre-fetching, and structural analysis) into a single decision engine that matches or exceeds the quality of pre-scanned local file analysis.

**Design rationale:** The Orchestrator consumes three layers of temporal intelligence, each with different latency and confidence characteristics:

| Anticipation Source | Available After | What It Provides |
|---|---|---|
| **Pre-fetched metadata** (Increment 2.1) | ~1–2 seconds into track | BPM, key, energy, valence, genre, track duration (from Spotify/MusicBrainz/MusicKit) |
| **Lookahead buffer** (Increment 2.6) | Continuously, 2.5s ahead | Upcoming FFT, stem, MIR, and mood data — knows drops, builds, silences before they render |
| **Structural predictions** (Increment 2.7) | ~15–30 seconds into track | Predicted section boundaries, section type (verse/chorus/bridge), time until next transition |

The Orchestrator's decision quality ramps up progressively as these sources come online:

- **Seconds 0–2:** Fallback to genre tags from Now Playing metadata (if available) or a neutral default preset. No audio-derived intelligence yet.
- **Seconds 2–5:** Pre-fetched metadata arrives. Orchestrator selects a mood-appropriate preset category using external BPM/energy/valence. Lookahead buffer begins providing analyzed frames.
- **Seconds 5–15:** MIR pipeline has accumulated enough audio for reliable tempo, key, and mood estimation. Orchestrator cross-validates its own MIR output against pre-fetched metadata and uses the higher-confidence source for each parameter.
- **Seconds 15–30:** Structural analyzer identifies the first section boundary. From this point forward, the Orchestrator can predict upcoming transitions and pre-initiate visual crossfades 2–3 seconds before a section change occurs.
- **Seconds 30+:** Structural predictions stabilize with high confidence. The Orchestrator operates at full capability — functionally equivalent to having pre-scanned the track.

**Files to create/edit:**
- `Orchestrator/AnticipationEngine.swift` — Central fusion module. Subscribes to: `analysisStream` (real-time lookahead head), `renderStream` (delayed render head), `PreFetchedTrackProfile` updates, and `StructuralPrediction` updates. Maintains a unified `AnticipationState` struct that represents the Orchestrator's best current understanding: confirmed tempo, estimated key, mood trajectory over the next 2.5 seconds, predicted next section boundary, and time-to-track-end. Implements confidence-weighted merging when multiple sources provide the same data (e.g., MIR-derived BPM vs. Spotify-provided BPM).
- `Orchestrator/Orchestrator.swift` — State machine: idle → listening → ramping → full. On audio input: enters `ramping` state, selects initial preset using whatever intelligence is available (metadata first, then MIR as it comes online). On reaching structural analysis confidence threshold: enters `full` state. Continuously queries `AnticipationEngine` for upcoming decisions. Schedules transitions proactively — when `AnticipationEngine` reports a section boundary in 3 seconds, the Orchestrator begins the crossfade immediately so that the visual transition *lands* on the musical transition rather than reacting to it after the fact.
- `Orchestrator/TrackChangeDetector.swift` — Detects track boundaries via three fused signals: (1) `TrackMetadata` change events from Now Playing, (2) audio-level heuristics (brief silence or dramatic spectral shift detected in the lookahead buffer), and (3) elapsed time approaching the pre-fetched track duration. On track change: resets `AnticipationEngine` and `StructuralAnalyzer` state, fires pre-fetch queries for the new track.
- Implement a heuristic policy first (no RL): match mood quadrant to category, avoid repeating same category twice in a row, prefer smooth energy transitions, use genre tags from pre-fetched metadata to influence category weighting. Factor in structural predictions: prefer to transition between presets at section boundaries rather than mid-section.

**Verification:** Stream a playlist in Apple Music with at least 5 tracks spanning different genres. Test criteria:
1. **Track 1 cold start:** Orchestrator selects a reasonable preset within 3 seconds using pre-fetched metadata (or a neutral default if pre-fetch fails). No black screen or "loading" state.
2. **Mid-track reactivity:** When a dramatic drop occurs, the lookahead buffer gives the Orchestrator advance notice — the visual transition should begin *before* the drop hits the speakers, not after.
3. **Section boundary prediction:** After the first verse-chorus transition, subsequent section changes should produce visual transitions that feel pre-planned, not reactive.
4. **Track change smoothness:** Between songs, the Orchestrator detects the boundary within 2 seconds, begins a transition, and has the new track's pre-fetched metadata informing preset selection before the MIR pipeline has caught up.
5. **Debug log shows decision rationale** including which anticipation source drove each decision and the confidence level.

### Increment 4.5: Reinforcement Learning Agent (Optional / Advanced)

**Goal:** Replace the heuristic policy with a trained DQN agent.

**This is a Python training task:**
- `tools/train_orchestrator_rl.py` — Simulated environment where the agent observes an `AnticipationState` (MIR features, pre-fetched metadata, structural predictions, lookahead mood trajectory) and selects from preset categories. Reward function penalizes jarring transitions, rewards energy matching, and gives bonus reward for transitions that land on predicted section boundaries.
- Export trained policy weights to CoreML `.mlpackage`

**Swift side:**
- `Orchestrator/Orchestrator.swift` — Load RL model, query it instead of heuristic rules, fall back to heuristic if model unavailable

**Verification:** Playlist visual selection improves subjectively over heuristic. A/B comparison in debug mode.

---

## Phase 5 — Legacy Preset Support (Blueprint Release 0.5–0.9)

### Increment 5.1: Milkdrop Preset Parser

**Goal:** Parse `.milk` preset files — extract per-frame equations, per-vertex equations, waveform definitions, and composite shader code.

**Files to create/edit:**
- `Presets/LegacyTranspiler.swift` — INI-style parser for `.milk` files. Extract sections: `[preset00]` per-frame vars, per-vertex equations, warp/composite HLSL code
- Define an intermediate representation `LegacyPreset` struct holding parsed equations and shader source

**Verification:** Parse 20 representative Cream of the Crop presets. All fields extracted. No crashes on malformed files.

### Increment 5.2: Equation Evaluator

**Goal:** Runtime evaluator for Milkdrop's per-frame and per-vertex math expressions.

**Files to create/edit:**
- `Presets/EquationEvaluator.swift` — Tokenizer + recursive descent parser for Milkdrop equation syntax (supports `sin`, `cos`, `abs`, `if`, `pow`, `log`, `rand`, built-in variables like `bass`, `mid`, `treb`, `time`)
- Compile parsed equations to a fast evaluation function (closure or bytecode interpreter)

**Verification:** Evaluate `rot = rot + 0.01 * bass_att` with mock audio data. Results match reference Milkdrop output.

### Increment 5.3: HLSL-to-Metal Shader Transpilation

**Goal:** Convert Milkdrop's HLSL warp/composite shaders to Metal Shading Language.

**Files to create/edit:**
- `Presets/LegacyTranspiler.swift` — Extend with HLSL-to-MSL conversion: remap `tex2D` to `texture.sample()`, `float4` type mappings, register-based texture binding to argument buffer binding
- Alternative: integrate Apple's `metal-shader-converter` CLI as a build-time step for batch conversion

**Verification:** 50 legacy presets render visually identically (or near-identically) to ProjectM reference screenshots.

---

## Phase 6 — UI & User Experience (Blueprint Release 0.9)

### Increment 6.1: SwiftUI Application Shell

**Goal:** Main window with Metal view, audio source controls, and streaming-aware HUD.

**Files to create/edit:**
- `PhospheneApp/Views/ContentView.swift` — Full-screen Metal view with overlay HUD that auto-hides on inactivity
- `PhospheneApp/Views/TransportBar.swift` — Audio source selector (system audio / specific app / local file fallback), fullscreen toggle, preset cycle override, settings gear
- `PhospheneApp/Views/AudioSourcePicker.swift` — Lists running audio-producing applications (via `SystemAudioCapture.availableApplications()` which uses `NSWorkspace.shared.runningApplications`) with icons. User selects which app to visualize, or "System Audio" for the full mix. Shows currently detected track info (title, artist, artwork) from Now Playing metadata.
- `PhospheneApp/Views/NowPlayingBanner.swift` — Floating overlay showing current track info and album artwork (sourced from MusicKit or Now Playing), current mood quadrant, active preset name, and anticipation status indicator (shows ramp-up progress: "learning structure..." → "fully anticipating"). Fades in on track change, fades out after a few seconds.
- `PhospheneApp/ViewModels/AppViewModel.swift` — Binds UI state to engine

**Verification:** User opens Phosphene, selects Spotify from the audio source picker, starts playing music in Spotify. Visualizations begin. The Now Playing banner shows the correct track info. Switching to Apple Music updates the source seamlessly.

### Increment 6.2: Visual History Timeline & Orchestrator Overlay

**Goal:** A timeline strip showing the Orchestrator's real-time decisions and mood analysis as a scrolling history.

**Design rationale:** In a streaming context, the timeline can't show a future playlist — the next track is unknown. Instead, it shows a scrolling history of what has played: mood arc, preset selections, and detected track changes. If local files are loaded (fallback mode), or if MusicKit provides queue info, it can also show upcoming tracks.

**Files to create/edit:**
- `PhospheneApp/Views/TimelineView.swift` — Horizontally scrolling timeline: colored segments per detected track showing mood quadrant, preset category labels, transition points. Auto-scrolls to follow playback. Expands rightward as new tracks play.
- `PhospheneApp/Views/PresetOverrideSheet.swift` — Click the current segment to override the active preset. Also allows locking a preset so the Orchestrator doesn't auto-switch.
- `PhospheneApp/ViewModels/TimelineViewModel.swift` — Subscribe to Orchestrator state, append history entries on track changes and preset transitions

**Verification:** Stream three songs. The timeline populates with three color-coded segments. Mood labels match the character of the music. User can click the active segment and force a different preset.

### Increment 6.3: Settings & Performance Dashboard

**Goal:** Preferences panel and real-time performance metrics.

**Files to create/edit:**
- `PhospheneApp/Views/SettingsView.swift` — Ray tracing on/off, particle density slider, transition speed, analysis lookahead delay (0–5s slider, default 2.5s), default audio source preference (remember last selected app), MusicKit authorization toggle, Spotify Web API key configuration, target frame rate, local file fallback option
- `PhospheneApp/Views/PerformanceDashboard.swift` — Overlay showing FPS, GPU utilization, ANE utilization, memory usage, current mood state, active stems, anticipation system status (lookahead buffer depth, pre-fetch latency, structural prediction confidence, Orchestrator state: ramping/full), and active data sources (Now Playing, MusicKit, Spotify API, MusicBrainz)

**Verification:** Toggling ray tracing shows immediate FPS impact. All metrics update live.

---

## Phase 7 — Optimization & Polish (Blueprint Release 0.9–1.0)

### Increment 7.1: Metal Performance Profiling Pass

**Goal:** Profile with Instruments and Metal Debugger. Eliminate bottlenecks.

**Claude Code tasks:**
- Add `os_signpost` markers to key pipeline stages (audio capture, stem separation, FFT, render encode, present)
- Document profiling methodology in `docs/PROFILING.md`
- Review all `MTLBuffer` allocations — ensure `.storageModeShared` everywhere, no accidental copies
- Verify Dynamic Caching is being utilized (no manual cache management competing with it)

**Verification:** Instruments trace shows no CPU-GPU sync stalls. Frame time under 8ms at 120fps on M3 Pro.

### Increment 7.2: Memory & Resource Optimization

**Goal:** Minimize memory footprint, ensure no disk swapping.

**Claude Code tasks:**
- Implement resource pooling for transient textures and buffers
- Add `MTLHeap` for grouped allocations where appropriate
- Implement LOD (level of detail) for particle counts and mesh complexity based on available GPU headroom
- Ensure ML model memory is released when not actively inferring

**Verification:** Activity Monitor shows stable memory under extended playback. No swap usage.

### Increment 7.3: Public Preset SDK & Documentation

**Goal:** Define the API for community preset authors.

**Files to create/edit:**
- `docs/PRESET_SDK.md` — Guide for writing native Phosphene presets: Metal shader API, available audio buffers (raw PCM, FFT, stems, features), preset manifest format, hot-reload workflow
- `PhospheneEngine/Presets/PresetSDK.swift` — Public protocol and types exported as a Swift module
- 3 example presets with extensive comments as templates

**Verification:** An external developer can read the SDK doc, write a `.metal` preset, drop it in the presets folder, and see it appear in the app.

---

## Phase 8 — Release Candidate (Blueprint Release 1.0)

### Increment 8.1: Cream of the Crop Batch Import

**Goal:** Automated pipeline to import, transpile, categorize, and index all 9,795 legacy presets.

**Claude Code tasks:**
- Write `tools/batch_import_presets.py` — Download the Cream of the Crop repo, parse all `.milk` files, auto-categorize by directory, run transpiler, output Metal shaders + manifest JSON
- Handle edge cases: presets with syntax errors, unsupported HLSL features (log warnings, skip gracefully)

**Verification:** At least 90% of presets transpile and render. Skipped presets are logged with reasons.

### Increment 8.2: App Store Packaging & Signing

**Goal:** Archive, sign, and prepare for distribution.

**Claude Code tasks:**
- Configure entitlements: network client (for MusicKit catalog queries, MusicBrainz/Spotify Web API metadata pre-fetching, and future updates), file access (for local file fallback and preset loading). Note: Core Audio taps do not require ScreenCaptureKit entitlements, but `NSScreenCaptureUsageDescription` is retained in Info.plist for potential future use.
- Set up app icons and launch screen
- Configure archive scheme with release optimizations (`-O` for Swift, `-Os` for Metal)
- Write `docs/RELEASE_CHECKLIST.md`

**Verification:** `xcodebuild archive` succeeds. Notarization passes. App launches from exported `.app` bundle.

---

## Claude Code Session Guidelines

### Context Window Management

Each increment above is designed so that Claude Code can:

1. **Read** the relevant existing files (typically 3-5 files, under 2000 lines total)
2. **Write** new code (typically 200-600 lines of new/modified code per increment)
3. **Run** build verification (`xcodebuild` or `swift test`)
4. **Iterate** on compiler errors within the same session

**If an increment feels too large during execution**, split it further. The natural split point is always at a file boundary — finish one file completely before starting the next.

### Prompt Template for Claude Code Sessions

When starting each increment, provide Claude Code with:

```
Working on Phosphene increment [X.Y]: [Name]
Goal: [one sentence]
Files to read first: [list paths]
Files to create/modify: [list paths]
Build command: xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build
Test command: swift test --package-path PhospheneEngine
```

### Key Technical Constraints to Reiterate

- **macOS 14.0+ only** — no iOS, no cross-platform
- **Metal only** — never OpenGL, never Vulkan
- **Core Audio taps for audio** — primary audio input is system audio capture via `AudioHardwareCreateProcessTap` (macOS 14.2+), not file loading. ScreenCaptureKit was abandoned because it silently fails to deliver audio callbacks on macOS 15+/26. Core Audio taps require no special entitlements or user permission prompts for system audio.
- **ANE for ML** — always configure CoreML models with `.cpuAndNeuralEngine`, never `.all` (which would compete with GPU)
- **UMA zero-copy** — all shared buffers must use `.storageModeShared`
- **Swift concurrency** — use `async/await` and actors for thread safety, avoid raw `DispatchQueue` where possible
- **No C++ interop in Phase 1-4** — pure Swift + Metal Shading Language. C++ interop only if absolutely required for legacy preset parsing
- **Graceful metadata degradation** — MusicKit is optional (requires Apple Music subscription). Now Playing metadata is best-effort. Pre-fetched metadata from external APIs is best-effort. Phosphene must function fully with audio-only (no metadata) from any source — quality improves with more metadata but never depends on it.
- **Analysis lookahead is always on** — The lookahead buffer defaults to 2.5 seconds and should never be disabled in the Orchestrator's decision path, even if the user sets it to 0 in the UI (the UI setting controls visual latency, not analysis pipelining). The Orchestrator should always consume the real-time analysis head for its decisions.
- **Network calls are non-blocking** — Metadata pre-fetching (MusicBrainz, Spotify Web API) must never block the audio or rendering pipelines. All queries are async with short timeouts (3 seconds). Cache aggressively. If the network is unavailable, the system falls back silently to audio-only intelligence.

### Dependency Installation Checklist

Run this once before beginning development:

```bash
# 1. Xcode (must be installed from App Store first)
xcode-select --install
sudo xcodebuild -license accept

# 2. Homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# 3. CLI tools
brew install python@3.11 ffmpeg git-lfs swiftlint
git lfs install

# 4. Python ML environment
python3.11 -m venv ~/phosphene-ml-env
source ~/phosphene-ml-env/bin/activate
pip install coremltools torch torchaudio onnx onnxruntime librosa numpy scipy

# 5. Metal Shader Converter (download manually)
# https://developer.apple.com/metal/ → "Metal Shader Converter" download
# Install to /usr/local/bin/metal-shader-converter

# 6. Verify
xcrun metal --version          # Metal compiler
python3.11 -c "import coremltools; print(coremltools.__version__)"
ffmpeg -version
```
