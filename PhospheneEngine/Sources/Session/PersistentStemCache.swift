// PersistentStemCache — Disk-backed content-keyed cache for local-file
// pre-analysis results (LF.3 / D-130).
//
// Sibling to `StemCache` (in-memory only). The persistent layer keys on
// the SHA-256 of the source audio file's bytes, not on `TrackIdentity`
// — so renamed/moved files still hit cache, and so the on-disk format
// stays decoupled from `TrackIdentity`'s evolving schema.
//
// Layout on disk:
//
//     <rootDirectory>/
//       sha256/
//         <aa>/                      (first 2 hex chars of the hash)
//           <full-hash>/
//             metadata.json          (schemaVersion + BeatGrid + StemFeatures + TrackProfile + …)
//             vocals.f32             (raw little-endian Float32 PCM)
//             drums.f32
//             bass.f32
//             other.f32
//
// Failure model: all cache failures (missing files, schema mismatch,
// corrupt JSON, partial write) surface as `PersistentStemCacheError`.
// Callers should log and fall through to the in-memory / re-analyze
// path — the cache is an optimization, never a correctness requirement.

import DSP
import Foundation
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
/// `CachedTrackData` plus auxiliary fields (`decodedDuration`) that
/// are persisted alongside the cache contents but are not part of
/// `CachedTrackData` itself.
public struct PersistentStemCacheEntry: Sendable {
    public let cached: CachedTrackData
    /// Duration of the source audio in seconds, as recorded at store time.
    public let decodedDuration: TimeInterval

    public init(cached: CachedTrackData, decodedDuration: TimeInterval) {
        self.cached = cached
        self.decodedDuration = decodedDuration
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
    /// version as a miss. Never re-define the meaning of version 1.
    public static let currentSchemaVersion: Int = 1

    /// Names of the stem `.f32` files. Order matches `CachedTrackData.stemWaveforms`
    /// (`[vocals, drums, bass, other]`).
    public static let stemLabels: [String] = ["vocals", "drums", "bass", "other"]

    /// Default sub-path under `~/Library/Application Support` where the
    /// cache lives in production.
    public static let defaultRootSubpath: String = "Phosphene/StemCache"

    // MARK: - State

    /// Root directory on disk. Created if missing at init time.
    public let rootDirectory: URL
    private let lock = NSLock()
    private let fileManager: FileManager

    // MARK: - Init

    /// Construct a cache rooted at the given directory. When
    /// `rootDirectory` is `nil`, defaults to
    /// `~/Library/Application Support/Phosphene/StemCache/`. Creates
    /// the directory tree if missing (idempotent).
    ///
    /// Tests should pass a fresh temp directory so they don't collide
    /// with the user's real cache.
    public init(rootDirectory: URL? = nil, fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
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
                gridOnsetOffsetMs: metadata.gridOnsetOffsetMs
            )
            return PersistentStemCacheEntry(
                cached: cached,
                decodedDuration: metadata.decodedDuration
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
        decodedDuration: TimeInterval
    ) throws {
        try lock.withLock {
            let dir = directory(for: hash)
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)

            let waveforms = data.stemWaveforms
            let sampleCounts = waveforms.map { $0.count }
            let metadata = PersistentStemCacheEntryMetadata(
                cacheSchemaVersion: Self.currentSchemaVersion,
                beatGrid: data.beatGrid,
                drumsBeatGrid: data.drumsBeatGrid,
                stemFeatures: data.stemFeatures,
                trackProfile: data.trackProfile,
                gridOnsetOffsetMs: data.gridOnsetOffsetMs,
                stemSampleCounts: sampleCounts,
                decodedDuration: decodedDuration
            )

            // Write stems first so a partial-store leaves metadata
            // pointing at a complete waveform set, not missing files.
            for (index, label) in Self.stemLabels.enumerated() {
                let path = dir.appendingPathComponent("\(label).f32")
                let samples = index < waveforms.count ? waveforms[index] : []
                try writeFloats(samples, to: path)
            }

            let metadataPath = dir.appendingPathComponent(Self.metadataFilename)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
            let json = try encoder.encode(metadata)
            try json.write(to: metadataPath, options: .atomic)
        }
    }

    /// Remove the cached entry for a given hash, if present. Used by
    /// tests; production has no eviction path (LF.4 territory).
    public func remove(hash: String) throws {
        try lock.withLock {
            let dir = directory(for: hash)
            if fileManager.fileExists(atPath: dir.path) {
                try fileManager.removeItem(at: dir)
            }
        }
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
