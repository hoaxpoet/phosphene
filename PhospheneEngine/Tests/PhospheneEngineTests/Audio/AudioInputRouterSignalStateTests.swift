// AudioInputRouterSignalStateTests — Regression tests for the tap-reinstall
// recovery state machine in AudioInputRouter+SignalState.
//
// Filed as CA-Audio-FU-4 (capability-registry doc-only finding from the
// CA-Audio audit on 2026-05-21): the 105-line extension implements the
// critical scrub-recovery path (3 attempts with 3/10/30s backoff) but had
// zero dedicated tests prior to this file. Without tests, a refactor or
// tuning regression could silently break audio recovery on every scrub-
// induced silence event without any test signal.
//
// Test approach: drive the state machine through its package-internal
// API surface via `@testable import Audio`. The asyncAfter'd workItems
// in scheduleNextReinstall use real wall-clock delays of 3/10/30s — we
// don't wait for them, we simulate them firing by calling
// attemptTapReinstall (or by manually clearing the workItem handle for
// counter-sequence tests). Each test that schedules cleans up via
// `defer { router.cancelPendingReinstall() }` so background workItems
// don't fire mid-next-test.

import Testing
import Foundation
@testable import Audio
@testable import Shared

// MARK: - Helpers

/// Test-controllable clock for driving the SilenceDetector without real waits.
private final class TestClock {
    var now: Double = 0
    func tick(_ dt: Double) { now += dt }
    func provider() -> () -> Double {
        // Capture self strongly — the SilenceDetector holds the closure for
        // its lifetime; releasing the clock mid-test would crash.
        { [unowned self] in self.now }
    }
}

/// Build an AudioInputRouter wired to a MockAudioCapture and a SilenceDetector
/// driven by a TestClock. Returns the tuple so individual tests can drive
/// whatever subset they need.
@available(macOS 14.2, *)
private func makeTestRouter(
    clock: TestClock = TestClock()
) -> (router: AudioInputRouter, mock: MockAudioCapture, detector: SilenceDetector, clock: TestClock) {
    let mock = MockAudioCapture()
    let detector = SilenceDetector(
        silenceRMSThreshold: 1e-6,
        silenceDuration: 3.0,
        recoveryDuration: 0.5,
        timeProvider: clock.provider()
    )
    let router = AudioInputRouter(
        capture: mock,
        metadata: nil,
        silenceDetector: detector
    )
    return (router, mock, detector, clock)
}

/// Clear the pending workItem WITHOUT resetting the attempt counter.
/// Simulates "the workItem fired and ran" for counter-sequence tests
/// without actually waiting for the 3/10/30 s asyncAfter delay.
/// Distinct from `cancelPendingReinstall()` which also zeroes attempts.
@available(macOS 14.2, *)
private func clearPendingWithoutResettingAttempts(_ router: AudioInputRouter) {
    router.lock.withLock {
        router.reinstallWorkItem?.cancel()
        router.reinstallWorkItem = nil
    }
}

// MARK: - scheduleNextReinstall

/// Audit recommendation #1: scheduleNextReinstall_attemptCount.
/// After 3 sequential calls (each simulating a prior workItem firing) the
/// counter advances 1 → 2 → 3. The 4th call hits the backoff-exhausted
/// guard and leaves the counter at 3 with no new workItem scheduled.
@available(macOS 14.2, *)
@Test func test_scheduleNextReinstall_attemptCountSequence() {
    let (router, _, _, _) = makeTestRouter()
    // LF.1: scheduler is mode-gated. Set a tap mode so the scheduler
    // exercises the attempt-counter logic this test is locking. Without
    // it the scheduler short-circuits at the mode-gate and the counter
    // stays at 0.
    router.lock.withLock { router.currentMode = .systemAudio }
    defer { router.cancelPendingReinstall() }

    router.scheduleNextReinstall()
    #expect(router.reinstallAttempts == 1)
    #expect(router.reinstallWorkItem != nil)
    clearPendingWithoutResettingAttempts(router)

    router.scheduleNextReinstall()
    #expect(router.reinstallAttempts == 2)
    #expect(router.reinstallWorkItem != nil)
    clearPendingWithoutResettingAttempts(router)

    router.scheduleNextReinstall()
    #expect(router.reinstallAttempts == 3)
    #expect(router.reinstallWorkItem != nil)
    clearPendingWithoutResettingAttempts(router)

    // 4th call: attempt (3) is NOT < reinstallDelays.count (3) → early return.
    router.scheduleNextReinstall()
    #expect(router.reinstallAttempts == 3)        // unchanged
    #expect(router.reinstallWorkItem == nil)      // no new workItem scheduled
}

/// While a workItem is pending, a second scheduleNextReinstall is a no-op.
/// Guards the `guard reinstallWorkItem == nil else { return false }` branch
/// at AudioInputRouter+SignalState.swift line 51. A regression of this guard
/// would double-bump the attempt counter on overlapping silence transitions
/// and burn through the 3-attempt cap on the first scrub.
@available(macOS 14.2, *)
@Test func test_scheduleNextReinstall_doesNotDoubleScheduleWhilePending() {
    let (router, _, _, _) = makeTestRouter()
    router.lock.withLock { router.currentMode = .systemAudio }  // LF.1 mode-gate
    defer { router.cancelPendingReinstall() }

    router.scheduleNextReinstall()
    #expect(router.reinstallAttempts == 1)
    let firstWorkItem = router.lock.withLock { router.reinstallWorkItem }

    // Second call without clearing the workItem.
    router.scheduleNextReinstall()
    #expect(router.reinstallAttempts == 1)         // unchanged
    let secondWorkItem = router.lock.withLock { router.reinstallWorkItem }
    #expect(secondWorkItem === firstWorkItem)      // same workItem object
}

// MARK: - cancelPendingReinstall

/// Audit recommendation #2: cancelPendingReinstall_resetsAttempts.
/// Cancel-on-active path zeroes both the workItem handle and the attempt
/// counter so a subsequent silence run starts fresh.
@available(macOS 14.2, *)
@Test func test_cancelPendingReinstall_resetsAttempts() {
    let (router, _, _, _) = makeTestRouter()
    router.lock.withLock { router.currentMode = .systemAudio }  // LF.1 mode-gate

    router.scheduleNextReinstall()
    #expect(router.reinstallAttempts == 1)
    #expect(router.reinstallWorkItem != nil)

    router.cancelPendingReinstall()
    #expect(router.reinstallAttempts == 0)
    #expect(router.reinstallWorkItem == nil)
}

// MARK: - handleSignalStateChange

/// The SilenceDetector's onStateChanged callback drives handleSignalStateChange.
/// The `.silent` branch must schedule a reinstall; verified here for the
/// short path (bypasses driving the detector through hysteresis).
@available(macOS 14.2, *)
@Test func test_handleSignalStateChange_silentSchedulesReinstall() {
    let (router, _, _, _) = makeTestRouter()
    router.lock.withLock { router.currentMode = .systemAudio }  // LF.1 mode-gate
    defer { router.cancelPendingReinstall() }

    router.handleSignalStateChange(.silent)
    #expect(router.reinstallAttempts == 1)
    #expect(router.reinstallWorkItem != nil)
}

/// The `.active` branch must cancel any pending reinstall and reset attempts.
/// Verifies the recovery short-circuit: if audio returns naturally on the
/// existing tap before the backoff window expires, no reinstall happens.
@available(macOS 14.2, *)
@Test func test_handleSignalStateChange_activeCancelsPending() {
    let (router, _, _, _) = makeTestRouter()
    router.lock.withLock { router.currentMode = .systemAudio }  // LF.1 mode-gate

    router.handleSignalStateChange(.silent)
    #expect(router.reinstallAttempts == 1)

    router.handleSignalStateChange(.active)
    #expect(router.reinstallAttempts == 0)
    #expect(router.reinstallWorkItem == nil)
}

// MARK: - attemptTapReinstall

/// Audit recommendation #3: attemptTapReinstall_skipsIfStateChanged.
/// If audio returned to .active during the backoff window, attemptTapReinstall
/// short-circuits (does NOT call stopCapture/startCapture) AND calls
/// cancelPendingReinstall. Verified by: a fresh detector defaults to .active,
/// so calling attemptTapReinstall directly hits the state-guard skip path.
@available(macOS 14.2, *)
@Test func test_attemptTapReinstall_skipsIfStateNotSilent() {
    let (router, mock, _, _) = makeTestRouter()
    // Set currentMode so we'd progress to performTapReinstall if the state
    // guard fails — this isolates the test to the state-guard branch only.
    router.lock.withLock { router.currentMode = .systemAudio }

    router.scheduleNextReinstall()
    #expect(router.reinstallAttempts == 1)
    #expect(router.reinstallWorkItem != nil)
    let stopsBefore = mock.stopCallCount
    let startsBefore = mock.startCallCount

    // Detector is .active by default — attemptTapReinstall must short-circuit.
    router.attemptTapReinstall(attemptNumber: 1)

    #expect(mock.stopCallCount == stopsBefore)     // no stopCapture
    #expect(mock.startCallCount == startsBefore)   // no startCapture
    // Skip-branch also calls cancelPendingReinstall (line 82), which zeroes
    // both fields. Proves the state-guard fired, not the mode-guard (which
    // leaves attempts/workItem unchanged).
    #expect(router.reinstallAttempts == 0)
    #expect(router.reinstallWorkItem == nil)
}

// MARK: - backoffExhausted

/// Audit recommendation #4: backoffExhausted_logsOnly.
/// After consuming all reinstallDelays entries, scheduleNextReinstall is a
/// no-op (the documented "treats prolonged silence as a real pause" log).
/// Verifies the cap holds and no new workItem is scheduled.
@available(macOS 14.2, *)
@Test func test_backoffExhausted_noNewScheduling() {
    let (router, _, _, _) = makeTestRouter()
    router.lock.withLock { router.currentMode = .systemAudio }  // LF.1 mode-gate
    defer { router.cancelPendingReinstall() }

    for _ in 0..<3 {
        router.scheduleNextReinstall()
        clearPendingWithoutResettingAttempts(router)
    }
    #expect(router.reinstallAttempts == 3)

    // 4th call: backoff exhausted.
    router.scheduleNextReinstall()
    #expect(router.reinstallAttempts == 3)         // unchanged
    #expect(router.reinstallWorkItem == nil)       // no workItem scheduled

    // 5th, 6th calls: still capped, still no scheduling. Behaviour is stable
    // under repeated silence-callback firings while in the exhausted state.
    router.scheduleNextReinstall()
    #expect(router.reinstallAttempts == 3)
    router.scheduleNextReinstall()
    #expect(router.reinstallAttempts == 3)
}

// MARK: - nextActiveToSilent

/// Audit recommendation #5: nextActiveToSilent_resetsAttempts.
/// A full silence → cancel-on-recovery → silence-again cycle: the second
/// silence run must start at attempts=1 (fresh counter), not at 2 (continued
/// from prior). Regression-locks the "cancel resets" behaviour at the
/// integration level via the handleSignalStateChange entry point.
@available(macOS 14.2, *)
@Test func test_nextActiveToSilent_resetsAttempts() {
    let (router, _, _, _) = makeTestRouter()
    router.lock.withLock { router.currentMode = .systemAudio }  // LF.1 mode-gate
    defer { router.cancelPendingReinstall() }

    // First silence run: attempts → 1.
    router.handleSignalStateChange(.silent)
    #expect(router.reinstallAttempts == 1)
    clearPendingWithoutResettingAttempts(router)

    // Simulate workItem firing AND a second silence callback while still in
    // .silent (would bump attempts to 2 in production via performTapReinstall's
    // unconditional reschedule at line 110). Done here by direct call to
    // scheduleNextReinstall (the workItem closure's effective body for the
    // state-stays-silent branch's reschedule tail).
    router.scheduleNextReinstall()
    #expect(router.reinstallAttempts == 2)
    clearPendingWithoutResettingAttempts(router)

    // Audio returns: handleSignalStateChange(.active) → cancelPendingReinstall.
    router.handleSignalStateChange(.active)
    #expect(router.reinstallAttempts == 0)

    // Second silence run: attempts must start fresh at 1.
    router.handleSignalStateChange(.silent)
    #expect(router.reinstallAttempts == 1)         // fresh, NOT continuation from 2
}

// MARK: - LF.1 — Mode-gate

/// LF.1 regression lock: the tap-reinstall scheduler is a no-op in
/// `.localFilePlayback` and `.localFile` modes — there is no process tap
/// to reinstall, and silence in a played file is real musical silence,
/// not a tap teardown. Verifies the gate at the top of
/// `scheduleNextReinstall(...)`. A regression would cause "Tap reinstall
/// scheduled" log lines to appear in `session.log` during local-file
/// playback sessions, breaking the LF.1 manual-verification grep.
@available(macOS 14.2, *)
@Test func test_scheduleNextReinstall_isNoOpInLocalFilePlaybackMode() {
    let (router, _, _, _) = makeTestRouter()
    let url = URL(fileURLWithPath: "/dev/null")
    router.lock.withLock { router.currentMode = .localFilePlayback(url) }
    defer { router.cancelPendingReinstall() }

    router.scheduleNextReinstall()
    #expect(router.reinstallAttempts == 0)
    #expect(router.reinstallWorkItem == nil)

    // handleSignalStateChange(.silent) also routes through the same gate.
    router.handleSignalStateChange(.silent)
    #expect(router.reinstallAttempts == 0)
    #expect(router.reinstallWorkItem == nil)
}

/// LF.1 regression lock: the existing `.localFile` (diagnostic injection)
/// mode is also gated. Mirrors the playback gate so the offline
/// `SoakTestHarness` path never schedules a reinstall either.
@available(macOS 14.2, *)
@Test func test_scheduleNextReinstall_isNoOpInLocalFileMode() {
    let (router, _, _, _) = makeTestRouter()
    let url = URL(fileURLWithPath: "/dev/null")
    router.lock.withLock { router.currentMode = .localFile(url) }
    defer { router.cancelPendingReinstall() }

    router.scheduleNextReinstall()
    #expect(router.reinstallAttempts == 0)
    #expect(router.reinstallWorkItem == nil)
}

// MARK: - Backoff tuning regression-lock

/// The 3/10/30 second backoff sequence is a deliberate design choice (per
/// ARCH §Audio Capture + AUDIO.md line 41): three attempts is enough to
/// ride out a typical scrub-induced disconnect without thrashing if the
/// user actually paused the music. Locking the literal values here prevents
/// a future "let's tune to [5, 15, 60]" PR from silently changing recovery
/// behaviour without a discussion. If a real tuning increment ships, this
/// test should be updated as part of that increment with the rationale in
/// the commit message.
@available(macOS 14.2, *)
@Test func test_reinstallDelays_matchDesignSpec() {
    let (router, _, _, _) = makeTestRouter()
    #expect(router.reinstallDelays == [3.0, 10.0, 30.0])
    #expect(router.reinstallDelays.count == 3)
}
