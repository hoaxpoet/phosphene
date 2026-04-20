// VisualizerEngine — Audio capture → FFT → MIR analysis → renderer pipeline owner.
//
// Created once at app launch by ContentView via @StateObject. Audio capture
// starts on first appear after verifying screen capture permission.

import Audio
import CoreGraphics
import DSP
import Foundation
import ML
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
    private var router: Any?

    /// Metadata pre-fetcher for external API queries.
    var preFetcher: MetadataPreFetcher?

    // MARK: - Stem Pipeline

    /// Session manager that coordinates playlist preparation. Set by the app
    /// layer before playback; exposes `cache` which is wired to `stemCache`
    /// when the session reaches `.ready`.
    var sessionManager: SessionManager?

    /// Pre-analyzed stem data from session preparation. Set by the app layer
    /// after `SessionPreparer.prepare(tracks:)` completes. When non-nil, each
    /// track change loads cached stems instead of waiting for live separation.
    var stemCache: StemCache?

    /// Stem separator (CoreML on ANE).
    let stemSeparator: StemSeparator?

    /// Ring buffer accumulating interleaved stereo PCM for stem separation.
    let stemSampleBuffer = StemSampleBuffer(sampleRate: 44100, maxSeconds: 15)

    /// Per-stem energy + beat analysis.
    let stemAnalyzer = StemAnalyzer(sampleRate: 44100)

    /// Background queue for stem separation (utility QoS — never blocks render).
    let stemQueue = DispatchQueue(label: "com.phosphene.stemSeparator", qos: .utility)

    /// Repeating timer that triggers stem separation every 5 seconds.
    var stemTimer: DispatchSourceTimer?

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
    private var hideNameTask: Task<Void, Never>?

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

    // MARK: - Initialization

    init() {
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

        self.context = ctx
        self.audioBuffer = buf
        self.fftProcessor = fft
        self.pipeline = pipe
        self.presetLoader = loader
        self.shaderLibrary = lib
        self.mirPipeline = MIRPipeline()
        self.particleGeometry = Self.makeParticleGeometry(context: ctx, library: lib)
        self.moodClassifier = Self.loadMoodClassifier()
        self.stemSeparator = Self.loadStemSeparator(device: ctx.device)
        self.sessionRecorder = SessionRecorder()

        // Wire per-frame capture hook: blit the drawable into a shared-storage
        // capture texture inside the command buffer, then read it in the buffer's
        // completion handler and hand to the recorder.
        if let recorder = self.sessionRecorder {
            let device = ctx.device
            pipe.onFrameRendered = { [weak recorder] drawableTex, features, stems, commandBuffer in
                guard let recorder = recorder else { return }
                // Skip video blit if the drawable is framebufferOnly (cannot be
                // read back). MetalView sets framebufferOnly=false, but defend
                // against future config changes rather than crashing at the
                // blit validation layer.
                let canBlit = !drawableTex.isFramebufferOnly
                                && drawableTex.width > 0
                                && drawableTex.height > 0
                if canBlit,
                   let captureTex = recorder.ensureCaptureTexture(
                        device: device,
                        width: drawableTex.width,
                        height: drawableTex.height,
                        pixelFormat: drawableTex.pixelFormat),
                   let blit = commandBuffer.makeBlitCommandEncoder() {
                    blit.copy(from: drawableTex, to: captureTex)
                    blit.endEncoding()
                }
                // Always record CSV rows; recorder reads its own capture texture.
                commandBuffer.addCompletedHandler { [weak recorder] _ in
                    recorder?.recordFrame(features: features, stems: stems)
                }
            }
        }

        // Generate noise textures in the background — the pipeline renders correctly
        // without them (shaders that don't sample noise work as before), so startup
        // isn't blocked.  setTextureManager is thread-safe.
        DispatchQueue.global(qos: .userInitiated).async {
            if let tm = try? TextureManager(context: ctx, shaderLibrary: lib) {
                pipe.setTextureManager(tm)
            } else {
                logger.warning("TextureManager init failed — noise textures unavailable")
            }
        }

        // Generate IBL environment textures (irradiance cubemap, prefiltered env, BRDF LUT)
        // in the background — ray march presets fall back to minimum ambient without them,
        // but glass and polished-metal materials require IBL for correct specular appearance.
        // setIBLManager is thread-safe.
        DispatchQueue.global(qos: .userInitiated).async {
            if let ibl = try? IBLManager(context: ctx, shaderLibrary: lib) {
                pipe.setIBLManager(ibl)
            } else {
                logger.warning("IBLManager init failed — IBL textures unavailable for ray march presets")
            }
        }

        loader.onPresetsReloaded = { [weak self] in
            guard let self, let current = self.presetLoader.currentPreset else { return }
            self.applyPreset(current)
            self.showPresetName(current.descriptor.name)
        }

        if #available(macOS 14.2, *) {
            self.router = setupAudioRouting(audioBuffer: buf, fftProcessor: fft)
        }

        // Finalize the video writer when the app is about to quit. Without
        // this the MP4 `moov` atom is never written and video.mp4 is
        // unplayable (ffprobe reports "moov atom not found"). The CSVs and
        // WAVs are written line-by-line and are unaffected.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.sessionRecorder?.finish()
        }
    }

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

    // MARK: - Public API

    /// Start audio capture and metadata observation.
    func startAudio() {
        // Start metadata observation unconditionally — AppleScript queries
        // music apps directly via Automation, no screen capture permission needed.
        if #available(macOS 14.2, *), let audioRouter = router as? AudioInputRouter {
            audioRouter.startMetadataOnly()
        }

        // Screen capture permission is only needed for Core Audio taps (audio capture).
        var permitted = CGPreflightScreenCaptureAccess()
        if !permitted {
            permitted = CGRequestScreenCaptureAccess()
        }
        hasScreenCapturePermission = permitted

        if permitted {
            startAudioCapture()
            startStemPipeline()
        } else {
            logger.info("Screen capture denied — grant in System Settings for audio capture")
            pollForScreenCapturePermission()
        }

        if let current = presetLoader.currentPreset {
            applyPreset(current)
            showPresetName(current.descriptor.name)
        }
    }

    /// Poll until screen capture permission is granted, then start audio capture.
    private func pollForScreenCapturePermission() {
        Task { @MainActor in
            while !hasScreenCapturePermission {
                try? await Task.sleep(for: .seconds(2))
                if CGPreflightScreenCaptureAccess() {
                    hasScreenCapturePermission = true
                    logger.info("Screen capture permission granted")
                    startAudioCapture()
                    startStemPipeline()
                    break
                }
            }
        }
    }

    /// Start Core Audio tap capture (requires screen capture permission).
    private func startAudioCapture() {
        if #available(macOS 14.2, *), let audioRouter = router as? AudioInputRouter {
            do {
                try audioRouter.start(mode: .systemAudio)
                logger.info("Audio capture started")
            } catch {
                logger.error("Audio capture failed: \(error)")
            }
        }
    }

    // MARK: - Toggles

    /// Toggle the debug metadata overlay.
    func toggleDebugOverlay() {
        showDebugOverlay.toggle()
    }

    // MARK: - Private Helpers

    /// Briefly display the preset name, then fade it out after 2 seconds.
    func showPresetName(_ name: String) {
        hideNameTask?.cancel()
        currentPresetName = name
        sessionRecorder?.log("preset → \(name)")
        hideNameTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.5)) {
                currentPresetName = nil
            }
        }
    }
}
