// RosetteStateTests — Unit tests for RosetteState's circular-phase smoother and
// symmetry-order transition (WHIT.1d-2 / WHIT.2a).
//
// Tests exercise the public Swift API only, at 60fps tick granularity — no Metal
// rendering, matching GossamerStateTests' pattern for a per-preset state object.
//
// Invariants verified (WHIT.2a, Matt: "this preset MUST use motion to smoothly
// transition from one pattern to another"):
//   1. Initial state: currentSymmetryN == 5 (Whitney's stated base order), settled.
//   2. A qualifying harmonicFlux spike starts a SMOOTH transition, not an instant jump —
//      one tick in, currentSymmetryN has moved only a little, nowhere near the target.
//   3. The transition is monotonic (5 -> 6 never backtracks) and settles to exactly the
//      target value once transitionDurationSeconds has elapsed.
//   4. reset() (track change) snaps back to the base order with no lingering transition.

import Testing
import Metal
@testable import Presets
import Shared

private enum RosetteStateTestError: Error { case noMetalDevice }

private func fv(harmonicFlux: Float = 0, tonalPhaseFifths: Float = 0, deltaTime: Float = 1.0 / 60.0) -> FeatureVector {
    var f = FeatureVector(time: 0, deltaTime: deltaTime)
    f.harmonicFlux = harmonicFlux
    f.tonalPhaseFifths = tonalPhaseFifths
    return f
}

@Suite("RosetteState symmetry-order transition (WHIT.2a)")
struct RosetteStateTests {

    private func makeState() throws -> RosetteState {
        guard let device = MTLCreateSystemDefaultDevice() else { throw RosetteStateTestError.noMetalDevice }
        guard let state = RosetteState(device: device) else { throw RosetteStateTestError.noMetalDevice }
        return state
    }

    @Test("Initial state is the base symmetry order, settled")
    func initialState() throws {
        let state = try makeState()
        #expect(state.currentSymmetryN == RosetteState.symmetrySequence[0])
    }

    @Test("A qualifying spike starts a smooth transition, not an instant jump")
    func transitionIsGradualNotInstant() throws {
        let state = try makeState()
        let dt: Float = 1.0 / 60.0
        // RosetteState starts with timeSinceLastStep == minHoldSeconds, so the first
        // qualifying spike starts the transition immediately (transitionElapsed resets to
        // 0 within this same tick, so THIS frame reports exactly the base value — the
        // transition's first frame of visible movement is the next tick).
        state.tick(deltaTime: dt, features: fv(harmonicFlux: 1.0, deltaTime: dt))
        let target = RosetteState.symmetrySequence[1]
        let base = RosetteState.symmetrySequence[0]
        #expect(state.currentSymmetryN == base,
                "currentSymmetryN moved before the transition's first elapsed frame — the trigger itself should not jump")

        state.tick(deltaTime: dt, features: fv(harmonicFlux: 0, deltaTime: dt))
        let nAfterSecondFrame = state.currentSymmetryN
        #expect(abs(nAfterSecondFrame - base) > 0,
                "currentSymmetryN did not move at all one frame into a triggered transition")
        #expect(abs(nAfterSecondFrame - target) > abs(target - base) * 0.5,
                "currentSymmetryN=\(nAfterSecondFrame) jumped more than halfway to the target=\(target) in a single 1/60s frame — this should be a multi-second smoothstep, not an instant step")
    }

    @Test("The transition is monotonic and settles exactly at the target after transitionDurationSeconds")
    func transitionMonotonicAndSettles() throws {
        let state = try makeState()
        let dt: Float = 1.0 / 60.0
        let target = RosetteState.symmetrySequence[1]

        state.tick(deltaTime: dt, features: fv(harmonicFlux: 1.0, deltaTime: dt))
        var previous = state.currentSymmetryN
        let totalFrames = Int((RosetteState.transitionDurationSeconds / dt).rounded(.up)) + 5
        for _ in 1..<totalFrames {
            state.tick(deltaTime: dt, features: fv(harmonicFlux: 0, deltaTime: dt))
            let current = state.currentSymmetryN
            #expect(current >= previous - 0.0001,
                    "currentSymmetryN went backwards (\(previous) -> \(current)) mid-transition — the interpolation must be monotonic")
            previous = current
        }
        #expect(previous == target,
                "currentSymmetryN=\(previous) did not settle exactly at target=\(target) after transitionDurationSeconds elapsed")
    }

    @Test("reset() snaps back to the base order with no lingering transition")
    func resetSnapsToBase() throws {
        let state = try makeState()
        let dt: Float = 1.0 / 60.0
        state.tick(deltaTime: dt, features: fv(harmonicFlux: 1.0, deltaTime: dt))
        state.tick(deltaTime: dt, features: fv(harmonicFlux: 0, deltaTime: dt))
        // Mid-transition: currentSymmetryN should be strictly between base and target here.
        #expect(state.currentSymmetryN != RosetteState.symmetrySequence[0])

        state.reset()
        #expect(state.currentSymmetryN == RosetteState.symmetrySequence[0])
        // No lingering animation: one more tick with no spike should not move it.
        state.tick(deltaTime: dt, features: fv(harmonicFlux: 0, deltaTime: dt))
        #expect(state.currentSymmetryN == RosetteState.symmetrySequence[0])
    }
}
