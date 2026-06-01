// StreamingArtworkFetcher — Single-URL byte fetcher for streaming-path
// artwork (LF.6.streaming-S3).
//
// The protocol exists so `VisualizerEngine` can inject a stub in tests
// without touching the network. The default implementation uses URLSession
// with a 5-second timeout: artwork is a soft-decoration concern, and we'd
// rather show the fallback glyph than block waiting on a slow CDN.
//
// Errors (non-2xx response, timeout, network failure) throw and are caught
// by S5's wiring; the caller publishes nil for `currentTrackArtworkData`
// on throw so the chrome falls back to the glyph.
//
// No request coalescing in the first cut — multiple track-changes in quick
// succession are handled by in-flight task cancellation in S5, not by
// deduping at this layer.

import Foundation
import os.log

// MARK: - Protocol

protocol StreamingArtworkFetching: Sendable {
    /// Fetch raw bytes for the given URL.
    /// Throws on non-2xx response, timeout, or network failure.
    func fetch(url: URL) async throws -> Data
}

// MARK: - Errors

enum StreamingArtworkFetcherError: Error, Equatable {
    /// Non-2xx HTTP status code returned from the CDN.
    case unexpectedStatus(Int)
    /// Response was not an `HTTPURLResponse` (should not happen for https).
    case invalidResponse
}

// MARK: - Default implementation

struct DefaultStreamingArtworkFetcher: StreamingArtworkFetching {

    static let defaultTimeoutSeconds: TimeInterval = 5.0

    private let urlSession: URLSession
    private let timeoutSeconds: TimeInterval

    init(
        urlSession: URLSession = DefaultStreamingArtworkFetcher.makeDefaultSession(),
        timeoutSeconds: TimeInterval = DefaultStreamingArtworkFetcher.defaultTimeoutSeconds
    ) {
        self.urlSession = urlSession
        self.timeoutSeconds = timeoutSeconds
    }

    /// Build a URLSession with the artwork timeout baked into the request
    /// timeout (the request-level timeout is what bounds an in-flight fetch
    /// for the live-track artwork path).
    static func makeDefaultSession() -> URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = defaultTimeoutSeconds
        config.timeoutIntervalForResource = defaultTimeoutSeconds * 2
        return URLSession(configuration: config)
    }

    func fetch(url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeoutSeconds
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw StreamingArtworkFetcherError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw StreamingArtworkFetcherError.unexpectedStatus(http.statusCode)
        }
        return data
    }
}
