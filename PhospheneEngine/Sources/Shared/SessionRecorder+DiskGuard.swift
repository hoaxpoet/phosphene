// SessionRecorder+DiskGuard — CLEAN.3.8 / GAP-6: disk-full / write-failure graceful
// degradation. The recorder wrote per-frame CSV + log via the NON-throwing
// `FileHandle.write(_:)`, which raises an uncatchable Objective-C exception on ENOSPC
// (disk full) → process crash, and can leave a half-written final row. These helpers
// route every write through `safeWrite`, which on failure halts the recorder honestly:
// it stops writing, logs once to the unified log (the on-disk log may also be unwritable),
// and retains whatever was already flushed. A pre-flight capacity check warns at session
// start. PersistentStemCache is already safe (atomic `write(to:options:.atomic)` + a
// throwing, caught `store`), so it is intentionally untouched.

import Foundation
import os.log

private let diskGuardLogger = Logger(subsystem: "com.phosphene", category: "SessionRecorder")

extension SessionRecorder {

    /// Minimum free bytes the recorder wants before/while recording (~a few seconds of
    /// video plus CSV/log headroom). Below this the pre-flight check warns; actual
    /// exhaustion is caught by `safeWrite` → `haltRecording`.
    static let minFreeBytesForRecording: Int64 = 200 * 1024 * 1024   // 200 MB

    /// Write `data` to `handle`, halting the recorder on failure. Returns `false` when the
    /// write was skipped (already halted) or failed (disk full). Uses the throwing
    /// `write(contentsOf:)` so an ENOSPC error is caught rather than raised as an
    /// uncatchable exception. Must be called on the recorder's serial `queue`.
    @discardableResult
    func safeWrite(_ data: Data, to handle: FileHandle) -> Bool {
        guard !recordingHalted else { return false }
        do {
            try handle.write(contentsOf: data)
            return true
        } catch {
            haltRecording(reason: "session-file write failed (likely disk full): \(error)")
            return false
        }
    }

    /// Stop recording honestly: set `recordingHalted`, log once to the unified log (the
    /// on-disk `session.log` may itself be unwritable). Idempotent. On the serial `queue`.
    func haltRecording(reason: String) {
        guard !recordingHalted else { return }
        recordingHalted = true
        let msg = "SessionRecorder HALTED: \(reason) — diagnostics stopped, "
            + "partial artifacts retained (CLEAN.3.8)"
        diskGuardLogger.error("\(msg, privacy: .public)")
    }

    // MARK: - Pre-flight capacity check

    /// `true` when at least `required` bytes are free. Unknown capacity (`nil`, e.g. a query
    /// failure) is permissive — never refuse recording because the volume couldn't be read.
    /// Pure → unit-testable.
    static func hasSufficientDiskSpace(
        availableBytes: Int64?,
        required: Int64 = minFreeBytesForRecording
    ) -> Bool {
        guard let availableBytes else { return true }
        return availableBytes >= required
    }

    /// Bytes available for important usage on the volume backing `url`, or `nil` if the
    /// volume can't be queried.
    static func availableBytes(at url: URL) -> Int64? {
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    /// Log a loud warning at session start if free space is below `minFreeBytesForRecording`.
    /// Recording still proceeds (a short session may fit); `safeWrite` halts honestly if it
    /// actually fills.
    static func warnIfLowDiskSpace(at url: URL) {
        let available = availableBytes(at: url)
        guard !hasSufficientDiskSpace(availableBytes: available) else { return }
        let mb = (available ?? 0) / (1024 * 1024)
        let msg = "SessionRecorder: low disk space (\(mb) MB free) at session start — "
            + "recording will halt honestly if the volume fills (CLEAN.3.8)"
        diskGuardLogger.warning("\(msg, privacy: .public)")
    }
}
