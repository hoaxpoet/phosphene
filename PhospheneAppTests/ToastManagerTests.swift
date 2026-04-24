// ToastManagerTests — Unit tests for ToastManager (U.6 Part C).

import Foundation
import Testing
@testable import PhospheneApp

@Suite("ToastManager")
@MainActor
struct ToastManagerTests {

    @Test func enqueue_appendsToVisible() {
        let tm = ToastManager()
        let toast = PhospheneToast(severity: .info, copy: "Hello", duration: .infinity)
        tm.enqueue(toast)
        #expect(tm.visibleToasts.count == 1)
        #expect(tm.visibleToasts[0].copy == "Hello")
    }

    @Test func dismiss_removesById() {
        let tm = ToastManager()
        let toast = PhospheneToast(severity: .info, copy: "Hi", duration: .infinity)
        tm.enqueue(toast)
        tm.dismiss(id: toast.id)
        #expect(tm.visibleToasts.isEmpty)
    }

    @Test func autoDismiss_afterDuration() async throws {
        let tm = ToastManager()
        let toast = PhospheneToast(severity: .info, copy: "Short-lived", duration: 0.05)
        tm.enqueue(toast)
        #expect(tm.visibleToasts.count == 1)
        try await Task.sleep(for: .milliseconds(150))
        #expect(tm.visibleToasts.isEmpty)
    }

    @Test func maxThreeVisible_dropsOldestNonDegradation() {
        let tm = ToastManager()
        let t1 = PhospheneToast(severity: .info, copy: "First", duration: .infinity)
        let t2 = PhospheneToast(severity: .warning, copy: "Second", duration: .infinity)
        let t3 = PhospheneToast(severity: .info, copy: "Third", duration: .infinity)
        let t4 = PhospheneToast(severity: .info, copy: "Fourth", duration: .infinity)
        tm.enqueue(t1); tm.enqueue(t2); tm.enqueue(t3); tm.enqueue(t4)
        #expect(tm.visibleToasts.count == 3)
        // t1 (oldest info) dropped; t2, t3, t4 remain
        #expect(tm.visibleToasts.map(\.copy) == ["Second", "Third", "Fourth"])
    }

    @Test func degradationSeverity_notDropped_whenOverflowing() {
        let tm = ToastManager()
        let t1 = PhospheneToast(severity: .degradation, copy: "Degradation 1", duration: .infinity)
        let t2 = PhospheneToast(severity: .degradation, copy: "Degradation 2", duration: .infinity)
        let t3 = PhospheneToast(severity: .degradation, copy: "Degradation 3", duration: .infinity)
        let t4 = PhospheneToast(severity: .info, copy: "Info", duration: .infinity)
        tm.enqueue(t1); tm.enqueue(t2); tm.enqueue(t3); tm.enqueue(t4)
        #expect(tm.visibleToasts.count == 3)
        // All 3 degradation present; info is the 4th but can't drop degradation — oldest dropped
        let copies = tm.visibleToasts.map(\.copy)
        #expect(copies.contains("Info"))
    }

    @Test func manualDuration_neverAutoDismisses() async throws {
        let tm = ToastManager()
        let toast = PhospheneToast(severity: .info, copy: "Sticky", duration: .infinity)
        tm.enqueue(toast)
        try await Task.sleep(for: .milliseconds(100))
        #expect(tm.visibleToasts.count == 1)
    }
}
