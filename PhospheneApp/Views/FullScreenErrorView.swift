// FullScreenErrorView — Reusable full-screen error layout for §9.1 and §9.2 errors.
//
// Layout: dimmed backdrop, centered card with icon, headline, optional body,
// primary CTA button, optional secondary text-link button.
//
// Construction:
//   FullScreenErrorView(error: .networkOffline, primaryAction: { … })
//
// Copy and CTA labels are resolved via LocalizedCopy.

import Shared
import SwiftUI

// MARK: - FullScreenErrorView

/// Full-screen error presentation for blocking UX errors (§9.1 permission, §9.2 connection,
/// §9.3 catastrophic preparation). Never shown during `.playing` state — use toasts there.
struct FullScreenErrorView: View {

    let error: UserFacingError
    let primaryAction: (() -> Void)?
    let secondaryAction: (() -> Void)?

    init(
        error: UserFacingError,
        primaryAction: (() -> Void)? = nil,
        secondaryAction: (() -> Void)? = nil
    ) {
        self.error = error
        self.primaryAction = primaryAction
        self.secondaryAction = secondaryAction
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
    }

    // MARK: - Icon

    private var icon: some View {
        Image(systemName: severityIcon)
            .font(.largeTitle.weight(.light))
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
            if let primaryKey = error.primaryCTAKey, let action = primaryAction {
                Button(LocalizedCopy.cta(primaryKey)) {
                    action()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }

            if let secondaryKey = error.secondaryCTAKey, let action = secondaryAction {
                Button(LocalizedCopy.cta(secondaryKey)) {
                    action()
                }
                .foregroundColor(.white.opacity(0.5))
                .font(.subheadline)
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
