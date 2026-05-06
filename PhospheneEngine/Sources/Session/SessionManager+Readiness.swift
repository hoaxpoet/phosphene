// SessionManager+Readiness — Progressive readiness computation.
// Extracted from SessionManager.swift to keep that file under the 400-line
// SwiftLint gate (BUG-006.1 added wiring instrumentation that pushed it over).

import Foundation

extension SessionManager {

    // MARK: - Progressive Readiness Computation

    // swiftlint:disable cyclomatic_complexity
    /// Compute the progressive readiness level from the current track statuses.
    ///
    /// Rules (D-056):
    /// - `.partial` tracks count toward the consecutive prefix only when their cached
    ///   `TrackProfile` has a non-nil BPM **and** at least one genre tag.
    /// - A `.failed` track (or any in-flight track) in the prefix breaks the run.
    /// - `fullyPrepared` requires every track to be in a terminal state
    ///   (`.ready`, `.partial`, or `.failed`) with at least one usable track.
    /// - `reactiveFallback` when all terminal tracks are `.failed` (nothing to plan).
    public static func computeReadiness(
        statuses: [TrackIdentity: TrackPreparationStatus],
        trackList: [TrackIdentity],
        cache: StemCache
    ) -> ProgressiveReadinessLevel {
        guard !trackList.isEmpty else { return .reactiveFallback }

        let threshold = defaultProgressiveReadinessThreshold
        let total = trackList.count

        var prefixCount = 0
        var prefixBroken = false
        var readyCount = 0       // .ready or .partial
        var allTerminal = true

        for track in trackList {
            let status = statuses[track] ?? .queued

            let isTerminal: Bool
            switch status {
            case .ready, .partial, .failed: isTerminal = true
            default:                        isTerminal = false
            }
            if !isTerminal { allTerminal = false }

            let isReady: Bool
            switch status {
            case .ready, .partial: isReady = true
            default:               isReady = false
            }
            if isReady { readyCount += 1 }

            // Prefix: consecutive qualifying tracks from position 1.
            if !prefixBroken {
                let countsForPrefix: Bool
                switch status {
                case .ready:
                    countsForPrefix = true
                case .partial:
                    if let profile = cache.trackProfile(for: track),
                       profile.bpm != nil,
                       !profile.genreTags.isEmpty {
                        countsForPrefix = true
                    } else {
                        countsForPrefix = false
                    }
                default:
                    countsForPrefix = false
                }
                if countsForPrefix { prefixCount += 1 } else { prefixBroken = true }
            }
        }

        if allTerminal && readyCount == 0 { return .reactiveFallback }
        if allTerminal { return .fullyPrepared }
        if prefixCount < threshold { return .preparing }

        let readyPercent = Double(readyCount) / Double(total)
        return readyPercent >= 0.5 ? .partiallyPlanned : .readyForFirstTracks
    }
    // swiftlint:enable cyclomatic_complexity
}
