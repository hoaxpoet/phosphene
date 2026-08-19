// ArrivalStepTests — the size must HOLD, and each change must land with a sound.
//
// The property under test is not "does it follow the audio". The drifting version this replaces
// followed true loudness at r = +0.863 and Matt still called it random on three consecutive
// reviews. What is asserted here is the SHAPE: long holds, discrete steps, no staircase, no
// flicker at a boundary. Those are exactly the properties a later coefficient tweak can destroy
// while every correlation stays green.
//
// ⚠ THE TIERS ARE RELATIVE TO THE TRACK, so every test here drives a HISTORY and then a change,
// never an absolute value. An earlier version of this file asserted against fixed edges (0.34 /
// 0.62) and passed — and those edges measured badly on real audio, leaving the tree in one tier
// for 130 of 142 seconds because the corrected level lives in 0.38…0.75 on that capture. A test
// that pins a constant it does not need is a test that will defend the wrong thing later.

import Testing
import Foundation
@testable import Renderer

private let dt: Float = 1.0 / 60.0

/// Drive `seconds` of constant input and return the growth value after each frame.
private func drive(_ step: ArrivalStep,
                   level: Float,
                   arrival: Float = 0,
                   seconds: Float) -> [Float] {
    (0..<Int(seconds / dt)).map { _ in
        step.update(level: level, arrival: arrival, deltaTime: dt)
    }
}

/// How many times the eased output reverses direction — the signature of flicker, which a span
/// or a variance both hide.
private func reversals(_ values: [Float]) -> Int {
    var count = 0
    var direction = 0
    for index in 1..<values.count {
        let delta = values[index] - values[index - 1]
        guard abs(delta) > 1e-5 else { continue }
        let sign = delta > 0 ? 1 : -1
        if direction != 0 && sign != direction { count += 1 }
        direction = sign
    }
    return count
}

// MARK: - Holding

/// A STEADY PASSAGE PRODUCES NO MOTION AT ALL. This is the whole point: the drifting version
/// crossed its own median 0.105 times/s on real music with nothing in the audio to explain it.
@Test func arrivalStep_steadyLevel_holdsPerfectlyStill() {
    let step = ArrivalStep()
    _ = drive(step, level: 0.50, seconds: 15)         // warmup, settle, ease
    let held = drive(step, level: 0.50, seconds: 30)  // then half a minute of the same passage
    let span = (held.max() ?? 0) - (held.min() ?? 0)
    #expect(span < 0.001, "a steady level must not move the size at all — span was \(span)")
}

/// ★ THERE IS NO WARM-UP, AND THAT IS THE POINT OF THE RANK.
///
/// This test replaces one that asserted the opposite. The design briefly tracked a running mean
/// and spread of the incoming level, which needed several seconds before a tier meant anything —
/// and the plain EMA behind it read 0.691 against a level of 0.445 on a real capture and never
/// stepped at all. `spectral_section_ratio` is already a per-track rank, so there is nothing to
/// estimate and nothing to seed: a track that opens dense must be able to grow the tree at once.
/// A test asserting a dead opening would now be defending a defect.
@Test func arrivalStep_fromTheFirstFrame_canStep() {
    let step = ArrivalStep()
    let out = drive(step, level: 0.90, arrival: 1.0, seconds: 2.0)
    #expect((out.last ?? 0) > 0.3,
            "a track that opens dense must grow at once, reached \(out.last ?? 0)")
}

/// AND IT HOLDS THROUGH ARRIVALS ONCE IT IS AT THE RIGHT TIER. An arrival is permission to change
/// tier, never a size in its own right — the distinction that separates this from FTR.24, whose
/// continuous accent Matt rejected as *"herky-jerky … looks defective"*.
@Test func arrivalStep_arrivalsAtTheSameTier_doNothing() {
    let step = ArrivalStep()
    _ = drive(step, level: 0.50, seconds: 15)
    let before = step.growth
    for index in 0..<600 {                            // 10 s of arrivals every ~170 ms
        _ = step.update(level: 0.50, arrival: index % 10 == 0 ? 1.0 : 0.0, deltaTime: dt)
    }
    #expect(abs(step.growth - before) < 0.001,
            "arrivals must not resize the tree at a settled tier (\(before) → \(step.growth))")
}

// MARK: - Stepping

/// A STEP UP WAITS FOR THE SOUND. The tier is wanted immediately; committing it is what waits, so
/// the change the eye sees coincides with something the ear just heard.
@Test func arrivalStep_stepUp_waitsForAnArrivalThenCommits() {
    let step = ArrivalStep()
    _ = drive(step, level: 0.30, seconds: 12)         // establish a quiet norm
    let low = step.growth
    // The level now says "bigger", but nothing has landed. Held, under the 3 s timeout.
    let quiet = drive(step, level: 0.70, arrival: 0.0, seconds: 1.5)
    #expect(abs((quiet.last ?? 0) - low) < 0.01,
            "no arrival, no step — moved \(low) → \(quiet.last ?? 0)")
    // Now something lands.
    _ = step.update(level: 0.70, arrival: 0.9, deltaTime: dt)
    let after = drive(step, level: 0.70, seconds: 1.0)
    #expect((after.last ?? 0) > low + 0.2, "the arrival must commit the step, got \(after.last ?? 0)")
}

/// …BUT NOT FOREVER. A section can get fuller without one clean transient, and a tree that
/// refuses to grow is FTR.3d's complaint (*"I expect the tree to grow outward, but it barely
/// moves"*) rebuilt as a deadlock.
@Test func arrivalStep_stepUp_commitsOnTimeoutWithoutAnyArrival() {
    let step = ArrivalStep()
    _ = drive(step, level: 0.30, seconds: 12)
    let low = step.growth
    let out = drive(step, level: 0.70, arrival: 0.0, seconds: 5)
    #expect((out.last ?? 0) > low + 0.2,
            "a sustained want must commit within the timeout, got \(out.last ?? 0)")
}

/// A STEP DOWN IS NOT TRIGGERED BY A TRANSIENT. A thinning arrangement does not announce itself
/// with an onset, so the downward direction commits on dwell alone.
@Test func arrivalStep_stepDown_commitsOnDwell() {
    let step = ArrivalStep()
    _ = drive(step, level: 0.40, seconds: 10)
    _ = drive(step, level: 0.80, arrival: 1.0, seconds: 8)     // climb
    let high = step.growth
    #expect(high > 0.2, "precondition: should have stepped up, got \(high)")
    let out = drive(step, level: 0.20, arrival: 0.0, seconds: 8)
    #expect((out.last ?? 1) < high - 0.2, "a thinned section must step down, got \(out.last ?? 1)")
}

/// NO STAIRCASE. A cooldown floors the gap between commits, so however abrupt the audio is the
/// tree walks between sizes instead of teleporting.
///
/// ⚠ THE FIRST VERSION OF THIS TEST WAS WRONG about its own starting point: it established a norm
/// at a constant level and called the result "tier 0", but a constant level settles at the MIDDLE
/// tier by construction (the mean converges onto it), so the "two-tier jump" was one step and the
/// assertion failed for the right reason. Getting to the bottom tier takes a level BELOW the
/// track's own norm, which is what the drop below does.
@Test func arrivalStep_twoTierJump_walksAndRespectsCooldown() {
    let step = ArrivalStep()
    _ = drive(step, level: 0.50, seconds: 12)                  // norm at 0.50 → middle tier
    _ = drive(step, level: 0.20, arrival: 0.0, seconds: 5)     // below the norm → bottom tier
    #expect(step.growth < 0.1, "precondition: should be at the bottom tier, got \(step.growth)")
    let out = (0..<Int(1.2 / dt)).map { _ in step.update(level: 0.95, arrival: 1.0, deltaTime: dt) }
    #expect((out.last ?? 0) < 0.85, "one tier per cooldown — reached \(out.last ?? 0) inside 1.2 s")
    let later = drive(step, level: 0.95, arrival: 1.0, seconds: 4)
    #expect((later.last ?? 0) > 0.85, "and it must get there, got \(later.last ?? 0)")
}

// MARK: - No flicker

/// ★ A LEVEL SITTING ON A BOUNDARY MUST NOT OSCILLATE, even with arrivals available on every
/// frame. It may step ONCE; a size that walks back and forth is the drift complaint at a higher
/// frequency. This is the test that made `minDwellSeconds` exist — without it the slack alone had
/// to do the whole job and a two-frame touch of the edge could commit.
@Test func arrivalStep_levelOnABoundary_doesNotOscillate() {
    let step = ArrivalStep()
    _ = drive(step, level: 0.50, arrival: 1.0, seconds: 12)
    var values: [Float] = []
    for index in 0..<Int(20 / dt) {
        values.append(step.update(level: 0.50 + (index % 2 == 0 ? 0.03 : -0.03),
                                  arrival: 1.0,
                                  deltaTime: dt))
    }
    #expect(reversals(values) <= 1,
            "boundary jitter must not walk the size back and forth — \(reversals(values)) reversals")
}

/// AND EVERY STEP IS EASED, never a cut: an unbounded jump is what made FTR.24 read as defective
/// (measured 10.7× peak velocity).
@Test func arrivalStep_perFrameChange_isBounded() {
    let step = ArrivalStep()
    _ = drive(step, level: 0.50, seconds: 8)
    var previous = step.growth
    var worst: Float = 0
    for index in 0..<Int(40 / dt) {
        // Alternate demanding passages so it steps repeatedly through the whole range.
        let level: Float = (index / 300) % 2 == 0 ? 0.85 : 0.15
        let value = step.update(level: level, arrival: 1.0, deltaTime: dt)
        worst = max(worst, abs(value - previous))
        previous = value
    }
    // τ 0.25 s at 60 fps: at most ~6.6 % of the remaining distance per frame.
    #expect(worst < 0.08, "no step may jump — worst single-frame change was \(worst)")
    #expect(worst > 0.001, "precondition: it should actually have stepped, worst was \(worst)")
}

/// A TRACK CHANGE STARTS SMALL, so a new track's first arrival grows the tree instead of finding it
/// already full from the previous one.
@Test func arrivalStep_reset_returnsToTheSmallestTier() {
    let step = ArrivalStep()
    _ = drive(step, level: 0.40, seconds: 10)
    _ = drive(step, level: 0.90, arrival: 1.0, seconds: 8)
    #expect(step.growth > 0.2, "precondition: should have grown, got \(step.growth)")
    step.reset()
    #expect(step.growth == 0, "reset must return to the smallest tier, got \(step.growth)")
    // …and the cooldown is re-armed, so the new track's first step cannot land instantly.
    let firstFrames = drive(step, level: 0.90, arrival: 1.0, seconds: 0.2)
    #expect((firstFrames.max() ?? 1) < 0.05,
            "the cooldown must survive a reset, reached \(firstFrames.max() ?? 1)")
}
