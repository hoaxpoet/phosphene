# CLAUDE.md — Phosphene

## What This Is

Phosphene is a native macOS music visualization engine for Apple Silicon. Before the music starts, Phosphene connects to a playlist, downloads 30-second preview clips for every track, and runs full ML-powered stem separation and MIR analysis on each. By the time the user presses play, the AI Orchestrator has planned the entire visual session — which visualizer for each track, where transitions land, and what the emotional arc looks like across the playlist. During playback, real-time audio analysis via Core Audio taps (`AudioHardwareCreateProcessTap`) refines the pre-analyzed data, and the Orchestrator adapts its plan as the music unfolds.

Phosphene does not control playback — the user starts the music in their streaming app when Phosphene signals it is ready. But Phosphene is not a passive listener. It is a VJ that prepares a show for a known setlist.

The name references the visual phenomenon of perceiving light and patterns without external visual stimulus — exactly what this software does with sound.

### Core Use Cases

1. **Curated playlist session**: The primary use case. The user connects a playlist from Apple Music or Spotify. Phosphene analyzes every track during a brief preparation phase (~20–30 seconds), then signals "Ready." From the first beat of the first song, stems are cached, the visualizer is chosen, and transitions are pre-planned across the entire session. This is how Phosphene is designed to be used.
2. **Listening party backdrop**: Friends gather, each brings a mix. One person connects the playlist, Phosphene prepares the show, and the group watches synchronized visuals on a TV or projector while listening together.
3. **Ambient accompaniment**: Solo listening — reading, working, unwinding — with visuals on a secondary display or in a window. For ad-hoc listening without a connected playlist, Phosphene falls back to its reactive mode (real-time analysis only, no pre-planned arc).
4. **Creative enhancement**: Immersive visual accompaniment to deepen the listening experience.

### Lineage

This is a ground-up native Swift/Metal rewrite. A prior Electron/WebGL prototype (v0.1–v0.2) validated the core audio analysis pipeline, visual feedback architecture, and shader design philosophy. That prototype's proven tuning constants, design decisions, and documented failure modes are preserved in this document. Do not re-learn them.

## Build & Test

```bash
xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build
swift test --package-path PhospheneEngine
xcodebuild -scheme PhospheneApp -destination 'platform=macOS' test
swiftlint lint --strict --config .swiftlint.yml
```

Warnings-as-errors is enforced per-target via `PhospheneApp/Phosphene.xcconfig`
(`SWIFT_TREAT_WARNINGS_AS_ERRORS = YES`) — do NOT pass the flag on the command
line, as it would propagate to SPM dependencies that compile with
`-suppress-warnings` and conflict at the Swift driver level.

Deployment target: macOS 14.0+ (Sonoma). Swift 6.0. Metal 3.1+.

**Current test count: 371 tests** (280 swift-testing + 91 XCTest, across unit, integration, regression, performance). All must pass before any new code is merged.

## Module Map

```
PhospheneApp/               → SwiftUI shell, views, view models
  ContentView.swift         → Main view (hosts MetalView + DebugOverlay) (✓ implemented)
  PhospheneApp.swift        → App entry point
  VisualizerEngine.swift    → Audio→FFT→render pipeline owner (✓ implemented)
  VisualizerEngine+Audio.swift → Audio routing, MIR analysis, mood classification callbacks (✓ implemented)
  VisualizerEngine+Stems.swift → Background stem separation pipeline, 5s cadence, track-change reset (✓ implemented)
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
    BeatDetector+Tempo      → Tempo estimation: IOI histogram + autocorrelation (✓ implemented)
    MIRPipeline             → Coordinator: all analyzers → FeatureVector for GPU (✓ implemented)
    SelfSimilarityMatrix    → Ring buffer of feature vectors, vDSP cosine similarity (✓ implemented)
    NoveltyDetector         → Checkerboard kernel boundary detection, adaptive threshold (✓ implemented)
    StructuralAnalyzer      → Section boundary prediction, repetition detection (✓ implemented)
    StemAnalyzer            → Per-stem energy (4× BandEnergyProcessor) + beat (1× BeatDetector on drums) → StemFeatures (✓ implemented)
  ML/                       → MPSGraph stem separator, Accelerate mood classifier (no CoreML dependency)
    StemSeparator.swift      → STFT → MPSGraph → iSTFT pipeline, StemSeparating protocol (✓ implemented)
    StemSeparator+Reconstruct → iSTFT reconstruction + mono averaging (✓ implemented)
    StemModel.swift          → MPSGraph Open-Unmix HQ inference engine, public API, I/O buffers (✓ implemented)
    StemModel+Graph         → MPSGraph construction: per-stem subgraph, LSTM, FC, BN helpers (✓ implemented)
    StemModel+Weights       → Weight manifest parsing, .bin loading, BN fusion (✓ implemented)
    MoodClassifier.swift    → Accelerate/vDSP MLP → valence/arousal, MoodClassifying protocol (✓ implemented)
    MoodClassifier+Weights  → Hardcoded Float32 weight arrays (3,346 params from DEAM training) (✓ implemented)
    ML.swift                → ML module declaration
  Renderer/                 → Metal context, pipelines, shader library, compute particles, noise textures
    MetalContext            → MTLDevice, command queue, triple-buffered semaphore, shared-texture helper (✓ implemented)
    ShaderLibrary           → Auto-discover .metal files, runtime compilation, cache (✓ implemented)
    RenderPipeline          → Feedback-texture ping-pong, warp/composite/blit passes, particle integration (✓ implemented)
    RenderPipeline+Draw     → Draw paths: direct, mesh, postProcess, feedback, warp, blit, particles (✓ implemented)
    RenderPipeline+MeshDraw → Mesh shader draw path: drawWithMeshShader, offscreen pass, MeshGenerator delegation (✓ implemented)
    RenderPipeline+PostProcess → HDR post-process draw path: drawWithPostProcess, lazy texture allocation (✓ implemented)
    PostProcessChain        → HDR scene texture (.rgba16Float), bloom ping-pong (.rgba16Float half-res), 4 pipeline states, ACES composite (✓ implemented)
    Protocols               → Rendering protocol for DI/testing (✓ implemented)
    Geometry/ProceduralGeometry → GPU compute particle system: UMA buffer + compute pipeline + render pipeline (✓ implemented)
    Geometry/MeshGenerator  → MTLMeshRenderPipelineDescriptor (M3+) + vertex fallback (M1/M2), draw dispatch (✓ implemented)
    RayTracing/BVHBuilder   → MTLPrimitiveAccelerationStructure BVH builder; blocking build() + non-blocking encodeBuild() (✓ implemented)
    RayTracing/RayIntersector → compute-pipeline intersector; nearest-hit + shadow kernels; blocking + non-blocking paths (✓ implemented)
    RayTracing/RayIntersector+Internal → RayGPUData/NearestHitData GPU struct layouts, buffer + pipeline helpers (✓ implemented)
    Shaders/Common.metal    → FeatureVector/FeedbackParams structs, hsv2rgb, fullscreen_vertex, feedback_warp_fragment, feedback_blit_fragment (✓ implemented)
    Shaders/MeshShaders.metal → ObjectPayload/MeshVertex/MeshPrimitive structs, mesh_object_shader, mesh_shader, mesh_fragment, mesh_fallback_vertex (✓ implemented)
    Shaders/Particles.metal → Murmuration compute kernel + bird silhouette vertex/fragment shaders (✓ implemented)
    Shaders/PostProcess.metal → pp_bright_pass_fragment, pp_blur_h/v_fragment (9-tap Gaussian), pp_composite_fragment (ACES tonemapping) (✓ implemented)
    Shaders/RayTracing.metal → RTRay/RTNearestHit structs, rt_nearest_hit_kernel, rt_shadow_kernel, rt_camera_ray, rt_reflect, rt_offset_point (✓ implemented)
    Shaders/RayMarch.metal   → raymarch_lighting_fragment (Cook-Torrance PBR, soft shadows, AO, fog), raymarch_composite_fragment (ACES SDR) (✓ implemented)
    Shaders/NoiseGen.metal   → Compute kernels for generating noise textures at startup: gen_perlin_2d, gen_perlin_3d, gen_fbm_rgba, gen_blue_noise (✓ implemented)
    Shaders/Waveform.metal  → 64-bar FFT spectrum + oscilloscope waveform (✓ implemented)
    TextureManager           → 5 pre-computed noise textures (noiseLQ 256², noiseHQ 1024², noiseVolume 64³, noiseFBM 1024², blueNoise 256²) generated via Metal compute at init, bound at texture(4)–texture(8). (✓ implemented)
  Presets/                  → Preset loading, categorization, hot-reload, feedback + mesh support
    PresetLoader            → Auto-discover .metal presets, compile standard + additive-blend + mesh pipeline states; skips utility files (✓ implemented)
    PresetLoader+Preamble   → Common Metal shader preamble: FeatureVector struct, meshlet structs, hsv2rgb, ShaderUtilities library loaded from bundle (✓ implemented)
    Shaders/ShaderUtilities.metal → 55 reusable functions: hash, noise (Perlin/simplex/Worley/FBM/curl), SDF primitives+ops, ray marching, PBR (Cook-Torrance), UV transforms, color/atmosphere (✓ implemented)
    PresetDescriptor        → JSON sidecar metadata with useFeedback, useMeshShader, usePostProcess, useRayMarch flags (✓ implemented)
    PresetCategory          → Visual aesthetic families (11 categories including abstract) (✓ implemented)
    Shaders/Starburst.metal → "Murmuration" preset — dusk sky gradient backdrop (✓ implemented)
    Shaders/Waveform.metal  → Spectrum bars + oscilloscope preset (✓ implemented)
    Shaders/Plasma.metal    → Demoscene plasma preset (✓ implemented)
    Shaders/Nebula.metal    → Radial frequency nebula preset (✓ implemented)
  Orchestrator/             → AI VJ: anticipation engine, transitions, preset selection (stub)
  Session/                  → Playlist connection, preview pipeline, session state
    PlaylistConnector       → Protocol PlaylistConnecting + concrete Apple Music (AppleScript) / Spotify (Web API) impl (✓ implemented)
    TrackIdentity           → Stable per-track cache key: title, artist, album, duration, catalog IDs (✓ implemented)
    PreviewResolver          → Resolve TrackIdentity → preview URL (iTunes Search API / MusicKit PreviewAssets) (✓ implemented)
    PreviewDownloader        → Batch download + decode AAC/MP3 → PCM via AVAudioFile (✓ implemented)
    SessionPreparer          → Orchestrate: download → separate → analyze → cache → plan (✓ implemented)
    StemCache                → Thread-safe per-track storage: separated stem waveforms + StemFeatures + TrackProfile (✓ implemented)
    TrackProfile             → Pre-computed MIR features per track: BPM, key, mood, spectral summary, stem energy balance (✓ implemented)
  Shared/                   → UMA buffer wrappers, type definitions, logging
    UMABuffer               → Generic .storageModeShared MTLBuffer + UMARingBuffer (✓ implemented)
    AudioFeatures           → @frozen SIMD-aligned structs: AudioFrame, FFTResult, TrackMetadata, PreFetchedTrackProfile (✓ implemented)
    AudioFeatures+Frame     → AudioFrame, FFTResult, StemData (✓ implemented)
    AudioFeatures+Metadata  → MetadataSource, TrackMetadata, PreFetchedTrackProfile (✓ implemented)
    AudioFeatures+Analyzed  → FeatureVector, FeedbackParams, StemFeatures, EmotionalState, StructuralPrediction (✓ implemented)
    AnalyzedFrame           → Timestamped container: AudioFrame + FFTResult + StemData + FeatureVector + EmotionalState (✓ implemented)
    StemSampleBuffer        → Interleaved stereo PCM ring buffer for stem separation input (✓ implemented)
    Logging                 → Per-module os.Logger instances (✓ implemented)
Tests/ (371 tests: 280 swift-testing + 91 XCTest)
  Audio/                    → AudioBufferTests, FFTProcessorTests, StreamingMetadataTests, MetadataPreFetcherTests, LookaheadBufferTests (10)
  DSP/                      → SpectralAnalyzerTests (8), BandEnergyProcessorTests (5), ChromaExtractorTests (6), BeatDetectorTests (7), MIRPipelineUnitTests (4), SelfSimilarityMatrixTests (5), NoveltyDetectorTests (5), StructuralAnalyzerTests (8)
  ML/                       → StemSeparatorTests (7), StemFFTTests (6: vDSP cross-validate, round-trip, fwd perf, inv perf, UMA storage, thread safety), StemModelTests (6: init, silence, cross-validate, perf gate <400ms, UMA storage, thread safety), MoodClassifierTests (7: init, classification, range, quadrants, protocol)
  Renderer/                 → MetalContextTests, ShaderLibraryTests, RenderPipelineTests, ProceduralGeometryTests (7: init, storage mode, dispatch, count, zero-audio, impulse, 1M perf), MeshGeneratorTests (6: descriptor, pipeline state, dispatch, maxVerts=256, maxPrims=512, <16ms perf), BVHBuilderTests (4: build, empty, rebuild, triangleCount), RayIntersectorTests (5: hit, miss, shadow, reflection, 1000-ray <2ms perf), PostProcessChainTests (6: HDR texture alloc, rgba16Float format, bloom threshold, Gaussian luminance preservation, ACES SDR mapping, <2ms perf at 1080p), ShaderUtilityTests (11: preamble inclusion, multi-domain compilation, noise determinism, SDF analytic, ray march hit/miss, PBR energy conservation, kaleidoscope symmetry, palette smoothness, ACES SDR range, fog identity, 1080p noise perf), TextureManagerTests (9: all 5 textures created, noiseLQ 256², noiseHQ 1024², noiseVolume 64³ type3D, noiseFBM rgba8Unorm, all storageModeShared, deterministic across inits, bindTextures sets indices 4–8, <500ms init perf)
  Shared/                   → AudioFeaturesTests (2: StemFeatures layout + SIMD alignment), UMABufferExtendedTests, EmotionalStateTests (4: quadrant classification), AnalyzedFrameTests (3), SceneUniformsTests (5: size/stride, alignment, default values, MSL layout, JSON parse), FeatureVectorExtendedTests (4: size, zero-at-start, accumulation formula, reset)
  Session/                  → PlaylistConnectorTests (8), PreviewResolverTests (6), PreviewDownloaderTests (6), SessionPreparerTests (5: single track, multiple, missing preview, progress, cancellation), StemCacheTests (3: load correct, unknown nil, thread safety)
  Integration/              → AudioToFFTPipelineTests, AudioToRenderPipelineTests, MetadataToOrchestratorTests, AudioToStemPipelineTests, MIRPipelineIntegrationTests (3), LookaheadIntegrationTests (1), StemsToRenderPipelineTests (4: warmup default, separation→analysis, track reset, Swift/MSL size), SessionPreparationIntegrationTests (3: full pipeline, BPM+mood, non-zero stems)
  Regression/               → FFTRegressionTests, MetadataParsingRegressionTests, ChromaRegressionTests (2), BeatDetectorRegressionTests (2), StructuralAnalysisRegressionTests (1) + golden fixtures
  Performance/              → FFTPerformanceTests, RenderLoopPerformanceTests, StemSeparationPerformanceTests (2: hard 400ms gate + measure block), DSPPerformanceTests (3)
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

### Layer 5a: Pre-Analyzed Stems (AVAILABLE FROM FIRST FRAME)
Stem waveforms separated from 30-second preview clips during the session preparation phase. Available instantly on track change — no warmup, no latency. Provides the correct spectral character and energy profile for each instrument in the track, but is not time-aligned with live playback. Each stem feeds its own energy and spectral analysis. Enables targeted visual routing: bass stem drives low-frequency geometric deformation, drum stem triggers particle emission, vocal stem modulates color saturation.

### Layer 5b: Real-Time Stems (REPLACES 5a AFTER ~10 SECONDS)
Full waveform separation from the live Core Audio tap via MPSGraph (Open-Unmix HQ). Arrives ~10–15 seconds into each track. Time-aligned with playback — replaces pre-analyzed stems via crossfade. Same per-stem analysis pipeline. Stems inherit the same hierarchy — their continuous energy is primary, their onset pulses are accent. In ad-hoc mode (no connected playlist), Layer 5a is unavailable and Layer 5b is the only stem source, with the existing ~10s warmup latency.

### Layer 5: Stems (PER-INSTRUMENT ROUTING — NEW IN NATIVE BUILD)
ML-separated audio stems (MPSGraph) (Vocals, Drums, Bass, Other). Each stem feeds its own energy and spectral analysis. Enables targeted visual routing: bass stem drives low-frequency geometric deformation, drum stem triggers particle emission, vocal stem modulates color saturation. Stems inherit the same hierarchy — their continuous energy is primary, their onset pulses are accent.

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

### Photorealistic Fragment Shader Rendering

Presets targeting photorealistic visuals (3D scenes with realistic lighting, materials, textures) use a different architectural pattern from the Milkdrop-style feedback loop. Both coexist in the engine; the shader's JSON sidecar declares which pattern it uses.

**Ray marching architecture (per-fragment):**
1. Construct a perspective ray from UV coordinates + camera uniforms (`FeatureVector.cameraFov`, `cameraPhi`, `cameraTheta`, `cameraDistance`)
2. Sphere-trace against the preset's SDF scene geometry (each preset defines its own `map(float3 p) → float`)
3. On hit: compute surface normal (central differences), determine material ID and UV
4. Evaluate PBR lighting: Cook-Torrance BRDF with metallic/roughness, GGX distribution, Schlick Fresnel, ambient occlusion
5. Cast shadow rays (soft shadows via penumbra estimation), multi-sample AO
6. Sample noise textures (bound at indices 4–7) for surface detail: metal grain, organic variation, weathering
7. Sample environment map (index 8) for reflections and image-based ambient lighting
8. Pass through HDR post-process chain: bloom, ACES tone mapping, color grading

**Why photorealistic presets failed before these additions:** Phosphene's original renderer bound exactly two data sources to fragment shaders: the feedback texture and the audio buffer. Without noise textures, every surface was mathematically smooth — no grain, no imperfection, no organic variation. Without a shared SDF/PBR library, each preset reimplemented ray marching and lighting from scratch (incorrectly). Without camera uniforms, 3D scenes hardcoded arbitrary camera parameters. Without `audioTime`, animation was driven by wall-clock time rather than music-weighted time, making movement feel disconnected from audio energy.

**Noise textures (bound at fixed sampler slots for all shaders):**
- `noise_lq` (texture 4): 256×256 `.r8Unorm` tileable Perlin — cheap lookup for subtle variation
- `noise_hq` (texture 5): 1024×1024 `.r16Float` Perlin — high detail for terrain, clouds, surfaces
- `noise_vol` (texture 6): 64×64×64 3D `.r8Unorm` — volumetric clouds, fog, smoke
- `noise_blue` (texture 7): 256×256 `.r8Unorm` blue noise — dithering, eliminating banding
These correspond to Milkdrop's `sampler_noise_lq`, `sampler_noise_hq`, `sampler_noisevol_hq`. Their absence was the single largest contributor to flat, synthetic-looking procedural textures.

**Shader utility library (`ShaderLib.metal`, compiled into preamble):**
All photorealistic presets share reusable functions: SDF primitives + combinators, ray marching loop, PBR lighting (Cook-Torrance), soft shadows, AO, procedural noise evaluation, cosine palettes, camera ray construction, domain transforms. This eliminates the pattern of each shader poorly reimplementing ray marching fundamentals.

**Audio routing for photorealistic scenes:**
Photorealistic presets map audio to scene *properties*, not feedback transforms:
- Continuous energy → material properties (emissive intensity, roughness), camera orbit speed, light intensity
- Spectral centroid → color temperature of lighting (cool blues ↔ warm oranges)
- Beat pulses → transient events (particle emission, material flash, camera shake)
- Stems → targeted effects (drum → physical impacts, bass → low-frequency deformation, vocal → ambient color saturation)
- `audioTime` → animation phase for organic motion that speeds up during loud passages and slows during quiet ones

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
{
  "stem_affinity": {
    "drums": "cohesion",
    "bass": "body_movement",
    "other": "flutter",
    "vocals": "color_warmth"
  }
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
| `stem_affinity` | optional | Declares which stems this preset uses and how. Enables the Orchestrator to pair tracks with presets that match their stem profile — e.g., drum-heavy tracks with drum-responsive presets. |

The scene manager auto-discovers shader files by scanning the presets directory. No manual registration.

---

## Hard Rules — Architecture

### Platform
- macOS only. No iOS, no cross-platform, no Catalyst, no Electron.
- Metal only. Never OpenGL, never Vulkan, never WebGL. Use Metal Shading Language (MSL).
- Apple frameworks only for system integration. No third-party audio capture or virtual audio drivers.

### Audio Input
- Primary LIVE audio input is Core Audio taps (`AudioHardwareCreateProcessTap`, macOS 14.2+). Secondary audio source: 30-second preview clips (AAC/MP3, DRM-free) downloaded via iTunes Search API / MusicKit for pre-analysis during session preparation. These are decoded to PCM via `AVAudioFile` and run through the stem separation and MIR pipelines before playback begins.
- `SystemAudioCapture` creates a process tap → aggregate device → IO proc pipeline delivering interleaved float32 PCM at 48kHz stereo on a real-time audio thread.
- `AudioInputRouter` abstracts three modes behind a callback API: `.systemAudio` (default), `.application(bundleIdentifier:)`, `.localFile(URL)`. Mode switching is seamless.
- `AudioBuffer` writes interleaved float32 from the IO callback into `UMARingBuffer<Float>` via pointer-based `write(from:count:)`.
- `FFTProcessor` reads the latest 1024 mono samples, applies Hann window, runs vDSP 1024-point FFT, writes 512 magnitude bins into `UMABuffer<Float>` for GPU binding.
- Local file playback via `AVAudioFile` exists only as a fallback for testing/offline use.
- Phosphene never controls music playback. It actively prepares a visual show for a known playlist, but the user initiates playback in their streaming app.
- App sandbox is disabled (`com.apple.security.app-sandbox = false`). `NSScreenCaptureUsageDescription` in Info.plist is kept for future ScreenCaptureKit fallback compatibility.
- **DRM silence detection** (Increment 3.18): Core Audio process taps are vulnerable to DRM-triggered silencing. When apps play protected streams (Apple Music lossless/FairPlay, Spotify DRM), macOS may zero out the tap's audio buffer to prevent capture. Because Phosphene is a passive listener, this breaks the entire pipeline silently — no error, just zero-energy frames producing a static or frozen visualizer. `AudioInputRouter` monitors sustained zero-energy frames (configurable threshold, default 3s). When triggered: (1) surface a non-intrusive visual indicator ("No audio signal detected"), (2) transition to an ambient/generative visual mode that runs without audio input, (3) continue monitoring for signal recovery and seamlessly resume audio-reactive rendering when audio returns. This is the single most important resilience feature for the primary use case (visualizing streaming music).

### Session Preparation Pipeline

Phosphene's primary operating mode is playlist-first: the user connects a playlist before playback begins, and Phosphene pre-analyzes every track so the visual show is ready from the first beat.

**Session lifecycle:**
- `idle` → user hasn't connected a playlist
- `connecting` → reading the playlist from the streaming app
- `preparing` → downloading preview clips, running stem separation + MIR on each track, planning the visual arc
- `ready` → all tracks analyzed, Orchestrator has planned the session, waiting for user to start playback
- `playing` → live session, real-time analysis refining pre-analyzed data, Orchestrator adapting its plan
- `ended` → playlist complete or user stopped

**Playlist connection:**
- Apple Music: AppleScript enumerates `every track of current playlist` — title, artist, album, duration, track index. Uses the existing `StreamingMetadata` AppleScript infrastructure.
- Spotify: Web API `GET /me/player/queue` returns up to 20 upcoming tracks. Fallback: if the user provides a Spotify playlist URL, fetch the full track list via the playlist endpoint.
- Manual: User pastes a playlist URL (Apple Music or Spotify) directly into Phosphene.

**Preview clip pipeline:**
- For each track, resolve a 30-second preview URL via the iTunes Search API (`previewUrl` field — universal, works for any track in the Apple Music catalog regardless of streaming source, no auth required, 20 req/min rate limit). MusicKit `Song.previewAssets` is an alternative for Apple Music subscribers.
- Download AAC/MP3 preview clips, decode to raw PCM via `AVAudioFile`.
- Preview clips are unprotected (no DRM) and freely decodable. This is a different audio path from the Core Audio tap — previews are downloaded files, not captured streams.

**Batch pre-analysis (per track):**
1. Run `StemSeparator.separate()` on the preview PCM → full separated waveforms (drums, bass, vocals, other)
2. Run `StemAnalyzer` on the separated stems → `StemFeatures` (energy, band slots, beat pulse per stem)
3. Run the MIR pipeline on the preview audio → BPM, key, mood (valence/arousal), spectral centroid, chroma
4. Run structural analysis on the preview → section boundary estimates (limited from 30s, but non-zero)
5. Store all results in a `StemCache` keyed by track identity

**Performance budget:** At ~142ms per stem separation on Apple Silicon (MPSGraph), a 20-track playlist pre-analyzes in ~3 seconds of compute. Preview downloads are the bottleneck (~10MB total, a few seconds on broadband). Total preparation time: ~20–30 seconds for a full playlist.

**Track transition behavior (replaces the current hard-reset model):**
- On track change, `VisualizerEngine` loads cached stems and MIR data for the new track from the `StemCache`. `StemFeatures` is populated immediately — never zeroed.
- `StemSampleBuffer` is NOT cleared. The ring buffer continues accumulating audio from the Core Audio tap for real-time refinement.
- Real-time separation runs in the background on its normal cadence. When the first real-time result arrives (~10–15s into the track), it crossfades with and then replaces the cached preview data.
- No preset ever sees zero stems during a playlist session. No warmup fallback is needed.

**Orchestrator session planning:**
- Before playback starts, the Orchestrator has a `TrackProfile` for every track in the playlist: BPM, key, mood, stem energy balance, genre tags, duration.
- It plans the full visual session: which preset for each track (matched by mood and stem affinity), where transitions land, what the emotional arc looks like across the playlist.
- Preset pipeline states can be pre-compiled for every preset the plan uses, eliminating runtime compilation hitches during transitions.
- During playback, the plan adapts — real-time MIR may reveal structural details the 30-second preview missed, and the Orchestrator adjusts transition timing accordingly.

### Real-Time Refinement Layer (Active During Playback)

During a playlist session, the session preparation pipeline provides the primary data. These three systems refine and extend that data in real time as each track plays. In ad-hoc mode (no connected playlist), these systems are the primary — and only — source of anticipation.

1. **Lookahead Buffer** — A deliberate 2.5s delay between audio analysis and visual rendering. The Orchestrator sees both the real-time analysis head (for anticipation) and the delayed render head (for current state). Always active internally.

2. **Metadata Pre-Fetching** — On track change (via Now Playing), fire parallel async queries to MusicBrainz, Spotify Web API, Apple Music catalog. Match by title+artist. Cache in LRU. 3-second timeouts. In playlist mode, this data is already cached from the preparation phase. In ad-hoc mode, this is the "fast hint" that accelerates the first ~15 seconds.

3. **Progressive Structural Analysis** — Self-similarity matrix from chroma + MFCC features. Novelty detection finds section boundaries. After 2+ boundaries, predict future boundary timestamps. This supplements the coarse structural data from the 30-second preview with time-aligned, complete structural analysis from the full track.

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
- Noise textures are generated once at startup via Metal compute shaders. Bound at texture indices 4–7, available to every preset shader. Never generate noise textures on CPU — compute shader path is 10–50× faster and textures live in `.storageModeShared` memory with no copy.
- `ShaderLib.metal` functions are compiled into the preamble (same mechanism as `Common.metal`). Preset shaders call any `sdf_*`, `rm_*`, `pbr_*`, `noise_*`, `color_*`, `transform_*`, `camera_*` function without redeclaring.
- Camera uniforms in `FeatureVector` (`audioTime`, `cameraFov`, `cameraDistance`, `cameraPhi`, `cameraTheta`) are populated by the render loop every frame. Default values produce a reasonable orbit camera for 3D SDF scenes. The Orchestrator can override via `PresetDescriptor`.
- **Texture binding layout (revised):** texture(0) = feedback read, texture(1) = feedback write, texture(2–3) = reserved, texture(4) = noiseLQ (256² Perlin FBM), texture(5) = noiseHQ (1024² Perlin FBM), texture(6) = noiseVolume (64³ 3D FBM), texture(7) = noiseFBM (1024² RGBA FBM), texture(8) = blueNoise (256² IGN dither), texture(9) = IBL irradiance map, texture(10) = IBL prefiltered environment map, texture(11) = BRDF LUT. Do not reassign these indices.
- **Buffer binding layout:** buffer(0) = FFT, buffer(1) = waveform, buffer(2) = FeatureVector, buffer(3) = StemFeatures, buffer(4–7) = future use.
- **Image-Based Lighting (IBL) pipeline** (Increment 3.16): HDR environment maps for photorealistic reflections and ambient lighting. `IBLManager` generates three textures at init: irradiance cubemap (diffuse ambient, 32² per face, convolved from source environment), prefiltered environment map (specular reflections, 128² per face, 5 mip levels for roughness LOD), and a 2D BRDF integration LUT (512², pre-computed split-sum lookup). Source environment is a procedural gradient sky + ground plane (generated via Metal compute) with future support for loading `.hdr`/`.exr` files. IBL textures bound at texture(9–11), available to all ray march presets. The lighting pass (`raymarch_lighting_fragment`) samples irradiance for diffuse ambient and prefiltered environment + BRDF LUT for specular reflections, replacing the current procedural sky fallback with physically accurate environment lighting. Materials like glass, metal, and water require IBL to look convincing — point lights alone cannot produce the complex reflection patterns these surfaces need.
- **Screen Space Global Illumination (SSGI)** (Increment 3.17): Approximate short-range diffuse light bounces using the existing G-buffer (depth + normals). Implemented as a post-process pass between the lighting pass and the composite pass. Samples nearby screen-space pixels to estimate indirect diffuse contribution — e.g., a glowing element reflecting color onto adjacent surfaces. Marginal performance cost (~0.5–1ms at 1080p) for significant photorealism improvement. Critical for scenes with strong local emitters (Popcorn's hot pan interior and oil surface bouncing warm light onto kernels, burner glow illuminating the skillet's exterior and grate, inter-kernel light scattering between popped whites). Does NOT replace hardware ray-traced GI — it approximates short-range bounces only, trading physical accuracy for frame budget compliance.
- **Shader utility library is always available.** Every preset inherits Noise, SDF, PBR, Environment, and Volumetric utility functions via the preamble. Preset shaders call these functions directly — never reimplement noise, SDF primitives, or BRDF math inline.
- **Material struct is standardized.** All photorealistic presets use the MSL `Material` struct for surface properties. This ensures consistent PBR evaluation across presets.
- **Noise textures are always bound.** `TextureManager` textures are bound at fixed indices in every draw path. Presets that don't sample them pay no cost (unused texture bindings are free).
- **MetalFX Upscaling** (Phase 7 — performance optimization): When profiling reveals thermal budget pressure from native-resolution ray marching, integrate Apple's MetalFX Temporal Upscaling. Render internal G-buffers and lighting at 50–70% resolution, upscale to native via MetalFX. This recovers thermal headroom for concurrent MPSGraph inference and ANE workloads during extended listening sessions. Deferred until real profiling data from photorealistic presets is available — do not optimize preemptively.

### ML Inference (No CoreML — fully migrated as of Phase 3.7)
- **No CoreML dependency.** All ML inference uses MPSGraph (GPU) or Accelerate (CPU). CoreML framework was removed in Increment 3.11.
- **Stem separator** (MPSGraph, GPU): Open-Unmix HQ architecture reconstructed in MPSGraph. Takes STFT magnitude spectrograms `[2049, 431]` per channel, outputs 4 masked spectrograms (vocals, drums, bass, other). Float32 throughout. Weights: 172 raw `.bin` files (135.9 MB) in `ML/Weights/`. STFT/iSTFT handled in Swift via Accelerate/vDSP. STFT params: n_fft=4096, hop=1024, sample_rate=44100. Fixed input: 431 frames (~10s). Performance: 142ms warm predict.
- **Mood classifier** (Accelerate, CPU): 4-layer MLP (10→64→32→16→2) with ReLU + tanh, implemented as 3 `vDSP_mmul` calls. Weights hardcoded as static `[Float]` arrays (3,346 params, extracted from the original DEAM-trained CoreML model). Outputs continuous valence (-1…1) and arousal (-1…1), smoothed with EMA. Input: 10 features (6-band energy, centroid, flux, major/minor key correlations).
- Stem separator outputs: Vocals, Drums, Bass, Other — each independently routed to shaders.
- - **Stem separation cadence improvement** (Phase 7 — ML optimization): The pre-analysis pipeline eliminates stem gaps at track transitions. The remaining concern is real-time refinement latency — how quickly the engine upgrades from cached preview stems to time-aligned live stems within a track. Near-term: reduce dispatch cadence from 5s to 2–3s after track changes. Long-term: evaluate streaming-native separation models or overlap-add architecture with shorter MPSGraph input windows for faster convergence.

### Orchestrator
**Two modes:**
- **Session mode** (playlist connected): Plans the full visual arc before playback starts using pre-analyzed `TrackProfile` data. Selects presets matched to each track's mood and stem profile. Pre-determines transition timing aligned to track boundaries and estimated section boundaries. Adapts the plan in real time as live MIR reveals structural details the 30-second preview missed.
- **Ad-hoc mode** (no playlist): Reactive decision-making under uncertainty. Four states: `idle` → `listening` → `ramping` → `full`. Falls back to heuristic preset selection based on live MIR data as it accumulates.

**Both modes share:**
- Visual transitions LAND on musical transitions (use lookahead to pre-initiate crossfades).
- No repeating the same preset category twice in succession.
- Section boundaries (structural analysis) are preferred transition points over timer-based switching.
- Track change detection fuses: Now Playing metadata, audio-level heuristics, elapsed time vs. pre-fetched duration.

### Pre-Fetch Philosophy
In **session mode**, pre-fetched metadata is gathered during the preparation phase for every track before playback starts. It complements the pre-analyzed stem and MIR data from preview clips. In **ad-hoc mode**, pre-fetched metadata is a "fast hint" that accelerates the first ~15 seconds of each track — the self-computed MIR pipeline is the real source of truth. In both modes, all external data is optional — Phosphene is fully functional via self-computed audio analysis alone.

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
- **340 tests** (249 swift-testing + 91 XCTest) across unit, integration, regression, and performance categories.
- All tests must pass before starting new work (`swift test --package-path PhospheneEngine` or `xcodebuild -scheme PhospheneApp -destination 'platform=macOS' test`).
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
20. **Raw `MLMultiArray.dataPointer` with `bindMemory(to: Float.self)` on ANE Float16 outputs**: The ANE outputs Float16 MLMultiArrays (dataType rawValue 65552) even when the model input is Float32. Using `dataPointer.bindMemory(to: Float.self, capacity:)` misinterprets the Float16 data as Float32 — producing garbage values and reading past the buffer. Also tried `vImageConvert_Planar16FtoPlanarF` for bulk conversion but it was slower than `MLShapedArray<Float>(converting:)`. The only reliable approach for Float16→Float32 from ANE output is `MLShapedArray<Float>(converting: output)`, which costs ~420ms for ~7M elements. This is internal to CoreML and sets the floor for unpack performance.

---

## What NOT To Do

- Do not use `AVAudioEngine` input tap as the primary audio source. Core Audio taps are primary.
- Do not use ScreenCaptureKit for audio-only capture — it silently fails on macOS 15+/26. Use `AudioHardwareCreateProcessTap` instead.
- Do not block the render loop on network calls, ML inference, or metadata queries.
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
struct StemFeatures             // 64 bytes: 4 floats per stem (vocals/drums/bass/other): energy, band0, band1, beat (GPU buffer(3))
struct FeedbackParams          // 32 bytes: decay, baseZoom, baseRot, beatZoom, beatRot, beatSensitivity, beatValue (GPU uniform)
struct Particle                // 64 bytes: position, velocity, color, life, size, seed, age (compute kernel state)
struct ParticleConfiguration   // particleCount, decayRate, burstThreshold, burstVelocity, drag (CPU-side tuning)
struct StructuralPrediction    // sectionIndex, sectionStartTime, predictedNextBoundary, confidence
struct VisualDirective         // Target family, color palette, camera speed, bloom, particles
struct TrackIdentity         // title, artist, album, duration, catalogIDs (Apple/Spotify/MusicBrainz)
struct TrackProfile          // BPM, key, mood, spectral centroid avg, genre tags, stem energy balance, estimated section count
struct SessionPlan           // Ordered list of (TrackIdentity, PresetDescriptor, transitionTiming)
struct CachedStemData        // Pre-separated stem waveforms (4× [Float]) + derived StemFeatures
enum SessionState            // idle, connecting, preparing, ready, playing, ended
```

## Linked Frameworks

Metal, MetalKit, MetalPerformanceShadersGraph, AVFoundation, Accelerate, ScreenCaptureKit, MusicKit

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
20. **Stem separation model**: Open-Unmix HQ (umxhq). HTDemucs was first choice but fails CoreML conversion due to complex tensor ops and dynamic shapes. Open-Unmix's LSTM architecture converts cleanly. Now runs entirely on MPSGraph (GPU, Float32) — the original CoreML `.mlpackage` was removed in Increment 3.11. STFT/iSTFT is handled in Swift via Accelerate/vDSP. Weights: 172 raw `.bin` files extracted by `tools/extract_umx_weights.py`. Performance: 142ms warm predict for 10s audio.
21. **MLShapedArray for CoreML I/O (historical)**: No longer applicable — CoreML was removed in Increment 3.11. Retained as a failed-approach reference for why the migration was necessary (ANE Float16 output, padded strides, ~420ms F16→F32 conversion overhead).
22. **GPU STFT/iSTFT (planned optimization)**: The current CPU-based STFT/iSTFT via Accelerate is the stem separation bottleneck (~6s for 10s of audio across 4 stems × 2 channels = 3448 FFT operations). The target architecture moves STFT/iSTFT to Metal compute shaders, eliminating CPU↔GPU copies and enabling the full separation pipeline (STFT → ANE predict → iSTFT → UMA buffers) to run without CPU-side data extraction. This would also enable real-time per-frame stem analysis rather than batch processing.
23. **MIR pipeline architecture**: DSP module takes `[Float]` magnitude arrays (not `UMABuffer`) — no Metal dependency. The caller extracts magnitudes from FFTProcessor's UMABuffer before passing to MIRPipeline. Chroma, key, and tempo are CPU-side properties on MIRPipeline (not in FeatureVector, which is limited to 24 floats for GPU upload). BandEnergyProcessor and BeatDetector independently compute 6-band bin ranges — simple duplication avoids coupling.
24. **Krumhansl-Schmuckler key estimation**: 24 key profiles (12 major + 12 minor rotations of Krumhansl 1990 profiles). Pearson correlation against normalized chroma vector. Minimum confidence threshold of 0.3 to avoid spurious key reports. Works well for clear tonal content; atonal or percussive-only material correctly returns nil.
25. **Mood classifier input features**: 10 pre-computed features, NOT raw 12-bin chroma. A tiny MLP cannot learn the Krumhansl-Schmuckler correlation function implicitly from 12 chroma bins — training converged to near-zero valence regardless of key mode. Pre-computing major/minor key correlations (which ChromaExtractor already calculates internally) reduces the problem to a trivially learnable function. The MLP provides smooth interpolation + efficient vDSP execution over what could be pure heuristics.
26. **Spectral flux normalization for GPU**: Raw flux depends on magnitude scale and bin count. MIRPipeline normalizes via running-max AGC (tracks peak flux with 0.999 decay). Spectral centroid normalized by dividing by Nyquist (24000 Hz) to map to 0–1.
27. **Tempo onset threshold**: 75th percentile of bass flux buffer × 2.0, with 150ms minimum spacing. The median of half-wave rectified flux is near-zero (most frames have zero flux), so median-based thresholds fail. The 75th percentile is non-zero only during genuine energy changes. Previous 300ms minimum spacing aliased all tempos to ~97 BPM.
28. **Chroma bin-count normalization**: Each FFT bin's magnitude contribution to its pitch class is weighted by `1/binsInPitchClass`. At 48kHz/1024-point FFT, pitch classes get 31–55 bins (1.77x ratio). Without normalization, key estimation is systematically biased toward high-bin-count pitch classes (F, E, D#).
29. **Structural analysis architecture**: Three-class decomposition: `SelfSimilarityMatrix` (ring buffer + cosine similarity), `NoveltyDetector` (checkerboard kernel + peak-picking), `StructuralAnalyzer` (coordinator + prediction). Feature vector is 16 floats (12 chroma + centroid/flux/rolloff/energy). Novelty detection runs every 30 frames (~0.5s), amortized cost ~0.03ms/frame. `StructuralPrediction` is CPU-side only — not in FeatureVector (locked at 24 floats for GPU). Min peak distance 120 frames (2s) balances sensitivity vs false positives.
30. **Feedback texture architecture**: Double-buffered ping-pong MTLTextures allocated lazily from the drawable size (handles the case where `drawableSizeWillChange` never fires). Three-pass render loop for feedback presets: (1) `feedback_warp_fragment` reads previous texture, applies bass→gravity / mid→current / treble→crystallization transforms with a wandering center, writes to current texture; (2) composite pass draws the preset fragment shader (additive blend pipeline state compiled separately by PresetLoader for presets with `use_feedback: true`) onto current texture; (3) drawable blit pass copies feedback texture to screen and renders compute particles on top with standard alpha blending. `FeedbackParams` (32 bytes, 8 floats) carries per-preset decay/zoom/rot values and live beat value to the shaders each frame. Non-feedback presets skip all three passes and render directly to the drawable (single-pass, zero regression from pre-feedback behavior).
31. **Particle rendering strategy for the Murmuration preset**: Compute particles render with standard `.sourceAlpha`/`.oneMinusSourceAlpha` blending (dark silhouettes over sky), NOT additive blending, NOT into the feedback texture. The sky gradient is rendered directly to the drawable each frame (standard preset pipeline, no feedback). This keeps the sky vivid instead of being washed out by feedback accumulation. The feedback texture path remains available but is currently unused by Murmuration — kept as infrastructure for future presets that need trails.
32. **Audio routing philosophy (learned from Murmuration tuning)**: Responding to `features.bass`/`features.mid`/`features.treble` means responding primarily to whatever instrument dominates the mix — which is often vocals in singer-songwriter tracks. To make a preset respond to specific musical content, use the 6-band energy values (`sub_bass`, `low_bass`, `low_mid`, `mid_high`, `high_mid`, `high_freq`) to deliberately target or avoid frequency ranges. Vocals live in `low_mid` (250-1kHz) and `mid_high` (1-4kHz); skipping those bands routes visual response to rhythm section and overtones instead. This is a simpler alternative to running per-stem analysis until the Orchestrator increment wires stem-specific routing.
33. **Creative design principle — marriage of art and technology**: Every preset should be rooted in a natural metaphor that the technology uniquely enables. Murmuration requires GPU compute (thousands of particles with custom physics) to exist — it couldn't be faked with Milkdrop's 1024 shape instances. The creative vision (a flock of starlings moving as one organism) and the technology (compute shaders with per-particle state) reinforce each other. Different audio features should control fundamentally different things: the waveform is a drawn shape, bass is gravity, mid is current, treble is crystallization, beats are phase transitions. Amplitude→magnitude mapping alone produces boring visuals regardless of tuning.
34. **ANE Float16 output and StemSeparator unpack strategy (superseded by Phase 3.7 MPSGraph migration)**: The ANE outputs Float16 MLMultiArrays (dataType=65552) even when the model was converted with Float32 inputs. `MLShapedArray<Float>(converting:)` is the only safe and correct way to get Float32 data from these outputs — it costs ~420ms for ~7M elements but handles both type conversion and stride padding. Once converted, the Float32 buffer has dense strides (stride[3]=1, stride[2]=nbFrames) suitable for direct `vDSP_mtrans` transpose. The `separate()` pack/write stages were optimized to <2ms each (raw MLMultiArray.dataPointer + vDSP_mtrans for pack, Float-specialized memcpy for write), but the unpack conversion sets a ~560ms floor (140ms predict + 420ms F16→F32). This is acceptable for the 5s background cadence but would need a CoreML API change or Float32-output model to reach sub-250ms.

35. **Open-Unmix HQ actual architecture (discovered in 3.7b weight extraction)**: Per-stem: 43 tensors, not 34. All Linear layers use `bias=False` (bias folded into BatchNorm). fc3/bn3 output 4098 features (2 channels × 2049 bins), not 2049. LSTM hidden_size=256 bidirectional (output 512), gate_size=1024 (4×256). Input normalization: 1487 bandwidth-limited bins. Raw weights: 172 .bin files, 135.9 MB float32, stored in `PhospheneEngine/Sources/ML/Weights/` with `manifest.json`. Tracked via Git LFS.

36. **MPSGraph Open-Unmix HQ reconstruction (Increment 3.8)**: All 4 stems in a single MPSGraph. Float32 throughout — eliminates ANE Float16→Float32 conversion bottleneck. Batch norm fused into scale+bias at init time (12 fusions). Bidirectional LSTM via `MPSGraphLSTMDescriptor.bidirectional = true` (macOS 12.3+). Gate order matches PyTorch default `[i, f, z, o]` — no weight reordering needed. PyTorch `bias_ih + bias_hh` summed at load time. Weights loaded from `.bin` files into `MTLBuffer(.storageModeShared)`. Fixed 431-frame input shape, graph compiled once at init. Performance: 102ms average warm predict (down from ~620ms CoreML). `StemModelEngine` class with pre-allocated UMA I/O buffers following the `StemFFTEngine` pattern.

37. **StemSeparator MPSGraph integration (Increment 3.9)**: `StemSeparator` now uses `StemModelEngine` instead of CoreML. STFT magnitudes are written directly into `StemModelEngine.inputMagLBuffer`/`inputMagRBuffer` via `memcpy` (same row-major [frame, bin] layout). Output magnitudes read directly from `StemModelEngine.outputBuffers[stem].magL/magR` as `UnsafeBufferPointer`. No MLMultiArray pack/unpack, no Float16→Float32 conversion. `StemSeparator+Pack.swift` renamed to `StemSeparator+Reconstruct.swift` — retains only `reconstructStemWaveforms` (iSTFT per stem) and `averageToMono` (vDSP). `import CoreML` removed from StemSeparator; CoreML remains for MoodClassifier until Increment 3.10. Warm `separate()`: 142ms avg (4.4× faster than 620ms CoreML path).

38. **Mesh shader pipeline architecture (Increment 3.2)**: Hardware capability gated at `device.supportsFamily(.apple8)` (M3+). On M3+: `MTLMeshRenderPipelineDescriptor` with `objectFunction` (optional) + `meshFunction` + `fragmentFunction`; draw via `drawMeshThreadgroups(_, threadsPerObjectThreadgroup:, threadsPerMeshThreadgroup:)`. On M1/M2: standard `MTLRenderPipelineDescriptor` with `mesh_fallback_vertex` + same fragment function; draw via `drawPrimitives`. `MeshGenerator` owns both pipeline states and abstracts the dispatch — callers never branch on hardware tier. `renderFrame` priority: mesh → feedback → direct. MSL note: mesh function parameters use `[[thread_index_in_threadgroup]]`, NOT `[[thread_index_in_mesh]]` (that attribute does not exist). `ObjectPayload` uses `object_data` address space qualifier for the payload pointer in the object shader and reference in the mesh shader. Preamble provides `ObjectPayload`, `MeshVertex`, `MeshPrimitive` to preset shaders that declare `use_mesh_shader: true`. Function naming convention for preset mesh shaders: `<name>_mesh_shader`, `<name>_object_shader` (optional), `<name>_fragment`.

39. **Shader utility library architecture (Phase 3R)**: `ShaderUtilities.metal` is a single MSL file containing all reusable shader functions (noise, SDF, ray marching, PBR lighting, UV transforms, color palettes, atmosphere). Included in the `PresetLoader` preamble string so every runtime-compiled preset shader has access without explicit imports. Functions organized by `// MARK: -` categories. All `static inline` to avoid symbol collision. Covers 6 domains: noise (12 functions), SDF (17 functions), ray marching (4 functions), PBR (6 functions), UV transforms (6 functions), color/atmosphere (8 functions). Each function validated against Shadertoy or Inigo Quilez reference implementations. Preamble order: FeatureVector struct → ShaderUtilities functions → preset shader code.

40. **Noise texture specifications (Increment 3.13)** ✅: `TextureManager` generates 5 pre-computed noise textures via Metal compute at init: `noiseLQ` (256² `.r8Unorm` tileable value-noise FBM), `noiseHQ` (1024² `.r8Unorm` tileable value-noise FBM), `noiseVolume` (64³ `.r8Unorm` tileable 3D value-noise FBM), `noiseFBM` (1024² `.rgba8Unorm` R=Perlin, G=shifted Perlin, B=inverted Worley, A=curl), `blueNoise` (256² `.r8Unorm` Interleaved Gradient Noise — GPU-computable deterministic approximation of blue noise). Kernels in `NoiseGen.metal` (`ng_` prefix guards against symbol collision). All `.storageModeShared`; 2D textures mipmapped via `MTLBlitCommandEncoder.generateMipmaps` (requires `.renderTarget` usage). Bound at `texture(4)`–`texture(8)` in every preset draw path. Total GPU memory: ~6 MB. `VisualizerEngine` creates on `.userInitiated` background queue; pipeline gracefully handles nil `TextureManager` (noise textures unavailable but rendering continues). Preamble gains `constexpr sampler` declarations (`linearSampler`, `nearestSampler`, `mipLinearSampler`) valid at MSL file scope.

41. **Multi-pass ray march pipeline (Phase 3R)**: `useRayMarch: true` presets render via 3-pass deferred: (1) ray march writes G-buffer (depth+materialID `.rg16Float`, normals `.rgba8Snorm`, albedo+material `.rgba8Unorm`); (2) lighting evaluates PBR with up to 4 audio-driven lights, soft SDF shadows, screen-space AO, procedural sky; (3) existing post-process chain. G-buffer textures lazy-allocated at drawable size. Scene function defined per-preset; infrastructure provides marching loop, normals, and lighting.

42. **Accumulated audio time (Phase 3R)**: Running sum of `totalEnergy * deltaTime` in `VisualizerEngine`, reset on track change. Nearly universal in Milkdrop presets — animation that breathes with the music. Delta: `(bass + mid + treble) / 3.0 * (1.0 / fps)`, clamped. Exposed via `FeatureVector.accumulatedAudioTime` (struct grows from 24 to 25 floats, 100 bytes, padded to 128 for SIMD alignment) and in `SceneUniforms` for ray march presets.

43. **Preview URL resolution strategy (Increment 2.5.2)**: iTunes Search API (`itunes.apple.com/search?term={artist}+{title}&media=music&entity=song&limit=1`) returns `previewUrl` for any track in the Apple Music catalog — no auth, no entitlement, universally available. Results are cached in memory keyed by `TrackIdentity` using `URL??` dict semantics: `nil` = uncached, `.some(nil)` = resolved but no preview found, `.some(url)` = preview URL. Rate limiting uses a sliding window over `requestTimestamps` (configurable window + count, default 20/60s). The `throttle()` loop is a `while true` with `Task.sleep` to handle concurrent callers all waking after the same delay.

44. **Preview audio decode architecture (Increment 2.5.2)**: `PreviewDownloader` injects the download step (`fileFetcher: (URL) async throws -> Data`) but always uses real `AVAudioFile` for decode — this tests the actual decode path with synthetic WAV data rather than mocking it away. Format is auto-detected from the first 4 bytes of the downloaded `Data` (RIFF=WAV, FORM=AIFF, caff=CAF, ID3/sync=MP3, default=M4A) so the correct temp file extension is used. `AVAudioFile` uses extensions to select the demuxer. Batch download uses a producer/consumer `withTaskGroup` pattern: seed `concurrency` tasks initially, dispatch the next pending track each time one completes — avoids creating all N tasks upfront, which would defeat the concurrency limit for large playlists.

## Reference Documents

The full development plan with phased increments is in `docs/DEVELOPMENT_PLAN.md`. Consult the relevant increment when starting a task — do not load the entire plan into context.

The architectural blueprint is in `docs/ARCHITECTURAL_BLUEPRINT.md`.

## Current Status

**Phase 3 in progress, under revised plan.** Phase 2 complete. Phase 3 was restructured after the original Increment 3.1 was discovered to have bundled three distinct units of work and left its "from stem-separated audio" goal unmet. See `docs/DEVELOPMENT_PLAN.md` for the full revised plan. The retroactive split and the new ordering are summarized below.

**Retroactive Phase 3 state:**
- **Increment 3.1 (Compute Shader Particle Pipeline)** ✅ — `ProceduralGeometry.swift`, `Particles.metal`, `MetalContext.makeSharedTexture`, 7 particle tests. Legitimate particle infrastructure deliverable.
- **Increment 3.1-bonus (Feedback Texture Infrastructure)** ✅ — `FeedbackParams` struct, `feedback_warp_fragment`/`feedback_blit_fragment` in `Common.metal`, three-pass feedback render path in `RenderPipeline` (`drawWithFeedback` with `drawParticleMode`/`drawSurfaceMode` split), `useFeedback` + `useParticles` flags on `PresetDescriptor`, dual pipeline state compilation in `PresetLoader`, `abstract` category, Membrane preset (second feedback user). **Scope violation:** this should have been its own increment; documented retroactively so the pattern isn't repeated.
- **Increment 3.1-preset (Murmuration)** ✅ — `Starburst.metal` + `Starburst.json`, flock compute kernel modifications in `Particles.metal`, audio routing. Ships with a documented full-mix workaround (`sub_bass + low_bass` / `high_mid + high_freq`) because the live stem pipeline was never wired. True stem routing for Murmuration is deferred to a Phase 3.5 preset-polish task that follows Increment 3.1b.

**Completed increments (Phase 3):**
- **Increment 3.1a — GPU STFT/iSTFT Compute Pipeline** ✅ — `StemFFTEngine` wrapping MPSGraph FFT, `StemFFT.swift`, CPU vDSP fallback behind `forceCPUFallback`. Dropped `separate()` from ~6500ms to ~2000ms. 6 StemFFTTests.
- **Increment 3.1b — Live Stem Pipeline Wiring + Per-Stem `StemFeatures`** ✅ — `StemSampleBuffer` (15s ring buffer), `StemAnalyzer` (4× BandEnergyProcessor + BeatDetector on drums), `StemFeatures` @frozen struct (16 floats = 64 bytes at GPU buffer(3)), background `DispatchSourceTimer` (5s cadence, utility QoS), track-change reset. 232 tests (226 + 2 layout + 4 integration). Known follow-up: idle suppression (skip separation during silence) and multi-frame AGC warmup.
- **Increment 3.1a-followup — StemSeparator CPU Memory Rearrangement** ✅ — Replaced scalar MLShapedArray loops and per-element UMABuffer writes with vectorized Accelerate operations. Pack: raw MLMultiArray.dataPointer + `vDSP_mtrans` (275ms → 1ms). Write: Float-specialized `UMABuffer.write` via memcpy (231ms → <1ms). Unpack transpose: `vDSP_mtrans` replacing nested scalar loops. Deinterleave: `vDSP_ctoz`. Mono averaging: `vDSP_vadd` + `vDSP_vsmul`. Total `separate()`: ~2000ms → ~600ms (3.4× improvement). Remaining ~420ms is Float16→Float32 conversion inside `MLShapedArray(converting:)` — the ANE outputs Float16 MLMultiArrays and this conversion is internal to CoreML. 236 tests (232 + 2 UMABuffer fast-path + 1 perf measure + 1 hard 750ms gate).

**Completed increments (Phase 3.7):**
- **Increment 3.7a — CPU-only CoreML Baseline Measurement** ✅ — Added `computeUnits` parameter to `StemSeparator.init`, 2 CPU-only perf tests. Results: ANE=659ms avg, CPU=592ms avg. CPU is ~10% faster (avoids F16→F32 conversion) but still above 400ms target. MPSGraph migration confirmed as the right path. 238 tests (222 swift-testing + 16 XCTest).
- **Increment 3.7b — Open-Unmix Weight Extraction Tool** ✅ — `tools/extract_umx_weights.py` extracts 172 tensors (43 per stem × 4 stems, 135.9 MB float32) from umxhq PyTorch checkpoint into raw `.bin` files + `manifest.json`. Key architecture corrections from spec: Linear layers use `bias=False`, fc3/bn3 output 4098 (2×2049), LSTM hidden=256 bidirectional, gate_size=1024. `tools/test_umx_weights.py` validates 6 checks (metadata, count, presence, shapes, sizes, data). Weights at `PhospheneEngine/Sources/ML/Weights/`, tracked via Git LFS, added to `Package.swift` as `.copy("Weights")`.
- **Increment 3.8 — MPSGraph Open-Unmix Inference Engine** ✅ — `StemModel.swift` + `StemModel+Graph.swift` + `StemModel+Weights.swift`: `StemModelEngine` class reconstructing Open-Unmix HQ entirely in MPSGraph. All 4 stems in single graph, Float32 throughout. Bidirectional 3-layer LSTM, fused batch norm (12 fusions), 172 weight tensors loaded from `.bin` files. 102ms average warm predict (6× faster than CoreML's ~620ms). 6 StemModelTests (init, silence, CoreML cross-validate, perf gate <400ms, UMA storage, thread safety). 244 tests (222 swift-testing + 22 XCTest).
- **Increment 3.9 — Integrate MPSGraph into StemSeparator** ✅ — Replaced CoreML prediction with `StemModelEngine` in `StemSeparator.separate()`. STFT magnitudes written directly into pre-allocated MTLBuffers via `memcpy`, eliminating MLMultiArray pack/unpack and Float16→Float32 conversion. `StemSeparator+Pack.swift` renamed to `StemSeparator+Reconstruct.swift` (kept iSTFT + mono averaging, deleted 6 CoreML pack/unpack methods). Removed `import CoreML` from StemSeparator. Warm `separate()`: **142ms avg** (4.4× faster than CoreML's ~620ms). Hard gate updated from 750ms to 400ms. 241 tests (221 swift-testing + 20 XCTest).

**Completed increments (Phase 3.7 continued):**
- **Increment 3.10 — Pure Accelerate MoodClassifier** ✅ — Replaced CoreML inference with 3 `vDSP_mmul` + bias + ReLU/tanh calls. Weights (3,346 Float32 params) hardcoded as static arrays in `MoodClassifier+Weights.swift`, extracted from the DEAM-trained CoreML model via `tools/extract_mood_weights.py`. `init()` is non-throwing (no model loading). Protocol `MoodClassifying` unchanged. 241 tests (221 swift-testing + 20 XCTest).
- **Increment 3.11 — Remove CoreML Dependency** ✅ — Deleted `StemSeparator.mlpackage` and `MoodClassifier.mlpackage`. Removed `import CoreML` from `ML.swift`. Removed `.copy("Models")` from `Package.swift`. Verified via `otool -L` that the binary no longer links CoreML. 241 tests pass, SwiftLint clean.

**Completed increments (Phase 3.2):**
- **Increment 3.2 — Mesh Shader Pipeline Infrastructure** ✅ — `MeshShaders.metal` (ObjectPayload/MeshVertex/MeshPrimitive structs, trivial object+mesh+fragment+fallback shaders), `MeshGenerator.swift` (detects `device.supportsFamily(.apple8)`, compiles `MTLMeshRenderPipelineDescriptor` on M3+ or vertex fallback on M1/M2, `draw()` dispatches `drawMeshThreadgroups`/`drawPrimitives` accordingly), `RenderPipeline+MeshDraw.swift` (`drawWithMeshShader` parallel to `drawDirect`), mesh branch in `renderFrame` (mesh → feedback → direct priority), `useMeshShader: Bool` on `PresetDescriptor`, meshlet struct definitions in `PresetLoader` preamble, `compileMeshShader` in `PresetLoader`. MSL fix: `[[thread_index_in_threadgroup]]` is correct; `[[thread_index_in_mesh]]` is not a valid Metal attribute. 247 tests (221 swift-testing + 26 XCTest).
- **Increment 3.2b — Fractal Tree Demonstration Preset** ✅ — `FractalTree.metal` (object shader packs audio into `FractalPayload`; 64-thread mesh shader generates 63-branch binary tree via iterative ancestry traversal, 252 vertices / 126 triangles per frame; fragment shader: depth-dependent colour bark→green→hue-shifted tips, beat flash, edge soft-fade; `fractal_tree_fallback_vertex` for M1/M2). `FractalTree.json` (`"family": "fractal"`, `"use_mesh_shader": true`). `PresetDescriptor` gains `meshThreadCount: Int` (default 64, key `"mesh_thread_count"`). `MeshGeneratorConfiguration` gains `meshThreadCount`/`objectThreadCount`; `MeshGenerator` gains `init(device:pipelineState:configuration:)` for preset-compiled states and binds `FeatureVector` to object/mesh/fragment stages. `VisualizerEngine.applyPreset` handles `useMeshShader: true`. Verified with "Cannonball" by The Breeders — responds particularly well to bass-heavy music. 247 tests, 0 failures.

**Completed increments (Phase 3.3):**
- **Increment 3.3 — Hardware Ray Tracing Infrastructure** ✅ — Native Metal ray tracing API (migrated away from deprecated `MPSRayIntersector`). `BVHBuilder.swift`: `MTLPrimitiveAccelerationStructureDescriptor` BVH builder with blocking `build()`/`rebuild()` + non-blocking `encodeBuild(into:)` for per-frame audio-reactive scene geometry. `RayIntersector.swift` + `RayIntersector+Internal.swift`: compute-pipeline intersector with blocking `intersect()`/`shadowRay()` + non-blocking `encodeNearestHit()`/`encodeShadow()`. `RayTracing.metal`: `rt_nearest_hit_kernel` + `rt_shadow_kernel` (`accept_any_intersection(true)`). MSL gotcha: `intersection_result<triangle_data>` exposes `triangle_barycentric_coord` (NOT `.barycentrics`); buffer binding requires `primitive_acceleration_structure`. 9 tests pass (4 BVHBuilder + 5 RayIntersector, perf gate < 2ms, actual ~0.8ms warm). 247 tests total, SwiftLint clean.
- **Increment 3.4 — HDR Post-Process Chain** ✅ — `PostProcessChain.swift`: owns HDR scene texture (`.rgba16Float` full-res), ping-pong bloom textures (`.rgba16Float` half-res), and 4 compiled pipeline states. `PostProcess.metal`: `pp_bright_pass_fragment` (luminance > 0.9 threshold, 2× downsample), `pp_blur_h/v_fragment` (9-tap separable Gaussian, sigma ≈ 1.5), `pp_composite_fragment` (ACES filmic tone mapping + 0.5× bloom additive → SDR). `RenderPipeline+PostProcess.swift`: `drawWithPostProcess` parallel to `drawDirect`/`drawWithFeedback`/`drawWithMeshShader`; renderFrame priority: mesh → postProcess → feedback → direct. `usePostProcess: Bool` on `PresetDescriptor` (JSON key `"use_post_process"`, default `false`). 6 PostProcessChainTests (HDR texture alloc, rgba16Float format, bloom threshold, Gaussian luminance preservation <2%, ACES SDR mapping, <2ms perf at 1080p). 262 tests total, SwiftLint clean.

**Completed increments (Phase 3.5):**
- **Increment 3.5 — Indirect Command Buffers** ✅ — GPU-driven ICB render path. `ICB.metal`: `icb_populate_kernel` compute shader reads `FeatureVector` (bass+mid+treble cumulative energy) and populates up to `maxCommandCount` (default 16) ICB slots; slot 0 unconditionally active (base layer), subsequent slots activate as energy rises above linearly spaced thresholds. `RenderPipeline+ICB.swift`: `ICBConfiguration` struct, `IndirectCommandBufferState` (ICB + compute pipeline + argument buffer for `command_buffer` MSL type + `commandCountBuffer` + UMA `featureVectorBuffer`/`stemFeaturesBuffer` — needed because `setFragmentBytes` is NOT inherited by ICB commands, only `setFragmentBuffer` bindings are). `drawWithICB`: three-phase loop: (1) blit reset, (2) compute populate, (3) render + `executeCommandsInBuffer`. Pipeline priority: mesh → postProcess → ICB → feedback → direct. `ShaderLibrary.renderPipelineState` gains `supportICB: Bool = false` parameter — pipelines used with ICBs must set `supportIndirectCommandBuffers = true`. Key lessons: `MTLIndirectCommandType.draw` (not `.drawPrimitives`), `useResource(_:usage:stages:)` for the stages-aware API (macOS 13+), and the argument buffer pattern for passing `command_buffer` to compute kernels via `makeArgumentEncoder(bufferIndex:)` + `setIndirectCommandBuffer(_:index:)`. 6 RenderPipelineICBTests (ICB creation, compute populate, execute, reset-between-frames, zero-audio minimum, <2ms perf). 268 tests total, SwiftLint clean.

**Completed increments (Phase 3R):**
- **Increment 3.12 — Shader Utility Library** ✅ — `ShaderUtilities.metal` (663 lines, 55 functions across 7 domains): hash (4), noise (10: Perlin/simplex/Worley/FBM/curl in 2D+3D), SDF primitives (8) + operations (9), ray marching (4: march/normal/AO/shadow via forward-declared `map()`), PBR lighting (6: Fresnel-Schlick, GGX, Smith, Cook-Torrance BRDF, point/directional light), UV transforms (6: polar/invRadius/kaleidoscope/Möbius/bipolar/logSpiral), color/atmosphere (8: cosine palette, ACES/Reinhard tone mapping, sRGB conversions, fog, atmospheric scatter, volumetric march). Loaded from Presets bundle at init, appended to preamble after struct definitions. `PresetLoader` skips utility files during preset discovery via `utilityFileNames` filter. All functions `static inline`; ray march functions use forward-declared `float map(float3 p)` — presets define `map()` to use them, non-ray-march presets are unaffected (dead code elimination). 11 ShaderUtilityTests (preamble inclusion, multi-domain compilation, noise determinism, SDF analytic correctness, ray march sphere hit/miss, PBR energy conservation, kaleidoscope symmetry, palette smoothness, ACES SDR range, fog identity, 1080p noise <2ms). 279 tests total (232 swift-testing + 47 XCTest), SwiftLint clean.
- **Increment 3.13 — Noise Texture Manager** ✅ — `TextureManager.swift`: generates 5 noise textures via Metal compute at init (`gen_perlin_2d`, `gen_perlin_3d`, `gen_fbm_rgba`, `gen_blue_noise` kernels in `NoiseGen.metal`). Textures: `noiseLQ` (256² `.r8Unorm` tileable Perlin FBM), `noiseHQ` (1024² `.r8Unorm`), `noiseVolume` (64³ `.r8Unorm` 3D FBM), `noiseFBM` (1024² `.rgba8Unorm` R=Perlin G=shifted B=Worley A=curl), `blueNoise` (256² `.r8Unorm` IGN dither). All `.storageModeShared`, 2D textures mipmapped. `bindTextures(to:)` sets fragment texture indices 4–8 in all draw paths (drawDirect, drawParticleMode, drawSurfaceMode, drawWithMeshShader, drawWithICB, drawWithPostProcess). `RenderPipeline` holds optional `TextureManager` behind `NSLock`. `VisualizerEngine` creates on background `.userInitiated` queue at startup. Preamble gains `constexpr sampler linearSampler/nearestSampler/mipLinearSampler` declarations and noise texture index documentation. 9 `TextureManagerTests` (dimensions, formats, storageMode, determinism, binding, <500ms perf). 288 tests total (232 swift-testing + 56 XCTest), SwiftLint clean.
- **Increment 3.14 — Multi-Pass Ray March Pipeline** ✅ — `RayMarchPipeline.swift`: owns G-buffer textures (gbuffer0 `.rg16Float`, gbuffer1 `.rgba8Snorm`, gbuffer2 `.rgba8Unorm`, litTexture `.rgba16Float`), two fixed pipeline states (lightingPipeline, compositePipeline), bilinear sampler, public `sceneUniforms: SceneUniforms`. `render(gbufferPipelineState:features:fftBuffer:waveformBuffer:stemFeatures:outputTexture:commandBuffer:noiseTextures:postProcessChain:)` runs 3-pass deferred encode. `RenderPipeline+RayMarch.swift`: `drawWithRayMarch` updates aspect ratio, lazy-allocates textures, delegates GPU work. `RayMarch.metal`: `raymarch_lighting_fragment` (Cook-Torrance PBR, 12-step soft shadows, 5-sample AO, fog, sky) + `raymarch_composite_fragment` (ACES SDR). `PostProcessChain` gains `runBloomAndComposite(from:to:commandBuffer:)` for ray march + bloom path. `PresetLoader` gains `CompiledShader` struct (replaced 3-member tuple), `compileRayMarchShader` (3-attachment G-buffer `MTLRenderPipelineDescriptor`), and split preamble architecture: `shaderPreamble` (all presets) vs `rayMarchGBufferPreamble` (ray march only — critical fix: `raymarch_gbuffer_fragment` calls preset-defined `sceneSDF`/`sceneMaterial` which standard presets never define, so it must not appear in the shared preamble). `SceneUniforms` Swift struct: 8×`SIMD4<Float>` = 128 bytes. Render path priority: mesh → postProcess → ICB → **rayMarch** → feedback → direct. 10 `RayMarchPipelineTests` (G-buffer alloc, formats, storage mode, sphere depth, outward normals, specular highlight, shadow region, bloom path, idempotent alloc, <8ms perf at 1080p). 340 tests total (249 swift-testing + 91 XCTest), SwiftLint clean.
- **Increment 3.15 — Extended Shader Uniforms** ✅ — `FeatureVector` grew from 24 to 32 floats (96→128 bytes): added `accumulatedAudioTime` (float 25) + 7 padding floats for SIMD alignment. MSL preamble `FeatureVector` struct updated to match (32 floats, field `accumulated_audio_time`). `SceneCamera` and `SceneLight` Codable structs added to `Presets` module; `PresetDescriptor` gains `sceneCamera: SceneCamera?`, `sceneLights: [SceneLight]`, `sceneFog: Float`, `sceneAmbient: Float` (JSON keys `scene_camera`, `scene_lights`, `scene_fog`, `scene_ambient`). `RenderPipeline` gains `accumulatedAudioTime: Float`, `resetAccumulatedAudioTime()`, and internal `stepAccumulatedTime(energy:deltaTime:)` behind `NSLock`; accumulation formula: `_accumulatedAudioTime += max(0, energy) * deltaTime`, driven by `(bass + mid + treble) / 3.0` each frame. `drawWithRayMarch` writes `accumulatedAudioTime` to `sceneUniforms.sceneParamsA.x` each frame. `VisualizerEngine+Presets.swift` gains `makeSceneUniforms(from:)` (camera basis construction: forward/right/up from position+target; first light → lightPositionAndIntensity + lightColor; fog/ambient → sceneParamsB). Track-change callback calls `pipeline.resetAccumulatedAudioTime()`. 9 new tests: 5 `SceneUniformsTests` (128-byte size/stride, 16-byte alignment, default value sanity, MSL probe kernel, JSON preset parse) + 4 `FeatureVectorExtendedTests` (128-byte size, zero-at-start, accumulation formula, reset via RenderPipeline). 3 existing tests updated (96→128 bytes). 307 tests total (232 swift-testing + 75 XCTest), SwiftLint clean.
- **Increment 3.6 — Render Graph / Capability Composition Refactor** ✅ — Replaced 6 scattered boolean capability flags with a generic render graph. `RenderPass` enum in `Shared` (raw strings: `"direct"`, `"feedback"`, `"particles"`, `"mesh_shader"`, `"post_process"`, `"ray_march"`, `"icb"`). `PresetDescriptor.passes: [RenderPass]` is the new source of truth; computed `useFeedback`/`useMeshShader`/etc. kept as backwards-compatible derived properties. Backward-compatible JSON decoding: `"passes"` key preferred, falls back to `synthesizePasses(from:)` reading legacy `use_feedback`/`use_mesh_shader`/etc. booleans. `RenderPipeline.activePasses` guarded by `passesLock`; `setActivePasses(_:)` + `currentPasses` public API. `renderFrame` replaced with data-driven loop: iterates `activePasses`, dispatches to first pass with available subsystem, falls back to `drawDirect`. `VisualizerEngine.applyPreset` rewritten as pass-walking configurator. 7 preset JSON files migrated to `"passes"` format. 7 new tests in `PresetTests.swift`. 314 tests total (239 swift-testing + 75 XCTest), SwiftLint clean.

- **Increment 3.16 — IBL Pipeline** ✅ — `IBLManager.swift`: generates 3 IBL textures via Metal compute kernels at init: `irradianceMap` (32² cubemap, `.rgba16Float`, 512-sample cosine-weighted hemisphere convolution per face), `prefilteredEnvMap` (128² cubemap, `.rgba16Float`, 5 mip levels, 256-sample GGX importance sampling per mip, roughness = mip/4), `brdfLUT` (512² 2D, `.rg16Float`, 1024-sample split-sum BRDF integration). Source environment: procedural gradient sky matching `rm_skyColor`. `bindTextures(to:)` sets fragment texture indices 9–11. `IBL.metal` in `Renderer/Shaders/`: 3 compute kernels (`ibl_gen_irradiance`, `ibl_gen_prefiltered_env`, `ibl_gen_brdf_lut`) + 3 `static inline` sampling utilities (`ibl_sample_irradiance`, `ibl_sample_prefiltered`, `ibl_sample_brdf_lut`) compiled into the same ShaderLibrary compilation unit as `RayMarch.metal`. `raymarch_lighting_fragment` adds `texturecube<float> iblIrradiance [[texture(9)]]`, `texturecube<float> iblPrefiltered [[texture(10)]]`, `texture2d<float> iblBRDFLUT [[texture(11)]]`; ambient term replaced by split-sum IBL (diffuse irradiance + specular prefiltered env + BRDF LUT factors); `max(..., albedo * 0.04 * ao)` minimum prevents fully black surfaces when IBL unloaded. `RenderPipeline` gains `iblManager: IBLManager?` + `setIBLManager(_:)`. `RayMarchPipeline.render` and `runLightingPass` accept `iblManager: IBLManager? = nil`. `RenderPipeline+RayMarch` forwards it. Preamble documents texture(9–11). 9 `IBLManagerTests` (cubemap dimensions, mip count, BRDF LUT format, storageModeShared, irradiance non-black all 6 faces, mip chain populated, BRDF LUT [0,1] range, binding at index 9, <1s perf). 323 tests total, SwiftLint clean.
- **Increment 3.17 — SSGI Post-Process Pass** ✅ — `SSGI.metal`: `ssgi_fragment` reads gbuffer0 (depth), gbuffer1 (normals), litTexture (direct lighting); samples 8 nearby screen-space positions in a blue-noise-rotated varying-radius spiral (`radiusFactor = (i + 0.5) / N` ensures non-zero falloff at every sample); accumulates indirect diffuse weighted by `(NdotD * 0.7 + 0.3) * falloff` (30% floor prevents zero contribution on convex surfaces); far-side depth rejection via `dot(toSample, rayDir) > farPlane * 0.1`; `kIndirectStrength = 0.3`; sky pixels (depth ≥ 0.999) early-exit. `ssgi_blend_fragment` bilinearly upsamples half-res ssgiTexture for additive blend into litTexture. `RayMarchPipeline` gains `ssgiTexture` (half-res `.rgba16Float`), `ssgiPipeline`, `ssgiBlendPipeline` (additive blend: src=one, dst=one), `ssgiEnabled: Bool`; pass methods extracted to `RayMarchPipeline+Passes.swift` for file-length compliance. `RenderPass` gains `.ssgi` case; `PresetDescriptor` gains `useSSGI` computed property; `RenderPipeline+RayMarch` wires `ssgiEnabled` from `activePasses`; `RenderPipeline+Draw` merges `.ssgi` into `.direct, .particles` break case. `sceneParamsB.w` overrides sample radius (0 → default 0.08 UV). 7 `SSGITests` (half-res texture, `.rgba16Float` format, storageModeShared, emissive surface illuminates neighbor, no emission → minimal contribution, disabled → no pass encoded, <1ms overhead at 1080p). 330 tests total (239 swift-testing + 91 XCTest), SwiftLint clean.
- **Increment 3.18 — DRM Silence Detection & Graceful Degradation** ✅ — `AudioSignalState` enum (`.active`, `.suspect`, `.silent`, `.recovering`) in `Audio/Protocols.swift`. `SilenceDetector` class in `Audio/SilenceDetector.swift`: time-injectable state machine (threshold `1e-6` RMS, `.suspect` at 1.5s, `.silent` at 3s total, `.recovering` immediately on signal return, `.active` after 0.5s sustained signal); `update(samples:count:)` called on real-time IO proc thread; `onStateChanged` callback invoked outside lock to prevent deadlock; `reset()` called on mode switch. `AudioInputRouter` gains `silenceDetector: SilenceDetector` (internal, wired into `systemCapture.onAudioBuffer` and `startFilePlayback`), `onSignalStateChanged: ((AudioSignalState) -> Void)?` (public), `signalState: AudioSignalState` (public); internal secondary init for test injection. `VisualizerEngine` gains `@Published var audioSignalState: AudioSignalState = .active`; `makeSignalStateCallback()` in `VisualizerEngine+Audio.swift` dispatches to MainActor and logs each transition. `ContentView` gains `NoAudioSignalBadge` (bottom-left overlay, auto-dismisses on recovery). 10 `SilenceDetectorTests` (init state, normal audio stays active, suspect at 1.5s, silent at 3s, recovering on signal return, active after recovery hold, brief dropout stays active, callback on each transition, no callback on non-transition frames, configurable thresholds). 340 tests total (249 swift-testing + 91 XCTest), SwiftLint clean.

**Completed increments (Phase 2.5):**
- **Increment 2.5.1 — Playlist Connector** ✅ — New `Session` SPM target. `TrackIdentity` struct (title, artist, album, duration, appleMusicID, spotifyID, musicBrainzID; `Sendable + Hashable + Codable`). `PlaylistConnecting` protocol + `PlaylistConnector` concrete class: Apple Music (AppleScript loop over `every track of current playlist`, linefeed-joined output), Spotify queue endpoint (`/me/player/queue`) and playlist URL endpoint (`/playlists/{id}/tracks`, paginated), Apple Music URL (validates format, falls back to current playlist pending MusicKit entitlement in Phase 4). All external calls injectable via `appleScriptReader` and `networkFetcher` closures. `PlaylistConnectorError` enum (5 cases). `Logging.session` logger added to `Shared`. SwiftLint fix: `SilenceDetector.update(rms:)` refactored — per-state logic extracted into 4 private `advance*` helpers, reducing cyclomatic complexity from 12 → 5; `s` renamed to `sample`. 8 `PlaylistConnectorTests` (ordered tracks, duration, Spotify queue, Spotify URL, empty playlist, network failure, Codable round-trip, duplicate order preservation). 348 tests total (257 swift-testing + 91 XCTest), SwiftLint clean.
- **Increment 2.5.2 — Preview Resolver & Downloader** ✅ — `PreviewAudio` struct (`Session/SessionTypes.swift`: trackIdentity, pcmSamples `[Float]`, sampleRate `Int`, duration `TimeInterval`). `PreviewResolving` protocol + `PreviewResolver` class (`Session/PreviewResolver.swift`): iTunes Search API (`itunes.apple.com/search?term=…&media=music&entity=song&limit=1`), injectable `networkFetcher` closure, in-memory cache keyed by `TrackIdentity` (hit/miss/nil-cached via `URL??` dict), sliding-window rate limiter (20 req/min default, configurable for testing). `PreviewDownloading` protocol + `PreviewDownloader` class (`Session/PreviewDownloader.swift`): injectable `fileFetcher` closure, format-sniffing temp file writer (WAV/AIFF/CAF/MP3/M4A auto-detected from file header bytes), real `AVAudioFile` decode to mono Float32 (multi-channel averaged), configurable concurrency ceiling (default 4, `withTaskGroup` producer/consumer), guaranteed temp file cleanup via `defer`. 6 `PreviewResolverTests` (known track → URL, unknown → nil, AAC URL format, rate-limit enforcement, timeout → nil graceful, cache dedup). 6 `PreviewDownloaderTests` (non-zero PCM, 44100 Hz, ~30s duration, concurrency ceiling, failed track skipped, temp file cleanup). 360 tests total (269 swift-testing + 91 XCTest), SwiftLint clean.
- **Increment 2.5.3 — Batch Pre-Analysis & Stem Cache** ✅ — `TrackProfile` struct (bpm, key, mood, spectralCentroidAvg, genreTags, stemEnergyBalance, estimatedSectionCount). `CachedTrackData` struct (stemWaveforms `[[Float]]`, stemFeatures `StemFeatures`, trackProfile `TrackProfile`). `StemCache` (`@unchecked Sendable`, `NSLock`-guarded `store/loadForPlayback/stemFeatures/trackProfile/count/clear`). `SessionPreparer` (`@MainActor ObservableObject`, `@Published progress`, sequential per-track loop with `Task.detached` for CPU work, cancellation via `Task.isCancelled`). `SessionPreparer+Analysis.swift` — `nonisolated` static helpers: `analyzePreview` (separator → AGC warmup → offline MIR), `warmUpAndAnalyze` (1024-sample hop multi-frame warmup), `analyzeMIR` (vDSP FFT frame-by-frame through `MIRPipeline`, mood every 30 frames), `computeFFTMagnitudes` (`FFTContext` struct packs working buffers). `StemFeatures` gains `: Equatable`. Session target deps expanded: Audio + DSP + ML. `VisualizerEngine` gains `stemCache: StemCache?`; `resetStemPipeline(for:)` loads from cache instead of zeroing (StemSampleBuffer not cleared). Track-change callback passes `TrackIdentity` to `resetStemPipeline`. 8 unit tests (`SessionPreparerTests` + `StemCacheTests`) + 3 integration tests (real Metal GPU, synthetic sine wave PCM, no network). 280 tests total (269 swift-testing + 91 XCTest — note: 91 XCTest unchanged, swift-testing count revised vs prior entry), SwiftLint clean.

**Completed increments (Phase 3.5 — Preset Library):**
- **Increment 3.5.3 — Glass Brutalist Preset** ✅ — `GlassBrutalist.metal` + `GlassBrutalist.json`. Ray march preset: a stark brutalist corridor of massive concrete pillars and horizontal slabs framing near-mirror glass panels between each bay. Two functions only (`sceneSDF` + `sceneMaterial`). Concrete SDF: floor/ceiling `sdPlane`s + mirrored pillar columns (`abs(p.x)` fold + Z `round()`-based repetition every 7 units) + cross-beams. Glass SDF: thin vertical panels offset by half a cell in Z. Audio routing (hierarchy-correct): `sub_bass + low_bass` → pillar Y-scale (continuous, primary); `mid` → glass panel Y-scale; `accumulated_audio_time` → slow sinusoidal corridor drift; `beat_bass` → transient 5 % pillar squeeze (accent, secondary). Material: concrete → two-octave `perlin2D` FBM albedo variation (roughness 0.82–0.92, metallic 0.0); glass → cool cyan, roughness 0.04, metallic 0.92 (near-mirror IBL specular → high litTexture luminance → SSGI indirect bleed onto concrete). Passes: `["ray_march", "ssgi", "post_process"]`. No new Swift files, no new tests needed (preset compiles dynamically via `PresetLoader`). 280 swift-testing + 91 XCTest pass, 0 SwiftLint violations.

**Ordered next increments** (per the revised plan):
1. **Increment 2.5.4 — Session State Machine & Track Change Behavior.** `SessionManager` formalizes the lifecycle: idle → connecting → preparing → ready → playing → ended.
2. **Phase 3.5 — Native Preset Library Expansion.** Next entry: **3.5.2 Murmuration Stem Routing Revision** (replace 6-band workaround with real stem routing from StemFeatures). Popcorn (3.5.1) removed from plan.
3. **Phase 4 — Orchestrator.** Revised to include session planning mode alongside reactive mode.
