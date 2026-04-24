// LocalizedCopy — App-layer bridge from UserFacingError to localized strings.
//
// All copy resolution goes through this single path, so tests can call
// LocalizedCopy.string(for:) without constructing String(localized:) inline.
// Strings live in PhospheneApp/en.lproj/Localizable.strings.

import Foundation
import Shared

// MARK: - LocalizedCopy

/// Resolves a `UserFacingError` case to its localized user-facing string.
///
/// Uses `String(localized:bundle:)` so the App bundle's `Localizable.strings`
/// is the authoritative source. If a key is missing, `String(localized:)` returns
/// the key itself — a signal of incomplete extraction.
enum LocalizedCopy {

    // MARK: - Primary resolution

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    static func string(for error: UserFacingError) -> String {
        switch error {

        // §9.1 Permission
        case .screenCapturePermissionDenied:
            return loc("error.permission.screen_capture.headline")
        case .appleScriptPermissionDenied:
            return loc("error.permission.applescript.headline")
        case .sandboxBlockingCapture:
            return ""  // dev-only, no user copy

        // §9.2 Connection
        case .appleMusicNotRunning:
            return loc("error.connection.apple_music_not_running.headline")
        case .noCurrentlyPlayingPlaylist:
            return loc("error.connection.no_playlist")
        case .spotifyURLMalformed:
            return loc("error.connection.spotify_url_malformed")
        case .spotifyURLNotPlaylist(let kind):
            return spotifyRejectionCopy(kind)
        case .spotifyRateLimited(let attempt):
            return String(format: loc("error.connection.spotify_rate_limited"), attempt)
        case .spotifyUnreachable:
            return loc("error.connection.spotify_unreachable.headline")
        case .emptyPlaylist:
            return loc("error.connection.empty_playlist")

        // §9.3 Preparation
        case .previewNotFound:
            return loc("error.preparation.preview_not_found")
        case .previewRateLimited:
            return loc("error.preparation.rate_limited")
        case .networkOffline:
            return loc("error.preparation.network_offline.headline")
        case .stemSeparationFailed:
            return loc("error.preparation.stem_failure")
        case .allTracksFailedToPrepare:
            return loc("error.preparation.all_failed.headline")
        case .preparationSlowOnFirstTrack:
            return loc("error.preparation.slow_first_track.headline")
        case .preparationTotalTimeout:
            return loc("error.preparation.total_timeout.headline")

        // §9.4 Playback
        case .silenceBrief:
            return loc("error.playback.silence_brief")
        case .silenceExtended:
            return loc("error.playback.silence_extended")
        case .tapReinstallAttempt:
            return ""  // log only
        case .tapReinstallAllFailed:
            return loc("error.playback.tap_reinstall_failed")
        case .mpsGraphAllocationFailure:
            return loc("error.playback.mpsgraph_failure")
        case .sampleRateMismatch(let rateHz):
            return String(format: loc("error.playback.sample_rate_mismatch"), rateHz)
        case .audioLevelsLow(let isSpotify):
            return loc(isSpotify ? "error.playback.audio_levels_low_spotify"
                                 : "error.playback.audio_levels_low_generic")
        case .frameBudgetExceeded:
            return ""  // log only unless settings flag is on
        case .displayDisconnectedMidSession:
            return loc("error.playback.display_disconnected")
        case .drawableSizeMismatch:
            return ""  // log only
        case .negativeNudgeTwice:
            return loc("error.playback.negative_nudge_twice")
        case .rePlanSucceeded:
            return loc("error.playback.replan_succeeded")
        }
    }

    /// Localized body/secondary copy for an error. Nil if the error has no body.
    static func bodyString(for error: UserFacingError) -> String? {
        switch error {
        case .screenCapturePermissionDenied:
            return loc("error.permission.screen_capture.body")
        case .appleScriptPermissionDenied:
            return loc("error.permission.applescript.body")
        case .appleMusicNotRunning:
            return loc("error.connection.apple_music_not_running.body")
        case .spotifyUnreachable:
            return loc("error.connection.spotify_unreachable.body")
        case .networkOffline:
            return loc("error.preparation.network_offline.body")
        case .allTracksFailedToPrepare:
            return loc("error.preparation.all_failed.body")
        case .preparationSlowOnFirstTrack:
            return loc("error.preparation.slow_first_track.body")
        case .preparationTotalTimeout:
            return loc("error.preparation.total_timeout.body")
        default:
            return nil
        }
    }

    /// Localized label for a CTA key. Returns the key itself if the key is missing.
    static func cta(_ key: String) -> String {
        loc(key)
    }

    // MARK: - Private

    private static func loc(_ key: String) -> String {
        String(localized: String.LocalizationValue(key), bundle: Bundle.main)
    }

    private static func spotifyRejectionCopy(_ kind: UserFacingError.SpotifyRejectionKind) -> String {
        switch kind {
        case .track:   return loc("error.connection.spotify_url_is_track")
        case .album:   return loc("error.connection.spotify_url_is_album")
        case .artist:  return loc("error.connection.spotify_url_is_artist")
        case .unknown: return loc("error.connection.spotify_url_unknown")
        }
    }
}

// MARK: - Jargon deny list

extension LocalizedCopy {

    /// Terms that must never appear in user-facing copy per UX_SPEC §9.5.
    static let jargonDenyList: [String] = [
        "MPSGraph", "FFT", "IRQ", "DRM", "NSURLError", "sandbox", "G-buffer",
        "SSGI", "MIR", "StemCache", "AudioHardware",
    ]

    /// Returns true if the copy string contains any jargon from the deny list.
    static func containsJargon(_ copy: String) -> Bool {
        jargonDenyList.contains { copy.contains($0) }
    }
}
