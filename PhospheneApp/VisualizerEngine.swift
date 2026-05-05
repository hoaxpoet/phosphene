// swiftlint:disable file_length
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

    /// Whether uncertified presets are eligible for reactive-mode selection.
    /// Mirrors `SettingsStore.showUncertifiedPresets`; pushed via `applyShowUncertifiedPresets(_:)`.
    var showUncertifiedPresets: Bool = false

    /// Current track metadata from Now Playing.
    @Published var currentTrack: TrackMetadata?

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
    /// via `setMeshPresetTick` / `setMeshPresetBuffer` in `applyPreset`.
    var arachneState: ArachneState?

    /// Latest bass stem attack ratio — updated each per-frame stem analysis pass,
    /// forwarded into MIRDiagnostics for the spider debug overlay.
    var latestBassAttackRatio: Float = 0

    /// Gossamer wave-pool state — allocated when the Gossamer preset is active,
    /// nil otherwise. Tick closure and waveBuffer are wired into the render pipeline
    /// via `setMeshPresetTick` / `setDirectPresetFragmentBuffer` in `applyPreset`.
    var gossamerState: GossamerState?

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

    /// CoreML mood classifier (valence/arousal on ANE).
    let moodClassifier: MoodClassifier?

    /// GPU compute particle system — attached to feedback presets only.
    var particleGeometry: ProceduralGeometry?

    /// Shader library for creating post-process chains on preset switch.
    let shaderLibrary: Renderer.ShaderLibrary

    /// AudioInputRouter requires macOS 14.2+; stored as Any to avoid propagating availability.
    var router: Any?

    /// Metadata pre-fetcher for external API queries.
    var preFetcher: MetadataPreFetcher?

    // MARK: - Device Tier

    /// GPU capability tier: .tier1 (M1/M2) or .tier2 (M3/M4).
    /// Drives per-tier defaults for FrameBudgetManager and MLDispatchScheduler.
    let deviceTier: DeviceTier

    // MARK: - Stem Pipeline

    /// Session manager that coordinates playlist preparation. Created at init;
    /// exposes `cache` which is wired to `stemCache` when the session reaches `.ready`.
    var sessionManager: SessionManager

    /// Pre-analyzed stem data from session preparation. Set by the app layer
    /// after `SessionPreparer.prepare(tracks:)` completes. When non-nil, each
    /// track change loads cached stems instead of waiting for live separation.
    var stemCache: StemCache?

    /// Stem separator (CoreML on ANE).
    let stemSeparator: StemSeparator?

    /// Ring buffer accumulating interleaved stereo PCM for stem separation.
    let stemSampleBuffer = StemSampleBuffer(sampleRate: 44100, maxSeconds: 15)

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

    /// Seeded LCG perturbation value shared between `buildPlan()` and `extendPlan()`.
    /// Reset to nil when a new session begins (`.connecting` state), so each session
    /// gets a fresh random seed while `extendPlan()` reuses the same one.
    var currentSessionPlanSeed: UInt64?

    /// Wall-clock timestamp of the first reactive `applyLiveUpdate()` call.
    /// Set on entry, reset to nil when `buildPlan()` succeeds (real plan takes over).
    var reactiveSessionStart: Date?

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

    // MARK: - Capture-Mode Switch Grace Window

    // MARK: - CaptureModeSwitchEngineInterface conformance (see CaptureModeSwitchCoordinator.swift)

    /// Wall-clock time at which the current capture-mode switch grace window expires.
    ///
    /// Set by `CaptureModeSwitchCoordinator` at the start of a live mode switch.
    /// The orchestrator's mood-override path checks this before applying a preset
    /// override, so a silence-derived mood divergence during the brief tap restart
    /// can't prematurely yank the user to a different preset. D-061(b).
    var captureModeSwitchGraceWindowEndsAt: Date?

    /// Returns `true` while a capture-mode switch grace window is active.
    var isCaptureModeSwitchGraceActive: Bool {
        guard let ends = captureModeSwitchGraceWindowEndsAt else { return false }
        return Date() < ends
    }

    /// Session-relative time of the last reactive preset switch.
    /// Prevents switching more often than once per 60 seconds.
    var lastReactiveSwitchTime: TimeInterval = -.infinity

    // MARK: - Initialization

    // swiftlint:disable cyclomatic_complexity function_body_length
    @MainActor
    init() {
        // Create shared instances up front — these go into both the engine pipeline
        // and the SessionPreparer (local vars used to avoid reading self before phase 2).
        let analyzer = StemAnalyzer(sampleRate: 44100)
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
        self.particleGeometry = Self.makeParticleGeometry(context: ctx, library: lib)
        self.moodClassifier = classifier
        self.stemAnalyzer = analyzer
        self.stemSeparator = sep
        self.sessionRecorder = SessionRecorder()
        // SessionManager is always created — uses the same component instances as the engine.
        // Ad-hoc mode never invokes the preparer; session mode uses it for pre-analysis.
        self.sessionManager = Self.makeSessionManager(sep: sep, analyzer: analyzer, classifier: classifier, device: ctx.device)

        // Wire the frame-budget governor and ML dispatch scheduler. Read QualityCeiling
        // from UserDefaults to determine if ultra mode (recording) disables both. D-057(d), D-059(d).
        let tier = Self.detectDeviceTier(device: ctx.device)
        let qualityCeilingRaw = UserDefaults.standard.string(
            forKey: "phosphene.settings.visuals.qualityCeiling"
        )
        let isUltra = qualityCeilingRaw == "ultra"
        self.deviceTier = tier
        pipe.frameBudgetManager = FrameBudgetManager(deviceTier: tier, qualityCeilingIsUltra: isUltra)
        self.mlDispatchScheduler = MLDispatchScheduler(deviceTier: tier, qualityCeilingIsUltra: isUltra)

        setupCaptureHook(pipe: pipe, ctx: ctx)
        setupBackgroundTextures(pipe: pipe, ctx: ctx, lib: lib)

        loader.onPresetsReloaded = { [weak self] in
            guard let self, let current = self.presetLoader.currentPreset else { return }
            self.applyPreset(current)
            self.showPresetName(current.descriptor.name)
        }

        if #available(macOS 14.2, *) {
            self.router = setupAudioRouting(audioBuffer: buf, fftProcessor: fft)
        }

        // Trigger plan construction whenever the session reaches .ready.
        // Also reset currentSessionPlanSeed on .connecting so each session gets a fresh seed.
        let mgr = sessionManager
        stateCancellable = mgr.$state
            .sink { [weak self] newState in
                guard let self else { return }
                if newState == .connecting { self.currentSessionPlanSeed = nil }
                if newState == .ready { self.buildPlan() }
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
    }
    // swiftlint:enable cyclomatic_complexity function_body_length

    /// Build the GPU particle system used by the Murmuration preset.
    /// Quality of movement over quantity — each bird should be visible.
    private static func makeParticleGeometry(
        context: MetalContext,
        library: Renderer.ShaderLibrary
    ) -> ProceduralGeometry? {
        guard let particles = try? ProceduralGeometry(
            device: context.device,
            library: library.library,
            configuration: ParticleConfiguration(
                particleCount: 5_000,
                decayRate: 0.0,     // Birds don't die — they're always alive.
                burstThreshold: 0.4, // Only strong beats trigger scatter.
                burstVelocity: 1.0,  // Not used (flocking, not explosions).
                drag: 0.8            // Light air drag — birds glide.
            ),
            pixelFormat: context.pixelFormat
        ) else {
            return nil
        }
        logger.info("Particle system created: 5K particles (attached per-preset)")
        return particles
    }

    /// Load the mood classifier.
    private static func loadMoodClassifier() -> MoodClassifier {
        let classifier = MoodClassifier()
        logger.info("MoodClassifier loaded")
        return classifier
    }
}

// MARK: - CaptureModeSwitchEngineInterface

extension VisualizerEngine: CaptureModeSwitchEngineInterface {
    // captureModeSwitchGraceWindowEndsAt is declared in VisualizerEngine.swift — no body needed.
}
