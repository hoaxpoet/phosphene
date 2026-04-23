// ConnectorType — Enum representing the three available playlist connectors.

// MARK: - ConnectorType

/// Identifies one of the three available playlist connectors in `ConnectorPickerView`.
enum ConnectorType: String, CaseIterable, Codable, Hashable {
    case appleMusic  = "apple_music"
    case spotify     = "spotify"
    case localFolder = "local_folder"

    var title: String {
        switch self {
        case .appleMusic:  return "Apple Music"
        case .spotify:     return "Spotify"
        case .localFolder: return "Local Folder"
        }
    }

    var subtitle: String {
        switch self {
        case .appleMusic:  return "Read your current Apple Music playlist"
        case .spotify:     return "Connect with a Spotify playlist link"
        case .localFolder: return "Play from a folder of audio files"
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
