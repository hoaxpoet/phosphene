// SettingsStoreTests — Persistence round-trip tests for SettingsStore (U.8 Part A).

import Foundation
import Testing
@testable import PhospheneApp

// MARK: - Helpers

private func makeSuite() -> UserDefaults {
    let name = "com.phosphene.test.settings.\(UUID().uuidString)"
    guard let suite = UserDefaults(suiteName: name) else { fatalError("test suite init failed") }
    return suite
}

private func teardown(_ defaults: UserDefaults) {
    UserDefaults.standard.removePersistentDomain(forName: defaults.description)
}

// MARK: - SettingsStoreTests

@Suite("SettingsStore")
@MainActor
struct SettingsStoreTests {

    @Test func init_noStoredValues_returnsDefaults() {
        let defaults = makeSuite()
        defer { teardown(defaults) }
        let store = SettingsStore(defaults: defaults)

        #expect(store.captureMode == .systemAudio)
        #expect(store.sourceAppOverride == nil)
        #expect(store.deviceTierOverride == .auto)
        #expect(store.qualityCeiling == .auto)
        #expect(store.includeMilkdropPresets == true)
        #expect(store.reducedMotion == .matchSystem)
        #expect(store.excludedPresetCategories.isEmpty)
        #expect(store.showLiveAdaptationToasts == false)
        #expect(store.sessionRecorderEnabled == true)
        #expect(store.sessionRetention == .lastN10)
        #expect(store.showPerformanceWarnings == false)
    }

    @Test func setCaptureMode_persistsToUserDefaults() {
        let defaults = makeSuite()
        defer { teardown(defaults) }
        let store = SettingsStore(defaults: defaults)

        store.captureMode = .specificApp

        let store2 = SettingsStore(defaults: defaults)
        #expect(store2.captureMode == .specificApp)
    }

    @Test func setAndReload_roundTripsAllEnumSettings() {
        let defaults = makeSuite()
        defer { teardown(defaults) }
        let store = SettingsStore(defaults: defaults)

        store.captureMode = .localFile
        store.deviceTierOverride = .forceTier2
        store.qualityCeiling = .ultra
        store.reducedMotion = .alwaysOn
        store.sessionRetention = .oneWeek

        let store2 = SettingsStore(defaults: defaults)
        #expect(store2.captureMode == .localFile)
        #expect(store2.deviceTierOverride == .forceTier2)
        #expect(store2.qualityCeiling == .ultra)
        #expect(store2.reducedMotion == .alwaysOn)
        #expect(store2.sessionRetention == .oneWeek)
    }

    @Test func setAndReload_roundTripsExcludedPresetCategories() {
        let defaults = makeSuite()
        defer { teardown(defaults) }
        let store = SettingsStore(defaults: defaults)

        store.excludedPresetCategories = [.geometric, .fluid]

        let store2 = SettingsStore(defaults: defaults)
        #expect(store2.excludedPresetCategories == [.geometric, .fluid])
    }

    @Test func setSourceAppOverride_roundTrips() {
        let defaults = makeSuite()
        defer { teardown(defaults) }
        let store = SettingsStore(defaults: defaults)

        let override = SourceAppOverride(bundleIdentifier: "com.spotify.client", displayName: "Spotify")
        store.sourceAppOverride = override

        let store2 = SettingsStore(defaults: defaults)
        #expect(store2.sourceAppOverride == override)
    }

    @Test func clearSourceAppOverride_removesValue() {
        let defaults = makeSuite()
        defer { teardown(defaults) }
        let store = SettingsStore(defaults: defaults)

        store.sourceAppOverride = SourceAppOverride(bundleIdentifier: "com.x", displayName: "X")
        store.sourceAppOverride = nil

        let store2 = SettingsStore(defaults: defaults)
        #expect(store2.sourceAppOverride == nil)
    }

    @Test func resetOnboarding_clearsOnboardingKeys_preservesOtherSettings() {
        let defaults = makeSuite()
        defer { teardown(defaults) }
        let store = SettingsStore(defaults: defaults)

        defaults.set(true, forKey: "phosphene.onboarding.photosensitivityAcknowledged")
        store.sessionRecorderEnabled = false

        store.resetOnboarding()

        #expect(defaults.object(forKey: "phosphene.onboarding.photosensitivityAcknowledged") == nil)
        let store2 = SettingsStore(defaults: defaults)
        #expect(store2.sessionRecorderEnabled == false)
    }

    @Test func captureModeChange_publishesEvent() async {
        let defaults = makeSuite()
        defer { teardown(defaults) }
        let store = SettingsStore(defaults: defaults)

        var received = false
        let cancellable = store.captureModeChanged.sink { received = true }
        _ = cancellable

        store.captureMode = .specificApp

        #expect(received)
    }

    @Test func deviceTierOverride_enforcesAutoDefault() {
        let defaults = makeSuite()
        defer { teardown(defaults) }
        let store = SettingsStore(defaults: defaults)
        #expect(store.deviceTierOverride == .auto)
    }

    @Test func sessionRetention_enforcesLastN10Default() {
        let defaults = makeSuite()
        defer { teardown(defaults) }
        let store = SettingsStore(defaults: defaults)
        #expect(store.sessionRetention == .lastN10)
    }

    @Test func showPerformanceWarnings_default_isFalse() {
        let defaults = makeSuite()
        defer { teardown(defaults) }
        let store = SettingsStore(defaults: defaults)
        #expect(store.showPerformanceWarnings == false)
    }

    @Test func showLiveAdaptationToasts_default_isFalse() {
        let defaults = makeSuite()
        defer { teardown(defaults) }
        let store = SettingsStore(defaults: defaults)
        #expect(store.showLiveAdaptationToasts == false)
    }

    @Test func includeMilkdropPresets_default_isTrue() {
        let defaults = makeSuite()
        defer { teardown(defaults) }
        let store = SettingsStore(defaults: defaults)
        #expect(store.includeMilkdropPresets == true)
    }
}
