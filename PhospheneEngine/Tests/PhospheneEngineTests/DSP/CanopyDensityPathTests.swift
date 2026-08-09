// CanopyDensityPathTests — DYN.3: does the canopy's ratio come from the rank or the fallback?
//
// WHY THIS EXISTS. Fractal Tree's canopy reads `spectral_section_ratio`. That field has two
// sources — DYN.2c's ranked branch when a usable density profile is installed, and DYN.2b's
// live-EMA fallback otherwise — and they behave completely differently: the rank is uniform
// over the track by construction and spans 0…2, while the fallback is a ratio of two EMAs of
// the same signal and sits near 1.0 by construction.
//
// Measured on Matt's session `2026-08-07T22-59-38Z`, the live field spanned **0.785…1.084**
// and the canopy moved 0.38…0.50 — his *"the entire suite of movement does not feel strongly
// tied to the music."* Feeding the SAME tap capture through the SAME production objects
// offline, with the SAME cached profile installed, the field spans its full 0…2 and the
// canopy grows and recedes. So the mechanism is not broken, and the recorded CSV cannot say
// which branch ran live — the two are not separable after the fact from one column.
//
// `MIRPipeline.canopyDensityBranch` answers it, and these tests gate the classifier itself.
// A diagnostic that names the wrong branch is worse than no diagnostic: it would have sent
// the next increment after the wrong cause, which is the failure this whole sequence has
// already made once.

import Testing
import Foundation
@testable import DSP
@testable import Shared

@Suite("Canopy density path (DYN.3)")
struct CanopyDensityPathTests {

    private static let fftSize = 1024

    /// Drive the pipeline past the 30 s probe with plausible broadband frames.
    ///
    /// FA #27 bars synthetic audio for *diagnosing musical behaviour*; this asserts only
    /// which code branch a profile selects, which is a property of the profile and not of
    /// the music. The magnitudes only need to be non-degenerate.
    private static func runPastProbe(profile: LoudnessProfile?) -> MIRPipeline {
        let pipeline = MIRPipeline(binCount: fftSize / 2, sampleRate: 44100, fftSize: fftSize)
        pipeline.setLoudnessProfile(profile)
        let fps: Float = 60
        let deltaTime: Float = 1.0 / fps
        var magnitudes = [Float](repeating: 0, count: fftSize / 2)
        var time: Float = 0
        for frame in 0..<Int(fps * 32) {
            // A moving spectral tilt, so the density legs see something that varies.
            let tilt = 0.5 + 0.4 * sin(Float(frame) * 0.01)
            for bin in 0..<magnitudes.count {
                let hf = Float(bin) / Float(magnitudes.count)
                magnitudes[bin] = (1 - hf) * (1 - tilt) + hf * tilt + 0.05
            }
            _ = pipeline.process(magnitudes: magnitudes, fps: fps, time: time, deltaTime: deltaTime)
            time += deltaTime
        }
        return pipeline
    }

    /// A profile with both quantile tables, wide enough to be usable.
    private static func fullProfile() -> LoudnessProfile {
        let steps = LoudnessProfile.steps
        let db = (0...steps).map { Float(-40) + Float($0) * (30.0 / Float(steps)) }
        let density = (0...steps).map { Float($0) / Float(steps) }
        return LoudnessProfile(quantilesDB: db, densityQuantiles: density)
    }

    @Test("a usable profile with density quantiles selects the ranked branch")
    func rankedBranch() {
        let pipeline = Self.runPastProbe(profile: Self.fullProfile())
        #expect(pipeline.canopyDensityBranch == "ranked", """
            got \(pipeline.canopyDensityBranch ?? "nil") — the probe must recognise a complete \
            profile, or it will send the next increment after the wrong cause.
            """)
        // The measured rate is the other half of the probe: every density time constant is
        // 1/(alpha * fps), so a rate that is not what the constants were calibrated for
        // silently retunes them. 60 fps in, 60 fps out.
        #expect(abs(pipeline.canopyAnalysisFPS - 60) < 3,
                "measured \(pipeline.canopyAnalysisFPS) fps against a 60 fps drive")
    }

    @Test("no profile falls back, and says so")
    func noProfileBranch() {
        let pipeline = Self.runPastProbe(profile: nil)
        #expect(pipeline.canopyDensityBranch == "fallback(no-profile)",
                "got \(pipeline.canopyDensityBranch ?? "nil")")
    }

    @Test("a level-only profile falls back — this is the silent case")
    func noDensityQuantilesBranch() {
        // A v8-era profile: level quantiles present, density quantiles never measured.
        // `densityRank` returns nil and the ratio quietly reverts to the DYN.2b EMA — the
        // exact defect DYN.2c exists to remove, and it leaves no trace in the CSV.
        let steps = LoudnessProfile.steps
        let db = (0...steps).map { Float(-40) + Float($0) * (30.0 / Float(steps)) }
        let pipeline = Self.runPastProbe(profile: LoudnessProfile(quantilesDB: db))
        #expect(pipeline.canopyDensityBranch == "fallback(no-density-quantiles)",
                "got \(pipeline.canopyDensityBranch ?? "nil")")
    }

    @Test("a brickwalled profile below the usability floor falls back")
    func unusableProfileBranch() {
        // innerRangeDB below `minimumUsableRangeDB` (0.5 dB after DYN.1d).
        let steps = LoudnessProfile.steps
        let db = (0...steps).map { Float(-12) + Float($0) * (0.1 / Float(steps)) }
        let density = (0...steps).map { Float($0) / Float(steps) }
        let pipeline = Self.runPastProbe(
            profile: LoudnessProfile(quantilesDB: db, densityQuantiles: density))
        #expect(pipeline.canopyDensityBranch == "fallback(profile-unusable)",
                "got \(pipeline.canopyDensityBranch ?? "nil")")
    }

    @Test("a track change clears the probe so the next track reports its own path")
    func resetClearsProbe() {
        let pipeline = Self.runPastProbe(profile: Self.fullProfile())
        #expect(pipeline.canopyDensityBranch != nil)
        pipeline.reset()
        #expect(pipeline.canopyDensityBranch == nil)
        #expect(pipeline.canopyAnalysisFPS == 0)
    }
}
