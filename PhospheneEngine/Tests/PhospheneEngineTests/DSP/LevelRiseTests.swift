// LevelRiseTests — FTR.24's accent driver: does it fire on an arrival and NOTHING else?
//
// The field exists because seven M7 rejections of "the tree grows and shrinks with no
// clear connection to the music" turned out to be one number: the size driver
// (`spectral_surge`) scores 0.25× event-versus-random specificity on real audio — it moves
// DOWN when the ear notices something. Generalisation evidence is offline and real, on four
// tracks chosen for different production (`docs/diagnostics/FTR15_SIZE_READS_LEVEL_*.md`
// §9); these tests guard the four properties that make the field a TRANSIENT rather than
// another level follower, which is the part a refactor can silently break.
//
// Synthetic spectra are the right instrument here and FA #27 does not apply: the claims are
// definitional (a step fires, a plateau does not), not perceptual. FA #27 bites when a
// synthetic envelope is used to stand in for real-music behaviour — that claim is made from
// the real captures, not from this file.

import Testing
import Foundation
@testable import DSP

// MARK: - Helpers

/// Broadband magnitudes at a chosen amplitude — pink-ish, like `SpectralDensityRealAudioTests`,
/// because a single peak is not what a level detector sees on real music.
private func broadband(amplitude: Float, binCount: Int = 512) -> [Float] {
    (0..<binCount).map { bin in
        amplitude / (1.0 + Float(bin) * 0.02)
    }
}

/// Run `frames` frames of constant amplitude and return `levelRise` after each.
private func drive(_ analyzer: SpectralAnalyzer,
                   amplitude: Float,
                   frames: Int,
                   deltaTime: Float) -> [Float] {
    let mags = broadband(amplitude: amplitude)
    return (0..<frames).map { _ in
        analyzer.process(magnitudes: mags, deltaTime: deltaTime).levelRise
    }
}

private let hopDT: Float = 1024.0 / 44100.0     // ≈ 23 ms, the live analysis hop

// MARK: - Tests

/// A PLATEAU IS NOT AN EVENT. The whole failure this field addresses is a driver that
/// reports on loudness rather than on arrivals, so the first thing to prove is that a loud
/// steady passage produces nothing at all.
@Test func levelRise_steadyLevel_staysSilent() {
    let analyzer = SpectralAnalyzer(binCount: 512, sampleRate: 44100, fftSize: 1024)
    let rises = drive(analyzer, amplitude: 0.5, frames: 60, deltaTime: hopDT)

    // Frame 1 is excluded: the trailing floor has no history yet, so the seed frame is a
    // rise against itself by construction and says nothing about steady-state behaviour.
    let settled = rises.dropFirst(4)
    #expect(settled.allSatisfy { $0 < 0.05 },
            "a constant level must not read as an event — max was \(settled.max() ?? -1)")
}

/// SILENCE PRODUCES NOTHING, which is why the preset can add this accent with no gate of
/// its own (D-037's neighbour: the silence STATE is the preset's business, but a driver
/// that fires in silence would force every consumer to gate it).
@Test func levelRise_silence_isZero() {
    let analyzer = SpectralAnalyzer(binCount: 512, sampleRate: 44100, fftSize: 1024)
    let rises = drive(analyzer, amplitude: 0, frames: 30, deltaTime: hopDT)
    #expect(rises.allSatisfy { $0 == 0 }, "silence must produce no accent")
}

/// AN ARRIVAL FIRES AT ONCE. +12 dB is a mix arriving; the attack is instantaneous by
/// design, so it must be up inside a frame or two rather than ramping.
@Test func levelRise_stepUp_firesImmediately() {
    let analyzer = SpectralAnalyzer(binCount: 512, sampleRate: 44100, fftSize: 1024)
    _ = drive(analyzer, amplitude: 0.1, frames: 40, deltaTime: hopDT)   // quiet passage
    let after = drive(analyzer, amplitude: 0.4, frames: 3, deltaTime: hopDT)  // ≈ +12 dB

    #expect(after[0] > 0.9,
            "a +12 dB arrival must fire on the FIRST frame, got \(after[0])")
}

/// AND THEN IT LETS GO. This is the property that distinguishes the field from `surge`: at
/// a sustained new level the accent must decay, because the sound landing is the news and
/// the plateau afterwards is not. `surge` (2.31 s release, ranked) deliberately does the
/// opposite, which is why both fields exist.
@Test func levelRise_sustainedAfterStep_decaysBack() {
    let analyzer = SpectralAnalyzer(binCount: 512, sampleRate: 44100, fftSize: 1024)
    _ = drive(analyzer, amplitude: 0.1, frames: 40, deltaTime: hopDT)
    let peak = drive(analyzer, amplitude: 0.4, frames: 1, deltaTime: hopDT)[0]
    // 1.0 s at the new level — five release time constants (τ 0.20 s).
    let held = drive(analyzer, amplitude: 0.4, frames: Int(1.0 / hopDT), deltaTime: hopDT)

    #expect(peak > 0.9, "precondition: the step should have fired, got \(peak)")
    #expect(held.last! < 0.10,
            "the accent must decay at a sustained level — ended at \(held.last!)")
}

/// RATE INVARIANCE, which is the reason the trailing floor is bounded in SECONDS and not in
/// frames. BUG-087: local-file analysis runs ~10–16 Hz and streaming ~51 Hz, so a fixed
/// sample count would be a 0.04 s window on one path and 0.2 s on the other — the same
/// class of bug as FTR.13's ease, which was sized in samples and ran on 2.1 of them.
@Test func levelRise_sameStepFiresAtBothAnalysisRates() {
    for dt in [Float(1.0 / 10.0), Float(1.0 / 51.0)] {
        let analyzer = SpectralAnalyzer(binCount: 512, sampleRate: 44100, fftSize: 1024)
        _ = drive(analyzer, amplitude: 0.1, frames: Int(1.0 / dt), deltaTime: dt)
        let fired = drive(analyzer, amplitude: 0.4, frames: 1, deltaTime: dt)[0]
        #expect(fired > 0.9,
                "the same +12 dB arrival must fire at \(Int(1 / dt)) Hz, got \(fired)")
    }
}

/// A SMALL RISE IS A SMALL ACCENT, and a 3 dB one is nothing at all. The band is 4–12 dB:
/// 3 dB is where an event becomes detectable, not where it is worth moving a picture for, and
/// a band that opened at 2 dB fired 1.47 times a second and read as a DC lift rather than an
/// accent (the calibration comment in `SpectralAnalyzer+Density` carries the measurement).
@Test func levelRise_isProportionalNotBinary() {
    func fire(dB: Float) -> Float {
        let analyzer = SpectralAnalyzer(binCount: 512, sampleRate: 44100, fftSize: 1024)
        _ = drive(analyzer, amplitude: 0.1, frames: 40, deltaTime: hopDT)
        let gain = pow(10, dB / 20)
        return drive(analyzer, amplitude: 0.1 * gain, frames: 1, deltaTime: hopDT)[0]
    }
    let below = fire(dB: 3), partial = fire(dB: 7), full = fire(dB: 14)
    #expect(below < 0.05, "a 3 dB rise is below the band and must not move the picture, got \(below)")
    #expect(partial > 0.10 && partial < 0.90, "a 7 dB rise should be PARTIAL, got \(partial)")
    #expect(full > partial, "14 dB must read larger than 7 dB (\(full) vs \(partial))")
}
