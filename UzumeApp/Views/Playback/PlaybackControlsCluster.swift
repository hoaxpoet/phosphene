// PlaybackControlsCluster — Top-right overlay: progress dots + settings + close.

import SwiftUI

// MARK: - PlaybackControlsCluster

/// Horizontal cluster of in-session controls: track-progress dots, settings stub, end-session.
///
/// Sits top-trailing on `PlaybackChromeView` with a 24 pt inset.
struct PlaybackControlsCluster: View {

    static let accessibilityID = "phosphene.playback.controlsCluster"

    let progress: SessionProgressData
    let reduceMotion: Bool
    let onSettings: () -> Void
    let onEndSession: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            SessionProgressDotsView(progress: progress, reduceMotion: reduceMotion)

            Divider()
                .frame(height: 16)
                .opacity(0.4)

            // Settings — U.8 will wire this to the settings sheet.
            Button {
                onSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.callout)
                    .foregroundColor(.white.opacity(0.7))
            }
            .buttonStyle(.plain)
            .help(String(localized: "playback.controls.settings.tooltip"))

            // End session.
            Button {
                onEndSession()
            } label: {
                Image(systemName: "xmark.circle")
                    .font(.callout)
                    .foregroundColor(.white.opacity(0.7))
            }
            .buttonStyle(.plain)
            .help(String(localized: "playback.controls.endSession.tooltip"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .overlayBackdrop()
        .accessibilityIdentifier(Self.accessibilityID)
    }
}
