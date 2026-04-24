// OnboardingReset — Clears all onboarding UserDefaults keys.
// Takes effect on next app launch — does NOT re-show onboarding in the current session.

import Foundation

// MARK: - OnboardingReset

enum OnboardingReset {

    /// All keys cleared by a reset. Add new onboarding keys here as they land.
    static let onboardingKeys: [String] = [
        "phosphene.onboarding.photosensitivityAcknowledged",
    ]

    /// Clears all onboarding state from `defaults`. Settings values are preserved.
    static func resetAllOnboardingState(in defaults: UserDefaults = .standard) {
        for key in onboardingKeys {
            defaults.removeObject(forKey: key)
        }
    }
}
