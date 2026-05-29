// AlbumArtworkCache — In-memory decode + downsize layer for LF.6 artwork bytes.
//
// LF.5 persists raw artwork bytes (PNG / JPEG, depending on container)
// alongside each cached LF track. Embedded artwork is commonly shipped at
// 600 × 600 to 3000 × 3000 px even when the chrome only renders a 48 pt
// thumbnail; decoding and drawing at source size every frame is wasteful.
// This cache decodes once per `(cacheKey, byte-identity)` pair, downsizes
// to 64 pt max edge (128 px native @2x retina), and parks the result in an
// `NSCache` capped at 20 entries — comfortably covers a long playlist's
// run of recent tracks while keeping resident memory bounded.
//
// Thread-safety: `NSCache` is already thread-safe. The decode/downsize
// path is pure (no shared state outside the cache), so multiple concurrent
// callers can resolve different keys without contention.
//
// LF.6 scope:
//   - In-memory only. The bytes are already persisted by LF.5's `artwork.bin`;
//     no need to double-cache them on disk.
//   - Source-bytes input. AsyncImage / URL-based loading is intentionally out
//     of scope — LF.6 carries Data, not URLs. LF.6.streaming will keep the
//     same shape and feed the same Data publisher from network-fetched bytes.

import AppKit
import Foundation

// MARK: - AlbumArtworkCache

/// Process-wide in-memory cache that decodes raw artwork bytes once and
/// returns downsized `NSImage` instances on subsequent lookups.
enum AlbumArtworkCache {

    // MARK: - Tuning

    /// Maximum entries retained in the LRU. Each entry is at most ~64 KB of
    /// decoded bitmap (128 × 128 px @4 bytes), so the worst-case resident
    /// footprint is ≲ 1.3 MB even when full.
    static let maxEntries: Int = 20

    /// Maximum edge length of the cached image in points. The chrome renders
    /// the thumbnail at 48 pt; 64 pt gives ~33% headroom for hover scale /
    /// future layouts without re-decoding.
    static let maxEdgePoints: CGFloat = 64

    // MARK: - Cache

    /// Backing `NSCache`. Keyed by `cacheKey` (typically `title|artist`);
    /// the value type is `NSImage`. `NSCache` already evicts on memory
    /// pressure in addition to honouring `countLimit`.
    ///
    /// `nonisolated(unsafe)` per Swift 6 strict concurrency: `NSCache` is
    /// internally thread-safe (Apple-documented), but the type isn't marked
    /// `Sendable` in the SDK. Same pattern as other process-wide caches in
    /// the app layer (e.g. file-system thumbnail caches).
    nonisolated(unsafe) private static let cache: NSCache<NSString, NSImage> = {
        let store = NSCache<NSString, NSImage>()
        store.countLimit = maxEntries
        store.name = "phosphene.AlbumArtworkCache"
        return store
    }()

    // MARK: - Public API

    /// Return the decoded + downsized image for the given artwork bytes
    /// under the given cache key. Returns `nil` when the bytes don't form a
    /// valid image — caller falls back to the no-artwork glyph.
    ///
    /// Cache keying is by `cacheKey` alone, not by byte identity. Two
    /// different artwork variants for the same `(title, artist)` would
    /// collide; for LF.5 this never happens because the bytes are derived
    /// from a stable content-hashed cache entry and identity collisions are
    /// already prevented by the LF.5 cache layer itself.
    static func image(for data: Data, cacheKey: String) -> NSImage? {
        let key = cacheKey as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        guard let decoded = decodeAndDownsize(data) else { return nil }
        cache.setObject(decoded, forKey: key)
        return decoded
    }

    /// Drop everything. Useful for tests and a future "Clear cache" affordance.
    static func clearAll() {
        cache.removeAllObjects()
    }

    // MARK: - Helpers

    /// Decode `data` into an `NSImage`, then redraw it into a fresh bitmap
    /// no larger than `maxEdgePoints × maxEdgePoints` (preserving aspect).
    /// Returns nil when the source bytes can't be decoded (malformed / wrong
    /// magic / 1-pixel error image from a CDN).
    private static func decodeAndDownsize(_ data: Data) -> NSImage? {
        guard let source = NSImage(data: data) else { return nil }
        let sourceSize = source.size
        guard sourceSize.width > 0, sourceSize.height > 0 else { return nil }

        let longest = max(sourceSize.width, sourceSize.height)
        if longest <= maxEdgePoints {
            // Already small enough; cache as-is without an extra redraw.
            return source
        }

        let scale = maxEdgePoints / longest
        let targetSize = NSSize(
            width: round(sourceSize.width * scale),
            height: round(sourceSize.height * scale)
        )
        let downsized = NSImage(size: targetSize)
        downsized.lockFocus()
        defer { downsized.unlockFocus() }
        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: NSRect(origin: .zero, size: sourceSize),
            operation: .copy,
            fraction: 1.0
        )
        return downsized
    }
}
