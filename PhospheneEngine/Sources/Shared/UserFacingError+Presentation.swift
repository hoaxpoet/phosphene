// UserFacingError+Presentation — Presentation metadata for every error case.
//
// Maps each case to its placement mode, severity, retry status, and CTA key.
// CTA keys are Localizable.strings keys; the App layer resolves them to strings.
// This extension lives in the engine (no UIKit/SwiftUI dependency).

import Foundation

// MARK: - Presentation Mode

/// Where a `UserFacingError` is displayed in the UI.
public enum ErrorPresentationMode: Sendable, Equatable {
    /// Replaces the current state view — user cannot proceed without resolving.
    case fullScreen
    /// Inline on the affected track's row in `PreparationProgressView`.
    case inlineOnRow
    /// Thin strip above the track list — non-blocking, auto-dismissed when resolved.
    case topBanner
    /// Bottom-right transient notification during `.playing` state.
    case bottomRightToast
    /// No user-visible presentation — logged to `session.log` only.
    case logOnly
}

// MARK: - Error Severity

/// Visual urgency of a `UserFacingError`.
public enum ErrorSeverity: Sendable, Equatable {
    /// Soft, non-blocking — something worth knowing.
    case info
    /// User may want to act, but the session can continue.
    case warning
    /// Phosphene is operating in degraded mode.
    case degradation
    /// Session cannot continue without user action.
    case fatal
}

// MARK: - Retry Status

/// Whether a `UserFacingError` is being automatically retried.
public struct ErrorRetryStatus: Sendable, Equatable {
    public let isAutoRetrying: Bool
    /// Short description appended to the toast copy, e.g. "attempt 2 of 3". Nil if not retrying.
    public let description: String?

    public static let none = ErrorRetryStatus(isAutoRetrying: false, description: nil)
    public static func autoRetrying(_ description: String? = nil) -> ErrorRetryStatus {
        ErrorRetryStatus(isAutoRetrying: true, description: description)
    }
}

// MARK: - Presentation Extension

extension UserFacingError {

    /// Where this error is presented in the UI.
    public var presentationMode: ErrorPresentationMode {
        switch self {

        // §9.1 — Permission
        case .screenCapturePermissionDenied, .appleScriptPermissionDenied:
            return .fullScreen
        case .sandboxBlockingCapture:
            return .logOnly

        // §9.2 — Connection
        case .appleMusicNotRunning, .noCurrentlyPlayingPlaylist,
             .spotifyURLMalformed, .spotifyURLNotPlaylist,
             .spotifyUnreachable, .emptyPlaylist:
            return .fullScreen
        case .spotifyRateLimited:
            return .fullScreen    // inline in SpotifyConnectionView, treated as full-screen state

        // §9.3 — Preparation
        case .previewNotFound, .stemSeparationFailed:
            return .inlineOnRow
        case .previewRateLimited, .preparationSlowOnFirstTrack, .preparationTotalTimeout:
            return .topBanner
        case .networkOffline, .allTracksFailedToPrepare:
            return .fullScreen

        // §9.4 — Playback
        case .silenceBrief:
            return .bottomRightToast   // rendered as ListeningBadgeView; bridge also uses this
        case .silenceExtended, .tapReinstallAllFailed, .mpsGraphAllocationFailure,
             .sampleRateMismatch, .audioLevelsLow, .displayDisconnectedMidSession,
             .negativeNudgeTwice, .rePlanSucceeded:
            return .bottomRightToast
        case .tapReinstallAttempt, .frameBudgetExceeded, .drawableSizeMismatch:
            return .logOnly
        }
    }

    /// Visual severity, maps to `PhospheneToast.Severity` in the App layer.
    public var severity: ErrorSeverity {
        switch self {
        case .networkOffline, .allTracksFailedToPrepare, .tapReinstallAllFailed:
            return .fatal
        case .screenCapturePermissionDenied, .appleScriptPermissionDenied,
             .spotifyUnreachable, .sampleRateMismatch, .audioLevelsLow:
            return .warning
        case .mpsGraphAllocationFailure, .stemSeparationFailed, .previewNotFound:
            return .degradation
        case .silenceExtended, .frameBudgetExceeded, .displayDisconnectedMidSession:
            return .warning
        default:
            return .info
        }
    }

    /// Auto-retry status, if applicable. Nil if the error does not auto-retry.
    public var retryStatus: ErrorRetryStatus? {
        switch self {
        case .noCurrentlyPlayingPlaylist:
            return .autoRetrying("checking every 2 seconds")
        case .spotifyRateLimited(let attempt):
            return .autoRetrying("attempt \(attempt) of 3")
        case .previewRateLimited:
            return .autoRetrying()
        default:
            return nil
        }
    }

    /// Localizable.strings key for the primary CTA button. Nil if none.
    public var primaryCTAKey: String? {
        switch self {
        case .screenCapturePermissionDenied, .appleScriptPermissionDenied:
            return "cta.open_system_settings"
        case .appleMusicNotRunning:
            return "cta.open_apple_music"
        case .spotifyURLMalformed, .spotifyURLNotPlaylist:
            return "cta.paste_again"
        case .spotifyUnreachable:
            return "cta.try_again"
        case .emptyPlaylist:
            return "cta.pick_different_playlist"
        case .networkOffline:
            return "cta.retry_when_online"
        case .allTracksFailedToPrepare:
            return "cta.pick_different_playlist"
        case .preparationSlowOnFirstTrack, .preparationTotalTimeout:
            return "cta.start_reactive_mode"
        default:
            return nil
        }
    }

    /// Localizable.strings key for the secondary CTA link. Nil if none.
    public var secondaryCTAKey: String? {
        switch self {
        case .screenCapturePermissionDenied:
            return nil
        case .appleScriptPermissionDenied:
            return "cta.skip_to_spotify"
        case .appleMusicNotRunning:
            return "cta.use_spotify"
        case .networkOffline, .allTracksFailedToPrepare:
            return "cta.start_reactive_mode"
        default:
            return nil
        }
    }

    /// Whether the error's toast auto-dismisses when the underlying condition resolves.
    ///
    /// `true` means the `PlaybackErrorBridge` should use condition-tagged dismiss;
    /// `false` means the toast has a fixed duration or requires user action.
    public var isConditionBound: Bool {
        switch self {
        case .silenceBrief, .silenceExtended, .audioLevelsLow:
            return true
        default:
            return false
        }
    }

    /// Stable string key for condition-based toast management in `PlaybackErrorBridge`.
    public var conditionID: String? {
        switch self {
        case .silenceBrief:      return "silence.brief"
        case .silenceExtended:   return "silence.extended"
        case .tapReinstallAllFailed: return "tap.reinstall.exhausted"
        case .mpsGraphAllocationFailure: return "mpsgraph.alloc.fail"
        case .sampleRateMismatch: return "audio.samplerate.mismatch"
        case .audioLevelsLow:    return "audio.levels.low"
        default:                 return nil
        }
    }
}
