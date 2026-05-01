// SpotifyOAuthPlaylistConnector — Wraps PlaylistConnector with OAuth-aware error remapping.
//
// When the inner connector receives HTTP 403 (spotifyLoginRequired) but the user
// is already authenticated, the playlist is genuinely private/inaccessible — not a
// login problem. This wrapper remaps the error accordingly so the VM can show the
// correct UI state.

import Session

// MARK: - SpotifyOAuthPlaylistConnector

/// Wraps `PlaylistConnector` and remaps `spotifyLoginRequired` → `spotifyPlaylistInaccessible`
/// when the user is already authenticated — a 403 then means "genuinely private playlist".
///
/// Used by `ConnectorPickerView` to inject the correct error semantics into the VM.
public final class SpotifyOAuthPlaylistConnector: PlaylistConnecting, @unchecked Sendable {

    private let inner: PlaylistConnector
    private let oauthProvider: SpotifyOAuthTokenProvider

    public init(
        inner: PlaylistConnector = PlaylistConnector(
            spotifyConnector: SpotifyWebAPIConnector.makeLive()
        ),
        oauthProvider: SpotifyOAuthTokenProvider
    ) {
        self.inner = inner
        self.oauthProvider = oauthProvider
    }

    public func connect(source: PlaylistSource) async throws -> [TrackIdentity] {
        do {
            return try await inner.connect(source: source)
        } catch PlaylistConnectorError.spotifyLoginRequired {
            let authenticated = await oauthProvider.isAuthenticated
            if authenticated {
                // User is logged in; 403 means the playlist is private.
                throw PlaylistConnectorError.spotifyPlaylistInaccessible
            }
            // User is not logged in; propagate so VM shows the login prompt.
            throw PlaylistConnectorError.spotifyLoginRequired
        }
    }
}
