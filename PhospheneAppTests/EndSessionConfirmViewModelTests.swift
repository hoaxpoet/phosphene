// EndSessionConfirmViewModelTests — Unit tests for EndSessionConfirmViewModel (U.6 Part B).

import Session
import Testing
@testable import PhospheneApp

@Suite("EndSessionConfirmViewModel")
@MainActor
struct EndSessionConfirmViewModelTests {

    private func makeVM() -> (EndSessionConfirmViewModel, SessionManager) {
        let mgr = SessionManager.testInstance()
        let vm = EndSessionConfirmViewModel(sessionManager: mgr)
        return (vm, mgr)
    }

    @Test func requestEnd_setsPresentedTrue() {
        let (vm, _) = makeVM()
        #expect(!vm.isPresented)
        vm.requestEnd()
        #expect(vm.isPresented)
    }

    @Test func confirm_callsSessionManagerEndSession() {
        let (vm, mgr) = makeVM()
        mgr.startAdHocSession()
        #expect(mgr.state == .playing)
        vm.requestEnd()
        vm.confirm()
        #expect(mgr.state == .ended)
        #expect(!vm.isPresented)
    }

    @Test func cancel_dismissesWithoutEndingSession() {
        let (vm, mgr) = makeVM()
        mgr.startAdHocSession()
        vm.requestEnd()
        vm.cancel()
        #expect(!vm.isPresented)
        #expect(mgr.state == .playing)
    }
}
