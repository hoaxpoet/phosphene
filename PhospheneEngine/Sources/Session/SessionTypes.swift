// SessionTypes — Shared value types for the session preparation pipeline.
// These types flow between PreviewResolver, PreviewDownloader, StemCache,
// and SessionPreparer as the pipeline moves from URL → PCM → stems → profile.

import Foundation

// MARK: - SessionState

/// The lifecycle state of a Phosphene visualization session.
public enum SessionState: String, Sendable, Equatable {
    /// No session is active.
    case idle
    /// Connecting to the music source and reading the playlist.
    case connecting
    /// Pre-analyzing tracks (stem separation + MIR analysis).
    case preparing
    /// Analysis complete. Waiting for playback to begin.
    case ready
    /// Playback is active.
    case playing
    /// The session has ended.
    case ended
}

// MARK: - ProgressiveReadinessLevel

/// Graduated preparation readiness level that advances independently of `SessionState`.
///
/// Allows `PreparationProgressView` to unlock the "Start now" CTA as soon as a minimum
/// prefix of tracks is ready, while preparation continues in the background.
///
/// `Comparable` ordering matches the case order: `preparing < readyForFirstTracks <
/// partiallyPlanned < fullyPrepared < reactiveFallback`. The `>=` idiom reads naturally
/// for threshold checks such as `progressiveReadinessLevel >= .readyForFirstTracks`.
public enum ProgressiveReadinessLevel: Sendable, Equatable, Comparable {
    /// Fewer than `DefaultProgressiveReadinessThreshold` consecutive tracks are ready from position 1.
    case preparing
    /// At least `DefaultProgressiveReadinessThreshold` consecutive tracks ready; < 50 % total.
    case readyForFirstTracks
    /// At least 50 % of all tracks ready; < 100 %.
    case partiallyPlanned
    /// All non-failed tracks are `.ready` or `.partial` — nothing left to prepare.
    case fullyPrepared
    /// No usable plan is possible (connector failure or all tracks failed).
    case reactiveFallback

    private var sortOrder: Int {
        switch self {
        case .preparing: return 0
        case .readyForFirstTracks: return 1
        case .partiallyPlanned: return 2
        case .fullyPrepared: return 3
        case .reactiveFallback: return 4
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}

/// Minimum number of consecutive ready tracks (from position 1) required to unlock "Start now".
public let defaultProgressiveReadinessThreshold: Int = 3

// MARK: - SessionPlan

/// A planned visual session for an ordered playlist.
///
/// Lightweight stub for Phase 4 Orchestrator expansion. The Orchestrator
/// will add preset assignments and transition timing per track.
public struct SessionPlan: Sendable {

    /// Ordered list of tracks in the session.
    public let tracks: [TrackIdentity]

    public init(tracks: [TrackIdentity]) {
        self.tracks = tracks
    }
}

// MARK: - PreviewAudio

/// Raw PCM audio decoded from a 30-second preview clip.
///
/// Produced by `PreviewDownloader` and consumed by `SessionPreparer` as the
/// input for stem separation and MIR analysis. All samples are mono Float32,
/// converted from the original stereo AAC/MP3 by averaging channels.
public struct PreviewAudio: Sendable {

    // MARK: - Properties

    /// The track this audio was downloaded for.
    public let trackIdentity: TrackIdentity

    /// Mono Float32 PCM samples, averaged from all source channels.
    public let pcmSamples: [Float]

    /// Sample rate of the decoded audio in Hz (typically 44100).
    public let sampleRate: Int

    /// Duration of the decoded audio in seconds.
    public let duration: TimeInterval

    // MARK: - Init

    /// Create a `PreviewAudio` value.
    ///
    /// - Parameters:
    ///   - trackIdentity: The track this audio corresponds to.
    ///   - pcmSamples: Mono Float32 PCM samples.
    ///   - sampleRate: Sample rate in Hz.
    ///   - duration: Duration in seconds.
    public init(
        trackIdentity: TrackIdentity,
        pcmSamples: [Float],
        sampleRate: Int,
        duration: TimeInterval
    ) {
        self.trackIdentity = trackIdentity
        self.pcmSamples = pcmSamples
        self.sampleRate = sampleRate
        self.duration = duration
    }
}
