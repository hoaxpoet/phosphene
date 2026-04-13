// PreviewResolverTests — Unit tests for PreviewResolver.
// All network calls are injected via the networkFetcher closure.
// No real iTunes or network access required.

import Testing
import Foundation
@testable import Session

// MARK: - Helpers

private func makeResolver() -> PreviewResolver {
    PreviewResolver()
}

private func makeTrack(
    title: String = "Bohemian Rhapsody",
    artist: String = "Queen"
) -> TrackIdentity {
    TrackIdentity(title: title, artist: artist)
}

/// Build a fake iTunes Search API response containing one result with `previewUrl`.
private func itunesResponse(previewURL: String = "https://example.com/preview.m4a") -> Data {
    let json: [String: Any] = [
        "resultCount": 1,
        "results": [[
            "trackName": "Bohemian Rhapsody",
            "artistName": "Queen",
            "previewUrl": previewURL,
            "kind": "song"
        ]]
    ]
    // swiftlint:disable:next force_try
    return try! JSONSerialization.data(withJSONObject: json)
}

/// Build a fake iTunes response with no results.
private func emptyItunesResponse() -> Data {
    let json: [String: Any] = ["resultCount": 0, "results": []]
    // swiftlint:disable:next force_try
    return try! JSONSerialization.data(withJSONObject: json)
}

private func ok200() -> HTTPURLResponse {
    // swiftlint:disable:next force_unwrapping
    HTTPURLResponse(url: URL(string: "https://itunes.apple.com/search")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
}

// MARK: - Suite

@Suite("PreviewResolver")
struct PreviewResolverTests {

    // MARK: - Known Track

    @Test func knownTrack_resolvesToURL() async throws {
        let resolver = makeResolver()
        let expectedURL = URL(string: "https://example.com/preview.m4a")

        resolver.networkFetcher = { _ in
            (itunesResponse(previewURL: "https://example.com/preview.m4a"), ok200())
        }

        let url = try await resolver.resolvePreviewURL(for: makeTrack())

        #expect(url == expectedURL)
    }

    // MARK: - Unknown Track

    @Test func unknownTrack_returnsNil() async throws {
        let resolver = makeResolver()

        resolver.networkFetcher = { _ in
            (emptyItunesResponse(), ok200())
        }

        let url = try await resolver.resolvePreviewURL(for: makeTrack(title: "Nonexistent Song XYZ"))

        #expect(url == nil)
    }

    // MARK: - Preview URL Format

    @Test func previewURL_isValidAAC() async throws {
        let resolver = makeResolver()
        // iTunes preview URLs end in .m4a (AAC in an MPEG-4 container).
        let aacURL = "https://audio-ssl.itunes.apple.com/itunes-assets/Music/track.m4a"
        resolver.networkFetcher = { _ in
            (itunesResponse(previewURL: aacURL), ok200())
        }

        let url = try await resolver.resolvePreviewURL(for: makeTrack())
        let resolved = try #require(url)

        // iTunes preview URLs are HTTPS and typically end in .m4a.
        #expect(resolved.scheme == "https")
        #expect(resolved.pathExtension == "m4a" || resolved.absoluteString.contains("itunes"))
    }

    // MARK: - Rate Limiting

    @Test func rateLimiting_respectsLimit() async throws {
        let resolver = makeResolver()
        // Use a very short window so the test completes quickly.
        resolver.rateLimitPerWindow = 3
        resolver.rateLimitWindow = 0.5

        var callCount = 0
        resolver.networkFetcher = { _ in
            callCount += 1
            return (itunesResponse(), ok200())
        }

        // Fire more requests than the rate limit allows in the window.
        // All four should eventually complete (after throttling), not throw.
        let tracks = (0..<4).map { i in makeTrack(title: "Track \(i)", artist: "Artist \(i)") }
        let start = Date()

        await withTaskGroup(of: Void.self) { group in
            for track in tracks {
                group.addTask {
                    _ = try? await resolver.resolvePreviewURL(for: track)
                }
            }
        }

        let elapsed = Date().timeIntervalSince(start)
        // 4 requests at 3/0.5s limit means the 4th must wait at least ~0.5s.
        #expect(elapsed >= 0.4)
        // All 4 calls eventually went through.
        #expect(callCount == 4)
    }

    // MARK: - Network Timeout

    @Test func networkTimeout_returnsNilGracefully() async throws {
        let resolver = makeResolver()
        resolver.networkFetcher = { _ in
            throw URLError(.timedOut)
        }

        // Should not throw — returns nil instead.
        let url = try await resolver.resolvePreviewURL(for: makeTrack())
        #expect(url == nil)
    }

    // MARK: - Cache

    @Test func multipleResolves_usesCache() async throws {
        let resolver = makeResolver()
        var fetchCount = 0

        resolver.networkFetcher = { _ in
            fetchCount += 1
            return (itunesResponse(), ok200())
        }

        let track = makeTrack()
        let first = try await resolver.resolvePreviewURL(for: track)
        let second = try await resolver.resolvePreviewURL(for: track)
        let third = try await resolver.resolvePreviewURL(for: track)

        // Network should be called exactly once; subsequent calls hit the cache.
        #expect(fetchCount == 1)
        #expect(first == second)
        #expect(second == third)
    }
}
