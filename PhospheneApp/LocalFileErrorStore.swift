// LocalFileErrorStore — GAP F (2026-05-28). Replaces NSAlert modals for
// non-destructive LF errors with inline messages that appear in IdleView
// and LocalSourceConnectionView.
//
// Per .impeccable.md design context: "No modal dialogs except for destructive
// confirmation." The LF.5 picker flow previously surfaced unsupported-format
// / unreadable / m3u-parse-failed / empty-folder errors as `NSAlert` modals
// — none of those are destructive, and the user lives in a sheet anyway.
// They belong inline.
//
// The store auto-clears the error after 6 seconds so a drag-drop error
// fired while the user is in `.playing` (and won't see the inline surface)
// doesn't leak into the next IdleView render. Tap to dismiss earlier.
//
// Shared as a `static let shared` singleton because `LocalFileMenuCommands`
// is a static enum and threading the store through every entry point would
// be intrusive. Tests get their own instance via the internal `init()` if
// they need to.

import Foundation
import Shared
import SwiftUI

// MARK: - UserFacingLocalFileError

/// Four pre-session error classes the LF picker flow can surface. Each maps
/// to a Localizable.strings key in the existing `lf.open.error.*` namespace
/// so we don't duplicate copy.
public enum UserFacingLocalFileError: Equatable, Sendable {
    case unsupportedFormat
    case unreadable
    case m3uParseFailed
    case emptyFolder

    /// Localized inline message shown in IdleView / LocalSourceConnectionView.
    public var localizedMessage: String {
        switch self {
        case .unsupportedFormat:
            return String(localized: "lf.open.error.unsupported_format")
        case .unreadable:
            return String(localized: "lf.open.error.unreadable")
        case .m3uParseFailed:
            return String(localized: "lf.open.error.m3u_parse_failed")
        case .emptyFolder:
            return String(localized: "lf.open.error.empty_folder")
        }
    }
}

// MARK: - LocalFileErrorStore

@MainActor
public final class LocalFileErrorStore: ObservableObject {

    /// Production-shared instance. Use this from static call sites in
    /// `LocalFileMenuCommands` and inject via `.environmentObject(...)` in
    /// `PhospheneApp` so SwiftUI consumers observe the same publisher.
    public static let shared = LocalFileErrorStore()

    /// Most recent error, or `nil` if no error is active. Auto-clears 6 s
    /// after `report(_:)` so a stale error doesn't leak into IdleView's
    /// next render if the user was in `.playing` when the error fired.
    @Published public private(set) var lastError: UserFacingLocalFileError?

    private var clearTask: Task<Void, Never>?
    private static let autoClearDelaySeconds: UInt64 = 6

    /// Internal — production uses `shared`. Tests construct their own.
    init() {}

    /// Surface an error. Cancels any in-flight auto-clear and schedules a
    /// new one. Reporting the same error twice in succession resets the
    /// auto-clear timer (so quick-fire double-drops keep the message
    /// visible for the full window).
    public func report(_ error: UserFacingLocalFileError) {
        lastError = error
        clearTask?.cancel()
        clearTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.autoClearDelaySeconds * 1_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.lastError = nil }
        }
    }

    /// Clear the active error immediately (tap-to-dismiss path or a
    /// successful subsequent action).
    public func clear() {
        clearTask?.cancel()
        clearTask = nil
        lastError = nil
    }
}

// MARK: - LocalFileErrorBanner

/// GAP F (2026-05-28) inline error surface. Renders a coral pip + the
/// localized message; tap-to-dismiss. Used by IdleView and
/// LocalSourceConnectionView. No background, no side-stripe, no modal —
/// just text with a small mark that signals "this is an error message,
/// not just decorative text."
struct LocalFileErrorBanner: View {

    let message: String
    let onDismiss: () -> Void

    var body: some View {
        Button(action: onDismiss) {
            HStack(spacing: 10) {
                Circle()
                    .fill(Color(nsColor: DashboardTokens.Color.coral))
                    .frame(width: 6, height: 6)
                Text(verbatim: message)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.85))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .transition(.opacity)
    }
}
