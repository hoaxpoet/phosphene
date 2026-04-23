// PhotosensitivityNoticeView — One-time sheet shown on first IdleView appearance.
//
// Two CTAs: "Enable Reduce motion" (opens Accessibility pane, then dismisses) and
// "I understand" (dismisses). Both call onAcknowledge — the notice does not reappear
// after either action because IdleView persists the flag via
// PhotosensitivityAcknowledgementStore.
//
// macOS does not expose a programmatic toggle for accessibilityDisplayShouldReduceMotion.
// "Enable Reduce motion" opens the Accessibility → Display pane; the user flips it there.

import AppKit
import SwiftUI

// MARK: - PhotosensitivityNoticeView

@MainActor
struct PhotosensitivityNoticeView: View {
    static let accessibilityID = "phosphene.view.photosensitivityNotice"

    let onAcknowledge: () -> Void

    // MARK: - Body

    var body: some View {
        VStack(spacing: 20) {
            Text("Heads up")
                .font(.headline)

            Text(
                "Phosphene renders high-contrast, fast-changing visuals. If you\u{2019}re sensitive to " +
                "flashing lights or strobe patterns, enable Reduce motion in Settings before starting."
            )
            .font(.body)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Button("Enable Reduce motion") {
                    openAccessibilityPane()
                    onAcknowledge()
                }
                .accessibilityIdentifier("phosphene.photosensitivity.openAccessibility")

                Button("I understand") {
                    onAcknowledge()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("phosphene.photosensitivity.acknowledge")
            }
        }
        .padding(32)
        .frame(width: 480)
        .accessibilityIdentifier(Self.accessibilityID)
    }

    // MARK: - Private

    private func openAccessibilityPane() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.universalaccess?Seeing_Display"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}
