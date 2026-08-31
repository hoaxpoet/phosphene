// AccessibilityLabels — Centralized VoiceOver label/hint lookup. (U.9)
//
// All methods return localized strings sourced from Localizable.strings
// under the "a11y.*" key namespace. Call sites combine values from here
// rather than building label strings inline.

import Foundation

// MARK: - AccessibilityLabels

enum AccessibilityLabels {

    // MARK: - Connector tile

    /// Full label for a `ConnectorTileView`: "Title. Subtitle/caption."
    static func connectorTileLabel(
        type: ConnectorType,
        isEnabled: Bool,
        disabledCaption: String?
    ) -> String {
        if isEnabled {
            return "\(type.title). \(type.subtitle)"
        }
        let caption = disabledCaption ?? String(localized: "a11y.connector.tile.hint.disabled")
        return "\(type.title). \(caption)"
    }

    static func connectorTileHint(isEnabled: Bool) -> String {
        isEnabled
            ? String(localized: "a11y.connector.tile.hint.enabled")
            : String(localized: "a11y.connector.tile.hint.disabled")
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
    static func toastLabel(copy: String, severity: PhospheneToast.Severity) -> String {
        let severityStr: String
        switch severity {
        case .info:        severityStr = String(localized: "a11y.toast.severity.info")
        case .warning:     severityStr = String(localized: "a11y.toast.severity.warning")
        case .degradation: severityStr = String(localized: "a11y.toast.severity.degradation")
        }
        return "\(severityStr): \(copy)"
    }
}
