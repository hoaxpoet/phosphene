// MetadataParsingRegressionTests — Golden JSON fixture tests for external API response parsing.
// Ensures that response parsing remains stable across code changes.

import Testing
import Foundation
@testable import Audio
@testable import Shared

@Suite("MetadataParsingRegression")
struct MetadataParsingRegressionTests {

    // MARK: - MusicBrainz Response Parsing

    /// Response format for MusicBrainz recording search.
    private struct MusicBrainzResponse: Decodable {
        struct Recording: Decodable {
            let title: String
            let length: Int?
            struct ArtistCredit: Decodable {
                struct Artist: Decodable {
                    let name: String
                }
                let artist: Artist
            }
            let artistCredit: [ArtistCredit]?
            struct Tag: Decodable {
                let name: String
                let count: Int
            }
            let tags: [Tag]?

            enum CodingKeys: String, CodingKey {
                case title, length, tags
                case artistCredit = "artist-credit"
            }
        }
        let recordings: [Recording]
    }

    /// Parse a MusicBrainz recording response into a PartialTrackProfile.
    private func parseMusicBrainz(_ data: Data) throws -> PartialTrackProfile? {
        let decoder = JSONDecoder()
        let response = try decoder.decode(MusicBrainzResponse.self, from: data)
        guard let recording = response.recordings.first else { return nil }

        let duration = recording.length.map { Double($0) / 1000.0 }
        let tags = recording.tags?.sorted(by: { $0.count > $1.count }).map(\.name) ?? []

        return PartialTrackProfile(
            genreTags: tags,
            duration: duration
        )
    }

    @Test func parseMusicBrainzResponse_knownJSON_matchesExpected() throws {
        let fixtureURL = Bundle.module.url(
            forResource: "musicbrainz_recording",
            withExtension: "json",
            subdirectory: "Fixtures"
        )
        let data = try Data(contentsOf: try #require(fixtureURL))

        let profile = try #require(try parseMusicBrainz(data))

        // Duration: 354947ms = 354.947s
        #expect(profile.duration != nil)
        let duration = try #require(profile.duration)
        #expect(abs(duration - 354.947) < 0.001)

        // Genre tags should be sorted by count (descending).
        #expect(profile.genreTags == ["rock", "classic rock", "progressive rock"])
    }

    // MARK: - Spotify Audio Features Parsing

    /// Response format for Spotify Audio Features endpoint.
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

    /// Musical key names for Spotify's pitch class notation.
    private static let keyNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    /// Parse a Spotify Audio Features response into a PartialTrackProfile.
    private func parseSpotifyAudioFeatures(_ data: Data) throws -> PartialTrackProfile? {
        let decoder = JSONDecoder()
        let features = try decoder.decode(SpotifyAudioFeatures.self, from: data)

        let keyName = Self.keyNames[features.key]
        let modeName = features.mode == 1 ? "major" : "minor"

        return PartialTrackProfile(
            bpm: features.tempo,
            key: "\(keyName) \(modeName)",
            energy: features.energy,
            valence: features.valence,
            danceability: features.danceability,
            duration: Double(features.durationMs) / 1000.0
        )
    }

    @Test func parseSpotifyAudioFeatures_knownJSON_matchesExpected() throws {
        let fixtureURL = Bundle.module.url(
            forResource: "spotify_audio_features",
            withExtension: "json",
            subdirectory: "Fixtures"
        )
        let data = try Data(contentsOf: try #require(fixtureURL))

        let profile = try #require(try parseSpotifyAudioFeatures(data))

        // BPM
        #expect(profile.bpm != nil)
        let bpm = try #require(profile.bpm)
        #expect(abs(bpm - 71.105) < 0.001)

        // Key: pitch class 0 = C, mode 1 = major
        #expect(profile.key == "C major")

        // Energy
        #expect(profile.energy != nil)
        let energy = try #require(profile.energy)
        #expect(abs(energy - 0.402) < 0.001)

        // Valence
        #expect(profile.valence != nil)
        let valence = try #require(profile.valence)
        #expect(abs(valence - 0.228) < 0.001)

        // Danceability
        #expect(profile.danceability != nil)
        let danceability = try #require(profile.danceability)
        #expect(abs(danceability - 0.404) < 0.001)

        // Duration: 354947ms = 354.947s
        #expect(profile.duration != nil)
        let duration = try #require(profile.duration)
        #expect(abs(duration - 354.947) < 0.001)
    }
}
