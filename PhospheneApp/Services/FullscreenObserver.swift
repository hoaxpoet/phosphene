// FullscreenObserver — Tracks NSWindow fullscreen state via system notifications.

import AppKit
import Foundation

// MARK: - FullscreenObserver

/// Observes `NSWindow.didEnterFullScreenNotification` and `didExitFullScreenNotification`
/// to maintain an authoritative `isFullscreen` flag.
///
/// Associated with a single `NSWindow`. Call `attach(to:)` from `PlaybackView.onAppear`
/// and `detach()` from `onDisappear`.
@MainActor
final class FullscreenObserver: ObservableObject {

    // MARK: - Published

    @Published private(set) var isFullscreen: Bool = false

    // MARK: - Private

    nonisolated(unsafe) private var enterObserver: Any?
    nonisolated(unsafe) private var exitObserver: Any?
    private weak var window: NSWindow?

    // MARK: - Init

    init() {}

    // MARK: - Attach / Detach

    /// Start observing fullscreen transitions on `window`.
    func attach(to window: NSWindow) {
        self.window = window
        isFullscreen = window.styleMask.contains(.fullScreen)

        enterObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didEnterFullScreenNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.isFullscreen = true }
        }

        exitObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didExitFullScreenNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.isFullscreen = false }
        }
    }

    /// Stop observing and release the window reference.
    func detach() {
        if let obs = enterObserver { NotificationCenter.default.removeObserver(obs) }
        if let obs = exitObserver { NotificationCenter.default.removeObserver(obs) }
        enterObserver = nil
        exitObserver = nil
        window = nil
    }

    // MARK: - Actions

    /// Toggle fullscreen on the associated window.
    func toggleFullscreen() {
        window?.toggleFullScreen(nil)
    }

    deinit {
        // Safe: observers are removed before retain cycle can form.
        if let obs = enterObserver { NotificationCenter.default.removeObserver(obs) }
        if let obs = exitObserver { NotificationCenter.default.removeObserver(obs) }
    }
}
