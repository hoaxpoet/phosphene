// ConcurrencyAuditProbe — CLEAN.1.1 diagnostic instrumentation for the
// BUG-031 / BUG-032 session + stem concurrency family.
//
// One root cause spans these defects: a single `StemSeparator` instance is
// shared by the live-playback path (`VisualizerEngine+Stems.performStemSeparation`,
// on `stemQueue`) and the session-prep path (`SessionPreparer.analyzePreview`,
// inside a `Task.detached`), and `separate()` writes its model input buffers
// and reads its model output buffers *outside* any lock (only the internal
// `StemModelEngine.predict()` GPU run is serialized). Two overlapping calls
// therefore interleave input-write → predict → output-read and corrupt each
// other's stems (BUG-031). The same instance is driven by two `_runPreparation`
// loops when `resumeFailedNetworkTracks()` spawns a second loop, and a prep
// task orphaned by `endSession()` can complete after a new session has started
// and overwrite its plan/state (BUG-032).
//
// This probe is PURE OBSERVABILITY. It changes no control flow and gates
// nothing: it allocates monotonic IDs, maintains in-flight / ownership /
// generation counters, and emits `[BUG-031]` / `[BUG-032]`-tagged log lines
// (ALARM at `.notice` level when an invariant the fix will enforce is
// violated). The generation comparison here only *logs*; the behavioural
// guard that mirrors `localFileSessionGen` lands with the CLEAN.1.3 fix.
//
// All members are thread-safe (one NSLock). Mirrors the `BUG012Probe`
// shape (D-079 `nonisolated(unsafe)` + external NSLock synchronization).
// Remove this file when the BUG-031/032 family closes.

import Foundation
import os.log

/// Diagnostic namespace for the BUG-031/032 concurrency family. All members
/// are thread-safe. See the file header for the race analysis that motivates
/// each counter. Logs are emitted via `Logging.concurrencyAudit` and tagged
/// `[BUG-031]` (stem interleave) or `[BUG-032]` (session lifecycle) for
/// grep-ability inside session captures.
public enum ConcurrencyAuditProbe {

    // MARK: - State
    //
    // All `_*` storage is protected by `lock`. `nonisolated(unsafe)` signals
    // to Swift 6 strict concurrency that synchronization is external (the
    // NSLock below), matching the same pattern as `BUG012Probe`.

    private static let lock = NSLock()

    nonisolated(unsafe) private static var _nextAuditID: UInt64 = 0

    // BUG-031 — StemSeparator.separate() interleave.
    nonisolated(unsafe) private static var _separateInFlight: Int = 0
    nonisolated(unsafe) private static var _maxSeparateInFlight: Int = 0
    nonisolated(unsafe) private static var _separateInterleaveCount: Int = 0
    nonisolated(unsafe) private static var _lastInputWriteID: UInt64 = 0

    // BUG-032 — session lifecycle.
    nonisolated(unsafe) private static var _sessionGeneration: UInt64 = 0
    nonisolated(unsafe) private static var _staleCompletionCount: Int = 0
    nonisolated(unsafe) private static var _orphanedEndSessionCount: Int = 0
    nonisolated(unsafe) private static var _runPreparationInFlight: Int = 0
    nonisolated(unsafe) private static var _maxRunPreparationInFlight: Int = 0
    nonisolated(unsafe) private static var _concurrentRunPreparationCount: Int = 0

    // MARK: - Audit ID Allocation

    /// Allocate a monotonic, process-unique ID for one `separate()` call so
    /// its input-write and ownership checks can be correlated in the log.
    public static func nextAuditID() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        _nextAuditID &+= 1
        return _nextAuditID
    }

    // MARK: - BUG-031: separate() In-Flight + Ownership

    /// Record entry into `StemSeparator.separate()`. Returns a fresh audit ID
    /// for this call. If more than one `separate()` is in flight on the shared
    /// instance, emits an ALARM — overlapping calls share the same model I/O
    /// buffers and will corrupt each other.
    @discardableResult
    public static func enterSeparate() -> UInt64 {
        lock.lock()
        _nextAuditID &+= 1
        let auditID = _nextAuditID
        _separateInFlight += 1
        let inFlight = _separateInFlight
        if inFlight > _maxSeparateInFlight { _maxSeparateInFlight = inFlight }
        lock.unlock()
        if inFlight > 1 {
            emitNotice(
                "[BUG-031][ALARM] separate() in-flight=\(inFlight) id=\(auditID) " +
                "thread=\(threadLabel()) — concurrent calls share StemSeparator model I/O buffers"
            )
        } else {
            emitInfo("[BUG-031] separate() enter id=\(auditID) in-flight=\(inFlight) thread=\(threadLabel())")
        }
        return auditID
    }

    /// Record that `separate()` has returned or thrown.
    public static func exitSeparate(id: UInt64, outcome: String) {
        lock.lock()
        _separateInFlight = max(0, _separateInFlight - 1)
        let inFlight = _separateInFlight
        lock.unlock()
        emitInfo(
            "[BUG-031] separate() exit id=\(id) outcome=\(outcome) " +
            "in-flight=\(inFlight) thread=\(threadLabel())"
        )
    }

    /// Record that this call has just written its magnitude data into the
    /// shared `StemModelEngine` input buffers. Stamps the buffers with the
    /// call's audit ID so a later ownership check can detect a clobber.
    public static func recordInputWrite(id: UInt64) {
        lock.lock()
        _lastInputWriteID = id
        lock.unlock()
    }

    /// Verify that the shared input buffers still belong to this call at the
    /// given pipeline stage. Returns `true` when owned. When another call has
    /// overwritten the input since `recordInputWrite`, emits an ALARM and
    /// increments the interleave counter — this is the BUG-031 corruption
    /// window made observable (`predict()` will run, or output will be read,
    /// against a foreign call's data).
    @discardableResult
    public static func checkInputOwnership(id: UInt64, stage: String) -> Bool {
        lock.lock()
        let owner = _lastInputWriteID
        let owned = owner == id
        if !owned { _separateInterleaveCount += 1 }
        let count = _separateInterleaveCount
        lock.unlock()
        if !owned {
            emitNotice(
                "[BUG-031][ALARM] \(stage): input owned by id=\(owner) but this call is id=\(id) " +
                "(interleave #\(count)) thread=\(threadLabel()) — stems will be cross-contaminated"
            )
        }
        return owned
    }

    // MARK: - BUG-032: Session Generation

    /// Advance the session generation at a lifecycle boundary (start / end /
    /// cancel) and return the new value. Observability only — the captured
    /// generation is compared at prep-completion to detect a stale task; no
    /// behaviour gates on it until the CLEAN.1.3 fix.
    @discardableResult
    public static func markSessionBoundary(_ reason: String) -> UInt64 {
        lock.lock()
        _sessionGeneration &+= 1
        let gen = _sessionGeneration
        lock.unlock()
        emitInfo("[BUG-032] session boundary (\(reason)) → generation=\(gen) thread=\(threadLabel())")
        return gen
    }

    /// Current session generation (snapshot of the boundary counter).
    public static func currentSessionGeneration() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return _sessionGeneration
    }

    /// Compare a prep task's spawn generation against the current generation
    /// at completion. Returns `true` when the task is stale (a newer boundary
    /// fired since it was spawned). A stale completion that is *not* the result
    /// of an explicit cancel is the BUG-032 hijack — it is about to overwrite a
    /// newer session's plan/state — and emits an ALARM.
    @discardableResult
    public static func recordPrepCompletion(spawnGeneration: UInt64, cancellationRequested: Bool) -> Bool {
        lock.lock()
        let current = _sessionGeneration
        let isStale = spawnGeneration != current
        if isStale && !cancellationRequested { _staleCompletionCount += 1 }
        let count = _staleCompletionCount
        lock.unlock()
        if isStale && !cancellationRequested {
            emitNotice(
                "[BUG-032][ALARM] prep completion for generation=\(spawnGeneration) under " +
                "current=\(current), cancellationRequested=false (hijack #\(count)) " +
                "thread=\(threadLabel()) — will overwrite the newer session's plan/state"
            )
        } else {
            emitInfo(
                "[BUG-032] prep completion generation=\(spawnGeneration) current=\(current) " +
                "stale=\(isStale) cancelled=\(cancellationRequested) thread=\(threadLabel())"
            )
        }
        return isStale
    }

    /// Record `endSession()` while a prep task or status subscription is still
    /// live. Unlike `cancel()`, `endSession()` does not tear these down, so the
    /// task is orphaned (BUG-032 defect 1). Emits a NOTICE when an orphan is
    /// left behind.
    public static func recordEndSession(hasPrepTask: Bool, hasStatusSubscription: Bool) {
        let orphaned = hasPrepTask || hasStatusSubscription
        lock.lock()
        if orphaned { _orphanedEndSessionCount += 1 }
        let count = _orphanedEndSessionCount
        lock.unlock()
        if orphaned {
            emitNotice(
                "[BUG-032][ALARM] endSession() left a live prep task=\(hasPrepTask) " +
                "statusSubscription=\(hasStatusSubscription) (orphan #\(count)) — not cancelled"
            )
        } else {
            emitInfo("[BUG-032] endSession() with no live prep task")
        }
    }

    // MARK: - BUG-032: _runPreparation Single-Flight

    /// Record entry into a `_runPreparation` loop. Returns the new in-flight
    /// count. More than one loop in flight means `resumeFailedNetworkTracks()`
    /// spawned a second loop over the same `StemSeparator` while the original
    /// was still running (BUG-032 defect 2) — emits an ALARM.
    @discardableResult
    public static func enterRunPreparation() -> Int {
        lock.lock()
        _runPreparationInFlight += 1
        let inFlight = _runPreparationInFlight
        if inFlight > _maxRunPreparationInFlight { _maxRunPreparationInFlight = inFlight }
        if inFlight > 1 { _concurrentRunPreparationCount += 1 }
        let concurrentCount = _concurrentRunPreparationCount
        lock.unlock()
        if inFlight > 1 {
            emitNotice(
                "[BUG-032][ALARM] _runPreparation in-flight=\(inFlight) (concurrent #\(concurrentCount)) " +
                "thread=\(threadLabel()) — two prep loops over one StemSeparator"
            )
        } else {
            emitInfo("[BUG-032] _runPreparation enter in-flight=\(inFlight) thread=\(threadLabel())")
        }
        return inFlight
    }

    /// Record that a `_runPreparation` loop has finished.
    public static func exitRunPreparation() {
        lock.lock()
        _runPreparationInFlight = max(0, _runPreparationInFlight - 1)
        let inFlight = _runPreparationInFlight
        lock.unlock()
        emitInfo("[BUG-032] _runPreparation exit in-flight=\(inFlight) thread=\(threadLabel())")
    }

    // MARK: - Snapshot

    /// Snapshot of every counter. Used by the CLEAN.1.1 instrumentation tests
    /// and (post-fix) by the regression gates.
    public struct Snapshot: Sendable, Equatable {
        public let separateInFlight: Int
        public let maxSeparateInFlight: Int
        public let separateInterleaveCount: Int
        public let sessionGeneration: UInt64
        public let staleCompletionCount: Int
        public let orphanedEndSessionCount: Int
        public let runPreparationInFlight: Int
        public let maxRunPreparationInFlight: Int
        public let concurrentRunPreparationCount: Int
    }

    public static func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return Snapshot(
            separateInFlight: _separateInFlight,
            maxSeparateInFlight: _maxSeparateInFlight,
            separateInterleaveCount: _separateInterleaveCount,
            sessionGeneration: _sessionGeneration,
            staleCompletionCount: _staleCompletionCount,
            orphanedEndSessionCount: _orphanedEndSessionCount,
            runPreparationInFlight: _runPreparationInFlight,
            maxRunPreparationInFlight: _maxRunPreparationInFlight,
            concurrentRunPreparationCount: _concurrentRunPreparationCount
        )
    }

    /// Reset every counter. **Test-only.** Production code never calls this;
    /// the counters are intentionally process-monotonic so they survive across
    /// sessions in a real capture.
    public static func resetForTesting() {
        lock.lock()
        _nextAuditID = 0
        _separateInFlight = 0
        _maxSeparateInFlight = 0
        _separateInterleaveCount = 0
        _lastInputWriteID = 0
        _sessionGeneration = 0
        _staleCompletionCount = 0
        _orphanedEndSessionCount = 0
        _runPreparationInFlight = 0
        _maxRunPreparationInFlight = 0
        _concurrentRunPreparationCount = 0
        lock.unlock()
    }

    // MARK: - Helpers

    /// Compact thread label ("main" / "bg") for log lines.
    private static func threadLabel() -> String {
        Thread.isMainThread ? "main" : "bg"
    }

    /// Single point of contact for `info`-level emission (keeps the
    /// `OSLogMessage` interpolation rules in one place).
    private static func emitInfo(_ message: String) {
        Logging.concurrencyAudit.info("\(message, privacy: .public)")
    }

    /// Single point of contact for `notice`-level emission.
    private static func emitNotice(_ message: String) {
        Logging.concurrencyAudit.notice("\(message, privacy: .public)")
    }
}
