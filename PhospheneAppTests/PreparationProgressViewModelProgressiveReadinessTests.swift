// PreparationProgressViewModelProgressiveReadinessTests — 2 app tests for Increment 6.1.
//
// Test 1: canStartNow reflects the injected progressiveReadinessLevel publisher.
// Test 2: Tapping "Start now" (via vm.startNow()) invokes the onStartNow closure.

import Combine
import Session
import Testing
@testable import PhospheneApp

// MARK: - Minimal Mock (shared with existing tests, but re-declared to keep file self-contained)

@MainActor
private final class PPVMReadinessMock: PreparationProgressPublishing {
    private(set) var trackStatuses: [TrackIdentity: TrackPreparationStatus] = [:]
    private var subject = CurrentValueSubject<[TrackIdentity: TrackPreparationStatus], Never>([:])
    var trackStatusesPublisher: AnyPublisher<[TrackIdentity: TrackPreparationStatus], Never> {
        subject.eraseToAnyPublisher()
    }
    func cancelPreparation() {}
    func fire(_ status: TrackPreparationStatus, for track: TrackIdentity) {
        trackStatuses[track] = status
        subject.send(trackStatuses)
    }
}

// MARK: - Suite

@Suite("PreparationProgressViewModel — Progressive Readiness")
@MainActor
struct PreparationProgressVMReadinessTests {

    @Test func canStartNow_reflectsReadinessPublisher() async throws {
        let pub = PPVMReadinessMock()
        let readinessSubject = CurrentValueSubject<ProgressiveReadinessLevel, Never>(.preparing)
        let vm = PreparationProgressViewModel(
            publisher: pub,
            trackList: [],
            progressiveReadinessPublisher: readinessSubject.eraseToAnyPublisher()
        )

        // Initially .preparing → canStartNow should be false.
        #expect(!vm.canStartNow)

        // Advance to .readyForFirstTracks → canStartNow should become true.
        readinessSubject.send(.readyForFirstTracks)
        try await Task.sleep(nanoseconds: 10_000_000)
        #expect(vm.canStartNow)

        // Advance further to .fullyPrepared → canStartNow should stay true.
        readinessSubject.send(.fullyPrepared)
        try await Task.sleep(nanoseconds: 10_000_000)
        #expect(vm.canStartNow)
    }

    @Test func startNow_invokesOnStartNowClosure() async throws {
        let pub = PPVMReadinessMock()
        let readinessSubject = CurrentValueSubject<ProgressiveReadinessLevel, Never>(.readyForFirstTracks)
        var startNowCallCount = 0

        let vm = PreparationProgressViewModel(
            publisher: pub,
            trackList: [],
            progressiveReadinessPublisher: readinessSubject.eraseToAnyPublisher(),
            onStartNow: { startNowCallCount += 1 }
        )

        try await Task.sleep(nanoseconds: 10_000_000)
        #expect(vm.canStartNow, "Pre-condition: canStartNow must be true before tapping")

        vm.startNow()

        #expect(startNowCallCount == 1, "onStartNow closure must be called exactly once")
    }
}
