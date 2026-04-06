// SpotifyFetcher — Queries Spotify Web API for track audio features.
// Requires client_id and client_secret (client credentials flow).
// Audio features endpoint is deprecated for apps created after Nov 2024 —
// this fetcher gracefully degrades, returning search-derived data only.

import Foundation
import Shared
import os.log

private let logger = Logging.metadata

// MARK: - SpotifyFetcher

/// Fetches track metadata from the Spotify Web API.
///
/// Uses the Client Credentials flow for server-to-server auth.
/// Searches for the track, then attempts to fetch audio features
/// (BPM, key, energy, valence, danceability). If audio features
/// return 403 (deprecated for newer apps), returns search data only.
public final class SpotifyFetcher: MetadataFetching, @unchecked Sendable {

    public let sourceName = "Spotify"

    private let clientID: String
    private let clientSecret: String

    /// Cached access token and expiry.
    private var accessToken: String?
    private var tokenExpiry: Date = .distantPast
    private let lock = NSLock()

    /// Musical key names for Spotify's pitch class notation.
    private static let keyNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

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
        // Authenticate.
        guard let token = await getAccessToken() else {
            logger.debug("Spotify: failed to obtain access token")
            return nil
        }

        // Search for the track.
        guard let trackID = await searchTrack(title: title, artist: artist, token: token) else {
            logger.debug("Spotify: track not found — \(title) by \(artist)")
            return nil
        }

        // Fetch audio features (may 403 on newer apps).
        let features = await fetchAudioFeatures(trackID: trackID, token: token)

        if let features {
            logger.debug("Spotify: full audio features for \(title)")
            return features
        }

        logger.debug("Spotify: audio features unavailable, returning search-only data")
        return nil
    }

    // MARK: - Authentication

    private func getAccessToken() async -> String? {
        // Check cached token.
        let cached = lock.withLock { () -> String? in
            if let token = accessToken, tokenExpiry > Date() {
                return token
            }
            return nil
        }
        if let cached { return cached }

        // Request new token via client credentials flow.
        guard let url = URL(string: "https://accounts.spotify.com/api/token") else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let credentials = "\(clientID):\(clientSecret)"
        guard let credData = credentials.data(using: .utf8) else { return nil }
        let base64 = credData.base64EncodedString()
        request.setValue("Basic \(base64)", forHTTPHeaderField: "Authorization")
        request.httpBody = "grant_type=client_credentials".data(using: .utf8)

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

    private func searchTrack(title: String, artist: String, token: String) async -> String? {
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
            return searchResponse.tracks.items.first?.id
        } catch {
            logger.debug("Spotify: search error — \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Audio Features

    private func fetchAudioFeatures(trackID: String, token: String) async -> PartialTrackProfile? {
        guard let url = URL(string: "https://api.spotify.com/v1/audio-features/\(trackID)") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return nil }

            // 403 = deprecated endpoint for newer apps. Graceful degradation.
            if httpResponse.statusCode == 403 {
                logger.info("Spotify: audio-features endpoint returned 403 (deprecated for this app)")
                return nil
            }

            guard httpResponse.statusCode == 200 else { return nil }

            let features = try JSONDecoder().decode(SpotifyAudioFeatures.self, from: data)

            let keyName: String?
            if features.key >= 0, features.key < Self.keyNames.count {
                let modeName = features.mode == 1 ? "major" : "minor"
                keyName = "\(Self.keyNames[features.key]) \(modeName)"
            } else {
                keyName = nil
            }

            return PartialTrackProfile(
                bpm: features.tempo,
                key: keyName,
                energy: features.energy,
                valence: features.valence,
                danceability: features.danceability,
                duration: Double(features.durationMs) / 1000.0
            )
        } catch {
            logger.debug("Spotify: audio-features error — \(error.localizedDescription)")
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
}

private struct SpotifyAudioFeatures: Decodable {
    let danceability: Float
    let energy: Float
    let key: Int
    let mode: Int
    let valence: Float
    let tempo: Float
    let durationMs: Int

    enum CodingKeys: String, CodingKey {
        case danceability, energy, key, mode, valence, tempo
        case durationMs = "duration_ms"
    }
}
