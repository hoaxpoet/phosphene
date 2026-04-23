// SpotifyConnectionView — URL-paste connection flow for Spotify.
// User pastes a Spotify playlist URL; the view validates it and shows a preview card.
// Continue starts the session. Rate-limit and error states have appropriate copy and CTAs.

import Session
import SwiftUI

// MARK: - SpotifyConnectionView

struct SpotifyConnectionView: View {
    static let accessibilityID = "phosphene.view.spotify.connection"

    @ObservedObject var viewModel: SpotifyConnectionViewModel
    let onConnect: @Sendable (PlaylistSource) async -> Void
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
        .navigationTitle("Spotify")
        .accessibilityIdentifier(Self.accessibilityID)
    }

    // MARK: - Paste field

    private var pasteField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Paste a Spotify playlist link.")
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
                Text("Checking\u{2026}")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.4))
            }
        case .preview(let id):
            previewCard(playlistID: id)
        case .rejectedKind(let kind):
            rejectionBody(for: kind)
        case .invalid:
            validationMessage("That doesn't look like a Spotify playlist link.")
        case .rateLimited(let attempt):
            rateLimitBody(attempt: attempt)
        case .notFound:
            validationMessage("Phosphene couldn't find that playlist. It may be private or deleted.")
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
                    Text("Spotify playlist recognized")
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

            Button(viewModel.isConnecting ? "Connecting\u{2026}" : "Continue") {
                viewModel.connect(startSession: onConnect)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(viewModel.isConnecting)
            .accessibilityIdentifier("phosphene.spotify.continueButton")
        }
    }

    private func rejectionBody(for kind: SpotifyURLKind) -> some View {
        let message: String
        switch kind {
        case .track:  message = "That\u{2019}s a track, not a playlist."
        case .album:  message = "That\u{2019}s an album, not a playlist."
        case .artist: message = "That\u{2019}s an artist page, not a playlist."
        default:      message = "That link doesn\u{2019}t look like a Spotify playlist."
        }
        return validationMessage(message)
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
                Text("Spotify is being slow \u{2014} still trying (attempt \(attempt) of 3)")
                    .font(.body)
                    .foregroundColor(.white.opacity(0.6))
            }
        }
    }

    private func errorBody(message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundColor(.orange.opacity(0.7))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Couldn\u{2019}t reach Spotify.")
                        .font(.headline)
                        .foregroundColor(.white)
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.4))
                }
            }
            Button("Try again") {
                viewModel.connect(startSession: onConnect)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        Button("Use Apple Music instead") { onUseAppleMusicInstead() }
            .foregroundColor(.white.opacity(0.4))
            .font(.subheadline)
    }
}
