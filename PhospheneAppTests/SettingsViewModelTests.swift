// SettingsViewModelTests — Tests for SettingsViewModel (U.8 Part A).

import Foundation
import Testing
@testable import PhospheneApp

// MARK: - SettingsViewModelTests

@Suite("SettingsViewModel")
@MainActor
struct SettingsViewModelTests {

    private func makeDefaults(_ tag: String = UUID().uuidString) -> UserDefaults {
        guard let suite = UserDefaults(suiteName: "com.phosphene.test.vm.\(tag)") else {
            fatalError("test suite init failed")
        }
        return suite
    }

    private func makeVM() -> (SettingsViewModel, SettingsStore) {
        let defaults = makeDefaults()
        let store = SettingsStore(defaults: defaults)
        let about = AboutSectionData(
            appVersion: "1.0",
            buildNumber: "100",
            macOSVersion: "macOS 15.0",
            gpuFamily: "Apple M2"
        )
        return (SettingsViewModel(store: store, about: about), store)
    }

    @Test func bindings_forwardToStore() {
        let (vm, store) = makeVM()

        vm.captureMode = .specificApp
        #expect(store.captureMode == .specificApp)

        vm.showLiveAdaptationToasts = true
        #expect(store.showLiveAdaptationToasts == true)

        vm.sessionRecorderEnabled = false
        #expect(store.sessionRecorderEnabled == false)
    }

    @Test func resetOnboarding_forwardsToStore() {
        let defaults = makeDefaults()
        let store = SettingsStore(defaults: defaults)
        let vm = SettingsViewModel(store: store)
        defaults.set(true, forKey: "phosphene.onboarding.photosensitivityAcknowledged")

        vm.resetOnboarding()

        #expect(defaults.object(forKey: "phosphene.onboarding.photosensitivityAcknowledged") == nil)
    }

    @Test func aboutSection_populatedFromInjectedData() {
        let (vm, _) = makeVM()
        #expect(vm.about.appVersion == "1.0")
        #expect(vm.about.buildNumber == "100")
        #expect(vm.about.macOSVersion == "macOS 15.0")
        #expect(vm.about.gpuFamily == "Apple M2")
    }

    @Test func includeMilkdropPresetsDisabled_flagIsTrue_untilPhaseMD() {
        let (vm, _) = makeVM()
        // Must remain true until Phase MD ships. This test is the enforcement gate.
        #expect(vm.includeMilkdropPresetsDisabled == true)
    }

    @Test func debugInfo_containsSystemInfo_noAudioData() {
        let (vm, _) = makeVM()
        let info = vm.about.debugInfo
        #expect(info.contains("Phosphene"))
        #expect(info.contains("1.0"))
        #expect(info.contains("Apple M2"))
        // Must not contain audio or session data keywords.
        #expect(!info.contains("bass"))
        #expect(!info.contains("FFT"))
        #expect(!info.contains("stem"))
    }
}
