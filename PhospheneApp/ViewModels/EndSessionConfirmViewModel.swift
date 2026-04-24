// EndSessionConfirmViewModel — State for the Esc-triggered end-session confirmation dialog.

import Foundation
import Session

// MARK: - EndSessionConfirmViewModel

/// Drives the confirmation dialog shown when the user presses Esc (windowed mode)
/// or clicks the close button on the playback chrome.
///
/// `.confirm()` calls through to `SessionManager.endSession()`.
/// `.cancel()` dismisses without side effects.
@MainActor
final class EndSessionConfirmViewModel: ObservableObject {

    // MARK: - Published

    @Published var isPresented: Bool = false

    // MARK: - Private

    private let sessionManager: SessionManager

    // MARK: - Init

    init(sessionManager: SessionManager) {
        self.sessionManager = sessionManager
    }

    // MARK: - API

    /// Show the confirmation dialog.
    func requestEnd() {
        isPresented = true
    }

    /// User confirmed — end the session and dismiss.
    func confirm() {
        isPresented = false
        sessionManager.endSession()
    }

    /// User cancelled — dismiss without side effects.
    func cancel() {
        isPresented = false
    }
}
