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
    static let accessibilityID = "uzume.view.spotify.connection"

    @ObservedObject var viewModel: SpotifyConnectionViewModel
    let onConnect: @Sendable ([TrackIdentity], PlaylistSource) async -> Void
    let onUseAppleMusicInstead: () -> Void

    @FocusState private var isURLFieldFocused: Bool

    var body: some View {
        ZStack {
            UzumeAppColor.canvas.ignoresSafeArea()
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
        .onAppear {
            // Dispatched async so focus lands after the NavigationStack push animation
            // has completed and the TextField is in the responder chain.
            DispatchQueue.main.async { isURLFieldFocused = true }
        }
    }

    // MARK: - Paste field

    private var pasteField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "connector.spotify.paste_label"))
                .font(.body)
                .foregroundColor(UzumeAppColor.textSecondary)
            TextField("", text: $viewModel.text, prompt: Text("https://open.spotify.com/playlist/\u{2026}")
                .foregroundColor(UzumeAppColor.textDisabled)
            )
            .textFieldStyle(.plain)
            .font(.system(.body, design: .monospaced))
            .foregroundColor(UzumeAppColor.textPrimary)
            .padding(12)
            .background(UzumeAppColor.surfaceRaised)
            .cornerRadius(8)
            .focused($isURLFieldFocused)
            .accessibilityIdentifier("uzume.spotify.urlField")
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
                ProgressView().controlSize(.mini).tint(UzumeAppColor.textDisabled)
                Text(String(localized: "connector.spotify.checking"))
                    .font(.caption)
                    .foregroundColor(UzumeAppColor.textDisabled)
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
            validationMessage(viewModel.authFailureMessage)
        case .error(let msg):
            errorBody(message: msg)
        }
    }

    // MARK: - State views

    private func previewCard(playlistID: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(UzumeAppColor.success.opacity(0.8))
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "connector.spotify.recognized_headline"))
                        .font(.headline)
                        .foregroundColor(UzumeAppColor.textPrimary)
                    Text(playlistID)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(UzumeAppColor.textDisabled)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(UzumeAppColor.surfaceRaised)
            .cornerRadius(10)

            let btnLabel = viewModel.isConnecting
                ? String(localized: "connector.spotify.connecting_button")
                : String(localized: "connector.spotify.continue_button")
            Button(btnLabel) {
                viewModel.connect(startSession: onConnect)
            }
            .buttonStyle(.borderedProminent)
            .uzumeTint()
            .keyboardShortcut(.defaultAction)
            .disabled(viewModel.isConnecting)
            .accessibilityIdentifier("uzume.spotify.continueButton")
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
                .foregroundColor(UzumeAppColor.warning.opacity(0.7))
            Text(text)
                .font(.body)
                .foregroundColor(UzumeAppColor.textTertiary)
        }
    }

    private func rateLimitBody(attempt: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.mini).tint(UzumeAppColor.textTertiary)
                Text(LocalizedCopy.string(for: .spotifyRateLimited(attempt: attempt)))
                    .font(.body)
                    .foregroundColor(UzumeAppColor.textTertiary)
            }
        }
    }

    private var requiresLoginBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .foregroundColor(UzumeAppColor.textTertiary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "connector.spotify.login_required_headline"))
                        .font(.headline)
                        .foregroundColor(UzumeAppColor.textPrimary)
                    Text(String(localized: "connector.spotify.login_required_body"))
                        .font(.body)
                        .foregroundColor(UzumeAppColor.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(UzumeAppColor.surfaceRaised)
            .cornerRadius(10)

            Button(String(localized: "connector.spotify.login_button")) {
                viewModel.login(startSession: onConnect)
            }
            .buttonStyle(.borderedProminent)
            .uzumeTint()
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("uzume.spotify.loginButton")
        }
    }

    private var waitingForCallbackBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small).tint(UzumeAppColor.textTertiary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "connector.spotify.waiting_for_callback_headline"))
                        .font(.headline)
                        .foregroundColor(UzumeAppColor.textPrimary)
                    Text(String(localized: "connector.spotify.waiting_for_callback_body"))
                        .font(.body)
                        .foregroundColor(UzumeAppColor.textTertiary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(UzumeAppColor.surfaceRaised)
            .cornerRadius(10)
        }
    }

    private func errorBody(message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundColor(UzumeAppColor.warning.opacity(0.7))
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "connector.spotify.error.headline"))
                        .font(.headline)
                        .foregroundColor(UzumeAppColor.textPrimary)
                    Text(message)
                        .font(.caption)
                        .foregroundColor(UzumeAppColor.textDisabled)
                }
            }
            Button(String(localized: "connector.spotify.try_again_button")) {
                viewModel.retry(startSession: onConnect)
            }
            .buttonStyle(.borderedProminent)
            .uzumeTint()
            .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        Button(String(localized: "connector.spotify.use_apple_music")) {
            onUseAppleMusicInstead()
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("uzume.spotify.useAppleMusicInstead")
    }
}
