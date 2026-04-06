// MetadataPreFetcherTests — Tests for parallel fetching, caching, merging, and timeouts.

import Testing
import Foundation
@testable import Audio
@testable import Shared

@Suite("MetadataPreFetcher")
struct MetadataPreFetcherTests {

    // MARK: - Helpers

    private func makeTrack(title: String = "Test Song", artist: String = "Test Artist") -> TrackMetadata {
        TrackMetadata(title: title, artist: artist, source: .nowPlaying)
    }

    // MARK: - Tests

    @Test func fetch_validTrack_returnsProfile() async {
        let fetcher = MockMetadataFetcher(
            sourceName: "TestSource",
            stubbedResult: PartialTrackProfile(bpm: 120)
        )
        let prefetcher = MetadataPreFetcher(fetchers: [fetcher])

        let profile = await prefetcher.prefetch(for: makeTrack())

        #expect(profile != nil)
        #expect(profile?.bpm == 120)
    }

    @Test func fetch_cachedTrack_returnsImmediately() async {
        let fetcher = MockMetadataFetcher(
            sourceName: "TestSource",
            stubbedResult: PartialTrackProfile(bpm: 128)
        )
        let prefetcher = MetadataPreFetcher(fetchers: [fetcher])
        let track = makeTrack()

        // First fetch — hits network.
        _ = await prefetcher.prefetch(for: track)
        #expect(fetcher.fetchCallCount == 1)

        // Second fetch — should hit cache, no new network call.
        let cached = await prefetcher.prefetch(for: track)
        #expect(fetcher.fetchCallCount == 1)
        #expect(cached?.bpm == 128)
    }

    @Test func fetch_parallelQueries_allSourcesQueried() async {
        let fetcherA = MockMetadataFetcher(sourceName: "A", stubbedResult: PartialTrackProfile(bpm: 120))
        let fetcherB = MockMetadataFetcher(sourceName: "B", stubbedResult: PartialTrackProfile(energy: 0.8))
        let fetcherC = MockMetadataFetcher(sourceName: "C", stubbedResult: PartialTrackProfile(valence: 0.6))
        let prefetcher = MetadataPreFetcher(fetchers: [fetcherA, fetcherB, fetcherC])

        _ = await prefetcher.prefetch(for: makeTrack())

        #expect(fetcherA.fetchCallCount == 1)
        #expect(fetcherB.fetchCallCount == 1)
        #expect(fetcherC.fetchCallCount == 1)
    }

    @Test func fetch_partialResults_returnsAvailableData() async {
        let fetcherA = MockMetadataFetcher(sourceName: "A", stubbedResult: PartialTrackProfile(bpm: 120))
        let fetcherB = MockMetadataFetcher(sourceName: "B", stubbedResult: nil)  // Failure
        let prefetcher = MetadataPreFetcher(fetchers: [fetcherA, fetcherB])

        let profile = await prefetcher.prefetch(for: makeTrack())

        #expect(profile != nil)
        #expect(profile?.bpm == 120)
    }

    @Test func fetch_networkTimeout_returnsWithinBudget() async {
        let slowFetcher = MockMetadataFetcher(
            sourceName: "Slow",
            stubbedResult: PartialTrackProfile(bpm: 999),
            fetchDelay: .seconds(10)
        )
        let fastFetcher = MockMetadataFetcher(
            sourceName: "Fast",
            stubbedResult: PartialTrackProfile(energy: 0.5)
        )
        let prefetcher = MetadataPreFetcher(
            fetchers: [slowFetcher, fastFetcher],
            timeoutSeconds: 1.0
        )

        let start = ContinuousClock.now
        let profile = await prefetcher.prefetch(for: makeTrack())
        let elapsed = ContinuousClock.now - start

        // Should complete within timeout + buffer, not wait for slow fetcher.
        #expect(elapsed < .seconds(3))
        #expect(profile?.energy == 0.5)
    }

    @Test func fetch_allSourcesFail_returnsNil() async {
        let fetcherA = MockMetadataFetcher(sourceName: "A", stubbedResult: nil)
        let fetcherB = MockMetadataFetcher(sourceName: "B", stubbedResult: nil)
        let prefetcher = MetadataPreFetcher(fetchers: [fetcherA, fetcherB])

        let profile = await prefetcher.prefetch(for: makeTrack())

        #expect(profile == nil)
    }

    @Test func cache_eviction_lruOrder() async {
        let fetcher = MockMetadataFetcher(sourceName: "S", stubbedResult: PartialTrackProfile(bpm: 1))
        let prefetcher = MetadataPreFetcher(fetchers: [fetcher], maxCacheSize: 3)

        // Fill cache with 3 entries.
        _ = await prefetcher.prefetch(for: makeTrack(title: "A", artist: "X"))
        _ = await prefetcher.prefetch(for: makeTrack(title: "B", artist: "X"))
        _ = await prefetcher.prefetch(for: makeTrack(title: "C", artist: "X"))

        // Insert 4th — should evict "A".
        _ = await prefetcher.prefetch(for: makeTrack(title: "D", artist: "X"))

        let evicted = prefetcher.cachedProfile(for: makeTrack(title: "A", artist: "X"))
        let kept = prefetcher.cachedProfile(for: makeTrack(title: "B", artist: "X"))

        #expect(evicted == nil)
        #expect(kept != nil)
    }

    @Test func cache_sameTrack_noRedundantNetworkCalls() async {
        let fetcher = MockMetadataFetcher(sourceName: "S", stubbedResult: PartialTrackProfile(bpm: 140))
        let prefetcher = MetadataPreFetcher(fetchers: [fetcher])
        let track = makeTrack()

        _ = await prefetcher.prefetch(for: track)
        _ = await prefetcher.prefetch(for: track)
        _ = await prefetcher.prefetch(for: track)

        #expect(fetcher.fetchCallCount == 1)
    }

    @Test func preFetchedProfile_bpmPresent_whenSourceResponds() async {
        let fetcher = MockMetadataFetcher(
            sourceName: "Spotify",
            stubbedResult: PartialTrackProfile(bpm: 128, key: "C major", energy: 0.7)
        )
        let prefetcher = MetadataPreFetcher(fetchers: [fetcher])

        let profile = await prefetcher.prefetch(for: makeTrack())

        #expect(profile?.bpm == 128)
        #expect(profile?.key == "C major")
        #expect(profile?.energy == 0.7)
    }

    @Test func fetch_genreTags_areUnioned() async {
        let fetcherA = MockMetadataFetcher(
            sourceName: "A",
            stubbedResult: PartialTrackProfile(genreTags: ["rock", "alternative"])
        )
        let fetcherB = MockMetadataFetcher(
            sourceName: "B",
            stubbedResult: PartialTrackProfile(genreTags: ["indie", "rock"])
        )
        let prefetcher = MetadataPreFetcher(fetchers: [fetcherA, fetcherB])

        let profile = await prefetcher.prefetch(for: makeTrack())

        #expect(profile != nil)
        // Genre tags should be unioned and deduplicated.
        let tags = profile?.genreTags ?? []
        #expect(tags.contains("rock"))
        #expect(tags.contains("alternative"))
        #expect(tags.contains("indie"))
        // "rock" should appear only once.
        #expect(tags.filter { $0 == "rock" }.count == 1)
    }
}
