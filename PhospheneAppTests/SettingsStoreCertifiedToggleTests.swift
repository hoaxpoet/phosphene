// SettingsStoreCertifiedToggleTests — V.6 certification toggle gate.
//
// Tests:
//   1. showUncertifiedPresets defaults to false.
//   2. Setting true persists to UserDefaults and survives reload.
//   3. PresetScoringContextProvider propagates the toggle to PresetScoringContext.

import Testing
import Foundation
@testable import PhospheneApp
import Orchestrator
import Presets
import Shared

// MARK: - Helpers (reuse the isolated-defaults pattern from SettingsStoreTests)

private func makeSuite() -> UserDefaults {
    let name = "com.phosphene.test.certified.\(UUID().uuidString)"
    guard let suite = UserDefaults(suiteName: name) else { fatalError("UserDefaults suite init failed") }
    return suite
}

private func teardown(_ defaults: UserDefaults) {
    UserDefaults.standard.removePersistentDomain(forName: defaults.description)
}

// MARK: - Suite

@Suite("SettingsStore — showUncertifiedPresets")
@MainActor
struct SettingsStoreCertifiedToggleTests {

    // MARK: - 1. Default is false

    @Test func default_showUncertifiedPresets_isFalse() {
        let defaults = makeSuite()
        defer { teardown(defaults) }
        let store = SettingsStore(defaults: defaults)

        #expect(store.showUncertifiedPresets == false)
    }

    // MARK: - 2. Persists to UserDefaults

    @Test func setTrue_persistsAcrossReload() {
        let defaults = makeSuite()
        defer { teardown(defaults) }
        let store = SettingsStore(defaults: defaults)

        store.showUncertifiedPresets = true

        let store2 = SettingsStore(defaults: defaults)
        #expect(store2.showUncertifiedPresets == true)
    }

    @Test func setFalse_afterTrue_persistsAcrossReload() {
        let defaults = makeSuite()
        defer { teardown(defaults) }
        let store = SettingsStore(defaults: defaults)

        store.showUncertifiedPresets = true
        store.showUncertifiedPresets = false

        let store2 = SettingsStore(defaults: defaults)
        #expect(store2.showUncertifiedPresets == false)
    }

    // MARK: - 3. Propagates to PresetScoringContext

    @Test func provider_propagatesToggleTrue_toContext() {
        let defaults = makeSuite()
        defer { teardown(defaults) }
        let store = SettingsStore(defaults: defaults)
        store.showUncertifiedPresets = true

        let provider = PresetScoringContextProvider(settingsStore: store, detectedTier: .tier2)
        let ctx = provider.build()

        #expect(ctx.includeUncertifiedPresets == true)
    }

    @Test func provider_propagatesToggleFalse_toContext() {
        let defaults = makeSuite()
        defer { teardown(defaults) }
        let store = SettingsStore(defaults: defaults)
        store.showUncertifiedPresets = false  // explicit false (matches default)

        let provider = PresetScoringContextProvider(settingsStore: store, detectedTier: .tier2)
        let ctx = provider.build()

        #expect(ctx.includeUncertifiedPresets == false)
    }
}
