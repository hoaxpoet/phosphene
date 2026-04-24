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
    /// The current playback queue from Spotify (up to 20 tracks).
    case spotifyCurrentQueue(accessToken: String)
    /// An Apple Music playlist URL (catalog or library link).
    case appleMusicPlaylistURL(String)
    /// A Spotify playlist URL with OAuth access token.
    case spotifyPlaylistURL(String, accessToken: String)
}

// MARK: - PlaylistConnectorError

/// Errors surfaced by `PlaylistConnector`.
public enum PlaylistConnectorError: Error, Sendable, Equatable {
    /// Apple Music is not running.
    case appleMusicNotRunning
    /// Spotify credentials are missing or the access token is expired.
    case spotifyAuthRequired
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

// MARK: - PlaylistConnector

/// Reads the full track list from Apple Music or Spotify playlists.
///
/// **Apple Music** — AppleScript enumerates `every track of current playlist`,
/// capturing title, artist, album, duration, and persistent ID. Requires the
/// Automation permission for Music (one-time system prompt).
///
/// **Spotify** — Web API: queue endpoint (`/me/player/queue`, up to 20 tracks)
/// or full playlist endpoint (`/playlists/{id}/tracks`, paginated).
///
/// All external calls are injectable via `appleScriptReader` and
/// `networkFetcher` closures — no real AppleScript or network calls are
/// made in unit tests.
public final class PlaylistConnector: PlaylistConnecting, @unchecked Sendable {

    // MARK: - Injected Dependencies

    /// Override in tests to return canned AppleScript output.
    /// Receives the AppleScript source string; returns the result string or nil.
    /// Defaults to executing real AppleScript via `NSAppleScript`.
    var appleScriptReader: (@Sendable (String) async -> String?)?

    /// Override in tests to return canned HTTP responses.
    /// Receives the `URLRequest`; returns `(Data, URLResponse)` or throws.
    /// Defaults to `urlSession.data(for:)`.
    var networkFetcher: (@Sendable (URLRequest) async throws -> (Data, URLResponse))?

    private let urlSession: URLSession

    // MARK: - Init

    /// Create a playlist connector.
    ///
    /// - Parameter urlSession: URL session for Spotify API calls (default: `.shared`).
    public init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    // MARK: - PlaylistConnecting

    public func connect(source: PlaylistSource) async throws -> [TrackIdentity] {
        switch source {
        case .appleMusicCurrentPlaylist:
            return try await fetchAppleMusicCurrentPlaylist()
        case .spotifyCurrentQueue(let token):
            return try await fetchSpotifyQueue(accessToken: token)
        case .appleMusicPlaylistURL(let urlString):
            return try await fetchAppleMusicPlaylistURL(urlString)
        case .spotifyPlaylistURL(let urlString, let token):
            return try await fetchSpotifyPlaylistURL(urlString, accessToken: token)
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

    // MARK: - Spotify Queue

    private func fetchSpotifyQueue(accessToken: String) async throws -> [TrackIdentity] {
        guard !accessToken.isEmpty else {
            throw PlaylistConnectorError.spotifyAuthRequired
        }

        guard let url = URL(string: "https://api.spotify.com/v1/me/player/queue") else {
            throw PlaylistConnectorError.networkFailure("Invalid Spotify queue URL")
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let data = try await performRequest(request, context: "Spotify queue")
        let tracks = try parseSpotifyQueueData(data)
        logger.info("Spotify queue: loaded \(tracks.count) track(s)")
        return tracks
    }

    private func parseSpotifyQueueData(_ data: Data) throws -> [TrackIdentity] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PlaylistConnectorError.parseFailure("Invalid Spotify queue JSON")
        }
        var raw: [[String: Any]] = []
        if let current = json["currently_playing"] as? [String: Any] {
            raw.append(current)
        }
        if let queue = json["queue"] as? [[String: Any]] {
            raw.append(contentsOf: queue)
        }
        return raw.compactMap(parseSpotifyTrack)
    }

    // MARK: - Spotify Playlist URL

    private func fetchSpotifyPlaylistURL(
        _ urlString: String,
        accessToken: String
    ) async throws -> [TrackIdentity] {
        guard !accessToken.isEmpty else {
            throw PlaylistConnectorError.spotifyAuthRequired
        }
        guard let playlistID = extractSpotifyPlaylistID(from: urlString) else {
            throw PlaylistConnectorError.unrecognizedPlaylistURL(urlString)
        }
        let tracks = try await fetchSpotifyPlaylistTracks(
            playlistID: playlistID,
            accessToken: accessToken
        )
        logger.info("Spotify playlist (\(playlistID)): loaded \(tracks.count) track(s)")
        return tracks
    }

    private func fetchSpotifyPlaylistTracks(
        playlistID: String,
        accessToken: String,
        offset: Int = 0,
        accumulated: [TrackIdentity] = []
    ) async throws -> [TrackIdentity] {
        let urlStr = "https://api.spotify.com/v1/playlists/\(playlistID)/tracks"
            + "?offset=\(offset)&limit=50"
        guard let url = URL(string: urlStr) else {
            throw PlaylistConnectorError.networkFailure("Invalid playlist tracks URL")
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let data = try await performRequest(request, context: "Spotify playlist tracks")

        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let items = json["items"] as? [[String: Any]]
        else {
            throw PlaylistConnectorError.parseFailure("Invalid playlist tracks JSON")
        }

        let batch = items.compactMap { item -> TrackIdentity? in
            guard let track = item["track"] as? [String: Any] else { return nil }
            return parseSpotifyTrack(track)
        }
        let all = accumulated + batch

        // Paginate if the API reports more tracks remain.
        let total = json["total"] as? Int ?? 0
        if all.count < total, !batch.isEmpty {
            return try await fetchSpotifyPlaylistTracks(
                playlistID: playlistID,
                accessToken: accessToken,
                offset: offset + batch.count,
                accumulated: all
            )
        }
        return all
    }

    private func parseSpotifyTrack(_ track: [String: Any]) -> TrackIdentity? {
        guard
            let name = track["name"] as? String, !name.isEmpty,
            let artists = track["artists"] as? [[String: Any]],
            let firstArtist = artists.first,
            let artistName = firstArtist["name"] as? String
        else { return nil }

        let album = (track["album"] as? [String: Any])?["name"] as? String
        let duration = (track["duration_ms"] as? Double).map { $0 / 1000.0 }
        let spotifyID = track["id"] as? String

        return TrackIdentity(
            title: name,
            artist: artistName,
            album: album,
            duration: duration,
            spotifyID: spotifyID
        )
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

    // MARK: - Shared Helpers

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

    /// Perform an authenticated HTTP request, handling common error codes.
    private func performRequest(_ request: URLRequest, context: String) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            if let fetcher = networkFetcher {
                (data, response) = try await fetcher(request)
            } else {
                (data, response) = try await urlSession.data(for: request)
            }
        } catch {
            throw PlaylistConnectorError.networkFailure(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw PlaylistConnectorError.networkFailure("\(context): not an HTTP response")
        }
        switch http.statusCode {
        case 200:
            return data
        case 401:
            throw PlaylistConnectorError.spotifyAuthRequired
        default:
            throw PlaylistConnectorError.networkFailure("\(context): HTTP \(http.statusCode)")
        }
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
