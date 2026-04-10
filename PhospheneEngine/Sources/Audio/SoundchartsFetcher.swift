// SoundchartsFetcher — Queries Soundcharts API for track audio features.
// Optional commercial API — best drop-in replacement for deprecated
// Spotify Audio Features. Gated behind SOUNDCHARTS_APP_ID and
// SOUNDCHARTS_API_KEY environment variables.

import Foundation
import Shared
import os.log

private let logger = Logging.metadata

// MARK: - SoundchartsFetcher

/// Fetches track audio features from the Soundcharts API.
///
/// Soundcharts provides BPM, key, energy, valence, danceability, and more.
/// Commercial API — requires app ID and API key. Optional: the pre-fetch
/// layer works without it (MusicBrainz provides genre tags, self-computed
/// MIR provides audio features from Increment 2.4 onward).
public final class SoundchartsFetcher: MetadataFetching, Sendable {

    public let sourceName = "Soundcharts"

    private let appID: String
    private let apiKey: String

    /// Base URL for Soundcharts API.
    private static let baseURL = "https://customer.api.soundcharts.com"

    /// Musical key names for pitch class notation.
    private static let keyNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    // MARK: - Init

    /// Create a Soundcharts fetcher.
    ///
    /// - Parameters:
    ///   - appID: Soundcharts app ID (x-app-id header).
    ///   - apiKey: Soundcharts API key (x-api-key header).
    public init(appID: String, apiKey: String) {
        self.appID = appID
        self.apiKey = apiKey
    }

    /// Create a Soundcharts fetcher from environment variables.
    /// Returns nil if SOUNDCHARTS_APP_ID or SOUNDCHARTS_API_KEY are not set.
    public static func fromEnvironment() -> SoundchartsFetcher? {
        guard let appID = ProcessInfo.processInfo.environment["SOUNDCHARTS_APP_ID"],
              let apiKey = ProcessInfo.processInfo.environment["SOUNDCHARTS_API_KEY"],
              !appID.isEmpty, !apiKey.isEmpty else {
            logger.info("Soundcharts credentials not found (SOUNDCHARTS_APP_ID / SOUNDCHARTS_API_KEY)")
            return nil
        }
        return SoundchartsFetcher(appID: appID, apiKey: apiKey)
    }

    // MARK: - MetadataFetching

    public func fetch(title: String, artist: String) async -> PartialTrackProfile? {
        // Search for the song UUID.
        guard let uuid = await searchSong(title: title, artist: artist) else {
            logger.debug("Soundcharts: song not found — \(title) by \(artist)")
            return nil
        }

        // Fetch song metadata (includes audio features).
        guard let profile = await fetchSongMetadata(uuid: uuid) else {
            logger.debug("Soundcharts: metadata fetch failed for \(uuid)")
            return nil
        }

        logger.debug("Soundcharts: fetched audio features for \(title)")
        return profile
    }

    // MARK: - Search

    private func searchSong(title: String, artist: String) async -> String? {
        let query = "\(title) \(artist)"
        var components = URLComponents(string: "\(Self.baseURL)/api/v2/search/songs")
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: "1"),
        ]

        guard let url = components?.url else { return nil }

        var request = URLRequest(url: url)
        request.setValue(appID, forHTTPHeaderField: "x-app-id")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return nil }

            let searchResponse = try JSONDecoder().decode(SCSearchResponse.self, from: data)
            return searchResponse.items.first?.uuid
        } catch {
            logger.debug("Soundcharts: search error — \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Song Metadata

    private func fetchSongMetadata(uuid: String) async -> PartialTrackProfile? {
        guard let url = URL(string: "\(Self.baseURL)/api/v2.25/song/\(uuid)") else { return nil }

        var request = URLRequest(url: url)
        request.setValue(appID, forHTTPHeaderField: "x-app-id")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 403 {
                    logger.info("Soundcharts: 403 — audio features not in current plan")
                }
                return nil
            }

            let songResponse = try JSONDecoder().decode(SCSongResponse.self, from: data)
            let song = songResponse.object

            let keyName: String?
            if let keyVal = song.audioFeatures?.key, keyVal >= 0, keyVal < Self.keyNames.count {
                let modeName = song.audioFeatures?.mode == 1 ? "major" : "minor"
                keyName = "\(Self.keyNames[keyVal]) \(modeName)"
            } else {
                keyName = nil
            }

            return PartialTrackProfile(
                bpm: song.audioFeatures?.tempo,
                key: keyName,
                energy: song.audioFeatures?.energy,
                valence: song.audioFeatures?.valence,
                danceability: song.audioFeatures?.danceability
            )
        } catch {
            logger.debug("Soundcharts: metadata error — \(error.localizedDescription)")
            return nil
        }
    }
}

// MARK: - Soundcharts Response Types

private struct SCSearchResponse: Decodable {
    let items: [SCSearchItem]
}

private struct SCSearchItem: Decodable {
    let uuid: String
}

private struct SCSongResponse: Decodable {
    let object: SCSong
}

private struct SCSong: Decodable {
    let audioFeatures: SCAudioFeatures?

    enum CodingKeys: String, CodingKey {
        case audioFeatures
    }
}

private struct SCAudioFeatures: Decodable {
    let tempo: Float?
    let key: Int?
    let mode: Int?
    let energy: Float?
    let valence: Float?
    let danceability: Float?
}
