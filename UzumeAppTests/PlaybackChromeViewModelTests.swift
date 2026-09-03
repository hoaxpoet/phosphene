// PlaybackChromeViewModelTests — Unit tests for PlaybackChromeViewModel (U.6 Part A).

import Audio
import Combine
import Foundation
import Orchestrator
import Presets
import Session
import Shared
import Testing
@testable import UzumeApp

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

/// A delay that never elapses: the quiet timer is armed but never fires.
private struct NeverDelay: DelayProviding {
    func sleep(seconds: Double) async throws { try await Task.sleep(for: .seconds(3600)) }
}

/// Records every requested sleep, then yields like `InstantDelay`.
private final class RecordingDelay: DelayProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var log: [Double] = []
    var requested: [Double] { lock.withLock { log } }
    func sleep(seconds: Double) async throws {
        lock.withLock { log.append(seconds) }
        await Task.yield()
    }
}

// swiftlint:disable large_tuple
@MainActor
private func makeVM(
    signal: AudioSignalState = .active,
    firstShowDelay: Double = 0,
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
        firstShowDelay: firstShowDelay,
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

    // CLEAN.1.4 (BUG-033): the VM must deallocate once nothing strong-references
    // it (its `deinit` cancels `hideTask`). Before the fix, two
    // `assign(to:on: self)` subscriptions (Subscribers.Assign retains its target)
    // stored on `self.cancellables` closed a retain cycle → the VM leaked every
    // session and `deinit` never ran. The `sink { [weak self] }` fix breaks it.
    // Red pre-fix (weakVM != nil), green post-fix.
    @Test func deallocates_noRetainCycle() {
        weak var weakVM: PlaybackChromeViewModel?
        do {
            let (vm, _, _, _, _) = makeVM()
            weakVM = vm
            #expect(weakVM != nil)
        }
        #expect(weakVM == nil, "PlaybackChromeViewModel leaked — assign(to:on:self) retain cycle regressed")
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
        // InstantDelay makes the 3s timer effectively instant (Task.yield).
        // 1000ms (was 300ms) absorbs @MainActor scheduling under parallel test
        // load — observed overlayVisible == true at the 300ms mark on a 328-test
        // parallel app run. The U.11 precedent (CLAUDE.md) carries 2-3× headroom
        // over the worst-observed delay.
        try await Task.sleep(for: .milliseconds(1000))
        #expect(!vm.overlayVisible)
        // DS.6 (D-241): inactivity lands on quiet — End session stays — never hidden.
        #expect(vm.visibility == .quiet)
    }

    // MARK: - DS.6 visibility states

    @Test func spaceToggle_fromFull_hides_andBack() {
        let (vm, _, _, _, _) = makeVM(delay: NeverDelay())
        vm.toggleOverlay()
        #expect(vm.visibility == .hidden)
        #expect(!vm.overlayVisible)
        vm.toggleOverlay()
        #expect(vm.visibility == .full)
    }

    @Test func onActivity_fromQuiet_restoresFull() async throws {
        let (vm, _, _, _, _) = makeVM(delay: InstantDelay())
        try await Task.sleep(for: .milliseconds(1000))
        #expect(vm.visibility == .quiet)
        vm.onActivity()
        #expect(vm.visibility == .full)
    }

    @Test func trackChange_restoresFullChrome() async throws {
        let (vm, _, trackPub, _, _) = makeVM(delay: NeverDelay())
        trackPub.send(TrackMetadata(title: "First", artist: "A"))
        try await Task.sleep(for: .milliseconds(20))
        vm.toggleOverlay()
        #expect(vm.visibility == .hidden)
        trackPub.send(TrackMetadata(title: "Second", artist: "A"))
        try await Task.sleep(for: .milliseconds(20))
        #expect(vm.visibility == .full, "a track change is activity (UX_SPEC §7.2)")
    }

    @Test func firstTrack_doesNotResetTheArrivalTimer() async throws {
        let recorder = RecordingDelay()
        let (vm, _, trackPub, _, _) = makeVM(firstShowDelay: 3.82, delay: recorder)
        trackPub.send(TrackMetadata(title: "First", artist: "A"))
        try await Task.sleep(for: .milliseconds(50))
        _ = vm
        #expect(recorder.requested.count == 1, "the first track must not re-arm the timer")
    }

    @Test func firstShow_waitsForTheArrival_thenThreeSeconds() async throws {
        let recorder = RecordingDelay()
        let (vm, _, _, _, _) = makeVM(firstShowDelay: 3.82, delay: recorder)
        try await Task.sleep(for: .milliseconds(50))
        #expect(recorder.requested.first == 3.82 + PlaybackChromeViewModel.inactivityDelay)
        vm.onActivity()
        try await Task.sleep(for: .milliseconds(50))
        #expect(recorder.requested.last == PlaybackChromeViewModel.inactivityDelay)
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
    }

    @Test func plannedSession_sessionProgress_carriesThePlan() async throws {
        let (vm, _, _, _, planPub) = makeVM()
        let plan = try makePlan()
        planPub.send(plan)
        try await Task.sleep(for: .milliseconds(20))
        #expect(!vm.sessionProgress.isReactiveMode)
        #expect(vm.sessionProgress.totalTracks == 1)
    }
}

// MARK: - Helpers

private func makePlan() throws -> PlannedSession {
    let json = """
    {"name":"TestPreset","family":"hypnotic","motion_intensity":0.5,
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
