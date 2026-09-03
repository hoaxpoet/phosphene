// PlaybackChromeView — Overlay chrome composition for the .playing state.
//
// The `PerformanceChrome` composition (COMPONENTS.md), retokenized in place at DS.6:
//   top-leading:     TrackInfoCardView — only while the listener shows track information
//   top-trailing:    PlaybackControlsCluster (+ the "still preparing" status beneath it)
//   top-centre:      ListeningBadgeView
//   bottom-centre:   LocalFileTransportBar (local-file sessions only)
//   bottom-trailing: ToastRegion
//
// Three visibility states, owned by `PlaybackChromeViewModel` (D-241):
//   .full   — everything above, hit-testable.
//   .quiet  — after inactivity: the cluster reduces to End session alone and every
//             other surface fades. The chrome can go quiet but never undiscoverable
//             (DESIGN.md §Curator Control Surface).
//   .hidden — the Space toggle only: nothing drawn, nothing hit-testable.
// Transitions are the standard 240 ms state change; reduced motion crossfades.

import SwiftUI

// MARK: - PreparationBackgroundIndicator

/// "Still preparing" — shown while background track preparation is still in flight (6.1).
///
/// A status, so it takes its tone from `StatusTone` like every other status surface
/// (D-234): symbol + text in the tone's foreground on its field, never a colour of its own.
/// It is opaque, so it owes the live frame no contrast measurement.
private struct PreparationBackgroundIndicator: View {

    @State private var visible = false
    let reduceMotion: Bool

    private let tone: StatusTone = .info

    var body: some View {
        HStack(spacing: UzumeSpace.x1) {
            Image(systemName: tone.symbol)
                .font(.caption2)
            Text(String(localized: "playback.still_preparing"))
                .font(.caption2)
        }
        .foregroundColor(tone.foreground)
        .padding(.horizontal, UzumeSpace.x2)
        .padding(.vertical, UzumeSpace.x1)
        .background(tone.background)
        .overlay(RoundedRectangle(cornerRadius: UzumeAppRadius.sm).stroke(tone.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: UzumeAppRadius.sm))
        .opacity(visible ? 1 : 0)
        .animation(UzumeAppMotion.stateChange(reduceMotion: reduceMotion), value: visible)
        .onAppear { visible = true }
        .help(String(localized: "playback.still_preparing.tooltip"))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "playback.still_preparing"))
        .accessibilityHint(String(localized: "playback.still_preparing.tooltip"))
    }
}

// MARK: - PlaybackChromeView

/// Auto-quieting overlay chrome layer for PlaybackView.
///
/// Composed as a ZStack and placed as `.overlay` on the full-bleed MetalView.
struct PlaybackChromeView: View {

    static let accessibilityID = "uzume.playback.chrome"

    @ObservedObject var viewModel: PlaybackChromeViewModel
    let toastManager: ToastManager
    /// `uzume.settings.visuals.showTrackInformation` — bound, so the cluster's control and
    /// Settings move the same value (DS.6).
    @Binding var showTrackInformation: Bool
    let onSettings: () -> Void
    let onEndSession: () -> Void
    /// LF.5.fix D-LF5-3 transport-bar callbacks. Default no-ops keep streaming-
    /// path callers (and tests) source-compatible — the bar only renders when
    /// `viewModel.isLocalFileSession == true`.
    var onLocalFileStop: () -> Void = {}
    var onLocalFilePrev: () -> Void = {}
    var onLocalFilePlayPause: () -> Void = {}
    var onLocalFileNext: () -> Void = {}

    private var isFull: Bool { viewModel.visibility == .full }
    private var motion: Animation { UzumeAppMotion.stateChange(reduceMotion: viewModel.reduceMotion) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Top-leading: the current track. Gone from the tree, not faded, when hidden.
            if showTrackInformation {
                TrackInfoCardView(
                    trackInfo: viewModel.currentTrack,
                    preset: viewModel.currentPreset,
                    isLocalFileSession: viewModel.isLocalFileSession
                )
                .padding(UzumeSpace.x6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .fadesUnlessFull(isFull, motion: motion)
            }

            // Top-trailing: controls cluster (reduces to End session when quiet) +
            // the "still preparing" status.
            VStack(alignment: .trailing, spacing: UzumeSpace.x1) {
                PlaybackControlsCluster(
                    progress: viewModel.sessionProgress,
                    reduceMotion: viewModel.reduceMotion,
                    showTrackInformation: $showTrackInformation,
                    quiet: viewModel.visibility == .quiet,
                    onSettings: onSettings,
                    onEndSession: onEndSession
                )
                if viewModel.isBackgroundPreparationActive {
                    PreparationBackgroundIndicator(reduceMotion: viewModel.reduceMotion)
                        .fadesUnlessFull(isFull, motion: motion)
                }
            }
            .padding(UzumeSpace.x6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

            // Top-centre: listening badge
            ListeningBadgeView(
                isVisible: viewModel.showListeningBadge,
                reduceMotion: viewModel.reduceMotion
            )
            .padding(.top, UzumeSpace.x12)
            .frame(maxWidth: .infinity, alignment: .top)
            .frame(maxHeight: .infinity, alignment: .top)
            .fadesUnlessFull(isFull, motion: motion)

            // Bottom-centre: LF.5.fix D-LF5-3 transport bar (LF mode only).
            if viewModel.isLocalFileSession {
                LocalFileTransportBar(
                    isPaused: viewModel.isLocalFilePaused,
                    onStop: onLocalFileStop,
                    onPrev: onLocalFilePrev,
                    onPlayPause: onLocalFilePlayPause,
                    onNext: onLocalFileNext
                )
                .padding(.bottom, 36)
                .frame(maxWidth: .infinity, alignment: .center)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .fadesUnlessFull(isFull, motion: motion)
            }

            // Bottom-trailing: toasts
            ToastRegion(toastManager: toastManager, reduceMotion: viewModel.reduceMotion)
                .padding(UzumeSpace.x6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .fadesUnlessFull(isFull, motion: motion)
        }
        .opacity(viewModel.visibility == .hidden ? 0 : 1)
        .animation(motion, value: viewModel.visibility)
        .allowsHitTesting(viewModel.visibility != .hidden)
        .accessibilityIdentifier(Self.accessibilityID)
    }
}

// MARK: - Fade helper

private extension View {
    /// Fades a chrome surface out — and takes it out of hit-testing — whenever the
    /// chrome is not `.full`. The cluster is the one surface that stays for `.quiet`.
    func fadesUnlessFull(_ isFull: Bool, motion: Animation) -> some View {
        opacity(isFull ? 1 : 0)
            .allowsHitTesting(isFull)
            .animation(motion, value: isFull)
    }
}
