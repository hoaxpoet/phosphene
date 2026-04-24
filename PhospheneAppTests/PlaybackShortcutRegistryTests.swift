// PlaybackShortcutRegistryTests — Unit tests for PlaybackShortcutRegistry (U.6 Part B).

import Foundation
import Orchestrator
import Testing
@testable import PhospheneApp

// MARK: - Stub router

@MainActor
private final class StubActionRouter: PlaybackActionRouter, @unchecked Sendable {
    var isMoodLocked: Bool = false
    var moreLikeThisCount = 0
    var lessLikeThisCount = 0
    var reshuffleCount = 0
    var nudgeCalls: [(NudgeDirection, Bool)] = []
    var rePlanCount = 0
    var undoCount = 0
    var toggleMoodLockCount = 0

    func moreLikeThis() { moreLikeThisCount += 1 }
    func lessLikeThis() { lessLikeThisCount += 1 }
    func reshuffleUpcoming() { reshuffleCount += 1 }
    func presetNudge(_ direction: NudgeDirection, immediate: Bool) { nudgeCalls.append((direction, immediate)) }
    func rePlanSession() { rePlanCount += 1 }
    func undoLastAdaptation() { undoCount += 1 }
    func toggleMoodLock() { toggleMoodLockCount += 1; isMoodLocked.toggle() }
}

@MainActor
private func makeRegistry() -> (PlaybackShortcutRegistry, StubActionRouter) {
    let router = StubActionRouter()
    let registry = PlaybackShortcutRegistry(
        actionRouter: router,
        onToggleFullscreen: {},
        onMoveToSecondaryDisplay: {},
        onToggleOverlay: {},
        onToggleDebug: {},
        onHandleEsc: {},
        onShowHelp: {},
        onShowPlanPreview: {}
    )
    return (registry, router)
}

// MARK: - Suite

@Suite("PlaybackShortcutRegistry")
@MainActor
struct PlaybackShortcutRegistryTests {

    @Test func allShortcutsUnique_byID() {
        let (registry, _) = makeRegistry()
        let ids = registry.shortcuts.map(\.id)
        let uniqueIDs = Set(ids)
        #expect(ids.count == uniqueIDs.count, "Duplicate shortcut IDs: \(ids)")
    }

    @Test func registryCoversAllExpectedIDs() {
        let (registry, _) = makeRegistry()
        let expectedIDs: Set<String> = [
            "fullscreenToggle", "fullscreenSecondary", "overlayToggle", "moodLock",
            "endSession", "helpOverlay", "planPreview",
            "moreLikeThis", "lessLikeThis", "reshuffleUpcoming",
            "presetNudgeNext", "presetNudgePrev", "presetCutNext", "presetCutPrev",
            "rePlan", "undoAdaptation", "debugToggle"
        ]
        let registeredIDs = Set(registry.shortcuts.map(\.id))
        let missing = expectedIDs.subtracting(registeredIDs)
        #expect(missing.isEmpty, "Missing shortcut IDs: \(missing)")
    }

    @Test func actionRouterStubs_areInvokable_withoutCrash() {
        let (_, router) = makeRegistry()
        router.moreLikeThis()
        router.lessLikeThis()
        router.reshuffleUpcoming()
        router.presetNudge(.next, immediate: false)
        router.presetNudge(.previous, immediate: true)
        router.rePlanSession()
        router.undoLastAdaptation()
        router.toggleMoodLock()
        #expect(router.moreLikeThisCount == 1)
        #expect(router.nudgeCalls.count == 2)
        #expect(router.toggleMoodLockCount == 1)
    }
}
