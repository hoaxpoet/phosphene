// StreamingArtworkURLResolverTests — Unit tests for the LF.6.streaming-S2
// resolver. Mirrors `PreviewResolverTests`'s shape: the resolver exposes
// a closure-injected `networkFetcher`, so we don't need URLProtocol stubs.

import Testing
import Foundation
@testable import Session

// MARK: - Helpers

private func makeResolver() -> StreamingArtworkURLResolver {
    StreamingArtworkURLResolver()
}

private func track(
    title: String = "So What",
    artist: String = "Miles Davis",
    spotifyArtworkURL: URL? = nil
) -> TrackIdentity {
    TrackIdentity(
        title: title,
        artist: artist,
        spotifyArtworkURL: spotifyArtworkURL
    )
}

/// Build a fake iTunes Search API response with a single `artworkUrl100`.
private func itunesResponse(artwork100URL: String) -> Data {
    let json: [String: Any] = [
        "resultCount": 1,
        "results": [[
            "trackName": "So What",
            "artistName": "Miles Davis",
            "artworkUrl100": artwork100URL,
            "kind": "song"
        ]]
    ]
    // swiftlint:disable:next force_try
    return try! JSONSerialization.data(withJSONObject: json)
}

private func emptyITunesResponse() -> Data {
    let json: [String: Any] = ["resultCount": 0, "results": []]
    // swiftlint:disable:next force_try
    return try! JSONSerialization.data(withJSONObject: json)
}

private func ok200() -> HTTPURLResponse {
    // swiftlint:disable:next force_unwrapping
    HTTPURLResponse(
        url: URL(string: "https://itunes.apple.com/search")!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
    )!
}

private func tooManyRequests() -> HTTPURLResponse {
    // swiftlint:disable:next force_unwrapping
    HTTPURLResponse(
        url: URL(string: "https://itunes.apple.com/search")!,
        statusCode: 429,
        httpVersion: nil,
        headerFields: nil
    )!
}

// MARK: - Suite

@Suite("StreamingArtworkURLResolver (LF.6.streaming)")
struct StreamingArtworkURLResolverTests {

    @Test("Spotify hint short-circuits — no iTunes request")
    func test_spotifyHintShortCircuits() async throws {
        let resolver = makeResolver()
        let spotifyURL = try #require(URL(string: "https://i.scdn.co/image/album-a-640.jpg"))
        // Network fetcher must not be invoked when Spotify hint is present.
        // nonisolated(unsafe) is fine: this counter is touched only from the
        // closure that the resolver calls synchronously off the main actor,
        // and we read it after the await completes.
        // swiftlint:disable:next nonisolated_unsafe
        nonisolated(unsafe) var networkCalls = 0
        resolver.networkFetcher = { _ in
            networkCalls += 1
            return (emptyITunesResponse(), ok200())
        }

        let url = await resolver.resolveArtworkURL(
            for: track(spotifyArtworkURL: spotifyURL)
        )
        #expect(url == spotifyURL)
        #expect(networkCalls == 0, "Spotify hint must short-circuit before any network call")
    }

    @Test("iTunes Search fallback resolves artwork URL with 600x600bb upgrade")
    func test_iTunesFallbackUpgrades100To600() async throws {
        let resolver = makeResolver()
        resolver.networkFetcher = { _ in
            (itunesResponse(artwork100URL: "https://is1-ssl.mzstatic.com/image/foo/100x100bb.jpg"), ok200())
        }

        let url = await resolver.resolveArtworkURL(for: track())
        #expect(url?.absoluteString == "https://is1-ssl.mzstatic.com/image/foo/600x600bb.jpg",
                "100x100bb must be rewritten to 600x600bb")
    }

    @Test("Both sources nil — Spotify hint absent + iTunes no-match")
    func test_bothSourcesNilReturnsNil() async throws {
        let resolver = makeResolver()
        resolver.networkFetcher = { _ in (emptyITunesResponse(), ok200()) }

        let url = await resolver.resolveArtworkURL(for: track(title: "Unknown Song XYZ-12345"))
        #expect(url == nil)
    }

    @Test("iTunes 429 returns nil (fallback policy)")
    func test_iTunes429ReturnsNil() async throws {
        let resolver = makeResolver()
        resolver.networkFetcher = { _ in (Data(), tooManyRequests()) }

        let url = await resolver.resolveArtworkURL(for: track())
        #expect(url == nil)
    }

    @Test("In-memory cache: second lookup for same track does not refetch")
    func test_inMemoryCachePreventsRefetch() async throws {
        let resolver = makeResolver()
        // swiftlint:disable:next nonisolated_unsafe
        nonisolated(unsafe) var networkCalls = 0
        resolver.networkFetcher = { _ in
            networkCalls += 1
            return (itunesResponse(artwork100URL: "https://cdn.example/100x100bb.jpg"), ok200())
        }

        let urlA = await resolver.resolveArtworkURL(for: track())
        let urlB = await resolver.resolveArtworkURL(for: track())
        #expect(urlA != nil)
        #expect(urlA == urlB)
        #expect(networkCalls == 1, "Second lookup must hit the in-memory cache")
    }

    @Test("Network error returns nil (does not throw)")
    func test_networkErrorReturnsNil() async throws {
        let resolver = makeResolver()
        resolver.networkFetcher = { _ in throw URLError(.notConnectedToInternet) }

        let url = await resolver.resolveArtworkURL(for: track())
        #expect(url == nil)
    }
}
