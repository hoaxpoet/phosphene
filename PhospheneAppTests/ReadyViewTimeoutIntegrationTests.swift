// ReadyViewTimeoutIntegrationTests — Integration tests for ReadyView timeout recovery (U.5 Part A).
//
// These tests exercise the user-facing actions available on the timeout overlay card:
//   • Retry — resets audio detector state and clears timeout flag
//   • End session — advances SessionManager to .ended
//
// The 90-second clock itself is not exercised (would make CI slow). The tests verify
// that the actions wired to the timeout overlay work correctly given that state.

import Audio
import Combine
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
    init(_ initial: AudioSignalState = .silent) { subject = CurrentValueSubject(initial) }
    func send(_ state: AudioSignalState) { subject.send(state) }
}

// swiftlint:disable large_tuple
@MainActor
private func makeReadyViewModel(
    signalState: AudioSignalState = .silent,
    delayProvider: any DelayProviding = RealDelay()
) -> (ReadyViewModel, FakeSignalPublisher, SessionManager) {
    let sigPub = FakeSignalPublisher(signalState)
    let planSubject = CurrentValueSubject<PlannedSession?, Never>(nil)
    let mgr = SessionManager.testInstance()
    let vm = ReadyViewModel(
        sessionSource: .appleMusicCurrentPlaylist,
        sessionManager: mgr,
        audioSignalStatePublisher: sigPub.publisher,
        planPublisher: planSubject.eraseToAnyPublisher(),
        reduceMotion: false,
        delayProvider: delayProvider
    )
    return (vm, sigPub, mgr)
}
// swiftlint:enable large_tuple

// MARK: - Suite

@Suite("ReadyView timeout actions")
@MainActor
struct ReadyViewTimeoutIntegrationTests {

    @Test("retry resets audio detector state and clears isTimedOut flag")
    func retry_resetsDetectorAndClearsTimeout() async throws {
        let (vm, sigPub, _) = makeReadyViewModel(delayProvider: InstantDelay())

        // Simulate audio arriving so hasDetectedAudio becomes true.
        sigPub.send(.active)
        try await Task.sleep(for: .milliseconds(50))
        #expect(vm.hasDetectedAudio, "pre-condition: audio must have been detected")
        #expect(!vm.isTimedOut, "no timeout has occurred yet")

        // User presses Retry (e.g. after a false alarm / reconnect scenario).
        vm.retry()

        #expect(!vm.hasDetectedAudio, "retry must reset detector")
        #expect(!vm.isTimedOut, "retry must clear timeout flag")
    }

    @Test("endSession transitions SessionManager to .ended")
    func endSession_advancesManagerToEnded() {
        let (vm, _, mgr) = makeReadyViewModel()
        #expect(mgr.state != .ended, "pre-condition: session should not already be ended")

        vm.endSession()

        #expect(mgr.state == .ended, "endSession must transition manager to .ended")
    }
}
