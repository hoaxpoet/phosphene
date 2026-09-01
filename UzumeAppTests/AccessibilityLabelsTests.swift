// AccessibilityLabelsTests — Unit tests for the AccessibilityLabels service. (U.9 Part B)

import Testing
@testable import UzumeApp

// MARK: - AccessibilityLabelsTests

@Suite("AccessibilityLabelsTests")
@MainActor
struct AccessibilityLabelsTests {

    // MARK: - sourceChoiceLabel

    @Test("Available tile label combines title and subtitle")
    func sourceChoiceLabelAvailable() {
        let label = AccessibilityLabels.sourceChoiceLabel(
            title: ConnectorType.appleMusic.title,
            detail: ConnectorType.appleMusic.subtitle
        )
        #expect(label.contains("Apple Music"))
        #expect(label.contains(ConnectorType.appleMusic.subtitle))
    }

    @Test("Unavailable tile label carries the reason instead of the subtitle")
    func sourceChoiceLabelUnavailable() {
        let reason = "Open Apple Music first"
        let label = AccessibilityLabels.sourceChoiceLabel(
            title: ConnectorType.appleMusic.title,
            detail: reason
        )
        #expect(label.contains("Apple Music"))
        #expect(label.contains(reason))
        #expect(!label.contains(ConnectorType.appleMusic.subtitle))
    }

    // MARK: - sourceChoiceHint

    @Test("Each affordance announces a distinct, non-empty hint")
    func sourceChoiceHintsDiffer() {
        let navigation = AccessibilityLabels.sourceChoiceHint(.navigation)
        let action = AccessibilityLabels.sourceChoiceHint(.action)
        let unavailable = AccessibilityLabels.sourceChoiceHint(.unavailable)

        #expect(!navigation.isEmpty)
        #expect(!action.isEmpty)
        #expect(!unavailable.isEmpty)
        // DS.2 decision A: an action tile is audibly different from a tile that
        // pushes a connector flow. If these collapse, that distinction is gone.
        #expect(navigation != action)
        #expect(action != unavailable)
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
