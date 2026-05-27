// VisualizerEngine+PublicAPI — startAudio, toggles, and display helpers.

import Audio
import CoreGraphics
import Foundation
import SwiftUI
import os.log

private let apiLogger = Logger(subsystem: "com.phosphene.app", category: "VisualizerEngine")

extension VisualizerEngine {

    // MARK: - Public API

    /// Start audio capture and metadata observation.
    func startAudio() {
        // LF.1: when the local-file playback path is already active, do
        // NOT start the process-tap capture. Otherwise `audioRouter.start(.systemAudio)`
        // below would call `stopInternal()` first, tearing down the
        // LocalFilePlaybackProvider that the LF.1 launch hook just stood up.
        // PlaybackView.setup() runs `startAudio()` unconditionally when the
        // playback view appears; the LF.1 hook transitions to .playing
        // before the view renders, so without this guard the LF playback
        // would be silently clobbered. Stem pipeline + preset apply are
        // already taken care of in `startLocalFilePlayback(url:)`.
        if localFilePlaybackActive {
            apiLogger.info("[LF.1] startAudio skipped — LF playback already active")
            return
        }
        if #available(macOS 14.2, *), let audioRouter = router as? AudioInputRouter {
            audioRouter.startMetadataOnly()
        }
        var permitted = CGPreflightScreenCaptureAccess()
        if !permitted { permitted = CGRequestScreenCaptureAccess() }
        hasScreenCapturePermission = permitted
        if permitted {
            startAudioCapture()
            startStemPipeline()
        } else {
            apiLogger.info("Screen capture denied — grant in System Settings for audio capture")
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
                    apiLogger.info("Screen capture permission granted")
                    startAudioCapture()
                    startStemPipeline()
                    break
                }
            }
        }
    }

    /// Start Core Audio tap capture (requires screen capture permission).
    private func startAudioCapture() {
        if #available(macOS 14.2, *), let audioRouter = router as? AudioInputRouter {
            do {
                try audioRouter.start(mode: .systemAudio)
                apiLogger.info("Audio capture started")
            } catch {
                apiLogger.error("Audio capture failed: \(error)")
            }
        }
    }

    // MARK: - LF.1 — Local File Playback

    /// Start playback of a local audio file via `AVAudioEngine`. Bypasses
    /// the Core Audio process-tap path entirely — no screen-capture
    /// permission required. Transitions the session to ad-hoc / `.playing`
    /// so `ContentView` renders the visualizer surface, and starts the
    /// background stem pipeline so live stem analysis kicks in after the
    /// usual ~10 s warmup.
    ///
    /// Invoked once at app launch from the `PHOSPHENE_LOCAL_FILE_PLAYBACK`
    /// env-var hook in `PhospheneApp.swift`. Safe to call when audio is
    /// not yet started (router is nil-tolerant); no-op if LF playback is
    /// already active.
    @MainActor
    func startLocalFilePlayback(url: URL) {
        guard !localFilePlaybackActive else {
            apiLogger.info("[LF.1] startLocalFilePlayback ignored — already active")
            return
        }
        // Flip the flag first so the SwiftUI body re-render that follows
        // sees LF playback as active and bypasses the permission gate
        // (see ContentView.swift). The router start is synchronous so the
        // tap is already delivering samples by the time SwiftUI repaints.
        localFilePlaybackActive = true

        if #available(macOS 14.2, *), let audioRouter = router as? AudioInputRouter {
            do {
                try audioRouter.start(mode: .localFilePlayback(url))
                apiLogger.info("[LF.1] LF playback router started: \(url.lastPathComponent, privacy: .public)")
            } catch {
                let msg = error.localizedDescription
                apiLogger.error("[LF.1] LF playback router start failed: \(msg, privacy: .public)")
                localFilePlaybackActive = false
                return
            }
        }

        startStemPipeline()
        sessionManager.startAdHocSession()

        if let current = presetLoader.currentPreset {
            applyPreset(current)
            showPresetName(current.descriptor.name)
        }
    }

    // MARK: - Accessibility (U.9, D-054)

    /// Apply reduced-motion and beat-amplitude flags to the render pipeline.
    ///
    /// Called from `PhospheneApp` whenever `AccessibilityState` publishes a change.
    /// Both `pipeline.frameReduceMotion` and `pipeline.beatAmplitudeScale` are
    /// read on the main actor in `draw(in:)`, so no lock is needed here.
    @MainActor
    func applyAccessibility(reduceMotion: Bool, beatAmplitudeScale: Float) {
        pipeline.frameReduceMotion = reduceMotion
        pipeline.beatAmplitudeScale = beatAmplitudeScale
        // Propagate to any active RayMarchPipeline so SSGI is suppressed immediately.
        // Uses the a11y-specific setter — the OR-gate ensures the governor flag is unaffected.
        currentRayMarchPipeline?.setA11yReducedMotion(reduceMotion)
    }

    // MARK: - Preset Settings

    /// Forward the "show uncertified presets" user preference into the engine.
    ///
    /// Called from `PhospheneApp` whenever `SettingsStore.showUncertifiedPresets` changes.
    /// Stored so `applyReactiveUpdate` can pass it through to `PresetScoringContext`,
    /// which otherwise defaults to `includeUncertifiedPresets: false`.
    @MainActor
    func applyShowUncertifiedPresets(_ show: Bool) {
        showUncertifiedPresets = show
    }

    // MARK: - Toggles

    /// Toggle the debug metadata overlay.
    func toggleDebugOverlay() {
        showDebugOverlay.toggle()
    }

    #if DEBUG
    /// Toggle forced-spider mode for visual verification. DEBUG builds only.
    ///
    /// - Returns: The new `forceSpiderActive` state (`true` = forced on).
    @discardableResult
    func toggleForceSpider() -> Bool {
        guard let state = arachneState else { return false }
        state.forceSpiderActive.toggle()
        return state.forceSpiderActive
    }
    #endif

    // MARK: - Display Helpers

    /// Briefly display the preset name, then fade it out after 2 seconds.
    func showPresetName(_ name: String) {
        hideNameTask?.cancel()
        currentPresetName = name
        sessionRecorder?.log("preset → \(name)")
        hideNameTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.5)) {
                currentPresetName = nil
            }
        }
    }
}
