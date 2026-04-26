// FirstAudioDetectorTests — Unit tests for FirstAudioDetector (Increment U.5 Part A).

import Audio
import Combine
import Testing
@testable import PhospheneApp

// MARK: - Helpers

private final class StatePublisher {
    private let subject: CurrentValueSubject<AudioSignalState, Never>
    var publisher: AnyPublisher<AudioSignalState, Never> { subject.eraseToAnyPublisher() }

    init(_ initial: AudioSignalState = .silent) {
        subject = CurrentValueSubject(initial)
    }

    func send(_ state: AudioSignalState) { subject.send(state) }
}

// MARK: - Suite

@Suite("FirstAudioDetector")
@MainActor
struct FirstAudioDetectorTests {

    @Test func init_hasDetectedAudio_isFalse() {
        let pub = StatePublisher(.silent)
        let detector = FirstAudioDetector(audioSignalStatePublisher: pub.publisher)
        #expect(!detector.hasDetectedAudio)
    }

    @Test func activeSustained250ms_firesDetection() async throws {
        let pub = StatePublisher(.silent)
        // InstantDelay makes the 250ms confirmation timer fire immediately — the
        // 50ms sleep is well above zero and lets all actor context-switches settle.
        let detector = FirstAudioDetector(
            audioSignalStatePublisher: pub.publisher,
            delayProvider: InstantDelay()
        )
        pub.send(.active)
        try await Task.sleep(for: .milliseconds(50))
        #expect(detector.hasDetectedAudio)
    }

    @Test func activeBrief_doesNotFire() async throws {
        let pub = StatePublisher(.silent)
        let detector = FirstAudioDetector(audioSignalStatePublisher: pub.publisher)
        pub.send(.active)
        try await Task.sleep(for: .milliseconds(100))
        pub.send(.silent)
        try await Task.sleep(for: .milliseconds(300))
        #expect(!detector.hasDetectedAudio)
    }

    @Test func suspectTransition_doesNotReset() async throws {
        let pub = StatePublisher(.silent)
        let detector = FirstAudioDetector(audioSignalStatePublisher: pub.publisher)
        pub.send(.active)
        try await Task.sleep(for: .milliseconds(100))
        pub.send(.suspect)
        try await Task.sleep(for: .milliseconds(50))
        pub.send(.active)
        try await Task.sleep(for: .milliseconds(200))
        // Total time in non-cancelled state ≥ 250 ms: should fire
        #expect(detector.hasDetectedAudio)
    }

    @Test func coldStartPath_silentToActiveViaRecovering_fires() async throws {
        let pub = StatePublisher(.recovering)
        let detector = FirstAudioDetector(
            audioSignalStatePublisher: pub.publisher,
            delayProvider: InstantDelay()
        )
        pub.send(.active)
        try await Task.sleep(for: .milliseconds(50))
        #expect(detector.hasDetectedAudio)
    }

    @Test func reset_clearsDetection_allowsRefire() async throws {
        let pub = StatePublisher(.silent)
        let detector = FirstAudioDetector(
            audioSignalStatePublisher: pub.publisher,
            delayProvider: InstantDelay()
        )
        pub.send(.active)
        try await Task.sleep(for: .milliseconds(50))
        #expect(detector.hasDetectedAudio)

        detector.reset()
        #expect(!detector.hasDetectedAudio)

        pub.send(.silent)
        pub.send(.active)
        try await Task.sleep(for: .milliseconds(50))
        #expect(detector.hasDetectedAudio)
    }

    @Test func recoveringState_cancelsTimer() async throws {
        let pub = StatePublisher(.silent)
        let detector = FirstAudioDetector(audioSignalStatePublisher: pub.publisher)
        pub.send(.active)
        try await Task.sleep(for: .milliseconds(100))
        pub.send(.recovering) // audio dropped to silent, now recovering
        try await Task.sleep(for: .milliseconds(300))
        #expect(!detector.hasDetectedAudio)
    }
}
