// DensitySmoothingRateInvarianceTests — DYN.4: a time constant must mean seconds.
//
// THE DEFECT THIS GATES. Every density follower was an EMA with a constant per-FRAME alpha,
// so its real time constant was `1 / (alpha * fps)` — a number that moves with the analysis
// rate. The constants were calibrated at 43.07 Hz (44.1 kHz / 1024, the offline hop) and the
// live pipeline runs at **9.9 Hz**, measured on Matt's session `2026-08-10T01-29-10Z`:
//
//     leg      documented   actually live (9.9 Hz)
//     section    τ 20 s       87 s
//     normal     τ 45 s       194 s
//
// That is not a subtle difference in feel. `LoudnessProfile.measure` builds the density
// quantiles from a τ20 s-smoothed series and its header claimed it "mirrors the live path
// frame for frame" — true only while both ran at 43 Hz. Ranking a τ87 s signal against a
// τ20 s distribution compresses every result toward the middle: live,
// `spectral_section_ratio` spanned **0.534…0.614** of its 0…2 range and Fractal Tree's
// canopy used 0.00…0.31 of its own, which is Matt's *"the entire suite of movement does not
// feel strongly tied to the music."* Offline at 43 Hz the same audio spans the full range.
//
// The class of bug is invisible: nothing about it is wrong on any single frame, no test that
// runs at one rate can see it, and the failure only appears when two components sampling at
// different rates have to agree. So it is gated on the property itself — the SAME signal,
// over the SAME wall-clock seconds, at two DIFFERENT rates, must smooth to the same
// trajectory.
//
// FA #27 bars synthetic audio for diagnosing musical behaviour. This asserts an arithmetic
// property of a follower, not a musical one, so a deterministic drive is the right tool —
// a real recording would make the test slower and its failure harder to read.

import Testing
import Foundation
@testable import DSP
@testable import Shared

@Suite("Density smoothing is rate-invariant (DYN.4)")
struct DensitySmoothingRateInvarianceTests {

    private static let fftSize = 1024
    private static let sampleRate: Float = 44100

    /// A deterministic spectrum whose high-frequency share swings on a ~12 s period —
    /// slow enough that a τ20 s leg is genuinely exercised, not just averaged flat.
    private static func magnitudes(atSeconds t: Float) -> [Float] {
        let tilt = 0.5 + 0.35 * sin(t * (2 * .pi / 12))
        let count = fftSize / 2
        return (0..<count).map { bin in
            let hf = Float(bin) / Float(count)
            return (1 - hf) * (1 - tilt) + hf * tilt + 0.05
        }
    }

    private struct Track {
        var section: [Float] = []
        var normal: [Float] = []
        var ratio: [Float] = []
        // DYN.5 — the spectral-feature followers, on the same wall-clock grid.
        var centroid: [Float] = []
        var flux: [Float] = []
    }

    /// Run the analyzer for `seconds` at `fps`, sampling every whole second so two runs at
    /// different rates are compared on the same wall-clock grid.
    private static func run(fps: Float, seconds: Float, profile: LoudnessProfile?) -> Track {
        let analyzer = SpectralAnalyzer(binCount: fftSize / 2,
                                        sampleRate: sampleRate, fftSize: fftSize)
        analyzer.setLoudnessProfile(profile)
        let deltaTime = 1 / fps
        var track = Track()
        var nextSample: Float = 1
        var t: Float = 0
        while t < seconds {
            let result = analyzer.process(magnitudes: magnitudes(atSeconds: t),
                                          deltaTime: deltaTime)
            t += deltaTime
            if t >= nextSample {
                track.section.append(analyzer.sectionDensity)
                track.normal.append(analyzer.densityNormal)
                track.ratio.append(result.sectionRatio)
                track.centroid.append(result.smoothedCentroid)
                track.flux.append(result.smoothedFlux)
                nextSample += 1
            }
        }
        return track
    }

    private static func maxAbsDiff(_ a: [Float], _ b: [Float]) -> Float {
        zip(a, b).map { abs($0 - $1) }.max() ?? 0
    }

    @Test("the same seconds at 43 Hz and 10 Hz smooth to the same trajectory")
    func trajectoriesAgreeAcrossRates() {
        let seconds: Float = 90
        let slow = Self.run(fps: LoudnessProfile.referenceAnalysisHz, seconds: seconds, profile: nil)
        let fast = Self.run(fps: 9.9, seconds: seconds, profile: nil)

        #expect(slow.section.count >= 89 && fast.section.count >= 89,
                "expected ~90 one-second samples, got \(slow.section.count) / \(fast.section.count)")
        let n = min(slow.section.count, fast.section.count)

        // The section leg is the one the canopy ranks. Its whole span here is ~0.2, so a
        // 0.005 tolerance is ~2.5 % — tight enough that a 4.4x error in tau cannot pass
        // (that mistake moved the live ratio from 2.00 to 0.58).
        let sectionDrift = Self.maxAbsDiff(Array(slow.section[0..<n]), Array(fast.section[0..<n]))
        #expect(sectionDrift < 0.005, """
            section leg drifts \(sectionDrift) between 43 Hz and 10 Hz. A per-FRAME alpha \
            makes tau depend on the analysis rate; it must be derived from deltaTime.
            """)

        let normalDrift = Self.maxAbsDiff(Array(slow.normal[0..<n]), Array(fast.normal[0..<n]))
        #expect(normalDrift < 0.005, "normal leg drifts \(normalDrift) between 43 Hz and 10 Hz")

        // The ratio is what Fractal Tree's canopy actually reads.
        let ratioDrift = Self.maxAbsDiff(Array(slow.ratio[0..<n]), Array(fast.ratio[0..<n]))
        #expect(ratioDrift < 0.02, "spectral_section_ratio drifts \(ratioDrift) across rates")
    }

    @Test("the ranked branch spans the same range at either rate")
    func rankedRangeAgreesAcrossRates() {
        // Build the density quantiles FROM the drive, exactly as `LoudnessProfile.measure`
        // builds them from a decoded track: quantiles of the smoothed series. Hand-picked
        // edges would only test whether I guessed the drive's range.
        let steps = LoudnessProfile.steps
        let reference = Self.run(fps: LoudnessProfile.referenceAnalysisHz,
                                 seconds: 90, profile: nil)
        let sorted = reference.section.sorted()
        let density = (0...steps).map { step -> Float in
            let index = Int((Float(sorted.count - 1) * Float(step) / Float(steps)).rounded())
            return sorted[min(max(index, 0), sorted.count - 1)]
        }
        let db = (0...steps).map { Float(-40) + Float($0) * (30.0 / Float(steps)) }
        let profile = LoudnessProfile(quantilesDB: db, densityQuantiles: density)

        let slow = Self.run(fps: LoudnessProfile.referenceAnalysisHz, seconds: 90, profile: profile)
        let fast = Self.run(fps: 9.9, seconds: 90, profile: profile)
        let slowSpan = (slow.ratio.max() ?? 0) - (slow.ratio.min() ?? 0)
        let fastSpan = (fast.ratio.max() ?? 0) - (fast.ratio.min() ?? 0)

        #expect(slowSpan > 0.2, "the drive must actually move the ranked ratio (got \(slowSpan))")
        #expect(abs(slowSpan - fastSpan) < 0.05, """
            ranked ratio spans \(slowSpan) at 43 Hz and \(fastSpan) at 60 Hz. This is the \
            defect exactly: the canopy read 0.534…0.614 live against 0.00…2.00 offline.
            """)
    }

    /// DYN.5. `spectral_centroid` and `spectral_flux` are read by many presets, not just
    /// Fractal Tree, so their followers running 1.4x fast at the live rate was a
    /// cross-preset gain error — and exactly the same shape of defect as the density legs.
    @Test("the centroid and flux followers agree across rates too")
    func spectralFeatureFollowersAgreeAcrossRates() {
        let slow = Self.run(fps: LoudnessProfile.referenceAnalysisHz, seconds: 90, profile: nil)
        let fast = Self.run(fps: 9.9, seconds: 90, profile: nil)
        let n = min(slow.centroid.count, fast.centroid.count)
        #expect(n >= 89, "expected ~90 one-second samples, got \(n)")

        // Centroid is in Hz, so scale the tolerance to the signal: 0.5 % of its own span.
        let slowSpan = (slow.centroid.max() ?? 0) - (slow.centroid.min() ?? 0)
        #expect(slowSpan > 1, "the drive must actually move the centroid (span \(slowSpan) Hz)")
        let centroidDrift = Self.maxAbsDiff(Array(slow.centroid[0..<n]), Array(fast.centroid[0..<n]))
        #expect(centroidDrift < slowSpan * 0.02, """
            centroid drifts \(centroidDrift) Hz between 43 Hz and 10 Hz against a span of \
            \(slowSpan) Hz — the follower width is still tied to the frame rate.
            """)

        // FLUX IS TESTED ON THE NORMALISED FIELD, and the distinction is the finding.
        // `smoothedFlux` is a per-FRAME spectral difference, so its MAGNITUDE is rate
        // dependent by construction — at 60 Hz consecutive frames are closer together and
        // each difference is smaller. Fixing the follower width cannot change that, and
        // rescaling the raw value is not available: `rawSmoothedFlux` feeds the mood
        // classifier (`VisualizerEngine+Audio`, `SessionPreparer+Analysis`) and the corpus
        // census, all calibrated against its current scale.
        //
        // What presets read is `f.spectral_flux`, which is `smoothedFlux / fluxRunningMax`
        // — and a constant gain cancels in that ratio, provided the running max decays over
        // the same WALL-CLOCK window at both rates. That is the part DYN.5 fixed, and it is
        // what this asserts.
        let slowNorm = Self.normalisedFlux(fps: LoudnessProfile.referenceAnalysisHz, seconds: 90)
        let fastNorm = Self.normalisedFlux(fps: 9.9, seconds: 90)
        let m = min(slowNorm.count, fastNorm.count)
        let normSpan = max((slowNorm.max() ?? 0) - (slowNorm.min() ?? 0), 1e-6)
        #expect(normSpan > 0.05, "the drive must move normalised flux (span \(normSpan))")
        let normDrift = Self.maxAbsDiff(Array(slowNorm[0..<m]), Array(fastNorm[0..<m]))
        #expect(normDrift < normSpan * 0.15, """
            spectral_flux drifts \(normDrift) between rates against a span of \(normSpan). \
            The running-max window is what must be wall-clock, not the raw difference.
            """)
    }

    /// `f.spectral_flux` as presets receive it, sampled on the same one-second grid.
    private static func normalisedFlux(fps: Float, seconds: Float) -> [Float] {
        let pipeline = MIRPipeline(binCount: fftSize / 2, sampleRate: sampleRate, fftSize: fftSize)
        let deltaTime = 1 / fps
        var out: [Float] = []
        var nextSample: Float = 1
        var t: Float = 0
        while t < seconds {
            let fv = pipeline.process(magnitudes: magnitudes(atSeconds: t),
                                      fps: fps, time: t, deltaTime: deltaTime)
            t += deltaTime
            if t >= nextSample { out.append(fv.spectralFlux); nextSample += 1 }
        }
        return out
    }

    @Test("tau constants reproduce the legacy coefficients at the reference rate")
    func referenceRateIsUnchanged() {
        // DYN.4 fixes a rate dependence; it must not retune anything. Each tau is defined so
        // the exponential form returns the old per-frame alpha exactly at 43.07 Hz.
        let dt = 1 / LoudnessProfile.referenceAnalysisHz
        for (name, legacy, tau) in [
            ("section", Float(0.00116), LoudnessProfile.densitySectionTau),
            ("level", Float(0.030), LoudnessProfile.levelSmoothingTau),
            ("fast", Float(0.117), SpectralAnalyzer.densityFastTau),
            ("slow", Float(0.0022), SpectralAnalyzer.densitySlowTau),
            ("normal", Float(0.00052), SpectralAnalyzer.densityNormalTau),
            ("centroid", Float(0.12), SpectralAnalyzer.centroidTau),
            ("rolloff", Float(0.12), SpectralAnalyzer.rolloffTau),
            ("flux", Float(0.25), SpectralAnalyzer.fluxTau)
        ] {
            let alpha = LoudnessProfile.emaAlpha(deltaTime: dt, tau: tau)
            #expect(abs(alpha - legacy) < 1e-5,
                    "\(name): alpha \(alpha) at the reference rate, legacy was \(legacy)")
        }
    }

    @Test("a zero or absent deltaTime falls back rather than freezing the follower")
    func degenerateDeltaTimeIsSafe() {
        // alpha 0 would freeze every follower at its seed for the rest of the track — a
        // worse failure than one frame smoothed at the wrong width.
        let tau = LoudnessProfile.densitySectionTau
        #expect(LoudnessProfile.emaAlpha(deltaTime: 0, tau: tau) > 0)
        #expect(LoudnessProfile.emaAlpha(deltaTime: -1, tau: tau) > 0)
        #expect(LoudnessProfile.emaAlpha(deltaTime: .nan, tau: tau) > 0)
        // And a long stall must not overshoot into instability.
        let big = LoudnessProfile.emaAlpha(deltaTime: 600, tau: tau)
        #expect(big > 0 && big <= 1, "alpha \(big) outside 0…1")
    }
}
