// CaptureModeReconciler — Reconciles CaptureMode settings changes with AudioInputRouter.
//
// Decision (U.8 pre-flight audit, 2026-04-24): LIVE-SWITCH PATH.
// AudioInputRouter has switchMode(_:) which calls stopInternal() (resetting SilenceDetector)
// then restarts in the new InputMode. This is a clean, low-risk swap path.
//
// Apply semantics:
//   .systemAudio  → InputMode.systemAudio
//   .specificApp  → InputMode.application(processID: pid) via NSWorkspace pid lookup
//   .localFile    → shows "coming later" toast; no router call
//
// The SilenceDetector briefly enters .suspect during the switch, recovers to .active
// within a few seconds as audio resumes. No DRM false-silent risk.
//
// Decision entry: docs/DECISIONS.md D-052 (written in Part C).

import AppKit
import Audio
import Combine
import Foundation
import os.log

private let logger = Logger(subsystem: "com.phosphene.app", category: "CaptureModeReconciler")

// MARK: - CaptureModeReconciler

/// Subscribes to SettingsStore.captureModeChanged and switches AudioInputRouter mode live.
@available(macOS 14.2, *)
@MainActor
final class CaptureModeReconciler {

    private let settingsStore: SettingsStore
    private weak var router: AudioInputRouter?
    private let toastManager: ToastManager
    private var cancellables = Set<AnyCancellable>()

    @available(macOS 14.2, *)
    init(settingsStore: SettingsStore, router: AudioInputRouter, toastManager: ToastManager) {
        self.settingsStore = settingsStore
        self.router = router
        self.toastManager = toastManager
        subscribeToChanges()
    }

    // MARK: - Private

    private func subscribeToChanges() {
        settingsStore.captureModeChanged
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.reconcile() }
            .store(in: &cancellables)
    }

    func reconcile() {
        let mode = settingsStore.captureMode

        // localFile mode shows a "coming later" toast without touching the router.
        if mode == .localFile {
            let toast = PhospheneToast(
                severity: .info,
                copy: NSLocalizedString("settings.audio.local_file.coming_later", comment: ""),
                source: .liveAdaptationAck
            )
            toastManager.enqueue(toast)
            logger.info("CaptureModeReconciler: localFile mode — showing coming-later toast")
            return
        }

        guard let router else { return }

        switch mode {
        case .systemAudio:
            do {
                try router.switchMode(.systemAudio)
                logger.info("CaptureModeReconciler: switched to systemAudio")
            } catch {
                logger.error("CaptureModeReconciler: switchMode failed — \(error)")
            }

        case .specificApp:
            guard let override = settingsStore.sourceAppOverride else {
                logger.debug("CaptureModeReconciler: specificApp selected but no app chosen yet")
                return
            }
            do {
                try router.switchMode(.application(bundleIdentifier: override.bundleIdentifier))
                logger.info("CaptureModeReconciler: switched to application '\(override.bundleIdentifier)'")
            } catch {
                logger.error("CaptureModeReconciler: switchMode(application) failed — \(error)")
            }

        case .localFile:
            break // handled above
        }
    }
}
