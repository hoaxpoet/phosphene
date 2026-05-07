// SpotifyItemsSchemaTests — Regression-locks Failed Approach #45 + #47.
//
// Failed Approach #45: Spotify deprecated `/v1/playlists/{id}/tracks` for `/items`,
// and the response schema changed: each `PlaylistTrackObject` now uses `"item"` as
// the key for the track object instead of `"track"`. Code that reads `item["track"]`
// returns nil for every entry and silently produces a zero-track playlist. The
// existing `SpotifyWebAPIConnectorTests` covers this with inline-built JSON; this
// test additionally locks the contract against an *on-disk* fixture that mirrors a
// real Spotify response shape (sibling-of-test JSON, not a builder dictionary).
//
// Failed Approach #47: discarding `preview_url` from the `/items` response and
// then querying iTunes Search for it instead. Spotify already returns CDN preview
// URLs inline; capturing them in `TrackIdentity.spotifyPreviewURL` short-circuits
// `PreviewResolver` for the ~95 % of tracks where Spotify has a preview.
//
// The fixture covers both: 2/3 tracks have a non-null `preview_url`, 1/3 has null.

import Testing
import Foundation
@testable import Session

@Suite("SpotifyItemsSchema")
struct SpotifyItemsSchemaTests {

    @Test("connector parses 3 tracks from the on-disk /items fixture (Failed Approach #45)")
    func test_itemsResponseDecodesViaItemKey() async throws {
        let fixtureURL = URL(fileURLWithPath: String(#filePath))
            .deletingLastPathComponent()  // Session/
            .deletingLastPathComponent()  // PhospheneEngineTests/
            .appendingPathComponent("Fixtures/spotify_items_response.json")
        let data = try Data(contentsOf: fixtureURL)

        let connector = SpotifyWebAPIConnector(tokenProvider: FixedTokenProvider())
        let response = try makeOK200(
            url: "https://api.spotify.com/v1/playlists/abc/items"
        )
        connector.networkFetcher = { _ in (data, response) }

        let tracks = try await connector.connect(playlistID: "abc")
        #expect(tracks.count == 3, """
            Expected 3 tracks decoded from the /items fixture; got \(tracks.count). \
            If 0, the parser regressed to the deprecated `track` key (Failed Approach #45).
            """)
        #expect(tracks[0].title == "Track A")
        #expect(tracks[0].artist == "Artist 1")
        #expect(tracks[2].title == "Track C")
    }

    @Test("preview_url is captured inline in TrackIdentity.spotifyPreviewURL (Failed Approach #47)")
    func test_previewURLCapturedInline() async throws {
        let fixtureURL = URL(fileURLWithPath: String(#filePath))
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/spotify_items_response.json")
        let data = try Data(contentsOf: fixtureURL)

        let connector = SpotifyWebAPIConnector(tokenProvider: FixedTokenProvider())
        let response = try makeOK200(
            url: "https://api.spotify.com/v1/playlists/abc/items"
        )
        connector.networkFetcher = { _ in (data, response) }

        let tracks = try await connector.connect(playlistID: "abc")
        #expect(tracks.count == 3)
        // Track A and Track C have preview_url; Track B has null.
        #expect(tracks[0].spotifyPreviewURL?.absoluteString == "https://example.com/preview-a.mp3",
                "Track A preview URL must be captured inline (Failed Approach #47)")
        #expect(tracks[1].spotifyPreviewURL == nil,
                "Track B null preview_url must yield nil (no fallback fabrication)")
        #expect(tracks[2].spotifyPreviewURL?.absoluteString == "https://example.com/preview-c.mp3")
    }
}

// MARK: - Helpers

/// Stub that returns a fixed access token without network access.
private final class FixedTokenProvider: SpotifyTokenProviding, @unchecked Sendable {
    func acquire() async throws -> String { "stub_token" }
    func invalidate() async {}
}

private func makeOK200(url: String) throws -> HTTPURLResponse {
    guard let parsed = URL(string: url),
          let response = HTTPURLResponse(
              url: parsed, statusCode: 200,
              httpVersion: nil, headerFields: nil
          ) else {
        throw NSError(domain: "SpotifyItemsSchemaTests", code: -1,
                      userInfo: [NSLocalizedDescriptionKey: "could not build HTTP response"])
    }
    return response
}
