// ContentView — Two-level routing: permission gate → session-state switch.
//
// The permission gate sits above the state switch per UX_SPEC §3.1 ("regardless of
// session state"). When PermissionMonitor.isScreenCaptureGranted is false,
// PermissionOnboardingView renders unconditionally — catching both fresh installs and
// mid-session revocations. When permission flips to true (detected via
// NSApplication.didBecomeActiveNotification), the view tree re-renders and routes to
// whatever SessionState is current.
//
// U.4: .preparing routes to PreparationProgressView; the ViewModel is owned as
// @StateObject inside the view so it survives re-renders within the same state.
// U.5: .ready routes to ReadyView; dependencies injected so the view's @StateObject
// ViewModel survives re-renders within the same state.

import Combine
import Orchestrator
import Session
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
    @EnvironmentObject private var engine: VisualizerEngine
    @EnvironmentObject private var accessibilityState: AccessibilityState

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
        case .idle:
            IdleView()
        case .connecting:
            ConnectingView()
        case .preparing:
            preparingView
        case .ready:
            readyView
        case .playing:
            playbackView
        case .ended:
            EndedView()
        }
    }

    @ViewBuilder
    private var playbackView: some View {
        PlaybackView(
            sessionManager: engine.sessionManager,
            audioSignalStatePublisher: engine.$audioSignalState.eraseToAnyPublisher(),
            currentTrackPublisher: engine.$currentTrack.eraseToAnyPublisher(),
            currentPresetNamePublisher: engine.$currentPresetName.eraseToAnyPublisher(),
            livePlanPublisher: engine.$livePlannedSession.eraseToAnyPublisher(),
            reduceMotionPublisher: accessibilityState.$reduceMotion.eraseToAnyPublisher(),
            progressiveReadinessPublisher: engine.sessionManager.$progressiveReadinessLevel
                .eraseToAnyPublisher(),
            dashboardSnapshotPublisher: engine.$dashboardSnapshot.eraseToAnyPublisher(),
            onEndSession: { engine.sessionManager.endSession() },
            reduceMotion: viewModel.reduceMotion
        )
    }

    @ViewBuilder
    private var readyView: some View {
        ReadyView(
            sessionSource: engine.sessionManager.sessionSource,
            sessionManager: engine.sessionManager,
            audioSignalStatePublisher: engine.$audioSignalState.eraseToAnyPublisher(),
            planPublisher: engine.$livePlannedSession.eraseToAnyPublisher(),
            onBeginPlayback: { engine.sessionManager.beginPlayback() },
            onRegenerate: { @MainActor lockedTracks, lockedPresets in
                engine.regeneratePlan(lockedTracks: lockedTracks, lockedPresets: lockedPresets)
            },
            reduceMotion: viewModel.reduceMotion
        )
    }

    @ViewBuilder
    private var preparingView: some View {
        if let publisher = engine.sessionManager.preparationProgress {
            PreparationProgressView(
                publisher: publisher,
                tracks: engine.sessionManager.preparingTracks,
                playlistName: "",
                progressiveReadinessPublisher: engine.sessionManager.$progressiveReadinessLevel
                    .eraseToAnyPublisher(),
                sessionManager: engine.sessionManager,
                onCancel: { engine.sessionManager.cancel() },
                onStartNow: { engine.sessionManager.startNow() }
            )
        } else {
            // Fallback (should not normally occur — SessionPreparer is always the publisher).
            VStack(spacing: 12) {
                Text("Preparing")
                    .font(.largeTitle)
                    .foregroundColor(.white)
                Text("Analyzing tracks…")
                    .font(.body)
                    .foregroundColor(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .accessibilityIdentifier(PreparationProgressView.accessibilityID)
        }
    }
}
