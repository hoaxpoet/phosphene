// PlaybackClockSmoother — a continuous playback position from a coarse playback clock (LFSTEM.1d).
//
// **The defect this exists for.** `MIRPipeline.elapsedSeconds` is the playback clock every
// position-sampled consumer reads. On the local-file path it advances in **100 ms steps** —
// measured on session `2026-08-27T13-24-37Z`: 1,714 steps of exactly 0.100 s and 1,345 steps of
// exactly 0.000, i.e. it does not move at all on 39 % of analysis frames. It is right on
// average (197.4 s of clock over 197 s of playback) and coarse instant to instant.
//
// That was harmless while its only fine-grained consumer did not exist. `instrumentFamilySeries`
// samples it on a 1 s hop, where a 100 ms quantum is invisible. LFSTEM.1's stem series is on a
// **23 ms** grid, so reading it through this clock produced a staircase: stem values held for
// 2–6 analysis frames and then jumped four or more grid frames at once, landing on whatever
// deviation spike happened to be there (observed frame-to-frame jumps up to 6.0 on
// `bassEnergyDev`). Matt's word for it was "twitchy", and it is — the live path it replaced
// computed features from a sliding audio window and was continuous by construction.
//
// **What this does.** Between ticks of the coarse clock, advance the position by real elapsed
// time; on a tick, resync to the authoritative value. The clock stays correct on average, the
// position moves smoothly, and error is bounded by one tick interval.
//
// This is the render-clock/musical-clock family again (BUG-096, BUG-097): the values were never
// wrong, the clock they were read against was.

import Foundation

// MARK: - PlaybackClockSmoother

/// Turns a coarsely-quantised playback clock into a continuous position.
///
/// Pure and clock-injected: `position(rawSeconds:now:)` takes the wall-clock reading rather than
/// calling `CACurrentMediaTime()` itself, so the behaviour is testable without timing races.
public struct PlaybackClockSmoother: Sendable {

    /// Longest stretch that may be dead-reckoned past the last tick.
    ///
    /// Slightly over two observed 100 ms ticks. It bounds the damage when the clock stops for a
    /// reason other than a missed tick — a pause, an ended track, a stalled analysis loop — so a
    /// stopped clock reads as "held" rather than running away into the rest of the track. Error
    /// against a healthy clock is bounded by one tick interval either way.
    public static let maxDeadReckonSeconds: Double = 0.25

    /// The last distinct value the coarse clock reported.
    private var lastTickValue: Double?
    /// Wall-clock time at which that value first appeared.
    private var lastTickWall: Double = 0
    /// Last position handed out, so the result can never go backwards within a track.
    private var lastPosition: Double = 0

    public init() {}

    /// A continuous playback position for `rawSeconds`.
    ///
    /// - Parameters:
    ///   - rawSeconds: the coarse clock's current reading.
    ///   - now: monotonic wall-clock seconds (`CACurrentMediaTime()` at the call site).
    public mutating func position(rawSeconds: Double, now: Double) -> Double {
        // A tick — or a seek, or a new track. Resync; the clock is authoritative when it moves.
        if lastTickValue != rawSeconds {
            lastTickValue = rawSeconds
            lastTickWall = now
            lastPosition = rawSeconds
            return rawSeconds
        }
        // Held: advance by real elapsed time, capped.
        let since = min(max(0, now - lastTickWall), Self.maxDeadReckonSeconds)
        let dead = rawSeconds + since
        // Never rewind inside a held stretch (a non-monotonic `now` would otherwise show up as
        // stems stepping backwards, which reads exactly like the staircase this fixes).
        lastPosition = max(lastPosition, dead)
        return lastPosition
    }

    /// Forget the clock's history. Call on track change, so the first frame of a new track
    /// resyncs instead of dead-reckoning from the previous track's last tick.
    public mutating func reset() {
        lastTickValue = nil
        lastTickWall = 0
        lastPosition = 0
    }
}
