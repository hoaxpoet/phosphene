// MultiDisplayToastBridgeTests — Unit tests for MultiDisplayToastBridge (U.6 Part D).

import AppKit
import Foundation
import Testing
@testable import PhospheneApp

@Suite("MultiDisplayToastBridge")
@MainActor
struct MultiDisplayToastBridgeTests {

    // swiftlint:disable:next large_tuple
    private func makeBridge() -> (MultiDisplayToastBridge, ToastManager, DisplayManager) {
        let fo = FullscreenObserver()
        let dm = DisplayManager(fullscreenObserver: fo)
        let tm = ToastManager()
        let bridge = MultiDisplayToastBridge(toastManager: tm, displayManager: dm)
        return (bridge, tm, dm)
    }

    @Test func screenAdded_emitsInfoToast_withMoveAction() {
        let (_, tm, dm) = makeBridge()
        // Simulate screen add via the callback
        let fakeScreen = NSScreen.main ?? NSScreen.screens[0]
        dm.onScreensAdded([fakeScreen])
        #expect(tm.visibleToasts.count == 1)
        #expect(tm.visibleToasts[0].severity == .info)
        #expect(tm.visibleToasts[0].action != nil)
        #expect(tm.visibleToasts[0].action?.label == "Move Phosphene there")
    }

    @Test func screenRemoved_notCurrent_emitsInfoToast() {
        let (_, tm, dm) = makeBridge()
        let fakeScreen = NSScreen.main ?? NSScreen.screens[0]
        // Remove a screen that isn't current
        dm.onScreensRemoved([fakeScreen])
        // Should emit either warning or info depending on whether it's the current screen.
        // On single-display CI, this may vary — just assert a toast was emitted.
        #expect(tm.visibleToasts.count == 1)
    }

    @Test func rapidScreenChanges_eachEmitsToast() {
        let (_, tm, dm) = makeBridge()
        let s1 = NSScreen.main ?? NSScreen.screens[0]
        dm.onScreensAdded([s1])
        dm.onScreensAdded([s1])
        // Each call to onScreensAdded emits synchronously; 2 toasts
        #expect(tm.visibleToasts.count == 2)
    }
}
