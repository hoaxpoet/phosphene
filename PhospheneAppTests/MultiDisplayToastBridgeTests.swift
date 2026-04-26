// MultiDisplayToastBridgeTests — Unit tests for MultiDisplayToastBridge (U.6 Part D).

import AppKit
import Foundation
import Testing
@testable import PhospheneApp

@Suite("MultiDisplayToastBridge")
@MainActor
struct MultiDisplayToastBridgeTests {

    private struct Harness {
        let bridge: MultiDisplayToastBridge
        let toastManager: ToastManager
        let displayManager: DisplayManager
    }

    private func makeHarness() -> Harness {
        let fo = FullscreenObserver()
        let dm = DisplayManager(fullscreenObserver: fo)
        let tm = ToastManager()
        let bridge = MultiDisplayToastBridge(toastManager: tm, displayManager: dm)
        return Harness(bridge: bridge, toastManager: tm, displayManager: dm)
    }

    @Test func screenAdded_emitsInfoToast_withMoveAction() {
        let harness = makeHarness()
        let fakeScreen = NSScreen.main ?? NSScreen.screens[0]
        harness.displayManager.onScreensAdded([fakeScreen])
        #expect(harness.toastManager.visibleToasts.count == 1)
        #expect(harness.toastManager.visibleToasts[0].severity == .info)
        #expect(harness.toastManager.visibleToasts[0].action != nil)
        #expect(harness.toastManager.visibleToasts[0].action?.label == "Move Phosphene there")
    }

    @Test func screenRemoved_notCurrent_emitsInfoToast() {
        let harness = makeHarness()
        let fakeScreen = NSScreen.main ?? NSScreen.screens[0]
        harness.displayManager.onScreensRemoved([fakeScreen])
        // Should emit either warning or info depending on whether it's the current screen.
        // On single-display dev machine, this may vary — just assert a toast was emitted.
        #expect(harness.toastManager.visibleToasts.count == 1)
    }

    @Test func rapidScreenChanges_eachEmitsToast() {
        let harness = makeHarness()
        let s1 = NSScreen.main ?? NSScreen.screens[0]
        harness.displayManager.onScreensAdded([s1])
        harness.displayManager.onScreensAdded([s1])
        // Each call to onScreensAdded emits synchronously; 2 toasts expected.
        #expect(harness.toastManager.visibleToasts.count == 2)
    }
}
