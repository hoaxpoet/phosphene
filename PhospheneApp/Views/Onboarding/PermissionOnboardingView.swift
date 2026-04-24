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
            Text(String(localized: "onboarding.permission.headline"))
                .font(.title2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(String(localized: "onboarding.permission.body"))
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button(String(localized: "onboarding.permission.open_settings")) {
                openSettings()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("phosphene.onboarding.openSettings")

            DisclosureGroup(
                String(localized: "onboarding.permission.why_label"),
                isExpanded: $showExplainer
            ) {
                Text(String(localized: "onboarding.permission.why_body"))
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
