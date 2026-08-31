// TonalAnalyzerTests — TIV computation on synthetic chroma fixtures (D-178).
//
// The TIV representation is only trustworthy if it is (a) stable on sustained
// harmony, (b) reactive at chord changes, (c) silent on atonal/noise input,
// and (d) transposition-invariant in SHAPE with a phase offset equal to the
// transposition interval. These four are the tests below. No audio fixtures —
// pure hand-built chroma vectors, so they run anywhere (fixture-free).

import Testing
import Foundation
@testable import DSP

@Suite("TonalAnalyzer — Tonal Interval Vector")
struct TonalAnalyzerTests {

    /// ~94 Hz MIR cadence (the production hop; 512 samples @ 48 kHz).
    private static let dt: Float = 1.0 / 94.0

    // MARK: - Chroma fixtures (C=0 … B=11)

    /// A major triad as a chroma vector: root, major third, perfect fifth = 1, rest 0.
    private static func majorTriad(root: Int) -> [Float] {
        var c = [Float](repeating: 0, count: 12)
        for interval in [0, 4, 7] { c[(root + interval) % 12] = 1 }
        return c
    }

    /// Run `frames` frames of a constant chroma; return the final Result.
    @discardableResult
    private static func settle(_ a: TonalAnalyzer, _ chroma: [Float], frames: Int) -> TonalAnalyzer.Result {
        var last = TonalAnalyzer.Result.zero
        for _ in 0..<frames { last = a.process(chroma: chroma, deltaTime: dt) }
        return last
    }

    // MARK: - (a) Sustained triad → stable phase, high consonance

    @Test("A held major triad settles to high consonance and a stable fifths phase")
    func heldTriadIsConsonantAndStable() {
        let a = TonalAnalyzer()
        let r1 = Self.settle(a, Self.majorTriad(root: 0), frames: 300)  // C major, ~3.2 s
        #expect(r1.consonance > 0.3, "a triad is tonal — consonance well above the gate floor")

        // Phase is deterministic and does not drift while the chord is held.
        let r2 = a.process(chroma: Self.majorTriad(root: 0), deltaTime: Self.dt)
        #expect(abs(r1.phaseFifths - r2.phaseFifths) < 1e-4, "fifths phase is stable on a held chord")
        #expect(r1.harmonicFlux < 0.05, "no chord change → flux decays to ~0")
    }

    // MARK: - (b) I–IV–V–I → distinct phase plateaus, flux peaks at changes

    @Test("A I–IV–V–I progression gives distinct fifths plateaus, flux peaks at changes, tension departs and resolves")
    func cadenceMovesPhaseAndSpikesFlux() {
        let a = TonalAnalyzer()
        // Establish C as "home": the tension slow-center has a ~20 s τ, so it
        // must settle on the tonic before departures register (otherwise the
        // slow center's cold-start ramp dominates — a real characterization,
        // not a test artifact). ~40 s of C settles it to ~86 %.
        Self.settle(a, Self.majorTriad(root: 0), frames: 3760)

        let chords = [0, 5, 7, 0]  // C, F, G, C  (I–IV–V–I in C)
        let framesPerChord = 200   // ~2.1 s each

        var fifthsPlateaus: [Float] = []
        var fluxPeakCount = 0
        var prevFlux: Float = 0
        var risingFlux = false
        var tensionEndOfChord: [Float] = []

        for chord in chords {
            let chroma = Self.majorTriad(root: chord)
            var lastR = TonalAnalyzer.Result.zero
            for _ in 0..<framesPerChord {
                lastR = a.process(chroma: chroma, deltaTime: Self.dt)
                // Count flux peaks: a rising→falling transition above a clear threshold.
                if lastR.harmonicFlux > 0.02 {
                    if lastR.harmonicFlux > prevFlux { risingFlux = true }
                    else if risingFlux { fluxPeakCount += 1; risingFlux = false }
                }
                prevFlux = lastR.harmonicFlux
            }
            fifthsPlateaus.append(lastR.phaseFifths)
            tensionEndOfChord.append(lastR.tension)
        }

        // Four chords → four settled phase values; the three distinct roots (C,F,G)
        // land on distinct fifths phases, and the return to C matches the opening C.
        #expect(abs(fifthsPlateaus[0] - fifthsPlateaus[3]) < 0.05,
                "I and the returning I land on the same fifths phase")
        #expect(abs(fifthsPlateaus[0] - fifthsPlateaus[1]) > 0.2, "I vs IV are distinct fifths phases")
        #expect(abs(fifthsPlateaus[1] - fifthsPlateaus[2]) > 0.2, "IV vs V are distinct fifths phases")

        // Three chord changes (I→IV→V→I) → 3 flux peaks (±1 tolerance, per the spec).
        #expect(fluxPeakCount >= 2 && fluxPeakCount <= 4,
                "one flux peak per chord change (3), within ±1 — got \(fluxPeakCount)")

        // Tension is a "distance from home" scalar: LOW at the tonic (I),
        // HIGHER when the harmony departs (IV / V — both a fifth from C, so
        // roughly symmetric, not V > IV), and it RESOLVES at the return to I.
        #expect(tensionEndOfChord[1] > tensionEndOfChord[0], "IV departs from the home tonic")
        #expect(tensionEndOfChord[2] > tensionEndOfChord[0], "V departs from the home tonic")
        #expect(tensionEndOfChord[3] < tensionEndOfChord[1], "the final I resolves tension back below IV")
    }

    // MARK: - (c) Atonal / flat chroma → below the gate, no signal

    @Test("A flat chroma (all pitch classes equal) reports ~zero consonance and gates tension/flux off")
    func flatChromaIsGatedToRest() {
        let a = TonalAnalyzer()
        let flat = [Float](repeating: 1, count: 12)  // equal energy in all 12 PCs
        let r = Self.settle(a, flat, frames: 300)
        // A constant chroma has zero energy in every TIV coefficient k≥1 → consonance 0.
        #expect(r.consonance < 0.12, "flat/atonal chroma sits below the gate floor")
        #expect(r.tension < 0.01, "tension gated off when not tonal")
        #expect(r.harmonicFlux < 0.01, "no harmonic motion on flat input")
    }

    @Test("Silence (all-zero chroma) yields the neutral rest Result")
    func silenceIsNeutral() {
        let a = TonalAnalyzer()
        let r = Self.settle(a, [Float](repeating: 0, count: 12), frames: 50)
        #expect(r.consonance < 0.01)
        #expect(r.tension == 0)
        #expect(r.harmonicFlux < 0.01)
    }

    // MARK: - (d) Transposition invariance

    @Test("Transposing the whole progression preserves consonance and shifts the fifths phase by the interval")
    func transpositionShiftsPhaseNotShape() {
        // The same C-major triad, and it transposed up 2 semitones (D major).
        let semitones = 2
        let cMajor = Self.majorTriad(root: 0)
        let dMajor = Self.majorTriad(root: semitones)

        let aC = TonalAnalyzer(); let rC = Self.settle(aC, cMajor, frames: 250)
        let aD = TonalAnalyzer(); let rD = Self.settle(aD, dMajor, frames: 250)

        // Magnitude-derived signals are transposition-invariant.
        #expect(abs(rC.consonance - rD.consonance) < 0.02, "consonance is transposition-invariant")

        // Fifths phase shifts by exactly −2π·5·t/12 (mod 2π): T'(k) = e^{−j2πkt/12}·T(k).
        let expected = -2 * Float.pi * 5 * Float(semitones) / 12
        let actual = rD.phaseFifths - rC.phaseFifths
        #expect(Self.wrappedNear(actual, expected, tol: 0.02),
                "fifths phase offset matches the transposition interval (got \(actual), want \(expected))")
    }

    // MARK: - reset()

    @Test("reset() clears decaying state so a new track starts fresh (no cross-track flux)")
    func resetClearsState() {
        let a = TonalAnalyzer()
        Self.settle(a, Self.majorTriad(root: 0), frames: 200)  // C major
        a.reset()
        // First frame of a new chord after reset: no previous TIV → flux must be ~0.
        let r = a.process(chroma: Self.majorTriad(root: 7), deltaTime: Self.dt)  // G major
        #expect(r.harmonicFlux < 0.01, "reset clears prev-TIV so the first new-track frame has no flux")
    }

    // MARK: - Helpers

    /// True if two angles are within `tol` after wrapping the difference into −π…π.
    private static func wrappedNear(_ a: Float, _ b: Float, tol: Float) -> Bool {
        var d = (a - b).truncatingRemainder(dividingBy: 2 * .pi)
        if d > .pi { d -= 2 * .pi }
        if d < -.pi { d += 2 * .pi }
        return abs(d) < tol
    }
}
