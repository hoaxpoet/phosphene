// SessionReadyWait — deterministic-but-bounded readiness wait for SessionManager
// tests (TESTFLAKE.1).
//
// The prior helpers polled `manager.state` against a wall-clock deadline
// (`Date() < deadline`), which starves under parallel-suite load: the deadline was
// widened 3 s → 15 s → 30 s and still flaked once the Ricercar FL.10 render tests
// added GPU/CPU contention. Awaiting the real background task
// (`manager.sessionPreparationTask.value`) is deterministic — it resolves exactly
// when prep completes, regardless of wall-clock — but a BARE await has no upper
// bound, so under pathological contention (e.g. two full test batteries at once) a
// starved or genuinely-deadlocked prep would HANG the suite forever. The guidance is
// explicit: don't convert a slip-class flake into a hang-class one.
//
// So: await the task, RACED against a generous hang-cap. Normal + parallel load
// completes far inside the cap (the whole engine suite runs in ~215 s; a single prep
// is quick), so this never flakes on a slip. Only a genuine hang / pathological
// starvation trips the cap — and then it FAILS loudly with a clear message instead
// of stalling CI.

import Foundation
import Testing
@testable import Session

/// Await `manager`'s background preparation deterministically, bounded by a hang-cap.
///
/// Returns as soon as `sessionPreparationTask` completes (→ `.ready`); records a test
/// Issue and returns if the cap elapses first (a genuine hang, not a slip). No-op when
/// no prep is in flight (a synchronous path already set `.ready`).
@MainActor
func awaitSessionReady(_ manager: SessionManager, hangCapSeconds: Double = 120) async {
    guard let task = manager.sessionPreparationTask else { return }
    let timedOut = await withTaskGroup(of: Bool.self) { group in
        group.addTask { await task.value; return false }
        group.addTask {
            try? await Task.sleep(nanoseconds: UInt64(hangCapSeconds * 1_000_000_000))
            return true
        }
        let first = await group.next() ?? false
        group.cancelAll()   // cancels our racer only — never the real prep task
        return first
    }
    if timedOut {
        Issue.record(
            "SessionManager preparation did not complete within \(hangCapSeconds)s — a genuine hang/deadlock, not a parallel-load slip (TESTFLAKE.1).")
    }
}
