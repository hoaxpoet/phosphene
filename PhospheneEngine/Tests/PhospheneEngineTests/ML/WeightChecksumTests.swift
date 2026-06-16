// WeightChecksumTests — load-time SHA-256 integrity gate for ML weights (CLEAN.5.5).
//
// GPU-free by construction (pure Data hashing + JSON/FileManager reads, no
// MPSGraph/Metal model build), so this suite joins the CI fast-gate allow-list
// in .github/workflows/ci.yml. It needs the real LFS .bin present (CI: lfs:true;
// worktrees: Scripts/bootstrap_fixtures.sh). Covers:
//   1. hex format pinned to the SHA-256 standard (lowercase, no separators)
//   2. verify() rejects a one-byte change with the model's named error
//   3. verify() accepts a matching digest
//   4. completeness gate — every .bin on disk ↔ a manifest entry with a valid sha256
//   5. happy path — the real loaders validate all committed bytes without throwing

import Testing
import Foundation
@testable import ML

@Suite struct WeightChecksumTests {

    // MARK: - 1. Hex Format

    /// Pins the encoding independent of the manifest: a future change to
    /// uppercase / separators would silently never-match the stored digests.
    @Test func test_hex_matchesSHA256Standard() {
        // Known-answer vectors (`printf abc | shasum -a 256`).
        #expect(WeightChecksum.hex(Data("abc".utf8))
            == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(WeightChecksum.hex(Data())
            == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    // MARK: - 2. Reject Mismatch (both error types)

    @Test func test_verify_throwsOnMismatch_stem() {
        let data = Data([0xDE, 0xAD, 0xBE, 0xEF])
        #expect(throws: StemModelWeightError.self) {
            try WeightChecksum.verify(data, expected: String(repeating: "0", count: 64), key: "x") {
                StemModelWeightError.checksumMismatch($0, expected: $1, got: $2)
            }
        }
    }

    @Test func test_verify_throwsOnMismatch_beatThis() {
        // One flipped byte vs. the digest of the original → mismatch.
        let good = Data([1, 2, 3, 4, 5, 6, 7, 8])
        let goodHex = WeightChecksum.hex(good)
        var bad = good
        bad[0] ^= 0xFF
        #expect(throws: BeatThisWeightError.self) {
            try WeightChecksum.verify(bad, expected: goodHex, key: "x") {
                BeatThisWeightError.checksumMismatch(key: $0, expected: $1, got: $2)
            }
        }
    }

    // MARK: - 3. Accept Match

    @Test func test_verify_passesOnMatch() throws {
        let data = Data([0xDE, 0xAD, 0xBE, 0xEF])
        try WeightChecksum.verify(data, expected: WeightChecksum.hex(data), key: "x") {
            StemModelWeightError.checksumMismatch($0, expected: $1, got: $2)
        }
    }

    // MARK: - 4. Completeness Gate

    /// Every on-disk .bin has a manifest entry carrying a non-empty, valid
    /// (64-char lowercase-hex) sha256, and every manifest `file` exists on
    /// disk. Catches the real future hole: someone adds a weight file and
    /// forgets the hash. Reads only the manifest + directory listing, so it is
    /// robust to LFS-pointer stubs (names exist even unsmudged).
    @Test func test_completeness_stem() throws {
        try assertCompleteHashes(manifest: stemManifestURL, weightsDir: stemWeightsDir)
    }

    @Test func test_completeness_beatThis() throws {
        try assertCompleteHashes(manifest: beatThisManifestURL, weightsDir: beatThisWeightsDir)
    }

    // MARK: - 5. Happy Path — Real Loaders Validate (GPU-free)

    /// These call the real load paths (with the checksum guard inside), so a
    /// green run proves every committed byte matches its committed digest in
    /// the format Swift produces. Neither entry point builds a Metal model.
    @Test func test_realStemWeights_loadAndValidate() throws {
        _ = try loadAllStemWeights()
    }

    @Test func test_realBeatThisWeights_loadAndValidate() throws {
        _ = try BeatThisModel.loadWeights()
    }

    // MARK: - Helpers

    private func assertCompleteHashes(manifest manifestURL: URL, weightsDir: URL) throws {
        let data = try Data(contentsOf: manifestURL)
        let obj = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let tensors = try #require(obj["tensors"] as? [String: [String: Any]])

        var manifestFiles = Set<String>()
        for (key, entry) in tensors {
            let file = try #require(entry["file"] as? String, "entry \(key) missing `file`")
            manifestFiles.insert(file)
            let sha = entry["sha256"] as? String
            #expect(sha != nil, "entry \(key) (\(file)) missing `sha256`")
            if let sha {
                #expect(sha.count == 64 && sha.allSatisfy(\.isHexDigit) && sha == sha.lowercased(),
                        "entry \(key) sha256 not 64-char lowercase hex: \(sha)")
            }
        }

        let onDisk = Set(
            (try FileManager.default.contentsOfDirectory(
                at: weightsDir, includingPropertiesForKeys: nil))
                .filter { $0.pathExtension == "bin" }
                .map(\.lastPathComponent)
        )
        #expect(onDisk == manifestFiles,
                "manifest/disk .bin mismatch — only in manifest: \(manifestFiles.subtracting(onDisk)); only on disk: \(onDisk.subtracting(manifestFiles))")
    }

    // Source-tree paths (CI + worktrees check out the tree; weights are LFS resources).
    private var weightsRoot: URL {
        URL(fileURLWithPath: String(#filePath))
            .deletingLastPathComponent()   // ML/
            .deletingLastPathComponent()   // PhospheneEngineTests/
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // PhospheneEngine/ (package root)
            .appendingPathComponent("Sources/ML/Weights")
    }
    private var stemWeightsDir: URL { weightsRoot }
    private var stemManifestURL: URL { weightsRoot.appendingPathComponent("manifest.json") }
    private var beatThisWeightsDir: URL { weightsRoot.appendingPathComponent("beat_this") }
    private var beatThisManifestURL: URL { beatThisWeightsDir.appendingPathComponent("manifest.json") }
}
