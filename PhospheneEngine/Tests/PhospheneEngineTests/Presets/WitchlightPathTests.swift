// WitchlightPathTests — the pen, tested without a GPU.
//
// `WitchlightPath` is the whole concept: if the path is wrong the preset is wrong no matter
// how the beads are shaded. These tests drive it against synthetic driver inputs (where the
// EXPECTED geometry is known analytically) and against the real fixtures (where the
// expected numbers come from WITCHLIGHT_DESIGN §2's measurement table).
//
// Synthetic input is legitimate HERE and only here: FA #27 bans synthetic audio for
// diagnosing pipeline behaviour, and every claim about how Witchlight responds to MUSIC is
// measured on the real fixtures below. These first cases are testing a kinematic model
// against its own definition — "a constant harmonic input must produce a straight stroke"
// is a statement about the integrator, not about music.

import Testing
import Foundation
@testable import Renderer
@testable import Shared

// MARK: - WitchlightPathTests

@Suite("Witchlight path generator")
struct WitchlightPathTests {

    private static let dt: Float = 1.0 / 60.0

    /// Drive the path with a constant-rate harmonic phase for `seconds`.
    private static func drive(
        _ path: WitchlightPath, seconds: Float, phaseRate: Float,
        arousal: Float = 0, bassDev: Float = 0, barHz: Float = 0
    ) {
        let frames = Int(seconds / dt)
        for i in 0..<frames {
            var f = FeatureVector()
            f.deltaTime = dt
            f.time = Float(i) * dt
            f.bass = 0.3; f.mid = 0.3; f.treble = 0.2       // not silent
            f.arousal = arousal
            f.bassDev = bassDev
            f.tonalPhaseFifths = wrap(Float(i) * dt * phaseRate)
            if barHz > 0 { f.barPhase01 = (Float(i) * dt * barHz).truncatingRemainder(dividingBy: 1) }
            var s = StemFeatures()
            s.drumsEnergy = 0.3; s.bassEnergy = 0.3; s.otherEnergy = 0.2; s.vocalsEnergy = 0.1
            path.advance(deltaTime: dt, features: f, stems: s)
        }
    }

    /// Drive that lets a tonal home establish, then YANKS the phase to the far side of
    /// the circle and holds it there.
    ///
    /// `drive(phaseRate:)` no longer produces an extreme steering demand under
    /// `.curvatureDeviation`: that model reads the excursion from the track's tonal home,
    /// and a steadily-rotating phase is chased by the home, so the excursion settles small.
    /// Testing the Dubins bound needs a driver that actually maxes the excursion out.
    private static func driveHeldOffHome(_ path: WitchlightPath, settle: Float, hold: Float) {
        let settleFrames = Int(settle / dt), holdFrames = Int(hold / dt)
        func step(_ index: Int, _ phase: Float) {
            var f = FeatureVector()
            f.deltaTime = dt
            f.time = Float(index) * dt
            f.bass = 0.3; f.mid = 0.3; f.treble = 0.2       // not silent
            f.tonalPhaseFifths = phase
            var stems = StemFeatures()
            stems.drumsEnergy = 0.3; stems.bassEnergy = 0.3
            stems.otherEnergy = 0.2; stems.vocalsEnergy = 0.1
            path.advance(deltaTime: dt, features: f, stems: stems)
        }
        for i in 0..<settleFrames { step(i, 0) }                       // home settles at 0
        for i in 0..<holdFrames { step(settleFrames + i, .pi * 0.98) } // ~antipodal excursion
    }

    private static func wrap(_ a: Float) -> Float {
        var x = a
        while x > .pi { x -= 2 * .pi }
        while x < -.pi { x += 2 * .pi }
        return x
    }

    /// Mean absolute discrete curvature (turn angle per vertex) over a bead polyline.
    private static func curvature(_ beads: [WitchlightBead]) -> [Float] {
        guard beads.count >= 3 else { return [] }
        var out: [Float] = []
        for i in 1..<(beads.count - 1) {
            let ax = beads[i].posX - beads[i - 1].posX, ay = beads[i].posY - beads[i - 1].posY
            let bx = beads[i + 1].posX - beads[i].posX, by = beads[i + 1].posY - beads[i].posY
            let la = (ax * ax + ay * ay).squareRoot(), lb = (bx * bx + by * by).squareRoot()
            guard la > 1e-7, lb > 1e-7 else { continue }
            out.append(abs(atan2(ax * by - ay * bx, ax * bx + ay * by)))
        }
        return out
    }

    private static func variance(_ values: [Float]) -> Float {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Float(values.count)
        return values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Float(values.count)
    }

    // MARK: - Kinematics

    @Test("a stationary harmony draws a straight stroke — the pen advances, nothing turns it")
    func stationaryHarmonyDrawsStraightLine() {
        let path = WitchlightPath()
        let seconds: Float = 10
        Self.drive(path, seconds: seconds, phaseRate: 0)
        // Expressed against the tuning, not a literal. The old `> 300` encoded the shipped
        // 34 Hz emission rate; WL.2-e solved that to 3.1 Hz (beads at 34 Hz sat 0.15 % of
        // frame height apart and merged into a smear), and a hard-coded count made a
        // deliberate geometry change look like a regression.
        let expected = Int(seconds * WitchlightTuning().emissionHz)
        #expect(path.beads.count >= expected * 3 / 4,
                """
                emitted \(path.beads.count) beads in \(seconds) s, expected about \(expected) \
                at \(WitchlightTuning().emissionHz) Hz — the pen stopped emitting
                """)
        // Heading never changed, so every bead is collinear with the pen's initial direction.
        #expect(path.headingTravel < 0.02,
                "a constant harmonic input turned the pen \(path.headingTravel) rad — it should not turn at all")
        let spans = Self.curvature(path.beads)
        let worst = spans.max() ?? 0
        #expect(worst < 0.02, "the stroke is not straight (max vertex turn \(worst) rad)")
    }

    @Test("a steadily moving harmony draws an open, curving stroke")
    func movingHarmonyDrawsOpenStroke() {
        let path = WitchlightPath()
        // 0.15 rad/s of harmonic drift ≈ half a turn of heading over 20 s: one big open arc.
        // (A faster monotone driver loops the pen right back past its own start, which is a
        // legitimate closed figure but not what "open stroke" is asserting.)
        Self.drive(path, seconds: 20, phaseRate: 0.15)
        // The pen must actually turn — this is the whole divergence axis (D-121).
        #expect(path.headingTravel > 1.0,
                "the harmonic steer barely moved the pen (\(path.headingTravel) rad over 20 s)")
        // …and it must turn ONE way under a monotone driver, i.e. an open arc, not a scribble.
        #expect(path.headingMonotonicity > 0.85,
                "a monotone harmonic drift produced a reversing path (monotonicity \(path.headingMonotonicity))")
        // Start and end are far apart: an OPEN stroke, not a closed loop back on itself.
        let first = path.beads[0]
        let last = path.beads[path.beads.count - 1]
        let dx = last.posX - first.posX, dy = last.posY - first.posY
        #expect((dx * dx + dy * dy).squareRoot() > 0.3, "the stroke closed back onto its own start")
    }

    @Test("the turn rate is clamped so no arc is tighter than the minimum radius (Dubins bound)")
    func turnRateIsClampedToTheMinimumRadius() {
        let path = WitchlightPath()
        // An excursion held near-antipodal to the tonal home: the largest steering demand
        // `.curvatureDeviation` can be given. Without the bound this is anti-reference `10`.
        Self.driveHeldOffHome(path, settle: 12, hold: 0)
        // Snapshot AFTER the home has settled, then measure only the first 2 s of the
        // excursion. The window has to be short against the home's own τ (≈ 8 s): a
        // deviation cannot be *held*, because `home` chases it — that transience is the
        // model, not a limitation of it, and a long window just measures the decay.
        let travelBeforeExcursion = path.headingTravel
        Self.driveHeldOffHome(path, settle: 0, hold: 2)
        let excursionTravel = path.headingTravel - travelBeforeExcursion
        let tuning = WitchlightTuning()
        // ω_max = v / R_min; v varies ±25 % with arousal, so allow the upper speed bound.
        let maxOmega = tuning.baseSpeed * (1 + tuning.speedModDepth) / tuning.minTurnRadius
        let ceiling = maxOmega * 2.0 * 1.05            // 2 s of excursion, 5 % slack
        #expect(excursionTravel <= ceiling, """
            the pen turned \(excursionTravel) rad in the 2 s excursion, above the \(ceiling) rad \
            the bounded-curvature clamp permits — the ball-of-yarn guard is not holding.
            """)
        // The clamp is deliberately NOT asserted to engage. Under `.curvatureDeviation` it is
        // inert BY CONSTRUCTION: `curvatureGain × π ≈ ω_max`, so the driver's own ±π bound
        // maps exactly onto the permitted curvature and the demand never exceeds it. The
        // ball-of-yarn floor is held by the gain calibration, not by saturation. (Demanding
        // frequent clamping was the superseded `.turnRate` model's signature — it saturated
        // on 30–78 % of frames across the §2 captures. That was the pathology, not the
        // requirement; see the D-209 amendment.)
        //
        // NO lower bound is asserted, deliberately. The obvious companion assertion — "an
        // extreme excursion should drive the pen NEAR ω_max, proving `curvatureGain` is still
        // calibrated" — has no defensible threshold, because two smoothing stages stand
        // between the raw phase and the steer: φ̄ is a τ ≈ 1.5 s EMA, so it never reaches ±π
        // quickly, and `home` (τ ≈ 8 s) starts chasing immediately. The peak deviation a real
        // driver can produce is therefore well under π and depends on both constants. Picking
        // a number here would mean tuning a threshold until it passed, which is worse than
        // leaving the property untested and saying so. Establishing the real peak-excursion
        // distribution across the §2 captures is the measurement that would earn this
        // assertion; until then the Dubins bound above is what this test guarantees.
        _ = tuning.curvatureGain
    }

    // MARK: - Relaxation

    @Test("the relaxation pass reduces curvature variance without collapsing the stroke")
    func relaxationReducesCurvatureVarianceWithoutCollapse() {
        var smoothTuning = WitchlightTuning()
        var noRelaxTuning = WitchlightTuning()
        noRelaxTuning.relaxLambda = 0
        smoothTuning.relaxLambda = WitchlightTuning().relaxLambda

        let relaxed = WitchlightPath(tuning: smoothTuning)
        let raw = WitchlightPath(tuning: noRelaxTuning)
        // A fast-reversing driver is what puts kinks in the polyline for relaxation to remove.
        for path in [relaxed, raw] { Self.drive(path, seconds: 20, phaseRate: 9.0) }

        let relaxedVariance = Self.variance(Self.curvature(relaxed.beads))
        let rawVariance = Self.variance(Self.curvature(raw.beads))
        #expect(relaxedVariance < rawVariance, """
            relaxation did not reduce curvature variance (\(rawVariance) → \(relaxedVariance)); \
            the calligraphic-stroke mechanism is inert.
            """)

        // …and it must not have flattened the figure. Laplacian smoothing SHRINKS, and a
        // per-frame λ of 0.30 collapsed a 2-circle heading sweep into a straight line during
        // WL.2 — this is the guard for that regression class.
        let relaxedExtent = Self.extent(relaxed.beads)
        let rawExtent = Self.extent(raw.beads)
        #expect(relaxedExtent > rawExtent * 0.55, """
            relaxation shrank the figure from \(rawExtent) to \(relaxedExtent) — Laplacian collapse. \
            `relaxLambda` is a PER-SECOND rate; a per-frame value of this size flattens the stroke.
            """)
    }

    /// RMS radius of the bead cloud about its own centroid.
    private static func extent(_ beads: [WitchlightBead]) -> Float {
        guard !beads.isEmpty else { return 0 }
        let n = Float(beads.count)
        let cx = beads.reduce(0) { $0 + $1.posX } / n
        let cy = beads.reduce(0) { $0 + $1.posY } / n
        let sum = beads.reduce(Float(0)) {
            let dx = $1.posX - cx, dy = $1.posY - cy
            return $0 + dx * dx + dy * dy
        }
        return (sum / n).squareRoot()
    }

    // MARK: - Events

    @Test("a bar downbeat sets exactly one bead per bar, permanently")
    func downbeatPromotesOneBeadPerBar() {
        let path = WitchlightPath()
        Self.drive(path, seconds: 20, phaseRate: 0.4, barHz: 0.5)   // 10 bars in 20 s
        #expect(path.promotionCount >= 8 && path.promotionCount <= 12,
                "expected ~10 promoted beads over 10 bars, got \(path.promotionCount)")
        let promoted = path.beads.filter { $0.promoted > 0.5 }
        #expect(!promoted.isEmpty, "no promoted bead survived in the trail")
    }

    @Test("the head flare honours its refractory interval (WITCHLIGHT_DESIGN §5)")
    func flareHonoursRefractoryInterval() {
        let path = WitchlightPath()
        // A continuously-firing driver: the ONLY thing limiting the rate is the refractory.
        Self.drive(path, seconds: 10, phaseRate: 0.4, bassDev: 1.5)
        let tuning = WitchlightTuning()
        let ceiling = Int(10.0 / tuning.flareRefractory) + 1
        #expect(path.flareCount <= ceiling, """
            \(path.flareCount) flares in 10 s exceeds the \(ceiling) the \
            \(tuning.flareRefractory) s hard refractory permits — the §5 re-fire budget is not enforced.
            """)
        #expect(path.flareCount >= 5, "the flare never fired on a driver far above its trigger")
        #expect(path.flareIntensity <= tuning.flareCeiling + 1e-4, "flare amplitude exceeded its ceiling")
    }

    @Test("silence keeps the pen moving with zero turn rate (D-037)")
    func silenceLaysAStraightStroke() {
        let path = WitchlightPath()
        for i in 0..<600 {
            var f = FeatureVector()
            f.deltaTime = Self.dt
            f.time = Float(i) * Self.dt
            f.tonalPhaseFifths = Self.wrap(Float(i) * Self.dt * 8.0)   // a live driver…
            path.advance(deltaTime: Self.dt, features: f, stems: StemFeatures())  // …but no energy
        }
        let expectedAtSilence = Int(600 * Self.dt * WitchlightTuning().emissionHz)
        #expect(path.beads.count >= expectedAtSilence * 3 / 4,
                """
                emitted \(path.beads.count) beads at silence, expected about \
                \(expectedAtSilence) — the pen stopped emitting and the trail would freeze
                """)
        #expect(path.headingTravel < 0.02,
                "the pen turned at silence (\(path.headingTravel) rad); §3.6 says θ̇ = 0 with nothing to say")
    }

    @Test("reset clears the pen, the trail and every envelope (track-change contract)")
    func resetClearsEverything() {
        let path = WitchlightPath()
        Self.drive(path, seconds: 10, phaseRate: 3.0, arousal: 0.5, bassDev: 1.2, barHz: 0.5)
        #expect(!path.beads.isEmpty)
        path.reset()
        #expect(path.beads.isEmpty, "beads survived reset — the previous track's drawing would persist")
        #expect(path.heading == 0 && path.turnCount == 0 && path.promotionCount == 0 && path.flareCount == 0)
        #expect(path.flareIntensity == 0)
        #expect(path.trailWindow == WitchlightTuning().trailSeconds, "the contracted window survived reset")
    }

    // MARK: - Against the real fixtures

    @Test("the smoothed harmonic phase travels the distance WITCHLIGHT_DESIGN §2.3 measured",
          arguments: WitchlightFixtureDrive.tracks)
    func phaseTravelMatchesTheDesignMeasurement(track: String) throws {
        // §2.3's table: total wrapped path over 30 s at τ = 1.5 s is 2.1 / 1.7 / 15.4 circles
        // for so_what / there_there / love_rehab. Reproducing it here proves the pen is being
        // steered by the SAME smoothed quantity the design was written against — the check
        // that caught a stray second smoothing stage cutting the travel by 2.5×.
        let expected: [String: Float] = ["so_what": 2.1, "there_there": 1.7, "love_rehab": 15.4]
        let drive = try WitchlightFixtureDrive.load(track)
        let path = WitchlightPath()
        WitchlightFixtureDrive.run(path, over: drive)

        let circles = path.phaseTravel / (2 * .pi)
        let target = try #require(expected[track])
        print(String(format: "[witchlight-path] %@: phase %.2f circles (design %.1f) · clamp %.1f %% · monotonicity %.2f",
                     track, circles, target, path.clampedFraction * 100, path.headingMonotonicity))
        #expect(circles > target * 0.7 && circles < target * 1.4, """
            \(track): the smoothed phase travelled \(circles) circles over 30 s; \
            WITCHLIGHT_DESIGN §2.3 measured \(target). A large gap means the pen is not reading \
            the driver the design was written against.
            """)
    }

    @Test("the figure reverses rather than spiralling, on all three fixtures",
          arguments: WitchlightFixtureDrive.tracks)
    func figureReversesRatherThanSpiralling(track: String) throws {
        // §3.1(b): if a capture sits at the clamp AND turns one way the whole time, the figure
        // degenerates to a circle. Clamping is fine; clamping monotonically is not.
        let drive = try WitchlightFixtureDrive.load(track)
        let path = WitchlightPath()
        WitchlightFixtureDrive.run(path, over: drive)
        // The assertion is the CONJUNCTION this test's own comment names, not monotonicity
        // alone. Under `.curvatureDeviation` a high-monotonicity figure is expected and
        // wanted: sitting in the tonal home draws a straight run and leaving it bends one
        // way, which is the "clean shepherd's crook" the WL.3 spike reported as its success
        // case. Monotonicity alone would fail that shape. What is degenerate is turning one
        // way *while saturated* — a minimum-radius circle — so both have to hold at once.
        let saturated = path.clampedFraction > 0.5
        let spiralling = path.headingMonotonicity > 0.9
        #expect(!(saturated && spiralling), """
            \(track): heading monotonicity \(path.headingMonotonicity) AT a clamp fraction of \
            \(path.clampedFraction) — the pen is pinned at the turn-rate bound and turning one \
            way, so the figure has degenerated to a minimum-radius circle. §3.1(b): lower the \
            steer gain; do NOT raise ω_max, which hides it.
            """)
        // And the pen must still be drawing something: a figure needs real heading travel.
        #expect(path.headingTravel > 1.0,
                "\(track): the pen barely turned (\(path.headingTravel) rad) — no figure at all")
    }
}
