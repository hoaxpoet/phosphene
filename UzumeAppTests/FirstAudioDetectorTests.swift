// FirstAudioDetectorTests — Unit tests for FirstAudioDetector (Increment U.5 Part A).
//
// Determinism note (hardening pass, 2026-06-01): these tests previously
// constructed the detector with the default `RealDelay` and waited a fixed
// 600 ms wall-clock margin over the 250 ms confirmation timer. Under the
// ~380-test parallel app run, @MainActor scheduling contention routinely
// delayed the timer continuation past that margin → intermittent failures
// (FirstAudioDetectorTests was a recurring flake). The detector already
// exposes an injectable `delayProvider`; we now drive a `ManualDelay` so the
// test controls EXACTLY when the "250 ms" elapses relative to state changes.
// No wall-clock dependence remains — the flake class is eliminated, not
// merely made less probable.

import Audio
import Combine
import Foundation
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

/// Controllable `DelayProviding` double. `sleep(seconds:)` suspends until the
/// test calls `releaseAll()` — letting a test deterministically order the
/// confirmation timer's completion against state changes (cancel-before-fire
/// for negative cases, fire for positive cases). No wall-clock.
private final class ManualDelay: DelayProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [CheckedContinuation<Void, Never>] = []

    func sleep(seconds: Double) async throws {
        await withCheckedContinuation { cont in
            lock.withLock { pending.append(cont) }
        }
    }

    /// Number of confirmation timers currently suspended in `sleep`.
    var pendingCount: Int { lock.withLock { pending.count } }

    /// Resume every suspended `sleep` — simulates the confirmation interval
    /// elapsing. Cancelled tasks resume then bail at the detector's
    /// `Task.isCancelled` guard; live tasks resume and set the flag.
    func releaseAll() {
        let conts = lock.withLock { defer { pending = [] }; return pending }
        conts.forEach { $0.resume() }
    }
}

// MARK: - Suite

@Suite("FirstAudioDetector")
@MainActor
struct FirstAudioDetectorTests {

    /// Yield until the confirmation Task has reached `delay.sleep` (so a
    /// subsequent state change cancels a *running* timer, and `releaseAll`
    /// actually has something to release). Bounded to avoid hangs on a bug.
    private func awaitConfirmationArmed(_ delay: ManualDelay) async {
        var yields = 0
        while delay.pendingCount == 0 && yields < 1000 { await Task.yield(); yields += 1 }
    }

    /// Yield until `condition` holds (or the bound trips). Used after
    /// `releaseAll()` to let the @MainActor task publish `hasDetectedAudio`.
    private func awaitCondition(_ condition: @autoclosure () -> Bool) async {
        var yields = 0
        while !condition() && yields < 1000 { await Task.yield(); yields += 1 }
    }

    /// Let any cancelled/post-release task drain a few hops (for negative
    /// assertions where the flag must stay false).
    private func drain() async {
        for _ in 0..<8 { await Task.yield() }
    }

    @Test func init_hasDetectedAudio_isFalse() {
        let pub = StatePublisher(.silent)
        let detector = FirstAudioDetector(audioSignalStatePublisher: pub.publisher)
        #expect(!detector.hasDetectedAudio)
    }

    @Test func activeSustained_firesDetection() async {
        let pub = StatePublisher(.silent)
        let delay = ManualDelay()
        let detector = FirstAudioDetector(
            audioSignalStatePublisher: pub.publisher, delayProvider: delay
        )
        pub.send(.active)
        await awaitConfirmationArmed(delay)
        delay.releaseAll()                      // 250 ms "elapses"
        await awaitCondition(detector.hasDetectedAudio)
        #expect(detector.hasDetectedAudio)
    }

    @Test func activeBrief_doesNotFire() async {
        let pub = StatePublisher(.silent)
        let delay = ManualDelay()
        let detector = FirstAudioDetector(
            audioSignalStatePublisher: pub.publisher, delayProvider: delay
        )
        pub.send(.active)
        await awaitConfirmationArmed(delay)
        pub.send(.silent)                       // drop before the interval elapses → cancels
        delay.releaseAll()
        await drain()
        #expect(!detector.hasDetectedAudio)
    }

    @Test func suspectTransition_doesNotReset() async {
        let pub = StatePublisher(.silent)
        let delay = ManualDelay()
        let detector = FirstAudioDetector(
            audioSignalStatePublisher: pub.publisher, delayProvider: delay
        )
        pub.send(.active)
        await awaitConfirmationArmed(delay)
        pub.send(.suspect)                      // tolerated — timer keeps running
        pub.send(.active)                       // already running — no restart
        delay.releaseAll()
        await awaitCondition(detector.hasDetectedAudio)
        #expect(detector.hasDetectedAudio)
    }

    @Test func coldStartPath_silentToActiveViaRecovering_fires() async {
        let pub = StatePublisher(.recovering)
        let delay = ManualDelay()
        let detector = FirstAudioDetector(
            audioSignalStatePublisher: pub.publisher, delayProvider: delay
        )
        pub.send(.active)
        await awaitConfirmationArmed(delay)
        delay.releaseAll()
        await awaitCondition(detector.hasDetectedAudio)
        #expect(detector.hasDetectedAudio)
    }

    @Test func reset_clearsDetection_allowsRefire() async {
        let pub = StatePublisher(.silent)
        let delay = ManualDelay()
        let detector = FirstAudioDetector(
            audioSignalStatePublisher: pub.publisher, delayProvider: delay
        )
        pub.send(.active)
        await awaitConfirmationArmed(delay)
        delay.releaseAll()
        await awaitCondition(detector.hasDetectedAudio)
        #expect(detector.hasDetectedAudio)

        detector.reset()
        #expect(!detector.hasDetectedAudio)

        pub.send(.silent)
        pub.send(.active)
        await awaitConfirmationArmed(delay)
        delay.releaseAll()
        await awaitCondition(detector.hasDetectedAudio)
        #expect(detector.hasDetectedAudio)
    }

    @Test func recoveringState_cancelsTimer() async {
        let pub = StatePublisher(.silent)
        let delay = ManualDelay()
        let detector = FirstAudioDetector(
            audioSignalStatePublisher: pub.publisher, delayProvider: delay
        )
        pub.send(.active)
        await awaitConfirmationArmed(delay)
        pub.send(.recovering)                   // audio dropped → cancels
        delay.releaseAll()
        await drain()
        #expect(!detector.hasDetectedAudio)
    }
}
