// ConnectorPickerView — Three-tile picker for Apple Music, Spotify, and Local Folder.
// Presented as a sheet from IdleView. Uses NavigationStack internally so each
// connector flow view is pushed onto the stack — back button returns to this picker.

import Session
import SwiftUI

// MARK: - ConnectorPickerView

struct ConnectorPickerView: View {
    static let accessibilityID = "phosphene.view.connectorPicker"

    /// Called when a connector successfully identifies a playlist.
    /// Caller is responsible for starting the session; this view just provides source.
    let onConnect: @Sendable (PlaylistSource) async -> Void

    @StateObject private var viewModel = ConnectorPickerViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 0) {
                    tileList
                    Spacer()
                    footer
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
            .navigationTitle(String(localized: "connector.picker.title"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "connector.picker.close_button")) { dismiss() }
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .navigationDestination(for: ConnectorType.self) { type in
                destination(for: type)
            }
        }
        .accessibilityIdentifier(Self.accessibilityID)
    }

    // MARK: - Private

    @ViewBuilder
    private var tileList: some View {
        VStack(spacing: 12) {
            appleMusicTile
            spotifyTile
            localFolderTile
        }
    }

    @ViewBuilder
    private var appleMusicTile: some View {
        if viewModel.appleMusicRunning {
            NavigationLink(value: ConnectorType.appleMusic) {
                ConnectorTileView(type: .appleMusic, isEnabled: true)
            }
            .buttonStyle(.plain)
        } else {
            ConnectorTileView(
                type: .appleMusic,
                isEnabled: false,
                disabledCaption: String(localized: "connector.picker.apple_music_disabled"),
                secondaryActionLabel: String(localized: "connector.picker.open_apple_music_button"),
                onSecondaryAction: { viewModel.openAppleMusic() }
            )
        }
    }

    @ViewBuilder
    private var spotifyTile: some View {
        NavigationLink(value: ConnectorType.spotify) {
            ConnectorTileView(type: .spotify, isEnabled: true)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var localFolderTile: some View {
        ConnectorTileView(
            type: .localFolder,
            isEnabled: false,
            disabledCaption: String(localized: "connector.picker.local_folder_disabled")
        )
    }

    @ViewBuilder
    private var footer: some View {
        Text(String(localized: "connector.picker.footer"))
            .font(.caption2)
            .foregroundColor(.white.opacity(0.3))
            .multilineTextAlignment(.center)
            .padding(.top, 24)
    }

    @ViewBuilder
    private func destination(for type: ConnectorType) -> some View {
        switch type {
        case .appleMusic:
            AppleMusicConnectionView(
                viewModel: AppleMusicConnectionViewModel(),
                onConnect: onConnect,
                onUseSpotifyInstead: { dismiss() }
            )
        case .spotify:
            SpotifyConnectionView(
                viewModel: SpotifyConnectionViewModel(),
                onConnect: onConnect,
                onUseAppleMusicInstead: {
                    // Navigation stack will pop; Apple Music tile is there if running.
                }
            )
        case .localFolder:
            Text(String(localized: "connector.picker.local_placeholder"))
                .foregroundColor(.white.opacity(0.5))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
        }
    }
}
