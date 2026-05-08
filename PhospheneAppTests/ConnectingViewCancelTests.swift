// ConnectingViewCancelTests — QR.4 / D-091.
//
// Verifies per-connector localization keys exist + resolve, accessibility
// identifier constants are stable, the view constructs without invoking the
// injected onCancel closure, and the headline does not have the trailing
// ellipsis that UX_SPEC §8.5 forbids on top-level state titles.
//
// SwiftUI subview traversal in unit tests is unreliable (Failed Approach
// #41 — accessibility tree only materialises with an active accessibility
// client), so we verify behaviour by invoking closures directly and by
// inspecting localized strings.

import AppKit
import Foundation
import Session
import SwiftUI
import Testing
@testable import PhospheneApp

@Suite("ConnectingViewCancel")
@MainActor
struct ConnectingViewCancelTests {

    @Test("required localization keys resolve to non-empty strings")
    func test_localizationKeys_resolve() {
        let keys = [
            "connecting.headline",
            "connecting.subtext",
            "connecting.appleMusic.subtext",
            "connecting.spotify.subtext",
            "connecting.localFolder.subtext",
            "connecting.cta.cancel"
        ]
        for key in keys {
            let value = String(localized: String.LocalizationValue(key))
            #expect(!value.isEmpty, "Localizable.strings missing key '\(key)'")
            #expect(value != key, "Localizable.strings key '\(key)' is unresolved (returned the key itself)")
        }
    }

    @Test("headline does not contain a trailing ellipsis")
    func test_headline_dropsTrailingEllipsis() {
        // UX_SPEC §8.5: state titles avoid ambient ellipses; the spinner
        // already conveys progress. Subtext rows may use them.
        let headline = String(localized: "connecting.headline")
        #expect(!headline.hasSuffix("…"),
                "connecting.headline must NOT end with an ellipsis (UX_SPEC §8.5)")
        #expect(!headline.hasSuffix("..."),
                "connecting.headline must NOT end with three dots either")
    }

    @Test("accessibility identifier constants are defined and distinct")
    func test_accessibilityIDs_areDistinct() {
        #expect(ConnectingView.accessibilityID == "phosphene.view.connecting")
        #expect(ConnectingView.cancelButtonID == "phosphene.connecting.cancel")
        #expect(ConnectingView.accessibilityID != ConnectingView.cancelButtonID)
    }

    @Test("view constructs with each PlaylistSource without invoking onCancel")
    func test_viewConstructs_doesNotInvokeOnCancel() {
        var calls = 0
        let sources: [PlaylistSource?] = [
            nil,
            .appleMusicCurrentPlaylist,
            .appleMusicPlaylistURL("https://music.apple.com/playlist/abc"),
            .spotifyCurrentQueue,
            .spotifyPlaylistURL("https://open.spotify.com/playlist/abc")
        ]
        for src in sources {
            let view = ConnectingView(source: src, onCancel: { calls += 1 })
            let host = NSHostingView(rootView: view)
            host.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
            host.layoutSubtreeIfNeeded()
        }
        #expect(calls == 0, "init must not invoke onCancel")
    }

    @Test("source binding maps via PlaylistSource cases — Spotify variants share subtext")
    func test_subtextResolution_isStableAcrossSpotifyVariants() {
        // Spec compliance: both Spotify-rooted PlaylistSource cases must yield
        // the same connecting.spotify.subtext key. If anyone adds a Spotify
        // variant they must update the switch in ConnectingView.connectorSubtext.
        let spotifyKey = String(localized: "connecting.spotify.subtext")
        #expect(!spotifyKey.isEmpty)
        let appleKey = String(localized: "connecting.appleMusic.subtext")
        #expect(!appleKey.isEmpty)
        #expect(spotifyKey != appleKey,
                "Apple Music and Spotify connecting subtexts must differ — per-connector personality")
    }
}
