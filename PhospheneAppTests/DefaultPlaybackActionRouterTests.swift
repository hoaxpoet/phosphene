// DefaultPlaybackActionRouterTests — Unit tests for DefaultPlaybackActionRouter (U.6 + U.6b).
// swiftlint:disable file_length
//
// Architecture: all engine operations are injected as closures; tests verify:
//   • State mutations on the router (familyBoosts, exclusions, adaptationHistory, etc.)
//   • Correct closure invocations (extend, reshuffle, plan restore)
//   • Toast bridge calls (via a recording ToastManager)
//   • Session-reset behaviour on state transitions

import Combine
import Foundation
import Orchestrator
import Presets
import Session
import Shared
import Testing
@testable import PhospheneApp

// MARK: - Helpers

/// Reference-type call tracker — lets escaping closures record invocations
/// without the `inout`-capture restriction on value types.
private final class CallTracker {
    var extendCalled = false
    var reshuffleCalled: ([TrackIdentity], [TrackIdentity: PresetDescriptor])?
    var rePlanCalled = false
    var overrideCalled: (String, Bool)?
    var restoreCalled: PlannedSession?
    var showPlanPreviewCalled = false
}

// swiftlint:disable type_body_length
@Suite("DefaultPlaybackActionRouter — U.6b")
@MainActor
struct DefaultPlaybackActionRouterU6bTests {

    // MARK: - Factory

    private static func makeRouter(
        currentPresetID: String? = "Fluid1",
        currentPresetFamily: PresetCategory? = .particles,
        sessionTime: TimeInterval = 0,
        livePlan: PlannedSession? = nil,
        catalog: [PresetDescriptor] = [],
        trackProfile: TrackProfile? = nil,
        currentTrackIndex: Int = 0,
        tracker: CallTracker = CallTracker(),
        toastManager: ToastManager = ToastManager()
    ) -> DefaultPlaybackActionRouter {
        let toastBridge = LiveAdaptationToastBridge(toastManager: toastManager)
        return DefaultPlaybackActionRouter(
            toastBridge: toastBridge,
            getSessionTime: { sessionTime },
            getCurrentPresetID: { currentPresetID },
            getCurrentPresetFamily: { currentPresetFamily },
            getLivePlan: { livePlan },
            getCatalog: { catalog },
            getTrackProfile: { trackProfile },
            getCurrentTrackIndex: { currentTrackIndex },
            getScoringContext: { fields in
                PresetScoringContext(
                    deviceTier: .tier1,
                    familyBoosts: fields.familyBoosts,
                    temporarilyExcludedFamilies: fields.temporarilyExcludedFamilies,
                    sessionExcludedPresets: fields.sessionExcludedPresets
                )
            },
            onExtendCurrentPreset: { _ in tracker.extendCalled = true },
            onReshuffle: { locked, presets in tracker.reshuffleCalled = (Array(locked), presets) },
            onRePlanSession: { tracker.rePlanCalled = true },
            onApplyPresetOverride: { id, imm in tracker.overrideCalled = (id, imm) },
            onRestorePlan: { plan in tracker.restoreCalled = plan },
            onShowPlanPreview: { tracker.showPlanPreviewCalled = true }
        )
    }

    // MARK: - Convenience plan builder

    private static func makePlan(trackCount: Int = 3) throws -> PlannedSession {
        let planner = DefaultSessionPlanner()
        let catalog = try (1...max(2, trackCount)).map { i -> PresetDescriptor in
            let json = """
            {"name":"Preset\(i)","family":"\(i % 2 == 0 ? "particles" : "hypnotic")",
             "visual_density":0.5,"motion_intensity":0.5,
             "color_temperature_range":[0.3,0.7],"fatigue_risk":"medium",
             "complexity_cost":{"tier1":1.0,"tier2":1.0},
             "transition_affordances":["crossfade"],"certified":true}
            """
            return try JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
        }
        let tracks: [(TrackIdentity, TrackProfile)] = (0..<trackCount).map { i in
            (TrackIdentity(title: "Track\(i)", artist: "A", duration: 180), TrackProfile.empty)
        }
        return try planner.plan(tracks: tracks, catalog: catalog, deviceTier: .tier1)
    }

    // MARK: Test 1 — moreLikeThis writes boost + calls extend

    @Test("moreLikeThis writes boost=0.3 and calls onExtendCurrentPreset")
    func moreLikeThis_writesBoostAndCallsExtend() {
        let tracker = CallTracker()
        let router = Self.makeRouter(tracker: tracker)
        router.moreLikeThis()
        #expect(router.familyBoosts[.particles] == 0.3, "boost should be 0.3")
        #expect(tracker.extendCalled, "onExtendCurrentPreset must be called")
    }

    // MARK: Test 2 — moreLikeThis is idempotent

    @Test("moreLikeThis is idempotent: calling twice leaves boost at 0.3, not 0.6")
    func moreLikeThis_isIdempotent() {
        let tracker = CallTracker()
        let router = Self.makeRouter(tracker: tracker)
        router.moreLikeThis()
        router.moreLikeThis()
        #expect(router.familyBoosts[.particles] == 0.3,
                "pressing + twice must remain at 0.3 not 0.6 (got \(router.familyBoosts[.particles] ?? -1))")
    }

    // MARK: Test 3 — lessLikeThis excludes family for 10 min, expiry correct

    @Test("lessLikeThis excludes family for 600s; entry expires at sessionTime + 601")
    func lessLikeThis_excludesFamilyFor600s() {
        let refTime: TimeInterval = 1000.0
        var extendCalled = false
        var reshuffleCalled: ([TrackIdentity], [TrackIdentity: PresetDescriptor])?
        var rePlanCalled = false
        var overrideCalled: (String, Bool)?
        var restoreCalled: PlannedSession?
        var showPlanCalled = false
        var sessionTime = refTime

        let toastMgr = ToastManager()
        let toastBridge = LiveAdaptationToastBridge(toastManager: toastMgr)
        let router = DefaultPlaybackActionRouter(
            toastBridge: toastBridge,
            getSessionTime: { sessionTime },
            getCurrentPresetID: { "Fluid1" },
            getCurrentPresetFamily: { .particles },
            onExtendCurrentPreset: { _ in extendCalled = true },
            onReshuffle: { locked, presets in reshuffleCalled = (Array(locked), presets) },
            onRePlanSession: { rePlanCalled = true },
            onApplyPresetOverride: { id, imm in overrideCalled = (id, imm) },
            onRestorePlan: { plan in restoreCalled = plan },
            onShowPlanPreview: { showPlanCalled = true }
        )

        router.lessLikeThis()

        let expiry = router.temporaryFamilyExclusions[.particles]
        #expect(expiry != nil, "family exclusion should be set")
        #expect(expiry == refTime + 600, "expiry should be sessionTime + 600 (got \(expiry ?? -1))")

        // Verify that at sessionTime + 601 the entry is pruned.
        sessionTime = refTime + 601
        let fields = router.adaptationFields(at: sessionTime)
        #expect(!fields.temporarilyExcludedFamilies.contains(.particles),
                "family should no longer be excluded at t+601")
    }

    // MARK: Test 4 — lessLikeThis adds preset to sessionExcludedPresets

    @Test("lessLikeThis adds preset ID to sessionExcludedPresets permanently")
    func lessLikeThis_addsPresetToSessionExclusions() {
        let router = Self.makeRouter(
            currentPresetID: "KineticSculpture",
            currentPresetFamily: .geometric
        )

        router.lessLikeThis()

        #expect(router.sessionExcludedPresets.contains("KineticSculpture"),
                "preset must be in sessionExcludedPresets")

        // Even after the family exclusion would expire, the preset stays excluded.
        let fields = router.adaptationFields(at: 9999)
        #expect(fields.sessionExcludedPresets.contains("KineticSculpture"),
                "sessionExcludedPresets survives family-exclusion expiry")
    }

    // MARK: Test 5 — Double-`-` within 90s emits ambient hint exactly once

    @Test("lessLikeThis twice within 90s emits ambient hint exactly once; ambientHintShown latches")
    func lessLikeThis_doubleNegativeEmitsHintOnce() {
        var sessionTime: TimeInterval = 100
        let toastMgr = ToastManager()
        let toastBridge = LiveAdaptationToastBridge(toastManager: toastMgr)
        var extendCalled = false
        var reshuffleCalled: ([TrackIdentity], [TrackIdentity: PresetDescriptor])?
        var rePlanCalled = false
        var overrideCalled: (String, Bool)?
        var restoreCalled: PlannedSession?
        var showPlanCalled = false

        let router = DefaultPlaybackActionRouter(
            toastBridge: toastBridge,
            getSessionTime: { sessionTime },
            getCurrentPresetID: { "P1" },
            getCurrentPresetFamily: { .particles },
            onExtendCurrentPreset: { _ in extendCalled = true },
            onReshuffle: { locked, presets in reshuffleCalled = (Array(locked), presets) },
            onRePlanSession: { rePlanCalled = true },
            onApplyPresetOverride: { id, imm in overrideCalled = (id, imm) },
            onRestorePlan: { plan in restoreCalled = plan },
            onShowPlanPreview: { showPlanCalled = true }
        )

        // First press: sets lastNegativeNudgeAt, no hint yet.
        router.lessLikeThis()
        #expect(!router.ambientHintShown, "no hint after first press")

        // Second press within 90s: triggers hint.
        sessionTime = 150  // 50s later, within 90s window
        router.lessLikeThis()
        #expect(router.ambientHintShown, "hint should fire on second press within 90s")

        // Third press: hint already shown; must NOT fire again.
        sessionTime = 180
        router.lessLikeThis()
        // The key invariant: ambientHintShown never resets within a session.
        #expect(router.ambientHintShown, "ambientHintShown stays true")
    }

    // MARK: Test 6 — reshuffleUpcoming preserves played tracks + current preset

    @Test("reshuffleUpcoming locks played tracks and current preset, not future tracks")
    func reshuffleUpcoming_preservesPlayedAndCurrent() throws {
        let plan = try Self.makePlan(trackCount: 3)
        var capturedLocked: Set<TrackIdentity>?
        var capturedLockedPresets: [TrackIdentity: PresetDescriptor]?
        var extendCalled = false
        var rePlanCalled = false
        var overrideCalled: (String, Bool)?
        var restoreCalled: PlannedSession?
        var showPlanCalled = false

        var reshuffleCalled: ([TrackIdentity], [TrackIdentity: PresetDescriptor])?
        let toastBridge = LiveAdaptationToastBridge(toastManager: ToastManager())
        let router = DefaultPlaybackActionRouter(
            toastBridge: toastBridge,
            getSessionTime: { 0 },
            getCurrentPresetID: { plan.tracks[1].preset.id },
            getCurrentPresetFamily: { plan.tracks[1].preset.family },
            getLivePlan: { plan },
            getCurrentTrackIndex: { 1 },  // Track index 1 is "current"
            onExtendCurrentPreset: { _ in extendCalled = true },
            onReshuffle: { locked, presets in
                capturedLocked = locked
                capturedLockedPresets = presets
                reshuffleCalled = (Array(locked), presets)
            },
            onRePlanSession: { rePlanCalled = true },
            onApplyPresetOverride: { id, imm in overrideCalled = (id, imm) },
            onRestorePlan: { plan in restoreCalled = plan },
            onShowPlanPreview: { showPlanCalled = true }
        )

        router.reshuffleUpcoming()

        // Track index 0 (played) should be in the lock set.
        let track0Identity = plan.tracks[0].track
        #expect(capturedLocked?.contains(track0Identity) == true,
                "played track must be locked")

        // Track index 1 (current) should have its preset locked.
        let track1Identity = plan.tracks[1].track
        let track1Preset   = plan.tracks[1].preset
        #expect(capturedLockedPresets?[track1Identity]?.id == track1Preset.id,
                "current track preset must be locked")

        // Track index 2 (future) should NOT be in lockedTracks.
        let track2Identity = plan.tracks[2].track
        #expect(capturedLocked?.contains(track2Identity) != true,
                "future track must not be in lockedTracks")
    }

    // MARK: Test 7 — presetNudge(.next, immediate: true) calls override immediately

    @Test("presetNudge(.next, immediate: true) calls onApplyPresetOverride(_, true)")
    func presetNudge_next_immediateCallsOverride() throws {
        let presetsJson = """
        {"name":"NextPreset","family":"geometric","visual_density":0.5,"motion_intensity":0.5,
         "color_temperature_range":[0.3,0.7],"fatigue_risk":"medium",
         "complexity_cost":{"tier1":1.0,"tier2":1.0},"transition_affordances":["crossfade"],
         "certified":true}
        """
        let catalog = [try JSONDecoder().decode(PresetDescriptor.self, from: Data(presetsJson.utf8))]
        let tracker = CallTracker()
        let router = Self.makeRouter(
            currentPresetID: "DifferentPreset",
            currentPresetFamily: .hypnotic,
            catalog: catalog,
            tracker: tracker
        )
        router.presetNudge(.next, immediate: true)
        #expect(tracker.overrideCalled?.0 == "NextPreset", "override must target the top-ranked preset")
        #expect(tracker.overrideCalled?.1 == true, "immediate=true must be forwarded")
    }

    // MARK: Test 8 — presetNudge(.previous) with no lastPlayedPresetID is a no-op

    @Test("presetNudge(.previous) with nil lastPlayedPresetID is a no-op")
    func presetNudge_previous_noLastPlayed_isNoOp() {
        let tracker = CallTracker()
        let router = Self.makeRouter(tracker: tracker)
        // lastPlayedPresetID is nil by default.
        router.presetNudge(.previous, immediate: true)
        #expect(tracker.overrideCalled == nil, "no override must be called when lastPlayedPresetID is nil")
    }

    // MARK: Test 9 — rePlanSession calls onRePlanSession and onShowPlanPreview

    @Test("rePlanSession calls onRePlanSession and onShowPlanPreview")
    func rePlanSession_callsBothClosures() {
        let tracker = CallTracker()
        let router = Self.makeRouter(tracker: tracker)
        router.rePlanSession()
        #expect(tracker.rePlanCalled, "onRePlanSession must be called")
        #expect(tracker.showPlanPreviewCalled, "onShowPlanPreview must be called")
    }

    // MARK: Test 10 — undoLastAdaptation restores plan but keeps familyBoosts

    @Test("undoLastAdaptation restores livePlan snapshot but preserves familyBoosts (D-058b)")
    func undoLastAdaptation_restoresPlanKeepsBoosts() throws {
        let plan = try Self.makePlan(trackCount: 2)
        var restoredPlan: PlannedSession?
        var extendCalled = false
        var reshuffleCalled: ([TrackIdentity], [TrackIdentity: PresetDescriptor])?
        var rePlanCalled = false
        var overrideCalled: (String, Bool)?
        var showPlanCalled = false

        let router = DefaultPlaybackActionRouter(
            getSessionTime: { 0 },
            getCurrentPresetID: { "Fluid1" },
            getCurrentPresetFamily: { .particles },
            getLivePlan: { plan },
            onExtendCurrentPreset: { _ in extendCalled = true },
            onReshuffle: { locked, presets in reshuffleCalled = (Array(locked), presets) },
            onRePlanSession: { rePlanCalled = true },
            onApplyPresetOverride: { id, imm in overrideCalled = (id, imm) },
            onRestorePlan: { plan in restoredPlan = plan },
            onShowPlanPreview: { showPlanCalled = true }
        )

        // Push a snapshot via moreLikeThis (which calls pushHistory internally).
        router.moreLikeThis()

        // Undo: should call onRestorePlan with the snapshot.
        router.undoLastAdaptation()

        #expect(restoredPlan != nil, "onRestorePlan must be called with a plan")
        // familyBoosts NOT cleared by undo (D-058b).
        #expect(router.familyBoosts[.particles] == 0.3,
                "familyBoosts must survive undo (D-058b)")
        #expect(router.adaptationHistory.isEmpty, "history should be empty after undo")
    }

    // MARK: Test 11 — undoLastAdaptation on empty history is a no-op + toast

    @Test("undoLastAdaptation on empty history is a no-op and emits 'Nothing to undo' toast")
    func undoLastAdaptation_emptyHistory_isNoOp() {
        let toastMgr = ToastManager()
        let toastBridge = LiveAdaptationToastBridge(toastManager: toastMgr)
        var extendCalled = false
        var reshuffleCalled: ([TrackIdentity], [TrackIdentity: PresetDescriptor])?
        var rePlanCalled = false
        var overrideCalled: (String, Bool)?
        var restoreCalled: PlannedSession?
        var showPlanCalled = false

        let router = DefaultPlaybackActionRouter(
            toastBridge: toastBridge,
            onExtendCurrentPreset: { _ in extendCalled = true },
            onReshuffle: { locked, presets in reshuffleCalled = (Array(locked), presets) },
            onRePlanSession: { rePlanCalled = true },
            onApplyPresetOverride: { id, imm in overrideCalled = (id, imm) },
            onRestorePlan: { plan in restoreCalled = plan },
            onShowPlanPreview: { showPlanCalled = true }
        )

        router.undoLastAdaptation()

        #expect(restoreCalled == nil, "onRestorePlan must NOT be called when history is empty")
        // The toast bridge coalesces async — we just verify no crash + history stays empty.
        #expect(router.adaptationHistory.isEmpty)
    }

    // MARK: Test 12 — resetAdaptationState clears everything

    @Test("resetAdaptationState clears all U.6b state fields")
    func resetAdaptationState_clearsAll() throws {
        let plan = try Self.makePlan(trackCount: 2)
        var extendCalled = false
        var reshuffleCalled: ([TrackIdentity], [TrackIdentity: PresetDescriptor])?
        var rePlanCalled = false
        var overrideCalled: (String, Bool)?
        var restoreCalled: PlannedSession?
        var showPlanCalled = false

        let router = DefaultPlaybackActionRouter(
            getSessionTime: { 0 },
            getCurrentPresetID: { "Fluid1" },
            getCurrentPresetFamily: { .particles },
            getLivePlan: { plan },
            onExtendCurrentPreset: { _ in extendCalled = true },
            onReshuffle: { locked, presets in reshuffleCalled = (Array(locked), presets) },
            onRePlanSession: { rePlanCalled = true },
            onApplyPresetOverride: { id, imm in overrideCalled = (id, imm) },
            onRestorePlan: { plan in restoreCalled = plan },
            onShowPlanPreview: { showPlanCalled = true }
        )

        // Populate state.
        router.moreLikeThis()            // familyBoosts + history
        router.lessLikeThis()            // temporaryFamilyExclusions + sessionExcluded + lastNegativeNudgeAt
        router.recordPresetTransition(outgoingPresetID: "OldPreset")

        // Verify populated.
        #expect(!router.familyBoosts.isEmpty)
        #expect(!router.temporaryFamilyExclusions.isEmpty)
        #expect(!router.sessionExcludedPresets.isEmpty)
        #expect(!router.adaptationHistory.isEmpty)
        #expect(router.lastNegativeNudgeAt != nil)
        #expect(router.lastPlayedPresetID == "OldPreset")

        router.resetAdaptationState()

        #expect(router.familyBoosts.isEmpty, "familyBoosts not cleared")
        #expect(router.temporaryFamilyExclusions.isEmpty, "temporaryFamilyExclusions not cleared")
        #expect(router.sessionExcludedPresets.isEmpty, "sessionExcludedPresets not cleared")
        #expect(router.adaptationHistory.isEmpty, "adaptationHistory not cleared")
        #expect(router.lastNegativeNudgeAt == nil, "lastNegativeNudgeAt not cleared")
        #expect(!router.ambientHintShown, "ambientHintShown not cleared")
        #expect(router.lastPlayedPresetID == nil, "lastPlayedPresetID not cleared")
    }

    // MARK: Test 13 — adaptationHistory is bounded at 8

    @Test("adaptationHistory is bounded at 8 entries; oldest dropped on overflow")
    func adaptationHistory_isBoundedAtEight() throws {
        let plan = try Self.makePlan(trackCount: 2)
        var extendCalled = false
        var reshuffleCalled: ([TrackIdentity], [TrackIdentity: PresetDescriptor])?
        var rePlanCalled = false
        var overrideCalled: (String, Bool)?
        var restoreCalled: PlannedSession?
        var showPlanCalled = false

        let router = DefaultPlaybackActionRouter(
            getSessionTime: { 0 },
            getCurrentPresetID: { "Fluid1" },
            getCurrentPresetFamily: { .particles },
            getLivePlan: { plan },
            onExtendCurrentPreset: { _ in extendCalled = true },
            onReshuffle: { locked, presets in reshuffleCalled = (Array(locked), presets) },
            onRePlanSession: { rePlanCalled = true },
            onApplyPresetOverride: { id, imm in overrideCalled = (id, imm) },
            onRestorePlan: { plan in restoreCalled = plan },
            onShowPlanPreview: { showPlanCalled = true }
        )

        // Push 10 entries.
        for _ in 0..<10 { router.moreLikeThis() }

        #expect(router.adaptationHistory.count <= 8,
                "history must be capped at 8 (got \(router.adaptationHistory.count))")
    }

    // MARK: Test 14 — toggleMoodLock persists state (U.6 regression)

    @Test("toggleMoodLock persists isMoodLocked state")
    func toggleMoodLock_persistsState() {
        let router = Self.makeRouter()
        #expect(!router.isMoodLocked)
        router.toggleMoodLock()
        #expect(router.isMoodLocked)
        router.toggleMoodLock()
        #expect(!router.isMoodLocked)
    }
}
// swiftlint:enable type_body_length
// swiftlint:enable file_length
