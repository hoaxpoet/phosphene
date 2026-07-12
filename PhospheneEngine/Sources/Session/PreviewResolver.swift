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

    /// The sliding-window limiter this resolver acquires from. Production uses
    /// `ITunesRateLimiter.shared` so the resolver and the app's metadata
    /// fetcher share ONE 20/min window (PUB.6, ultra-review — previously each
    /// client ran its own, and the fetcher had none). Tests inject a private
    /// instance for isolation.
    private let rateLimiter: ITunesRateLimiter

    /// Maximum requests allowed within `rateLimitWindow`. Defaults to 20 (iTunes limit).
    /// Forwards to the limiter (kept for API/test compatibility).
    public var rateLimitPerWindow: Int {
        get { rateLimiter.maxRequestsPerWindow }
        set { rateLimiter.maxRequestsPerWindow = newValue }
    }

    /// Duration of the sliding rate-limit window in seconds. Defaults to 60.
    /// Forwards to the limiter (kept for API/test compatibility).
    public var rateLimitWindow: TimeInterval {
        get { rateLimiter.window }
        set { rateLimiter.window = newValue }
    }

    // MARK: - State

    private let stateLock = NSLock()
    // nil outer = not cached; inner = .some(url) or .some(nil)
    private var cache: [TrackIdentity: URL?] = [:]

    private static let baseURL = "https://itunes.apple.com/search"

    // MARK: - Init

    public init(rateLimiter: ITunesRateLimiter = .shared) {
        self.rateLimiter = rateLimiter
    }

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
        await rateLimiter.acquire()

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
            // PUB.2 (ultra-review): do NOT cache nil on a non-200 — 429/5xx are
            // transient, and a poisoned cache entry made the D-061(d)
            // network-recovery retry permanently unable to succeed for the
            // track. Only a definitive 200-with-no-result means "no preview"
            // (cached below); transient failures return nil uncached, matching
            // the thrown-error path above.
            logger.info("Non-200 response for '\(track.title)' — returning nil uncached (transient)")
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
