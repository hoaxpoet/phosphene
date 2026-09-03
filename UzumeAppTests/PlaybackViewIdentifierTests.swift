// PlaybackViewIdentifierTests — Structural accessibilityID tests for U.6 chrome views (U.6).
//
// Following the D-044 / U.1 pattern: verify each view declares its expected
// accessibilityID constant. Tests are instant (no rendering required).

import Session
import Testing
@testable import UzumeApp

@Suite("PlaybackView chrome identifiers")
@MainActor
struct PlaybackChromeIdentifierTests {

    @Test func trackInfoCardView_hasExpectedID() {
        #expect(TrackInfoCardView.accessibilityID == "uzume.playback.trackInfoCard")
    }

    @Test func sessionProgressDotsView_hasExpectedID() {
        #expect(SessionProgressDotsView.accessibilityID == "uzume.playback.progressDots")
    }

    @Test func playbackControlsCluster_hasExpectedID() {
        #expect(PlaybackControlsCluster.accessibilityID == "uzume.playback.controlsCluster")
    }

    // DS.6: the two controls the cluster gained identifiers for. Extend, never edit.
    @Test func playbackControlsCluster_toggleTrackInfo_hasExpectedID() {
        #expect(PlaybackControlsCluster.toggleTrackInfoID == "uzume.playback.toggleTrackInfo")
    }

    @Test func playbackControlsCluster_endSession_hasExpectedID() {
        #expect(PlaybackControlsCluster.endSessionID == "uzume.playback.endSession")
    }

    @Test func listeningBadgeView_hasExpectedID() {
        #expect(ListeningBadgeView.accessibilityID == "uzume.playback.listeningBadge")
    }

    @Test func playChromeView_hasExpectedID() {
        #expect(PlaybackChromeView.accessibilityID == "uzume.playback.chrome")
    }

    @Test func shortcutHelpOverlayView_hasExpectedID() {
        #expect(ShortcutHelpOverlayView.accessibilityID == "uzume.playback.shortcutHelp")
    }

    @Test func endSessionConfirmViewModel_defaultsUnpresented() {
        let mgr = SessionManager.testInstance()
        let vm = EndSessionConfirmViewModel(sessionManager: mgr)
        #expect(!vm.isPresented)
    }
}
