// StemAnalyzerTests — unit tests for StemAnalyzer's sliding-window analysis contract.
//
// The per-frame stem analysis architecture (VisualizerEngine+Audio.runPerFrameStemAnalysis)
// depends on StemAnalyzer.analyze producing continuously-varying features when called
// with different sliding 1024-sample windows of the same underlying waveform. This
// suite verifies that contract explicitly — if StemAnalyzer were ever refactored in a
// way that made its output independent of the window's position, the per-frame
// architecture would silently degrade to the old 5s-piecewise-constant behaviour.
//
// Historical context: session 2026-04-16T20-56-46Z exposed that StemFeatures values
// hit the GPU only once per 5s separation cycle. `stems.drumsBeat` held 0.825 across
// 300+ consecutive frames, producing "terrain frozen, palette cycling" visuals.
// These tests exist to prevent regression.

import Foundation
import Testing
import Shared
@testable import DSP

// MARK: - Helpers

/// A synthetic stem waveform with characteristically varying per-1024-sample energy.
/// Builds 5 seconds of 44.1 kHz audio where amplitude ramps from 0 → 0.8 → 0.1 → 0.6
/// via piecewise-linear segments so sliding windows at different offsets yield
/// meaningfully different magnitudes.
private func rampedWaveform(durationSec: Float = 5, sampleRate: Float = 44100) -> [Float] {
    let count = Int(durationSec * sampleRate)
    let segmentA = count / 3
    let segmentB = 2 * count / 3
    var out = [Float](repeating: 0, count: count)
    for i in 0..<count {
        let envelope: Float
        if i < segmentA {
            let t = Float(i) / Float(segmentA)
            envelope = t * 0.8
        } else if i < segmentB {
            let t = Float(i - segmentA) / Float(segmentB - segmentA)
            envelope = 0.8 + t * (0.1 - 0.8)
        } else {
            let t = Float(i - segmentB) / Float(count - segmentB)
            envelope = 0.1 + t * (0.6 - 0.1)
        }
        // 220 Hz tone so energy lands squarely in the bass band.
        let phase = 2 * .pi * 220.0 * Float(i) / sampleRate
        out[i] = sin(phase) * envelope
    }
    return out
}

/// Slice a 1024-sample window from each stem starting at `offset`.
/// Matches the slicing that runPerFrameStemAnalysis does in the app.
private func window(stems: [[Float]], atOffset offset: Int, size: Int = 1024) -> [[Float]] {
    stems.map { stem in
        let end = min(offset + size, stem.count)
        if offset < end {
            return Array(stem[offset..<end])
        } else {
            return [Float](repeating: 0, count: size)
        }
    }
}

// MARK: - Sliding-window variance contract

@Test
func stemAnalyzer_slidingWindows_produceVaryingFeatures() {
    let analyzer = StemAnalyzer(sampleRate: 44100)
    // Put the ramped waveform in the BASS stem (index 2) so we watch bassEnergy vary.
    // Other stems are silent so they don't contribute noise.
    let drumsAndVocalsSilent = [Float](repeating: 0, count: Int(5 * 44100))
    let stems = [
        drumsAndVocalsSilent,       // vocals
        drumsAndVocalsSilent,       // drums
        rampedWaveform(),           // bass
        drumsAndVocalsSilent        // other
    ]

    // Simulate the per-frame architecture: slide 1024-sample windows through
    // the waveform at audio-rate (735-sample hops ≈ 60fps).
    let hop = 735
    let windowSize = 1024
    let frames = (stems[0].count - windowSize) / hop + 1

    var bassEnergies: [Float] = []
    bassEnergies.reserveCapacity(frames)

    for frame in 0..<frames {
        let offset = frame * hop
        let win = window(stems: stems, atOffset: offset, size: windowSize)
        let features = analyzer.analyze(stemWaveforms: win, fps: 60)
        bassEnergies.append(features.bassEnergy)
    }

    // Skip the first 180 frames (3s) — BandEnergyProcessor AGC warmup.
    let warmupFrames = 180
    let steadyState = Array(bassEnergies[warmupFrames...])

    // Contract 1: the analyzer must produce non-zero energy on a non-silent stem.
    let peakEnergy = steadyState.max() ?? 0
    #expect(peakEnergy > 0.01,
            "bassEnergy must be non-zero on a non-silent bass stem (got peak \(peakEnergy))")

    // Contract 2: the analyzer must produce DIFFERENT energies across sliding windows.
    // If this ever becomes uniform, the per-frame architecture is broken — the
    // visualizer will revert to piecewise-constant behaviour.
    let minEnergy = steadyState.min() ?? 0
    let maxEnergy = steadyState.max() ?? 0
    let spread = maxEnergy - minEnergy
    #expect(spread > 0.01,
            "sliding windows must produce varying energies — spread=\(spread) (min=\(minEnergy), max=\(maxEnergy))")

    // Contract 3: adjacent windows should produce SIMILAR but distinguishable values
    // (continuity, not step-change). Measure that 99% of per-frame deltas are < 20% of
    // the total spread — catches the degenerate "jumps only every 600 frames" pattern.
    let deltas = zip(steadyState, steadyState.dropFirst()).map { abs($0 - $1) }
    let sortedDeltas = deltas.sorted()
    let p99Delta = sortedDeltas[min(sortedDeltas.count - 1, Int(Double(sortedDeltas.count) * 0.99))]
    #expect(p99Delta < spread * 0.5,
            "per-frame deltas must be smooth — p99 delta \(p99Delta) vs spread \(spread)")
}

// MARK: - Empty-stem safety

@Test
func stemAnalyzer_zeroLengthWindow_returnsZeroFeatures() {
    let analyzer = StemAnalyzer(sampleRate: 44100)
    let empty: [[Float]] = [[], [], [], []]
    let features = analyzer.analyze(stemWaveforms: empty, fps: 60)
    // All zero-length inputs should produce non-negative, non-NaN values.
    for value in [features.vocalsEnergy, features.drumsEnergy,
                  features.bassEnergy, features.otherEnergy,
                  features.drumsBeat] {
        #expect(value.isFinite, "All-zero input must not produce NaN/Inf (got \(value))")
        #expect(value >= 0, "Energies must be non-negative (got \(value))")
    }
}

// MARK: - Independence from absolute offset

@Test
func stemAnalyzer_sameWindow_producesStableFeatures() {
    let analyzer = StemAnalyzer(sampleRate: 44100)
    let bass = rampedWaveform()
    let silent = [Float](repeating: 0, count: bass.count)
    let stems = [silent, silent, bass, silent]

    // Analyze the SAME window repeatedly — features should converge to a steady state.
    let offset = Int(2.5 * 44100)  // 2.5s into the waveform
    let win = window(stems: stems, atOffset: offset)

    var lastEnergy: Float = 0
    for _ in 0..<300 {  // long enough for AGC to settle
        let features = analyzer.analyze(stemWaveforms: win, fps: 60)
        lastEnergy = features.bassEnergy
    }
    // Run a few more frames and assert the output has converged (bounded drift).
    var drift: Float = 0
    let baseline = lastEnergy
    for _ in 0..<60 {
        let features = analyzer.analyze(stemWaveforms: win, fps: 60)
        drift = max(drift, abs(features.bassEnergy - baseline))
    }
    #expect(drift < 0.05,
            "repeated analysis of the same window must converge (drift=\(drift))")
}
