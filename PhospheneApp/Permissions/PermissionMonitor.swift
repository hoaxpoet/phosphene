// PermissionMonitor — Publishes screen-capture permission state; refreshes on foreground.
//
// Observes NSApplication.didBecomeActiveNotification so returning from System Settings
// after granting permission automatically advances the UI without requiring a user click.

import AppKit
import Combine

// MARK: - PermissionMonitor

/// `@MainActor` observable that publishes `isScreenCaptureGranted` and re-reads it
/// whenever the app re-enters the foreground.
///
/// Owned by `PhospheneApp` as a `@StateObject`; injected into the view hierarchy as
/// an environment object so `ContentView` can gate the session-state switch on it.
@MainActor
final class PermissionMonitor: ObservableObject {

    // MARK: - Published

    /// `true` when `CGPreflightScreenCaptureAccess()` reports permission granted.
    /// Updated immediately on init and on every `NSApplication.didBecomeActiveNotification`.
    @Published private(set) var isScreenCaptureGranted: Bool

    // MARK: - Private

    private let provider: any ScreenCapturePermissionProviding
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    /// - Parameters:
    ///   - provider: Permission-state source. Defaults to the system CGPreflight call.
    ///   - notificationCenter: Notification centre to observe. Injectable for tests.
    init(
        provider: any ScreenCapturePermissionProviding = SystemScreenCapturePermissionProvider(),
        notificationCenter: NotificationCenter = .default
    ) {
        self.provider = provider
        self.isScreenCaptureGranted = provider.isGranted()

        notificationCenter.publisher(for: NSApplication.didBecomeActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
    }

    // MARK: - Internal

    /// Re-reads permission state from the provider. Called automatically on foreground;
    /// also available as an explicit trigger for tests or force-refresh paths.
    func refresh() {
        isScreenCaptureGranted = provider.isGranted()
    }
}
