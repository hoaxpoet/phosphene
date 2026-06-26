// RenderPipeline — MTKViewDelegate that drives the audio-reactive render loop.
// Supports both direct rendering and Milkdrop-style feedback (double-buffered ping-pong).
// Binds FFT magnitude and PCM waveform UMA buffers to a full-screen fragment shader.
// swiftlint:disable file_length

import Metal
@preconcurrency import MetalKit
import Shared
import os.log

private let logger = Logger(subsystem: "com.phosphene.renderer", category: "RenderPipeline")

public final class RenderPipeline: NSObject, Rendering, @unchecked Sendable {

    // MARK: - Metal State

    let context: MetalContext
    var pipelineState: MTLRenderPipelineState
    let pipelineLock = NSLock()

    // MARK: - Audio Buffers (UMA zero-copy — written by audio thread, read by GPU)

    let fftMagnitudeBuffer: MTLBuffer   // 512 floats from FFTProcessor
    let waveformBuffer: MTLBuffer       // 2048 interleaved floats from AudioBuffer

    // MARK: - Particle System

    /// Optional particle geometry — compute update + point-sprite rendering.
    /// Typed as `any ParticleGeometry` so per-preset conformers (Murmuration's
    /// `ProceduralGeometry`, future siblings) can attach via `setParticleGeometry`. D-097.
    var particleGeometry: (any ParticleGeometry)?
    let particleLock = NSLock()

    // MARK: - Scene Geometry Overlay (Dragon Bloom strands, D-137)

    /// Optional additive geometry drawn into the mv_warp scene texture AFTER the
    /// fullscreen background fragment (the 3 Dragon Bloom spectral strands). The
    /// pipeline's blend is additive; the draw binds FeatureVector(0) + StemFeatures(1)
    /// so the strand vertex shader can compute the per-point math from time + stems.
    /// nil = no overlay (every other direct/mv_warp preset). Set via `setSceneGeometry`.
    let sceneGeometryLock = NSLock()
    var sceneGeometryState: MTLRenderPipelineState?
    var sceneGeometryVertexCount = 0
    var sceneGeometryInstanceCount = 0
    var sceneGeometryPrimitive: MTLPrimitiveType = .lineStrip

    /// mv_warp chromatic colour-separation amount (Dragon Bloom L3, D-137), bound
    /// to `mvWarp_fragment` at fragment buffer 0. 0 ⇒ identity (every other mv_warp
    /// preset unchanged). Set via `setMVWarpChromatic`.
    var mvWarpChromatic: Float = 0

    /// mv_warp per-frame WETNESS-channel decay multiplier (Skein.ENGINE.2), bound to the
    /// warp/hold fragment at fragment buffer 1. Skein's canvas-hold carries a transient
    /// "wetness" signal in the feedback texture's ALPHA channel (RGB stays the lossless
    /// permanent paint record); the warp fragment decays A by this factor each frame while
    /// holding RGB byte-identically. `1.0` ⇒ A held unchanged. Only Skein's own
    /// `skein_warp_fragment` reads buffer 1 — every other mv_warp preset uses the shared
    /// `mvWarp_fragment` (which does not declare buffer 1), so the binding is ignored and
    /// they are byte-identical regardless of this value. Driven per-frame from `SkeinState`
    /// (decay pauses at silence — the §5.2 step-3 accumulated-audio-time semantics). Set via
    /// `setMVWarpWetnessDecay`.
    var mvWarpWetnessDecay: Float = 1.0

    /// Skein.5.3b: a per-TRACK canvas-ground override (LINEAR rgba) for canvas-hold presets
    /// whose ground travels with the palette (the Skein palette library — light AND dark
    /// grounds). `nil` (every other preset, and Skein before its state exists) ⇒ the
    /// preset-static `canvasClearColor` from the `marks` descriptor — byte-identical for all
    /// non-consumers. Consulted by `setupMVWarp`'s fresh-texture clear (incl. the resize
    /// re-clear path) and `clearMVWarpCanvasToGround` (the §1.5 track-change wipe). Reset to
    /// `nil` at preset teardown beside the wetness/structure resets. Set via
    /// `setMVWarpCanvasGround`.
    var mvWarpCanvasGroundOverride: SIMD4<Double>?

    /// mv_warp display-stage post params (Dragon Bloom L4, D-137), bound to
    /// `mvWarp_blit_fragment` at fragment buffer 0. `x` = invert amount
    /// (source.milk `bInvert=1` — flips the cool full-warp fill to warm), `y` =
    /// brighten amount (`bBrighten=1`). These are DISPLAY-only (the blit output
    /// is presented, never swapped back into the feedback loop), matching
    /// Milkdrop's fixed-function comp semantics — applied to the float feedback on
    /// the way to the drawable, never fed back. `x` = invert (`bInvert`), `y` =
    /// video-echo alpha (`fVideoEchoAlpha`, orientation-1 horizontal mirror), `z` =
    /// gamma multiply (`fGammaAdj`). `(0, 0, 1)` ⇒ identity blit (every other
    /// mv_warp preset byte-for-byte unchanged). Set via `setMVWarpPost`.
    var mvWarpInvert: Float = 0
    var mvWarpEcho: Float = 0
    var mvWarpGamma: Float = 1
    /// Smoothed beat-pulse envelope (Dragon Bloom comp pump, D-137). Sharp attack on
    /// a beat, smooth decay between — so each beat reads as a pump-and-settle, not a
    /// per-frame flicker. Updated on the render loop (MainActor); display-only.
    var mvWarpBeatEnv: Float = 0
    /// Whether the comp beat pump fires (Skein.ENGINE.1.1, D-143). Formerly keyed on
    /// `sceneGeometryState != nil` (so any marks-on-top preset inherited Dragon Bloom's
    /// pump); now a per-preset flag from the `marks` descriptor block. true only for
    /// Dragon Bloom (the only `strandsOnTop` preset today ⇒ byte-identical); false for a
    /// quiet held canvas (Skein) so it gets true comp-identity. Set via `setMVWarpPost`.
    var mvWarpBeatPulseEnabled: Bool = false

    /// Fata Morgana frame_eqs beat-rotation accumulator (D-139), faithful to the
    /// source: `is_beat` from max(bass,mid,treb) vs a slow average + decaying peak;
    /// `rott = π·p2/4` smooths a per-beat index step into the warp lattice's q1/q2
    /// (cos/sin). MainActor-only (the mv_warp draw path), no lock — same convention
    /// as `auroraDrumsSmoothed`.
    var fataAvg: Float = 0
    var fataPeak: Float = 0
    var fataT0: Float = 0
    var fataP1: Float = 0
    var fataP2: Float = 0
    var fataIndex: Int = 0
    /// Fata Morgana frame counter (FM.L2): drives the shapes' colour cycle and
    /// shape-0 rotation (butterchurn's `frame`). Incremented per fata draw.
    var fataFrame: Int = 0
    /// Fata Morgana custom-shape pipelines (FM.L2), set from the app at preset switch
    /// via `setFataShapePipelines`. nil for every other preset. Drawn on top of the
    /// warp target in `drawWithFataMorgana`.
    var fataShapeAdditive: MTLRenderPipelineState?
    var fataShapeNormal: MTLRenderPipelineState?
    /// Master size gain on the stem-driven Fata blob radius (FM.L2, D-139). The shapes
    /// are driven by the D-026 `_energy_rel` primitive (~1.0-centred, the faithful analog
    /// of Milkdrop's `_att`), so rad ≈ baseRad at average level — matching the source's
    /// `baseVal.rad × _att`. 1.5 gives a touch more presence on Phosphene's wider 16:9
    /// canvas vs the oracle's 4:3. (The earlier 5.0 compensated for the wrong 0.5-centred
    /// AGC `_energy` drive, which oversized the blobs into the gray-wash.) Diag sweeps it
    /// via FATA_BOOST.
    var fataShapeSizeGain: Float = 1.5
    /// Diagnostic term-isolation selector (FM.L2), passed to the fata comp via the
    /// unused gammaAdj channel. 0 = normal. The diag sets it from FATA_DEBUG to isolate
    /// the field / glow / stars and locate the gray-wash. (Kept as diagnostic infra.)
    var fataDebugMode: Float = 0
    /// Per-session phase jitter (seconds) added to the horizon-glow clock so every
    /// session opens at a DIFFERENT point in the slow_roam_sin spectrum cycle instead
    /// of all starting at the same hue (Matt: "horizon color different on startup").
    /// Re-rolled once per Fata activation in `setFataShapePipelines`. butterchurn itself
    /// has no such jitter (its glow is pure session-time, so every load starts the same)
    /// — this is a deliberate, Matt-requested divergence. The diag pins it (default 0,
    /// or FATA_GLOW_JITTER) for reproducibility. See `computeFataUniforms` / kFataGlowSeed.
    var fataGlowSeedJitter: Float = 0
    /// Coordinated-sway bar clock (FM.L2). Advances +1 per musical bar (accumulates
    /// `barPhase01` deltas, handling the downbeat wrap). The shapes sway horizontally by
    /// `cos(π·swayClock)` — a 2-bar period that turns around on every downbeat, so the
    /// few spectra sweep back and forth over the water in time with the bars (Matt's
    /// vision). Frozen when no bar grid is present (barPhase01 static) → shapes hold.
    /// MainActor-only (the mv_warp draw path).
    var fataSwayClock: Float = 0
    var fataPrevBarPhase: Float = 0

    /// Nacre (NACRE.3): hue ← harmony. `nacreCentroidNorm` is a slow EMA of the spectral
    /// centroid (the section's brightness baseline, ~5 s); the palette-phase nudge tracks
    /// the centroid's DEVIATION from it (track-robust — responds to harmonic/timbral shifts,
    /// not absolute level). `nacreHueEMA` is the calm-smoothed output (the `hueShift` bound).
    /// MainActor-only (the mv_warp draw path), no lock — same convention as the fata accumulators.
    var nacreCentroidNorm: Float = 0
    var nacreHueEMA: Float = 0
    /// Nacre (NACRE.3): `nacreSeedEMA` is the SLOW (~0.5 s) total-energy envelope driving the
    /// WARP's core SEED, kept near-steady so the fed-back seed never flares into smears.
    /// `nacreSpinEMA`: smoothed stem-fullness (avg of the four stem energies, ~0.5 s) → the
    /// warp's energy-driven TURNING (`nu.spin`): the molten field swirls faster as the music
    /// fills out, slower when sparse (the motion connection). The band average is blind to
    /// full-band entries — energy is in the stems (Matt M7). [The DISPLAY-stage voice-glow
    /// envelope `nacreCoreEMA` was removed — Matt M7: blinding on the vocal peaks, no read.]
    /// (`floretSwellEMA`: Floret ~0.5 s avg-stem envelope → warp-seed bloom inflation;
    /// `floretSpin`: Floret accumulated rotation angle (rad) → the comp's bass-driven spin —
    /// FLORET.3a; folded onto this line to stay under the type_body_length cap, see FLORET_PLAN §12.)
    var nacreSeedEMA: Float = 0, nacreSpinEMA: Float = 0, floretSwellEMA: Float = 0, floretSpin: Float = 0

    // MARK: - Live Audio Features

    /// Latest audio features from MIR analysis (band energy, beats, spectral).
    /// Set from the analysis queue, read in the render loop.
    var latestFeatures = FeatureVector.zero
    let featuresLock = NSLock()

    // MARK: - Live Structural-Section Signal (Skein.ENGINE.3, D-151)

    /// Latest live structural-section prediction from the MIR `StructuralAnalyzer`
    /// (`{ sectionIndex, sectionStartTime, predictedNextBoundary, confidence }`).
    ///
    /// CPU-only — NOT part of the GPU `FeatureVector`/`Common.metal` contract (no D-099
    /// migration). Rides the same lock-guarded analysis→render value-injection bridge as
    /// `setMood`/`latestFeatures` (D-024 / FA #25), but as a **separate** store: structure is
    /// not a `FeatureVector` field, so it is never clobbered by `setFeatures`. Written from the
    /// analysis queue (`setStructuralPrediction`, alongside the per-frame MIR features publish);
    /// read on the render thread by the Skein mesh-preset tick closure. Defaults to `.none`, and
    /// **only `SkeinState` consumes it** — every other preset's tick ignores it, so this store is
    /// inert for them (the byte-identical guarantee). See `setStructuralPrediction`.
    ///
    /// Internal (not `private`) so the `setStructuralPrediction` setter in the
    /// `RenderPipeline+PresetSwitching` extension can write it — exactly as `latestFeatures` is
    /// internal so `setMood` can, and `currentDrawableSize` backs `mvWarpDrawableSize`. Always
    /// access under `structuralPredictionLock` (read via the `latestStructuralPrediction` getter).
    var storedStructuralPrediction: StructuralPrediction = .none
    let structuralPredictionLock = NSLock()

    /// The latest live structural-section prediction (lock-guarded read). `.none` until the
    /// analysis queue first publishes one (and after a track-change / preset-switch reset). Read by
    /// the Skein tick closure on the render thread — the analysis thread writes it via
    /// `setStructuralPrediction`, exactly the `setMood` cross-thread situation. (Skein.ENGINE.3)
    public var latestStructuralPrediction: StructuralPrediction {
        structuralPredictionLock.withLock { storedStructuralPrediction }
    }

    // MARK: - Session Recording Hook

    /// Per-frame capture hook for SessionRecorder. Invoked after `renderFrame`,
    /// before commit. Nil = zero overhead.
    public var onFrameRendered: ((_ drawableTexture: MTLTexture,
                                  _ features: FeatureVector,
                                  _ stems: StemFeatures,
                                  _ commandBuffer: MTLCommandBuffer) -> Void)?

    // MARK: - Per-Stem Features

    /// Latest per-stem features from the background stem pipeline.
    /// Set from the stem queue (~5s cadence), read every frame in the render loop.
    var latestStemFeatures = StemFeatures.zero
    let stemFeaturesLock = NSLock()

    /// 150 ms τ EMA of `StemFeatures.drumsEnergyDev`, updated by
    /// `drawWithRayMarch` and patched into the stems snapshot bound at fragment
    /// buffer(3). Drives the Ferrofluid Ocean aurora curtain intensity envelope
    /// (V.9 Session 4.5c / D-127). Accessed only from the `@MainActor` ray-march
    /// draw path — no lock required.
    var auroraDrumsSmoothed: Float = 0

    /// BUG-041 — per-track warmup gate on the aurora's drums driver, 0 → 1
    /// over `RenderPipeline.auroraWarmupSeconds` after each track change.
    /// The per-stem deviation EMA re-seeds when `StemAnalyzer` resets per
    /// track and overswings 1.2–3.3× for the first ~10 s (measured, session
    /// `2026-06-10T14-55-32Z`) — without this gate the aurora flashes at
    /// exactly the track starts Matt flagged. Reset to 0 alongside
    /// `resetAccumulatedAudioTime()` (the existing track-change hook).
    /// Accessed only from the ray-march draw path, like `auroraDrumsSmoothed`.
    var auroraTrackWarmup01: Float = 1.0

    /// FBS.S5 (D-158) — smoothed aurora palette phase (τ ≈ 3 s EMA over the
    /// composite pitch/valence hue target), patched into the stems snapshot at
    /// `StemFeatures.auroraPalettePhase`. Replaces the shader's per-pixel raw
    /// pitch-field read, which strobed the reflected sky when pitch confidence
    /// flapped across its gate (~9×/s measured on session
    /// 2026-06-10T19-13-14Z). Not reset per track — hue continuity across
    /// track changes is free of steps by construction. Accessed only from the
    /// ray-march draw path, like `auroraDrumsSmoothed`.
    var auroraHuePhase: Float = 0

    /// FBS Stage 2 — passage-loudness envelope (symmetric τ 2.5 s EMA over
    /// the total stem energy, `punchEnergyStep`) that scales the FFO
    /// beat-punch height. Patched into the stems snapshot at
    /// `StemFeatures.totalEnergySmoothed`. Not reset per track: the EMA
    /// adapts across a track change on the same ~2.5 s scale as the punch
    /// becoming audible (anchor + amp ramp), so a loud→quiet segue eases
    /// rather than pops. Accessed only from the ray-march draw path, like
    /// `auroraDrumsSmoothed`.
    var punchEnergySmoothed: Float = 0

    /// BUG-047 — aurora curtain orbit azimuth (radians), integrated per
    /// frame by `auroraOrbitStep` (arousal scales the SPEED of each
    /// increment, never rescaling history). Shipped via
    /// `StemFeatures.auroraOrbitAzimuth`. `lastAuroraAat` tracks the
    /// previous frame's `accumulatedAudioTime` to form the increment;
    /// a track-change reset (aat going backwards) advances nothing.
    /// Ray-march draw path only, like the other aurora drivers.
    var auroraOrbitAzimuth: Float = 0
    var lastAuroraAat: Float?

    // MARK: - Feedback Textures (Milkdrop-style ping-pong)

    /// Double-buffered feedback textures. Index flips each frame.
    var feedbackTextures: [MTLTexture] = []
    /// Which texture is the current write target (0 or 1).
    var feedbackIndex: Int = 0
    /// Current feedback parameters (from preset descriptor).
    var currentFeedbackParams: FeedbackParams?
    /// Additive-blended pipeline for the feedback composite pass.
    var feedbackComposePipelineState: MTLRenderPipelineState?
    let feedbackLock = NSLock()

    /// Built-in pipeline states for feedback warp and blit passes.
    let feedbackWarpPipelineState: MTLRenderPipelineState
    let feedbackBlitPipelineState: MTLRenderPipelineState
    /// Bilinear, clamp-to-edge sampler for feedback texture reads.
    let feedbackSamplerState: MTLSamplerState

    /// True when the active preset actually samples the feedback ping-pong, i.e.
    /// surface-mode feedback (Membrane: warp → composite → blit). Particle-mode
    /// feedback presets (Murmuration) draw straight to the drawable and never sample
    /// the ping-pong, and non-feedback presets have no params — both are false.
    /// Gates ping-pong allocation + the warp/compose passes (CLEAN.4.4). Thread-safe.
    var activePresetSamplesFeedback: Bool {
        let hasParams = feedbackLock.withLock { currentFeedbackParams != nil }
        let hasParticles = particleLock.withLock { particleGeometry != nil }
        return hasParams && !hasParticles
    }

    // MARK: - Mesh Shader State

    /// Optional mesh generator — attached when the active preset has `useMeshShader: true`.
    var meshGenerator: MeshGenerator?
    let meshLock = NSLock()

    /// Optional per-frame tick closure for mesh preset state (e.g. ArachneState.tick).
    /// Called once per frame in renderFrame before the draw pass.
    var meshPresetTick: (@Sendable (FeatureVector, StemFeatures) -> Void)?
    let meshPresetTickLock = NSLock()

    // MARK: - Post-Process Chain

    /// Optional HDR post-process chain — bloom + ACES tone mapping.
    var postProcessChain: PostProcessChain?
    let postProcessLock = NSLock()

    // MARK: - ICB State (Increment 3.5)

    /// Optional ICB state for GPU-driven indirect command buffer rendering.
    var icbState: IndirectCommandBufferState?
    let icbLock = NSLock()

    // MARK: - Ray March Pipeline (Increment 3.14)

    /// Optional deferred ray march pipeline — G-buffer + PBR lighting + composite.
    var rayMarchPipeline: RayMarchPipeline?
    let rayMarchLock = NSLock()

    // MARK: - MV-Warp State (MV-2, D-027)

    /// Optional per-vertex feedback warp state — allocated when the active preset
    /// declares `.mvWarp` in its passes array.
    var mvWarpState: MVWarpState?
    /// Decay for the mv_warp compose pass — mirrors preset descriptor `pf.decay`.
    var mvWarpDecay: Float = 0.96
    /// Last drawable size reported by `mtkView(_:drawableSizeWillChange:)`.
    /// Used by `setupMVWarp` so mid-session preset switches allocate at the real size.
    var currentDrawableSize: CGSize = CGSize(width: 1920, height: 1080)

    /// Public accessor for the last known drawable size (guarded by mvWarpLock).
    public var mvWarpDrawableSize: CGSize {
        mvWarpLock.withLock { currentDrawableSize }
    }
    let mvWarpLock = NSLock()

    // MARK: - Direct-preset half-res render path (NB.8)

    /// Render scale for the direct-fragment path: 1.0 = full drawable resolution
    /// (default), < 1.0 = render the preset fragment to an offscreen texture at
    /// `scale × drawable` then bilinearly upscale to the drawable. Used by heavy
    /// volumetric presets (Nimbus) whose march cost scales with on-screen pixel
    /// count — at full energy Nimbus's body swells to fill the frame and the
    /// full-res march exceeds the 7 ms Tier-2 ceiling; a 0.5× march is ~4×
    /// cheaper and the soft gas tolerates the upscale. Set per-preset in
    /// `applyPreset`; reset to 1.0 on every preset change.
    private var _directRenderScale: Float = 1.0
    private let directRenderScaleLock = NSLock()

    /// Set the direct-preset render scale (1.0 = full res; e.g. 0.5 = half-res
    /// march + upscale). Reset to 1.0 on preset change.
    ///
    /// Called from `applyPreset` on the MainActor — the same actor the render
    /// loop (`draw(in:)` → `drawDirect`) runs on, so the eager pre-allocation
    /// below cannot race the render thread's `halfResTarget`.
    public func setDirectRenderScale(_ scale: Float) {
        directRenderScaleLock.withLock { _directRenderScale = scale }
        // NB.8 polish: pre-allocate the half-res target NOW (at preset apply)
        // rather than lazily on the first rendered frame — that lazy allocation
        // was part of the ~one-frame startup hitch (~25 ms) the instant the
        // preset switched in (NB.8 live session). `drawDirect`'s lazy realloc
        // still covers later drawable resizes.
        if scale < 0.999 {
            let size = mvWarpDrawableSize
            _ = halfResTarget(drawableWidth: max(Int(size.width), 1),
                              drawableHeight: max(Int(size.height), 1),
                              scale: scale)
        }
    }

    var directRenderScale: Float {
        directRenderScaleLock.withLock { _directRenderScale }
    }

    /// Cached offscreen target for the half-res direct path; (re)allocated lazily
    /// in `drawDirect` when the scale or drawable size changes. Render-thread only.
    var halfResTexture: MTLTexture?
    var halfResTextureSize: (width: Int, height: Int) = (0, 0)

    // MARK: - Noise Textures (Increment 3.13)

    /// Optional noise texture manager — binds 5 pre-computed textures at slots 4–8.
    var textureManager: TextureManager?
    let textureManagerLock = NSLock()

    // MARK: - Spectral History (buffer(5))

    /// Per-frame MIR history ring buffer — bound at fragment buffer(5). Updated each frame.
    public let spectralHistory: SpectralHistoryBuffer

    // MARK: - Direct Preset Fragment Buffer (buffer(6))

    /// Per-preset fragment buffer at index 6 for direct mv_warp presets (e.g. Gossamer).
    /// Set via `setDirectPresetFragmentBuffer`; `nil` when no active preset uses it.
    var directPresetFragmentBuffer: MTLBuffer?
    let directPresetFragmentBufferLock = NSLock()

    // MARK: - Direct Preset Fragment Buffer 2 (buffer(7))

    /// Secondary per-preset fragment buffer at index 7 for direct mv_warp presets (e.g. Arachne).
    /// Second CPU-side state buffer; web pool at buffer(6), spider GPU at buffer(7).
    var directPresetFragmentBuffer2: MTLBuffer?
    let directPresetFragmentBuffer2Lock = NSLock()

    // MARK: - Direct Preset Fragment Buffer 3 (buffer(8))

    /// Tertiary per-preset fragment buffer at index 8. Reserved for future
    /// preset-uniform CPU-driven state. Currently unused; first planned consumer
    /// is Lumen Mosaic (Phase LM) for `LumenPatternState`. Slot is shared — any
    /// future preset that needs a third per-frame state buffer binds here. See
    /// CLAUDE.md GPU Contract for the slot 6 / 7 / 8 reservation list. (D-LM-buffer-slot-8)
    var directPresetFragmentBuffer3: MTLBuffer?
    let directPresetFragmentBuffer3Lock = NSLock()

    // MARK: - Ray-March Preset Height Texture (texture(10))

    /// Per-preset baked height field for ray-march presets. Bound at fragment
    /// texture slot 10 of the ray-march G-buffer pass — non-Ferrofluid presets
    /// receive the zero-filled 1×1 `RayMarchPipeline.ferrofluidHeightPlaceholderTexture`
    /// so the slot-10 declaration is always satisfied. First consumer:
    /// Ferrofluid Ocean V.9 (`FerrofluidParticles.heightTexture`, per V.9
    /// Session 4.5b Phase 1).
    var rayMarchPresetHeightTexture: MTLTexture?
    let rayMarchPresetHeightTextureLock = NSLock()

    // MARK: - Dynamic Text Overlay (texture 12)

    /// Per-frame CPU text rasterization for text-overlay presets (e.g. SpectralCartograph).
    /// Bound at fragment texture(12). Created/destroyed by `setDynamicTextOverlay(_:)`.
    var dynamicTextOverlay: DynamicTextOverlay?
    let dynamicTextOverlayLock = NSLock()

    /// Per-frame callback invoked in `refresh()` to populate the text overlay.
    /// Set by the app layer when a text-overlay preset is active.
    /// The callback receives the overlay and the current frame's FeatureVector.
    var textOverlayCallback: ((DynamicTextOverlay, FeatureVector) -> Void)?
    let textOverlayCallbackLock = NSLock()

    // MARK: - IBL Textures (Increment 3.16)

    /// Optional IBL texture manager — binds irradiance, prefiltered env, and BRDF LUT at slots 9–11.
    var iblManager: IBLManager?
    let iblManagerLock = NSLock()

    // MARK: - Render Graph (Increment 3.6)

    /// Active render passes declared by the current preset.
    ///
    /// `renderFrame` iterates this array and dispatches to the first pass whose
    /// required subsystem is available, replacing the old priority-ordered boolean
    /// flag chain.  Set atomically via `setActivePasses(_:)`.
    var activePasses: [RenderPass] = [.direct]
    let passesLock = NSLock()

    // MARK: - Staged Composition (V.ENGINE.1)

    /// Active staged stages + per-stage offscreen textures. See RenderPipeline+Staged.
    var stagedStages: [StagedStageSpec] = []
    var stagedTextures: [String: MTLTexture] = [:]
    let stagedLock = NSLock()

    // MARK: - Accessibility Flags (U.9, D-054)

    /// Beat-pulse amplitude scale. `1.0` normal; `0.5` reduced-motion. See D-054.
    public var beatAmplitudeScale: Float = 1.0
    /// When true, mv_warp and SSGI passes are suppressed. See D-054.
    public var frameReduceMotion: Bool = false

    // MARK: - Accumulated Audio Time (Increment 3.15)

    /// Energy-weighted running time — accumulates faster during loud passages.
    /// Reset to 0 on track change via `resetAccumulatedAudioTime()`.
    private var _accumulatedAudioTime: Float = 0
    let audioTimeLock = NSLock()

    /// Current accumulated audio time (energy-weighted, reset on track change).
    public var accumulatedAudioTime: Float {
        audioTimeLock.withLock { _accumulatedAudioTime }
    }

    /// Reset accumulated audio time to zero. Call on track change.
    public func resetAccumulatedAudioTime() {
        audioTimeLock.withLock { _accumulatedAudioTime = 0 }
        // BUG-041 — new track: re-warm the aurora's drums driver (the stem
        // analyzer resets too and its deviation EMA overswings while it
        // re-converges) and drop the previous track's smoothed value.
        auroraTrackWarmup01 = 0
        auroraDrumsSmoothed = 0
    }

    /// Advance accumulated audio time by one frame.
    /// `energy` should be `max(0, (bass + mid + treble) / 3.0)`.
    /// Called by `draw(in:)` each frame; also accessible from tests via `@testable import`.
    func stepAccumulatedTime(energy: Float, deltaTime: Float) {
        audioTimeLock.withLock {
            _accumulatedAudioTime += max(0, energy) * deltaTime
        }
    }

    // MARK: - Frame Budget Governor (D-057)

    /// Optional frame budget governor. When nil, the governor is disabled (tests,
    /// headless contexts). Wire in from VisualizerEngine after construction.
    public var frameBudgetManager: FrameBudgetManager?

    /// Secondary timing observer for soak/diagnostics (D-060c). Same source as `frameBudgetManager`.
    public var onFrameTimingObserved: ((_ cpuMs: Float, _ gpuMs: Float?) -> Void)?

    /// Render-loop CPU breakdown observer (PERF.2-render — BUG-019 instrumentation).
    /// Fires from the same command-buffer completion handler as `onFrameTimingObserved`,
    /// so the lag pattern is identical (1–3 frames behind the features the row carries).
    ///   - `encodeCpuMs`: wall-clock from `draw()` entry through `commandBuffer.commit()`.
    ///                    Excludes the inflight-semaphore wait (pre-entry) and the GPU
    ///                    queue-wait + GPU-execute (post-commit).
    ///   - `renderframeCpuMs`: time spent inside `renderFrame(...)` — the big switch
    ///                         over active passes. Tells you whether the CPU work is in
    ///                         the dispatched pass or in the pre/post setup.
    public var onRenderTimingObserved: ((_ encodeCpuMs: Float, _ renderframeCpuMs: Float) -> Void)?

    /// Ray-march per-pass CPU breakdown observer (PERF.2-pass — BUG-019 instrumentation).
    /// Fires from `drawWithRayMarch` after `RayMarchPipeline.render(...)` returns. Only
    /// invoked on ray-march frames; other preset paths leave the recorder's values empty.
    ///   - `gbufferMs`: wall-clock of the G-buffer pass (SDF or mesh dispatch).
    ///   - `lightingMs`: wall-clock of the lighting pass.
    ///   - `ssgiMs`: wall-clock of SSGI pass + blend (0 when suppressed for this frame).
    ///   - `postProcessMs`: wall-clock of bloom / composite.
    public var onRayMarchPassTimingObserved: (
        (_ gbufferMs: Float, _ lightingMs: Float, _ ssgiMs: Float, _ postProcessMs: Float) -> Void
    )?

    // MARK: - Timing

    let startTime: CFAbsoluteTime
    var lastFrameTime: CFAbsoluteTime
    var drawStartTime: CFAbsoluteTime = 0

    // MARK: - Init

    /// Create the render pipeline with audio buffer bindings and feedback infrastructure.
    ///
    /// - Parameters:
    ///   - context: Metal context (device, queue, semaphore).
    ///   - shaderLibrary: Compiled shader library for pipeline state creation.
    ///   - fftBuffer: UMA buffer containing 512 FFT magnitude bins (from FFTProcessor).
    ///   - waveformBuffer: UMA buffer containing interleaved stereo PCM (from AudioBuffer).
    public init(
        context: MetalContext,
        shaderLibrary: ShaderLibrary,
        fftBuffer: MTLBuffer,
        waveformBuffer: MTLBuffer
    ) throws {
        self.context = context
        self.fftMagnitudeBuffer = fftBuffer
        self.waveformBuffer = waveformBuffer
        self.startTime = CFAbsoluteTimeGetCurrent()
        self.lastFrameTime = self.startTime
        self.spectralHistory = SpectralHistoryBuffer(device: context.device)

        self.pipelineState = try shaderLibrary.renderPipelineState(
            named: "waveform",
            vertexFunction: "fullscreen_vertex",
            fragmentFunction: "waveform_fragment",
            pixelFormat: context.pixelFormat,
            device: context.device
        )
        self.feedbackWarpPipelineState = try shaderLibrary.renderPipelineState(
            named: "feedback_warp",
            vertexFunction: "fullscreen_vertex",
            fragmentFunction: "feedback_warp_fragment",
            pixelFormat: context.pixelFormat,
            device: context.device
        )
        self.feedbackBlitPipelineState = try shaderLibrary.renderPipelineState(
            named: "feedback_blit",
            vertexFunction: "fullscreen_vertex",
            fragmentFunction: "feedback_blit_fragment",
            pixelFormat: context.pixelFormat,
            device: context.device
        )

        // Bilinear, clamp-to-edge sampler for feedback texture reads.
        let samplerDesc = MTLSamplerDescriptor()
        samplerDesc.minFilter = .linear
        samplerDesc.magFilter = .linear
        samplerDesc.sAddressMode = .clampToEdge
        samplerDesc.tAddressMode = .clampToEdge
        guard let sampler = context.device.makeSamplerState(descriptor: samplerDesc) else {
            throw MetalContextError.noDevice
        }
        self.feedbackSamplerState = sampler

        super.init()
        logger.info("RenderPipeline initialized with render-graph support")
    }

    // MARK: - Render Graph

    /// Set the active render passes for the current preset.
    ///
    /// Called from `applyPreset` after all subsystems are configured.
    /// `renderFrame` iterates this array each frame to select the draw path.
    /// Thread-safe — can be called from any queue.
    public func setActivePasses(_ passes: [RenderPass]) {
        passesLock.withLock { activePasses = passes }
        logger.info("Active passes: [\(passes.map(\.rawValue).joined(separator: ", "))]")
    }

    /// The currently active render passes (snapshot for testing / diagnostics).
    public var currentPasses: [RenderPass] {
        passesLock.withLock { activePasses }
    }

    /// Whether `draw(in:)` renders this frame, or skips it as a transient preset-SWAP
    /// state. `applyPreset` (main thread) clears `activePasses` to `[]` before republishing
    /// the new preset's passes at the very end, while `draw(in:)` runs concurrently on
    /// MTKView's display-link thread. A frame that lands in that window must NOT render:
    /// `renderFrame` would fall through to `drawDirect` with the new preset's
    /// already-published direct pipeline, sending it to the 8-bit drawable — a benign stray
    /// frame for an 8-bit preset (the rare BUG-060 glitch), a hard format-mismatch GPU
    /// abort for Nacre's `.rgba16Float` direct pipeline (BUG-061). Empty `activePasses`
    /// only ever exists mid-swap (every applied preset has non-empty passes), so skipping
    /// is correct — MTKView holds the last presented frame for the ~ms of the swap.
    var willRenderActiveFrame: Bool {
        passesLock.withLock { !activePasses.isEmpty }
    }

    // MARK: - MTKViewDelegate

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        let width = max(Int(size.width), 1)
        let height = max(Int(size.height), 1)

        // CLEAN.4.4: only (re)allocate the ping-pong for a preset that samples it.
        // A non-feedback or particle-mode preset gets none — and any pair left over
        // from a previous feedback preset is released here (the resize is the natural
        // boundary if the switch-away free was missed). Feedback presets re-allocate
        // at the new size, preserving the D-061(a) hot-plug no-torn-frames contract.
        // The other subsystems below (post-process, ray march, mv_warp, staged) keep
        // their unconditional reallocation — they are gated by their own attachment.
        if activePresetSamplesFeedback {
            var textures: [MTLTexture] = []
            var feedbackAllocOK = true
            for i in 0..<2 {
                guard let tex = context.makeSharedTexture(
                    width: width,
                    height: height,
                    usage: [.renderTarget, .shaderRead]
                ) else {
                    // CLEAN.4.3: do NOT `return` here — that abandoned the post-process /
                    // ray-march / mv_warp reallocations below, stranding them at the stale
                    // size. Drop the feedback pair (feedback rendering guards on empty) and
                    // fall through so the other subsystems still resize.
                    logger.error("Failed to allocate feedback texture \(i)")
                    feedbackAllocOK = false
                    break
                }
                textures.append(tex)
            }
            feedbackLock.withLock {
                if feedbackAllocOK {
                    feedbackTextures = textures
                    feedbackIndex = 0
                } else {
                    feedbackTextures = []
                }
            }
        } else {
            feedbackLock.withLock { feedbackTextures = [] }
        }

        // Reallocate post-process textures if a chain is attached.
        postProcessLock.withLock {
            postProcessChain?.allocateTextures(width: width, height: height)
        }

        // Reallocate ray march G-buffer and lit textures if a pipeline is attached.
        rayMarchLock.withLock {
            rayMarchPipeline?.allocateTextures(width: width, height: height)
        }

        // Track size so mid-session preset switches allocate mv_warp textures correctly.
        mvWarpLock.withLock { currentDrawableSize = size }

        // Reallocate mv_warp textures if the active preset uses the warp pass.
        reallocateMVWarpTextures(size: size)
        // Reallocate per-stage offscreen textures for staged-composition presets.
        reallocateStagedTextures(size: size)

        logger.info("Drawable resized to \(width)×\(height)")
    }

    @MainActor
    public func draw(in view: MTKView) {
        // Wait for an available frame slot (triple buffering).
        context.inflightSemaphore.wait()

        guard let commandBuffer = context.commandQueue.makeCommandBuffer() else {
            context.inflightSemaphore.signal()
            return
        }

        let cpuDrawStart = CACurrentMediaTime()

        let now = CFAbsoluteTimeGetCurrent()
        let elapsed = Float(now - startTime)
        let deltaTime = Float(now - lastFrameTime)
        lastFrameTime = now

        var features = featuresLock.withLock { latestFeatures }
        features.time = elapsed
        features.deltaTime = deltaTime
        let size = view.drawableSize
        features.aspectRatio = size.height > 0 ? Float(size.width / size.height) : 1.777

        let energy = (features.bass + features.mid + features.treble) / 3.0
        stepAccumulatedTime(energy: energy, deltaTime: deltaTime)
        features.accumulatedAudioTime = audioTimeLock.withLock { _accumulatedAudioTime }

        // Beat clamp: scale onset-pulse amplitudes (U.9, D-054). Timing primitives NOT clamped.
        let beatScale = beatAmplitudeScale
        features.beatBass *= beatScale
        features.beatMid *= beatScale
        features.beatTreble *= beatScale
        features.beatComposite *= beatScale

        let stemSnap = stemFeaturesLock.withLock { latestStemFeatures }
        spectralHistory.append(features: features, stems: stemSnap)

        // PERF.2-render — BUG-019 instrumentation. Time the renderFrame dispatch
        // (the big switch over active passes) separately from the surrounding
        // setup + commit overhead, so the CPU bump can be attributed.
        let renderframeStart = CACurrentMediaTime()
        // Skip the frame during the transient preset-SWAP window (BUG-061 / BUG-060).
        // `applyPreset` runs on the main thread while this draw runs on MTKView's
        // CVDisplayLink thread (hence the per-field locks); it clears `activePasses` to
        // [] up front and republishes the real passes only at the very end. A frame that
        // lands in that window sees EMPTY passes + the new preset's already-published
        // direct pipeline → `renderFrame` falls through to `drawDirect`, rendering that
        // pipeline straight to the 8-bit drawable. For an 8-bit preset that's a benign
        // stray frame (the rare BUG-060 glitch); for Nacre's `.rgba16Float` direct
        // pipeline it's a hard attachment-format-mismatch GPU abort. Empty `activePasses`
        // only ever exists mid-swap (every applied preset has non-empty passes), so
        // skipping it is correct — MTKView holds the last presented frame for the ~ms of
        // the swap. The empty command buffer still commits + signals the inflight
        // semaphore below, so triple-buffering never stalls.
        if willRenderActiveFrame {
            renderFrame(commandBuffer: commandBuffer, view: view, features: &features)
            // Session recording hook — after renderFrame so drawable has the final image.
            if let hook = onFrameRendered, let drawable = view.currentDrawable {
                let stems = stemFeaturesLock.withLock { latestStemFeatures }
                hook(drawable.texture, features, stems, commandBuffer)
            }
        }
        let renderframeCpuMs = Float((CACurrentMediaTime() - renderframeStart) * 1000)

        // PERF.2-render — total CPU encode time, from draw() entry through
        // commandBuffer.commit(). Excludes the inflight-semaphore wait (which
        // happens before cpuDrawStart) and the GPU wait/execute time (which
        // happens after commit()). Combined with frame_cpu_ms (full wall-clock
        // including GPU completion handler dispatch), the diagnostic split is:
        //   commit_to_complete_ms = frame_cpu_ms - encode_cpu_ms
        //   pre_post_render_ms    = encode_cpu_ms - renderframe_cpu_ms
        let encodeCpuMs = Float((CACurrentMediaTime() - cpuDrawStart) * 1000)
        let sema = context.inflightSemaphore
        commandBuffer.addCompletedHandler { [weak self, cpuDrawStart, encodeCpuMs, renderframeCpuMs, sema] cb in
            sema.signal()
            let cpuMs = Float((CACurrentMediaTime() - cpuDrawStart) * 1000)
            let gpuMs: Float? = cb.gpuEndTime > cb.gpuStartTime
                ? Float((cb.gpuEndTime - cb.gpuStartTime) * 1000)
                : nil
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.onFrameTimingObserved?(cpuMs, gpuMs)
                self.onRenderTimingObserved?(encodeCpuMs, renderframeCpuMs)
                guard let mgr = self.frameBudgetManager else { return }
                let level = mgr.observe(.init(cpuFrameMs: cpuMs, gpuFrameMs: gpuMs))
                self.applyQualityLevel(level)
            }
        }

        commandBuffer.commit()
    }
}
