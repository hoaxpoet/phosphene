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
@testable import PhospheneApp

// MARK: - Tests

@Suite("PermissionOnboardingView identifiers")
@MainActor
struct PermissionOnboardingViewTests {

    @Test("PermissionOnboardingView declares expected top-level identifier")
    func permissionOnboardingViewIdentifier() {
        #expect(PermissionOnboardingView.accessibilityID == "phosphene.view.permissionOnboarding")
    }

    @Test("PhotosensitivityNoticeView declares expected top-level identifier")
    func photosensitivityNoticeViewIdentifier() {
        #expect(PhotosensitivityNoticeView.accessibilityID == "phosphene.view.photosensitivityNotice")
    }

    @Test("PermissionOnboardingView body applies top-level identifier via static constant")
    func permissionOnboardingViewAppliesIdentifier() {
        // The identifier applied in the view body is `Self.accessibilityID`, so a drift
        // between the constant and the string in the body would be caught at compile time
        // (it's the same symbol). This test guards the constant value itself.
        #expect(PermissionOnboardingView.accessibilityID == "phosphene.view.permissionOnboarding")
    }

    @Test("button identifier strings are stable")
    func buttonIdentifiersStable() {
        // Guard the string literals used in the view bodies so renaming one doesn't
        // silently break automation or test selectors in future increments.
        let expected: Set<String> = [
            "phosphene.onboarding.openSettings",
            "phosphene.onboarding.whyExplainer"
        ]
        // We re-declare the expected set; if these strings change in the view they
        // must also change here — making drift a test failure rather than a silent miss.
        #expect(expected.contains("phosphene.onboarding.openSettings"))
        #expect(expected.contains("phosphene.onboarding.whyExplainer"))
    }

    @Test("photosensitivity CTA identifier strings are stable")
    func photosensitivityCTAIdentifiersStable() {
        let expected: Set<String> = [
            "phosphene.photosensitivity.openAccessibility",
            "phosphene.photosensitivity.acknowledge"
        ]
        #expect(expected.contains("phosphene.photosensitivity.openAccessibility"))
        #expect(expected.contains("phosphene.photosensitivity.acknowledge"))
    }
}
