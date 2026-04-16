# CLAUDE.md — Phosphene

## What This Is

Phosphene is a native macOS music visualization engine for Apple Silicon. Before the music starts, Phosphene connects to a playlist, downloads 30-second preview clips for every track, and runs full ML-powered stem separation and MIR analysis on each. By the time the user presses play, the AI Orchestrator has planned the entire visual session — which visualizer for each track, where transitions land, and what the emotional arc looks like across the playlist. During playback, real-time audio analysis via Core Audio taps (`AudioHardwareCreateProcessTap`) refines the pre-analyzed data, and the Orchestrator adapts its plan as the music unfolds.

Phosphene does not control playback — the user starts the music in their streaming app when Phosphene signals it is ready.

See `docs/PRODUCT_SPEC.md` for the full product definition, `docs/ARCHITECTURE.md` for system design, `docs/DECISIONS.md` for rationale behind key choices, and `docs/RUNBOOK.md` for build/test/CI/troubleshooting.

## Build & Test

```bash
xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build
swift test --package-path PhospheneEngine
xcodebuild -scheme PhospheneApp -destination 'platform=macOS' test
swiftlint lint --strict --config .swiftlint.yml
```

Warnings-as-errors is enforced per-target via `PhospheneApp/Phosphene.xcconfig` — do NOT pass the flag on the command line (conflicts with SPM dependency `-suppress-warnings`).

Deployment target: macOS 14.0+ (Sonoma). Swift 6.0. Metal 3.1+.

All tests must pass before any new code is merged (regression gate).

## Module Map

```
PhospheneApp/               → SwiftUI shell, views, view models
  ContentView.swift         → Main view (hosts MetalView + DebugOverlay + NoAudioSignalBadge)
  PhospheneApp.swift        → App entry point
  VisualizerEngine.swift    → Audio→FFT→render pipeline owner
  VisualizerEngine+Audio.swift → Audio routing, MIR analysis, mood classification, signal state callbacks
  VisualizerEngine+Stems.swift → Background stem separation pipeline, 5s cadence, track-change reset
  VisualizerEngine+Presets.swift → makeSceneUniforms(from:) for ray march camera/light setup
  Views/MetalView.swift     → NSViewRepresentable wrapping MTKView

PhospheneEngine/
  Audio/
    SystemAudioCapture      → Core Audio tap: system-wide or per-app
    AudioInputRouter        → Unified source: .systemAudio/.application/.localFile → callbacks + dual analysis/render frames
    LookaheadBuffer         → Timestamped ring buffer, dual read heads (analysis + render), configurable 2.5s delay
    AudioBuffer             → IO proc → UMARingBuffer<Float> bridge for GPU
    FFTProcessor            → vDSP 1024-pt FFT → 512 magnitude bins in UMABuffer
    SilenceDetector         → DRM silence state machine: .active → .suspect (1.5s) → .silent (3s) → .recovering → .active (0.5s hold)
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
    BeatDetector            → 6-band onset detection, grouped beat pulses, tempo via autocorrelation
    BeatDetector+Tempo      → IOI histogram + autocorrelation tempo estimation
    MIRPipeline             → Coordinator: all analyzers → FeatureVector for GPU
    SelfSimilarityMatrix    → Ring buffer of feature vectors, vDSP cosine similarity
    NoveltyDetector         → Checkerboard kernel boundary detection, adaptive threshold
    StructuralAnalyzer      → Section boundary prediction, repetition detection
    StemAnalyzer            → Per-stem energy (4× BandEnergyProcessor) + beat (1× BeatDetector on drums) → StemFeatures
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
    RenderPipeline+ICB      → Indirect command buffer: drawWithICB, populate compute + execute render
    RayMarchPipeline        → Deferred 3-pass: G-buffer textures, lighting pipeline, composite pipeline
    RayMarchPipeline+Passes → SSGI pass extraction for file-length compliance
    PostProcessChain        → HDR scene texture, bloom ping-pong, 4 pipeline states, ACES composite
    IBLManager              → Irradiance cubemap (32²) + prefiltered env (128², 5 mips) + BRDF LUT (512²)
    TextureManager          → 5 noise textures via Metal compute at init, bound at texture(4–8)
    Geometry/ProceduralGeometry → GPU compute particle system: UMA buffer + compute + render pipelines
    Geometry/MeshGenerator  → M3+ mesh shader + M1/M2 vertex fallback, draw dispatch abstraction
    RayTracing/BVHBuilder   → MTLPrimitiveAccelerationStructure, blocking + non-blocking paths
    RayTracing/RayIntersector → Compute-pipeline intersector, nearest-hit + shadow kernels
    Shaders/Common.metal    → FeatureVector/FeedbackParams structs, hsv2rgb, fullscreen_vertex, feedback shaders
    Shaders/MeshShaders.metal → Mesh pipeline structs, object/mesh/fragment + fallback vertex shaders
    Shaders/Particles.metal → Murmuration compute kernel + bird silhouette vertex/fragment
    Shaders/PostProcess.metal → Bright pass, Gaussian blur H/V, ACES composite
    Shaders/RayTracing.metal → RT structs, nearest-hit kernel, shadow kernel, camera ray utils
    Shaders/RayMarch.metal   → Cook-Torrance PBR deferred lighting (IBL ambient tinted by lightColor), composite fragment, depth/G-buffer debug pipelines
    Shaders/SSGI.metal       → Screen-space global illumination (8-sample spiral, half-res, additive blend)
    Shaders/NoiseGen.metal   → Compute kernels: gen_perlin_2d, gen_perlin_3d, gen_fbm_rgba, gen_blue_noise
    Shaders/IBL.metal        → IBL generation kernels + sampling utilities
  Presets/
    PresetLoader            → Auto-discover, compile standard + additive + mesh + ray march pipelines, skip utility files
    PresetLoader+Preamble   → Shared preamble: FeatureVector struct → ShaderUtilities → noise samplers → preset code. Forwards `sceneMaterial(p, matID, FeatureVector& f, SceneUniforms& s, ...)` so ray-march presets can apply identical audio-reactive deformation in both sceneSDF and sceneMaterial (DECISIONS D-021).
    PresetDescriptor        → JSON sidecar: passes, feedback params, scene camera/lights, stem affinity
    PresetDescriptor+SceneUniforms → Constructs SceneUniforms from descriptor (camera basis, light, fog, near/far). FOV converted from JSON degrees → radians exactly once.
    PresetCategory          → 11 aesthetic families
    Shaders/ShaderUtilities.metal → 55 reusable functions: noise, SDF, PBR, ray march, UV, color, atmosphere
    Shaders/Waveform.metal  → Spectrum bars + oscilloscope
    Shaders/Plasma.metal    → Demoscene plasma
    Shaders/Nebula.metal    → Radial frequency nebula
    Shaders/Starburst.metal → Murmuration sky backdrop
    Shaders/GlassBrutalist.metal → Brutalist corridor — static architecture; only the glass-fin X-position deforms with bass (Option A design, see DECISIONS D-020). Light/fog/colour modulated in shared Swift path.
    Shaders/KineticSculpture.metal → Interlocking lattice of Brushed Aluminum + Frosted Glass + Liquid Mercury, abstract ray march. FOV in degrees (post-fix; was radians, see commit history).
    Shaders/TestSphere.metal → Minimal pipeline-verification SDF (sphere + floor); used for end-to-end ray-march compile/render test.
    Shaders/VolumetricLithograph.metal → Psychedelic linocut terrain (3.5.4 / v4). fbm3D heightfield swept by `s.sceneParamsA.x` at slow rate 0.015; melody-primary blend `0.75 × (f.mid_att × 15) + 0.35 × (f.bass_att × 1.2)` — works for both percussive (Love Rehab) and melodic (Tea Lights) music. Forward camera dolly at 1.8 u/s (configured in VisualizerEngine+Presets.swift). Three strata with narrow linocut coverage (~15% peaks): palette-tinted near-black valleys, razor-thin emissive ridge-line seam, polished-metal peaks. Peaks use IQ cosine `palette()` driven by terrain noise + audio time + `f.mid_att × 3` (melody-modulated hue) + valence. `smoothstep(0.35, 0.70, f.spectral_flux)` drives palette brightness flare (× 1.8 peak, × 2.4 ridge) into HDR bloom + 0.02 coverage expansion — genre-agnostic accent that fires on kick drums, guitar strums, vocal onsets, piano chord changes alike. `sqrt(f.mid) × 1.6` polishes peak roughness. `scene_fog: 0` truly disables fog. Miss/sky pixels tinted by `scene.lightColor.rgb`. SSGI omitted.
  Orchestrator/             → AI VJ: preset selection, transitions, session planning (stub — see ENGINEERING_PLAN.md Phase 4)
  Session/
    SessionManager          → Lifecycle state machine (idle→connecting→preparing→ready→playing→ended), @MainActor ObservableObject; degrades gracefully on connector/preparation failure
    PlaylistConnector       → Apple Music (AppleScript) / Spotify (Web API) / URL parsing
    TrackIdentity           → Stable cache key: title, artist, album, duration, catalog IDs
    SessionTypes            → SessionState enum, SessionPlan stub (expanded by Orchestrator in Phase 4)
    PreviewResolver          → iTunes Search API → preview URL, in-memory cache (URL?? semantics), rate limiter (20/60s)
    PreviewDownloader        → Batch download + format-sniff + AVAudioFile decode to mono Float32, withTaskGroup concurrency ceiling (default 4)
    SessionPreparer          → Download → separate → analyze → cache per track, @MainActor ObservableObject with @Published progress
    StemCache                → Thread-safe per-track: stem waveforms + StemFeatures + TrackProfile, NSLock-guarded
    TrackProfile             → BPM, key, mood, spectral centroid avg, genre tags, stem energy balance, estimated section count
  Shared/
    UMABuffer               → Generic .storageModeShared MTLBuffer + UMARingBuffer
    AudioFeatures           → @frozen SIMD-aligned structs (see Key Types below)
    AnalyzedFrame           → Timestamped container: AudioFrame + FFTResult + StemData + FeatureVector + EmotionalState
    StemSampleBuffer        → Interleaved stereo PCM ring buffer for stem separation input (15s)
    RenderPass              → Enum: direct, feedback, particles, mesh_shader, post_process, ray_march, icb, ssgi
    Logging                 → Per-module os.Logger instances (subsystem: "com.phosphene")
    SessionRecorder         → Continuous diagnostic capture per app launch: video.mp4 (H.264, 30 fps) + features.csv + stems.csv + stems/<N>_<title>/{drums,bass,vocals,other}.wav + session.log. Writes to ~/Documents/phosphene_sessions/<timestamp>/. Finalised on NSApplication.willTerminateNotification. Validated by SessionRecorderTests.
Tests/
  Audio/                    → AudioBufferTests, FFTProcessorTests, StreamingMetadataTests, MetadataPreFetcherTests, LookaheadBufferTests, SilenceDetectorTests
  DSP/                      → SpectralAnalyzerTests, BandEnergyProcessorTests, ChromaExtractorTests, BeatDetectorTests, MIRPipelineUnitTests, SelfSimilarityMatrixTests, NoveltyDetectorTests, StructuralAnalyzerTests
  ML/                       → StemSeparatorTests, StemFFTTests, StemModelTests, MoodClassifierTests
  Renderer/                 → MetalContextTests, ShaderLibraryTests, RenderPipelineTests, ProceduralGeometryTests, MeshGeneratorTests, BVHBuilderTests, RayIntersectorTests, PostProcessChainTests, ShaderUtilityTests, TextureManagerTests, RayMarchPipelineTests, SceneUniformsTests, FeatureVectorExtendedTests, SSGITests, RenderPipelineICBTests
  Shared/                   → AudioFeaturesTests, UMABufferExtendedTests, EmotionalStateTests, AnalyzedFrameTests
  Session/                  → SessionManagerTests, PlaylistConnectorTests, PreviewResolverTests, PreviewDownloaderTests, SessionPreparerTests, StemCacheTests
  Integration/              → AudioToFFTPipelineTests, AudioToRenderPipelineTests, MetadataToOrchestratorTests, AudioToStemPipelineTests, MIRPipelineIntegrationTests, LookaheadIntegrationTests, StemsToRenderPipelineTests, SessionPreparationIntegrationTests
  Regression/               → FFTRegressionTests, MetadataParsingRegressionTests, ChromaRegressionTests, BeatDetectorRegressionTests, StructuralAnalysisRegressionTests + golden fixtures
  Performance/              → FFTPerformanceTests, RenderLoopPerformanceTests, StemSeparationPerformanceTests, DSPPerformanceTests
  TestDoubles/              → MockAudioCapture, StubFFTProcessor, FakeStemSeparator, StubMoodClassifier, AudioFixtures, MockMetadataProvider, MockMetadataFetcher
```

---

## Audio Data Hierarchy — The Most Important Design Rule

**Learned the hard way in the Electron prototype. Beat-dominant designs feel out of sync. Continuous-energy-dominant designs feel locked to the music. Non-negotiable.**

### Layer 1: Continuous Energy Bands (PRIMARY VISUAL DRIVER)
`bass`, `mid`, `treble` (3-band) and 6-band equivalents. Zero detection delay. Feedback zoom, rotation, color shifts, geometry deformation — all driven primarily by these.

### Layer 2: Spectrum and Waveform Textures (RICHEST DATA)
512 FFT magnitude bins + 1024 waveform samples → GPU as buffer data, not scalars. Modern GPUs process 512+ bins per fragment.

### Layer 3: Spectral Features (DERIVED CHARACTERISTICS)
Centroid, flux, rolloff, MFCCs, chroma. Modulate color temperature, complexity, scene behavior.

### Layer 4: Beat Onset Pulses (ACCENT ONLY — NEVER PRIMARY)
±80ms jitter from threshold-crossing. Feedback amplifies jitter. Must NEVER be the dominant motion driver.

### Layer 5a: Pre-Analyzed Stems (AVAILABLE FROM FIRST FRAME)
From 30-second preview clips. Available instantly on track change via StemCache. Not time-aligned with live playback.

### Layer 5b: Real-Time Stems (REPLACES 5a AFTER ~10 SECONDS)
From live Core Audio tap via MPSGraph. Time-aligned with playback. Crossfades with 5a.

**Rule of thumb:** `base_zoom` and `base_rot` (continuous energy) should be 2–4× larger than `beat_zoom` and `beat_rot` (onset pulses).

---

## Proven Audio Analysis Tuning

These constants were validated across genres. Do not re-tune from scratch.

### Frequency Bands

**3-band:** Bass 20–250 Hz, Mid 250–4000 Hz, Treble 4000–20000 Hz.

**6-band:** Sub Bass 20–80 Hz, Low Bass 80–250 Hz, Low Mid 250–1000 Hz, Mid High 1000–4000 Hz, High Mid 4000–8000 Hz, High 8000+ Hz.

### AGC (Automatic Gain Control)

Milkdrop-style average-tracking. Output = `raw / runningAverage * 0.5`. Two-speed warmup: fast (0.95 rate, ~1s) then moderate (0.992, ~2s settling). 6-band AGC normalizes against total energy (not per-band) to preserve relative differences.

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

### Tempo

75th percentile of bass flux buffer × 2.0, with 150ms minimum spacing. Known octave-error limitation (basic autocorrelation often returns half-tempo). Pre-fetched BPM from metadata APIs disambiguates.

### Chroma

Bin-count normalized: weight = `1/binsInPitchClass`. Skip bins below 65 Hz. At 48kHz/1024-point FFT, pitch classes get 31–55 bins — without normalization, key estimation is biased.

### Mood Classifier Inputs

10 features: 6-band energy, centroid, flux, major/minor key correlations. NOT raw 12-bin chroma (a tiny MLP cannot learn the Krumhansl-Schmuckler function from raw bins). Spectral flux normalized via running-max AGC (0.999 decay). Centroid normalized by Nyquist (24000 Hz).

---

## Key Types (Shared Module)

```swift
struct FeatureVector          // 32 floats = 128 bytes (SIMD-aligned). GPU buffer(2).
                              // Floats 1–24: energy bands, smoothed bands, beat pulses, spectral features,
                              //   mood valence/arousal, structural prediction fields, camera uniforms.
                              // Float 25: accumulatedAudioTime. Floats 26–32: padding.
struct FeedbackParams         // 32 bytes (8 floats): decay, baseZoom, baseRot, beatZoom, beatRot,
                              //   beatSensitivity, beatValue, padding.
struct StemFeatures           // 64 bytes (16 floats): 4 per stem (vocals/drums/bass/other):
                              //   energy, band0, band1, beat. GPU buffer(3).
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
```

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
buffer(0) = FFT magnitudes (512 floats)
buffer(1) = waveform samples (1024 floats)
buffer(2) = FeatureVector (128 bytes, 32 floats)
buffer(3) = StemFeatures (64 bytes, 16 floats)
buffer(4–7) = future use
```

### Preamble Compilation Order
`FeatureVector struct` → `ShaderUtilities.metal functions` → `constexpr sampler declarations` → preset shader code.

Ray march presets get a separate `rayMarchGBufferPreamble` (includes `raymarch_gbuffer_fragment` which calls preset-defined `sceneSDF`/`sceneMaterial`). This must NOT appear in the shared preamble — standard presets never define those functions.

### G-Buffer Layout (Ray March)
```
gbuffer0: .rg16Float   (depth + materialID)
gbuffer1: .rgba8Snorm  (normals)
gbuffer2: .rgba8Unorm  (albedo + material)
litTexture: .rgba16Float (lighting output)
```

### SSGI
Half-res `.rgba16Float`. 8-sample blue-noise-rotated spiral. `kIndirectStrength = 0.3`. Sky pixels (depth ≥ 0.999) early-exit. Additive blend (src=one, dst=one). `sceneParamsB.w` overrides sample radius (0 → default 0.08 UV).

### AccumulatedAudioTime
`_accumulatedAudioTime += max(0, energy) * deltaTime` where energy = `(bass + mid + treble) / 3.0`. Reset on track change via `pipeline.resetAccumulatedAudioTime()`. Written to `sceneUniforms.sceneParamsA.x` each frame for ray march presets. Exposed as `FeatureVector.accumulated_audio_time` (float 25) for all presets.

### Mesh Shader Architecture
Hardware gated: `device.supportsFamily(.apple8)` (M3+). On M3+: `MTLMeshRenderPipelineDescriptor` + `drawMeshThreadgroups`. On M1/M2: standard vertex pipeline + `drawPrimitives`. `MeshGenerator` owns both and abstracts dispatch. MSL: `[[thread_index_in_threadgroup]]` is correct; `[[thread_index_in_mesh]]` does not exist. `ObjectPayload` uses `object_data` address space.

### ICB Architecture
`icb_populate_kernel` reads FeatureVector, activates slots based on cumulative energy thresholds. `setFragmentBytes` is NOT inherited by ICB commands — use `setFragmentBuffer` bindings. Pipelines must set `supportIndirectCommandBuffers = true`. Use `useResource(_:usage:stages:)` (stages-aware API, macOS 13+).

---

## Preset Metadata Format

```json
{
  "name": "Glass Brutalist",
  "family": "geometric",
  "duration": 30,
  "passes": ["ray_march", "ssgi", "post_process"],
  "scene_camera": { "position": [0, 2, -3], "target": [0, 2, 4], "fov": 65 },
  "scene_lights": [{ "position": [0, 4.5, 2], "color": [1, 0.95, 0.9], "intensity": 3.0 }],
  "scene_fog": 0.015,
  "scene_ambient": 0.08,
  "stem_affinity": {
    "drums": "pillar_squeeze",
    "bass": "pillar_scale",
    "other": "glass_scale",
    "vocals": "color_warmth"
  }
}
```

| Field | Default | Notes |
|-------|---------|-------|
| `name` | required | Display name |
| `family` | required | Aesthetic family: `fluid`, `geometric`, `abstract`, `fractal`, etc. |
| `duration` | 30 | Preferred scene duration (seconds). Orchestrator can override. |
| `passes` | `["direct"]` | Required render passes. Backward-compatible: falls back to `synthesizePasses(from:)` reading legacy booleans. |
| `beat_source` | `"bass"` | Which onset drives beat uniform: `bass`, `mid`, `treble`, `composite` |
| `beat_zoom` | 0.03 | Beat accent zoom (keep < base_zoom) |
| `beat_rot` | 0.01 | Beat accent rotation |
| `base_zoom` | 0.12 | Continuous energy zoom (primary driver) |
| `base_rot` | 0.03 | Continuous energy rotation (primary driver) |
| `decay` | 0.955 | Feedback decay. 0.85 = short trails, 0.95 = long. |
| `beat_sensitivity` | 1.0 | Beat pulse multiplier. Range 0–3.0. |
| `stem_affinity` | optional | Maps stems to visual parameters for Orchestrator pairing. |
| `mesh_thread_count` | 64 | Thread count for mesh shader dispatch. |

---

## Session Preparation Pipeline

**Lifecycle:** `idle` → `connecting` → `preparing` → `ready` → `playing` → `ended`.

**Per-track preparation:** Download preview (iTunes Search API `previewUrl`) → decode to PCM (AVAudioFile) → stem separation (MPSGraph, ~142ms) → MIR pipeline (BPM, key, mood, spectral, structural) → cache in StemCache.

**Track transition behavior:** On track change, `VisualizerEngine` loads cached stems from StemCache — StemFeatures is populated immediately, never zeroed. StemSampleBuffer is NOT cleared (ring buffer continues for real-time refinement). Real-time separation crossfades with cached data after ~10–15s. No preset ever sees zero stems during a playlist session.

**Performance budget:** 142ms stem separation per track. Preview downloads are the bottleneck (~10MB total). Total: ~20–30 seconds for a 20-track playlist.

**Metadata fetcher priority:** MusicBrainz (always, free) → Soundcharts (optional, commercial, gated by env vars) → Spotify (optional, search-only) → MusicKit (optional). Self-computed MIR is the authoritative source.

---

## ML Inference

No CoreML dependency. All ML uses MPSGraph (GPU) or Accelerate (CPU).

**Stem separator (MPSGraph):** Open-Unmix HQ. Float32 throughout. 172 weight tensors (135.9 MB) in `ML/Weights/`, Git LFS. STFT: n_fft=4096, hop=1024, sample_rate=44100, 431 frames (~10s). Bidirectional 3-layer LSTM, hidden=256, gate_size=1024. BN fused at init (12 fusions). STFT/iSTFT via Accelerate/vDSP. Input magnitudes written directly to pre-allocated MTLBuffers via memcpy. 142ms warm predict. Hard gate: 400ms.

**Mood classifier (Accelerate):** 4-layer MLP (10→64→32→16→2) via 3× `vDSP_mmul`. 3,346 hardcoded Float32 params from DEAM training. Outputs continuous valence/arousal (-1…1), EMA smoothed.

**Stem separation cadence:** Background `DispatchSourceTimer`, 5s, utility QoS. Track-change loads from StemCache first, then live refinement crossfades.

---

## Code Style

- Swift 6.0, `SWIFT_STRICT_CONCURRENCY = complete`. `async`/`await` and actors. Avoid raw `DispatchQueue` except for Accelerate/vDSP.
- Shared types: `Sendable`. Audio frame types: `@frozen`, SIMD-aligned.
- `NSLock.withLock {}` from synchronous contexts only. For types mixing sync callbacks with async API, use `@unchecked Sendable` class with NSLock.
- No `print()`. Use `os.Logger` via `Shared/Logging.swift`.
- SwiftLint: `force_cast`/`force_try`/`force_unwrapping` → error. `file_length` warning at 400. `cyclomatic_complexity` warning at 10.
- All `public` API has `///` doc comments. Every file uses `// MARK: -` dividers.
- Protocol-first design. Every injectable dependency has a protocol. Tests use doubles from `TestDoubles/`.

---

## Failed Approaches — Do Not Repeat

1. **IIR energy-difference beat detection (3-band)**: Machine-gun false positives.
2. **Rising-edge accumulation**: IIR filters oscillate, defeating the accumulator.
3. **FFT-based per-bin spectral flux**: Threshold tuning intractable across genres.
4. **Beat-dominant visual design** (beat_zoom >> base_zoom): ±80ms jitter amplified by feedback.
5. **BlackHole virtual audio driver**: Broken on macOS Sequoia.
6. **Web Audio API AnalyserNode**: Broken for virtual devices on macOS.
7. **ScreenCaptureKit for audio-only capture**: Zero audio callbacks on macOS 15+/26.
8. **AcousticBrainz**: Shut down 2022.
9. **MPNowPlayingInfoCenter for reading other apps' metadata**: Only returns host app's own info.
10. **Spotify Audio Features endpoint**: Deprecated Nov 2024, returns 403.
11. **MediaRemote private framework** (macOS 15+): Operation not permitted from signed app bundles.
12. **HTDemucs CoreML conversion**: Complex tensor ops block conversion.
13. **End-to-end CoreML audio separation models**: No complex number support in CoreML.
14. **Raw MLMultiArray.dataPointer with ANE Float16 outputs**: Padded strides cause SIGSEGV.
15. **Chroma from low-frequency FFT bins (<500 Hz)**: Bin resolution too coarse for pitch accuracy.
16. **Raw 12-bin chroma as mood input**: Tiny MLP can't learn Krumhansl-Schmuckler from raw bins.
17. **Autocorrelation half-tempo**: Known octave error. Metadata disambiguates.
18. **Median-based tempo threshold**: Half-wave rectified flux is mostly zeros → median ≈ 0.
19. **Unweighted chroma accumulation**: Bin-count bias across pitch classes.
20. **CoreML ANE outputs with bindMemory(to: Float.self)**: Float16 misinterpreted as Float32.
21. **CATapDescription(stereoMixdownOfProcesses: [])**: Empty array = silence. Use `stereoGlobalTapButExcludeProcesses: []`.
22. **Screen capture permission assumption**: Tap creation succeeds without permission but delivers zeros. Must call `CGRequestScreenCaptureAccess()` first.
23. **Architecture deformation in ray-march scene presets**: Bass-driven beam dipping, pillar squeezing, fin Y-stretching all read as broken/rubber. Architecture has implied permanence — modulate light/atmosphere/camera, not the building (DECISIONS D-020).
24. **Modulating only `lightColor` for mood-driven palette shift**: Indoor ray-march scenes are dominated by IBL ambient; the direct light only catches surfaces facing it. Tinting the light alone leaves most pixels colour-unchanged. Multiply IBL ambient by `lightColor.rgb` so the shift propagates everywhere (DECISIONS D-022).
25. **Mood values written to a `@Published` overlay property without a renderer-bound path**: MoodClassifier output reaches the SwiftUI debug overlay but never the GPU FeatureVector unless `RenderPipeline.setMood` is called explicitly and `setFeatures` preserves valence/arousal across overwrites (DECISIONS D-024).
26. **Beat-pulse keyed only to `beatBass`**: Tracks where the kick is buried (Love Shack, anything snare-driven) get no pulse. Use `max(beatBass, beatMid, beatComposite)` for cross-genre coverage.
27. **Synthetic audio for visualizer diagnostics**: Hand-authored FeatureVector envelopes do not reproduce real-music pipeline noise/cross-band correlation/MIR-derived structure. Diagnostic harnesses must run the actual capture path on real audio.
28. **Locking `AVAssetWriter` to the first observed drawable size**: MTKView's drawable size is transient at launch; lock to the first size and later frames at the steady-state size get blitted into a corner of the writer's larger buffer. Defer writer init until N consecutive same-size frames; once locked, skip mismatched frames rather than blit-into-wrong-geometry.
29. **Hardcoded sample rate (44.1 kHz) when the tap reports something else**: Phosphene assumes 44.1/48 kHz internally for stem separation and beat-detection windowing. If the user's Audio MIDI Setup runs at 96 kHz, beat windows and BPM math are off by ~2.18×. Set Audio MIDI Setup to 48 kHz to match (RUNBOOK).
30. **Spotify default normalization (Volume level: Normal)**: Knocks mastered peaks from ~0.7 to ~0.15-0.20, compressing AGC headroom and degrading mood-classifier stability. Toggle Normalize Volume off in Spotify settings (RUNBOOK).

---

## What NOT To Do

- Do not block the render loop on network, ML, or metadata.
- Do not allocate in the Core Audio IO proc callback.
- Do not use `.storageModeManaged` buffers.
- Do not make beat onset the primary visual driver.
- Do not hardcode shader paths.
- Do not normalize 6-band AGC per-band.
- Do not pass `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` on the xcodebuild command line.
- Do not assume Now Playing metadata is available or accurate.
- Do not use `[[thread_index_in_mesh]]` in MSL (does not exist).
- Do not deform architecture geometry with audio in ray-march scene presets — modulate light/atmosphere/camera instead (DECISIONS D-020).
- Do not write to `latestFeatures.valence` / `arousal` from the MIR path. Mood goes through `RenderPipeline.setMood`; `setFeatures` preserves mood across overwrites.
- Do not lock `AVAssetWriter` to the first observed drawable size — defer until N consecutive same-size frames; skip mismatched frames after.
- Do not key visualizer beat-pulse logic to a single onset band — use `max(beatBass, beatMid, beatComposite)` so snare-driven and kick-driven tracks both register.

---

## Current Status

**Phase 3 substantially complete. Phase 2.5 (session preparation) complete.** Recent landed work:

- **Glass Brutalist Option A** — static brutalist corridor; music drives only light/fog/path (DECISIONS D-020). Per-frame Swift modulation in `drawWithRayMarch` reads `BaseSceneSnapshot` so modulation is additive on the JSON baseline.
- **Preamble extension** — `sceneMaterial(p, matID, FeatureVector& f, SceneUniforms& s, ...)` for all three ray-march presets, eliminating boundary-classification mismatch (D-021).
- **IBL ambient tinting** — `iblAmbient *= scene.lightColor.rgb` so mood-driven palette shift propagates across the scene (D-022).
- **Tap reinstall on prolonged silence** — recovers from scrub-induced source teardowns (D-023).
- **Mood injection** — `RenderPipeline.setMood` + valence/arousal preservation in `setFeatures` (D-024).
- **`SessionRecorder`** — continuous diagnostic capture (video + features + stems + WAVs + log) per app launch (D-025).

The next ordered increments are:

1. **Phase 4 — Orchestrator** — scored preset selection, transition policy, session planning, golden-session tests.

See `docs/ENGINEERING_PLAN.md` for the full forward plan with done-when criteria and verification commands.

## Linked Frameworks

Metal, MetalKit, MetalPerformanceShadersGraph, AVFoundation, Accelerate, ScreenCaptureKit (Info.plist only), MusicKit.

## Development Constraints

- **Team**: Matt (product/design direction) + Claude Code (implementation).
- **Platform**: macOS only. Mac mini primary dev/deploy target.
- **Performance target**: 60fps at 1080p on Apple Silicon.
- **Dependencies**: Minimize external. Prefer Apple frameworks.
- **Learning stays local**: On-device only. No cloud, no telemetry.
- **License**: MIT.
