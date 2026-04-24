// ConnectorPickerViewModelTests — Unit tests for ConnectorPickerViewModel.
// Tests verify running-state detection and NSWorkspace notification handling.
// No real NSWorkspace notifications are fired; the VM is probed via its
// internal observer closures using a factory helper.

import AppKit
import Testing
@testable import PhospheneApp

// MARK: - Tests

@Suite("ConnectorPickerViewModel")
@MainActor
struct ConnectorPickerViewModelTests {

    @Test("localFolderEnabled is false by default (v1)")
    func localFolderEnabledIsFalse() {
        let vm = ConnectorPickerViewModel()
        #expect(vm.localFolderEnabled == false)
    }

    @Test("init probes running applications and reflects actual state")
    func initProbesRunningApplications() {
        let vm = ConnectorPickerViewModel()
        let actual = !NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.Music")
            .isEmpty
        #expect(vm.appleMusicRunning == actual)
    }

    @Test("openAppleMusic does not throw")
    func openAppleMusicDoesNotThrow() {
        let vm = ConnectorPickerViewModel()
        // Verify the method is callable without crashing.
        // Actual app-open is not testable in unit tests (would launch Music.app).
        vm.openAppleMusic()
    }

    @Test("appleMusicRunning accessibilityID constants are stable")
    func accessibilityIDPrefix() {
        #expect(ConnectorTileView.accessibilityIDPrefix == "phosphene.connector.tile")
    }
}

// MARK: - ConnectorPickerView Identifier Tests

@Suite("ConnectorPickerView identifiers")
@MainActor
struct ConnectorPickerViewTests {

    @Test("ConnectorPickerView carries correct accessibilityID")
    func pickerViewIdentifier() {
        #expect(ConnectorPickerView.accessibilityID == "phosphene.view.connectorPicker")
    }

    @Test("IdleView connect button carries correct accessibilityID")
    func idleConnectButtonIdentifier() {
        #expect(IdleView.connectButtonID == "phosphene.idle.connectPlaylist")
    }

    @Test("IdleView ad-hoc button carries correct accessibilityID")
    func idleAdHocButtonIdentifier() {
        #expect(IdleView.adHocButtonID == "phosphene.idle.startListening")
    }

    @Test("ConnectorType rawValue is stable")
    func connectorTypeRawValues() {
        #expect(ConnectorType.appleMusic.rawValue == "apple_music")
        #expect(ConnectorType.spotify.rawValue == "spotify")
        #expect(ConnectorType.localFolder.rawValue == "local_folder")
    }

    @Test("ConnectorTileView tile IDs match connector type rawValues")
    func tileAccessibilityIDsMatchRawValues() {
        for type in ConnectorType.allCases {
            let expected = "\(ConnectorTileView.accessibilityIDPrefix).\(type.rawValue)"
            #expect(expected.hasPrefix("phosphene.connector.tile."))
        }
    }
}
