// PlaybackControlsCluster — Top-trailing overlay: progress dots + track info + settings + end.
//
// DS.6: the `PerformanceControls` component (COMPONENTS.md). Three controls — Show/Hide
// track info (the same words DS.4a gave the preparation screen, D-239), Settings, End
// session — behind the session-position dots. Every control declares a label and a
// hint that says what it does now.

import SwiftUI

// MARK: - PlaybackControlsCluster

/// Horizontal cluster of in-session controls: track-progress dots, track-info toggle,
/// settings, end-session.
///
/// Sits top-trailing on `PlaybackChromeView` with a 24 pt inset.
struct PlaybackControlsCluster: View {

    static let accessibilityID = "uzume.playback.controlsCluster"
    static let toggleTrackInfoID = "uzume.playback.toggleTrackInfo"
    static let endSessionID = "uzume.playback.endSession"

    let progress: SessionProgressData
    let reduceMotion: Bool
    @Binding var showTrackInformation: Bool
    let onSettings: () -> Void
    let onEndSession: () -> Void

    var body: some View {
        HStack(spacing: UzumeSpace.x3) {
            SessionProgressDotsView(progress: progress, reduceMotion: reduceMotion)

            Rectangle()
                .fill(UzumeAppColor.line)
                .frame(width: 1, height: 16)

            trackInfoToggle

            ClusterButton(
                symbol: "gearshape",
                label: String(localized: "playback.controls.settings.tooltip"),
                hint: String(localized: "a11y.playback.settings.hint"),
                action: onSettings
            )

            ClusterButton(
                symbol: "xmark.circle",
                label: String(localized: "playback.controls.endSession.tooltip"),
                hint: String(localized: "a11y.playback.endSession.hint"),
                action: onEndSession
            )
            .accessibilityIdentifier(Self.endSessionID)
        }
        .padding(.horizontal, UzumeSpace.x3)
        .padding(.vertical, UzumeSpace.x2)
        .performanceBackdrop()
        .accessibilityIdentifier(Self.accessibilityID)
    }

    // MARK: - Subviews

    private var trackInfoToggle: some View {
        ClusterButton(
            symbol: showTrackInformation ? "info.circle.fill" : "info.circle",
            label: String(localized: showTrackInformation
                ? "preparation.toggle_track_info.hide"
                : "preparation.toggle_track_info.show"),
            hint: String(localized: showTrackInformation
                ? "a11y.playback.toggleTrackInfo.hint.hide"
                : "a11y.playback.toggleTrackInfo.hint.show"),
            action: { showTrackInformation.toggle() }
        )
        .accessibilityIdentifier(Self.toggleTrackInfoID)
    }
}

// MARK: - ClusterButton

/// One icon control in the cluster: tooltip, VoiceOver label and hint all say what it
/// does now (CLAUDE.md's unmechanized rule).
private struct ClusterButton: View {

    let symbol: String
    let label: String
    let hint: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.callout)
                .foregroundColor(UzumeAppColor.textSecondary)
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityHint(hint)
    }
}
