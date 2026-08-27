// PlaybackClockSmootherTests — the gate LFSTEM.1's alignment test could not be.
//
// LFSTEM.1 shipped with a correct series and a correct read: `StemFeatureSeriesTests` proved a
// change at a known second lands at that second, and it still does. What no test covered was the
// CLOCK the series is read against — `MIRPipeline.elapsedSeconds` advances in 100 ms steps on
// the local-file path — so a 23 ms grid came out as a staircase in production and nothing went
// red. The alignment gate tested the map; this tests the hand holding it.
//
// The headline case (`staircase`) reproduces the real measurement: a clock quantised to 100 ms
// read at ~18 Hz, which is what session `2026-08-27T13-24-37Z` recorded.

import Foundation
import Testing
@testable import Shared

@Suite("Playback clock smoothing (LFSTEM.1d)")
struct PlaybackClockSmootherTests {

    /// THE case. A 100 ms-quantised clock sampled at ~18 Hz must still yield a position that
    /// advances on every frame — otherwise a fine-grained series is read as a staircase.
    @Test("A 100 ms-quantised clock still yields a position that advances every frame")
    func staircase_isRemoved() {
        var clock = PlaybackClockSmoother()
        let frameInterval = 1.0 / 18.0          // the measured local-file analysis rate
        var positions: [Double] = []

        // 2 s of playback: the raw clock ticks in 0.1 s steps, frames arrive every ~55 ms.
        for i in 0..<36 {
            let now = Double(i) * frameInterval
            let raw = (now / 0.1).rounded(.down) * 0.1   // quantised exactly as measured
            positions.append(clock.position(rawSeconds: raw, now: now))
        }

        let held = zip(positions, positions.dropFirst()).filter { $1 <= $0 }.count
        #expect(held == 0, """
                \(held) of \(positions.count - 1) frames did not advance — a fine-grained series \
                read on this position still steps. That is the staircase LFSTEM.1d exists to fix.
                """)

        // And the smoothing must not invent motion: the position tracks real time within a tick.
        for (i, p) in positions.enumerated() {
            let realTime = Double(i) * frameInterval
            #expect(abs(p - realTime) <= 0.1 + 1e-9, """
                    position \(p) drifted from real time \(realTime) by more than one tick — \
                    dead reckoning must stay bounded by the clock it is smoothing.
                    """)
        }
    }

    /// A control: with a clock that is ALREADY continuous, smoothing must be a no-op that
    /// returns the clock's own values. Otherwise this helper would be adding error on the
    /// streaming path, which has no quantisation problem.
    @Test("A continuous clock passes through untouched")
    func continuousClock_isUnchanged() {
        var clock = PlaybackClockSmoother()
        for i in 0..<50 {
            let t = Double(i) * (1.0 / 60.0)
            #expect(clock.position(rawSeconds: t, now: t) == t,
                    "a clock that ticks every frame is authoritative on every frame")
        }
    }

    /// A stopped clock — paused, ended, or a stalled analysis loop — must settle rather than
    /// running away into the rest of the track.
    @Test("A stopped clock is capped, not extrapolated forever")
    func stoppedClock_isCapped() {
        var clock = PlaybackClockSmoother()
        _ = clock.position(rawSeconds: 10.0, now: 100.0)
        let afterOneSecond = clock.position(rawSeconds: 10.0, now: 101.0)
        let afterOneMinute = clock.position(rawSeconds: 10.0, now: 160.0)
        #expect(afterOneSecond == 10.0 + PlaybackClockSmoother.maxDeadReckonSeconds)
        #expect(afterOneMinute == afterOneSecond,
                "a clock stopped for a minute must not report a minute of playback")
    }

    /// A tick corrects drift WITHOUT rewinding.
    ///
    /// This case asserted the opposite until LFSTEM.1d's second round: it required a tick to snap
    /// the position back to the raw value, which is precisely the rewind that put stem values a
    /// few frames into the past several times a minute. Dead reckoning legitimately runs tens of
    /// milliseconds past a tick before the tick confirming it arrives; that correction belongs in
    /// the band, not in a jump backwards.
    @Test("A tick corrects drift without rewinding the position")
    func tick_correctsWithoutRewinding() {
        var clock = PlaybackClockSmoother()
        _ = clock.position(rawSeconds: 10.0, now: 100.0)
        let ahead = clock.position(rawSeconds: 10.0, now: 100.2)   // dead-reckoned to 10.2
        let afterTick = clock.position(rawSeconds: 10.1, now: 100.21)
        #expect(afterTick >= ahead,
                "the position went BACKWARDS across a tick — stems re-read a frame they passed")
        #expect(afterTick <= 10.1 + PlaybackClockSmoother.maxDeadReckonSeconds,
                "and it stays inside the band the clock defines")
    }

    /// A discontinuity is not drift: a seek resyncs exactly, in either direction.
    @Test("A seek resyncs exactly rather than being absorbed as drift")
    func seek_resyncsExactly() {
        var clock = PlaybackClockSmoother()
        _ = clock.position(rawSeconds: 10.0, now: 100.0)
        #expect(clock.position(rawSeconds: 3.0, now: 100.3) == 3.0,
                "a backward seek lands on the seek target, not on the band edge")
        #expect(clock.position(rawSeconds: 200.0, now: 100.4) == 200.0,
                "and a forward jump does too")
    }

    /// Track change: the new track's first frame must resync, not dead-reckon from the old one.
    @Test("reset() forgets the previous track's clock")
    func reset_forgetsHistory() {
        var clock = PlaybackClockSmoother()
        _ = clock.position(rawSeconds: 240.0, now: 100.0)
        clock.reset()
        #expect(clock.position(rawSeconds: 0.0, now: 100.5) == 0.0,
                "a new track starts at its own clock, not the previous track's position")
    }

    /// Within one held stretch the position cannot go backwards, or stems step in reverse —
    /// which looks exactly like the staircase this replaces.
    @Test("A non-monotonic wall clock cannot rewind the position")
    func monotonic_withinAHeldStretch() {
        var clock = PlaybackClockSmoother()
        _ = clock.position(rawSeconds: 5.0, now: 200.0)
        let forward = clock.position(rawSeconds: 5.0, now: 200.05)
        let backward = clock.position(rawSeconds: 5.0, now: 200.01)
        #expect(backward == forward, "the position holds rather than rewinding")
    }
}
