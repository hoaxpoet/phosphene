// AccessibilityLabels — Centralized VoiceOver label/hint lookup. (U.9)
//
// All methods return localized strings sourced from Localizable.strings
// under the "a11y.*" key namespace. Call sites combine values from here
// rather than building label strings inline.

import Foundation

// MARK: - AccessibilityLabels

enum AccessibilityLabels {

    // MARK: - Source choice tile

    /// Which of `SourceChoice`'s affordances a hint is being asked for. Mirrors
    /// `SourceChoice.Affordance` without its closures so this service stays free
    /// of any dependency on the view layer.
    enum SourceChoiceKind {
        case navigation
        case action
        case unavailable
    }

    /// Full label for a `SourceChoice`: "Title. Detail." — `detail` is the
    /// subtitle when the source can be chosen and the reason when it cannot.
    /// This is the shape both the connector tiles and the local action tiles
    /// have announced since U.9; DS.2 consolidated them onto one component.
    static func sourceChoiceLabel(title: String, detail: String) -> String {
        "\(title). \(detail)"
    }

    /// Hint for a `SourceChoice`. DS.2 gave the local action tiles a hint they
    /// did not have before (decision A): a tile that pushes a connector flow and
    /// a tile that opens a macOS panel behave differently, and VoiceOver users
    /// previously heard that difference only on the first of the two screens.
    static func sourceChoiceHint(_ kind: SourceChoiceKind) -> String {
        switch kind {
        case .navigation:  return String(localized: "a11y.connector.tile.hint.enabled")
        case .action:      return String(localized: "a11y.source.tile.hint.action")
        case .unavailable: return String(localized: "a11y.connector.tile.hint.disabled")
        }
    }

    // MARK: - Track info card

    /// Builds a single VoiceOver label from optional track/artist/preset fields.
    static func trackInfoCardLabel(
        title: String?,
        artist: String?,
        preset: String?
    ) -> String {
        var parts: [String] = []
        if let title, !title.isEmpty {
            parts.append(title)
        } else {
            parts.append(String(localized: "a11y.trackInfoCard.unknownTrack"))
        }
        if let artist, !artist.isEmpty { parts.append(artist) }
        if let preset, !preset.isEmpty { parts.append(preset) }
        return parts.joined(separator: ", ")
    }

    // MARK: - Toast

    /// "Warning: No audio detected for 15 seconds."
    static func toastLabel(copy: String, severity: UzumeToast.Severity) -> String {
        let severityStr: String
        switch severity {
        case .info:        severityStr = String(localized: "a11y.toast.severity.info")
        case .warning:     severityStr = String(localized: "a11y.toast.severity.warning")
        case .degradation: severityStr = String(localized: "a11y.toast.severity.degradation")
        case .fatal:       severityStr = String(localized: "a11y.toast.severity.fatal")
        }
        return "\(severityStr): \(copy)"
    }
}
