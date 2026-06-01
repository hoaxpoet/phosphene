// StreamingArtworkFetcherTests — LF.6.streaming-S3: URLSession-backed
// single-URL byte fetcher.
//
// Uses URLProtocol stub per CLAUDE.md's URLProtocol invariant. The suite is
// `.serialized` because StubURLProtocol uses a global handler that must not
// bleed between concurrently-executing tests.

import Foundation
import Testing

@testable import PhospheneApp

// MARK: - StubURLProtocol

private final class ArtworkStubURLProtocol: URLProtocol {
    // nonisolated(unsafe): serial writes from @Suite(.serialized) test setup.
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Data, HTTPURLResponse))?

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            guard let handler = ArtworkStubURLProtocol.handler else {
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
    config.protocolClasses = [ArtworkStubURLProtocol.self]
    return URLSession(configuration: config)
}

private func makeResponse(url: URL, status: Int) throws -> HTTPURLResponse {
    try #require(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil))
}

// MARK: - Tests

@Suite("StreamingArtworkFetcher (LF.6.streaming)", .serialized)
struct StreamingArtworkFetcherTests {

    @Test("fetch returns body on 200")
    func test_fetchSucceedsOn200() async throws {
        let url = try #require(URL(string: "https://i.scdn.co/image/album-a-640.jpg"))
        let payload = Data(repeating: 0x42, count: 1024)
        ArtworkStubURLProtocol.handler = { _ in (payload, try makeResponse(url: url, status: 200)) }

        let fetcher = DefaultStreamingArtworkFetcher(urlSession: makeSession())
        let bytes = try await fetcher.fetch(url: url)
        #expect(bytes == payload)
    }

    @Test("fetch throws unexpectedStatus on 404")
    func test_fetchThrowsOn404() async throws {
        let url = try #require(URL(string: "https://i.scdn.co/image/missing.jpg"))
        ArtworkStubURLProtocol.handler = { _ in (Data(), try makeResponse(url: url, status: 404)) }

        let fetcher = DefaultStreamingArtworkFetcher(urlSession: makeSession())
        await #expect(throws: StreamingArtworkFetcherError.unexpectedStatus(404)) {
            _ = try await fetcher.fetch(url: url)
        }
    }

    @Test("fetch throws unexpectedStatus on 500")
    func test_fetchThrowsOn500() async throws {
        let url = try #require(URL(string: "https://i.scdn.co/image/server-error.jpg"))
        ArtworkStubURLProtocol.handler = { _ in (Data(), try makeResponse(url: url, status: 500)) }

        let fetcher = DefaultStreamingArtworkFetcher(urlSession: makeSession())
        await #expect(throws: StreamingArtworkFetcherError.unexpectedStatus(500)) {
            _ = try await fetcher.fetch(url: url)
        }
    }

    @Test("fetch surfaces underlying network error")
    func test_fetchPropagatesNetworkError() async throws {
        let url = try #require(URL(string: "https://i.scdn.co/image/network-fail.jpg"))
        ArtworkStubURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }

        let fetcher = DefaultStreamingArtworkFetcher(urlSession: makeSession())
        do {
            _ = try await fetcher.fetch(url: url)
            Issue.record("Expected network error to throw")
        } catch let error as URLError {
            #expect(error.code == .notConnectedToInternet)
        }
    }

    @Test("fetch returns a 2xx body other than 200 (e.g. 206)")
    func test_fetchAcceptsAll2xx() async throws {
        let url = try #require(URL(string: "https://i.scdn.co/image/partial.jpg"))
        let payload = Data(repeating: 0xCC, count: 256)
        ArtworkStubURLProtocol.handler = { _ in (payload, try makeResponse(url: url, status: 206)) }

        let fetcher = DefaultStreamingArtworkFetcher(urlSession: makeSession())
        let bytes = try await fetcher.fetch(url: url)
        #expect(bytes == payload)
    }
}
