// UserFacingError — Typed enum covering every user-visible error surface in Phosphene.
//
// Lives in the Shared module (engine-layer) so Session, Audio, and App can all
// reference the same typed cases. Copy lives in the App bundle's Localizable.strings;
// `LocalizedCopy` (App layer) bridges case → localized string.
//
// Organised by the four §9 tables in UX_SPEC.md:
//   §9.1 Permission (3 cases)
//   §9.2 Connection (7 cases)
//   §9.3 Preparation (7 cases)
//   §9.4 Playback (12 cases)
//
// Total: 29 cases matching the 29 rows in UX_SPEC §9.1–§9.4.
//
// CaseIterable is provided via manual `allCases` because Swift cannot synthesise
// it for enums with associated values. Use `representativeCases` in tests.

import Foundation

// MARK: - UserFacingError

/// A typed error case for every user-visible error surface in Phosphene.
///
/// Each case maps to exactly one row in `UX_SPEC.md §9.1–§9.4`. Silent rows
/// (developer-only / log-only) are represented by cases whose `presentationMode`
/// returns `.logOnly` — the App layer should not show UI for them.
public enum UserFacingError: Sendable, Hashable {

    // MARK: §9.1 Permission

    /// Screen-capture permission not granted (`CGPreflightScreenCaptureAccess() == false`).
    case screenCapturePermissionDenied

    /// Automation (AppleScript) permission denied for Apple Music.
    case appleScriptPermissionDenied

    /// Sandbox preventing audio capture — should never occur in production (sandbox disabled).
    /// Always resolves to `.logOnly` presentation.
    case sandboxBlockingCapture

    // MARK: §9.2 Connection

    /// Apple Music app is not running.
    case appleMusicNotRunning

    /// Apple Music is running but the user has no currently-playing playlist.
    case noCurrentlyPlayingPlaylist

    /// The pasted URL does not parse as any Spotify link.
    case spotifyURLMalformed

    /// The pasted URL is a valid Spotify link but is not a playlist.
    case spotifyURLNotPlaylist(kind: SpotifyRejectionKind)

    /// Spotify Web API returned 429; auto-retrying. `attempt` is 1-based (1–3).
    case spotifyRateLimited(attempt: Int)

    /// Spotify Web API unreachable after all retries.
    case spotifyUnreachable

    /// The playlist URL resolved but the playlist contains zero tracks.
    case emptyPlaylist

    // MARK: §9.3 Preparation

    /// iTunes Search API returned no preview URL for this specific track.
    case previewNotFound(trackTitle: String)

    /// iTunes Search API returned 429; preparation continues at reduced throughput.
    case previewRateLimited

    /// Network unreachable while fetching previews (aggregated failure heuristic).
    case networkOffline

    /// Stem separation failed for this specific track (preview found and downloaded).
    case stemSeparationFailed(trackTitle: String)

    /// Every track in the playlist failed preparation — session unlaunchable.
    case allTracksFailedToPrepare

    /// First-track preparation has taken longer than 90 seconds.
    case preparationSlowOnFirstTrack(elapsedSeconds: Int)

    /// Total preparation elapsed more than 2 minutes without reaching progressive-ready.
    case preparationTotalTimeout

    // MARK: §9.4 Playback

    /// Audio has been silent for more than 3 seconds ("Listening…" badge, not a toast).
    case silenceBrief

    /// Audio has been silent for more than 15 seconds (bottom-right toast).
    case silenceExtended

    /// The Core Audio tap was reinstalled — informational log event, no user copy.
    case tapReinstallAttempt

    /// Three consecutive tap reinstall attempts all failed.
    case tapReinstallAllFailed

    /// MPSGraph stem-separation allocation failed mid-session; falling back to reactive mode.
    case mpsGraphAllocationFailure

    /// The system audio sample rate is not 44.1 or 48 kHz. `rateHz` is the actual rate.
    case sampleRateMismatch(rateHz: Int)

    /// Detected persistently low audio levels. `isSpotifySource` triggers Normalize-Volume copy.
    case audioLevelsLow(isSpotifySource: Bool)

    /// Frame budget exceeded and governor activated — log-only by default.
    case frameBudgetExceeded

    /// The output display was disconnected mid-session — reparenting is handled silently.
    case displayDisconnectedMidSession

    /// Video-writer drawable-size mismatch logged to session.log — never shown to user.
    case drawableSizeMismatch

    /// Curator pressed `-` twice within 90 s — ambient hint (§8.2 of UX_SPEC).
    case negativeNudgeTwice

    /// `⌘R` re-plan completed — acknowledgment toast (flag-gated, §7.4 of UX_SPEC).
    case rePlanSucceeded

    // MARK: - Nested Types

    /// What kind of non-playlist Spotify URL was rejected.
    public enum SpotifyRejectionKind: Sendable, Hashable, CaseIterable {
        case track
        case album
        case artist
        case unknown
    }
}

// MARK: - CaseIterable

extension UserFacingError: CaseIterable {
    /// One representative instance per case, for use in exhaustive tests.
    ///
    /// Cases with associated values use stable representative values so that
    /// jargon and coverage tests can iterate all 29 cases.
    public static var allCases: [UserFacingError] {
        [
            // §9.1 Permission
            .screenCapturePermissionDenied,
            .appleScriptPermissionDenied,
            .sandboxBlockingCapture,

            // §9.2 Connection
            .appleMusicNotRunning,
            .noCurrentlyPlayingPlaylist,
            .spotifyURLMalformed,
            .spotifyURLNotPlaylist(kind: .track),
            .spotifyRateLimited(attempt: 1),
            .spotifyUnreachable,
            .emptyPlaylist,

            // §9.3 Preparation
            .previewNotFound(trackTitle: "Sample Track"),
            .previewRateLimited,
            .networkOffline,
            .stemSeparationFailed(trackTitle: "Sample Track"),
            .allTracksFailedToPrepare,
            .preparationSlowOnFirstTrack(elapsedSeconds: 91),
            .preparationTotalTimeout,

            // §9.4 Playback
            .silenceBrief,
            .silenceExtended,
            .tapReinstallAttempt,
            .tapReinstallAllFailed,
            .mpsGraphAllocationFailure,
            .sampleRateMismatch(rateHz: 96_000),
            .audioLevelsLow(isSpotifySource: true),
            .frameBudgetExceeded,
            .displayDisconnectedMidSession,
            .drawableSizeMismatch,
            .negativeNudgeTwice,
            .rePlanSucceeded,
        ]
    }
}
