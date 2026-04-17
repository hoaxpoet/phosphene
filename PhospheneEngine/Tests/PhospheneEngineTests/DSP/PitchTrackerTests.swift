// PitchTrackerTests — unit tests for YIN-based vocal pitch tracking (MV-3c, D-028).
//
// Four contracts:
//   1. Pure 440 Hz sine → estimated pitch within ±5 cents of 440 Hz.
//   2. Pure 220 Hz sine → estimated pitch within ±5 cents of 220 Hz.
//   3. Silent input → 0 Hz, confidence < 0.4.
//   4. Random noise (no pitch) → 0 Hz or confidence < 0.6.

import Foundation
import Testing
@testable import DSP

// MARK: - Helpers

/// ±N cents tolerance check: |log2(est/ref)| × 1200 < centsThreshold.
private func withinCents(_ estimatedHz: Float, reference: Float, centsThreshold: Float) -> Bool {
    guard estimatedHz > 0 && reference > 0 else { return false }
    let cents = abs(log2(estimatedHz / reference)) * 1200
    return cents < centsThreshold
}

/// Generates exactly `count` samples of a pure sine at `hz`.
private func pureSine(hz: Float, sampleRate: Float = 44100, count: Int = 2048) -> [Float] {
    (0..<count).map { i in
        0.7 * sin(2 * .pi * hz * Float(i) / sampleRate)
    }
}

/// A deterministic pseudo-random sequence with no periodic structure.
private func randomNoise(count: Int = 2048, seed: UInt64 = 42) -> [Float] {
    var state = seed
    return (0..<count).map { _ in
        state = state &* 6364136223846793005 &+ 1442695040888963407
        let bits = UInt32((state >> 33) & 0xFFFFFF)
        return (Float(bits) / Float(0xFFFFFF)) * 2 - 1
    }
}

// MARK: - Tests

@Test
func pitchTracker_440Hz_withinFiveCents() {
    let tracker = PitchTracker(sampleRate: 44100)
    let waveform = pureSine(hz: 440, sampleRate: 44100, count: 2048)

    // EMA decay = 0.8; after 50 frames: ema ≈ rawHz × (1 - 0.8^50) ≈ rawHz.
    var result = (hz: Float(0), confidence: Float(0))
    for _ in 0..<50 {
        result = tracker.process(waveform: waveform)
    }

    #expect(result.hz > 0, "440 Hz sine should be detected as voiced (got 0 Hz)")
    #expect(withinCents(result.hz, reference: 440, centsThreshold: 5),
            "440 Hz sine should be within 5 cents, got \(result.hz) Hz")
    #expect(result.confidence >= 0.6,
            "440 Hz sine should have confidence ≥ 0.6, got \(result.confidence)")
}

@Test
func pitchTracker_220Hz_withinFiveCents() {
    let tracker = PitchTracker(sampleRate: 44100)
    let waveform = pureSine(hz: 220, sampleRate: 44100, count: 2048)

    var result = (hz: Float(0), confidence: Float(0))
    for _ in 0..<50 {
        result = tracker.process(waveform: waveform)
    }

    #expect(result.hz > 0, "220 Hz sine should be detected as voiced (got 0 Hz)")
    #expect(withinCents(result.hz, reference: 220, centsThreshold: 5),
            "220 Hz sine should be within 5 cents, got \(result.hz) Hz")
    #expect(result.confidence >= 0.6,
            "220 Hz sine should have confidence ≥ 0.6, got \(result.confidence)")
}

@Test
func pitchTracker_silence_givesZeroHzLowConfidence() {
    let tracker = PitchTracker(sampleRate: 44100)
    let silence = [Float](repeating: 0, count: 2048)

    var result = (hz: Float(1), confidence: Float(1))
    for _ in 0..<5 {
        result = tracker.process(waveform: silence)
    }

    #expect(result.hz == 0, "Silent input should yield 0 Hz, got \(result.hz)")
    #expect(result.confidence < 0.4,
            "Silent input confidence should be < 0.4, got \(result.confidence)")
}

@Test
func pitchTracker_randomNoise_lowConfidenceOrZeroHz() {
    let tracker = PitchTracker(sampleRate: 44100)
    let noise = randomNoise(count: 2048)

    var result = (hz: Float(0), confidence: Float(1))
    for _ in 0..<5 {
        result = tracker.process(waveform: noise)
    }

    // Random noise has no periodic structure; YIN should either find no dip below
    // threshold (→ 0 Hz) or report low confidence.
    let isUnvoiced = result.hz == 0 || result.confidence < 0.6
    #expect(isUnvoiced,
            "Random noise should yield 0 Hz or confidence < 0.6, got hz=\(result.hz) conf=\(result.confidence)")
}
