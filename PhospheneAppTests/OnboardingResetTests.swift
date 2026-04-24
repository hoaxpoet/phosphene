// OnboardingResetTests — Tests for OnboardingReset (U.8 Part C).

import Foundation
import Testing
@testable import PhospheneApp

// MARK: - OnboardingResetTests

@Suite("OnboardingReset")
struct OnboardingResetTests {

    private func makeDefaults(_ tag: String = UUID().uuidString) -> UserDefaults {
        guard let suite = UserDefaults(suiteName: "com.phosphene.test.onb.\(tag)") else {
            fatalError("test suite init failed")
        }
        return suite
    }

    @Test func reset_clearsAllOnboardingKeys() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: "phosphene.onboarding.photosensitivityAcknowledged")

        OnboardingReset.resetAllOnboardingState(in: defaults)

        for key in OnboardingReset.onboardingKeys {
            #expect(defaults.object(forKey: key) == nil)
        }
    }

    @Test func reset_doesNotClearSettings() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: "phosphene.settings.diagnostics.sessionRecorderEnabled")
        defaults.set(true, forKey: "phosphene.onboarding.photosensitivityAcknowledged")

        OnboardingReset.resetAllOnboardingState(in: defaults)

        // Settings key must be preserved.
        #expect(defaults.bool(forKey: "phosphene.settings.diagnostics.sessionRecorderEnabled") == true)
        // Onboarding key must be cleared.
        #expect(defaults.object(forKey: "phosphene.onboarding.photosensitivityAcknowledged") == nil)
    }
}
