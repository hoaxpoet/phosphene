// SessionRecorderRetentionPolicyTests — Tests for SessionRecorderRetentionPolicy (U.8 Part C).

import Foundation
import Testing
@testable import PhospheneApp

// MARK: - SessionRecorderRetentionPolicyTests

@Suite("SessionRecorderRetentionPolicy")
struct SessionRecorderRetentionPolicyTests {

    // MARK: - Helpers

    private func makeTempDir() throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhospheneRetentionTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        return tmp
    }

    private func createSessions(in dir: URL, names: [String]) throws {
        for name in names {
            let folder = dir.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
    }

    private func names(in dir: URL) throws -> Set<String> {
        let contents = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        return Set(contents)
    }

    // Sorted newest-first ISO timestamps
    private let timestamps: [String] = {
        let forward = (1...15).map { "2026-04-\(String(format: "%02d", $0))T12-00-00Z" }
        return Array(forward.reversed())
    }()

    /// A wallClock far in the future so freshly-created test folders don't trigger
    /// the "active session" 60-second guard.
    private var futureWallClock: Date { Date().addingTimeInterval(3600) }

    private func parseISO(_ string: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: string) else { fatalError("date parse failed: \(string)") }
        return date
    }

    @Test func lastN10_keepsOnly10Newest() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try createSessions(in: dir, names: timestamps) // 15 sessions

        SessionRecorderRetentionPolicy.apply(
            policy: .lastN10, sessionsDir: dir, wallClock: futureWallClock
        )

        let remaining = try names(in: dir)
        #expect(remaining.count == 10)
        #expect(remaining.contains("2026-04-15T12-00-00Z"))
        #expect(!remaining.contains("2026-04-01T12-00-00Z"))
    }

    @Test func keepAll_noDeletions() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try createSessions(in: dir, names: Array(timestamps.prefix(5)))

        SessionRecorderRetentionPolicy.apply(
            policy: .keepAll, sessionsDir: dir, wallClock: futureWallClock
        )

        let remaining = try names(in: dir)
        #expect(remaining.count == 5)
    }

    @Test func oneDay_deletesOlderThan24h() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let old = "2026-04-01T12-00-00Z"
        let recent = "2026-04-15T12-00-00Z"
        try createSessions(in: dir, names: [old, recent])

        let now = parseISO("2026-04-16T12:00:00Z")

        SessionRecorderRetentionPolicy.apply(
            policy: .oneDay, sessionsDir: dir, now: now, wallClock: futureWallClock
        )

        let remaining = try names(in: dir)
        #expect(remaining.contains(recent))
        #expect(!remaining.contains(old))
    }

    @Test func oneWeek_deletesOlderThan7d() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        // "old" is 23 days before "now", "recent" is 4 days before "now".
        // With a 7-day cutoff (now=Apr24), anything before Apr17 is deleted.
        let old = "2026-04-01T12-00-00Z"
        let recent = "2026-04-20T12-00-00Z"
        try createSessions(in: dir, names: [old, recent])

        let now = parseISO("2026-04-24T12:00:00Z")

        SessionRecorderRetentionPolicy.apply(
            policy: .oneWeek, sessionsDir: dir, now: now, wallClock: futureWallClock
        )

        let remaining = try names(in: dir)
        #expect(remaining.contains(recent))
        #expect(!remaining.contains(old))
    }

    @Test func activeSession_neverDeleted() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Create 11 sessions with ISO names.
        let oldNames = (1...11).map { "2026-04-\(String(format: "%02d", $0))T12-00-00Z" }
        try createSessions(in: dir, names: oldNames)

        // Active session: just created so modDate = wallClock (within 60 s guard).
        let active = dir.appendingPathComponent("2026-04-30T23-59-00Z")
        try FileManager.default.createDirectory(at: active, withIntermediateDirectories: true)

        // Pass `now` as a past time (2026-04-24 matches current wallClock date range).
        // The apply function uses wallClock (real Date()) internally for the active guard.
        SessionRecorderRetentionPolicy.apply(policy: .lastN10, sessionsDir: dir)

        // Active session must survive even though it's the 12th (11 + active)
        let remaining = try names(in: dir)
        #expect(remaining.contains("2026-04-30T23-59-00Z"))
    }

    @Test func missingDirectory_noOp_noCreation() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("DoesNotExist-\(UUID().uuidString)")

        // Must not throw or create the directory
        SessionRecorderRetentionPolicy.apply(policy: .lastN10, sessionsDir: missing)

        #expect(!FileManager.default.fileExists(atPath: missing.path))
    }

    // MARK: - BUG-082: non-session folders must not occupy retention slots

    /// The real directory holds four permanent non-session folders. Before the fix they
    /// sorted ABOVE every timestamped session (letters rank above digits in a descending
    /// lexicographic sort), so they consumed four of `lastN10`'s ten slots and could never be
    /// pruned themselves — retention was silently `lastN6` and real captures were deleted
    /// while still in use.
    private static let realWorldNonSessionFolders = [
        "fixturegen-love_rehab",
        "fixturegen-so_what",
        "fixturegen-there_there",
        "beat-match-test-session",
    ]

    @Test func lastN10_nonSessionFoldersNeitherCountedNorDeleted() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        // 12 real sessions, newest first, plus the four permanent fixture folders.
        let sessions = (1...12).map { "2026-04-\(String(format: "%02d", $0))T12-00-00Z" }
        try createSessions(in: dir, names: sessions + Self.realWorldNonSessionFolders)

        SessionRecorderRetentionPolicy.apply(
            policy: .lastN10, sessionsDir: dir, wallClock: futureWallClock
        )

        let remaining = try names(in: dir)

        // Exactly the two OLDEST sessions go — not four of them to make room for fixtures.
        #expect(!remaining.contains("2026-04-01T12-00-00Z"))
        #expect(!remaining.contains("2026-04-02T12-00-00Z"))
        let survivingSessions = remaining.filter { $0.hasPrefix("2026-") }
        #expect(survivingSessions.count == 10, """
            \(survivingSessions.count) sessions survived, expected 10. Non-session folders are \
            being counted against the retention limit again (BUG-082) — `sessionFolders` must \
            filter to names that parse as a session timestamp.
            """)

        // And the fixture folders are untouched: not sessions, so not this policy's business.
        for name in Self.realWorldNonSessionFolders {
            #expect(remaining.contains(name), "retention deleted non-session folder \(name)")
        }
    }

    @Test func oneWeek_doesNotDeleteNonSessionFolders() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try createSessions(in: dir, names: ["2026-04-01T12-00-00Z"] + Self.realWorldNonSessionFolders)

        // `now` far in the future so the lone real session is unambiguously expired.
        SessionRecorderRetentionPolicy.apply(
            policy: .oneWeek,
            sessionsDir: dir,
            now: parseISO("2026-06-01T12:00:00Z"),
            wallClock: futureWallClock
        )

        let remaining = try names(in: dir)
        #expect(!remaining.contains("2026-04-01T12-00-00Z"), "expired session should be pruned")
        for name in Self.realWorldNonSessionFolders {
            #expect(remaining.contains(name), "age-based retention deleted non-session folder \(name)")
        }
    }

    /// The pre-fix name parser did `index(startIndex, offsetBy: 10)` unconditionally, which
    /// traps on any shorter name. Harmless while only the age-based arms called it; the
    /// BUG-082 fix calls it on every directory, so a stray short-named folder would have
    /// crashed app launch.
    @Test func shortAndOddFolderNamesDoNotTrap() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try createSessions(in: dir, names: ["old", "a", "", "tmp", "2026", "2026-04-01T12-00-00Z"]
            .filter { !$0.isEmpty })

        SessionRecorderRetentionPolicy.apply(
            policy: .lastN10, sessionsDir: dir, wallClock: futureWallClock
        )

        let remaining = try names(in: dir)
        for name in ["old", "a", "tmp", "2026"] {
            #expect(remaining.contains(name), "non-session folder \(name) was deleted")
        }
    }
}
