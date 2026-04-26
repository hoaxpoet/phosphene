// NetworkRecoveryCoordinator — Resumes network-failed tracks when connectivity returns
// during the .preparing session state (Increment 7.2, D-061).
//
// ReachabilityMonitor (U.7 Part B) already debounces network state at 1s and publishes
// isOnline. PreparationErrorViewModel consumes it for copy changes. This coordinator
// adds the *retry-driving* purpose: when online flips false→true while state==.preparing,
// it calls SessionManager.resumeFailedNetworkTracks() so downloads that failed during
// the outage get another attempt.
//
// Guards:
//   · 2s additional debounce on top of ReachabilityMonitor's 1s (= 3s total). Briefly
//     bouncing networks don't trigger immediate re-attempts that may fail again. D-061(e).
//   · Hard cap of 3 recovery attempts per session. After 3, the user's existing "Retry"
//     button (PreparationFailureView) provides a hard-restart path. D-061(e).
//   · Only fires when SessionManager.state == .preparing. Recovery is preparation-only.

import Combine
import Foundation
import Session
import os.log

private let logger = Logger(subsystem: "com.phosphene.app", category: "NetworkRecoveryCoordinator")

// MARK: - NetworkRecoveryCoordinator

/// Wires `ReachabilityMonitor` to `SessionManager.resumeFailedNetworkTracks()` during preparation.
///
/// Owned by `PreparationProgressView` as `@State`. Takes an injectable `ReachabilityPublishing`
/// so tests can drive it without `NWPathMonitor`. D-061(d,e).
@MainActor
final class NetworkRecoveryCoordinator {

    // MARK: - Constants

    /// Additional debounce on top of `ReachabilityMonitor`'s 1s debounce.
    /// Composed: 1s (reachability) + 2s (here) = 3s effective recovery delay. D-061(e).
    static let recoveryDebounceSecs: TimeInterval = 2

    /// Maximum number of automatic recovery attempts per preparation session.
    /// After this, the user must use the manual "Retry" button. D-061(e).
    static let maxRecoveryAttempts: Int = 3

    // MARK: - State

    /// Number of automatic recovery attempts made in the current preparation session.
    private(set) var recoveryAttemptCount: Int = 0

    /// Latest session state tracked from the injected publisher.
    private var latestSessionState: SessionState = .idle

    // MARK: - Dependencies

    private weak var sessionManager: SessionManager?
    private let reachability: any ReachabilityPublishing

    private var cancellables = Set<AnyCancellable>()
    private var debounceTask: Task<Void, Never>?

    // MARK: - Init

    init(
        sessionManager: SessionManager,
        reachability: any ReachabilityPublishing,
        sessionStatePublisher: AnyPublisher<SessionState, Never>
    ) {
        self.sessionManager = sessionManager
        self.reachability = reachability

        sessionStatePublisher
            .sink { [weak self] in self?.latestSessionState = $0 }
            .store(in: &cancellables)

        reachability.isOnlinePublisher
            .removeDuplicates()
            .sink { [weak self] isOnline in
                guard isOnline else { return }   // only act on false→true transitions
                self?.handleNetworkRestored()
            }
            .store(in: &cancellables)
    }

    // MARK: - Session Reset

    /// Reset the attempt counter when a new preparation session begins.
    func resetForNewSession() {
        recoveryAttemptCount = 0
        debounceTask?.cancel()
        debounceTask = nil
    }

    // MARK: - Private

    private func handleNetworkRestored() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.recoveryDebounceSecs))
            guard !Task.isCancelled, let self else { return }
            await self.attemptRecovery()
        }
    }

    private func attemptRecovery() async {
        guard let sessionManager else { return }
        guard latestSessionState == .preparing else {
            logger.debug("NetworkRecoveryCoordinator: network restored but not in .preparing — skipping")
            return
        }
        guard recoveryAttemptCount < Self.maxRecoveryAttempts else {
            let cap = Self.maxRecoveryAttempts
            logger.info("NetworkRecoveryCoordinator: recovery cap (\(cap, privacy: .public)) reached — user must use manual Retry")
            return
        }

        recoveryAttemptCount += 1
        let attempt = recoveryAttemptCount
        let cap = Self.maxRecoveryAttempts
        // swiftlint:disable:next line_length
        logger.info("NetworkRecoveryCoordinator: network restored — resuming failed tracks (attempt \(attempt, privacy: .public)/\(cap, privacy: .public))")

        await sessionManager.resumeFailedNetworkTracks()
    }
}
