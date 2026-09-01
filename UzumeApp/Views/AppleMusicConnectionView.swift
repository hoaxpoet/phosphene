// AppleMusicConnectionView — Connection flow for Apple Music.
// Covers all five user-visible states: connecting, noCurrentPlaylist, notRunning,
// permissionDenied, and error. Successful connection calls onConnect and pops navigation.

import Session
import SwiftUI

// MARK: - AppleMusicConnectionView

struct AppleMusicConnectionView: View {
    static let accessibilityID = "uzume.view.appleMusic.connection"

    @ObservedObject var viewModel: AppleMusicConnectionViewModel
    // Apple Music has no pre-fetched tracks — passes [] so the caller uses startSession(source:).
    let onConnect: @Sendable ([TrackIdentity], PlaylistSource) async -> Void
    let onUseSpotifyInstead: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            UzumeAppColor.canvas.ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer()
                stateContent
                Spacer()
                footer
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
            .frame(maxWidth: 480)
        }
        .onAppear { viewModel.beginConnect() }
        .onDisappear { viewModel.cancelRetry() }
        .onChange(of: viewModel.state) { _, newState in
            if case .connected = newState {
                Task { await onConnect([], .appleMusicCurrentPlaylist) }
            }
        }
        .navigationTitle(String(localized: "connector.apple_music.title"))
        .accessibilityIdentifier(Self.accessibilityID)
    }

    // MARK: - Footer

    // Shown in every state (not just on error) so the user can switch to
    // Spotify from the waiting screen without backing out to the picker.
    private var footer: some View {
        Button(String(localized: "connector.apple_music.use_spotify_button")) {
            onUseSpotifyInstead()
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("uzume.appleMusic.useSpotifyInstead")
    }

    // MARK: - State content

    @ViewBuilder
    private var stateContent: some View {
        switch viewModel.state {
        case .idle, .connecting:
            connectingBody
        case .noCurrentPlaylist:
            noPlaylistBody
        case .notRunning:
            notRunningBody
        case .permissionDenied:
            permissionDeniedBody
        case .error(let msg):
            errorBody(message: msg)
        case .connected:
            connectingBody  // briefly visible while onConnect fires
        }
    }

    // MARK: - State views

    private var connectingBody: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.large)
                .tint(UzumeAppColor.textPrimary)
            Text(String(localized: "connector.apple_music.connecting"))
                .font(.body)
                .foregroundColor(UzumeAppColor.textTertiary)
        }
    }

    private var noPlaylistBody: some View {
        VStack(spacing: 20) {
            Image(systemName: "music.note.list")
                .font(.largeTitle)
                .foregroundColor(UzumeAppColor.textDisabled)
            VStack(spacing: 8) {
                Text(String(localized: "connector.apple_music.no_playlist.headline"))
                    .font(.headline)
                    .foregroundColor(UzumeAppColor.textPrimary)
                    .multilineTextAlignment(.center)
                Text(String(localized: "connector.apple_music.no_playlist.status"))
                    .font(.caption)
                    .foregroundColor(UzumeAppColor.textDisabled)
            }
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.small)
                .tint(UzumeAppColor.textTertiary)
        }
    }

    private var notRunningBody: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.circle")
                .font(.largeTitle)
                .foregroundColor(UzumeAppColor.textDisabled)
            VStack(spacing: 8) {
                Text(String(localized: "connector.apple_music.not_running.headline"))
                    .font(.headline)
                    .foregroundColor(UzumeAppColor.textPrimary)
                Text(String(localized: "connector.apple_music.not_running.body"))
                    .font(.body)
                    .foregroundColor(UzumeAppColor.textTertiary)
                    .multilineTextAlignment(.center)
            }
            Button(String(localized: "connector.apple_music.open_button")) {
                viewModel.openAppleMusic()
            }
            .buttonStyle(.borderedProminent)
            .uzumeTint()
            .keyboardShortcut(.defaultAction)
        }
    }

    private var permissionDeniedBody: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.circle")
                .font(.largeTitle)
                .foregroundColor(UzumeAppColor.textDisabled)
            VStack(spacing: 8) {
                Text(String(localized: "connector.apple_music.permission.headline"))
                    .font(.headline)
                    .foregroundColor(UzumeAppColor.textPrimary)
                    .multilineTextAlignment(.center)
                Text(String(localized: "connector.apple_music.permission.body"))
                    .font(.body)
                    .foregroundColor(UzumeAppColor.textTertiary)
                    .multilineTextAlignment(.center)
            }
            Button(String(localized: "connector.apple_music.permission.button")) {
                viewModel.openAutomationSettings()
            }
            .buttonStyle(.borderedProminent)
            .uzumeTint()
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("uzume.appleMusic.openSystemSettings")
        }
    }

    private func errorBody(message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(UzumeAppColor.textDisabled)
            VStack(spacing: 8) {
                Text(String(localized: "connector.apple_music.error.headline"))
                    .font(.headline)
                    .foregroundColor(UzumeAppColor.textPrimary)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.caption)
                    .foregroundColor(UzumeAppColor.textDisabled)
                    .multilineTextAlignment(.center)
            }
            Button(String(localized: "connector.apple_music.try_again_button")) {
                viewModel.retry()
            }
            .buttonStyle(.borderedProminent)
            .uzumeTint()
            .keyboardShortcut(.defaultAction)
        }
    }
}
