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
        pipe.onFrameRendered = { [weak recorder, weak self] drawableTex, features, stems, commandBuffer in
            guard let recorder = recorder else { return }
            // Snapshot the latest beat-sync data before encoding the command buffer
            // so the completion handler captures a point-in-time value from this frame.
            let beatSync = self?.beatSyncLock.withLock { self?.latestBeatSyncSnapshot } ?? .zero
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
                recorder?.recordFrame(features: features, stems: stems, beatSync: beatSync)
            }
        }
        // Feed full-pipeline timing into features.csv frame_cpu_ms /
        // frame_gpu_ms columns. Lag: 1–3 frames behind the row's features
        // (RenderPipeline triple-buffers; documented in SessionRecorder).
        pipe.onFrameTimingObserved = { [weak recorder] cpuMs, gpuMs in
            recorder?.recordFrameTiming(cpuMs: cpuMs, gpuMs: gpuMs)
        }
        // PERF.2-render — feed the render-loop CPU breakdown (encode_cpu_ms +
        // renderframe_cpu_ms) so BUG-019 diagnosis can split where the bump lands.
        pipe.onRenderTimingObserved = { [weak recorder] encodeMs, renderframeMs in
            recorder?.recordRenderTimings(encodeCpuMs: encodeMs, renderFrameCpuMs: renderframeMs)
        }
        // PERF.2-pass — feed the ray-march per-sub-pass breakdown
        // (gbuffer/lighting/ssgi/post-process) so the BUG-019 fix increment
        // has a concrete target.
        pipe.onRayMarchPassTimingObserved = { [weak recorder] gbufMs, lightMs, ssgiMs, postMs in
            recorder?.recordRayMarchPassTimings(
                gbufferMs: gbufMs,
                lightingMs: lightMs,
                ssgiMs: ssgiMs,
                postProcessMs: postMs
            )
        }
    }

    /// Wire per-frame dashboard snapshot push. Replaces the DASH.6 GPU
    /// composer; SwiftUI overlay subscribes to `dashboardSnapshot` directly.
    /// (DASH.7 — full implementation in `VisualizerEngine+Dashboard.swift`.)
    @MainActor
    func setupDashboardSnapshotPump(pipe: RenderPipeline) {
        let previous = pipe.onFrameRendered
        pipe.onFrameRendered = { [weak self] drawableTex, features, stems, commandBuffer in
            previous?(drawableTex, features, stems, commandBuffer)
            guard let self else { return }
            Task { @MainActor [weak self] in
                self?.publishDashboardSnapshot(stems: stems)
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
        classifier: MoodClassifier?,
        device: MTLDevice,
        sessionRecorder: SessionRecorder? = nil,
        metadataFetcher: MetadataPreFetcher? = nil
    ) -> SessionManager {
        let resolvedSep: any StemSeparating = sep ?? NullStemSeparator()
        let beatGridAnalyzer: (any BeatGridAnalyzing)? = {
            guard let analyzer = try? DefaultBeatGridAnalyzer(device: device) else {
                initLogger.warning("DefaultBeatGridAnalyzer init failed — beat grid analysis disabled")
                return nil
            }
            return analyzer
        }()
        let preparer = SessionPreparer(
            resolver: PreviewResolver(),
            downloader: PreviewDownloader(),
            stemSeparator: resolvedSep,
            stemAnalyzer: analyzer,
            moodClassifier: classifier ?? MoodClassifier(),
            beatGridAnalyzer: beatGridAnalyzer,
            metadataFetcher: metadataFetcher,
            sessionRecorder: sessionRecorder
        )
        return SessionManager(
            connector: PlaylistConnector(),
            preparer: preparer,
            sessionRecorder: sessionRecorder
        )
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

    /// Register thermal-state + Low-Power-Mode observers that drive the frame-budget
    /// governor's quality floor (CLEAN.4.6 / D-167). A rising thermal state pre-empts the
    /// GPU's own thermal throttle by reducing visual load one floor ahead of it; Low Power
    /// Mode imposes a mild reduction. Both recompute from `ProcessInfo` and hand the floor
    /// to the active `FrameBudgetManager`, which applies it on the next frame.
    func setupThermalGovernorObserver() {
        NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applyCurrentThermalFloor()
        }
        NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applyCurrentThermalFloor()
        }
    }

    /// Recompute the budget-governor quality floor from the current thermal state + Low
    /// Power Mode and hand it to the active `FrameBudgetManager` (CLEAN.4.6 / D-167).
    func applyCurrentThermalFloor() {
        let info = ProcessInfo.processInfo
        pipeline.frameBudgetManager?.setThermalFloor(
            FrameBudgetManager.qualityFloor(
                thermalState: info.thermalState,
                lowPowerMode: info.isLowPowerModeEnabled
            )
        )
    }

    // MARK: - Device Tier Detection

    /// Infer the Apple Silicon generation from the Metal device name.
    ///
    /// Returns `.tier2` for M3/M4 devices, `.tier1` for all others (M1, M2,
    /// or unrecognised names — conservative fallback).
    static func detectDeviceTier(device: MTLDevice) -> DeviceTier {
        let name = device.name.lowercased()
        if name.contains("m3") || name.contains("m4") { return .tier2 }
        return .tier1
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
