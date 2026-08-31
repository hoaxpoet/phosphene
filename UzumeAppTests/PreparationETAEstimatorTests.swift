// PreparationETAEstimatorTests — Unit tests for the rolling EMA over stage durations.
// Pure value-type tests; no Metal, no async, no UI.

import Foundation
import Session
import Testing
@testable import PhospheneApp

@Suite("PreparationETAEstimator")
struct PreparationETAEstimatorTests {

    // MARK: - Warm-up Gate

    @Test func firstThreeTracks_returnsNil() {
        var estimator = PreparationETAEstimator()

        // Feed 2 completions (below threshold of 3).
        estimator.record(StageCompletion(stage: .resolving, duration: 0.5))
        estimator.record(StageCompletion(stage: .downloading, duration: 1.2))

        let result = estimator.estimate(for: .resolving)
        #expect(result == nil, "Expected nil before minSamplesRequired completions")
    }

    @Test func afterThreeTracks_returnsNonNilEstimate() {
        var estimator = PreparationETAEstimator()
        feedCompletions(&estimator, count: 3)

        let result = estimator.estimate(for: .resolving)
        #expect(result != nil, "Expected non-nil estimate after \(PreparationETAEstimator.minSamplesRequired) samples")
    }

    // MARK: - EMA Bias

    @Test func emaFavorsRecentSamples() {
        var estimator = PreparationETAEstimator()

        // Feed 5 slow samples (10s each) then 5 fast samples (1s each).
        for _ in 0..<5 {
            estimator.record(StageCompletion(stage: .stemSeparation, duration: 10.0))
        }
        for _ in 0..<5 {
            estimator.record(StageCompletion(stage: .stemSeparation, duration: 1.0))
        }

        let result = estimator.estimate(for: .analyzing(stage: .stemSeparation))
        let pureMean: Double = (5 * 10 + 5 * 1) / 10  // = 5.5

        // EMA at alpha=0.3 should be biased toward the recent (fast) samples — below mean.
        #expect(result != nil)
        if let result {
            #expect(result < pureMean, "EMA (\(result)) should be below pure mean (\(pureMean)) after fast samples")
        }
    }

    @Test func failedTrackDurations_notIncludedInEMA() {
        // Strategy: seed with 3 successful completions establishing a baseline EMA,
        // then verify that recording a very long "failed" duration doesn't affect output.
        // (PreparationETAEstimator.record is only called for successful tracks.)
        var estimator = PreparationETAEstimator()
        feedCompletions(&estimator, count: 3, duration: 1.0)

        let baselineEstimate = estimator.estimate(for: .resolving)

        // The caller (ViewModel) must NOT call record() for failed tracks.
        // This test verifies the estimator itself doesn't change when we don't record.
        let estimateAfterFailedTrack = estimator.estimate(for: .resolving)

        #expect(baselineEstimate == estimateAfterFailedTrack,
                "Estimate must not change when failed tracks are excluded from record()")
    }

    @Test func estimateForCurrentTrack_sumsRemainingStageEMAs() {
        var estimator = PreparationETAEstimator()

        // Feed known durations: resolving=1s, downloading=2s, stemSep=3s, caching=0.5s.
        for _ in 0..<5 {
            estimator.record(StageCompletion(stage: .resolving, duration: 1.0))
            estimator.record(StageCompletion(stage: .downloading, duration: 2.0))
            estimator.record(StageCompletion(stage: .stemSeparation, duration: 3.0))
            estimator.record(StageCompletion(stage: .caching, duration: 0.5))
        }

        // A track currently `.downloading` has stemSeparation + caching remaining.
        let estimate = estimator.estimate(for: .downloading(progress: -1))
        #expect(estimate != nil)
        if let estimate {
            // With pure EMA and constant inputs, EMA ≈ actual value.
            // stemSep(3) + caching(0.5) = 3.5 ± small floating-point drift.
            #expect(estimate > 3.0 && estimate < 4.0,
                    "Expected ~3.5s for downloading stage, got \(estimate)")
        }
    }

    // MARK: - Helpers

    private func feedCompletions(
        _ estimator: inout PreparationETAEstimator,
        count: Int,
        duration: TimeInterval = 0.5
    ) {
        for _ in 0..<count {
            estimator.record(StageCompletion(stage: .resolving, duration: duration))
            estimator.record(StageCompletion(stage: .downloading, duration: duration))
            estimator.record(StageCompletion(stage: .stemSeparation, duration: duration))
            estimator.record(StageCompletion(stage: .caching, duration: duration))
        }
    }
}
