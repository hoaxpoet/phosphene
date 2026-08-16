// CircularPhaseSmootherTests — the ±π seam is the whole point (FTR.19 / D-209).

import Testing
import Foundation
@testable import Renderer

@Suite("CircularPhaseSmoother (FTR.19 / D-209)")
struct CircularPhaseSmootherTests {

    private static func wrap(_ value: Float) -> Float {
        var v = value
        while v > .pi { v -= 2 * .pi }
        while v < -.pi { v += 2 * .pi }
        return v
    }

    /// THE DEFECT THIS TYPE EXISTS FOR. A scalar EMA of the raw sawtooth swings ~2π when the phase
    /// crosses the seam; the circular form must not. Measured in Fractal Tree's shipping hue that
    /// seam produced jumps of up to 180° of hue, ~1.5 times a second.
    @Test("a seam crossing does not produce a jump")
    func seamCrossingIsSmooth() {
        var smoother = CircularPhaseSmoother(alpha: 0.5)
        // Walk across +π → −π in small real steps.
        var phase: Float = 3.0
        var previous = smoother.smooth(phase)
        var worstStep: Float = 0
        for _ in 0..<40 {
            phase = Self.wrap(phase + 0.1)
            let now = smoother.smooth(phase)
            worstStep = Swift.max(worstStep, abs(Self.wrap(now - previous)))
            previous = now
        }
        #expect(worstStep < 0.2, """
            the smoothed phase jumped \\(worstStep) rad crossing the ±π seam. A scalar EMA of the raw
            sawtooth is what produces that, and it is what D-209 forbids.
            """)
    }

    /// Seeded exactly on the first call — no ramp from zero, which at a track change would read as
    /// the colour sweeping in from wherever the previous track left off.
    @Test("the first sample is passed through exactly")
    func seedsExactly() {
        var smoother = CircularPhaseSmoother()
        #expect(abs(Self.wrap(smoother.smooth(2.5) - 2.5)) < 1e-5)
        var other = CircularPhaseSmoother()
        #expect(abs(Self.wrap(other.smooth(-2.9) - (-2.9))) < 1e-5)
    }

    /// It must still FOLLOW a real harmonic change — a smoother that never arrives is a different
    /// defect (DYN.1e shipped a band Matt could not see).
    @Test("it converges on a sustained change")
    func convergesOnRealChange() {
        var smoother = CircularPhaseSmoother(alpha: 0.065)
        _ = smoother.smooth(0)
        var last: Float = 0
        for _ in 0..<200 { last = smoother.smooth(1.5) }
        #expect(abs(Self.wrap(last - 1.5)) < 0.05, """
            after 200 updates at a fixed 1.5 rad the smoothed phase is \\(last) — it is not
            converging, so a real key change would never reach the hue.
            """)
    }

    /// `reset` drops history so a new track does not glide in from the old one's key.
    @Test("reset re-seeds")
    func resetReseeds() {
        var smoother = CircularPhaseSmoother()
        for _ in 0..<50 { _ = smoother.smooth(0) }
        smoother.reset()
        #expect(abs(Self.wrap(smoother.smooth(2.0) - 2.0)) < 1e-5, "reset did not re-seed")
    }
}
