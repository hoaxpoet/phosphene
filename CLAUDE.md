# CLAUDE.md — Phosphene

## What This Is

Phosphene is a native macOS music visualization engine for Apple Silicon. It captures live system audio from streaming services (Apple Music, Spotify, Tidal, etc.) via Core Audio taps (`AudioHardwareCreateProcessTap`), performs real-time audio analysis and ML-powered stem separation, and renders Metal-based visuals that respond to the music's frequency content, rhythm, and emotional character.

Users do NOT load audio files. They play music in their streaming app and Phosphene visualizes it. Phosphene is a passive listener — it never controls playback.

The name references the visual phenomenon of perceiving light and patterns without external visual stimulus — exactly what this software does with sound.

### Core Use Cases

1. **Listening party backdrop**: Friends gather, each brings a mix. Phosphene runs fullscreen on a TV or projector, producing synchronized visuals while people listen together.
2. **Ambient accompaniment**: Solo listening — reading, working, unwinding — with visuals on a secondary display or in a window.
3. **Creative enhancement**: Immersive visual accompaniment to deepen the listening experience.

### Lineage

This is a ground-up native Swift/Metal rewrite. A prior Electron/WebGL prototype (v0.1–v0.2) validated the core audio analysis pipeline, visual feedback architecture, and shader design philosophy. That prototype's proven tuning constants, design decisions, and documented failure modes are preserved in this document. Do not re-learn them.

## Build & Test

```bash
xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build
swift test --package-path PhospheneEngine
swiftlint lint --strict --config .swiftlint.yml
```

Warnings-as-errors is enforced per-target via `PhospheneApp/Phosphene.xcconfig`
(`SWIFT_TREAT_WARNINGS_AS_ERRORS = YES`) — do NOT pass the flag on the command
line, as it would propagate to SPM dependencies that compile with
`-suppress-warnings` and conflict at the Swift driver level.

Deployment target: macOS 14.0+ (Sonoma). Swift 6.0. Metal 3.1+.

**Current test count: 213 tests** (unit, integration, regression, performance). All must pass before any new code is merged.

## Module Map

```
PhospheneApp/               → SwiftUI shell, views, view models
  ContentView.swift         → Main view + VisualizerEngine (audio→FFT→render pipeline owner)
  PhospheneApp.swift        → App entry point
  Views/MetalView.swift     → NSViewRepresentable wrapping MTKView

PhospheneEngine/
  Audio/                    → Core Audio tap capture, ring buffers, FFT
    SystemAudioCapture      → Core Audio tap wrapper: system-wide or per-app (✓ implemented)
    AudioInputRouter        → Unified source abstraction: system/app/file → callbacks + dual analysis/render frame callbacks (✓ implemented)
    LookaheadBuffer         → Timestamped ring buffer, dual read heads (analysis + render), configurable delay (✓ implemented)
    AudioBuffer             → IO proc → UMARingBuffer<Float> bridge for GPU (✓ implemented)
    FFTProcessor            → vDSP 1024-pt FFT → 512 magnitude bins in UMABuffer (✓ implemented)
    Protocols               → AudioCapturing, AudioBuffering, FFTProcessing, MoodClassifying, MetadataProviding, MetadataFetching (✓ implemented)
    StreamingMetadata       → AppleScript polling of Apple Music/Spotify, track change detection (✓ implemented)
    MetadataPreFetcher      → Parallel async queries, LRU cache, merge partial results (✓ implemented)
    MusicBrainzFetcher      → Free API, genre tags + duration from MusicBrainz recordings (✓ implemented)
    SpotifyFetcher          → Client credentials flow, search-only track matching (✓ implemented)
    SoundchartsFetcher      → Optional commercial API, BPM/key/energy/valence/danceability (✓ implemented)
    MusicKitBridge          → Optional MusicKit catalog enrichment, graceful no-op (✓ implemented)
  DSP/                      → Spectral analysis, beat/onset detection, chroma, MIR pipeline
    SpectralAnalyzer        → Spectral centroid, rolloff, flux via vDSP (✓ implemented)
    BandEnergyProcessor     → 3-band + 6-band energy, AGC, FPS-independent smoothing (✓ implemented)
    ChromaExtractor         → 12-bin chroma vector, Krumhansl-Schmuckler key estimation (✓ implemented)
    BeatDetector            → 6-band onset detection, grouped beat pulses, tempo via autocorrelation (✓ implemented)
    MIRPipeline             → Coordinator: all analyzers → FeatureVector for GPU (✓ implemented)
    SelfSimilarityMatrix    → Ring buffer of feature vectors, vDSP cosine similarity (✓ implemented)
    NoveltyDetector         → Checkerboard kernel boundary detection, adaptive threshold (✓ implemented)
    StructuralAnalyzer      → Section boundary prediction, repetition detection (✓ implemented)
  ML/                       → CoreML wrappers: stem separator, mood classifier
    Models/StemSeparator.mlpackage → Open-Unmix HQ 4-stem mask estimator for ANE (✓ converted)
    Models/MoodClassifier.mlpackage → Valence/arousal MLP for ANE (✓ trained)
    StemSeparator.swift      → STFT → CoreML → iSTFT pipeline, StemSeparating protocol (✓ implemented)
    MoodClassifier.swift    → 10-feature MLP → valence/arousal, MoodClassifying protocol (✓ implemented)
    ML.swift                → CoreML module imports
  Renderer/                 → Metal context, pipelines, shader library, compute particles
    MetalContext            → MTLDevice, command queue, triple-buffered semaphore, shared-texture helper (✓ implemented)
    ShaderLibrary           → Auto-discover .metal files, runtime compilation, cache (✓ implemented)
    RenderPipeline          → Feedback-texture ping-pong, warp/composite/blit passes, particle integration (✓ implemented)
    Protocols               → Rendering protocol for DI/testing (✓ implemented)
    Geometry/ProceduralGeometry → GPU compute particle system: UMA buffer + compute pipeline + render pipeline (✓ implemented)
    Shaders/Common.metal    → FeatureVector/FeedbackParams structs, hsv2rgb, fullscreen_vertex, feedback_warp_fragment, feedback_blit_fragment (✓ implemented)
    Shaders/Particles.metal → Murmuration compute kernel + bird silhouette vertex/fragment shaders (✓ implemented)
    Shaders/Waveform.metal  → 64-bar FFT spectrum + oscilloscope waveform (✓ implemented)
  Presets/                  → Preset loading, categorization, hot-reload, feedback support
    PresetLoader            → Auto-discover .metal presets, compile standard + additive-blend pipeline states (✓ implemented)
    PresetDescriptor        → JSON sidecar metadata with useFeedback flag (✓ implemented)
    PresetCategory          → Visual aesthetic families (11 categories including abstract) (✓ implemented)
    Shaders/Starburst.metal → "Murmuration" preset — dusk sky gradient backdrop (✓ implemented)
    Shaders/Waveform.metal  → Spectrum bars + oscilloscope preset (✓ implemented)
    Shaders/Plasma.metal    → Demoscene plasma preset (✓ implemented)
    Shaders/Nebula.metal    → Radial frequency nebula preset (✓ implemented)
  Orchestrator/             → AI VJ: anticipation engine, transitions, preset selection (stub)
  Shared/                   → UMA buffer wrappers, type definitions, logging
    UMABuffer               → Generic .storageModeShared MTLBuffer + UMARingBuffer (✓ implemented)
    AudioFeatures           → @frozen SIMD-aligned structs: AudioFrame, FFTResult, TrackMetadata, PreFetchedTrackProfile (✓ implemented)
    AnalyzedFrame           → Timestamped container: AudioFrame + FFTResult + StemData + FeatureVector + EmotionalState (✓ implemented)
    Logging                 → Per-module os.Logger instances (✓ implemented)

Tests/ (213 tests)
  Audio/                    → AudioBufferTests, FFTProcessorTests, StreamingMetadataTests, MetadataPreFetcherTests, LookaheadBufferTests (10)
  DSP/                      → SpectralAnalyzerTests (8), BandEnergyProcessorTests (5), ChromaExtractorTests (6), BeatDetectorTests (7), MIRPipelineUnitTests (4), SelfSimilarityMatrixTests (5), NoveltyDetectorTests (5), StructuralAnalyzerTests (8)
  ML/                       → StemSeparatorTests (8), MoodClassifierTests (7: model loading, classification, range, quadrants, protocol)
  Renderer/                 → MetalContextTests, ShaderLibraryTests, RenderPipelineTests, ProceduralGeometryTests (7: init, storage mode, dispatch, count, zero-audio, impulse, 1M perf)
  Shared/                   → AudioFeaturesTests, UMABufferExtendedTests, EmotionalStateTests (4: quadrant classification), AnalyzedFrameTests (3)
  Integration/              → AudioToFFTPipelineTests, AudioToRenderPipelineTests, MetadataToOrchestratorTests, AudioToStemPipelineTests, MIRPipelineIntegrationTests (3), LookaheadIntegrationTests (1)
  Regression/               → FFTRegressionTests, MetadataParsingRegressionTests, ChromaRegressionTests (2), BeatDetectorRegressionTests (2), StructuralAnalysisRegressionTests (1) + golden fixtures
  Performance/              → FFTPerformanceTests, RenderLoopPerformanceTests, StemSeparationPerformanceTests, DSPPerformanceTests (3)
  TestDoubles/              → MockAudioCapture, StubFFTProcessor, FakeStemSeparator, StubMoodClassifier, AudioFixtures, MockMetadataProvider, MockMetadataFetcher
```

---

## Audio Data Hierarchy — The Most Important Design Rule

**This hierarchy was learned the hard way in the Electron prototype. Beat-dominant designs feel out of sync. Continuous-energy-dominant designs feel locked to the music. This is non-negotiable.**

Audio data is organized in layers of decreasing synchronization fidelity. Every visual design decision must respect this ordering:

### Layer 1: Continuous Energy Bands (PRIMARY VISUAL DRIVER)
`bass`, `mid`, `treble` (3-band) and 6-band equivalents. These ARE the audio signal, smoothed and normalized. Feedback zoom, rotation, color shifts, and geometry deformation should be driven primarily by these values. They are perfectly synchronized by definition — there is zero detection delay.

### Layer 2: Spectrum and Waveform Textures (RICHEST DATA)
FFT magnitude spectrum (512 bins from 1024-point FFT) and raw time-domain waveform (1024 samples). These go to the GPU as buffer data, not reduced to scalar values. This is the key advantage over Milkdrop — modern GPUs can process 512+ frequency bins per fragment, enabling per-bin visual detail that was impossible in 2001. Also perfectly synchronized.

### Layer 3: Spectral Features (DERIVED CHARACTERISTICS)
Spectral centroid (brightness), continuous spectral flux (rate of change), MFCCs, chroma. Useful for modulating color temperature, visual complexity, scene behavior. Synchronized but one step removed from raw signal.

### Layer 4: Beat Onset Pulses (ACCENT ONLY — NEVER PRIMARY)
Discrete accent events that spike on detected onsets and exponentially decay. They add punch — a momentary flash, a brief burst, a color spike. They must NEVER be the dominant driver of visual motion because they have inherent timing jitter (±80ms) from threshold-crossing detection. The feedback loop amplifies this jitter, making beat-dominant visuals feel out of sync with the music.

### Layer 5: Stems (PER-INSTRUMENT ROUTING — NEW IN NATIVE BUILD)
CoreML-separated audio stems (Vocals, Drums, Bass, Other). Each stem feeds its own energy and spectral analysis. Enables targeted visual routing: bass stem drives low-frequency geometric deformation, drum stem triggers particle emission, vocal stem modulates color saturation. Stems inherit the same hierarchy — their continuous energy is primary, their onset pulses are accent.

**Rule of thumb for shader authors**: `base_zoom` and `base_rot` (continuous energy) should be 2–4x larger than `beat_zoom` and `beat_rot` (onset pulses). The continuous values do the heavy lifting; the beat adds spice.

---

## Proven Audio Analysis Tuning

These constants were validated across genres in the Electron prototype. Port them directly — do not re-tune from scratch.

### Frequency Bands

**3-band:**
- Bass: 20–250 Hz
- Mid: 250–4000 Hz
- Treble: 4000–20000 Hz

**6-band:**
- Sub Bass: 20–80 Hz (kick drums, 808s)
- Low Bass: 80–250 Hz (bass guitar, low synths)
- Low Mid: 250–1000 Hz (snare body, guitar, vocals)
- Mid High: 1000–4000 Hz (snare crack, hi-hats, presence)
- High Mid: 4000–8000 Hz (cymbals, air)
- High: 8000+ Hz (sibilance, sparkle)

### AGC (Automatic Gain Control)

Milkdrop-style average-tracking AGC ensures consistent visual reactivity regardless of source volume or genre:
- A slow running average (~5s adaptation time) tracks the baseline level per band
- Output = `raw / runningAverage * 0.5` — average levels map to ~0.5, loud moments reach 0.8–1.0, quiet moments sit at 0.2–0.3
- Two-speed warmup: fast initial adaptation (0.95 rate) stabilizes in ~1s, then switches to moderate rate (0.992) for ~2s settling
- 6-band AGC normalizes against total energy (not per-band), preserving relative differences between bands

### Smoothing

Two smoothing tiers per frame for 3-band values. All rates are FPS-independent via `pow(rate, 30/fps)`:
- **Instant** (`bass`, `mid`, `treble`): Fast smoothing for tight audio-reactive motion. Per-band rates: bass 0.65, mid/treble 0.75.
- **Attenuated** (`bass_att`, `mid_att`, `treb_att`): Heavy smoothing (0.95 rate) for slow, flowing motion — analogous to Milkdrop's `_att` values.

The 6-band values use the same per-band smoothing rates as their parent 3-band tier.

### Onset Detection

Spectral flux on the 6-band IIR RMS values — detects changes in per-band energy, not absolute levels.

Per frame, for each of 6 bands:
1. Compute spectral flux: `max(0, currentRMS - previousRMS)` (half-wave rectified)
2. Store flux in a circular buffer (50 frames ≈ 0.8s at 60fps)
3. Compute adaptive threshold: `median(buffer) × 1.5`
4. Onset fires when flux > threshold AND cooldown has elapsed

Per-band cooldowns (validated across genres):
- Low bands (sub_bass, low_bass): 400ms
- Mid bands (low_mid, mid_high): 200ms
- High bands (high_mid, high): 150ms

Grouped beat pulses:
- `beat_bass`: fires when sub_bass OR low_bass has onset (400ms group cooldown)
- `beat_mid`: fires when low_mid OR mid_high has onset (200ms group cooldown)
- `beat_treble`: fires when high_mid OR high has onset (150ms group cooldown)

Pulse decay: `pow(0.6813, 30/fps)` per frame — reaches 0.1 in ~200ms at 60fps.

### Validated Onset Counts (Reference — per 5-second window)

| Track | Genre | sub_bass | low_bass | low_mid | mid_high | high_mid | high |
|-------|-------|----------|----------|---------|----------|----------|------|
| Love Rehab (Chaim) | Electronic ~125 BPM | 11 | 10 | 20 | 4 | 0 | 1 |
| So What (Miles Davis) | Jazz ~136 BPM | 5 | 2 | 5 | 6 | 2 | 1 |
| There There (Radiohead) | Rock, syncopated | 6 | 7 | 21 | 18 | 16 | 5 |

If the native implementation produces substantially different counts for these tracks, the tuning has regressed.

---

## Visual Design Philosophy

### Milkdrop-Style Feedback Architecture

Every shader operates on the same core visual loop:
1. Read previous frame via a feedback texture (sampler)
2. Apply feedback transforms: zoom and rotation, driven primarily by continuous energy, with beat accents
3. Multiply by decay (typically 0.85–0.95) — creates trails and persistence
4. Composite new elements on top of the decayed/transformed previous frame
5. Output becomes next frame's feedback texture

Feedback personality is controlled by per-preset params:
- High decay (0.95): Long trails, smooth evolution, ambient feel
- Low decay (0.85): Short trails, snappy response, aggressive feel
- High base_zoom/base_rot: Strong continuous motion from audio energy (primary)
- Moderate beat_zoom/beat_rot: Accent pulses on top (secondary)

Feedback is implemented as a double-buffered render-to-texture ping-pong pattern.

### Color Philosophy

- Rich, saturated palettes — not pastel, not washed out
- Full spectrum: deep purples, electric blues, hot oranges, neon greens
- Dark backgrounds dominate — visuals emerge from darkness
- Gradients are first-class: smooth color transitions, not hard edges
- Spectral centroid modulates palette warmth (low = cool blues/purples, high = warm oranges/pinks)
- Always clamp output with `min(color, 1.0)` to prevent white clipping from feedback accumulation

### Scene Metadata Format

Each shader has a JSON sidecar defining its behavior. This format carries forward from the prototype:

```json
{
  "name": "Kaleidoscope",
  "family": "geometric",
  "duration": 25,
  "description": "Sacred geometry spiral — explosive beat rotation",
  "author": "Matt",
  "beat_source": "composite",
  "beat_zoom": 0.05,
  "beat_rot": 0.05,
  "base_zoom": 0.12,
  "base_rot": 0.06,
  "decay": 0.91,
  "beat_sensitivity": 1.2
}
```

| Field | Default | Description |
|-------|---------|-------------|
| `name` | required | Display name |
| `family` | required | Aesthetic family: `"fluid"`, `"geometric"`, `"abstract"` |
| `duration` | 30 | Preferred scene duration in seconds |
| `beat_source` | `"bass"` | Which onset drives the beat uniform: `"bass"`, `"mid"`, `"treble"`, `"composite"` |
| `beat_zoom` | 0.03 | Beat accent zoom (keep smaller than base_zoom) |
| `beat_rot` | 0.01 | Beat accent rotation |
| `base_zoom` | 0.12 | Continuous energy zoom (primary driver) |
| `base_rot` | 0.03 | Continuous energy rotation (primary driver) |
| `decay` | 0.955 | Feedback decay per frame. 0.85 = short trails. 0.95 = long. |
| `beat_sensitivity` | 1.0 | Beat pulse multiplier. 0.0 = ignore beats. Range 0–3.0. |

The scene manager auto-discovers shader files by scanning the presets directory. No manual registration.

---

## Hard Rules — Architecture

### Platform
- macOS only. No iOS, no cross-platform, no Catalyst, no Electron.
- Metal only. Never OpenGL, never Vulkan, never WebGL. Use Metal Shading Language (MSL).
- Apple frameworks only for system integration. No third-party audio capture or virtual audio drivers.

### Audio Input
- Primary input is ALWAYS Core Audio taps (`AudioHardwareCreateProcessTap`, macOS 14.2+), never file loading.
- `SystemAudioCapture` creates a process tap → aggregate device → IO proc pipeline delivering interleaved float32 PCM at 48kHz stereo on a real-time audio thread.
- `AudioInputRouter` abstracts three modes behind a callback API: `.systemAudio` (default), `.application(bundleIdentifier:)`, `.localFile(URL)`. Mode switching is seamless.
- `AudioBuffer` writes interleaved float32 from the IO callback into `UMARingBuffer<Float>` via pointer-based `write(from:count:)`.
- `FFTProcessor` reads the latest 1024 mono samples, applies Hann window, runs vDSP 1024-point FFT, writes 512 magnitude bins into `UMABuffer<Float>` for GPU binding.
- Local file playback via `AVAudioFile` exists only as a fallback for testing/offline use.
- Phosphene never controls music playback. It is a passive listener.
- App sandbox is disabled (`com.apple.security.app-sandbox = false`). `NSScreenCaptureUsageDescription` in Info.plist is kept for future ScreenCaptureKit fallback compatibility.

### Streaming Anticipation Pipeline

Because streaming audio arrives without a pre-scannable file, Phosphene employs three systems to recover anticipatory capability:

1. **Lookahead Buffer** — A deliberate 2.5s delay between audio analysis and visual rendering. The Orchestrator sees both the real-time analysis head (for anticipation) and the delayed render head (for current state). Always active internally.

2. **Metadata Pre-Fetching** — On track change (via Now Playing), fire parallel async queries to MusicBrainz, Spotify Web API, Apple Music catalog. Match by title+artist. Cache in LRU. 3-second timeouts. Network failures are silent — pre-fetched data is optional, never a dependency.

3. **Progressive Structural Analysis** — Self-similarity matrix from chroma + MFCC features. Novelty detection finds section boundaries. After 2+ boundaries, predict future boundary timestamps. Low-structure music produces low-confidence predictions, not false ones.

### Memory & GPU
- ALL shared buffers between CPU, GPU, and ANE: `MTLResourceOptions.storageModeShared` (UMA zero-copy).
- Never `.storageModePrivate` or `.storageModeManaged` unless GPU-exclusive.
- Dynamic Caching is hardware-managed. Do not manually manage GPU cache residency.

### Metal Rendering
- `MPSRayIntersector` for ray tracing. Never software ray-triangle intersection.
- Metal mesh shaders for procedural geometry. Vertex shader fallback for pre-M3 hardware.
- Indirect Command Buffers (ICBs) for GPU-driven rendering in performance-critical paths.
- Framebuffer feedback: double-buffered render-to-texture ping-pong.
- Post-processing: bloom → radial blur → chromatic aberration → tone mapping → color grading.
- Support EDR output via `CAMetalLayer` on HDR displays. SDR tone mapping fallback.

### CoreML / Neural Engine
- ALL CoreML models: `.cpuAndNeuralEngine` compute units. Never `.all` or `.cpuAndGPU` — GPU is reserved for rendering.
- Models are `.mlpackage` format in `ML/Models/`, tracked via Git LFS.
- **Stem separator architecture** (STFT split): CoreML model takes STFT magnitude spectrograms `[1, 2, 2049, nb_frames]`, outputs 4 filtered spectrograms `[4, 2, 2049, nb_frames]` (vocals, drums, bass, other). STFT/iSTFT handled in Swift via Accelerate/vDSP — CoreML cannot process complex numbers. Model: Open-Unmix HQ (LSTM-based, 68 MB). STFT params: n_fft=4096, hop=1024, sample_rate=44100. Fixed input size: 431 frames (~10s of audio at 44100 Hz). Shorter inputs are zero-padded; longer inputs are truncated.
- **ANE Float16 output**: Small CoreML models may output `Float16` MLMultiArrays on ANE. `MLShapedArray<Float16>` requires macOS 15+. Use `MLMultiArray` subscript access (`multiArray[index].floatValue`) for type-safe extraction compatible with macOS 14+.
- **ANE output buffer padding**: CoreML outputs from the Neural Engine have padded strides (e.g., stride[2]=448 for shape[3]=431, aligned for ANE tile sizes) but `dataPointer` only covers the logical element count — accessing padding indices causes SIGSEGV. Use `MLShapedArray.withUnsafeShapedBufferPointer` to correctly traverse padded layouts. Never use raw `MLMultiArray.dataPointer` with reported strides on ANE outputs.
- **STFT/iSTFT performance**: The current CPU-based STFT/iSTFT via Accelerate is the bottleneck (~6s for a 10s chunk across 4 stems × 2 channels). The endgame optimization is moving STFT/iSTFT to Metal compute shaders, eliminating CPU↔GPU copies entirely and enabling the separation pipeline to run within a single GPU command buffer alongside rendering. This is tracked as a future increment.
- Stem separator outputs: Vocals, Drums, Bass, Other — each independently routed to shaders.
- Mood classifier outputs continuous valence (-1…1) and arousal (-1…1), smoothed with EMA. Input: 10 features (6-band energy, centroid, flux, major/minor key correlations). Model: 914-parameter MLP on ANE.

### Orchestrator
- Four states: `idle` → `listening` → `ramping` → `full`.
- Visual transitions LAND on musical transitions (use lookahead to pre-initiate crossfades).
- No repeating the same preset category twice in succession.
- Section boundaries (structural analysis) are preferred transition points over timer-based switching.
- Track change detection fuses: Now Playing metadata, audio-level heuristics, elapsed time vs. pre-fetched duration.

### Pre-Fetch Philosophy
Pre-fetched metadata is a **"fast hint"** that accelerates the first ~15 seconds of a track. It is NOT a hard dependency. The self-computed MIR pipeline (Increment 2.4) computes BPM, key, spectral features, and mood from live audio — pre-fetch just gives the Orchestrator a head start before MIR has enough data to be confident.

**Fetcher priority:**
1. MusicBrainz (always active, free) — genre tags, duration
2. Soundcharts (optional, commercial) — BPM, key, energy, valence, danceability. Best external source for audio features. Gated behind `SOUNDCHARTS_APP_ID` / `SOUNDCHARTS_API_KEY` env vars.
3. Spotify (optional, needs credentials) — search-only track matching, duration. Audio features endpoint deprecated Nov 2024.
4. MusicKit (optional, needs entitlement) — artwork, genre, duration enrichment.

### Metadata Degradation
Phosphene works at every tier — never show errors or degraded UI when metadata is unavailable:
- Full metadata (Soundcharts + MusicBrainz + MusicKit + Now Playing) → best experience
- Now Playing + MusicBrainz only → good experience, genre tags available immediately
- Now Playing only → good experience, slower ramp-up
- No metadata at all → fully functional via self-computed MIR audio analysis alone

### Code Style
- Swift 6.0 with `SWIFT_STRICT_CONCURRENCY = complete`. `async`/`await` and actors. Avoid raw `DispatchQueue` except for Accelerate/vDSP.
- Shared data types: `Sendable`. Audio frame types: `@frozen`, SIMD-aligned.
- `CMSampleBuffer` is thread-safe but not marked `Sendable` in Swift 6. Use `nonisolated(unsafe)` or `@unchecked Sendable` box wrappers when transferring across isolation boundaries (e.g., from `SCStreamOutput` callback to `AsyncStream`).
- `NSLock` cannot be used in `async` contexts in Swift 6. Use `NSLock.withLock {}` from synchronous contexts only, or convert to an actor. For types that mix sync callbacks (e.g., `SCStreamOutput`) with async API, use `@unchecked Sendable` class with `NSLock.withLock` rather than actor.
- No C++ interop unless required for legacy preset parsing.
- SwiftLint enforced. Config at `.swiftlint.yml`. Key rules: `force_cast`, `force_try`, `force_unwrapping` → error; `file_length` warning at 400 lines; `cyclomatic_complexity` warning at 10.
- No `print()` in production code. Use `os.Logger` via `Shared/Logging.swift` — one logger per module (`Logger(subsystem: "com.phosphene", category: "<module>")`). Use `.debug` for per-frame data, `.info` for lifecycle events, `.error` for failures.
- All `public` API must have `///` doc comments. Every source file uses `// MARK: -` section dividers.
- Protocol-first design for testability. Every injectable dependency has a protocol (`AudioCapturing`, `AudioBuffering`, `FFTProcessing`, `Rendering`, `MetadataProviding`, `MetadataFetching`). Tests use doubles from `TestDoubles/`.

### Testing
- **213 tests** across unit, integration, regression, and performance categories.
- All tests must pass before starting new work (`swift test --package-path PhospheneEngine`).
- Test doubles in `Tests/TestDoubles/`: `MockAudioCapture`, `StubFFTProcessor`, `FakeStemSeparator`, `StubMoodClassifier`, `AudioFixtures`, `MockMetadataProvider`, `MockMetadataFetcher`.
- Regression tests use golden fixtures in `Tests/Regression/Fixtures/`.
- Performance tests use `XCTest.measure {}` with baselines.

---

## Failed Approaches — Do Not Repeat

These were tried in the Electron prototype and abandoned with documented reasons:

1. **IIR energy-difference beat detection (3-band)**: Machine-gun false positives. IIR filters smear onsets over many frames, making edge detection unreliable.
2. **Rising-edge accumulation**: IIR filters don't produce clean rise-then-flat patterns. Energy oscillates, defeating the accumulator.
3. **FFT-based spectral flux (1024-point, per-bin, dual-rate EMA thresholds)**: Threshold tuning was intractable. Too many parameters, different settings needed per genre. The current 6-band IIR flux approach is simpler and more robust.
4. **Beat-dominant visual design** (beat_zoom >> base_zoom): Onset pulses have ±80ms jitter, which the feedback loop amplifies. Visuals feel out of sync. Continuous energy values are perfectly synchronized because they ARE the audio. This lesson took multiple iterations to learn. Do not revisit it.
5. **BlackHole virtual audio driver**: Broken on macOS Sequoia. `DoIOOperation` timing guard zeros out the read buffer. Additionally, Chromium's Web Audio API can't read from virtual devices on macOS.
6. **Web Audio API AnalyserNode for frequency analysis**: Chromium's implementation is broken for virtual audio devices on macOS. IIR filters in application code give direct control.
7. **ScreenCaptureKit for audio-only capture** (macOS 26): `SCStream` with `capturesAudio = true` delivers video frames but zero audio callbacks, even with both `.screen` and `.audio` stream outputs registered and screen capture permission confirmed working. The root cause is unknown — may be a macOS 26 regression or a deliberate policy change. Core Audio taps (`AudioHardwareCreateProcessTap`, macOS 14.2+) work perfectly and are purpose-built for audio tapping.
8. **AcousticBrainz**: Shut down in 2022. The project was discontinued and the API is no longer available. MusicBrainz recording search (free, no auth) provides genre tags as an alternative.
9. **MPNowPlayingInfoCenter for reading other apps' metadata**: Only returns the host app's own published Now Playing info. Cannot read Spotify, Apple Music, etc.
11. **MediaRemote private framework for Now Playing** (macOS 15+): `MRMediaRemoteGetNowPlayingInfo` works from CLI tools but returns `kMRMediaRemoteFrameworkErrorDomain Code=3 "Operation not permitted"` from signed app bundles, even with screen capture permission granted. Use AppleScript via Automation framework instead — queries Apple Music and Spotify directly with a clean per-app permission prompt.
10. **Spotify Audio Features endpoint**: Deprecated for apps created after Nov 2024. Returns 403. Dropped entirely — Spotify is now search-only for track matching. Use Soundcharts (commercial) or self-computed MIR for audio features instead.
12. **HTDemucs direct CoreML conversion**: Both `torch.jit.trace` → `coremltools.convert()` and `torch.onnx.export()` → CoreML fail. HTDemucs uses STFT/iSTFT with complex tensors (`view_as_complex`) and dynamic shape calculations (`int` cast on tensor shapes) that coremltools 9.0 cannot convert. The same `int` op bug affects Open-Unmix's `Separator` wrapper. Solution: convert only the neural network core (mask estimation), handle STFT/iSTFT externally in Swift via Accelerate/vDSP.
13. **End-to-end audio-in/audio-out CoreML models for source separation**: CoreML has no complex number support. All audio separation models (HTDemucs, Open-Unmix, Demucs) use STFT/iSTFT internally, which requires complex arithmetic. The architecture must be split: STFT/iSTFT in Swift (Accelerate), neural network mask estimation in CoreML.
14. **Raw `MLMultiArray.dataPointer` with reported strides on ANE outputs**: ANE output buffers have padded strides (aligned to tile sizes) but `dataPointer` only maps the logical element count. Accessing padding indices causes SIGSEGV. Use `MLShapedArray.withUnsafeShapedBufferPointer` instead — it correctly handles padded layouts. This also applies to `withUnsafeBytes`.
15. **Chroma extraction using low-frequency FFT bins (< 500 Hz)**: At 48kHz/1024-point FFT, bin resolution is 46.875 Hz. Below ~500 Hz, bin centers don't align with musical pitches — e.g., 261.6 Hz (C4) maps to bin 6 (281.25 Hz) which rounds to C#, not C. 220 Hz (A3) maps to bin 5 (234.375 Hz) which rounds to A#, not A. Solution: skip bins below 65 Hz entirely, and rely on higher octaves (C5+, 523+ Hz) where bin-to-pitch mapping is accurate. The higher harmonics naturally carry the pitch information.
16. **Raw 12-bin chroma as mood classifier input**: A 914-param MLP (or even 3490-param) cannot learn the Krumhansl-Schmuckler key correlation function from raw chroma bins. Training loss plateaued at 0.23 (RMSE ~0.48) and valence output was near-zero for both major and minor key inputs. The correlation computation involves rotating the chroma vector through all 12 keys and comparing against 24 profiles — too complex for a tiny network to approximate. Solution: pre-compute major/minor key correlations as 2 scalar inputs (replacing 12 chroma bins), reducing the model input from 20 to 10 features. Training loss dropped to 0.02 (RMSE ~0.14).
17. **Autocorrelation tempo estimation returning half-tempo**: Basic autocorrelation of onset functions often returns half the true tempo (e.g., 60 BPM instead of 120 BPM) because the autocorrelation peak at lag=2×beat is often stronger than at lag=1×beat. This is a well-known "octave error". Accept it for now — the pre-fetched BPM from metadata APIs disambiguates. Future fix: onset spacing analysis or harmonic product spectrum.
18. **Median-based threshold for tempo onset timestamps**: Half-wave rectified spectral flux is zero for most frames (no energy increase = zero flux after rectification). The median of a buffer that's mostly zeros is near-zero, making `median * N` near-zero regardless of multiplier. Every positive flux passed, and the 300ms minimum spacing became the only gate — forcing IOIs at ~310ms intervals regardless of actual tempo (310ms → 194 BPM → octave-halved to 97). Fix: use 75th percentile instead of median, which is non-zero only when there's genuine activity, and reduce minimum spacing to 150ms so it doesn't alias real tempos.
19. **Unweighted chroma accumulation from FFT bins**: FFT bins are linearly spaced in frequency, but pitch classes are logarithmically spaced. At 48kHz/1024-point FFT, some pitch classes get up to 1.77x more bins than others (F=55 bins, G=31 bins). Without per-bin normalization (weight = 1/binsInPitchClass), pitch classes with more bins accumulate proportionally more energy, systematically biasing key estimation. Fix: precompute per-bin weights at init and multiply each bin's magnitude contribution.

---

## What NOT To Do

- Do not use `AVAudioEngine` input tap as the primary audio source. Core Audio taps are primary.
- Do not use ScreenCaptureKit for audio-only capture — it silently fails on macOS 15+/26. Use `AudioHardwareCreateProcessTap` instead.
- Do not block the render loop on network calls, CoreML inference, or metadata queries.
- Do not use `.storageModeManaged` buffers — they trigger implicit CPU-GPU copies that defeat UMA.
- Do not make beat onset the primary driver of visual motion. Continuous energy bands are primary. This is the single most important visual design constraint.
- Do not hardcode shader paths. All shaders are discovered via directory scan.
- Do not require audio files or pre-scanning for the Orchestrator. It works from live streaming audio.
- Do not assume Now Playing metadata is always available or accurate. Cross-reference with MIR.
- Do not normalize 6-band AGC per-band. Normalize against total energy to preserve relative differences.
- Do not use `MTLCaptureManager` in release builds.
- Do not use `CATapDescription(stereoMixdownOfProcesses: [])` with an empty array — it means "mix zero processes" = silence. Use `CATapDescription(stereoGlobalTapButExcludeProcesses: [])` for system-wide capture.
- Do not allocate or block in the Core Audio IO proc callback — it runs on a real-time audio thread.
- Do not assume Core Audio taps deliver audio without screen capture permission. `AudioHardwareCreateProcessTap` succeeds even without permission, but the tap silently delivers zeros. Call `CGPreflightScreenCaptureAccess()` / `CGRequestScreenCaptureAccess()` before starting capture, and prompt the user to grant permission in System Settings if denied.

---

## Key Types (Shared Module)

```swift
struct AudioFrame              // PCM samples, timestamp, sample rate
struct FFTResult               // Magnitude bins (512), phase bins, dominant frequency
struct BandEnergy              // 3-band (bass/mid/treble) + 6-band, instant + attenuated
struct StemData                // Four stems: vocals, drums, bass, other (each as AudioFrame)
struct SpectralFeatures        // centroid, flux, rolloff, MFCCs, chroma, ZCR
struct OnsetPulses             // beat_bass, beat_mid, beat_treble, composite (all 0–1 decaying)
struct EmotionalState           // valence: Float (-1…1), arousal: Float (-1…1), quadrant: EmotionalQuadrant
struct StructuralPrediction    // section start, predicted next boundary, confidence, section index
struct AnalyzedFrame           // Timestamped bundle of all above
struct TrackMetadata           // title, artist, album, genre, duration, artwork URL, source
struct PreFetchedTrackProfile  // External BPM, key, energy, valence, danceability, genre tags
struct PresetDescriptor        // id, family, tags, scene metadata, useFeedback (JSON sidecar fields)
struct FeedbackParams          // 32 bytes: decay, baseZoom, baseRot, beatZoom, beatRot, beatSensitivity, beatValue (GPU uniform)
struct Particle                // 64 bytes: position, velocity, color, life, size, seed, age (compute kernel state)
struct ParticleConfiguration   // particleCount, decayRate, burstThreshold, burstVelocity, drag (CPU-side tuning)
struct StructuralPrediction    // sectionIndex, sectionStartTime, predictedNextBoundary, confidence
struct VisualDirective         // Target family, color palette, camera speed, bloom, particles
```

## Linked Frameworks

Metal, MetalKit, CoreML, AVFoundation, Accelerate, ScreenCaptureKit, MusicKit

## Development Constraints

- **Team**: Matt (product/design direction) + Claude Code (implementation).
- **Platform**: macOS only. Mac mini is the primary development and deployment target.
- **Performance target**: 60fps at 1080p on Apple Silicon. Shaders, FFT, texture uploads, and ML inference must not cause frame drops.
- **Dependencies**: Minimize external dependencies. Prefer Apple frameworks. FFT via Accelerate/vDSP, not third-party libraries.
- **Learning stays local**: All future preference learning and adaptation is on-device only. No cloud, no telemetry, no data leaves the machine.
- **License**: MIT.

## Resolved Decisions

1. **Audio capture**: Core Audio taps (`AudioHardwareCreateProcessTap`, macOS 14.2+) via native Swift. No virtual audio driver. System-wide: `CATapDescription(stereoGlobalTapButExcludeProcesses: [])`. Per-app: `CATapDescription(stereoMixdownOfProcesses: [pid])`. Tap feeds an aggregate device (`AudioHardwareCreateAggregateDevice`) whose IO proc delivers interleaved float32 PCM on a real-time audio thread. ScreenCaptureKit was tried first but fails to deliver audio callbacks on macOS 15+/26 despite video frames arriving — abandoned in favor of Core Audio taps.
2. **Visual feedback**: Milkdrop-style previous-frame feedback with per-shader zoom, rotation, and decay. This is Phosphene's core visual identity.
3. **Audio data hierarchy**: Continuous energy = primary. Spectrum/waveform = richest. Beat = accent only. Non-negotiable.
4. **Beat detection**: 6-band spectral flux with adaptive median threshold and band-appropriate cooldowns. Four alternative approaches were tried and failed.
5. **Per-shader customization**: Each shader declares `beat_source` and all feedback params in JSON metadata.
6. **Spectrum/waveform as GPU data**: Sent as buffer/texture data, not reduced to scalar uniforms.
7. **Scene timing**: Per-shader duration in metadata. The Orchestrator can override based on structural analysis.
8. **Shader discovery**: Auto-scan directory. No manual registration.
9. **Sample rate**: 48kHz stereo float32 (matching Core Audio tap format).
11. **Shader compilation**: Runtime compilation from `.metal` source via `device.makeLibrary(source:options:)`. Shaders are SPM bundle resources (`.copy("Shaders")` in Package.swift), auto-discovered at startup.
12. **Full-screen rendering**: Single oversized triangle (3 vertices, no vertex buffer) generated in vertex shader from `vertex_id`. More efficient than a quad.
13. **Screen capture permission**: Required for Core Audio taps to deliver non-zero audio. Must call `CGRequestScreenCaptureAccess()` before starting capture. Tap creation succeeds without permission but delivers silence.
10. **Learning stays local**: On-device only. No cloud. No telemetry.
14. **Preset hot-reload**: `PresetLoader` watches external directories via `DispatchSource.FileSystemObject`. New `.metal` files are discovered and compiled without restart. Each preset has an independent pipeline state compiled with a shared preamble (FeatureVector struct, fullscreen_vertex, HSV utilities).
15. **Protocol-oriented testability**: All major subsystems have corresponding protocols (`AudioCapturing`, `AudioBuffering`, `FFTProcessing`, `Rendering`). Production code depends on protocols; test doubles inject via initializer.
16. **Structured logging**: `os.Logger` via `Shared/Logging.swift`. One subsystem (`com.phosphene`), one category per module. No `print()` in production code.
17. **SwiftLint enforcement**: `.swiftlint.yml` with `force_cast`/`force_try`/`force_unwrapping` as errors, `file_length` warning at 400, `cyclomatic_complexity` warning at 10. Tests and tools directories excluded from lint.
18. **Streaming metadata**: `StreamingMetadata` polls MediaRemote (private framework, dynamically loaded) every 2s for system-wide Now Playing state. `MetadataPreFetcher` queries external APIs in parallel (3s per-fetcher timeouts, LRU cache). Active fetchers: MusicBrainz (always, free), Soundcharts (optional, commercial), Spotify (optional, search-only). Pre-fetched data is a "fast hint" for the first ~15s — self-computed MIR (Increment 2.4) is the real source of truth.
19. **Essentia for offline validation**: Essentia (AGPL) is used in `tools/` Python scripts only — NOT in the app binary. Pre-computes ground-truth audio features for testing and validates self-computed MIR accuracy. Never link Essentia into PhospheneEngine or PhospheneApp.
20. **Stem separation model**: Open-Unmix HQ (umxhq). HTDemucs was first choice but fails CoreML conversion due to complex tensor ops and dynamic shapes. Open-Unmix's LSTM architecture converts cleanly. The CoreML model operates on STFT magnitude spectrograms (not raw audio) — STFT/iSTFT is handled in Swift via Accelerate/vDSP. Conversion: `tools/convert_stem_model.py`. Tests: `tools/test_stem_model.py` (6 assertions, all pass). Model: 68 MB `.mlpackage`, inference 0.17s for 10s audio on ANE.
21. **MLShapedArray for CoreML I/O**: ANE output buffers have padded strides with unmapped padding regions — raw `MLMultiArray.dataPointer` access crashes. `MLShapedArray.withUnsafeShapedBufferPointer` correctly traverses padded layouts. Used for both input packing and output unpacking in `StemSeparator`.
22. **GPU STFT/iSTFT (planned optimization)**: The current CPU-based STFT/iSTFT via Accelerate is the stem separation bottleneck (~6s for 10s of audio across 4 stems × 2 channels = 3448 FFT operations). The target architecture moves STFT/iSTFT to Metal compute shaders, eliminating CPU↔GPU copies and enabling the full separation pipeline (STFT → ANE predict → iSTFT → UMA buffers) to run without CPU-side data extraction. This would also enable real-time per-frame stem analysis rather than batch processing.
23. **MIR pipeline architecture**: DSP module takes `[Float]` magnitude arrays (not `UMABuffer`) — no Metal dependency. The caller extracts magnitudes from FFTProcessor's UMABuffer before passing to MIRPipeline. Chroma, key, and tempo are CPU-side properties on MIRPipeline (not in FeatureVector, which is limited to 24 floats for GPU upload). BandEnergyProcessor and BeatDetector independently compute 6-band bin ranges — simple duplication avoids coupling.
24. **Krumhansl-Schmuckler key estimation**: 24 key profiles (12 major + 12 minor rotations of Krumhansl 1990 profiles). Pearson correlation against normalized chroma vector. Minimum confidence threshold of 0.3 to avoid spurious key reports. Works well for clear tonal content; atonal or percussive-only material correctly returns nil.
25. **Mood classifier input features**: 10 pre-computed features, NOT raw 12-bin chroma. A tiny MLP cannot learn the Krumhansl-Schmuckler correlation function implicitly from 12 chroma bins — training converged to near-zero valence regardless of key mode. Pre-computing major/minor key correlations (which ChromaExtractor already calculates internally) reduces the problem to a trivially learnable function. The MLP provides smooth interpolation + efficient ANE execution over what could be pure heuristics.
26. **Spectral flux normalization for GPU**: Raw flux depends on magnitude scale and bin count. MIRPipeline normalizes via running-max AGC (tracks peak flux with 0.999 decay). Spectral centroid normalized by dividing by Nyquist (24000 Hz) to map to 0–1.
27. **Tempo onset threshold**: 75th percentile of bass flux buffer × 2.0, with 150ms minimum spacing. The median of half-wave rectified flux is near-zero (most frames have zero flux), so median-based thresholds fail. The 75th percentile is non-zero only during genuine energy changes. Previous 300ms minimum spacing aliased all tempos to ~97 BPM.
28. **Chroma bin-count normalization**: Each FFT bin's magnitude contribution to its pitch class is weighted by `1/binsInPitchClass`. At 48kHz/1024-point FFT, pitch classes get 31–55 bins (1.77x ratio). Without normalization, key estimation is systematically biased toward high-bin-count pitch classes (F, E, D#).
29. **Structural analysis architecture**: Three-class decomposition: `SelfSimilarityMatrix` (ring buffer + cosine similarity), `NoveltyDetector` (checkerboard kernel + peak-picking), `StructuralAnalyzer` (coordinator + prediction). Feature vector is 16 floats (12 chroma + centroid/flux/rolloff/energy). Novelty detection runs every 30 frames (~0.5s), amortized cost ~0.03ms/frame. `StructuralPrediction` is CPU-side only — not in FeatureVector (locked at 24 floats for GPU). Min peak distance 120 frames (2s) balances sensitivity vs false positives.
30. **Feedback texture architecture**: Double-buffered ping-pong MTLTextures allocated lazily from the drawable size (handles the case where `drawableSizeWillChange` never fires). Three-pass render loop for feedback presets: (1) `feedback_warp_fragment` reads previous texture, applies bass→gravity / mid→current / treble→crystallization transforms with a wandering center, writes to current texture; (2) composite pass draws the preset fragment shader (additive blend pipeline state compiled separately by PresetLoader for presets with `use_feedback: true`) onto current texture; (3) drawable blit pass copies feedback texture to screen and renders compute particles on top with standard alpha blending. `FeedbackParams` (32 bytes, 8 floats) carries per-preset decay/zoom/rot values and live beat value to the shaders each frame. Non-feedback presets skip all three passes and render directly to the drawable (single-pass, zero regression from pre-feedback behavior).
31. **Particle rendering strategy for the Murmuration preset**: Compute particles render with standard `.sourceAlpha`/`.oneMinusSourceAlpha` blending (dark silhouettes over sky), NOT additive blending, NOT into the feedback texture. The sky gradient is rendered directly to the drawable each frame (standard preset pipeline, no feedback). This keeps the sky vivid instead of being washed out by feedback accumulation. The feedback texture path remains available but is currently unused by Murmuration — kept as infrastructure for future presets that need trails.
32. **Audio routing philosophy (learned from Murmuration tuning)**: Responding to `features.bass`/`features.mid`/`features.treble` means responding primarily to whatever instrument dominates the mix — which is often vocals in singer-songwriter tracks. To make a preset respond to specific musical content, use the 6-band energy values (`sub_bass`, `low_bass`, `low_mid`, `mid_high`, `high_mid`, `high_freq`) to deliberately target or avoid frequency ranges. Vocals live in `low_mid` (250-1kHz) and `mid_high` (1-4kHz); skipping those bands routes visual response to rhythm section and overtones instead. This is a simpler alternative to running per-stem analysis until the Orchestrator increment wires stem-specific routing.
33. **Creative design principle — marriage of art and technology**: Every preset should be rooted in a natural metaphor that the technology uniquely enables. Murmuration requires GPU compute (thousands of particles with custom physics) to exist — it couldn't be faked with Milkdrop's 1024 shape instances. The creative vision (a flock of starlings moving as one organism) and the technology (compute shaders with per-particle state) reinforce each other. Different audio features should control fundamentally different things: the waveform is a drawn shape, bass is gravity, mid is current, treble is crystallization, beats are phase transitions. Amplitude→magnitude mapping alone produces boring visuals regardless of tuning.

## Reference Documents

The full development plan with phased increments is in `docs/DEVELOPMENT_PLAN.md`. Consult the relevant increment when starting a task — do not load the entire plan into context.

The architectural blueprint is in `docs/ARCHITECTURAL_BLUEPRINT.md`.

## Current Status

**Phase 3 in progress, under revised plan.** Phase 2 complete. Phase 3 was restructured after the original Increment 3.1 was discovered to have bundled three distinct units of work and left its "from stem-separated audio" goal unmet. See `docs/DEVELOPMENT_PLAN.md` for the full revised plan. The retroactive split and the new ordering are summarized below.

**Retroactive Phase 3 state:**
- **Increment 3.1 (Compute Shader Particle Pipeline)** ✅ — `ProceduralGeometry.swift`, `Particles.metal`, `MetalContext.makeSharedTexture`, 7 particle tests. Legitimate particle infrastructure deliverable.
- **Increment 3.1-bonus (Feedback Texture Infrastructure)** ✅ — `FeedbackParams` struct, `feedback_warp_fragment`/`feedback_blit_fragment` in `Common.metal`, three-pass feedback render path in `RenderPipeline` (`drawWithFeedback` with `drawParticleMode`/`drawSurfaceMode` split), `useFeedback` + `useParticles` flags on `PresetDescriptor`, dual pipeline state compilation in `PresetLoader`, `abstract` category, Membrane preset (second feedback user). **Scope violation:** this should have been its own increment; documented retroactively so the pattern isn't repeated.
- **Increment 3.1-preset (Murmuration)** ✅ — `Starburst.metal` + `Starburst.json`, flock compute kernel modifications in `Particles.metal`, audio routing. Ships with a documented full-mix workaround (`sub_bass + low_bass` / `high_mid + high_freq`) because the live stem pipeline was never wired. True stem routing for Murmuration is deferred to a Phase 3.5 preset-polish task that follows Increment 3.1b.

**Ordered next increments** (per the revised plan):
1. **Increment 3.1a — GPU STFT/iSTFT Compute Pipeline** (promoted from Increment 7.1). Replace `StemSeparator`'s Accelerate CPU STFT/iSTFT with a Metal compute path, dropping per-separation time from ~6.5s to ≤250ms. Prerequisite for all real-time stem work.
2. **Increment 3.1b — Live Stem Pipeline Wiring + Per-Stem `FeatureVector` Extension.** Wire `StemSeparator.separate()` into `VisualizerEngine` on a rolling 10s/5s-cadence background queue, run per-stem `BandEnergyProcessor` + `BeatDetector`, expose results to shaders via a new `StemFeatures` struct bound at GPU `buffer(3)`. Enables Murmuration's stem-routing re-do and all downstream stem-driven presets.
3. **Increment 3.2 — Mesh Shader Pipeline Infrastructure** (now infrastructure-only, no preset). `MeshShaders.metal` shared utilities, `MeshGenerator.swift` with mesh path + vertex fallback, new `drawWithMeshShader` render path, `useMeshShader` flag, 6 `MeshGeneratorTests`.
4. **Increment 3.2b — Fractal Tree Demonstration Preset.** First preset using the mesh shader pipeline. Recursive 3D branching structure responding to audio.
5. **Increment 3.3 — Hardware Ray Tracing Infrastructure.** `BVHBuilder`, `RayIntersector`, `RayTracing.metal`, 9 tests. (The original 3.3 spec had `PostProcess.metal` in it; that file was extracted to Increment 3.4.)
6. **Increment 3.4 — HDR Post-Process Chain** (extracted from 3.3). `PostProcessChain.swift`, `PostProcess.metal` (bright pass, blur H/V, ACES composite), `usePostProcess` flag, 6 tests. Independent of ray tracing.
7. **Increment 3.5 — Indirect Command Buffers** (was 3.4).
8. **Increment 3.6 (deferred) — Render Graph Refactor.** Fires when capability flag count exceeds 4.
9. **Phase 3.5 — Native Preset Library Expansion.** Dedicated home for native presets that depend on Phase 3 infrastructure. First entry: **3.5.1 Photorealistic Popcorn**, depends on 3.1b + 3.3 + 3.4.

**Increment Scope Discipline rule**: per the revised `DEVELOPMENT_PLAN.md` Code Hygiene Rules, one increment is one reviewable unit of work. Infrastructure increments and preset increments are never bundled in the same increment. Scope creep is recorded retroactively as a new increment, not silently absorbed.

Increment 2.6 added the analysis lookahead buffer — a configurable delay between analysis and rendering for anticipatory visual decisions. `AnalyzedFrame` is a timestamped container bundling all per-frame analysis results (AudioFrame + FFTResult + StemData + FeatureVector + EmotionalState). `LookaheadBuffer` is a thread-safe ring buffer (default 512 frames, 2.5s delay) with dual read heads: the analysis head returns the latest frame (real-time) and the render head returns the frame delayed by the configured amount. `AudioInputRouter` gained `onAnalysisFrame` and `onRenderFrame` dual callbacks for the Orchestrator. 187 Swift tests pass (173 existing + 14 new: 10 LookaheadBuffer unit tests, 3 AnalyzedFrame unit tests, 1 integration test verifying delay accuracy within ±100ms).

Increment 2.7 added progressive structural analysis — real-time section boundary detection and next-boundary prediction. `SelfSimilarityMatrix` stores 600 frames of 16-float feature vectors (12 chroma + 4 spectral) in a ring buffer with vDSP cosine similarity. `NoveltyDetector` convolves a checkerboard kernel along the similarity diagonal and peak-picks with adaptive threshold (mean + 1.5×stddev, min 2s between peaks). `StructuralAnalyzer` coordinates both, running novelty detection every 30 frames (~0.5s amortized). After 2+ boundaries, predicts next via average section duration; repetition detection (section-average cosine similarity) boosts confidence for ABAB patterns. `StructuralPrediction` is CPU-side only, added to `AnalyzedFrame`. MIRPipeline gained StructuralAnalyzer as its 5th sub-analyzer. 206 Swift tests pass (187 existing + 19 new: 5 SelfSimilarityMatrix, 5 NoveltyDetector, 8 StructuralAnalyzer, 1 AABA regression).

BPM and key estimation bugs fixed at end of increment 2.5: tempo onset threshold changed from median (near-zero for half-wave rectified flux) to 75th percentile; chroma accumulation now weights bins by inverse pitch-class count to compensate for non-uniform FFT-to-pitch mapping. Known remaining issues: BPM histogram peaks are thin (peak counts of 2-3) making tempo estimates fragile; tempo takes ~35s to converge; accuracy vs ground truth not yet validated across genres.
