// LocalFileRecentsStore — LF.5 / D-132 "Open Recent ▸" persistence layer.
//
// Owns the `phosphene.lf.recents` UserDefaults entry: a JSON-encoded list
// of the last `maxRecents` (default 10) local-file / folder / M3U opens.
// `File → Open Recent ▸` reactively rebuilds from the published list, and
// the entry-add hook in `LocalFileMenuCommands` calls `addOrPromote(...)`
// every time the user successfully opens a local file from any surface
// (menu picker, drag-and-drop, file-association, env-var hook).
//
// Entry semantics:
//   - LRU: re-opening an entry already in the list moves it to position 1.
//   - Capacity-bounded: the oldest entry falls off when a new one lands
//     beyond `maxRecents`.
//   - Stale-aware: `RecentItem.isMissing` returns `true` when the file at
//     `url.path` no longer exists. The menu surfaces these as disabled
//     "(missing)" rows; one click on a missing item removes it.
//   - Defensive on load: a persisted list of length > `maxRecents`
//     (corrupted UserDefaults from a future-version write) is truncated
//     on load and re-persisted at the next mutation.

import Combine
import Foundation
import os.log

private let recentsLogger = Logger(
    subsystem: "com.phosphene.app",
    category: "LocalFileRecentsStore"
)

// MARK: - RecentKind

/// Distinguishes the four LF.5 entry shapes. The menu uses this to choose
/// an icon and a label format ("[filename]" vs "Folder: [name]" vs
/// "Playlist: [name]").
public enum RecentKind: String, Codable, Sendable, Equatable {
    case file
    case folder
    case m3u
}

// MARK: - RecentItem

/// One entry in the Recents list.
public struct RecentItem: Codable, Sendable, Equatable, Identifiable, Hashable {

    public let url: URL
    public let kind: RecentKind
    public let openedAt: Date

    public init(url: URL, kind: RecentKind, openedAt: Date = Date()) {
        self.url = url
        self.kind = kind
        self.openedAt = openedAt
    }

    /// `RecentItem` is identified by `(url, kind)`; the timestamp is mutable
    /// (refreshes on every re-open) and not part of identity.
    public var id: String { url.absoluteString + "|" + kind.rawValue }

    /// `true` when the file / folder / M3U at `url` no longer exists. The
    /// menu disables these rows and surfaces "(missing)" alongside the
    /// title.
    public var isMissing: Bool {
        !FileManager.default.fileExists(atPath: url.path)
    }

    /// Display label for the menu row.
    ///
    /// GAP E refresh (2026-05-28): returns the bare filename / folder name —
    /// kind is no longer disambiguated via prefix text ("Folder: " /
    /// "Playlist: "). The leading SF Symbol from `systemImage` carries that
    /// signal instead, matching macOS menu conventions (folder.fill +
    /// folder name, music.note.list + playlist name, etc.).
    public var displayLabel: String {
        url.lastPathComponent
    }

    /// SF Symbol name for the leading glyph in `File → Open Recent ▸` menu
    /// items. Per GAP E (2026-05-28) the kind-disambiguation moves from
    /// prefixed text into a system glyph — readable at a glance, idiomatic
    /// for macOS menus.
    public var systemImage: String {
        switch kind {
        case .file:   return "waveform"
        case .folder: return "folder.fill"
        case .m3u:    return "music.note.list"
        }
    }
}

// MARK: - LocalFileRecentsStore

/// Observable wrapper around `phosphene.lf.recents` UserDefaults persistence.
///
/// Constructed once per app launch in `PhospheneApp` and injected into the
/// `File → Open Recent ▸` menu builder + the LF dispatch glue so every
/// successful open promotes an entry to position 1.
@MainActor
public final class LocalFileRecentsStore: ObservableObject {

    // MARK: - Constants

    public static let defaultUserDefaultsKey: String = "phosphene.lf.recents"
    public static let maxRecents: Int = 10

    // MARK: - State

    @Published public private(set) var recents: [RecentItem] = []

    private let userDefaults: UserDefaults
    private let userDefaultsKey: String

    // MARK: - Init

    public init(
        userDefaults: UserDefaults = .standard,
        key: String = LocalFileRecentsStore.defaultUserDefaultsKey
    ) {
        self.userDefaults = userDefaults
        self.userDefaultsKey = key
        self.recents = Self.load(from: userDefaults, key: key)
    }

    // MARK: - Mutation

    /// Add a new entry at position 1, OR move an existing entry (matched
    /// on `url + kind`) to position 1. The timestamp refreshes to `now`.
    /// Truncates to `maxRecents` after insert.
    public func addOrPromote(url: URL, kind: RecentKind, at now: Date = Date()) {
        var list = recents
        list.removeAll { $0.url == url && $0.kind == kind }
        list.insert(RecentItem(url: url, kind: kind, openedAt: now), at: 0)
        if list.count > Self.maxRecents {
            list = Array(list.prefix(Self.maxRecents))
        }
        recents = list
        persist()
    }

    /// Remove a single entry by identity. No-op when not present.
    public func remove(_ item: RecentItem) {
        recents.removeAll { $0.id == item.id }
        persist()
    }

    /// Drop every entry.
    public func clearAll() {
        recents = []
        persist()
    }

    // MARK: - Persistence

    private func persist() {
        do {
            let data = try JSONEncoder().encode(recents)
            userDefaults.set(data, forKey: userDefaultsKey)
        } catch {
            recentsLogger.warning(
                "[LF.5] LocalFileRecentsStore persist failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// Load the persisted list. Returns `[]` on missing / malformed JSON.
    /// Defensively truncates to `maxRecents` (corrupted UserDefaults from
    /// a future-version write could ship more).
    private static func load(from defaults: UserDefaults, key: String) -> [RecentItem] {
        guard let data = defaults.data(forKey: key) else { return [] }
        do {
            let decoded = try JSONDecoder().decode([RecentItem].self, from: data)
            return Array(decoded.prefix(maxRecents))
        } catch {
            recentsLogger.warning(
                "[LF.5] LocalFileRecentsStore load failed: \(error.localizedDescription, privacy: .public)"
            )
            return []
        }
    }
}
