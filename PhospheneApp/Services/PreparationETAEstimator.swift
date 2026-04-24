// PreparationETAEstimator — Rolling EMA over per-stage durations.
// Returns estimated remaining time for a track currently in-flight.
// Pure value type — no side effects, fully testable in isolation.

import Foundation
import Session

// MARK: - Stage

/// Preparation stage identifier used as the EMA key.
enum PreparationStage: CaseIterable {
    case resolving
    case downloading
    case stemSeparation
    case caching
}

// MARK: - StageCompletion

/// A single observed stage completion used to update the EMA.
struct StageCompletion {
    let stage: PreparationStage
    let duration: TimeInterval
}

// MARK: - PreparationETAEstimator

/// Estimates remaining preparation time using an EMA over historical stage durations.
///
/// Returns `nil` until `minSamplesRequired` completions have been recorded — the UI
/// shows "Estimating…" or hides the ETA during this warm-up period.
struct PreparationETAEstimator {

    // MARK: - Configuration

    static let minSamplesRequired = 3
    static let emaAlpha: Double = 0.3

    // MARK: - State

    private var emaByStage: [PreparationStage: Double] = [:]
    private var sampleCount = 0

    // MARK: - Update

    /// Record a completed stage. Updates the EMA for that stage.
    ///
    /// Failed and partial track durations are NOT included — they are outliers
    /// that would bias estimates for the normal path.
    mutating func record(_ completion: StageCompletion) {
        let prev = emaByStage[completion.stage] ?? completion.duration
        emaByStage[completion.stage] = Self.emaAlpha * completion.duration + (1 - Self.emaAlpha) * prev
        sampleCount += 1
    }

    // MARK: - Estimate

    /// Estimated remaining time for a track at the given status.
    ///
    /// Returns `nil` if fewer than `minSamplesRequired` samples have been recorded.
    ///
    /// - Parameters:
    ///   - currentStatus: The track's current preparation status.
    /// - Returns: Estimated seconds remaining, or `nil` if insufficient data.
    func estimate(for currentStatus: TrackPreparationStatus) -> TimeInterval? {
        guard sampleCount >= Self.minSamplesRequired else { return nil }

        let remainingStages = stages(after: currentStatus)
        guard !remainingStages.isEmpty else { return nil }

        return remainingStages.reduce(0.0) { sum, stage in
            sum + (emaByStage[stage] ?? 0)
        }
    }

    // MARK: - Private

    private func stages(after status: TrackPreparationStatus) -> [PreparationStage] {
        switch status {
        case .queued:
            return PreparationStage.allCases
        case .resolving:
            return [.downloading, .stemSeparation, .caching]
        case .downloading:
            return [.stemSeparation, .caching]
        case .analyzing(let stage):
            switch stage {
            case .stemSeparation: return [.caching]
            case .mir: return [.caching]
            case .caching: return []
            }
        case .ready, .partial, .failed:
            return []
        }
    }
}
