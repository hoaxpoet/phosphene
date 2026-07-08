// swiftlint:disable file_length
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable type_body_length
// VisualizerEngine — Audio capture → FFT → MIR analysis → renderer pipeline owner.
//
// Created once at app launch by ContentView via @StateObject. Audio capture
// starts on first appear after verifying screen capture permission.

import Audio
import Combine
import CoreGraphics
import DSP
import Foundation
import ML
import Orchestrator
import os.log
import Presets
import Renderer
import Session
import Shared
import SwiftUI

private let logger = Logger(subsystem: "com.phosphene.app", category: "VisualizerEngine")

// MARK: - MIRDiagnostics

/// Raw MIR values for debug overlay diagnostics.
struct MIRDiagnostics {
    var magMax: Float = 0
    var bass: Float = 0
    var mid: Float = 0
    var centroid: Float = 0
    var flux: Float = 0
    var majorCorr: Float = 0
    var minorCorr: Float = 0
    var callbackCount: Int = 0
    var onsetsPerSec: Int = 0
    var totalEnergy: Float = 0
    /// AGC-normalised 20–80 Hz sub-bass band (spider trigger input).
    var subBass: Float = 0
    /// Bass stem attack ratio (ratio of attack energy to sustained RMS).
    var bassAttackRatio: Float = 0
}

// MARK: - VisualizerEngine

/// Owns the audio capture → FFT → renderer pipeline.
///
/// Created once at app launch via `@StateObject`. Audio capture starts
/// on first appear after verifying screen capture permission.
final class VisualizerEngine: ObservableObject, @unchecked Sendable {

    // MARK: - Published State

    /// Currently displayed preset name (shown briefly on switch).
    @Published var currentPresetName: String?

    /// Whether the debug overlay is visible (toggle with 'D' key).
    @Published var showDebugOverlay = false

    /// Per-frame dashboard snapshot (BeatSync + Stems + Perf). Republished from
    /// `onFrameRendered` on `@MainActor`; the SwiftUI dashboard overlay view
    /// model (DASH.7) subscribes via Combine and throttles to ~30 Hz.
    ///
    /// CLEAN.1.4 (BUG-033): this is a dedicated `CurrentValueSubject`, **not**
    /// `@Published`. As `@Published` on this `@EnvironmentObject`-wide engine,
    /// writing it every rendered frame fired `objectWillChange` and re-evaluated
    /// the *entire* SwiftUI tree at 60 Hz. Routing it through its own subject means
    /// only `DashboardOverlayViewModel` (which throttles to ~30 Hz) re-renders.
    let dashboardSnapshotSubject = CurrentValueSubject<DashboardSnapshot?, Never>(nil)

    /// Whether the dashboard overlay is currently visible. `PlaybackView` pushes
    /// its local `showDebug` here. CLEAN.1.4 (BUG-033): the per-frame snapshot
    /// pump skips all snapshot work when this is false — and the dashboard
    /// defaults to hidden. Plain (non-`@Published`): toggled rarely, and it must
    /// not itself invalidate the tree.
    var dashboardOverlayVisible = false

    /// Whether uncertified presets are eligible for reactive-mode selection.
    /// Mirrors `SettingsStore.showUncertifiedPresets`; pushed via `applyShowUncertifiedPresets(_:)`.
    var showUncertifiedPresets: Bool = false

    /// Current track metadata from Now Playing.
    @Published var currentTrack: TrackMetadata?

    /// Raw album-artwork bytes for the live track (PNG / JPEG, depending on
    /// container). LF.6: populated alongside `currentTrack` for local-file
    /// sessions from the LF.5 persistent cache's `artwork.bin` sibling.
    /// Streaming sessions leave this `nil` until LF.6.streaming wires up
    /// Spotify Web API + iTunes Search artwork-URL fetch.
    ///
    /// **Invariant:** updated in the same MainActor tick as `currentTrack`
    /// — title-first then artwork-second — so chrome consumers binding to
    /// both don't briefly render the previous track's artwork against the
    /// new track's title (or vice versa). See `handleLocalFileReady()` /
    /// `advanceLocalFileQueue(direction:)` for the LF write sites.
    @Published var currentTrackArtworkData: Data?

    /// Most-recently-resolved canonical `TrackIdentity` for the live track.
    /// Set by the track-change handler in `VisualizerEngine+Capture.swift`
    /// after `canonicalTrackIdentity(matching:)` resolution; consumed by
    /// `applyPreset` so per-track preset state (e.g. Lumen Mosaic's per-song
    /// palette draw) can be loaded when a preset is activated mid-track,
    /// without waiting for the next track-change to fire `resetStemPipeline`.
    /// Internal-only twin of `currentTrack`; not `@Published` because no view
    /// model binds to it. (BUG-016 fix, 2026-05-26.)
    var lastResolvedTrackIdentity: TrackIdentity?

    /// Beat-regularity of the live track (FBS / D-154), resolved from the
    /// cached grids in `resetStemPipeline` at track change. `true` ⇒ the
    /// reactive scorer hard-excludes `requires_regular_beat` presets (FFO);
    /// nil = unknown/uncached — permissive. Stored here because the reactive
    /// evaluate runs off the analysis path where the caches are not reachable.
    var currentTrackBeatIrregular: Bool?

    /// 0-based index of the live track within `livePlannedSession`, or nil when
    /// the track is not part of the plan (covers, remasters, encoding-different
    /// versions) or when no plan exists. Set by the orchestrator plan walk in
    /// `currentPreset(at:)` / `currentTrackIndexInPlan()`. QR.4 / D-091 — replaces
    /// the lowercased title+artist string match in `PlaybackChromeViewModel`,
    /// which silently failed on covers/remasters.
    @Published var currentTrackIndex: Int?

    /// Pre-fetched profile from external APIs.
    @Published var preFetchedProfile: PreFetchedTrackProfile?

    /// Live mood classification from MoodClassifier (updated per frame).
    @Published var currentMood: EmotionalState = .neutral

    /// Live estimated key from MIR pipeline.
    @Published var estimatedKey: String?

    /// Live estimated tempo from MIR pipeline.
    @Published var estimatedTempo: Float?

    /// Raw MIR diagnostic values for debug overlay.
    @Published var mirDiag: MIRDiagnostics = MIRDiagnostics()

    /// Whether feature capture is active (toggle with 'C' key).
    @Published var isCapturing = false

    /// Whether screen capture permission has been granted.
    @Published var hasScreenCapturePermission = false

    /// Current audio signal state — `.silent` indicates DRM-triggered tap silencing.
    @Published var audioSignalState: AudioSignalState = .active

    /// When true, the ray march G-buffer debug visualization is active.
    /// gbuf2 is copied directly to the drawable — bypassing lighting/SSGI/ACES —
    /// so the raw 4-quadrant diagnostic colors are readable on screen.
    /// Toggle with 'G' key. Only affects ray march presets.
    @Published var debugGBufferMode: Bool = false {
        didSet { currentRayMarchPipeline?.debugGBufferMode = debugGBufferMode }
    }

    /// Reference to the currently-active RayMarchPipeline (if any).
    /// Kept so `debugGBufferMode.didSet` can push changes without a pipeline lookup.
    /// Set in `applyPreset` when a ray march preset is activated; cleared otherwise.
    var currentRayMarchPipeline: RayMarchPipeline?

    /// Arachne web-pool state — allocated when the Arachne preset is active,
    /// nil otherwise. Tick closure and webBuffer are wired into the render pipeline
    /// via `setMeshPresetTick` / `setDirectPresetFragmentBuffer` in `applyPreset`.
    var arachneState: ArachneState?

    /// Latest bass stem attack ratio — updated each per-frame stem analysis pass,
    /// forwarded into MIRDiagnostics for the spider debug overlay.
    var latestBassAttackRatio: Float = 0

    /// Gossamer wave-pool state — allocated when the Gossamer preset is active,
    /// nil otherwise. Tick closure and waveBuffer are wired into the render pipeline
    /// via `setMeshPresetTick` / `setDirectPresetFragmentBuffer` in `applyPreset`.
    var gossamerState: GossamerState?

    /// Aurora Veil kink-accumulator + pitch-smoother state — allocated when
    /// the Aurora Veil preset is active, nil otherwise. Tick closure and
    /// stateBuffer are wired via `setMeshPresetTick` /
    /// `setDirectPresetFragmentBuffer` in `applyPreset` (AV.2 — same Gossamer
    /// pattern, slot 6).
    var auroraVeilState: AuroraVeilState?

    /// Nimbus Energy bloom follower + gas flow-phase state — allocated when the
    /// Nimbus preset is active, nil otherwise. Tick closure and stateBuffer are
    /// wired via `setMeshPresetTick` / `setDirectPresetFragmentBuffer` in
    /// `applyPreset` (NB.4 — same direct-preset slot-6 pattern as Aurora Veil).
    var nimbusState: NimbusState?

    /// Skein painter integrators + onset-burst ring + per-track seed — allocated
    /// when the Skein preset is active, nil otherwise. Tick closure and
    /// skeinBuffer are wired via `setMeshPresetTick` / `setDirectPresetFragmentBuffer`
    /// in `applyPreset` (Skein.ENGINE.1.2 — the gated slot-6 marks-on-top overlay
    /// buffer). Re-seeded on track change for the §5.7 determinism property.
    var skeinState: SkeinState?

    /// Lumen Mosaic 4-light pattern engine — allocated when the Lumen Mosaic
    /// preset is active, nil otherwise. Tick closure flushes the engine state
    /// to a 336-byte UMA buffer bound at fragment slot 8 of the ray-march
    /// G-buffer + lighting passes via `setDirectPresetFragmentBuffer3` in
    /// `applyPreset`. (LM.2 / D-LM-buffer-slot-8.)
    var lumenPatternEngine: LumenPatternEngine?

    /// Ferrofluid Ocean particle scaffolding (V.9 Session 4.5b Phase 1) —
    /// allocated when that preset is active, nil otherwise. Owns the 2048-
    /// particle UMA buffer + 512×512 r16Float baked height texture bound at
    /// fragment texture slot 10 of the ray-march G-buffer pass via
    /// `setRayMarchPresetHeightTexture` in `applyPreset`. Phase 1 bakes the
    /// height field once at preset apply (particles are static); Phase 2 will
    /// add per-frame SPH-lite motion + audio forces.
    var ferrofluidParticles: FerrofluidParticles?

    /// Tessellated quad mesh + G-buffer pipeline for the V.9 Session 4.5c
    /// Phase 1 Step B mesh-displacement path. Allocated alongside
    /// `ferrofluidParticles` when Ferrofluid Ocean is the active preset;
    /// owns the 256² vertex buffer, index buffer, mesh G-buffer pipeline
    /// state, and depth-stencil state. The encode closure registered via
    /// `setMeshGBufferEncoder` captures a weak reference to this instance.
    var ferrofluidMesh: FerrofluidMesh?

    /// Dynamic text overlay for SpectralCartograph — allocated when that preset is
    /// active, nil otherwise. Freed and detached on every `applyPreset` call.
    var spectralCartographOverlay: DynamicTextOverlay?

    // MARK: - Pipeline References

    /// Metal context shared across the pipeline.
    let context: MetalContext

    /// Active render pipeline driving the MTKView.
    let pipeline: RenderPipeline

    /// Ring buffer receiving PCM samples from the audio capture.
    private let audioBuffer: AudioBuffer

    /// Real-time FFT processor writing magnitudes to a GPU buffer.
    private let fftProcessor: FFTProcessor

    /// Preset loader managing shader compilation and hot-reload.
    let presetLoader: PresetLoader

    /// MIR feature extraction pipeline (spectral, energy, chroma, beat).
    let mirPipeline: MIRPipeline

    /// Mood classifier (valence/arousal — MPSGraph + hardcoded MLP weights).
    let moodClassifier: MoodClassifier?

    /// GPU compute particle system for Murmuration — attached to feedback
    /// presets via `ParticleGeometry` (D-097).
    var murmurationGeometry: (any ParticleGeometry)?

    /// Physarum agent-network for the Filigree preset — attached via
    /// `ParticleGeometry` (D-097, PHYS.2). Built eagerly like Murmuration.
    var filigreeGeometry: (any ParticleGeometry)?

    /// Reaction–diffusion cell colony for the Mitosis preset — attached via
    /// `ParticleGeometry` (D-097, MITOSIS.1). Built eagerly like Filigree.
    var mitosisGeometry: (any ParticleGeometry)?

    /// Detailed fluorescence-microscopy cell division for the Cytokinesis preset
    /// (Mitosis gen-2) — explicit per-cell `ParticleGeometry` (D-097, MITOSIS-G2.1).
    var cytokinesisGeometry: (any ParticleGeometry)?

    /// Fluid dye simulation + glow ribbons for the Ricercar preset (Fantasia rebuild)
    /// — Stam stable-fluids `ParticleGeometry` (D-097, RICERCAR-FL.5).
    var ricercarGeometry: (any ParticleGeometry)?

    /// Shader library for creating post-process chains on preset switch.
    let shaderLibrary: Renderer.ShaderLibrary

    /// AudioInputRouter requires macOS 14.2+; stored as Any to avoid propagating availability.
    var router: Any?

    /// True once the live tap has delivered any non-silent audio this session
    /// (BUG-057). Drives the silent-tap card's pause-suppression: a session that
    /// has had audio and goes silent is a user pause (suppress), not a broken tap.
    var hasEverDetectedAudio: Bool {
        if #available(macOS 14.2, *), let audioRouter = router as? AudioInputRouter {
            return audioRouter.hasEverDetectedSignal
        }
        return false
    }

    /// Metadata pre-fetcher for external API queries.
    var preFetcher: MetadataPreFetcher?

    // MARK: - Streaming Artwork (LF.6.streaming)

    /// Resolves album-artwork URLs for streaming tracks. Spotify-first
    /// (`TrackIdentity.spotifyArtworkURL`) then iTunes Search fallback.
    var streamingArtworkResolver: StreamingArtworkURLResolving = StreamingArtworkURLResolver()

    /// URLSession-backed byte fetcher for resolved artwork URLs.
    var streamingArtworkFetcher: StreamingArtworkFetching = DefaultStreamingArtworkFetcher()

    /// Disk cache for fetched artwork bytes (SHA-256-keyed LRU, 100 MB cap,
    /// `~/Library/Caches/com.phosphene.app/streaming-artwork/`).
    var streamingArtworkDiskCache = StreamingArtworkDiskCache()

    /// Owns the in-flight artwork fetch task for the live streaming track.
    /// Lazily constructed once `init()` is past phase 2 so the publish
    /// closure can capture `self`.
    var streamingArtworkPublisher: StreamingArtworkPublisher?

    // MARK: - Device Tier

    /// GPU capability tier: .tier1 (M1/M2) or .tier2 (M3/M4).
    /// Drives per-tier defaults for FrameBudgetManager and MLDispatchScheduler.
    let deviceTier: DeviceTier

    // MARK: - Stem Pipeline

    /// Session manager that coordinates playlist preparation. Created at init;
    /// exposes `cache` which is wired to `stemCache` when the session reaches `.ready`.
    var sessionManager: SessionManager

    /// Pre-analyzed stem data from session preparation.
    ///
    /// Wired eagerly in `init` to `sessionManager.cache` (the same `StemCache`
    /// instance that `SessionPreparer` populates during preparation). The cache
    /// fills with entries as background preparation completes, so the field is
    /// always non-nil after init even though entries become available
    /// progressively. This is the cache that `resetStemPipeline(for:)` reads
    /// on track change to load pre-separated stems and the prepared `BeatGrid`.
    /// (BUG-006.2 fix for cause 1 — was declared but never assigned.)
    var stemCache: StemCache?

    /// Disk-backed content-keyed stem cache for local-file playback
    /// (LF.3 / D-130). Lives alongside the in-memory `stemCache` —
    /// the persistent layer survives app restarts so a second launch
    /// on the same local file installs cached BeatGrid + stems in
    /// ~100 ms instead of re-running the ~2 s pre-analysis. Wired
    /// eagerly in `init` to a default cache rooted at
    /// `~/Library/Application Support/Phosphene/StemCache/`. Stays
    /// `nil` if the cache directory can't be created — the LF path
    /// then falls through to the LF.2 in-memory-only flow on every
    /// launch.
    var persistentStemCache: PersistentStemCache?

    /// Current persistent-cache footprint in bytes. Drives the dynamic
    /// `Phosphene → Clear Local-File Cache (<size>)` menu label (LF.4 / D-131).
    /// Refreshed on engine init, after each LF preparation completes, and
    /// after `clearAll()` runs. Slightly stale between refreshes is fine
    /// — the menu label re-reads on next refresh.
    @Published var localFileCacheBytes: Int64 = 0

    /// Recompute the persistent-cache footprint and republish.
    @MainActor
    func refreshLocalFileCacheBytes() {
        localFileCacheBytes = persistentStemCache?.totalBytes() ?? 0
    }

    /// `true` when the LF audio router is paused (via the transport bar's
    /// Play/Pause button). `false` when actively playing or when no LF
    /// session is active. Drives the transport bar's glyph (▶ vs ⏸).
    /// LF.5.fix D-LF5-3.
    @Published var isLocalFilePaused: Bool = false

    /// GAP H (2026-05-28): the most-recently-active LF SessionOrigin,
    /// preserved across `endSession()` so EndedView can offer a
    /// "Play %@ again" CTA. Cleared when a streaming session takes over;
    /// updated whenever a fresh LF session starts. `nil` between launches
    /// AND when the last completed session was streaming.
    @Published var lastEndedLocalFileOrigin: SessionOrigin?

    /// LF.5.fix.3-C: URL that `handleLocalFileReady` already committed to
    /// playback for the current LF session. Used as a duplicate-emission
    /// guard — if `handleLocalFileReady` fires a second time for the same
    /// URL (e.g. a stale prep result driving a redundant `_completeLocalFilesReady`),
    /// the call no-ops instead of tearing down the audio router mid-track.
    ///
    /// Captured in session 2026-05-28T20-57-46Z lines 78-94: SZ2 was already
    /// playing when a second `prepareLocalFiles DONE` triggered .ready again
    /// → `handleLocalFileReady` ran provider.teardown + restart from frame
    /// 0 with no user input. With Bug A's gen-counter fix in place this
    /// shouldn't fire, but Matt requested defense-in-depth (URL match only)
    /// at LF.5.fix.3-C kickoff so future races can't reproduce the symptom.
    ///
    /// Cleared on `.preparing` (new session starting) and `.ended` (session
    /// teardown) in the state-machine observer.
    var lastStartedLocalFilePlaybackURL: URL?

    /// Stem separator (MPSGraph on GPU).
    let stemSeparator: StemSeparator?

    /// Ring buffer accumulating interleaved stereo PCM for stem separation.
    /// Buffer capacity is sized at `StemSeparator.modelSampleRate` (44100 Hz)
    /// for `maxSeconds` of stereo audio; on a 48 kHz tap it still holds ≈ 13.8 s,
    /// which exceeds every consumer's 10 s window. The actual tap rate is
    /// supplied to the rate-aware `snapshotLatest`/`rms` overloads so the
    /// retrieved sample count matches real wall-clock time. (D-079, QR.1)
    let stemSampleBuffer = StemSampleBuffer(
        sampleRate: Double(StemSeparator.modelSampleRate),
        maxSeconds: 15
    )

    /// Lock guarding `_tapSampleRate`. Writes happen on the audio thread; reads
    /// from `stemQueue` and `analysisQueue`. Cross-core visibility for an
    /// 8-byte field is not guaranteed without a synchronization barrier on
    /// Apple Silicon, so all access goes through `tapSampleRate` /
    /// `updateTapSampleRate(_:)`. (Architect H1, D-079, QR.1)
    private let tapSampleRateLock = NSLock()

    /// Backing store for `tapSampleRate`. Read/write under `tapSampleRateLock`.
    private var _tapSampleRate: Double = Double(StemSeparator.modelSampleRate)

    /// Actual sample rate delivered by the Core Audio tap. Typically 48000 Hz
    /// when Audio MIDI Setup is left at its default; 44100 Hz on some hardware.
    /// Initialized to `StemSeparator.modelSampleRate`; the audio callback
    /// updates it on every frame via `updateTapSampleRate(_:)`. The lock
    /// provides cross-core visibility for the stem queue and analysis queue.
    var tapSampleRate: Double {
        tapSampleRateLock.withLock { _tapSampleRate }
    }

    /// Update the captured tap sample rate. Called from the audio callback.
    /// The audio thread always passes the current install's rate, so the
    /// stored value is stable for the lifetime of a tap install (and changes
    /// only across capture-mode switches that re-install the tap).
    func updateTapSampleRate(_ rate: Double) {
        tapSampleRateLock.withLock { _tapSampleRate = rate }
    }

    /// Per-stem energy + beat analysis.
    let stemAnalyzer: StemAnalyzer

    /// Background queue for stem separation (utility QoS — never blocks render).
    let stemQueue = DispatchQueue(label: "com.phosphene.stemSeparator", qos: .utility)

    /// Repeating timer that triggers stem separation every 5 seconds.
    var stemTimer: DispatchSourceTimer?

    /// ML dispatch scheduler — defers stem separation to frame-timing-clean moments.
    /// Nil in test/headless contexts where no scheduler is wired. Increment 6.3.
    var mlDispatchScheduler: MLDispatchScheduler?

    /// Wall-clock timestamp of when the current stem dispatch was first requested.
    /// Set at the start of the pending window; cleared when the dispatch fires.
    /// Nil when no dispatch is pending (timer has not yet fired, or last dispatch completed).
    var pendingDispatchStartTime: TimeInterval?

    /// Beat This! analyzer used for live tap audio analysis. Allocated lazily on first
    /// use in `runLiveBeatAnalysisIfNeeded()` — weight loading is heavy.
    var liveBeatGridAnalyzer: DefaultBeatGridAnalyzer?

    /// IFC.4 (D-177) — PANNs instrument-family analyzer for the LF pre-analysis
    /// path. Eager-init alongside the LF beat-grid analyzer; nil → empty series.
    var liveFamilyAnalyzer: InstrumentFamilyAnalyzer?

    /// IFC.4 (D-177) — the active track's preview-derived instrument-family
    /// activity series (Layer 5a). Installed at track change from the cache;
    /// sampled by playback position each analysis frame. Empty → family fields
    /// clear to zero. Cleared on every track-change path (anti-leak, §What NOT To Do).
    var currentFamilySeries: [InstrumentFamilyActivity] = []

    /// Number of live Beat This! analysis attempts made for the current track.
    /// Reset to 0 on `resetStemPipeline(for:)`. Allows one retry at 20 s if the
    /// first attempt at 10 s returns an empty grid (e.g. quiet intros, complex
    /// meters like Money 7/4 that Beat This! misses in a short window).
    var liveBeatAnalysisAttempts: Int = 0

    /// Whether the BUG-007.9 hybrid runtime recalibration has fired for the
    /// current track. One-shot: set true after a successful recalibration
    /// (or a deliberate skip). Reset to false in `resetStemPipeline(for:)`.
    var runtimeRecalibrationDone: Bool = false

    // MARK: - Stem Per-Frame Analysis State
    //
    // After each 5s stem separation completes on `stemQueue`, the produced
    // mono stem waveforms are stored here along with a wall-clock timestamp.
    // The per-frame analysis path in `processAnalysisFrame` (on
    // `analysisQueue`) slides a 1024-sample window through these waveforms
    // at real-time rate, running `StemAnalyzer.analyze` on each frame so
    // `StemFeatures` values in GPU buffer(3) update continuously instead of
    // stepping every 5 seconds (see `VisualizerEngine+Stems.runStemSeparation`
    // and `VisualizerEngine+Audio.runPerFrameStemAnalysis`).
    //
    // Writer: stemQueue (runStemSeparation). Reader: analysisQueue
    // (processAnalysisFrame). Lock synchronizes the handoff.

    /// The 4 separated mono stem waveforms (vocals, drums, bass, other) from
    /// the most recent `StemSeparator.separate` call. Each array covers
    /// approximately 10s of audio at 44.1 kHz. Empty before the first
    /// separation completes; cleared on track change.
    var latestSeparatedStems: [[Float]] = []

    /// Wall-clock timestamp of when `latestSeparatedStems` was stored. Used
    /// by the per-frame analyzer to compute a sliding window offset.
    var latestSeparationTimestamp: CFAbsoluteTime = 0

    /// Protects `latestSeparatedStems` + `latestSeparationTimestamp` across
    /// the stemQueue → analysisQueue handoff.
    let stemsStateLock = NSLock()

    /// Whether MIR recording is active.
    var mirPipelineIsRecording: Bool { mirPipeline.isRecording }

    /// Visual phase offset in milliseconds applied to beat/bar phase display only.
    /// Positive = flash fires earlier. Developer-only calibration — default 0.
    /// Backed by `LiveBeatDriftTracker.visualPhaseOffsetMs` (thread-safe).
    var beatPhaseOffsetMs: Float {
        get { mirPipeline.liveDriftTracker.visualPhaseOffsetMs }
        set { mirPipeline.liveDriftTracker.visualPhaseOffsetMs = newValue }
    }

    /// Shift the visual beat phase by `delta` ms. Clamped to ±500 ms.
    /// `[` key = −10 ms, `]` key = +10 ms in the developer shortcut map.
    func adjustBeatPhaseOffset(ms delta: Float) {
        let clamped = max(-500, min(500, beatPhaseOffsetMs + delta))
        beatPhaseOffsetMs = clamped
        logger.info("Beat phase offset adjusted to \(clamped, format: .fixed(precision: 1)) ms")
    }

    /// Cycle the bar-phase rotation offset by +1 (BUG-007.4 dev shortcut).
    /// `Shift+B` walks through 0..(beatsPerBar-1) so the user can confirm the
    /// Spotify-clip-phase hypothesis: keep cycling until the SpectralCartograph "1"
    /// lands on the song's perceived downbeat. Resets on track change.
    /// Setter wraps modulo the installed grid's beatsPerBar — no need to know it here.
    func cycleBarPhaseOffset() {
        let tracker = mirPipeline.liveDriftTracker
        tracker.barPhaseOffset += 1
        logger.info("Bar-phase offset cycled to \(tracker.barPhaseOffset) (BUG-007.4)")
    }

    /// Tap-to-output audio latency in milliseconds (BUG-007.6). Default 50 ms.
    /// Backed by `LiveBeatDriftTracker.audioOutputLatencyMs`. Persists across tracks.
    var audioOutputLatencyMs: Float {
        get { mirPipeline.liveDriftTracker.audioOutputLatencyMs }
        set { mirPipeline.liveDriftTracker.audioOutputLatencyMs = newValue }
    }

    /// Adjust audio output latency by `delta` ms (BUG-007.6). Setter clamps to ±500 ms.
    /// `,` key = −5 ms, `.` key = +5 ms in the developer shortcut map.
    func adjustAudioOutputLatency(ms delta: Float) {
        audioOutputLatencyMs += delta
        let actual = audioOutputLatencyMs
        logger.info("Audio output latency adjusted to \(actual, format: .fixed(precision: 1)) ms (BUG-007.6)")
    }

    /// Current frame-budget quality level. Read directly from the governor each
    /// time the debug overlay repaints — no @Published needed since the overlay
    /// refreshes on VisualizerEngine objectWillChange. D-057.
    var currentQualityLevel: FrameBudgetManager.QualityLevel {
        pipeline.frameBudgetManager?.currentLevel ?? .full
    }

    /// Human-readable ML dispatch state for the debug overlay. Increment 6.3.
    var currentMLSchedulerState: String {
        guard pendingDispatchStartTime != nil else { return "idle" }
        switch mlDispatchScheduler?.lastDecision {
        case .none:                         return "pending"
        case .dispatchNow:                  return "dispatch"
        case .forceDispatch:               return "force"
        case .defer(let ms):               return "defer \(Int(ms))ms"
        }
    }

    // MARK: - Beat Sync Diagnostic State

    /// Most-recent beat-sync snapshot from the analysis queue.
    /// Written on analysisQueue; read on the GPU completion handler queue.
    /// Guards both writes and reads with `beatSyncLock`.
    var latestBeatSyncSnapshot: BeatSyncSnapshot = .zero
    let beatSyncLock = NSLock()

    // MARK: - Capture/Recording State

    /// Feature capture file handle.
    var captureHandle: FileHandle?

    /// Path to the current capture file.
    var captureFilePath: String?

    // MARK: - Session Recorder

    /// Continuous diagnostic capture — video + per-frame CSVs + stem wavs +
    /// session.log. Runs from app launch; artifacts live under
    /// `~/Documents/phosphene_sessions/<timestamp>/`.
    let sessionRecorder: SessionRecorder?

    // MARK: - Signal Quality Monitor

    /// Continuous assessment of tap input quality (peak dBFS + spectral balance).
    let inputLevelMonitor = InputLevelMonitor()

    /// Last logged quality grade; avoids spamming session.log on every frame.
    var lastLoggedQuality: SignalQuality = .unknown

    /// Task that hides the preset name after a delay.
    var hideNameTask: Task<Void, Never>?

    // MARK: - Analysis State
    //
    // These are accessed from the background analysis queue via the audio
    // callback. The class is `@unchecked Sendable` and the mutations happen
    // only on the serial `analysisQueue`, so there is no data race.
    // Internal (not private) so the +Audio extension can access them.

    /// Running frame count for the analysis queue.
    var analysisFrameCount = 0

    /// Last MIR analysis sample rate written to `session.log` (BUG-053). 0 until
    /// the first frame logs it. Lets each session's artifact self-document the
    /// rate the live MIR actually ran at — the verification signal for the
    /// rate-reconfigure fix (key estimation is unreliable; the `os_log`
    /// `MIR_RATE` line isn't persisted). Re-logged on any change (device swap).
    var lastLoggedAnalysisRate: Float = 0

    /// 10-second EMA accumulator matching DEAM's track-level feature averages.
    var accumulatedFeatures = [Float](repeating: 0, count: 10)

    /// Whether `accumulatedFeatures` has been seeded with the first frame.
    var featureAccumInitialized = false

    /// Timestamp of the last analysis frame (for dt / effective fps).
    var lastAnalysisTime: CFAbsoluteTime = 0

    /// Diagnostic log file for the analysis queue.
    var diagLog: FileHandle?

    /// Background queue running MIR analysis off the real-time audio thread.
    let analysisQueue = DispatchQueue(
        label: "com.phosphene.analysis",
        qos: .userInteractive
    )

    /// EMA alpha for the accumulated mood-classifier feature window.
    /// At ~94 callbacks/s, alpha=0.01 gives ~7s effective window.
    static let featureEmaAlpha: Float = 0.01

    // MARK: - Orchestrator

    /// Session planner that produces a `PlannedSession` before playback.
    let sessionPlanner = DefaultSessionPlanner()

    /// Live adapter that refines the plan as playback progresses.
    let liveAdapter = DefaultLiveAdapter()

    /// Reactive orchestrator for ad-hoc (no-playlist) sessions.
    let reactiveOrchestrator = DefaultReactiveOrchestrator()

    /// The active planned session. Populated when the session reaches `.ready`.
    /// Guarded by `orchestratorLock` — read/write only under the lock.
    var livePlan: PlannedSession?

    /// Protects `livePlan` across the main-thread writer and render/audio-queue readers.
    let orchestratorLock = NSLock()

    /// SwiftUI-observable mirror of `livePlan`. Updated on the main actor inside
    /// `buildPlan()` and `regeneratePlan(lockedTracks:)` immediately after the lock write.
    @Published var livePlannedSession: PlannedSession?

    /// Retains the Combine subscription that triggers `buildPlan()` on `.ready`.
    var stateCancellable: AnyCancellable?

    /// Retains the subscription that calls `extendPlan()` as readiness level advances.
    var readinessCancellable: AnyCancellable?

    /// GAP H (2026-05-28): retains the subscription that stashes the most
    /// recent LF SessionOrigin into `lastEndedLocalFileOrigin` for the
    /// EndedView "Play <name> again" CTA.
    var lastLocalFileSourceCancellable: AnyCancellable?

    /// Seeded LCG perturbation value shared between `buildPlan()` and `extendPlan()`.
    /// Reset to nil when a new session begins (`.connecting` state), so each session
    /// gets a fresh random seed while `extendPlan()` reuses the same one.
    var currentSessionPlanSeed: UInt64?

    /// Wall-clock timestamp of the first reactive `applyLiveUpdate()` call.
    /// Set on entry, reset to nil when `buildPlan()` succeeds (real plan takes over).
    var reactiveSessionStart: Date?

    // MARK: - BUG-015 Live-Adaptation Wire Inputs

    /// 0-based plan index for the live track, resolved on the audio thread in
    /// `makeTrackChangeCallback`. Read by `runOrchestratorLiveUpdate(mir:)` on
    /// the analysis queue. Nil when no plan exists OR when the live track is
    /// not in the plan (cover/remaster/encoding-different variant). Guarded by
    /// `orchestratorLock` so cross-thread access is race-free (BUG-015).
    ///
    /// Separate from the `@Published var currentTrackIndex: Int?` SwiftUI
    /// surface: that one is MainActor-bound (written inside a
    /// `Task { @MainActor }` block), so it is not safe to read from the
    /// analysis queue without a thread hop. This field is the lock-guarded
    /// analysis-queue mirror — same value, different access discipline.
    var liveTrackPlanIndex: Int?

    /// Most recent mood classification (post-stability attenuation) written
    /// by `publishMoodResult` on the analysis queue. Read by
    /// `runOrchestratorLiveUpdate(mir:)` on the same queue and passed into
    /// `applyLiveUpdate(mood:)` (BUG-015). Defaults to `.neutral` so the wire
    /// is well-defined before the first mood frame fires (≈ first 3 seconds).
    /// Guarded by `orchestratorLock`.
    var lastClassifiedMood: EmotionalState = .neutral

    /// Once-per-track diagnostic latch for `runOrchestratorLiveUpdate(mir:)`
    /// (BUG-015 follow-up). When `false`, the next wire tick that actually
    /// reaches `applyLiveUpdate(...)` emits one `Orchestrator: wire active`
    /// line to both `session.log` (via `sessionRecorder?.log`) and the
    /// unified log (via `os.Logger`), then flips to `true`. Reset to
    /// `false` in the track-change callback so each new track produces
    /// exactly one wire-active line. Closes the BUG-015 validation
    /// ambiguity where reactive `holdDecision` paths log nothing per the
    /// existing log gate at `VisualizerEngine+Orchestrator.swift:291`,
    /// AND closes the doc-vs-runtime gap noted during BUG-015's first
    /// validation pass: existing Orchestrator log lines write to
    /// `os.Logger` only, not to `session.log`. The diagnostic dual-writes
    /// per the `VisualizerEngine+WiringLogs.swift` pattern.
    /// Guarded by `orchestratorLock`.
    var orchestratorWireLoggedThisTrack: Bool = false

    // MARK: - Preset Signaling (V.7.6.2)

    /// Subscription to the active preset's `presetCompletionEvent`. Replaced on
    /// every `applyPreset` call; cleared when the active preset does not conform
    /// to `PresetSignaling`.
    var presetCompletionCancellable: AnyCancellable?

    /// Wall-clock time at which the current segment became active, in
    /// `Date.timeIntervalSinceReferenceDate` seconds. Set on each `applyPreset`.
    /// Used to gate completion events against `PresetSignalingDefaults.minSegmentDuration`.
    var currentSegmentStartTime: TimeInterval = 0

    /// Number of force-dispatched preset transitions this session — counter for
    /// telemetry / debug overlay. Each `presetCompletionEvent` honoured (above the
    /// `minSegmentDuration` floor) increments this.
    var presetCompletionAdvanceCount: Int = 0

    /// Session-relative time of the last reactive preset switch.
    /// Prevents switching more often than once per 60 seconds.
    var lastReactiveSwitchTime: TimeInterval = -.infinity

    /// When true, the LiveAdapter mood-override path is suppressed so the current
    /// preset (e.g. Spectral Cartograph) is not replaced by the orchestrator.
    /// Toggled via the L dev shortcut. Structural-boundary rescheduling still runs.
    var diagnosticPresetLocked: Bool = false

    /// LFPLAN.3: the planned preset id the orchestrator wire last auto-applied on the
    /// current track (`nil` at track start → the first planned segment applies). Lets
    /// `applyLiveUpdate` detect a segment-boundary change and apply the new preset
    /// exactly once. Reset on track change. Guarded by `orchestratorLock`.
    var lastAppliedPlannedPresetID: String?

    /// LFPLAN.3: set when the USER manually picks a preset (cycle or nudge) so the plan
    /// stops auto-applying for the rest of the track and resumes at the next one
    /// (Matt 2026-06-19: "resume next track"). Reset on track change. Guarded by `orchestratorLock`.
    var manualPresetOverrideThisTrack: Bool = false

    /// LFPLAN.4: track-relative time (seconds since this track began) of the last planned
    /// auto-apply, for the min-dwell gate in `applyPlannedSegment`. Reset on track change.
    /// Guarded by `orchestratorLock`.
    var lastPlannedApplyTrackTime: TimeInterval = 0

    // MARK: - Initialization

    // swiftlint:disable cyclomatic_complexity function_body_length
    @MainActor
    init() {
        // Create shared instances up front — these go into both the engine pipeline
        // and the SessionPreparer (local vars used to avoid reading self before phase 2).
        // StemAnalyzer consumes mono stem waveforms output by `StemSeparator`,
        // which always run at the model's native rate (44100 Hz) regardless of
        // tap rate. This is `StemSeparator.modelSampleRate`, not `tapSampleRate`.
        let analyzer = StemAnalyzer(sampleRate: StemSeparator.modelSampleRate)
        let classifier = Self.loadMoodClassifier()

        // Metal setup is required for the app to function — a failure here
        // means the hardware doesn't support Metal at all.
        guard let ctx = try? MetalContext(),
              let buf = try? AudioBuffer(device: ctx.device),
              let fft = try? FFTProcessor(device: ctx.device),
              let lib = try? ShaderLibrary(context: ctx)
        else {
            fatalError("Metal initialization failed — Apple Silicon with Metal 3.1+ required")
        }

        let loader = PresetLoader(device: ctx.device, pixelFormat: ctx.pixelFormat)

        guard let pipe = try? RenderPipeline(
            context: ctx,
            shaderLibrary: lib,
            fftBuffer: fft.magnitudeBuffer.buffer,
            waveformBuffer: buf.metalBuffer
        ) else {
            fatalError("RenderPipeline creation failed")
        }

        if !loader.presets.isEmpty,
           let waveformIndex = loader.selectPreset(named: "Waveform") {
            logger.info("Starting with preset: Waveform (index \(waveformIndex))")
        }

        let sep = Self.loadStemSeparator(device: ctx.device)

        self.context = ctx
        self.audioBuffer = buf
        self.fftProcessor = fft
        self.pipeline = pipe
        self.presetLoader = loader
        self.shaderLibrary = lib
        self.mirPipeline = MIRPipeline()
        // BUG-007.6: internal-Mac-speaker tap-to-output latency calibration.
        // Empirical default from session 2026-05-07T18-21-37Z analysis. Tunable
        // at runtime via `,`/`.` developer shortcuts. AirPods / Bluetooth users
        // will need a higher value; surfaces as a setting in a future increment.
        self.mirPipeline.liveDriftTracker.audioOutputLatencyMs = 50.0
        // CSP.3 (2026-05-27): Ferrofluid Ocean cold-start fix toggle. Reads
        // UserDefaults at app launch; default ON (CSP.3 is the experimental
        // arm of Matt's A/B). To run the off-side without recompiling:
        //   defaults write com.phosphene.app ffoColdStartFixEnabled -bool NO
        // The toggle gates TWO things:
        //   1. MIRPipeline.trackElapsedS writes the real time when ON; 100.0
        //      when OFF (collapses the shader's smoothstep crossfade to the
        //      warm path).
        //   2. resetStemPipeline installs the computed cached bass proportion
        //      when ON; 0.25 (the formula pivot) when OFF (collapses the
        //      shader's one-sided baseline contribution to 0).
        // Together, OFF restores the pre-CSP.3 `1.0 + 0.35*bass_energy_dev`
        // formula exactly. See CLAUDE.md §Cold-Start Phase Contract.
        let ffoColdStartFixEnabled = (UserDefaults.standard
            .object(forKey: "ffoColdStartFixEnabled") as? Bool) ?? true
        self.mirPipeline.ffoColdStartFixEnabled = ffoColdStartFixEnabled
        let tier = Self.detectDeviceTier(device: ctx.device)
        self.murmurationGeometry = Self.makeMurmurationGeometry(context: ctx, library: lib)
        self.filigreeGeometry = Self.makeFiligreeGeometry(context: ctx, library: lib)
        self.mitosisGeometry = Self.makeMitosisGeometry(context: ctx, library: lib)
        self.cytokinesisGeometry = Self.makeCytokinesisGeometry(context: ctx, library: lib)
        self.ricercarGeometry = Self.makeRicercarGeometry(context: ctx, library: lib)
        self.moodClassifier = classifier
        self.stemAnalyzer = analyzer
        self.stemSeparator = sep
        self.sessionRecorder = SessionRecorder()
        // Round 26 (2026-05-15): construct the metadata fetcher early so it
        // can be shared between SessionPreparer (offline prep-time meter
        // override via time_signature) and `makeAudioRouter`'s track-change
        // callback (BPM/key display + late-arriving meter correction). One
        // fetcher, one LRU cache; prep populates the cache for tracks in the
        // playlist, runtime hits the same cache on track-change so the
        // network request from the runtime side is a no-op.
        let metadataFetcher = MetadataPreFetcher(fetchers: Self.buildFetcherList())
        // SessionManager is always created — uses the same component instances as the engine.
        // Ad-hoc mode never invokes the preparer; session mode uses it for pre-analysis.
        self.sessionManager = Self.makeSessionManager(
            sep: sep,
            analyzer: analyzer,
            classifier: classifier,
            device: ctx.device,
            sessionRecorder: self.sessionRecorder,
            metadataFetcher: metadataFetcher
        )
        self.preFetcher = metadataFetcher
        // BUG-006.2 fix (cause 1): wire engine.stemCache to the SessionPreparer's
        // cache instance. The cache reference is stable from init; entries get
        // added as `SessionPreparer.prepare(tracks:)` completes per-track.
        // Before this assignment, every `resetStemPipeline(for:)` call took the
        // cache-miss branch and the prepared BeatGrid never installed.
        self.stemCache = self.sessionManager.cache

        // LF.3 / D-130: stand up the persistent disk-backed cache used
        // by the LF preparation path (consumed by VisualizerEngine+LocalFilePlayback.swift
        // through the `LocalFilePreparing` delegate). Defaults to
        // `~/Library/Application Support/Phosphene/StemCache/`. Failure
        // to create the directory leaves `persistentStemCache = nil`
        // and the LF path falls through to the in-memory-only flow.
        do {
            self.persistentStemCache = try PersistentStemCache()
        } catch {
            let msg = error.localizedDescription
            logger.warning(
                "[LF.3] PersistentStemCache init failed: \(msg, privacy: .public) — disk cache disabled"
            )
            self.persistentStemCache = nil
        }
        // LF.4: prime the menu cache-size publisher.
        self.localFileCacheBytes = self.persistentStemCache?.totalBytes() ?? 0

        // Wire the frame-budget governor and ML dispatch scheduler. Read QualityCeiling
        // from UserDefaults to determine if ultra mode (recording) disables both. D-057(d), D-059(d).
        let qualityCeilingRaw = UserDefaults.standard.string(
            forKey: "phosphene.settings.visuals.qualityCeiling"
        )
        let isUltra = qualityCeilingRaw == "ultra"
        self.deviceTier = tier
        pipe.frameBudgetManager = FrameBudgetManager(deviceTier: tier, qualityCeilingIsUltra: isUltra)
        // CLEAN.4.6: seed the quality floor in case the app launches already under thermal
        // pressure or Low Power Mode (the observer only fires on subsequent changes).
        pipe.frameBudgetManager?.setThermalFloor(
            FrameBudgetManager.qualityFloor(
                thermalState: ProcessInfo.processInfo.thermalState,
                lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled
            )
        )
        self.mlDispatchScheduler = MLDispatchScheduler(deviceTier: tier, qualityCeilingIsUltra: isUltra)

        setupCaptureHook(pipe: pipe, ctx: ctx)
        setupBackgroundTextures(pipe: pipe, ctx: ctx, lib: lib)
        setupDashboardSnapshotPump(pipe: pipe)

        loader.onPresetsReloaded = { [weak self] in
            guard let self, let current = self.presetLoader.currentPreset else { return }
            self.applyPreset(current)
            self.showPresetName(current.descriptor.name)
        }

        if #available(macOS 14.2, *) {
            self.router = setupAudioRouting(audioBuffer: buf, fftProcessor: fft)
        }

        // LF.4: SessionManager delegates the heavy ML pipeline back to the
        // engine via the `LocalFilePreparing` protocol. Wired here, post-init,
        // because SessionManager was constructed before `self` was fully
        // available. The weak reference lets SessionManager survive engine
        // teardown cleanly.
        sessionManager.localFilePreparer = self

        // LF.6.streaming-S5: assemble the streaming-side artwork publisher.
        // Built post-phase-2 so the publish closure can `[weak self]`-capture
        // and write `currentTrackArtworkData` on the MainActor.
        self.streamingArtworkPublisher = StreamingArtworkPublisher(
            resolver: streamingArtworkResolver,
            fetcher: streamingArtworkFetcher,
            diskCache: streamingArtworkDiskCache,
            publish: { [weak self] data in
                self?.currentTrackArtworkData = data
            }
        )

        // Trigger plan construction whenever the session reaches .ready.
        // For LF sessions (`currentSource.isLocalFile`), `handleLocalFileReady()`
        // installs the cached BeatGrid + starts the LF audio router + advances
        // the session to `.playing` directly. For streaming sessions, `buildPlan()`
        // produces the planned-session structure.
        // Also reset currentSessionPlanSeed on .connecting so each session gets a fresh seed.
        let mgr = sessionManager
        stateCancellable = mgr.$state
            .sink { [weak self] newState in
                guard let self else { return }
                if newState == .connecting {
                    self.currentSessionPlanSeed = nil
                    // LF.6.fix.1 (BUG-024): wipe stale LF artwork at session
                    // boundary so a streaming session starting after an LF
                    // session doesn't briefly render the prior track's
                    // cached artwork before the first streaming track-change
                    // callback fires. Defense-in-depth with the per-track
                    // clear at VisualizerEngine+Capture.swift:190.
                    // LF.6.streaming-S5: also cancel any in-flight streaming
                    // fetch from the prior session so a slow CDN response
                    // can never land on the new session's chrome.
                    self.streamingArtworkPublisher?.update(for: nil)
                    self.currentTrackArtworkData = nil
                }
                if newState == .preparing {
                    // LF.5.fix.3-C: each new session entry clears the
                    // duplicate-emission guard so the next `.ready` for a
                    // genuinely new URL proceeds normally. Within a session,
                    // .preparing → .ready → .playing is once-and-done; the
                    // field remains nil until handleLocalFileReady commits it.
                    self.lastStartedLocalFilePlaybackURL = nil
                }
                if newState == .ready {
                    if self.sessionManager.currentSource?.isLocalFile == true {
                        self.handleLocalFileReady()
                    } else {
                        self.buildPlan()
                    }
                }
                if newState == .ended {
                    // LF.5.fix.2-FU2: halt the stem analyzer timer BEFORE
                    // stopping the audio router. The timer fires every 5 s
                    // and drains the stem lookahead buffer; without this
                    // call the analyzer kept running for ~60-120 s after
                    // Stop on the verification session 2026-05-28T19-42-50Z
                    // (12 separations on stale / silence frames). Cancelling
                    // first means no further dispatch lands after the audio
                    // router teardown.
                    self.stopStemPipeline()
                    // LF.5.fix D-LF5-2: Phosphene IS the player for local-file
                    // sessions, so End Session must actually stop audio. For
                    // streaming sessions stop() also tears down the Core Audio
                    // process tap (correct behaviour at session end — the
                    // streaming app keeps playing, Phosphene stops analysing).
                    // Either way, idempotent + safe.
                    if #available(macOS 14.2, *), let audioRouter = self.router as? AudioInputRouter {
                        audioRouter.stop()
                    }
                    // LF.5.fix D-LF5-3: reset transport state so a new session
                    // (or a re-open of the same file) doesn't inherit a stale
                    // paused flag.
                    self.isLocalFilePaused = false
                    // LF.5.fix.3-C: release the URL marker so a re-open of
                    // the same file starts cleanly.
                    self.lastStartedLocalFilePlaybackURL = nil
                }
            }

        // GAP H (2026-05-28): stash the most recent LF SessionOrigin across
        // endSession so EndedView can offer a "Play <name> again" CTA. The
        // observer overrides on every LF emit (preserves the latest LF
        // source). A streaming-session emit clears it (the next EndedView
        // for that session shouldn't suggest replaying an unrelated LF
        // source). A nil emit (during endSession) is intentionally ignored
        // — that's exactly the moment we want to preserve.
        lastLocalFileSourceCancellable = mgr.$currentSource
            .removeDuplicates()
            .sink { [weak self] source in
                guard let self else { return }
                switch source {
                case .localFile, .localFiles, .localFolder, .localPlaylist:
                    self.lastEndedLocalFileOrigin = source
                case .playlist:
                    self.lastEndedLocalFileOrigin = nil
                case .none:
                    break                          // preserve stash through endSession
                }
            }

        // Extend the plan as background preparation makes more tracks available.
        // Only fires when livePlan is already set (i.e. buildPlan() has run).
        readinessCancellable = mgr.$progressiveReadinessLevel
            .dropFirst()
            .sink { [weak self] _ in
                guard let self else { return }
                let inActiveSession = self.sessionManager.state == .ready
                    || self.sessionManager.state == .playing
                guard inActiveSession else { return }
                guard self.orchestratorLock.withLock({ self.livePlan }) != nil else { return }
                self.extendPlan()
            }

        setupTerminationObserver()
        setupThermalGovernorObserver()

        BUG012Probe.recordVisualizerEngineInit()
    }
    // swiftlint:enable cyclomatic_complexity function_body_length

    /// BUG-012 instrumentation — record VisualizerEngine teardown. If a crash
    /// fires during teardown, the deinit log line lands in `session.log`
    /// before the process exits and gives a clear "we were dying when this
    /// crashed" signal. Remove once BUG-012 closes.
    deinit {
        BUG012Probe.recordVisualizerEngineDeinit()
        diagLog?.closeFile()   // CLEAN.3.5: release the ~/phosphene_diag.log handle
    }

    /// Build the flock used by the Murmuration preset — the **3D version of the
    /// proven parametric-ellipse flock** (`Murmuration3DGeometry` +
    /// `Murmuration3D.metal`), 2026-06-04.
    ///
    /// This realises the uplift's actual goal — a *3D* murmuration — by lifting the
    /// 40-round 2D architecture (birds spring-pulled to home slots in a morphing
    /// ellipse → dense, coherent, framed by construction) into 3D with perspective
    /// depth and real banking (the rolling dark bands), rather than the emergent
    /// GPU-boids redesign that failed across many M7 rounds (sparse, spraying,
    /// off-canvas — control is what a murmuration preset needs, not pure emergence).
    /// Returns `any ParticleGeometry` (D-097, siblings not subclasses).
    private static func makeMurmurationGeometry(
        context: MetalContext,
        library: Renderer.ShaderLibrary
    ) -> (any ParticleGeometry)? {
        guard let flock = try? Murmuration3DGeometry(
            device: context.device,
            library: library.library,
            configuration: Murmuration3DConfiguration(),
            pixelFormat: context.pixelFormat
        ) else {
            return nil
        }
        logger.info("Murmuration created: 3D parametric-ellipse flock (\(Murmuration3DConfiguration().particleCount) birds)")
        return flock
    }

    /// Build the physarum agent-network for the Filigree preset
    /// (`PhysarumGeometry` + `Physarum.metal`, PHYS.2). Returns
    /// `any ParticleGeometry` (D-097, siblings not subclasses).
    private static func makeFiligreeGeometry(
        context: MetalContext,
        library: Renderer.ShaderLibrary
    ) -> (any ParticleGeometry)? {
        guard let web = try? PhysarumGeometry(
            device: context.device,
            library: library.library,
            configuration: PhysarumConfiguration(),
            pixelFormat: context.pixelFormat
        ) else {
            return nil
        }
        logger.info("Filigree created: physarum agent-network (\(PhysarumConfiguration().agentCount) agents)")
        return web
    }

    /// Build the reaction–diffusion cell colony for the Mitosis preset
    /// (`MitosisGeometry` + `Mitosis.metal`, MITOSIS.1). Returns
    /// `any ParticleGeometry` (D-097, siblings not subclasses).
    private static func makeMitosisGeometry(
        context: MetalContext,
        library: Renderer.ShaderLibrary
    ) -> (any ParticleGeometry)? {
        guard let colony = try? MitosisGeometry(
            device: context.device,
            library: library.library,
            configuration: MitosisConfiguration(),
            pixelFormat: context.pixelFormat
        ) else {
            return nil
        }
        let cfg = MitosisConfiguration()
        logger.info("Mitosis created: reaction–diffusion cell colony (\(cfg.width)×\(cfg.height) sim)")
        return colony
    }

    /// Build the detailed fluorescence-microscopy cell-division geometry for the
    /// Cytokinesis preset (`MitosisGen2Geometry` + `MitosisGen2.metal`, MITOSIS-G2.1).
    /// Returns `any ParticleGeometry` (D-097, siblings not subclasses).
    private static func makeCytokinesisGeometry(
        context: MetalContext,
        library: Renderer.ShaderLibrary
    ) -> (any ParticleGeometry)? {
        guard let cells = try? MitosisGen2Geometry(
            device: context.device,
            library: library.library,
            configuration: MitosisGen2Configuration(),
            pixelFormat: context.pixelFormat
        ) else {
            return nil
        }
        logger.info("Cytokinesis created: detailed explicit-cell division (Mitosis gen-2)")
        return cells
    }

    /// Build the fluid dye simulation + glow-ribbon geometry for the Ricercar
    /// preset (Fantasia rebuild — `RicercarFluidGeometry` + `RicercarFluid.metal`,
    /// RICERCAR-FL). Returns `any ParticleGeometry` (D-097, siblings not subclasses).
    private static func makeRicercarGeometry(
        context: MetalContext,
        library: Renderer.ShaderLibrary
    ) -> (any ParticleGeometry)? {
        guard let fluid = try? RicercarFluidGeometry(
            device: context.device,
            library: library.library,
            pixelFormat: context.pixelFormat
        ) else {
            return nil
        }
        logger.info("Ricercar created: Stam stable-fluids dye sim + glow ribbons (Fantasia rebuild)")
        return fluid
    }

    /// Resolve a particle-preset name to the geometry conformer the engine
    /// has built for it. Returns `nil` for any unknown preset name; the
    /// caller is expected to log + fall through. Exposed as `internal` so
    /// `applyPreset .particles:` and `ParticleDispatchResolutionTests` share
    /// a single mapping (D-097).
    func resolveParticleGeometry(forPresetName name: String) -> (any ParticleGeometry)? {
        switch name {
        case "Murmuration": return murmurationGeometry
        case "Filigree":    return filigreeGeometry
        case "Mitosis":     return mitosisGeometry
        case "Cytokinesis": return cytokinesisGeometry
        case "Ricercar":    return ricercarGeometry
        default:            return nil
        }
    }

    /// Load the mood classifier.
    private static func loadMoodClassifier() -> MoodClassifier {
        let classifier = MoodClassifier()
        logger.info("MoodClassifier loaded")
        return classifier
    }
}
