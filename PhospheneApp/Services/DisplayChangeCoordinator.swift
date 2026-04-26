// DisplayChangeCoordinator — Resilience contract for display hot-plug events (Increment 7.2).
//
// Provides the engine-side response to NSScreen add/remove/window-move events that
// MultiDisplayToastBridge already detects. The bridge handles user-facing toasts;
// this coordinator handles engine-state correctness guarantees:
//
//   · FrameBudgetManager rolling window is cleared so transient post-reparent frames
//     don't poison the ML scheduler's "is render clean right now?" signal.
//   · SessionManager.state, livePlan, and current preset ID are not modified.
//   · SessionRecorder relock happens via the existing drawable-size path (3.5.4.8),
//     not here — the coordinator's job is to reset auxiliary state only. D-061(a).
//
// Threading: @MainActor throughout. Subscriptions to DisplayManager.$currentScreen
// and $allScreens arrive on the main queue.

import AppKit
import Combine
import Foundation
import os.log
import Renderer

private let logger = Logger(subsystem: "com.phosphene.app", category: "DisplayChangeCoordinator")

// MARK: - DisplayChangeCoordinator

/// Coordinates engine-side resilience responses to display hot-plug and window-move events.
///
/// Owned by `PlaybackView` as `@State`, wired in `setup()` alongside `DisplayManager`
/// and `MultiDisplayToastBridge`. Does NOT replace or wrap those two — subscribes
/// independently via Combine. D-061(a).
@MainActor
final class DisplayChangeCoordinator {

    // MARK: - Event Type

    /// The kind of display change that was processed.
    enum Event: Sendable, Equatable {
        case screenAdded
        case screenRemoved(wasActive: Bool)
        case windowMovedToScreen
    }

    // MARK: - State

    private(set) var lastEvent: Event?
    private(set) var lastEventAt: Date?

    // MARK: - Dependencies

    private weak var displayManager: DisplayManager?
    private weak var frameBudgetManager: FrameBudgetManager?

    // MARK: - Combine

    private var cancellables = Set<AnyCancellable>()
    private var previousAllScreens: Set<NSScreen> = []
    private var previousCurrentScreen: NSScreen?

    // MARK: - Init

    init(
        displayManager: DisplayManager,
        frameBudgetManager: FrameBudgetManager?
    ) {
        self.displayManager = displayManager
        self.frameBudgetManager = frameBudgetManager
        self.previousAllScreens = Set(NSScreen.screens)
        self.previousCurrentScreen = displayManager.currentScreen

        displayManager.$allScreens
            .dropFirst()
            .sink { [weak self] screens in
                self?.handleScreenSetChange(newScreens: screens)
            }
            .store(in: &cancellables)

        displayManager.$currentScreen
            .dropFirst()
            .sink { [weak self] screen in
                self?.handleCurrentScreenChange(newScreen: screen)
            }
            .store(in: &cancellables)
    }

    // MARK: - Private

    private func handleScreenSetChange(newScreens: [NSScreen]) {
        let new = Set(newScreens)
        let added = new.subtracting(previousAllScreens)
        let removed = previousAllScreens.subtracting(new)

        if !added.isEmpty {
            recordEvent(.screenAdded)
            logger.info("DisplayChangeCoordinator: screen(s) added — no engine action needed")
        }

        if !removed.isEmpty {
            let wasActive = removed.contains(where: { $0 == previousCurrentScreen })
            recordEvent(.screenRemoved(wasActive: wasActive))

            if wasActive {
                // Post-reparent frames are transient; clear the rolling window so the
                // ML scheduler doesn't see them as "clean". currentLevel is preserved. D-061(a).
                frameBudgetManager?.resetRecentFrameBuffer()
                logger.info("DisplayChangeCoordinator: active screen removed — rolling buffer cleared")
            } else {
                logger.info("DisplayChangeCoordinator: inactive screen removed — no engine action")
            }
        }

        previousAllScreens = new
    }

    private func handleCurrentScreenChange(newScreen: NSScreen?) {
        guard newScreen != previousCurrentScreen else { return }

        // Screen identity change without a plug/unplug = window moved to another display.
        let allScreensUnchanged = Set(NSScreen.screens) == previousAllScreens
        if allScreensUnchanged {
            recordEvent(.windowMovedToScreen)
            frameBudgetManager?.resetRecentFrameBuffer()
            let name = newScreen?.localizedName ?? "unknown"
            logger.info("DisplayChangeCoordinator: window moved to '\(name)' — rolling buffer cleared")
        }

        previousCurrentScreen = newScreen
    }

    private func recordEvent(_ event: Event) {
        lastEvent = event
        lastEventAt = Date()
    }
}
