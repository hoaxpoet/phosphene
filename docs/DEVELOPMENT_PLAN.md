# Phosphene — Development Plan for Claude Code Implementation (v2)

## Revision Notes (v2)

This revision addresses insufficient test coverage and code hygiene observed during Phase 1 development. Key changes from v1:

- **New Quality Standards section** — project-wide testing policy, linting rules, and CI expectations
- **New Increment 0.2** — test infrastructure, CI pipeline, and code quality tooling setup
- **Explicit Test Requirements on every increment** — each increment now specifies exactly which unit tests, integration tests, and assertions must be written alongside the production code
- **Code Hygiene Checklist** added to Claude Code Session Guidelines — every session must pass before the increment is considered complete
- **Stronger Verification criteria** — "it looks right" replaced with measurable, automatable assertions
- **Testing-related technical constraints** added (protocol-oriented design for testability, dependency injection, no singletons)
- **Regression test suite gate** — all existing tests must pass before any new code is merged

All other architectural decisions, module structure, and phasing from v1 are preserved.

---

## Project Overview

**Phosphene** is a next-generation, AI-driven music visualization engine built exclusively for Apple Silicon (M3/M4). It succeeds ProjectM/Milkdrop by combining Metal rendering, real-time ML-powered audio stem separation on the Apple Neural Engine, Music Information Retrieval (MIR), and an AI Orchestrator that autonomously curates visual playlists matched to the emotional arc of the music.

**Primary audio source:** System audio capture via Core Audio taps (`AudioHardwareCreateProcessTap`, macOS 14.2+). Phosphene visualizes whatever the user is streaming — Apple Music, Spotify, Tidal, YouTube Music, or any other audio source — by tapping the system audio output directly. It enriches the experience with track metadata from MusicKit and the macOS Now Playing API. Local file playback is supported as a fallback but is not the primary workflow. ScreenCaptureKit was originally planned but abandoned because it silently fails to deliver audio callbacks on macOS 15+/26.

**Streaming Anticipation Architecture:** Because streaming audio arrives without a pre-scannable file, Phosphene employs three complementary systems to recover the anticipatory capability that pre-scanning would otherwise provide:

1. **Analysis Lookahead Buffer** — A configurable 2–3 second delay between audio analysis and visual rendering. The audio pipeline processes frames ahead of what the renderer displays, giving the Orchestrator a genuine lookahead window to prepare for upcoming musical moments (drops, builds, transitions). This latency is imperceptible in a visualizer context where viewers do not expect sample-accurate video sync.
2. **Metadata Pre-Fetching** — When Now Playing reports a new track, Phosphene queries external music databases (MusicBrainz, Soundcharts) for pre-analyzed audio features: BPM, key, energy, danceability, genre, and duration. This is a **"fast hint"** that accelerates the first ~15 seconds — the self-computed MIR pipeline (Increment 2.4) is the real source of truth. Pre-fetch data is optional at every level; the system is resilient to any external API being unavailable.
3. **Progressive Structural Analysis** — After hearing 15–20 seconds of a track, a self-similarity analysis identifies section boundaries (intro, verse, chorus, bridge) and predicts when future transitions will occur based on the repetitive structure inherent in virtually all popular music. After the first chorus, the system can predict when the second chorus will arrive.

Combined, these three systems give the Orchestrator roughly the same decision-making information as a pre-scanned local file after a brief ramp-up period at the start of each track.

This plan decomposes the architectural blueprint into **Claude Code-safe increments** — discrete tasks that can each be completed within a single context window without risk of truncation or loss of coherence.

---

## Quality Standards

This section defines project-wide testing, code hygiene, and CI requirements. **Every increment must satisfy these standards before it is considered complete.** Claude Code sessions should treat these as hard constraints, not aspirational goals.

### Testing Policy

**Minimum coverage target: 80% line coverage** on all non-UI, non-Metal-shader Swift code in `PhospheneEngine`. UI code (`PhospheneApp/Views/`) and `.metal` shader files are exempt from automated coverage but require manual verification steps documented in each increment.

**Test categories and when to use each:**

| Category | Location | What It Covers | When Required |
|----------|----------|----------------|---------------|
| **Unit tests** | `Tests/PhospheneEngineTests/` | Single type in isolation. All dependencies mocked/stubbed via protocols. | Every increment that adds or modifies a Swift type. |
| **Integration tests** | `Tests/PhospheneEngineTests/Integration/` | Two or more real modules wired together (e.g., AudioBuffer → FFTProcessor pipeline). | Every increment that connects modules or adds a new pipeline stage. |
| **Snapshot / regression tests** | `Tests/PhospheneEngineTests/Regression/` | Golden-value comparisons: known input → expected output, saved to disk. Catches silent numerical drift. | Every DSP, MIR, or ML increment. |
| **Performance tests** | `Tests/PhospheneEngineTests/Performance/` | `XCTest.measure {}` blocks with baselines. Catches regressions in hot paths. | Every renderer, audio, or DSP increment. |
| **Manual verification** | Documented in increment's Verification section | Visual output, live audio behavior, UI interaction. | Every increment. |

**Test naming convention:** `test_<MethodOrBehavior>_<Scenario>_<ExpectedResult>()`
- Example: `test_write_fullRingOverwrite_oldestSamplesOverwritten()`
- Example: `test_fftProcess_440HzSine_peakAtBin9()`

**Test file naming convention:** One test file per source file, mirroring the module structure.
- `Audio/AudioBuffer.swift` → `Tests/PhospheneEngineTests/Audio/AudioBufferTests.swift`
- `DSP/BeatDetector.swift` → `Tests/PhospheneEngineTests/DSP/BeatDetectorTests.swift`
- Integration tests: `Tests/PhospheneEngineTests/Integration/AudioToFFTPipelineTests.swift`

### Testability Requirements (Dependency Injection)

**No singletons.** Every dependency is injected via initializer parameters. Types depend on protocols, not concrete classes.

**Protocol-first design.** Before implementing a concrete type, define the protocol it conforms to. This enables test doubles (mocks, stubs, fakes) without conditional compilation or swizzling.

Required protocols (define incrementally as each module is built):

| Protocol | Concrete Implementation | Purpose |
|----------|------------------------|---------|
| `AudioCapturing` | `SystemAudioCapture` | Mockable audio source for tests that don't need real hardware |
| `AudioBuffering` | `AudioBuffer` | Allows injection of pre-filled buffers in downstream tests |
| `FFTProcessing` | `FFTProcessor` | Stub with known FFT output for renderer/DSP tests |
| `StemSeparating` | `StemSeparator` | Fake that returns canned stem data without CoreML |
| `MoodClassifying` | `MoodClassifier` | Stub returning fixed valence/arousal for orchestrator tests |
| `MetadataProviding` | `StreamingMetadata` | Fake metadata source for testing track change logic |
| `PresetLoading` | `PresetLoader` | Stub preset catalog for orchestrator tests |
| `Rendering` | `RenderPipeline` | Headless/no-op renderer for non-visual tests |

**Test doubles directory:** `Tests/PhospheneEngineTests/TestDoubles/` — shared mocks, stubs, and fixture data.

### Code Hygiene Rules

These rules apply to every line of code written in every increment:

1. **SwiftLint clean.** Zero warnings, zero errors. The `.swiftlint.yml` is the source of truth. No `// swiftlint:disable` without a comment explaining why.
2. **No force-unwraps (`!`) outside of tests.** Production code uses `guard let`, `if let`, or `precondition` with a message. Tests may use `XCTUnwrap` or force-unwrap for brevity.
3. **No `print()` in production code.** Use `os.Logger` with appropriate log levels (`.debug`, `.info`, `.error`, `.fault`). Define one `Logger` per module with a subsystem of `"com.phosphene.<module>"`.
4. **All public API has doc comments.** Every `public` type, method, and property gets a `///` doc comment explaining what it does, not how. Include `- Parameter`, `- Returns`, and `- Throws` annotations where applicable.
5. **No magic numbers.** Named constants or enums. `let fftSize = 1024` not bare `1024` in a function call.
6. **MARK annotations.** Every source file uses `// MARK: -` to delineate sections: Properties, Initialization, Public API, Private Helpers, Protocol Conformance.
7. **File length limit: 400 lines.** If a file exceeds 400 lines, split it. Extract a helper type, an extension, or a sub-module.
8. **Cyclomatic complexity limit: 10 per function.** SwiftLint enforces this. Complex logic gets decomposed into helper functions.
9. **No commented-out code.** Delete it. Git has history.
10. **Every `TODO` has a tracking increment.** Format: `// TODO: [Increment 3.2] Add mesh shader LOD support`

### CI Pipeline (Enforced via Claude Code Hooks)

Every Claude Code session that modifies Swift code must end with:

```bash
# 1. Lint
swiftlint lint --strict --config .swiftlint.yml

# 2. Build (warnings-as-errors)
xcodebuild -scheme PhospheneApp -destination 'platform=macOS' \
  build SWIFT_TREAT_WARNINGS_AS_ERRORS=YES 2>&1

# 3. Test (all tests, not just new ones)
swift test --package-path PhospheneEngine 2>&1

# 4. Coverage check (after Phase 1 is complete)
# xcrun llvm-cov report ... (threshold: 80%)
```

**All four steps must pass.** If any step fails, the increment is not complete. Claude Code should fix the failure before moving on.

### Regression Gate

**All existing tests must pass before writing new code.** At the start of every Claude Code session, run `swift test` first. If anything is red, fix it before starting the increment's work. This prevents test rot and cascading failures.

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
│   │   ├── StreamingMetadata.swift    # MediaRemote Now Playing polling, track change detection
│   │   ├── MetadataPreFetcher.swift   # Parallel async queries, LRU cache, merge
│   │   ├── MusicBrainzFetcher.swift   # Free API: genre tags, duration
│   │   ├── SpotifyFetcher.swift       # Search-only track matching (audio features deprecated)
│   │   ├── SoundchartsFetcher.swift   # Optional commercial API: BPM, key, energy, valence
│   │   └── MusicKitBridge.swift       # Optional MusicKit catalog enrichment
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
    └── PhospheneEngineTests/
        ├── Audio/                     # Unit tests mirroring source structure
        │   ├── AudioBufferTests.swift
        │   ├── FFTProcessorTests.swift
        │   ├── SystemAudioCaptureTests.swift
        │   ├── AudioInputRouterTests.swift
        │   ├── LookaheadBufferTests.swift
        │   ├── StreamingMetadataTests.swift
        │   └── MetadataPreFetcherTests.swift
        ├── DSP/
        │   ├── SpectralAnalyzerTests.swift
        │   ├── BeatDetectorTests.swift
        │   ├── ChromaExtractorTests.swift
        │   ├── StructuralAnalyzerTests.swift
        │   └── FeatureVectorTests.swift
        ├── ML/
        │   ├── StemSeparatorTests.swift
        │   └── MoodClassifierTests.swift
        ├── Renderer/
        │   ├── MetalContextTests.swift
        │   ├── ShaderLibraryTests.swift
        │   └── RenderPipelineTests.swift
        ├── Presets/
        │   ├── PresetLoaderTests.swift
        │   ├── PresetCategoryTests.swift
        │   └── LegacyTranspilerTests.swift
        ├── Orchestrator/
        │   ├── OrchestratorTests.swift
        │   ├── EmotionMapperTests.swift
        │   ├── TransitionEngineTests.swift
        │   ├── TrackChangeDetectorTests.swift
        │   └── AnticipationEngineTests.swift
        ├── Shared/
        │   ├── UMABufferTests.swift
        │   └── AudioFeaturesTests.swift
        ├── Integration/               # Multi-module integration tests
        │   ├── AudioToFFTPipelineTests.swift
        │   ├── AudioToStemPipelineTests.swift
        │   ├── MIRPipelineTests.swift
        │   ├── MetadataToOrchestratorTests.swift
        │   └── FullPipelineTests.swift
        ├── Regression/                # Golden-value snapshot tests
        │   ├── FFTRegressionTests.swift
        │   ├── ChromaRegressionTests.swift
        │   ├── BeatDetectorRegressionTests.swift
        │   └── Fixtures/              # Known-good input/output pairs
        │       ├── 440hz_sine_1s.pcm
        │       ├── 440hz_fft_expected.json
        │       ├── cmajor_chord_chroma_expected.json
        │       └── 120bpm_kick_onsets_expected.json
        ├── Performance/               # XCTest.measure benchmarks
        │   ├── FFTPerformanceTests.swift
        │   ├── AudioBufferPerformanceTests.swift
        │   └── RenderLoopPerformanceTests.swift
        └── TestDoubles/               # Shared mocks, stubs, fakes
            ├── MockAudioCapture.swift
            ├── StubFFTProcessor.swift
            ├── FakeStemSeparator.swift
            ├── StubMoodClassifier.swift
            ├── MockMetadataProvider.swift
            ├── StubPresetLoader.swift
            └── AudioFixtures.swift    # Helper to generate sine waves, noise, silence
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
- Create a `README.md` stub

**Verification:** Project builds and launches an empty window. All frameworks link without error.

**Estimated scope:** ~200 lines of config + stubs. Well within context.

### Increment 0.2: Test Infrastructure & Code Quality Tooling

**Goal:** Set up the testing foundation, CI hooks, linting, logging, and shared test utilities so that every subsequent increment can write tests from day one without friction.

**Claude Code instructions:**

**SwiftLint configuration** — create `.swiftlint.yml`:
```yaml
# .swiftlint.yml
included:
  - PhospheneEngine/Sources
  - PhospheneApp
excluded:
  - PhospheneEngine/.build
opt_in_rules:
  - force_unwrapping           # No ! in production code
  - implicitly_unwrapped_optional
  - discouraged_optional_boolean
  - empty_count
  - closure_spacing
  - operator_usage_whitespace
  - redundant_nil_coalescing
  - sorted_imports
  - vertical_whitespace_closing_braces
  - unowned_variable_capture
disabled_rules:
  - todo                        # We use TODO with increment tracking
force_cast: error
force_try: error
force_unwrapping: error
line_length:
  warning: 120
  error: 150
file_length:
  warning: 400
  error: 500
cyclomatic_complexity:
  warning: 10
  error: 15
function_body_length:
  warning: 50
  error: 80
type_body_length:
  warning: 300
  error: 400
identifier_name:
  min_length: 2
  max_length: 60
```

**Logging infrastructure** — create `Shared/Logging.swift`:
- Define `os.Logger` instances per module: `Logger.audio`, `Logger.dsp`, `Logger.renderer`, `Logger.orchestrator`, `Logger.ml`
- Subsystem: `"com.phosphene"`, categories matching module names
- Wrapper that makes log level consistent across the project

**Test fixtures helper** — create `Tests/PhospheneEngineTests/TestDoubles/AudioFixtures.swift`:
- `AudioFixtures.sineWave(frequency: Float, sampleRate: Float, duration: Float) -> [Float]` — generates a pure sine tone
- `AudioFixtures.silence(sampleCount: Int) -> [Float]` — all zeros
- `AudioFixtures.whiteNoise(sampleCount: Int) -> [Float]` — deterministic PRNG-seeded noise (same seed = same output for reproducibility)
- `AudioFixtures.impulse(sampleCount: Int, position: Int) -> [Float]` — single spike, useful for testing transient detection
- `AudioFixtures.mixStereo(left: [Float], right: [Float]) -> [Float]` — interleave two mono signals

**Test helper protocols** — create `Tests/PhospheneEngineTests/TestDoubles/MockAudioCapture.swift` (and other stubs listed in Architecture Overview):
- `MockAudioCapture: AudioCapturing` — calls its callback with canned PCM data on demand, no hardware needed
- `StubFFTProcessor: FFTProcessing` — returns pre-configured magnitude array
- `AudioFixtures` doubles as the data source for all test doubles

**CI hook script** — create `tools/ci-check.sh`:
```bash
#!/bin/bash
set -euo pipefail
echo "=== SwiftLint ==="
swiftlint lint --strict --config .swiftlint.yml
echo "=== Build ==="
xcodebuild -scheme PhospheneApp -destination 'platform=macOS' \
  build SWIFT_TREAT_WARNINGS_AS_ERRORS=YES 2>&1
echo "=== Tests ==="
swift test --package-path PhospheneEngine 2>&1
echo "=== All checks passed ==="
```

**Verification:**
- `swiftlint lint` runs clean on all placeholder files
- `swift test` runs (0 tests, 0 failures — no tests yet, but the harness works)
- `./tools/ci-check.sh` exits 0
- `AudioFixtures.sineWave(frequency: 440, sampleRate: 48000, duration: 0.1)` returns 4800 samples; first sample ≈ 0.0, sample at index 27 ≈ 1.0 (quarter wavelength of 440Hz at 48kHz)

**Test requirements for this increment:**
- `AudioFixturesTests.swift` — 5 tests: sine wave amplitude range [-1,1], silence is all zeros, white noise has nonzero RMS, impulse has exactly one nonzero sample, stereo interleave length is 2× mono

---

## Phase 1 — Core Foundation & Metal Rendering (Blueprint Release 0.1)

### Increment 1.1: Metal Context & Render Loop ✅

**Goal:** Initialize a Metal device, command queue, and CAMetalLayer-backed rendering loop in a SwiftUI view via `MTKView` / `NSViewRepresentable`.

**Files to create/edit:**
- `Renderer/MetalContext.swift` — `MTLDevice`, `MTLCommandQueue`, pixel format selection, triple-buffered semaphore
- `Renderer/RenderPipeline.swift` — Basic render pass descriptor, clear color, drawable presentation
- `PhospheneApp/Views/MetalView.swift` — `NSViewRepresentable` wrapping `MTKView` with delegate
- `PhospheneApp/Views/ContentView.swift` — Host the MetalView

**Test requirements:**
- `MetalContextTests.swift` — 4 tests:
  - `test_init_createsDevice_deviceIsNotNil()` — MTLDevice initializes on Apple Silicon
  - `test_init_createsCommandQueue_queueIsNotNil()`
  - `test_pixelFormat_defaultsBGRA8Unorm()`
  - `test_semaphore_tripleBuffered_maxConcurrentFramesIs3()`
- `RenderPipelineTests.swift` — 3 tests:
  - `test_init_withValidDevice_createsPipelineState()`
  - `test_renderPassDescriptor_hasClearColor()`
  - `test_draw_withNilDrawable_doesNotCrash()` — resilience test

**Verification:** Window displays a solid color that changes per-frame (proves render loop is active at 60/120 fps). All 7 unit tests pass.

### Increment 1.2: UMA Shared Buffer Infrastructure ✅

**Goal:** Build the zero-copy UMA buffer abstraction that allows CPU, GPU, and ANE to share memory.

**Files to create/edit:**
- `Shared/UMABuffer.swift` — Generic wrapper around `MTLBuffer` with `.storageModeShared`, typed pointer access, ring-buffer support for audio frames
- `Shared/AudioFeatures.swift` — Structs for `AudioFrame`, `FFTResult`, `StemData`, `FeatureVector` (all `@frozen` and SIMD-aligned for GPU consumption)

**Test requirements:**
- `UMABufferTests.swift` — 10 tests:
  - `test_init_withCapacity_allocatesCorrectByteCount()`
  - `test_storageMode_isShared()`
  - `test_write_readBack_valuesMatch()` — CPU round-trip
  - `test_write_gpuRead_valuesMatch()` — Write on CPU, read via trivial compute shader, compare
  - `test_ringBuffer_overwrite_oldDataOverwritten()`
  - `test_ringBuffer_readLatest_returnsNewestSamples()`
  - `test_ringBuffer_capacity_neverExceeded()`
  - `test_typedPointer_alignment_isSIMDAligned()`
  - `test_reset_clearsAllData()`
  - `test_concurrentWriteRead_noDataRace()` — Write on background thread, read on main, no crash (use TSan)
- `AudioFeaturesTests.swift` — 6 tests:
  - `test_audioFrame_memoryLayout_isSIMDAligned()`
  - `test_fftResult_binCount_is512()`
  - `test_featureVector_defaultValues_areZero()`
  - `test_stemData_fourStems_correctLayout()`
  - `test_audioFrame_equatable_sameValues_areEqual()`
  - `test_featureVector_simdSize_matchesGPUExpectation()`

**Verification:** All 16 unit tests pass. GPU compute shader test proves zero-copy (same pointer).

### Increment 1.3: System Audio Capture via Core Audio Taps ✅

**Goal:** Capture live system audio output and fill the UMA ring buffer with PCM float32 samples.

**Design rationale:** (unchanged from v1)

**Files created:**
- `Audio/SystemAudioCapture.swift` — Creates a `CATapDescription`, builds an aggregate device, delivers audio via IO proc callback.
- `Audio/AudioInputRouter.swift` — Unified callback-based interface: system audio, app-specific audio, local file fallback. Conforms to `AudioCapturing` protocol.
- `Audio/AudioBuffer.swift` — Ring buffer with `write(from:count:)`. Conforms to `AudioBuffering` protocol.
- `Audio/FFTProcessor.swift` — vDSP 1024-point FFT. Conforms to `FFTProcessing` protocol.
- `tools/audio-tap-test.swift` — Standalone live verification binary.

**Test requirements:**
- `AudioBufferTests.swift` — 12 tests (existing from v1, verify all still pass):
  - `test_write_singleFrame_readBackMatches()`
  - `test_write_multipleFrames_latestSamplesCorrect()`
  - `test_write_overflowRing_oldestOverwritten()`
  - `test_rms_silence_isZero()`
  - `test_rms_knownSine_matchesExpected()` — use `AudioFixtures.sineWave`, assert RMS ≈ 0.707 (±0.01)
  - `test_latestSamples_count_matchesRequested()`
  - `test_latestSamples_afterReset_allZeros()`
  - `test_metalBuffer_isNotNil()`
  - `test_metalBuffer_storageMode_isShared()`
  - `test_writeFromPointer_zeroCopy_matchesDirect()` — compare pointer-based write vs array-based write
  - `test_threadSafety_concurrentWrites_noCrash()` — dispatch 10 concurrent writes
  - `test_capacity_reportedCorrectly()`
- `FFTProcessorTests.swift` — 10 tests:
  - `test_init_binCount_is512()`
  - `test_process_silence_allBinsNearZero()` — max magnitude < 0.001
  - `test_process_440HzSine_peakInExpectedBin()` — bin 9 (440/48000*1024) has highest magnitude
  - `test_process_lowFreqSine_peakInLowBins()` — 100Hz, verify energy below bin 5
  - `test_process_stereoInput_mixesDown()` — L=sine, R=silence → half amplitude
  - `test_process_shortInput_padsWithZeros()` — input < 1024, no crash, reasonable output
  - `test_process_outputBuffer_storageModeShared()`
  - `test_process_noAllocation_perFrame()` — measure allocations, assert 0 heap allocs in hot path
  - `test_process_hannWindow_applied()` — process a DC signal, verify spectral leakage is suppressed vs rectangular window
  - `test_process_deterministic_sameInput_sameOutput()` — process twice, outputs identical
- `AudioInputRouterTests.swift` — 6 tests:
  - `test_init_defaultMode_isSystemAudio()`
  - `test_setMode_filePlayback_callsAVAudioFile()` — mock file, verify callback fires
  - `test_onAudioSamples_callbackFires_withValidPointer()`
  - `test_stop_noMoreCallbacks()`
  - `test_switchMode_whileRunning_noGap()` — verify no crash on hot-switch
  - `test_routerConformsToAudioCapturing()`
- **Integration test** `AudioToFFTPipelineTests.swift` — 3 tests:
  - `test_sineWaveThroughPipeline_fftShowsPeak()` — mock audio source → AudioBuffer → FFTProcessor → verify peak bin
  - `test_silenceThroughPipeline_fftIsFlat()`
  - `test_continuousStream_noMemoryGrowth()` — process 10,000 frames, assert stable memory

**Performance tests** `FFTPerformanceTests.swift`:
  - `test_fftProcess_1024Samples_performance()` — `measure {}` block, baseline < 0.1ms

**Verification:** All 31+ unit tests pass. Integration tests pass. Standalone `audio-tap-test.swift` captures live audio. `swift test` + `swiftlint` clean.

**Implementation notes (completed 2026-04-06):** (unchanged from v1)

### Increment 1.4: Basic Fragment Shader Visualizer ✅

**Goal:** Render a full-screen quad driven by FFT data — proving the audio-to-GPU-to-pixel pipeline works end to end.

**Files created/edited:** (unchanged from v1)

**Test requirements:**
- `ShaderLibraryTests.swift` — 6 tests:
  - `test_init_discoversWaveformShader()`
  - `test_loadShader_validName_returnsPipelineState()`
  - `test_loadShader_invalidName_returnsNil()`
  - `test_cachedPipelineState_sameName_returnsSameInstance()`
  - `test_allShaderNames_returnsNonEmptySet()`
  - `test_shaderCompilation_noWarnings()` — compile all discovered shaders, assert no compilation warnings
- `RenderPipelineTests.swift` — add 4 tests:
  - `test_bindFFTBuffer_bufferIsAccessible()`
  - `test_bindWaveformBuffer_bufferIsAccessible()`
  - `test_draw_withValidBuffers_completesWithoutError()`
  - `test_draw_withStubFFT_producesNonBlackOutput()` — render one frame with a known FFT stub, read back pixels, assert not all black
- **Integration test** `Integration/AudioToRenderPipelineTests.swift` — 2 tests:
  - `test_fullPipeline_sineWave_rendersNonBlackFrame()` — mock audio → buffer → FFT → render → read pixels → assert non-uniform
  - `test_fullPipeline_silence_rendersBackgroundOnly()`

**Verification:** Play music in any streaming app. 64-bar spectrum and waveform respond in real time. All 12+ new tests pass. Full `./tools/ci-check.sh` green.

**Implementation notes (completed 2026-04-06):** (unchanged from v1)

### Increment 1.5: Basic Preset Abstraction & Hot-Reloading ✅

**Goal:** Define a `Preset` protocol and loader so that shaders can be swapped at runtime.

**Files to create/edit:**
- `Presets/PresetCategory.swift` — Enum for categories: `waveform`, `fractal`, `geometric`, `particles`, `hypnotic`, `supernova`, `reaction`, `drawing`, `dancer`, `transition`
- `Presets/PresetLoader.swift` — Discovers `.metal` files in a presets directory, compiles pipeline states, caches them, supports hot-reload via `DispatchSource.FileSystemObject`. Conforms to `PresetLoading` protocol.
- Write 2-3 simple native presets as separate `.metal` files to prove the loader works

**Test requirements:**
- `PresetCategoryTests.swift` — 4 tests:
  - `test_allCases_count_is10()`
  - `test_rawValues_areSnakeCase()`
  - `test_codable_roundTrip()`
  - `test_displayName_isHumanReadable()`
- `PresetLoaderTests.swift` — 8 tests:
  - `test_init_discoversPresetsInDirectory()`
  - `test_loadPreset_validName_returnsPipelineState()`
  - `test_loadPreset_invalidName_returnsNil()`
  - `test_presetCount_matchesFilesOnDisk()`
  - `test_allPresets_compileSuccessfully()` — no compilation errors on any discovered preset
  - `test_caching_samePresetTwice_returnsCachedState()`
  - `test_presetsByCategory_filtersCorrectly()` — given manifest, returns only matching category
  - `test_hotReload_newFileAdded_detectedWithinTimeout()` — write a new .metal file, assert loader discovers it within 2 seconds
- `StubPresetLoader.swift` in TestDoubles — returns canned preset list, no disk access

**Verification:** Press a key to cycle through presets. New `.metal` files dropped into the presets folder appear without restarting. All 12 tests pass.

---

## Phase 2 — Audio Intelligence & ML Pipeline (Blueprint Release 0.3)

### Increment 2.1: Streaming Metadata Integration & Pre-Fetching ✅

**Status:** Complete.

**Goal:** Enrich the audio pipeline with track metadata from streaming services and external music databases. Pre-fetched data is a "fast hint" for the first ~15 seconds — self-computed MIR (Increment 2.4) is the real source of truth.

**Design rationale:** (unchanged from v1)

**Key decisions made during implementation:**
- `MPNowPlayingInfoCenter` only returns the host app's own metadata — cannot read other apps. Switched to MediaRemote private framework (dynamically loaded) for system-wide Now Playing.
- AcousticBrainz shut down in 2022 — removed. MusicBrainz (free) provides genre tags.
- Spotify Audio Features deprecated Nov 2024 (403 for new apps) — Spotify is search-only for track matching. Soundcharts added as optional commercial replacement for audio features (BPM, key, energy, valence, danceability).
- Essentia (AGPL) for offline validation in `tools/` Python scripts only — NOT shipped in app binary. Pre-computes ground-truth features for testing and validates MIR pipeline accuracy.

**Files created/edited:**
- `Audio/StreamingMetadata.swift` — Polls MediaRemote for system-wide Now Playing. Detects track changes. Conforms to `MetadataProviding`.
- `Audio/MetadataPreFetcher.swift` — Parallel async queries with 3s per-fetcher timeouts, LRU cache (50 entries via OrderedDictionary), merge partial results.
- `Audio/MusicBrainzFetcher.swift` — Free API, no auth. Genre tags + duration from recording search.
- `Audio/SpotifyFetcher.swift` — Client credentials flow, search-only track matching. Env vars: `SPOTIFY_CLIENT_ID`, `SPOTIFY_CLIENT_SECRET`.
- `Audio/SoundchartsFetcher.swift` — Optional commercial API for audio features. Env vars: `SOUNDCHARTS_APP_ID`, `SOUNDCHARTS_API_KEY`.
- `Audio/MusicKitBridge.swift` — Optional MusicKit enrichment. `#if canImport(MusicKit)` gated, graceful no-op.
- `Audio/Protocols.swift` — Added `MetadataProviding`, `MetadataFetching`, `TrackChangeEvent`, `PartialTrackProfile`.
- `Audio/AudioInputRouter.swift` — Added `onTrackChange` callback, optional metadata provider.
- `Shared/AudioFeatures.swift` — Added `TrackMetadata`, `PreFetchedTrackProfile`, `MetadataSource`.
- `PhospheneApp/ContentView.swift` — Wired StreamingMetadata + MetadataPreFetcher into VisualizerEngine.
- `PhospheneApp/Views/DebugOverlayView.swift` — Debug overlay (toggle with 'D' key) showing track info + pre-fetched data.

**Tests:** 21 new tests (115 total). 7 StreamingMetadata, 10 MetadataPreFetcher, 2 integration, 2 regression with golden JSON fixtures.

**Verification:** Play a song in Spotify, then switch to Apple Music. Press 'D' for debug overlay. Track info appears from MediaRemote. MusicBrainz genre tags appear within 2 seconds. Soundcharts audio features appear if credentials are configured.

### Increment 2.2: CoreML Stem Separation Model Conversion

**Goal:** Convert an open-source stem separation model to CoreML `.mlpackage` targeting the ANE.

**This is a Python-side task.** Claude Code will:
- Write `tools/convert_stem_model.py` with:
  - Model loading, ONNX export, CoreML conversion
  - Input/output shape validation assertions
  - Automated comparison: run PyTorch inference and CoreML inference on same input, assert max absolute error < 0.01
- Write `tools/test_stem_model.py` — integration test:
  - Load a 10-second WAV, run inference, write 4 stem WAVs
  - Assert each stem WAV has correct sample rate, channel count, and nonzero energy
  - Assert stems recombine to approximate original (sum of stems ≈ original, MSE < 0.05)

**Test requirements (Python):**
- `tools/test_stem_model.py` — 6 assertions:
  - Output shape is `[4, 2, T]`
  - Each stem has nonzero RMS
  - Vocal stem has lower energy than drum stem on a drum-heavy test clip
  - Stems sum to approximate original (MSE < 0.05)
  - CoreML output matches PyTorch output (max abs error < 0.01)
  - Inference completes in < 5 seconds for 10 seconds of audio on ANE

**Verification:** Four output WAV files sound correct individually. All Python tests pass.

### Increment 2.3: Swift CoreML Stem Separator Integration

**Goal:** Load the `.mlpackage` in Swift, run inference on the ANE, write separated stems into UMA buffers.

**Files to create/edit:**
- `ML/StemSeparator.swift` — Load `MLModel`, configure for `.cpuAndNeuralEngine`, accept `UMABuffer<Float>` input, write 4 stem `UMABuffer<Float>` outputs. Conforms to `StemSeparating` protocol.
- Update `Audio/AudioBuffer.swift` to provide chunked audio windows

**Test requirements:**
- `StemSeparatorTests.swift` — 8 tests:
  - `test_init_loadsModel_noThrow()`
  - `test_init_computeUnits_isCPUAndNeuralEngine()`
  - `test_separate_validInput_returnsFourStems()`
  - `test_separate_silence_allStemsNearZero()`
  - `test_separate_outputBuffers_storageModeShared()`
  - `test_separate_stemLabels_correctOrder()` — vocals, drums, bass, other
  - `test_separate_chunkedInput_noGapBetweenChunks()`
  - `test_conformsToStemSeparating()`
- `FakeStemSeparator.swift` in TestDoubles — returns canned stem data (e.g., copies input to drums stem, zeros others)
- **Performance test** `Performance/StemSeparationPerformanceTests.swift`:
  - `test_separate_4096Samples_performance()` — measure, baseline < 50ms

**Integration test** `Integration/AudioToStemPipelineTests.swift` — 2 tests:
  - `test_sineWaveInput_stemsHaveExpectedEnergyDistribution()`
  - `test_continuousChunks_noMemoryLeak()` — process 100 chunks, assert stable memory

**Verification:** Debug overlay shows per-stem RMS levels. Drums spike on kicks. All 12+ tests pass.

### Increment 2.4: MIR Feature Extraction Pipeline

**Goal:** Implement real-time MIR feature extraction on the CPU using Accelerate. This is the primary source of audio features (BPM, key, spectral characteristics) — pre-fetched data from external APIs (Increment 2.1) is a "fast hint" for the first ~15 seconds, after which the self-computed MIR pipeline takes over as the source of truth.

**Essentia validation tooling:** Use Essentia (AGPL, Python) in `tools/` scripts to pre-compute ground-truth audio features for test fixtures. Compare self-computed MIR output against Essentia's output to validate accuracy. Essentia is NEVER linked into PhospheneEngine or PhospheneApp — it is an offline validation tool only.

**Files to create/edit:**
- `DSP/SpectralAnalyzer.swift` — Spectral centroid, rolloff, flux (vDSP)
- `DSP/ChromaExtractor.swift` — 12-bin chroma vector, key estimation
- `DSP/BeatDetector.swift` — Onset detection, tempo estimation via autocorrelation
- `DSP/FeatureVector.swift` — Combines all features into SIMD-aligned struct
- `tools/essentia_ground_truth.py` — Essentia-based ground truth generator for MIR validation fixtures

**Test requirements:**
- `SpectralAnalyzerTests.swift` — 8 tests:
  - `test_centroid_silence_isZero()`
  - `test_centroid_lowFreqSine_belowMidpoint()`
  - `test_centroid_highFreqSine_aboveMidpoint()`
  - `test_rolloff_silence_isZero()`
  - `test_rolloff_fullBandNoise_near85Percent()`
  - `test_flux_steadySignal_nearZero()`
  - `test_flux_suddenOnset_highValue()`
  - `test_allFeatures_deterministic_sameInput_sameOutput()`
- `ChromaExtractorTests.swift` — 6 tests:
  - `test_chroma_CMajorChord_peakAtCEG()` — bins 0, 4, 7 have highest energy
  - `test_chroma_AMinorChord_peakAtACE()`
  - `test_chroma_silence_allBinsNearZero()`
  - `test_keyEstimation_CMajorChord_returnsC()`
  - `test_keyEstimation_AMinorScale_returnsAm()`
  - `test_chroma_deterministic()`
- `BeatDetectorTests.swift` — 7 tests:
  - `test_tempo_120BPMKick_estimatesNear120()` — synthesize 120BPM kick pattern, assert tempo ∈ [118, 122]
  - `test_tempo_90BPMKick_estimatesNear90()`
  - `test_tempo_silence_returnsNilOrZero()`
  - `test_onsetDetection_singleImpulse_detectsOne()`
  - `test_onsetDetection_regularKicks_countMatchesExpected()`
  - `test_onsetDetection_noOnsets_inSilence()`
  - `test_tempo_deterministic()`
- `FeatureVectorTests.swift` — 4 tests:
  - `test_combine_allFeaturesPresent()`
  - `test_simdAlignment_matchesGPUExpectation()`
  - `test_defaultValues_allZero()`
  - `test_encode_toUMABuffer_readBackMatches()`

**Regression tests** `Regression/`:
  - `FFTRegressionTests.swift` — known 440Hz sine → golden FFT magnitude array (saved to `Fixtures/440hz_fft_expected.json`), assert max delta < 0.0001
  - `ChromaRegressionTests.swift` — known C major chord → golden chroma vector, assert max delta < 0.01
  - `BeatDetectorRegressionTests.swift` — known 120BPM kick pattern → golden onset timestamps, assert max delta < 10ms

**Performance tests:**
  - `Performance/DSPPerformanceTests.swift` — measure spectral centroid, chroma, and beat detection on 1 second of audio, assert < 5ms each

**Integration test** `Integration/MIRPipelineTests.swift` — 3 tests:
  - `test_fullMIRPipeline_sineWave_allFeaturesPopulated()`
  - `test_fullMIRPipeline_silence_gracefulDefaults()`
  - `test_fullMIRPipeline_continuousFrames_noMemoryGrowth()`

**Verification:** Console shows "BPM: 128, Key: Am, Centroid: 3400Hz, Brightness: 0.72" updating in real time. All 28+ unit tests, 3 regression tests, 3 performance tests, and 3 integration tests pass.

### Increment 2.5: Mood Classification Model

**Goal:** Train or convert a lightweight valence/arousal classifier and deploy on ANE.

**Python side:**
- `tools/train_mood_classifier.py`
- `tools/test_mood_classifier.py` — 4 assertions:
  - Output shape is `[2]` (valence, arousal)
  - Values in range [-1, 1]
  - High-energy major-key input → positive valence, high arousal
  - Slow minor-key input → negative valence, low arousal

**Swift side:**
- `ML/MoodClassifier.swift` — Conforms to `MoodClassifying` protocol.
- `Shared/AudioFeatures.swift` — Add `EmotionalState` struct with `valence: Float`, `arousal: Float`, `quadrant: EmotionalQuadrant`

**Test requirements:**
- `MoodClassifierTests.swift` — 7 tests:
  - `test_init_loadsModel()`
  - `test_classify_validFeatureVector_returnsEmotionalState()`
  - `test_classify_valenceInRange_minus1To1()`
  - `test_classify_arousalInRange_minus1To1()`
  - `test_classify_highEnergyMajorKey_happyQuadrant()`
  - `test_classify_lowEnergyMinorKey_sadQuadrant()`
  - `test_conformsToMoodClassifying()`
- `EmotionalStateTests.swift` — 4 tests:
  - `test_quadrant_highValenceHighArousal_isHappy()`
  - `test_quadrant_lowValenceLowArousal_isSad()`
  - `test_quadrant_lowValenceHighArousal_isTense()`
  - `test_quadrant_highValenceLowArousal_isCalm()`
- `StubMoodClassifier.swift` in TestDoubles — returns fixed (valence, arousal) for orchestrator testing

**Verification:** Debug overlay shows "Mood: Happy/Energetic (V:0.7 A:0.8)" updating per segment. All 11 tests pass.

### Increment 2.6: Analysis Lookahead Buffer

**Goal:** Configurable delay between analysis and rendering for anticipatory visual decisions.

**Design rationale:** (unchanged from v1)

**Files to create/edit:**
- `Audio/LookaheadBuffer.swift` — Timestamped ring buffer with dual read heads (analysis and render).
- `Shared/AnalyzedFrame.swift` — Timestamped container: `AudioFrame` + `FFTResult` + `StemData` + `FeatureVector` + `EmotionalState`.
- `Audio/AudioInputRouter.swift` — Dual callbacks: `onAnalysisFrame` and `onRenderFrame`.

**Test requirements:**
- `LookaheadBufferTests.swift` — 10 tests:
  - `test_enqueue_incrementsCount()`
  - `test_dequeueAnalysisHead_returnsLatestFrame()`
  - `test_dequeueRenderHead_returnsDelayedFrame()`
  - `test_delay_2500ms_renderHeadLagsAnalysisHead()` — enqueue frames with timestamps, assert render head timestamp = analysis head - 2500ms (±50ms)
  - `test_delay_0ms_bothHeadsReturnSameFrame()`
  - `test_setDelay_midStream_adjustsSmoothly()`
  - `test_buffer_overflow_dropsOldestFrames()`
  - `test_reset_clearsAllFrames()`
  - `test_emptyBuffer_dequeue_returnsNil()`
  - `test_threadSafety_concurrentEnqueueDequeue_noCrash()`
- `AnalyzedFrameTests.swift` — 3 tests:
  - `test_init_allFieldsAccessible()`
  - `test_timestamp_monotonicallyIncreasing()`
  - `test_memoryLayout_isReasonableSize()` — assert < 64KB per frame

**Integration test:**
  - `test_analysisToRenderDelay_measuredAccurately()` — push 100 frames at 60fps, measure actual delay at render head, assert within ±100ms of configured delay

**Verification:** Two debug oscilloscopes show analysis and render heads with visible lag. All 13+ tests pass.

### Increment 2.7: Progressive Structural Analysis

**Goal:** Real-time structural segmentation that predicts section boundaries.

**Algorithm overview:** (unchanged from v1)

**Files to create/edit:**
- `DSP/StructuralAnalyzer.swift`
- `DSP/SelfSimilarityMatrix.swift`
- `DSP/NoveltyDetector.swift`
- `Shared/AnalyzedFrame.swift` — Add `StructuralPrediction`.

**Test requirements:**
- `StructuralAnalyzerTests.swift` — 8 tests:
  - `test_init_noSegments()`
  - `test_feed_oneSection_noPredictioin()` — not enough data yet
  - `test_feed_twoSections_predictsThirdBoundary()`
  - `test_sectionBoundary_detectedOnNoveltyPeak()`
  - `test_repetition_identifiedCorrectly()` — section 3 similar to section 1
  - `test_confidence_lowForAmbientTrack()` — feed random feature vectors, assert low confidence
  - `test_confidence_highForRepetitiveTrack()` — feed ABAB pattern, assert high confidence
  - `test_reset_clearsHistory()`
- `SelfSimilarityMatrixTests.swift` — 5 tests:
  - `test_add_frame_matrixGrows()`
  - `test_similarity_identicalFrames_is1()`
  - `test_similarity_orthogonalFrames_isNear0()`
  - `test_ringBuffer_capsAtMaxHistory()`
  - `test_cosineSimilarity_matchesManualCalculation()`
- `NoveltyDetectorTests.swift` — 5 tests:
  - `test_detect_noChange_noPeaks()`
  - `test_detect_abruptChange_peakDetected()`
  - `test_detect_gradualChange_noPeak()`
  - `test_peakPicking_adaptiveThreshold_ignoresMinorFluctuations()`
  - `test_detect_deterministic()`

**Regression test:**
  - `Regression/StructuralAnalysisRegressionTests.swift` — feed a known AABA feature sequence (from fixture file), assert detected boundaries match golden timestamps (±500ms)

**Verification:** After first verse-chorus, debug shows predicted next boundary within ±5 seconds. All 18+ tests pass.

---

## Phase 3 — Advanced Metal Rendering (Blueprint Release 0.5)

### Increment 3.1: Compute Shader Particle System

**Goal:** GPU compute pipeline driving millions of particles from stem-separated audio.

**Files to create/edit:**
- `Renderer/Shaders/Particles.metal`
- `Renderer/Geometry/ProceduralGeometry.swift`

**Test requirements:**
- `ProceduralGeometryTests.swift` — 6 tests:
  - `test_init_particleBuffer_allocatedWithCapacity()`
  - `test_particleBuffer_storageModeShared()`
  - `test_dispatch_compute_noGPUError()` — run compute dispatch, assert command buffer completes without error
  - `test_particleCount_matchesConfiguration()`
  - `test_zeroAudioInput_particlesStationary()` — all velocities near zero after compute
  - `test_impulseAudioInput_particlesEmitted()` — nonzero velocity for some particles
- **Performance test:**
  - `test_particleCompute_1MillionParticles_under8ms()` — measure GPU compute time

**Verification:** Visual: millions of particles on screen, drum stem triggers bursts. All 7 tests pass.

### Increment 3.2: Mesh Shader Pipeline (Object + Mesh Shaders)

**Goal:** Metal mesh shading for procedural fractal and geometric generation.

**Files to create/edit:**
- `Renderer/Shaders/MeshShaders.metal`
- `Renderer/Geometry/MeshGenerator.swift`

**Test requirements:**
- `MeshGeneratorTests.swift` — 5 tests:
  - `test_init_createsMeshPipelineDescriptor()`
  - `test_meshPipelineState_createdSuccessfully()`
  - `test_dispatch_meshDraw_completesWithoutError()`
  - `test_maxVerticesPerMeshlet_is256()`
  - `test_maxPrimitivesPerMeshlet_is512()`
- **Performance test:**
  - `test_meshShaderFractal_60fps_frameTimeUnder16ms()`

**Verification:** 3D fractal structure renders, branches respond to audio. Frame rate > 60fps. All 6 tests pass.

### Increment 3.3: Hardware Ray Tracing Integration

**Goal:** Ray-traced reflections and shadows using `MPSRayIntersector`.

**Files to create/edit:**
- `Renderer/RayTracing/BVHBuilder.swift`
- `Renderer/RayTracing/RayIntersector.swift`
- `Renderer/Shaders/PostProcess.metal`

**Test requirements:**
- `BVHBuilderTests.swift` — 4 tests:
  - `test_build_withTriangles_createsAccelerationStructure()`
  - `test_build_emptyGeometry_handlesGracefully()`
  - `test_rebuild_afterGeometryChange_succeeds()`
  - `test_accelerationStructure_isNotNil()`
- `RayIntersectorTests.swift` — 4 tests:
  - `test_intersect_rayHitsTriangle_returnsHit()`
  - `test_intersect_rayMissesGeometry_returnsNoHit()`
  - `test_shadowRay_occluded_returnsInShadow()`
  - `test_reflectionRay_computedCorrectly()`
- **Performance test:**
  - `test_rayTrace_1000Rays_under2ms()`

**Verification:** Geometric preset shows reflections and shadows. Toggle ray tracing on/off to see difference. All 9 tests pass.

### Increment 3.4: Indirect Command Buffers for GPU-Driven Rendering

**Goal:** GPU encodes its own draw calls via ICBs based on audio state.

**Files to create/edit:**
- `Renderer/RenderPipeline.swift` — ICB creation and execution

**Test requirements:**
- `RenderPipelineICBTests.swift` — 5 tests:
  - `test_createICB_maxCommandCount_matchesConfig()`
  - `test_computeShader_populatesICB_nonZeroCommands()`
  - `test_executeICB_completesWithoutError()`
  - `test_icb_resetBetweenFrames()`
  - `test_icb_withZeroAudio_minimumDrawCalls()`
- **Performance test:**
  - `test_gpuDrivenRendering_cpuFrameTimeReduced()` — compare CPU frame time with and without ICB

**Verification:** CPU frame time drops. GPU debugger confirms GPU-originated draw calls. All 6 tests pass.

---

## Phase 4 — AI Orchestrator & VJ Logic (Blueprint Release 0.7)

### Increment 4.1: Preset Categorization & Metadata System

**Goal:** Data layer tagging presets with category, visual characteristics, and mood match.

**Files to create/edit:**
- `Presets/PresetCategory.swift` — Expand with metadata fields: color temperature (warm/cool), geometric complexity (low/med/high), motion intensity, bloom level
- `Presets/PresetLoader.swift` — Parse embedded metadata from preset files or a sidecar JSON manifest
- `presets_manifest.json` with entries for all native presets and their properties

**Test requirements:**
- `PresetCategoryTests.swift` — add 5 tests:
  - `test_metadata_colorTemperature_defaultIsNeutral()`
  - `test_metadata_complexity_validRange()`
  - `test_metadata_codable_roundTripWithMetadata()`
  - `test_presetsForMood_highValenceHighArousal_returnsWarmCategories()`
  - `test_presetsForMood_lowValenceLowArousal_returnsCoolCategories()`
- `PresetLoaderTests.swift` — add 4 tests:
  - `test_loadManifest_validJSON_parsesAllEntries()`
  - `test_loadManifest_missingFields_usesDefaults()`
  - `test_loadManifest_malformedJSON_returnsEmptyGracefully()`
  - `test_presetsForMood_filtersCorrectly()`

**Verification:** `PresetLoader.presets(forMood: .highValenceHighArousal)` returns the correct subset. All 9 tests pass.

### Increment 4.2: Emotion-to-Visual Semantic Mapper

**Goal:** Implement the mapping matrix from the blueprint — emotional quadrant to visual parameters.

**Files to create/edit:**
- `Orchestrator/EmotionMapper.swift` — Takes `EmotionalState` and returns `VisualDirective` (target preset category, color palette, camera speed, bloom intensity, particle emission rate, ray-trace bounce limit)
- `Shared/VisualDirective.swift` — The struct that parameterizes the renderer

**Test requirements:**
- `EmotionMapperTests.swift` — 10 tests:
  - `test_map_highValenceHighArousal_warmHues()`
  - `test_map_highValenceHighArousal_fastCameraRotation()`
  - `test_map_highValenceHighArousal_highBloom()`
  - `test_map_highValenceLowArousal_pastelPalette()`
  - `test_map_highValenceLowArousal_slowTransforms()`
  - `test_map_lowValenceHighArousal_sharpGeometry()`
  - `test_map_lowValenceHighArousal_deepRedsPurples()`
  - `test_map_lowValenceLowArousal_coolHues()`
  - `test_map_lowValenceLowArousal_lowAmbientLight()`
  - `test_map_neutralValues_reasonableDefaults()`
- `VisualDirectiveTests.swift` — 3 tests:
  - `test_directive_allFieldsPresent()`
  - `test_directive_codable_roundTrip()`
  - `test_directive_defaultValues_areNeutral()`

**Verification:** Unit tests covering all four quadrants produce expected directives. All 13 tests pass.

### Increment 4.3: Transition Engine

**Goal:** Smooth crossfading between two active presets using dual render targets and interpolation.

**Files to create/edit:**
- `Orchestrator/TransitionEngine.swift` — Maintains two `RenderPipeline` instances, alpha-blends output textures, supports dissolve / morph / wipe styles
- `Renderer/Shaders/Transition.metal` — Fragment shader blending two input textures
- `Renderer/RenderPipeline.swift` — Support rendering to offscreen texture

**Test requirements:**
- `TransitionEngineTests.swift` — 8 tests:
  - `test_init_noActiveTransition()`
  - `test_startTransition_setsIsTransitioningTrue()`
  - `test_progress_atStart_isZero()`
  - `test_progress_atEnd_isOne()`
  - `test_progress_midway_isNearHalf()`
  - `test_completeTransition_setsIsTransitioningFalse()`
  - `test_transitionStyle_dissolve_linearAlpha()`
  - `test_concurrentTransitionRequest_queuesNotOverlaps()`
- **Performance test:**
  - `test_dualRenderTarget_transitionFrame_under16ms()`

**Verification:** Press a key to trigger a transition. Two presets blend smoothly over 2 seconds with no frame drops. All 9 tests pass.

### Increment 4.4: Streaming-Aware Orchestrator Core

**Goal:** The main Orchestrator fusing all three anticipation systems into a single decision engine.

**Design rationale:** (unchanged from v1 — see Anticipation Source table and progressive ramp-up timeline)

**Files to create/edit:**
- `Orchestrator/AnticipationEngine.swift` — Central fusion module with confidence-weighted merging
- `Orchestrator/Orchestrator.swift` — State machine: idle → listening → ramping → full. Heuristic policy first (no RL).
- `Orchestrator/TrackChangeDetector.swift` — Fuses Now Playing events, audio-level heuristics, and elapsed time

**Test requirements:**
- `AnticipationEngineTests.swift` — 10 tests:
  - `test_init_stateIsEmpty()`
  - `test_feedAnalysisFrame_updatesCurrentState()`
  - `test_feedPreFetchedProfile_mergesWithMIR()`
  - `test_confidenceWeighting_prefersHigherConfidence()` — MIR says BPM=120 (conf 0.9), Spotify says BPM=122 (conf 0.7), result ≈ 120
  - `test_moodTrajectory_providesLookaheadWindow()`
  - `test_predictedBoundary_fromStructuralAnalysis_present()`
  - `test_noMetadata_functionsWithAudioOnly()`
  - `test_allSourcesFail_gracefulDefaults()`
  - `test_reset_clearsAccumulatedState()`
  - `test_trackDuration_improvesEndOfTrackPrediction()`
- `OrchestratorTests.swift` — 12 tests:
  - `test_init_stateIsIdle()`
  - `test_audioInput_transitionsToListening()`
  - `test_afterMIRRampUp_transitionsToRamping()`
  - `test_afterStructuralConfidence_transitionsToFull()`
  - `test_selectPreset_matchesMoodQuadrant()` — use StubMoodClassifier + StubPresetLoader
  - `test_selectPreset_neverRepeatsSameCategoryTwice()`
  - `test_transition_prefersStructuralBoundary()` — when boundary predicted in 3s, transition starts now
  - `test_transition_fallsBackToTimer_whenNoStructure()`
  - `test_trackChange_resetsAnticipation()`
  - `test_trackChange_triggersPreFetch()`
  - `test_coldStart_selectsReasonableDefault()`
  - `test_presetOverride_locksOrchestratorSelection()`
- `TrackChangeDetectorTests.swift` — 7 tests:
  - `test_metadataChange_emitsTrackChange()`
  - `test_sameMetadata_noEvent()`
  - `test_audioSilence_plusMetadataChange_emitsEvent()`
  - `test_elapsedTimeNearDuration_raisesConfidence()`
  - `test_noMetadata_audioOnlyDetection_works()`
  - `test_rapidMetadataChanges_debounced()`
  - `test_reset_clearsElapsedTime()`

**Integration test** `Integration/MetadataToOrchestratorTests.swift` — 3 tests:
  - `test_trackChange_orchestratorReceivesNewState()`
  - `test_moodShift_triggersPresetChange()`
  - `test_fullPipeline_5MockTracks_noConsecutiveCategoryRepeats()`

**Verification:** Stream a 5-track playlist. Orchestrator selects mood-appropriate presets, transitions land on section boundaries, no black screens. Debug log shows decision rationale. All 32+ tests pass.

### Increment 4.5: Reinforcement Learning Agent (Optional / Advanced)

**Goal:** Replace the heuristic policy with a trained DQN agent.

**Python side:**
- `tools/train_orchestrator_rl.py` — simulated environment, reward function penalizes jarring transitions
- Export to `.mlpackage`

**Python tests:**
- `tools/test_orchestrator_rl.py` — 4 assertions:
  - Agent selects different actions for different mood quadrants
  - Reward is higher for energy-matched vs mismatched selections
  - Bonus reward for boundary-aligned transitions
  - Exported CoreML model accepts correct input shape

**Swift side:**
- `Orchestrator/Orchestrator.swift` — Load RL model, fall back to heuristic if unavailable

**Test requirements:**
- `OrchestratorTests.swift` — add 3 tests:
  - `test_rlModel_loaded_usesModelPolicy()`
  - `test_rlModel_unavailable_fallsBackToHeuristic()`
  - `test_rlModel_sameInput_deterministicOutput()`

**Verification:** A/B comparison in debug mode. All tests pass.

---

## Phase 5 — Legacy Preset Support (Blueprint Release 0.5–0.9)

### Increment 5.1: Milkdrop Preset Parser

**Goal:** Parse `.milk` preset files — extract per-frame equations, per-vertex equations, waveform definitions, and composite shader code.

**Files to create/edit:**
- `Presets/LegacyTranspiler.swift` — INI-style parser
- `LegacyPreset` struct as intermediate representation

**Test requirements:**
- `LegacyTranspilerTests.swift` — 10 tests:
  - `test_parse_validMilkFile_extractsPerFrameVars()`
  - `test_parse_validMilkFile_extractsPerVertexEquations()`
  - `test_parse_validMilkFile_extractsWarpShader()`
  - `test_parse_validMilkFile_extractsCompositeShader()`
  - `test_parse_emptyFile_returnsNilGracefully()`
  - `test_parse_malformedFile_noThrow()`
  - `test_parse_missingSection_partialResultReturned()`
  - `test_parse_unicodeContent_handled()`
  - `test_parse_windowsLineEndings_handled()`
  - `test_parse_20RepresentativePresets_allFieldsExtracted()` — batch test against fixture files

**Regression test:**
  - `Regression/PresetParserRegressionTests.swift` — parse 5 fixture `.milk` files, assert extracted fields match golden JSON snapshots

**Verification:** Parse 20 representative Cream of the Crop presets. All fields extracted. No crashes. All 11+ tests pass.

### Increment 5.2: Equation Evaluator

**Goal:** Runtime evaluator for Milkdrop's per-frame and per-vertex math expressions.

**Files to create/edit:**
- `Presets/EquationEvaluator.swift` — Tokenizer + recursive descent parser

**Test requirements:**
- `EquationEvaluatorTests.swift` — 15 tests:
  - `test_eval_constant_returnsValue()`
  - `test_eval_addition_correct()`
  - `test_eval_multiplication_correct()`
  - `test_eval_precedence_mulBeforeAdd()`
  - `test_eval_parentheses_overridePrecedence()`
  - `test_eval_sin_correct()`
  - `test_eval_cos_correct()`
  - `test_eval_abs_negativeInput_returnsPositive()`
  - `test_eval_pow_correct()`
  - `test_eval_if_trueCondition_returnsFirst()`
  - `test_eval_if_falseCondition_returnsSecond()`
  - `test_eval_variable_bass_resolves()`
  - `test_eval_variable_time_resolves()`
  - `test_eval_assignment_rotEquation_matchesReference()` — `rot = rot + 0.01 * bass_att` with mock audio
  - `test_eval_complexExpression_nestedCalls()`

**Regression test:**
  - `Regression/EquationRegressionTests.swift` — 10 expressions from real presets with known outputs, verified against reference Milkdrop

**Verification:** All 15+ unit tests and 10 regression tests pass.

### Increment 5.3: HLSL-to-Metal Shader Transpilation

**Goal:** Convert Milkdrop's HLSL warp/composite shaders to Metal Shading Language.

**Files to create/edit:**
- `Presets/LegacyTranspiler.swift` — HLSL-to-MSL conversion

**Test requirements:**
- `LegacyTranspilerHLSLTests.swift` — 8 tests:
  - `test_transpile_tex2D_becomesTextureSample()`
  - `test_transpile_float4_mappedCorrectly()`
  - `test_transpile_registerBinding_toArgumentBuffer()`
  - `test_transpile_simpleShader_compilesInMetal()`
  - `test_transpile_complexShader_compilesInMetal()`
  - `test_transpile_unsupportedFeature_loggedAndSkipped()`
  - `test_transpile_emptySource_returnsNil()`
  - `test_transpile_50Presets_atLeast90PercentSucceed()`

**Verification:** 50 legacy presets render near-identically to ProjectM reference. All 8 tests pass.

---

## Phase 6 — UI & User Experience (Blueprint Release 0.9)

### Increment 6.1: SwiftUI Application Shell

**Goal:** Main window with Metal view, audio source controls, and streaming-aware HUD.

**Files to create/edit:**
- `PhospheneApp/Views/ContentView.swift` — Full-screen Metal view with overlay HUD
- `PhospheneApp/Views/TransportBar.swift` — Audio source selector, fullscreen toggle, preset cycle, settings
- `PhospheneApp/Views/AudioSourcePicker.swift` — Lists running audio-producing applications
- `PhospheneApp/Views/NowPlayingBanner.swift` — Track info, mood quadrant, preset name, anticipation status
- `PhospheneApp/ViewModels/AppViewModel.swift` — Binds UI state to engine

**Test requirements:**
- `AppViewModelTests.swift` — 8 tests:
  - `test_init_audioSource_isSystemAudio()`
  - `test_setAudioSource_application_updatesRouter()`
  - `test_trackMetadata_updates_publishedToUI()`
  - `test_moodState_updates_publishedToUI()`
  - `test_activePreset_updates_publishedToUI()`
  - `test_isFullscreen_toggle_updatesState()`
  - `test_presetOverride_locksOrchestrator()`
  - `test_availableApps_listsRunningProcesses()`

**Verification:** Select Spotify from picker, play music, visualizations begin. Now Playing banner shows correct info. All 8 tests pass.

### Increment 6.2: Visual History Timeline & Orchestrator Overlay

**Goal:** Timeline strip showing Orchestrator decisions and mood analysis.

**Files to create/edit:**
- `PhospheneApp/Views/TimelineView.swift`
- `PhospheneApp/Views/PresetOverrideSheet.swift`
- `PhospheneApp/ViewModels/TimelineViewModel.swift`

**Test requirements:**
- `TimelineViewModelTests.swift` — 6 tests:
  - `test_init_emptyTimeline()`
  - `test_trackChange_addsSegment()`
  - `test_presetChange_addsTransitionMarker()`
  - `test_segmentColor_matchesMoodQuadrant()`
  - `test_multipleTrackChanges_segmentCountMatches()`
  - `test_presetOverride_locksFlagOnSegment()`

**Verification:** Stream three songs. Timeline populates with three color-coded segments. All 6 tests pass.

### Increment 6.3: Settings & Performance Dashboard

**Goal:** Preferences panel and real-time performance metrics.

**Files to create/edit:**
- `PhospheneApp/Views/SettingsView.swift` — Ray tracing toggle, particle density, transition speed, lookahead delay, audio source preference, MusicKit auth, Spotify API key, target frame rate
- `PhospheneApp/Views/PerformanceDashboard.swift` — FPS, GPU/ANE utilization, memory, mood state, stems, anticipation status, active data sources

**Test requirements:**
- `SettingsViewModelTests.swift` — 5 tests:
  - `test_rayTracing_toggle_persistsToUserDefaults()`
  - `test_lookaheadDelay_clamped_0to5()`
  - `test_targetFrameRate_options_60and120()`
  - `test_particleDensity_slider_range()`
  - `test_defaults_areReasonable()`

**Verification:** Toggling ray tracing shows immediate FPS impact. All 5 tests pass.

---

## Phase 7 — Optimization & Polish (Blueprint Release 0.9–1.0)

### Increment 7.1: Metal Performance Profiling Pass

**Goal:** Profile with Instruments and Metal Debugger. Eliminate bottlenecks.

**Claude Code tasks:**
- Add `os_signpost` markers to key pipeline stages
- Document methodology in `docs/PROFILING.md`
- Review all `MTLBuffer` allocations — ensure `.storageModeShared` everywhere
- Verify no manual cache management competing with Dynamic Caching

**Test requirements:**
- `Performance/FullPipelinePerformanceTests.swift` — 4 benchmarks:
  - `test_fullFrame_audioToPixels_under8ms()` — end-to-end at 120fps
  - `test_fftAlone_under0_1ms()`
  - `test_stemSeparation_under50ms()`
  - `test_orchestratorDecision_under1ms()`
- Add `XCTMetric` baselines so regressions are caught by CI

**Verification:** Instruments trace shows no CPU-GPU sync stalls. Frame time under 8ms at 120fps on M3 Pro. All 4 performance benchmarks within baselines.

### Increment 7.2: Memory & Resource Optimization

**Goal:** Minimize memory footprint, ensure no disk swapping.

**Claude Code tasks:**
- Resource pooling for transient textures and buffers
- `MTLHeap` for grouped allocations
- LOD for particles and mesh complexity based on GPU headroom
- ML model memory released when not inferring

**Test requirements:**
- `Performance/MemoryStabilityTests.swift` — 3 tests:
  - `test_extendedPlayback_10Minutes_memoryStable()` — process 36,000 frames, assert memory delta < 50MB
  - `test_trackChanges_100Tracks_noMemoryGrowth()` — simulate 100 track changes, assert stable
  - `test_presetSwitch_100Times_noLeaks()` — cycle presets rapidly, assert stable

**Verification:** Activity Monitor shows stable memory. No swap. All 3 tests pass.

### Increment 7.3: Public Preset SDK & Documentation

**Goal:** Define the API for community preset authors.

**Files to create/edit:**
- `docs/PRESET_SDK.md` — Guide for writing native presets
- `PhospheneEngine/Presets/PresetSDK.swift` — Public protocol and types
- 3 example presets with extensive comments

**Test requirements:**
- `PresetSDKTests.swift` — 4 tests:
  - `test_presetProtocol_hasRequiredProperties()`
  - `test_examplePreset_conformsToProtocol()`
  - `test_examplePreset_compilesSuccessfully()`
  - `test_presetManifest_exampleParsesCorrectly()`

**Verification:** External developer can write a preset following the SDK doc, drop it in the folder, see it appear. All 4 tests pass.

---

## Phase 8 — Release Candidate (Blueprint Release 1.0)

### Increment 8.1: Cream of the Crop Batch Import

**Goal:** Automated pipeline to import, transpile, categorize, and index all 9,795 legacy presets.

**Claude Code tasks:**
- `tools/batch_import_presets.py` — download, parse, categorize, transpile, output Metal shaders + manifest

**Test requirements (Python):**
- `tools/test_batch_import.py` — 5 assertions:
  - At least 90% of presets transpile without error
  - Manifest JSON is valid and contains all transpiled entries
  - Skipped presets are logged with reasons
  - No duplicate IDs in manifest
  - Category distribution is non-degenerate (no single category has >50%)

**Verification:** At least 90% of 9,795 presets transpile and render. Skipped presets logged. All 5 tests pass.

### Increment 8.2: App Store Packaging & Signing

**Goal:** Archive, sign, and prepare for distribution.

**Claude Code tasks:**
- Configure entitlements: network client, file access
- App icons and launch screen
- Archive scheme with release optimizations
- `docs/RELEASE_CHECKLIST.md`

**Test requirements:**
- Final CI gate — every test category must pass:
  - All unit tests (target: 200+)
  - All integration tests (target: 15+)
  - All regression tests (target: 20+)
  - All performance tests within baselines (target: 15+)
  - SwiftLint clean
  - Zero compiler warnings
  - Coverage ≥ 80% on PhospheneEngine

**Verification:** `xcodebuild archive` succeeds. Notarization passes. App launches from exported `.app`. Full test suite green.

---

## Retroactive Quality Increment

### Increment R.1: Test Debt Paydown for Phase 1 (1.1–1.5) ✅

**Goal:** Bring the already-built Phase 1 code up to the quality standards defined in this document.

**Rationale:** Increments 1.1–1.5 were built under v1 of the development plan, which lacked explicit test requirements per increment. The code worked but had gaps in test coverage, protocol-based testability, doc comments, and logging.

**Completed 2026-04-06 in four sub-increments:**

#### R.1a: Protocols, Test Doubles & Logging Infrastructure ✅

Defined testability protocols and created test doubles:
- **Protocols** (`Audio/Protocols.swift`, `Renderer/Protocols.swift`): `AudioCapturing`, `AudioBuffering`, `FFTProcessing`, `Rendering` — all production types now conform to injectable protocols
- **Test doubles** (`TestDoubles/`): `MockAudioCapture` (delivers canned PCM via callback), `StubFFTProcessor` (returns pre-configured magnitudes), `AudioFixtures` (deterministic sine, silence, noise, impulse generators)
- **Logging** (`Shared/Logging.swift`): Per-module `os.Logger` instances — `audio`, `dsp`, `renderer`, `orchestrator`, `ml` — subsystem `"com.phosphene"`
- `AudioInputRouter` refactored to depend on `AudioCapturing` protocol, not concrete `SystemAudioCapture`

#### R.1b: Unit Tests for Renderer and Shared Modules ✅

Added unit tests mirroring source structure:
- `Audio/AudioBufferTests.swift` — ring buffer write/read, RMS, reset, thread safety
- `Audio/FFTProcessorTests.swift` — bin count, 440Hz peak detection, short input, determinism
- `Renderer/MetalContextTests.swift` — device, queue, pixel format, semaphore (4 tests)
- `Renderer/ShaderLibraryTests.swift` — shader discovery, compilation, caching, no warnings (6 tests)
- `Renderer/RenderPipelineTests.swift` — buffer binding, draw completion, non-black output with stub FFT
- `Shared/AudioFeaturesTests.swift` — memory layout, SIMD alignment, default values (6 tests)
- `Shared/UMABufferExtendedTests.swift` — zero-copy GPU roundtrip, overflow, concurrent access (10 tests)
- Existing monolithic `AudioTests.swift` split into per-file test files

#### R.1c: Integration, Regression & Performance Tests ✅

- **Integration** (`Integration/`): `AudioToFFTPipelineTests` (sine→FFT peak, silence→flat, 10k-frame memory stability), `AudioToRenderPipelineTests` (full pipeline non-black frame, silence background)
- **Regression** (`Regression/`): `FFTRegressionTests` with golden fixtures (`440hz_sine_4800.json`, `440hz_fft_expected.json`) — asserts max delta < 0.001 across 512 bins
- **Performance** (`Performance/`): `FFTPerformanceTests` (1024-sample FFT baseline), `RenderLoopPerformanceTests` (frame encode/commit throughput)

#### R.1d: Code Hygiene Pass ✅

- **SwiftLint config** (`.swiftlint.yml`): `force_cast`, `force_try`, `force_unwrapping` → error severity; `file_length` warning → 400; `cyclomatic_complexity` warning → 10
- **Zero `print()` calls** in production code — all replaced with structured `os.Logger` in R.1a
- **Doc comments** on all `public` types, methods, and properties across all production files
- **MARK annotations** in every source file (Properties, Initialization, Public API, Private Helpers)
- **Named constants** extracted: `maxFramesInFlight`, `fftSize`, `binCount`, `defaultWaveformCapacity`, `defaultCapacity`
- **Force-unwrap cleanup**: vDSP pointer ops wrapped in `swiftlint:disable` with comments; `try!` in `ContentView` → `guard let ... try?` + `fatalError`; `PresetDescriptor.fallback` → `do/catch`
- **Refactored** `SystemAudioCapture.startCapture()` from 70-line method → 20-line method + 4 private helpers (fixes cyclomatic complexity and function_body_length)
- Sorted imports across all PhospheneApp files

**Final verification results (R.1 complete):**
- `swift test` → **94 tests pass** (up from 23 pre-R.1)
- `swiftlint lint --strict` → **0 violations**
- `xcodebuild build` → **0 warnings** in project code
- `grep -rn "print(" PhospheneEngine/Sources/` → **0 results**
- All public API has `///` doc comments

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

### Session Start Checklist (MANDATORY)

Before writing any new code in a session, Claude Code must:

```bash
# 1. Run existing tests — all must pass before new work begins
swift test --package-path PhospheneEngine

# 2. Lint — must be clean
swiftlint lint --strict --config .swiftlint.yml
```

If either step fails, fix it first. Do not start the increment's work on a red baseline.

### Session End Checklist (MANDATORY)

Before considering an increment complete, Claude Code must run and pass all of:

```bash
# 1. Lint (zero warnings)
swiftlint lint --strict --config .swiftlint.yml

# 2. Build (warnings-as-errors)
xcodebuild -scheme PhospheneApp -destination 'platform=macOS' \
  build SWIFT_TREAT_WARNINGS_AS_ERRORS=YES 2>&1

# 3. ALL tests (not just new ones — full regression)
swift test --package-path PhospheneEngine 2>&1
```

**All three must pass.** If any fails, fix it before ending the session.

### Code Hygiene Checklist (Per Increment)

For every file created or modified in the increment, verify:

- [ ] No `print()` — use `Logger.audio.debug(...)` etc.
- [ ] No force-unwraps (`!`) in production code
- [ ] All `public` API has `///` doc comments
- [ ] `// MARK: -` sections: Properties, Initialization, Public API, Private Helpers
- [ ] No magic numbers — named constants or enums
- [ ] No commented-out code
- [ ] Every `TODO` has an increment reference: `// TODO: [Increment X.Y] description`
- [ ] File under 400 lines (split if exceeded)
- [ ] New protocols defined for any type that will be a dependency of other modules
- [ ] Test file created mirroring source file path

### Test Writing Checklist (Per Increment)

- [ ] Unit tests for every new public method
- [ ] At least one test per error/edge case path (nil input, empty array, overflow, timeout)
- [ ] Test doubles (mocks/stubs) for all injected dependencies
- [ ] Integration test if this increment connects two modules
- [ ] Regression test if this increment involves numerical computation (DSP, FFT, MIR)
- [ ] Performance test if this increment is on a hot path (audio callback, render loop, FFT)
- [ ] All tests follow naming convention: `test_<Method>_<Scenario>_<Expected>()`
- [ ] Tests are deterministic — no flaky timing, seeded random, known inputs

### Key Technical Constraints to Reiterate

- **macOS 14.0+ only** — no iOS, no cross-platform
- **Metal only** — never OpenGL, never Vulkan
- **Core Audio taps for audio** — primary audio input is system audio capture via `AudioHardwareCreateProcessTap` (macOS 14.2+), not file loading. ScreenCaptureKit was abandoned because it silently fails to deliver audio callbacks on macOS 15+/26. Core Audio taps require screen capture permission to deliver non-zero audio — call `CGRequestScreenCaptureAccess()` before starting.
- **ANE for ML** — always configure CoreML models with `.cpuAndNeuralEngine`, never `.all` (which would compete with GPU)
- **UMA zero-copy** — all shared buffers must use `.storageModeShared`
- **Swift concurrency** — use `async/await` and actors for thread safety, avoid raw `DispatchQueue` where possible
- **No C++ interop in Phase 1-4** — pure Swift + Metal Shading Language. C++ interop only if absolutely required for legacy preset parsing
- **Graceful metadata degradation** — MusicKit is optional. Now Playing is best-effort. Pre-fetched metadata is best-effort. Phosphene must function fully with audio-only.
- **Analysis lookahead is always on** — defaults to 2.5 seconds, never disabled in Orchestrator decision path
- **Network calls are non-blocking** — 3-second timeouts, aggressive caching, silent fallback on failure
- **Protocol-oriented design** — every cross-module dependency is injected via protocol, enabling test doubles
- **No singletons** — all dependencies injected via initializer
- **Logging via os.Logger** — never `print()`. Subsystem: `"com.phosphene"`, category per module.
- **Audio data hierarchy is non-negotiable** — continuous energy is primary visual driver, beat onset is accent only. See CLAUDE.md.

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
xcrun metal --version
python3.11 -c "import coremltools; print(coremltools.__version__)"
ffmpeg -version
swiftlint version
```
- `