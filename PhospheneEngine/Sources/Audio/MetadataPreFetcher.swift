// MetadataPreFetcher — Parallel async queries to external music databases.
// Queries MusicBrainz, Spotify Web API, and other sources concurrently,
// merges partial results, and caches in an LRU cache.

import Foundation
import OrderedCollections
import Shared
import os.log

private let logger = Logging.metadata

// MARK: - MetadataPreFetcher

/// Pre-fetches rich track metadata from external APIs.
///
/// On a track change, fires all configured fetchers in parallel with
/// per-fetcher timeouts. Partial results are merged into a single
/// `PreFetchedTrackProfile` and cached in an LRU cache.
/// Network failures are always silent — metadata is optional.
public final class MetadataPreFetcher: @unchecked Sendable {

    // MARK: - Configuration

    private let fetchers: [any MetadataFetching]
    private let timeoutSeconds: Double
    private let maxCacheSize: Int

    // MARK: - Cache

    private var cache: OrderedDictionary<String, PreFetchedTrackProfile> = [:]
    private let lock = NSLock()

    // MARK: - Init

    /// Create a metadata pre-fetcher.
    ///
    /// - Parameters:
    ///   - fetchers: External API fetchers to query in parallel.
    ///   - timeoutSeconds: Per-fetcher timeout (default 3 seconds).
    ///   - maxCacheSize: Maximum LRU cache entries (default 50).
    public init(
        fetchers: [any MetadataFetching] = [],
        timeoutSeconds: Double = 3.0,
        maxCacheSize: Int = 50
    ) {
        self.fetchers = fetchers
        self.timeoutSeconds = timeoutSeconds
        self.maxCacheSize = maxCacheSize
    }

    // MARK: - Public API

    /// Pre-fetch metadata for a track from all configured sources.
    ///
    /// Returns cached data immediately on cache hit. On cache miss,
    /// queries all fetchers in parallel with timeouts and merges results.
    /// Returns nil if the track is unfetchable or all sources fail.
    public func prefetch(for track: TrackMetadata) async -> PreFetchedTrackProfile? {
        guard let key = cacheKey(for: track) else {
            logger.debug("Track not fetchable: missing title or artist")
            return nil
        }

        // Cache hit — promote in LRU order and return.
        if let cached = lock.withLock({ promoteAndGet(key: key) }) {
            logger.debug("Cache hit for \(track.title ?? "?")")
            return cached
        }

        guard !fetchers.isEmpty else {
            logger.debug("No fetchers configured")
            return nil
        }

        guard let title = track.title, let artist = track.artist else { return nil }

        // Fire all fetchers in parallel with per-fetcher timeouts.
        let partials = await withTaskGroup(of: PartialTrackProfile?.self) { group in
            for fetcher in fetchers {
                group.addTask { [timeoutSeconds] in
                    await Self.fetchWithTimeout(
                        fetcher,
                        title: title,
                        artist: artist,
                        timeout: timeoutSeconds
                    )
                }
            }

            var results: [PartialTrackProfile] = []
            for await partial in group {
                if let partial {
                    results.append(partial)
                }
            }
            return results
        }

        guard !partials.isEmpty else {
            logger.info("All sources failed for \(title) — \(artist)")
            return nil
        }

        let profile = merge(partials)
        lock.withLock { insertIntoCache(key: key, profile: profile) }
        logger.info("Pre-fetched profile for \(title) — \(artist) from \(partials.count) source(s)")

        return profile
    }

    /// Synchronous cache lookup without triggering any network calls.
    /// Promotes the entry in LRU order on hit.
    public func cachedProfile(for track: TrackMetadata) -> PreFetchedTrackProfile? {
        guard let key = cacheKey(for: track) else { return nil }
        return lock.withLock { promoteAndGet(key: key) }
    }

    // MARK: - Cache Key

    func cacheKey(for track: TrackMetadata) -> String? {
        guard track.isFetchable,
              let title = track.title,
              let artist = track.artist else { return nil }
        return "\(title.lowercased())|\(artist.lowercased())"
    }

    // MARK: - LRU Cache Internals

    /// Promote an entry to the end of the ordered dictionary (most recently used)
    /// and return its value. Returns nil on cache miss.
    private func promoteAndGet(key: String) -> PreFetchedTrackProfile? {
        guard let value = cache[key] else { return nil }
        cache.removeValue(forKey: key)
        cache[key] = value
        return value
    }

    /// Insert a profile into the cache, evicting the oldest entry if at capacity.
    private func insertIntoCache(key: String, profile: PreFetchedTrackProfile) {
        if cache.count >= maxCacheSize {
            cache.removeFirst()
        }
        cache[key] = profile
    }

    // MARK: - Parallel Fetch with Timeout

    private static func fetchWithTimeout(
        _ fetcher: any MetadataFetching,
        title: String,
        artist: String,
        timeout: Double
    ) async -> PartialTrackProfile? {
        await withTaskGroup(of: PartialTrackProfile?.self) { group in
            group.addTask {
                await fetcher.fetch(title: title, artist: artist)
            }

            group.addTask {
                try? await Task.sleep(for: .seconds(timeout))
                return nil
            }

            // First result wins. If the timeout finishes first, cancel the fetch.
            // `group.next()` returns an Optional<Optional<_>> — flatten it.
            let result = await group.next()
            group.cancelAll()
            return result.flatMap { $0 }
        }
    }

    // MARK: - Merge

    /// Merge multiple partial profiles into a single `PreFetchedTrackProfile`.
    /// First non-nil value wins for scalar fields; genre tags are unioned.
    func merge(_ partials: [PartialTrackProfile]) -> PreFetchedTrackProfile {
        var bpm: Float?
        var key: String?
        var energy: Float?
        var valence: Float?
        var danceability: Float?
        var duration: Double?
        var timeSignature: Int?
        var allGenres: [String] = []

        for partial in partials {
            if bpm == nil { bpm = partial.bpm }
            if key == nil { key = partial.key }
            if energy == nil { energy = partial.energy }
            if valence == nil { valence = partial.valence }
            if danceability == nil { danceability = partial.danceability }
            if duration == nil { duration = partial.duration }
            if timeSignature == nil { timeSignature = partial.timeSignature }
            allGenres.append(contentsOf: partial.genreTags)
        }

        // Deduplicate genre tags while preserving order.
        var seen = Set<String>()
        let uniqueGenres = allGenres.filter { seen.insert($0).inserted }

        return PreFetchedTrackProfile(
            bpm: bpm,
            key: key,
            energy: energy,
            valence: valence,
            danceability: danceability,
            genreTags: uniqueGenres,
            duration: duration,
            timeSignature: timeSignature
        )
    }
}
