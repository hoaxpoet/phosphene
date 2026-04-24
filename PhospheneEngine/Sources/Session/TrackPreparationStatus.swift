// TrackPreparationStatus — Per-track state in the session preparation pipeline.
// Seven canonical statuses cover every stage from queued through terminal outcomes.
// Reason strings are user-facing copy (< 40 chars); internal detail goes to the log.

import Foundation

// MARK: - AnalysisStage

/// Sub-stage within the analysis phase of session preparation.
public enum AnalysisStage: Sendable, Equatable {
    /// MPSGraph stem separation running (the bottleneck — up to 142 ms).
    case stemSeparation
    /// MIR pipeline: BPM, key, mood, spectral centroid.
    case mir
    /// Writing completed analysis to StemCache.
    case caching
}

// MARK: - TrackPreparationStatus

/// The current preparation status of a single track.
///
/// Advances from `.queued` through analysis stages to a terminal outcome.
/// All non-terminal statuses may transition to `.ready`, `.partial`, or `.failed`.
public enum TrackPreparationStatus: Equatable, Sendable {

    /// Waiting to be processed (not yet started).
    case queued

    /// Preview URL lookup in flight via iTunes Search API.
    case resolving

    /// Preview audio downloading. `progress` is 0–1 when known; −1 = indeterminate.
    case downloading(progress: Double)

    /// CPU/GPU analysis in progress. `stage` identifies the current sub-task.
    case analyzing(stage: AnalysisStage)

    /// Track fully prepared — stems + MIR cached and ready for playback.
    case ready

    /// Preview resolved and downloaded, but stem separation failed.
    /// Track will play in reactive mode (real-time stems only).
    ///
    /// `reason` is user-facing copy (< 40 chars).
    case partial(reason: String)

    /// Unrecoverable failure — no preview found or download error.
    /// Track will be skipped in the session plan.
    ///
    /// `reason` is user-facing copy (< 40 chars).
    case failed(reason: String)

    // MARK: - Derived Properties

    /// `true` for terminal statuses that produce no further updates.
    public var isTerminal: Bool {
        switch self {
        case .ready, .partial, .failed: return true
        default: return false
        }
    }

    /// `true` while analysis is actively in-flight.
    public var isInFlight: Bool {
        switch self {
        case .resolving, .downloading, .analyzing: return true
        default: return false
        }
    }
}
