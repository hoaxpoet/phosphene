// ConnectorType — Enum representing the three available playlist connectors.

import Foundation

// MARK: - ConnectorType

/// Identifies one of the three available playlist connectors in `ConnectorPickerView`.
enum ConnectorType: String, CaseIterable, Codable, Hashable {
    case appleMusic  = "apple_music"
    case spotify     = "spotify"
    case localFolder = "local_folder"

    var title: String {
        switch self {
        case .appleMusic:  return String(localized: "connector.type.apple_music.title")
        case .spotify:     return String(localized: "connector.type.spotify.title")
        case .localFolder: return String(localized: "connector.type.local_folder.title")
        }
    }

    var subtitle: String {
        switch self {
        case .appleMusic:  return String(localized: "connector.type.apple_music.subtitle")
        case .spotify:     return String(localized: "connector.type.spotify.subtitle")
        case .localFolder: return String(localized: "connector.type.local_folder.subtitle")
        }
    }

    var systemImage: String {
        switch self {
        case .appleMusic:  return "music.note.list"
        case .spotify:     return "link"
        case .localFolder: return "folder.fill"
        }
    }
}
