// SpotifyTokenProviderTests — Unit tests for the SpotifyTokenProviding fallback.
// The production token provider is the app-layer SpotifyOAuthTokenProvider
// (Authorization Code + PKCE), covered by PhospheneApp's OAuth tests. The
// client-credentials DefaultSpotifyTokenProvider was removed in CLEAN.2.1
// (a native app must not embed a client secret), so only the unconfigured-
// fallback sentinel remains to cover here.

import Testing
@testable import Session

// MARK: - Suite

@Suite("SpotifyTokenProvider")
struct SpotifyTokenProviderTests {

    @Test("MissingCredentialsTokenProvider always throws spotifyAuthFailure")
    func missingCredentialsProviderThrows() async throws {
        let provider = MissingCredentialsTokenProvider()
        do {
            _ = try await provider.acquire()
            Issue.record("Expected spotifyAuthFailure")
        } catch PlaylistConnectorError.spotifyAuthFailure {
            // Expected.
        }
    }
}
