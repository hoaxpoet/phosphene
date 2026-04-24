// FullscreenObserverTests — Unit tests for FullscreenObserver (U.6 Part D).
//
// NSWindow.didEnterFullScreenNotification / didExitFullScreenNotification are
// synthesized by posting to NotificationCenter with a dummy object reference.

import AppKit
import Testing
@testable import PhospheneApp

@Suite("FullscreenObserver")
@MainActor
struct FullscreenObserverTests {

    @Test func receivesDidEnterNotification_setsTrue() async throws {
        let observer = FullscreenObserver()
        let window = NSWindow()
        observer.attach(to: window)
        #expect(!observer.isFullscreen)

        NotificationCenter.default.post(
            name: NSWindow.didEnterFullScreenNotification,
            object: window
        )
        try await Task.sleep(for: .milliseconds(20))
        #expect(observer.isFullscreen)

        observer.detach()
    }

    @Test func receivesDidExitNotification_setsFalse() async throws {
        let observer = FullscreenObserver()
        let window = NSWindow()
        observer.attach(to: window)

        // Enter first
        NotificationCenter.default.post(
            name: NSWindow.didEnterFullScreenNotification,
            object: window
        )
        try await Task.sleep(for: .milliseconds(20))
        #expect(observer.isFullscreen)

        // Then exit
        NotificationCenter.default.post(
            name: NSWindow.didExitFullScreenNotification,
            object: window
        )
        try await Task.sleep(for: .milliseconds(20))
        #expect(!observer.isFullscreen)

        observer.detach()
    }
}
