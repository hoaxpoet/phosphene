// IdentityMigrator — One-shot relocation of state stranded by the RN.1 rename.
//
// The Phosphene → Uzume rename changed the bundle identifier
// (com.phosphene.app → io.uzume.mac), and macOS derives three storage
// locations from it. Nothing is lost on disk, but the app stops looking where
// the data actually is:
//
//   UserDefaults   ~/Library/Preferences/com.phosphene.app.plist  → new domain reads empty
//   Stem cache     ~/Library/Application Support/Phosphene/       → hundreds of MB, each
//                                                                   entry costs an ML
//                                                                   stem-separation pass
//   Keychain       service "com.phosphene.spotify"                → Spotify reconnect
//
// TCC grants (Screen Recording, Apple Events, Apple Music) are keyed to the
// bundle ID by the OS and CANNOT be migrated — they must be re-granted. That
// is expected and documented in RUNBOOK §Troubleshooting.
//
// Every step is idempotent: it runs only when the old location has data AND
// the new one does not, so a second launch is a no-op. Failures are logged and
// swallowed — a stranded cache costs recomputation, never correctness.
//
// Old locations are NOT deleted, with one exception: the stem cache is MOVED
// rather than copied, because duplicating hundreds of MB to leave a copy
// nobody reads is worse than relocating it. The move is a same-volume rename.

import Foundation
import os.log

private let logger = Logger(subsystem: "io.uzume.mac", category: "IdentityMigrator")

// MARK: - IdentityMigrator

enum IdentityMigrator {

    // MARK: - Legacy identity (RN.1)

    static let legacyBundleID = "com.phosphene.app"
    static let legacyAppSupportDirName = "Phosphene"
    static let currentAppSupportDirName = "Uzume"
    static let legacyKeychainService = "com.phosphene.spotify"
    static let currentKeychainService = "io.uzume.spotify"

    // MARK: - API

    /// Run every pending migration. Safe to call on each launch.
    static func migrate(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) {
        migrateUserDefaults(into: defaults)
        migrateApplicationSupport(using: fileManager)
    }

    // MARK: - UserDefaults

    /// Copy every key from the old bundle domain that the new domain lacks.
    ///
    /// Reads the legacy domain explicitly rather than via `UserDefaults(suiteName:)`
    /// so a value already set under the new identity always wins — the user's
    /// current preference is never overwritten by a stale one.
    static func migrateUserDefaults(
        into defaults: UserDefaults,
        legacyDomain: String = legacyBundleID
    ) {
        guard let legacy = defaults.persistentDomain(forName: legacyDomain),
              !legacy.isEmpty else { return }

        var moved = 0
        for (key, value) in legacy where defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
            moved += 1
        }
        if moved > 0 {
            logger.info("IdentityMigrator: carried \(moved) setting(s) over from the old identity")
        }
    }

    // MARK: - Application Support

    /// Relocate `Application Support/Phosphene` to `.../Uzume`.
    ///
    /// Whole-directory move when the destination is absent (the common case).
    /// When both exist — a launch under the new identity happened before the
    /// migration ran — merges per child, and existing children win.
    static func migrateApplicationSupport(using fileManager: FileManager) {
        guard let root = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else { return }

        let old = root.appendingPathComponent(legacyAppSupportDirName, isDirectory: true)
        let new = root.appendingPathComponent(currentAppSupportDirName, isDirectory: true)
        guard fileManager.fileExists(atPath: old.path) else { return }

        do {
            if !fileManager.fileExists(atPath: new.path) {
                try fileManager.moveItem(at: old, to: new)
                logger.info("IdentityMigrator: moved Application Support/Phosphene → /Uzume")
                return
            }
            let children = try fileManager.contentsOfDirectory(
                at: old, includingPropertiesForKeys: nil
            )
            for child in children {
                let target = new.appendingPathComponent(child.lastPathComponent)
                guard !fileManager.fileExists(atPath: target.path) else { continue }
                try fileManager.moveItem(at: child, to: target)
            }
            logger.info("IdentityMigrator: merged \(children.count) item(s) into Application Support/Uzume")
        } catch {
            // A stranded cache is recomputed, not corrupted. Never fail launch.
            logger.error("IdentityMigrator: Application Support migration skipped — \(error.localizedDescription, privacy: .public)")
        }
    }
}
