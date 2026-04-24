// DisplayManager — Tracks connected displays and moves the window between them.
//
// Screen identification: NSScreen.main is the primary (menu bar) screen.
// Moving between displays in fullscreen requires exit → move → re-enter because
// macOS doesn't support a direct fullscreen-window migration between screens.
// This is the "fullscreen quirk" documented in Apple DTS notes.

import AppKit
import Foundation
import os.log

private let logger = Logger(subsystem: "com.phosphene.app", category: "DisplayManager")

// MARK: - DisplayManager

/// Tracks the set of connected `NSScreen`s and provides display-move actions.
///
/// Observes `NSApplication.didChangeScreenParametersNotification` for hot-plug events.
/// Disconnects trigger automatic reparenting to the primary screen.
@MainActor
final class DisplayManager: ObservableObject {

    // MARK: - Published

    @Published private(set) var allScreens: [NSScreen] = NSScreen.screens
    @Published private(set) var currentScreen: NSScreen? = NSScreen.main
    @Published private(set) var primaryScreen: NSScreen? = NSScreen.main

    // MARK: - Private

    private weak var window: NSWindow?
    nonisolated(unsafe) private var screenChangeObserver: Any?
    private let fullscreenObserver: FullscreenObserver

    // MARK: - Init

    init(fullscreenObserver: FullscreenObserver) {
        self.fullscreenObserver = fullscreenObserver
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleScreenChange() }
        }
    }

    deinit {
        if let obs = screenChangeObserver { NotificationCenter.default.removeObserver(obs) }
    }

    // MARK: - Attach

    func attach(to window: NSWindow) {
        self.window = window
        currentScreen = window.screen
        primaryScreen = NSScreen.main
    }

    // MARK: - Move Actions

    /// Move the window to the next non-primary screen, cycling if multiple are connected.
    func moveToSecondaryDisplay() {
        let screens = NSScreen.screens
        let primary = NSScreen.main
        let nonPrimary = screens.filter { $0 != primary }

        guard !nonPrimary.isEmpty else {
            logger.info("DisplayManager: only one display connected — no move")
            return
        }

        let target: NSScreen
        if let current = window?.screen,
           let idx = nonPrimary.firstIndex(of: current),
           nonPrimary.count > 1 {
            // Cycle to next non-primary
            target = nonPrimary[(idx + 1) % nonPrimary.count]
        } else {
            target = nonPrimary[0]
        }

        moveWindow(to: target)
    }

    /// Move the window back to the primary (menu-bar) screen.
    func moveToPrimaryDisplay() {
        guard let primary = NSScreen.main else { return }
        moveWindow(to: primary)
    }

    // MARK: - Private

    private func moveWindow(to screen: NSScreen) {
        guard let window else { return }

        if fullscreenObserver.isFullscreen {
            // Quirk: macOS requires exit → move → re-enter for cross-screen fullscreen.
            // The re-enter happens via a notification observer on didExitFullScreen.
            window.toggleFullScreen(nil)
            let targetFrame = screen.visibleFrame
            let enterOnExit = NotificationCenter.default.addObserver(
                forName: NSWindow.didExitFullScreenNotification,
                object: window,
                queue: .main
            ) { [weak window] _ in
                MainActor.assumeIsolated {
                    window?.setFrame(targetFrame, display: true)
                    window?.toggleFullScreen(nil)
                }
            }
            // Clean up observer after 3s (belt + suspenders).
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(3))
                _ = self // suppress capture warning
                NotificationCenter.default.removeObserver(enterOnExit)
            }
        } else {
            let origin = CGPoint(
                x: screen.visibleFrame.midX - window.frame.width / 2,
                y: screen.visibleFrame.midY - window.frame.height / 2
            )
            window.setFrameOrigin(origin)
        }

        currentScreen = screen
        logger.info("DisplayManager: moved to '\(screen.localizedName)'")
    }

    private func handleScreenChange() {
        let prev = allScreens
        allScreens = NSScreen.screens
        primaryScreen = NSScreen.main
        currentScreen = window?.screen ?? NSScreen.main

        let added   = Set(allScreens).subtracting(Set(prev))
        let removed = Set(prev).subtracting(Set(allScreens))

        if !added.isEmpty {
            logger.info("DisplayManager: screens added: \(added.map(\.localizedName))")
            onScreensAdded(added)
        }

        if !removed.isEmpty {
            logger.info("DisplayManager: screens removed: \(removed.map(\.localizedName))")
            onScreensRemoved(removed)
        }
    }

    // MARK: - Callbacks (overridden by MultiDisplayToastBridge)

    var onScreensAdded: (Set<NSScreen>) -> Void = { _ in }
    var onScreensRemoved: (Set<NSScreen>) -> Void = { _ in }
}
