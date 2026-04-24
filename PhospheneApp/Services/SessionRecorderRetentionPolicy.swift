// SessionRecorderRetentionPolicy — Prunes old session recording folders at app launch.
//
// Called once at app launch via PhospheneApp.init. Runs synchronously (no background)
// since folder counts are typically small (<100) and deletion is fast.
//
// Safety constraints:
//   - Never deletes a folder modified within the last 60 seconds (active session guard).
//   - If the sessions directory does not exist, no-op — does NOT create it.

import Foundation
import os.log

private let logger = Logger(subsystem: "com.phosphene.app", category: "SessionRecorderRetentionPolicy")

// MARK: - SessionRecorderRetentionPolicy

enum SessionRecorderRetentionPolicy {

    // MARK: - API

    /// Apply the retention policy, deleting session folders that exceed the limit.
    ///
    /// - Parameters:
    ///   - policy: The retention rule from SettingsStore.
    ///   - sessionsDir: The ~/Documents/phosphene_sessions/ URL. Defaults to the standard location.
    ///   - now: Current date (injectable for testing).
    static func apply(
        policy: SessionRetentionPolicy,
        sessionsDir: URL = defaultSessionsDir,
        now: Date = Date(),
        wallClock: Date = Date()
    ) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: sessionsDir.path) else {
            logger.debug("SessionRecorderRetentionPolicy: sessions directory absent — no-op")
            return
        }

        guard policy != .keepAll else {
            logger.debug("SessionRecorderRetentionPolicy: keepAll — no deletions")
            return
        }

        let folders = sessionFolders(in: sessionsDir, fm: fm)
        let toDelete = foldersToDelete(folders, policy: policy, now: now, wallClock: wallClock)

        for url in toDelete {
            do {
                try fm.removeItem(at: url)
                logger.info("SessionRecorderRetentionPolicy: deleted \(url.lastPathComponent)")
            } catch {
                logger.warning("SessionRecorderRetentionPolicy: failed to delete \(url.lastPathComponent) — \(error)")
            }
        }
    }

    // MARK: - Default URL

    static var defaultSessionsDir: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("phosphene_sessions")
    }

    // MARK: - Private helpers

    private static func sessionFolders(in dir: URL, fm: FileManager) -> [(url: URL, name: String)] {
        let contents = (try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: .skipsHiddenFiles
        )) ?? []

        return contents
            .filter { url in
                var isDir: ObjCBool = false
                fm.fileExists(atPath: url.path, isDirectory: &isDir)
                return isDir.boolValue
            }
            .map { ($0, $0.lastPathComponent) }
            .sorted { $0.name > $1.name } // newest first (ISO timestamps sort lexicographically)
    }

    private static func foldersToDelete(
        _ folders: [(url: URL, name: String)],
        policy: SessionRetentionPolicy,
        now: Date,
        wallClock: Date = Date()
    ) -> [URL] {
        // Never delete a folder modified in the last 60 s (active session guard).
        // Uses wallClock (real time) — the injected `now` is only for cutoff math.
        let fm = FileManager.default
        let activeThreshold: TimeInterval = 60

        func isActive(_ url: URL) -> Bool {
            guard let attrs = try? fm.attributesOfItem(atPath: url.path),
                  let modDate = attrs[.modificationDate] as? Date
            else { return false }
            return wallClock.timeIntervalSince(modDate) < activeThreshold
        }

        switch policy {
        case .keepAll:
            return []

        case .lastN10:
            return Array(folders.dropFirst(10)).map(\.url).filter { !isActive($0) }

        case .lastN25:
            return Array(folders.dropFirst(25)).map(\.url).filter { !isActive($0) }

        case .oneDay:
            let cutoff = now.addingTimeInterval(-86_400)
            let oneDayExpired = folders.filter { folder in
                guard let date = dateFromFolderName(folder.name) else { return false }
                return date < cutoff && !isActive(folder.url)
            }
            return oneDayExpired.map(\.url)

        case .oneWeek:
            let cutoff = now.addingTimeInterval(-7 * 86_400)
            let oneWeekExpired = folders.filter { folder in
                guard let date = dateFromFolderName(folder.name) else { return false }
                return date < cutoff && !isActive(folder.url)
            }
            return oneWeekExpired.map(\.url)
        }
    }

    /// Parses the ISO-8601 timestamp from session folder names like "2026-04-24T21-05-47Z".
    private static func dateFromFolderName(_ name: String) -> Date? {
        // Session folders use hyphens instead of colons in the time component.
        let normalized = name
            .replacingOccurrences(of: "T", with: "T")
            .replacingOccurrences(of: "-", with: ":")
        // Re-substitute the date separator
        let fixed = normalized
            .replacingCharacters(in: normalized.startIndex..<normalized.index(normalized.startIndex, offsetBy: 10),
                                 with: String(name.prefix(10)))
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withColonSeparatorInTimeZone]
        return formatter.date(from: fixed + (fixed.hasSuffix("Z") ? "" : "Z"))
    }
}
