// StreamingArtworkDiskCache — SHA-256-keyed LRU disk cache for streaming-path
// artwork bytes (LF.6.streaming-S4).
//
// Layout on disk: `<directoryURL>/<sha256(sourceURL)>.bin`.
//
// Location (default): `~/Library/Caches/com.phosphene.app/streaming-artwork/`.
// macOS may purge `Caches/` under disk pressure; we accept that — re-fetch
// costs one HTTP round-trip. Matches Spotify's own client behaviour.
//
// LRU policy: every read touches the file's modification date (used as the
// access-time signal). After every write we sum the cache size; if over
// `maxBytes`, evict oldest-modification-first until under the cap. Trim runs
// inside the actor — never on the render loop.
//
// Concurrency: the type is an `actor`, so all disk I/O is serialised. Disk
// reads/writes for cache hits and stores are small (≲ 100 KB) and infrequent
// (one per streaming track-change, ~1 every few minutes), so per-call I/O
// inside the actor is fine — no need for `Task.detached`.
//
// Corruption tolerance: a malformed `.bin` returns nil from `bytes(for:)`
// rather than crashing, so the caller falls back to a network fetch.

import CryptoKit
import Foundation
import os.log

// MARK: - StreamingArtworkDiskCache

actor StreamingArtworkDiskCache {

    // MARK: - Tuning

    /// Default 100 MB cap — ~1,200 cached tracks at typical Spotify CDN size
    /// (~80 KB JPEG). Picked at LF.6.streaming Pre-Flight Audit (Decision 2).
    static let defaultMaxBytes: Int = 100 * 1024 * 1024

    /// Default cache root: `~/Library/Caches/com.phosphene.app/streaming-artwork/`.
    /// Falls back to a `Library/Caches`-relative path under `$HOME` if the
    /// FileManager lookup ever fails (treated as best-effort).
    static func defaultDirectoryURL() -> URL {
        let caches: URL
        if let url = try? FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) {
            caches = url
        } else {
            caches = URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Caches", isDirectory: true)
        }
        return caches
            .appendingPathComponent("com.phosphene.app", isDirectory: true)
            .appendingPathComponent("streaming-artwork", isDirectory: true)
    }

    // MARK: - State

    private let directoryURL: URL
    private let maxBytes: Int
    private let logger = Logger(
        subsystem: "com.phosphene.app",
        category: "StreamingArtworkDiskCache"
    )

    // MARK: - Init

    init(
        directoryURL: URL = StreamingArtworkDiskCache.defaultDirectoryURL(),
        maxBytes: Int = StreamingArtworkDiskCache.defaultMaxBytes
    ) {
        self.directoryURL = directoryURL
        self.maxBytes = maxBytes
    }

    // MARK: - Public API

    /// Return cached bytes for the given source URL, or nil if there is no
    /// entry / the entry is unreadable. On hit, touches the file's
    /// modification date so the LRU prefers more-recently-accessed entries.
    func bytes(for url: URL) -> Data? {
        let file = fileURL(for: url)
        guard FileManager.default.fileExists(atPath: file.path) else {
            return nil
        }
        do {
            let data = try Data(contentsOf: file)
            // Touch mtime so LRU treats this as recently accessed.
            try? FileManager.default.setAttributes(
                [.modificationDate: Date()],
                ofItemAtPath: file.path
            )
            return data
        } catch {
            logger.warning("disk-cache read failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Store bytes for the given source URL, atomically. Trims the cache
    /// to `maxBytes` after the write — oldest-modification first.
    func store(_ data: Data, for url: URL) {
        let file = fileURL(for: url)
        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            try data.write(to: file, options: .atomic)
            // Stamp mtime so a write counts as the most-recent access.
            try? FileManager.default.setAttributes(
                [.modificationDate: Date()],
                ofItemAtPath: file.path
            )
            trim()
        } catch {
            logger.warning("disk-cache write failed: \(error.localizedDescription)")
        }
    }

    /// Drop every cached entry. Used by tests and exposed for a future
    /// "Clear streaming-artwork cache" affordance.
    func clearAll() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directoryURL.path) else { return }
        do {
            // Remove children rather than the directory itself so the cache
            // stays usable across the call.
            let entries = try fm.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            )
            for entry in entries {
                try? fm.removeItem(at: entry)
            }
        } catch {
            logger.warning("disk-cache clear failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Internals

    /// SHA-256 hex digest of the URL's absolute string, used as the on-disk
    /// filename stem.
    private func filename(for url: URL) -> String {
        let bytes = Data(url.absoluteString.utf8)
        let digest = SHA256.hash(data: bytes)
        return digest.map { String(format: "%02x", $0) }.joined() + ".bin"
    }

    private func fileURL(for url: URL) -> URL {
        directoryURL.appendingPathComponent(filename(for: url), isDirectory: false)
    }

    /// Walk the cache directory, total up sizes; if over `maxBytes`, evict
    /// oldest-modification-first until under the cap.
    private func trim() {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else { return }

        var inventory: [CacheEntry] = []
        for entry in entries {
            guard let attrs = try? entry.resourceValues(
                forKeys: [.fileSizeKey, .contentModificationDateKey]
            ) else { continue }
            // Distant-past fallback so missing dates evict first.
            inventory.append(CacheEntry(
                url: entry,
                size: attrs.fileSize ?? 0,
                modified: attrs.contentModificationDate ?? .distantPast
            ))
        }

        var total = inventory.reduce(0) { $0 + $1.size }
        guard total > maxBytes else { return }

        // Sort oldest-first so we evict least-recently-modified entries first.
        inventory.sort { $0.modified < $1.modified }
        for entry in inventory {
            if total <= maxBytes { break }
            do {
                try fm.removeItem(at: entry.url)
                total -= entry.size
            } catch {
                logger.warning(
                    "disk-cache evict failed for \(entry.url.lastPathComponent): \(error.localizedDescription)"
                )
            }
        }
    }

    /// Inventory row used by `trim()` — extracted to avoid a 3-tuple
    /// (`large_tuple` SwiftLint violation).
    private struct CacheEntry {
        let url: URL
        let size: Int
        let modified: Date
    }
}
