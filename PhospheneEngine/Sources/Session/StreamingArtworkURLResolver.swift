// StreamingArtworkURLResolver — Resolves album-artwork URLs for streaming
// playlist tracks (LF.6.streaming-S2).
//
// Primary source: `TrackIdentity.spotifyArtworkURL` (inline from the
// Spotify Web API `/items` response — no network request needed).
// Fallback: iTunes Search API by `<artist> <title>` (free, no auth,
// 20 req/min) for non-Spotify tracks or tracks where Spotify returned
// no `album.images[]`. The iTunes `artworkUrl100` is rewritten in-string
// from `100x100bb` to `600x600bb` for a higher-resolution image —
// Apple's CDN supports the swap on most entries.
//
// Results are cached in memory per resolver instance, so each track is
// only queried once per session. Same shape as `PreviewResolver`, which
// LF.6.streaming explicitly models this layer on.

import Foundation
import os

// MARK: - Protocol

public protocol StreamingArtworkURLResolving: Sendable {
    /// Returns an artwork URL for the given track, or `nil` if none can be
    /// resolved from either Spotify hint or iTunes Search fallback.
    func resolveArtworkURL(for track: TrackIdentity) async -> URL?
}

// MARK: - Concrete Implementation

public final class StreamingArtworkURLResolver: StreamingArtworkURLResolving, @unchecked Sendable {

    // MARK: - Dependencies

    /// Injectable network fetcher. Defaults to `URLSession.shared`. Replace
    /// in tests to avoid real network calls.
    public var networkFetcher: (URLRequest) async throws -> (Data, URLResponse) = {
        try await URLSession.shared.data(for: $0)
    }

    // MARK: - State

    private let stateLock = NSLock()
    // `URL??`:
    //   .none — not cached; needs resolution
    //   .some(nil) — resolved to "no artwork available"
    //   .some(url) — cached resolved URL
    private var cache: [TrackIdentity: URL?] = [:]

    private static let itunesBaseURL = "https://itunes.apple.com/search"

    // MARK: - Init

    public init() {}

    // MARK: - StreamingArtworkURLResolving

    public func resolveArtworkURL(for track: TrackIdentity) async -> URL? {
        // Cached result — including "no artwork" (nil) — short-circuits.
        if let cached = stateLock.withLock({ cache[track] }) {
            return cached
        }

        // Spotify-first: the connector captured `album.images[0].url` inline,
        // so no network request is needed for Spotify-sourced tracks.
        if let spotifyURL = track.spotifyArtworkURL {
            stateLock.withLock { cache[track] = .some(spotifyURL) }
            return spotifyURL
        }

        // iTunes Search fallback.
        let resolved = await fetchITunesArtworkURL(for: track)
        stateLock.withLock { cache[track] = .some(resolved) }
        return resolved
    }

    // MARK: - iTunes Search fallback

    private func fetchITunesArtworkURL(for track: TrackIdentity) async -> URL? {
        guard let request = buildITunesRequest(for: track) else {
            logger.error("Could not build iTunes search request for '\(track.title)'")
            return nil
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await networkFetcher(request)
        } catch {
            logger.info("iTunes Search artwork lookup failed for '\(track.title)': \(error)")
            return nil
        }

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            // 429 / 5xx etc. — treat as "no artwork" rather than error;
            // matches `PreviewResolver` fallback policy.
            return nil
        }
        return parseArtworkURL(from: data)
    }

    private func buildITunesRequest(for track: TrackIdentity) -> URLRequest? {
        guard var components = URLComponents(string: Self.itunesBaseURL) else { return nil }
        let term = "\(track.artist) \(track.title)"
        components.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "1")
        ]
        guard let url = components.url else { return nil }
        return URLRequest(url: url, timeoutInterval: 10)
    }

    private func parseArtworkURL(from data: Data) -> URL? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]],
              let first = results.first,
              let artwork100 = first["artworkUrl100"] as? String
        else { return nil }
        // Apple's CDN serves `<…>/100x100bb.jpg`; the same path with
        // `600x600bb` resolves to a higher-resolution variant for most
        // entries. Stuck-state guidance §2 notes a small fraction of 404s
        // at 600px — those surface as fetch errors at the S3 layer and
        // fall back to the glyph (we don't transparently downgrade here).
        let upgraded = artwork100.replacingOccurrences(of: "100x100bb", with: "600x600bb")
        return URL(string: upgraded)
    }
}

// MARK: - Logger

private let logger = Logger(subsystem: "com.phosphene", category: "StreamingArtworkURLResolver")
