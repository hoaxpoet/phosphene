// PreparationProgressViewModel — Bridges PreparationProgressPublishing into PreparationProgressView.
// Maintains derived state: ordered rows, aggregate progress, ETA estimates, cancel confirmation.
//
// Increment 6.1: FeatureFlags.progressiveReadiness removed. canStartNow is now derived
// from a SessionManager.$progressiveReadinessLevel publisher injected at init.

import Combine
import Session
import SwiftUI

// MARK: - PreparationCounts

/// Terminal-state track counts derived from the latest publisher emission.
struct PreparationCounts {
    var ready: Int
    var partial: Int
    var failed: Int
    var total: Int

    static let zero = PreparationCounts(ready: 0, partial: 0, failed: 0, total: 0)
}

// MARK: - RowData

/// Flat view model for a single row in the preparation list.
struct RowData: Identifiable {
    let id: TrackIdentity
    let title: String
    let artist: String
    let status: TrackPreparationStatus
    let etaSeconds: TimeInterval?
}

// MARK: - PreparationProgressViewModel

/// ViewModel for `PreparationProgressView`.
///
/// Subscribes to `PreparationProgressPublishing.trackStatusesPublisher`,
/// maintains ordered rows and aggregate progress, and manages cancel confirmation.
@MainActor
final class PreparationProgressViewModel: ObservableObject {

    // MARK: - Published

    /// Rows in original track-list order (not dictionary order).
    @Published private(set) var rows: [RowData] = []

    /// Fraction of tracks in a terminal-success state (.ready or .partial).
    @Published private(set) var aggregateProgress: Double = 0

    /// Counts summary.
    @Published private(set) var counts: PreparationCounts = .zero

    /// Whether the "Start now" CTA is enabled.
    /// True when `SessionManager.progressiveReadinessLevel >= .readyForFirstTracks`.
    @Published private(set) var canStartNow: Bool = false

    /// Number of tracks currently in a usable state (.ready or .partial).
    /// Shown in the "Start now with N tracks ready" CTA copy.
    @Published private(set) var readyTrackCount: Int = 0

    /// Whether to show the cancel-confirmation dialog (≥ 1 track is .ready).
    @Published var showCancelConfirmation = false

    // MARK: - Private State

    private let publisher: any PreparationProgressPublishing
    private let trackList: [TrackIdentity]
    private let onStartNow: () -> Void
    private var cancellables = Set<AnyCancellable>()
    private var estimator = PreparationETAEstimator()
    private var stageStartTimes: [TrackIdentity: [PreparationStage: Date]] = [:]

    // MARK: - Init

    /// Create a view model backed by the given progress publisher.
    ///
    /// - Parameters:
    ///   - publisher: The `SessionPreparer` (or mock) to observe.
    ///   - trackList: Ordered list of tracks — rows appear in this order.
    ///   - progressiveReadinessPublisher: Emits `ProgressiveReadinessLevel` from `SessionManager`.
    ///     Drives `canStartNow`. Pass `Just(.preparing).eraseToAnyPublisher()` in tests that
    ///     don't exercise the progressive-readiness path.
    ///   - onStartNow: Closure called when the user taps "Start now". Typically
    ///     forwards to `SessionManager.startNow()`.
    init(
        publisher: any PreparationProgressPublishing,
        trackList: [TrackIdentity],
        progressiveReadinessPublisher: AnyPublisher<ProgressiveReadinessLevel, Never>,
        onStartNow: @escaping () -> Void = {}
    ) {
        self.publisher = publisher
        self.trackList = trackList
        self.onStartNow = onStartNow

        publisher.trackStatusesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] statuses in
                self?.handleStatusUpdate(statuses)
            }
            .store(in: &cancellables)

        progressiveReadinessPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] level in
                self?.canStartNow = level >= .readyForFirstTracks
            }
            .store(in: &cancellables)
    }

    // MARK: - Actions

    /// Handle the "Start now" button tap.
    func startNow() {
        onStartNow()
    }

    /// Handle a cancel button tap.
    ///
    /// Shows a confirmation dialog if any track is already `.ready`; otherwise
    /// cancels immediately. The view reacts to session-state changes — it does
    /// not navigate itself.
    func requestCancel() {
        let anyReady = rows.contains { $0.status == .ready }
        if anyReady {
            showCancelConfirmation = true
        } else {
            cancel()
        }
    }

    /// Cancel preparation unconditionally.
    ///
    /// Forwards to `publisher.cancelPreparation()`. `SessionManager` is responsible
    /// for transitioning state to `.idle` — the view disappears reactively.
    func cancel() {
        publisher.cancelPreparation()
    }

    // MARK: - Private

    private func handleStatusUpdate(_ statuses: [TrackIdentity: TrackPreparationStatus]) {
        let now = Date()

        for track in trackList {
            guard let status = statuses[track] else { continue }
            updateTiming(track: track, status: status, now: now)
        }

        rows = trackList.map { track in
            let status = statuses[track] ?? .queued
            let eta = estimator.estimate(for: status)
            return RowData(
                id: track,
                title: track.title,
                artist: track.artist,
                status: status,
                etaSeconds: eta
            )
        }

        let ready   = rows.filter { $0.status == .ready }.count
        let partial = rows.filter { if case .partial = $0.status { return true }; return false }.count
        let failed  = rows.filter { if case .failed  = $0.status { return true }; return false }.count
        let total   = trackList.count

        counts = PreparationCounts(ready: ready, partial: partial, failed: failed, total: total)
        aggregateProgress = total > 0 ? Double(ready + partial) / Double(total) : 0
        readyTrackCount = ready + partial
    }

    private func updateTiming(track: TrackIdentity, status: TrackPreparationStatus, now: Date) {
        let stage = preparationStage(for: status)

        if let stage {
            if stageStartTimes[track] == nil { stageStartTimes[track] = [:] }
            if stageStartTimes[track]?[stage] == nil {
                stageStartTimes[track]?[stage] = now
            }
        }

        if status.isTerminal && status == .ready {
            if let times = stageStartTimes[track] {
                for (completedStage, startTime) in times {
                    let duration = now.timeIntervalSince(startTime)
                    estimator.record(StageCompletion(stage: completedStage, duration: duration))
                }
            }
            stageStartTimes.removeValue(forKey: track)
        }
    }

    private func preparationStage(for status: TrackPreparationStatus) -> PreparationStage? {
        switch status {
        case .resolving: return .resolving
        case .downloading: return .downloading
        case .analyzing(let stage):
            switch stage {
            case .stemSeparation, .mir: return .stemSeparation
            case .caching: return .caching
            }
        default: return nil
        }
    }
}
