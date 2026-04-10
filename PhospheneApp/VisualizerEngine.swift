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
    private let presetLoader: PresetLoader

    /// MIR feature extraction pipeline (spectral, energy, chroma, beat).
    let mirPipeline: MIRPipeline

    /// CoreML mood classifier (valence/arousal on ANE).
    let moodClassifier: MoodClassifier?

    /// GPU compute particle system — attached to feedback presets only.
    private var particleGeometry: ProceduralGeometry?

    /// AudioInputRouter requires macOS 14.2+; stored as Any to avoid propagating availability.
    private var router: Any?

    /// Metadata pre-fetcher for external API queries.
    var preFetcher: MetadataPreFetcher?

    // MARK: - Stem Pipeline

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

    /// Whether MIR recording is active.
    var mirPipelineIsRecording: Bool { mirPipeline.isRecording }

    // MARK: - Capture/Recording State

    /// Feature capture file handle.
    var captureHandle: FileHandle?

    /// Path to the current capture file.
    var captureFilePath: String?

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
        self.mirPipeline = MIRPipeline()
        self.particleGeometry = Self.makeParticleGeometry(context: ctx, library: lib)
        self.moodClassifier = Self.loadMoodClassifier()
        self.stemSeparator = Self.loadStemSeparator(device: ctx.device)

        loader.onPresetsReloaded = { [weak self] in
            guard let self, let current = self.presetLoader.currentPreset else { return }
            self.applyPreset(current)
            self.showPresetName(current.descriptor.name)
        }

        if #available(macOS 14.2, *) {
            self.router = setupAudioRouting(audioBuffer: buf, fftProcessor: fft)
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
        logger.info("Particle system created: 500K particles (attached per-preset)")
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

    // MARK: - Preset Cycling

    /// Advance to the next preset and update the pipeline.
    func nextPreset() {
        guard let preset = presetLoader.nextPreset() else { return }
        applyPreset(preset)
        showPresetName(preset.descriptor.name)
    }

    /// Go back to the previous preset and update the pipeline.
    func previousPreset() {
        guard let preset = presetLoader.previousPreset() else { return }
        applyPreset(preset)
        showPresetName(preset.descriptor.name)
    }

    /// Apply a preset to the render pipeline, including feedback and particle configuration.
    private func applyPreset(_ preset: PresetLoader.LoadedPreset) {
        let desc = preset.descriptor
        pipeline.setActivePipelineState(preset.pipelineState)

        if desc.useFeedback, let fbPipeline = preset.feedbackPipelineState {
            let params = FeedbackParams(
                decay: desc.decay,
                baseZoom: desc.baseZoom,
                baseRot: desc.baseRot,
                beatZoom: desc.beatZoom,
                beatRot: desc.beatRot,
                beatSensitivity: desc.beatSensitivity
            )
            pipeline.setFeedbackParams(params)
            pipeline.setFeedbackComposePipeline(fbPipeline)
            // Attach particles only for presets that declare use_particles in their JSON.
            pipeline.setParticleGeometry(desc.useParticles ? particleGeometry : nil)
        } else {
            pipeline.setFeedbackParams(nil)
            pipeline.setFeedbackComposePipeline(nil)
            // Detach particles — non-feedback presets don't use compute particles.
            pipeline.setParticleGeometry(nil)
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
    private func showPresetName(_ name: String) {
        hideNameTask?.cancel()
        currentPresetName = name
        hideNameTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.5)) {
                currentPresetName = nil
            }
        }
    }

}
