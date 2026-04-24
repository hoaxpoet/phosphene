// PreparationErrorViewModelTests — Unit tests for PreparationErrorViewModel.
//
// Tests:
//   1. Initial state is .normal.
//   2. Going offline (after downloads start) → .fullScreen(.networkOffline).
//   3. Coming back online clears offline state.
//   4. All tracks failing → .fullScreen(.allTracksFailedToPrepare).
//   5. Rate-limit signal → .banner(.previewRateLimited).
//   6. Going offline while all queued does not show error.
//   7. Offline takes priority over an in-progress download.

import Combine
import Session
import Shared
import Testing
@testable import PhospheneApp

// MARK: - Suite

@MainActor
@Suite("PreparationErrorViewModel")
struct PreparationErrorViewModelTests {

    // MARK: - Helpers

    private func makeTrack(_ title: String) -> TrackIdentity {
        TrackIdentity(title: title, artist: "Test Artist")
    }

    private typealias StatusSubject = CurrentValueSubject<[TrackIdentity: TrackPreparationStatus], Never>

    private struct SUTBundle {
        let sut: PreparationErrorViewModel
        let subject: StatusSubject
        let reachability: StubReachabilityMonitor
    }

    private func makeSUT(
        statuses: [TrackIdentity: TrackPreparationStatus] = [:],
        totalTrackCount: Int = 2,
        isOnline: Bool = true
    ) -> SUTBundle {
        let subject = StatusSubject(statuses)
        let reachability = StubReachabilityMonitor(initialValue: isOnline)
        let sut = PreparationErrorViewModel(
            statusPublisher: subject.eraseToAnyPublisher(),
            reachability: reachability,
            totalTrackCount: totalTrackCount
        )
        return SUTBundle(sut: sut, subject: subject, reachability: reachability)
    }

    // MARK: - Tests

    @Test("initial state is .normal")
    func test_initialState_isNormal() {
        let bundle = makeSUT()
        #expect(bundle.sut.presentationState == .normal)
    }

    @Test("going offline after downloads start → fullScreen networkOffline")
    func test_offlineAfterStart_showsFullScreen() async {
        let track = makeTrack("Track 1")
        let bundle = makeSUT(statuses: [track: .downloading(progress: 0.3)], totalTrackCount: 1)
        bundle.subject.send([track: .downloading(progress: 0.3)])
        await Task.yield()

        bundle.reachability.isOnline = false
        await Task.yield()

        #expect(bundle.sut.presentationState == .fullScreen(.networkOffline))
    }

    @Test("going offline while all tracks queued does not show error")
    func test_offlineWhileQueued_noError() async {
        let track = makeTrack("Track 1")
        let bundle = makeSUT(statuses: [track: .queued], totalTrackCount: 1)
        bundle.reachability.isOnline = false
        await Task.yield()
        // All tracks still queued — no download started, so no offline error.
        #expect(bundle.sut.presentationState == .normal)
    }

    @Test("coming back online clears fullScreen networkOffline")
    func test_backOnline_clearsOfflineError() async {
        let track = makeTrack("Track 1")
        let bundle = makeSUT(statuses: [track: .downloading(progress: 0.5)], totalTrackCount: 1)
        bundle.subject.send([track: .downloading(progress: 0.5)])
        await Task.yield()

        bundle.reachability.isOnline = false
        await Task.yield()
        #expect(bundle.sut.presentationState == .fullScreen(.networkOffline))

        bundle.reachability.isOnline = true
        await Task.yield()
        #expect(bundle.sut.presentationState == .normal)
    }

    @Test("all tracks failed → fullScreen allTracksFailedToPrepare")
    func test_allTracksFailed_showsFullScreen() async {
        let track1 = makeTrack("Track 1")
        let track2 = makeTrack("Track 2")
        let bundle = makeSUT(totalTrackCount: 2)
        bundle.subject.send([
            track1: .failed(reason: "Not found"),
            track2: .failed(reason: "Not found")
        ])
        await Task.yield()
        #expect(bundle.sut.presentationState == .fullScreen(.allTracksFailedToPrepare))
    }

    @Test("rate-limit signal → banner previewRateLimited")
    func test_rateLimitSignal_showsBanner() async {
        let track = makeTrack("Track 1")
        let bundle = makeSUT(totalTrackCount: 1)
        bundle.subject.send([track: .partial(reason: "rate limit exceeded")])
        await Task.yield()
        #expect(bundle.sut.presentationState == .banner(.previewRateLimited))
    }

    @Test("offline takes priority over downloading in-progress")
    func test_offlinePriority_overInProgress() async {
        let track = makeTrack("Track 1")
        let bundle = makeSUT(statuses: [track: .downloading(progress: 0.2)], totalTrackCount: 1)
        bundle.subject.send([track: .downloading(progress: 0.2)])
        await Task.yield()

        bundle.reachability.isOnline = false
        await Task.yield()
        #expect(bundle.sut.presentationState == .fullScreen(.networkOffline))
    }

    @Test("single ready track prevents allTracksFailedToPrepare")
    func test_oneReadyTrack_notAllFailed() async {
        let track1 = makeTrack("Track 1")
        let track2 = makeTrack("Track 2")
        let bundle = makeSUT(totalTrackCount: 2)
        bundle.subject.send([
            track1: .ready,
            track2: .failed(reason: "Not found")
        ])
        await Task.yield()
        // One track is ready — not all failed.
        #expect(bundle.sut.presentationState == .normal)
    }
}
