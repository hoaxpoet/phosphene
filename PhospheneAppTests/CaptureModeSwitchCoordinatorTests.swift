// CaptureModeSwitchCoordinatorTests — Verifies the capture-mode switch session-state
// preservation contract (Increment 7.2, D-061).
//
// Tests verify D-061(b,c):
//  1. Non-localFile switch → grace window flag set; silence threshold raised.
//  2. Grace window raises PlaybackErrorBridge threshold to 20s.
//  3. After window closes: thresholds restored; isGraceWindowActive == false.
//  4. localFile switch → no grace window (D-052 path preserved).
//  5. Consecutive grace window opens: second cancels first (idempotent).

import Audio
import Combine
import Foundation
import Testing
@testable import PhospheneApp

// MARK: - MockCaptureModeSwitchEngine

/// Test double for CaptureModeSwitchEngineInterface — no Metal required.
@MainActor
final class MockCaptureModeSwitchEngine: CaptureModeSwitchEngineInterface {
    var captureModeSwitchGraceWindowEndsAt: Date?
}

// MARK: - CaptureModeSwitchCoordinatorTests

@Suite("CaptureModeSwitchCoordinator")
@MainActor
struct CaptureModeSwitchCoordinatorTests {

    // MARK: - Helpers

    private struct Fixture {
        let store: SettingsStore
        let toastManager: ToastManager
        let errorBridge: PlaybackErrorBridge
        let mockEngine: MockCaptureModeSwitchEngine
        let coordinator: CaptureModeSwitchCoordinator
    }

    private func makeFixture() -> Fixture {
        guard let suite = UserDefaults(suiteName: "com.phosphene.test.cmsw.\(UUID().uuidString)") else {
            fatalError("test UserDefaults init failed")
        }
        let store = SettingsStore(defaults: suite)
        let tm = ToastManager()
        let subject = CurrentValueSubject<AudioSignalState, Never>(.active)
        let bridge = PlaybackErrorBridge(
            audioSignalStatePublisher: subject.eraseToAnyPublisher(),
            toastManager: tm
        )
        let mockEngine = MockCaptureModeSwitchEngine()
        let coordinator = CaptureModeSwitchCoordinator(
            engine: mockEngine,
            playbackErrorBridge: bridge,
            settingsStore: store
        )
        return Fixture(
            store: store,
            toastManager: tm,
            errorBridge: bridge,
            mockEngine: mockEngine,
            coordinator: coordinator
        )
    }

    // MARK: - Tests

    @Test("grace window not active initially")
    func test_initialState_noGraceWindow() {
        let fix = makeFixture()
        #expect(fix.coordinator.isGraceWindowActive == false)
        #expect(fix.errorBridge.effectiveThresholdSeconds ==
                PlaybackErrorBridge.silenceToastThresholdSeconds)
    }

    @Test("openGraceWindow sets isGraceWindowActive and engine flag")
    func test_openGraceWindow_setsFlags() {
        let fix = makeFixture()
        fix.coordinator.openGraceWindow()

        #expect(fix.coordinator.isGraceWindowActive == true)
        #expect(fix.mockEngine.captureModeSwitchGraceWindowEndsAt != nil)
    }

    @Test("openGraceWindow raises silence threshold to 20s")
    func test_openGraceWindow_raisesThresholdTo20s() {
        let fix = makeFixture()
        fix.coordinator.openGraceWindow()
        #expect(fix.errorBridge.effectiveThresholdSeconds == 20)
        #expect(fix.errorBridge.effectiveThresholdSeconds ==
                PlaybackErrorBridge.silenceToastGraceWindowThresholdSeconds)
    }

    @Test("closeGraceWindow restores threshold to 15s and clears flags")
    func test_closeGraceWindow_restoresThreshold() {
        let fix = makeFixture()
        fix.coordinator.openGraceWindow()
        fix.coordinator.closeGraceWindow()

        #expect(fix.coordinator.isGraceWindowActive == false)
        #expect(fix.mockEngine.captureModeSwitchGraceWindowEndsAt == nil)
        #expect(fix.errorBridge.effectiveThresholdSeconds ==
                PlaybackErrorBridge.silenceToastThresholdSeconds)
    }

    @Test("localFile mode does not open grace window")
    func test_localFile_noGraceWindow() {
        let fix = makeFixture()
        fix.store.captureMode = .localFile

        // The coordinator's handleModeChange returns early for .localFile.
        // Grace window state should be untouched.
        #expect(fix.coordinator.isGraceWindowActive == false)
        #expect(fix.errorBridge.effectiveThresholdSeconds ==
                PlaybackErrorBridge.silenceToastThresholdSeconds)
    }

    @Test("consecutive openGraceWindow calls are idempotent for threshold")
    func test_consecutiveOpen_idempotent() {
        let fix = makeFixture()
        fix.coordinator.openGraceWindow()
        fix.coordinator.openGraceWindow()   // second call should replace first

        #expect(fix.coordinator.isGraceWindowActive == true)
        #expect(fix.errorBridge.effectiveThresholdSeconds == 20)
    }
}
