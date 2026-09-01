// RecoveryScreen — the blocking status placement. (DS.3)
//
// Two views carried this layout before DS.3: dimmed canvas, tone icon, headline,
// optional body, primary CTA with `.keyboardShortcut(.defaultAction)`, optional
// secondary text link. The only real difference between them was where the button
// labels came from — one hard-coded the two preparation actions, the other read the
// error's CTA keys — so this takes an explicit action set and lets the caller decide.
//
// One of the two had no construction site anywhere in the app and had never appeared
// in a shipped build (recorded in KNOWN_ISSUES.md); deleting it removed the
// duplication at zero behavioural risk.
//
// Of the four status placements this is the only blocking one: it replaces the view
// behind it and offers a way out. Interruption, lifetime and dismissal are what keep
// the four separate (COMPONENTS.md § Status placements); the tone vocabulary is the
// whole of the sharing.

import Shared
import SwiftUI

// MARK: - RecoveryScreen

/// Full-screen blocking failure with one or two recovery paths, per UX_SPEC §9.1–§9.3.
/// Never shown during `.playing` — use `PerformanceToast` there.
struct RecoveryScreen: View {
    static let accessibilityID      = "uzume.view.preparationFailure"
    static let pickPlaylistButtonID = "uzume.preparationFailure.pickPlaylist"
    static let reactiveButtonID     = "uzume.preparationFailure.startReactive"

    let error: UserFacingError
    let primaryLabel: String
    let primaryAction: () -> Void
    let secondaryLabel: String?
    let secondaryAction: (() -> Void)?

    init(
        error: UserFacingError,
        primaryLabel: String,
        primaryAction: @escaping () -> Void,
        secondaryLabel: String? = nil,
        secondaryAction: (() -> Void)? = nil
    ) {
        self.error = error
        self.primaryLabel = primaryLabel
        self.primaryAction = primaryAction
        self.secondaryLabel = secondaryLabel
        self.secondaryAction = secondaryAction
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            UzumeAppColor.canvas.ignoresSafeArea()

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
        Image(systemName: tone.symbol)
            .font(.largeTitle.weight(.light))
            .foregroundColor(tone.foreground.opacity(0.7))
    }

    // MARK: - Text block

    private var textBlock: some View {
        VStack(spacing: 12) {
            Text(headline)
                .font(.title2)
                .fontWeight(.medium)
                .foregroundColor(UzumeAppColor.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let body = LocalizedCopy.bodyString(for: error) {
                Text(body)
                    .font(.body)
                    .foregroundColor(UzumeAppColor.textTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Actions

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 12) {
            Button(primaryLabel) {
                primaryAction()
            }
            .buttonStyle(.borderedProminent)
            .uzumeTint()
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier(Self.pickPlaylistButtonID)

            if let secondaryLabel, let secondaryAction {
                Button(secondaryLabel) {
                    secondaryAction()
                }
                .foregroundColor(UzumeAppColor.textTertiary)
                .font(.subheadline)
                .accessibilityIdentifier(Self.reactiveButtonID)
            }
        }
    }

    // MARK: - Private

    private var tone: StatusTone { .from(error.severity) }

    private var headline: String {
        let copy = LocalizedCopy.string(for: error)
        return copy.isEmpty ? String(localized: "fullscreen_error.default_headline") : copy
    }
}
