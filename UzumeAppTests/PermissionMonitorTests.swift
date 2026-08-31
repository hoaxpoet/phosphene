// PermissionMonitorTests — Tests for PermissionMonitor observable + refresh behaviour.
//
// Uses a stub ScreenCapturePermissionProviding and an injected NotificationCenter
// so tests run without system permission dialogs or notification side effects.

import AppKit
import Combine
import Testing
@testable import PhospheneApp

// MARK: - Stub Provider

/// In-memory permission provider whose return value can be flipped between tests.
private final class StubPermissionProvider: ScreenCapturePermissionProviding, @unchecked Sendable {
    var granted: Bool
    init(granted: Bool) { self.granted = granted }
    func isGranted() -> Bool { granted }
}

// MARK: - Tests

@Suite("PermissionMonitor")
@MainActor
struct PermissionMonitorTests {

    // MARK: Initial state

    @Test("reflects provider state at init when denied")
    func initReflectsDeniedState() {
        let provider = StubPermissionProvider(granted: false)
        let monitor = PermissionMonitor(provider: provider, notificationCenter: .init())
        #expect(monitor.isScreenCaptureGranted == false)
    }

    @Test("reflects provider state at init when granted")
    func initReflectsGrantedState() {
        let provider = StubPermissionProvider(granted: true)
        let monitor = PermissionMonitor(provider: provider, notificationCenter: .init())
        #expect(monitor.isScreenCaptureGranted == true)
    }

    // MARK: Manual refresh

    @Test("refresh re-reads from provider")
    func refreshRereadsProvider() {
        let provider = StubPermissionProvider(granted: false)
        let monitor = PermissionMonitor(provider: provider, notificationCenter: .init())
        #expect(monitor.isScreenCaptureGranted == false)

        provider.granted = true
        monitor.refresh()

        #expect(monitor.isScreenCaptureGranted == true)
    }

    @Test("refresh to false when provider revokes")
    func refreshRevokes() {
        let provider = StubPermissionProvider(granted: true)
        let monitor = PermissionMonitor(provider: provider, notificationCenter: .init())
        #expect(monitor.isScreenCaptureGranted == true)

        provider.granted = false
        monitor.refresh()

        #expect(monitor.isScreenCaptureGranted == false)
    }

    // MARK: Foreground notification

    @Test("didBecomeActive notification triggers refresh via injected notification centre")
    func didBecomeActiveNotificationTriggersRefresh() async throws {
        let provider = StubPermissionProvider(granted: false)
        let center = NotificationCenter()
        let monitor = PermissionMonitor(provider: provider, notificationCenter: center)
        #expect(monitor.isScreenCaptureGranted == false)

        provider.granted = true
        center.post(name: NSApplication.didBecomeActiveNotification, object: nil)

        // Combine's receive(on: DispatchQueue.main) needs a run-loop turn.
        try await Task.sleep(for: .milliseconds(50))
        #expect(monitor.isScreenCaptureGranted == true)
    }
}
