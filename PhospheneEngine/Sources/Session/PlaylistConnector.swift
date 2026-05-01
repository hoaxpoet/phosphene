// PlaylistConnector — Reads the full track list from Apple Music or Spotify.
// Outputs an ordered [TrackIdentity] for every source type.
// All external calls (AppleScript, network) are injectable for testing.

import AppKit
import Foundation
import Shared
import os.log

private let logger = Logging.session

// MARK: - PlaylistSource

/// The source of a playlist connection request.
public enum PlaylistSource: Sendable {
    /// The currently loaded playlist in the Apple Music app.
    case appleMusicCurrentPlaylist
    /// The current playback queue from Spotify (up to 20 tracks via player API).
    case spotifyCurrentQueue
    /// An Apple Music playlist URL (catalog or library link).
    case appleMusicPlaylistURL(String)
    /// A Spotify playlist URL. Client-credentials auth is handled internally.
    case spotifyPlaylistURL(String)
}

// MARK: - PlaylistConnectorError

/// Errors surfaced by `PlaylistConnector` and `SpotifyWebAPIConnector`.
public enum PlaylistConnectorError: Error, Sendable, Equatable {
    /// Apple Music is not running.
    case appleMusicNotRunning
    /// Spotify client credentials are missing, invalid, or rejected by the token endpoint.
    case spotifyAuthFailure(String)
    /// The Spotify API requires the user to complete OAuth login (user-level scope needed).
    /// The token provider has no valid access token and no refresh token to exchange.
    case spotifyLoginRequired
    /// The Spotify playlist is private or otherwise inaccessible (HTTP 403).
    case spotifyPlaylistInaccessible
    /// The Spotify playlist was not found (HTTP 404).
    case spotifyPlaylistNotFound
    /// Spotify rate limit hit; `retryAfterSeconds` from the Retry-After header (or 1.0).
    case rateLimited(retryAfterSeconds: Double)
    /// The provided URL is not a recognized Apple Music or Spotify format.
    case unrecognizedPlaylistURL(String)
    /// A network request failed.
    case networkFailure(String)
    /// The API response could not be parsed.
    case parseFailure(String)
}

// MARK: - PlaylistConnecting

/// Protocol for reading an ordered track list from a music source.
///
/// Conforming types return an ordered `[TrackIdentity]` array for a given
/// `PlaylistSource`. Duplicate tracks preserve their playlist order.
public protocol PlaylistConnecting: AnyObject, Sendable {
    /// Connect to the given source and return an ordered list of track identities.
    ///
    /// - Parameter source: The playlist source to connect to.
    /// - Returns: An ordered array of `TrackIdentity` values. Returns an empty
    ///   array if the playlist exists but contains no tracks.
    /// - Throws: `PlaylistConnectorError` on configuration or network failure.
    func connect(source: PlaylistSource) async throws -> [TrackIdentity]
}

// MARK: - PlaylistSource + Display

extension PlaylistSource {
    /// Short user-facing name for the music source used in `ReadyView` headlines.
    public var displayName: String {
        switch self {
        case .appleMusicCurrentPlaylist, .appleMusicPlaylistURL:
            return "Apple Music"
        case .spotifyCurrentQueue, .spotifyPlaylistURL:
            return "Spotify"
        }
    }
}

// MARK: - Connectors directory

// SpotifyTokenProvider and SpotifyWebAPIConnector live in the Connectors/ subdirectory:
//   Sources/Session/Connectors/SpotifyTokenProvider.swift
//   Sources/Session/Connectors/SpotifyWebAPIConnector.swift

// MARK: - PlaylistConnector

/// Reads the full track list from Apple Music or Spotify playlists.
///
/// **Apple Music** — AppleScript enumerates `every track of current playlist`,
/// capturing title, artist, album, duration, and persistent ID. Requires the
/// Automation permission for Music (one-time system prompt).
///
/// **Spotify** — delegates to `SpotifyWebAPIConnector`, which handles
/// client-credentials auth, pagination, and all Spotify-specific error mapping.
///
/// `appleScriptReader` is injectable for tests — no real AppleScript is executed
/// in unit tests. Spotify I/O is injectable via `SpotifyWebAPIConnector.networkFetcher`.
public final class PlaylistConnector: PlaylistConnecting, @unchecked Sendable {

    // MARK: - Dependencies

    /// Override in tests to return canned AppleScript output.
    var appleScriptReader: (@Sendable (String) async -> String?)?

    private let spotifyConnector: any SpotifyWebAPIConnecting

    // MARK: - Init

    /// Create a playlist connector.
    ///
    /// - Parameter spotifyConnector: Spotify Web API connector (default: live impl).
    public init(spotifyConnector: any SpotifyWebAPIConnecting = SpotifyWebAPIConnector.makeLive()) {
        self.spotifyConnector = spotifyConnector
    }

    // MARK: - PlaylistConnecting

    public func connect(source: PlaylistSource) async throws -> [TrackIdentity] {
        switch source {
        case .appleMusicCurrentPlaylist:
            return try await fetchAppleMusicCurrentPlaylist()
        case .appleMusicPlaylistURL(let urlString):
            return try await fetchAppleMusicPlaylistURL(urlString)
        case .spotifyCurrentQueue:
            throw PlaylistConnectorError.networkFailure(
                "Spotify queue requires an active OAuth session (v2 feature)"
            )
        case .spotifyPlaylistURL(let urlString):
            guard let playlistID = extractSpotifyPlaylistID(from: urlString) else {
                throw PlaylistConnectorError.unrecognizedPlaylistURL(urlString)
            }
            return try await spotifyConnector.connect(playlistID: playlistID)
        }
    }

    // MARK: - Apple Music

    private func fetchAppleMusicCurrentPlaylist() async throws -> [TrackIdentity] {
        guard isAppRunning("com.apple.Music") else {
            logger.info("Apple Music is not running")
            throw PlaylistConnectorError.appleMusicNotRunning
        }

        // Enumerate tracks and join with linefeed so field separators ("||")
        // never collide with the track separator.
        let script = """
        tell application "Music"
            set trackList to {}
            repeat with t in (get every track of current playlist)
                set trackInfo to (get name of t) & "||" & ¬
                    (get artist of t) & "||" & ¬
                    (get album of t) & "||" & ¬
                    ((get duration of t) as text) & "||" & ¬
                    (get persistent ID of t)
                set end of trackList to trackInfo
            end repeat
            set AppleScript's text item delimiters to linefeed
            set result to trackList as text
            set AppleScript's text item delimiters to ""
            return result
        end tell
        """

        let output = await executeAppleScript(script)
        guard let output, !output.isEmpty else {
            logger.debug("Apple Music playlist: no tracks returned")
            return []
        }

        let tracks = parseAppleMusicOutput(output)
        logger.info("Apple Music playlist: loaded \(tracks.count) track(s)")
        return tracks
    }

    private func parseAppleMusicOutput(_ output: String) -> [TrackIdentity] {
        output
            .components(separatedBy: "\n")
            .filter { !$0.isEmpty }
            .compactMap { line -> TrackIdentity? in
                let parts = line.components(separatedBy: "||")
                guard parts.count >= 4 else { return nil }
                let title  = parts[0].trimmingCharacters(in: .whitespaces)
                let artist = parts[1].trimmingCharacters(in: .whitespaces)
                let album  = parts[2].trimmingCharacters(in: .whitespaces)
                let durStr = parts[3].trimmingCharacters(in: .whitespaces)
                let pid    = parts.count >= 5
                    ? parts[4].trimmingCharacters(in: .whitespaces)
                    : nil
                guard !title.isEmpty, !artist.isEmpty else { return nil }
                return TrackIdentity(
                    title: title,
                    artist: artist,
                    album: album.isEmpty ? nil : album,
                    duration: Double(durStr),
                    appleMusicID: pid?.isEmpty == false ? pid : nil
                )
            }
    }

    // MARK: - Apple Music Playlist URL

    private func fetchAppleMusicPlaylistURL(_ urlString: String) async throws -> [TrackIdentity] {
        // URL-based Apple Music catalog lookup requires a MusicKit entitlement —
        // deferred to Phase 4. Validate the URL format early, then fall back to
        // the current playlist so the path is not a silent no-op.
        guard urlString.contains("music.apple.com") else {
            throw PlaylistConnectorError.unrecognizedPlaylistURL(urlString)
        }
        logger.info("Apple Music URL playlist: falling back to current playlist (MusicKit deferred)")
        return try await fetchAppleMusicCurrentPlaylist()
    }

    // MARK: - Helpers

    private func isAppRunning(_ bundleID: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleID }
    }

    private func executeAppleScript(_ source: String) async -> String? {
        if let reader = appleScriptReader {
            return await reader(source)
        }
        return await Task.detached(priority: .userInitiated) {
            guard let script = NSAppleScript(source: source) else { return nil }
            var errorDict: NSDictionary?
            let result = script.executeAndReturnError(&errorDict)
            if let errorDict {
                let code = errorDict[NSAppleScript.errorNumber] as? Int ?? 0
                // -600 = app not running, -1728 = no current track — both expected.
                if code != -600 && code != -1728 {
                    let msg = errorDict[NSAppleScript.errorMessage] as? String ?? "unknown"
                    logger.debug("AppleScript error (\(code)): \(msg)")
                }
                return nil
            }
            return result.stringValue
        }.value
    }

    private func extractSpotifyPlaylistID(from urlString: String) -> String? {
        guard
            let url = URL(string: urlString),
            url.host?.contains("spotify.com") == true
        else { return nil }
        let parts = url.pathComponents
        guard
            let idx = parts.firstIndex(of: "playlist"),
            parts.index(after: idx) < parts.endIndex
        else { return nil }
        return parts[parts.index(after: idx)]
    }
}
