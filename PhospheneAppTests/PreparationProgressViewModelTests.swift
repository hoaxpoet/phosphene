// PreparationProgressViewModelTests — Unit tests for PreparationProgressViewModel.
// Uses a local MockPreparationProgressPublisher to drive status transitions.

import Combine
import Session
import Testing
@testable import PhospheneApp

// MARK: - Local Mock

@MainActor
private final class MockPublisher: PreparationProgressPublishing {
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

    func setAll(_ statuses: [TrackIdentity: TrackPreparationStatus]) {
        trackStatuses = statuses
        subject.send(trackStatuses)
    }
}

// MARK: - Helpers

private func makeTrack(_ title: String) -> TrackIdentity {
    TrackIdentity(title: title, artist: "Test Artist")
}

// MARK: - Suite

@Suite("PreparationProgressViewModel")
@MainActor
struct PreparationProgressViewModelTests {

    // MARK: - Row Order

    @Test func init_buildsRowsInTrackListOrder_notDictOrder() async throws {
        let tracks = ["Charlie", "Alpha", "Bravo"].map { makeTrack($0) }
        let pub = MockPublisher()
        pub.setAll(Dictionary(uniqueKeysWithValues: tracks.map { ($0, TrackPreparationStatus.queued) }))

        let vm = PreparationProgressViewModel(
            publisher: pub,
            trackList: tracks,
            progressiveReadinessPublisher: Just(.preparing).eraseToAnyPublisher()
        )
        try await Task.sleep(nanoseconds: 10_000_000)

        #expect(vm.rows.map(\.title) == ["Charlie", "Alpha", "Bravo"],
                "Rows must follow trackList order, not dictionary insertion order")
    }

    // MARK: - Status Updates

    @Test func publisherEmission_updatesRows() async throws {
        let track = makeTrack("So What")
        let pub = MockPublisher()
        let vm = PreparationProgressViewModel(
            publisher: pub,
            trackList: [track],
            progressiveReadinessPublisher: Just(.preparing).eraseToAnyPublisher()
        )

        pub.fire(.queued, for: track)
        try await Task.sleep(nanoseconds: 10_000_000)
        #expect(vm.rows.first?.status == .queued)

        pub.fire(.resolving, for: track)
        try await Task.sleep(nanoseconds: 10_000_000)
        #expect(vm.rows.first?.status == .resolving)

        pub.fire(.ready, for: track)
        try await Task.sleep(nanoseconds: 10_000_000)
        #expect(vm.rows.first?.status == .ready)
    }

    // MARK: - Aggregate Progress

    @Test func aggregateProgress_readyAndPartialCount_outOfTotal() async throws {
        let tracks = (0..<5).map { makeTrack("T\($0)") }
        let pub = MockPublisher()
        let vm = PreparationProgressViewModel(
            publisher: pub,
            trackList: tracks,
            progressiveReadinessPublisher: Just(.preparing).eraseToAnyPublisher()
        )

        pub.fire(.ready, for: tracks[0])
        pub.fire(.ready, for: tracks[1])
        pub.fire(.partial(reason: "Stems unavailable"), for: tracks[2])
        // tracks[3], tracks[4] stay queued

        var statuses = pub.trackStatuses
        for track in tracks where statuses[track] == nil { statuses[track] = .queued }
        pub.setAll(statuses)
        try await Task.sleep(nanoseconds: 20_000_000)

        // ready=2, partial=1 → 3/5 = 0.6
        #expect(abs(vm.aggregateProgress - 0.6) < 0.01,
                "Expected 0.6, got \(vm.aggregateProgress)")
        #expect(vm.counts.ready == 2)
        #expect(vm.counts.partial == 1)
        #expect(vm.counts.failed == 0)
        #expect(vm.counts.total == 5)
    }

    // MARK: - canStartNow (replaces FeatureFlags gate, Increment 6.1)

    @Test func canStartNow_falseWhenReadinessIsPreparing() async throws {
        let track = makeTrack("InProgress")
        let pub = MockPublisher()
        let readinessSubject = CurrentValueSubject<ProgressiveReadinessLevel, Never>(.preparing)
        let vm = PreparationProgressViewModel(
            publisher: pub,
            trackList: [track],
            progressiveReadinessPublisher: readinessSubject.eraseToAnyPublisher()
        )

        pub.fire(.ready, for: track)
        try await Task.sleep(nanoseconds: 10_000_000)

        // Still .preparing → CTA stays hidden.
        #expect(!vm.canStartNow)
    }

    // MARK: - Cancel

    @Test func cancel_callsPublisherCancelPreparation() async throws {
        let pub = MockPublisher()
        let vm = PreparationProgressViewModel(
            publisher: pub,
            trackList: [],
            progressiveReadinessPublisher: Just(.preparing).eraseToAnyPublisher()
        )

        vm.cancel()

        #expect(pub.cancelCallCount == 1)
    }

    // MARK: - Stress

    @Test func flakyNetwork_rapidStatusChanges_noCrash() async throws {
        let tracks = (0..<5).map { makeTrack("S\($0)") }
        let pub = MockPublisher()
        let vm = PreparationProgressViewModel(
            publisher: pub,
            trackList: tracks,
            progressiveReadinessPublisher: Just(.preparing).eraseToAnyPublisher()
        )

        // Fire 100 rapid updates across all tracks — must not crash.
        let statuses: [TrackPreparationStatus] = [
            .queued, .resolving, .downloading(progress: 0.5),
            .analyzing(stage: .stemSeparation), .ready
        ]
        for i in 0..<100 {
            let track = tracks[i % tracks.count]
            let status = statuses[i % statuses.count]
            pub.fire(status, for: track)
        }

        try await Task.sleep(nanoseconds: 20_000_000)

        // No assertion needed — the test passes if no crash/assertion failure occurred.
        #expect(vm.rows.count == tracks.count)
    }
}
