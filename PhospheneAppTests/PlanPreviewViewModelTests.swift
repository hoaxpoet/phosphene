// PlanPreviewViewModelTests — Unit tests for PlanPreviewViewModel (Increment U.5 Part B).

import Combine
import Foundation
import Orchestrator
import Presets
import Session
import Shared
import Testing
@testable import PhospheneApp

// MARK: - Helpers

private func makePlan(trackCount: Int = 2, duration: TimeInterval = 180) throws -> PlannedSession {
    let planner = DefaultSessionPlanner()
    let catalog = [try makeTestPreset(name: "PresetA"), try makeTestPreset(name: "PresetB")]
    let tracks: [(TrackIdentity, TrackProfile)] = (0..<trackCount).map { i in
        (TrackIdentity(title: "Track \(i + 1)", artist: "Artist", duration: duration),
         TrackProfile.empty)
    }
    return try planner.plan(tracks: tracks, catalog: catalog, deviceTier: .tier1)
}

private func makeTestPreset(name: String = "TestPreset") throws -> PresetDescriptor {
    let json = """
    {"name":"\(name)","family":"abstract","motion_intensity":0.5,
     "color_temperature_range":[0.3,0.7],"fatigue_risk":"medium",
     "complexity_cost":{"tier1":1.0,"tier2":1.0},
     "transition_affordances":["crossfade"]}
    """
    return try JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
}

private class FakePlanSubject {
    private let subject = CurrentValueSubject<PlannedSession?, Never>(nil)
    var publisher: AnyPublisher<PlannedSession?, Never> { subject.eraseToAnyPublisher() }
    func send(_ plan: PlannedSession?) { subject.send(plan) }
}

// MARK: - Suite

@Suite("PlanPreviewViewModel")
@MainActor
struct PlanPreviewViewModelTests {

    @Test func init_buildsRowsFromPlannedSession() throws {
        let plan = try makePlan(trackCount: 3)
        let fakeSubject = FakePlanSubject()
        let vm = PlanPreviewViewModel(
            initialPlan: plan,
            planPublisher: fakeSubject.publisher,
            onRegenerate: { _, _ in }
        )
        #expect(vm.rows.count == 3)
    }

    @Test func rowCount_matchesPlannedTracks() throws {
        let plan = try makePlan(trackCount: 5)
        let fakeSubject = FakePlanSubject()
        let vm = PlanPreviewViewModel(
            initialPlan: plan,
            planPublisher: fakeSubject.publisher,
            onRegenerate: { _, _ in }
        )
        #expect(vm.rows.count == 5)
    }

    @Test func rowData_durationFromPlannedStartEnd_notTrackIdentityDuration() throws {
        let plan = try makePlan(trackCount: 1, duration: 200)
        let fakeSubject = FakePlanSubject()
        let vm = PlanPreviewViewModel(
            initialPlan: plan,
            planPublisher: fakeSubject.publisher,
            onRegenerate: { _, _ in }
        )
        let row = try #require(vm.rows.first)
        // Duration comes from plannedEndTime - plannedStartTime (per spec).
        #expect(row.duration >= 199)
    }

    @Test func incomingTransition_firstTrack_isNil() throws {
        let plan = try makePlan(trackCount: 2)
        let fakeSubject = FakePlanSubject()
        let vm = PlanPreviewViewModel(
            initialPlan: plan,
            planPublisher: fakeSubject.publisher,
            onRegenerate: { _, _ in }
        )
        let firstRow = try #require(vm.rows.first)
        #expect(firstRow.incomingTransition == nil, "First track must have no incoming transition")
    }

    @Test func incomingTransition_subsequentTrack_isPresent() throws {
        let plan = try makePlan(trackCount: 2)
        let fakeSubject = FakePlanSubject()
        let vm = PlanPreviewViewModel(
            initialPlan: plan,
            planPublisher: fakeSubject.publisher,
            onRegenerate: { _, _ in }
        )
        #expect(vm.rows.count >= 2)
        let secondRow = vm.rows[1]
        #expect(secondRow.incomingTransition != nil, "Second track must have an incoming transition")
    }

    @Test func publisherEmission_updatesRows() async throws {
        let fakeSubject = FakePlanSubject()
        let vm = PlanPreviewViewModel(
            initialPlan: nil,
            planPublisher: fakeSubject.publisher,
            onRegenerate: { _, _ in }
        )
        #expect(vm.rows.isEmpty)
        let plan = try makePlan(trackCount: 4)
        fakeSubject.send(plan)
        try await Task.sleep(for: .milliseconds(10))
        #expect(vm.rows.count == 4)
    }

    @Test func swapPreset_updatesRowAndAddsLock() throws {
        let plan = try makePlan(trackCount: 2)
        let fakeSubject = FakePlanSubject()
        let vm = PlanPreviewViewModel(
            initialPlan: plan,
            planPublisher: fakeSubject.publisher,
            onRegenerate: { _, _ in }
        )
        let firstRow = try #require(vm.rows.first)
        let newPreset = try makeTestPreset(name: "SwappedPreset")
        vm.swapPreset(for: firstRow.id, to: newPreset)

        let updatedRow = try #require(vm.rows.first)
        #expect(updatedRow.presetName == "SwappedPreset")
        #expect(updatedRow.isLocked)
        #expect(vm.manuallyLockedTracks.contains(firstRow.id))
    }

    @Test func resetLock_removesFromManuallyLocked() throws {
        let plan = try makePlan(trackCount: 1)
        let fakeSubject = FakePlanSubject()
        let vm = PlanPreviewViewModel(
            initialPlan: plan,
            planPublisher: fakeSubject.publisher,
            onRegenerate: { _, _ in }
        )
        let row = try #require(vm.rows.first)
        let newPreset = try makeTestPreset(name: "Locked")
        vm.swapPreset(for: row.id, to: newPreset)
        #expect(vm.manuallyLockedTracks.contains(row.id))

        vm.resetLock(for: row.id)
        #expect(!vm.manuallyLockedTracks.contains(row.id))
    }
}
