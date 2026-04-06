import SwiftUI
import Renderer
import Audio
import Shared
import os.log
import CoreGraphics

private let logger = Logger(subsystem: "com.phosphene.app", category: "ContentView")

struct ContentView: View {
    @StateObject private var engine = VisualizerEngine()

    var body: some View {
        MetalView(context: engine.context, pipeline: engine.pipeline)
            .frame(minWidth: 800, minHeight: 600)
            .onAppear { engine.startAudio() }
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
    // AudioInputRouter requires macOS 14.2+; stored as Any to avoid propagating availability.
    private var router: Any?

    init() {
        let ctx = try! MetalContext()
        let buf = try! AudioBuffer(device: ctx.device)
        let fft = try! FFTProcessor(device: ctx.device)
        let lib = try! ShaderLibrary(context: ctx)
        let pipe = try! RenderPipeline(
            context: ctx,
            shaderLibrary: lib,
            fftBuffer: fft.magnitudeBuffer.buffer,
            waveformBuffer: buf.metalBuffer
        )

        self.context = ctx
        self.audioBuffer = buf
        self.fftProcessor = fft
        self.pipeline = pipe

        if #available(macOS 14.2, *) {
            let audioRouter = AudioInputRouter()
            // Wire audio callback: samples → ring buffer → FFT.
            // This closure runs on the real-time audio IO thread.
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
        // Core Audio taps require Screen Recording (or System Audio Recording) permission.
        // Without it, the tap is created but delivers silence.
        let hasPermission = CGPreflightScreenCaptureAccess()
        if !hasPermission {
            logger.warning("Screen capture permission not granted — requesting now")
            let granted = CGRequestScreenCaptureAccess()
            logger.info("Screen capture permission request result: \(granted)")
            if !granted {
                logger.error("Screen capture permission denied. Grant it in System Settings → Privacy & Security → Screen Recording (or Screen & System Audio Recording), then relaunch.")
                return
            }
        } else {
            logger.info("Screen capture permission: granted")
        }

        if #available(macOS 14.2, *), let audioRouter = router as? AudioInputRouter {
            do {
                try audioRouter.start(mode: .systemAudio)
                logger.info("Audio capture started successfully")
            } catch {
                logger.error("Audio capture failed: \(error)")
            }
        } else {
            logger.warning("Audio capture unavailable (requires macOS 14.2+)")
        }
    }
}
