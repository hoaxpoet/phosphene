// DefaultPlaybackActionRouterTests — Unit tests for DefaultPlaybackActionRouter (U.6 Part B).

import Foundation
import Orchestrator
import Session
import Testing
@testable import PhospheneApp

// MARK: - Suite

@Suite("DefaultPlaybackActionRouter")
@MainActor
struct DefaultPlaybackActionRouterTests {

    @Test func allStubs_invokeWithoutCrash() {
        let router = DefaultPlaybackActionRouter()
        // All stubs should be callable without throwing or crashing.
        router.moreLikeThis()
        router.lessLikeThis()
        router.reshuffleUpcoming()
        router.presetNudge(.next, immediate: false)
        router.presetNudge(.previous, immediate: true)
        router.rePlanSession()
        router.undoLastAdaptation()
        // No assertions needed — absence of crash is the invariant.
        #expect(true)
    }

    @Test func toggleMoodLock_persistsState() {
        let router = DefaultPlaybackActionRouter()
        #expect(!router.isMoodLocked)
        router.toggleMoodLock()
        #expect(router.isMoodLocked)
        router.toggleMoodLock()
        #expect(!router.isMoodLocked)
    }
}
