// PersistentStemCacheEvictionTests — LF.4 / D-131 housekeeping coverage.
//
// totalBytes() accuracy, evictToMaxBytes() boundary cases, clearAll(),
// mtime-driven eviction ordering, and the store(...)-triggered automatic
// eviction path.
//
// Each test uses a fresh temp directory and explicit cap overrides so it
// doesn't depend on UserDefaults state from the user's machine.

import Foundation
import Testing
@testable import DSP
@testable import Session
@testable import Shared

@Suite("PersistentStemCache + eviction (LF.4)")
struct PersistentStemCacheEvictionTests {

    // MARK: - Fixtures

    private static func makeTempDir() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("PersistentStemCacheEvictionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Returns a 64-char lowercase hex pseudo-hash starting with the given
    /// 2-char prefix. The cache treats this as an opaque key string.
    private static func hash(prefix: String, suffix: String = String(repeating: "0", count: 62)) -> String {
        precondition(prefix.count == 2)
        return prefix + suffix
    }

    private static func smallCachedTrack(stemSampleCount: Int = 256) -> CachedTrackData {
        let stems: [[Float]] = (0..<4).map { stemIndex in
            (0..<stemSampleCount).map { sampleIndex in
                Float(stemIndex) * 0.1 + Float(sampleIndex) * 0.001
            }
        }
        let stemFeatures = StemFeatures(
            vocalsEnergy: 0.1, vocalsBand0: 0, vocalsBand1: 0, vocalsBeat: 0,
            drumsEnergy: 0.1, drumsBand0: 0, drumsBand1: 0, drumsBeat: 0,
            bassEnergy: 0.1, bassBand0: 0, bassBand1: 0, bassBeat: 0,
            otherEnergy: 0.1, otherBand0: 0, otherBand1: 0, otherBeat: 0
        )
        return CachedTrackData(
            stemWaveforms: stems,
            stemFeatures: stemFeatures,
            trackProfile: TrackProfile(),
            beatGrid: .empty,
            drumsBeatGrid: .empty,
            gridOnsetOffsetMs: 0
        )
    }

    // MARK: - totalBytes()

    @Test func totalBytes_emptyCache_returnsZero() throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cache = try PersistentStemCache(rootDirectory: dir, maxBytes: Int64.max)

        #expect(cache.totalBytes() == 0)
    }

    @Test func totalBytes_oneEntry_matchesActualFileSizes() throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cache = try PersistentStemCache(rootDirectory: dir, maxBytes: Int64.max)
        try cache.store(Self.smallCachedTrack(), hash: Self.hash(prefix: "aa"), decodedDuration: 10)

        let bytes = cache.totalBytes()
        // One entry: 4 stem files (256 samples × 4 bytes = 1024 bytes each = 4096) + metadata.json (~2 KB).
        #expect(bytes > 4096, "Expected at least 4 KB (stems alone) but got \(bytes)")
        #expect(bytes < 20_000, "Expected at most ~20 KB for one small entry but got \(bytes)")
    }

    @Test func totalBytes_multipleEntries_sumsCorrectly() throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cache = try PersistentStemCache(rootDirectory: dir, maxBytes: Int64.max)
        try cache.store(Self.smallCachedTrack(), hash: Self.hash(prefix: "aa"), decodedDuration: 10)
        let oneEntryBytes = cache.totalBytes()
        try cache.store(Self.smallCachedTrack(), hash: Self.hash(prefix: "bb"), decodedDuration: 10)

        let twoEntriesBytes = cache.totalBytes()
        #expect(twoEntriesBytes > oneEntryBytes)
        #expect(twoEntriesBytes >= 2 * oneEntryBytes - 100, "two entries should be ~2× one entry")
    }

    // MARK: - evictToMaxBytes() boundary cases

    @Test func evictToMaxBytes_capZero_evictsAll() throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cache = try PersistentStemCache(rootDirectory: dir, maxBytes: Int64.max)
        try cache.store(Self.smallCachedTrack(), hash: Self.hash(prefix: "aa"), decodedDuration: 10)
        try cache.store(Self.smallCachedTrack(), hash: Self.hash(prefix: "bb"), decodedDuration: 10)
        try cache.store(Self.smallCachedTrack(), hash: Self.hash(prefix: "cc"), decodedDuration: 10)

        let evicted = try cache.evictToMaxBytes(0)

        #expect(evicted == 3)
        #expect(cache.totalBytes() == 0)
        #expect(cache.contains(hash: Self.hash(prefix: "aa")) == false)
        #expect(cache.contains(hash: Self.hash(prefix: "bb")) == false)
        #expect(cache.contains(hash: Self.hash(prefix: "cc")) == false)
    }

    @Test func evictToMaxBytes_capLarge_evictsNothing() throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cache = try PersistentStemCache(rootDirectory: dir, maxBytes: Int64.max)
        try cache.store(Self.smallCachedTrack(), hash: Self.hash(prefix: "aa"), decodedDuration: 10)
        try cache.store(Self.smallCachedTrack(), hash: Self.hash(prefix: "bb"), decodedDuration: 10)

        let evicted = try cache.evictToMaxBytes(Int64.max)

        #expect(evicted == 0)
        #expect(cache.contains(hash: Self.hash(prefix: "aa")))
        #expect(cache.contains(hash: Self.hash(prefix: "bb")))
    }

    @Test func evictToMaxBytes_capMidpoint_evictsOldestFirst() throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cache = try PersistentStemCache(rootDirectory: dir, maxBytes: Int64.max)

        // Insert three entries with deliberate mtime spacing so the eviction
        // order is unambiguous. Each store writes metadata.json with the
        // wall-clock now; the small sleeps spread them across distinct ticks.
        try cache.store(Self.smallCachedTrack(), hash: Self.hash(prefix: "aa"), decodedDuration: 10)
        try Self.sleep(seconds: 1.1)
        try cache.store(Self.smallCachedTrack(), hash: Self.hash(prefix: "bb"), decodedDuration: 10)
        try Self.sleep(seconds: 1.1)
        try cache.store(Self.smallCachedTrack(), hash: Self.hash(prefix: "cc"), decodedDuration: 10)

        let totalBefore = cache.totalBytes()
        let oneEntryBytes = totalBefore / 3
        let midpoint = oneEntryBytes * 2 + (oneEntryBytes / 2)

        let evicted = try cache.evictToMaxBytes(midpoint)

        // Should evict the oldest one (aa) to bring total under midpoint.
        #expect(evicted >= 1)
        #expect(cache.contains(hash: Self.hash(prefix: "aa")) == false, "oldest entry should be evicted first")
        #expect(cache.contains(hash: Self.hash(prefix: "cc")), "newest entry should survive")
    }

    @Test func evictToMaxBytes_mtimeOrdering_touchedEntryStaysLonger() throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cache = try PersistentStemCache(rootDirectory: dir, maxBytes: Int64.max)

        try cache.store(Self.smallCachedTrack(), hash: Self.hash(prefix: "aa"), decodedDuration: 10)
        try Self.sleep(seconds: 1.1)
        try cache.store(Self.smallCachedTrack(), hash: Self.hash(prefix: "bb"), decodedDuration: 10)
        try Self.sleep(seconds: 1.1)
        // Re-store aa — bumps its metadata.json mtime to the most recent.
        try cache.store(Self.smallCachedTrack(), hash: Self.hash(prefix: "aa"), decodedDuration: 10)

        // Evict to fit just one entry — bb (now oldest) should go.
        let totalBefore = cache.totalBytes()
        let oneEntryBytes = totalBefore / 2

        _ = try cache.evictToMaxBytes(oneEntryBytes)

        #expect(cache.contains(hash: Self.hash(prefix: "aa")), "re-stored entry has newest mtime and survives")
        #expect(cache.contains(hash: Self.hash(prefix: "bb")) == false, "older mtime entry is evicted")
    }

    // MARK: - clearAll()

    @Test func clearAll_emptiesCache_preservesRootDirectory() throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cache = try PersistentStemCache(rootDirectory: dir, maxBytes: Int64.max)
        try cache.store(Self.smallCachedTrack(), hash: Self.hash(prefix: "aa"), decodedDuration: 10)
        try cache.store(Self.smallCachedTrack(), hash: Self.hash(prefix: "bb"), decodedDuration: 10)

        let freed = try cache.clearAll()

        #expect(freed > 0)
        #expect(cache.totalBytes() == 0)
        #expect(cache.contains(hash: Self.hash(prefix: "aa")) == false)
        // Root directory is preserved so subsequent store()s don't need to recreate it.
        #expect(FileManager.default.fileExists(atPath: dir.path))
    }

    @Test func clearAll_onEmptyCache_isNoOp() throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cache = try PersistentStemCache(rootDirectory: dir, maxBytes: Int64.max)

        let freed = try cache.clearAll()

        #expect(freed == 0)
    }

    // MARK: - Automatic eviction from store(...)

    @Test func store_respectsInjectedCap_triggersAutoEviction() throws {
        // Measure one entry's actual on-disk size, then set the cap to
        // ~1.5× that — guarantees one entry fits while two don't.
        let probeDir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: probeDir) }
        let probe = try PersistentStemCache(rootDirectory: probeDir, maxBytes: Int64.max)
        try probe.store(Self.smallCachedTrack(), hash: Self.hash(prefix: "zz"), decodedDuration: 10)
        let oneEntryBytes = probe.totalBytes()

        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        // Cap headroom: 1.5× one entry → fits exactly one entry; 2nd store evicts.
        let cap = oneEntryBytes * 3 / 2
        let cache = try PersistentStemCache(rootDirectory: dir, maxBytes: cap)
        try cache.store(Self.smallCachedTrack(), hash: Self.hash(prefix: "aa"), decodedDuration: 10)
        try Self.sleep(seconds: 1.1)
        try cache.store(Self.smallCachedTrack(), hash: Self.hash(prefix: "bb"), decodedDuration: 10)

        // After the second store, the auto-evict pass should have removed the older entry.
        #expect(cache.contains(hash: Self.hash(prefix: "bb")), "newer entry survives")
        #expect(cache.contains(hash: Self.hash(prefix: "aa")) == false, "older entry evicted under cap")
        #expect(cache.totalBytes() <= cap, "post-eviction total \(cache.totalBytes()) > cap \(cap)")
    }

    @Test func defaultMaxBytes_matchesPrompt() throws {
        // Validates the documented LF.4 default (500 MB ≈ 70 cached tracks at ~7 MB/track).
        // No UserDefaults dependency — `defaultMaxBytes` is a static const.
        #expect(PersistentStemCache.defaultMaxBytes == 500 * 1024 * 1024)
    }

    // MARK: - Helpers

    /// Sleep just over 1 second to ensure HFS+/APFS mtime granularity advances.
    /// macOS APFS reports nanosecond resolution but writes pass through the
    /// VFS layer which can clamp to whole-second precision under some
    /// conditions — the 1.1 s buffer makes the test robust either way.
    private static func sleep(seconds: TimeInterval) throws {
        Thread.sleep(forTimeInterval: seconds)
    }
}
