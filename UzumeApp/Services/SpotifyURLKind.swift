// SpotifyURLKind — Parsed result of a Spotify URL or URI.

// MARK: - SpotifyURLKind

/// The kind of Spotify content identified in a pasted URL or URI.
enum SpotifyURLKind: Equatable {
    /// A Spotify playlist. The associated `id` is the Spotify playlist ID.
    case playlist(id: String)
    /// A Spotify track.
    case track(id: String)
    /// A Spotify album.
    case album(id: String)
    /// A Spotify artist page.
    case artist(id: String)
    /// The input could not be parsed as a Spotify URL or URI.
    case invalid
}
