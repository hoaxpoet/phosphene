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
