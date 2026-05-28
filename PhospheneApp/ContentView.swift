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
    @EnvironmentObject private var recentsStore: LocalFileRecentsStore

    init(viewModel: SessionStateViewModel) {
        self._viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        Group {
            // LF.4: in local-file playback mode the audio path is
            // AVAudioEngine, not Core Audio process taps, so screen-capture
            // permission is irrelevant. Bypass the gate so the visualizer
            // renders even on a fresh install where permission was never
            // granted. The `currentSource` publisher tracks LF state — derived
            // from the canonical SessionManager source rather than a parallel
            // boolean flag (was `engine.localFilePlaybackActive` pre-LF.4).
            if permissionMonitor.isScreenCaptureGranted
                || engine.sessionManager.currentSource?.isLocalFile == true {
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
            ConnectingView(
                source: engine.sessionManager.sessionSource,
                onCancel: { engine.sessionManager.cancel() }
            )
        case .preparing:
            preparingView
        case .ready:
            // LF.4: local-file sessions don't show ReadyView (the user
            // has nothing to confirm — Phosphene IS the player). The engine's
            // `.ready` handler advances to `.playing` in the same MainActor
            // tick; routing the visible UI directly to PlaybackView avoids
            // any flash of ReadyView during the cross-state transition.
            if engine.sessionManager.currentSource?.isLocalFile == true {
                playbackView
            } else {
                readyView
            }
        case .playing:
            playbackView
        case .ended:
            // `cancel()` (not `endSession()`) transitions any state → `.idle` —
            // the prompt assumed endSession() did the .ended → .idle transition,
            // but it transitions any state → `.ended`. cancel() is the documented
            // .idle return path.
            //
            // GAP H (2026-05-28): when the just-ended session was a local-file
            // session, pass the stashed origin + a replay closure so EndedView
            // can offer "Play <name> again." The closure dispatches back through
            // LocalFileMenuCommands to re-open the right source.
            EndedView(
                trackCount: engine.sessionManager.currentPlan?.tracks.count ?? 0,
                sessionDuration: nil,
                onStartNewSession: { engine.sessionManager.cancel() },
                onOpenSessionsFolder: { EndedView.openSessionsFolder() },
                lastLocalFileOrigin: engine.lastEndedLocalFileOrigin,
                onReplayLocalFile: engine.lastEndedLocalFileOrigin.map { origin in
                    { replayLocalFile(origin: origin) }
                }
            )
        }
    }

    /// GAP H: dispatch a stashed LF SessionOrigin back through the LF entry
    /// points. Single files / folders / playlists go through their respective
    /// `openLocal*` helpers (which re-promote to Recents). Flat-drop origins
    /// re-queue the expanded URL list directly.
    @MainActor
    private func replayLocalFile(origin: SessionOrigin) {
        // Returning to .idle first ensures startLocalFiles can take over
        // cleanly (endSession leaves state == .ended; cancel returns to .idle).
        engine.sessionManager.cancel()
        Task { @MainActor in
            switch origin {
            case .localFile(let url):
                await LocalFileMenuCommands.openLocalFile(
                    at: url, engine: engine, recentsStore: recentsStore
                )
            case .localFolder(let folder, _):
                await LocalFileMenuCommands.openLocalFolder(
                    at: folder, engine: engine, recentsStore: recentsStore
                )
            case .localPlaylist(let playlist, _):
                await LocalFileMenuCommands.openLocalM3U(
                    at: playlist, engine: engine, recentsStore: recentsStore
                )
            case .localFiles(let urls):
                await engine.sessionManager.startLocalFiles(at: urls, origin: .localFiles(urls))
            case .playlist:
                break                       // never happens — stash is LF-only
            }
        }
    }

    @ViewBuilder
    private var playbackView: some View {
        PlaybackView(
            sessionManager: engine.sessionManager,
            audioSignalStatePublisher: engine.$audioSignalState.eraseToAnyPublisher(),
            currentTrackPublisher: engine.$currentTrack.eraseToAnyPublisher(),
            currentTrackIndexPublisher: engine.$currentTrackIndex.eraseToAnyPublisher(),
            currentPresetNamePublisher: engine.$currentPresetName.eraseToAnyPublisher(),
            livePlanPublisher: engine.$livePlannedSession.eraseToAnyPublisher(),
            reduceMotionPublisher: accessibilityState.$reduceMotion.eraseToAnyPublisher(),
            progressiveReadinessPublisher: engine.sessionManager.$progressiveReadinessLevel
                .eraseToAnyPublisher(),
            dashboardSnapshotPublisher: engine.$dashboardSnapshot.eraseToAnyPublisher(),
            currentSourcePublisher: engine.sessionManager.$currentSource.eraseToAnyPublisher(),
            isLocalFilePausedPublisher: engine.$isLocalFilePaused.eraseToAnyPublisher(),
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
                // GAP D (2026-05-28): plumb the current SessionOrigin so the
                // preparation header swaps from the generic streaming-path
                // "Preparing your session" to a contextual LF line
                // ("Reading mix.m3u" / "Reading 8 tracks from Tempo" etc.).
                headerContext: engine.sessionManager.currentSource,
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
