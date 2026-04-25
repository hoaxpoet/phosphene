// SessionStateViewModel — Bridges SessionManager into the SwiftUI view layer.
//
// Observes SessionManager.state and publishes it for view routing in ContentView.
// Forwards reduceMotion from AccessibilityState (U.9 migration: was direct
// NSWorkspace read; now sourced from AccessibilityState for consistent
// SettingsStore preference + system flag combination).
//
// If Combine + @MainActor interaction causes compilation issues under Swift 6,
// the assignment-sink pattern used here (receive(on:).assign(to:on:)) is the
// recommended fallback over manual objectWillChange subscriptions.

import Combine
import Session
import SwiftUI

// MARK: - SessionStateViewModel

/// Bridges `SessionManager` state into the SwiftUI view hierarchy.
///
/// Owned by the app entry point; passed to `ContentView` via its initializer.
/// Views observe `state` to determine which top-level view to show.
/// `reduceMotion` is forwarded from `AccessibilityState` — it combines the system
/// `NSWorkspace` flag with the user's `ReducedMotionPreference` from `SettingsStore`.
@MainActor
final class SessionStateViewModel: ObservableObject {

    // MARK: - Published

    /// Current session lifecycle state. Mirrors `SessionManager.state`.
    @Published private(set) var state: SessionState

    /// Effective reduce-motion state (system flag × user preference).
    /// Forwarded from `AccessibilityState`. Used by ContentView to pass
    /// into PlaybackView and ReadyView.
    @Published private(set) var reduceMotion: Bool

    // MARK: - Private

    private let sessionManager: SessionManager
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    /// Create a view model backed by the given session manager and accessibility state.
    ///
    /// - Parameters:
    ///   - sessionManager: The shared session manager instance.
    ///   - accessibilityState: Single source of truth for reduce-motion state.
    init(sessionManager: SessionManager, accessibilityState: AccessibilityState) {
        self.sessionManager = sessionManager
        self.state = sessionManager.state
        self.reduceMotion = accessibilityState.reduceMotion

        sessionManager.$state
            .receive(on: DispatchQueue.main)
            .assign(to: \.state, on: self)
            .store(in: &cancellables)

        accessibilityState.$reduceMotion
            .receive(on: DispatchQueue.main)
            .assign(to: \.reduceMotion, on: self)
            .store(in: &cancellables)
    }
}
