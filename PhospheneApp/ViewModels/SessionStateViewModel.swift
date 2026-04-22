// SessionStateViewModel — Bridges SessionManager into the SwiftUI view layer.
//
// Observes SessionManager.state and publishes it for view routing in ContentView.
// Also tracks the system reduce-motion preference (planted for U.6/U.9 consumption).
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
/// Views observe `state` to determine which top-level view to show. The
/// `reduceMotion` property is planted for U.6 (overlay animation) and U.9
/// (mv_warp gating) and has no consumer in U.1.
@MainActor
final class SessionStateViewModel: ObservableObject {

    // MARK: - Published

    /// Current session lifecycle state. Mirrors `SessionManager.state`.
    @Published private(set) var state: SessionState

    /// Whether the system reduce-motion accessibility setting is active.
    /// Updated live via `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification`.
    @Published private(set) var reduceMotion: Bool

    // MARK: - Private

    private let sessionManager: SessionManager
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    /// Create a view model backed by the given session manager.
    ///
    /// - Parameter sessionManager: The shared session manager instance.
    init(sessionManager: SessionManager) {
        self.sessionManager = sessionManager
        self.state = sessionManager.state
        self.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        sessionManager.$state
            .receive(on: DispatchQueue.main)
            .assign(to: \.state, on: self)
            .store(in: &cancellables)

        NotificationCenter.default.publisher(
            for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
            self?.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        }
        .store(in: &cancellables)
    }
}
