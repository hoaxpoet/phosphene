// PhotosensitivityAcknowledgementStoreTests — Exercises UserDefaults persistence contract.
//
// Each test uses a dedicated UserDefaults suite (never .standard) and removes the
// persistent domain in teardown so acknowledgement state doesn't leak between runs.

import Foundation
import Testing
@testable import PhospheneApp

// MARK: - Tests

// Type name kept ≤ 40 chars per SwiftLint type_name rule.
@Suite("PhotosensitivityAcknowledgementStore")
struct PhotosensitivityStoreTests {

    @Test("defaults to not acknowledged on fresh suite")
    func defaultsFalse() throws {
        let suiteName = "test.photosensitivity.default"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let store = PhotosensitivityAcknowledgementStore(defaults: defaults)
        #expect(store.isAcknowledged == false)
    }

    @Test("markAcknowledged persists across store instances")
    func markAcknowledgedPersists() throws {
        let suiteName = "test.photosensitivity.persist"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let storeA = PhotosensitivityAcknowledgementStore(defaults: defaults)
        storeA.markAcknowledged()

        let storeB = PhotosensitivityAcknowledgementStore(defaults: defaults)
        #expect(storeB.isAcknowledged == true)
    }

    @Test("separate suites do not leak acknowledgement state")
    func separateSuitesDoNotLeak() throws {
        let suiteAcknowledged = "test.photosensitivity.leak.acknowledged"
        let suiteClean = "test.photosensitivity.leak.clean"
        defer {
            UserDefaults.standard.removePersistentDomain(forName: suiteAcknowledged)
            UserDefaults.standard.removePersistentDomain(forName: suiteClean)
        }

        let acknowledgedDefaults = try #require(UserDefaults(suiteName: suiteAcknowledged))
        let acknowledgedStore = PhotosensitivityAcknowledgementStore(defaults: acknowledgedDefaults)
        acknowledgedStore.markAcknowledged()

        let cleanDefaults = try #require(UserDefaults(suiteName: suiteClean))
        let cleanStore = PhotosensitivityAcknowledgementStore(defaults: cleanDefaults)
        #expect(cleanStore.isAcknowledged == false)
    }

    @Test("markAcknowledged is idempotent")
    func idempotent() throws {
        let suiteName = "test.photosensitivity.idempotent"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let store = PhotosensitivityAcknowledgementStore(defaults: defaults)
        store.markAcknowledged()
        store.markAcknowledged()
        #expect(store.isAcknowledged == true)
    }
}
