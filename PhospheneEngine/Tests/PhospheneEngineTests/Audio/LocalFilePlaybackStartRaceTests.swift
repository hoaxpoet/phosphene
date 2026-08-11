// LocalFilePlaybackStartRaceTests — BUG-078 regression gate.
//
// `start()` tears down any previous instance BEFORE taking the lock (BUG-021,
// so AVFoundation teardown never runs under the provider's NSLock). Two
// concurrent `start()` calls can therefore interleave as:
//
//   thread B: stop()          — snapshot is nil, nothing to tear down
//   thread A: _startLocked()  — adopts engine/player #1, still playing
//   thread B: _startLocked()  — OVERWRITES the fields with engine/player #2
//
// Instance #1 is then orphaned while running: never stopped, never detached,
// its observer never removed. Its last strong reference is the one AVFAudio
// holds inside the pending `scheduleFile` completion block, so the node is
// finally released on its own `CommandQueue` — where `-[AVAudioNode dealloc]`
// → `Stop()` → `dispatch_sync` re-enters the queue it is already running on
// and libdispatch traps the process (25 `.ips` reports, 19 naming
// `concurrentDoubleStart_serializesWithoutDeadlock`).
//
// This gate does not try to catch the trap — that is timing-dependent and
// needs full-suite load. It catches the orphaning, which is deterministic
// enough to fail reliably and is the thing actually being fixed.

import AVFoundation
import Foundation
import Testing

@testable import Audio

// MARK: - Breadcrumb counter

/// Tallies the provider's diagnostic breadcrumbs from the several threads that
/// emit them.
private final class BreadcrumbTally: @unchecked Sendable {
    private let lock = NSLock()
    private var instances = 0
    private var teardowns = 0

    func record(_ event: String) {
        lock.withLock {
            if event == "provider.start INSTANCE" { instances += 1 }
            if event == "provider.teardown ENTER" { teardowns += 1 }
        }
    }

    var counts: (instances: Int, teardowns: Int) {
        lock.withLock { (instances, teardowns) }
    }
}

// MARK: - Fixture

private enum StartRaceFixture {
    /// The real tempo fixture. Long enough that every raced instance still has
    /// a `scheduleFile` command in flight when it is orphaned.
    static func url() -> URL? {
        let testDir = URL(fileURLWithPath: String(#filePath)).deletingLastPathComponent()
        let source = testDir
            .deletingLastPathComponent()  // PhospheneEngineTests/
            .deletingLastPathComponent()  // Tests/
            .appendingPathComponent("Fixtures/tempo/love_rehab.m4a")
        guard FileManager.default.fileExists(atPath: source.path) else {
            Issue.record(Comment(rawValue: "Start-race fixture absent at \(source.path) — run "
                                 + "Scripts/fetch_tempo_fixtures.sh. (No silent skip per CLAUDE.md.)"))
            return nil
        }
        return source
    }
}

// MARK: - Suite

/// Serialized for the same reason as `SessionLifecycleChurnTests`: real
/// AVAudioEngine instances and raw threads.
@Suite("LocalFilePlaybackProvider start race (BUG-078)", .serialized)
struct LocalFilePlaybackStartRaceTests {

    @Test func concurrentStart_neverOrphansARunningInstance() throws {
        guard #available(macOS 14.2, *) else { return }
        guard let url = StartRaceFixture.url() else { return }

        let tally = BreadcrumbTally()
        let provider = LocalFilePlaybackProvider(url: url)
        provider.onDiagnosticEvent = { tally.record($0) }

        for _ in 0..<24 {
            let both = DispatchSemaphore(value: 0)
            for _ in 0..<2 {
                Thread.detachNewThread {
                    // A racing start may legitimately throw (device mid-
                    // reconfiguration); orphaning is the defect under test.
                    try? provider.start()
                    both.signal()
                }
            }
            both.wait()
            both.wait()
        }
        provider.stop()

        let (instances, teardowns) = tally.counts
        #expect(instances > 0, "no instance was ever started — the race never ran")
        let orphans = instances - teardowns
        let message = "\(instances) engine/player instances adopted, \(teardowns) torn down: "
            + "\(orphans) were overwritten while still running. Each orphan leaks an "
            + "AVAudioEngine and can trap the process when its final release lands on the "
            + "node's own CommandQueue (BUG-078)."
        #expect(teardowns == instances, Comment(rawValue: message))
    }

    /// **BUG078.3 — the second route to the same trap, which the gate above cannot see.**
    ///
    /// The orphan gate above stayed GREEN while the process still trapped ~20 % of the
    /// time (measured 2026-08-10, 4/20 on a targeted filter). That is the useful fact:
    /// every instance *was* being torn down, so the surviving failure was never an
    /// orphaned instance. It was a command armed on a correctly-torn-down one.
    ///
    /// The reschedule path used to check `playerNode === player` under `lock`, release
    /// it, and only then call `scheduleFile`. A `stop()` landing in that window nils the
    /// fields and runs `player.stop()`, so the command was armed on a node the provider
    /// had already released — and AVFAudio's own `AVAEBlock` retains the node inside
    /// that queued command, making it the last strong reference. Its destruction on the
    /// node's `CommandQueue` then ran `-[AVAudioNode dealloc]` there, whose `Stop()`
    /// `dispatch_sync`s into the queue it is already on. libdispatch traps.
    ///
    /// Instrumented proof of the window (temporary probe, 14 runs): **every run that
    /// recorded a stale schedule crashed (8/8); no clean run recorded one (0/4).**
    ///
    /// `_scheduleFileLoopLocked` now performs the identity check and the re-arm in one
    /// critical section.
    ///
    /// **What this test is worth, stated honestly: it does NOT reproduce the trap.**
    /// Measured against the faithful pre-fix ordering it passed **0 traps in 6 runs**
    /// (and an earlier stop-vs-start shape passed 5/5), because the crash needs the
    /// accumulated load of the full churn suite — the same conclusion the orphan gate
    /// above reached for the first race. It asserts only that the guard **fired**, i.e.
    /// that the check-and-re-arm window is genuinely being entered; a green run here is
    /// evidence the path is exercised, not evidence the race is closed.
    ///
    /// The load-bearing evidence for the fix is the measured before/after on the real
    /// reproducer, `SessionLifecycleChurnTests.concurrentDoubleStart_…` under
    /// `swift test --filter concurrentDoubleStart`: **10 crashes in 14 runs before,
    /// 0 in 30 after.** Re-run that, not this, when judging a change to this path.
    @Test func rescheduleRacingTeardown_neverArmsACommandOnAReleasedNode() throws {
        guard #available(macOS 14.2, *) else { return }
        guard let url = StartRaceFixture.url() else { return }

        let provider = LocalFilePlaybackProvider(url: url)
        // Racing double-`start()`, the shape that actually reproduces. A stop-vs-start
        // churn was tried first and does NOT: 5/5 green against the pre-fix ordering,
        // because the collision needs two `_startLocked()` calls swapping `playerNode`
        // while a reschedule is already in flight. `onFileEnded` stays nil so the LF.1
        // loop keeps re-arming underneath the swap.
        for _ in 0..<48 {
            let both = DispatchSemaphore(value: 0)
            for _ in 0..<2 {
                Thread.detachNewThread {
                    try? provider.start()   // may legitimately throw mid-reconfiguration
                    both.signal()
                }
            }
            both.wait()
            both.wait()
        }
        provider.stop()

        let bailouts = provider.staleRescheduleBailoutCount()
        #expect(bailouts > 0, """
            The reschedule guard never fired across 40 stop/start rounds, so this test did \
            not exercise the check-and-re-arm window it exists to protect. Treat a green \
            result here as unproven, not as evidence the race is closed — tighten the \
            churn until the guard trips.
            """)
    }
}
