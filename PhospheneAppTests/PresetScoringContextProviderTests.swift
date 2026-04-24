// PresetScoringContextProviderTests — Tests for PresetScoringContextProvider (U.8 Part C).

import Foundation
import Orchestrator
import Shared
import Testing
@testable import PhospheneApp

// MARK: - PresetScoringContextProviderTests

@Suite("PresetScoringContextProvider")
@MainActor
struct PresetScoringContextProviderTests {

    private func makeProvider(detectedTier: DeviceTier = .tier1) -> (PresetScoringContextProvider, SettingsStore) {
        guard let suite = UserDefaults(suiteName: "com.phosphene.test.prov.\(UUID().uuidString)") else {
            fatalError("test suite init failed")
        }
        let store = SettingsStore(defaults: suite)
        return (PresetScoringContextProvider(settingsStore: store, detectedTier: detectedTier), store)
    }

    @Test func deviceTierOverrideAuto_usesDetected() {
        let (provider, store) = makeProvider(detectedTier: .tier1)
        store.deviceTierOverride = .auto
        #expect(provider.effectiveTier == .tier1)
    }

    @Test func deviceTierOverrideForceTier1_returnsT1() {
        let (provider, store) = makeProvider(detectedTier: .tier2)
        store.deviceTierOverride = .forceTier1
        #expect(provider.effectiveTier == .tier1)
    }

    @Test func deviceTierOverrideForceTier2_returnsT2() {
        let (provider, store) = makeProvider(detectedTier: .tier1)
        store.deviceTierOverride = .forceTier2
        #expect(provider.effectiveTier == .tier2)
    }

    @Test func excludedFamilies_storedInSettings_readByProvider() {
        // Verifies that excludedPresetCategories is stored and readable.
        // The propagation to PresetScoringContext.excludedFamilies is tested
        // after Part C extends PresetScoringContext.
        let (_, store) = makeProvider()
        store.excludedPresetCategories = [.geometric, .fluid]
        #expect(store.excludedPresetCategories.contains(.geometric))
        #expect(store.excludedPresetCategories.contains(.fluid))
    }

    @Test func qualityCeiling_storedInSettings_readByProvider() {
        // Verifies qualityCeiling is stored. Context propagation tested after Part C.
        let (_, store) = makeProvider()
        store.qualityCeiling = .performance
        #expect(store.qualityCeiling == .performance)
    }
}
