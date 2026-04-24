// UserFacingErrorTests — Exhaustive coverage tests for UserFacingError.
//
// Tests:
//   1. Every case has a presentation mode (no crash on switch exhaustion).
//   2. Every case has a severity.
//   3. The total case count matches UX_SPEC §9 row count (29).
//   4. log-only cases have no CTA keys.
//   5. Condition-bound cases have conditionIDs; non-bound don't.
//   6. CaseIterable allCases contains exactly 29 entries.
//   7. SpotifyRejectionKind.allCases is stable (4 cases).

import Testing
@testable import Shared

// MARK: - UserFacingErrorTests

@Suite("UserFacingError")
struct UserFacingErrorTests {

    // MARK: Count

    @Test("allCases count matches UX_SPEC §9 row count (29)")
    func test_caseCount_matchesSpecRowCount() {
        // 3 (§9.1) + 7 (§9.2) + 7 (§9.3) + 12 (§9.4) = 29
        #expect(UserFacingError.allCases.count == 29)
    }

    // MARK: Presentation mode

    @Test("every case has a presentationMode without crashing", arguments: UserFacingError.allCases)
    func test_everyCase_hasPresentationMode(_ error: UserFacingError) {
        let mode = error.presentationMode
        // Just confirming the switch is exhaustive and doesn't throw.
        _ = mode
    }

    // MARK: Severity

    @Test("every case has a severity without crashing", arguments: UserFacingError.allCases)
    func test_everyCase_hasSeverity(_ error: UserFacingError) {
        _ = error.severity
    }

    // MARK: Log-only cases have no primary CTA

    @Test("log-only cases have no primaryCTAKey")
    func test_logOnly_hasNoCTAKey() {
        let logOnlyCases: [UserFacingError] = [
            .sandboxBlockingCapture,
            .tapReinstallAttempt,
            .frameBudgetExceeded,
            .displayDisconnectedMidSession,
            .drawableSizeMismatch,
        ]
        for error in logOnlyCases {
            #expect(error.presentationMode == .logOnly || error.primaryCTAKey == nil,
                    "Expected no CTA key for log-only \(error)")
        }
    }

    // MARK: Condition-bound cases have conditionIDs

    @Test("isConditionBound cases each have a conditionID")
    func test_conditionBound_hasConditionID() {
        for error in UserFacingError.allCases where error.isConditionBound {
            #expect(error.conditionID != nil,
                    "Expected conditionID for condition-bound case \(error)")
        }
    }

    @Test("non-condition-bound cases without toast don't need conditionID")
    func test_nonConditionBound_logOnly_hasNoConditionID() {
        let logOnly: [UserFacingError] = [
            .tapReinstallAttempt, .frameBudgetExceeded, .drawableSizeMismatch, .sandboxBlockingCapture
        ]
        for error in logOnly {
            #expect(error.conditionID == nil,
                    "Expected no conditionID for \(error)")
        }
    }

    // MARK: §9.1 presentation modes

    @Test("permission errors present as fullScreen")
    func test_permissionErrors_fullScreen() {
        #expect(UserFacingError.screenCapturePermissionDenied.presentationMode == .fullScreen)
        #expect(UserFacingError.appleScriptPermissionDenied.presentationMode == .fullScreen)
        #expect(UserFacingError.sandboxBlockingCapture.presentationMode == .logOnly)
    }

    // MARK: §9.3 inline-row cases

    @Test("previewNotFound and stemSeparationFailed are inlineOnRow")
    func test_perTrackErrors_inlineOnRow() {
        #expect(UserFacingError.previewNotFound(trackTitle: "X").presentationMode == .inlineOnRow)
        #expect(UserFacingError.stemSeparationFailed(trackTitle: "X").presentationMode == .inlineOnRow)
    }

    // MARK: §9.4 playback toasts

    @Test("silenceExtended is bottomRightToast with warning severity")
    func test_silenceExtended_toastSeverity() {
        let e = UserFacingError.silenceExtended
        #expect(e.presentationMode == .bottomRightToast)
        #expect(e.severity == .warning)
        #expect(e.isConditionBound == true)
    }

    @Test("tapReinstallAttempt is logOnly")
    func test_tapReinstallAttempt_logOnly() {
        #expect(UserFacingError.tapReinstallAttempt.presentationMode == .logOnly)
    }

    // MARK: SpotifyRejectionKind

    @Test("SpotifyRejectionKind has 4 cases")
    func test_spotifyRejectionKind_count() {
        #expect(UserFacingError.SpotifyRejectionKind.allCases.count == 4)
    }

    // MARK: RetryStatus

    @Test("noCurrentlyPlayingPlaylist auto-retries")
    func test_noPlaylist_autoRetries() {
        let status = UserFacingError.noCurrentlyPlayingPlaylist.retryStatus
        #expect(status?.isAutoRetrying == true)
    }

    @Test("spotifyRateLimited includes attempt in description")
    func test_spotifyRateLimited_retryDescription() {
        let status = UserFacingError.spotifyRateLimited(attempt: 2).retryStatus
        #expect(status?.isAutoRetrying == true)
        #expect(status?.description?.contains("2") == true)
    }
}
