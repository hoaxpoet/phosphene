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

Deployment target: macOS 14.0+ (Sonoma). Swift 6.0. Metal 3.1+.

**Current test count: 94 tests** (unit, integration, regression, performance). All must pass before any new code is merged.

## Module Map

```
PhospheneApp/               → SwiftUI shell, views, view models
  ContentView.swift         → Main view + VisualizerEngine (audio→FFT→render pipeline owner)
  PhospheneApp.swift        → App entry point
  Views/MetalView.swift     → NSViewRepresentable wrapping MTKView

PhospheneEngine/
  Audio/                    → Core Audio tap capture, ring buffers, FFT
    SystemAudioCapture      → Core Audio tap wrapper: system-wide or per-app (✓ implemented)
    AudioInputRouter        → Unified source abstraction: system/app/file → callbacks (✓ implemented)
    AudioBuffer             → IO proc → UMARingBuffer<Float> bridge for GPU (✓ implemented)
    FFTProcessor            → vDSP 1024-pt FFT → 512 magnitude bins in UMABuffer (✓ implemented)
    Protocols               → AudioCapturing, AudioBuffering, FFTProcessing (✓ implemented)
  DSP/                      → Spectral analysis, beat/onset detection, chroma, MFCCs (stub)
  ML/                       → CoreML wrappers: stem separator, mood classifier (stub)
  Renderer/                 → Metal context, pipelines, shader library
    MetalContext            → MTLDevice, command queue, triple-buffered semaphore (✓ implemented)
    ShaderLibrary           → Auto-discover .metal files, runtime compilation, cache (✓ implemented)
    RenderPipeline          → Full-screen shader pass, audio UMA buffer binding (✓ implemented)
    Protocols               → Rendering protocol for DI/testing (✓ implemented)
    Shaders/Waveform.metal  → 64-bar FFT spectrum + oscilloscope waveform (✓ implemented)
  Presets/                  → Preset loading, categorization, hot-reload
    PresetLoader            → Auto-discover .metal presets, compile, hot-reload via FSEvents (✓ implemented)
    PresetDescriptor        → JSON sidecar metadata (feedback params, beat source) (✓ implemented)
    PresetCategory          → Visual aesthetic families (10 categories) (✓ implemented)
  Orchestrator/             → AI VJ: anticipation engine, transitions, preset selection (stub)
  Shared/                   → UMA buffer wrappers, type definitions, logging
    UMABuffer               → Generic .storageModeShared MTLBuffer + UMARingBuffer (✓ implemented)
    AudioFeatures           → @frozen SIMD-aligned structs: AudioFrame, FFTResult, etc. (✓ implemented)
    Logging                 → Per-module os.Logger instances (✓ implemented)

Tests/ (94 tests)
  Audio/                    → AudioBufferTests, FFTProcessorTests
  Renderer/                 → MetalContextTests, ShaderLibraryTests, RenderPipelineTests
  Shared/                   → AudioFeaturesTests, UMABufferExtendedTests
  Integration/              → AudioToFFTPipelineTests, AudioToRenderPipelineTests
  Regression/               → FFTRegressionTests + golden fixtures (440hz_sine, 440hz_fft)
  Performance/              → FFTPerformanceTests, RenderLoopPerformanceTests
  TestDoubles/              → MockAudioCapture, StubFFTProcessor, AudioFixtures
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
- Stem separator outputs: Vocals, Drums, Bass, Other — each independently routed to shaders.
- Mood classifier outputs continuous valence (-1…1) and arousal (-1…1), smoothed with EMA.

### Orchestrator
- Four states: `idle` → `listening` → `ramping` → `full`.
- Visual transitions LAND on musical transitions (use lookahead to pre-initiate crossfades).
- No repeating the same preset category twice in succession.
- Section boundaries (structural analysis) are preferred transition points over timer-based switching.
- Track change detection fuses: Now Playing metadata, audio-level heuristics, elapsed time vs. pre-fetched duration.

### Metadata Degradation
Phosphene works at every tier — never show errors or degraded UI when metadata is unavailable:
- Full metadata (MusicKit + Spotify API + Now Playing) → best experience
- Now Playing only → good experience, slower ramp-up
- No metadata at all → fully functional via audio analysis alone

### Code Style
- Swift 6.0 with `SWIFT_STRICT_CONCURRENCY = complete`. `async`/`await` and actors. Avoid raw `DispatchQueue` except for Accelerate/vDSP.
- Shared data types: `Sendable`. Audio frame types: `@frozen`, SIMD-aligned.
- `CMSampleBuffer` is thread-safe but not marked `Sendable` in Swift 6. Use `nonisolated(unsafe)` or `@unchecked Sendable` box wrappers when transferring across isolation boundaries (e.g., from `SCStreamOutput` callback to `AsyncStream`).
- `NSLock` cannot be used in `async` contexts in Swift 6. Use `NSLock.withLock {}` from synchronous contexts only, or convert to an actor. For types that mix sync callbacks (e.g., `SCStreamOutput`) with async API, use `@unchecked Sendable` class with `NSLock.withLock` rather than actor.
- No C++ interop unless required for legacy preset parsing.
- SwiftLint enforced. Config at `.swiftlint.yml`. Key rules: `force_cast`, `force_try`, `force_unwrapping` → error; `file_length` warning at 400 lines; `cyclomatic_complexity` warning at 10.
- No `print()` in production code. Use `os.Logger` via `Shared/Logging.swift` — one logger per module (`Logger(subsystem: "com.phosphene", category: "<module>")`). Use `.debug` for per-frame data, `.info` for lifecycle events, `.error` for failures.
- All `public` API must have `///` doc comments. Every source file uses `// MARK: -` section dividers.
- Protocol-first design for testability. Every injectable dependency has a protocol (`AudioCapturing`, `AudioBuffering`, `FFTProcessing`, `Rendering`). Tests use doubles from `TestDoubles/`.

### Testing
- **94 tests** across unit, integration, regression, and performance categories.
- All tests must pass before starting new work (`swift test --package-path PhospheneEngine`).
- Test doubles in `Tests/TestDoubles/`: `MockAudioCapture`, `StubFFTProcessor`, `AudioFixtures`.
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
struct EmotionVector           // valence: Float (-1…1), arousal: Float (-1…1)
struct StructuralPrediction    // section start, predicted next boundary, confidence, section index
struct AnalyzedFrame           // Timestamped bundle of all above
struct TrackMetadata           // title, artist, album, genre, duration, artwork URL, source
struct PreFetchedTrackProfile  // External BPM, key, energy, valence, danceability, genre tags
struct PresetDescriptor        // id, family, tags, scene metadata (all JSON sidecar fields)
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

## Reference Documents

The full development plan with phased increments is in `docs/DEVELOPMENT_PLAN.md`. Consult the relevant increment when starting a task — do not load the entire plan into context.

The architectural blueprint is in `docs/ARCHITECTURAL_BLUEPRINT.md`.

## Current Status

**Phase 1 complete.** Increments 1.1–1.5 and R.1 (quality retrofit) are done. The audio-to-GPU-to-pixel pipeline works end to end: Core Audio taps → AudioBuffer → FFTProcessor → Metal shader rendering. Preset hot-reload works. 94 tests pass. SwiftLint clean. Next up: Phase 2 (streaming metadata, stem separation, MIR features, mood classification).
