// IdentityMigratorTests — RN.1 state migration across the bundle-ID change.
//
// The Application Support cases run against a temp directory injected via a
// FileManager subclass, so the developer's real ~/Library is never touched.

import Foundation
import Testing
@testable import UzumeApp

// MARK: - Test double

/// Redirects `.applicationSupportDirectory` to a temp root.
private final class TempAppSupportFileManager: FileManager, @unchecked Sendable {
    let root: URL
    init(root: URL) { self.root = root; super.init() }

    override func url(
        for directory: FileManager.SearchPathDirectory,
        in domain: FileManager.SearchPathDomainMask,
        appropriateFor url: URL?,
        create shouldCreate: Bool
    ) throws -> URL {
        guard directory == .applicationSupportDirectory else {
            return try super.url(for: directory, in: domain, appropriateFor: url, create: shouldCreate)
        }
        return root
    }
}

// MARK: - Tests

@Suite("RN.1 identity migration")
struct IdentityMigratorTests {

    private func makeTempRoot() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rn1-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Application Support

    @Test("Whole directory moves when the new location is absent")
    func movesWhenDestinationAbsent() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let marker = root.appendingPathComponent("Phosphene/StemCache/entry.bin")
        try write("cached", to: marker)

        IdentityMigrator.migrateApplicationSupport(using: TempAppSupportFileManager(root: root))

        let moved = root.appendingPathComponent("Uzume/StemCache/entry.bin")
        #expect(FileManager.default.fileExists(atPath: moved.path))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Phosphene").path))
    }

    @Test("Running twice is a no-op")
    func isIdempotent() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("cached", to: root.appendingPathComponent("Phosphene/StemCache/entry.bin"))
        let fm = TempAppSupportFileManager(root: root)

        IdentityMigrator.migrateApplicationSupport(using: fm)
        IdentityMigrator.migrateApplicationSupport(using: fm)

        let moved = root.appendingPathComponent("Uzume/StemCache/entry.bin")
        #expect(try String(contentsOf: moved, encoding: .utf8) == "cached")
    }

    @Test("Existing new-identity data wins over the legacy copy")
    func mergeKeepsExistingChildren() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("old", to: root.appendingPathComponent("Phosphene/StemCache/entry.bin"))
        try write("new", to: root.appendingPathComponent("Uzume/StemCache/entry.bin"))
        try write("only-old", to: root.appendingPathComponent("Phosphene/Presets/p.metal"))

        IdentityMigrator.migrateApplicationSupport(using: TempAppSupportFileManager(root: root))

        // StemCache already existed under the new identity — left untouched.
        #expect(try String(
            contentsOf: root.appendingPathComponent("Uzume/StemCache/entry.bin"), encoding: .utf8
        ) == "new")
        // Presets had no counterpart — carried across.
        #expect(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Uzume/Presets/p.metal").path
        ))
    }

    @Test("Nothing to migrate is harmless")
    func noLegacyDirectoryIsSafe() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        IdentityMigrator.migrateApplicationSupport(using: TempAppSupportFileManager(root: root))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Uzume").path))
    }

    // MARK: - UserDefaults

    @Test("Legacy settings carry over, and current values are never overwritten")
    func carriesSettingsWithoutClobbering() throws {
        let suiteName = "io.uzume.test.identity.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let legacyDomain = IdentityMigrator.legacyBundleID + ".test.\(UUID().uuidString)"
        defer { defaults.removePersistentDomain(forName: legacyDomain) }
        defaults.setPersistentDomain(
            ["carried": "from-old", "contested": "from-old"], forName: legacyDomain
        )
        defaults.set("already-here", forKey: "contested")

        IdentityMigrator.migrateUserDefaults(into: defaults, legacyDomain: legacyDomain)

        #expect(defaults.string(forKey: "carried") == "from-old")
        #expect(defaults.string(forKey: "contested") == "already-here")
    }
}
