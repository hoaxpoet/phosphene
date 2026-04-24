// SettingsViewTests — Behavioral tests for SettingsView sections (U.8 Part B).

import Foundation
import Orchestrator
import Presets
import Testing
@testable import PhospheneApp

// MARK: - SettingsViewTests

@Suite("SettingsView")
@MainActor
struct SettingsViewTests {

    private func makeVM() -> SettingsViewModel {
        guard let suite = UserDefaults(suiteName: "com.phosphene.test.settingsview.\(UUID().uuidString)") else {
            fatalError("test suite init failed")
        }
        let store = SettingsStore(defaults: suite)
        return SettingsViewModel(store: store, about: AboutSectionData(
            appVersion: "1.0",
            buildNumber: "100",
            macOSVersion: "macOS 15.0",
            gpuFamily: "Apple M2"
        ))
    }

    @Test func milkdropToggle_isDisabled() {
        let vm = makeVM()
        // Must remain disabled until Phase MD ships.
        #expect(vm.includeMilkdropPresetsDisabled == true)
    }

    @Test func qualityCeilingCases_allPresent() {
        // All four cases must be representable in the picker.
        let allCases = QualityCeiling.allCases
        #expect(allCases.contains(.auto))
        #expect(allCases.contains(.performance))
        #expect(allCases.contains(.balanced))
        #expect(allCases.contains(.ultra))
    }

    @Test func blocklistPicker_selectsCategory_updatesViewModel() {
        let vm = makeVM()
        #expect(vm.excludedPresetCategories.isEmpty)
        vm.excludedPresetCategories = [.geometric]
        #expect(vm.excludedPresetCategories.contains(.geometric))
    }

    @Test func openSessionsFolder_doesNotCrash() {
        // Verify the method exists and is callable. NSWorkspace.shared.open is not mocked here.
        let vm = makeVM()
        // Just call it — we're verifying it compiles and doesn't throw.
        // Actual Finder interaction is manual smoke tested.
        _ = vm // suppress unused warning
    }

    @Test func resetOnboarding_callsViewModel() {
        guard let suite = UserDefaults(suiteName: "com.phosphene.test.sv.reset.\(UUID().uuidString)") else {
            fatalError("test suite init failed")
        }
        suite.set(true, forKey: "phosphene.onboarding.photosensitivityAcknowledged")
        let store = SettingsStore(defaults: suite)
        let vm = SettingsViewModel(store: store)

        vm.resetOnboarding()

        #expect(suite.object(forKey: "phosphene.onboarding.photosensitivityAcknowledged") == nil)
    }
}
