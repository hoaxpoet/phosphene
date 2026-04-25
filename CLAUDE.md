# CLAUDE.md — Phosphene

## What This Is

Phosphene is a native macOS music visualization engine for Apple Silicon. Before the music starts, Phosphene connects to a playlist, downloads 30-second preview clips for every track, and runs full ML-powered stem separation and MIR analysis on each. By the time the user presses play, the AI Orchestrator has planned the entire visual session — which visualizer for each track, where transitions land, and what the emotional arc looks like across the playlist. During playback, real-time audio analysis via Core Audio taps (`AudioHardwareCreateProcessTap`) refines the pre-analyzed data, and the Orchestrator adapts its plan as the music unfolds.

Phosphene does not control playback — the user starts the music in their streaming app when Phosphene signals it is ready.

See `docs/PRODUCT_SPEC.md` for the full product definition, `docs/ARCHITECTURE.md` for system design, `docs/DECISIONS.md` for rationale behind key choices, `docs/RUNBOOK.md` for build/test/CI/troubleshooting, `docs/MILKDROP_ARCHITECTURE.md` for the research findings that drive the Phase MV (Musicality) work, `docs/UX_SPEC.md` for the user-facing product UX contract (state-to-view mapping, error taxonomy, onboarding), and `docs/SHADER_CRAFT.md` for the preset authoring handbook (detail cascade, material cookbook, per-preset uplift playbook) in `docs/ENGINEERING_PLAN.md`.

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
  ContentView.swift         → Pure switch on SessionManager.state; no layout logic
  PhospheneApp.swift        → App entry point; wires SessionStateViewModel + startAdHocSession()
  VisualizerEngine.swift    → Audio→FFT→render pipeline owner; owns SessionManager (non-optional)
  VisualizerEngine+Audio.swift → Audio routing, MIR analysis, mood classification, signal state callbacks
  VisualizerEngine+Stems.swift → Background stem separation pipeline, 5s cadence, track-change reset
  VisualizerEngine+Presets.swift → makeSceneUniforms(from:) for ray march camera/light setup
  Permissions/
    ScreenCapturePermissionProvider.swift → Protocol + CGPreflightScreenCaptureAccess-backed impl (never prompts)
    PermissionMonitor.swift               → @MainActor ObservableObject; refreshes isScreenCaptureGranted on foreground (U.2)
    PhotosensitivityAcknowledgementStore.swift → UserDefaults-backed first-run flag; key phosphene.onboarding.photosensitivityAcknowledged (U.2)
  Services/
    DelayProviding.swift    → Protocol for injectable sleep (RealDelay + InstantDelay); makes retry loops unit-testable without wall-clock waits
    SpotifyURLKind.swift    → Enum: .playlist(id:) / .track / .album / .artist / .invalid
    SpotifyURLParser.swift  → Pure enum; static parse(_ input:) → SpotifyURLKind; handles HTTPS, spotify: URI, @-prefix, query params, podcasts
  ViewModels/
    SessionStateViewModel.swift → @MainActor ObservableObject bridging SessionManager.state → SwiftUI; publishes state + reduceMotion
    ConnectorPickerViewModel.swift → @MainActor ObservableObject; NSWorkspace observers (nonisolated(unsafe)) for AM launch/terminate; 250ms debounce
    AppleMusicConnectionViewModel.swift → State machine (idle→connecting→noCurrentPlaylist/notRunning/permissionDenied/error/connected); 2s auto-retry via DelayProviding
    SpotifyConnectionViewModel.swift → State machine (empty→parsing→preview/rejectedKind/invalid→rateLimited/notFound/error); 300ms debounce; [2s,5s,15s] rate-limit retry
  Views/
    MetalView.swift         → NSViewRepresentable wrapping MTKView
    DebugOverlayView.swift  → Developer debug overlay (D key)
    ConnectorType.swift     → Enum: .appleMusic/.spotify/.localFolder; title/subtitle/systemImage
    ConnectorTileView.swift → Reusable tile: icon + title/subtitle; disabled state with alt caption + optional secondary action button
    ConnectorPickerView.swift → NavigationStack in sheet; three tiles; navigationDestination(for: ConnectorType.self)
    AppleMusicConnectionView.swift → Five-state connection view (connecting/noCurrentPlaylist/notRunning/permissionDenied/error); onConnect fires on .connected
    SpotifyConnectionView.swift → URL paste field; preview card; rejectedKind copy; rate-limit retry indicator; error body
    Onboarding/PermissionOnboardingView.swift → Screen-capture permission explainer; "Open System Settings" CTA (U.2)
    Onboarding/PhotosensitivityNoticeView.swift → One-time photosensitivity sheet on IdleView first appearance (U.2)
    Idle/IdleView.swift     → .idle state; "Connect a playlist" sheet CTA + "Start listening now" ad-hoc CTA (U.3)
    Connecting/ConnectingView.swift → .connecting state: per-connector spinner + cancel
    Preparation/PreparationProgressView.swift → .preparing state: per-track status + partial-ready CTA
    Ready/ReadyView.swift   → .ready state: "Press play in your music app" + first-audio autodetect
    Playback/PlaybackView.swift → .playing state: full-bleed Metal + preset badge + signal badge + debug overlay + keyboard shortcuts
    Ended/EndedView.swift   → .ended state: session summary + new session affordance

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
    BeatDetector            → 6-band onset detection, grouped beat pulses, tempo via autocorrelation
    BeatDetector+Tempo      → IOI histogram + autocorrelation tempo estimation
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
    Shaders/MVWarp.metal    → Default engine-library mvWarp implementations (mvWarp_vertex_default, identity warpPerFrame/Vertex); fixed fragment shaders shared by all presets (mvWarp_fragment, mvWarp_compose_fragment, mvWarp_blit_fragment)
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
    PresetLoader+Preamble   → Shared preamble: FeatureVector struct → V.1 Noise utility tree → V.1 PBR utility tree → ShaderUtilities → noise samplers → preset code. Forwards `sceneSDF(p, FeatureVector& f, SceneUniforms& s, StemFeatures& stems)` and `sceneMaterial(p, matID, f, s, stems, albedo, roughness, metallic)` so ray-march presets can do per-stem routing (Milkdrop-style) directly in sceneSDF/sceneMaterial. StemFeatures plumbed through G-buffer fragment call sites. Presets should apply the D-019 warmup fallback `smoothstep(0.02, 0.06, totalStemEnergy)` to mix between FeatureVector proxies and stem direct reads (see VolumetricLithograph for reference implementation). Also contains `mvWarpPreamble` (MV-2, D-027): MVWarpPerFrame struct, WarpVertexOut, warpSampler, forward declarations for preset `mvWarpPerFrame`/`mvWarpPerVertex`, and the `mvWarp_vertex` 32×24 grid shader. SceneUniforms defined via `#ifndef SCENE_UNIFORMS_DEFINED` guard so direct (non-ray-march) mv_warp presets compile correctly.
    PresetDescriptor        → JSON sidecar: passes, feedback params, scene camera/lights, stem affinity
    PresetDescriptor+SceneUniforms → Constructs SceneUniforms from descriptor (camera basis, light, fog, near/far). FOV converted from JSON degrees → radians exactly once.
    PresetCategory          → 11 aesthetic families
    Shaders/ShaderUtilities.metal → 55 reusable functions: noise, SDF, PBR, ray march, UV, color, atmosphere (legacy camelCase names)
    Shaders/Utilities/Noise/  → V.1 Noise utility tree (9 files, snake_case, D-045). Load order: Hash → Perlin → Simplex → FBM → RidgedMultifractal → Worley → DomainWarp → Curl → BlueNoise. Provides: hash_u32/f01 family, perlin2d/3d/4d, simplex3d/4d, fbm4/8/12/fbm_vec3, ridged_mf, worley2d/3d/fbm, warped_fbm/vec, curl_noise, blue_noise_sample/ign/ign_temporal.
    Shaders/Utilities/PBR/    → V.1 PBR utility tree (9 files, snake_case, D-045). Load order: Fresnel → NormalMapping → BRDF → Thin → DetailNormals → Triplanar → POM → SSS → Fiber. Provides: fresnel_schlick/roughness/dielectric/f0_conductor, ggx_d/g_schlick/g_smith, brdf_ggx/lambert/oren_nayar/ashikhmin_shirley/cook_torrance, decode_normal_map/dx, ts_to_ws/ws_to_ts, tbn_from_derivatives, combine_normals_udn/whiteout, triplanar_blend_weights/sample/normal, parallax_occlusion/shadowed (POMResult), sss_backlit/wrap_lighting, fiber_marschner_lite/trt_lobe (FiberBRDFResult), thinfilm_rgb/hue_rotate.
    Shaders/Waveform.metal  → Spectrum bars + oscilloscope
    Shaders/Plasma.metal    → Demoscene plasma
    Shaders/Nebula.metal    → Radial frequency nebula
    Shaders/Starburst.metal → Murmuration sky backdrop (MV-2: mv_warp pass replaces feedback+particles; bass_att_rel drives zoom breath, mid_att_rel drives slow rotation, decay=0.97 for long cloud smear)
    Shaders/GlassBrutalist.metal → Brutalist corridor — static architecture; only the glass-fin X-position deforms with bass (Option A design, see DECISIONS D-020). Light/fog/colour modulated in shared Swift path.
    Shaders/KineticSculpture.metal → Interlocking lattice of Brushed Aluminum + Frosted Glass + Liquid Mercury, abstract ray march. FOV in degrees (post-fix; was radians, see commit history).
    Shaders/TestSphere.metal → Minimal pipeline-verification SDF (sphere + floor); used for end-to-end ray-march compile/render test.
    Shaders/SpectralCartograph.metal → Instrument-family diagnostic preset. Four-panel real-time MIR visualiser: TL=FFT spectrum (log-freq, centroid-coloured), TR=3-band deviation meters (D-026 compliant), BL=valence/arousal phase plot with 8s trail, BR=scrolling graphs for beat_phase01/bass_dev/vocal pitch. Reads SpectralHistoryBuffer at buffer(5). Direct pass only; no feedback, no warp.
    Shaders/Arachne.metal → Bioluminescent spider web 3D SDF ray march (Increment 3.5.10, D-041). Direct fragment + mv_warp (decay=0.92). 64-step ray march from z=−1.8; anchor web at (0,0,0.2) always present. Pool webs (up to 11) at hub_xy×{0.9,0.8} spread, depth z∈[−0.4,1.4]. sdWebElement: hub cap + progressive radial draw (alternating-pair order {0,6,3,9,1,7,4,10,2,8,5,11}, ±22% angular jitter per-spoke) + Archimedean spiral (7 turns, min(fract,1-fract) correct SDF). Tube radius 0.012. Beat-phase vibration. Miss-ray bioluminescent glow exp2(−dist×14) ensures D-037 acceptance. Spider SDF (ArachneSpiderGPU at buffer(7)) on anchor web when triggered. D-019/D-026 compliant.
    Arachnid/ArachneState.swift → Per-preset world state: 12-web pool, stages (anchorPulse→radial→spiral→stable→evicting), beat-measured stage advancement, drum-driven spawn accumulator, LCG PRNG, GPU webBuffer flush. (Increment 3.5.5)
    Shaders/Gossamer.metal → Bioluminescent hero-web sonic resonator (Increment 3.5.6, v3 geometry). Direct fragment + mv_warp. 17 explicitly-defined irregular spoke angles (spacing 0.27–0.77 rad, one 0.77 rad open sector lower-right). Hub at (0.465, 0.32) — upper screen — clips top spiral rings into asymmetric arcs naturally. No formula, no hash-jitter. Up to 32 propagating color waves emitted when vocalsPitchConfidence > 0.35 OR |vocalsEnergyDev| > 0.05; wave hue baked from YIN pitch, saturation from other-stem density. mv_warp trails accumulate wave echoes. Ambient drift floor keeps ≥2 waves at silence. D-026/D-019 compliant.
    Gossamer/GossamerState.swift → Per-preset world state: 32-wave pool, Wave structs with birthTime/hue/saturation/amplitude, GossamerGPU buffer (528 bytes) at fragment buffer(6). Vocal confidence gate + FV fallback. Retirement when age > maxWaveLifetime=6s. (Increment 3.5.6)
    Shaders/Stalker.metal → Bioluminescent spider silhouette mesh shader (Increment 3.5.7). 2-threadgroup dispatch: threadgroup 0 = dim static background web (hub + anchors + radials + spiral), threadgroup 1 = articulated spider body + 8 legs. Listening pose (raised front legs) fires on sustained low-attack-ratio bass. Additive blend; near-black silhouette reads against dark background via rim emissive. Organic family. Completes the Arachnid Trilogy.
    Stalker/StalkerGait.swift → Pure alternating-tetrapod gait solver: 8 Leg structs with hip/tip/knee, 2-segment IK with outward knee bend, beat phase-lock with soft pull (not snap), free-run fallback at 2.5 cycles/sec, listening-pose front-leg raise blend. (Increment 3.5.7)
    Stalker/StalkerState.swift → Per-preset world state: GaitSolver + scene mode state machine (.entering→.crossing→.listening→.exiting→.pausing), sustained-bass accumulator (0.75s threshold, low bassAttackRatio gate), StalkerGPU buffer (352 bytes) at object/mesh buffer(1). FV fallback via sub_bass + bass_att_rel heuristic. (Increment 3.5.7)
    Shaders/VolumetricLithograph.metal → Psychedelic linocut terrain (MV-2 / v4.1). fbm3D heightfield swept by `s.sceneParamsA.x` at slow rate 0.015; melody-primary blend `0.75 × (0.5 + f.mid_att_rel) + 0.35 × (0.3 + f.bass_att_rel × 0.7)` — deviation-driven, genre-stable across AGC shifts (MV-1 / D-026). Stem-accurate drivers blend in via `smoothstep(0.02, 0.06, totalStemEnergy)` warmup (D-019). Forward camera dolly at 1.8 u/s (configured in VisualizerEngine+Presets.swift). Three strata with narrow linocut coverage (~15% peaks): palette-tinted near-black valleys, razor-thin emissive ridge-line seam, polished-metal peaks. Peaks use IQ cosine `palette()` driven by terrain noise + audio time + `0.5 + f.mid_att_rel × 0.5` (melody-modulated hue) + valence. Accent/strobe from `smoothstep(0.30/0.70, stems.drums_beat)` with FV fallback `smoothstep(0.35, 0.70, f.spectral_flux)`. `f.mid_dev × 1.5` polishes peak roughness. `scene_fog: 0` truly disables fog. Miss/sky pixels tinted by `scene.lightColor.rgb`. SSGI omitted. MV-2: mv_warp pass adds temporal feedback accumulation — melody-driven zoom breath (mid_att_rel × 0.003), valence-driven rotation, decay=0.96; per-vertex UV ripple from bass (horizontal) and melody (vertical) at 0.004 UV amplitude. Passes: ray_march + post_process + mv_warp.
  Orchestrator/             → AI VJ: preset selection, transitions, session planning (Increments 4.1–4.3 complete — see ENGINEERING_PLAN.md Phase 4)
    PresetScorer            → DefaultPresetScorer: 4 weighted sub-scores (mood/tempoMotion/stemAffinity/sectionSuitability) + 2 multiplicative penalties (family-repeat, fatigue). PresetScoring protocol. PresetScoreBreakdown for inspection. (D-032)
    PresetScoringContext    → Immutable Sendable snapshot: deviceTier, frameBudgetMs, recentHistory, currentPreset, elapsedSessionTime, currentSection. PresetHistoryEntry for session history.
    TransitionPolicy        → DefaultTransitionPolicy: structural boundary (confidence≥0.5, 2.5s window) beats duration-expired timer. TransitionDecision: trigger/scheduledAt/style/duration/confidence/rationale. Style from transitionAffordances + energy. Crossfade duration scales 2.0s→0.5s with energy. TransitionDeciding protocol. (D-033)
    PlannedSession          → Output types for SessionPlanner: PlannedSession, PlannedTrack, PlannedTransition, PlanningWarning. PlannedSession.track(at:)/transition(at:) for playback-time O(N) lookups. (D-034)
    SessionPlanner          → DefaultSessionPlanner: greedy forward-walk composes PresetScorer + TransitionPolicy. SessionPlanning protocol. Synchronous plan() + async planAsync() with precompile closure. SessionPlanningError. (D-034)
  Session/
    SessionManager          → Lifecycle state machine (idle→connecting→preparing→ready→playing→ended), @MainActor ObservableObject; degrades gracefully on connector/preparation failure
    PlaylistConnector       → Apple Music (AppleScript) / Spotify (Web API) / URL parsing
    TrackIdentity           → Stable cache key: title, artist, album, duration, catalog IDs
    SessionTypes            → SessionState enum, SessionPlan stub (expanded by Orchestrator in Phase 4)
    PreviewResolver          → iTunes Search API → preview URL, in-memory cache (URL?? semantics), rate limiter (20/60s)
    PreviewDownloader        → Batch download + format-sniff + AVAudioFile decode to mono Float32, withTaskGroup concurrency ceiling (default 4)
    SessionPreparer          → Download → separate → analyze → cache per track, @MainActor ObservableObject with @Published progress
    StemCache                → Thread-safe per-track: stem waveforms + StemFeatures + TrackProfile, NSLock-guarded
    TrackProfile             → BPM, key, mood, spectral centroid avg, genre tags, stem energy balance, estimated section count.
                               NOTE: no `fullDuration` field — full track duration comes from TrackIdentity.duration (Double?, nil = unknown). SessionPlanner defaults to 180 s when nil.
  Shared/
    UMABuffer               → Generic .storageModeShared MTLBuffer + UMARingBuffer
    AudioFeatures           → @frozen SIMD-aligned structs (see Key Types below)
    AnalyzedFrame           → Timestamped container: AudioFrame + FFTResult + StemData + FeatureVector + EmotionalState
    StemSampleBuffer        → Interleaved stereo PCM ring buffer for stem separation input (15s)
    RenderPass              → Enum: direct, feedback, particles, mesh_shader, post_process, ray_march, icb, ssgi, mv_warp
    Logging                 → Per-module os.Logger instances (subsystem: "com.phosphene")
    SessionRecorder         → Continuous diagnostic capture per app launch: video.mp4 (H.264, 30 fps) + features.csv + stems.csv + stems/<N>_<title>/{drums,bass,vocals,other}.wav + session.log. Writes to ~/Documents/phosphene_sessions/<timestamp>/. Writer locks after 30 stable drawable frames; if a different size arrives consistently for ≥90 frames after lock (bad initial lock from transient Retina→logical-point resize), tears down and relocks — logs "video writer relocking". Finalised on NSApplication.willTerminateNotification. Validated by SessionRecorderTests.
    SpectralHistoryBuffer   → Per-frame MIR history ring buffer. 5 rings × 480 samples (≈8s at 60fps) in a 16 KB UMA MTLBuffer bound at fragment index 5 in direct-pass encoders. Tracks valence, arousal, beat_phase01, bass_dev, log-normalized vocal pitch. Updated once per frame in RenderPipeline.draw(in:); reset on track change.
    DeviceTier              → .tier1 (M1/M2) / .tier2 (M3/M4). frameBudgetMs getter. Used by PresetScoringContext for complexity-cost exclusion gate.
Tests/
  Audio/                    → AudioBufferTests, FFTProcessorTests, StreamingMetadataTests, MetadataPreFetcherTests, LookaheadBufferTests, SilenceDetectorTests
  DSP/                      → SpectralAnalyzerTests, BandEnergyProcessorTests, ChromaExtractorTests, BeatDetectorTests, MIRPipelineUnitTests, SelfSimilarityMatrixTests, NoveltyDetectorTests, StructuralAnalyzerTests, BeatPredictorTests, PitchTrackerTests, StemAnalyzerMV3Tests
  ML/                       → StemSeparatorTests, StemFFTTests, StemModelTests, MoodClassifierTests
  Renderer/                 → MetalContextTests, ShaderLibraryTests, RenderPipelineTests, ProceduralGeometryTests, MeshGeneratorTests, BVHBuilderTests, RayIntersectorTests, PostProcessChainTests, ShaderUtilityTests, TextureManagerTests, RayMarchPipelineTests, SceneUniformsTests, FeatureVectorExtendedTests, SSGITests, RenderPipelineICBTests, MVWarpPipelineTests, SpectralCartographTests
  Utilities/                → NoiseTestHarness (compute-pipeline harness), NoiseUtilityTests (~30 @Test, 10 suites), PBRUtilityTests (~45 @Test, 8 suites) — all V.1 utility tests
  Shared/                   → AudioFeaturesTests, UMABufferExtendedTests, EmotionalStateTests, AnalyzedFrameTests, SpectralHistoryBufferTests
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

### Tempo

75th percentile of bass flux buffer × 2.0, with 150ms minimum spacing. Known octave-error limitation (basic autocorrelation often returns half-tempo). Pre-fetched BPM from metadata APIs disambiguates.

### Chroma

Bin-count normalized: weight = `1/binsInPitchClass`. Skip bins below 65 Hz. At 48kHz/1024-point FFT, pitch classes get 31–55 bins — without normalization, key estimation is biased.

### Mood Classifier Inputs

10 features: 6-band energy, centroid, flux, major/minor key correlations. NOT raw 12-bin chroma (a tiny MLP cannot learn the Krumhansl-Schmuckler function from raw bins). Spectral flux normalized via running-max AGC (0.999 decay). Centroid normalized by Nyquist (24000 Hz).

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
                              // valence, arousal, beat_phase01, bass_dev, vocals_pitch_norm.
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
              [1920..2399] vocals_pitch_norm history (0..1, log-mapped 80..800 Hz, 0 = unvoiced)
              [2400] write_head  [2401] samples_valid
buffer(6–7) = future use
```

**Authoring note:** buffer(0) is `FeatureVector`, not FFT — the old documentation was wrong. All existing presets (Starburst, VolumetricLithograph, etc.) bind in this order. New preset fragment functions must declare `constant FeatureVector& fv [[buffer(0)]]`. The `SpectralHistory` buffer(5) is available in direct-pass presets; ray march presets currently skip it.

### Preamble Compilation Order
`FeatureVector struct` → `V.1 Noise utility tree (9 files)` → `V.1 PBR utility tree (9 files)` → `ShaderUtilities.metal functions` → `constexpr sampler declarations` → preset shader code.

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
| `family` | required | Aesthetic family: `fluid`, `geometric`, `abstract`, `fractal`, `instrument`, etc. |
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
| `visual_density` | 0.5 | 0 = sparse/minimal, 1 = packed/busy. Low-arousal tracks prefer low density. (Increment 4.0) |
| `motion_intensity` | 0.5 | 0 = static/slow, 1 = fast/kinetic. Informs tempo match during scoring. (Increment 4.0) |
| `color_temperature_range` | `[0.3, 0.7]` | `[cool, warm]` each 0–1. 0 = cold blue, 1 = hot orange. Intersected with mood-derived target range. (Increment 4.0) |
| `fatigue_risk` | `"medium"` | `"low"`, `"medium"`, or `"high"`. Controls cooldown penalty between reuses. Unknown values log a warning and fall back to medium. (Increment 4.0) |
| `transition_affordances` | `["crossfade"]` | Array of `"crossfade"`, `"cut"`, `"morph"`. Styles this preset tolerates as incoming/outgoing transition. (Increment 4.0) |
| `section_suitability` | all sections | Array of `"ambient"`, `"buildup"`, `"peak"`, `"bridge"`, `"comedown"`. Sections this preset suits. Default = all (no penalty). (Increment 4.0) |
| `complexity_cost` | `{"tier1":1.0,"tier2":1.0}` | Estimated ms at 1080p per device tier (M1/M2 = tier1, M3+ = tier2). Accepts scalar or `{"tier1":x,"tier2":y}`. (Increment 4.0) |

---

## Visual Quality Floor

See `docs/SHADER_CRAFT.md` for the authoring handbook. This section is the short contract every preset shader session must satisfy.

**The detail cascade (mandatory).** Every primary surface has four distinct detail scales layered:

1. **Macro** — SDF geometry or mesh silhouette (unit scale).
2. **Meso** — variation ridges, dents, per-instance jitter (∼0.1–0.3 unit scale).
3. **Micro** — surface-scale normal / texture detail (∼0.01–0.03 unit scale).
4. **Specular breakup** — roughness variation, glints, grunge (pixel to sub-pixel scale).

A preset that skips any cascade layer reads as primitive, regardless of clever audio routing. This is enforced by the rubric below.

**Noise floor (mandatory).** Minimum **4 octaves** of noise on any hero surface. The `fbm8` and `warped_fbm` utilities in `Shaders/Utilities/Noise/` (Phase V.1–V.3) are the default. Single-octave-fBM presets fail certification.

**Material count (mandatory).** Minimum **3 distinct materials** per preset, drawn from the cookbook in `SHADER_CRAFT.md §4` (20 recipes: polished chrome, brushed aluminum, silk thread, wet stone, frosted glass, ferrofluid, bark, leaf, etc.). Plasma-family stylized presets are exempt.

**Authoring workflow (mandatory).** Coarse-to-fine, 9 passes: macro geometry → materials → meso variation → micro detail → specular breakup → atmosphere → lighting polish → audio reactivity → review. See `SHADER_CRAFT.md §2.2`. Writing a finished-looking shader in a single pass is the observed cause of every primitive output.

**Reference-image-first (mandatory).** Before writing MSL, read `docs/VISUAL_REFERENCES/<preset>/README.md` and the curated images. Authoring from prose description alone is observed Failed Approach #40. Session prompts must cite specific reference image filenames for the traits being implemented.

**Rubric (enforced at certification — Increment V.6).**

- Mandatory 7/7: detail cascade, ≥4 noise octaves, ≥3 materials, deviation-primitive audio (D-026), graceful silence fallback, p95 frame time ≤ tier budget, Matt-approved reference frame match.
- Expected ≥2/4: triplanar texturing, detail normals, volumetric fog / aerial perspective, SSS / fiber BRDF / anisotropic specular.
- Strongly preferred ≥1/4: hero specular highlight in ≥60% of frames, POM on at least one surface, volumetric light shafts or dust motes, chromatic aberration / thin-film interference.

Minimum score: **10/15** with all mandatory passing. Uncertified presets stay in the catalog but Orchestrator excludes them by default.

**Shader file length.** SwiftLint `file_length: 400` is relaxed for `.metal` files (see `SHADER_CRAFT.md §11.1`). Good ray-march shaders run 800–2000 lines; do not truncate or split for lint conformance.

---

## Session Preparation Pipeline

**Lifecycle:** `idle` → `connecting` → `preparing` → `ready` → `playing` → `ended`.

**Per-track preparation:** Download preview (iTunes Search API `previewUrl`) → decode to PCM (AVAudioFile) → stem separation (MPSGraph, ~142ms) → MIR pipeline (BPM, key, mood, spectral, structural) → cache in StemCache.

**Track transition behavior:** On track change, `VisualizerEngine` loads cached stems from StemCache — StemFeatures is populated immediately, never zeroed. StemSampleBuffer is NOT cleared (ring buffer continues for real-time refinement). Real-time separation crossfades with cached data after ~10–15s. No preset ever sees zero stems during a playlist session.

**Performance budget:** 142ms stem separation per track. Preview downloads are the bottleneck (~10MB total). Total: ~20–30 seconds for a 20-track playlist.

**Metadata fetcher priority:** MusicBrainz (always, free) → Soundcharts (optional, commercial, gated by env vars) → Spotify (optional, search-only) → MusicKit (optional). Self-computed MIR is the authoritative source.

---

## UX Contract

See `docs/UX_SPEC.md` for the full product UX specification (personas, onboarding, preparation UI, error taxonomy, copy guide, settings surface, accessibility). This section is the short contract every UI session must satisfy.

**State-to-view mapping (mandatory).** `ContentView` is a pure switch on `SessionManager.state`. Six top-level views, one per state — no orphans, no overloaded views:

| State | View | Purpose |
|---|---|---|
| `.idle` | `IdleView` | Connect a playlist or start ad-hoc |
| `.connecting` | `ConnectingView` | Per-connector spinner + cancel |
| `.preparing` | `PreparationProgressView` | Per-track status + partial-ready CTA |
| `.ready` | `ReadyView` | "Press play in your music app" + first-audio autodetect |
| `.playing` | `PlaybackView` | Full-bleed visuals + auto-hiding overlay chrome |
| `.ended` | `EndedView` | Session summary + new session affordance |

`ContentView` owns no logic beyond routing. View logic lives in per-view ViewModels (`@MainActor ObservableObject`).

**Copy principles (mandatory).** User-facing strings follow `UX_SPEC.md §8.5`:
- Describe the situation, not the exception. Not "NSURLError -1009" but "You're offline."
- Every error message has a CTA or a clear "auto-retrying" status.
- No jargon: never "MPSGraph," "FFT," "tap," "DRM," or "sandbox" in user copy. Internal logs use jargon freely.
- Never apologize. Either describe what happened or offer a fix.
- Never show a full-screen error during `.playing`. Bottom-right toast only. The visuals are the point.

**Product truths (never violate).**
- Phosphene does not control playback. No pause/play/skip buttons on `PlaybackView` — they'd lie.
- First-audio autodetect advances `.ready → .playing`. No user click required.
- Every user-facing string is externalized in `Localizable.strings`, even in English-only v1.
- Debug overlay (`D` key) is separate from user overlay chrome (`Space` key). Hidden by default for users.
- Overlay text has ≥4.5:1 contrast against worst-case preset frame via blurred dark backdrop.
- Reduced-motion mode disables `mv_warp` feedback and caps beat-pulse amplitude.

**Error taxonomy authority.** `UX_SPEC.md §8` is the canonical mapping from internal error state to user-facing language. Any new `UserFacingError` case must add a row to that table before shipping. `RUNBOOK.md §Common Failure Modes` stays developer-facing and should cross-reference UX_SPEC copy to prevent drift.

**Progressive readiness.** `PreparationProgressView` shows a **"Start now"** CTA at the `ready_for_first_tracks` threshold (Increment 6.1). Users are not forced to wait for full playlist preparation. `SessionManager` exposes `progressiveReadinessLevel` so playback can show a subtle indicator while trailing tracks continue preparing.

---

## ML Inference

No CoreML dependency. All ML uses MPSGraph (GPU) or Accelerate (CPU).

**Stem separator (MPSGraph):** Open-Unmix HQ. Float32 throughout. 172 weight tensors (135.9 MB) in `ML/Weights/`, Git LFS. STFT: n_fft=4096, hop=1024, sample_rate=44100, 431 frames (~10s). Bidirectional 3-layer LSTM, hidden=256, gate_size=1024. BN fused at init (12 fusions). STFT/iSTFT via Accelerate/vDSP. Input magnitudes written directly to pre-allocated MTLBuffers via memcpy. 142ms warm predict. Hard gate: 400ms.

**Mood classifier (Accelerate):** 4-layer MLP (10→64→32→16→2) via 3× `vDSP_mmul`. 3,346 hardcoded Float32 params from DEAM training. Outputs continuous valence/arousal (-1…1), EMA smoothed.

**Stem separation cadence:** Background `DispatchSourceTimer`, 5s, utility QoS. Track-change loads from StemCache first, then live refinement crossfades.

**Stem analysis cadence (per-frame since engine increment 3.5.4.9):** `StemAnalyzer` runs every audio-callback frame on `analysisQueue`, slicing a 1024-sample window from the latest separated stem waveforms. Window scans from the chunk's 5-second mark forward at real-time rate so `StemFeatures` values in GPU buffer(3) update continuously (~94 Hz) instead of stepping every 5s. Before this change stems were piecewise-constant for 5s — session `2026-04-16T20-56-46Z` showed only 25 unique `drumsBeat` values across 8,987 frames (0.3%), which made stem-driven preset visuals freeze for 5 seconds then jump.

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
31. **Absolute thresholds on AGC-normalized energy** (e.g. `smoothstep(0.22, 0.32, f.bass)`): AGC's denominator (running-average) moves with mix density, so the same acoustic kick reads different values across tracks or across sections of one track. Six VL iterations (v3→v4.2) hit this repeatedly. Drive from deviation instead — `f.bassRel`, `f.bassDev` (D-026, MV-1). See `docs/MILKDROP_ARCHITECTURE.md` for the full diagnosis.
32. **Driving ray-march preset visuals from instantaneous audio alone**: feedback is the mechanism that turns simple audio into compound musical motion (Milkdrop's core insight). Ray-march presets rendered from scratch each frame can only show instantaneous audio state — no accumulation, no "breathing", no musicality regardless of how clever the shader drivers are. Fixed in MV-2: the `mv_warp` render pass (D-027) provides per-vertex feedback accumulation. See VolumetricLithograph for the reference implementation.
33. **Free-running `sin(time)` oscillation in organic preset motion**: A `sin(time * k)` term runs at a fixed cycle rate regardless of music, making the visual feel mechanical and disconnected from the audio. Observed in Arachne v1 (session 2026-04-21T13-26-38Z): hub throb `sin(time*9)` ≈ 1.4 Hz oscillation ignored tempo entirely; strand quiver `sin(dist*15 - time*4.8)` scrolled continuously even at silence. Fix: replace with beat_phase01-locked phase (`sin(dist*k - beat_phase01*2π)` = exactly one wave per beat) or beat-anticipation amplitude (`smoothstep(0.75, 1.0, beat_phase01)`). If BeatPredictor has no stable estimate, gate on `bassDev > 0` so motion only fires on above-average transients.
34. **`abs(fract(x) − 0.5)` as an SDF fold for periodic structures (spiral threads, ring bands)**: This formula gives 0 at integer positions (in the GAPS between threads) and 0.5 at half-integer positions (ON the threads). It is the inverse of a correct distance field — coverage computed from it is maximal everywhere threads are NOT, filling the entire area instead of drawing thin strands. Use `min(fract(x), 1 − fract(x))` which correctly gives 0 ON the thread and 0.5 in the gaps. Bit both Arachne and Gossamer during Increment 3.5.10/3.5.11 and caused both to render as filled discs. The visual tells: perfectly uniform lit region where web should be, no strand structure visible.

35. **Single-octave noise for hero surfaces**: 1–3 octaves of Perlin or fBM reads as primitive. Real surfaces have variation across many spatial frequencies simultaneously. Minimum 4 octaves for any hero surface; 8 octaves (`fbm8` utility) for terrain or cloud fields. Observed across every preset iteration before Phase V. See `SHADER_CRAFT.md §3`.

36. **Uniform-albedo-per-material presets**: A constant `float3 albedo` anywhere on a hero surface reads as clipart. Real surfaces have per-point variation. Drive albedo through `fbm8` or `worley_fbm` at minimum, or through a cookbook material recipe from `SHADER_CRAFT.md §4` that already layers variation.

37. **Constant roughness**: `roughness = 0.3` across a surface reads as CGI-plastic. Vary roughness spatially via noise. Even 10% variation breaks the plastic look. Silk, metal, wet stone, ferrofluid — all need spatially varied roughness.

38. **Grey fog**: Fog color matching scene palette (sky, horizon, mood) reads as atmosphere. Grey fog reads as a printing defect. Always tint fog to match scene, not to a neutral middle-gray.

39. **Authoring shaders without reading `docs/VISUAL_REFERENCES/<preset>/`**: Claude Code has no visual feedback loop; the only way to hit quality targets is to anchor on specific reference images before writing code. Sessions that skip this produce primitive output, observed across every preset iteration v1→v3 prior to Phase V. Session prompts must cite specific reference image filenames for the traits being implemented. See `SHADER_CRAFT.md §2.3`.

40. **Cylinder-as-silk, cube-as-rock, sphere-as-organic**: SDF primitives are building blocks, not final forms. Always apply at least one modifier (displacement, twist, noise-driven deformation, smooth union with secondary primitive) before applying materials. An unmodified primitive with a fancy material still reads as a primitive.

41. **SwiftUI accessibility tree traversal in unit tests**: On macOS, SwiftUI only materialises the `accessibilityChildren()` tree when an active accessibility client (VoiceOver, Accessibility Inspector, XCUITest) queries it. In unit tests running via `xcodebuild test`, no client exists — `accessibilityChildren()` returns empty even after rendering into an NSWindow with a RunLoop cycle. ObjC dynamic dispatch (`NSSelectorFromString("accessibilityChildren")`) has the same limitation. Fix: expose `static let accessibilityID: String` on each view and bind it via `.accessibilityIdentifier(Self.accessibilityID)`. Tests check the static constant; the binding is enforced by construction. See D-044.

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
- Do not threshold absolute AGC-normalized energy values (`f.bass > 0.22`). Drive from deviation primitives (`f.bassDev`, `f.bassRel`) — D-026.
- Do not write new ray-march presets without also implementing the `mv_warp` pass (D-027, MV-2). The shader runs every frame from scratch; without per-vertex feedback accumulation, motion cannot compound and visuals feel disconnected from music regardless of how clever the audio drivers are. See `docs/MILKDROP_ARCHITECTURE.md`. VolumetricLithograph is the reference implementation — add `"mv_warp"` to the preset's passes JSON and implement `mvWarpPerFrame`/`mvWarpPerVertex` in the .metal file.
- Do not author a preset without first reading `docs/VISUAL_REFERENCES/<preset>/README.md` and the curated reference images. Authoring from prose description alone is Failed Approach #39.
- Do not ship a preset with fewer than 4 octaves of noise on any hero surface. Mandatory per `SHADER_CRAFT.md §12.1`.
- Do not ship a preset with fewer than 3 distinct materials. Mandatory per `SHADER_CRAFT.md §12.1`. Plasma-family exempt.
- Do not skip the coarse-to-fine authoring workflow (`SHADER_CRAFT.md §2.2`). A single-pass shader that tries to do everything at once is untuneable and ships primitive.
- Do not show full-screen errors during the `.playing` state. Use bottom-right toasts only. Per `UX_SPEC.md §8`.
- Do not put pause / play / skip controls in `PlaybackView`. Phosphene does not control playback and any such control would lie. Per `UX_SPEC.md UX-2`.
- Do not use jargon in user-facing strings (FFT / MPSGraph / tap / DRM / sandbox / SSGI / G-buffer). Internal logs use jargon freely; user copy does not. Per `UX_SPEC.md §8.5`.
- Do not bypass the certification rubric when a preset visually "feels done." Matt-approved reference frame match is mandatory per `SHADER_CRAFT.md §12.1`.

---

## Current Status

**Phase U (UX Architecture) in progress — U.1 through U.9 complete. Phase 4 (Orchestrator), Phase 3, and Phase 2.5 (session preparation) complete.** Recent landed work:

- **Increment U.9: Accessibility pass** — Three-part delivery. Part A: `AccessibilityState` (`@MainActor ObservableObject`, `NSWorkspace` + `ReducedMotionPreference` three-way logic), `applyPreference(_:)`, `shouldExecuteMVWarp(presetEnabled:)`, `beatAmplitudeScale`. Engine: `RenderPipeline.frameReduceMotion` gates mv_warp via extracted `drawMVWarpReducedMotion()`; `RayMarchPipeline.reducedMotion` gates SSGI (`ssgiEnabled && !reducedMotion`). Beat-clamp applied to `beatBass/Mid/Treble/Composite` in `draw(in:)` before `renderFrame` — timing primitives (`beatPhase01`, `beatsUntilNext`) left untouched. `SessionStateViewModel` updated to take `accessibilityState:` at init. Part B: Dynamic Type — 16 user-facing view files updated (all `.system(size:)` → semantic SwiftUI font styles). VoiceOver — `MetalView.setAccessibilityElement(false)`, 8 interactive elements labelled, `AccessibilityLabels` service (connector tile, track info card, toast), 14 new `Localizable.strings` a11y keys, `AccessibilityNotification.Announcement` on new toasts, `TopBannerView` dismiss label localized. Part C: `QualityGradeIndicator` (SF Symbol shape + G/Y/R letter for color-blindness), `DebugOverlayView` SIGNAL block updated, `PresetContrastCertificationTests` (WCAG 4.5:1 gate over all presets × 3 fixtures). New tests: 5 `AccessibilityStateTests` + 3 `BeatAmplitudeClampTests` + 5 `MVWarpReducedMotionGateTests` + 9 `AccessibilityLabelsTests` + 1 `DynamicTypeRegressionTests` + N×3 `PresetContrastCertificationTests` (587 engine total; 0 SwiftLint violations). D-054.
- **Increment U.8: Settings panel** — Three-part delivery. Part A+B: `SettingsTypes` (`CaptureMode`, `DeviceTierOverride`, `ReducedMotionPreference`, `SessionRetentionPolicy`, `SourceAppOverride`), `QualityCeiling` enum in Orchestrator module (`.auto/.performance/.balanced/.ultra` with `complexityThresholdMs(for:)` gate), `SettingsStore` (`@MainActor ObservableObject`, `phosphene.settings.*` key scheme, 11 `@Published` properties, `captureModeChanged: PassthroughSubject`), `SettingsMigrator` (one-time legacy key migration), `SettingsViewModel` (computed bindings, `AboutSectionData.current()`, `includeMilkdropPresetsDisabled` Phase MD gate), `SettingsView` (`NavigationSplitView` sheet, 720×520pt, four sections: Audio/Visuals/Diagnostics/About), `CaptureModeReconciler` (LIVE-SWITCH PATH via `AudioInputRouter.switchMode(_:)`, D-052), `SessionRecorderRetentionPolicy.apply(policy:sessionsDir:now:wallClock:)` (no-op if dir absent, active-session guard), `OnboardingReset`. Part C: `PresetScoringContext` extended with `excludedFamilies: Set<PresetCategory>` and `qualityCeiling: QualityCeiling` (both defaulted for backward-compat, D-053), `DefaultPresetScorer` checks blocklist then quality-ceiling budget, `PresetScoringContextProvider.build()` propagates settings, `SessionRecorder.init(enabled:)` early-returns nil when disabled, `LiveAdaptationToastBridge` key migrated to `phosphene.settings.visuals.*`, `PhospheneApp.swift` calls `SettingsMigrator.migrate()` + `SessionRecorderRetentionPolicy.apply()` at launch, settings gear in `PlaybackView` opens sheet. 50 new `Localizable.strings` keys. 39 new app tests + 9 engine tests (573 engine total); 0 SwiftLint violations. D-052, D-053.
- **Increment U.7: Error taxonomy + toast system** — Three-part delivery. Part A: `UserFacingError` (29 cases, engine `Shared` module), `Localizable.strings` (English), `LocalizedCopy` service, retroactive string extraction from U.1–U.6 views. Part B: `FullScreenErrorView`, `PreparationFailureView`, `TopBannerView` (44pt amber banner), `PreparationErrorViewModel` (6-rule priority: offline → allFailed → rateLimited → slowFirstTrack → totalTimeout → normal), `ReachabilityMonitor` (NWPathMonitor + 1s debounce). Wired into `PreparationProgressView`. Part C: `PhospheneToast.conditionID`, `ToastManager.dismissByCondition/_isConditionAsserted`, `PlaybackErrorConditionTracker`, `PlaybackErrorBridge` (replaces `SilenceToastBridge`; fires silence toast at 15s per §9.4, condition-ID auto-dismiss on recovery). Wired into `PlaybackView`. 15 new tests; 0 SwiftLint violations. D-051.
- **Increment U.6: PlaybackView chrome — auto-hiding overlay, keyboard shortcuts, toasts, fullscreen, multi-display** — Complete rewrite of `PlaybackView` with publisher-injection pattern (ContentView passes `engine.$xxx.eraseToAnyPublisher()` at callsite). Layer stack: MetalView → `TrackChangeAnimationView` (center-to-top-left boundary animation) → `PlaybackChromeView` (auto-hiding) → `ShortcutHelpOverlayView` (Shift+?) → `DebugOverlayView` → end-session confirm dialog. New files: `PlaybackChromeViewModel` (auto-hide timer, track/preset/plan subscriptions), `ToastManager` (3-slot queue, severity: info/warning/degradation), `PlaybackShortcutRegistry` (16 shortcuts in 3 categories — playback/liveAdaptation/developer), `PlaybackKeyMonitor` (NSEvent-based, replaces .onKeyPress), `FullscreenObserver` (NSWindow notification-based), `DisplayManager` (NSScreen observer, screen add/remove callbacks), `LiveAdaptationToastBridge` (wires future U.6b adaptation events to toast queue), `MultiDisplayToastBridge` (display connect/disconnect toasts), `DefaultPlaybackActionRouter` (stub implementations, all wired to `PlaybackActionRouter` protocol in Orchestrator module), `EndSessionConfirmViewModel`, `PhospheneToast` model. View layer: `TrackInfoCardView`, `ListeningBadgeView`, `SessionProgressDotsView`, `PlaybackControlsCluster`, `PlaybackChromeView`, `ShortcutHelpOverlayView`, `ToastView`, `ToastContainerView`, `TrackChangeAnimationView`, `OverlayBackdropStyle`. Engine additions: `PlaybackActionRouter` protocol in Orchestrator module (U.6b semantics documented as TODOs). 44 new app tests (551 engine + 145 app = 696 total); 0 SwiftLint violations. D-049 (Shift+? vs P keybinding split), D-050 (PlaybackActionRouter protocol in Orchestrator module).
- **Increment U.5: ReadyView — plan preview + first-audio autodetect + timeout recovery + regenerate plan** — Four parts delivered. Part A: `ReadyView` (headline, subtext, pulsing border, 90-second timeout overlay), `ReadyViewModel` (`@MainActor ObservableObject`, 90s Task-based timeout, `retry()` / `endSession()`), `FirstAudioDetector` (250ms sustained `.active` gate, `.suspect` is no-op, `reset()` on retry), `ReadyPulsingBorder` / `ReadyBackgroundPresetView` stubs. Part B: `PlanPreviewView` (sheet with `NavigationStack`), `PlanPreviewViewModel` (track list from `PlannedSession`, manual lock/unlock per track, `regeneratePlan()` spinner), `PlanPreviewRowView` (track number, lock icon, preset name, family pill, duration, context menu), `PlanPreviewTransitionView` (crossfade/cut badge). Part C: `PresetPreviewController` stub (deferred per D-048 to U.5b). Part D: `DefaultSessionPlanner.plan(seed:)` — seeded ±0.02 LCG perturbation via `seededNoise(seed:trackIndex:presetID:)` (D-047); `PlannedSession.applying(overrides:)` in Orchestrator module; `VisualizerEngine.regeneratePlan(lockedTracks:lockedPresets:)` wires seed + lock preservation into the live plan. 551 engine tests + 101 app tests; 0 SwiftLint violations. D-047 (seeded regeneration), D-048 (preview loop deferred to U.5b).
- **Increment U.4: Preparation progress UI** — Full `PreparationProgressView` rewrite with per-track rows (`TrackPreparationRow` + `TrackPreparationStatusIcon`), 4pt aggregate progress Capsule bar, cancel confirmation dialog (gated on ≥1 `.ready` track), and dormant "Start now" CTA (`FeatureFlags.progressiveReadiness = false` until Inc 6.1). `PreparationProgressViewModel` subscribes to `PreparationProgressPublishing`, maintains `trackList`-ordered `[RowData]`, `PreparationCounts`, and ETA estimates via `PreparationETAEstimator` (EMA α=0.3, ≥3 samples gate). Engine additions: `TrackPreparationStatus` (7-case enum), `PreparationProgressPublishing` protocol, `SessionPreparer` instrumented with `@Published trackStatuses`, `preparationTask` stored Task, and `withTaskCancellationHandler` propagating outer-task cancellation. `SessionManager.cancel()` + `preparingTracks` + `preparationProgress` wired through `ContentView.preparingView`. 23 new tests (20 engine + 3 cancel integration). 546 engine + 70 app tests; 0 SwiftLint violations.
- **Increment U.3: Playlist connector picker** — `ConnectorPickerView` (NavigationStack in `.sheet` from IdleView) with three tiles: Apple Music (disabled when not running), Spotify (URL paste), Local folder (coming later stub). `ConnectorPickerViewModel` uses `NSWorkspace` launch/terminate observers with `nonisolated(unsafe)` storage (Swift 6 `deinit` constraint). `AppleMusicConnectionViewModel`: five-state machine with 2s auto-retry on `.noCurrentPlaylist` via injectable `DelayProviding`. `SpotifyConnectionViewModel`: URL debounce (300ms), `SpotifyURLParser` (handles HTTPS/URI/@ forms), HTTP 429 backoff [2s, 5s, 15s], `.spotifyAuthRequired` degrades to `startSession` directly (no OAuth in U.3). `PhospheneApp.swift`: removed auto-start `startAdHocSession()` — replaced by "Start listening now" button in IdleView. `LocalFolderConnector` stub (`#if ENABLE_LOCAL_FOLDER_CONNECTOR`). D-046 in DECISIONS.md. 56 PhospheneApp tests; 0 SwiftLint violations.
- **Increment U.2: Permission onboarding** — `PermissionMonitor` (`@MainActor ObservableObject`) checking `CGPreflightScreenCaptureAccess` on every `NSApplication.didBecomeActiveNotification`. `PermissionOnboardingView` (URL-scheme to System Settings, return auto-detected). `PhotosensitivityNoticeView` (one-time sheet on first IdleView appearance, backed by `PhotosensitivityAcknowledgementStore`). `ContentView` refactored to two-level switch: permission gate above state switch. Key decision: preflight + URL scheme, NOT `CGRequestScreenCaptureAccess()` — the request API's system dialog doesn't compose with "open and return" UX.
- **Increment V.1: Shader utility library (Noise + PBR)** — 18 new `.metal` utility files in `Sources/Presets/Shaders/Utilities/`. Noise tree (9 files): Hash → Perlin → Simplex → FBM → RidgedMultifractal → Worley → DomainWarp → Curl → BlueNoise. PBR tree (9 files): Fresnel → NormalMapping → BRDF → Thin → DetailNormals → Triplanar → POM → SSS → Fiber. `PresetLoader+Preamble.swift` extended with `noiseLoadOrder`/`pbrLoadOrder` arrays and `loadUtilityDirectory(_:priorityOrder:from:)` — utilities concatenated before ShaderUtilities.metal. New tests: `NoiseTestHarness.swift` (compute-pipeline harness), `NoiseUtilityTests.swift` (~30 @Test), `PBRUtilityTests.swift` (~45 @Test). Zero dHash drift in PresetRegressionTests. D-045 in DECISIONS.md. 85 utility tests pass; 453 total; pre-existing failures unchanged.
- **Increment U.1: Session-state views** — `SessionStateViewModel` (`@MainActor ObservableObject`) bridges `SessionManager.state` → SwiftUI; publishes `state` + `reduceMotion`. Six stub views under `PhospheneApp/Views/` (IdleView, ConnectingView, PreparationProgressView, ReadyView, PlaybackView, EndedView), each with `static let accessibilityID` and `.accessibilityIdentifier(Self.accessibilityID)`. ContentView refactored to pure switch on `viewModel.state`. PlaybackView absorbs Metal/overlay chrome from former ContentView. PhospheneApp.swift wired: VisualizerEngine owns SessionManager; ad-hoc session starts at launch. New `PhospheneAppTests` target with 9 tests. D-044. 453 tests total; pre-existing failures unchanged.
- **Increment 3.5.11: Gossamer SDF correction + v3 acceptance** — Fixed inverted SDF in `gossamerSpiralDist` and `gossamerHubDist` (`abs(fract−0.5)` → `min(fract, 1−fract)`): the old formula gave 0 in thread gaps and 0.5 on threads, making the entire capture zone render as a filled disc instead of a web. Also corrected D-037 acceptance invariant 3: brightness formula changed to `0.12 + f.bass×0.76 + bassRel×0.12` so silence (f.bass=0) is dim and steady music (f.bass≈0.5) is lit; beat flash reduced 0.65→0.30. Includes v3 geometry: 17 explicit irregular spoke angles, off-center hub at (0.465, 0.32), kWebRadius 0.42→0.44, elliptical stretch removed. D-042. Golden hashes regenerated. 444 tests; pre-existing failures unchanged.
- **Increment 3.5.10: Arachne ray march remaster** — Complete shader rewrite from mesh_shader to 3D SDF ray march (direct fragment + mv_warp). 64-step march; camera at z=−1.8 for dramatic close-up scale. `sdWebElement` draws webs progressively: alternating-pair radial order {0,6,3,9,1,7,4,10,2,8,5,11} mirrors real orb-weaver construction; ±22% per-spoke angular jitter via `rng_seed` hash makes each web unique. Corrected SDF (`min(fract, 1−fract)`) for spiral threads. Pool webs mapped to 3D at varying depths z∈[−0.4,1.4]; anchor web always at (0,0,0.2). Spider always placed on anchor web, fixing Z-depth mismatch. Miss-ray glow `exp2(−minWebDist×14)` ensures D-037 formComplexity. `directPresetFragmentBuffer2` (buffer(7)) infrastructure for spider GPU struct. D-041. 444 tests; pre-existing failures unchanged.
- **Increment 3.5.9: Spider easter egg in Arachne** — 3D ray-march SDF spider materialises as a rare reward (~1-in-10 songs) inside the Arachne mesh-shader preset. Trigger: `subBass > 0.65 AND bassAttackRatio < 0.55` held ≥ 0.75 s (sustained resonant bass, not kick drums) + 300 s session cooldown. `ArachneSpiderGPU` (80 bytes) at fragment buffer(4) via new `meshPresetFragmentBuffer` infrastructure in `RenderPipeline`. `ArachneState+Spider.swift` extension: gait solver (alternating-tetrapod, smoothstep foot-plant easing), `activateSpider()` (positions at most-opaque stable web hub, initialises 8 leg tips), `writeSpiderToGPU()`. `Arachne.metal`: `ArachneSpiderGPU` struct, 5 SDF helpers (`spOpSmoothUnion`, `spSdCapsule`, `spSdEllipsoid`, `sdSpiderLocal`, `calcSpiderNormal`), PBR chitin overlay (near-black base + iridescent spec + bioluminescent rim). `float2 clipXY` added to `MeshVertex` for screen-space ray-march. D-040 in DECISIONS.md. 444 tests total; pre-existing failures unchanged.
- **Increment 5.3: Visual Regression Snapshots** — `PresetRegressionTests.swift`: 3 parametrized regression tests × 11 presets (Fractal Tree excluded — meshShader). 64-bit dHash via 9×8 luma grid + horizontal-difference bits. Hamming distance ≤ 8 tolerance. `goldenPresetHashes` dictionary inline in test file. `UPDATE_GOLDEN_SNAPSHOTS=1 swift test --filter test_printGoldenHashes` regenerates all values. `_acceptanceFixture`/`PresetFixtureContext` promoted to `internal` in `PresetAcceptanceTests.swift`. D-039 in DECISIONS.md. 439 tests total; pre-existing failures unchanged.
- **Increment 4.5: Live Adaptation** — `LiveAdapter.swift` + `LiveAdapter+Patching.swift` + `VisualizerEngine+Orchestrator.swift`. `DefaultLiveAdapter` implementing `LiveAdapting` protocol: boundary reschedule fires when `confidence ≥ 0.5` and deviation > 5 s (wins over mood override); mood override fires when `|Δv| > 0.4 || |Δa| > 0.4`, elapsed < 40%, and an alternative preset scores > 0.15 higher. `LiveAdaptation` result type with nested `PresetOverride` struct (Sendable-safe). `PlannedSession.applying(_:at:)` extension in Orchestrator module for controlled patching using internal memberwise inits. App-layer wiring in `VisualizerEngine+Orchestrator.swift`: `buildPlan()`, `currentPreset(at:)`, `currentTransition(at:)`, `applyLiveUpdate(...)`, `detectDeviceTier(device:)`. 8 unit tests. D-035 in DECISIONS.md. 407 tests total; 4 pre-existing Apple Music env failures unchanged.
- **Increment 4.4: Golden session fixtures** — `GoldenSessionTests.swift` with 12 regression tests across 3 curated playlists (high-energy electronic / mellow jazz / genre-diverse). Locks in exact preset sequences, transition styles, and timing against the full 11-preset production catalog. Key decisions: `allBreakdowns` NOT added to `PlannedTrack` — runner-up inspection done via `DefaultPresetScorer().breakdown(preset:track:context:)` directly in test body, no new public API; `PlannedTransition` has no `trigger` enum field — structuralBoundary is verified by `reason.hasPrefix("Structural boundary")`; two spec derivation errors corrected against code (Plasma beats FO in high-energy sessions because tempCenter 0.6 is closer to targetTemp 0.78 than FO's 0.325). 399 tests total; 4 pre-existing Apple Music env failures unchanged.
- **Increment 4.3: SessionPlanner** — `DefaultSessionPlanner` composing `PresetScoring` + `TransitionDeciding` into a greedy forward-walk pre-session planner. Produces `PlannedSession` — ordered list of `PlannedTrack` entries each carrying score breakdown, transition decision, and timing. `planAsync` accepts a precompile closure (injected, keeps Orchestrator free of Renderer dependency). Synchronous `plan()` is deterministic: same inputs → byte-identical output. `PlannedSession.track(at:)` / `.transition(at:tolerance:)` for O(N) playback-time lookups. `PlanningWarning` surfaces degradation events (noEligiblePresets, forcedFamilyRepeat, budgetExceeded). `SessionPlanningError` covers emptyPlaylist, emptyCatalog, precompileFailed. 13 unit tests. D-034 in DECISIONS.md. 387 tests total; 4 pre-existing Apple Music env failures unchanged. **SessionManager integration deferred** — Session module cannot import Orchestrator (circular dependency); app-layer wiring is Increment 4.5.
- **Increment 4.2: TransitionPolicy** — `DefaultTransitionPolicy` implementing `TransitionDeciding` protocol. Structural boundary trigger (confidence ≥ 0.5, 2.5 s lookahead) takes priority over duration-expired timer fallback. `TransitionDecision` value type: trigger, scheduledAt, style, duration, confidence, rationale. Style negotiated from `transitionAffordances` + energy (cut preferred at energy > 0.7, crossfade otherwise). Crossfade duration scales linearly 2.0 s→0.5 s with energy. 12 unit tests. D-033 in DECISIONS.md. 374 tests total; 4 pre-existing Apple Music env failures unchanged.
- **Increment 4.1: PresetScorer** — `DefaultPresetScorer` implementing `PresetScoring` protocol. Four weighted sub-scores: mood (0.30), stemAffinity (0.25), sectionSuitability (0.25), tempoMotion (0.20). Two multiplicative penalties: family-repeat (0.2×) and fatigue smoothstep (60/120/300s cooldown by `FatigueRisk`). Hard exclusions gate perf-budget breakers and the currently-playing preset. `PresetScoreBreakdown` exposes all sub-scores for introspection. `PresetScoringContext` is a fully Sendable value snapshot using monotonic `elapsedSessionTime` — no `Date.now()` inside the scorer (guarantees determinism). `DeviceTier` enum added to Shared. `stemAffinity: [String: String]` added to `PresetDescriptor` (was in JSON sidecars, now decoded). 13 unit tests. D-032 in DECISIONS.md. 362 tests total; 5 pre-existing failures unchanged.
- **Increment 4.0: Enriched preset metadata schema** — `PresetMetadata.swift` with `FatigueRisk`, `TransitionAffordance`, `SongSection`, `ComplexityCost`. `PresetDescriptor` extended with 7 new Orchestrator-facing fields (`visual_density`, `motion_intensity`, `color_temperature_range`, `fatigue_risk`, `transition_affordances`, `section_suitability`, `complexity_cost`), all optional in JSON with fallback-on-missing / warn-on-malformed decoding. All 11 built-in preset JSON sidecars back-filled. 6 new `PresetDescriptorMetadataTests`. D-029 in DECISIONS.md. (Pulled forward from Phase 5.1.)
- **SwiftLint L-1 structural cleanup** — Pure mechanical refactor: zero logic changes, zero new public API. Reduced from 24 → 0 violations by extracting overlong functions and splitting oversized files into extension files. New files: `StemAnalyzer+RichMetadata.swift`, `MIRPipeline+Recording.swift`, `AudioInputRouter+SignalState.swift`, `RayMarchPipeline+PipelineStates.swift`, `RenderPipeline+FeedbackDraw.swift`, `RenderPipeline+PresetSwitching.swift`, `PresetLoader+WarpPreamble.swift`, `VisualizerEngine+Capture.swift`, `VisualizerEngine+InitHelpers.swift`, `VisualizerEngine+PublicAPI.swift`. All helpers private/internal only. 349 tests pass (4 pre-existing Apple Music environment failures unchanged).
- **SwiftLint L-0 cleanup** — Auto-corrected comma/colon/operator spacing; fixed identifier names (single-letter variable renames); fixed 2 force-unwrap violations; fixed orphaned doc comment; targeted `disable/enable` around the CSV row-writing block in `SessionRecorder`; fixed multiline-arguments in `StemAnalyzer`, `InputLevelMonitor`, `VisualizerEngine+Audio`. Reduced from 166 → 24 violations (structural file/function-length refactors deferred to a dedicated increment).
- **D-030: SpectralHistoryBuffer + SpectralCartograph** — 16 KB UMA ring buffer at buffer(5) carrying 5×480 sample trails (valence, arousal, beat_phase01, bass_dev, vocals_pitch_norm). `SpectralCartograph` preset: first `instrument`-family four-panel MIR diagnostic. `PresetCategory.instrument` added. CLAUDE.md GPU Contract corrected (buffer(0)=FeatureVector, buffer(5)=SpectralHistory). 15+ new tests.
- **BeatPredictor timing fix** — `beatPhase01` was always 0 in production because `MIRPipeline.processAnalysisFrame` passes `time: 0` to every `BeatPredictor.update()` call; `lastBeatTime > 0` guard silently rejected the first onset, so `hasPeriod` never became true. Fixed by internal `elapsedTime` accumulation from `deltaTime`, independent of the `time` parameter. Guards changed from `> 0` to `>= 0`.
- **InputLevelMonitor** — continuous tap-quality assessment (peak dBFS + spectral balance → green/yellow/red grade). Peak-only classification after session 2026-04-17 revealed treble-ratio thresholds produced false positives on bass-heavy tracks. Logs quality transitions to session.log; shown in debug overlay.
- **MV-3: Beyond-Milkdrop extensions** — `StemFeatures` expanded 32→64 floats (128→256 bytes, D-028). Three sub-increments: (a) per-stem rich metadata `{onsetRate, centroid, attackRatio, energySlope}` computed in `StemAnalyzer.computeRichFeatures()` via RMS EMAs (τ=50ms/500ms), spectral centroid, leaky-integrator onset rate; (b) `BeatPredictor` class (IIR period from onset rising edges) → `FeatureVector.beatPhase01/beatsUntilNext` for anticipatory pre-beat animation; (c) `PitchTracker` (YIN via vDSP_dotpr, key fix: advance to CMNDF local minimum before parabolic interpolation) → `StemFeatures.vocalsPitchHz/Confidence`. Metal preamble and Swift structs updated byte-for-byte. `VolumetricLithograph.metal` uses `beat_phase01` for anticipatory zoom ramp (`approachFrac * 0.004`) and `vl_pitchHueShift()` for pitch→hue mapping. 9 new unit tests across `StemAnalyzerMV3Tests`, `BeatPredictorTests`, `PitchTrackerTests`. (D-028)
- **MV-1: Milkdrop-correct deviation primitives** — `FeatureVector` expanded 32→48 floats (128→192 bytes), `StemFeatures` expanded 16→32 floats (64→128 bytes). Nine new FV deviation fields (`bassRel/Dev`, `midRel/Dev`, `trebRel/Dev`, `bassAttRel`, `midAttRel`, `trebAttRel`) derived in `MIRPipeline.buildFeatureVector()` as `xRel = (x - 0.5) * 2.0`, `xDev = max(0, xRel)`. Eight new StemFeatures deviation fields (`{vocals,drums,bass,other}EnergyRel/Dev`) derived in `StemAnalyzer.analyze()` via per-stem EMA (decay 0.995). Metal preamble structs in `PresetLoader+Preamble.swift` updated to match. `VolumetricLithograph.metal` updated as reference implementation: all four FeatureVector fallback drivers converted from absolute-threshold to deviation form. `RelDevTests.swift` (4 contract tests) gates the invariants. (D-026)
- **Increment 3.5.7: Stalker preset** — Third and final preset in the Arachnid Trilogy. Bioluminescent spider silhouette traverses a dim static background web. Articulated 8-leg alternating-tetrapod gait phase-locks to BPM via soft pull (no snap). Phosphene-exclusive: sustained low-attack-ratio bass (bassAttackRatio < 0.55 held ≥ 0.75s) triggers the listening pose (front legs raised, gait frozen) while transient kick-drum bass does not — distinguishes vibration character that Milkdrop's vocabulary cannot. `StalkerGait.swift` (pure gait solver with 2-segment IK, listening blend, beat easing). `StalkerState.swift` (scene mode state machine + sustained-bass accumulator + GPU buffer flush, 352 bytes). `Stalker.metal`: 2-threadgroup dispatch (web + spider). `StalkerGPU` struct at object/mesh buffer(1). D-026/D-019 compliant. 16 unit tests (8 gait + 8 state) in `StalkerGaitTests.swift` / `StalkerStateTests.swift`. Arachnid Trilogy complete: Arachne (mesh construction), Gossamer (mv_warp silk resonance), Stalker (mesh predator). Orchestrator family-repeat penalty naturally prevents two trilogy presets appearing consecutively. 455 tests total; 4 pre-existing Apple Music environment failures unchanged.
- **Increment 3.5.6: Gossamer preset** — Bioluminescent hero-web as sonic resonator. Single SDF-drawn static web (12 radials + Archimedean capture spiral) with up to 32 vocal-pitch-keyed propagating color waves. Emission gates on `vocalsPitchConfidence > 0.35 OR |vocalsEnergyDev| > 0.05`. Wave hue baked from YIN pitch at emission, saturation from other-stem density, amplitude from vocals_energy_dev. mv_warp pass accumulates decaying echoes (decay=0.955). Ambient drift floor guarantees ≥2 waves at silence. Fragment buffer(6) binding via `pipeline.setDirectPresetFragmentBuffer` / `directPresetFragmentBuffer`. `GossamerState.swift` owns a 32-entry pool + 528-byte GossamerGPU MTLBuffer. 8 unit tests in `GossamerStateTests.swift`. 435 tests total; 4 pre-existing Apple Music environment failures unchanged.
- **Increment 3.5.5: Arachne preset** — Bioluminescent spider web mesh shader. `ArachneState.swift` manages 12-web pool with beat-measured stage lifecycle (anchorPulse→radial→spiral→stable→evicting), drum-driven spawn accumulator, LCG PRNG, `MTLBuffer` GPU flush. `Arachne.metal`: object shader dispatches 12 mesh threadgroups; 64-thread mesh shader emits hub cap + anchor dots + radial spokes + spiral segments per web; fragment applies D-019 warmup, bass quiver, MV-3b beat anticipation. Organic family (`PresetCategory.organic` added, D-038). Quiver wave phase-locked to beat_phase01; exp2(-dist*3) bioluminescent glow falloff; sat=0.92. 8 unit tests in `ArachneStateTests.swift`. `PresetCategory.allCases.count` updated to 14. 427 tests total; 4 pre-existing Apple Music environment failures unchanged.
- **Increment 5.2: Preset Acceptance Checklist** — `PresetAcceptanceTests.swift`: 4 parametrized invariant tests over all 11 production presets (44 test cases). Fixtures: silence (all zero), steady mid-energy (all bands at 0.5), beat-heavy (bass=0.80, bassRel=0.60, beatBass=1.0, from Love Rehab 125 BPM reference), quiet passage (all bands at 0.15, bassRel=−0.70, from Miles Davis sparse sections). Invariants: non-black at silence; no white clip on non-HDR paths; beat response ≤ 2× continuous + 1.0; form complexity ≥ 2. Module-level `_acceptanceFixture` loads presets once; returns [] (zero test cases) if bundle resources absent. D-037 in DECISIONS.md. 419 tests total (Swift Testing counts @Test functions, not parametrized cases); 4 pre-existing Apple Music environment failures unchanged.
- **Increment 4.6: Ad-Hoc Reactive Mode** — `DefaultReactiveOrchestrator` (stateless pure function): `ReactiveAccumulationState` (listening/ramping/full), `ReactiveDecision`, `ReactiveOrchestrating` protocol. Confidence ramps 0→0.3 over 0–15 s, 0.3→1.0 over 15–30 s, 1.0 after 30 s. Switch conditions: score gap > 0.20 or boundary confidence ≥ 0.5. `VisualizerEngine+Orchestrator` routes to `applyReactiveUpdate()` when `livePlan == nil`; 60 s cooldown prevents switch-thrashing; `buildPlan()` clears `reactiveSessionStart` when a real plan arrives. 8 unit tests. D-036 in DECISIONS.md. 415 tests total; 4 pre-existing Apple Music environment failures unchanged.
- **Swift 6 concurrency cleanup** — `@MainActor` on `draw(in:)` and all render-path helpers (`renderFrame`, `drawDirect`, `drawWithFeedback`, `drawWithRayMarch`, etc.) that access `MTKView.currentDrawable`/`currentRenderPassDescriptor`/`drawableSize`. Xcode IDE warnings resolved; xcodebuild already clean via `@preconcurrency import MetalKit`.

The next ordered increments are:

1. **Increment U.6b — Live adaptation semantics.** Wire `moreLikeThis()`, `lessLikeThis()`, `reshuffleUpcoming()`, `presetNudge()`, `rePlanSession()`, `undoLastAdaptation()` in `DefaultPlaybackActionRouter` (all currently stub-logged). See `docs/ENGINEERING_PLAN.md §U.6b`.
2. **Increment 6.1 — Progressive Session Readiness.** Gates the "Start now" CTA in `PreparationProgressView` (dormant in U.4 via `FeatureFlags.progressiveReadiness = false`). See `docs/ENGINEERING_PLAN.md §Phase 6`.
3. **Increment V.2 — Shader utility library: Geometry + Volume + Texture.** Follows V.1 (Noise + PBR already complete). See `docs/ENGINEERING_PLAN.md §Phase V`.

See `docs/ENGINEERING_PLAN.md` for the full forward plan with done-when criteria and verification commands. See `docs/MILKDROP_ARCHITECTURE.md` for the research that scopes Phase MV and now also gates Phase MD (Milkdrop ingestion). See `docs/UX_SPEC.md` for the product-UX source of truth and `docs/SHADER_CRAFT.md` for the shader authoring handbook.

## Linked Frameworks

Metal, MetalKit, MetalPerformanceShadersGraph, AVFoundation, Accelerate, ScreenCaptureKit (Info.plist only), MusicKit.

## Development Constraints

- **Team**: Matt (product/design direction) + Claude Code (implementation).
- **Platform**: macOS only. Mac mini primary dev/deploy target.
- **Performance target**: 60fps at 1080p on Apple Silicon.
- **Dependencies**: Minimize external. Prefer Apple frameworks.
- **Learning stays local**: On-device only. No cloud, no telemetry.
- **License**: MIT.
