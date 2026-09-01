// SettingsMigratorTests — Migration tests for SettingsMigrator (U.8 Part A).

import Foundation
import Testing
@testable import UzumeApp

// MARK: - SettingsMigratorTests

@Suite("SettingsMigrator")
struct SettingsMigratorTests {

    private func makeSuite() -> UserDefaults {
        guard let suite = UserDefaults(suiteName: "io.uzume.test.migrator.\(UUID().uuidString)") else {
            fatalError("UserDefaults suite init failed — test setup error")
        }
        return suite
    }

    @Test func oldShowLiveAdaptationToasts_migratesToNewKey() {
        let defaults = makeSuite()
        defaults.set(true, forKey: "phosphene.showLiveAdaptationToasts")

        SettingsMigrator.migrate(in: defaults)

        #expect(defaults.bool(forKey: "uzume.settings.visuals.showLiveAdaptationToasts") == true)
        #expect(defaults.object(forKey: "phosphene.showLiveAdaptationToasts") == nil)
    }

    /// RN.6 / D-231. The rename reaches persisted state, so every key a prior install
    /// wrote under `phosphene.*` must arrive under `uzume.*`. This asserts the whole set
    /// in one pass: a key added to `SettingsStore` but forgotten in the migration map
    /// fails here rather than silently resetting that setting on the user's next launch.
    @Test func rn6_everyPersistedKeyMigratesToUzumeNamespace() {
        let defaults = makeSuite()

        // (legacyKey, value) covering every persisted surface: visuals, diagnostics,
        // onboarding, local-file recents, and the engine-read cache cap.
        let seeded: [(String, Any)] = [
            ("phosphene.settings.visuals.deviceTierOverride", "high"),
            ("phosphene.settings.visuals.qualityCeiling", "full"),
            ("phosphene.settings.visuals.reducedMotion", true),
            ("phosphene.settings.visuals.excludedPresetCategories", ["hypnotic"]),
            ("phosphene.settings.visuals.showLiveAdaptationToasts", false),
            ("phosphene.settings.visuals.showUncertifiedPresets", true),
            ("phosphene.settings.diagnostics.sessionRecorderEnabled", true),
            ("phosphene.settings.diagnostics.sessionRetention", "keepAll"),
            ("phosphene.onboarding.photosensitivityAcknowledged", true),
            ("phosphene.lf.recents", ["/tmp/a.m4a"]),
            ("phosphene.cache.localFile.maxBytes", 1_073_741_824),
        ]
        for (key, value) in seeded { defaults.set(value, forKey: key) }

        SettingsMigrator.migrate(in: defaults)

        for (legacyKey, _) in seeded {
            let renamed = legacyKey.replacingOccurrences(of: "phosphene.", with: "uzume.")
            #expect(
                defaults.object(forKey: renamed) != nil,
                "\(legacyKey) did not reach \(renamed) — the setting would silently reset"
            )
            #expect(
                defaults.object(forKey: legacyKey) == nil,
                "\(legacyKey) survived migration — it should be removed once carried"
            )
        }
    }

    /// Values must survive the hop, not just the keys.
    @Test func rn6_migrationPreservesValues() {
        let defaults = makeSuite()
        defaults.set(false, forKey: "phosphene.settings.visuals.showLiveAdaptationToasts")
        defaults.set(1_073_741_824, forKey: "phosphene.cache.localFile.maxBytes")
        defaults.set(["/tmp/a.m4a", "/tmp/b.m4a"], forKey: "phosphene.lf.recents")

        SettingsMigrator.migrate(in: defaults)

        #expect(defaults.bool(forKey: "uzume.settings.visuals.showLiveAdaptationToasts") == false)
        #expect(defaults.integer(forKey: "uzume.cache.localFile.maxBytes") == 1_073_741_824)
        #expect(defaults.stringArray(forKey: "uzume.lf.recents") == ["/tmp/a.m4a", "/tmp/b.m4a"])
    }

    /// An install that never launched between U.6 and RN.6 holds the flat pre-scheme key
    /// and must still land in uzume.* in a single pass — no intermediate hop required.
    @Test func rn6_preSchemeInstallLandsInUzumeInOnePass() {
        let defaults = makeSuite()
        defaults.set(true, forKey: "phosphene.showLiveAdaptationToasts")

        SettingsMigrator.migrate(in: defaults)

        #expect(defaults.bool(forKey: "uzume.settings.visuals.showLiveAdaptationToasts") == true)
        #expect(defaults.object(forKey: "phosphene.showLiveAdaptationToasts") == nil)
        #expect(defaults.object(forKey: "phosphene.settings.visuals.showLiveAdaptationToasts") == nil)
    }

    @Test func migrate_idempotent() {
        let defaults = makeSuite()
        defaults.set(true, forKey: "phosphene.showLiveAdaptationToasts")

        SettingsMigrator.migrate(in: defaults)
        SettingsMigrator.migrate(in: defaults)

        #expect(defaults.bool(forKey: "uzume.settings.visuals.showLiveAdaptationToasts") == true)
        #expect(defaults.object(forKey: "phosphene.showLiveAdaptationToasts") == nil)
    }

    @Test func migrate_noOldKeys_noOp() {
        let defaults = makeSuite()

        SettingsMigrator.migrate(in: defaults)

        #expect(defaults.object(forKey: "uzume.settings.visuals.showLiveAdaptationToasts") == nil)
    }

    @Test func migrate_newKeyAlreadyPresent_cleansOldKey() {
        let defaults = makeSuite()
        defaults.set(false, forKey: "phosphene.showLiveAdaptationToasts")
        defaults.set(true, forKey: "uzume.settings.visuals.showLiveAdaptationToasts")

        SettingsMigrator.migrate(in: defaults)

        // New key preserved as-is, old key removed.
        #expect(defaults.bool(forKey: "uzume.settings.visuals.showLiveAdaptationToasts") == true)
        #expect(defaults.object(forKey: "phosphene.showLiveAdaptationToasts") == nil)
    }
}
