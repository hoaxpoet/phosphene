// SettingsMigrator — One-shot UserDefaults key migration into the uzume.* scheme.
//
// Called once at app launch from UzumeApp.init (via onAppear or App.init).
// Idempotent: running twice does not corrupt state.
//
// Migrations:
//   U.6  "phosphene.showLiveAdaptationToasts"       → the settings scheme
//   RN.6 every "phosphene.*" persisted key          → its "uzume.*" twin (D-231)
//
// The U.6 entry now points straight at its uzume.* destination, so an install that
// never launched between U.6 and RN.6 lands correctly in one pass and no entry
// depends on another running first.
//
// No migration needed for showPerformanceWarnings — that key did not previously exist
// in the codebase (confirmed in pre-flight audit, 2026-04-24).

import Foundation
import os.log

private let logger = Logger(subsystem: "io.uzume.mac", category: "SettingsMigrator")

// MARK: - SettingsMigrator

enum SettingsMigrator {

    // MARK: - Migration Map

    /// (oldKey, newKey) pairs. Order does not matter — each is independent, and the
    /// U.6 entry below is written to reach its final destination directly rather than
    /// chaining through the intermediate `phosphene.settings.*` name.
    private static let migrations: [(old: String, new: String)] = [
        // U.6 — pre-scheme flat key, retargeted at RN.6 to land in uzume.* in one hop.
        (old: "phosphene.showLiveAdaptationToasts",
         new: "uzume.settings.visuals.showLiveAdaptationToasts"),

        // RN.6 (D-231) — the rename reaches persisted state. Without these, every
        // setting silently reverts to its default on the first post-rename launch.
        (old: "phosphene.settings.visuals.deviceTierOverride",
         new: "uzume.settings.visuals.deviceTierOverride"),
        (old: "phosphene.settings.visuals.qualityCeiling",
         new: "uzume.settings.visuals.qualityCeiling"),
        (old: "phosphene.settings.visuals.reducedMotion",
         new: "uzume.settings.visuals.reducedMotion"),
        (old: "phosphene.settings.visuals.excludedPresetCategories",
         new: "uzume.settings.visuals.excludedPresetCategories"),
        (old: "phosphene.settings.visuals.showLiveAdaptationToasts",
         new: "uzume.settings.visuals.showLiveAdaptationToasts"),
        (old: "phosphene.settings.visuals.showUncertifiedPresets",
         new: "uzume.settings.visuals.showUncertifiedPresets"),
        (old: "phosphene.settings.diagnostics.sessionRecorderEnabled",
         new: "uzume.settings.diagnostics.sessionRecorderEnabled"),
        (old: "phosphene.settings.diagnostics.sessionRetention",
         new: "uzume.settings.diagnostics.sessionRetention"),
        (old: "phosphene.onboarding.photosensitivityAcknowledged",
         new: "uzume.onboarding.photosensitivityAcknowledged"),
        (old: "phosphene.lf.recents",
         new: "uzume.lf.recents"),
        // Read by the ENGINE (PersistentStemCache), migrated here — same defaults
        // domain, and the app is the only process that runs a migration.
        (old: "phosphene.cache.localFile.maxBytes",
         new: "uzume.cache.localFile.maxBytes"),
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
