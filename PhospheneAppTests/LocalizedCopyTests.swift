// LocalizedCopyTests — Exhaustive coverage for LocalizedCopy.string(for:).
//
// Tests:
//   1. Every case returns a non-empty string (or empty for log-only cases).
//   2. Cases with associated values interpolate correctly.
//   3. No user-facing string contains blacklisted jargon.
//   4. CTA keys resolve to non-empty strings.
//   5. Missing key falls through to key name (native String(localized:) behaviour).

import Shared
import Testing
@testable import PhospheneApp

// MARK: - LocalizedCopyTests

@Suite("LocalizedCopy")
struct LocalizedCopyTests {

    // MARK: - All cases have defined copy

    @Test("every non-log-only case returns non-empty string")
    func test_everyNonLogOnlyCase_hasNonEmptyString() {
        let logOnlyCases: Set<String> = [
            "sandboxBlockingCapture",
            "tapReinstallAttempt",
            "frameBudgetExceeded",
            "drawableSizeMismatch",
        ]
        for error in UserFacingError.allCases {
            let copy = LocalizedCopy.string(for: error)
            let label = "\(error)"
            if logOnlyCases.contains(where: { label.contains($0) }) {
                #expect(copy.isEmpty, "Expected empty copy for log-only case \(error)")
            } else {
                #expect(!copy.isEmpty, "Expected non-empty copy for \(error), got empty")
            }
        }
    }

    // MARK: - Associated value interpolation

    @Test("spotifyRateLimited interpolates attempt number")
    func test_spotifyRateLimited_interpolation() {
        let copy = LocalizedCopy.string(for: .spotifyRateLimited(attempt: 2))
        #expect(copy.contains("2"), "Expected attempt number in copy: \(copy)")
        #expect(!copy.contains("%d"), "Expected format specifier resolved in: \(copy)")
    }

    // MARK: - CA-Shared-FU-1: retryStatus wire-up

    @Test("spotifyRateLimited copy sources retry suffix from retryStatus.description")
    func test_spotifyRateLimited_retrySuffixFromAccessor() {
        // The localized base ("Spotify is being slow — still trying") no longer
        // contains the attempt number; the suffix is appended by LocalizedCopy
        // from UserFacingError.retryStatus.description ("attempt 2 of 3").
        let copy = LocalizedCopy.string(for: .spotifyRateLimited(attempt: 2))
        #expect(copy.contains("attempt 2 of 3"),
                "Expected retryStatus.description suffix in copy: '\(copy)'")
        #expect(copy.contains("(attempt 2 of 3)"),
                "Expected parenthesised suffix in copy: '\(copy)'")
    }

    @Test("spotifyRateLimited base copy is the localized headline only")
    func test_spotifyRateLimited_baseCopy_noInlineFormat() {
        // The Localizable.strings value no longer carries a %d placeholder —
        // the wire-up moved the attempt-number formatting out of the .strings
        // file into UserFacingError.retryStatus + LocalizedCopy.appendRetryStatus.
        let copy = LocalizedCopy.string(for: .spotifyRateLimited(attempt: 1))
        #expect(copy.hasPrefix("Spotify is being slow"),
                "Expected base headline at start of copy: '\(copy)'")
    }

    @Test("non-retrying error has no suffix appended")
    func test_nonRetryingError_noSuffix() {
        // .silenceExtended has retryStatus == nil — no suffix should be appended.
        let copy = LocalizedCopy.string(for: .silenceExtended)
        #expect(!copy.contains(" ("),
                "Expected no retry suffix on non-retrying error: '\(copy)'")
    }

    @Test("sampleRateMismatch interpolates rate in Hz")
    func test_sampleRateMismatch_interpolation() {
        let copy = LocalizedCopy.string(for: .sampleRateMismatch(rateHz: 96_000))
        #expect(copy.contains("96"), "Expected rate in copy: \(copy)")
        #expect(!copy.contains("%d"), "Expected format specifier resolved in: \(copy)")
    }

    @Test("spotifyURLNotPlaylist track copy mentions track")
    func test_spotifyURLNotPlaylist_track() {
        let copy = LocalizedCopy.string(for: .spotifyURLNotPlaylist(kind: .track))
        #expect(copy.lowercased().contains("track"),
                "Expected 'track' in rejection copy: \(copy)")
    }

    @Test("audioLevelsLow Spotify copy mentions Normalize Volume")
    func test_audioLevelsLow_spotify_copy() {
        let copy = LocalizedCopy.string(for: .audioLevelsLow(isSpotifySource: true))
        #expect(copy.contains("Normalize Volume") || copy.lowercased().contains("spotify"),
                "Expected Spotify-specific copy: \(copy)")
    }

    @Test("audioLevelsLow non-Spotify copy is generic")
    func test_audioLevelsLow_generic_copy() {
        let spotifyCopy  = LocalizedCopy.string(for: .audioLevelsLow(isSpotifySource: true))
        let genericCopy  = LocalizedCopy.string(for: .audioLevelsLow(isSpotifySource: false))
        #expect(spotifyCopy != genericCopy, "Expected different copy for Spotify vs generic source")
    }

    // MARK: - Jargon blacklist

    @Test("no user-facing copy contains jargon from deny list", arguments: UserFacingError.allCases)
    func test_noJargon_inCopy(_ error: UserFacingError) {
        let copy = LocalizedCopy.string(for: error)
        guard !copy.isEmpty else { return }  // log-only cases have empty copy
        let found = LocalizedCopy.jargonDenyList.filter { copy.contains($0) }
        #expect(found.isEmpty, "Found jargon \(found) in copy for \(error): '\(copy)'")
    }

    // MARK: - CTA keys

    @Test("all primaryCTAKeys resolve to non-empty strings")
    func test_allPrimaryCTAKeys_resolve() {
        for error in UserFacingError.allCases {
            guard let key = error.primaryCTAKey else { continue }
            let resolved = LocalizedCopy.cta(key)
            #expect(!resolved.isEmpty, "CTA key '\(key)' for \(error) resolved to empty string")
        }
    }

    @Test("all secondaryCTAKeys resolve to non-empty strings")
    func test_allSecondaryCTAKeys_resolve() {
        for error in UserFacingError.allCases {
            guard let key = error.secondaryCTAKey else { continue }
            let resolved = LocalizedCopy.cta(key)
            #expect(!resolved.isEmpty, "Secondary CTA key '\(key)' for \(error) resolved to empty")
        }
    }

    // MARK: - Body strings

    @Test("networkOffline has non-empty body string")
    func test_networkOffline_hasBodyString() {
        let body = LocalizedCopy.bodyString(for: .networkOffline)
        #expect(body?.isEmpty == false, "Expected non-empty body for networkOffline")
    }

    @Test("allTracksFailedToPrepare has non-empty body string")
    func test_allTracksFailed_hasBodyString() {
        let body = LocalizedCopy.bodyString(for: .allTracksFailedToPrepare)
        #expect(body?.isEmpty == false, "Expected non-empty body for allTracksFailedToPrepare")
    }

    @Test("silenceExtended has no body string")
    func test_silenceExtended_noBodyString() {
        #expect(LocalizedCopy.bodyString(for: .silenceExtended) == nil)
    }

    // MARK: - Exact copy spot-checks (gate against UX_SPEC drift)

    @Test("screen capture permission copy is verbatim from UX_SPEC §9.1")
    func test_screenCapture_exactCopy() {
        let copy = LocalizedCopy.string(for: .screenCapturePermissionDenied)
        #expect(copy == "Phosphene needs permission to hear music playing on your Mac.")
    }

    @Test("silence extended copy is verbatim from UX_SPEC §9.4")
    func test_silenceExtended_exactCopy() {
        let copy = LocalizedCopy.string(for: .silenceExtended)
        #expect(copy == "Haven\u{2019}t heard anything for a while. Is the music playing?")
    }

    @Test("allTracksFailedToPrepare headline is verbatim from UX_SPEC §9.3")
    func test_allTracksFailed_exactCopy() {
        let copy = LocalizedCopy.string(for: .allTracksFailedToPrepare)
        #expect(copy == "Couldn\u{2019}t prepare any of this playlist.")
    }

    @Test("networkOffline headline is verbatim from UX_SPEC §9.3")
    func test_networkOffline_exactCopy() {
        let copy = LocalizedCopy.string(for: .networkOffline)
        #expect(copy == "You\u{2019}re offline.")
    }
}
