// swiftlint:disable file_length
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable type_body_length
// PersistentStemCache — Disk-backed content-keyed cache for local-file
// pre-analysis results (LF.3 / D-130; LF.4 / D-131 eviction + clear;
// LF.5 / D-132 schema v2 with ID3 / Vorbis metadata).
//
// Sibling to `StemCache` (in-memory only). The persistent layer keys on
// the SHA-256 of the source audio file's bytes, not on `TrackIdentity`
// — so renamed/moved files still hit cache, and so the on-disk format
// stays decoupled from `TrackIdentity`'s evolving schema.
//
// LF.4: an LRU eviction policy keeps the cache from growing unbounded.
// Default cap is 500 MB (~70 tracks at ~7 MB/track). Eviction fires
// after every successful `store(...)` call so the cap is continuously
// enforced. `clearAll()` is the user-facing reset hook surfaced via the
// `Phosphene → Clear Local-File Cache (<size>)` menu item.
//
// LF.5: `metadata.json` schema bumps to version 2 with an optional
// `metadata: LocalFileMetadata` field carrying ID3 / Vorbis-extracted
// title / artist / album. Optional `artwork.bin` sibling holds raw image
// bytes (PNG / JPEG — whatever the container embedded). Schema-v1 entries
// on disk throw `schemaMismatch` and the caller re-prepares.
//
// Layout on disk:
//
//     <rootDirectory>/
//       sha256/
//         <aa>/                      (first 2 hex chars of the hash)
//           <full-hash>/
//             metadata.json          (schemaVersion + BeatGrid + StemFeatures + TrackProfile + LocalFileMetadata + …)
//             vocals.f32             (raw little-endian Float32 PCM)
//             drums.f32
//             bass.f32
//             other.f32
//             artwork.bin            (LF.5; optional — only present when the source ships embedded art)
//
// Failure model: all cache failures (missing files, schema mismatch,
// corrupt JSON, partial write) surface as `PersistentStemCacheError`.
// Callers should log and fall through to the in-memory / re-analyze
// path — the cache is an optimization, never a correctness requirement.

import DSP
import Foundation
import ML
import Shared

// MARK: - Errors

/// Failures specific to `PersistentStemCache`. Distinct from
/// `LocalFileDecodeError` because the cache layer never opens the source
/// audio file — it only reads/writes pre-computed analysis bytes.
public enum PersistentStemCacheError: Error, Sendable, Equatable {
    /// `FileManager` could not produce a usable Application Support
    /// directory, or the chosen root path can't be created.
    case rootDirectoryUnavailable(reason: String)
    /// `metadata.json` decoded to a schema version this build can't read.
    /// The caller should treat this as a miss and overwrite.
    case schemaMismatch(expected: Int, found: Int)
    /// `metadata.json` is missing or fails JSON parse.
    case corruptMetadata(reason: String)
    /// One of the four expected stem `.f32` files is missing.
    case missingStem(stemLabel: String)
    /// A stem `.f32` file exists but its byte count is not a multiple of
    /// `MemoryLayout<Float>.size`, suggesting partial write or corruption.
    case malformedStem(stemLabel: String, byteCount: Int)
}

// MARK: - Loaded entry

/// Bundle returned by `PersistentStemCache.load(hash:)`. Carries the
/// `CachedTrackData` plus auxiliary fields (`decodedDuration`,
/// `metadata`, `artworkData`) that are persisted alongside the cache
/// contents but are not part of `CachedTrackData` itself.
public struct PersistentStemCacheEntry: Sendable {
    public let cached: CachedTrackData
    /// Duration of the source audio in seconds, as recorded at store time.
    public let decodedDuration: TimeInterval
    /// AVAsset.commonMetadata-extracted title / artist / album from the
    /// source file. All fields nil when the file shipped no metadata.
    /// Added in schema v2 (LF.5).
    public let metadata: LocalFileMetadata
    /// Raw artwork bytes (PNG / JPEG, depending on container). `nil` when
    /// the source file shipped no embedded artwork. Persisted as a sibling
    /// `artwork.bin` file in the cache directory. Added in schema v2 (LF.5).
    public let artworkData: Data?

    public init(
        cached: CachedTrackData,
        decodedDuration: TimeInterval,
        metadata: LocalFileMetadata = LocalFileMetadata(),
        artworkData: Data? = nil
    ) {
        self.cached = cached
        self.decodedDuration = decodedDuration
        self.metadata = metadata
        self.artworkData = artworkData
    }
}

// MARK: - Metadata envelope

/// On-disk JSON wrapper around a `CachedTrackData`'s non-waveform
/// components. The stem waveforms are stored as sibling raw-float files
/// because (a) they dominate per-track byte count (~7 MB) and inflating
/// them through JSON would multiply storage and parse cost, and
/// (b) raw `.f32` files are inspectable with downstream audio tools.
private struct PersistentStemCacheEntryMetadata: Codable {
    let cacheSchemaVersion: Int
    let beatGrid: BeatGrid
    let drumsBeatGrid: BeatGrid
    let stemFeatures: StemFeatures
    let trackProfile: TrackProfile
    let gridOnsetOffsetMs: Double
    /// Sample counts for the four stem waveforms in the same order they
    /// were stored. Used to validate the `.f32` byte counts on load.
    let stemSampleCounts: [Int]
    /// Duration of the source audio in seconds, as decoded by
    /// `PreviewAudio.fromLocalFile(at:)`. Persisted so the synthetic
    /// `TrackIdentity` reconstructed on a cache hit carries the same
    /// `duration` value as the one built during a fresh-analyze pass —
    /// `WIRING:` log lines and `TrackIdentity.==` then match across
    /// cache hit/miss.
    let decodedDuration: TimeInterval
    /// AVAsset.commonMetadata-extracted title / artist / album. Added in
    /// schema v2 (LF.5). Nil when the source file shipped no metadata.
    let metadata: LocalFileMetadata?
    /// Per-window instrument-family activity series (Layer 5a, IFC.6 / D-177).
    /// Added in schema v6. Optional so a decode never fails on it; empty on
    /// non-orchestral tracks. Without it, a disk-cache hit on a local
    /// orchestral file replays with no family activity (the sections go dark).
    let instrumentFamilySeries: [InstrumentFamilyActivity]?
}

// MARK: - PersistentStemCache

/// Disk-backed cache of pre-analyzed track data keyed by the SHA-256
/// content hash of the source audio file.
///
/// Thread-safe: all public mutators acquire an `NSLock` before touching
/// the filesystem. Reads also lock, both to serialize against
/// in-flight writes and to give straightforward concurrent-access
/// regression coverage.
public final class PersistentStemCache: @unchecked Sendable {

    // MARK: - Constants

    /// On-disk schema version. Increment when the on-disk format
    /// changes in a way that previously-written entries can no longer
    /// be read correctly — `load(hash:)` treats any non-matching
    /// version as a miss. Never re-define the meaning of any prior version.
    ///
    /// History:
    ///   v1 (LF.3 / D-130) — original schema.
    ///   v2 (LF.5 / D-132) — adds `metadata: LocalFileMetadata?` (ID3 /
    ///                       Vorbis title / artist / album) + optional
    ///                       sibling `artwork.bin` file with raw image bytes.
    ///   v3 (LFPLAN.6) — adds `TrackProfile.sectionStartTimes` (detected section
    ///                       boundary times). Decodes fine on v2 (the field is
    ///                       optional → nil), but the planner can't segment on
    ///                       real sections without it, so v2 entries must be
    ///                       re-analysed rather than read back with nil times.
    ///   v4 (LFPLAN.8) — `sectionStartTimes` is now strength-filtered (only boundaries
    ///                       ≥ 0.5× the track's strongest novelty peak). v3 entries hold
    ///                       the old UNFILTERED times, so they must be re-analysed for the
    ///                       filter to reach the planner.
    ///   v5 (SECDET.3b) — `sectionStartTimes` now means the McFee/Ellis batch detector's
    ///                       boundaries (SectionDetector), not the novelty detector's. The
    ///                       payload decodes identically, but v4 entries hold the old
    ///                       novelty boundaries, so they must be re-analysed for the real
    ///                       sections to reach the planner.
    ///   v6 (IFC.6 / D-177) — adds `instrumentFamilySeries` (the per-window PANNs
    ///                       instrument-family activity, Layer 5a). v5 entries lack it, so an
    ///                       orchestral local file cached under v5 would replay with no family
    ///                       activity — re-analyse so the family series reaches the preset.
    public static let currentSchemaVersion: Int = 6

    /// Names of the stem `.f32` files. Order matches `CachedTrackData.stemWaveforms`
    /// (`[vocals, drums, bass, other]`).
    public static let stemLabels: [String] = ["vocals", "drums", "bass", "other"]

    /// Filename for the optional artwork sibling (LF.5). Bytes are raw image
    /// data (PNG / JPEG depending on container). Absence is non-fatal; the
    /// entry remains valid as long as the metadata.json + four stems exist.
    public static let artworkFilename: String = "artwork.bin"

    /// Default sub-path under `~/Library/Application Support` where the
    /// cache lives in production.
    public static let defaultRootSubpath: String = "Phosphene/StemCache"

    /// `UserDefaults` key holding the LRU eviction cap (Int64 byte count).
    /// Operators can override the default 500 MB cap without a recompile:
    ///   defaults write com.phosphene.app phosphene.cache.localFile.maxBytes -int <bytes>
    public static let maxBytesUserDefaultsKey: String = "phosphene.cache.localFile.maxBytes"

    /// LF.4 default cap. 500 MB ≈ 70 cached tracks at ~7 MB/track (LF.3
    /// per-track budget — `metadata.json` ~5 KB + four 1.76 MB `.f32` stems).
    public static let defaultMaxBytes: Int64 = 500 * 1024 * 1024

    // MARK: - State

    /// Root directory on disk. Created if missing at init time.
    public let rootDirectory: URL
    private let lock = NSLock()
    private let fileManager: FileManager

    /// Eviction cap in bytes. `nil` defers to
    /// `Self.configuredMaxBytes()` (UserDefaults override → default 500 MB).
    /// Tests inject a fixed value here to avoid cross-test UserDefaults
    /// contamination during parallel execution.
    private let injectedMaxBytes: Int64?

    // MARK: - Init

    /// Construct a cache rooted at the given directory. When
    /// `rootDirectory` is `nil`, defaults to
    /// `~/Library/Application Support/Phosphene/StemCache/`. Creates
    /// the directory tree if missing (idempotent).
    ///
    /// `maxBytes` overrides the auto-eviction cap consulted after every
    /// `store(...)`. Production callers leave it `nil` so the
    /// UserDefaults-driven `configuredMaxBytes()` applies; tests inject a
    /// huge value to disable eviction or a small value to exercise it.
    ///
    /// Tests should pass a fresh temp directory so they don't collide
    /// with the user's real cache.
    public init(
        rootDirectory: URL? = nil,
        maxBytes: Int64? = nil,
        fileManager: FileManager = .default
    ) throws {
        self.fileManager = fileManager
        self.injectedMaxBytes = maxBytes
        if let rootDirectory {
            self.rootDirectory = rootDirectory
        } else {
            do {
                let appSupport = try fileManager.url(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask,
                    appropriateFor: nil,
                    create: true
                )
                self.rootDirectory = appSupport
                    .appendingPathComponent(Self.defaultRootSubpath, isDirectory: true)
            } catch {
                throw PersistentStemCacheError.rootDirectoryUnavailable(
                    reason: error.localizedDescription
                )
            }
        }
        do {
            try fileManager.createDirectory(
                at: self.rootDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            throw PersistentStemCacheError.rootDirectoryUnavailable(
                reason: error.localizedDescription
            )
        }
    }

    // MARK: - Lookup

    /// Cheap existence check — does this cache hold a complete entry
    /// for the given content hash? "Complete" means metadata.json and
    /// all four stem files are present. Returns `false` on any partial
    /// state; the caller should treat that as a miss.
    public func contains(hash: String) -> Bool {
        lock.withLock {
            let dir = directory(for: hash)
            for path in expectedFiles(in: dir) where !fileManager.fileExists(atPath: path.path) {
                return false
            }
            return true
        }
    }

    /// Load the cached entry for the given content hash.
    ///
    /// Throws `PersistentStemCacheError` on any failure (missing file,
    /// schema mismatch, corrupt JSON, malformed waveform). Callers
    /// treat any thrown error as a cache miss.
    public func load(hash: String) throws -> PersistentStemCacheEntry {
        try lock.withLock {
            let dir = directory(for: hash)
            let metadata = try readMetadata(in: dir)
            guard metadata.cacheSchemaVersion == Self.currentSchemaVersion else {
                throw PersistentStemCacheError.schemaMismatch(
                    expected: Self.currentSchemaVersion,
                    found: metadata.cacheSchemaVersion
                )
            }
            var stemWaveforms: [[Float]] = []
            stemWaveforms.reserveCapacity(Self.stemLabels.count)
            for (index, label) in Self.stemLabels.enumerated() {
                let path = dir.appendingPathComponent("\(label).f32")
                let expectedCount = index < metadata.stemSampleCounts.count
                    ? metadata.stemSampleCounts[index]
                    : nil
                let samples = try readFloats(from: path, label: label, expectedCount: expectedCount)
                stemWaveforms.append(samples)
            }
            let cached = CachedTrackData(
                stemWaveforms: stemWaveforms,
                stemFeatures: metadata.stemFeatures,
                trackProfile: metadata.trackProfile,
                beatGrid: metadata.beatGrid,
                drumsBeatGrid: metadata.drumsBeatGrid,
                gridOnsetOffsetMs: metadata.gridOnsetOffsetMs,
                instrumentFamilySeries: metadata.instrumentFamilySeries ?? []
            )

            // Artwork is optional — missing file or empty bytes is fine.
            let artworkPath = dir.appendingPathComponent(Self.artworkFilename)
            let artworkData: Data? = fileManager.fileExists(atPath: artworkPath.path)
                ? try? Data(contentsOf: artworkPath)
                : nil

            return PersistentStemCacheEntry(
                cached: cached,
                decodedDuration: metadata.decodedDuration,
                metadata: metadata.metadata ?? LocalFileMetadata(),
                artworkData: artworkData
            )
        }
    }

    /// Persist a cached entry under the given content hash. Creates the
    /// per-hash directory if missing; overwrites any prior entry at the
    /// same hash. Writes are issued individually; a process kill
    /// mid-store leaves a partial directory that `load(hash:)` rejects.
    ///
    /// `decodedDuration` is the duration (seconds) returned from
    /// `PreviewAudio.fromLocalFile(at:)`. Persisted so the synthetic
    /// `TrackIdentity` on a future cache-hit carries the same duration
    /// value.
    public func store(
        _ data: CachedTrackData,
        hash: String,
        decodedDuration: TimeInterval,
        metadata: LocalFileMetadata = LocalFileMetadata(),
        artworkData: Data? = nil
    ) throws {
        try lock.withLock {
            let dir = directory(for: hash)
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)

            let waveforms = data.stemWaveforms
            let sampleCounts = waveforms.map { $0.count }
            let envelope = PersistentStemCacheEntryMetadata(
                cacheSchemaVersion: Self.currentSchemaVersion,
                beatGrid: data.beatGrid,
                drumsBeatGrid: data.drumsBeatGrid,
                stemFeatures: data.stemFeatures,
                trackProfile: data.trackProfile,
                gridOnsetOffsetMs: data.gridOnsetOffsetMs,
                stemSampleCounts: sampleCounts,
                decodedDuration: decodedDuration,
                metadata: metadata.isEmpty ? nil : metadata,
                instrumentFamilySeries: data.instrumentFamilySeries.isEmpty ? nil : data.instrumentFamilySeries
            )

            // Write stems first so a partial-store leaves metadata
            // pointing at a complete waveform set, not missing files.
            for (index, label) in Self.stemLabels.enumerated() {
                let path = dir.appendingPathComponent("\(label).f32")
                let samples = index < waveforms.count ? waveforms[index] : []
                try writeFloats(samples, to: path)
            }

            // Write optional artwork.bin before metadata.json so a partial-store
            // either has the complete entry (incl. artwork) or fails the
            // metadata.json existence check (caller treats as miss).
            let artworkPath = dir.appendingPathComponent(Self.artworkFilename)
            if let artworkData, !artworkData.isEmpty {
                try artworkData.write(to: artworkPath, options: .atomic)
            } else if fileManager.fileExists(atPath: artworkPath.path) {
                // Overwrite-without-artwork case: prior entry had artwork, new
                // one doesn't. Remove the stale sibling so post-load reads
                // don't surface stale art.
                try? fileManager.removeItem(at: artworkPath)
            }

            let metadataPath = dir.appendingPathComponent(Self.metadataFilename)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
            let json = try encoder.encode(envelope)
            try json.write(to: metadataPath, options: .atomic)
        }
        // Eviction is intentionally OUTSIDE the lock — `evictToMaxBytes`
        // acquires the lock itself, and recursive NSLock acquisition deadlocks.
        // The post-store window before eviction is bounded; an external reader
        // racing with eviction sees either the pre-eviction set or the
        // post-eviction set (both internally consistent). `try?` swallows any
        // eviction error — eviction failure is non-fatal (cache just grows).
        let cap = injectedMaxBytes ?? Self.configuredMaxBytes()
        _ = try? evictToMaxBytes(cap)
    }

    /// Remove the cached entry for a given hash, if present. Used by
    /// tests and by `evictToMaxBytes(_:)` during LF.4 LRU eviction.
    public func remove(hash: String) throws {
        try lock.withLock {
            let dir = directory(for: hash)
            if fileManager.fileExists(atPath: dir.path) {
                try fileManager.removeItem(at: dir)
            }
        }
    }

    // MARK: - LF.4 housekeeping

    /// Sum the byte count of every cached file under `rootDirectory`. O(N)
    /// over per-hash directory listings — cheap enough to call from the
    /// SwiftUI menu update path (a few hundred `stat` calls for a full
    /// 500 MB cache).
    public func totalBytes() -> Int64 {
        lock.withLock { Self.computeTotalBytes(under: rootDirectory) }
    }

    /// Evict cached entries (oldest first by `metadata.json` mtime) until
    /// the cache's total footprint is at or below `maxBytes`. Returns the
    /// number of entries removed. `maxBytes <= 0` evicts everything.
    ///
    /// Mtime is the eviction discriminator because it's the cheapest
    /// per-entry attribute the filesystem already tracks for our writes
    /// — `store(...)` writes metadata.json atomically last, so its mtime
    /// reflects the last successful population. Reads do not bump mtime,
    /// so the "least-recently-stored" eviction order is approximate, not
    /// "least-recently-used" in the strict sense. Acceptable for the LF
    /// scope: the user re-plays the same tracks repeatedly, so writes are
    /// rare and the mtime ordering still favours retention of the most
    /// recently played files.
    @discardableResult
    public func evictToMaxBytes(_ maxBytes: Int64) throws -> Int {
        try evictToMaxBytes(maxBytes, recorder: nil)
    }

    @discardableResult
    func evictToMaxBytes(_ maxBytes: Int64, recorder: SessionRecorder?) throws -> Int {
        try lock.withLock {
            var entries = try Self.enumerateEntries(under: rootDirectory)
            var total = entries.reduce(Int64(0)) { $0 + $1.bytes }
            if total <= maxBytes { return 0 }

            entries.sort { $0.mtime < $1.mtime } // oldest first
            var evicted = 0
            for entry in entries {
                if total <= maxBytes { break }
                try fileManager.removeItem(at: entry.directory)
                total -= entry.bytes
                evicted += 1
                let msg = "STEM_CACHE_EVICTED: hash=\(entry.hashPrefix), bytes=\(entry.bytes)"
                recorder?.log(msg)
            }
            return evicted
        }
    }

    /// Remove every cached entry. Returns the number of bytes freed.
    /// Preserves the root directory itself so subsequent `store(...)` calls
    /// don't need to re-create it.
    @discardableResult
    public func clearAll() throws -> Int64 {
        try lock.withLock {
            let freed = Self.computeTotalBytes(under: rootDirectory)
            guard let contents = try? fileManager.contentsOfDirectory(
                at: rootDirectory,
                includingPropertiesForKeys: nil
            ) else {
                return 0
            }
            for child in contents {
                try fileManager.removeItem(at: child)
            }
            return freed
        }
    }

    // MARK: - LF.4 eviction helpers

    /// Per-cached-entry summary used by `evictToMaxBytes`. `hashPrefix`
    /// is the first 12 hex chars of the full hash for log lines.
    private struct CacheEntryInfo {
        let directory: URL
        let bytes: Int64
        let mtime: Date
        let hashPrefix: String
    }

    /// Resolve the operator-configured eviction cap, falling back to
    /// `defaultMaxBytes` (500 MB) when the UserDefaults key is unset.
    static func configuredMaxBytes() -> Int64 {
        let raw = UserDefaults.standard.object(forKey: maxBytesUserDefaultsKey)
        if let int64 = raw as? Int64 {
            return int64
        }
        if let int = raw as? Int {
            return Int64(int)
        }
        if let number = raw as? NSNumber {
            return number.int64Value
        }
        return defaultMaxBytes
    }

    /// Walk every `sha256/<aa>/<full-hash>/` subdir under `root` and
    /// return an unordered array of `CacheEntryInfo`. Uses the
    /// metadata.json mtime as the eviction sort key (cheap to read; bumped
    /// on every successful `store(...)` overwrite). Skips directories
    /// that don't contain the expected file set.
    private static func enumerateEntries(under root: URL) throws -> [CacheEntryInfo] {
        let fm = FileManager.default
        let sha256Root = root.appendingPathComponent("sha256", isDirectory: true)
        guard fm.fileExists(atPath: sha256Root.path) else { return [] }
        let shardURLs = (try? fm.contentsOfDirectory(
            at: sha256Root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        var result: [CacheEntryInfo] = []
        result.reserveCapacity(64)
        for shard in shardURLs {
            let hashDirs = (try? fm.contentsOfDirectory(
                at: shard,
                includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            for hashDir in hashDirs {
                let metadata = hashDir.appendingPathComponent(metadataFilename)
                guard fm.fileExists(atPath: metadata.path) else { continue }
                let attrs = try? fm.attributesOfItem(atPath: metadata.path)
                let mtime = (attrs?[.modificationDate] as? Date) ?? Date(timeIntervalSince1970: 0)
                let bytes = computeBytes(in: hashDir)
                let hashPrefix = String(hashDir.lastPathComponent.prefix(12))
                result.append(CacheEntryInfo(
                    directory: hashDir,
                    bytes: bytes,
                    mtime: mtime,
                    hashPrefix: hashPrefix
                ))
            }
        }
        return result
    }

    /// Sum the file sizes inside a single per-hash directory.
    private static func computeBytes(in directory: URL) -> Int64 {
        let fm = FileManager.default
        let children = (try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        var total: Int64 = 0
        for child in children {
            let attrs = try? fm.attributesOfItem(atPath: child.path)
            if let size = attrs?[.size] as? Int64 {
                total += size
            } else if let size = attrs?[.size] as? Int {
                total += Int64(size)
            } else if let size = attrs?[.size] as? NSNumber {
                total += size.int64Value
            }
        }
        return total
    }

    /// Aggregate `computeBytes(in:)` across every per-hash directory under
    /// `root/sha256/<aa>/`. Returns 0 when the cache tree is empty or
    /// the root directory doesn't yet contain a `sha256/` subdir.
    private static func computeTotalBytes(under root: URL) -> Int64 {
        let entries = (try? enumerateEntries(under: root)) ?? []
        return entries.reduce(Int64(0)) { $0 + $1.bytes }
    }

    // MARK: - File-layout helpers

    private func directory(for hash: String) -> URL {
        let prefix = hash.count >= 2 ? String(hash.prefix(2)) : "00"
        return rootDirectory
            .appendingPathComponent("sha256", isDirectory: true)
            .appendingPathComponent(prefix, isDirectory: true)
            .appendingPathComponent(hash, isDirectory: true)
    }

    private func expectedFiles(in directory: URL) -> [URL] {
        var paths: [URL] = [directory.appendingPathComponent(Self.metadataFilename)]
        for label in Self.stemLabels {
            paths.append(directory.appendingPathComponent("\(label).f32"))
        }
        return paths
    }

    private static let metadataFilename: String = "metadata.json"

    // MARK: - JSON I/O

    private func readMetadata(in directory: URL) throws -> PersistentStemCacheEntryMetadata {
        let path = directory.appendingPathComponent(Self.metadataFilename)
        guard fileManager.fileExists(atPath: path.path) else {
            throw PersistentStemCacheError.corruptMetadata(reason: "metadata.json not found")
        }
        let data: Data
        do {
            data = try Data(contentsOf: path)
        } catch {
            throw PersistentStemCacheError.corruptMetadata(reason: error.localizedDescription)
        }
        do {
            return try JSONDecoder().decode(PersistentStemCacheEntryMetadata.self, from: data)
        } catch {
            throw PersistentStemCacheError.corruptMetadata(reason: error.localizedDescription)
        }
    }

    // MARK: - Raw Float32 I/O

    private func writeFloats(_ floats: [Float], to url: URL) throws {
        let data = floats.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
        try data.write(to: url, options: .atomic)
    }

    private func readFloats(
        from url: URL,
        label: String,
        expectedCount: Int?
    ) throws -> [Float] {
        guard fileManager.fileExists(atPath: url.path) else {
            throw PersistentStemCacheError.missingStem(stemLabel: label)
        }
        let data = try Data(contentsOf: url)
        let byteCount = data.count
        let stride = MemoryLayout<Float>.size
        guard byteCount % stride == 0 else {
            throw PersistentStemCacheError.malformedStem(stemLabel: label, byteCount: byteCount)
        }
        let actualCount = byteCount / stride
        if let expectedCount, actualCount != expectedCount {
            throw PersistentStemCacheError.malformedStem(stemLabel: label, byteCount: byteCount)
        }
        var samples = [Float](repeating: 0, count: actualCount)
        _ = samples.withUnsafeMutableBytes { dest in
            data.copyBytes(to: dest)
        }
        return samples
    }
}
