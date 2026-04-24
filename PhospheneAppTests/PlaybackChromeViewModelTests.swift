// PlaybackChromeViewModelTests — Unit tests for PlaybackChromeViewModel (U.6 Part A).

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

private final class FakeSignalPublisher {
    private let subject: CurrentValueSubject<AudioSignalState, Never>
    var publisher: AnyPublisher<AudioSignalState, Never> { subject.eraseToAnyPublisher() }
    init(_ initial: AudioSignalState = .active) { subject = CurrentValueSubject(initial) }
    func send(_ state: AudioSignalState) { subject.send(state) }
}

private final class FakeTrackPublisher {
    private let subject = CurrentValueSubject<TrackMetadata?, Never>(nil)
    var publisher: AnyPublisher<TrackMetadata?, Never> { subject.eraseToAnyPublisher() }
    func send(_ meta: TrackMetadata?) { subject.send(meta) }
}

private final class FakePresetPublisher {
    private let subject = CurrentValueSubject<String?, Never>(nil)
    var publisher: AnyPublisher<String?, Never> { subject.eraseToAnyPublisher() }
    func send(_ name: String?) { subject.send(name) }
}

private final class FakePlanPublisher2 {
    private let subject = CurrentValueSubject<PlannedSession?, Never>(nil)
    var publisher: AnyPublisher<PlannedSession?, Never> { subject.eraseToAnyPublisher() }
    func send(_ plan: PlannedSession?) { subject.send(plan) }
}

// swiftlint:disable large_tuple
@MainActor
private func makeVM(
    signal: AudioSignalState = .active,
    delay: any DelayProviding = InstantDelay()
) -> (PlaybackChromeViewModel, FakeSignalPublisher, FakeTrackPublisher, FakePresetPublisher, FakePlanPublisher2) {
    let sig = FakeSignalPublisher(signal)
    let track = FakeTrackPublisher()
    let preset = FakePresetPublisher()
    let plan = FakePlanPublisher2()
    let vm = PlaybackChromeViewModel(
        audioSignalStatePublisher: sig.publisher,
        currentTrackPublisher: track.publisher,
        currentPresetNamePublisher: preset.publisher,
        livePlanPublisher: plan.publisher,
        delay: delay
    )
    return (vm, sig, track, preset, plan)
}
// swiftlint:enable large_tuple

// MARK: - Suite

@Suite("PlaybackChromeViewModel")
@MainActor
struct PlaybackChromeViewModelTests {

    @Test func init_overlayVisible_isTrue() {
        let (vm, _, _, _, _) = makeVM()
        #expect(vm.overlayVisible)
    }

    @Test func onActivity_resetsHideTimer_andKeepsOverlayVisible() async throws {
        let (vm, _, _, _, _) = makeVM(delay: InstantDelay())
        // After instant hide fires
        try await Task.sleep(for: .milliseconds(20))
        // Activity should reset and show overlay
        vm.onActivity()
        #expect(vm.overlayVisible)
    }

    @Test func overlayAutoHides_afterDelay() async throws {
        let (vm, _, _, _, _) = makeVM(delay: InstantDelay())
        // InstantDelay fires synchronously; give the Task a chance to run
        try await Task.sleep(for: .milliseconds(20))
        #expect(!vm.overlayVisible)
    }

    @Test func sustainedSilence_showsListeningBadge() async throws {
        let (vm, sig, _, _, _) = makeVM()
        sig.send(.silent)
        try await Task.sleep(for: .milliseconds(20))
        #expect(vm.showListeningBadge)
    }

    @Test func transientSilence_suspect_doesNotShowBadge() async throws {
        let (vm, sig, _, _, _) = makeVM()
        sig.send(.suspect)
        try await Task.sleep(for: .milliseconds(20))
        #expect(!vm.showListeningBadge)
    }

    @Test func signalRecovery_hidesListeningBadge() async throws {
        let (vm, sig, _, _, _) = makeVM()
        sig.send(.silent)
        try await Task.sleep(for: .milliseconds(20))
        #expect(vm.showListeningBadge)
        sig.send(.active)
        try await Task.sleep(for: .milliseconds(20))
        #expect(!vm.showListeningBadge)
    }

    @Test func reactiveMode_sessionProgress_collapses() async throws {
        let (vm, _, _, _, planPub) = makeVM()
        planPub.send(nil)
        try await Task.sleep(for: .milliseconds(20))
        #expect(vm.sessionProgress.isReactiveMode)
        #expect(vm.orchestratorState == .reactive)
    }

    @Test func orchestratorStateIndicator_planned_withPlan() async throws {
        let (vm, _, _, _, planPub) = makeVM()
        let plan = try makePlan()
        planPub.send(plan)
        try await Task.sleep(for: .milliseconds(20))
        #expect(vm.orchestratorState == .planned)
        #expect(!vm.sessionProgress.isReactiveMode)
        #expect(vm.sessionProgress.totalTracks == 1)
    }
}

// MARK: - Helpers

private func makePlan() throws -> PlannedSession {
    let json = """
    {"name":"TestPreset","family":"abstract","motion_intensity":0.5,
     "color_temperature_range":[0.3,0.7],"fatigue_risk":"medium",
     "complexity_cost":{"tier1":1.0,"tier2":1.0},
     "transition_affordances":["crossfade"]}
    """
    let preset = try JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
    return try DefaultSessionPlanner().plan(
        tracks: [(TrackIdentity(title: "T", artist: "A", duration: 180), .empty)],
        catalog: [preset],
        deviceTier: .tier1
    )
}
