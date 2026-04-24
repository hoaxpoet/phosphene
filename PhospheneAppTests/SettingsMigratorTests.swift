// SettingsMigratorTests — Migration tests for SettingsMigrator (U.8 Part A).

import Foundation
import Testing
@testable import PhospheneApp

// MARK: - SettingsMigratorTests

@Suite("SettingsMigrator")
struct SettingsMigratorTests {

    private func makeSuite() -> UserDefaults {
        guard let suite = UserDefaults(suiteName: "com.phosphene.test.migrator.\(UUID().uuidString)") else {
            fatalError("UserDefaults suite init failed — test setup error")
        }
        return suite
    }

    @Test func oldShowLiveAdaptationToasts_migratesToNewKey() {
        let defaults = makeSuite()
        defaults.set(true, forKey: "phosphene.showLiveAdaptationToasts")

        SettingsMigrator.migrate(in: defaults)

        #expect(defaults.bool(forKey: "phosphene.settings.visuals.showLiveAdaptationToasts") == true)
        #expect(defaults.object(forKey: "phosphene.showLiveAdaptationToasts") == nil)
    }

    @Test func migrate_idempotent() {
        let defaults = makeSuite()
        defaults.set(true, forKey: "phosphene.showLiveAdaptationToasts")

        SettingsMigrator.migrate(in: defaults)
        SettingsMigrator.migrate(in: defaults)

        #expect(defaults.bool(forKey: "phosphene.settings.visuals.showLiveAdaptationToasts") == true)
        #expect(defaults.object(forKey: "phosphene.showLiveAdaptationToasts") == nil)
    }

    @Test func migrate_noOldKeys_noOp() {
        let defaults = makeSuite()

        SettingsMigrator.migrate(in: defaults)

        #expect(defaults.object(forKey: "phosphene.settings.visuals.showLiveAdaptationToasts") == nil)
    }

    @Test func migrate_newKeyAlreadyPresent_cleansOldKey() {
        let defaults = makeSuite()
        defaults.set(false, forKey: "phosphene.showLiveAdaptationToasts")
        defaults.set(true, forKey: "phosphene.settings.visuals.showLiveAdaptationToasts")

        SettingsMigrator.migrate(in: defaults)

        // New key preserved as-is, old key removed.
        #expect(defaults.bool(forKey: "phosphene.settings.visuals.showLiveAdaptationToasts") == true)
        #expect(defaults.object(forKey: "phosphene.showLiveAdaptationToasts") == nil)
    }
}
