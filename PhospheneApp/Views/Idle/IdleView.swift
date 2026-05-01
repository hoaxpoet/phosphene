// IdleView — Shown when SessionManager.state == .idle.
// U.1 stub: displays state name on black background.
// U.2: photosensitivity sheet on first appearance (persisted via UserDefaults).
// U.3: connector picker CTA + ad-hoc "Start listening now" CTA.

import Session
import SwiftUI

// MARK: - IdleView

@MainActor
struct IdleView: View {
    static let accessibilityID        = "phosphene.view.idle"
    static let connectButtonID        = "phosphene.idle.connectPlaylist"
    static let adHocButtonID          = "phosphene.idle.startListening"

    @EnvironmentObject private var engine: VisualizerEngine

    @State private var showPhotosensitivityNotice = false
    @State private var showConnectorPicker        = false
    private let acknowledgementStore              = PhotosensitivityAcknowledgementStore()

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("Phosphene")
                .font(.largeTitle)
                .fontWeight(.thin)
                .foregroundColor(.white)

            Spacer().frame(height: 8)

            VStack(spacing: 12) {
                Button(String(localized: "idle.connect_button")) {
                    showConnectorPicker = true
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier(Self.connectButtonID)

                Button(String(localized: "idle.adhoc_button")) {
                    engine.sessionManager.startAdHocSession()
                }
                .foregroundColor(.white.opacity(0.5))
                .font(.subheadline)
                .accessibilityIdentifier(Self.adHocButtonID)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .accessibilityIdentifier(Self.accessibilityID)
        .onAppear {
            if !acknowledgementStore.isAcknowledged {
                showPhotosensitivityNotice = true
            }
        }
        .sheet(isPresented: $showPhotosensitivityNotice) {
            PhotosensitivityNoticeView {
                acknowledgementStore.markAcknowledged()
                showPhotosensitivityNotice = false
            }
        }
        .sheet(isPresented: $showConnectorPicker) {
            ConnectorPickerView { tracks, source in
                // No explicit dismiss needed — startSession transitions state to
                // .connecting, which causes ContentView to replace IdleView (and
                // this sheet) with ConnectingView automatically.
                //
                // Route by SOURCE, not tracks.isEmpty:
                // - Spotify: always use preFetchedTracks (even if empty) to avoid
                //   SessionManager re-fetching via client-credentials (→ 401).
                // - Apple Music / other: no pre-fetched tracks; SM fetches itself.
                switch source {
                case .spotifyPlaylistURL, .spotifyCurrentQueue:
                    await engine.sessionManager.startSession(preFetchedTracks: tracks, source: source)
                default:
                    await engine.sessionManager.startSession(source: source)
                }
            }
        }
    }
}
