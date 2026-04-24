// ToastManagerConditionTests — Tests for condition-ID API on ToastManager (U.7 Part C).
//
// Tests:
//   1. dismissByCondition removes all toasts with matching conditionID.
//   2. isConditionAsserted returns true while the toast is visible.
//   3. isConditionAsserted returns false after dismissByCondition.

import Foundation
import Testing
@testable import PhospheneApp

@Suite("ToastManager condition-ID")
@MainActor
struct ToastManagerConditionTests {

    @Test("dismissByCondition removes matching toasts")
    func test_dismissByCondition_removesMatching() {
        let tm = ToastManager()
        let t1 = PhospheneToast(
            severity: .degradation, copy: "Silence", duration: .infinity, conditionID: "silence.extended")
        let t2 = PhospheneToast(severity: .info, copy: "Other", duration: .infinity, conditionID: nil)
        tm.enqueue(t1)
        tm.enqueue(t2)
        #expect(tm.visibleToasts.count == 2)

        tm.dismissByCondition("silence.extended")

        #expect(tm.visibleToasts.count == 1)
        #expect(tm.visibleToasts[0].copy == "Other")
    }

    @Test("isConditionAsserted returns true while toast visible")
    func test_isConditionAsserted_trueWhileVisible() {
        let tm = ToastManager()
        let toast = PhospheneToast(
            severity: .degradation, copy: "Silence", duration: .infinity, conditionID: "silence.extended")
        tm.enqueue(toast)
        #expect(tm.isConditionAsserted("silence.extended") == true)
    }

    @Test("isConditionAsserted returns false after dismissByCondition")
    func test_isConditionAsserted_falseAfterDismiss() {
        let tm = ToastManager()
        let toast = PhospheneToast(
            severity: .degradation, copy: "Silence", duration: .infinity, conditionID: "silence.extended")
        tm.enqueue(toast)
        tm.dismissByCondition("silence.extended")
        #expect(tm.isConditionAsserted("silence.extended") == false)
    }
}
