// PreparationFailureView — Full-screen replacement for the .preparing state when all
// tracks have failed or the network has dropped entirely.
//
// Shown when PreparationErrorViewModel.presentationState == .fullScreen(error).
// Provides two recovery paths:
//   primary   → "Pick another playlist" (onPickAnotherPlaylist)
//   secondary → "Start reactive mode"   (onStartReactive)
//
// All copy resolved via LocalizedCopy / Localizable.strings.

import Shared
import SwiftUI

// MARK: - PreparationFailureView

/// Full-screen catastrophic-preparation failure, per UX_SPEC §9.3 §9.2.
/// Replaces the track-list pane when PreparationErrorViewModel fires .fullScreen.
struct PreparationFailureView: View {
    static let accessibilityID      = "phosphene.view.preparationFailure"
    static let pickPlaylistButtonID = "phosphene.preparationFailure.pickPlaylist"
    static let reactiveButtonID     = "phosphene.preparationFailure.startReactive"

    let error: UserFacingError
    let onPickAnotherPlaylist: () -> Void
    let onStartReactive: (() -> Void)?

    init(
        error: UserFacingError,
        onPickAnotherPlaylist: @escaping () -> Void,
        onStartReactive: (() -> Void)? = nil
    ) {
        self.error = error
        self.onPickAnotherPlaylist = onPickAnotherPlaylist
        self.onStartReactive = onStartReactive
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()
                icon
                textBlock
                actions
                Spacer()
            }
            .padding(.horizontal, 40)
            .frame(maxWidth: 520)
        }
        .accessibilityIdentifier(Self.accessibilityID)
    }

    // MARK: - Icon

    private var icon: some View {
        Image(systemName: severityIcon)
            .font(.system(size: 44, weight: .light))
            .foregroundColor(severityColor.opacity(0.7))
    }

    // MARK: - Text block

    private var textBlock: some View {
        VStack(spacing: 12) {
            Text(headline)
                .font(.title2)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let body = LocalizedCopy.bodyString(for: error) {
                Text(body)
                    .font(.body)
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Actions

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 12) {
            Button(String(localized: "preparation.failure.pick_playlist_button")) {
                onPickAnotherPlaylist()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier(Self.pickPlaylistButtonID)

            if let startReactive = onStartReactive {
                Button(String(localized: "preparation.failure.start_reactive_button")) {
                    startReactive()
                }
                .foregroundColor(.white.opacity(0.5))
                .font(.subheadline)
                .accessibilityIdentifier(Self.reactiveButtonID)
            }
        }
    }

    // MARK: - Private helpers

    private var headline: String {
        let copy = LocalizedCopy.string(for: error)
        return copy.isEmpty ? String(localized: "fullscreen_error.default_headline") : copy
    }

    private var severityIcon: String {
        switch error.severity {
        case .fatal:       return "xmark.circle"
        case .warning:     return "exclamationmark.circle"
        case .degradation: return "exclamationmark.triangle"
        case .info:        return "info.circle"
        }
    }

    private var severityColor: Color {
        switch error.severity {
        case .fatal:       return .red
        case .warning:     return .orange
        case .degradation: return .yellow
        case .info:        return .white
        }
    }
}
