// NetworkRecoveryCoordinatorTests — Verifies the network-recovery retry contract (Increment 7.2, D-061).
//
// Tests verify D-061(d,e):
//  1. false→true while .preparing → recovery attempt counted once.
//  2. false→true while .idle → recovery NOT triggered (state guard).
//  3. false→true→false→true within debounce window → only one attempt (idempotent).
//  4. After maxRecoveryAttempts reached → additional online events do not count further.
//  5. resetForNewSession() resets counter and cancels pending debounce.

import Combine
import Foundation
import Session
import Testing
@testable import PhospheneApp

// MARK: - MockReachabilityForNRC

@MainActor
final class MockReachabilityForNRC: ReachabilityPublishing {
    private let subject = CurrentValueSubject<Bool, Never>(true)

    var isOnline: Bool { subject.value }
    var isOnlinePublisher: AnyPublisher<Bool, Never> { subject.eraseToAnyPublisher() }

    func setOnline(_ value: Bool) {
        subject.send(value)
    }
}

// MARK: - NetworkRecoveryCoordinatorTests

@Suite("NetworkRecoveryCoordinator")
@MainActor
struct NetworkRecoveryCoordinatorTests {

    // MARK: - Helpers

    private struct Fixture {
        let sessionManager: SessionManager
        let reachability: MockReachabilityForNRC
        let sessionStateSubject: CurrentValueSubject<SessionState, Never>
        let coordinator: NetworkRecoveryCoordinator
    }

    private func makeFixture(initialState: SessionState = .idle) -> Fixture {
        let sessionManager = SessionManager.testInstance()
        let reachability = MockReachabilityForNRC()
        let stateSubject = CurrentValueSubject<SessionState, Never>(initialState)
        let coordinator = NetworkRecoveryCoordinator(
            sessionManager: sessionManager,
            reachability: reachability,
            sessionStatePublisher: stateSubject.eraseToAnyPublisher()
        )
        return Fixture(
            sessionManager: sessionManager,
            reachability: reachability,
            sessionStateSubject: stateSubject,
            coordinator: coordinator
        )
    }

    // MARK: - Tests

    @Test("initial state: no recovery attempts counted")
    func test_initialState_noAttempts() {
        let fix = makeFixture()
        #expect(fix.coordinator.recoveryAttemptCount == 0)
    }

    @Test("online while not preparing: state guard blocks recovery")
    func test_online_notPreparing_noAttempt() async {
        let fix = makeFixture(initialState: .idle)

        // Go offline then back online while state == .idle.
        fix.reachability.setOnline(false)
        fix.reachability.setOnline(true)

        // Allow debounce to settle — we yield to give the coordinator's Task a chance to run
        // through the guard (which should reject the attempt).
        try? await Task.sleep(for: .milliseconds(50))

        #expect(fix.coordinator.recoveryAttemptCount == 0)
    }

    @Test("online while preparing: attempt counted")
    func test_online_preparing_countsAttempt() async {
        let fix = makeFixture(initialState: .preparing)

        // Go offline then back online.
        fix.reachability.setOnline(false)
        fix.reachability.setOnline(true)

        // Wait past the debounce window so the Task runs.
        let debouncePlus = NetworkRecoveryCoordinator.recoveryDebounceSecs + 0.1
        try? await Task.sleep(for: .seconds(debouncePlus))

        #expect(fix.coordinator.recoveryAttemptCount == 1)
    }

    @Test("rapid online→offline→online within debounce: single attempt only")
    func test_rapidToggle_debounce_singleAttempt() async {
        let fix = makeFixture(initialState: .preparing)

        // First online event.
        fix.reachability.setOnline(false)
        fix.reachability.setOnline(true)

        // Immediately go offline and back online before debounce fires (< 2s window).
        fix.reachability.setOnline(false)
        fix.reachability.setOnline(true)

        // Wait past ONE full debounce window.
        let debouncePlus = NetworkRecoveryCoordinator.recoveryDebounceSecs + 0.1
        try? await Task.sleep(for: .seconds(debouncePlus))

        // Second online event cancelled the first Task — only one attempt should have fired.
        #expect(fix.coordinator.recoveryAttemptCount == 1)
    }

    @Test("recovery cap: attempts stop after maxRecoveryAttempts")
    func test_recoveryCap_stopsAt3() async {
        let fix = makeFixture(initialState: .preparing)
        let debounce = NetworkRecoveryCoordinator.recoveryDebounceSecs + 0.1

        // Drive 4 online recovery cycles, each waiting for the full debounce.
        for _ in 0..<4 {
            fix.reachability.setOnline(false)
            fix.reachability.setOnline(true)
            try? await Task.sleep(for: .seconds(debounce))
        }

        // Should be capped at maxRecoveryAttempts, not 4.
        #expect(fix.coordinator.recoveryAttemptCount == NetworkRecoveryCoordinator.maxRecoveryAttempts)
    }

    @Test("resetForNewSession resets counter and state guard works after reset")
    func test_resetForNewSession_resetsCount() async {
        let fix = makeFixture(initialState: .preparing)
        let debounce = NetworkRecoveryCoordinator.recoveryDebounceSecs + 0.1

        // Exhaust the cap.
        for _ in 0..<NetworkRecoveryCoordinator.maxRecoveryAttempts {
            fix.reachability.setOnline(false)
            fix.reachability.setOnline(true)
            try? await Task.sleep(for: .seconds(debounce))
        }
        #expect(fix.coordinator.recoveryAttemptCount == NetworkRecoveryCoordinator.maxRecoveryAttempts)

        // Reset for a new session.
        fix.coordinator.resetForNewSession()
        #expect(fix.coordinator.recoveryAttemptCount == 0)

        // After reset, a new online event should count again.
        fix.reachability.setOnline(false)
        fix.reachability.setOnline(true)
        try? await Task.sleep(for: .seconds(debounce))

        #expect(fix.coordinator.recoveryAttemptCount == 1)
    }

    @Test("resetForNewSession cancels in-flight debounce task")
    func test_resetForNewSession_cancelsPendingTask() async {
        let fix = makeFixture(initialState: .preparing)

        // Kick off a debounce (but don't wait for it to complete).
        fix.reachability.setOnline(false)
        fix.reachability.setOnline(true)

        // Cancel immediately before the 2s debounce elapses.
        fix.coordinator.resetForNewSession()

        // Wait past the original debounce window.
        let debouncePlus = NetworkRecoveryCoordinator.recoveryDebounceSecs + 0.1
        try? await Task.sleep(for: .seconds(debouncePlus))

        // The cancelled task should not have incremented the count.
        #expect(fix.coordinator.recoveryAttemptCount == 0)
    }
}
