// VisualizerEngine+InitHelpers — Private setup helpers called from init.

import AppKit
import Foundation
import Metal
import Renderer
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
