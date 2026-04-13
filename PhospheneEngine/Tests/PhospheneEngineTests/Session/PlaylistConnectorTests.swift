// PlaylistConnectorTests — Unit tests for PlaylistConnector.
// All external calls (AppleScript, network) are injected via closures.
// No real Apple Music, Spotify, or network access required.

import Testing
import Foundation
@testable import Session

// MARK: - Helpers

private func makeConnector() -> PlaylistConnector {
    PlaylistConnector()
}

/// Build a minimal Spotify track JSON object.
private func spotifyTrack(
    name: String,
    artist: String,
    album: String = "Album",
    durationMs: Double = 240_000,
    id: String = "abc123"
) -> [String: Any] {
    [
        "name": name,
        "artists": [["name": artist, "id": "artist_\(artist)"]],
        "album": ["name": album],
        "duration_ms": durationMs,
        "id": id
    ]
}

/// Encode a JSON object to `Data`, failing the test on error.
private func jsonData(_ object: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: object)
}

/// Build a 200 OK HTTP response for the given URL string.
private func ok200(_ urlString: String) -> HTTPURLResponse {
    // swiftlint:disable:next force_unwrapping
    HTTPURLResponse(url: URL(string: urlString)!, statusCode: 200, httpVersion: nil, headerFields: nil)!
}

// MARK: - Suite

@Suite("PlaylistConnector")
struct PlaylistConnectorTests {

    // MARK: - Apple Music

    @Test func appleMusicPlaylist_returnsOrderedTracks() async throws {
        let connector = makeConnector()
        // Simulate Apple Music returning 3 tracks in a specific order.
        connector.appleScriptReader = { _ in
            """
            Breathe||Pink Floyd||The Dark Side of the Moon||163.0||PID_1
            Money||Pink Floyd||The Dark Side of the Moon||382.0||PID_2
            Time||Pink Floyd||The Dark Side of the Moon||413.0||PID_3
            """
        }

        let tracks = try await connector.connect(source: .appleMusicCurrentPlaylist)

        #expect(tracks.count == 3)
        #expect(tracks[0].title == "Breathe")
        #expect(tracks[1].title == "Money")
        #expect(tracks[2].title == "Time")
    }

    @Test func appleMusicPlaylist_includesDuration() async throws {
        let connector = makeConnector()
        connector.appleScriptReader = { _ in
            "Wish You Were Here||Pink Floyd||Wish You Were Here||314.0||PID_99"
        }

        let tracks = try await connector.connect(source: .appleMusicCurrentPlaylist)

        #expect(tracks.count == 1)
        let track = try #require(tracks.first)
        #expect(track.duration == 314.0)
        #expect(track.artist == "Pink Floyd")
        #expect(track.appleMusicID == "PID_99")
    }

    @Test func emptyPlaylist_returnsEmptyArray() async throws {
        let connector = makeConnector()
        // AppleScript returns nil (no tracks) or empty string.
        connector.appleScriptReader = { _ in nil }

        let tracks = try await connector.connect(source: .appleMusicCurrentPlaylist)

        #expect(tracks.isEmpty)
    }

    @Test func duplicateTracks_preserveOrder() async throws {
        let connector = makeConnector()
        // Same track appears twice — e.g. in a DJ set repeat. Both must be kept.
        connector.appleScriptReader = { _ in
            """
            Blue Monday||New Order||Power, Corruption & Lies||456.0||PID_A
            Blue Monday||New Order||Power, Corruption & Lies||456.0||PID_A
            """
        }

        let tracks = try await connector.connect(source: .appleMusicCurrentPlaylist)

        #expect(tracks.count == 2)
        #expect(tracks[0].title == "Blue Monday")
        #expect(tracks[1].title == "Blue Monday")
    }

    // MARK: - Spotify Queue

    @Test func spotifyQueue_returnsUpTo20Tracks() async throws {
        let connector = makeConnector()

        let queueTracks = (1...5).map { i in
            spotifyTrack(name: "Track \(i)", artist: "Artist", id: "id_\(i)")
        }
        let payload: [String: Any] = [
            "currently_playing": spotifyTrack(name: "Track 0", artist: "Artist", id: "id_0"),
            "queue": queueTracks
        ]
        let responseData = try jsonData(payload)
        connector.networkFetcher = { _ in (responseData, ok200("https://api.spotify.com/v1/me/player/queue")) }

        let tracks = try await connector.connect(source: .spotifyCurrentQueue(accessToken: "tok"))

        // 1 currently_playing + 5 queue = 6
        #expect(tracks.count == 6)
        #expect(tracks[0].title == "Track 0")
        #expect(tracks[5].title == "Track 5")
    }

    @Test func spotifyPlaylistURL_returnsFullTrackList() async throws {
        let connector = makeConnector()

        let items = (1...3).map { i -> [String: Any] in
            ["track": spotifyTrack(name: "Song \(i)", artist: "Band", id: "sid_\(i)")]
        }
        let payload: [String: Any] = ["items": items, "total": 3]
        let responseData = try jsonData(payload)
        connector.networkFetcher = { _ in (responseData, ok200("https://api.spotify.com/v1/playlists/abc/tracks")) }

        let tracks = try await connector.connect(
            source: .spotifyPlaylistURL("https://open.spotify.com/playlist/abc", accessToken: "tok")
        )

        #expect(tracks.count == 3)
        #expect(tracks[0].title == "Song 1")
        #expect(tracks[1].title == "Song 2")
        #expect(tracks[2].title == "Song 3")
    }

    @Test func networkFailure_throwsGracefully() async throws {
        let connector = makeConnector()
        connector.networkFetcher = { _ in
            throw URLError(.notConnectedToInternet)
        }

        var caught: PlaylistConnectorError?
        do {
            _ = try await connector.connect(source: .spotifyCurrentQueue(accessToken: "tok"))
        } catch let err as PlaylistConnectorError {
            caught = err
        }

        if case .networkFailure = caught {
            // Expected — test passes.
        } else {
            Issue.record("Expected .networkFailure, got \(String(describing: caught))")
        }
    }

    // MARK: - TrackIdentity Codable

    @Test func trackIdentity_codable_roundTrip() throws {
        let original = TrackIdentity(
            title: "Pyramid Song",
            artist: "Radiohead",
            album: "Amnesiac",
            duration: 294.9,
            appleMusicID: "appleID_99",
            spotifyID: "spotifyID_77",
            musicBrainzID: "mbid-abc-123"
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(TrackIdentity.self, from: data)

        #expect(decoded == original)
        #expect(decoded.title == "Pyramid Song")
        #expect(decoded.appleMusicID == "appleID_99")
        #expect(decoded.spotifyID == "spotifyID_77")
        #expect(decoded.musicBrainzID == "mbid-abc-123")
    }
}
