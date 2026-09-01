// PermissionOnboardingView — Shown when screen-capture permission is not granted.
//
// Renders regardless of SessionManager.state (the permission gate in ContentView
// sits above the state switch). No "Retry" button — return-detection is automatic
// via PermissionMonitor's didBecomeActiveNotification observer.
//
// Primary CTA calls CGRequestScreenCaptureAccess (BUG-111). U.2 deliberately never
// prompted — "the system dialog doesn't compose with Open System Settings and return."
// That rationale assumed macOS already listed the app in Privacy & Security → Screen &
// System Audio Recording, which it only does AFTER the app has requested access once.
// On a fresh install (or after tccutil reset / the RN.1 bundle-ID change) the pane is
// empty, the deep link is a dead end, and this card is the only reachable UI — a closed
// loop. Requesting registers the app and lets the user grant from the OS dialog.
//
// The secondary "Open System Settings" link keeps the deep link for the already-denied
// case, where macOS suppresses the dialog but the app IS listed.

import AppKit
import CoreGraphics
import SwiftUI

// MARK: - PermissionOnboardingView

@MainActor
struct PermissionOnboardingView: View {
    static let accessibilityID = "uzume.view.permissionOnboarding"

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

            Button(String(localized: "onboarding.permission.grant")) {
                // Registers the app with TCC and shows the OS dialog. Return value is
                // ignored: PermissionMonitor's didBecomeActive refresh does the routing.
                _ = CGRequestScreenCaptureAccess()
            }
            .buttonStyle(.borderedProminent)
            .uzumeTint()
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("uzume.onboarding.grantAccess")

            Button(String(localized: "onboarding.permission.open_settings")) {
                openSettings()
            }
            .buttonStyle(.link)
            .accessibilityIdentifier("uzume.onboarding.openSettings")

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
            .accessibilityIdentifier("uzume.onboarding.whyExplainer")
        }
        .frame(maxWidth: 480)
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(UzumeAppColor.canvas)
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
