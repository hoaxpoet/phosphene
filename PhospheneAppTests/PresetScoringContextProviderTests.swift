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

    @Test func excludedFamilies_propagatedToContext() {
        let (provider, store) = makeProvider()
        store.excludedPresetCategories = [.geometric, .particles]
        let ctx = provider.build()
        #expect(ctx.excludedFamilies.contains(.geometric))
        #expect(ctx.excludedFamilies.contains(.particles))
    }

    @Test func qualityCeiling_propagatedToContext() {
        let (provider, store) = makeProvider()
        store.qualityCeiling = .performance
        let ctx = provider.build()
        #expect(ctx.qualityCeiling == .performance)
    }
}
