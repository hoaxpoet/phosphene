// ReadyViewModelTests — Unit tests for ReadyViewModel (Increment U.5 Part A).

import Audio
import Combine
import Foundation
import Orchestrator
import Presets
import Session
import Shared
import Testing
@testable import PhospheneApp

// MARK: - Helpers

private final class FakeStatePublisher {
    private let subject: CurrentValueSubject<AudioSignalState, Never>
    var publisher: AnyPublisher<AudioSignalState, Never> { subject.eraseToAnyPublisher() }
    init(_ initial: AudioSignalState = .silent) { subject = CurrentValueSubject(initial) }
    func send(_ state: AudioSignalState) { subject.send(state) }
}

private final class FakePlanPublisher {
    private let subject = CurrentValueSubject<PlannedSession?, Never>(nil)
    var publisher: AnyPublisher<PlannedSession?, Never> { subject.eraseToAnyPublisher() }
    func send(_ plan: PlannedSession?) { subject.send(plan) }
}

/// Build a minimal 1-track plan for test assertions.
private func makeTestPlan(trackCount: Int = 1, duration: TimeInterval = 200) throws -> PlannedSession {
    let planner = DefaultSessionPlanner()
    let identity = TrackIdentity(title: "Test Track", artist: "Artist", duration: duration)
    let profile = TrackProfile.empty
    let preset = try makeTestPreset()
    return try planner.plan(
        tracks: Array(repeating: (identity, profile), count: trackCount),
        catalog: [preset],
        deviceTier: .tier1
    )
}

private func makeTestPreset() throws -> PresetDescriptor {
    let json = """
    {"name":"TestPreset","family":"abstract","motion_intensity":0.5,
     "color_temperature_range":[0.3,0.7],"fatigue_risk":"medium",
     "complexity_cost":{"tier1":1.0,"tier2":1.0},
     "transition_affordances":["crossfade"]}
    """
    return try JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
}

// swiftlint:disable large_tuple
@MainActor
private func makeViewModel(
    source: PlaylistSource? = .appleMusicCurrentPlaylist,
    signalState: AudioSignalState = .silent,
    reduceMotion: Bool = false
) -> (ReadyViewModel, FakeStatePublisher, FakePlanPublisher, SessionManager) {
    let sigPub = FakeStatePublisher(signalState)
    let planPub = FakePlanPublisher()
    let mgr = SessionManager.testInstance()
    let vm = ReadyViewModel(
        sessionSource: source,
        sessionManager: mgr,
        audioSignalStatePublisher: sigPub.publisher,
        planPublisher: planPub.publisher,
        reduceMotion: reduceMotion
    )
    return (vm, sigPub, planPub, mgr)
}
// swiftlint:enable large_tuple

// MARK: - Suite

@Suite("ReadyViewModel")
@MainActor
struct ReadyViewModelTests {

    @Test func init_appleMusicSource_setsSourceName() {
        let (vm, _, _, _) = makeViewModel(source: .appleMusicCurrentPlaylist)
        #expect(vm.sourceName == "Apple Music")
    }

    @Test func init_spotifySource_setsSourceName() {
        let (vm, _, _, _) = makeViewModel(source: .spotifyCurrentQueue)
        #expect(vm.sourceName == "Spotify")
    }

    @Test func init_nilSource_fallsBackToGenericCopy() {
        let (vm, _, _, _) = makeViewModel(source: nil)
        #expect(vm.sourceName == "your music app")
    }

    @Test func planPublisher_updatesTrackCountAndDuration() async throws {
        let (vm, _, planPub, _) = makeViewModel()
        #expect(vm.trackCount == 0)
        let plan = try makeTestPlan(trackCount: 1, duration: 200)
        planPub.send(plan)
        try await Task.sleep(for: .milliseconds(10))
        #expect(vm.trackCount == 1)
        #expect(vm.estimatedDuration >= 199)
    }

    @Test func firstAudioDetected_emitsAdvanceSignal() async throws {
        let (vm, sigPub, _, _) = makeViewModel()
        var advanced = false
        let cancellable = vm.shouldAdvanceToPlaying.sink { advanced = true }
        sigPub.send(.active)
        try await Task.sleep(for: .milliseconds(600))
        #expect(advanced)
        _ = cancellable
    }

    @Test func audioDetectedBeforeTimeout_hasDetectedAudioFlips() async throws {
        let (vm, sigPub, _, _) = makeViewModel()
        sigPub.send(.active)
        try await Task.sleep(for: .milliseconds(600))
        #expect(vm.hasDetectedAudio)
        #expect(!vm.isTimedOut)
    }

    @Test func initialState_isTimedOut_isFalse() {
        let (vm, _, _, _) = makeViewModel()
        #expect(!vm.isTimedOut)
    }

    @Test func retry_resetsDetectorAndClearsTimeout() async throws {
        let (vm, sigPub, _, _) = makeViewModel()
        sigPub.send(.active)
        try await Task.sleep(for: .milliseconds(600))
        #expect(vm.hasDetectedAudio)

        vm.retry()
        #expect(!vm.hasDetectedAudio)
        #expect(!vm.isTimedOut)
    }

    @Test func endSession_callsSessionManagerEndSession() {
        let (vm, _, _, mgr) = makeViewModel()
        #expect(mgr.state != .ended)
        vm.endSession()
        #expect(mgr.state == .ended)
    }

    @Test func reduceMotion_propagatesInitialValue() {
        let (vm, _, _, _) = makeViewModel(reduceMotion: true)
        #expect(vm.reduceMotion)
    }
}
