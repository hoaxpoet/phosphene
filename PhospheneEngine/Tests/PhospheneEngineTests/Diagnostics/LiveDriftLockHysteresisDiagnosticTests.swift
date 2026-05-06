// LiveDriftLockHysteresisDiagnosticTests — BUG-007 reproducer.
//
// Reproduces the two failure mechanisms observed in the BUG-006.2 session
// capture (2026-05-06T20-11-46Z, Money 7/4 with prepared grid bpm=123.2):
//
//   Mechanism A (oscillation): The sub_bass onset cooldown (~400 ms) mismatches
//   the prepared-grid beat period (487 ms). Roughly 70% of onsets fall outside
//   the ±50 ms driftSearchWindow. After 3 consecutive misses (lockReleaseMisses),
//   lock drops from LOCKED to LOCKING, then briefly re-acquires on the next hit.
//
//   Mechanism B (freeze/plateau): The prepared-cache path installs the raw
//   BeatGrid from the 30-second preview without calling offsetBy(). Once
//   playbackTime exceeds ~30 s, nearestBeat() returns nil for all onsets,
//   consecutiveMisses accumulates without bound, and lock stays LOCKING forever.
//   drift freezes at its last EMA value.
//
// Run with: BUG_007_DIAGNOSIS=1 swift test --filter LiveDriftLockHysteresisDiagnostic
//
// The test_mechanism_B assertion INTENTIONALLY FAILS on the current codebase —
// its failure IS the bug documentation. test_mechanism_A intentionally fails
// too; both are allowed failures whose printed diagnostics are the deliverable.
//
// All tests are gated behind BUG_007_DIAGNOSIS=1 so they do not block CI.

import Foundation
import Testing
@testable import DSP

// MARK: - Helpers

private final class TraceCapture: @unchecked Sendable {
    var entries: [LiveBeatDriftTraceEntry] = []
    var lockHistory: [(time: Double, lockState: LiveBeatDriftTracker.LockState)] = []
}

private func makeMoneySyntheticGrid(
    bpm: Double = 123.2,
    coverageSeconds: Double = 30.0
) -> BeatGrid {
    let period = 60.0 / bpm
    var beats: [Double] = []
    var downbeats: [Double] = []
    var t = 0.14
    while t <= coverageSeconds {
        beats.append(t)
        t += period
    }
    // Add downbeats every 2 beats (as per captured meter=2/X)
    for i in stride(from: 0, to: beats.count, by: 2) {
        downbeats.append(beats[i])
    }
    return BeatGrid(
        beats: beats,
        downbeats: downbeats,
        bpm: bpm,
        beatsPerBar: 2,
        barConfidence: 0.7,
        frameRate: 50.0,
        frameCount: Int(coverageSeconds * 50)
    )
}

// MARK: - Diagnostic Suite

@Suite("LiveDriftLockHysteresisDiagnostic",
       .enabled(if: ProcessInfo.processInfo.environment["BUG_007_DIAGNOSIS"] == "1",
                "Set BUG_007_DIAGNOSIS=1 to run BUG-007 diagnostic tests"))
struct LiveDriftLockHysteresisDiagnosticTests {

    // MARK: - Check 1 / Mechanism B: Prepared grid freeze after 30 s

    /// Replays 50 seconds of sub_bass onsets against an extrapolated grid (offsetBy(0)).
    /// Fix A (BUG-007.2) calls offsetBy(0) in the production prepared-cache install path,
    /// extrapolating beats to a 300-second horizon so nearestBeat() always returns non-nil.
    /// Lock should reach .locked and stay there throughout the 50-second run.
    ///
    /// The raw-grid (pre-fix) behaviour is tested by the unit regression gate
    /// `test_preparedGridExhaustion_withoutOffsetBy_dropsLock` in LiveBeatDriftTrackerTests.
    @Test("Mechanism B: prepared grid freeze after 30-second coverage exhausted")
    func test_mechanismB_preparedGridFreezesAt30s() {
        let rawGrid = makeMoneySyntheticGrid(bpm: 123.2, coverageSeconds: 30.0)
        let grid = rawGrid.offsetBy(0)   // Fix A: extrapolate beats to 300 s horizon

        let tracker = LiveBeatDriftTracker()
        tracker.setGrid(grid)

        let capture = TraceCapture()
        var lockSamples: [(time: Double, lock: Int)] = []
        tracker.diagnosticTrace = { entry in
            capture.entries.append(entry)
        }

        // Simulate 50 seconds at 60 fps with sub_bass onsets every ~400 ms.
        let fps: Double = 60
        let dt = Float(1.0 / fps)
        let durationS: Double = 50
        var onsetAccum: Double = 0
        let onsetIntervalS: Double = 0.400   // 400 ms sub_bass cooldown cadence

        for frame in 0..<Int(durationS * fps) {
            let t = Double(frame) / fps
            onsetAccum += 1.0 / fps
            let isOnset = onsetAccum >= onsetIntervalS
            if isOnset { onsetAccum -= onsetIntervalS }

            let result = tracker.update(subBassOnset: isOnset, playbackTime: t, deltaTime: dt)
            if frame % Int(fps) == 0 || isOnset {
                lockSamples.append((time: t, lock: result.lockState == .locked ? 2 : result.lockState == .locking ? 1 : 0))
            }
        }

        // Print the full trace — this IS the diagnosis artifact.
        print("\n=== BUG-007 Mechanism B: onset trace ===")
        print("t(s) | nearest_beat | instant_drift_ms | prev_drift_ms | new_drift_ms | tight | matched | misses | lock")
        for e in capture.entries {
            let nb = e.nearestBeat.map { String(format: "%.4f", $0) } ?? "nil"
            let id = e.instantDriftMs.map { String(format: "%+.1f", $0) } ?? "nil"
            let lock = e.lockState == .locked ? "LOCKED" : e.lockState == .locking ? "LOCKING" : "UNLOCKED"
            // Use %@ (not %s) — Swift Strings are not C strings; %s causes SIGSEGV.
            let nbPad = nb + String(repeating: " ", count: max(0, 8 - nb.count))
            let idPad = String(repeating: " ", count: max(0, 7 - id.count)) + id
            print(String(format: "%.3f | %@ | %@ | %+7.1f | %+7.1f | %@ | %d | %d | %@",
                e.onsetTime, nbPad, idPad,
                e.prevDriftMs, e.newDriftMs,
                e.isTightMatch ? "Y" : "N",
                e.matchedOnsets, e.consecutiveMisses, lock))
        }

        // Print lock_state evolution at 1-second resolution.
        print("\n=== Lock state over time (1 s resolution) ===")
        print("t(s) | lock (0=unlocked,1=locking,2=locked)")
        for s in lockSamples where s.time == Double(Int(s.time)) {
            print(String(format: "%.0f | %d", s.time, s.lock))
        }

        // Diagnosis invariant: last drift update should be near t=30 s.
        let lastDriftEntry = capture.entries.filter { $0.nearestBeat != nil }.last
        print("\n=== Summary ===")
        print("Total onset events: \(capture.entries.count)")
        print("Onset events with beat found: \(capture.entries.filter { $0.nearestBeat != nil }.count)")
        print("Last drift-update time: \(lastDriftEntry.map { String(format: "%.3f s", $0.onsetTime) } ?? "none")")
        print("Last drift value: \(lastDriftEntry.map { String(format: "%+.3f ms", $0.newDriftMs) } ?? "n/a")")
        let frozenEntries = capture.entries.filter { $0.nearestBeat == nil && $0.onsetTime > 30.0 }
        print("nil-nearest-beat entries after t=30 s: \(frozenEntries.count)")

        // Fix A regression gate: with offsetBy(0) applied, the grid is extrapolated to 300 s.
        // nearestBeat() returns non-nil for all onsets past t=30 s; lock must remain .locked.
        let lockedAt40s = lockSamples.filter { $0.time >= 40.0 && $0.time <= 41.0 }.first?.lock ?? 0
        // swiftlint:disable line_length
        #expect(lockedAt40s == 2, "BUG-007 Mechanism B: lock should stay .locked at t=40 s but prepared grid has no extrapolated beats past t=30 s. Fix: setBeatGrid(cached.beatGrid.offsetBy(0))")
        // swiftlint:enable line_length
    }

    // MARK: - Check 1 / Mechanism A: Lock oscillation from miss-rate mismatch

    /// Replays 30 seconds with the correct prepared grid (offsetBy already applied)
    /// to isolate the oscillation from the finite-horizon freeze.
    /// Shows that even with a correct extrapolated grid, the 400 ms onset cadence
    /// vs 487 ms beat period produces a ~71% miss rate that causes LOCKED→LOCKING
    /// oscillation via the lockReleaseMisses=3 gate.
    @Test("Mechanism A: lock oscillates due to sub_bass cadence vs grid period mismatch")
    func test_mechanismA_lockOscillatesFrom400msVs487msCadence() {
        // Use offsetBy(0) to ensure the grid extends to 300 s — isolates mechanism A.
        let rawGrid = makeMoneySyntheticGrid(bpm: 123.2, coverageSeconds: 30.0)
        let grid = rawGrid.offsetBy(0)   // extrapolate to 300 s horizon

        let tracker = LiveBeatDriftTracker()
        tracker.setGrid(grid)

        let traceCapture = TraceCapture()
        tracker.diagnosticTrace = { entry in traceCapture.entries.append(entry) }

        let fps: Double = 60
        let dt = Float(1.0 / fps)
        var lockHistory: [(time: Double, lock: LiveBeatDriftTracker.LockState)] = []
        var prevLock: LiveBeatDriftTracker.LockState = .unlocked
        var onsetAccum: Double = 0
        let onsetIntervalS: Double = 0.400

        for frame in 0..<Int(60.0 * fps) {
            let t = Double(frame) / fps
            onsetAccum += 1.0 / fps
            let isOnset = onsetAccum >= onsetIntervalS
            if isOnset { onsetAccum -= onsetIntervalS }

            let result = tracker.update(subBassOnset: isOnset, playbackTime: t, deltaTime: dt)
            if result.lockState != prevLock {
                lockHistory.append((time: t, lock: result.lockState))
                prevLock = result.lockState
            }
        }

        let hits = traceCapture.entries.filter { $0.nearestBeat != nil }.count
        let misses = traceCapture.entries.filter { $0.nearestBeat == nil }.count
        let totalOnsets = traceCapture.entries.count
        let missRate = Double(misses) / Double(max(1, totalOnsets))
        let tightMatches = traceCapture.entries.filter { $0.isTightMatch }.count

        print("\n=== BUG-007 Mechanism A: 400ms-vs-487ms mismatch ===")
        print("Total sub_bass onsets in 60 s: \(totalOnsets)")
        print("Onsets with beat found (±50 ms): \(hits)  (\(String(format: "%.0f", (1-missRate)*100))%)")
        print("Onsets with no beat found (miss): \(misses)  (\(String(format: "%.0f", missRate*100))%)")
        print("Tight matches (±30 ms after EMA): \(tightMatches)")

        print("\nLock-state transitions:")
        for entry in lockHistory {
            let name = entry.lock == .locked ? "LOCKED" : entry.lock == .locking ? "LOCKING" : "UNLOCKED"
            print(String(format: "  t=%.2f s → %@", entry.time, name))
        }

        let lockedTransitions = lockHistory.filter { $0.lock == .locked }.count
        let lockingTransitions = lockHistory.filter { $0.lock == .locking }.count
        print("\nLOCKED transitions (lock re-acquired): \(lockedTransitions)")
        print("LOCKING transitions (lock lost):       \(lockingTransitions)")
        print("Oscillation rate ≈ every \(String(format: "%.1f", 60.0 / Double(max(1,lockedTransitions)))) s")

        // Check 2 sensitivity sweep: how does miss rate change with strictMatchWindow?
        print("\n=== Check 2: strictMatchWindow sensitivity (simulated) ===")
        print("(Counts tight matches at various window sizes using the captured trace entries)")
        print("window_ms | tight_matches | tight_pct")
        for windowMs in [20.0, 30.0, 40.0, 50.0, 75.0] {
            let count = traceCapture.entries.filter { entry in
                guard let id = entry.instantDriftMs else { return false }
                // Recompute isTightMatch for this window: |instantDrift − prevDrift| × 0.6 < windowMs/1000
                // i.e., |instantDrift − prevDrift| × 0.6 < window
                let delta = abs(id - entry.prevDriftMs) * 0.6
                return delta < windowMs
            }.count
            let pct = 100.0 * Double(count) / Double(max(1, hits))
            print(String(format: "%-10.0f | %d / %d | %.0f%%", windowMs, count, hits, pct))
        }

        // INTENTIONAL PARTIAL FAILURE: strict contract is that once LOCKED it
        // should not flip to LOCKING under stable input. With the current
        // lockReleaseMisses=3 and 400ms-vs-487ms cadence, it oscillates.
        // This assertion documents the minimum desired behaviour after the fix.
        let oscillations = min(lockedTransitions, lockingTransitions) - 1  // subtract initial transitions
        // swiftlint:disable line_length
        #expect(oscillations <= 2, "BUG-007 Mechanism A: expected <=2 lock oscillations in 60 s on a correctly extrapolated grid. Fix: increase lockReleaseMisses or add lock hysteresis.")
        // swiftlint:enable line_length
    }

    // MARK: - Check 3: Decay path inspection

    /// Verifies that the no-onset decay path does not contribute to the plateau.
    /// For Money's 487ms beat period, decay fires only after 2×487=974 ms silence.
    /// During the Money session, silence gaps are short (~50-100 ms between onset groups),
    /// so decay should not be active. This test confirms decay does not interfere.
    @Test("Check 3: decay path inactive during normal Money beat cadence")
    func test_check3_decayPathDoesNotCauseFreeze() {
        let grid = makeMoneySyntheticGrid(bpm: 123.2, coverageSeconds: 30.0).offsetBy(0)
        let tracker = LiveBeatDriftTracker()
        tracker.setGrid(grid)

        let traceCapture3 = TraceCapture()
        tracker.diagnosticTrace = { entry in traceCapture3.entries.append(entry) }

        let fps: Double = 60
        let dt = Float(1.0 / fps)

        // Drive with onsets every 400 ms for 30 seconds, let drift converge,
        // then confirm the drift is NOT decaying toward 0 between onsets.
        var onsetAccum: Double = 0
        var driftSamples: [(time: Double, driftMs: Double)] = []
        for frame in 0..<Int(30.0 * fps) {
            let t = Double(frame) / fps
            onsetAccum += 1.0 / fps
            let isOnset = onsetAccum >= 0.400
            if isOnset { onsetAccum -= 0.400 }
            let result = tracker.update(subBassOnset: isOnset, playbackTime: t, deltaTime: dt)
            _ = result  // we only care about traceCapture3
            if frame % 60 == 0 {
                driftSamples.append((time: t, driftMs: tracker.currentDriftMs))
            }
        }

        print("\n=== Check 3: drift at 1-second intervals (decay path check) ===")
        print("t(s) | drift_ms")
        for s in driftSamples { print(String(format: "%.0f | %+.3f", s.time, s.driftMs)) }

        // With onsets every 400 ms and Money's 487 ms beat period, the inter-onset
        // gap is 400 ms — well below the 2×487=974 ms decay threshold. So the decay
        // path should not fire. Confirm: drift at t=5..10 s is NOT collapsing to 0.
        let driftAt5s = driftSamples.first(where: { $0.time >= 5.0 })?.driftMs ?? 0
        let driftAt10s = driftSamples.first(where: { $0.time >= 10.0 })?.driftMs ?? 0
        print("\nDrift at t~5 s: \(String(format: "%+.3f", driftAt5s)) ms (should be non-zero if any onset matched)")
        print("Drift at t~10 s: \(String(format: "%+.3f", driftAt10s)) ms")

        // Verify: at least one onset matched in 30 seconds (decay path alone can't cause plateau)
        let anyHit = traceCapture3.entries.contains { $0.nearestBeat != nil }
        #expect(anyHit, "Check 3: at least one onset should find a grid beat in 30 seconds; decay is NOT the cause")
    }
}
