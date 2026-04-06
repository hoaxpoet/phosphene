import SwiftUI
import Renderer
import Audio
import Presets
import Shared
import os.log
import CoreGraphics

private let logger = Logger(subsystem: "com.phosphene.app", category: "ContentView")

struct ContentView: View {
    @StateObject private var engine = VisualizerEngine()

    var body: some View {
        ZStack(alignment: .topLeading) {
            MetalView(context: engine.context, pipeline: engine.pipeline)

            if let name = engine.currentPresetName {
                Text(name)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
                    .padding(8)
                    .background(.black.opacity(0.4))
                    .cornerRadius(6)
                    .padding(12)
                    .transition(.opacity)
                    .allowsHitTesting(false)
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
    }
}

// MARK: - VisualizerEngine

/// Owns the audio capture → FFT → renderer pipeline.
/// Created once at app launch via @StateObject; audio starts on first appear.
final class VisualizerEngine: ObservableObject, @unchecked Sendable {
    let context: MetalContext
    let pipeline: RenderPipeline

    private let audioBuffer: AudioBuffer
    private let fftProcessor: FFTProcessor
    private let presetLoader: PresetLoader
    // AudioInputRouter requires macOS 14.2+; stored as Any to avoid propagating availability.
    private var router: Any?

    @Published var currentPresetName: String?
    private var hideNameTask: Task<Void, Never>?

    init() {
        let ctx = try! MetalContext()
        let buf = try! AudioBuffer(device: ctx.device)
        let fft = try! FFTProcessor(device: ctx.device)
        let lib = try! ShaderLibrary(context: ctx)

        let loader = PresetLoader(device: ctx.device, pixelFormat: ctx.pixelFormat)

        let pipe = try! RenderPipeline(
            context: ctx,
            shaderLibrary: lib,
            fftBuffer: fft.magnitudeBuffer.buffer,
            waveformBuffer: buf.metalBuffer
        )

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
            let audioRouter = AudioInputRouter()
            audioRouter.onAudioSamples = {
                [weak buf, weak fft]
                (samples: UnsafePointer<Float>, count: Int, rate: Float, channels: UInt32) in
                guard let buf, let fft else { return }
                buf.write(from: samples, count: count)
                let latest = buf.latestSamples(count: FFTProcessor.fftSize * 2)
                if !latest.isEmpty {
                    fft.processStereo(interleavedSamples: latest, sampleRate: rate)
                }
            }
            self.router = audioRouter
        }
    }

    func startAudio() {
        let hasPermission = CGPreflightScreenCaptureAccess()
        if !hasPermission {
            let granted = CGRequestScreenCaptureAccess()
            if !granted {
                logger.error("Screen capture permission denied. Grant it in System Settings → Privacy & Security → Screen Recording, then relaunch.")
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

    func nextPreset() {
        guard let preset = presetLoader.nextPreset() else { return }
        pipeline.setActivePipelineState(preset.pipelineState)
        showPresetName(preset.descriptor.name)
    }

    func previousPreset() {
        guard let preset = presetLoader.previousPreset() else { return }
        pipeline.setActivePipelineState(preset.pipelineState)
        showPresetName(preset.descriptor.name)
    }

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
