// ContentView — Main visualizer view with keyboard-driven preset navigation.

import Audio
import CoreGraphics
import os.log
import Presets
import Renderer
import Shared
import SwiftUI

private let logger = Logger(subsystem: "com.phosphene.app", category: "ContentView")

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
        .onAppear { engine.startAudio() }
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

    /// Task that hides the preset name after a delay.
    private var hideNameTask: Task<Void, Never>?

    /// Metadata pre-fetcher for external API queries.
    private var preFetcher: MetadataPreFetcher?

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
            if let preset = loader.currentPreset {
                pipe.setActivePipelineState(preset.pipelineState)
            }
        }

        self.context = ctx
        self.audioBuffer = buf
        self.fftProcessor = fft
        self.pipeline = pipe
        self.presetLoader = loader

        loader.onPresetsReloaded = { [weak self] in
            guard let self, let current = self.presetLoader.currentPreset else { return }
            self.pipeline.setActivePipelineState(current.pipelineState)
            self.showPresetName(current.descriptor.name)
        }

        if #available(macOS 14.2, *) {
            let metadata = StreamingMetadata()
            let audioRouter = AudioInputRouter(metadata: metadata)
            audioRouter.onAudioSamples = { [weak buf, weak fft] samples, count, rate, _ in
                guard let buf, let fft else { return }
                buf.write(from: samples, count: count)
                let latest = buf.latestSamples(count: FFTProcessor.fftSize * 2)
                if !latest.isEmpty {
                    fft.processStereo(interleavedSamples: latest, sampleRate: rate)
                }
            }

            // Build fetcher list — MusicBrainz is always available (free API).
            // Spotify requires credentials via environment variables.
            var fetchers: [any MetadataFetching] = [MusicBrainzFetcher()]
            if let spotify = SpotifyFetcher.fromEnvironment() {
                fetchers.append(spotify)
                logger.info("Spotify fetcher enabled")
            } else {
                logger.info("Spotify fetcher disabled (no credentials)")
            }

            let fetcher = MetadataPreFetcher(fetchers: fetchers)
            self.preFetcher = fetcher

            audioRouter.onTrackChange = { [weak self] event in
                guard let self else { return }
                Task { @MainActor in
                    self.currentTrack = event.current
                    self.preFetchedProfile = nil
                    logger.info("Track changed: \(event.current.title ?? "?") — \(event.current.artist ?? "?")")
                }
                Task {
                    let profile = await fetcher.prefetch(for: event.current)
                    await MainActor.run {
                        self.preFetchedProfile = profile
                    }
                }
            }

            self.router = audioRouter
        }
    }

    // MARK: - Public API

    /// Request screen capture permission and start audio capture.
    func startAudio() {
        let hasPermission = CGPreflightScreenCaptureAccess()
        if !hasPermission {
            let granted = CGRequestScreenCaptureAccess()
            if !granted {
                logger.error("Screen capture denied. Enable in System Settings → Privacy → Screen Recording.")
                return
            }
        }

        if #available(macOS 14.2, *), let audioRouter = router as? AudioInputRouter {
            do {
                try audioRouter.start(mode: .systemAudio)
                logger.info("Audio capture started")
            } catch {
                logger.error("Audio capture failed: \(error)")
            }
        }

        if let current = presetLoader.currentPreset {
            showPresetName(current.descriptor.name)
        }
    }

    // MARK: - Preset Cycling

    /// Advance to the next preset and update the pipeline.
    func nextPreset() {
        guard let preset = presetLoader.nextPreset() else { return }
        pipeline.setActivePipelineState(preset.pipelineState)
        showPresetName(preset.descriptor.name)
    }

    /// Go back to the previous preset and update the pipeline.
    func previousPreset() {
        guard let preset = presetLoader.previousPreset() else { return }
        pipeline.setActivePipelineState(preset.pipelineState)
        showPresetName(preset.descriptor.name)
    }

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
