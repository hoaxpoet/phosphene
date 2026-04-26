// LiveAdaptationToastBridgeTests — Unit tests for LiveAdaptationToastBridge (U.6 Part C).

import Foundation
import Testing
@testable import PhospheneApp

@Suite("LiveAdaptationToastBridge")
@MainActor
struct LiveAdaptationToastBridgeTests {

    @Test func flagOff_noToast_onEmitAck() async throws {
        let tm = ToastManager()
        let bridge = LiveAdaptationToastBridge(toastManager: tm)
        // Default: flag is off (UserDefaults.bool returns false by default)
        UserDefaults.standard.removeObject(forKey: LiveAdaptationToastBridge.userDefaultsKey)
        bridge.emitAck("Test message")
        try await Task.sleep(for: .milliseconds(50))
        #expect(tm.visibleToasts.isEmpty, "Flag off — no toast should appear")
    }

    @Test func flagOn_emitAck_createsInfoToast() async throws {
        let tm = ToastManager()
        let bridge = LiveAdaptationToastBridge(toastManager: tm)
        UserDefaults.standard.set(true, forKey: LiveAdaptationToastBridge.userDefaultsKey)
        defer { UserDefaults.standard.removeObject(forKey: LiveAdaptationToastBridge.userDefaultsKey) }

        bridge.emitAck("Plan adjusted")
        // 2600ms gives 600ms margin over the 2s coalescing window — accounts for
        // @MainActor contention during parallel test runs.
        try await Task.sleep(for: .milliseconds(2600))
        try #require(tm.visibleToasts.count == 1)
        #expect(tm.visibleToasts[0].severity == .info)
        #expect(tm.visibleToasts[0].source == .liveAdaptationAck)
    }

    @Test func rapidAdaptations_coalesced_intoSingleToast() async throws {
        let tm = ToastManager()
        let bridge = LiveAdaptationToastBridge(toastManager: tm)
        UserDefaults.standard.set(true, forKey: LiveAdaptationToastBridge.userDefaultsKey)
        defer { UserDefaults.standard.removeObject(forKey: LiveAdaptationToastBridge.userDefaultsKey) }

        bridge.emitAck("Change 1")
        bridge.emitAck("Change 2")
        bridge.emitAck("Change 3")
        try await Task.sleep(for: .milliseconds(2600))
        try #require(tm.visibleToasts.count == 1)
        #expect(tm.visibleToasts[0].copy.contains("3"))
    }

    @Test func flagOn_singleMessage_usesMessageDirectly() async throws {
        let tm = ToastManager()
        let bridge = LiveAdaptationToastBridge(toastManager: tm)
        UserDefaults.standard.set(true, forKey: LiveAdaptationToastBridge.userDefaultsKey)
        defer { UserDefaults.standard.removeObject(forKey: LiveAdaptationToastBridge.userDefaultsKey) }

        bridge.emitAck("Skipping organic for 10 min")
        try await Task.sleep(for: .milliseconds(2600))
        try #require(tm.visibleToasts.count == 1)
        #expect(tm.visibleToasts[0].copy == "Skipping organic for 10 min")
    }
}
