// PhotosensitivityAcknowledgementStore — Persists first-run photosensitivity acknowledgement.
//
// Backed by UserDefaults. Injectable suite name allows test isolation without touching .standard.

import Foundation

// MARK: - PhotosensitivityAcknowledgementStore

/// Persists whether the user has acknowledged the photosensitivity notice.
///
/// Key: `phosphene.onboarding.photosensitivityAcknowledged`.
/// Tests must construct with a named `UserDefaults` suite and tear it down after each test.
final class PhotosensitivityAcknowledgementStore {

    // MARK: - Private

    private enum Keys {
        static let acknowledged = "phosphene.onboarding.photosensitivityAcknowledged"
    }

    private let defaults: UserDefaults

    // MARK: - Init

    /// - Parameter defaults: Defaults suite to read from and write to. Defaults to `.standard`.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - API

    /// `true` after `markAcknowledged()` has been called at least once in this suite.
    var isAcknowledged: Bool {
        defaults.bool(forKey: Keys.acknowledged)
    }

    /// Persists the acknowledgement flag. Idempotent.
    func markAcknowledged() {
        defaults.set(true, forKey: Keys.acknowledged)
    }
}
