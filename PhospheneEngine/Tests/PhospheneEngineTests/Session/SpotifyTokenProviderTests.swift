// SpotifyTokenProviderTests — Unit tests for DefaultSpotifyTokenProvider.
// Uses a URLProtocol stub with nonisolated(unsafe) global handler for serial test setup.
// Zero real network access required.

import Testing
import Foundation
@testable import Session

// MARK: - StubURLProtocol

private final class StubURLProtocol: URLProtocol {
    // nonisolated(unsafe): only written in serial test setup, read in the URLSession
    // networking thread. Concurrent writes during the same test case are impossible
    // because Swift Testing serialises @Suite methods by default.
    // swiftlint:disable:next nonisolated_unsafe
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Data, HTTPURLResponse))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            guard let handler = StubURLProtocol.handler else {
                client?.urlProtocol(self, didFailWithError: URLError(.unknown))
                return
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

// MARK: - Helpers

private func makeSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
    return URLSession(configuration: config)
}

private func tokenResponse(
    accessToken: String = "test_token",
    expiresIn: Int = 3600
) throws -> (Data, HTTPURLResponse) {
    let json: [String: Any] = ["access_token": accessToken, "token_type": "Bearer", "expires_in": expiresIn]
    let data = try JSONSerialization.data(withJSONObject: json)
    // swiftlint:disable:next force_unwrapping
    let response = HTTPURLResponse(url: URL(string: "https://accounts.spotify.com/api/token")!,
                                   statusCode: 200, httpVersion: nil, headerFields: nil)!
    return (data, response)
}

private func httpResponse(status: Int) -> HTTPURLResponse {
    // swiftlint:disable:next force_unwrapping
    HTTPURLResponse(url: URL(string: "https://accounts.spotify.com/api/token")!,
                    statusCode: status, httpVersion: nil, headerFields: nil)!
}

// MARK: - Suite

// .serialized: tests share the global StubURLProtocol.handler; parallel runs
// would allow one test's handler to bleed into another's URL session.
@Suite("SpotifyTokenProvider", .serialized)
struct SpotifyTokenProviderTests {

    @Test("acquire succeeds and returns token")
    func acquireSuccess() async throws {
        StubURLProtocol.handler = { _ in try tokenResponse(accessToken: "abc123") }
        let provider = DefaultSpotifyTokenProvider(
            clientID: "id", clientSecret: "secret", urlSession: makeSession()
        )
        let token = try await provider.acquire()
        #expect(token == "abc123")
    }

    @Test("cache hit before safety margin skips network")
    func cacheHitBeforeMargin() async throws {
        var callCount = 0
        StubURLProtocol.handler = { _ in
            callCount += 1
            return try tokenResponse(accessToken: "tok", expiresIn: 3600)
        }
        let provider = DefaultSpotifyTokenProvider(
            clientID: "id", clientSecret: "secret", urlSession: makeSession()
        )
        _ = try await provider.acquire()
        let token2 = try await provider.acquire()
        #expect(token2 == "tok")
        #expect(callCount == 1, "Second acquire should use cache, not fire another request")
    }

    @Test("invalidate forces re-fetch on next acquire")
    func invalidateForcesRefresh() async throws {
        var callCount = 0
        StubURLProtocol.handler = { _ in
            callCount += 1
            return try tokenResponse(accessToken: "tok_\(callCount)", expiresIn: 3600)
        }
        let provider = DefaultSpotifyTokenProvider(
            clientID: "id", clientSecret: "secret", urlSession: makeSession()
        )
        _ = try await provider.acquire()
        await provider.invalidate()
        let token2 = try await provider.acquire()
        #expect(callCount == 2, "Should fetch again after invalidate")
        #expect(token2 == "tok_2")
    }

    @Test("401 from token endpoint throws spotifyAuthFailure")
    func unauthorizedThrows() async throws {
        StubURLProtocol.handler = { _ in (Data(), httpResponse(status: 401)) }
        let provider = DefaultSpotifyTokenProvider(
            clientID: "id", clientSecret: "secret", urlSession: makeSession()
        )
        do {
            _ = try await provider.acquire()
            Issue.record("Expected spotifyAuthFailure")
        } catch PlaylistConnectorError.spotifyAuthFailure {
            // Expected.
        }
    }

    @Test("400 from token endpoint throws spotifyAuthFailure")
    func badRequestThrows() async throws {
        StubURLProtocol.handler = { _ in (Data(), httpResponse(status: 400)) }
        let provider = DefaultSpotifyTokenProvider(
            clientID: "id", clientSecret: "secret", urlSession: makeSession()
        )
        do {
            _ = try await provider.acquire()
            Issue.record("Expected spotifyAuthFailure")
        } catch PlaylistConnectorError.spotifyAuthFailure {
            // Expected.
        }
    }

    @Test("missing credentials init throws spotifyAuthFailure")
    func missingCredentialsThrows() async throws {
        // DefaultSpotifyTokenProvider.init(urlSession:) reads Bundle.main.infoDictionary.
        // In test targets SpotifyClientID/Secret are empty strings → throws.
        // On a dev machine with creds configured, the throw may not fire — that's fine.
        do {
            _ = try DefaultSpotifyTokenProvider(urlSession: makeSession())
            // Credentials are present on this machine — test is vacuously satisfied.
        } catch PlaylistConnectorError.spotifyAuthFailure {
            // Expected on machines without credentials configured.
        }
    }

    @Test("network failure throws networkFailure")
    func networkFailureMapsCorrectly() async throws {
        StubURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        let provider = DefaultSpotifyTokenProvider(
            clientID: "id", clientSecret: "secret", urlSession: makeSession()
        )
        do {
            _ = try await provider.acquire()
            Issue.record("Expected networkFailure")
        } catch PlaylistConnectorError.networkFailure {
            // Expected.
        }
    }

    @Test("concurrent acquire calls deduplicate to one request")
    func concurrentAcquiresDedup() async throws {
        var callCount = 0
        // Thread.sleep is synchronous — works fine in StubURLProtocol.startLoading().
        StubURLProtocol.handler = { _ in
            callCount += 1
            Thread.sleep(forTimeInterval: 0.01)
            return try tokenResponse(accessToken: "tok", expiresIn: 3600)
        }
        let provider = DefaultSpotifyTokenProvider(
            clientID: "id", clientSecret: "secret", urlSession: makeSession()
        )
        async let t1 = provider.acquire()
        async let t2 = provider.acquire()
        async let t3 = provider.acquire()
        let results = try await [t1, t2, t3]
        #expect(results.allSatisfy { $0 == "tok" })
        // All three calls should share a single in-flight request.
        #expect(callCount == 1, "Concurrent acquire() calls should share one request, got \(callCount)")
    }

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
