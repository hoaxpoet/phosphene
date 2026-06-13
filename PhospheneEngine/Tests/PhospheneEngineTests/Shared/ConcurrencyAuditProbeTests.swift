// ConcurrencyAuditProbeTests — CLEAN.1.1 instrumentation coverage for the
// BUG-031/032 concurrency-family probe.
//
// These tests validate that the probe *detects* the family's races — in-flight
// overlap and input-ownership clobber in `StemSeparator.separate()` (BUG-031),
// stale/orphaned prep completion and a double `_runPreparation` loop (BUG-032).
// They do NOT fix the underlying defect; the live red→green regression tests
// against the real `StemSeparator` / `SessionManager` land with the CLEAN.1.2
// and CLEAN.1.3 fix increments.
//
// XCTest (not swift-testing) so these run in the serial XCTest phase, isolated
// from the parallel swift-testing tests that also drive the probe through
// production code (`SessionLifecycleChurnTests`, `StemSeparatorTests`, …) — the
// same isolation rationale as `BUG012ConcurrencyTest`.

import XCTest
@testable import Shared

final class ConcurrencyAuditProbeTests: XCTestCase {

    override func setUp() {
        super.setUp()
        ConcurrencyAuditProbe.resetForTesting()
    }

    override func tearDown() {
        ConcurrencyAuditProbe.resetForTesting()
        super.tearDown()
    }

    // MARK: - BUG-031: separate() interleave

    /// Two overlapping `separate()` calls on the shared instance: the probe
    /// records max-in-flight ≥ 2 and an input-ownership clobber — the exact
    /// corruption window where one call's `predict()`/output-read consumes the
    /// other call's input.
    func test_separate_overlappingCalls_detectInterleave() {
        let idA = ConcurrencyAuditProbe.enterSeparate()
        ConcurrencyAuditProbe.recordInputWrite(id: idA)

        // Call B enters before A finishes and writes its own input, clobbering
        // the shared model input buffer A is about to consume.
        let idB = ConcurrencyAuditProbe.enterSeparate()
        ConcurrencyAuditProbe.recordInputWrite(id: idB)

        // A checks ownership before reading its outputs: the buffers now belong
        // to B → corruption detected. B still owns them.
        XCTAssertFalse(
            ConcurrencyAuditProbe.checkInputOwnership(id: idA, stage: "post-predict"),
            "A must observe that its input was clobbered by B"
        )
        XCTAssertTrue(ConcurrencyAuditProbe.checkInputOwnership(id: idB, stage: "post-predict"))

        ConcurrencyAuditProbe.exitSeparate(id: idA, outcome: "exit")
        ConcurrencyAuditProbe.exitSeparate(id: idB, outcome: "exit")

        let snap = ConcurrencyAuditProbe.snapshot()
        XCTAssertEqual(snap.maxSeparateInFlight, 2, "both calls were in flight at once")
        XCTAssertEqual(snap.separateInterleaveCount, 1, "exactly one ownership clobber observed")
        XCTAssertEqual(snap.separateInFlight, 0, "all calls exited")
    }

    /// Serial (non-overlapping) `separate()` calls raise no interleave alarm.
    func test_separate_serialCalls_noInterleave() {
        for _ in 0..<3 {
            let id = ConcurrencyAuditProbe.enterSeparate()
            ConcurrencyAuditProbe.recordInputWrite(id: id)
            XCTAssertTrue(ConcurrencyAuditProbe.checkInputOwnership(id: id, stage: "post-predict"))
            ConcurrencyAuditProbe.exitSeparate(id: id, outcome: "exit")
        }
        let snap = ConcurrencyAuditProbe.snapshot()
        XCTAssertEqual(snap.maxSeparateInFlight, 1)
        XCTAssertEqual(snap.separateInterleaveCount, 0)
    }

    // MARK: - BUG-032: stale prep completion (orphan hijack)

    /// A prep task completing under the same generation it was spawned in is
    /// the normal path — not stale.
    func test_prepCompletion_sameGeneration_notStale() {
        let gen = ConcurrencyAuditProbe.markSessionBoundary("beginPreparation")
        let stale = ConcurrencyAuditProbe.recordPrepCompletion(
            spawnGeneration: gen, cancellationRequested: false
        )
        XCTAssertFalse(stale)
        XCTAssertEqual(ConcurrencyAuditProbe.snapshot().staleCompletionCount, 0)
    }

    /// A new session boundary (endSession/startSession) firing during prepare()
    /// makes the completion stale; with no explicit cancel it is the BUG-032
    /// hijack — it is about to overwrite the newer session's plan/state.
    func test_prepCompletion_afterNewBoundary_isHijack() {
        let gen = ConcurrencyAuditProbe.markSessionBoundary("beginPreparation")
        _ = ConcurrencyAuditProbe.markSessionBoundary("endSession")
        let stale = ConcurrencyAuditProbe.recordPrepCompletion(
            spawnGeneration: gen, cancellationRequested: false
        )
        XCTAssertTrue(stale, "completion of the old generation is stale")
        XCTAssertEqual(
            ConcurrencyAuditProbe.snapshot().staleCompletionCount, 1,
            "a non-cancelled stale completion is a hijack"
        )
    }

    /// A stale completion that *was* explicitly cancelled is expected behaviour,
    /// not a hijack — `cancel()` already tears the task down.
    func test_prepCompletion_staleButCancelled_notCountedAsHijack() {
        let gen = ConcurrencyAuditProbe.markSessionBoundary("beginPreparation")
        _ = ConcurrencyAuditProbe.markSessionBoundary("cancel")
        let stale = ConcurrencyAuditProbe.recordPrepCompletion(
            spawnGeneration: gen, cancellationRequested: true
        )
        XCTAssertTrue(stale)
        XCTAssertEqual(
            ConcurrencyAuditProbe.snapshot().staleCompletionCount, 0,
            "an explicitly-cancelled stale completion is expected, not a hijack"
        )
    }

    // MARK: - BUG-032: endSession orphan + double _runPreparation

    /// `endSession()` leaving a live prep task / status subscription behind is
    /// flagged as an orphan; a clean end is not.
    func test_endSession_withLiveTask_flagsOrphan() {
        ConcurrencyAuditProbe.recordEndSession(hasPrepTask: true, hasStatusSubscription: false)
        XCTAssertEqual(ConcurrencyAuditProbe.snapshot().orphanedEndSessionCount, 1)

        ConcurrencyAuditProbe.recordEndSession(hasPrepTask: false, hasStatusSubscription: false)
        XCTAssertEqual(
            ConcurrencyAuditProbe.snapshot().orphanedEndSessionCount, 1,
            "a clean end adds no orphan"
        )
    }

    /// A second `_runPreparation` loop entering while the first is in flight
    /// (the `resumeFailedNetworkTracks` defect) is detected.
    func test_runPreparation_secondLoop_detected() {
        XCTAssertEqual(ConcurrencyAuditProbe.enterRunPreparation(), 1)
        XCTAssertEqual(ConcurrencyAuditProbe.enterRunPreparation(), 2, "second concurrent loop")

        let snap = ConcurrencyAuditProbe.snapshot()
        XCTAssertEqual(snap.maxRunPreparationInFlight, 2)
        XCTAssertEqual(snap.concurrentRunPreparationCount, 1)

        ConcurrencyAuditProbe.exitRunPreparation()
        ConcurrencyAuditProbe.exitRunPreparation()
        XCTAssertEqual(ConcurrencyAuditProbe.snapshot().runPreparationInFlight, 0)
    }

    // MARK: - Probe machinery

    func test_resetForTesting_clearsAllCounters() {
        _ = ConcurrencyAuditProbe.enterSeparate()
        _ = ConcurrencyAuditProbe.markSessionBoundary("x")
        _ = ConcurrencyAuditProbe.enterRunPreparation()
        ConcurrencyAuditProbe.recordEndSession(hasPrepTask: true, hasStatusSubscription: true)

        ConcurrencyAuditProbe.resetForTesting()

        XCTAssertEqual(
            ConcurrencyAuditProbe.snapshot(),
            ConcurrencyAuditProbe.Snapshot(
                separateInFlight: 0, maxSeparateInFlight: 0, separateInterleaveCount: 0,
                sessionGeneration: 0, staleCompletionCount: 0, orphanedEndSessionCount: 0,
                runPreparationInFlight: 0, maxRunPreparationInFlight: 0,
                concurrentRunPreparationCount: 0
            )
        )
    }

    /// The probe's own state is thread-safe: hammering enter/exit from many
    /// threads never crashes and leaves the in-flight counter back at 0.
    func test_probe_isThreadSafe_underConcurrentEnterExit() {
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "cap.test.concurrent", attributes: .concurrent)
        for _ in 0..<8 {
            group.enter()
            queue.async {
                for _ in 0..<50 {
                    let id = ConcurrencyAuditProbe.enterSeparate()
                    ConcurrencyAuditProbe.recordInputWrite(id: id)
                    _ = ConcurrencyAuditProbe.checkInputOwnership(id: id, stage: "stress")
                    ConcurrencyAuditProbe.exitSeparate(id: id, outcome: "exit")
                }
                group.leave()
            }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 30), .success)
        XCTAssertEqual(ConcurrencyAuditProbe.snapshot().separateInFlight, 0)
    }
}
