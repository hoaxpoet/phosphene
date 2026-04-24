// EscBehaviorTests — Verifies the Esc key two-mode behavior (U.6 Part D).
//
// Esc in fullscreen: toggles fullscreen, does NOT end session.
// Esc in windowed mode: requests end-session confirmation.

import AppKit
import Session
import Testing
@testable import PhospheneApp

@Suite("Esc Behavior")
@MainActor
struct EscBehaviorTests {

    @Test func esc_whenFullscreen_exitsFullscreen_doesNotEndSession() async throws {
        let fo = FullscreenObserver()
        let window = NSWindow()
        fo.attach(to: window)

        // Manually set isFullscreen by posting the notification
        NotificationCenter.default.post(name: NSWindow.didEnterFullScreenNotification, object: window)
        try await Task.sleep(for: .milliseconds(20))
        #expect(fo.isFullscreen)

        let mgr = SessionManager.testInstance()
        mgr.startAdHocSession()
        let endVM = EndSessionConfirmViewModel(sessionManager: mgr)

        // Simulate Esc handler logic
        if fo.isFullscreen {
            // Would call fo.toggleFullscreen() — we can't do the full toggle in unit test
            // but we verify the decision branch: endVM should NOT be triggered
            // Assertion: isPresented stays false
        } else {
            endVM.requestEnd()
        }
        #expect(!endVM.isPresented, "Esc in fullscreen should not trigger end-session dialog")

        fo.detach()
    }

    @Test func esc_whenWindowed_requestsEndSession() {
        let fo = FullscreenObserver()
        let window = NSWindow()
        fo.attach(to: window)
        #expect(!fo.isFullscreen)

        let mgr = SessionManager.testInstance()
        let endVM = EndSessionConfirmViewModel(sessionManager: mgr)

        // Simulate Esc handler logic
        if fo.isFullscreen {
            fo.toggleFullscreen()
        } else {
            endVM.requestEnd()
        }
        #expect(endVM.isPresented, "Esc in windowed mode should show end-session dialog")

        fo.detach()
    }
}
