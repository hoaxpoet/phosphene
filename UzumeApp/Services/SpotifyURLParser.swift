// SpotifyURLParser — Parses Spotify URLs and spotify: URIs into SpotifyURLKind.

import Foundation

// MARK: - SpotifyURLParser

/// Parses Spotify URLs and spotify: URIs into a typed `SpotifyURLKind`.
///
/// Accepted formats:
/// - `https://open.spotify.com/playlist/<id>` (canonical)
/// - `https://open.spotify.com/playlist/<id>?si=...` (with share token)
/// - `spotify:playlist:<id>` (URI scheme)
/// - Country-code subdomains, e.g. `https://open.spotify.com/playlist/<id>`
/// - Leading/trailing whitespace (paste artifacts)
/// - Leading `@` (paste artifact from some browsers)
///
/// Podcast URLs (`/show/`, `/episode/`) and other unrecognized types map to `.invalid`.
enum SpotifyURLParser {

    // MARK: - Parse

    /// Parse the input string into a `SpotifyURLKind`.
    static func parse(_ input: String) -> SpotifyURLKind {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .invalid }

        if trimmed.hasPrefix("spotify:") {
            return parseURI(trimmed)
        }
        return parseHTTPS(trimmed)
    }

    // MARK: - Private

    private static func parseURI(_ uri: String) -> SpotifyURLKind {
        let parts = uri.split(separator: ":", omittingEmptySubsequences: true)
        guard parts.count >= 3, parts[0] == "spotify" else { return .invalid }
        let type = String(parts[1])
        let id   = String(parts[2])
        return kind(type: type, id: id)
    }

    private static func parseHTTPS(_ urlString: String) -> SpotifyURLKind {
        // Accept a leading "@" — some browsers paste share links with it.
        let cleaned = urlString.hasPrefix("@") ? String(urlString.dropFirst()) : urlString
        guard
            let url  = URL(string: cleaned),
            let host = url.host,
            host.hasSuffix("spotify.com")
        else { return .invalid }

        // Strip "/" from path components and take the first two meaningful segments.
        let path = url.pathComponents.filter { $0 != "/" }
        guard path.count >= 2 else { return .invalid }

        return kind(type: path[0], id: path[1])
    }

    private static func kind(type: String, id: String) -> SpotifyURLKind {
        guard !id.isEmpty else { return .invalid }
        switch type {
        case "playlist": return .playlist(id: id)
        case "track":    return .track(id: id)
        case "album":    return .album(id: id)
        case "artist":   return .artist(id: id)
        default:         return .invalid  // show, episode, user, etc.
        }
    }
}
