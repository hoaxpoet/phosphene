// ConnectorPickerFooterTests — the source picker's footer must stay true for
// every tile it sits under. (COPY-001)
//
// The footer used to read "Uzume reads what's playing. It doesn't control
// playback." That is true for Apple Music and Spotify, where Uzume listens to
// another app's output and the Curator presses play — and false for the Local
// files tile directly above it, where Uzume decodes the audio itself and ships
// a full transport (`LocalFileTransportBar`: stop / previous / play-pause /
// next). One screen, three sources, one blanket disclaimer that could not be
// true for all of them.
//
// EXPERIENCE_MODEL.md §Add music states the rule this guards: "Each source
// names its actual capabilities; a source never promises what it cannot
// honour."

import Testing
@testable import UzumeApp

// MARK: - ConnectorPickerFooterTests

@Suite("Connector picker footer (COPY-001)")
@MainActor
struct ConnectorPickerFooterTests {

    private var footer: String { String(localized: "connector.picker.footer") }

    @Test("The footer makes no unqualified claim that Uzume never controls playback")
    func footerMakesNoBlanketClaim() {
        // The exact sentence the defect was. Its return is the regression.
        #expect(!footer.contains("It doesn’t control playback"))
        #expect(!footer.contains("It doesn't control playback"))
    }

    @Test("The footer names the sources its listen-only behaviour applies to")
    func footerNamesTheStreamingSources() {
        // A claim scoped to Apple Music and Spotify is true; an unscoped one is
        // not, because Local files sits on the same screen.
        #expect(footer.contains("Apple Music"))
        #expect(footer.contains("Spotify"))
    }

    @Test("Local playback really does own transport — the reason this rule exists")
    func localTransportExists() {
        // If this ever stops being true, the original blanket footer becomes
        // correct again and this whole suite should be revisited rather than
        // silently kept.
        #expect(LocalFileTransportBar.accessibilityID == "uzume.playback.lfTransport")
    }
}
