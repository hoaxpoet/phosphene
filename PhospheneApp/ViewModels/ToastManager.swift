// ToastManager — Queue and lifecycle manager for in-session toast notifications.

import Combine
import Foundation
import os.log

private let logger = Logger(subsystem: "com.phosphene.app", category: "ToastManager")

// MARK: - ToastManager

/// Manages the lifecycle of `PhospheneToast` notifications.
///
/// Maintains a FIFO queue of up to three visible toasts. Auto-dismisses each
/// toast after its configured duration. Overflow drops the oldest non-degradation
/// toast rather than silencing an important alert.
///
/// All mutations must occur on the main actor.
@MainActor
final class ToastManager: ObservableObject {

    // MARK: - Published

    @Published private(set) var visibleToasts: [PhospheneToast] = []

    // MARK: - Constants

    private static let maxVisible = 3

    // MARK: - Private

    private var dismissTasks: [UUID: Task<Void, Never>] = [:]

    // MARK: - API

    /// Enqueue a toast for display. Auto-dismiss fires after `toast.duration` seconds.
    ///
    /// If the queue is already at `maxVisible`:
    /// - Drops the oldest non-degradation toast to make room.
    /// - If all visible toasts are `.degradation`, drops the oldest regardless.
    func enqueue(_ toast: PhospheneToast) {
        if visibleToasts.count >= Self.maxVisible {
            dropOldest()
        }
        visibleToasts.append(toast)
        logger.info("Toast enqueued [\(String(describing: toast.severity))] \(toast.copy)")

        guard toast.duration < .infinity else { return }

        let id = toast.id
        let duration = toast.duration
        dismissTasks[id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.dismiss(id: id) }
        }
    }

    /// Manually dismiss a toast by ID.
    func dismiss(id: UUID) {
        dismissTasks[id]?.cancel()
        dismissTasks[id] = nil
        visibleToasts.removeAll { $0.id == id }
    }

    /// Dismiss all visible toasts that share the given `conditionID`.
    ///
    /// Called by `PlaybackErrorBridge` when a condition (e.g. silence) clears.
    func dismissByCondition(_ conditionID: String) {
        let matching = visibleToasts.filter { $0.conditionID == conditionID }
        for toast in matching {
            dismiss(id: toast.id)
        }
    }

    /// Returns true if any visible toast carries the given `conditionID`.
    ///
    /// Used by bridges to avoid enqueuing a duplicate condition toast.
    func isConditionAsserted(_ conditionID: String) -> Bool {
        visibleToasts.contains { $0.conditionID == conditionID }
    }

    // MARK: - Private

    private func dropOldest() {
        // Prefer dropping info/warning before degradation.
        if let idx = visibleToasts.firstIndex(where: { $0.severity != .degradation }) {
            let dropped = visibleToasts[idx]
            dismissTasks[dropped.id]?.cancel()
            dismissTasks[dropped.id] = nil
            visibleToasts.remove(at: idx)
            logger.debug("Toast overflow — dropped '\(dropped.copy)'")
        } else if !visibleToasts.isEmpty {
            let dropped = visibleToasts[0]
            dismissTasks[dropped.id]?.cancel()
            dismissTasks[dropped.id] = nil
            visibleToasts.removeFirst()
        }
    }
}
