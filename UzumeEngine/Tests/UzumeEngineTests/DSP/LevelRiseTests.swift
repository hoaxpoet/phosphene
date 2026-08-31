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

/// AN ARRIVAL FIRES AT ONCE — within the 40 ms pre-smoothing, not within one sample.
///
/// The follower's attack is instantaneous, but its INPUT is a level damped with a 40 ms τ (the
/// price of rate invariance), so a step reaches ~0.73 on the first frame and saturates over the
/// next two. That is still "at once" perceptually — 60 ms is far inside the ~100 ms window in
/// which the eye reads sound and motion as simultaneous — and it is the property that keeps the
/// value from arriving at the geometry as a single-frame discontinuity, which is exactly what
/// made FTR.24's first consumer look defective.
@Test func levelRise_stepUp_firesImmediately() {
    let analyzer = SpectralAnalyzer(binCount: 512, sampleRate: 44100, fftSize: 1024)
    _ = drive(analyzer, amplitude: 0.1, frames: 40, deltaTime: hopDT)   // quiet passage
    let after = drive(analyzer, amplitude: 0.4, frames: 4, deltaTime: hopDT)  // ≈ +12 dB

    #expect(after[0] > 0.5,
            "a +12 dB arrival must be MOSTLY there on the first frame, got \(after[0])")
    #expect(after.max()! > 0.9,
            "…and saturate within 4 frames (≈ 90 ms), got \(after.max()!)")
}

/// AND THEN IT LETS GO. This is the property that distinguishes the field from `surge`: at
/// a sustained new level the accent must decay, because the sound landing is the news and
/// the plateau afterwards is not. `surge` (2.31 s release, ranked) deliberately does the
/// opposite, which is why both fields exist.
@Test func levelRise_sustainedAfterStep_decaysBack() {
    let analyzer = SpectralAnalyzer(binCount: 512, sampleRate: 44100, fftSize: 1024)
    _ = drive(analyzer, amplitude: 0.1, frames: 40, deltaTime: hopDT)
    let peak = drive(analyzer, amplitude: 0.4, frames: 4, deltaTime: hopDT).max()!
    // 1.0 s at the new level — five release constants (τ 0.20 s), and well past the
    // 0.15 s lag, after which the difference itself is zero.
    let held = drive(analyzer, amplitude: 0.4, frames: Int(1.0 / hopDT), deltaTime: hopDT)

    #expect(peak > 0.9, "precondition: the step should have fired, got \(peak)")
    #expect(held.last! < 0.10,
            "the accent must decay at a sustained level — ended at \(held.last!)")
}

/// ★★★ RATE INVARIANCE ON A DISTRIBUTION, not on one enormous input.
///
/// THIS TEST'S PREDECESSOR PASSED WHILE THE FIELD HAD A 22× RATE DEPENDENCE, and that is the
/// most useful thing in this file. It asked only whether a synthetic +12 dB step still fires at
/// 10 Hz and 51 Hz — and a step that large saturates the band at any rate, so it could not fail.
/// Meanwhile the real statistic diverged wildly on real music: measured on one capture with the
/// original trailing-MINIMUM formulation, 0.04 fires/s at 15.8 Hz against 0.89/s at 59.4 Hz.
/// A consumer calibrated at the low rate doubled its motion at the high one and Matt rejected it
/// on sight (*"herky-jerky … looks defective"*).
///
/// The cause was a statistic with a hidden sample-count term: a MINIMUM over a time window
/// spans more frames at a higher rate, and each frame's level is noisier because the hop is
/// shorter, so the floor digs deeper. The fix is a fixed-LAG difference on a pre-smoothed level.
///
/// So this test drives a repeating amplitude pattern — a crude stand-in for music, with rises of
/// several sizes — and compares the DUTY CYCLE and MEAN across the two real analysis rates
/// (BUG-087: local files ~10–16 Hz, the tap ~51–59 Hz). Those are the statistics a consumer's
/// motion budget actually depends on.
@Test func levelRise_distributionMatchesAcrossAnalysisRates() {
    func statistics(rate: Float) -> (duty: Float, mean: Float) {
        let analyzer = SpectralAnalyzer(binCount: 512, sampleRate: 44100, fftSize: 1024)
        let dt = 1.0 / rate
        var out: [Float] = []
        // 24 s of a repeating 6-step amplitude pattern: two big rises, two small, two holds.
        let pattern: [Float] = [0.08, 0.30, 0.10, 0.14, 0.45, 0.12]
        var elapsed: Float = 0
        var index = 0
        while elapsed < 24 {
            // Each step lasts 0.4 s of WALL TIME regardless of rate, so both runs see the
            // same music — the only difference between them is the analysis rate itself.
            var held: Float = 0
            while held < 0.4 {
                out.append(analyzer.process(magnitudes: broadband(amplitude: pattern[index]),
                                            deltaTime: dt).levelRise)
                held += dt
                elapsed += dt
            }
            index = (index + 1) % pattern.count
        }
        let duty = Float(out.filter { $0 > 0.01 }.count) / Float(out.count)
        return (duty, out.reduce(0, +) / Float(out.count))
    }
    let low = statistics(rate: 15.8)     // local-file analysis
    let high = statistics(rate: 59.4)    // the tap path

    // A factor of 1.6 on the same audio is the bar: below it a consumer tuned on one path is
    // recognisably the same on the other. The shipped defect was 22×.
    let dutyRatio = max(low.duty, high.duty) / max(min(low.duty, high.duty), 1e-6)
    let meanRatio = max(low.mean, high.mean) / max(min(low.mean, high.mean), 1e-6)
    #expect(dutyRatio < 1.6, """
        duty cycle differs \(String(format: "%.1f", dutyRatio))× between 15.8 Hz \
        (\(String(format: "%.2f", low.duty))) and 59.4 Hz (\(String(format: "%.2f", high.duty))) \
        — a consumer calibrated on one path will not behave on the other. Do NOT widen this bar; \
        the statistic itself has a sample-count term if this fails.
        """)
    #expect(meanRatio < 1.6, """
        mean output differs \(String(format: "%.1f", meanRatio))× between the two analysis rates \
        (\(String(format: "%.3f", low.mean)) vs \(String(format: "%.3f", high.mean))).
        """)
}

/// The original, KEPT as the coarse floor it always was — a big arrival must still fire at both
/// rates. It is necessary and nowhere near sufficient; the test above is the real gate.
@Test func levelRise_sameStepFiresAtBothAnalysisRates() {
    for dt in [Float(1.0 / 10.0), Float(1.0 / 51.0)] {
        let analyzer = SpectralAnalyzer(binCount: 512, sampleRate: 44100, fftSize: 1024)
        _ = drive(analyzer, amplitude: 0.1, frames: Int(1.0 / dt), deltaTime: dt)
        let fired = drive(analyzer, amplitude: 0.4, frames: 2, deltaTime: dt).max() ?? 0
        #expect(fired > 0.9,
                "the same +12 dB arrival must fire at \(Int(1 / dt)) Hz, got \(fired)")
    }
}

/// A SMALL RISE IS A SMALL ACCENT. The band is 2–7 dB of a FIXED-LAG difference, which is a
/// smaller number than the same event produces against a trailing minimum — the two are not
/// interchangeable, and swapping the statistic without re-deriving the band is how the first
/// version of this field shipped with a 22× rate dependence.
@Test func levelRise_isProportionalNotBinary() {
    func fire(dB: Float) -> Float {
        let analyzer = SpectralAnalyzer(binCount: 512, sampleRate: 44100, fftSize: 1024)
        _ = drive(analyzer, amplitude: 0.1, frames: 40, deltaTime: hopDT)
        let gain = pow(10, dB / 20)
        // The PEAK of the response over ~150 ms, not the first sample: with a 40 ms
        // pre-smoothing the first frame sees only ~63 % of the step, so a single-frame read
        // reports every rise as smaller than it is.
        return drive(analyzer, amplitude: 0.1 * gain, frames: 7, deltaTime: hopDT).max()!
    }
    let below = fire(dB: 1), partial = fire(dB: 4), full = fire(dB: 9)
    #expect(below < 0.10, "a 1 dB rise is below the band and must not move the picture, got \(below)")
    #expect(partial > 0.10 && partial < 0.95, "a 4 dB rise should be PARTIAL, got \(partial)")
    #expect(full >= partial, "9 dB must read at least as large as 4 dB (\(full) vs \(partial))")
}
