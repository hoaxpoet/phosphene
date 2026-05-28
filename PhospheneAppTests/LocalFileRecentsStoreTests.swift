// LocalFileRecentsStoreTests — LF.5 / D-132 Recents persistence regression.
//
// Each test owns a fresh `UserDefaults(suiteName:)` so the user's real
// `phosphene.lf.recents` entry is never read or written.

import Foundation
import Testing
@testable import PhospheneApp

@Suite("LocalFileRecentsStore (LF.5)")
@MainActor
struct LocalFileRecentsStoreTests {

    // MARK: - Helpers

    /// Allocate a private UserDefaults suite for one test. Returns the
    /// defaults instance + the suite name (so the test's defer can remove
    /// the persistence record cleanly).
    private func makeSuite() -> (UserDefaults, String) {
        let suite = "LocalFileRecentsStoreTests-\(UUID().uuidString)"
        // swiftlint:disable:next force_unwrapping
        return (UserDefaults(suiteName: suite)!, suite)
    }

    private func cleanup(suite: String) {
        UserDefaults.standard.removePersistentDomain(forName: suite)
    }

    private func makeURL(_ name: String) -> URL {
        URL(fileURLWithPath: "/private/var/tmp/\(name)")
    }

    // MARK: - Init / load

    @Test func init_emptyDefaults_returnsEmptyList() throws {
        let (defaults, suite) = makeSuite()
        defer { cleanup(suite: suite) }
        let store = LocalFileRecentsStore(userDefaults: defaults, key: "phosphene.lf.recents")
        #expect(store.recents.isEmpty)
    }

    // MARK: - addOrPromote

    @Test func addOrPromote_addsNewItem_atPositionOne() throws {
        let (defaults, suite) = makeSuite()
        defer { cleanup(suite: suite) }
        let store = LocalFileRecentsStore(userDefaults: defaults, key: "phosphene.lf.recents")

        store.addOrPromote(url: makeURL("a.m4a"), kind: .file)

        #expect(store.recents.count == 1)
        #expect(store.recents[0].url == makeURL("a.m4a"))
        #expect(store.recents[0].kind == .file)
    }

    @Test func addOrPromote_movesExistingToFront_lruStyle() throws {
        let (defaults, suite) = makeSuite()
        defer { cleanup(suite: suite) }
        let store = LocalFileRecentsStore(userDefaults: defaults, key: "phosphene.lf.recents")

        store.addOrPromote(url: makeURL("a.m4a"), kind: .file)
        store.addOrPromote(url: makeURL("b.m4a"), kind: .file)
        store.addOrPromote(url: makeURL("c.m4a"), kind: .file)
        // Re-open a.m4a — should move to front.
        store.addOrPromote(url: makeURL("a.m4a"), kind: .file)

        #expect(store.recents.map { $0.url } == [makeURL("a.m4a"), makeURL("c.m4a"), makeURL("b.m4a")])
    }

    @Test func addOrPromote_capsAtMaxRecents() throws {
        let (defaults, suite) = makeSuite()
        defer { cleanup(suite: suite) }
        let store = LocalFileRecentsStore(userDefaults: defaults, key: "phosphene.lf.recents")

        // Add 15 items — only the most recent 10 should survive.
        for index in 0..<15 {
            store.addOrPromote(url: makeURL("file-\(index).m4a"), kind: .file)
        }

        #expect(store.recents.count == LocalFileRecentsStore.maxRecents)
        // Most recent is file-14.m4a; oldest in list is file-5.m4a.
        #expect(store.recents.first?.url == makeURL("file-14.m4a"))
        #expect(store.recents.last?.url == makeURL("file-5.m4a"))
    }

    @Test func addOrPromote_perKindIdentity() throws {
        // A .file at /tmp/a vs a .folder at /tmp/a are distinct entries.
        let (defaults, suite) = makeSuite()
        defer { cleanup(suite: suite) }
        let store = LocalFileRecentsStore(userDefaults: defaults, key: "phosphene.lf.recents")

        store.addOrPromote(url: makeURL("a"), kind: .file)
        store.addOrPromote(url: makeURL("a"), kind: .folder)

        #expect(store.recents.count == 2)
        #expect(store.recents[0].kind == .folder)
        #expect(store.recents[1].kind == .file)
    }

    // MARK: - remove + clearAll

    @Test func remove_dropsTargetedItem() throws {
        let (defaults, suite) = makeSuite()
        defer { cleanup(suite: suite) }
        let store = LocalFileRecentsStore(userDefaults: defaults, key: "phosphene.lf.recents")

        store.addOrPromote(url: makeURL("a.m4a"), kind: .file)
        store.addOrPromote(url: makeURL("b.m4a"), kind: .file)
        let toRemove = store.recents[0]
        store.remove(toRemove)

        #expect(store.recents.count == 1)
        #expect(store.recents[0].url == makeURL("a.m4a"))
    }

    @Test func clearAll_emptiesList() throws {
        let (defaults, suite) = makeSuite()
        defer { cleanup(suite: suite) }
        let store = LocalFileRecentsStore(userDefaults: defaults, key: "phosphene.lf.recents")

        for index in 0..<5 {
            store.addOrPromote(url: makeURL("file-\(index).m4a"), kind: .file)
        }
        store.clearAll()

        #expect(store.recents.isEmpty)
    }

    // MARK: - Persistence roundtrip

    @Test func persistenceRoundtrip_acrossInstances() throws {
        let (defaults, suite) = makeSuite()
        defer { cleanup(suite: suite) }

        do {
            let store = LocalFileRecentsStore(userDefaults: defaults, key: "phosphene.lf.recents")
            store.addOrPromote(url: makeURL("a.m4a"), kind: .file)
            store.addOrPromote(url: makeURL("playlist.m3u"), kind: .m3u)
            store.addOrPromote(url: makeURL("Music"), kind: .folder)
        }

        // Second instance over the same UserDefaults — list should restore.
        let restored = LocalFileRecentsStore(userDefaults: defaults, key: "phosphene.lf.recents")
        #expect(restored.recents.count == 3)
        #expect(restored.recents[0].url == makeURL("Music"))
        #expect(restored.recents[0].kind == .folder)
        #expect(restored.recents[2].url == makeURL("a.m4a"))
    }

    @Test func load_truncatesOversizedPersistedList() throws {
        let (defaults, suite) = makeSuite()
        defer { cleanup(suite: suite) }

        // Simulate a corrupted future-version write with 15 items.
        var oversized: [RecentItem] = []
        for index in 0..<15 {
            oversized.append(RecentItem(
                url: makeURL("file-\(index).m4a"),
                kind: .file,
                openedAt: Date()
            ))
        }
        let data = try JSONEncoder().encode(oversized)
        defaults.set(data, forKey: "phosphene.lf.recents")

        let store = LocalFileRecentsStore(userDefaults: defaults, key: "phosphene.lf.recents")
        #expect(store.recents.count == LocalFileRecentsStore.maxRecents)
    }

    // MARK: - Stale detection

    @Test func isMissing_detectsAbsentFile() throws {
        let absent = makeURL("definitely-not-here-\(UUID().uuidString).m4a")
        let item = RecentItem(url: absent, kind: .file)
        #expect(item.isMissing)
    }

    @Test func isMissing_returnsFalseForExistingFile() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("LocalFileRecentsStoreTests-\(UUID().uuidString).m4a")
        try Data().write(to: dir)
        defer { try? FileManager.default.removeItem(at: dir) }

        let item = RecentItem(url: dir, kind: .file)
        #expect(item.isMissing == false)
    }

    @Test func displayLabel_returnsBareFileName_perGapERefresh() throws {
        // GAP E (2026-05-28): kind disambiguation moved from prefixed text
        // into a leading SF Symbol via `systemImage`. displayLabel is now
        // just the URL's last path component for every kind.
        let file = RecentItem(url: makeURL("song.m4a"), kind: .file)
        let folder = RecentItem(url: makeURL("Music"), kind: .folder)
        let playlist = RecentItem(url: makeURL("mix.m3u"), kind: .m3u)

        #expect(file.displayLabel == "song.m4a")
        #expect(folder.displayLabel == "Music")
        #expect(playlist.displayLabel == "mix.m3u")
    }

    @Test func systemImage_mapsKindToSFSymbol_perGapERefresh() throws {
        let file = RecentItem(url: makeURL("song.m4a"), kind: .file)
        let folder = RecentItem(url: makeURL("Music"), kind: .folder)
        let playlist = RecentItem(url: makeURL("mix.m3u"), kind: .m3u)

        #expect(file.systemImage == "waveform")
        #expect(folder.systemImage == "folder.fill")
        #expect(playlist.systemImage == "music.note.list")
    }
}
