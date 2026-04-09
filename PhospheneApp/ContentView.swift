// ContentView — Main visualizer view with keyboard-driven preset navigation.

import Audio
import CoreGraphics
import DSP
import ML
import os.log
import Presets
import Renderer
import Shared
import SwiftUI

private let logger = Logger(subsystem: "com.phosphene.app", category: "ContentView")

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

// MARK: - ContentView

/// Root view displaying the Metal visualizer with a preset name overlay.
///
/// Keyboard controls:
/// - Right arrow / Space: next preset
/// - Left arrow: previous preset
struct ContentView: View {
    @StateObject private var engine = VisualizerEngine()

    var body: some View {
        ZStack {
            MetalView(context: engine.context, pipeline: engine.pipeline)

            if let name = engine.currentPresetName {
                Text(name)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
                    .padding(8)
                    .background(.black.opacity(0.4))
                    .cornerRadius(6)
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }

            // Debug overlay — toggle with 'D' key.
            if engine.showDebugOverlay {
                DebugOverlayView(engine: engine)
            }
        }
        .focusable()
        .frame(minWidth: 800, minHeight: 600)
        .onAppear {
            engine.startAudio()
        }
        .onKeyPress(.rightArrow) {
            engine.nextPreset()
            return .handled
        }
        .onKeyPress(.leftArrow) {
            engine.previousPreset()
            return .handled
        }
        .onKeyPress(.space) {
            engine.nextPreset()
            return .handled
        }
        .onKeyPress("d") {
            engine.toggleDebugOverlay()
            return .handled
        }
        .onKeyPress("c") {
            engine.toggleCapture()
            return .handled
        }
        .onKeyPress("r") {
            engine.toggleRecording()
            return .handled
        }
    }
}

// MARK: - VisualizerEngine

/// Owns the audio capture → FFT → renderer pipeline.
///
/// Created once at app launch via `@StateObject`. Audio capture starts
/// on first appear after verifying screen capture permission.
final class VisualizerEngine: ObservableObject, @unchecked Sendable {

    // MARK: - Properties

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
    private let mirPipeline: MIRPipeline

    /// CoreML mood classifier (valence/arousal on ANE).
    private let moodClassifier: MoodClassifier?

    /// GPU compute particle system — attached to feedback presets only.
    private var particleGeometry: ProceduralGeometry?

    /// AudioInputRouter requires macOS 14.2+; stored as Any to avoid propagating availability.
    private var router: Any?

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

    /// Whether MIR recording is active.
    var mirPipelineIsRecording: Bool { mirPipeline.isRecording }

    /// Whether feature capture is active (toggle with 'C' key).
    @Published var isCapturing = false

    /// Feature capture file handle.
    private var captureHandle: FileHandle?



    /// Path to the current capture file.
    private(set) var captureFilePath: String?

    /// Whether screen capture permission has been granted.
    @Published var hasScreenCapturePermission = false

    /// Task that hides the preset name after a delay.
    private var hideNameTask: Task<Void, Never>?

    /// Metadata pre-fetcher for external API queries.
    private var preFetcher: MetadataPreFetcher?

    // MARK: - Analysis State
    //
    // These are accessed from the background analysis queue via the audio
    // callback. The class is `@unchecked Sendable` and the mutations happen
    // only on the serial `analysisQueue`, so there is no data race.

    /// Running frame count for the analysis queue.
    private var analysisFrameCount = 0

    /// 10-second EMA accumulator matching DEAM's track-level feature averages.
    private var accumulatedFeatures = [Float](repeating: 0, count: 10)

    /// Whether `accumulatedFeatures` has been seeded with the first frame.
    private var featureAccumInitialized = false

    /// Timestamp of the last analysis frame (for dt / effective fps).
    private var lastAnalysisTime: CFAbsoluteTime = 0

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

        if !loader.presets.isEmpty {
            if let waveformIndex = loader.selectPreset(named: "Waveform") {
                logger.info("Starting with preset: Waveform (index \(waveformIndex))")
            }
        }

        self.context = ctx
        self.audioBuffer = buf
        self.fftProcessor = fft
        self.pipeline = pipe
        self.presetLoader = loader
        self.mirPipeline = MIRPipeline()

        // Create GPU particle system — a few thousand birds for the Murmuration preset.
        // Quality of movement over quantity. Each bird should be visible.
        if let particles = try? ProceduralGeometry(
            device: ctx.device,
            library: lib.library,
            configuration: ParticleConfiguration(
                particleCount: 5_000,
                decayRate: 0.0,     // Birds don't die — they're always alive.
                burstThreshold: 0.4, // Only strong beats trigger scatter.
                burstVelocity: 1.0,  // Not used (flocking, not explosions).
                drag: 0.8            // Light air drag — birds glide.
            ),
            pixelFormat: ctx.pixelFormat
        ) {
            self.particleGeometry = particles
            logger.info("Particle system created: 500K particles (attached per-preset)")
        }

        do {
            self.moodClassifier = try MoodClassifier()
            logger.info("MoodClassifier loaded")
        } catch {
            self.moodClassifier = nil
            logger.error("MoodClassifier failed to load: \(error)")
        }

        loader.onPresetsReloaded = { [weak self] in
            guard let self, let current = self.presetLoader.currentPreset else { return }
            self.applyPreset(current)
            self.showPresetName(current.descriptor.name)
        }

        if #available(macOS 14.2, *) {
            self.router = setupAudioRouting(audioBuffer: buf, fftProcessor: fft)
        }
    }

    /// Set up audio routing, MIR analysis, mood classification, and metadata pre-fetching.
    @available(macOS 14.2, *)
    private func setupAudioRouting(
        audioBuffer buf: AudioBuffer,
        fftProcessor fft: FFTProcessor
    ) -> AudioInputRouter {
        let metadata = StreamingMetadata()
        let audioRouter = AudioInputRouter(metadata: metadata)
        let mir = self.mirPipeline
        let mood = self.moodClassifier

        // Create diagnostic log file.
        let diagPath = NSHomeDirectory() + "/phosphene_diag.log"
        FileManager.default.createFile(atPath: diagPath, contents: nil)
        let diagLog = FileHandle(forWritingAtPath: diagPath)

        let analysisQueue = DispatchQueue(label: "com.phosphene.analysis", qos: .userInteractive)

        // 10-second EMA accumulator for features fed to the mood classifier.
        // Matches DEAM's track-level average feature distribution.
        // At ~94 callbacks/s, alpha=0.01 gives ~7s effective window.
        let featureEmaAlpha: Float = 0.01
        self.lastAnalysisTime = CFAbsoluteTimeGetCurrent()

        // Audio callback: buffer write + FFT only (real-time safe).
        // MIR + mood classification dispatched to a background queue.
        audioRouter.onAudioSamples = { [weak self, weak buf, weak fft] samples, count, rate, _ in
            guard let buf, let fft else { return }
            buf.write(from: samples, count: count)
            let latest = buf.latestSamples(count: FFTProcessor.fftSize * 2)
            guard !latest.isEmpty else { return }

            let fftResult = fft.processStereo(interleavedSamples: latest, sampleRate: rate)

            // Copy magnitudes off the real-time thread for analysis.
            let binCount = Int(fftResult.binCount)
            let magnitudes = Array(fft.magnitudeBuffer.pointer.prefix(binCount))

            analysisQueue.async { [weak self] in
                guard let self else { return }
                let now = CFAbsoluteTimeGetCurrent()
                let dt = max(Float(now - self.lastAnalysisTime), 0.001)
                self.lastAnalysisTime = now
                let effectiveFps = 1.0 / dt

                let fv = mir.process(
                    magnitudes: magnitudes, fps: effectiveFps, time: 0, deltaTime: dt
                )

                // Feed live MIR features (band energy, beats, spectral) to the render pipeline.
                // RenderPipeline.draw(in:) overlays timing fields each frame.
                self.pipeline.setFeatures(fv)

                // Update feedback beat value from live audio (per-frame).
                self.pipeline.updateFeedbackBeatValue(from: fv)

                self.analysisFrameCount += 1

                // Build per-frame features and accumulate via 10s EMA.
                let nyquist: Float = 24000.0
                let centroidNorm = mir.rawSmoothedCentroid / nyquist
                let frameFeatures: [Float] = [
                    fv.subBass, fv.lowBass, fv.lowMid,
                    fv.midHigh, fv.highMid, fv.high,
                    centroidNorm, mir.rawSmoothedFlux,
                    mir.latestMajorKeyCorrelation,
                    mir.latestMinorKeyCorrelation
                ]

                // EMA accumulation to match DEAM's track-level averages.
                if !self.featureAccumInitialized {
                    self.accumulatedFeatures = frameFeatures
                    self.featureAccumInitialized = true
                } else {
                    for idx in 0..<10 {
                        self.accumulatedFeatures[idx] = featureEmaAlpha * frameFeatures[idx]
                            + (1 - featureEmaAlpha) * self.accumulatedFeatures[idx]
                    }
                }

                // Run mood classifier on accumulated (averaged) features.
                if let mood {
                    let features = self.accumulatedFeatures
                    // Write capture row (~every 10th frame to avoid huge files).
                    if self.analysisFrameCount % 10 == 0 {
                        self.writeCaptureRow(
                            features: features, fv: fv,
                            magMax: magnitudes.max() ?? 0,
                            key: mir.estimatedKey
                        )
                    }

                    if let state = try? mood.classify(features: features) {
                        // Diagnostic: once per second, write to file.
                        if self.analysisFrameCount % 60 == 0 {
                            let line = String(
                                format: "bassTs=%d iBPM=%.0f sBPM=%.0f td=%@"
                                + " key=%@ mood=(%.2f,%.2f) quad=%@\n",
                                mir.bassOnsetCount,
                                mir.instantBPM ?? 0,
                                mir.stableBPM ?? 0,
                                mir.tempoDebug,
                                mir.stableKey ?? mir.estimatedKey ?? "nil",
                                state.valence, state.arousal,
                                state.quadrant.rawValue
                            )
                            diagLog?.write(Data(line.utf8))
                        }
                        let te = fv.subBass + fv.lowBass + fv.lowMid
                            + fv.midHigh + fv.highMid + fv.high
                        let diag = MIRDiagnostics(
                            magMax: magnitudes.max() ?? 0,
                            bass: fv.bass, mid: fv.mid,
                            centroid: fv.spectralCentroid,
                            flux: fv.spectralFlux,
                            majorCorr: mir.latestMajorKeyCorrelation,
                            minorCorr: mir.latestMinorKeyCorrelation,
                            callbackCount: self.analysisFrameCount,
                            onsetsPerSec: mir.onsetsPerSecond,
                            totalEnergy: te
                        )
                        let stability = mir.featureStability
                        Task { @MainActor [weak self] in
                            // Attenuate mood toward neutral during ramp-up.
                            var attenuated = state
                            attenuated.valence *= stability
                            attenuated.arousal *= stability
                            self?.currentMood = attenuated
                            // Prefer pre-fetched metadata over self-computed.
                            if self?.preFetchedProfile?.key == nil {
                                self?.estimatedKey = mir.stableKey ?? mir.estimatedKey
                            }
                            if self?.preFetchedProfile?.bpm == nil {
                                self?.estimatedTempo = mir.stableBPM ?? mir.estimatedTempo
                            }
                            self?.mirDiag = diag
                        }
                    }
                }
            }
        }

        // Build fetcher list.
        // MusicKit: genre from Apple Music catalog (works for any streaming app).
        // MusicBrainz: genre tags (always free).
        // Soundcharts/Spotify: optional, need credentials.
        var fetchers: [any MetadataFetching] = [
            ITunesSearchFetcher(),
            MusicBrainzFetcher()
        ]
        if let soundcharts = SoundchartsFetcher.fromEnvironment() {
            fetchers.append(soundcharts)
            logger.info("Soundcharts fetcher enabled (audio features)")
        }
        if let spotify = SpotifyFetcher.fromEnvironment() {
            fetchers.append(spotify)
            logger.info("Spotify fetcher enabled (search only)")
        }

        let fetcher = MetadataPreFetcher(fetchers: fetchers)
        self.preFetcher = fetcher

        audioRouter.onTrackChange = { [weak self] event in
            guard let self else { return }
            mir.currentTrackName = event.current.title ?? ""
            mir.currentArtistName = event.current.artist ?? ""
            Task { @MainActor in
                self.currentTrack = event.current
                self.preFetchedProfile = nil
                logger.info("Track: \(event.current.title ?? "?") — \(event.current.artist ?? "?")")
            }
            // Reset MIR accumulators on track change.
            mir.reset()

            Task {
                let profile = await fetcher.prefetch(for: event.current)
                await MainActor.run {
                    self.preFetchedProfile = profile

                    // Use pre-fetched BPM/key to override self-computed values.
                    if let bpm = profile?.bpm {
                        self.estimatedTempo = bpm
                        logger.info("Using pre-fetched BPM: \(bpm)")
                    }
                    if let key = profile?.key {
                        self.estimatedKey = key
                        logger.info("Using pre-fetched key: \(key)")
                    }
                }
            }
        }

        return audioRouter
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
        } else {
            logger.info("Screen capture denied — grant in System Settings for audio capture")
            // Poll until permission is granted — no restart required.
            Task { @MainActor in
                while !hasScreenCapturePermission {
                    try? await Task.sleep(for: .seconds(2))
                    if CGPreflightScreenCaptureAccess() {
                        hasScreenCapturePermission = true
                        logger.info("Screen capture permission granted")
                        startAudioCapture()
                        break
                    }
                }
            }
        }

        if let current = presetLoader.currentPreset {
            applyPreset(current)
            showPresetName(current.descriptor.name)
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

    /// Toggle the debug metadata overlay.
    func toggleDebugOverlay() {
        showDebugOverlay.toggle()
    }

    /// Toggle MIR feature recording to ~/phosphene_features.csv.
    func toggleRecording() {
        if mirPipeline.isRecording {
            mirPipeline.stopRecording()
        } else {
            mirPipeline.startRecording()
        }
    }

    /// Toggle feature vector capture to CSV file.
    func toggleCapture() {
        if isCapturing {
            stopCapture()
        } else {
            startCapture()
        }
    }

    private func startCapture() {
        let dir = FileManager.default.temporaryDirectory
        let name = "phosphene_features_\(Int(Date().timeIntervalSince1970)).csv"
        let url = dir.appendingPathComponent(name)

        FileManager.default.createFile(atPath: url.path, contents: nil)
        guard let handle = FileHandle(forWritingAtPath: url.path) else {
            logger.error("Failed to create capture file: \(url.path)")
            return
        }

        let header = "timestamp,track,artist,genre,subBass,lowBass,lowMid,midHigh,highMid,high,"
            + "centroid,flux,majorCorr,minorCorr,bass3,mid3,treble3,magMax,key\n"
        handle.write(Data(header.utf8))

        captureHandle = handle
        captureFilePath = url.path
        isCapturing = true
        logger.info("Feature capture started: \(url.path, privacy: .public)")
    }

    private func stopCapture() {
        captureHandle?.closeFile()
        captureHandle = nil
        isCapturing = false
        if let path = captureFilePath {
            logger.info("Feature capture stopped: \(path, privacy: .public)")
        }
    }

    /// Write a feature row to the capture file (called from analysis queue).
    func writeCaptureRow(features: [Float], fv: Shared.FeatureVector,
                         magMax: Float, key: String?) {
        guard let handle = captureHandle else { return }
        let track = currentTrack?.title ?? ""
        let artist = currentTrack?.artist ?? ""
        let genre = preFetchedProfile?.genreTags.joined(separator: "|") ?? ""
        let row = String(
            format: "%.3f,%@,%@,%@,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,"
            + "%.5f,%.5f,%.5f,%.5f,%.4f,%.4f,%.4f,%.5f,%@\n",
            Date().timeIntervalSince1970,
            track.replacingOccurrences(of: ",", with: ";"),
            artist.replacingOccurrences(of: ",", with: ";"),
            genre.replacingOccurrences(of: ",", with: "|"),
            features[0], features[1], features[2],
            features[3], features[4], features[5],
            features[6], features[7], features[8], features[9],
            fv.bass, fv.mid, fv.treble, magMax,
            key ?? "nil"
        )
        handle.write(Data(row.utf8))
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
