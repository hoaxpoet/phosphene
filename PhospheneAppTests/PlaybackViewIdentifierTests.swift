// PlaybackViewIdentifierTests — Structural accessibilityID tests for U.6 chrome views (U.6).
//
// Following the D-044 / U.1 pattern: verify each view declares its expected
// accessibilityID constant. Tests are instant (no rendering required).

import Session
import Testing
@testable import PhospheneApp

@Suite("PlaybackView chrome identifiers")
@MainActor
struct PlaybackChromeIdentifierTests {

    @Test func trackInfoCardView_hasExpectedID() {
        #expect(TrackInfoCardView.accessibilityID == "phosphene.playback.trackInfoCard")
    }

    @Test func sessionProgressDotsView_hasExpectedID() {
        #expect(SessionProgressDotsView.accessibilityID == "phosphene.playback.progressDots")
    }

    @Test func playbackControlsCluster_hasExpectedID() {
        #expect(PlaybackControlsCluster.accessibilityID == "phosphene.playback.controlsCluster")
    }

    @Test func listeningBadgeView_hasExpectedID() {
        #expect(ListeningBadgeView.accessibilityID == "phosphene.playback.listeningBadge")
    }

    @Test func playChromeView_hasExpectedID() {
        #expect(PlaybackChromeView.accessibilityID == "phosphene.playback.chrome")
    }

    @Test func shortcutHelpOverlayView_hasExpectedID() {
        #expect(ShortcutHelpOverlayView.accessibilityID == "phosphene.playback.shortcutHelp")
    }

    @Test func endSessionConfirmViewModel_defaultsUnpresented() {
        let mgr = SessionManager.testInstance()
        let vm = EndSessionConfirmViewModel(sessionManager: mgr)
        #expect(!vm.isPresented)
    }
}
