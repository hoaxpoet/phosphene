// PhospheneToast — Toast notification model for in-session status messages.

import Foundation

// MARK: - PhospheneToast

/// A transient in-session notification shown in the bottom-right toast slot.
///
/// Toasts are managed by `ToastManager`. Up to three are visible simultaneously.
/// Degradation-severity toasts are never auto-dropped when the queue overflows.
struct PhospheneToast: Identifiable, Equatable, Sendable {

    // MARK: - Severity

    /// Visual priority of the toast.
    enum Severity: Equatable, Sendable {
        case info         // Grey accent — informational (display connect, adaptation ack)
        case warning      // Amber accent — soft degradation (display disconnect)
        case degradation  // Red accent — hard degradation (no audio detected)
    }

    // MARK: - Source

    /// What generated this toast. Used for coalescing and filtering logic.
    enum Source: Equatable, Sendable {
        case signalState        // SilenceDetector sustained .silent
        case liveAdaptationAck  // User keystroke feedback (router action confirmed)
        case displayChange      // Screen plug/unplug event
        case degradation        // Preparation failure or other hard error
        case generic            // Other one-off messages
    }

    // MARK: - ToastAction

    /// An optional inline CTA button shown alongside the toast copy.
    struct ToastAction: Equatable, Sendable {
        let label: String
        let handler: @MainActor @Sendable () -> Void

        static func == (lhs: ToastAction, rhs: ToastAction) -> Bool {
            lhs.label == rhs.label
        }
    }

    // MARK: - Properties

    let id: UUID
    let severity: Severity
    let copy: String
    /// Seconds before auto-dismiss. Use `TimeInterval.infinity` for manual-dismiss-only.
    let duration: TimeInterval
    let source: Source
    /// Optional inline action button.
    let action: ToastAction?
    /// Stable identifier for condition-bound toasts.
    /// `ToastManager.dismissByCondition(_:)` removes toasts sharing this ID
    /// when the underlying condition clears (e.g. silence resolves).
    let conditionID: String?

    // MARK: - Init

    init(
        id: UUID = UUID(),
        severity: Severity,
        copy: String,
        duration: TimeInterval = 4,
        source: Source = .generic,
        action: ToastAction? = nil,
        conditionID: String? = nil
    ) {
        self.id = id
        self.severity = severity
        self.copy = copy
        self.duration = duration
        self.source = source
        self.action = action
        self.conditionID = conditionID
    }
}
