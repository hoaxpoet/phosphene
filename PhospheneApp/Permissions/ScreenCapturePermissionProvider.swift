// ScreenCapturePermissionProvider — Abstracts CGPreflightScreenCaptureAccess for testability.
// Never calls CGRequestScreenCaptureAccess (system dialog doesn't compose with URL-scheme flow).

import CoreGraphics

// MARK: - Protocol

/// Abstracts screen-capture permission state so `PermissionMonitor` can be tested without
/// the system permission dialog.
protocol ScreenCapturePermissionProviding: Sendable {
    /// Returns the current screen-capture permission status without prompting the user.
    func isGranted() -> Bool
}

// MARK: - Production Implementation

/// Production provider backed by `CGPreflightScreenCaptureAccess`. Never prompts.
struct SystemScreenCapturePermissionProvider: ScreenCapturePermissionProviding {
    func isGranted() -> Bool {
        CGPreflightScreenCaptureAccess()
    }
}
