// AppleMusicConnectionView — Connection flow for Apple Music.
// Covers all five user-visible states: connecting, noCurrentPlaylist, notRunning,
// permissionDenied, and error. Successful connection calls onConnect and pops navigation.

import Session
import SwiftUI

// MARK: - AppleMusicConnectionView

struct AppleMusicConnectionView: View {
    static let accessibilityID = "phosphene.view.appleMusic.connection"

    @ObservedObject var viewModel: AppleMusicConnectionViewModel
    let onConnect: @Sendable (PlaylistSource) async -> Void
    let onUseSpotifyInstead: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer()
                stateContent
                Spacer()
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
            .frame(maxWidth: 480)
        }
        .onAppear { viewModel.beginConnect() }
        .onDisappear { viewModel.cancelRetry() }
        .onChange(of: viewModel.state) { _, newState in
            if case .connected = newState {
                Task { await onConnect(.appleMusicCurrentPlaylist) }
            }
        }
        .navigationTitle(String(localized: "connector.apple_music.title"))
        .accessibilityIdentifier(Self.accessibilityID)
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
                .tint(.white)
            Text(String(localized: "connector.apple_music.connecting"))
                .font(.body)
                .foregroundColor(.white.opacity(0.6))
        }
    }

    private var noPlaylistBody: some View {
        VStack(spacing: 20) {
            Image(systemName: "music.note.list")
                .font(.system(size: 40))
                .foregroundColor(.white.opacity(0.4))
            VStack(spacing: 8) {
                Text(String(localized: "connector.apple_music.no_playlist.headline"))
                    .font(.headline)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                Text(String(localized: "connector.apple_music.no_playlist.status"))
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.4))
            }
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.small)
                .tint(.white.opacity(0.5))
        }
    }

    private var notRunningBody: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 40))
                .foregroundColor(.white.opacity(0.4))
            VStack(spacing: 8) {
                Text(String(localized: "connector.apple_music.not_running.headline"))
                    .font(.headline)
                    .foregroundColor(.white)
                Text(String(localized: "connector.apple_music.not_running.body"))
                    .font(.body)
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
            Button(String(localized: "connector.apple_music.open_button")) {
                viewModel.openAppleMusic()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
    }

    private var permissionDeniedBody: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.circle")
                .font(.system(size: 40))
                .foregroundColor(.white.opacity(0.4))
            VStack(spacing: 8) {
                Text(String(localized: "connector.apple_music.permission.headline"))
                    .font(.headline)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                Text(String(localized: "connector.apple_music.permission.body"))
                    .font(.body)
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
            Button(String(localized: "connector.apple_music.permission.button")) {
                viewModel.openAutomationSettings()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("phosphene.appleMusic.openSystemSettings")
        }
    }

    private func errorBody(message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(.white.opacity(0.4))
            VStack(spacing: 8) {
                Text(String(localized: "connector.apple_music.error.headline"))
                    .font(.headline)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.4))
                    .multilineTextAlignment(.center)
            }
            VStack(spacing: 12) {
                Button(String(localized: "connector.apple_music.try_again_button")) {
                    viewModel.retry()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                Button(String(localized: "connector.apple_music.use_spotify_button")) {
                    onUseSpotifyInstead()
                }
                .foregroundColor(.white.opacity(0.5))
                .font(.subheadline)
            }
        }
    }
}
