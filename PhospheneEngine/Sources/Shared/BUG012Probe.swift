// BUG012Probe — Diagnostic instrumentation for the MPSGraph EXC_BAD_ACCESS
// crash filed as BUG-012 (see docs/QUALITY/KNOWN_ISSUES.md).
//
// The crash fired once on 2026-05-15 at `StemFFTEngine.runForwardGraph` on
// `Thread 71 — com.phosphene.stemSeparator queue` after repeated
// `ML: force-dispatch after 2100ms` messages. Address 0x8 indicates a nil
// member access; suspected race between the ML dispatch scheduler's
// force-dispatch path and a stem separator with an in-flight buffer / graph.
//
// This probe is pure observability. It does NOT change any behaviour. It
// supplies the next crash with:
//   - Monotonic dispatch sequence numbers (`dispatchID`) so logs across
//     stemQueue, the MainActor scheduler hop, and the FFT engine layers can
//     be correlated for a single separation.
//   - In-flight counters at the two layers where re-entry would be a bug
//     (`stemDispatch` = outer `performStemSeparation`; `fftForward` = inner
//     `StemFFTEngine.forward`). If a counter ever observes > 1, the probe
//     logs a `.notice`-level alarm. The dispatch path's serial-queue
//     analysis says these counters should never exceed 1; a violation
//     would localise the race surface immediately.
//   - Lifecycle counters for `StemFFTEngine`, `StemSeparator`, and
//     `VisualizerEngine` so a crash during teardown is distinguishable
//     from a crash during steady-state operation.
//
// All probe methods are thread-safe. Calls are cheap (one lock acquire +
// one log line); production cost is negligible at the 5 s stem cadence.
//
// Remove this file when BUG-012 closes.

import Foundation
import os.log

/// Diagnostic namespace for BUG-012. All members are thread-safe.
///
/// See file header for the rationale and the dispatch-path analysis that
/// motivated each counter. Logs are emitted via `Logging.bug012` and
/// tagged with `[BUG-012]` for grep-ability inside session captures.
public enum BUG012Probe {

    // MARK: - State
    //
    // All `_*` storage is protected by `lock`. The `nonisolated(unsafe)`
    // annotations signal to Swift 6 strict concurrency that the
    // synchronization is external (NSLock above), not actor isolation —
    // matching the documented "disable concurrency-safety checks if
    // accesses are protected by an external synchronization mechanism"
    // pattern. Same shape as `tapSampleRate` / `_tapSampleRate` in
    // VisualizerEngine (D-079).

    private static let lock = NSLock()
    nonisolated(unsafe) private static var _nextDispatchID: UInt64 = 0
    nonisolated(unsafe) private static var _stemDispatchInFlight: Int = 0
    nonisolated(unsafe) private static var _fftForwardInFlight: Int = 0
    nonisolated(unsafe) private static var _fftInverseInFlight: Int = 0
    nonisolated(unsafe) private static var _stemFFTEngineLiveCount: Int = 0
    nonisolated(unsafe) private static var _stemSeparatorLiveCount: Int = 0
    nonisolated(unsafe) private static var _visualizerEngineLiveCount: Int = 0

    // MARK: - Dispatch ID Allocation

    /// Allocate a monotonic, process-unique ID for the next stem-separation
    /// dispatch. Used as a correlation key across the timer fire, the
    /// MainActor scheduler hop, the stemQueue re-entry, the separator call,
    /// and the underlying FFT-engine calls.
    public static func nextDispatchID() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        _nextDispatchID &+= 1
        return _nextDispatchID
    }

    // MARK: - Stem Dispatch In-Flight Counter (performStemSeparation)

    /// Record that `performStemSeparation` has begun. Returns the new
    /// in-flight count. If it exceeds 1, an alarm-level log is emitted —
    /// the serial-queue analysis says this should be unreachable.
    @discardableResult
    public static func enterStemDispatch(dispatchID: UInt64) -> Int {
        lock.lock()
        _stemDispatchInFlight += 1
        let count = _stemDispatchInFlight
        lock.unlock()
        if count > 1 {
            emitNotice(
                "[BUG-012][ALARM] stem dispatch in-flight=\(count) id=\(dispatchID) " +
                "thread=\(threadLabel()) (serial-queue contract violated)"
            )
        } else {
            emitInfo(
                "[BUG-012] stem dispatch enter id=\(dispatchID) in-flight=\(count) " +
                "thread=\(threadLabel())"
            )
        }
        return count
    }

    /// Record that `performStemSeparation` has finished (or thrown).
    public static func exitStemDispatch(dispatchID: UInt64, outcome: String) {
        lock.lock()
        _stemDispatchInFlight = max(0, _stemDispatchInFlight - 1)
        let count = _stemDispatchInFlight
        lock.unlock()
        emitInfo(
            "[BUG-012] stem dispatch exit id=\(dispatchID) outcome=\(outcome) " +
            "in-flight=\(count) thread=\(threadLabel())"
        )
    }

    // MARK: - FFT Forward In-Flight Counter (StemFFTEngine.forward)

    /// Record that `StemFFTEngine.forward` has begun. Returns the new
    /// in-flight count. Forward is locked internally by an `NSLock`, so
    /// the count should never exceed 1 — a violation would mean either
    /// the lock semantics changed or two engines are sharing the
    /// counter unexpectedly (the latter is impossible — the probe is a
    /// process-global namespace).
    @discardableResult
    public static func enterFFTForward(dispatchID: UInt64) -> Int {
        lock.lock()
        _fftForwardInFlight += 1
        let count = _fftForwardInFlight
        lock.unlock()
        if count > 1 {
            emitNotice(
                "[BUG-012][ALARM] fft forward in-flight=\(count) id=\(dispatchID) " +
                "thread=\(threadLabel()) " +
                "(engine lock semantics violated or shared probe state collided)"
            )
        } else {
            emitInfo(
                "[BUG-012] fft forward enter id=\(dispatchID) in-flight=\(count) " +
                "thread=\(threadLabel())"
            )
        }
        return count
    }

    public static func exitFFTForward(dispatchID: UInt64, outcome: String) {
        lock.lock()
        _fftForwardInFlight = max(0, _fftForwardInFlight - 1)
        let count = _fftForwardInFlight
        lock.unlock()
        emitInfo(
            "[BUG-012] fft forward exit id=\(dispatchID) outcome=\(outcome) " +
            "in-flight=\(count) thread=\(threadLabel())"
        )
    }

    // MARK: - FFT Inverse In-Flight Counter (StemFFTEngine.inverse)

    @discardableResult
    public static func enterFFTInverse(dispatchID: UInt64) -> Int {
        lock.lock()
        _fftInverseInFlight += 1
        let count = _fftInverseInFlight
        lock.unlock()
        if count > 1 {
            emitNotice(
                "[BUG-012][ALARM] fft inverse in-flight=\(count) id=\(dispatchID) " +
                "thread=\(threadLabel())"
            )
        }
        return count
    }

    public static func exitFFTInverse(dispatchID: UInt64, outcome: String) {
        lock.lock()
        _fftInverseInFlight = max(0, _fftInverseInFlight - 1)
        let count = _fftInverseInFlight
        lock.unlock()
        emitInfo(
            "[BUG-012] fft inverse exit id=\(dispatchID) outcome=\(outcome) " +
            "in-flight=\(count)"
        )
    }

    // MARK: - Lifecycle Counters

    public static func recordStemFFTEngineInit() {
        lock.lock()
        _stemFFTEngineLiveCount += 1
        let count = _stemFFTEngineLiveCount
        lock.unlock()
        emitInfo("[BUG-012] StemFFTEngine init — live=\(count)")
    }

    public static func recordStemFFTEngineDeinit() {
        lock.lock()
        _stemFFTEngineLiveCount = max(0, _stemFFTEngineLiveCount - 1)
        let count = _stemFFTEngineLiveCount
        lock.unlock()
        emitNotice(
            "[BUG-012] StemFFTEngine deinit — live=\(count) thread=\(threadLabel())"
        )
    }

    public static func recordStemSeparatorInit() {
        lock.lock()
        _stemSeparatorLiveCount += 1
        let count = _stemSeparatorLiveCount
        lock.unlock()
        emitInfo("[BUG-012] StemSeparator init — live=\(count)")
    }

    public static func recordStemSeparatorDeinit() {
        lock.lock()
        _stemSeparatorLiveCount = max(0, _stemSeparatorLiveCount - 1)
        let count = _stemSeparatorLiveCount
        lock.unlock()
        emitNotice(
            "[BUG-012] StemSeparator deinit — live=\(count) thread=\(threadLabel())"
        )
    }

    public static func recordVisualizerEngineInit() {
        lock.lock()
        _visualizerEngineLiveCount += 1
        let count = _visualizerEngineLiveCount
        lock.unlock()
        emitInfo("[BUG-012] VisualizerEngine init — live=\(count)")
    }

    public static func recordVisualizerEngineDeinit() {
        lock.lock()
        _visualizerEngineLiveCount = max(0, _visualizerEngineLiveCount - 1)
        let count = _visualizerEngineLiveCount
        lock.unlock()
        emitNotice(
            "[BUG-012] VisualizerEngine deinit — live=\(count) thread=\(threadLabel())"
        )
    }

    // MARK: - Free-form Logging

    /// Emit a single informational log line tagged for BUG-012.
    public static func log(
        _ stage: String,
        dispatchID: UInt64? = nil,
        detail: String = ""
    ) {
        let idPart = dispatchID.map { " id=\($0)" } ?? ""
        let detailPart = detail.isEmpty ? "" : " \(detail)"
        emitInfo("[BUG-012] \(stage)\(idPart)\(detailPart) thread=\(threadLabel())")
    }

    /// Emit a notice-level log line (more prominent in `log show` output).
    /// Use for scheduler decisions, force-dispatch firings, and crash-adjacent
    /// boundaries that we want to find quickly.
    public static func notice(
        _ stage: String,
        dispatchID: UInt64? = nil,
        detail: String = ""
    ) {
        let idPart = dispatchID.map { " id=\($0)" } ?? ""
        let detailPart = detail.isEmpty ? "" : " \(detail)"
        emitNotice("[BUG-012] \(stage)\(idPart)\(detailPart) thread=\(threadLabel())")
    }

    // MARK: - Snapshots

    /// Snapshot of all counters. Used by tests + the regression gate.
    public struct Snapshot: Sendable, Equatable {
        public let stemDispatchInFlight: Int
        public let fftForwardInFlight: Int
        public let fftInverseInFlight: Int
        public let stemFFTEngineLive: Int
        public let stemSeparatorLive: Int
        public let visualizerEngineLive: Int
    }

    public static func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return Snapshot(
            stemDispatchInFlight: _stemDispatchInFlight,
            fftForwardInFlight: _fftForwardInFlight,
            fftInverseInFlight: _fftInverseInFlight,
            stemFFTEngineLive: _stemFFTEngineLiveCount,
            stemSeparatorLive: _stemSeparatorLiveCount,
            visualizerEngineLive: _visualizerEngineLiveCount
        )
    }

    /// Reset every counter to zero. **Test-only.** Production code never
    /// calls this; the counters are intentionally process-monotonic so
    /// they survive across sessions.
    public static func resetForTesting() {
        lock.lock()
        _nextDispatchID = 0
        _stemDispatchInFlight = 0
        _fftForwardInFlight = 0
        _fftInverseInFlight = 0
        _stemFFTEngineLiveCount = 0
        _stemSeparatorLiveCount = 0
        _visualizerEngineLiveCount = 0
        lock.unlock()
    }

    // MARK: - Helpers

    /// Compact thread label for log lines. The unified log already includes
    /// thread ID per line; this returns a short qualifier ("main" or "bg")
    /// so the grep'd output is more readable. The full thread state is
    /// recoverable via `log show --info` if needed.
    private static func threadLabel() -> String {
        Thread.isMainThread ? "main" : "bg"
    }

    /// Single point of contact for `info`-level emission. Keeps the
    /// `OSLogMessage` interpolation rules (no `+` concatenation, single
    /// interpolation per call) in one place.
    private static func emitInfo(_ message: String) {
        Logging.bug012.info("\(message, privacy: .public)")
    }

    /// Single point of contact for `notice`-level emission.
    private static func emitNotice(_ message: String) {
        Logging.bug012.notice("\(message, privacy: .public)")
    }
}
