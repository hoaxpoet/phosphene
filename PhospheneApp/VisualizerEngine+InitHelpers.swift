// VisualizerEngine+InitHelpers — Private setup helpers called from init.

import AppKit
import Audio
import DSP
import Foundation
import Metal
import ML
import Renderer
import Session
import Shared
import os.log

private let initLogger = Logger(subsystem: "com.phosphene.app", category: "VisualizerEngine")

extension VisualizerEngine {

    // MARK: - Init Helpers

    /// Wire the per-frame capture hook: blit the drawable into a capture texture
    /// inside the command buffer, then hand it to the recorder for video+CSV.
    func setupCaptureHook(pipe: RenderPipeline, ctx: MetalContext) {
        guard let recorder = self.sessionRecorder else { return }
        let device = ctx.device
        pipe.onFrameRendered = { [weak recorder] drawableTex, features, stems, commandBuffer in
            guard let recorder = recorder else { return }
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
            commandBuffer.addCompletedHandler { [weak recorder] _ in
                recorder?.recordFrame(features: features, stems: stems)
            }
        }
    }

    /// Spin up background tasks to generate noise and IBL textures.
    func setupBackgroundTextures(pipe: RenderPipeline, ctx: MetalContext, lib: Renderer.ShaderLibrary) {
        DispatchQueue.global(qos: .userInitiated).async {
            if let tm = try? TextureManager(context: ctx, shaderLibrary: lib) {
                pipe.setTextureManager(tm)
            } else {
                initLogger.warning("TextureManager init failed — noise textures unavailable")
            }
        }
        DispatchQueue.global(qos: .userInitiated).async {
            if let ibl = try? IBLManager(context: ctx, shaderLibrary: lib) {
                pipe.setIBLManager(ibl)
            } else {
                initLogger.warning("IBLManager init failed — IBL textures unavailable for ray march presets")
            }
        }
    }

    // MARK: - Session Manager Factory

    /// Build a `SessionManager` wired to the engine's ML components.
    ///
    /// Uses a static factory so it can be called during phase-1 init before
    /// `self` is fully available. Shares `analyzer` and `classifier` instances
    /// with the engine's live pipeline to avoid double-loading the ML weights.
    ///
    /// `NullStemSeparator` is substituted when the Open-Unmix weights are absent —
    /// ad-hoc mode never invokes the preparer, so it never throws.
    @MainActor
    static func makeSessionManager(
        sep: StemSeparator?,
        analyzer: StemAnalyzer,
        classifier: MoodClassifier?
    ) -> SessionManager {
        let resolvedSep: any StemSeparating = sep ?? NullStemSeparator()
        let preparer = SessionPreparer(
            resolver: PreviewResolver(),
            downloader: PreviewDownloader(),
            stemSeparator: resolvedSep,
            stemAnalyzer: analyzer,
            moodClassifier: classifier ?? MoodClassifier()
        )
        return SessionManager(connector: PlaylistConnector(), preparer: preparer)
    }

    /// Register the willTerminate observer so the session recorder finalises the MP4.
    func setupTerminationObserver() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.sessionRecorder?.finish()
        }
    }
}

// MARK: - NullStemSeparator

/// Fallback `StemSeparating` used when Open-Unmix weights are absent.
///
/// `separate()` always throws `modelNotFound`. `SessionPreparer` in ad-hoc mode
/// never calls `separate()`, so this is safe for production use. If pre-analyzed
/// session mode is attempted without weights, preparation fails gracefully and the
/// engine falls back to live-only reactive mode.
private final class NullStemSeparator: StemSeparating, @unchecked Sendable {
    let stemLabels = ["vocals", "drums", "bass", "other"]
    var stemBuffers: [UMABuffer<Float>] { [] }

    func separate(audio: [Float], channelCount: Int, sampleRate: Float) throws -> StemSeparationResult {
        throw StemSeparationError.modelNotFound
    }
}
