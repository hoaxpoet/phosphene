// SpotifyWebAPIConnector — Fetches Spotify playlist track lists via the Web API.
//
// Uses OAuth (user-level) token via SpotifyOAuthTokenProvider for full playlist access.
// Client-credentials (public playlists only) is supported via DefaultSpotifyTokenProvider.
//
// Endpoint: /v1/playlists/{id}/items (not the deprecated /tracks — deprecated 2024,
// returns 403 for development-mode apps). Per Spotify Web API docs, each PlaylistTrackObject
// uses "item" as the key for the track/episode object; "track" is the deprecated field name.
//
// 401 handling: on a 401 the token is invalidated and the call is retried once.
// A second 401 throws .spotifyAuthFailure immediately.
//
// Status code mapping:
//   200 → success
//   401 → invalidate token, retry once; second 401 → .spotifyAuthFailure
//   403 → .spotifyLoginRequired (client-credentials hitting OAuth-gated endpoint)
//   404 → .spotifyPlaylistNotFound
//   429 → .rateLimited (parses Retry-After if present)
//   other → .networkFailure

import Foundation
import Shared
import os.log

private let logger = Logging.session

// MARK: - SpotifyWebAPIConnecting

/// Reads a Spotify playlist's full track list from the Web API.
public protocol SpotifyWebAPIConnecting: AnyObject, Sendable {
    /// Fetch the ordered track list for the given Spotify playlist ID.
    func connect(playlistID: String) async throws -> [TrackIdentity]

    /// Fetch the current user's player queue (up to 20 tracks).
    func queue(accessToken: String) async throws -> [TrackIdentity]
}

// MARK: - SpotifyWebAPIConnector

/// Default `SpotifyWebAPIConnecting` implementation.
///
/// Injects a `SpotifyTokenProviding` for testability — unit tests supply a
/// stub that returns a canned token without hitting the network.
public final class SpotifyWebAPIConnector: SpotifyWebAPIConnecting, @unchecked Sendable {

    // MARK: - Dependencies

    private let tokenProvider: any SpotifyTokenProviding

    /// Override in tests to return canned HTTP responses.
    var networkFetcher: (@Sendable (URLRequest) async throws -> (Data, URLResponse))?

    private let urlSession: URLSession

    // MARK: - Init

    /// Create a connector.
    ///
    /// - Parameters:
    ///   - tokenProvider: Token provider for client-credentials auth.
    ///   - urlSession: URL session for API calls (default: `.shared`).
    public init(
        tokenProvider: any SpotifyTokenProviding,
        urlSession: URLSession = .shared
    ) {
        self.tokenProvider = tokenProvider
        self.urlSession = urlSession
    }

    /// Convenience factory for the production default.
    ///
    /// If credentials are missing from Info.plist, returns a connector backed by a
    /// stub token provider that throws `.spotifyAuthFailure` on every `acquire()`.
    /// This ensures `PlaylistConnector.init()` is non-throwing while still surfacing
    /// missing-credentials as a real error at connect time rather than silently degrading.
    public static func makeLive(urlSession: URLSession = .shared) -> SpotifyWebAPIConnector {
        if let provider = try? DefaultSpotifyTokenProvider(urlSession: urlSession) {
            return SpotifyWebAPIConnector(tokenProvider: provider, urlSession: urlSession)
        }
        return SpotifyWebAPIConnector(
            tokenProvider: MissingCredentialsTokenProvider(),
            urlSession: urlSession
        )
    }

    // MARK: - SpotifyWebAPIConnecting

    public func connect(playlistID: String) async throws -> [TrackIdentity] {
        let token = try await tokenProvider.acquire()
        let tracks = try await fetchPlaylistTracks(playlistID: playlistID, token: token, retried: false)
        logger.info("Spotify playlist (\(playlistID)): loaded \(tracks.count) track(s)")
        return tracks
    }

    public func queue(accessToken: String) async throws -> [TrackIdentity] {
        guard let url = URL(string: "https://api.spotify.com/v1/me/player/queue") else {
            throw PlaylistConnectorError.networkFailure("Invalid Spotify queue URL")
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let data = try await performRequest(request, context: "Spotify queue", token: accessToken, retried: true)
        let tracks = try parseQueueData(data)
        logger.info("Spotify queue: loaded \(tracks.count) track(s)")
        return tracks
    }

    // MARK: - Playlist Fetch

    private func fetchPlaylistTracks(
        playlistID: String,
        token: String,
        retried: Bool
    ) async throws -> [TrackIdentity] {
        // Paginate using the `next` URL returned by the API.
        var accumulated: [TrackIdentity] = []
        var nextURL: URL? = makeTracksURL(playlistID: playlistID, offset: 0)
        var currentToken = token

        while let url = nextURL {
            var request = URLRequest(url: url)
            request.setValue("Bearer \(currentToken)", forHTTPHeaderField: "Authorization")

            let data: Data
            do {
                data = try await performRequest(request,
                    context: "Spotify playlist tracks",
                    token: currentToken,
                    retried: retried)
            } catch PlaylistConnectorError.spotifyAuthFailure where !retried {
                // Token was invalidated inside performRequest; acquire a fresh one and retry.
                currentToken = try await tokenProvider.acquire()
                return try await fetchPlaylistTracks(
                    playlistID: playlistID, token: currentToken, retried: true
                )
            }

            guard
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let items = json["items"] as? [[String: Any]]
            else {
                let preview = String(data: data.prefix(500), encoding: .utf8) ?? "<binary>"
                logger.error("Spotify /items parse failure. Response preview: \(preview)")
                throw PlaylistConnectorError.parseFailure("Invalid playlist tracks JSON")
            }

            let batch = items.compactMap { item -> TrackIdentity? in
                // Per Spotify Web API docs: the current key is "item" (TrackObject|EpisodeObject).
                // The "track" key is deprecated but retained as a fallback for backward compatibility.
                let trackObj = (item["item"] as? [String: Any]) ?? (item["track"] as? [String: Any])
                guard let track = trackObj else { return nil }
                return parseTrack(track)
            }
            logger.info("Spotify /items page: \(batch.count) tracks parsed from \(items.count) items")
            accumulated.append(contentsOf: batch)

            // Follow `next` URL if the API provides one.
            if let nextStr = json["next"] as? String, let nextParsed = URL(string: nextStr) {
                nextURL = nextParsed
            } else {
                nextURL = nil
            }
        }
        return accumulated
    }

    private func makeTracksURL(playlistID: String, offset: Int) -> URL? {
        // Use /items (not the deprecated /tracks) — Spotify deprecated /tracks in 2024.
        // Note on `fields`: field filtering is intentionally omitted. The /items endpoint
        // silently omits items whose `track` field is null when a fields filter is applied,
        // causing compactMap to produce an empty array even for valid playlists.
        // `market=from_token` is required: without it the API can return null track objects
        // for region-restricted content, also silently dropping items.
        var comps = URLComponents(string: "https://api.spotify.com/v1/playlists/\(playlistID)/items")
        comps?.queryItems = [
            URLQueryItem(name: "market", value: "from_token"),
            URLQueryItem(name: "limit", value: "100"),
            URLQueryItem(name: "offset", value: "\(offset)")
        ]
        return comps?.url
    }

    // MARK: - HTTP Layer

    /// Perform a request, mapping HTTP status codes to typed errors.
    ///
    /// - Parameters:
    ///   - retried: `true` if this is already a retry; prevents double-invalidate loops.
    private func performRequest(
        _ request: URLRequest,
        context: String,
        token: String,
        retried: Bool
    ) async throws -> Data {
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
            throw PlaylistConnectorError.networkFailure("\(context): non-HTTP response")
        }

        switch http.statusCode {
        case 200:
            return data
        case 401:
            await tokenProvider.invalidate()
            // Signal to callers that they should acquire a fresh token and retry once.
            throw PlaylistConnectorError.spotifyAuthFailure("401 from \(context)")
        case 403:
            let body = String(data: data, encoding: .utf8) ?? "<unreadable>"
            logger.error("Spotify 403 body: \(body)")
            // As of late 2024, Spotify's playlist endpoints require user-level OAuth.
            // A 403 from a client-credentials token means the endpoint needs OAuth scope;
            // surface .spotifyLoginRequired so the VM can prompt the user to log in.
            // If a user-level OAuth token is in use, 403 means genuinely private playlist
            // and callers should map this to .spotifyPlaylistInaccessible instead.
            // Token providers that perform OAuth should override this by catching the error
            // and rethrowing as .spotifyPlaylistInaccessible when authenticated.
            throw PlaylistConnectorError.spotifyLoginRequired
        case 404:
            throw PlaylistConnectorError.spotifyPlaylistNotFound
        case 429:
            let retryAfter = (http.value(forHTTPHeaderField: "Retry-After"))
                .flatMap(Double.init) ?? 1.0
            throw PlaylistConnectorError.rateLimited(retryAfterSeconds: retryAfter)
        default:
            throw PlaylistConnectorError.networkFailure("\(context): HTTP \(http.statusCode)")
        }
    }

    // MARK: - Parsing

    private func parseQueueData(_ data: Data) throws -> [TrackIdentity] {
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
        return raw.compactMap(parseTrack)
    }

    private func parseTrack(_ track: [String: Any]) -> TrackIdentity? {
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
}
