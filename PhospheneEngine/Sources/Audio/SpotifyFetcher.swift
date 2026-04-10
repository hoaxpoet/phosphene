// SpotifyFetcher — Queries Spotify Web API for track matching.
// Uses search endpoint only — audio features endpoint is deprecated
// (403 for apps created after Nov 2024). Returns duration from search.
// Requires client_id and client_secret (client credentials flow).

import Foundation
import Shared
import os.log

private let logger = Logging.metadata

// MARK: - SpotifyFetcher

/// Fetches track metadata from the Spotify Web API search endpoint.
///
/// Uses the Client Credentials flow for server-to-server auth.
/// Searches for the track and returns duration from the search result.
/// Audio features (BPM, key, energy, etc.) are NOT fetched — that
/// endpoint was deprecated in Nov 2024. Self-computed MIR (Increment 2.4)
/// provides these features instead.
public final class SpotifyFetcher: MetadataFetching, @unchecked Sendable {

    public let sourceName = "Spotify"

    private let clientID: String
    private let clientSecret: String

    /// Cached access token and expiry.
    private var accessToken: String?
    private var tokenExpiry: Date = .distantPast
    private let lock = NSLock()

    // MARK: - Init

    /// Create a Spotify fetcher.
    ///
    /// - Parameters:
    ///   - clientID: Spotify app client ID.
    ///   - clientSecret: Spotify app client secret.
    public init(clientID: String, clientSecret: String) {
        self.clientID = clientID
        self.clientSecret = clientSecret
    }

    /// Create a Spotify fetcher from environment variables.
    /// Returns nil if SPOTIFY_CLIENT_ID or SPOTIFY_CLIENT_SECRET are not set.
    public static func fromEnvironment() -> SpotifyFetcher? {
        guard let id = ProcessInfo.processInfo.environment["SPOTIFY_CLIENT_ID"],
              let secret = ProcessInfo.processInfo.environment["SPOTIFY_CLIENT_SECRET"],
              !id.isEmpty, !secret.isEmpty else {
            logger.info("Spotify credentials not found in environment (SPOTIFY_CLIENT_ID / SPOTIFY_CLIENT_SECRET)")
            return nil
        }
        return SpotifyFetcher(clientID: id, clientSecret: secret)
    }

    // MARK: - MetadataFetching

    public func fetch(title: String, artist: String) async -> PartialTrackProfile? {
        guard let token = await getAccessToken() else {
            logger.debug("Spotify: failed to obtain access token")
            return nil
        }

        guard let result = await searchTrack(title: title, artist: artist, token: token) else {
            logger.debug("Spotify: track not found — \(title) by \(artist)")
            return nil
        }

        logger.debug("Spotify: matched \(title) by \(artist)")

        return PartialTrackProfile(
            duration: result.durationMs.map { Double($0) / 1000.0 }
        )
    }

    // MARK: - Authentication

    private func getAccessToken() async -> String? {
        let cached = lock.withLock { () -> String? in
            if let token = accessToken, tokenExpiry > Date() {
                return token
            }
            return nil
        }
        if let cached { return cached }

        guard let url = URL(string: "https://accounts.spotify.com/api/token") else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let credentials = "\(clientID):\(clientSecret)"
        guard let credData = credentials.data(using: .utf8) else { return nil }
        let base64 = credData.base64EncodedString()
        request.setValue("Basic \(base64)", forHTTPHeaderField: "Authorization")
        request.httpBody = Data("grant_type=client_credentials".utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                logger.debug("Spotify: auth failed")
                return nil
            }

            let tokenResponse = try JSONDecoder().decode(SpotifyTokenResponse.self, from: data)
            lock.withLock {
                accessToken = tokenResponse.accessToken
                tokenExpiry = Date().addingTimeInterval(Double(tokenResponse.expiresIn - 60))
            }
            return tokenResponse.accessToken
        } catch {
            logger.debug("Spotify: auth error — \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Search

    private func searchTrack(title: String, artist: String, token: String) async -> SpotifyTrack? {
        let query = "track:\(title) artist:\(artist)"
        var components = URLComponents(string: "https://api.spotify.com/v1/search")
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "type", value: "track"),
            URLQueryItem(name: "limit", value: "1"),
        ]

        guard let url = components?.url else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return nil }

            let searchResponse = try JSONDecoder().decode(SpotifySearchResponse.self, from: data)
            return searchResponse.tracks.items.first
        } catch {
            logger.debug("Spotify: search error — \(error.localizedDescription)")
            return nil
        }
    }
}

// MARK: - Spotify Response Types

private struct SpotifyTokenResponse: Decodable {
    let accessToken: String
    let tokenType: String
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
    }
}

private struct SpotifySearchResponse: Decodable {
    let tracks: SpotifyTrackList
}

private struct SpotifyTrackList: Decodable {
    let items: [SpotifyTrack]
}

private struct SpotifyTrack: Decodable {
    let id: String
    let durationMs: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case durationMs = "duration_ms"
    }
}
