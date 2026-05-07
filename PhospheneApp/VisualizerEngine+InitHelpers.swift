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
    }

    /// Allocate the dashboard composer and wire it into the render pipeline.
    /// The composer is enabled/disabled via `dashboardEnabled` (bound to `D`).
    @MainActor
    func setupDashboardComposer(pipe: RenderPipeline, ctx: MetalContext, lib: Renderer.ShaderLibrary) {
        guard let composer = DashboardComposer(
            device: ctx.device,
            shaderLibrary: lib,
            pixelFormat: ctx.pixelFormat
        ) else {
            initLogger.warning("DashboardComposer init failed — dashboard cards unavailable")
            return
        }
        self.dashboardComposer = composer
        pipe.setDashboardComposer(composer)

        // Per-frame snapshot push. `onFrameRendered` already runs once per
        // rendered frame on `@MainActor`, but it fires AFTER the draw paths
        // have written to the drawable. The composer's `composite()` is invoked
        // from inside each draw path (RenderPipeline.compositeDashboard, called
        // immediately before `present`); the snapshot pushed here is what
        // composite reads on the next frame's update — one-frame lag is
        // imperceptible for instrumentation. Wire onto the existing capture
        // hook so DASH.6 doesn't introduce a second per-frame closure path.
        let previous = pipe.onFrameRendered
        pipe.onFrameRendered = { [weak self, weak composer] drawableTex, features, stems, commandBuffer in
            previous?(drawableTex, features, stems, commandBuffer)
            guard let self, let composer else { return }
            Task { @MainActor [weak self, weak composer] in
                guard let self, let composer, composer.enabled else { return }
                let beat = self.beatSyncLock.withLock { self.latestBeatSyncSnapshot }
                let perf = self.assemblePerfSnapshot(pipeline: self.pipeline)
                composer.update(beat: beat, stems: stems, perf: perf)
            }
        }
    }

    /// Build a `PerfSnapshot` from the current `FrameBudgetManager` +
    /// `MLDispatchScheduler` state. Used by the dashboard composer's per-frame
    /// snapshot push.
    @MainActor
    func assemblePerfSnapshot(pipeline pipe: RenderPipeline) -> PerfSnapshot {
        let mgr = pipe.frameBudgetManager
        let level = mgr?.currentLevel ?? .full
        let recentMs = mgr?.recentMaxFrameMs ?? 0
        let observed = mgr?.recentFramesObserved ?? 0
        let target = mgr?.configuration.targetFrameMs ?? 14
        let (mlCode, deferMs): (Int, Float) = {
            switch self.mlDispatchScheduler?.lastDecision {
            case .none:                          return (0, 0)
            case .dispatchNow:                   return (1, 0)
            case .defer(let ms):                 return (2, ms)
            case .forceDispatch:                 return (3, 0)
            }
        }()
        return PerfSnapshot(
            recentMaxFrameMs: recentMs,
            recentFramesObserved: observed,
            targetFrameMs: target,
            qualityLevelRawValue: level.rawValue,
            qualityLevelDisplayName: level.displayName,
            mlDecisionCode: mlCode,
            mlDeferRetryMs: deferMs
        )
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
        sessionRecorder: SessionRecorder? = nil
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
