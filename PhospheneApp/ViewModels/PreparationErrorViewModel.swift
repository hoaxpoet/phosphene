// PreparationErrorViewModel — Determines the error presentation mode for PreparationProgressView.
//
// Subscribes to SessionPreparer's per-track status publisher and ReachabilityMonitor.
// Publishes a PresentationState that drives whether PreparationProgressView shows:
//   - .normal     → standard progress-row list
//   - .banner(error) → TopBannerView above the list
//   - .fullScreen(error) → PreparationFailureView replacing the list
//
// Decision rules (highest priority wins):
//   1. Network offline → .fullScreen(.networkOffline)
//   2. All tracks failed → .fullScreen(.allTracksFailedToPrepare)
//   3. previewRateLimited received → .banner(.previewRateLimited)
//   4. First track >90 s still not ready → .banner(.preparationSlowOnFirstTrack)
//   5. Total elapsed >120 s without progressive-ready → .banner(.preparationTotalTimeout)
//   6. Otherwise → .normal

import Combine
import Foundation
import os.log
import Session
import Shared

private let logger = Logger(subsystem: "com.phosphene.app", category: "PreparationErrorVM")

// MARK: - PreparationPresentationState

/// The presentation mode PreparationProgressView should render.
enum PreparationPresentationState: Equatable {
    case normal
    case banner(UserFacingError)
    case fullScreen(UserFacingError)
}

// MARK: - PreparationErrorViewModel

@MainActor
final class PreparationErrorViewModel: ObservableObject {

    // MARK: - Published

    @Published private(set) var presentationState: PreparationPresentationState = .normal

    // MARK: - Private

    private var cancellables = Set<AnyCancellable>()

    // Tracks
    private var trackStatuses: [TrackIdentity: TrackPreparationStatus] = [:]
    private var totalTrackCount: Int = 0

    // Timing
    private var preparationStartDate = Date()
    private var firstTrackReadyDate: Date?
    private var hasRateLimitSignal = false

    // Timer
    private var timerTask: Task<Void, Never>?

    // MARK: - Init

    init(
        statusPublisher: AnyPublisher<[TrackIdentity: TrackPreparationStatus], Never>,
        reachability: any ReachabilityPublishing,
        totalTrackCount: Int
    ) {
        self.totalTrackCount = totalTrackCount

        statusPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] statuses in
                self?.handle(statuses: statuses)
            }
            .store(in: &cancellables)

        reachability.isOnlinePublisher
            .receive(on: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] isOnline in
                self?.handleReachability(isOnline: isOnline)
            }
            .store(in: &cancellables)

        startTimer()
    }

    // MARK: - Private

    private func handle(statuses: [TrackIdentity: TrackPreparationStatus]) {
        trackStatuses = statuses

        // Check if any track has a rate-limit signal.
        // (SessionPreparer communicates rate-limit via .partial reason in v1.)
        if statuses.values.contains(where: {
            if case .partial(let reason) = $0 { return reason.lowercased().contains("rate") }
            return false
        }) {
            hasRateLimitSignal = true
        }

        // Track when the first track becomes ready.
        if firstTrackReadyDate == nil,
           statuses.values.contains(where: { $0 == .ready }) {
            firstTrackReadyDate = Date()
        }

        recompute()
    }

    private func handleReachability(isOnline: Bool) {
        guard !isOnline else {
            recompute()
            return
        }
        // Only show offline error if we've actually started downloading
        // (at least one track is beyond .queued).
        let hasStarted = trackStatuses.values.contains(where: { $0 != .queued })
        if hasStarted {
            presentationState = .fullScreen(.networkOffline)
            logger.info("PreparationErrorVM: offline — showing full-screen error")
        }
    }

    private func recompute() {
        // Rule 1: Network check handled by reachability subscription.
        if case .fullScreen(.networkOffline) = presentationState { return }

        // Rule 2: All tracks failed.
        if totalTrackCount > 0,
           !trackStatuses.isEmpty,
           trackStatuses.values.allSatisfy({ if case .failed = $0 { return true }; return false }) {
            presentationState = .fullScreen(.allTracksFailedToPrepare)
            logger.info("PreparationErrorVM: all tracks failed")
            return
        }

        // Rule 3: Rate limit.
        if hasRateLimitSignal {
            presentationState = .banner(.previewRateLimited)
            return
        }

        // Rule 4: First track slow (>90s without any ready track).
        let elapsed = Date().timeIntervalSince(preparationStartDate)
        if firstTrackReadyDate == nil, elapsed > 90 {
            presentationState = .banner(.preparationSlowOnFirstTrack(elapsedSeconds: Int(elapsed)))
            return
        }

        // Rule 5: Total timeout (>120s without progressive-ready).
        if firstTrackReadyDate == nil, elapsed > 120 {
            presentationState = .banner(.preparationTotalTimeout)
            return
        }

        presentationState = .normal
    }

    private func startTimer() {
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, let self else { return }
                await MainActor.run { self.recompute() }
            }
        }
    }
}
