// NoticeBanner — the persistent status placement. (DS.3)
//
// A 44pt strip above the track list: non-blocking, and visible until
// `PreparationErrorViewModel` changes state.
//
// Its predecessor took `error: UserFacingError` and never read `error.severity` —
// the fill was a hard-coded amber with near-black text, so every banner looked the
// same whatever went wrong. It now derives its tone the way every other status
// surface does, which is also what flips it from an amber fill with black text to
// the token warning treatment: bright yellow on a deep field with a border.
//
// The `onDismiss` closure and its identifier are kept exactly as they were. No
// construction site passes one, so the button has never rendered in a shipped build;
// that is recorded in KNOWN_ISSUES.md rather than fixed here, because wiring it is a
// behaviour change and deleting it breaks a pinned identifier.

import Shared
import SwiftUI

// MARK: - NoticeBanner

/// Non-blocking strip above the track list for preparation errors that do not stop
/// the session. Persists until the view model's presentation state changes.
struct NoticeBanner: View {
    static let bannerID  = "uzume.preparation.topBanner"
    static let dismissID = "uzume.preparation.topBanner.dismiss"

    let error: UserFacingError
    let onDismiss: (() -> Void)?

    init(error: UserFacingError, onDismiss: (() -> Void)? = nil) {
        self.error = error
        self.onDismiss = onDismiss
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: tone.symbol)
                .font(.callout.weight(.semibold))
                .foregroundColor(tone.foreground)

            Text(bannerMessage)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(tone.foreground)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            if onDismiss != nil {
                Button {
                    onDismiss?()
                } label: {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(tone.foreground.opacity(0.7))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(Self.dismissID)
                .accessibilityLabel(Text(String(localized: "a11y.preparation.topBanner.dismiss.label")))
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 44)
        .frame(maxWidth: .infinity)
        .background(tone.background)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(tone.border)
                .frame(height: 1)
        }
        .accessibilityIdentifier(Self.bannerID)
    }

    // MARK: - Private

    private var tone: StatusTone { .from(error.severity) }

    private var bannerMessage: String {
        LocalizedCopy.string(for: error)
    }
}
