// BandEnergyProcessorTests — Unit tests for band energy extraction, AGC, and smoothing.

import Testing
import Foundation
@testable import DSP

// MARK: - Basic Energy Tests

@Test func bandEnergy_silence_allZero() {
    let processor = BandEnergyProcessor()
    let magnitudes = [Float](repeating: 0, count: 512)
    let result = processor.process(magnitudes: magnitudes, fps: 60)

    #expect(result.bass == 0, "Bass should be 0 for silence")
    #expect(result.mid == 0, "Mid should be 0 for silence")
    #expect(result.treble == 0, "Treble should be 0 for silence")
    #expect(result.subBass == 0, "SubBass should be 0 for silence")
}

@Test func bandEnergy_lowFreqOnly_bassNonZero() {
    let processor = BandEnergyProcessor()
    // Bin 2 ≈ 94 Hz → falls in bass (20-250 Hz) and lowBass (80-250 Hz)
    let magnitudes = AudioFixtures.syntheticMagnitudes(peaks: [(bin: 2, magnitude: 1.0)])

    // Feed enough frames for AGC to stabilize.
    for _ in 0..<120 {
        _ = processor.process(magnitudes: magnitudes, fps: 60)
    }
    let result = processor.process(magnitudes: magnitudes, fps: 60)

    #expect(result.bass > 0, "Bass should be non-zero for low-frequency signal")
    #expect(result.lowBass > 0, "LowBass should be non-zero for signal at ~94 Hz")
    // High bands should be zero (no energy there).
    #expect(result.highMid == 0 || result.highMid < 0.001,
            "HighMid should be near zero for low-frequency signal")
}

// MARK: - AGC Tests

@Test func bandEnergy_steadySignal_agcNormalizesNearHalf() {
    let processor = BandEnergyProcessor()
    // Uniform energy across all bins.
    let magnitudes = AudioFixtures.uniformMagnitudes(magnitude: 0.5)

    // Run 300 frames for AGC to fully stabilize.
    var result = processor.process(magnitudes: magnitudes, fps: 60)
    for _ in 0..<300 {
        result = processor.process(magnitudes: magnitudes, fps: 60)
    }

    // After AGC stabilization, total energy should map to ~0.5 region.
    // Individual bands depend on their share of total energy.
    let totalSmoothed = result.bass + result.mid + result.treble
    #expect(totalSmoothed > 0.1, "Total 3-band energy should be meaningful after AGC, got \(totalSmoothed)")
    #expect(totalSmoothed < 2.0, "Total 3-band energy should be reasonable after AGC, got \(totalSmoothed)")
}

@Test func bandEnergy_6band_preservesRelativeDifferences() {
    let processor = BandEnergyProcessor()
    // Strong bass, weak treble — relative difference should survive AGC.
    var magnitudes = [Float](repeating: 0, count: 512)
    // Bins 0-5 (bass region) at magnitude 1.0
    for i in 0..<6 { magnitudes[i] = 1.0 }
    // Bins 170-511 (high region) at magnitude 0.1
    for i in 170..<512 { magnitudes[i] = 0.1 }

    // Run enough frames for smoothing/AGC.
    var result = processor.process(magnitudes: magnitudes, fps: 60)
    for _ in 0..<300 {
        result = processor.process(magnitudes: magnitudes, fps: 60)
    }

    // Bass-region energy should be larger than high-region energy.
    let bassRegion = result.subBass + result.lowBass
    let highRegion = result.high
    #expect(bassRegion > highRegion,
            "Bass region (\(bassRegion)) should exceed high region (\(highRegion)) — relative differences must survive AGC")
}

// MARK: - FPS Independence

@Test func bandEnergy_differentFPS_convergesSimilar() {
    // Two processors with same input but different FPS should converge to similar values.
    let processor30 = BandEnergyProcessor()
    let processor60 = BandEnergyProcessor()
    let magnitudes = AudioFixtures.uniformMagnitudes(magnitude: 0.5)

    // Run 300 frames at each rate.
    var result30 = processor30.process(magnitudes: magnitudes, fps: 30)
    var result60 = processor60.process(magnitudes: magnitudes, fps: 60)
    for _ in 0..<300 {
        result30 = processor30.process(magnitudes: magnitudes, fps: 30)
        result60 = processor60.process(magnitudes: magnitudes, fps: 60)
    }

    // Both should converge to similar stable values (within 20% tolerance).
    let tolerance: Float = 0.2
    let diff = abs(result30.bass - result60.bass)
    let maxVal = max(result30.bass, result60.bass)
    let relDiff = maxVal > 0 ? diff / maxVal : 0
    #expect(relDiff < tolerance,
            "30fps bass (\(result30.bass)) and 60fps bass (\(result60.bass)) should converge similarly")
}
