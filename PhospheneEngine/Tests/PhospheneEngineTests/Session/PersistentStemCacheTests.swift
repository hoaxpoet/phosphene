// PersistentStemCacheTests — Unit tests for the LF.3 disk-backed
// content-keyed stem cache (D-130).
//
// Each test owns a fresh temp directory. The cache layer never reads
// the user's real `~/Library/Application Support/Phosphene/StemCache/`
// during testing.

import Foundation
import Testing
@testable import DSP
@testable import Session
@testable import Shared

@Suite("PersistentStemCache")
struct PersistentStemCacheTests {

    // MARK: - Fixtures

    /// 16-byte hex stand-in for a SHA-256 — the cache only treats this
    /// as an opaque key string, so test hashes don't need to be real.
    private static let fixtureHash = "abc123def456abc123def456abc123def456abc123def456abc123def456abcd"

    private static func makeCachedTrackData(stemSampleCount: Int = 256) -> CachedTrackData {
        let stems: [[Float]] = (0..<4).map { stemIndex in
            (0..<stemSampleCount).map { sampleIndex in
                Float(stemIndex) * 0.1 + Float(sampleIndex) * 0.001
            }
        }
        let stemFeatures = StemFeatures(
            vocalsEnergy: 0.31, vocalsBand0: 0.21, vocalsBand1: 0.11, vocalsBeat: 0.01,
            drumsEnergy: 0.52, drumsBand0: 0.42, drumsBand1: 0.32, drumsBeat: 0.12,
            bassEnergy: 0.43, bassBand0: 0.33, bassBand1: 0.23, bassBeat: 0.02,
            otherEnergy: 0.24, otherBand0: 0.14, otherBand1: 0.05, otherBeat: 0
        )
        let trackProfile = TrackProfile(
            bpm: 118.5,
            key: "C minor",
            mood: EmotionalState(valence: 0.42, arousal: 0.61),
            spectralCentroidAvg: 0.087,
            genreTags: ["electronic", "pop"],
            stemEnergyBalance: stemFeatures,
            estimatedSectionCount: 2
        )
        let beatGrid = BeatGrid(
            beats: [0.1, 0.6, 1.1, 1.6],
            downbeats: [0.1, 1.1],
            bpm: 120.0,
            beatsPerBar: 4,
            barConfidence: 0.85,
            frameRate: 50.0,
            frameCount: 1500
        )
        let drumsGrid = BeatGrid(
            beats: [0.2, 0.7, 1.2],
            downbeats: [0.2],
            bpm: 119.8,
            beatsPerBar: 4,
            barConfidence: 0.75,
            frameRate: 50.0,
            frameCount: 1500
        )
        return CachedTrackData(
            stemWaveforms: stems,
            stemFeatures: stemFeatures,
            trackProfile: trackProfile,
            beatGrid: beatGrid,
            drumsBeatGrid: drumsGrid,
            gridOnsetOffsetMs: 12.5
        )
    }

    private static func makeTempDir() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("PersistentStemCacheTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func expectEqual(_ lhs: CachedTrackData, _ rhs: CachedTrackData) {
        #expect(lhs.stemWaveforms.count == rhs.stemWaveforms.count)
        for (i, (a, b)) in zip(lhs.stemWaveforms, rhs.stemWaveforms).enumerated() {
            #expect(a.count == b.count, "stem \(i) length differs")
            #expect(a == b, "stem \(i) samples differ")
        }
        #expect(lhs.stemFeatures == rhs.stemFeatures)
        #expect(lhs.beatGrid == rhs.beatGrid)
        #expect(lhs.drumsBeatGrid == rhs.drumsBeatGrid)
        #expect(lhs.gridOnsetOffsetMs == rhs.gridOnsetOffsetMs)
        #expect(lhs.trackProfile.bpm == rhs.trackProfile.bpm)
        #expect(lhs.trackProfile.key == rhs.trackProfile.key)
        #expect(lhs.trackProfile.mood == rhs.trackProfile.mood)
        #expect(lhs.trackProfile.spectralCentroidAvg == rhs.trackProfile.spectralCentroidAvg)
        #expect(lhs.trackProfile.genreTags == rhs.trackProfile.genreTags)
        #expect(lhs.trackProfile.estimatedSectionCount == rhs.trackProfile.estimatedSectionCount)
    }

    /// Default duration used by the test fixtures. Matches `love_rehab.m4a`
    /// (29.93 s) so future tests that combine the fixture file with the
    /// in-memory CachedTrackData stay consistent.
    private static let defaultDuration: TimeInterval = 29.93

    // MARK: - Tests

    @Test("Roundtrip: store then load produces equivalent data")
    func test_roundtrip() throws {
        let tempDir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let cache = try PersistentStemCache(rootDirectory: tempDir)

        let original = Self.makeCachedTrackData(stemSampleCount: 4410)
        #expect(cache.contains(hash: Self.fixtureHash) == false)
        try cache.store(original, hash: Self.fixtureHash, decodedDuration: Self.defaultDuration)
        #expect(cache.contains(hash: Self.fixtureHash) == true)

        let loaded = try cache.load(hash: Self.fixtureHash)
        Self.expectEqual(loaded.cached, original)
        #expect(loaded.decodedDuration == Self.defaultDuration)
    }

    @Test("Roundtrip preserves StemFeatures fields beyond the 16 base floats")
    func test_roundtrip_extendedStemFields() throws {
        let tempDir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let cache = try PersistentStemCache(rootDirectory: tempDir)

        var stems = StemFeatures.zero
        stems.vocalsEnergyRel = 0.71
        stems.drumsEnergyDev = 0.42
        stems.vocalsPitchHz = 220.5
        stems.vocalsPitchConfidence = 0.83
        stems.cachedBassProportion = 0.34
        stems.drumsEnergyDevSmoothed = 0.12

        let data = CachedTrackData(
            stemWaveforms: (0..<4).map { _ in [Float]([0.1, 0.2, 0.3]) },
            stemFeatures: stems,
            trackProfile: TrackProfile()
        )

        try cache.store(data, hash: Self.fixtureHash, decodedDuration: Self.defaultDuration)
        let entry = try cache.load(hash: Self.fixtureHash)
        let loaded = entry.cached
        #expect(loaded.stemFeatures.vocalsEnergyRel == 0.71)
        #expect(loaded.stemFeatures.drumsEnergyDev == 0.42)
        #expect(loaded.stemFeatures.vocalsPitchHz == 220.5)
        #expect(loaded.stemFeatures.vocalsPitchConfidence == 0.83)
        #expect(loaded.stemFeatures.cachedBassProportion == 0.34)
        #expect(loaded.stemFeatures.drumsEnergyDevSmoothed == 0.12)
    }

    @Test("Load on a non-existent hash throws corruptMetadata")
    func test_load_missingEntry_throws() throws {
        let tempDir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let cache = try PersistentStemCache(rootDirectory: tempDir)

        #expect(throws: PersistentStemCacheError.self) {
            _ = try cache.load(hash: Self.fixtureHash)
        }
    }

    @Test("Schema mismatch on load throws and contains is unaffected")
    func test_load_schemaMismatch_throws() throws {
        let tempDir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let cache = try PersistentStemCache(rootDirectory: tempDir)
        let data = Self.makeCachedTrackData()
        try cache.store(data, hash: Self.fixtureHash, decodedDuration: Self.defaultDuration)

        // Rewrite metadata.json with a bogus schema version. Use the
        // same hash; preserve every other field so the failure is
        // unambiguously the version field.
        let dir = tempDir
            .appendingPathComponent("sha256", isDirectory: true)
            .appendingPathComponent(String(Self.fixtureHash.prefix(2)), isDirectory: true)
            .appendingPathComponent(Self.fixtureHash, isDirectory: true)
        let metadataPath = dir.appendingPathComponent("metadata.json")
        var json = try String(contentsOf: metadataPath, encoding: .utf8)
        json = json.replacingOccurrences(of: "\"cacheSchemaVersion\" : 1", with: "\"cacheSchemaVersion\" : 999")
        try json.write(to: metadataPath, atomically: true, encoding: .utf8)

        #expect(throws: PersistentStemCacheError.self) {
            _ = try cache.load(hash: Self.fixtureHash)
        }
    }

    @Test("Corrupt metadata JSON is rejected on load")
    func test_load_corruptMetadata_throws() throws {
        let tempDir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let cache = try PersistentStemCache(rootDirectory: tempDir)
        let data = Self.makeCachedTrackData()
        try cache.store(data, hash: Self.fixtureHash, decodedDuration: Self.defaultDuration)

        let dir = tempDir
            .appendingPathComponent("sha256", isDirectory: true)
            .appendingPathComponent(String(Self.fixtureHash.prefix(2)), isDirectory: true)
            .appendingPathComponent(Self.fixtureHash, isDirectory: true)
        let metadataPath = dir.appendingPathComponent("metadata.json")
        try "{not valid json}".write(to: metadataPath, atomically: true, encoding: .utf8)

        #expect(throws: PersistentStemCacheError.self) {
            _ = try cache.load(hash: Self.fixtureHash)
        }
    }

    @Test("Missing stem file rejects the entry")
    func test_load_missingStem_throws() throws {
        let tempDir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let cache = try PersistentStemCache(rootDirectory: tempDir)
        let data = Self.makeCachedTrackData()
        try cache.store(data, hash: Self.fixtureHash, decodedDuration: Self.defaultDuration)

        let dir = tempDir
            .appendingPathComponent("sha256", isDirectory: true)
            .appendingPathComponent(String(Self.fixtureHash.prefix(2)), isDirectory: true)
            .appendingPathComponent(Self.fixtureHash, isDirectory: true)
        let drumsPath = dir.appendingPathComponent("drums.f32")
        try FileManager.default.removeItem(at: drumsPath)

        // contains() should now report incomplete.
        #expect(cache.contains(hash: Self.fixtureHash) == false)
        #expect(throws: PersistentStemCacheError.self) {
            _ = try cache.load(hash: Self.fixtureHash)
        }
    }

    @Test("Malformed stem byte count is detected")
    func test_load_malformedStem_throws() throws {
        let tempDir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let cache = try PersistentStemCache(rootDirectory: tempDir)
        let data = Self.makeCachedTrackData()
        try cache.store(data, hash: Self.fixtureHash, decodedDuration: Self.defaultDuration)

        let dir = tempDir
            .appendingPathComponent("sha256", isDirectory: true)
            .appendingPathComponent(String(Self.fixtureHash.prefix(2)), isDirectory: true)
            .appendingPathComponent(Self.fixtureHash, isDirectory: true)
        let bassPath = dir.appendingPathComponent("bass.f32")
        // Write 7 bytes — not a multiple of 4 (Float32 stride).
        try Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07]).write(to: bassPath)

        #expect(throws: PersistentStemCacheError.self) {
            _ = try cache.load(hash: Self.fixtureHash)
        }
    }

    @Test("Overwriting an existing entry replaces all stem files")
    func test_store_overwrite() throws {
        let tempDir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let cache = try PersistentStemCache(rootDirectory: tempDir)

        let first = Self.makeCachedTrackData(stemSampleCount: 100)
        try cache.store(first, hash: Self.fixtureHash, decodedDuration: 10.0)

        let second = Self.makeCachedTrackData(stemSampleCount: 500)
        try cache.store(second, hash: Self.fixtureHash, decodedDuration: 50.0)

        let entry = try cache.load(hash: Self.fixtureHash)
        let loaded = entry.cached
        #expect(loaded.stemWaveforms[0].count == 500)
        #expect(loaded.stemWaveforms[1].count == 500)
        #expect(loaded.stemWaveforms[2].count == 500)
        #expect(loaded.stemWaveforms[3].count == 500)
        #expect(entry.decodedDuration == 50.0, "store overwrite must update decodedDuration too")
    }

    @Test("Concurrent store + load are serialized safely")
    func test_concurrentAccess_isSafe() async throws {
        let tempDir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let cache = try PersistentStemCache(rootDirectory: tempDir)
        // Seed an initial entry so loaders have something to read.
        try cache.store(
            Self.makeCachedTrackData(),
            hash: Self.fixtureHash,
            decodedDuration: Self.defaultDuration
        )

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<32 {
                let payload = Self.makeCachedTrackData(stemSampleCount: 64 + i * 4)
                group.addTask {
                    try? cache.store(
                        payload,
                        hash: Self.fixtureHash,
                        decodedDuration: Self.defaultDuration
                    )
                }
                group.addTask {
                    _ = try? cache.load(hash: Self.fixtureHash)
                }
            }
        }

        // After the fan-out, the final entry should still be readable.
        let entry = try cache.load(hash: Self.fixtureHash)
        let loaded = entry.cached
        #expect(loaded.stemWaveforms.count == 4)
        // Every stem array should be the same length (matches whichever
        // store landed last — but never a mix-and-match across writers).
        let lengths = Set(loaded.stemWaveforms.map { $0.count })
        #expect(lengths.count == 1, "stem lengths differed: \(lengths)")
    }

    @Test("Default constructor uses Application Support; explicit root is honoured")
    func test_init_honoursExplicitRoot() throws {
        let tempDir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let cache = try PersistentStemCache(rootDirectory: tempDir)
        #expect(cache.rootDirectory.path == tempDir.path)
        #expect(FileManager.default.fileExists(atPath: tempDir.path))
    }

    @Test("Two-byte hash prefix shards correctly")
    func test_storage_shardsByHashPrefix() throws {
        let tempDir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let cache = try PersistentStemCache(rootDirectory: tempDir)
        let data = Self.makeCachedTrackData()
        try cache.store(data, hash: Self.fixtureHash, decodedDuration: Self.defaultDuration)

        let prefix = String(Self.fixtureHash.prefix(2))
        let dir = tempDir
            .appendingPathComponent("sha256", isDirectory: true)
            .appendingPathComponent(prefix, isDirectory: true)
            .appendingPathComponent(Self.fixtureHash, isDirectory: true)
        #expect(FileManager.default.fileExists(atPath: dir.path))
        #expect(FileManager.default.fileExists(
            atPath: dir.appendingPathComponent("metadata.json").path
        ))
        for label in PersistentStemCache.stemLabels {
            #expect(FileManager.default.fileExists(
                atPath: dir.appendingPathComponent("\(label).f32").path
            ))
        }
    }
}
