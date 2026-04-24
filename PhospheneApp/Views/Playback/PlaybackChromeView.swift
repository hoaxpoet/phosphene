// PlaybackChromeView — Overlay chrome composition for the .playing state.
//
// Three surfaces:
//   top-leading:  TrackInfoCardView
//   top-trailing: PlaybackControlsCluster
//   top-center:   ListeningBadgeView
//   bottom-trailing: toast slot (ToastContainerView, wired in Part C)
//
// The entire chrome layer opacity-animates to 0 on auto-hide. When hidden,
// allowsHitTesting is false so no interactions are intercepted.

import SwiftUI

// MARK: - PlaybackChromeView

/// Auto-hiding overlay chrome layer for PlaybackView.
///
/// Composed as a ZStack and placed as `.overlay` on the full-bleed MetalView.
struct PlaybackChromeView: View {

    static let accessibilityID = "phosphene.playback.chrome"

    @ObservedObject var viewModel: PlaybackChromeViewModel
    let toastManager: ToastManager
    let onEndSession: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Top-leading: track info
            TrackInfoCardView(
                trackInfo: viewModel.currentTrack,
                preset: viewModel.currentPreset,
                orchestratorState: viewModel.orchestratorState
            )
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            // Top-trailing: controls cluster
            PlaybackControlsCluster(
                progress: viewModel.sessionProgress,
                reduceMotion: viewModel.reduceMotion,
                onSettings: {
                    // TODO(U.8): open Settings sheet
                },
                onEndSession: onEndSession
            )
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

            // Top-center: listening badge
            ListeningBadgeView(
                isVisible: viewModel.showListeningBadge,
                reduceMotion: viewModel.reduceMotion
            )
            .padding(.top, 48)
            .frame(maxWidth: .infinity, alignment: .top)
            .frame(maxHeight: .infinity, alignment: .top)

            // Bottom-trailing: toast container (Part C)
            ToastContainerView(toastManager: toastManager)
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .opacity(viewModel.overlayVisible ? 1 : 0)
        .animation(
            viewModel.reduceMotion ? .none : .easeInOut(duration: 0.5),
            value: viewModel.overlayVisible
        )
        .allowsHitTesting(viewModel.overlayVisible)
        .accessibilityIdentifier(Self.accessibilityID)
    }
}
