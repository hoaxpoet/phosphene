// UzumeToast — Toast notification model for in-session status messages.

import Foundation
import Shared

// MARK: - UzumeToast

/// A transient in-session notification shown in the bottom-right toast slot.
///
/// Toasts are managed by `ToastManager`. Up to three are visible simultaneously.
/// Degradation- and fatal-severity toasts are never auto-dropped when the queue overflows.
struct UzumeToast: Identifiable, Equatable, Sendable {

    // MARK: - Severity

    /// Visual priority of the toast.
    ///
    /// Mirrors `ErrorSeverity` one-for-one as of DS.3a (D-236). It gained `fatal` because
    /// `PlaybackErrorBridge` was folding fatal errors into `degradation` before any view
    /// could see them — the distinction died in this enum's narrowness, which is why the
    /// silence toast could not be told apart from a dropped stem.
    ///
    /// Tone comes from `StatusTone.from(_:)`; these cases carry priority, never colour.
    enum Severity: Equatable, Sendable {
        case info         // Informational (display connect, adaptation ack)
        case warning      // The session continues (display disconnect)
        case degradation  // Uzume is coping but compromised (dropped stem, missing preview)
        case fatal        // Uzume is not delivering (no audio detected)

        /// The one place an `ErrorSeverity` becomes a toast severity. Both enums carry
        /// the same four cases (D-236), so nothing is folded — the `.degradation, .fatal`
        /// collapse this replaced is what hid fatal from every view, and made the silence
        /// toast indistinguishable from a dropped stem.
        init(_ severity: ErrorSeverity) {
            switch severity {
            case .info:        self = .info
            case .warning:     self = .warning
            case .degradation: self = .degradation
            case .fatal:       self = .fatal
            }
        }
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
