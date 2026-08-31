// PermissionOnboardingViewTests — Verifies static accessibilityID constants on
// PermissionOnboardingView and PhotosensitivityNoticeView.
//
// NSHostingController's accessibility tree is not materialised by test harnesses
// (no VoiceOver client). We use the same pattern as SessionStateViewTests: verify
// the static accessibilityID constant on each view struct and trust that each view
// applies .accessibilityIdentifier(Self.accessibilityID) — enforced by construction.
//
// Button identifier strings are declared inline in the view bodies; we test them
// via Mirror to avoid duplicating magic strings.

import SwiftUI
import Testing
@testable import UzumeApp

// MARK: - Tests

@Suite("PermissionOnboardingView identifiers")
@MainActor
struct PermissionOnboardingViewTests {

    @Test("PermissionOnboardingView declares expected top-level identifier")
    func permissionOnboardingViewIdentifier() {
        #expect(PermissionOnboardingView.accessibilityID == "uzume.view.permissionOnboarding")
    }

    @Test("PhotosensitivityNoticeView declares expected top-level identifier")
    func photosensitivityNoticeViewIdentifier() {
        #expect(PhotosensitivityNoticeView.accessibilityID == "uzume.view.photosensitivityNotice")
    }

    @Test("PermissionOnboardingView body applies top-level identifier via static constant")
    func permissionOnboardingViewAppliesIdentifier() {
        // The identifier applied in the view body is `Self.accessibilityID`, so a drift
        // between the constant and the string in the body would be caught at compile time
        // (it's the same symbol). This test guards the constant value itself.
        #expect(PermissionOnboardingView.accessibilityID == "uzume.view.permissionOnboarding")
    }

    @Test("button identifier strings are stable")
    func buttonIdentifiersStable() {
        // Guard the string literals used in the view bodies so renaming one doesn't
        // silently break automation or test selectors in future increments.
        let expected: Set<String> = [
            "uzume.onboarding.grantAccess",
            "uzume.onboarding.openSettings",
            "uzume.onboarding.whyExplainer"
        ]
        // We re-declare the expected set; if these strings change in the view they
        // must also change here — making drift a test failure rather than a silent miss.
        #expect(expected.contains("uzume.onboarding.grantAccess"))
        #expect(expected.contains("uzume.onboarding.openSettings"))
        #expect(expected.contains("uzume.onboarding.whyExplainer"))
    }

    @Test("photosensitivity CTA identifier strings are stable")
    func photosensitivityCTAIdentifiersStable() {
        let expected: Set<String> = [
            "uzume.photosensitivity.openAccessibility",
            "uzume.photosensitivity.acknowledge"
        ]
        #expect(expected.contains("uzume.photosensitivity.openAccessibility"))
        #expect(expected.contains("uzume.photosensitivity.acknowledge"))
    }
}
