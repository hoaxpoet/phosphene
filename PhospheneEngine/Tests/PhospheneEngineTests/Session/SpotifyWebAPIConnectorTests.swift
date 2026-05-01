// SpotifyWebAPIConnectorTests — Unit tests for SpotifyWebAPIConnector.
// All HTTP I/O goes through connector.networkFetcher (URLProtocol mock not needed;
// the networkFetcher closure is simpler and already proven in PlaylistConnectorTests).
// Zero real network access required.

import Testing
import Foundation
@testable import Session

// MARK: - Helpers

/// Minimal track JSON matching the fields=... subset requested by the connector.
private func apiTrack(
    name: String,
    artist: String,
    id: String = "tid",
    durationMs: Double = 210_000
) -> [String: Any] {
    [
        "name": name,
        "artists": [["name": artist]],
        "album": ["name": "Album"],
        "id": id,
        "duration_ms": durationMs
    ]
}

private func jsonData(_ object: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: object)
}

private func ok200(_ url: String = "https://api.spotify.com/v1/playlists/abc/tracks") -> HTTPURLResponse {
    // swiftlint:disable:next force_unwrapping
    HTTPURLResponse(url: URL(string: url)!, statusCode: 200, httpVersion: nil, headerFields: nil)!
}

private func httpResponse(status: Int, headers: [String: String]? = nil) -> HTTPURLResponse {
    // swiftlint:disable:next force_unwrapping
    HTTPURLResponse(url: URL(string: "https://api.spotify.com")!, statusCode: status,
                    httpVersion: nil, headerFields: headers)!
}

/// Stub token provider that returns a fixed token without network access.
private final class FixedTokenProvider: SpotifyTokenProviding, @unchecked Sendable {
    let token: String
    init(_ token: String = "stub_token") { self.token = token }
    func acquire() async throws -> String { token }
    func invalidate() async {}
}

/// Token provider that tracks `invalidate()` calls.
private actor TrackingTokenProvider: SpotifyTokenProviding {
    var invalidateCalled = false
    var acquireCount = 0
    private let tokens: [String]
    private var index = 0

    init(tokens: [String]) { self.tokens = tokens }

    func acquire() async throws -> String {
        acquireCount += 1
        guard index < tokens.count else {
            throw PlaylistConnectorError.spotifyAuthFailure("No more tokens")
        }
        let token = tokens[index]
        index += 1
        return token
    }

    func invalidate() async {
        invalidateCalled = true
    }
}

// MARK: - Suite

@Suite("SpotifyWebAPIConnector")
struct SpotifyWebAPIConnectorTests {

    // MARK: - Happy path

    @Test("connect returns tracks from single-page response")
    func singlePageSuccess() async throws {
        let items = (1...3).map { i -> [String: Any] in
            ["track": apiTrack(name: "Track \(i)", artist: "Artist", id: "id\(i)")]
        }
        let payload: [String: Any] = ["items": items]
        let data = try jsonData(payload)

        let connector = SpotifyWebAPIConnector(tokenProvider: FixedTokenProvider())
        connector.networkFetcher = { _ in (data, ok200()) }

        let tracks = try await connector.connect(playlistID: "abc")
        #expect(tracks.count == 3)
        #expect(tracks[0].title == "Track 1")
        #expect(tracks[2].title == "Track 3")
    }

    @Test("connect paginates across 3 pages totalling 250 tracks")
    func threePagePagination() async throws {
        // Page 1: 100 tracks + next URL
        // Page 2: 100 tracks + next URL
        // Page 3: 50 tracks + no next
        // nonisolated(unsafe): written only in the serial networkFetcher closure
        // which executes on the URLSession networking thread sequentially per request.
        // swiftlint:disable:next nonisolated_unsafe
        nonisolated(unsafe) var callIndex = 0
        let connector = SpotifyWebAPIConnector(tokenProvider: FixedTokenProvider())
        connector.networkFetcher = { _ in
            callIndex += 1
            let batchSize = callIndex < 3 ? 100 : 50
            let items = (1...batchSize).map { i -> [String: Any] in
                ["track": apiTrack(name: "T\(callIndex)-\(i)", artist: "A", id: "t\(callIndex)\(i)")]
            }
            var payload: [String: Any] = ["items": items]
            if callIndex < 3 {
                payload["next"] = "https://api.spotify.com/v1/playlists/abc/tracks?offset=\(callIndex * 100)"
            }
            let data = try JSONSerialization.data(withJSONObject: payload)
            return (data, HTTPURLResponse(
                // swiftlint:disable:next force_unwrapping
                url: URL(string: "https://api.spotify.com/v1/playlists/abc/tracks")!,
                statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        let tracks = try await connector.connect(playlistID: "abc")
        #expect(tracks.count == 250)
        #expect(callIndex == 3)
    }

    // MARK: - 401 retry

    @Test("401 on playlist call invalidates token and retries once, then succeeds")
    func retryOnce401ThenSuccess() async throws {
        let items = [["track": apiTrack(name: "Song", artist: "A", id: "s1")]]
        let successData = try jsonData(["items": items])
        // swiftlint:disable:next nonisolated_unsafe
        nonisolated(unsafe) var callIndex = 0

        let tokenProvider = TrackingTokenProvider(tokens: ["tok1", "tok2"])
        let connector = SpotifyWebAPIConnector(tokenProvider: tokenProvider)
        connector.networkFetcher = { _ in
            callIndex += 1
            if callIndex == 1 {
                return (Data(), httpResponse(status: 401))
            }
            return (successData, ok200())
        }

        let tracks = try await connector.connect(playlistID: "abc")
        #expect(tracks.count == 1)
        #expect(await tokenProvider.invalidateCalled)
        #expect(await tokenProvider.acquireCount == 2)
    }

    @Test("401 on both attempts throws spotifyAuthFailure")
    func doubleRetry401Fails() async throws {
        let tokenProvider = TrackingTokenProvider(tokens: ["tok1", "tok2"])
        let connector = SpotifyWebAPIConnector(tokenProvider: tokenProvider)
        connector.networkFetcher = { _ in (Data(), httpResponse(status: 401)) }

        do {
            _ = try await connector.connect(playlistID: "abc")
            Issue.record("Expected spotifyAuthFailure")
        } catch PlaylistConnectorError.spotifyAuthFailure {
            // Expected.
        }
    }

    // MARK: - Error mapping

    @Test("403 maps to spotifyPlaylistInaccessible")
    func forbiddenMapsToInaccessible() async throws {
        let connector = SpotifyWebAPIConnector(tokenProvider: FixedTokenProvider())
        connector.networkFetcher = { _ in (Data(), httpResponse(status: 403)) }

        do {
            _ = try await connector.connect(playlistID: "private_id")
            Issue.record("Expected spotifyPlaylistInaccessible")
        } catch PlaylistConnectorError.spotifyPlaylistInaccessible {
            // Expected.
        }
    }

    @Test("404 maps to spotifyPlaylistNotFound")
    func notFoundMapsCorrectly() async throws {
        let connector = SpotifyWebAPIConnector(tokenProvider: FixedTokenProvider())
        connector.networkFetcher = { _ in (Data(), httpResponse(status: 404)) }

        do {
            _ = try await connector.connect(playlistID: "gone_id")
            Issue.record("Expected spotifyPlaylistNotFound")
        } catch PlaylistConnectorError.spotifyPlaylistNotFound {
            // Expected.
        }
    }

    @Test("429 maps to rateLimited and parses Retry-After header")
    func rateLimitedParsesRetryAfter() async throws {
        let connector = SpotifyWebAPIConnector(tokenProvider: FixedTokenProvider())
        connector.networkFetcher = { _ in
            (Data(), httpResponse(status: 429, headers: ["Retry-After": "30"]))
        }

        do {
            _ = try await connector.connect(playlistID: "abc")
            Issue.record("Expected rateLimited")
        } catch PlaylistConnectorError.rateLimited(let retryAfter) {
            #expect(retryAfter == 30.0)
        }
    }

    @Test("429 without Retry-After defaults to 1.0 second")
    func rateLimitedDefaultRetryAfter() async throws {
        let connector = SpotifyWebAPIConnector(tokenProvider: FixedTokenProvider())
        connector.networkFetcher = { _ in (Data(), httpResponse(status: 429)) }

        do {
            _ = try await connector.connect(playlistID: "abc")
            Issue.record("Expected rateLimited")
        } catch PlaylistConnectorError.rateLimited(let retryAfter) {
            #expect(retryAfter == 1.0)
        }
    }

    @Test("network error maps to networkFailure")
    func networkErrorMapsToNetworkFailure() async throws {
        let connector = SpotifyWebAPIConnector(tokenProvider: FixedTokenProvider())
        connector.networkFetcher = { _ in throw URLError(.notConnectedToInternet) }

        do {
            _ = try await connector.connect(playlistID: "abc")
            Issue.record("Expected networkFailure")
        } catch PlaylistConnectorError.networkFailure {
            // Expected.
        }
    }
}

// MARK: - SpotifyIntegrationTests

/// Integration tests that call the real Spotify API.
/// Gated behind SPOTIFY_INTEGRATION_TESTS=1 env var.
///
/// To run:
///   SPOTIFY_INTEGRATION_TESTS=1 swift test --package-path PhospheneEngine \
///       --filter SpotifyIntegrationTests
@Suite("SpotifyIntegrationTests")
struct SpotifyIntegrationTests {

    @Test("connect to public playlist returns ≥40 tracks with valid metadata")
    func publicPlaylistHasTracksWithMetadata() async throws {
        guard ProcessInfo.processInfo.environment["SPOTIFY_INTEGRATION_TESTS"] == "1" else {
            return  // Skip when flag is not set.
        }
        let tokenProvider = try DefaultSpotifyTokenProvider()
        let connector = SpotifyWebAPIConnector(tokenProvider: tokenProvider)

        // "Today's Top Hits" — consistently public and large.
        let playlistID = "37i9dQZF1DXcBWIGoYBM5M"
        let tracks = try await connector.connect(playlistID: playlistID)

        #expect(tracks.count >= 40, "Expected ≥40 tracks, got \(tracks.count)")
        for track in tracks {
            #expect(!track.title.isEmpty, "Track title must not be empty")
            #expect(!track.artist.isEmpty, "Track artist must not be empty")
            #expect(track.spotifyID != nil, "Track must have a Spotify ID")
        }
    }
}
