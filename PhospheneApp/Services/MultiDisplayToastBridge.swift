// MultiDisplayToastBridge — Emits toasts on display hot-plug and disconnect events.

import AppKit
import Foundation
import os.log

private let logger = Logger(subsystem: "com.phosphene.app", category: "MultiDisplayToastBridge")

// MARK: - MultiDisplayToastBridge

/// Wires `DisplayManager` hot-plug callbacks to the `ToastManager` queue.
///
/// Screen added: info toast with an inline "Move" action.
/// Current-screen removed: warning toast + auto-move to primary.
@MainActor
final class MultiDisplayToastBridge {

    private let toastManager: ToastManager
    private let displayManager: DisplayManager

    // Coalescing: rapid adds/removes within 0.5s produce one toast.
    private var coalesceTask: Task<Void, Never>?
    private var pendingEvents: [String] = []

    init(toastManager: ToastManager, displayManager: DisplayManager) {
        self.toastManager = toastManager
        self.displayManager = displayManager

        displayManager.onScreensAdded = { [weak self] screens in
            self?.handleAdded(screens)
        }
        displayManager.onScreensRemoved = { [weak self] screens in
            self?.handleRemoved(screens)
        }
    }

    // MARK: - Private

    private func handleAdded(_ screens: Set<NSScreen>) {
        guard !screens.isEmpty else { return }
        let message = "New display connected."

        let toast = PhospheneToast(
            severity: .info,
            copy: message,
            duration: .infinity,
            source: .displayChange,
            action: PhospheneToast.ToastAction(label: "Move Phosphene there") { [weak self] in
                self?.displayManager.moveToSecondaryDisplay()
            }
        )
        toastManager.enqueue(toast)
        logger.info("MultiDisplayToastBridge: screen added — toast shown")
    }

    private func handleRemoved(_ screens: Set<NSScreen>) {
        // Check if the current screen was removed.
        let currentScreen = displayManager.currentScreen
        let wasCurrentRemoved = screens.contains(where: { $0 == currentScreen })
        let names = screens.map(\.localizedName).joined(separator: ", ")

        if wasCurrentRemoved {
            displayManager.moveToPrimaryDisplay()
            let toast = PhospheneToast(
                severity: .warning,
                copy: "Output display disconnected. Moved to main display.",
                duration: 5,
                source: .displayChange
            )
            toastManager.enqueue(toast)
            logger.info("MultiDisplayToastBridge: active screen '\(names)' removed — moved to primary")
        } else {
            let toast = PhospheneToast(
                severity: .info,
                copy: "Display '\(names)' disconnected.",
                duration: 4,
                source: .displayChange
            )
            toastManager.enqueue(toast)
        }
    }
}
