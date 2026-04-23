// ContentView — Two-level routing: permission gate → session-state switch.
//
// The permission gate sits above the state switch per UX_SPEC §3.1 ("regardless of
// session state"). When PermissionMonitor.isScreenCaptureGranted is false,
// PermissionOnboardingView renders unconditionally — catching both fresh installs and
// mid-session revocations. When permission flips to true (detected via
// NSApplication.didBecomeActiveNotification), the view tree re-renders and routes to
// whatever SessionState is current.

import SwiftUI

// MARK: - ContentView

/// Routes to the correct top-level view based on permission state and `SessionManager.state`.
///
/// Outer branch: permission gate (`PermissionMonitor.isScreenCaptureGranted`).
/// Inner branch: session-state switch (`SessionStateViewModel.state`).
/// All layout and logic lives in the per-state views and their view models.
struct ContentView: View {
    @StateObject var viewModel: SessionStateViewModel
    @EnvironmentObject private var permissionMonitor: PermissionMonitor

    init(viewModel: SessionStateViewModel) {
        self._viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        Group {
            if permissionMonitor.isScreenCaptureGranted {
                sessionStateBody
            } else {
                PermissionOnboardingView()
            }
        }
    }

    // MARK: - Private

    @ViewBuilder
    private var sessionStateBody: some View {
        switch viewModel.state {
        case .idle:       IdleView()
        case .connecting: ConnectingView()
        case .preparing:  PreparationProgressView()
        case .ready:      ReadyView()
        case .playing:    PlaybackView()
        case .ended:      EndedView()
        }
    }
}
