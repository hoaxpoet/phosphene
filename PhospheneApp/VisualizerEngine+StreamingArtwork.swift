// VisualizerEngine+StreamingArtwork — LF.6.streaming-S5 wiring.
//
// The streaming-side track-change callback owns the artwork-publish flow
// for Spotify / Apple Music / tap-path sessions. LF.6 ships LF-side
// artwork via `currentTrackArtworkData`; LF.6.streaming feeds the same
// publisher from the network.
//
// Flow per streaming track-change:
//   1. Title publishes; artwork publishes nil immediately (LF.6 invariant
//      — title-first then artwork-second within the same MainActor tick).
//   2. `StreamingArtworkPublisher.update(for:)` cancels any in-flight
//      previous-track task, resolves the artwork URL (Spotify-first +
//      iTunes Search fallback), checks the disk cache, falls back to
//      a network fetch, persists to the cache, and publishes bytes on
//      the MainActor — gated on `!Task.isCancelled` so a rapid
//      A → B track-change can never let A's bytes overwrite B's state.
//   3. On any failure (resolver returns nil, fetch throws), publishes
//      nil so the chrome falls back to the glyph.
//
// The publisher is extracted from `VisualizerEngine` itself so tests
// can drive the flow with stub deps + a recorded-publish closure
// without spinning up the full Metal pipeline.

import Foundation
import Session
import os.log

// MARK: - StreamingArtworkPublisher

/// Owns the resolver / fetcher / disk-cache trio plus the in-flight
/// `Task` so a track-change can cancel-and-replace cleanly.
@MainActor
final class StreamingArtworkPublisher {

    // MARK: - Deps

    private let resolver: StreamingArtworkURLResolving
    private let fetcher: StreamingArtworkFetching
    private let diskCache: StreamingArtworkDiskCache
    private let publish: @MainActor (Data?) -> Void

    private let logger = Logger(
        subsystem: "com.phosphene.app",
        category: "StreamingArtworkPublisher"
    )

    // MARK: - State

    /// The most-recently-launched fetch task. Cancelled on every new
    /// `update(for:)` call so A → B can never let A's bytes win.
    private var inFlight: Task<Void, Never>?

    // MARK: - Init

    init(
        resolver: StreamingArtworkURLResolving,
        fetcher: StreamingArtworkFetching,
        diskCache: StreamingArtworkDiskCache,
        publish: @escaping @MainActor (Data?) -> Void
    ) {
        self.resolver = resolver
        self.fetcher = fetcher
        self.diskCache = diskCache
        self.publish = publish
    }

    // MARK: - Public API

    /// Cancel any in-flight artwork task and start fetching for `track`.
    /// Pass `nil` (track-cleared) to abort and stay nil.
    @discardableResult
    func update(for track: TrackIdentity?) -> Task<Void, Never> {
        // Cancel-and-replace; B's fetch must always win over A's.
        inFlight?.cancel()

        guard let track else {
            publish(nil)
            let noop = Task<Void, Never> {}
            inFlight = noop
            return noop
        }

        let ctx = FlowContext(
            resolver: resolver,
            fetcher: fetcher,
            diskCache: diskCache,
            publish: publish,
            logger: logger
        )
        let task = Task { @MainActor in
            await Self.resolveFetchAndPublish(track: track, ctx: ctx)
        }
        inFlight = task
        return task
    }

    /// Bundle of dependencies passed into the resolve → fetch → publish
    /// chain. Exists to keep `resolveFetchAndPublish` under the function-
    /// parameter-count lint limit while still being injectable.
    private struct FlowContext {
        let resolver: StreamingArtworkURLResolving
        let fetcher: StreamingArtworkFetching
        let diskCache: StreamingArtworkDiskCache
        let publish: @MainActor (Data?) -> Void
        let logger: Logger
    }

    /// Run the resolve → disk-cache → fetch → publish chain. Every publish
    /// is gated on `!Task.isCancelled` so a cancelled task never writes.
    @MainActor
    private static func resolveFetchAndPublish(
        track: TrackIdentity,
        ctx: FlowContext
    ) async {
        // 1) Resolve URL (Spotify-first hint → iTunes Search fallback).
        guard let url = await ctx.resolver.resolveArtworkURL(for: track) else {
            if !Task.isCancelled { ctx.publish(nil) }
            return
        }
        if Task.isCancelled { return }

        // 2) Disk cache hit — no network needed.
        if let cached = await ctx.diskCache.bytes(for: url) {
            if !Task.isCancelled { ctx.publish(cached) }
            return
        }
        if Task.isCancelled { return }

        // 3) Network fetch + persist + publish.
        do {
            let data = try await ctx.fetcher.fetch(url: url)
            if Task.isCancelled { return }
            await ctx.diskCache.store(data, for: url)
            if !Task.isCancelled { ctx.publish(data) }
        } catch {
            ctx.logger.info("artwork fetch failed for \(track.title): \(error.localizedDescription)")
            if !Task.isCancelled { ctx.publish(nil) }
        }
    }
}
