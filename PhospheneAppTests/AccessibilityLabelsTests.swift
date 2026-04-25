// AccessibilityLabelsTests — Unit tests for the AccessibilityLabels service. (U.9 Part B)

import Testing
@testable import PhospheneApp

// MARK: - AccessibilityLabelsTests

@Suite("AccessibilityLabelsTests")
@MainActor
struct AccessibilityLabelsTests {

    // MARK: - connectorTileLabel

    @Test("Enabled tile label combines title and subtitle")
    func connectorTileLabelEnabled() {
        let label = AccessibilityLabels.connectorTileLabel(
            type: .appleMusic,
            isEnabled: true,
            disabledCaption: nil
        )
        #expect(label.contains("Apple Music"))
        #expect(label.contains(ConnectorType.appleMusic.subtitle))
    }

    @Test("Disabled tile label with caption uses caption instead of subtitle")
    func connectorTileLabelDisabledWithCaption() {
        let caption = "Open Apple Music first"
        let label = AccessibilityLabels.connectorTileLabel(
            type: .appleMusic,
            isEnabled: false,
            disabledCaption: caption
        )
        #expect(label.contains("Apple Music"))
        #expect(label.contains(caption))
        #expect(!label.contains(ConnectorType.appleMusic.subtitle))
    }

    @Test("Disabled tile label without caption falls back to localized hint string")
    func connectorTileLabelDisabledNoCaption() {
        let label = AccessibilityLabels.connectorTileLabel(
            type: .localFolder,
            isEnabled: false,
            disabledCaption: nil
        )
        #expect(label.contains("Local Folder"))
        #expect(!label.isEmpty)
    }

    // MARK: - trackInfoCardLabel

    @Test("Full track info card label joins title, artist, and preset")
    func trackInfoCardLabelFull() {
        let label = AccessibilityLabels.trackInfoCardLabel(
            title: "So What",
            artist: "Miles Davis",
            preset: "Glass Brutalist"
        )
        #expect(label.contains("So What"))
        #expect(label.contains("Miles Davis"))
        #expect(label.contains("Glass Brutalist"))
    }

    @Test("Track info card label omits nil artist gracefully")
    func trackInfoCardLabelNoArtist() {
        let label = AccessibilityLabels.trackInfoCardLabel(
            title: "Unknown",
            artist: nil,
            preset: nil
        )
        #expect(label == "Unknown")
    }

    @Test("Track info card label uses fallback when title is nil or empty")
    func trackInfoCardLabelNoTitle() {
        let labelNil = AccessibilityLabels.trackInfoCardLabel(
            title: nil,
            artist: "Someone",
            preset: nil
        )
        #expect(!labelNil.isEmpty)
        #expect(labelNil.contains("Someone"))

        let labelEmpty = AccessibilityLabels.trackInfoCardLabel(
            title: "",
            artist: "Someone",
            preset: nil
        )
        #expect(!labelEmpty.isEmpty)
    }

    // MARK: - toastLabel

    @Test("Toast label prefixes copy with severity string")
    func toastLabelInfo() {
        let label = AccessibilityLabels.toastLabel(
            copy: "Display connected",
            severity: .info
        )
        #expect(label.contains("Info"))
        #expect(label.contains("Display connected"))
    }

    @Test("Toast label uses Warning prefix for warning severity")
    func toastLabelWarning() {
        let label = AccessibilityLabels.toastLabel(
            copy: "Audio is quiet",
            severity: .warning
        )
        #expect(label.contains("Warning"))
    }

    @Test("Toast label uses Alert prefix for degradation severity")
    func toastLabelDegradation() {
        let label = AccessibilityLabels.toastLabel(
            copy: "No audio detected",
            severity: .degradation
        )
        #expect(label.contains("Alert"))
        #expect(label.contains("No audio detected"))
    }
}
