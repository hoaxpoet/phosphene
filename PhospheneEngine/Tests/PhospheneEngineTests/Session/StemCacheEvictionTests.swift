// StemCacheEvictionTests — CLEAN.3.5: the in-memory StemCache is LRU-bounded.
//
// Before CLEAN.3.5 `StemCache` was an unbounded `[TrackIdentity: CachedTrackData]`
// with no eviction and no disk backing for streaming preview data (~7 MB/track), so
// it grew without limit across the engine's lifetime under track churn. It now caps at
// `maxEntries` and evicts the least-recently-used track (bumped on store + loadForPlayback).

import Testing
import Foundation
@testable import Session
@testable import Shared

@Suite("StemCache LRU eviction")
struct StemCacheEvictionTests {

    private func identity(_ title: String) -> TrackIdentity {
        TrackIdentity(title: title, artist: "Artist", duration: 180)
    }

    private func data() -> CachedTrackData {
        CachedTrackData(stemWaveforms: [], stemFeatures: .zero, trackProfile: .empty)
    }

    @Test("Storing past maxEntries evicts the least-recently-used track")
    func evictsLRUOverCap() {
        let cache = StemCache(maxEntries: 2)
        let a = identity("A"), b = identity("B"), c = identity("C")

        cache.store(data(), for: a)
        cache.store(data(), for: b)
        _ = cache.loadForPlayback(track: a)   // A is now more-recently-used than B
        cache.store(data(), for: c)           // exceeds cap 2 → evict the LRU (B)

        #expect(cache.count == 2, "cache must stay bounded at maxEntries")
        #expect(cache.loadForPlayback(track: b) == nil, "B (least-recently-used) should be evicted")
        #expect(cache.loadForPlayback(track: a) != nil, "A (recently used) should survive")
        #expect(cache.loadForPlayback(track: c) != nil, "C (just stored) should be present")
    }

    @Test("Re-storing an existing key updates in place without growing the cache")
    func reStoreSameKeyDoesNotGrow() {
        let cache = StemCache(maxEntries: 2)
        let a = identity("A")
        cache.store(data(), for: a)
        cache.store(data(), for: a)
        #expect(cache.count == 1, "re-storing the same key must not double-count")
    }

    @Test("clear() empties the cache and its LRU order")
    func clearEmpties() {
        let cache = StemCache(maxEntries: 4)
        cache.store(data(), for: identity("A"))
        cache.store(data(), for: identity("B"))
        cache.clear()
        #expect(cache.count == 0)
    }
}
