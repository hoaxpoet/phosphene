// PlaybackErrorConditionTracker — Tracks which condition-bound UserFacingError toasts
// are currently asserted, mirroring ToastManager.isConditionAsserted without coupling
// to the toast lifecycle in unit tests.
//
// Used by PlaybackErrorBridge to decide whether to suppress a re-assertion.

import Foundation
import Shared

// MARK: - PlaybackErrorConditionTracker

/// Lightweight register of currently-asserted condition IDs.
///
/// `PlaybackErrorBridge` calls `assert(_:)` when enqueuing a condition toast
/// and `clear(_:)` when dismissing it. Tests can check `isAsserted(_:)` without
/// spinning up a full `ToastManager`.
@MainActor
final class PlaybackErrorConditionTracker {

    // MARK: - Private

    private var asserted: Set<String> = []

    // MARK: - API

    /// Mark a condition as currently asserted (toast is visible).
    func assert(_ conditionID: String) {
        asserted.insert(conditionID)
    }

    /// Clear a condition (toast dismissed or condition resolved).
    func clear(_ conditionID: String) {
        asserted.remove(conditionID)
    }

    /// Returns true if the condition is currently asserted.
    func isAsserted(_ conditionID: String) -> Bool {
        asserted.contains(conditionID)
    }

    /// Clear all tracked conditions (e.g. on session end).
    func reset() {
        asserted.removeAll()
    }
}
