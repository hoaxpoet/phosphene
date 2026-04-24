// CaptureModeReconcilerTests — Tests for CaptureModeReconciler (U.8 Part C).
//
// Decision: LIVE-SWITCH PATH via AudioInputRouter.switchMode(_:).
// These tests verify the reconciler's logic: mode mapping and "coming later" toast.
// Live AudioInputRouter switching is integration-tested manually (smoke test step 2).

import Audio
import Foundation
import Testing
@testable import PhospheneApp

// MARK: - CaptureModeReconcilerTests

@Suite("CaptureModeReconciler")
@MainActor
struct CaptureModeReconcilerTests {

    @available(macOS 14.2, *)
    private struct ReconcilerFixture {
        let reconciler: CaptureModeReconciler
        let store: SettingsStore
        let toasts: ToastManager
    }

    @available(macOS 14.2, *)
    private func makeReconciler() -> ReconcilerFixture {
        guard let suite = UserDefaults(suiteName: "com.phosphene.test.cap.\(UUID().uuidString)") else {
            fatalError("test suite init failed")
        }
        let store = SettingsStore(defaults: suite)
        let toasts = ToastManager()
        let harness = CaptureModeReconcilerTestHarness(settingsStore: store, toastManager: toasts)
        return ReconcilerFixture(reconciler: harness.reconciler, store: store, toasts: toasts)
    }

    @available(macOS 14.2, *)
    @Test func localFileMode_showsComingLaterToast() {
        let fixture = makeReconciler()
        fixture.store.captureMode = .localFile
        fixture.reconciler.reconcile()
        #expect(fixture.toasts.visibleToasts.count == 1)
    }

    @Test func captureModeChange_publishesEventFromStore() {
        guard let suite = UserDefaults(suiteName: "com.phosphene.test.cap2.\(UUID().uuidString)") else {
            fatalError("test suite init failed")
        }
        let store = SettingsStore(defaults: suite)

        var eventCount = 0
        let cancellable = store.captureModeChanged.sink { eventCount += 1 }
        _ = cancellable

        store.captureMode = .specificApp
        store.captureMode = .systemAudio

        #expect(eventCount == 2)
    }
}

// MARK: - CaptureModeReconcilerTestHarness

/// Wraps CaptureModeReconciler for unit tests that don't need a live router.
@available(macOS 14.2, *)
@MainActor
private struct CaptureModeReconcilerTestHarness {
    let reconciler: CaptureModeReconciler

    init(settingsStore: SettingsStore, toastManager: ToastManager) {
        self.reconciler = CaptureModeReconciler(
            settingsStore: settingsStore,
            router: AudioInputRouter(),
            toastManager: toastManager
        )
    }
}
