// PreparationCancelIntegrationTests — Integration tests for the cancel flow
// through PreparationProgressViewModel → PreparationProgressPublishing.
// Verifies that cancel() routes to the publisher and that the confirmation
// dialog gate works correctly.

import Combine
import Session
import Testing
@testable import PhospheneApp

// MARK: - Suite

@Suite("PreparationCancelIntegration")
@MainActor
struct PreparationCancelIntegrationTests {

    // MARK: - Helpers

    private func makeTrack(_ title: String) -> TrackIdentity {
        TrackIdentity(title: title, artist: "Test Artist")
    }

    private func makePublisher() -> MockCancelPublisher {
        MockCancelPublisher()
    }

    // MARK: - Tests

    @Test func cancel_noReadyTracks_skipsConfirmationDialog() async throws {
        let track = makeTrack("Queued Track")
        let pub = makePublisher()
        let vm = PreparationProgressViewModel(
            publisher: pub,
            trackList: [track],
            progressiveReadinessPublisher: Just(.preparing).eraseToAnyPublisher()
        )

        // Fire queued — no ready tracks yet.
        pub.fire(.queued, for: track)
        try await Task.sleep(nanoseconds: 10_000_000)

        vm.requestCancel()

        // No .ready tracks → confirmation dialog should NOT appear.
        #expect(!vm.showCancelConfirmation)
    }

    @Test func cancel_withReadyTrack_showsConfirmationDialog() async throws {
        let track = makeTrack("Ready Track")
        let pub = makePublisher()
        let vm = PreparationProgressViewModel(
            publisher: pub,
            trackList: [track],
            progressiveReadinessPublisher: Just(.preparing).eraseToAnyPublisher()
        )

        pub.fire(.ready, for: track)
        try await Task.sleep(nanoseconds: 10_000_000)

        vm.requestCancel()

        // One .ready track → confirmation required.
        #expect(vm.showCancelConfirmation)
    }

    @Test func cancel_forwardsToCancelPreparation() async throws {
        let pub = makePublisher()
        let vm = PreparationProgressViewModel(
            publisher: pub,
            trackList: [],
            progressiveReadinessPublisher: Just(.preparing).eraseToAnyPublisher()
        )

        vm.cancel()

        #expect(pub.cancelCallCount == 1)
    }
}

// MARK: - Local Mock

@MainActor
private final class MockCancelPublisher: PreparationProgressPublishing {
    private(set) var trackStatuses: [TrackIdentity: TrackPreparationStatus] = [:]
    private var subject = CurrentValueSubject<[TrackIdentity: TrackPreparationStatus], Never>([:])
    private(set) var cancelCallCount = 0

    var trackStatusesPublisher: AnyPublisher<[TrackIdentity: TrackPreparationStatus], Never> {
        subject.eraseToAnyPublisher()
    }

    func cancelPreparation() { cancelCallCount += 1 }

    func fire(_ status: TrackPreparationStatus, for track: TrackIdentity) {
        trackStatuses[track] = status
        subject.send(trackStatuses)
    }
}
