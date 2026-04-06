// MusicBrainzFetcher — Queries MusicBrainz recording search API.
// Free API, no authentication required. Returns genre tags and duration.
// Rate limit: 1 request/second with a descriptive User-Agent.

import Foundation
import Shared
import os.log

private let logger = Logging.metadata

// MARK: - MusicBrainzFetcher

/// Fetches track metadata from the MusicBrainz recording search API.
///
/// MusicBrainz is a free, community-maintained music database. The API
/// requires a descriptive User-Agent header but no authentication.
/// Returns genre tags and track duration.
public final class MusicBrainzFetcher: MetadataFetching, Sendable {

    public let sourceName = "MusicBrainz"

    /// Base URL for MusicBrainz API v2.
    private static let baseURL = "https://musicbrainz.org/ws/2"

    /// User-Agent required by MusicBrainz API policy.
    private static let userAgent = "Phosphene/1.0 (https://github.com/hoaxpoet/phosphene)"

    public init() {}

    // MARK: - MetadataFetching

    public func fetch(title: String, artist: String) async -> PartialTrackProfile? {
        guard let url = buildSearchURL(title: title, artist: artist) else {
            logger.debug("MusicBrainz: failed to build search URL")
            return nil
        }

        do {
            var request = URLRequest(url: url)
            request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                logger.debug("MusicBrainz: non-200 response")
                return nil
            }

            return parseResponse(data)
        } catch {
            logger.debug("MusicBrainz: request failed — \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - URL Building

    private func buildSearchURL(title: String, artist: String) -> URL? {
        // Lucene query: recording:"title" AND artist:"artist"
        let query = "recording:\"\(title)\" AND artist:\"\(artist)\""
        var components = URLComponents(string: "\(Self.baseURL)/recording")
        components?.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "fmt", value: "json"),
            URLQueryItem(name: "limit", value: "1"),
        ]
        return components?.url
    }

    // MARK: - Response Parsing

    private func parseResponse(_ data: Data) -> PartialTrackProfile? {
        do {
            let response = try JSONDecoder().decode(MBRecordingResponse.self, from: data)
            guard let recording = response.recordings.first else {
                logger.debug("MusicBrainz: no recordings found")
                return nil
            }

            let duration = recording.length.map { Double($0) / 1000.0 }
            let tags = recording.tags?
                .sorted { $0.count > $1.count }
                .map(\.name) ?? []

            logger.debug("MusicBrainz: found \(recording.title) with \(tags.count) tags")

            return PartialTrackProfile(
                genreTags: tags,
                duration: duration
            )
        } catch {
            logger.debug("MusicBrainz: JSON parse failed — \(error.localizedDescription)")
            return nil
        }
    }
}

// MARK: - MusicBrainz Response Types

private struct MBRecordingResponse: Decodable {
    let recordings: [MBRecording]
}

private struct MBRecording: Decodable {
    let title: String
    let length: Int?
    let tags: [MBTag]?

    enum CodingKeys: String, CodingKey {
        case title, length, tags
    }
}

private struct MBTag: Decodable {
    let name: String
    let count: Int
}
