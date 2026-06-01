// StreamingArtworkPublishingTests — LF.6.streaming-S5: drive the
// `StreamingArtworkPublisher` flow with stub deps + a recorder publish
// closure. Asserts the three S5 contracts:
//   (1) resolvable artwork → bytes land in `currentTrackArtworkData`.
//   (2) unresolvable artwork → nil is published.
//   (3) rapid A → B track-change cancels A; only B's bytes ever appear.

import Foundation
import Session
import Testing

@testable import PhospheneApp

// MARK: - Stub deps

private final class StubResolver: StreamingArtworkURLResolving, @unchecked Sendable {
    private let lock = NSLock()
    private var perTrackURL: [String: URL] = [:]
    var delay: Duration = .zero

    func setURL(_ url: URL, for title: String) {
        lock.withLock { perTrackURL[title] = url }
    }

    func resolveArtworkURL(for track: TrackIdentity) async -> URL? {
        if delay > .zero {
            try? await Task.sleep(for: delay)
        }
        return lock.withLock { perTrackURL[track.title] }
    }
}

private final class StubFetcher: StreamingArtworkFetching, @unchecked Sendable {
    private let lock = NSLock()
    private var perURLBytes: [URL: Data] = [:]
    var delay: Duration = .zero
    var throwError: Error?

    func setBytes(_ data: Data, for url: URL) {
        lock.withLock { perURLBytes[url] = data }
    }

    func fetch(url: URL) async throws -> Data {
        if delay > .zero {
            try? await Task.sleep(for: delay)
        }
        if let err = throwError { throw err }
        guard let bytes = lock.withLock({ perURLBytes[url] }) else {
            throw URLError(.fileDoesNotExist)
        }
        return bytes
    }
}

@MainActor
private final class PublishRecorder {
    private(set) var values: [Data?] = []
    func record(_ data: Data?) { values.append(data) }
    var latest: Data?? { values.last }
}

// MARK: - Helpers

private func makeTempDir() throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("StreamingArtworkPublishingTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@MainActor
private func makePublisher(
    resolver: StubResolver,
    fetcher: StubFetcher,
    diskCache: StreamingArtworkDiskCache,
    recorder: PublishRecorder
) -> StreamingArtworkPublisher {
    StreamingArtworkPublisher(
        resolver: resolver,
        fetcher: fetcher,
        diskCache: diskCache,
        publish: { data in recorder.record(data) }
    )
}

private func track(_ title: String, artist: String = "Test Artist") -> TrackIdentity {
    TrackIdentity(title: title, artist: artist)
}

// MARK: - Suite

@MainActor
@Suite("StreamingArtworkPublishing (LF.6.streaming)")
struct StreamingArtworkPublishingTests {

    @Test("Resolvable artwork lands in currentTrackArtworkData")
    func test_resolvableArtworkPublishes() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let resolver = StubResolver()
        let fetcher = StubFetcher()
        let cache = StreamingArtworkDiskCache(directoryURL: dir, maxBytes: 1024 * 1024)
        let recorder = PublishRecorder()
        let publisher = makePublisher(resolver: resolver, fetcher: fetcher, diskCache: cache, recorder: recorder)

        let url = try #require(URL(string: "https://i.scdn.co/image/album-a.jpg"))
        let bytes = Data(repeating: 0xAB, count: 128)
        resolver.setURL(url, for: "TrackA")
        fetcher.setBytes(bytes, for: url)

        await publisher.update(for: track("TrackA")).value

        // Most recent published value is the resolved bytes.
        #expect(recorder.values.last == bytes)
    }

    @Test("Unresolvable artwork → nil published")
    func test_unresolvableArtworkPublishesNil() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let resolver = StubResolver()
        let fetcher = StubFetcher()
        let cache = StreamingArtworkDiskCache(directoryURL: dir, maxBytes: 1024 * 1024)
        let recorder = PublishRecorder()
        let publisher = makePublisher(resolver: resolver, fetcher: fetcher, diskCache: cache, recorder: recorder)

        // No URL set in resolver → resolveArtworkURL returns nil.
        await publisher.update(for: track("UnknownTrack")).value

        #expect(recorder.values.last == .some(nil),
                "Unresolvable track must publish nil so the chrome falls back to the glyph")
    }

    @Test("Fetcher error → nil published (no crash, no stale bytes)")
    func test_fetchErrorPublishesNil() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let resolver = StubResolver()
        let fetcher = StubFetcher()
        fetcher.throwError = URLError(.timedOut)
        let cache = StreamingArtworkDiskCache(directoryURL: dir, maxBytes: 1024 * 1024)
        let recorder = PublishRecorder()
        let publisher = makePublisher(resolver: resolver, fetcher: fetcher, diskCache: cache, recorder: recorder)

        let url = try #require(URL(string: "https://i.scdn.co/image/slow.jpg"))
        resolver.setURL(url, for: "SlowTrack")

        await publisher.update(for: track("SlowTrack")).value

        #expect(recorder.values.last == .some(nil))
    }

    @Test("Disk-cache hit short-circuits the fetcher")
    func test_diskCacheHitSkipsFetcher() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let resolver = StubResolver()
        let fetcher = StubFetcher()
        fetcher.throwError = URLError(.notConnectedToInternet)  // would fail if invoked
        let cache = StreamingArtworkDiskCache(directoryURL: dir, maxBytes: 1024 * 1024)
        let recorder = PublishRecorder()
        let publisher = makePublisher(resolver: resolver, fetcher: fetcher, diskCache: cache, recorder: recorder)

        let url = try #require(URL(string: "https://i.scdn.co/image/cached.jpg"))
        let bytes = Data(repeating: 0xCD, count: 64)
        await cache.store(bytes, for: url)
        resolver.setURL(url, for: "CachedTrack")

        await publisher.update(for: track("CachedTrack")).value
        #expect(recorder.values.last == bytes,
                "Disk-cache hit must publish cached bytes without calling fetcher")
    }

    @Test("Rapid A → B cancels A; only B's bytes ever appear")
    func test_rapidTrackChangeCancelsPrior() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let resolver = StubResolver()
        let fetcher = StubFetcher()
        // A's resolve is slow so B has time to launch and overtake.
        resolver.delay = .milliseconds(200)
        let cache = StreamingArtworkDiskCache(directoryURL: dir, maxBytes: 1024 * 1024)
        let recorder = PublishRecorder()
        let publisher = makePublisher(resolver: resolver, fetcher: fetcher, diskCache: cache, recorder: recorder)

        let urlA = try #require(URL(string: "https://i.scdn.co/image/a.jpg"))
        let urlB = try #require(URL(string: "https://i.scdn.co/image/b.jpg"))
        let bytesA = Data(repeating: 0xAA, count: 32)
        let bytesB = Data(repeating: 0xBB, count: 32)
        resolver.setURL(urlA, for: "A")
        resolver.setURL(urlB, for: "B")
        fetcher.setBytes(bytesA, for: urlA)
        fetcher.setBytes(bytesB, for: urlB)

        // Fire A then immediately fire B before A's slow resolve completes.
        publisher.update(for: track("A"))
        // Yield so A's task has a moment to start its resolve+sleep.
        try? await Task.sleep(for: .milliseconds(10))
        let taskB = publisher.update(for: track("B"))
        // Wait long enough that both A's slow resolve and B's fast path would
        // have completed.
        await taskB.value
        try? await Task.sleep(for: .milliseconds(300))

        // The recorder must NEVER have observed A's bytes.
        #expect(!recorder.values.contains(bytesA),
                "Cancelled A must never publish its bytes")
        // The latest published value should be B's bytes.
        #expect(recorder.values.last == bytesB,
                "B's bytes must be the final published value")
    }

    @Test("nil track-change publishes nil and cancels in-flight")
    func test_nilTrackPublishesNilAndCancels() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let resolver = StubResolver()
        let fetcher = StubFetcher()
        resolver.delay = .milliseconds(200)
        let cache = StreamingArtworkDiskCache(directoryURL: dir, maxBytes: 1024 * 1024)
        let recorder = PublishRecorder()
        let publisher = makePublisher(resolver: resolver, fetcher: fetcher, diskCache: cache, recorder: recorder)

        let urlA = try #require(URL(string: "https://i.scdn.co/image/a.jpg"))
        let bytesA = Data(repeating: 0xAA, count: 32)
        resolver.setURL(urlA, for: "A")
        fetcher.setBytes(bytesA, for: urlA)

        publisher.update(for: track("A"))
        try? await Task.sleep(for: .milliseconds(10))
        publisher.update(for: nil)
        // Give A's slow resolve a chance to finish if cancellation didn't work.
        try? await Task.sleep(for: .milliseconds(300))

        #expect(!recorder.values.contains(bytesA),
                "Cancelled A must never publish its bytes after a nil update")
        // Last publish was the explicit nil from `update(for: nil)`.
        #expect(recorder.values.last == .some(nil))
    }
}
