// PlaybackChromeView — Overlay chrome composition for the .playing state.
//
// Three surfaces:
//   top-leading:  TrackInfoCardView
//   top-trailing: PlaybackControlsCluster (+ "still preparing" teal dot when applicable)
//   top-center:   ListeningBadgeView
//   bottom-trailing: toast slot (ToastContainerView, wired in Part C)
//
// The entire chrome layer opacity-animates to 0 on auto-hide. When hidden,
// allowsHitTesting is false so no interactions are intercepted.

import SwiftUI

// MARK: - PreparationBackgroundIndicator

/// Subtle teal dot shown while background track preparation is still in flight (6.1).
private struct PreparationBackgroundIndicator: View {

    @State private var visible = false

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color.teal)
                .frame(width: 4, height: 4)
            Text(String(localized: "playback.still_preparing"))
                .font(.caption2)
                .foregroundColor(.teal.opacity(0.85))
        }
        .opacity(visible ? 1 : 0)
        .animation(.easeIn(duration: 0.4), value: visible)
        .onAppear { visible = true }
        .help(String(localized: "playback.still_preparing.tooltip"))
    }
}

// MARK: - PlaybackChromeView

/// Auto-hiding overlay chrome layer for PlaybackView.
///
/// Composed as a ZStack and placed as `.overlay` on the full-bleed MetalView.
struct PlaybackChromeView: View {

    static let accessibilityID = "phosphene.playback.chrome"

    @ObservedObject var viewModel: PlaybackChromeViewModel
    let toastManager: ToastManager
    let onSettings: () -> Void
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

            // Top-trailing: controls cluster + optional "still preparing" indicator
            VStack(alignment: .trailing, spacing: 4) {
                PlaybackControlsCluster(
                    progress: viewModel.sessionProgress,
                    reduceMotion: viewModel.reduceMotion,
                    onSettings: onSettings,
                    onEndSession: onEndSession
                )
                if viewModel.isBackgroundPreparationActive {
                    PreparationBackgroundIndicator()
                }
            }
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
