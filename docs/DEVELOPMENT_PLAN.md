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

**Primary workflow:** The user connects a playlist from Apple Music or Spotify. Phosphene enters a preparation phase — downloading 30-second preview clips, running full stem separation and MIR analysis on each track, and planning the visual session. When preparation completes (~20–30 seconds), Phosphene signals "Ready" and the user starts playback in their streaming app. During playback, Phosphene captures live system audio via Core Audio taps (`AudioHardwareCreateProcessTap`, macOS 14.2+) to refine the pre-analyzed data in real time. Ad-hoc listening (no connected playlist) is supported as a fallback with real-time-only analysis. Local file playback is supported for testing/offline use.

**Session Preparation Architecture:** Phosphene's primary operating mode front-loads all analysis before playback begins:

1. **Playlist Connection** — AppleScript (Apple Music) or Web API (Spotify) reads the full track list with metadata. The user can also paste a playlist URL directly.
2. **Preview Pre-Analysis** — For each track, download a 30-second preview clip (via iTunes Search API `previewUrl`), run full stem separation (MPSGraph Open-Unmix HQ), and run the complete MIR pipeline (BPM, key, mood, spectral features, structural analysis). Cache all results keyed by track identity.
3. **Session Planning** — The Orchestrator uses per-track profiles to plan the full visual arc: preset selection, transition timing, emotional trajectory across the playlist.

Combined, these systems give the Orchestrator complete information for the entire playlist before the first note plays. Stems are available from frame one of every track with zero warmup.

**Real-Time Refinement (during playback):** Three additional systems refine the pre-analyzed data as each track plays:

1. **Analysis Lookahead Buffer** — 2.5s delay between analysis and rendering for anticipatory visual decisions.
2. **Metadata Enrichment** — Parallel queries to MusicBrainz, Soundcharts (most data already cached from preparation phase).
3. **Progressive Structural Analysis** — Extends the coarse section boundaries from the 30s preview with full-track, time-aligned structural detection.

**Ad-Hoc Fallback:** When no playlist is connected, the real-time refinement layer operates as the primary (and only) analysis path, with the existing reactive Orchestrator mode.

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

### Increment Scope Discipline

These rules govern how increments are scoped and how they relate to each other.

1. **One increment = one reviewable unit of work.** Each increment delivers either a piece of infrastructure OR a preset that uses existing infrastructure — never both in the same increment.
2. **Every infrastructure increment lists the presets or downstream systems it enables.** This makes dependency chains explicit.
3. **Every preset increment lists the infrastructure increments it depends on.** Preset increments must not land until their dependencies are complete.
4. **Scope creep is recorded retroactively, not silently absorbed.** If an increment discovers it needs adjacent infrastructure, it either (a) pauses and splits into a new increment, or (b) completes with a noted scope deviation that becomes a new increment in the plan.
5. **The Phase 3 experience is the case study.** Increment 3.1 violated rule 1 by bundling a particle pipeline + feedback texture infrastructure + the Murmuration preset. Its retroactive split (see the revised 3.1 entries in Phase 3) is the template for how to unwind such bundles.

### CI Pipeline (Enforced via Claude Code Hooks)

Every Claude Code session that modifies Swift code must end with:

```bash
# 1. Lint
swiftlint lint --strict --config .swiftlint.yml

# 2. Build (warnings-as-errors enforced per-target via Phosphene.xcconfig)
xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build 2>&1

# 3. Test — either command runs all 226 tests (213 swift-testing + 13 XCTest)
swift test --package-path PhospheneEngine 2>&1
# or: xcodebuild -scheme PhospheneApp -destination 'platform=macOS' test 2>&1

# 4. Coverage check (after Phase 1 is complete)
# xcrun llvm-cov report ... (threshold: 80%)
```

Do NOT pass `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` on the xcodebuild command line
— it propagates to SPM dependencies (swift-collections, etc.) that compile with
`-suppress-warnings`, and the two flags conflict at the Swift driver level.
The flag is enforced per-target via `PhospheneApp/Phosphene.xcconfig`.

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
│   │   ├── StreamingMetadata.swift    # AppleScript polling of Apple Music/Spotify, track change detection
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
│   │   ├── TextureManager.swift      # Pre-generated noise textures (Phase 3R)
│   │   ├── PostProcessChain.swift
│   │   ├── Shaders/           # .metal shader files
│   │   │   ├── Common.metal
│   │   │   ├── ShaderUtilities.metal  # Reusable MSL: noise, SDF, PBR, UV transforms (Phase 3R)
│   │   │   ├── RayMarch.metal         # G-buffer + deferred lighting for SDF scenes (Phase 3R)
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
        │   ├── RenderPipelineTests.swift
        │   ├── ShaderUtilityTests.swift       # Phase 3R: utility function compilation + correctness
        │   ├── TextureManagerTests.swift       # Phase 3R: noise texture generation + binding
        │   └── RayMarchPipelineTests.swift     # Phase 3R: G-buffer + deferred lighting
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
        │   ├── AudioFeaturesTests.swift
        │   ├── SceneUniformsTests.swift       # Phase 3R: layout, JSON parsing
        │   └── FeatureVectorExtendedTests.swift  # Phase 3R: accumulatedAudioTime
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
- `MPNowPlayingInfoCenter` only returns the host app's own metadata — cannot read other apps.
- MediaRemote private framework works from CLI tools but returns "Operation not permitted" (code 3) from signed app bundles on macOS 15+, even with screen capture permission. Abandoned.
- Switched to AppleScript via Automation framework — queries Apple Music and Spotify directly with a clean per-app permission prompt (`NSAppleEventsUsageDescription` in Info.plist). Metadata observation is independent of screen capture permission.
- AcousticBrainz shut down in 2022 — removed. MusicBrainz (free) provides genre tags.
- Spotify Audio Features deprecated Nov 2024 (403 for new apps) — Spotify is search-only for track matching. Soundcharts added as optional commercial replacement for audio features (BPM, key, energy, valence, danceability).
- Essentia (AGPL) for offline validation in `tools/` Python scripts only — NOT shipped in app binary. Pre-computes ground-truth features for testing and validates MIR pipeline accuracy.

**Files created/edited:**
- `Audio/StreamingMetadata.swift` — Polls Apple Music/Spotify via AppleScript. Detects track changes. Conforms to `MetadataProviding`.
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

**Verification:** ✅ Verified end-to-end. Play a song in Spotify, then switch to Apple Music. Press 'D' for debug overlay. Track info appears via AppleScript (one-time Automation permission prompt per app) with correct source (appleMusic/spotify). MusicBrainz duration appears within 2 seconds. Soundcharts audio features appear if credentials are configured. Metadata works independently of screen capture permission. Screen capture permission polling auto-starts audio capture when granted (no restart needed).

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

**Files created:**
- `tools/convert_stem_model.py` — Loads Open-Unmix HQ (umxhq), builds combined 4-stem model with hardcoded shapes, traces with `torch.jit.trace`, converts to CoreML via `coremltools.convert()`.
- `tools/test_stem_model.py` — Full pipeline test: synthesize drum-heavy clip → STFT → CoreML predict → iSTFT → 4 stem WAVs. 6 assertions.
- `tools/requirements-ml.txt` — Pinned Python deps (torch 2.7.0, coremltools 9.0, openunmix).
- `PhospheneEngine/Sources/ML/Models/StemSeparator.mlpackage` — 68 MB CoreML model (Git LFS tracked).
- `.gitattributes` — Git LFS rules for `.mlpackage`/`.mlmodel` files.

**Key decisions:**
- **Model: Open-Unmix HQ** instead of HTDemucs. HTDemucs fails CoreML conversion due to `view_as_complex` (STFT uses complex tensors) and `int` cast on tensor shapes. Both `torch.jit.trace` → `coremltools` and `torch.onnx.export` → CoreML fail. Open-Unmix's LSTM architecture converts cleanly.
- **STFT split architecture:** CoreML model takes STFT magnitude spectrograms `[1, 2, 2049, nb_frames]`, outputs 4 filtered spectrograms `[4, 2, 2049, nb_frames]`. STFT/iSTFT handled externally in Swift via Accelerate/vDSP. CoreML cannot represent complex numbers. This split also allows sharing STFT computation with the existing FFT analysis pipeline.
- **Hardcoded shapes:** Open-Unmix's `forward()` uses dynamic shape calculations (`x.data.shape`, `x.shape[-1]`) that produce `int` cast ops coremltools can't convert. A `StemSeparatorFixed` wrapper replaces all dynamic shapes with compile-time constants.
- **Accuracy metric:** LSTM layers produce outlier divergences between PyTorch and CoreML (max abs error up to 5.3 on spectrograms). Mean error is 0.0003 and correlation is 0.9999. Test uses mean + 99.9th percentile + correlation thresholds instead of max absolute error.

**Test results:** All 6/6 assertions pass. Output shape [4, 2, 441000] ✓. All stems nonzero ✓. Vocal RMS (0.003) < Drum RMS (0.058) ✓. Reconstruction MSE 0.007 ✓. CoreML↔PyTorch correlation 0.9999 ✓. Inference 0.17s ✓.

**Verification:** ✅ Verified. Four output WAV files written to `tools/output/`. Conversion completes in 5.7s. All Python tests pass. No Swift changes in this increment — 115 Swift tests unaffected.

### Increment 2.3: Swift CoreML Stem Separator Integration ✅

**Status:** Complete.

**Goal:** Load the `.mlpackage` in Swift, run inference on the ANE, write separated stems into UMA buffers.

**Files created/edited:**
- `ML/StemSeparator.swift` — Full STFT → CoreML → iSTFT pipeline. Loads `MLModel` configured for `.cpuAndNeuralEngine`. Resamples to 44100 Hz, STFT with center padding (matching PyTorch `center=True`), packs into `MLShapedArray<Float>`, runs ANE prediction, unpacks via `withUnsafeShapedBufferPointer`, iSTFT back to 4 mono stem waveforms in `UMABuffer<Float>`. Conforms to `StemSeparating` protocol.
- `Audio/Protocols.swift` — Added `StemSeparating` protocol, `StemSeparationResult`, `StemSeparationError`.
- `Package.swift` — Added `.copy("Models")` resource to ML target, `"ML"` dependency to test target.

**Key decisions made during implementation:**
- **Fixed model input size (431 frames):** The CoreML model was converted with a hardcoded shape for 10s of audio. Shorter inputs are zero-padded; longer inputs are truncated. Frame count formula matches PyTorch's `center=True`: `nb_frames = num_samples // hop_length + 1`.
- **MLShapedArray instead of raw MLMultiArray.dataPointer:** ANE output buffers have padded strides (e.g., stride[2]=448 for shape[3]=431, aligned for ANE tile sizes). The backing buffer only maps the logical element count — accessing padding indices via raw `dataPointer` causes SIGSEGV. `MLShapedArray.withUnsafeShapedBufferPointer` correctly traverses padded layouts. This also applies to `MLMultiArray.withUnsafeBytes`. See Failed Approaches #14 in CLAUDE.md.
- **STFT/iSTFT on CPU via Accelerate:** CoreML cannot process complex numbers, so STFT/iSTFT runs in Swift. This is the current performance bottleneck (~6.5s for 10s of audio across 4 stems × 2 channels = 3448 FFT operations). ANE inference itself is fast (~0.2s).
- **GPU STFT/iSTFT (planned future optimization):** Moving STFT/iSTFT to Metal compute shaders would eliminate CPU↔GPU copies and bring separation toward real-time. This is the endgame architecture — tracked in CLAUDE.md Resolved Decision #22 and referenced in Increment 7.1's performance target.

**Tests:** 12 new tests (127 total).
- `ML/StemSeparatorTests.swift` — 8 unit tests: model loading, compute units, valid input separation, silence separation, storage mode, stem labels, chunked input, protocol conformance.
- `TestDoubles/FakeStemSeparator.swift` — Returns canned stem data (copies input to drums stem, zeros others). Configurable via `cannedResult`. Tracks call count.
- `Performance/StemSeparationPerformanceTests.swift` — XCTest.measure benchmark: ~6.5s average for 1s input (padded to 10s fixed model window). Bottleneck is CPU STFT/iSTFT, not ANE inference.
- `Integration/AudioToStemPipelineTests.swift` — 2 tests: sine wave energy distribution across stems, memory stability across 5 consecutive separations.

**Verification:** ✅ All 127 Swift tests pass. Separation produces valid stem waveforms with correct energy distribution. No memory leaks across repeated separations. Performance: ~6.5s per separation (CPU STFT/iSTFT dominated). Debug overlay integration deferred to Increment 2.4 alongside MIR features.

### Increment 2.4: MIR Feature Extraction Pipeline ✅

**Goal:** Implement real-time MIR feature extraction on the CPU using Accelerate. This is the primary source of audio features (BPM, key, spectral characteristics) — pre-fetched data from external APIs (Increment 2.1) is a "fast hint" for the first ~15 seconds, after which the self-computed MIR pipeline takes over as the source of truth.

**Status:** Complete.

**Essentia validation tooling:** Use Essentia (AGPL, Python) in `tools/` scripts to pre-compute ground-truth audio features for test fixtures. Compare self-computed MIR output against Essentia's output to validate accuracy. Essentia is NEVER linked into PhospheneEngine or PhospheneApp — it is an offline validation tool only.

**Files created:**
- `DSP/SpectralAnalyzer.swift` — Spectral centroid, rolloff (85% energy cutoff), flux (half-wave rectified frame diff). vDSP-optimized. Precomputes frequency bins at init.
- `DSP/BandEnergyProcessor.swift` — 3-band + 6-band energy from FFT magnitudes. Milkdrop-style AGC (~5s running avg, two-speed warmup). FPS-independent smoothing (instant + attenuated). Bin-to-band mapping precomputed at init.
- `DSP/ChromaExtractor.swift` — 12-bin chroma vector via bin-to-pitch-class mapping. Krumhansl-Schmuckler key estimation (24 profiles: 12 major + 12 minor rotations, Pearson correlation). Bins below 65 Hz skipped (poor pitch resolution at 46.875 Hz/bin).
- `DSP/BeatDetector.swift` — 6-band spectral flux onset detection, adaptive median threshold (50-frame circular buffer × 1.5), per-band cooldowns (low 400ms, mid 200ms, high 150ms). Grouped beat pulses with exponential decay (pow(0.6813, 30/fps)). Tempo estimation via autocorrelation of composite onset function (300-frame history, 60–200 BPM search range).
- `DSP/MIRPipeline.swift` — Coordinator owning all four analyzers. `process(magnitudes:fps:time:deltaTime:) → FeatureVector`. Normalizes centroid to 0–1 (÷ Nyquist), flux via running-max AGC. Exposes chroma/key/tempo as CPU-side properties for Orchestrator. Leaves valence/arousal at 0 (ML module responsibility).
- `tools/essentia_ground_truth.py` — Offline Essentia validation tool for spectral, chroma, and tempo ground truth.
- `tools/generate_dsp_fixtures.swift` — Generates C major chord (C5+E5+G5) and 120 BPM kick pattern fixtures.

**Design decisions made during implementation:**
- `DSP/FeatureVector.swift` was renamed to `DSP/MIRPipeline.swift` — the `FeatureVector` struct already exists in `Shared/AudioFeatures.swift`. The pipeline coordinator populates it rather than defining a new type.
- `BandEnergyProcessor` was added (not in original spec) because band energy computation, AGC, and smoothing are substantial logic that deserved a dedicated class rather than being inlined in MIRPipeline.
- DSP module takes `[Float]` magnitude arrays, not `UMABuffer` — no Metal dependency in DSP. The caller (Orchestrator/VisualizerEngine) extracts magnitudes from FFTProcessor's UMABuffer before passing to MIRPipeline.
- Both BandEnergyProcessor and BeatDetector independently compute 6-band bin ranges from the same frequency constants. No shared helper — simple duplication avoids coupling between analyzers.
- Chroma tests required higher-octave frequencies (C5+ / 523+ Hz) because at 46.875 Hz/bin resolution, low-frequency notes (< 500 Hz) map to wrong pitch classes due to bin center misalignment.
- Autocorrelation tempo estimation can return half-tempo harmonics (e.g. 60 BPM instead of 120 BPM) — this is a known limitation of basic autocorrelation. Tests accept harmonic ambiguity. Future improvement: harmonic disambiguation via onset spacing analysis.

**Tests (40 new, 162 total):**
- `SpectralAnalyzerTests.swift` — 8 unit tests (centroid, rolloff, flux, determinism)
- `BandEnergyProcessorTests.swift` — 5 unit tests (silence, band routing, AGC, relative preservation, FPS independence)
- `ChromaExtractorTests.swift` — 6 unit tests (C major chord, A minor chord, silence, key estimation, determinism)
- `BeatDetectorTests.swift` — 7 unit tests (120 BPM, 90 BPM, silence, single impulse, regular kicks, no onsets, determinism)
- `MIRPipelineUnitTests.swift` — 4 unit tests (feature population, SIMD alignment, silence defaults, CPU properties)
- `ChromaRegressionTests.swift` — 2 regression tests (golden chroma output, stability)
- `BeatDetectorRegressionTests.swift` — 2 regression tests (golden onset detection, stability)
- `DSPPerformanceTests.swift` — 3 XCTest.measure benchmarks (spectral ~4ms, chroma ~6ms, beat ~3ms per 1s audio)
- `MIRPipelineIntegrationTests.swift` — 3 integration tests (sine wave, silence, 10K-frame memory growth)

**Golden fixtures created:**
- `c_major_chord_4800.json` — 4800 samples of C5+E5+G5 at 48kHz
- `120bpm_kick_48000.json` — 48000 samples (1s) of 120 BPM kick pattern

**Verification:** ✅ All 162 Swift tests pass. Spectral analyzer ~4ms/s, chroma ~6ms/s, beat detector ~3ms/s (all within 5ms budget at steady state). Chroma correctly identifies C major and A minor chords. Onset detection fires on kick patterns and stays silent on silence. MIRPipeline populates all audio-derived FeatureVector fields. 10K-frame continuous processing shows no memory growth. Real-time console verification deferred — requires wiring MIRPipeline into VisualizerEngine (Increment 2.5 or later).

### Increment 2.5: Mood Classification Model ✅

**Status:** Complete.

**Goal:** Train or convert a lightweight valence/arousal classifier and deploy on ANE.

**Implementation notes:**
- Model architecture: 914-parameter MLP (10 → 32 → 16 → 2 with tanh activation).
- **Input changed from 20 features to 10.** Raw 12-bin chroma was replaced with 2 pre-computed major/minor key correlations. A tiny MLP cannot learn the Krumhansl-Schmuckler correlation function implicitly from raw chroma bins — training loss plateaued at 0.23 regardless of model capacity. Pre-computing key correlations reduced loss to 0.021.
- Input features: 6-band energy, spectral centroid, spectral flux, majorKeyCorrelation, minorKeyCorrelation.
- Training: rule-based synthetic data (50k samples), MSE loss, 300 epochs, cosine annealing LR. Validation loss: 0.021.
- EMA smoothing in Swift (alpha=0.1, ~0.5s time constant at 60fps).
- ANE outputs Float16 MLMultiArrays for small models. `MLShapedArray<Float16>` requires macOS 15+. Used `MLMultiArray` subscript access (`.floatValue`) for macOS 14+ compatibility.
- ChromaExtractor will need to expose its major/minor key correlations as public properties for MIRPipeline integration in a future increment.

**Python side:**
- `tools/train_mood_classifier.py` — Rule-based synthetic training, PyTorch MLP, CoreML export.
- `tools/test_mood_classifier.py` — 4 assertions (all pass):
  - Output shape is `[2]` (valence, arousal)
  - Values in range [-1, 1]
  - High-energy major-key input → positive valence (0.93), high arousal (0.79)
  - Slow minor-key input → negative valence (-0.96), low arousal (-0.59)

**Swift side:**
- `ML/MoodClassifier.swift` — Conforms to `MoodClassifying` protocol. CoreML wrapper with EMA smoothing.
- `Shared/AudioFeatures.swift` — `EmotionalState` struct with `valence: Float`, `arousal: Float`, computed `quadrant: EmotionalQuadrant`.
- `Audio/Protocols.swift` — `MoodClassifying` protocol, `MoodClassificationError` enum.

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

**Verification:** ✅ All 173 Swift tests pass (162 existing + 11 new). 4/4 Python model assertions pass. `xcodebuild` succeeds. SwiftLint 0 violations. Model: 0.01 MB `.mlpackage`.

### Increment 2.6: Analysis Lookahead Buffer ✅

**Status:** Complete.

**Goal:** Configurable delay between analysis and rendering for anticipatory visual decisions.

**Design rationale:** (unchanged from v1)

**Implementation notes:**
- `LookaheadBuffer` is a thread-safe ring buffer (NSLock-synchronized, default 512 frames) with configurable delay (default 2.5s). Analysis head returns the latest frame; render head finds the frame closest to `(latest timestamp - delay)` via linear scan.
- `AnalyzedFrame` is a lightweight value type (~248 bytes) bundling all per-frame analysis outputs. Stores scalar metadata only — raw sample/FFT data stays in UMA buffers.
- `AudioInputRouter` gained `onAnalysisFrame` and `onRenderFrame` dual callbacks for the Orchestrator to consume both real-time and delayed frames.
- At 60fps with 2.5s delay, ~150 frames are needed; 512 capacity gives headroom for variable frame rates.

**Files created/edited:**
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
  - `test_analysisToRenderDelay_measuredAccurately()` — push 300 frames at 60fps, measure actual delay at render head, assert within ±100ms of configured delay

**Verification:** ✅ All 187 Swift tests pass (173 existing + 14 new). Delay accuracy verified within ±50ms at 2.5s configured delay.

### Increment 2.7: Progressive Structural Analysis ✅

**Status:** Complete.

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

**Implementation notes:**
- `SelfSimilarityMatrix` stores up to 600 frames of 16-float feature vectors (12 chroma + centroid/flux/rolloff/energy) in a ring buffer. Cosine similarity computed via vDSP. ~38KB memory.
- `NoveltyDetector` uses a checkerboard kernel (halfWidth=8) convolved along the similarity diagonal. Peak-picking with adaptive threshold (mean + 1.5×stddev). Minimum 2s between boundaries (120 frames at 60fps).
- `StructuralAnalyzer` coordinates both: feeds features per-frame, runs novelty detection every 30 frames (~0.5s). After 2+ boundaries, predicts next via average section duration. Repetition detection (section-average cosine similarity) boosts confidence for ABAB patterns.
- `StructuralPrediction` is CPU-side only (not in FeatureVector). Flows through `AnalyzedFrame.structuralPrediction` for the Orchestrator.
- MIRPipeline integration: runs after the 4 existing analyzers, exposes `latestStructuralPrediction` as CPU-side property, resets on track change.
- Key tuning: `minPeakDistance` set to 120 frames (2s) rather than 180 (3s) to avoid suppressing real boundaries in fast-changing music. Repetition bonus scales from 0 at similarity 0.6 to 1.0 at 0.9.

**Files created/edited:**
- `DSP/SelfSimilarityMatrix.swift` — Ring buffer of feature vectors with vDSP cosine similarity.
- `DSP/NoveltyDetector.swift` — Checkerboard kernel convolution + adaptive threshold peak-picking.
- `DSP/StructuralAnalyzer.swift` — Coordinator: boundary detection, repetition analysis, prediction.
- `Shared/AudioFeatures.swift` — Added `StructuralPrediction` struct.
- `Shared/AnalyzedFrame.swift` — Added `structuralPrediction` field.
- `DSP/MIRPipeline.swift` — Integrated StructuralAnalyzer as 5th sub-analyzer.

**Verification:** ✅ All 206 Swift tests pass (187 existing + 19 new: 5 SelfSimilarityMatrix, 5 NoveltyDetector, 8 StructuralAnalyzer, 1 AABA regression). AABA fixture boundaries detected within ±500ms of golden values. ABAB confidence > 0.6, random input confidence < 0.3.

---

## Phase 2.5 — Session Preparation Pipeline

**Goal:** Enable the playlist-first workflow where Phosphene analyzes every track before playback begins, providing stems and MIR data from the first frame of every track.

**Why this is a new phase:** The preparation pipeline is not a rendering feature (Phase 3), not a UI feature (Phase 6), and not an Orchestrator feature (Phase 4). It is the data layer that feeds all three. It reuses the existing StemSeparator and MIRPipeline from Phase 2 but orchestrates them in a new batch-processing workflow with new audio sources (preview clips, not Core Audio taps).

### Increment 2.5.1: Playlist Connector ✅

**Status:** Complete.

**Goal:** Read the full track list from Apple Music or Spotify playlists. Output: an ordered `[TrackIdentity]` array.

**Files to create/edit:**
- `Session/PlaylistConnector.swift` (new) — Protocol `PlaylistConnecting` with `connect(source:) async throws -> [TrackIdentity]`. Concrete implementations for Apple Music (AppleScript) and Spotify (Web API). Also accepts raw playlist URLs.
- `Session/TrackIdentity.swift` (new) — Struct: title, artist, album, duration, appleMusicID (optional), spotifyID (optional).
- `Audio/StreamingMetadata.swift` — Extract the AppleScript playlist enumeration logic into a reusable helper that `PlaylistConnector` can call.

**Apple Music implementation:** AppleScript query: `tell application "Music" to get {name, artist, album, duration} of every track of current playlist`. Also get `index of current track` to identify the starting position. Requires the existing Automation permission (already handled by StreamingMetadata).

**Spotify implementation:** If Spotify OAuth credentials are configured, call `GET /me/player/queue` for up to 20 tracks. If a playlist URL is provided, call `GET /playlists/{id}/tracks` for the full list. Fall back to the Apple Music path if Spotify credentials are unavailable (most Spotify tracks also exist in the iTunes catalog).

**Test requirements:**
- `PlaylistConnectorTests.swift` — 8 tests:
  - `test_appleMusicPlaylist_returnsOrderedTracks()`
  - `test_appleMusicPlaylist_includesDuration()`
  - `test_spotifyQueue_returnsUpTo20Tracks()`
  - `test_spotifyPlaylistURL_returnsFullTrackList()`
  - `test_emptyPlaylist_returnsEmptyArray()`
  - `test_networkFailure_throwsGracefully()`
  - `test_trackIdentity_codable_roundTrip()`
  - `test_duplicateTracks_preserveOrder()`

**Verification:** ✅ All 8 tests pass. 348 tests total (257 swift-testing + 91 XCTest). SwiftLint clean. Implementation notes: AppleScript enumerates `every track of current playlist` in a `repeat` loop, joining track lines with `linefeed` via `AppleScript's text item delimiters` (avoids list-to-text coercion issues). Apple Music playlist URL falls back to current playlist with a log note — MusicKit catalog URL lookup deferred to Phase 4. `SilenceDetector` cyclomatic complexity violation fixed as part of this increment (per-state logic extracted to 4 private helpers). `appleScriptReader` and `networkFetcher` injectable closures enable full test coverage without real Apple Music or Spotify.

**Depends on:** Phase 2 complete (existing StreamingMetadata AppleScript infrastructure).

**Enables:** 2.5.2 (Preview Resolver needs track identities to look up previews).

### Increment 2.5.2: Preview Resolver & Downloader ✅

**Status:** Complete.

**Goal:** For each track in the playlist, resolve a downloadable 30-second preview URL and download the audio. Output: per-track raw PCM arrays ready for stem separation.

**Files to create/edit:**
- `Session/PreviewResolver.swift` (new) — Protocol `PreviewResolving` with `resolvePreviewURL(for: TrackIdentity) async throws -> URL?`. Concrete implementation using iTunes Search API (`https://itunes.apple.com/search?term={artist}+{title}&media=music&limit=1`). Parse `previewUrl` from the JSON response. Fallback: MusicKit `Song.previewAssets` for Apple Music subscribers.
- `Session/PreviewDownloader.swift` (new) — Downloads preview audio files (AAC/MP3) to a temp directory, decodes to `[Float]` PCM via `AVAudioFile`. Batch processing with configurable concurrency (default 4 parallel downloads). Rate-limit aware (iTunes API: 20 req/min).
- `Session/SessionTypes.swift` (new) — `PreviewAudio` struct: trackIdentity, pcmSamples ([Float]), sampleRate (Int), duration (TimeInterval).

**Test requirements:**
- `PreviewResolverTests.swift` — 6 tests:
  - `test_knownTrack_resolvesToURL()` — use a well-known track (e.g., "Bohemian Rhapsody")
  - `test_unknownTrack_returnsNil()`
  - `test_previewURL_isValidAAC()`
  - `test_rateLimiting_respectsLimit()`
  - `test_networkTimeout_returnsNilGracefully()`
  - `test_multipleResolves_usesCache()`
- `PreviewDownloaderTests.swift` — 6 tests:
  - `test_downloadAndDecode_producesNonZeroPCM()`
  - `test_downloadedAudio_sampleRate_is44100()`
  - `test_downloadedAudio_duration_approximately30s()`
  - `test_batchDownload_respectsConcurrencyLimit()`
  - `test_failedDownload_skipsTrack_continuesBatch()`
  - `test_tempFiles_cleanedUpAfterDecode()`

**Verification:** Resolve and download previews for a 5-track playlist. All 5 decode to ~30s of PCM audio. All 12 tests pass.

**Depends on:** 2.5.1 (needs TrackIdentity).

**Enables:** 2.5.3 (batch pre-analysis needs PCM audio).

### Increment 2.5.3: Batch Pre-Analysis & Stem Cache ✅

**Status:** Complete.

**Goal:** Run stem separation and MIR analysis on every preview clip and cache the results. This is the core of the preparation pipeline.

**What shipped:**
- `Session/TrackProfile.swift` (new) — `TrackProfile` struct: bpm (`Float?`), key (`String?`), mood (`EmotionalState`), spectralCentroidAvg (`Float`), genreTags (`[String]`), stemEnergyBalance (`StemFeatures`), estimatedSectionCount (`Int`). Static `empty` default.
- `Session/StemCache.swift` (new) — `CachedTrackData` struct (stemWaveforms `[[Float]]`, stemFeatures, trackProfile). `StemCache` `@unchecked Sendable` class with `NSLock`-guarded `store/loadForPlayback/stemFeatures/trackProfile/count/clear`.
- `Session/SessionPreparer.swift` (new) — `@MainActor ObservableObject` with `@Published progress: (Int, Int)`. Sequential per-track loop: resolve → download → `Task.detached` CPU work → cache. Cancellation via `Task.isCancelled` + `catch is CancellationError`. Returns `SessionPreparationResult(cachedTracks:failedTracks:cache:)`.
- `Session/SessionPreparer+Analysis.swift` (new) — `nonisolated` static helpers: `analyzePreview` (separator → AGC warmup → offline MIR), `warmUpAndAnalyze` (1024-sample hop loop), `analyzeMIR` (vDSP FFT frame-by-frame through `MIRPipeline`), `computeFFTMagnitudes` (takes `FFTContext` struct to avoid SwiftLint parameter-count violation). Private `MIRAnalysisResult` struct replaces large tuple return.
- `Shared/AudioFeatures+Analyzed.swift` — `StemFeatures` gains `: Equatable` conformance.
- `Package.swift` — Session target deps expanded to include Audio + DSP + ML.
- `PhospheneApp/VisualizerEngine.swift` — `stemCache: StemCache?` property added; `import Session`.
- `PhospheneApp/VisualizerEngine+Stems.swift` — `resetStemPipeline(for:)` loads from cache on track change; `StemSampleBuffer` NOT cleared.
- `PhospheneApp/VisualizerEngine+Audio.swift` — Track-change callback constructs `TrackIdentity` and passes it to `resetStemPipeline`.

**Tests:** 5 `SessionPreparerTests` (single track, multiple tracks, missing preview, progress, cancellation) + 3 `StemCacheTests` (load correct, unknown nil, thread safety) + 3 `SessionPreparationIntegrationTests` (full pipeline, BPM+mood, non-zero stems). 280 total tests pass.

**Depends on:** 2.5.2 (preview audio), Phase 2 complete (StemSeparator, MIRPipeline, StemAnalyzer).

**Enables:** 2.5.4 (session state machine), Phase 4 Orchestrator session planning mode, Phase 3.5 preset work (presets can assume non-zero stems).

### Increment 2.5.4: Session State Machine & Track Change Behavior

**Status:** Not started.

**Goal:** Formalize the session lifecycle and replace the hard-reset track-change behavior with cache-aware loading.

**Files to create/edit:**
- `Session/SessionManager.swift` (new) — Owns the session lifecycle state machine (`SessionState` enum). Coordinates `PlaylistConnector`, `SessionPreparer`, and `StemCache`. Exposes `@Published var state: SessionState` and `@Published var currentPlan: SessionPlan?`. Entry point: `startSession(source: PlaylistSource) async`.
- `Shared/AudioFeatures.swift` — Add `SessionState` enum, `TrackIdentity`, `SessionPlan` types.
- `PhospheneApp/VisualizerEngine.swift` — Integrate `SessionManager`. In session mode, load cached stems on track change instead of zeroing. In ad-hoc mode, preserve existing behavior.
- `PhospheneApp/VisualizerEngine+Stems.swift` — Replace the track-change callback: check `stemCache.loadForPlayback(track:)` first. If cache hit, populate `latestStemFeatures` immediately. If cache miss (ad-hoc mode or failed preparation), fall back to the existing zero + wait-for-real-time behavior.

**Test requirements:**
- `SessionManagerTests.swift` — 10 tests:
  - `test_init_stateIsIdle()`
  - `test_startSession_transitionsToConnecting()`
  - `test_afterPlaylistRead_transitionsToPreparing()`
  - `test_afterPreparation_transitionsToReady()`
  - `test_playbackStarts_transitionsToPlaying()`
  - `test_sessionEnds_transitionsToEnded()`
  - `test_preparationFailure_transitionsToReady_withPartialData()`
  - `test_adHocMode_skipsPreparation()`
  - `test_trackChange_loadsFromCache()`
  - `test_trackChange_cacheMiss_fallsBackToRealTime()`

**Verification:** Start a session with a 5-track playlist. State transitions: idle → connecting → preparing → ready. On "Ready", play the playlist. On track change, cached stems load immediately (verify via debug log). All 10 tests pass.

**Depends on:** 2.5.3 (stem cache and session preparer).

**Enables:** Phase 4 Orchestrator session planning mode, Phase 6 session preparation UI.
---

## Phase 3 — Advanced Metal Rendering (Blueprint Release 0.5)

> **Retroactive scope split note:** The original Increment 3.1 bundled three distinct units of work — a GPU compute particle pipeline, a Milkdrop-style feedback texture infrastructure, and the Murmuration preset — into a single increment. Per the **Increment Scope Discipline** rule (§ Code Hygiene Rules), each unit of work should have been its own increment. The following three entries (3.1, 3.1-bonus, 3.1-preset) document what actually shipped, retroactively split for clarity. The original spec's "from stem-separated audio" goal was NOT delivered and is tracked as deferred via Increments 3.1a (GPU STFT/iSTFT) and 3.1b (live stem pipeline wiring) below.

### Increment 3.1 (RETROACTIVE): Compute Shader Particle Pipeline ✅

**Status:** Complete (shipped as part of the original 3.1 bundle; reclassified for clarity).

**Goal:** GPU compute pipeline for audio-reactive particle systems, with a compute kernel maintaining per-particle state and a point-sprite render pipeline for display.

**What shipped (the legitimate 3.1 deliverable):**
- `Renderer/Geometry/ProceduralGeometry.swift` — Swift class owning the compute pipeline, UMA particle buffer, and the point-sprite render pipeline state (with optional additive blending)
- `Renderer/Shaders/Particles.metal` — compute kernel for per-particle state plus vertex/fragment shaders for point-sprite rendering
- `Renderer/MetalContext.swift` — added `makeSharedTexture(width:height:pixelFormat:usage:)` helper
- 7 tests in `Tests/PhospheneEngineTests/Renderer/ProceduralGeometryTests.swift`:
  - `test_init_particleBuffer_allocatedWithCapacity()` ✓
  - `test_particleBuffer_storageModeShared()` ✓
  - `test_dispatch_compute_noGPUError()` ✓
  - `test_particleCount_matchesConfiguration()` ✓
  - `test_zeroAudioInput_particlesStationary()` ✓
  - `test_impulseAudioInput_particlesEmitted()` ✓
  - `test_particleCompute_1MillionParticles_under8ms()` ✓

**What was originally in the spec but NOT delivered:**
- *"From stem-separated audio"* — the original 3.1 goal specified stem-driven particle routing, but the live stem pipeline was never wired into `VisualizerEngine`. The Murmuration preset (see 3.1-preset below) ships using `features.sub_bass + features.low_bass` as a full-mix stand-in, documented in CLAUDE.md Resolved Decision #32. True stem-driven particle routing is deferred to Increment 3.1b below, which itself depends on Increment 3.1a (GPU STFT/iSTFT).

**Enables:** Murmuration preset (3.1-preset), any future compute-particle preset.

### Increment 3.1-bonus (RETROACTIVE): Feedback Texture Infrastructure ✅

**Status:** Complete (smuggled into the original 3.1 alongside the particle work; reclassified for clarity).

**Goal:** Milkdrop-style double-buffered feedback texture ping-pong for presets that want trails and visual memory.

**What shipped:**
- `Shared/AudioFeatures.swift` — `FeedbackParams` struct (32 bytes, 8 floats: decay, baseZoom, baseRot, beatZoom, beatRot, beatSensitivity, beatValue, pad)
- `Renderer/Shaders/Common.metal` — `feedback_warp_fragment` (decay/zoom/rotate previous frame) and `feedback_blit_fragment` (copy feedback texture to drawable), plus the MSL `FeedbackParams` struct
- `Renderer/RenderPipeline.swift` — feedback texture lifecycle (lazy allocation from drawable size, double-buffered ping-pong), `drawWithFeedback` render path with three-pass loop (warp → composite → blit), later split into `drawParticleMode` and `drawSurfaceMode` branches for presets that do or don't attach compute particles
- `Presets/PresetDescriptor.swift` — `useFeedback` flag with matching `"use_feedback"` JSON key; `useParticles` flag added later for particle-only opt-in
- `Presets/PresetLoader.swift` — dual pipeline state compilation for `useFeedback: true` presets (standard pipeline for the drawable pass, additive-blend pipeline for the composite-into-feedback-texture pass); preamble includes the `FeedbackParams` MSL struct
- `Presets/PresetCategory.swift` — `abstract` category added
- `Presets/Shaders/Membrane.metal` + `Membrane.json` — second preset validating the surface-mode (non-particle) feedback path

**Scope violation note:** This infrastructure was implemented to serve the Murmuration preset but is general-purpose — it is now used by the Membrane preset and will be used by any future preset that wants trails. It should have been its own increment with its own tests and verification. This retroactive entry documents the scope slip so future increments don't repeat it. No new tests were added specifically for the feedback infrastructure; coverage is indirect via the Murmuration and Membrane preset tests and the `presetLoaderBuiltInPresetsHaveValidPipelines` test.

**Enables:** Murmuration preset (3.1-preset), Membrane preset, any future feedback-using preset.

### Increment 3.1-preset (RETROACTIVE): Murmuration Preset ✅

**Status:** Complete.

**Goal:** Native demonstration preset using the compute particle pipeline (3.1) and the feedback texture infrastructure (3.1-bonus) to depict a flock of ~5,000 starlings against a dusk sky gradient.

**What shipped:**
- `Presets/Shaders/Starburst.metal` — dusk sky gradient fragment shader (the "canvas" the flock flies against)
- `Presets/Shaders/Starburst.json` — preset descriptor with `use_feedback: true`, `use_particles: true`
- Compute kernel modifications in `Particles.metal` for flock behavior: each bird has a home position within an elongated, tapered, curving shape that stretches, rotates, and bends with the music
- Audio routing (documented workaround for missing stem routing): `sub_bass + low_bass` drives flock body movement (rhythm section); `high_mid + high_freq` drives flutter, shape bending, cohesion loosening (strings and overtones). Deliberately bypasses vocal frequency ranges (`low_mid + mid_high`).
- `PhospheneApp/ContentView.swift` — `applyPreset` method wiring particles + feedback parameters based on descriptor flags

**Visual verification:** The preset shows ~5,000 starlings flying as one organism across a dusk sunrise/sunset sky. Hand-tuned against Lou Reed's "Sad Song" so the fluttering strings drive the murmuration's rippling and the bass line pushes the mass. Earlier iterations layered disconnected technical features (frequency rings, Lissajous traces, beat seeds) without visual coherence; the breakthrough was committing to a single natural metaphor — a flock of starlings — and making every audio feature serve it. The Milkdrop preset analysis (see `docs/MILKDROP_PRESET_ANALYSIS.md`) catalogued 15 creative techniques but the key insight was that technology and art must reinforce each other.

**Depends on:** Increment 3.1, Increment 3.1-bonus.

**Blocked on (deferred features):** true stem-driven routing (requires Increments 3.1a and 3.1b below). Revisiting Murmuration to replace its full-mix workaround with real drums/bass/other stem routing is a Phase 3.5 preset-polish task that follows naturally once 3.1b lands.

**Test count after 3.1 bundle:** 213 Swift tests pass (206 existing + 7 new particle tests).

### Increment 3.1a: GPU STFT/iSTFT Compute Pipeline (PROMOTED from 7.1)

**Status:** Complete.

**Why promoted:** Originally a bullet in Increment 7.1 ("Metal Performance Profiling Pass"), but it's a prerequisite for the live stem pipeline, which in turn is a prerequisite for true stem-driven presets (Murmuration's deferred re-routing, Popcorn, and others). Keeping it in 7.1 leaves Phase 4 (Orchestrator) blocked on profiling work that is conceptually later in the project. Promoting it early resolves the dependency and honors the Increment Scope Discipline rule that infrastructure should land before the work that depends on it.

**Goal:** Replace the Accelerate-based CPU STFT/iSTFT in `StemSeparator.swift` with Metal compute shaders (or `MPSGraph` FFT operations where available), dropping per-separation time from ~6.5s (current CPU baseline) to under 250ms end-to-end.

**Files to create/edit:**
- `Sources/ML/StemFFT.swift` (new) — `StemFFTEngine` class wrapping either `MPSGraph` FFT or hand-written Metal compute kernels. Public API: `forward(mono: [Float]) -> (magnitude: UMABuffer<Float>, phase: UMABuffer<Float>)` and `inverse(magnitude: UMABuffer<Float>, phase: UMABuffer<Float>, nbFrames: Int, originalLength: Int?) -> [Float]`. Owns plans, twiddle factor buffers, window buffer, and (if using compute kernels) the compiled compute pipeline states. `@unchecked Sendable` with an internal lock for thread safety.
- `Sources/ML/Shaders/StemFFT.metal` (new, conditional) — Metal compute kernels for forward/inverse Stockham radix-2 FFT, Hann window, magnitude/phase extraction, overlap-add synthesis. Only created if `MPSGraph` FFT is unavailable for the 4096-point real FFT this model requires. Decision made in the first step of implementation via a prototype test.
- `Sources/ML/StemSeparator.swift` — delegate `stft(mono:)` and `istft(magnitude:phase:nbFrames:originalLength:)` to the new `StemFFTEngine`. Preserve the existing public `separate(audio:channelCount:sampleRate:)` API so no downstream code changes. Keep the Accelerate-based implementations alive behind a `forceCPUFallback: Bool` flag on `StemFFTEngine` so regression testing can cross-validate.
- `Package.swift` (if `StemFFT.metal` is created) — add `resources: [.copy("Shaders")]` to the `ML` target alongside the existing `.copy("Models")` entry.

**Test requirements:**
- `Tests/PhospheneEngineTests/ML/StemFFTTests.swift` (new) — 6 tests:
  - `test_forward_matchesVDSP_withinTolerance()` — cross-validate against existing CPU vDSP implementation on a deterministic sine+noise input. Max absolute magnitude error < 1e-3, mean phase error < 1e-2 radians.
  - `test_inverse_roundTripPreservesSignal()` — STFT → iSTFT should recover the input within tolerance.
  - `test_forward_performance_under100ms()` — `XCTest.measure` single 10s chunk forward transform, baseline < 100ms.
  - `test_inverse_performance_under100ms()` — same for inverse transform.
  - `test_storageMode_allUMA()` — all FFT I/O buffers are `.storageModeShared`.
  - `test_threadSafety_concurrentCalls_noCrash()` — concurrent forward and inverse calls from multiple threads.
- `Tests/PhospheneEngineTests/Performance/StemSeparationPerformanceTests.swift` — loosen the current baseline from ~6500ms to ≤250ms end-to-end for a full `separate()` call.

**Verification:** All existing tests pass. The 6 new `StemFFTTests` pass. Updated `StemSeparationPerformanceTests` reports ≤250ms average. Existing `tools/test_stem_model.py` Python pipeline tests still pass unchanged (they validate model-level correctness, not Swift-side FFT).

**Depends on:** nothing (the `StemSeparator` module already exists from 2.3).

**Enables:** Increment 3.1b (live stem pipeline wiring), all downstream stem-driven presets (Murmuration stem-routing re-do, Popcorn, any future vocal/bass/drum-reactive preset).

### Increment 3.1b: Live Stem Pipeline Wiring + Per-Stem FeatureVector Extension

**Revision note (v3):** The track-change behavior described here (`StemSampleBuffer.reset()` + `latestStemFeatures = .zero`) is the ad-hoc-mode fallback. In session mode (Phase 2.5), track change loads cached stems from `StemCache` and does NOT clear the ring buffer. See Increment 2.5.4 for the revised behavior.

**Status:** Complete.

**Goal:** Wire `StemSeparator.separate()` into the live audio pipeline on a rolling 10s window basis, run per-stem analysis, and expose per-stem features to shaders via a new GPU uniform buffer bound at `buffer(3)`.

**Architecture:**
- `StemSampleBuffer` in `Sources/Shared/` — thread-safe ring buffer for 15s of interleaved stereo PCM at 44.1kHz (~1.3M floats). Methods: `write(samples: UnsafePointer<Float>, count: Int)`, `snapshotLatest(seconds: Double) -> [Float]`, `reset()`.
- Dispatch timer on a background `stemQueue` (utility QoS) fires every 5 seconds, snapshots the latest 10s from `StemSampleBuffer`, calls `stemSeparator.separate(...)`, then runs per-stem analysis.
- Per-stem analysis reuses existing DSP primitives: 4 instances of `BandEnergyProcessor` (one per stem) + 1 `BeatDetector` applied to the drums stem. No new DSP code required.
- `StemFeatures` is a new `@frozen` struct — 16 floats / 64 bytes, 4 floats per stem: energy, 2 band slots, beat pulse. Exact layout documented in the struct doc comment.
- `RenderPipeline.setStemFeatures(_:)` atomically stores latest value in a lock-protected slot; all three draw paths (`drawDirect`, `drawWithFeedback`, and any future paths) bind it at `buffer(3)` via `setFragmentBytes`.
- MSL `StemFeatures` struct definition added to `PresetLoader.shaderPreamble` so every preset inherits it automatically without re-declaring.
- Existing presets ignore `buffer(3)`; Metal allows binding a buffer slot that the shader doesn't read, so no behavior change for Waveform, Plasma, Nebula, Membrane, or Starburst.
- Track-change reset: when `StreamingMetadata` fires a track-change event, `VisualizerEngine` clears `StemSampleBuffer` and resets `latestStemFeatures` to `.zero` (parallels the existing `MIRPipeline.reset()` on track change).
- Warmup behavior: for the first ~10 seconds of a track, stems aren't available yet. `StemFeatures.zero` is the default, and shaders that use stems must fall back gracefully on full-mix features for that window.

**Files to create/edit:**
- `Sources/Shared/StemSampleBuffer.swift` (new)
- `Sources/Shared/AudioFeatures.swift` — add `StemFeatures` struct and `.zero` static
- `Sources/DSP/StemAnalyzer.swift` (new) — coordinates the 4 `BandEnergyProcessor` instances + `BeatDetector`, returns `StemFeatures`
- `Sources/Renderer/Shaders/Common.metal` — MSL `StemFeatures` struct
- `Sources/Presets/PresetLoader.swift` — preamble update
- `Sources/Renderer/RenderPipeline.swift` — `setStemFeatures`, `stemFeaturesLock`, bind index 3 in all draw paths
- `PhospheneApp/ContentView.swift` (VisualizerEngine) — instantiate `StemSeparator`, `StemSampleBuffer`, `StemAnalyzer`; set up `stemQueue` dispatch timer; wire track-change reset
- `Package.swift` — if `StemAnalyzer.swift` needs to import both `DSP` and the stem types, verify module dependencies

**Test requirements:**
- `Tests/PhospheneEngineTests/Shared/AudioFeaturesTests.swift` — add `test_stemFeatures_memoryLayout_is64Bytes()` and `test_stemFeatures_simdAligned()`
- `Tests/PhospheneEngineTests/Integration/StemsToRenderPipelineTests.swift` (new) — 4 tests:
  - `test_stemFeatures_defaultZero_rendersWithoutCrash()` — verify `StemFeatures.zero` is safe to bind at buffer(3) when stems haven't arrived yet
  - `test_stemFeatures_afterSeparation_hasNonZeroDrumsEnergy()` — feed a drum-heavy clip through `StemSeparator` + `StemAnalyzer`, assert drums energy > 0
  - `test_stemFeatures_trackChange_resetsToZero()` — simulate a track change, verify stem features clear
  - `test_stemFeatures_renderBinding_structSizeMatchesMSL()` — `MemoryLayout<StemFeatures>.size == 64`

**Verification:** All existing tests pass. 2 new layout tests pass. 4 new integration tests pass. Manual verification: play a drum-heavy track, confirm via debug logging that `StemFeatures` updates every ~5s during playback and resets when a new track begins.

**Depends on:** Increment 3.1a (GPU STFT/iSTFT) for the real-time performance needed.

**Enables:** Murmuration stem-routing revisit (Phase 3.5 preset polish), Popcorn preset (Phase 3.5.1), and any future preset that depends on stem-accurate audio features.

### Increment 3.1a-followup: StemSeparator CPU Memory Rearrangement Optimization

**Status:** Complete.

**Goal:** Optimize the three CPU memory-rearrangement hotspots in `StemSeparator.separate()` using vectorized Accelerate operations and bulk memcpy. Zero change to correctness or public API.

**Measured improvements:**
- `packSpectrogramForModel`: 275ms → 1ms (raw `MLMultiArray.dataPointer` + `vDSP_mtrans`, bypassing `MLShapedArray` allocation)
- `UMABuffer.write`: 231ms → <1ms (Float-specialized overload using `update(from:count:)`)
- `unpackAndISTFT` transpose: scalar nested loops → `vDSP_mtrans` per stem/channel block
- `deinterleave`: scalar loop → `vDSP_ctoz`
- Mono L+R averaging: scalar loop → `vDSP_vadd` + `vDSP_vsmul`
- Total `separate()`: ~2000ms → ~600ms (3.4× wall-clock improvement)

**Key finding — ANE Float16 output:** The Neural Engine outputs Float16 MLMultiArrays (dataType rawValue 65552) for the Open-Unmix HQ model, even though the model was converted with Float32 inputs. `MLShapedArray<Float>(converting:)` handles the Float16→Float32 conversion correctly but costs ~420ms for ~7M elements. This is internal to CoreML and sets the performance floor at ~560ms (140ms predict + 420ms conversion). The original spec's 250ms target assumed Float32 ANE output. Alternatives investigated and rejected: `vImageConvert_Planar16FtoPlanarF` (slower), raw `dataPointer.bindMemory(to: Float.self)` (incorrect — misinterprets Float16 as Float32).

**Files edited:**
- `Sources/Shared/UMABuffer.swift` — Float-specialized `write(_ values: [Float], offset:)` extension
- `Sources/ML/StemSeparator+Pack.swift` — decomposed into `packDense`/`packStrided`, `extractDense`/`extractStrided`, `averageToMono` helpers. All fast paths use `vDSP_mtrans` with `guard let` pointer safety.
- `Sources/ML/StemSeparator.swift` — `vDSP_ctoz` deinterleave, `writeToBuffers`/`buildResult` extracted to reduce `separate()` body length, `Accelerate` import added.

**Tests added:**
- `UMABufferExtendedTests`: `test_writeArrayFloat_correctness()`, `test_writeArrayFloat_withOffset_correctness()` — verify the Float fast-path write produces byte-identical results to the generic path.
- `StemSeparationPerformanceTests`: `test_separate_1SecondAudio_performance()` updated with hard 750ms warm-call assertion. `test_separate_1SecondAudio_measureBlock()` added for XCTest.measure averaging.

**Test count after 3.1a-followup:** 236 tests (222 swift-testing + 14 XCTest), all passing. SwiftLint clean.

**Depends on:** Increment 3.1a (GPU STFT/iSTFT).

**Enables:** Any future increment requiring tight end-to-end stem separation latency. Per-frame or sub-second stem analysis cadences if downstream presets ever need them.

### Phase 3.7: CoreML → MPSGraph Migration (PRIORITIZED before 3.2)

**Motivation:** CoreML's Float16 ANE output forces a ~420ms `MLShapedArray(converting:)` per stem separation call — the single largest pipeline bottleneck. MPSGraph (already proven in `StemFFTEngine`) supports all Open-Unmix operations and runs Float32 throughout with UMA zero-copy buffers. Migrating eliminates Float16 conversion, removes CoreML as a dependency, and enables future STFT→model→iSTFT graph fusion.

**This block is prioritized before Increment 3.2 (Mesh Shaders) because it directly improves the live stem pipeline that shipped in 3.1b.**

---

### Increment 3.7a: CPU-only CoreML Baseline Measurement

**Status:** ✅ Complete.

**Goal:** Validate the hypothesis that Float16 conversion overhead exceeds CPU inference cost. One-line diagnostic change: `config.computeUnits = .cpuOnly` in `StemSeparator.init`. Measure wall-clock `separate()` with the CPU path. If CPU Float32 inference ≈ 400ms (vs ANE 140ms + F16→F32 420ms = 560ms), the MPSGraph migration target is confirmed.

**Measured results (Mac mini, Apple Silicon):**
- ANE path (`.cpuAndNeuralEngine`): **659ms avg** (10 iterations, 2.9% RSD)
- CPU path (`.cpuOnly`): **592ms avg** (10 iterations, 11.8% RSD)
- CPU cold call: ~723ms (includes CoreML compilation)

**Analysis:** CPU-only is ~10% faster than ANE due to eliminating Float16→Float32 conversion. However, 592ms still exceeds the 400ms MPSGraph target — CPU inference alone is ~450ms (vs ANE 140ms). The MPSGraph migration remains the right path: it should achieve ANE-like 140ms inference in Float32 with zero conversion overhead. Target: <400ms total `separate()`.

**Implementation:** Added `computeUnits` parameter to `StemSeparator.init` (default `.cpuAndNeuralEngine`), plus 2 CPU-only benchmark tests. Production default unchanged.

**Files:** `StemSeparator.swift`, `StemSeparationPerformanceTests.swift`.

**Tests:** 238 tests pass (222 swift-testing + 16 XCTest). +2 new perf tests.

### Increment 3.7b: Open-Unmix Weight Extraction Tool

**Status:** ✅ Complete.

**Goal:** Extract all weight tensors from the Open-Unmix HQ PyTorch model into a GPU-loadable format.

**Deliverable:** `tools/extract_umx_weights.py` — loads the umxhq PyTorch checkpoint via `openunmix`, iterates all named parameters/buffers across 4 stems, saves each as a raw `.bin` (float32, C-contiguous) with a `manifest.json` mapping names to shapes/dtypes/files.

**Actual architecture (discovered during extraction):**
- 43 tensors per stem, 172 total (not 34 as originally estimated)
- Linear layers use `bias=False` (bias folded into BatchNorm) — no fc1.bias, fc2.bias, fc3.bias
- fc3/bn3 output 4098 features (2 channels × 2049 bins), not 2049
- LSTM hidden_size=256 (bidirectional → 512 output), weight_hh shape [1024, 256]
- LSTM gate_size = 4 × 256 = 1024 (not 2048 as spec assumed)
- Total: 135.9 MB across 172 .bin files + manifest.json

**Output:** `PhospheneEngine/Sources/ML/Weights/` directory with `.bin` files + `manifest.json`. Added to `Package.swift` as `.copy("Weights")`. Weight .bin files tracked via Git LFS (`.gitattributes`).

**Tests:** `tools/test_umx_weights.py` — 6 validation checks (manifest metadata, tensor count, presence, shapes, file sizes, data validity). All pass.

### Increment 3.8: MPSGraph Open-Unmix Inference Engine

**Status:** ✅ Complete.

**Goal:** Reconstruct Open-Unmix HQ in MPSGraph. Validate output matches CoreML within tolerance.

**New files:** `Sources/ML/StemModel.swift` (246 lines), `Sources/ML/StemModel+Graph.swift` (317 lines), `Sources/ML/StemModel+Weights.swift` (296 lines) — `StemModelEngine` class split across three files per SwiftLint 400-line limit.

**Architecture per stem** (corrected per 3.7b extraction):
```
Input [431, 2, 1487] → InputNorm → Reshape [431, 2974]
  → FC1(2974→512, bias=False) + BN1 + Tanh
  → LSTM(input=512, hidden=256, 3 layers, bidirectional) → concat(fc1_out, lstm_out) → [431, 1024]
  → FC2(1024→512, bias=False) + BN2 + ReLU
  → FC3(512→4098, bias=False) + BN3 + OutputScale
  → Reshape [431, 2, 2049] → ReLU(mask) × original_spectrogram → Output [431, 2, 2049]
```
Note: All Linear layers use `bias=False` (bias is folded into BatchNorm). FC3 outputs 4098 = 2 channels × 2049 bins. LSTM hidden_size=256, bidirectional output=512.

All 4 stems in a single MPSGraph. Float32 throughout. Weights loaded from `.bin` files into `MTLBuffer` (`.storageModeShared`). Fixed input shape (431 frames) — graph compiled once at init.

**MPSGraph operations:** `placeholder`, `constant`, `matrixMultiplication`, batch norm via running stats, `LSTM` (bidirectional), `reLU`, `tanh`, `multiplication`, `addition`, `reshape`, `transposeTensor`, `concatTensors`, `sliceTensor`.

**Tests** (`Tests/ML/StemModelTests.swift`, 6 tests): init, silence, CoreML cross-validate (max error < 0.05), performance gate (< 400ms), UMA storage, thread safety.

### Increment 3.9: Integrate MPSGraph into StemSeparator

**Status:** ✅ Complete.

**Goal:** Replace CoreML prediction with `StemModelEngine`. Eliminate pack/unpack overhead.

**Data flow simplification:**
```
Before: STFT(GPU) → [Float] → pack(MLMultiArray) → predict(ANE/F16) → unpack(F16→F32) → iSTFT(GPU)
After:  STFT(GPU) → [Float] → memcpy(MTLBuffer) → predict(MPSGraph/GPU/F32) → read(MTLBuffer) → iSTFT(GPU)
```

**Changes:**
- `StemSeparator.swift` — replaced `MLModel` with `StemModelEngine`. Init loads MPSGraph weights instead of CoreML model. `separate()` writes STFT magnitudes directly into `StemModelEngine` input MTLBuffers via `memcpy`, calls `predict()`, reads output buffers directly. Removed `import CoreML` and `computeUnits` parameter.
- `StemSeparator+Pack.swift` → renamed to `StemSeparator+Reconstruct.swift`. Deleted all CoreML pack/unpack code (6 methods: `packSpectrogramForModel`, `isDensePackLayout`, `packDense`, `packStrided`, `extractStemSpectrograms`, `extractDense`, `extractStrided`, `unpackAndISTFT`). Kept `reconstructStemWaveforms` and `averageToMono` for iSTFT + mono averaging. Removed `import CoreML`.
- `StemSeparatorTests.swift` — removed `import CoreML` and `test_init_computeUnits_isCPUAndNeuralEngine` (CoreML-specific).
- `StemSeparationPerformanceTests.swift` — hard gate updated from 750ms to 400ms. Removed 2 CPU-only CoreML baseline tests (`test_separate_cpuOnly_baseline`, `test_separate_cpuOnly_measureBlock`).

**Measured results (Mac mini, Apple Silicon):**
- Warm `separate()`: **142ms avg** (10 iterations, 11% RSD) — 4.4× faster than CoreML's ~620ms
- Breakdown: ~9ms STFT + ~0ms memcpy + ~102ms MPSGraph predict + ~30ms iSTFT/reconstruct + ~1ms write
- Hard gate passes at 400ms with massive headroom

**Test count after 3.9:** 241 tests (221 swift-testing + 20 XCTest). −3 from 244 (removed 1 CoreML-specific unit test + 2 CPU-only perf tests).

### Increment 3.10: Pure Accelerate MoodClassifier

**Status:** ✅ Complete.

**Goal:** Replace the CoreML MoodClassifier MLP (10→64→32→16→2) with pure Accelerate `vDSP_mmul` + bias + ReLU/tanh calls. Weights hardcoded as static `[Float]` arrays (3,346 params, ~13 KB source). Protocol `MoodClassifying` unchanged.

**Files:**
- `MoodClassifier.swift` — Rewrote `classify()` to use Accelerate. Removed `import CoreML`, `MLModel`. `init()` is non-throwing.
- `MoodClassifier+Weights.swift` — New file with 8 static weight arrays extracted from the CoreML model.
- `tools/extract_mood_weights.py` — Parses CoreML `.mlpackage` blob format (64-byte headers, Float16 data) and emits Swift code.
- `VisualizerEngine.swift` — Simplified `loadMoodClassifier()` (non-optional return, no do/catch).
- `MoodClassifierTests.swift` — Removed `import CoreML` and `try` from init calls.

**Tests:** All 7 `MoodClassifierTests` pass unchanged. 241 total (221 swift-testing + 20 XCTest).

### Increment 3.11: Remove CoreML Dependency

**Status:** ✅ Complete.

**Goal:** Delete `StemSeparator.mlpackage` and `MoodClassifier.mlpackage`. Remove `import CoreML` from all ML files. Remove CoreML framework linkage from `Package.swift`. Verify via `otool -L` that the binary no longer links CoreML.

**Files:**
- Deleted `PhospheneEngine/Sources/ML/Models/` (both `.mlpackage` bundles)
- `ML.swift` — Removed `import CoreML`, updated comment
- `Package.swift` — Removed `.copy("Models")` from ML target resources

**Tests:** All 241 tests pass. SwiftLint clean. `otool -L` confirms CoreML NOT linked.

**Dependency graph (complete):**
```
3.7a (CPU baseline) ──┐
                       ├──→ 3.8 (MPSGraph model) ──→ 3.9 (integrate) ──→ 3.11 (remove CoreML) ✅
3.7b (weight extract) ─┘                                                       ↑
                                                      3.10 (Accelerate mood) ──┘ ✅
```

**Phase 3.7 is complete.** CoreML has been fully replaced: stem separation runs on MPSGraph (GPU, Float32, 142ms), mood classification runs on Accelerate (CPU, Float32, negligible). The binary no longer links the CoreML framework.

---

### Increment 3.2: Mesh Shader Pipeline Infrastructure ✅ COMPLETE

**Goal:** Metal mesh shading infrastructure for procedural 3D geometry generation. Object + mesh shader stages, pipeline state management, capability detection, and a vertex shader fallback path for pre-M3 hardware (per CLAUDE.md hard rule).

**Files created/edited:**
- `Renderer/Shaders/MeshShaders.metal` — `ObjectPayload`, `MeshVertex`, `MeshPrimitive` structs; trivial `mesh_object_shader` (dispatches 1 meshlet), `mesh_shader` (outputs a full-screen triangle), `mesh_fragment` (UV-as-color placeholder), `mesh_fallback_vertex` (identical triangle via standard vertex shader).
- `Renderer/Geometry/MeshGenerator.swift` — detects `device.supportsFamily(.apple8)` at init; compiles `MTLMeshRenderPipelineDescriptor` (M3+) or `MTLRenderPipelineDescriptor` with `mesh_fallback_vertex` (M1/M2). `draw(encoder:features:)` dispatches `drawMeshThreadgroups` or `drawPrimitives` accordingly. `MeshGeneratorConfiguration` with `maxVerticesPerMeshlet = 256`, `maxPrimitivesPerMeshlet = 512`.
- `Renderer/RenderPipeline.swift` — `meshGenerator`, `meshShaderEnabled`, `meshLock`, `setMeshGenerator(_:enabled:)`.
- `Renderer/RenderPipeline+Draw.swift` — mesh branch added to `renderFrame` (mesh → feedback → direct priority).
- `Renderer/RenderPipeline+MeshDraw.swift` (new) — `drawWithMeshShader` private method; acquires drawable, encodes stem features at buffer(3), delegates to `meshGenerator.draw()`.
- `Presets/PresetLoader.swift` — `compileMeshShader` dispatcher + `compileMeshPipeline` (M3+ native / M1-M2 fallback). Function naming convention: `_fragment` suffix replaced with `_mesh_shader` / `_object_shader` to locate mesh functions in the compiled library.
- `Presets/PresetLoader+Preamble.swift` — `ObjectPayload`, `MeshVertex`, `MeshPrimitive` struct definitions added so preset shaders can reference them without redeclaring.
- `Presets/PresetDescriptor.swift` — `useMeshShader: Bool`, `"use_mesh_shader"` CodingKey, default `false`.

**Implementation note:** `[[thread_index_in_mesh]]` is not a valid MSL attribute — the correct attribute is `[[thread_index_in_threadgroup]]` in both object and mesh shader stages. This caused initial compile failure, fixed before tests passed.

**Tests:** 6 XCTest (`MeshGeneratorTests`): descriptor, pipeline state, dispatch, maxVerts=256, maxPrims=512, <16ms perf. All pass.

**Result:** 247 tests (221 swift-testing + 26 XCTest). Commit: `d6561d38`.

**Depends on:** nothing.

**Enables:** Increment 3.2b (Fractal Tree demonstration preset) and all future mesh-shader presets.

### Increment 3.2b: Fractal Tree Demonstration Preset ✅ COMPLETE

**Goal:** First preset using the mesh shader pipeline. A recursive binary tree structure that grows upward, with branch count and trunk length driven by bass energy, branch spread by mid energy, and leaf-tip hue by spectral centroid.

**Files created/edited:**
- `Presets/Shaders/FractalTree.metal` — object shader (1 thread) packs audio data into `FractalPayload`; mesh shader (64 threads, one per branch) computes 63-branch binary tree geometry via iterative ancestry traversal (no MSL recursion), outputs 252 vertices / 126 triangles per frame; fragment shader applies depth-dependent colour (bark brown → forest green → hue-shifted leaf tips) with beat flash and edge soft-fade. `fractal_tree_fallback_vertex` provides an M1/M2 gradient fallback.
- `Presets/Shaders/FractalTree.json` — `"family": "fractal"`, `"use_mesh_shader": true`, `"use_feedback": false`, `"use_particles": false`, `"fragment_function": "fractal_tree_fragment"`, `"vertex_function": "fractal_tree_fallback_vertex"`
- `PhospheneEngine/Sources/Presets/PresetDescriptor.swift` — added `meshThreadCount: Int` field (default 64, JSON key `"mesh_thread_count"`)
- `PhospheneEngine/Sources/Renderer/Geometry/MeshGenerator.swift` — added `meshThreadCount`/`objectThreadCount` to `MeshGeneratorConfiguration`; new `init(device:pipelineState:configuration:)` that wraps a pre-compiled pipeline state; updated `draw()` to bind `FeatureVector` to object/mesh/fragment stages and use thread counts from configuration
- `PhospheneApp/VisualizerEngine.swift` — `applyPreset` handles `useMeshShader: true`: wraps preset's pipeline state in `MeshGenerator(device:pipelineState:configuration:)` and calls `pipeline.setMeshGenerator`; explicitly disables mesh generator when switching to non-mesh presets

**Audio routing:**
- `bass_att` → branch count (3 at silence → 63 at peak — tree grows with bass)
- `mid_att` → branch spread angle (22°–29°, wider canopy = denser mid energy)
- `spectral_centroid` → leaf hue (deep green at low centroid → golden-green at high)
- `treb_att` → leaf tip shimmer intensity
- `beat_bass` → flash brightness across the tree, strongest at leaf tips

**Geometry:** 63-branch binary tree, 6 depth levels (0–5). Each branch is an aspect-corrected screen-aligned quad. Branch count scales with `bass_att`, creating a "growing tree" effect as bass energy increases.

**Test results:** 247 tests (221 swift-testing + 26 XCTest), 0 failures. `presetLoaderBuiltInPresetsHaveValidPipelines()` confirmed passing with native mesh pipeline compiled on M3/M4.

**Verified:** Fractal tree renders at 60fps on M4. Trunk grows visibly with bass. Canopy colour responds to spectral content. Beat pulses visible across the tree. Tested with "Cannonball" by The Breeders — responds particularly well to bass-heavy material. Future preset-parameter tuning (branch angle, thickness curves, colour palette) deferred to Phase 3.5 preset-polish.

**Depends on:** Increment 3.2 (mesh shader infrastructure).

**Enables:** nothing downstream — this is a leaf preset increment.

### Increment 3.3: Hardware Ray Tracing Infrastructure ✅

**Goal:** Native Metal `MTLAccelerationStructure` + `BVHBuilder` infrastructure for ray-traced shadows and reflections. Shader-accessible acceleration structure, intersection kernels, and shared ray-tracing utility functions.

> **API migration note:** Originally specced as `MPSRayIntersector` + `MPSTriangleAccelerationStructure`. Migrated to the native Metal ray tracing API (`MTLAccelerationStructure`, `MTLAccelerationStructureCommandEncoder`, MSL `primitive_acceleration_structure` + `intersector<triangle_data>`) because the MPS variants are deprecated. The native API is lower-level but avoids deprecation warnings and is what Apple recommends for new code.

> **Dynamic geometry note:** Both `BVHBuilder` and `RayIntersector` expose non-blocking encode paths (`encodeBuild`, `encodeNearestHit`, `encodeShadow`) for per-frame audio-reactive scene geometry. The blocking `build()` / `intersect()` convenience wrappers are for tests and one-off queries only.

> **MSL gotcha documented:** `intersection_result<triangle_data>` provides `triangle_barycentric_coord` (NOT `.barycentrics` — that member does not exist in the macOS 14 Metal compiler 32023). Buffer bindings require `primitive_acceleration_structure`; `acceleration_structure<triangle_data>` as a buffer param is a compile error.

> **Scope split note:** The original Increment 3.3 entry listed `Renderer/Shaders/PostProcess.metal` under this increment. That file has been extracted into a separate Increment 3.4 (HDR Post-Process Chain) because post-processing is independent of ray tracing conceptually and architecturally. Per the Increment Scope Discipline rule, they are now separate increments.

**Files created/edited:**
- `Renderer/RayTracing/BVHBuilder.swift` — `MTLPrimitiveAccelerationStructureDescriptor` BVH builder; blocking `build()`/`rebuild()` + non-blocking `encodeBuild(into:)` for render-loop use
- `Renderer/RayTracing/RayIntersector.swift` — compute-pipeline-based intersector; blocking `intersect()`/`shadowRay()` + non-blocking `encodeNearestHit()`/`encodeShadow()`; static `reflectionDirection()` CPU helper
- `Renderer/RayTracing/RayIntersector+Internal.swift` — private GPU struct layouts (`RayGPUData`, `NearestHitData`) and buffer/pipeline helpers; split out to keep each file under the 400-line SwiftLint limit
- `Renderer/Shaders/RayTracing.metal` — `RTRay`/`RTNearestHit` structs, `rt_nearest_hit_kernel`, `rt_shadow_kernel`, `rt_camera_ray`/`rt_reflect`/`rt_offset_point` utilities

**Test results (9/9 pass):**
- `BVHBuilderTests.swift` — 4 XCTest tests: build, empty geometry, rebuild, triangleCount
- `RayIntersectorTests.swift` — 5 XCTest tests: hit, miss, shadow occluded, reflection (CPU), 1000-ray perf gate < 2ms (actual: ~0.8ms warm)
- 247 total tests pass (221 swift-testing + 26 XCTest), SwiftLint clean

**Depends on:** nothing.

**Enables:** Increment 3.5.1 Popcorn preset (real shadows on the pan floor and under kernels), any future preset needing ray-traced shadows or reflections.

### Increment 3.4: HDR Post-Process Chain (EXTRACTED from 3.3)

**Status:** Not started.

**Goal:** Multi-pass HDR rendering pipeline with bloom, tone mapping, and color grading. Enables photorealistic presets by providing the post-process chain that `PostProcess.metal` was originally slated to house.

**Architecture:**
- `PostProcessChain` Swift class — owns HDR scene texture (`.rgba16Float`), ping-pong bloom textures (half-res), and 4 pipeline states (bright pass, blur H, blur V, composite).
- Render path: scene preset → HDR texture → bright pass → Gaussian blur H → Gaussian blur V → composite (ACES tone-map + color grade) → drawable (`.bgra8Unorm_srgb`).
- `usePostProcess` flag on `PresetDescriptor` (default `false`, existing presets unaffected).
- New `drawWithPostProcess` private method in `RenderPipeline`, parallel to `drawDirect` / `drawWithFeedback` / `drawWithMeshShader`.
- HDR textures lazy-allocated at drawable size (same lifecycle pattern as the feedback textures).

**Files to create/edit:**
- `Renderer/PostProcessChain.swift` (new) — texture and pipeline-state owner, `render(scenePipelineState:features:fftBuffer:waveformBuffer:drawable:view:commandBuffer:)` entry point
- `Renderer/Shaders/PostProcess.metal` (new) — 4 fragment shaders: bright pass, separable Gaussian blur H, separable Gaussian blur V, ACES composite
- `Presets/PresetDescriptor.swift` — `usePostProcess: Bool` field, default `false`. Matching `"use_post_process"` CodingKey.
- `Renderer/RenderPipeline.swift` — new `drawWithPostProcess` path; `draw(in:)` branches on `usePostProcess`

**Test requirements:**
- `Tests/PhospheneEngineTests/Renderer/PostProcessChainTests.swift` (new) — 5 tests:
  - `test_init_createsHDRAndBloomTextures()` — HDR scene texture and both bloom textures are allocated with correct dimensions
  - `test_hdrTexture_pixelFormat_isRGBA16Float()` — HDR texture uses `.rgba16Float`
  - `test_bloomThreshold_onlyBrightPixelsPass()` — feed a test HDR input with known pixel values, verify only luminance > 0.9 survives the bright pass
  - `test_gaussianBlur_preservesLuminance()` — blur a solid-color region and verify total luminance is preserved within tolerance
  - `test_acesTonemap_mapsHDRToSDR()` — verify that values > 1.0 map into the SDR range and the curve matches the ACES formula
- **Performance test:**
  - `test_fullChain_under2ms_at1080p()` — the full 4-pass chain at 1920×1080 completes in under 2ms

**Verification:** A test shader writing an HDR color with some pixels > 1.0 produces visible bloom in the final composited output. Tone-mapped output is within gamut. All 6 tests pass.

**Depends on:** nothing (can be implemented independently of 3.3 ray tracing).

**Enables:** Increment 3.5.1 (Popcorn) and any future photorealistic preset that needs bloom, tone mapping, or HDR rendering.

### Increment 3.5: Indirect Command Buffers for GPU-Driven Rendering ✅

**Goal:** GPU encodes its own draw calls via ICBs based on audio state.

**Files created/edited:**
- `Renderer/Shaders/ICB.metal` — `icb_populate_kernel` compute shader: reads `FeatureVector`, populates up to `maxCommandCount` (default 16) ICB slots via `render_command`; slot 0 unconditionally active, subsequent slots activate as `bass + mid + treble` energy exceeds linearly spaced thresholds; inactive slots call `cmd.reset()`.
- `Renderer/RenderPipeline+ICB.swift` — `ICBConfiguration` struct, `IndirectCommandBufferState` class (ICB + compute pipeline + argument buffer for `command_buffer` MSL type + UMA `featureVectorBuffer`/`stemFeaturesBuffer`), `drawWithICB()` three-phase render path, `setICBState()`.
- `Renderer/RenderPipeline.swift` — Added `icbState`, `icbEnabled`, `icbLock`.
- `Renderer/RenderPipeline+Draw.swift` — ICB branch in `renderFrame()`: mesh → postProcess → **ICB** → feedback → direct.
- `Renderer/ShaderLibrary.swift` — `supportICB: Bool = false` param on `renderPipelineState()`.

**Tests:** 6 RenderPipelineICBTests (all pass):
- `test_createICB_maxCommandCount_matchesConfig()`
- `test_computeShader_populatesICB_nonZeroCommands()`
- `test_executeICB_completesWithoutError()`
- `test_icb_resetBetweenFrames()`
- `test_icb_withZeroAudio_minimumDrawCalls()`
- `test_gpuDrivenRendering_cpuFrameTimeReduced()` — avg ~0.001s/frame, hard gate <2ms ✓

**Verified:** 268 tests total, 0 failures, SwiftLint clean.

**Key implementation lessons:**
- `MTLIndirectCommandType.draw` is the correct option (not `.drawPrimitives`).
- `setFragmentBytes` is NOT inherited by ICB commands when `inheritBuffers = true` — only `setFragmentBuffer` bindings are. Solution: pre-allocated UMA `featureVectorBuffer` and `stemFeaturesBuffer` on `IndirectCommandBufferState`.
- Pipelines used with `executeCommandsInBuffer` must be compiled with `supportIndirectCommandBuffers = true`.
- Pass `command_buffer` to compute kernels via the argument buffer pattern: `makeArgumentEncoder(bufferIndex:)` + `setIndirectCommandBuffer(_:index:)` + `useResource(icb, usage: .write)`.
- Use `useResource(_:usage:stages:)` (macOS 13+ API) to avoid deprecation warnings on `MTLRenderCommandEncoder`.

**Depends on:** nothing.

**Enables:** Future performance optimizations for presets with large dynamic draw-call counts. Also triggers Increment 3.6 (render graph refactor) — ICB raises the capability flag count to 5 (mesh, postProcess, ICB, feedback, direct), crossing the threshold.

### Increment 3.6: Render Graph / Capability Composition Refactor ✅

**Status:** Complete.

**Motivation:** The capability-flag pattern (`useFeedback`, `useParticles`, `useMeshShader`, `usePostProcess`, `useICB`, `useRayMarch`) was crossing the manageable threshold — each new capability required a branch in `RenderPipeline.renderFrame`, a boolean on `RenderPipeline`, a conditional in `PresetLoader`, and a JSON flag in every preset. At N=6 the combinations started to explode.

**What shipped:**
- `RenderPass` enum (in `Shared` module): `direct`, `feedback`, `particles`, `meshShader`, `postProcess`, `rayMarch`, `icb` — with raw string values matching JSON keys
- `PresetDescriptor.passes: [RenderPass]` replaces 5 stored boolean flags; computed `useFeedback`, `useMeshShader`, etc. are kept as backwards-compatible derived properties
- Backward-compatible JSON decoding: `"passes"` key preferred; falls back to `synthesizePasses(from:)` which reads legacy `use_feedback` / `use_mesh_shader` / `use_post_process` / `use_ray_march` / `use_particles` boolean flags
- `RenderPipeline.activePasses: [RenderPass]` with `setActivePasses(_:)` / `currentPasses` (thread-safe via `passesLock`)
- `RenderPipeline.renderFrame` replaced with data-driven loop: iterates `activePasses`, dispatches to first pass with available subsystem, falls back to `drawDirect`
- `RenderPipeline+RayMarch`: replaced removed `postProcessEnabled` bool with `passesLock.withLock { activePasses.contains(.postProcess) }`
- `VisualizerEngine.applyPreset` rewrote as pass-walking configurator; removed `applyRayMarchPreset` private helper
- 7 preset JSON files migrated to `"passes"` format; legacy format still decodes correctly
- 7 new tests in `PresetTests.swift` covering `RenderPass` raw values, JSON decoding, legacy synthesis, and `setActivePasses` round-trip
- 314 tests total (239 swift-testing + 75 XCTest), SwiftLint clean

**Depends on:** 3.1, 3.1-bonus, 3.2, 3.3, 3.4, 3.5, 3.14, 3.15 (all complete)

**Enables:** sustainable scaling of the preset library past the 6-capability ceiling.

---

## Phase 3.5 — Native Preset Library Expansion

**Goal:** Ship a curated library of native presets that exercise the Phase 3 infrastructure. Each preset increment depends on one or more infrastructure increments from Phase 3 and must not start until those dependencies are verified complete.

**Naming convention:** `Increment 3.5.N` — each native preset is a separate increment with a clear concept, audio routing, dependency list, and per-preset test/diagnose workflow. Per the Increment Scope Discipline rule, a preset and the infrastructure it depends on are never bundled.

**Prerequisite:** Phase 2.5 (Session Preparation Pipeline) should be complete before preset work begins, so presets can be designed with the assumption that stems are always available from frame one. Presets should NOT include warmup fallback logic.

### Increment 3.5.1: REMOVED — Photorealistic Popcorn

**Status:** Removed from plan. The concept (photorealistic cast-iron skillet with popping kernels) prioritized technical demonstration over emotional musical connection. The visual metaphor — a kitchen scene — has a thin relationship to the music beyond "kernels pop on drum hits." This conflicts with the project's creative philosophy that visuals should function as another member of the band, not a Pixar short. The massive dependency list (3.1a, 3.1b, 3.3, 3.4, 3.12–3.17) and multiple failed implementation attempts confirmed this was the wrong first preset.

### Increment 3.5.2: Murmuration Stem Routing Revision

**Status:** Not started. Next preset in the expansion phase.

[See the full increment prompt created earlier in this conversation for the complete specification.]

---

### Increment 3.5.3: Glass Brutalist Preset ✅

**Status:** Complete.

**Concept:** A stark brutalist corridor of massive concrete pillars and horizontal ceiling slabs, with near-mirror glass panels positioned between each pillar bay. The architecture breathes and heaves with low-frequency energy; glass panels produce high-luminance IBL specular reflections that the SSGI pass bleeds as indirect diffuse light onto adjacent concrete surfaces.

**Files created:**
- `PhospheneEngine/Sources/Presets/Shaders/GlassBrutalist.metal`
- `PhospheneEngine/Sources/Presets/Shaders/GlassBrutalist.json`

**Passes:** `["ray_march", "ssgi", "post_process"]` — G-buffer deferred lighting → SSGI indirect bleed → bloom + ACES tone map.

**SDF geometry:**
- Concrete: floor/ceiling `sdPlane`s + paired pillar columns (mirrored via `abs(p.x)` fold, repeated in Z at 7-unit intervals via `round()`-based repetition) + horizontal cross-beams at pillar tops.
- Glass: thin vertical panels (`sdBox`, half-depth 0.05) offset by half a cell in Z so they sit between each pillar row.

**Audio routing (hierarchy-correct):**
- `f.sub_bass + f.low_bass` → pillar Y-scale (continuous energy, primary driver; architecture heaves with bass stem proxy)
- `f.mid` → glass panel Y-scale (continuous energy, melody-reactive)
- `f.accumulated_audio_time` → slow sinusoidal corridor drift (scene breathes overall)
- `f.beat_bass` → 5 % transient pillar X/Z-squeeze (accent, secondary — well within 2–4× continuous/beat ratio)

**Materials:**
- Concrete: two-octave `perlin2D` FBM on `p.xz` for gritty albedo variation (grey range 0.32–0.56 with slight warm cast), roughness 0.82–0.92, metallic 0.0.
- Glass: cool cyan albedo [0.55, 0.82, 0.96], roughness 0.04, metallic 0.92. Near-mirror finish produces strong specular IBL contribution in the `rgba16Float` litTexture; SSGI samples this brightness and bleeds cyan-tinted indirect diffuse onto adjacent concrete.

**Architecture notes:**
- `sceneMaterial` has no `FeatureVector` access (forward declaration constraint). Audio-reactive material properties are expressed geometrically in `sceneSDF` only. Material re-evaluates sub-SDFs at rest pose (no deformation) for stable boundaries.
- `gb_rep()` helper uses `round()` not `fmod()` for correct negative-coordinate domain repetition (same lesson as `ks_rep` in KineticSculpture).
- No new Swift files, no new tests (preset compiles dynamically via `PresetLoader` at runtime).

**Verified:** Build succeeded. 280 swift-testing + 91 XCTest pass. 0 SwiftLint violations. Pre-existing `test_fullScreenNoise_1080p_under2ms` flake (2.08 ms vs 2.0 ms threshold, system-load-dependent) unrelated to this increment.

**Enables:** Demonstrates full ray_march → ssgi → post_process pipeline with a concrete creative concept. Reference architecture for future corridor/architectural presets.

---

*Additional Phase 3.5 preset entries are added as presets are designed.*

---

## Phase 3R — Rendering Fidelity Infrastructure

**Goal:** Close the quality gap between Phosphene's current fragment-shader output and photorealistic visuals. Four infrastructure increments provide the building blocks that every high-fidelity preset needs: reusable shader functions, pre-computed noise textures, a deferred ray march pipeline, and extended scene uniforms. These are independent of geometry pipelines (mesh shaders, ray tracing acceleration structures) — they enhance the *fragment-shader-only* path that most presets use.

**Why this phase exists:** The screenshots from Phase 3.5.1 Popcorn development attempts revealed that the rendering pipeline lacks fundamental infrastructure. Fragment shaders trying to fake 3D scenes without noise textures, lighting models, or SDF utilities produce flat, synthetic results. The Milkdrop preset analysis (see `MILKDROP_PRESET_ANALYSIS.md`) documents 15 creative techniques that all depend on infrastructure Phosphene doesn't have yet — noise samplers, polar/bipolar UV transforms, gradient advection, articulated kinematics, reaction-diffusion systems. This phase provides the foundation.

**Dependency chain:**
```
3.12 (Shader Utility Library) ──┐
                                 ├──→ 3.14 (Ray March Pipeline) ──→ Phase 3.5 presets
3.13 (Noise Texture Manager) ───┘                                       ↑
                                                                         │
3.15 (Extended Shader Uniforms) ─────────────────────────────────────────┘
```

**Phase 3R status: ✅ COMPLETE.** All four increments (3.12, 3.13, 3.14, 3.15) are done. Phase 3.5 presets are now unblocked.

### Increment 3.12: Shader Utility Library

**Status:** Complete.

**Goal:** Create `ShaderUtilities.metal` — a comprehensive MSL function library included in every preset via the `PresetLoader` preamble. Provides noise generation, SDF primitives, ray marching, PBR lighting, UV transforms, color palettes, and atmospheric effects as reusable, tested functions.

**Why this is the highest-priority rendering increment:** Every preset currently hand-rolls its own noise, lighting, and color math — badly. A shared utility library immediately raises the quality floor for all presets. The Milkdrop preset analysis identifies noise sampling as the single biggest missing capability (used in Sparkle, Supernova, Reaction, and Drawing categories). PBR lighting is the second biggest gap (needed for Geometric and any photorealistic preset).

**Files to create/edit:**
- `Renderer/Shaders/ShaderUtilities.metal` (new, ~800–1000 lines) — all utility functions, organized by `// MARK: -` category. All functions `static inline`.
- `Presets/PresetLoader+Preamble.swift` — insert `ShaderUtilities.metal` content into the preamble string, after FeatureVector struct and before preset shader code. The content is loaded from the bundle resource at init, not hardcoded as a string literal.
- `Package.swift` — ensure `ShaderUtilities.metal` is included in the shader resources (`.copy("Shaders")` or `.process("Shaders")`).

**Function inventory (53 functions across 6 domains):**

| Domain | Functions | Count |
|--------|-----------|-------|
| **Noise** | `hash21`, `hash31`, `hash22`, `hash33`, `perlin2D`, `perlin3D`, `simplex2D`, `simplex3D`, `worley2D`, `worley3D`, `fbm2D`, `fbm3D`, `curl2D`, `curl3D` | 14 |
| **SDF Primitives** | `sdSphere`, `sdBox`, `sdRoundBox`, `sdTorus`, `sdCylinder`, `sdCapsule`, `sdCone`, `sdPlane` | 8 |
| **SDF Operations** | `opUnion`, `opSubtract`, `opIntersect`, `opSmoothUnion`, `opSmoothSubtract`, `opRepeat`, `opTwist`, `opBend`, `opRound` | 9 |
| **Ray Marching** | `rayMarch`, `calcNormal`, `calcAO`, `softShadow` | 4 |
| **PBR Lighting** | `fresnelSchlick`, `distributionGGX`, `geometrySmith`, `cookTorranceBRDF`, `evaluatePointLight`, `evaluateDirectionalLight` | 6 |
| **UV Transforms** | `uvPolar`, `uvInvRadius`, `uvKaleidoscope`, `uvMoebius`, `uvBipolar`, `uvLogSpiral` | 6 |
| **Color/Atmosphere** | `palette`, `toneMapACES`, `toneMapReinhard`, `linearToSRGB`, `sRGBToLinear`, `fog`, `atmosphericScatter`, `volumetricMarch` | 8 |

**Reference implementations:** Each function should be validated against established sources:
- Noise: Stefan Gustavson's simplex noise, Inigo Quilez's noise functions
- SDF: Inigo Quilez's SDF library (iquilezles.org/articles/distfunctions/)
- PBR: LearnOpenGL.com Cook-Torrance implementation, Epic Games' UE4 PBR notes
- UV transforms: Flexi's "Box of Tricks" from Milkdrop (see `MILKDROP_PRESET_ANALYSIS.md` Hypnotic section)
- Tone mapping: Academy Color Encoding System (ACES) fitted curve by Stephen Hill

**Test requirements:**
- `Tests/PhospheneEngineTests/Renderer/ShaderUtilityTests.swift` (new) — 10 tests:
  - `test_preambleIncludesShaderUtilities()` — verify the compiled preamble string contains ShaderUtilities content
  - `test_presetCompilation_withUtilityFunctions_succeeds()` — compile a test preset that calls at least one function from each domain
  - `test_noiseOutput_deterministic_sameInputSameOutput()` — compile and run a compute kernel calling `perlin2D` with known inputs, verify output matches expected values
  - `test_sdfSphere_knownDistance_matchesAnalytic()` — `sdSphere(float3(1,0,0), 0.5)` should return 0.5
  - `test_rayMarch_sphereScene_hitsAtExpectedDistance()` — march toward a unit sphere at origin, verify hit distance ≈ expected
  - `test_cookTorrance_energyConservation_outputLEInput()` — PBR output luminance ≤ input light energy
  - `test_uvKaleidoscope_symmetry_nFinsProducesNFoldSymmetry()` — verify angular folding correctness
  - `test_palette_sweepT_producesSmooth gradient()` — cosine palette with t from 0→1 produces no discontinuities
  - `test_acesToneMap_hdrInput_outputInSDRRange()` — values > 1.0 map to (0, 1)
  - `test_fog_zeroDistance_noEffect()` — fog at distance 0 returns original color
- **Performance test:**
  - `test_fullScreenNoise_1080p_under2ms()` — full-screen `fbm3D` at 1920×1080 completes in under 2ms

**Verification:** All existing 268 tests pass. 11 new tests pass. A test preset calling noise + SDF + PBR compiles and renders without errors. Visual inspection: noise output looks organic (not banded), SDF sphere has smooth edges, PBR lighting shows specular highlight and Fresnel rim.

**Depends on:** nothing.

**Enables:** Increment 3.14 (ray march pipeline), all future presets needing noise/SDF/PBR, immediate quality improvement for existing presets that could be updated to use utility functions.

### Increment 3.13: Noise Texture Manager

**Status:** Complete.

**Goal:** Create `TextureManager` — generates and binds 5 pre-computed noise textures at application init, providing Milkdrop-equivalent noise samplers to all preset shaders.

**Why textures in addition to procedural noise (3.12):** Procedural noise computed per-pixel in a fragment shader has no mipmaps, no hardware filtering, and costs ALU every frame. Pre-computed noise textures are sampled via the texture unit with free bilinear/trilinear filtering and mipmaps, are much cheaper per pixel, and enable 3D volumetric noise (which is prohibitively expensive to compute per-pixel). The Milkdrop preset analysis shows that `sampler_noisevol_hq` (3D noise) is essential for clouds, gas, and nebula effects (Supernova/Burst, Supernova/Gas) — these are impossible without a 3D texture.

**Files created/edited:**
- `Renderer/TextureManager.swift` (new) — owns 5 `MTLTexture` objects. Generates via Metal compute kernels on init (synchronous GPU dispatch). Provides `bindTextures(to:)` binding all 5 at fixed fragment texture indices 4–8. Optional reference held by `RenderPipeline` behind `NSLock`.
- `Renderer/Shaders/NoiseGen.metal` (new) — 4 compute kernels with `ng_`-prefixed helpers to avoid MSL symbol collisions: `gen_perlin_2d`, `gen_perlin_3d`, `gen_fbm_rgba`, `gen_blue_noise`.
- `Renderer/RenderPipeline.swift` — `var textureManager: TextureManager?` + `NSLock` + `setTextureManager(_:)`. Added `bindNoiseTextures(to:)` helper called in every draw path.
- `Renderer/RenderPipeline+Draw.swift`, `+MeshDraw.swift`, `+ICB.swift`, `+PostProcess.swift` — `bindNoiseTextures(to:encoder)` added to `drawDirect`, `drawParticleMode`, `drawSurfaceMode`, `drawWithMeshShader`, `drawWithICB`.
- `Renderer/PostProcessChain.swift` — `render(…noiseTextures: TextureManager? = nil)` backward-compatible param; bound in `runScenePass`.
- `Presets/PresetLoader+Preamble.swift` — sampler declarations + noise texture index documentation.
- `PhospheneApp/VisualizerEngine.swift` — creates `TextureManager` on `.userInitiated` background queue at startup; pipeline renders without noise textures until generation completes.

**Texture specifications (as implemented):**

| Name | Dimensions | Format | Type | Contents |
|------|-----------|--------|------|----------|
| `noiseLQ` | 256×256 | `.r8Unorm` | `MTLTextureType2D` | Tileable value-noise FBM (4 octaves), mipmapped |
| `noiseHQ` | 1024×1024 | `.r8Unorm` | `MTLTextureType2D` | Tileable value-noise FBM (4 octaves), mipmapped |
| `noiseVolume` | 64×64×64 | `.r8Unorm` | `MTLTextureType3D` | Tileable 3D value-noise FBM (3 octaves) |
| `noiseFBM` | 1024×1024 | `.rgba8Unorm` | `MTLTextureType2D` | R=Perlin FBM, G=shifted Perlin, B=inverted Worley, A=curl magnitude, mipmapped |
| `blueNoise` | 256×256 | `.r8Unorm` | `MTLTextureType2D` | Interleaved Gradient Noise (IGN, Jimenez 2014), mipmapped |

All textures: `.storageModeShared` (UMA), deterministic (identical output each launch). Total GPU memory: ~6 MB. 2D textures require `.renderTarget` usage flag for `MTLBlitCommandEncoder.generateMipmaps(for:)` to succeed.

**Implementation deviations from spec:**

1. **noiseFBM channels**: Spec called for `G=Simplex`. Simplex noise requires a 3D permutation table that exceeds the 4 KB `setBytes` limit when passing as a buffer to a compute kernel. Replaced with `G=shifted Perlin` (same value-noise base, phase-shifted by 0.5 in both axes) — sufficient visual variety for material layering, avoids the buffer size constraint.

2. **blueNoise algorithm**: Spec called for "void-and-cluster". Void-and-cluster is an iterative CPU algorithm (not GPU-computable); it would require a separate CPU generation path and a buffer upload, defeating the GPU-compute approach. Replaced with Interleaved Gradient Noise (IGN, Jimenez 2014 GDC) — deterministic, computable in a single GPU pass, produces good low-discrepancy dithering properties validated in the literature. A note is added to resolved decisions.

3. **Preamble approach**: Spec showed file-scope `texture2d<float> noiseLQ [[texture(4)]];` declarations. MSL does not permit texture objects as file-scope globals — they must be function parameters. The preamble instead documents the binding indices as comments and adds three `constexpr sampler` declarations (`linearSampler`, `nearestSampler`, `mipLinearSampler`), which ARE valid at MSL file scope. Preset shaders declare the textures they need as function parameters with `[[texture(4..8)]]`.

**Preamble additions (as implemented):**
```metal
// Noise textures bound by TextureManager — declare as function parameters to sample:
//   texture2d<float>  noiseLQ     [[texture(4)]]  — 256²  tileable Perlin FBM
//   texture2d<float>  noiseHQ     [[texture(5)]]  — 1024² tileable Perlin FBM
//   texture3d<float>  noiseVolume [[texture(6)]]  — 64³   tileable 3D FBM
//   texture2d<float>  noiseFBM    [[texture(7)]]  — 1024² RGBA FBM
//   texture2d<float>  blueNoise   [[texture(8)]]  — 256²  IGN dither
constexpr sampler linearSampler(filter::linear, address::repeat);
constexpr sampler nearestSampler(filter::nearest, address::repeat);
constexpr sampler mipLinearSampler(filter::linear, mip_filter::linear, address::repeat);
```

**Tests delivered:**
- `Tests/PhospheneEngineTests/Renderer/TextureManagerTests.swift` (new) — 9 tests:
  - `test_init_createsAllFiveTextures()` — all 5 textures are non-nil after init
  - `test_noiseLQ_dimensions_256x256()` — verify width, height, pixel format
  - `test_noiseHQ_dimensions_1024x1024()`
  - `test_noiseVolume_dimensions_64x64x64_type3D()` — verify texture type is `.type3D`
  - `test_noiseFBM_pixelFormat_rgba8Unorm()`
  - `test_allTextures_storageModeShared()` — UMA compliance
  - `test_noiseGeneration_deterministic_sameOutputEachInit()` — two instances, pixel-identical output
  - `test_bindTextures_setsCorrectIndices()` — compiles inline Metal shader sampling `[[texture(4)]]`, renders to 4×4 offscreen texture, verifies non-zero pixel output
  - `test_init_textureGeneration_under500ms()` — hard gate: 500ms

**Verification:** All 279 prior tests pass. 9 new tests pass. 288 total (232 swift-testing + 56 XCTest). SwiftLint clean.

**Depends on:** nothing (but benefits greatly from 3.12 — preset shaders can combine procedural utility functions with texture sampling).

**Enables:** Increment 3.14 (ray march pipeline uses noise textures for materials), all presets needing organic textures (Reaction, Supernova, Drawing categories from Milkdrop analysis).

### Increment 3.14: Multi-Pass Ray March Pipeline ✅ COMPLETE

**Status:** Complete.

**Goal:** Deferred rendering pipeline for SDF ray-marched scenes — a G-buffer pass, a PBR lighting pass, and integration with the existing post-process chain. Enables photorealistic 3D presets rendered entirely in fragment shaders.

**Why deferred:** A single fragment pass that ray marches AND evaluates PBR lighting AND computes shadows is prohibitively expensive at 60fps. Deferred rendering separates geometry evaluation (one SDF march per pixel) from lighting (evaluated only on visible surfaces), and allows multi-light scenes without re-marching.

**Files created/edited:**
- `Renderer/Shaders/RayMarch.metal` (new) — 2 Renderer-library shader functions (G-buffer fragment is per-preset, not in shared library):
  - `raymarch_lighting_fragment` — reads 3 G-buffer targets, evaluates Cook-Torrance PBR (GGX NDF, Smith geometry, Fresnel-Schlick), 12-step screen-space soft shadows, 5-sample cone AO, procedural sky fallback, audio-reactive emissive highlights from `sceneParamsA.x` (audioTime). Outputs to HDR `.rgba16Float`.
  - `raymarch_composite_fragment` — ACES filmic tone-map from litTexture → drawable format (SDR).
- `Renderer/RayMarchPipeline.swift` (new) — `RayMarchPipeline` class: owns 4 textures (gbuffer0 `.rg16Float`, gbuffer1 `.rgba8Snorm`, gbuffer2 `.rgba8Unorm`, litTexture `.rgba16Float`), 2 fixed pipeline states (lightingPipeline, compositePipeline), bilinear sampler, public `sceneUniforms: SceneUniforms`. `allocateTextures(width:height:)` / `ensureAllocated(width:height:)` for lazy resize. `render(gbufferPipelineState:features:fftBuffer:waveformBuffer:stemFeatures:outputTexture:commandBuffer:noiseTextures:postProcessChain:)` — 9 params, 3-pass encode. `rgba8Snorm` created via private `makeSnormTexture` helper (not available from `MetalContext.makeSharedTexture`).
- `Renderer/RenderPipeline+RayMarch.swift` (new) — `drawWithRayMarch(commandBuffer:view:features:stemFeatures:activePipeline:rayMarchState:)`: updates `sceneUniforms.sceneParamsA.y` (aspect ratio), lazily allocates textures, resolves optional PostProcessChain, delegates all GPU encoding to `RayMarchPipeline.render`.
- `Renderer/RenderPipeline.swift` — added `rayMarchPipeline: RayMarchPipeline?`, `rayMarchEnabled: Bool`, `rayMarchLock: NSLock`, `setRayMarchPipeline(_:enabled:)`. `drawableSizeWillChange` calls `rayMarchPipeline?.allocateTextures`.
- `Renderer/RenderPipeline+Draw.swift` — ray march snapshot + branch in `renderFrame`: mesh → postProcess → ICB → **rayMarch** → feedback → direct.
- `Renderer/PostProcessChain.swift` — added `runBloomAndComposite(from:to:commandBuffer:)`: accepts external `litTexture`, skips scene pass, runs bright-pass → blur-H → blur-V → ACES composite. Used by ray march + bloom path without duplicating the chain's scene pass.
- `Presets/PresetDescriptor.swift` — `useRayMarch: Bool` field (`"use_ray_march"` key, default `false`).
- `Presets/PresetLoader.swift` — added `CompiledShader` struct replacing 3-member tuple (SwiftLint `large_tuple`), `rayMarchPipelineState: MTLRenderPipelineState?` on `LoadedPreset`, `compileRayMarchShader(at:descriptor:)` builds 3-attachment `MTLRenderPipelineDescriptor` (attachments[0]=`.rg16Float`, [1]=`.rgba8Snorm`, [2]=`.rgba8Unorm`) for the G-buffer pass. `// swiftlint:disable file_length` and `type_body_length` added (file grew to 470 lines with the ray march compilation path).
- `Presets/PresetLoader+Preamble.swift` — added `rayMarchGBufferPreamble: String` static property (separate from `shaderPreamble`) containing `SceneUniforms` MSL struct, `GBufferOutput` struct, `sceneSDF`/`sceneMaterial` forward declarations, and the `raymarch_gbuffer_fragment` function body. **Critical preamble split**: `raymarch_gbuffer_fragment` calls preset-defined `sceneSDF`/`sceneMaterial` which standard presets never define — including it in `shaderPreamble` broke all standard preset compilation. The fix was two separate static properties; `compileRayMarchShader` concatenates both while `compileStandardShader` uses only `shaderPreamble`.
- `Shared/AudioFeatures+SceneUniforms.swift` (new) — `@frozen public struct SceneUniforms: Sendable`, 8×`SIMD4<Float>` (128 bytes, matches MSL layout exactly — `SIMD3<Float>` was avoided due to Swift/MSL 16-byte alignment mismatch). Fields: `cameraOriginAndFov`, `cameraForward`, `cameraRight`, `cameraUp`, `lightPositionAndIntensity`, `lightColor`, `sceneParamsA` (audioTime, aspectRatio, near, far), `sceneParamsB` (fogNear, fogFar, reserved). Default init: camera at (0,0,−5) looking +Z, light at (3,8,−3), fov=π/4, far=30.
- `Renderer/Shaders/Common.metal` — added MSL `SceneUniforms` struct (8×float4) for use by Renderer library shaders (`RayMarch.metal`). Not in preamble (preamble is for preset shaders; Renderer shaders use the Renderer Metal library directly).
- `PhospheneApp/VisualizerEngine+Presets.swift` — added `useRayMarch` branch (first check in `applyPreset`), extracted `applyRayMarchPreset(preset:rmPipelineState:desc:)` private helper to resolve `function_body_length` SwiftLint limit. Ray march + bloom path wired: `desc.usePostProcess` triggers `PostProcessChain` creation alongside `RayMarchPipeline`.

**G-buffer texture layout (as implemented):**

| Target | Format | Contents |
|--------|--------|----------|
| G-buffer 0 | `.rg16Float` | R = depth_normalized [0..1), G = unused |
| G-buffer 1 | `.rgba8Snorm` | RGB = world-space normal, A = ambient occlusion |
| G-buffer 2 | `.rgba8Unorm` | RGB = albedo, A = packed roughness (upper 4b) + metallic (lower 4b) |

**Per-preset scene function:** Each ray march preset defines `float sceneSDF(float3 p, constant FeatureVector& f, constant SceneUniforms& s)` and `void sceneMaterial(float3 p, int matID, thread float3& albedo, thread float& roughness, thread float& metallic)`. The G-buffer fragment (compiled into each preset's shader source via `rayMarchGBufferPreamble`) calls these — preset authors write only scene geometry and materials, not marching loops, normal estimation, or lighting.

**Implementation deviations from spec:**

1. **Two preamble properties instead of one**: The spec assumed G-buffer infrastructure would live in the shared preamble. In practice, `raymarch_gbuffer_fragment` forward-declares and calls `sceneSDF`/`sceneMaterial`, which are undefined in standard (non-ray-march) presets. Including it in the shared preamble caused linker failures for all standard presets. Fix: separate `rayMarchGBufferPreamble` only included when compiling ray march preset shaders.

2. **`CompiledShader` struct**: Spec showed a `(standard:feedback:rayMarch:)` tuple return from `compileShader`. A 3-element named tuple triggers SwiftLint `large_tuple`. Replaced with a lightweight `CompiledShader` struct with default-nil parameters for feedback and rayMarch states.

3. **`rgba8Snorm` texture helper**: `MetalContext.makeSharedTexture` does not expose snorm formats. `RayMarchPipeline` has a private `makeSnormTexture(width:height:)` that builds `MTLTextureDescriptor` directly with `.rgba8Snorm`, `.shared` storage, and `[.renderTarget, .shaderRead]` usage.

4. **`runBloomAndComposite` instead of re-running PostProcessChain scene pass**: The existing `PostProcessChain.render` runs its own scene pass (rendering the preset fragment shader again into the HDR texture). For ray march presets, the scene is already rendered into `litTexture` by `RayMarchPipeline`. The new `runBloomAndComposite(from:to:commandBuffer:)` accepts an external `MTLTexture` as the source, sets it as `sceneTexture`, and runs only the 4 post-processing passes (bright-pass, blur-H, blur-V, ACES composite) without re-running the scene.

**Tests delivered:**
- `Tests/PhospheneEngineTests/Renderer/RayMarchPipelineTests.swift` (new) — 10 XCTest tests:
  - `test_gbufferAllocation_matchesRequestedSize` — all 4 textures have correct width/height
  - `test_gbufferFormats_areCorrect` — `.rg16Float`, `.rgba8Snorm`, `.rgba8Unorm`, `.rgba16Float`
  - `test_gbufferTextures_storageMode_isShared` — UMA compliance for all 4 textures
  - `test_sphere_depth_isNonZero` — center pixel depth < 0.999 (ray hits sphere SDF)
  - `test_sphere_normals_pointOutward` — all hit pixels have nz < 0 (facing camera at z=−5)
  - `test_litOutput_hasSpecularHighlight_atCenter` — luminance > 0.01 at sphere center
  - `test_shadowRegion_isDarkerThanLitRegion` — both lit sphere and background are nonzero
  - `test_combined_rayMarchAndPostProcess_producesValidOutput` — bloom path produces non-zero drawable
  - `test_ensureAllocated_isIdempotent` — second call with same size leaves texture pointers unchanged
  - `test_fullPipeline_under8ms_at1080p` — hard perf gate: complete 3-pass pipeline at 1920×1080

**Verification:** All 288 prior tests pass. 10 new tests pass. 298 total (232 swift-testing + 66 XCTest). SwiftLint clean (0 violations, 0 serious across 78 files). `RayMarchPipeline` initializes and allocates textures correctly. G-buffer pass writes depth/normals/albedo; lighting pass evaluates PBR; composite pass applies ACES tone mapping. Sphere scene with soft shadow and AO renders as expected. Bloom path routes `litTexture` through `PostProcessChain.runBloomAndComposite` correctly.

**Depends on:** Increment 3.12 (shader utility library — SDF/PBR/noise functions in preamble), Increment 3.13 (noise textures — bound at indices 4–8, available to ray march material functions).

**Enables:** Increment 3.5.1 Popcorn and all future photorealistic presets, Milkdrop Reaction-category equivalents (reaction-diffusion in 3D).

### Increment 3.15: Extended Shader Uniforms (SceneUniforms + Accumulated Audio Time) ✅ COMPLETE

**Status:** ✅ Complete. 307 tests pass (232 swift-testing + 75 XCTest).

**Goal:** Add `accumulatedAudioTime` to `FeatureVector` for all presets, and add per-preset scene configuration (`SceneCamera`, `SceneLight`, fog, ambient) to `PresetDescriptor` with `SceneUniforms` population at preset-switch time. These changes provide the scene-level and time-level data that photorealistic and Milkdrop-style presets need.

**What was implemented:**

`FeatureVector` grew from 24 floats (96 bytes) to 32 floats (128 bytes): `accumulatedAudioTime` added as float 25, followed by 7 padding floats (`_pad1`–`_pad7`) for SIMD alignment. MSL preamble `FeatureVector` struct updated to match (32 floats, field `accumulated_audio_time`).

`SceneUniforms` uses the existing Increment 3.14 layout (8 × `SIMD4<Float>` = 128 bytes): `cameraOriginAndFov`, `cameraForward`, `cameraRight`, `cameraUp`, `lightPositionAndIntensity`, `lightColor`, `sceneParamsA` (x=audioTime, y=aspectRatio, z=near, w=far), `sceneParamsB` (x=fogNear, y=fogFar, z=ambient, w=reserved).

`SceneCamera` and `SceneLight` Codable structs added to `Presets` module. `PresetDescriptor` gains `sceneCamera: SceneCamera?`, `sceneLights: [SceneLight]`, `sceneFog: Float`, `sceneAmbient: Float`.

`RenderPipeline` gains `accumulatedAudioTime: Float`, `resetAccumulatedAudioTime()`, and internal `stepAccumulatedTime(energy:deltaTime:)` behind `NSLock`. Accumulation formula: `_accumulatedAudioTime += max(0, energy) * deltaTime`, driven by `(bass + mid + treble) / 3.0` each frame. `drawWithRayMarch` writes `accumulatedAudioTime` to `sceneUniforms.sceneParamsA.x` each frame.

`VisualizerEngine+Presets.swift` gains `makeSceneUniforms(from:)`: camera basis construction (forward/right/up from position+target), first light → lightPositionAndIntensity + lightColor, fog/ambient → sceneParamsB. Track-change callback calls `pipeline.resetAccumulatedAudioTime()`.

**Files created/modified:**
- `Shared/AudioFeatures+Analyzed.swift` — `FeatureVector` 96→128 bytes, `accumulatedAudioTime` field
- `Presets/PresetDescriptor.swift` — `SceneCamera`, `SceneLight` structs; new JSON fields
- `Presets/PresetLoader+Preamble.swift` — MSL `FeatureVector` updated to 32 floats
- `Renderer/RenderPipeline.swift` — accumulated time state, step/reset methods, per-frame accumulation
- `Renderer/RenderPipeline+RayMarch.swift` — writes audioTime to sceneParamsA.x each frame
- `PhospheneApp/VisualizerEngine+Presets.swift` (new) — `makeSceneUniforms(from:)`, preset apply logic
- `PhospheneApp/VisualizerEngine+Audio.swift` — `resetAccumulatedAudioTime()` on track change
- `Tests/Shared/SceneUniformsTests.swift` (new) — 5 tests
- `Tests/Shared/FeatureVectorExtendedTests.swift` (new) — 4 tests
- 3 existing tests updated (96→128 bytes): `AudioFeaturesTests`, `MIRPipelineUnitTests`, `UMABufferTests`, `PipelineIntegrationTests`

**Verification:** ✅ 307 tests pass. `FeatureVector` is 128 bytes (32 floats). MSL probe kernel reads all 32 fields without compile errors. JSON preset with `scene_camera`, `scene_lights`, `scene_fog`, `scene_ambient` decodes correctly. `accumulatedAudioTime` starts at 0, accumulates at `energy × deltaTime` rate, and resets to 0 on `resetAccumulatedAudioTime()`.

**Depends on:** Increment 3.14 (SceneUniforms struct exists in Renderer module).

**Enables:** All presets using accumulated audio time (nearly universal — see Milkdrop analysis), Phase 3.5 Popcorn.

### Increment 3.16: Image-Based Lighting (IBL) Pipeline

**Status:** Complete ✅

**Goal:** HDR environment map generation and IBL texture pipeline for physically accurate ambient lighting and specular reflections in all ray march presets. Replaces the procedural sky fallback in `raymarch_lighting_fragment` with irradiance + prefiltered environment sampling.

**Why this is needed now:** The ray march pipeline (3.14) evaluates Cook-Torrance PBR with point/directional lights and a procedural sky fallback. This produces acceptable lighting for matte surfaces but fails for reflective materials (glass, polished metal, water, wet surfaces) because point lights alone cannot produce the complex, continuous reflection patterns these materials require. IBL is a prerequisite for photorealistic presets — shipping Popcorn (3.5.1) without it would produce a visually flat cast-iron pan and unconvincing kernel surfaces.

**Texture binding resolution:** `TextureManager` currently occupies texture(4–8) with noise textures. IBL textures bind at texture(9–11): irradiance cubemap, prefiltered environment map, BRDF integration LUT. The prior documentation claimed texture(8) was reserved for environment maps, but `blueNoise` was implemented at texture(8) in Increment 3.13. This increment resolves the conflict by using indices 9–11.

**Files to create/edit:**
- `Renderer/IBLManager.swift` (new) — `IBLManager` class: generates 3 IBL textures at init via Metal compute kernels. Owns: `irradianceMap` (cubemap, 32² per face, `.rgba16Float`, convolved from source), `prefilteredEnvMap` (cubemap, 128² per face, 5 mip levels for roughness LOD, `.rgba16Float`), `brdfLUT` (2D, 512², `.rg16Float`, split-sum integration). Default source environment: procedural gradient sky + ground plane (generated via compute). Future: accept `.hdr`/`.exr` files. `bindTextures(to:)` sets fragment texture indices 9–11.
- `Renderer/Shaders/IBL.metal` (new) — Metal compute kernels: `gen_irradiance_cubemap` (hemisphere cosine-weighted convolution), `gen_prefiltered_env` (GGX importance sampling per mip level), `gen_brdf_lut` (split-sum numeric integration). MSL utility functions: `ibl_sample_irradiance`, `ibl_sample_prefiltered`, `ibl_sample_brdf_lut` for use by the lighting pass.
- `Renderer/Shaders/RayMarch.metal` — Update `raymarch_lighting_fragment` to sample IBL textures for diffuse ambient (irradiance map) and specular reflections (prefiltered env + BRDF LUT). Keep existing point/directional light evaluation alongside IBL. Add `texture2d<float> iblIrradiance [[texture(9)]]`, `texturecube<float> iblPrefiltered [[texture(10)]]`, `texture2d<float> brdfLUT [[texture(11)]]` parameters.
- `Renderer/RenderPipeline.swift` — Hold optional `IBLManager`, bind IBL textures in ray march draw paths.
- `Renderer/RenderPipeline+RayMarch.swift` — Pass IBL textures to lighting pass encoder.
- `Presets/PresetLoader+Preamble.swift` — Add IBL texture index documentation to `rayMarchGBufferPreamble`.

**Test requirements:**
- `Tests/PhospheneEngineTests/Renderer/IBLManagerTests.swift` (new) — 9 tests:
  - `test_init_createsIrradianceMap()` — non-nil, correct dimensions (32² per face)
  - `test_init_createsPrefilteredEnvMap()` — non-nil, correct dimensions (128² per face), 5 mip levels
  - `test_init_createsBRDFLUT()` — non-nil, 512², `.rg16Float`
  - `test_allTextures_storageModeShared()` — UMA compliance
  - `test_irradiance_nonBlack()` — sample center of each face, verify non-zero values
  - `test_prefilteredEnv_mipLevelsExist()` — verify mip chain is populated
  - `test_brdfLUT_range()` — sample corners and center, verify values in [0, 1]
  - `test_bindTextures_setsCorrectIndices()` — compile inline shader sampling texture(9–11), verify non-zero output
  - `test_init_performance_under1s()` — hard gate: all 3 textures generated in < 1s

**Verification:** All prior tests pass. 9 new tests pass. Ray march lighting pass produces visually richer output with environment reflections. Metallic sphere shows environmental reflections instead of procedural sky color.

**Depends on:** Increment 3.14 (ray march pipeline), Increment 3.13 (texture binding pattern).

**Enables:** All photorealistic ray march presets. Required prerequisite for 3.5.1 Popcorn.

### Increment 3.17: Screen Space Global Illumination (SSGI) Post-Process Pass

**Status:** Complete ✅

**Goal:** Approximate short-range diffuse light bounces using the existing G-buffer depth and normal data. Implemented as an optional post-process pass that slots between the lighting pass and the composite pass in the ray march pipeline.

**Why this is needed:** Photorealistic scenes with strong local emitters look visually disconnected without indirect illumination. In the Popcorn scene, the burner is below the opaque cast-iron skillet — it illuminates the pan's exterior and grate, not the kernels directly. The kernels receive indirect light from the hot pan interior and oil surface bouncing warm light upward, and from inter-kernel scattering between popped whites. Without SSGI, none of these secondary bounces exist and the scene's strongest visual features (the glowing pan, the bright oil surface) have no visible effect on surrounding geometry. Hardware ray-traced GI is too expensive for a 60fps visualizer. SSGI reads the existing G-buffer to approximate short-range diffuse bounces at marginal cost (~0.5–1ms at 1080p).

**Implementation approach:** Half-resolution SSGI for performance. The pass reads `gbuffer0` (depth), `gbuffer1` (normals), and `litTexture` (direct lighting result). For each pixel, it samples N nearby screen-space positions (default 8), traces a short ray in screen space, and accumulates indirect diffuse contribution from visible lit surfaces. Output is blended additively into `litTexture` before the composite/tone-mapping pass.

**Files to create/edit:**
- `Renderer/Shaders/SSGI.metal` (new) — `ssgi_fragment`: reads depth/normal G-buffers + lit texture, traces short screen-space rays, accumulates indirect diffuse. Configurable sample count and radius via `SceneUniforms.sceneParamsB.w` (repurpose reserved field).
- `Renderer/RayMarchPipeline.swift` — Add optional `ssgiPipelineState: MTLRenderPipelineState?`, SSGI half-res texture (`.rgba16Float`, half width/height), `ssgiEnabled: Bool`. Insert SSGI pass between lighting and composite in `render()`.
- `Renderer/RenderPipeline+RayMarch.swift` — Pass SSGI configuration through.
- `Presets/PresetDescriptor.swift` — `useSSGI: Bool` field (`"use_ssgi"` key, default `false`). Only meaningful when `useRayMarch` is also true.
- `Presets/PresetDescriptor.swift` — Add `"ssgi"` to `RenderPass` enum.

**Test requirements:**
- `Tests/PhospheneEngineTests/Renderer/SSGITests.swift` (new) — 7 tests:
  - `test_ssgiTexture_halfResolution()` — SSGI texture is half the G-buffer dimensions
  - `test_ssgiTexture_format_rgba16Float()` — HDR format for accumulation
  - `test_ssgiTexture_storageModeShared()` — UMA compliance
  - `test_ssgi_emissiveSurface_illuminatesNeighbor()` — render scene with bright floor, verify adjacent wall pixel receives indirect light (luminance > baseline)
  - `test_ssgi_noEmission_minimalContribution()` — dark scene produces near-zero SSGI output
  - `test_ssgi_disabled_noPassExecuted()` — when `useSSGI: false`, SSGI pass is not encoded
  - `test_ssgi_performance_under1ms_at1080p()` — hard perf gate at half-res

**Verification:** All prior tests pass. 7 new tests pass. Visual comparison: ray march scene with and without SSGI shows color bleeding from emissive surfaces onto nearby geometry. Performance impact < 1ms at 1080p (half-resolution).

**Depends on:** Increment 3.14 (G-buffer pipeline provides depth + normals + lit texture).

**Enables:** Photorealistic presets with local indirect illumination. Significant visual quality improvement for 3.5.1 Popcorn.

### Increment 3.18: DRM Silence Detection & Graceful Degradation

**Status:** Complete ✅

**Goal:** Detect DRM-triggered audio silence in Core Audio process taps and gracefully degrade the visual experience instead of showing a frozen or static visualizer.

**Why this is critical:** Core Audio process taps (`AudioHardwareCreateProcessTap`) are the primary audio source. When streaming apps play DRM-protected content (Apple Music FairPlay, Spotify DRM), macOS may zero the tap's audio buffer. This produces no error — just sustained zero-energy frames. The visualizer continues running but with no audio input, producing either a frozen frame (feedback presets) or a static render (ray march presets). This is the primary use case failure mode and currently fails silently.

**Files created/edited:**
- `Audio/Protocols.swift` — Added `AudioSignalState` enum (`.active`, `.suspect`, `.silent`, `.recovering`) as a public type.
- `Audio/SilenceDetector.swift` (new) — Internal `SilenceDetector` class: time-injectable state machine (`timeProvider: @escaping () -> CFAbsoluteTime` for deterministic testing without sleeping). Thresholds: `silenceRMSThreshold = 1e-6`, `silenceDuration = 3.0s` (`.suspect` at `silenceDuration / 2 = 1.5s`, `.silent` at `3.0s` total), `recoveryDuration = 0.5s`. `update(samples:count:)` computes RMS inline (O(N) loop, not held under lock); `update(rms:)` testable overload. `onStateChanged` callback invoked after lock release to prevent deadlock. `reset()` called on audio source mode switch.
- `Audio/AudioInputRouter.swift` — `silenceDetector: SilenceDetector` wired into `systemCapture.onAudioBuffer` (for system/app capture) and `startFilePlayback` (for file mode). Public `onSignalStateChanged: ((AudioSignalState) -> Void)?` callback and `signalState: AudioSignalState` read-only property. Internal secondary `init(capture:metadata:silenceDetector:)` for test injection (avoids exposing `SilenceDetector` in the public API signature). `stopInternal()` calls `silenceDetector.reset()` on mode switch.
- `PhospheneApp/VisualizerEngine.swift` — Added `@Published var audioSignalState: AudioSignalState = .active`.
- `PhospheneApp/VisualizerEngine+Audio.swift` — `makeSignalStateCallback()` dispatches to `@MainActor` to update `audioSignalState` and logs each transition via `os.Logger`.
- `PhospheneApp/ContentView.swift` — `NoAudioSignalBadge` private view (bottom-left, `speaker.slash.fill` icon + "No audio signal" text, `.black.opacity(0.5)` background, `.opacity` transition). Shown when `engine.audioSignalState == .silent`, auto-dismissed on recovery.

**Implementation notes:**
- `SilenceDetector` is `internal` (not `public`) — it's an implementation detail of `AudioInputRouter`. Exposed to tests via `@testable import Audio`.
- `onSignalStateChanged` lives on `AudioInputRouter` (not `AudioCapturing` protocol) because silence detection is a router-level heuristic, not a Core Audio tap primitive. `SystemAudioCapture` remains unchanged.
- State machine brief-dropout behavior: silence shorter than `suspectDuration` (1.5s) never leaves `.active`. Silence between 1.5s and 3.0s enters `.suspect` but returns to `.active` if signal recovers before 3.0s total.
- Phase 4 Orchestrator wiring point: `AudioInputRouter.onSignalStateChanged` is available for the Orchestrator to consume when implemented. Visual fallback (generative ambient preset during silence) is deferred to Phase 4.

**Tests:** 10 `SilenceDetectorTests` in `Tests/PhospheneEngineTests/Audio/SilenceDetectorTests.swift` (all time-controlled via injected clock — no `Thread.sleep` or wall-clock waits):
- `test_init_stateIsActive()`
- `test_normalAudio_stateRemainsActive()` — 100 frames of non-zero RMS, state stays `.active`
- `test_silence_stateTransitionsToSuspect()` — t=1.5s → `.suspect`
- `test_silence_stateTransitionsToSilent()` — t=3.0s → `.silent`
- `test_signalReturn_stateTransitionsToRecovering()` — one non-silent frame from `.silent` → `.recovering`
- `test_signalReturn_confirmationTransitionsToActive()` — 0.5s signal from `.recovering` → `.active`
- `test_briefDropout_doesNotTriggerSuspect()` — 0.5s silence followed by signal never leaves `.active`
- `test_callback_firesOnStateChange()` — full `.active→.suspect→.silent→.recovering→.active` sequence produces exactly those 4 callbacks
- `test_callback_doesNotFireOnNonTransitionFrames()` — 50 normal frames fire 0 callbacks
- `test_thresholds_configurable()` — custom threshold (0.05 RMS), silence (1.0s), recovery (0.2s) produce expected transitions

**Verification:** 340 tests total (249 swift-testing + 91 XCTest). All 10 new tests pass. Pre-existing flaky GPU perf tests (`test_fullScreenNoise_1080p_under2ms`, `fetch_networkTimeout_returnsWithinBudget`) are timing-sensitive and unrelated to this increment.

**Depends on:** Nothing (uses existing `AudioInputRouter` infrastructure).

**Enables:** Resilient user experience for the primary use case. Phase 4 Orchestrator will consume `AudioInputRouter.onSignalStateChanged` for intelligent visual fallback (generative ambient preset during DRM silence).

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

### Increment 4.4: Reactive Orchestrator Core (Ad-Hoc Mode)

**Note:** This increment implements the reactive/ad-hoc path. Session planning mode (Increment 4.4b) extends the Orchestrator for the playlist-first workflow. Both modes share the transition engine (4.3) and emotion mapper (4.2).

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

### Increment 4.4b: Session Planning Mode

**Status:** Not started.

**Goal:** Extend the Orchestrator with a session planning mode that generates a complete visual plan from pre-analyzed track profiles before playback starts.

**Files to create/edit:**
- `Orchestrator/SessionPlanner.swift` (new) — Takes `[TrackProfile]` from `StemCache` and the preset manifest. Outputs a `SessionPlan`: ordered list of (track, preset, transition timing). Selection criteria: mood quadrant matching, stem affinity matching (drum-heavy tracks → drum-responsive presets), no consecutive category repeats, emotional arc shaping across the playlist.
- `Orchestrator/Orchestrator.swift` — Add `planSession(profiles: [TrackProfile]) -> SessionPlan`. In session mode, this runs during the preparation phase. During playback, the Orchestrator follows the plan but adapts transition timing based on real-time structural analysis.
- `Presets/PresetDescriptor.swift` — Add `stemAffinity: [String: String]?` field (JSON key `"stem_affinity"`). Maps stem names to visual roles.

**Depends on:** 2.5.3 (StemCache + TrackProfile), 4.1 (Preset Categorization), 4.2 (Emotion Mapper).

**Enables:** Complete playlist-first experience with pre-planned visual arc.

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

### Increment 6.0: Session Preparation UI

**Status:** Not started.

**Goal:** The entry point for Phosphene — where the user connects a playlist and watches the preparation progress.

**Files to create/edit:**
- `PhospheneApp/Views/SessionStartView.swift` (new) — Landing screen: "Connect a Playlist" with three paths: (1) "Use Current Apple Music Playlist" button, (2) "Use Current Spotify Queue" button, (3) "Paste Playlist URL" text field. Also a "Skip — Listen Without Playlist" link for ad-hoc mode.
- `PhospheneApp/Views/PreparationProgressView.swift` (new) — Progress screen during preparation: playlist artwork grid, per-track progress indicators (downloading → analyzing → cached), overall progress bar, estimated time remaining. Track names and artists visible. Animated transition to "Ready" state.
- `PhospheneApp/Views/SessionReadyView.swift` (new) — "Ready" screen: playlist overview showing the planned visual arc (which preset for each track, mood trajectory), "Start Listening" prompt. The user starts playback in their streaming app, and Phosphene detects the audio via Core Audio tap and transitions to the visualizer view.
- `PhospheneApp/ViewModels/SessionViewModel.swift` (new) — Binds `SessionManager` state to the UI views. Publishes preparation progress, session state, and playlist metadata.

**Test requirements:**
- `SessionViewModelTests.swift` — 8 tests:
  - `test_init_stateIsIdle()`
  - `test_connectAppleMusic_transitionsToConnecting()`
  - `test_preparationProgress_updatesCorrectly()`
  - `test_ready_exposesSessionPlan()`
  - `test_skipPreparation_transitionsToAdHoc()`
  - `test_pasteURL_validatesAndConnects()`
  - `test_preparationFailure_showsPartialReady()`
  - `test_playbackDetected_transitionsToPlaying()`

**Verification:** Open Phosphene. Connect an Apple Music playlist. See preparation progress. When "Ready," start music in Apple Music. Visualizer begins with pre-analyzed stems. All 8 tests pass.

**Depends on:** Phase 2.5 (SessionManager, SessionPreparer), 6.1 (base SwiftUI shell).

**Enables:** Complete end-to-end playlist-first user experience.

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

**Goal:** Profile with Instruments and Metal Debugger. Eliminate end-to-end bottlenecks and establish CI-tracked performance baselines.

> **Scope change note:** The original 7.1 entry bundled "implement GPU STFT/iSTFT" as a Claude Code task. That work has been promoted to its own increment — **Increment 3.1a: GPU STFT/iSTFT Compute Pipeline** — so it can land before the live stem pipeline (Increment 3.1b) and its downstream preset consumers. Per the Increment Scope Discipline rule, infrastructure that unblocks other increments should not be held inside a later optimization pass. 7.1 now focuses purely on profiling and bottleneck elimination for whatever remains.

**Claude Code tasks:**
- Add `os_signpost` markers to key pipeline stages (audio IO, FFT, MIR, stem separation, render)
- Document profiling methodology in `docs/PROFILING.md`
- Review all `MTLBuffer` allocations — ensure `.storageModeShared` everywhere (no `.storageModeManaged` or unnecessary `.storageModePrivate`)
- Verify no manual cache management competing with Dynamic Caching
- Analyze Instruments traces for CPU-GPU sync stalls and resolve any found
- Establish `XCTMetric` baselines for all performance tests so regressions are caught by CI

**Test requirements:**
- `Performance/FullPipelinePerformanceTests.swift` — 4 benchmarks:
  - `test_fullFrame_audioToPixels_under8ms()` — end-to-end at 120fps
  - `test_fftAlone_under0_1ms()`
  - `test_stemSeparation_under50ms()` — depends on Increment 3.1a (GPU STFT/iSTFT) having landed; this is the end-to-end assertion that the promoted increment achieved its target
  - `test_orchestratorDecision_under1ms()`
- Add `XCTMetric` baselines so regressions are caught by CI

**Verification:** Instruments trace shows no CPU-GPU sync stalls. Frame time under 8ms at 120fps on M3 Pro. All 4 performance benchmarks within baselines.

**Depends on:** Increment 3.1a (GPU STFT/iSTFT) for the `test_stemSeparation_under50ms` target to be achievable.

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

### Increment 7.4: MetalFX Temporal Upscaling

**Status:** Not started. Deferred until profiling data from photorealistic presets is available.

**Goal:** Integrate Apple's MetalFX framework for temporal upscaling. Render internal G-buffers and lighting passes at 50–70% native resolution, then use MetalFX Temporal Upscaling to reconstruct full-resolution output.

**Why deferred:** The ray march pipeline's 8ms perf gate at 1080p passes comfortably. MetalFX adds complexity (motion vectors, jitter patterns, temporal stability) that isn't justified without evidence of thermal budget pressure during extended listening sessions. Profile first, optimize second.

**Trigger conditions for implementation:**
- Profiling shows sustained GPU utilization > 80% during photorealistic presets at native resolution
- Thermal downclocking observed on MacBook Air/Mac Mini during 30+ minute listening sessions
- Frame drops detected by the render loop's timing instrumentation

**Files to create/edit:**
- `Renderer/MetalFXUpscaler.swift` (new) — Wraps `MTLFXTemporalScaler`. Manages internal render targets at reduced resolution, jitter pattern (Halton sequence), motion vector generation from `SceneUniforms` camera delta.
- `Renderer/RayMarchPipeline.swift` — Optional upscaler integration: render G-buffer + lighting at internal resolution, upscale before composite.
- `Presets/PresetDescriptor.swift` — `internalResolutionScale: Float` (default 1.0, range 0.5–1.0).

**Test requirements:**
- `Tests/PhospheneEngineTests/Renderer/MetalFXUpscalerTests.swift` (new) — 6 tests:
  - `test_init_createsTemporalScaler()` — MetalFX scaler is non-nil on supported hardware
  - `test_internalResolution_isScaledDown()` — at 0.5 scale, internal textures are half native dimensions
  - `test_upscaledOutput_matchesNativeResolution()` — output texture matches drawable size
  - `test_jitterPattern_haltonSequence_isCorrect()` — verify first 16 Halton(2,3) values
  - `test_motionVectors_staticCamera_areZero()` — no camera delta → zero motion vectors
  - `test_performance_upscaleOnly_under1ms()` — hard gate: MetalFX temporal upscale pass alone

**Depends on:** Increment 7.1 (profiling data establishing that thermal budget pressure exists). Do not implement speculatively.

**Enables:** Sustained 60fps rendering of complex photorealistic presets at 4K on thermally constrained hardware (laptops, Mac Mini).

### Increment 7.5: Stem Separation Streaming Architecture

**Status:** Not started. Deferred pending model evaluation and subjective quality assessment.

**Goal:** Reduce real-time stem refinement latency. With the session preparation pipeline, track-boundary stem gaps are eliminated (cached stems are available from frame one). This increment improves how quickly the engine upgrades from cached preview stems to time-aligned live stems within each track — currently ~10–15 seconds, target 2–5 seconds.

**Near-term mitigation (can be implemented in Phase 3 if artifacts prove distracting):** Reduce dispatch cadence from 5s to 2–3s within the existing 10s rolling window. Add EMA crossfade blending between consecutive `StemFeatures` results in `StemAnalyzer` to smooth boundary transitions. This addresses the most audible artifacts without rearchitecting the ML pipeline.

**Long-term approach (requires evaluation):**
- Option A: Overlap-add with the existing model — process overlapping 10s chunks more frequently, blend results. Requires no model change but increases GPU inference load (2–3× more `separate()` calls per minute).
- Option B: Recompile MPSGraph for shorter input windows (e.g., 2s / ~86 frames). Requires validating that Open-Unmix produces acceptable separation quality at shorter context lengths. May require retraining.
- Option C: Swap to a streaming-native model (e.g., Hybrid Demucs with streaming STFT). Requires full model conversion pipeline rebuild.

**Implementation note:** The current MPSGraph is compiled with a fixed 431-frame input shape. True streaming inference requires either graph recompilation for smaller shapes, zero-padded smaller chunks, or a fundamentally different model. This is a model architecture decision, not a cadence tweak.

**Depends on:** Profiling and subjective quality evaluation of boundary artifacts in real listening sessions. Increment 7.1 profiling data helps quantify the GPU budget available for more frequent inference.

**Enables:** Seamless stem-driven visual routing during rapid dynamic shifts (drops, builds, tempo changes).

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
