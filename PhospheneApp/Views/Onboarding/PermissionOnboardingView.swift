// PermissionOnboardingView — Shown when screen-capture permission is not granted.
//
// Renders regardless of SessionManager.state (the permission gate in ContentView
// sits above the state switch). No "Retry" button — return-detection is automatic
// via PermissionMonitor's didBecomeActiveNotification observer.
//
// Opens x-apple.systempreferences:…?Privacy_ScreenCapture via NSWorkspace.
// Never calls CGRequestScreenCaptureAccess.

import AppKit
import SwiftUI

// MARK: - PermissionOnboardingView

@MainActor
struct PermissionOnboardingView: View {
    static let accessibilityID = "phosphene.view.permissionOnboarding"

    @State private var showExplainer = false

    // MARK: - Body

    var body: some View {
        VStack(spacing: 20) {
            Text("Phosphene needs permission to hear music playing on your Mac.")
                .font(.title2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(
                "To follow along with your music, Phosphene listens to the audio coming out of your " +
                "speakers \u{2014} the same way a screen recorder would. It doesn\u{2019}t record your screen, your " +
                "microphone, or anything else. Nothing ever leaves your Mac."
            )
            .font(.body)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

            Button("Open System Settings") {
                openSettings()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("phosphene.onboarding.openSettings")

            DisclosureGroup(
                "Why does this need screen recording permission?",
                isExpanded: $showExplainer
            ) {
                Text(
                    "On macOS, permission to capture system audio is bundled with screen recording " +
                    "permission. Apple groups them together. Phosphene uses only the audio portion."
                )
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            }
            .accessibilityIdentifier("phosphene.onboarding.whyExplainer")
        }
        .frame(maxWidth: 480)
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .accessibilityIdentifier(Self.accessibilityID)
    }

    // MARK: - Private

    private func openSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}
