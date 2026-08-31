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
    /// - `.partial` tracks NEVER count toward the consecutive prefix (PUB.6,
    ///   ultra-review). D-056 intended them to qualify when their cached
    ///   `TrackProfile` carried BPM + genre, but no code path has ever stored a
    ///   cache entry for a `.partial` track (stems fail → nothing is stored),
    ///   so the qualification was unreachable dead code. Making the D-056 rule
    ///   real would mean storing a metadata-only entry on the analysisError
    ///   path — a readiness-semantics change to take up deliberately, not a
    ///   side effect of a doc fix.
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
                // Only `.ready` qualifies. (The D-056 `.partial`-with-profile
                // arm was deleted at PUB.6 — unreachable; see the doc comment.)
                let countsForPrefix: Bool
                if case .ready = status { countsForPrefix = true } else { countsForPrefix = false }
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
