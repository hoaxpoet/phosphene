// VisualizerEngine+InitHelpers — Private setup helpers called from init.

import AppKit
import Audio
import DSP
import Foundation
import Metal
import ML
import Presets
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
        setupDrawableLifecycleWatchdog(pipe: pipe, recorder: recorder)
    }

    /// HANG.1 watchdog. The render thread cannot log after `nextDrawable` blocks, so this
    /// independent task snapshots the lock-protected probe and persists the blocked call site.
    /// It also writes a low-rate balance heartbeat for healthy-session comparison.
    /// The OS's own view of whether it is shedding performance for heat, plus the two other
    /// unprivileged state flags that change what the hardware will deliver.
    ///
    /// `ProcessInfo.thermalState` is deliberately coarse (four levels) and is the only thermal
    /// signal available without root — see the BUG-100 note at the call site for why
    /// `powermetrics` is not an option.
    static func thermalDescription() -> String {
        let info = ProcessInfo.processInfo
        let state: String
        switch info.thermalState {
        case .nominal:  state = "nominal"
        case .fair:     state = "fair"
        case .serious:  state = "serious"
        case .critical: state = "critical"
        @unknown default: state = "unknown"
        }
        return "state=\(state) low_power=\(info.isLowPowerModeEnabled) "
             + "active_cpus=\(info.activeProcessorCount)"
    }

    func setupDrawableLifecycleWatchdog(pipe: RenderPipeline, recorder: SessionRecorder) {
        Task.detached(priority: .utility) { [weak pipe, weak recorder] in
            var lastHeartbeatBucket: UInt64 = 0
            var lastStallFrame: UInt64?
            var lastRenderTarget = ""
            var lastThermalState = ""
            var lastFailureCount: UInt64 = 0
            var lastUnpresentedCount: UInt64 = 0

            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let pipe, let recorder else { return }
                let snapshot = pipe.drawableLifecycleSnapshot()

                // Record the size the GPU is actually drawing at, whenever it changes.
                // `frame_gpu_ms` is uninterpretable without it — see `renderTargetDescription`.
                let target = pipe.renderTargetDescription
                if target != lastRenderTarget {
                    lastRenderTarget = target
                    let message = "RENDER_TARGET \(target)"
                    recorder.log(message)
                    initLogger.info("\(message, privacy: .public)")
                }

                // BUG-100 — is the machine throttling, or is the app slower?
                //
                // The open half of BUG-100 is a 2.5x frame-time degradation over 70 s at 4K
                // while the app's own CPU work stayed flat (encode 12.9 -> 15.2 ms) — same work,
                // less delivered. Thermal throttling is the leading explanation and nothing in
                // the session recorded it, so it could not be confirmed or ruled out.
                //
                // ⚠ NOT `powermetrics`, which is what was asked for: it refuses to run without
                // root ("powermetrics must be invoked as the superuser"), so the app cannot
                // sample it, and shipping a privileged helper to read one counter is not
                // proportionate. `ProcessInfo.thermalState` is the supported unprivileged
                // primitive for exactly this question — the OS's own view of whether it is
                // shedding performance for heat — and `nominal` throughout a degrading session
                // would falsify the thermal hypothesis just as usefully as `serious` confirms it.
                //
                // Logged on CHANGE, so the transition timestamps line up against `frame_gpu_ms`,
                // plus once at the start so a session that never changes still records its state
                // (absence of a line would otherwise be ambiguous between "nominal" and "not
                // instrumented").
                let thermal = Self.thermalDescription()
                if thermal != lastThermalState {
                    lastThermalState = thermal
                    let message = "THERMAL_STATE \(thermal)"
                    recorder.log(message)
                    initLogger.info("\(message, privacy: .public)")
                }

                let heartbeatBucket = snapshot.commandBuffersCompleted / 600
                if heartbeatBucket > lastHeartbeatBucket {
                    lastHeartbeatBucket = heartbeatBucket
                    let message = "DRAWABLE_LIFECYCLE heartbeat \(snapshot.logDescription)"
                    recorder.log(message)
                    initLogger.info("\(message, privacy: .public)")
                }

                if snapshot.commandBufferFailures > lastFailureCount
                    || snapshot.unpresentedAcquisitions > lastUnpresentedCount {
                    lastFailureCount = snapshot.commandBufferFailures
                    lastUnpresentedCount = snapshot.unpresentedAcquisitions
                    let message = "DRAWABLE_LIFECYCLE imbalance \(snapshot.logDescription)"
                    recorder.log(message)
                    initLogger.error("\(message, privacy: .public)")
                }

                if let frame = snapshot.pendingRequestFrame,
                   let pendingSeconds = snapshot.pendingRequestSeconds,
                   pendingSeconds >= 0.5,
                   frame != lastStallFrame {
                    lastStallFrame = frame
                    let message = "DRAWABLE_LIFECYCLE STALL \(snapshot.logDescription)"
                    recorder.log(message)
                    initLogger.fault("\(message, privacy: .public)")
                }
            }
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
        // IFC.4 (D-177) — PANNs instrument-family analyzer for orchestral
        // section capture. nil → empty family series (graceful degrade).
        let familyAnalyzer: (any InstrumentFamilyAnalyzing)? = {
            guard let analyzer = try? InstrumentFamilyAnalyzer(device: device) else {
                initLogger.warning("InstrumentFamilyAnalyzer init failed — family activity disabled")
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
            familyAnalyzer: familyAnalyzer,
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
