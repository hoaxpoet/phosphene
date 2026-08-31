// ConnectingView — Shown when SessionManager.state == .connecting.
//
// Per UX_SPEC §1.4 row 2: "Per-connector spinner + cancel". Per §8.5 copy
// principles: top-level state titles avoid trailing ellipses (the spinner
// already conveys "in progress"); subtext rows may use them.
//
// QR.4 (D-091): replaces the U.1 stub with a per-connector spinner +
// per-connector subtext + cancel button wired to `SessionManager.cancel()`.

import Session
import SwiftUI

// MARK: - ConnectingView

@MainActor
struct ConnectingView: View {
    static let accessibilityID    = "phosphene.view.connecting"
    static let cancelButtonID     = "phosphene.connecting.cancel"

    /// Source of the in-flight connection. nil for ad-hoc / reactive sessions.
    let source: PlaylistSource?
    let onCancel: () -> Void

    @State private var spinnerAngle: Double = 0

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: connectorSystemImage)
                .font(.system(size: 48, weight: .thin))
                .foregroundColor(.white.opacity(0.85))
                .rotationEffect(.degrees(spinnerAngle))
                .onAppear {
                    withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                        spinnerAngle = 360
                    }
                }
                .accessibilityHidden(true)

            Text(String(localized: "connecting.headline"))
                .font(.largeTitle)
                .fontWeight(.thin)
                .foregroundColor(.white)

            Text(connectorSubtext)
                .font(.body)
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)

            Spacer().frame(height: 24)

            Button(String(localized: "connecting.cta.cancel")) {
                onCancel()
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier(Self.cancelButtonID)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .accessibilityIdentifier(Self.accessibilityID)
    }

    // MARK: - Per-connector copy

    private var connectorSystemImage: String {
        switch source {
        case .appleMusicCurrentPlaylist?, .appleMusicPlaylistURL?:
            return "music.note.list"
        case .spotifyCurrentQueue?, .spotifyPlaylistURL?:
            return "link"
        case .none:
            return "waveform"
        }
    }

    private var connectorSubtext: String {
        switch source {
        case .appleMusicCurrentPlaylist?, .appleMusicPlaylistURL?:
            return String(localized: "connecting.appleMusic.subtext")
        case .spotifyCurrentQueue?, .spotifyPlaylistURL?:
            return String(localized: "connecting.spotify.subtext")
        case .none:
            return String(localized: "connecting.subtext")
        }
    }
}
