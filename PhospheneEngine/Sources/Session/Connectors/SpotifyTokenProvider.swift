// SpotifyTokenProvider — `SpotifyTokenProviding` protocol + the unconfigured
// fallback used when no authenticated provider is wired into a connector.
// The production implementation is the app-layer `SpotifyOAuthTokenProvider`
// (Authorization Code + PKCE — no client secret; a native app must not embed one).

import Foundation
import Shared

// MARK: - SpotifyTokenProviding

/// Acquires a Spotify bearer token. The production implementation is the
/// app-layer `SpotifyOAuthTokenProvider` (OAuth user token via PKCE).
public protocol SpotifyTokenProviding: AnyObject, Sendable {
    /// Return a valid Spotify bearer token, refreshing if necessary.
    ///
    /// Throws `PlaylistConnectorError.spotifyAuthFailure` (or
    /// `.spotifyLoginRequired`) when no valid token can be obtained.
    func acquire() async throws -> String

    /// Evict the cached token, forcing the next `acquire()` to re-authenticate.
    func invalidate() async
}

// MARK: - MissingCredentialsTokenProvider

/// Fallback token provider used when a `SpotifyWebAPIConnector` is built without
/// an authenticated provider (the `makeLive()` default). Every `acquire()`
/// throws `.spotifyAuthFailure` so missing wiring surfaces as a real error at
/// connect time rather than silently degrading. The production Spotify playlist
/// flow injects `SpotifyOAuthTokenProvider` (PKCE user token) instead.
final class MissingCredentialsTokenProvider: SpotifyTokenProviding, @unchecked Sendable {
    func acquire() async throws -> String {
        throw PlaylistConnectorError.spotifyAuthFailure(
            "Spotify requires OAuth login; no authenticated token provider is configured."
        )
    }
    func invalidate() async {}
}
