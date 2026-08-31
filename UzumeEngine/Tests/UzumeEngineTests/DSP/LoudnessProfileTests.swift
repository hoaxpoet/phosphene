// LoudnessProfileTests — DYN.1c: does a per-track band fix what a fixed band cannot?
//
// The defect these tests encode, measured on session `2026-08-04T20-23-15Z` (Hummer):
// `spectral_surge` reaches 1.00 at 31.6 s and stays pinned for 62 % of the capture, while
// sections LATER in the track are 4 dB louder than the one that saturated it. Once pinned
// the field is a constant, so the tree grew to full size before the full band arrived.
//
// Two levels of the same claim, deliberately:
//   1. `fixedBandCannotSeparateTwoLoudSections` / `profileSeparatesThem` — the pair. The
//      first FAILS to distinguish and is expected to; the second must.
//   2. `measureBracketsTheTrackItMeasured` — the offline measurement over real PCM,
//      through the shared FFT kernel, on the same scale the live analyzer reads.
//
// Broadband spectra throughout, never single peaks: DYN.1's synthetic single-peak suite
// stayed green through eight failed live reviews (see SpectralDensityRealAudioTests).

import Testing
import Foundation
@testable import Audio
@testable import DSP
@testable import Shared

@Suite("Per-track loudness profile (DYN.1c)")
struct LoudnessProfileTests {

    private static let binCount = 512
    private static let fftSize = 1024
    private static let sampleRate: Float = 48000

    // MARK: - Fixtures

    /// Pink-ish broadband magnitudes (energy ∝ 1/f, the rough shape of a rock mix),
    /// scaled so the frame's `LoudnessProfile.levelDB` lands on `targetDB`.
    private static func spectrum(atLevelDB targetDB: Float) -> [Float] {
        let shape: [Float] = (0..<binCount).map { bin in
            let hz = Float(bin) * sampleRate / Float(fftSize)
            return 1.0 / max(hz, 30)
        }
        let shapeDB = LoudnessProfile.levelDB(magnitudes: shape, count: binCount)
        // Level is 10·log10(Σ mag²), so scaling every bin by g shifts it by 20·log10(g).
        let gain = powf(10, (targetDB - shapeDB) / 20)
        return shape.map { $0 * gain }
    }

    /// Run `frames` frames of a constant-level spectrum through `analyzer`, return the
    /// final surge. Long enough for the follower to settle either direction.
    @discardableResult
    private static func hold(_ analyzer: SpectralAnalyzer, atLevelDB level: Float, frames: Int) -> Float {
        let magnitudes = spectrum(atLevelDB: level)
        var surge: Float = 0
        for _ in 0..<frames { surge = analyzer.process(magnitudes: magnitudes, deltaTime: 1024.0 / 44100.0).surge }
        return surge
    }

    /// The smoothed-level series the live analyzer would see for a section list, computed
    /// through the SAME shared definitions the analyzer uses. This is what a real offline
    /// measurement produces; building it here keeps the test free of an audio fixture.
    private static func smoothedLevels(sections: [(levelDB: Float, frames: Int)]) -> [Float] {
        var levels: [Float] = []
        var smoothed: Float = 0
        var seeded = false
        // DYN.4 — the alpha this fixture's own frame duration implies for the shared tau.
        let alpha = LoudnessProfile.emaAlpha(
            deltaTime: 1 / LoudnessProfile.referenceAnalysisHz,
            tau: LoudnessProfile.levelSmoothingTau)
        for section in sections {
            let level = LoudnessProfile.levelDB(
                magnitudes: spectrum(atLevelDB: section.levelDB), count: binCount)
            for _ in 0..<section.frames {
                if !seeded {
                    smoothed = level
                    seeded = true
                } else {
                    smoothed = alpha * level + (1 - alpha) * smoothed
                }
                levels.append(smoothed)
            }
        }
        return levels
    }

    /// Quiet intro, an arrival, then a materially louder later section — Hummer's shape.
    /// Both loud sections sit ABOVE the fixed band's top edge (−15 dB), which is the
    /// condition under which a fixed band cannot tell them apart.
    private static let quietDB: Float = -30
    private static let arrivalDB: Float = -14
    private static let laterLouderDB: Float = -10
    private static let sections: [(levelDB: Float, frames: Int)] = [
        (quietDB, 900), (arrivalDB, 900), (laterLouderDB, 900),
    ]

    // MARK: - The defect

    @Test("a FIXED band pins on the first loud section and cannot see a louder one later")
    func fixedBandCannotSeparateTwoLoudSections() {
        let analyzer = SpectralAnalyzer(binCount: Self.binCount,
                                        sampleRate: Self.sampleRate,
                                        fftSize: Self.fftSize)
        Self.hold(analyzer, atLevelDB: Self.quietDB, frames: 900)
        let arrival = Self.hold(analyzer, atLevelDB: Self.arrivalDB, frames: 900)
        let later = Self.hold(analyzer, atLevelDB: Self.laterLouderDB, frames: 900)

        print(String(format: "[fixed band] arrival %.3f → 4 dB louder later %.3f", arrival, later))
        #expect(arrival > 0.99, "the arrival should saturate the fixed band — that is the defect")
        #expect(later - arrival < 0.01, """
            A section 4 dB louder than the arrival reads \(later) against \(arrival). Pinned \
            is a constant: this is why the tree reached full size before the full band \
            arrived on Matt's Hummer capture.
            """)
    }

    // MARK: - The fix

    @Test("a per-track profile keeps a later, louder section ABOVE the arrival")
    func profileSeparatesThem() throws {
        let profile = try #require(
            LoudnessProfile(smoothedLevelsDB: Self.smoothedLevels(sections: Self.sections)))
        #expect(profile.isUsable)
        // Three equal-length sections ⇒ each occupies about a third of the distribution.
        #expect(profile.rank(ofLevelDB: Self.quietDB) < 0.4)
        #expect(profile.rank(ofLevelDB: Self.laterLouderDB) > 0.9)

        let analyzer = SpectralAnalyzer(binCount: Self.binCount,
                                        sampleRate: Self.sampleRate,
                                        fftSize: Self.fftSize)
        analyzer.setLoudnessProfile(profile)
        Self.hold(analyzer, atLevelDB: Self.quietDB, frames: 900)
        let arrival = Self.hold(analyzer, atLevelDB: Self.arrivalDB, frames: 900)
        let later = Self.hold(analyzer, atLevelDB: Self.laterLouderDB, frames: 900)

        print(String(format: "[profile %.1f…%.1f dB] arrival %.3f → louder later %.3f",
                     profile.quietDB, profile.loudDB, arrival, later))
        #expect(arrival < 0.99, "the arrival must leave headroom for the louder section")
        #expect(later > arrival + 0.05, """
            With this track's own band the 4 dB-louder section reads \(later) against the \
            arrival's \(arrival). If these are equal the field is still pinned and the \
            visual still cannot grow past the first loud moment.
            """)
    }

    @Test("reset() keeps the installed profile — the LF path resets AFTER installing")
    func resetPreservesProfile() throws {
        // `handleLocalFileReady` calls `resetStemPipeline` (which installs the profile)
        // and then `mirPipeline.reset()` before starting the router. A profile cleared in
        // reset() would be discarded on the one path that has one.
        let profile = try #require(
            LoudnessProfile(smoothedLevelsDB: Self.smoothedLevels(sections: Self.sections)))
        let analyzer = SpectralAnalyzer(binCount: Self.binCount,
                                        sampleRate: Self.sampleRate,
                                        fftSize: Self.fftSize)
        analyzer.setLoudnessProfile(profile)
        analyzer.reset()
        let arrival = Self.hold(analyzer, atLevelDB: Self.arrivalDB, frames: 1800)
        #expect(arrival < 0.99, """
            After reset() the arrival reads \(arrival) — the fixed band's pinned value. \
            The profile did not survive reset(), so the LF path would run unprofiled.
            """)
    }

    // MARK: - Guards

    @Test("a constant-level source produces no usable profile — keep the fixed band")
    func constantLevelIsRefused() {
        let flat = LoudnessProfile(smoothedLevelsDB: [Float](repeating: -18, count: 2000))
        #expect(flat?.isUsable == false, "a 0 dB range must not rank its own dither")

        let analyzer = SpectralAnalyzer(binCount: Self.binCount,
                                        sampleRate: Self.sampleRate,
                                        fftSize: Self.fftSize)
        analyzer.setLoudnessProfile(flat)
        // Unusable → fixed band → a −10 dB section still pins, as it did before DYN.1c.
        #expect(Self.hold(analyzer, atLevelDB: -10, frames: 1800) > 0.99)
    }

    /// DYN.1d — the gate used to require 4 dB of inner range, which refused every
    /// brickwalled master and so kept the fixed band on exactly the tracks a fixed band
    /// serves worst. Cherub Rock measures 1.46 dB and pinned 92.7 % of a session because
    /// of it. A narrow-but-real distribution must produce a USABLE profile.
    @Test("a narrow-range (brickwalled) master still yields a usable profile")
    func narrowRangeMasterIsUsable() throws {
        // ~1.5 dB of inner range — Cherub Rock's measured figure — over three sections.
        let sections: [(levelDB: Float, frames: Int)] = [(-15.0, 800), (-14.2, 800), (-13.5, 800)]
        let profile = try #require(
            LoudnessProfile(smoothedLevelsDB: Self.smoothedLevels(sections: sections)))
        print(String(format: "[narrow] inner range %.2f dB, usable=%@",
                     profile.innerRangeDB, profile.isUsable ? "yes" : "NO"))
        #expect(profile.innerRangeDB < 4.0, "fixture must sit under the OLD 4 dB gate to be a regression test")
        #expect(profile.isUsable, """
            A \(profile.innerRangeDB) dB master was refused, so the surge falls back to the \
            fixed absolute band — which is precisely the DYN.1c defect, on the class of \
            track least able to survive it.
            """)

        // And it must still RANK: the loudest section above the quietest.
        #expect(profile.rank(ofLevelDB: -13.5) > profile.rank(ofLevelDB: -15.0) + 0.3)
    }

    @Test("too few frames is not a track")
    func shortSeriesIsRefused() {
        let short = (0..<100).map { Float($0) * 0.1 - 30 }
        #expect(LoudnessProfile(smoothedLevelsDB: short) == nil)
    }

    // MARK: - Offline measurement over real PCM

    /// The offline path end to end: PCM → shared FFT kernel → `levelDB` → percentiles.
    /// The bracket assertion is the scale check — if `measure` and the live analyzer
    /// disagreed on the level scale (the DYN.1 calibration's error #2, which cost a review
    /// round), the percentiles would not contain the levels the analyzer reads.
    @Test("measure() brackets the levels the live analyzer reads for the same audio")
    func measureBracketsTheTrackItMeasured() throws {
        var generator = SystemRandomNumberGenerator()
        func noise(count: Int, amplitude: Float) -> [Float] {
            (0..<count).map { _ in Float.random(in: -amplitude...amplitude, using: &generator) }
        }
        // 700 frames quiet + 700 loud, a 20 dB step. Above `minimumFrames` either side.
        let samples = noise(count: Self.fftSize * 700, amplitude: 0.02)
            + noise(count: Self.fftSize * 700, amplitude: 0.2)

        let profile = try #require(
            LoudnessProfile.measure(samples: samples, sampleRate: 48000, fftSize: Self.fftSize))
        print(String(format: "[measure] %.1f…%.1f dB (range %.1f)",
                     profile.quietDB, profile.loudDB, profile.rangeDB))
        #expect(profile.isUsable)
        #expect(profile.rangeDB > 10, """
            A 20 dB step in the source produced a \(profile.rangeDB) dB measured range. \
            The distribution is not tracking the material.
            """)

        // Same audio through the live analyzer: its level must land INSIDE the measured
        // distribution, which is only true if both paths share the level scale.
        let fft = try FFTMagnitudeKernel(fftSize: Self.fftSize)
        var loudFrameLevels: [Float] = []
        var offset = Self.fftSize * 700
        while offset + Self.fftSize <= samples.count {
            for i in 0..<Self.fftSize { fft.windowed[i] = samples[offset + i] }
            fft.computeMagnitudes()
            loudFrameLevels.append(
                LoudnessProfile.levelDB(magnitudes: fft.magnitudes, count: fft.binCount))
            offset += Self.fftSize
        }
        let loudMean = loudFrameLevels.reduce(0, +) / Float(loudFrameLevels.count)
        let rank = profile.rank(ofLevelDB: loudMean)
        print(String(format: "[measure] loud-section mean level %.1f dB → rank %.3f", loudMean, rank))
        #expect(rank > 0.5, """
            The loud half of the source ranks \(rank) in its own measured distribution \
            (\(profile.quietDB)…\(profile.loudDB) dB). Offline and live are not on the same \
            scale — the exact failure mode documented in docs/ENGINE/DYN1_CALIBRATION.md §2.
            """)
    }
}
