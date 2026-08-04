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

    /// Session folders only — directories whose name parses as a session timestamp.
    ///
    /// The name check is load-bearing, not defensive (BUG-082). `phosphene_sessions/` also
    /// holds permanent non-session directories — `fixturegen-love_rehab`, `fixturegen-so_what`,
    /// `fixturegen-there_there`, `beat-match-test-session` — and the sort below is
    /// lexicographic, where letters rank above digits. Unfiltered, those four sorted ABOVE
    /// every real session, so `lastN10` spent four of its ten slots on them (and could never
    /// prune them, since they were always inside the kept prefix). Retention was silently
    /// `lastN6`, and real captures were deleted while still in use.
    ///
    /// Filtering here rather than in each policy arm is deliberate: a directory that is not a
    /// session is not this policy's business at all — it must neither be COUNTED against the
    /// limit nor be a deletion candidate. The `oneDay`/`oneWeek` arms already consulted
    /// `dateFromFolderName`; only the `lastN` arms did not, which is the whole defect.
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
            .filter { dateFromFolderName($0.name) != nil }
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

    /// Parses the timestamp from a session folder name like `2026-04-24T21-05-47Z`, or `nil`
    /// if the name is not a session folder at all.
    ///
    /// A strict whole-string format match, replacing a character-substitution routine that
    /// unconditionally did `index(startIndex, offsetBy: 10)` — which traps on any name
    /// shorter than ten characters. That was reachable only from the `oneDay`/`oneWeek` arms
    /// before; BUG-082's fix calls this on EVERY directory, so a folder named `old/` next to
    /// the sessions would have crashed app launch. The formatter is built per call rather
    /// than cached in a `static` because `DateFormatter` is not `Sendable`; this runs once
    /// per folder at launch over a handful of folders.
    private static func dateFromFolderName(_ name: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss'Z'"
        return formatter.date(from: name)
    }
}
