// TopBannerView — Amber warning strip shown above the track list for non-blocking
// preparation errors (rate limiting, slow first track, total timeout).
//
// Layout: 44pt amber strip, warning icon + message, optional dismiss button.
// Used by PreparationProgressView when PreparationErrorViewModel.presentationState == .banner(error).

import Shared
import SwiftUI

// MARK: - TopBannerView

/// Non-blocking amber warning strip for preparation degradation signals.
/// Never replaces the track list — appears above it as a dismissible alert strip.
struct TopBannerView: View {
    static let bannerID   = "phosphene.preparation.topBanner"
    static let dismissID  = "phosphene.preparation.topBanner.dismiss"

    let error: UserFacingError
    let onDismiss: (() -> Void)?

    init(error: UserFacingError, onDismiss: (() -> Void)? = nil) {
        self.error = error
        self.onDismiss = onDismiss
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.callout.weight(.semibold))
                .foregroundColor(.black.opacity(0.75))

            Text(bannerMessage)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.black.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            if onDismiss != nil {
                Button {
                    onDismiss?()
                } label: {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.black.opacity(0.55))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(Self.dismissID)
                .accessibilityLabel(Text(String(localized: "a11y.preparation.topBanner.dismiss.label")))
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 44)
        .background(Color.orange.opacity(0.88))
        .accessibilityIdentifier(Self.bannerID)
    }

    // MARK: - Private

    private var bannerMessage: String {
        LocalizedCopy.string(for: error)
    }
}
