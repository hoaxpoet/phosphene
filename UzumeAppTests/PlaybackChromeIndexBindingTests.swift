// PlaybackChromeIndexBindingTests — QR.4 / D-091. Validates that
// PlaybackChromeViewModel's session-progress index binds to the
// `currentTrackIndexPublisher` from VisualizerEngine instead of the
// pre-QR.4 lowercased title+artist string match. Pre-fix the match silently
// failed for covers, remasters, and encoding-different versions.

import Audio
import Combine
import Foundation
import Orchestrator
import Presets
import Session
import Shared
import Testing
@testable import PhospheneApp

@Suite("PlaybackChromeIndexBinding")
@MainActor
struct PlaybackChromeIndexBindingTests {

    // MARK: - Fixture publishers

    private final class FakeSignal {
        let subject = CurrentValueSubject<AudioSignalState, Never>(.active)
        var publisher: AnyPublisher<AudioSignalState, Never> { subject.eraseToAnyPublisher() }
    }

    private final class FakeTrack {
        let subject = CurrentValueSubject<TrackMetadata?, Never>(nil)
        var publisher: AnyPublisher<TrackMetadata?, Never> { subject.eraseToAnyPublisher() }
        func send(_ meta: TrackMetadata?) { subject.send(meta) }
    }

    private final class FakeIndex {
        let subject = CurrentValueSubject<Int?, Never>(nil)
        var publisher: AnyPublisher<Int?, Never> { subject.eraseToAnyPublisher() }
        func send(_ idx: Int?) { subject.send(idx) }
    }

    private final class FakePreset {
        let subject = CurrentValueSubject<String?, Never>(nil)
        var publisher: AnyPublisher<String?, Never> { subject.eraseToAnyPublisher() }
    }

    private final class FakePlan {
        let subject = CurrentValueSubject<PlannedSession?, Never>(nil)
        var publisher: AnyPublisher<PlannedSession?, Never> { subject.eraseToAnyPublisher() }
        func send(_ plan: PlannedSession?) { subject.send(plan) }
    }

    // MARK: - Helpers

    private func buildPlan(trackCount: Int) throws -> PlannedSession {
        let json = """
        {"name":"TestPreset","family":"hypnotic","motion_intensity":0.5,
         "color_temperature_range":[0.3,0.7],"fatigue_risk":"medium",
         "complexity_cost":{"tier1":1.0,"tier2":1.0},
         "transition_affordances":["crossfade"]}
        """
        let preset = try JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
        let tracks = (0..<trackCount).map {
            (TrackIdentity(title: "Track \($0)", artist: "Artist \($0)", duration: 180), TrackProfile.empty)
        }
        return try DefaultSessionPlanner().plan(
            tracks: tracks,
            catalog: [preset],
            deviceTier: .tier1
        )
    }

    private func makeVM(
        track: FakeTrack,
        index: FakeIndex,
        plan: FakePlan
    ) -> PlaybackChromeViewModel {
        PlaybackChromeViewModel(
            audioSignalStatePublisher: FakeSignal().publisher,
            currentTrackPublisher: track.publisher,
            currentTrackIndexPublisher: index.publisher,
            currentPresetNamePublisher: FakePreset().publisher,
            livePlanPublisher: plan.publisher,
            delay: InstantDelay()
        )
    }

    private func tick(ms: UInt64 = 30) async throws {
        try await Task.sleep(for: .milliseconds(ms))
    }

    // MARK: - Tests

    @Test("currentIndex updates when the index publisher emits 2")
    func test_indexPublisherEmits2_progressUpdates() async throws {
        let track = FakeTrack()
        let index = FakeIndex()
        let planPub = FakePlan()
        let viewModel = makeVM(track: track, index: index, plan: planPub)
        let session = try buildPlan(trackCount: 5)
        planPub.send(session)
        try await tick()

        index.send(2)
        try await tick()

        #expect(viewModel.sessionProgress.currentIndex == 2,
                "sessionProgress.currentIndex must reflect the published index")
        #expect(viewModel.sessionProgress.totalTracks == 5)
        #expect(!viewModel.sessionProgress.isReactiveMode)
    }

    @Test("nil index — track not in plan — sets currentIndex to -1, not stale value")
    func test_nilIndex_meansTrackNotInPlan() async throws {
        let track = FakeTrack()
        let index = FakeIndex()
        let planPub = FakePlan()
        let viewModel = makeVM(track: track, index: index, plan: planPub)
        let session = try buildPlan(trackCount: 3)
        planPub.send(session)
        try await tick()

        index.send(1)
        try await tick()
        #expect(viewModel.sessionProgress.currentIndex == 1)

        index.send(nil)
        try await tick()
        #expect(viewModel.sessionProgress.currentIndex == -1,
                "nil published index must set currentIndex to -1 (sentinel), not retain the previous value")
    }

    @Test("no string-match path: title differing in case/whitespace from plan does not affect index")
    func test_titleCaseMismatch_doesNotChangeIndex() async throws {
        // The whole point of QR.4 — the view model must NEVER infer the index
        // from `currentTrack` title comparisons.
        let track = FakeTrack()
        let index = FakeIndex()
        let planPub = FakePlan()
        let viewModel = makeVM(track: track, index: index, plan: planPub)
        let session = try buildPlan(trackCount: 3)
        planPub.send(session)
        try await tick()

        // Engine publishes index=0 (canonical match in the plan).
        index.send(0)
        // Streaming metadata arrives with a title that does NOT match plan.tracks[0]
        // (e.g. cover version, remaster suffix, different encoding mojibake).
        track.send(TrackMetadata(
            title: "TRACK 0 — REMASTERED",
            artist: "Artist 0",
            duration: 180
        ))
        try await tick()

        #expect(viewModel.sessionProgress.currentIndex == 0,
                "index must follow the published value; the view model must not re-derive it from title match")
    }

    @Test("nil plan keeps reactive-mode display regardless of index")
    func test_nilPlan_isReactiveMode() async throws {
        let track = FakeTrack()
        let index = FakeIndex()
        let planPub = FakePlan()
        let viewModel = makeVM(track: track, index: index, plan: planPub)

        planPub.send(nil)
        try await tick()
        index.send(0)  // shouldn't matter — no plan
        try await tick()

        #expect(viewModel.sessionProgress.isReactiveMode)
        #expect(viewModel.sessionProgress.totalTracks == 0)
        #expect(viewModel.sessionProgress.currentIndex == -1)
    }
}
