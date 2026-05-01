// SpotifyConnectionView — URL-paste connection flow for Spotify.
// User pastes a Spotify playlist URL; the view validates it and shows a preview card.
// Continue starts the session. Rate-limit and error states have appropriate copy and CTAs.
//
// U.11 additions:
//   .requiresLogin      → "Log in with Spotify" button; tapping calls viewModel.login()
//   .waitingForCallback → spinner while the browser OAuth flow completes

import Session
import SwiftUI

// MARK: - SpotifyConnectionView

struct SpotifyConnectionView: View {
    static let accessibilityID = "phosphene.view.spotify.connection"

    @ObservedObject var viewModel: SpotifyConnectionViewModel
    let onConnect: @Sendable ([TrackIdentity], PlaylistSource) async -> Void
    let onUseAppleMusicInstead: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 24) {
                pasteField
                stateContent
                Spacer()
                footer
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
            .frame(maxWidth: 520)
        }
        .navigationTitle(String(localized: "connector.spotify.title"))
        .accessibilityIdentifier(Self.accessibilityID)
    }

    // MARK: - Paste field

    private var pasteField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "connector.spotify.paste_label"))
                .font(.body)
                .foregroundColor(.white.opacity(0.7))
            TextField("", text: $viewModel.text, prompt: Text("https://open.spotify.com/playlist/\u{2026}")
                .foregroundColor(.white.opacity(0.25))
            )
            .textFieldStyle(.plain)
            .font(.system(.body, design: .monospaced))
            .foregroundColor(.white)
            .padding(12)
            .background(Color.white.opacity(0.07))
            .cornerRadius(8)
            .accessibilityIdentifier("phosphene.spotify.urlField")
        }
    }

    // MARK: - State content

    @ViewBuilder
    private var stateContent: some View {
        switch viewModel.state {
        case .empty:
            EmptyView()
        case .parsing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.mini).tint(.white.opacity(0.4))
                Text(String(localized: "connector.spotify.checking"))
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.4))
            }
        case .preview(let id):
            previewCard(playlistID: id)
        case .rejectedKind(let kind):
            rejectionBody(for: kind)
        case .invalid:
            validationMessage(LocalizedCopy.string(for: .spotifyURLMalformed))
        case .rateLimited(let attempt):
            rateLimitBody(attempt: attempt)
        case .notFound:
            validationMessage(String(localized: "connector.spotify.not_found"))
        case .privatePlaylist:
            validationMessage(String(localized: "connector.spotify.private_playlist"))
        case .requiresLogin:
            requiresLoginBody
        case .waitingForCallback:
            waitingForCallbackBody
        case .authFailure:
            validationMessage(String(localized: "connector.spotify.auth_failure"))
        case .error(let msg):
            errorBody(message: msg)
        }
    }

    // MARK: - State views

    private func previewCard(playlistID: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green.opacity(0.8))
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "connector.spotify.recognized_headline"))
                        .font(.headline)
                        .foregroundColor(.white)
                    Text(playlistID)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.07))
            .cornerRadius(10)

            let btnLabel = viewModel.isConnecting
                ? String(localized: "connector.spotify.connecting_button")
                : String(localized: "connector.spotify.continue_button")
            Button(btnLabel) {
                viewModel.connect(startSession: onConnect)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(viewModel.isConnecting)
            .accessibilityIdentifier("phosphene.spotify.continueButton")
        }
    }

    private func rejectionBody(for kind: SpotifyURLKind) -> some View {
        let errorKind: UserFacingError.SpotifyRejectionKind
        switch kind {
        case .track:   errorKind = .track
        case .album:   errorKind = .album
        case .artist:  errorKind = .artist
        default:       errorKind = .unknown
        }
        return validationMessage(LocalizedCopy.string(for: .spotifyURLNotPlaylist(kind: errorKind)))
    }

    private func validationMessage(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle")
                .foregroundColor(.orange.opacity(0.7))
            Text(text)
                .font(.body)
                .foregroundColor(.white.opacity(0.6))
        }
    }

    private func rateLimitBody(attempt: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.mini).tint(.white.opacity(0.5))
                Text(LocalizedCopy.string(for: .spotifyRateLimited(attempt: attempt)))
                    .font(.body)
                    .foregroundColor(.white.opacity(0.6))
            }
        }
    }

    private var requiresLoginBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .foregroundColor(.white.opacity(0.6))
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "connector.spotify.login_required_headline"))
                        .font(.headline)
                        .foregroundColor(.white)
                    Text(String(localized: "connector.spotify.login_required_body"))
                        .font(.body)
                        .foregroundColor(.white.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.07))
            .cornerRadius(10)

            Button(String(localized: "connector.spotify.login_button")) {
                viewModel.login(startSession: onConnect)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("phosphene.spotify.loginButton")
        }
    }

    private var waitingForCallbackBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small).tint(.white.opacity(0.6))
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "connector.spotify.waiting_for_callback_headline"))
                        .font(.headline)
                        .foregroundColor(.white)
                    Text(String(localized: "connector.spotify.waiting_for_callback_body"))
                        .font(.body)
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.07))
            .cornerRadius(10)
        }
    }

    private func errorBody(message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundColor(.orange.opacity(0.7))
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "connector.spotify.error.headline"))
                        .font(.headline)
                        .foregroundColor(.white)
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.4))
                }
            }
            Button(String(localized: "connector.spotify.try_again_button")) {
                viewModel.connect(startSession: onConnect)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        Button(String(localized: "connector.spotify.use_apple_music")) {
            onUseAppleMusicInstead()
        }
        .foregroundColor(.white.opacity(0.4))
        .font(.subheadline)
    }
}
