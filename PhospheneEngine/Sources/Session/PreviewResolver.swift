// PreviewResolver — Resolves 30-second preview URLs for playlist tracks.
// Primary source: TrackIdentity.spotifyPreviewURL (Spotify Web API, inline in /items response).
// Fallback: iTunes Search API (free, no auth, 20 req/min) for non-Spotify tracks or tracks
// where Spotify returns null for preview_url.
// Results are cached in memory so each track is only ever fetched once.

import Foundation
import os

// MARK: - Protocol

/// Resolves a downloadable 30-second preview URL for a track.
public protocol PreviewResolving: Sendable {
    /// Returns a preview URL for the given track, or `nil` if none is available.
    /// Implementations must be safe to call concurrently.
    func resolvePreviewURL(for track: TrackIdentity) async throws -> URL?
}

// MARK: - Concrete Implementation

/// Resolves 30-second preview URLs for tracks.
///
/// Primary source: `TrackIdentity.spotifyPreviewURL` (inline from the Spotify
/// Web API `/items` response — no network request needed).
/// Fallback: iTunes Search API (free, no auth, 20 req/min) for non-Spotify tracks
/// or tracks where Spotify returns `null` for `preview_url`.
///
/// Results are cached in memory — a second call for the same `TrackIdentity`
/// returns immediately without a network request. Rate-limiting is enforced
/// transparently: if the request window is full, callers are suspended until
/// a slot opens rather than receiving an error.
public final class PreviewResolver: PreviewResolving, @unchecked Sendable {

    // MARK: - Dependencies

    /// Injectable network fetcher. Defaults to `URLSession.shared`.
    /// Replace in tests to avoid real network calls.
    public var networkFetcher: (URLRequest) async throws -> (Data, URLResponse) = {
        try await URLSession.shared.data(for: $0)
    }

    // MARK: - Rate-limit Configuration

    /// Maximum requests allowed within `rateLimitWindow`. Defaults to 20 (iTunes limit).
    public var rateLimitPerWindow: Int = 20

    /// Duration of the sliding rate-limit window in seconds. Defaults to 60.
    public var rateLimitWindow: TimeInterval = 60.0

    // MARK: - State

    private let stateLock = NSLock()
    // nil outer = not cached; inner = .some(url) or .some(nil)
    private var cache: [TrackIdentity: URL?] = [:]
    private var requestTimestamps: [Date] = []

    private static let baseURL = "https://itunes.apple.com/search"

    // MARK: - Init

    public init() {}

    // MARK: - PreviewResolving

    public func resolvePreviewURL(for track: TrackIdentity) async throws -> URL? {
        // Fast path: return cached result if present (including "no preview" nil).
        if let cached = lockedCachedURL(for: track) {
            return cached
        }

        // Fast path: Spotify already provided the preview URL in the playlist response.
        // Seed the cache and return immediately — no iTunes Search API call needed.
        if let spotifyURL = track.spotifyPreviewURL {
            stateLock.withLock { cache[track] = .some(spotifyURL) }
            return spotifyURL
        }

        // Enforce rate limit before sending a request.
        await throttle()

        guard let request = buildRequest(for: track) else {
            logger.error("Could not build iTunes search request for '\(track.title)'")
            return nil
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await networkFetcher(request)
        } catch {
            logger.error("iTunes Search request failed for '\(track.title)': \(error)")
            return nil
        }

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            logger.info("Non-200 response for '\(track.title)', caching nil")
            stateLock.withLock { cache[track] = .some(nil) }
            return nil
        }

        let url = parsePreviewURL(from: data)
        stateLock.withLock { cache[track] = .some(url) }
        if let url {
            logger.debug("Resolved preview for '\(track.title)': \(url)")
        } else {
            logger.info("No preview URL found for '\(track.title)'")
        }
        return url
    }

    // MARK: - Private Helpers

    /// Returns the cached result for `track`, or `nil` if not yet cached.
    ///
    /// Returns `URL??`:
    ///  - `.none` — not in cache at all (caller must fetch)
    ///  - `.some(.none)` — cached as "no preview available"
    ///  - `.some(.some(url))` — cached preview URL
    private func lockedCachedURL(for track: TrackIdentity) -> URL?? {
        stateLock.withLock { cache[track] }
    }

    /// Suspends the caller if the rate-limit window is full, then records the timestamp.
    private func throttle() async {
        while true {
            let waitTime: TimeInterval = stateLock.withLock {
                let now = Date()
                let windowStart = now.addingTimeInterval(-rateLimitWindow)
                requestTimestamps.removeAll { $0 <= windowStart }

                if requestTimestamps.count >= rateLimitPerWindow,
                   let oldest = requestTimestamps.first {
                    let waitUntil = oldest.addingTimeInterval(rateLimitWindow)
                    return max(0.001, waitUntil.timeIntervalSince(now))
                }
                requestTimestamps.append(now)
                return 0
            }

            guard waitTime > 0 else { return }
            try? await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
        }
    }

    private func buildRequest(for track: TrackIdentity) -> URLRequest? {
        guard var components = URLComponents(string: Self.baseURL) else { return nil }
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

    private func parsePreviewURL(from data: Data) -> URL? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]],
              let first = results.first,
              let previewString = first["previewUrl"] as? String else {
            return nil
        }
        return URL(string: previewString)
    }
}

// MARK: - Logger

private let logger = Logger(subsystem: "com.phosphene", category: "PreviewResolver")
