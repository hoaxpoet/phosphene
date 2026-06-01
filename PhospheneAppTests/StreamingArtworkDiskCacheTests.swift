// StreamingArtworkDiskCacheTests — LF.6.streaming-S4: SHA-256-keyed LRU
// byte cache in `~/Library/Caches/`. Tests use a per-test directory under
// `/tmp` so the real Caches directory is never touched.

import Foundation
import Testing

@testable import PhospheneApp

@Suite("StreamingArtworkDiskCache (LF.6.streaming)")
struct StreamingArtworkDiskCacheTests {

    // MARK: - Helpers

    private static func makeTempDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(
                "StreamingArtworkDiskCacheTests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private static func makeBytes(size: Int, fill: UInt8 = 0x5A) -> Data {
        Data(repeating: fill, count: size)
    }

    // MARK: - Tests

    @Test("store + bytes roundtrip returns identical bytes")
    func test_storeAndBytesRoundtrip() async throws {
        let dir = try Self.makeTempDirectory()
        defer { Self.cleanup(dir) }
        let cache = StreamingArtworkDiskCache(directoryURL: dir, maxBytes: 1024 * 1024)
        let url = try #require(URL(string: "https://i.scdn.co/image/album-a-640.jpg"))
        let payload = Self.makeBytes(size: 256)

        await cache.store(payload, for: url)
        let read = await cache.bytes(for: url)
        #expect(read == payload)
    }

    @Test("bytes returns nil for an unseen URL")
    func test_missReturnsNil() async throws {
        let dir = try Self.makeTempDirectory()
        defer { Self.cleanup(dir) }
        let cache = StreamingArtworkDiskCache(directoryURL: dir, maxBytes: 1024 * 1024)
        let url = try #require(URL(string: "https://i.scdn.co/image/never-stored.jpg"))
        let read = await cache.bytes(for: url)
        #expect(read == nil)
    }

    @Test("persistence survives across cache-instance lifetimes")
    func test_persistenceAcrossInstances() async throws {
        let dir = try Self.makeTempDirectory()
        defer { Self.cleanup(dir) }
        let url = try #require(URL(string: "https://i.scdn.co/image/persist.jpg"))
        let payload = Self.makeBytes(size: 128, fill: 0x33)

        do {
            let writer = StreamingArtworkDiskCache(directoryURL: dir, maxBytes: 1024 * 1024)
            await writer.store(payload, for: url)
        }

        let reader = StreamingArtworkDiskCache(directoryURL: dir, maxBytes: 1024 * 1024)
        let read = await reader.bytes(for: url)
        #expect(read == payload, "Bytes must survive across cache instances (same directory)")
    }

    @Test("LRU eviction drops oldest-modified entries when over cap")
    func test_lruEvictionDropsOldest() async throws {
        let dir = try Self.makeTempDirectory()
        defer { Self.cleanup(dir) }
        // 3 KB cap; each entry 1 KB — first two fit, third forces eviction.
        let cache = StreamingArtworkDiskCache(directoryURL: dir, maxBytes: 3 * 1024)
        let urlA = try #require(URL(string: "https://example.com/a.jpg"))
        let urlB = try #require(URL(string: "https://example.com/b.jpg"))
        let urlC = try #require(URL(string: "https://example.com/c.jpg"))
        let urlD = try #require(URL(string: "https://example.com/d.jpg"))

        // Write A, B, C — under cap (3 KB exactly). Sleep between writes so
        // mtimes differ at the second level.
        await cache.store(Self.makeBytes(size: 1024), for: urlA)
        try await Task.sleep(nanoseconds: 1_100_000_000)
        await cache.store(Self.makeBytes(size: 1024), for: urlB)
        try await Task.sleep(nanoseconds: 1_100_000_000)
        await cache.store(Self.makeBytes(size: 1024), for: urlC)

        // All three present.
        #expect(await cache.bytes(for: urlA) != nil)
        #expect(await cache.bytes(for: urlB) != nil)
        #expect(await cache.bytes(for: urlC) != nil)

        // Re-touch A (the oldest) so B becomes the LRU victim. The above
        // `bytes(for: urlA)` already touched A's mtime, but call again with
        // a delay to guarantee separation from B's mtime.
        try await Task.sleep(nanoseconds: 1_100_000_000)
        _ = await cache.bytes(for: urlA)

        // Now write D — pushes total to 4 KB → trim must evict ≥ 1 KB.
        await cache.store(Self.makeBytes(size: 1024), for: urlD)

        // B is the oldest entry by mtime (never re-touched after creation),
        // so it should have been evicted; A, C, D remain.
        #expect(await cache.bytes(for: urlA) != nil, "Most-recently-touched A must remain")
        #expect(await cache.bytes(for: urlB) == nil, "Oldest entry B must be evicted")
        #expect(await cache.bytes(for: urlC) != nil, "C remains (between A and D in mtime)")
        #expect(await cache.bytes(for: urlD) != nil, "Just-written D must remain")
    }

    @Test("clearAll drops every cached entry")
    func test_clearAll() async throws {
        let dir = try Self.makeTempDirectory()
        defer { Self.cleanup(dir) }
        let cache = StreamingArtworkDiskCache(directoryURL: dir, maxBytes: 1024 * 1024)
        let url1 = try #require(URL(string: "https://example.com/1.jpg"))
        let url2 = try #require(URL(string: "https://example.com/2.jpg"))

        await cache.store(Self.makeBytes(size: 256), for: url1)
        await cache.store(Self.makeBytes(size: 256), for: url2)
        #expect(await cache.bytes(for: url1) != nil)
        #expect(await cache.bytes(for: url2) != nil)

        await cache.clearAll()

        #expect(await cache.bytes(for: url1) == nil)
        #expect(await cache.bytes(for: url2) == nil)
    }

    @Test("corrupt entry on disk returns nil, does not crash")
    func test_corruptEntryReturnsNil() async throws {
        let dir = try Self.makeTempDirectory()
        defer { Self.cleanup(dir) }
        // Pre-create the directory and drop a garbage file that doesn't match
        // any URL hash. The cache should ignore it and return nil for any
        // real URL lookup.
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stray = dir.appendingPathComponent("not-a-real-hash.bin")
        try Data([0x00, 0x01, 0x02]).write(to: stray)

        let cache = StreamingArtworkDiskCache(directoryURL: dir, maxBytes: 1024 * 1024)
        let url = try #require(URL(string: "https://example.com/unrelated.jpg"))
        #expect(await cache.bytes(for: url) == nil)
    }

    @Test("different URLs produce different filenames (no key collision)")
    func test_distinctURLsDistinctEntries() async throws {
        let dir = try Self.makeTempDirectory()
        defer { Self.cleanup(dir) }
        let cache = StreamingArtworkDiskCache(directoryURL: dir, maxBytes: 1024 * 1024)
        let urlA = try #require(URL(string: "https://example.com/a.jpg"))
        let urlB = try #require(URL(string: "https://example.com/b.jpg"))

        let bytesA = Self.makeBytes(size: 64, fill: 0xAA)
        let bytesB = Self.makeBytes(size: 64, fill: 0xBB)
        await cache.store(bytesA, for: urlA)
        await cache.store(bytesB, for: urlB)

        #expect(await cache.bytes(for: urlA) == bytesA)
        #expect(await cache.bytes(for: urlB) == bytesB)
    }
}
