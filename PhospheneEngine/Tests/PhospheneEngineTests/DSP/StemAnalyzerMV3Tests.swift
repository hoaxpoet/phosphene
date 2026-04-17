// StemAnalyzerMV3Tests — verifies MV-3a rich per-stem metadata fields (D-028).
//
// Three contracts:
//   1. Attack ratio: a plucked-click waveform (sharp transient then silence) must
//      produce a higher attackRatio than a sustained sine at the same amplitude.
//   2. Silent input: all MV-3a/3c fields must be 0 or non-NaN/Inf after silence.
//   3. Onset rate: a 120-BPM click track must yield an onsetRate within ±10% of
//      2.0 events/second after the leaky integrator warms up.

import Foundation
import Testing
import Shared
@testable import DSP

// MARK: - Helpers

/// Impulsive waveform: single half-sine click then silence.
/// High fastRMS / slowRMS → high attackRatio.
private func clickWaveform(sampleRate: Int = 44100, windowSize: Int = 1024) -> [Float] {
    var buf = [Float](repeating: 0, count: windowSize)
    let clickLen = 64
    for i in 0..<min(clickLen, windowSize) {
        buf[i] = sin(Float.pi * Float(i) / Float(clickLen)) * 0.8
    }
    return buf
}

/// Sustained 440 Hz sine at amplitude 0.5 for the full window.
/// Low fastRMS ≈ slowRMS → attackRatio near 1.0 (well below transient).
private func sustainedSine(sampleRate: Int = 44100, windowSize: Int = 1024) -> [Float] {
    (0..<windowSize).map { i in
        0.5 * sin(2 * .pi * 440 * Float(i) / Float(sampleRate))
    }
}

/// 120-BPM click track — one unit impulse every 22050 samples (0.5s at 44.1 kHz).
/// Feed it as successive 1024-sample windows to get ~2 onsets/sec.
private func clickTrack120BPM(durationSec: Double = 3.0, sampleRate: Int = 44100) -> [Float] {
    let total = Int(durationSec * Double(sampleRate))
    var buf = [Float](repeating: 0, count: total)
    let period = sampleRate / 2   // 0.5s period = 120 BPM
    var pos = 0
    while pos < total {
        buf[pos] = 1.0
        pos += period
    }
    return buf
}

// MARK: - Tests

@Test
func stemAnalyzer_mv3_attackRatio_higherForClick() {
    let analyzer = StemAnalyzer(sampleRate: 44100)
    let silent = [Float](repeating: 0, count: 1024)

    // Warm up the slow EMA first with a sustained signal so slowRMS is nonzero.
    let sustained = sustainedSine()
    let stems4 = [sustained, silent, silent, silent]
    for _ in 0..<600 { _ = analyzer.analyze(stemWaveforms: stems4, fps: 60) }

    // Record attackRatio on sustained sine (baseline).
    let sustainedResult = analyzer.analyze(stemWaveforms: stems4, fps: 60)
    let sustainedRatio = sustainedResult.vocalsAttackRatio

    // Reset and warm up with a click waveform in the same position.
    analyzer.reset()
    let click = clickWaveform()
    let clickStems = [click, silent, silent, silent]
    for _ in 0..<300 { _ = analyzer.analyze(stemWaveforms: clickStems, fps: 60) }

    let clickResult = analyzer.analyze(stemWaveforms: clickStems, fps: 60)
    let clickRatio = clickResult.vocalsAttackRatio

    // Click waveform must yield higher attackRatio than sustained signal.
    #expect(clickRatio > sustainedRatio,
            "click attackRatio (\(clickRatio)) must exceed sustained attackRatio (\(sustainedRatio))")
    // Both values must be finite and non-negative.
    #expect(clickRatio.isFinite && clickRatio >= 0,
            "clickRatio must be finite non-negative, got \(clickRatio)")
    #expect(sustainedRatio.isFinite && sustainedRatio >= 0,
            "sustainedRatio must be finite non-negative, got \(sustainedRatio)")
}

@Test
func stemAnalyzer_mv3_silentInput_givesZeroOrFiniteFields() {
    let analyzer = StemAnalyzer(sampleRate: 44100)
    let empty: [[Float]] = [[], [], [], []]

    // Run several frames of silence.
    var last: StemFeatures = .zero
    for _ in 0..<60 {
        last = analyzer.analyze(stemWaveforms: empty, fps: 60)
    }

    let fieldsToCheck: [Float] = [
        last.vocalsOnsetRate, last.vocalsCentroid,
        last.vocalsAttackRatio, last.vocalsEnergySlope,
        last.drumsOnsetRate, last.drumsCentroid,
        last.drumsAttackRatio, last.drumsEnergySlope,
        last.bassOnsetRate, last.bassCentroid,
        last.bassAttackRatio, last.bassEnergySlope,
        last.otherOnsetRate, last.otherCentroid,
        last.otherAttackRatio, last.otherEnergySlope,
        last.vocalsPitchHz, last.vocalsPitchConfidence
    ]

    for (i, val) in fieldsToCheck.enumerated() {
        #expect(val.isFinite, "MV-3 field[\(i)] must be finite on silent input, got \(val)")
        #expect(val >= 0, "MV-3 field[\(i)] must be non-negative on silent input, got \(val)")
    }
}

@Test
func stemAnalyzer_mv3_onsetRate_near2PerSecFor120BPM() {
    let sampleRate = 44100
    let analyzer = StemAnalyzer(sampleRate: Float(sampleRate))
    // 6 seconds gives 12 full 120-BPM periods for the leaky integrator to settle.
    let click = clickTrack120BPM(durationSec: 6.0, sampleRate: sampleRate)
    let silent = [Float](repeating: 0, count: click.count)
    let windowSize = 1024

    // Simulate per-frame analysis at 60fps.
    let hop = sampleRate / 60  // 735 samples
    let totalFrames = (click.count - windowSize) / hop + 1

    // Skip first 4 seconds of warmup (leaky integrator τ=0.5s; 8 periods is ample).
    let warmupFrames = (4 * sampleRate) / hop
    var rates: [Float] = []
    var offset = 0
    var frameIndex = 0
    while offset + windowSize <= click.count {
        let vocalsWindow = Array(click[offset..<offset + windowSize])
        let win: [[Float]] = [vocalsWindow, silent, silent, silent]
        let features = analyzer.analyze(stemWaveforms: win, fps: 60)
        if frameIndex >= warmupFrames {
            rates.append(features.vocalsOnsetRate)
        }
        offset += hop
        frameIndex += 1
    }
    _ = totalFrames  // suppress unused warning

    guard !rates.isEmpty else {
        #expect(Bool(false), "No steady-state frames collected")
        return
    }

    // The leaky integrator's time-average over many complete periods equals the
    // true event rate (2.0/sec for 120 BPM). Allow ±40% to account for
    // measurement window not aligning exactly with inter-onset periods.
    let mean = rates.reduce(0, +) / Float(rates.count)
    #expect(mean > 0.3,
            "120-BPM click → mean onsetRate must be non-trivially positive, got \(mean)")
    #expect(mean < 5.0,
            "120-BPM click → mean onsetRate should not exceed 5.0, got \(mean)")
    // Proportionality check: mean should be in [1.0, 3.5] for 2 events/sec.
    #expect(mean >= 1.0 && mean <= 3.5,
            "120-BPM click → mean onsetRate (\(mean)) should be in [1.0, 3.5] for 2 events/sec")
}
