// PlanPreviewRegenerateTests — Tests for PlanPreviewViewModel regeneration flow (U.5 Part D).

import Combine
import Foundation
import Orchestrator
import Presets
import Session
import Shared
import Testing
@testable import PhospheneApp

// MARK: - Helpers

private func makePreset(name: String) throws -> PresetDescriptor {
    let json = """
    {"name":"\(name)","family":"hypnotic","motion_intensity":0.5,
     "color_temperature_range":[0.3,0.7],"fatigue_risk":"medium",
     "complexity_cost":{"tier1":1.0,"tier2":1.0},
     "transition_affordances":["crossfade"]}
    """
    return try JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
}

private func makePlan(trackCount: Int = 3, duration: TimeInterval = 180) throws -> PlannedSession {
    let planner = DefaultSessionPlanner()
    let catalog = [try makePreset(name: "PresetA"), try makePreset(name: "PresetB")]
    let tracks: [(TrackIdentity, TrackProfile)] = (0..<trackCount).map { i in
        (TrackIdentity(title: "Track \(i + 1)", artist: "Artist", duration: duration),
         TrackProfile.empty)
    }
    return try planner.plan(tracks: tracks, catalog: catalog, deviceTier: .tier1)
}

@MainActor
private class CapturingSubject {
    private let subject = CurrentValueSubject<PlannedSession?, Never>(nil)
    var publisher: AnyPublisher<PlannedSession?, Never> { subject.eraseToAnyPublisher() }
    private(set) var regenerateCalls: [(Set<TrackIdentity>, [TrackIdentity: PresetDescriptor])] = []

    func makeOnRegenerate() -> @MainActor (Set<TrackIdentity>, [TrackIdentity: PresetDescriptor]) -> Void {
        return { [weak self] locked, presets in
            self?.regenerateCalls.append((locked, presets))
        }
    }

    func deliver(_ plan: PlannedSession?) { subject.send(plan) }
}

// MARK: - Suite

@Suite("PlanPreviewViewModel regeneration")
@MainActor
struct PlanPreviewRegenerateTests {

    @Test("regeneratePlan calls onRegenerate and sets isRegenerating")
    func regeneratePlan_callsOnRegenerateAndSetsSpinner() throws {
        let subject = CapturingSubject()
        let plan = try makePlan()
        let vm = PlanPreviewViewModel(
            initialPlan: plan,
            planPublisher: subject.publisher,
            onRegenerate: subject.makeOnRegenerate()
        )

        #expect(!vm.isRegenerating)
        vm.regeneratePlan()
        #expect(vm.isRegenerating, "spinner should show immediately")
        #expect(subject.regenerateCalls.count == 1)
    }

    @Test("regeneratePlan preserves manually locked track picks")
    func regeneratePlan_preservesManualLocks() async throws {
        let subject = CapturingSubject()
        let plan = try makePlan(trackCount: 2)

        var capturedLocked: Set<TrackIdentity> = []
        var capturedPresets: [TrackIdentity: PresetDescriptor] = [:]
        let vm = PlanPreviewViewModel(
            initialPlan: plan,
            planPublisher: subject.publisher,
            onRegenerate: { locked, presets in
                capturedLocked = locked
                capturedPresets = presets
            }
        )

        // Lock the first track to a specific preset.
        let firstRow = try #require(vm.rows.first)
        let lockedPreset = try makePreset(name: "LockedPreset")
        vm.swapPreset(for: firstRow.id, to: lockedPreset)
        #expect(vm.manuallyLockedTracks.contains(firstRow.id))

        vm.regeneratePlan()

        #expect(capturedLocked.contains(firstRow.id), "locked set must include the swapped track")
        #expect(capturedPresets[firstRow.id]?.name == "LockedPreset", "locked preset map must carry the user pick")
    }

    @Test("regeneratePlan spinner clears when new plan arrives")
    func regenerateSpinner_clearsOnPlanDelivery() async throws {
        let subject = CapturingSubject()
        let plan = try makePlan()
        let vm = PlanPreviewViewModel(
            initialPlan: plan,
            planPublisher: subject.publisher,
            onRegenerate: subject.makeOnRegenerate()
        )

        vm.regeneratePlan()
        #expect(vm.isRegenerating)

        // Deliver a new plan — simulates engine completing regeneration.
        let newPlan = try makePlan(trackCount: 3)
        subject.deliver(newPlan)
        try await Task.sleep(for: .milliseconds(20))

        #expect(!vm.isRegenerating, "spinner must clear after plan update")
        #expect(vm.rows.count == 3)
    }

    @Test("regeneratePlan while in-flight is a no-op")
    func regeneratePlan_alreadyRegenerating_isNoOp() throws {
        let subject = CapturingSubject()
        let plan = try makePlan()
        let vm = PlanPreviewViewModel(
            initialPlan: plan,
            planPublisher: subject.publisher,
            onRegenerate: subject.makeOnRegenerate()
        )

        vm.regeneratePlan()
        vm.regeneratePlan()  // second call while isRegenerating

        #expect(subject.regenerateCalls.count == 1, "second call must be dropped")
    }
}
