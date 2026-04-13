// SilenceDetectorTests — Unit tests for the DRM silence detection state machine.
// All tests use an injected time provider to avoid real sleeping.

import Testing
import Foundation
@testable import Audio

// MARK: - Helpers

/// Build a SilenceDetector with a controllable clock.
private func makeDetector(
    threshold: Float = 1e-6,
    silenceDuration: TimeInterval = 3.0,
    recoveryDuration: TimeInterval = 0.5,
    clock: @escaping () -> Double
) -> SilenceDetector {
    SilenceDetector(
        silenceRMSThreshold: threshold,
        silenceDuration: silenceDuration,
        recoveryDuration: recoveryDuration,
        timeProvider: clock
    )
}

// MARK: - Initial State

@Test func test_init_stateIsActive() {
    var t = 0.0
    let detector = makeDetector(clock: { t })
    #expect(detector.state == .active)
}

// MARK: - Normal Audio

@Test func test_normalAudio_stateRemainsActive() {
    var t = 0.0
    let detector = makeDetector(clock: { t })

    // Feed non-zero RMS across 5 simulated seconds.
    for i in 0..<100 {
        t = Double(i) * 0.05  // steps of 50ms
        detector.update(rms: 0.1)
    }
    #expect(detector.state == .active)
}

// MARK: - Silence Transitions

@Test func test_silence_stateTransitionsToSuspect() {
    var t = 0.0
    let detector = makeDetector(silenceDuration: 3.0, clock: { t })

    // First silent frame starts the clock.
    detector.update(rms: 0)
    #expect(detector.state == .active)

    // Advance to exactly suspectDuration (= silenceDuration / 2 = 1.5s).
    t = 1.5
    detector.update(rms: 0)
    #expect(detector.state == .suspect)
}

@Test func test_silence_stateTransitionsToSilent() {
    var t = 0.0
    let detector = makeDetector(silenceDuration: 3.0, clock: { t })

    // Enter suspect.
    detector.update(rms: 0)  // t=0, silenceStart set
    t = 1.5
    detector.update(rms: 0)  // → .suspect
    #expect(detector.state == .suspect)

    // Advance to total silenceDuration.
    t = 3.0
    detector.update(rms: 0)  // elapsed = 3.0 ≥ 3.0 → .silent
    #expect(detector.state == .silent)
}

// MARK: - Recovery Transitions

@Test func test_signalReturn_stateTransitionsToRecovering() {
    var t = 0.0
    let detector = makeDetector(silenceDuration: 3.0, recoveryDuration: 0.5, clock: { t })

    // Drive to .silent.
    detector.update(rms: 0); t = 1.5; detector.update(rms: 0)
    t = 3.0; detector.update(rms: 0)
    #expect(detector.state == .silent)

    // One non-silent frame → immediate .recovering.
    t = 3.1
    detector.update(rms: 0.5)
    #expect(detector.state == .recovering)
}

@Test func test_signalReturn_confirmationTransitionsToActive() {
    var t = 0.0
    let detector = makeDetector(silenceDuration: 3.0, recoveryDuration: 0.5, clock: { t })

    // Drive to .recovering.
    detector.update(rms: 0); t = 1.5; detector.update(rms: 0)
    t = 3.0; detector.update(rms: 0)
    t = 3.1; detector.update(rms: 0.5)  // → .recovering, signalReturnTime = 3.1
    #expect(detector.state == .recovering)

    // Advance by recoveryDuration.
    t = 3.6  // elapsed from signalReturn = 0.5 ≥ recoveryDuration
    detector.update(rms: 0.5)
    #expect(detector.state == .active)
}

// MARK: - Brief Dropout

@Test func test_briefDropout_doesNotTriggerSuspect() {
    var t = 0.0
    let detector = makeDetector(silenceDuration: 3.0, clock: { t })

    // Silence starts at t=0.
    detector.update(rms: 0)
    #expect(detector.state == .active)

    // Signal returns at 0.5s — well under suspectDuration (1.5s).
    t = 0.5
    detector.update(rms: 0.5)
    #expect(detector.state == .active)

    // Continued signal for another 5s — still active.
    for i in 1..<100 {
        t = 0.5 + Double(i) * 0.05
        detector.update(rms: 0.5)
    }
    #expect(detector.state == .active)
}

// MARK: - Callback

@Test func test_callback_firesOnStateChange() {
    var t = 0.0
    let detector = makeDetector(silenceDuration: 3.0, recoveryDuration: 0.5, clock: { t })

    var transitions: [AudioSignalState] = []
    detector.onStateChanged = { transitions.append($0) }

    // Drive: active → suspect → silent → recovering → active.
    detector.update(rms: 0)          // t=0, start silence
    t = 1.5
    detector.update(rms: 0)          // → .suspect
    t = 3.0
    detector.update(rms: 0)          // → .silent
    t = 3.1
    detector.update(rms: 0.5)        // → .recovering
    t = 3.6
    detector.update(rms: 0.5)        // → .active

    #expect(transitions == [.suspect, .silent, .recovering, .active])
}

@Test func test_callback_doesNotFireOnNonTransitionFrames() {
    var t = 0.0
    let detector = makeDetector(silenceDuration: 3.0, clock: { t })

    var callCount = 0
    detector.onStateChanged = { _ in callCount += 1 }

    // Feed 50 normal frames — no state change should fire.
    for i in 0..<50 {
        t = Double(i) * 0.02
        detector.update(rms: 0.3)
    }
    #expect(callCount == 0)
}

// MARK: - Configurable Thresholds

@Test func test_thresholds_configurable() {
    var t = 0.0
    // Higher threshold (0.05) — moderate audio counts as silent.
    // Shorter silence window (1.0s) — silence confirmed faster.
    // Shorter recovery (0.2s) — recovery confirmed faster.
    let detector = makeDetector(
        threshold: 0.05,
        silenceDuration: 1.0,
        recoveryDuration: 0.2,
        clock: { t }
    )

    // suspectDuration = 0.5s. Advance to 0.5s with sub-threshold RMS.
    detector.update(rms: 0.04)       // t=0, below threshold → silence start
    t = 0.5
    detector.update(rms: 0.04)       // elapsed 0.5s ≥ suspectDuration (0.5s) → .suspect
    #expect(detector.state == .suspect)

    // Advance to 1.0s total → .silent.
    t = 1.0
    detector.update(rms: 0.04)
    #expect(detector.state == .silent)

    // Signal returns → .recovering.
    t = 1.1
    detector.update(rms: 0.5)
    #expect(detector.state == .recovering)

    // Advance by 0.21s past signal return → .active (avoids FP edge cases at exact boundary).
    t = 1.31
    detector.update(rms: 0.5)
    #expect(detector.state == .active)
}
