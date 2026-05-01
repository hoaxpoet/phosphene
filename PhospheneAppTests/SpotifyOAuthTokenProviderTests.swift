// SpotifyOAuthTokenProviderTests — Unit tests for SpotifyOAuthTokenProvider.
//
// All tests use:
//   - MockKeychainStore (in-memory, no Keychain access)
//   - StubURLProtocol (injectable URLSession, no network)
//   - A no-op openURL closure (no browser opens)
//
// The suite is .serialized because StubURLProtocol uses a global handler that
// must not bleed between concurrently-executing tests.

import Testing
import Foundation
import Session
@testable import PhospheneApp

// MARK: - StubURLProtocol

private final class OAuthStubURLProtocol: URLProtocol {
    // nonisolated(unsafe): serial writes from @Suite(.serialized) test setup.
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Data, HTTPURLResponse))?

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            guard let handler = OAuthStubURLProtocol.handler else {
                client?.urlProtocol(self, didFailWithError: URLError(.unknown)); return
            }
            let (data, response) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

// MARK: - MockKeychainStore

private final class MockKeychainStore: SpotifyKeychainStoring, @unchecked Sendable {
    private var stored: String?
    func saveRefreshToken(_ token: String) { stored = token }
    func loadRefreshToken() -> String? { stored }
    func deleteRefreshToken() { stored = nil }
}

// MARK: - Helpers

private func makeSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [OAuthStubURLProtocol.self]
    return URLSession(configuration: config)
}

private func tokenResponseData(
    accessToken: String = "access_token_xyz",
    refreshToken: String? = "refresh_token_abc",
    expiresIn: Int = 3600
) throws -> (Data, HTTPURLResponse) {
    var json: [String: Any] = ["access_token": accessToken, "expires_in": expiresIn, "token_type": "Bearer"]
    if let rt = refreshToken { json["refresh_token"] = rt }
    let data = try JSONSerialization.data(withJSONObject: json)
    // swiftlint:disable force_unwrapping
    let url = URL(string: "https://accounts.spotify.com/api/token")!
    let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
    // swiftlint:enable force_unwrapping
    return (data, response)
}

private func errorResponseData(statusCode: Int = 400) -> (Data, HTTPURLResponse) {
    let data = Data(#"{"error":"invalid_grant"}"#.utf8)
    // swiftlint:disable force_unwrapping
    let url = URL(string: "https://accounts.spotify.com/api/token")!
    let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
    // swiftlint:enable force_unwrapping
    return (data, response)
}

private func makeProvider(
    keychain: MockKeychainStore = MockKeychainStore(),
    tokenHandler: ((URLRequest) throws -> (Data, HTTPURLResponse))? = nil,
    openURL: @Sendable @escaping (URL) -> Void = { _ in }
) -> SpotifyOAuthTokenProvider {
    OAuthStubURLProtocol.handler = tokenHandler
    return SpotifyOAuthTokenProvider(
        keychainStore: keychain,
        urlSession: makeSession(),
        openURL: openURL
    )
}

// MARK: - Tests

@Suite("SpotifyOAuthTokenProvider", .serialized)
struct SpotifyOAuthTokenProviderTests {

    // MARK: acquire()

    @Test("acquire with no stored refresh token throws spotifyLoginRequired")
    func acquireNoRefreshToken() async throws {
        let provider = makeProvider()
        do {
            _ = try await provider.acquire()
            Issue.record("Expected .spotifyLoginRequired, but no error was thrown")
        } catch PlaylistConnectorError.spotifyLoginRequired {
            // Expected.
        } catch {
            Issue.record("Wrong error: \(error)")
        }
    }

    @Test("acquire with valid cached token returns cached token without network call")
    func acquireCachedToken() async throws {
        var networkCallCount = 0
        let keychain = MockKeychainStore()
        keychain.saveRefreshToken("stored_refresh")

        let provider = makeProvider(keychain: keychain, tokenHandler: { _ in
            networkCallCount += 1
            return try tokenResponseData(accessToken: "first_access")
        })

        // Warm up: triggers silent refresh, caches the access token.
        let first = try await provider.acquire()
        #expect(first == "first_access")
        #expect(networkCallCount == 1)

        // Second call should return cached token without hitting network.
        let second = try await provider.acquire()
        #expect(second == "first_access")
        #expect(networkCallCount == 1)  // no additional call
    }

    @Test("acquire with stored refresh token performs silent refresh and returns new token")
    func acquireSilentRefresh() async throws {
        let keychain = MockKeychainStore()
        keychain.saveRefreshToken("valid_refresh_token")

        let provider = makeProvider(keychain: keychain, tokenHandler: { _ in
            try tokenResponseData(accessToken: "refreshed_access", refreshToken: "new_refresh")
        })

        let token = try await provider.acquire()
        #expect(token == "refreshed_access")
        #expect(await provider.isAuthenticated == true)
    }

    @Test("acquire with invalid refresh token clears keychain and throws spotifyLoginRequired")
    func acquireInvalidRefreshToken() async throws {
        let keychain = MockKeychainStore()
        keychain.saveRefreshToken("expired_refresh_token")

        let provider = makeProvider(keychain: keychain, tokenHandler: { _ in
            errorResponseData(statusCode: 400)
        })

        do {
            _ = try await provider.acquire()
            Issue.record("Expected .spotifyLoginRequired, but no error was thrown")
        } catch PlaylistConnectorError.spotifyLoginRequired {
            // Expected.
        }

        // Refresh token should have been cleared.
        #expect(keychain.loadRefreshToken() == nil)
        #expect(await provider.isAuthenticated == false)
    }

    // MARK: isAuthenticated

    @Test("isAuthenticated is false when no keychain token exists")
    func isAuthenticatedFalseInitially() async {
        let provider = makeProvider()
        #expect(await provider.isAuthenticated == false)
    }

    @Test("isAuthenticated is true when keychain has a refresh token on init")
    func isAuthenticatedTrueWithStoredToken() async {
        let keychain = MockKeychainStore()
        keychain.saveRefreshToken("stored_token")
        let provider = makeProvider(keychain: keychain)
        #expect(await provider.isAuthenticated == true)
    }

    // MARK: login()

    @Test("login opens browser and succeeds when handleCallback delivers valid code")
    func loginSuccess() async throws {
        nonisolated(unsafe) var openedURL: URL?
        let keychain = MockKeychainStore()

        let provider = makeProvider(
            keychain: keychain,
            tokenHandler: { _ in
                try tokenResponseData(accessToken: "oauth_access", refreshToken: "oauth_refresh")
            },
            openURL: { url in openedURL = url }
        )

        let loginTask = Task { try await provider.login() }

        // Give login() time to set up the continuation and open the browser.
        try await Task.sleep(for: .milliseconds(30))

        // Simulate the browser redirect.
        // swiftlint:disable:next force_unwrapping
        let callbackURL = URL(string: "phosphene://spotify-callback?code=auth_code_xyz")!
        await provider.handleCallback(url: callbackURL)

        try await loginTask.value

        #expect(await provider.isAuthenticated == true)
        #expect(openedURL?.absoluteString.contains("accounts.spotify.com/authorize") == true)
        #expect(keychain.loadRefreshToken() == "oauth_refresh")
    }

    @Test("login fails when handleCallback delivers OAuth error")
    func loginDenied() async throws {
        let provider = makeProvider(openURL: { _ in })

        let loginTask = Task { try await provider.login() }
        try await Task.sleep(for: .milliseconds(30))

        // swiftlint:disable:next force_unwrapping
        let callbackURL = URL(string: "phosphene://spotify-callback?error=access_denied")!
        await provider.handleCallback(url: callbackURL)

        do {
            try await loginTask.value
            Issue.record("Expected spotifyAuthFailure, but no error was thrown")
        } catch PlaylistConnectorError.spotifyAuthFailure {
            // Expected.
        }

        #expect(await provider.isAuthenticated == false)
    }

    @Test("handleCallback with wrong URL scheme is a no-op")
    func handleCallbackWrongScheme() async {
        let provider = makeProvider()
        // Should not crash or affect state.
        // swiftlint:disable:next force_unwrapping
        let wrongURL = URL(string: "https://not-a-callback.com/path?code=abc")!
        await provider.handleCallback(url: wrongURL)
        #expect(await provider.isAuthenticated == false)
    }

    // MARK: logout()

    @Test("logout clears all tokens and marks unauthenticated")
    func logout() async throws {
        let keychain = MockKeychainStore()
        keychain.saveRefreshToken("some_refresh")

        let provider = makeProvider(keychain: keychain)
        #expect(await provider.isAuthenticated == true)

        await provider.logout()

        #expect(await provider.isAuthenticated == false)
        #expect(keychain.loadRefreshToken() == nil)
    }

    // MARK: invalidate()

    @Test("invalidate clears access token but preserves refresh token in keychain")
    func invalidateClearsAccessToken() async throws {
        let keychain = MockKeychainStore()
        keychain.saveRefreshToken("refresh_persisted")

        // Pass refreshToken: nil so the exchange response does not rotate the
        // stored refresh token — the keychain should still hold "refresh_persisted"
        // after acquire() and after invalidate().
        let provider = makeProvider(keychain: keychain, tokenHandler: { _ in
            try tokenResponseData(accessToken: "initial_access", refreshToken: nil)
        })

        // Fill the cache.
        _ = try await provider.acquire()

        await provider.invalidate()

        // Refresh token in keychain should be untouched.
        #expect(keychain.loadRefreshToken() == "refresh_persisted")
    }
}
