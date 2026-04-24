// SettingsMigrator — One-shot UserDefaults key migration to phosphene.settings.* scheme.
//
// Called once at app launch from PhospheneApp.init (via onAppear or App.init).
// Idempotent: running twice does not corrupt state.
//
// Migrations:
//   "phosphene.showLiveAdaptationToasts"
//     → "phosphene.settings.visuals.showLiveAdaptationToasts"
//
// No migration needed for showPerformanceWarnings — that key did not previously exist
// in the codebase (confirmed in pre-flight audit, 2026-04-24).

import Foundation
import os.log

private let logger = Logger(subsystem: "com.phosphene.app", category: "SettingsMigrator")

// MARK: - SettingsMigrator

enum SettingsMigrator {

    // MARK: - Migration Map

    /// (oldKey, newKey) pairs. Order does not matter — each is independent.
    private static let migrations: [(old: String, new: String)] = [
        (
            old: "phosphene.showLiveAdaptationToasts",
            new: "phosphene.settings.visuals.showLiveAdaptationToasts"
        ),
    ]

    // MARK: - API

    /// Run all pending migrations against `defaults`.
    ///
    /// For each migration: if the old key has a value AND the new key is absent,
    /// copies the value and removes the old key. Idempotent.
    static func migrate(in defaults: UserDefaults = .standard) {
        for (old, new) in migrations {
            guard let value = defaults.object(forKey: old) else { continue }
            guard defaults.object(forKey: new) == nil else {
                // New key already present — just clean up the old one.
                defaults.removeObject(forKey: old)
                logger.debug("SettingsMigrator: cleaned stale key '\(old)'")
                continue
            }
            defaults.set(value, forKey: new)
            defaults.removeObject(forKey: old)
            logger.info("SettingsMigrator: migrated '\(old)' → '\(new)'")
        }
    }
}
