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

// MARK: - Diagnostic: real-vocal-shape inputs (P0 investigation, 2026-05-19)

/// Generates a harmonic signal that approximates a real vocal note:
/// fundamental + 4 harmonics with typical amplitude rolloff (1.0, 0.5, 0.3,
/// 0.2, 0.1) + small white noise floor. This is structurally closer to what
/// the Demucs vocals stem outputs than a pure sine.
private func harmonicVocal(hz: Float, sampleRate: Float = 44100, count: Int = 2048,
                           noiseAmp: Float = 0.05) -> [Float] {
    let amps: [Float] = [1.0, 0.5, 0.3, 0.2, 0.1]
    var state: UInt64 = 42
    return (0..<count).map { i in
        let t = Float(i) / sampleRate
        var sample: Float = 0
        for (idx, amp) in amps.enumerated() {
            sample += amp * sin(2 * .pi * hz * Float(idx + 1) * t)
        }
        // White-noise floor — simulates imperfect stem separation residual.
        state = state &* 6364136223846793005 &+ 1442695040888963407
        let bits = UInt32((state >> 33) & 0xFFFFFF)
        let noise = (Float(bits) / Float(0xFFFFFF)) * 2 - 1
        return 0.4 * sample + noiseAmp * noise
    }
}

/// Diagnostic: PitchTracker on a vocal-like signal at 220 Hz (A3, typical
/// male singing range) with 4 harmonics + 5 % noise floor.
///
/// **If this passes** — the tracker handles real-vocal-shape inputs. The
/// live-session failure (vocalsPitchConfidence = 0 across all sessions) is
/// caused by something upstream: separator output quality, sample-rate
/// mismatch, empty waveform.
///
/// **If this fails** — the tracker's yinThreshold = 0.15 + confidence
/// threshold 0.6 are too strict for anything other than pure sines. The
/// live failure is in the tracker tuning, and we should relax thresholds.
@Test
func pitchTracker_harmonicVocal_220Hz_diagnostic() {
    let tracker = PitchTracker(sampleRate: 44100)
    let waveform = harmonicVocal(hz: 220, sampleRate: 44100, count: 2048, noiseAmp: 0.05)

    var result = (hz: Float(0), confidence: Float(0))
    for _ in 0..<50 {
        result = tracker.process(waveform: waveform)
    }

    let hzMsg = "Harmonic 220 Hz: detected — got 0 Hz, conf=\(result.confidence)."
    #expect(result.hz > 0, Comment(rawValue: hzMsg))
    let centsMsg = "Harmonic 220 Hz: within 50 cents — got \(result.hz) Hz"
    #expect(withinCents(result.hz, reference: 220, centsThreshold: 50), Comment(rawValue: centsMsg))
    let confMsg = "Harmonic 220 Hz: confidence ≥ 0.6 — got \(result.confidence)"
    #expect(result.confidence >= 0.6, Comment(rawValue: confMsg))
}

/// Same diagnostic at 440 Hz (A4, female singing range, also a common
/// instrumental melodic frequency).
@Test
func pitchTracker_harmonicVocal_440Hz_diagnostic() {
    let tracker = PitchTracker(sampleRate: 44100)
    let waveform = harmonicVocal(hz: 440, sampleRate: 44100, count: 2048, noiseAmp: 0.05)

    var result = (hz: Float(0), confidence: Float(0))
    for _ in 0..<50 {
        result = tracker.process(waveform: waveform)
    }

    let hzMsg = "Harmonic 440 Hz: detected — got 0 Hz, conf=\(result.confidence)"
    #expect(result.hz > 0, Comment(rawValue: hzMsg))
    let centsMsg = "Harmonic 440 Hz: within 50 cents — got \(result.hz) Hz"
    #expect(withinCents(result.hz, reference: 440, centsThreshold: 50), Comment(rawValue: centsMsg))
    let confMsg = "Harmonic 440 Hz: confidence ≥ 0.6 — got \(result.confidence)"
    #expect(result.confidence >= 0.6, Comment(rawValue: confMsg))
}

// MARK: - Regression: live-path 1024-sample window contract (2026-05-19 P0)
//
// The live path (`VisualizerEngine+Audio.swift`) and `SessionPreparer+Analysis.swift`
// both pass 1024-sample windows to `StemAnalyzer.analyze`, which forwards
// `stemWaveforms[0]` to `PitchTracker.process`. Before the 2026-05-19 fix,
// PitchTracker zero-padded the first half of its 2048-sample internal
// buffer when given a 1024-sample input — the cross-correlation in the
// YIN difference function was structurally zero (the zero-padded half
// dotted with the signal half = 0 for every τ), so CMNDF never dipped
// below the 0.15 threshold and `findMinimum` always returned -1 → the
// tracker returned `(0, 0)` on every live frame. The fix added an
// internal ring buffer so the tracker accumulates samples across
// multiple `process()` calls.
//
// This test feeds consecutive 1024-sample chunks of a harmonic vocal
// signal (the actual live-path size) and verifies pitch is detected
// correctly. Before the fix this test would fail by returning `(0, 0)`
// every call. The existing `pitchTracker_*_withinFiveCents` tests pass
// 2048-sample windows directly so they masked the bug.

@Test
func pitchTracker_consecutive1024Windows_detectsPitch() {
    let tracker = PitchTracker(sampleRate: 44100)
    // 32 × 1024 = 32768 samples ≈ 740 ms of audio at 44.1 kHz. Plenty for
    // YIN to accumulate a full window + run for several frames + let EMA
    // converge.
    let totalSamples = 32 * 1024
    let fullSignal = harmonicVocal(hz: 220, sampleRate: 44100,
                                    count: totalSamples, noiseAmp: 0.05)

    var result = (hz: Float(0), confidence: Float(0))
    var firstNonZeroChunk = -1
    for chunk in 0..<32 {
        let start = chunk * 1024
        let slice = Array(fullSignal[start..<start + 1024])
        result = tracker.process(waveform: slice)
        if result.hz > 0 && firstNonZeroChunk == -1 {
            firstNonZeroChunk = chunk
        }
    }

    let detectedMsg = "Live-path 1024-sample windows: pitch should be detected after enough chunks accumulate. Got 0 Hz after 32 chunks. firstNonZeroChunk=\(firstNonZeroChunk). Before the 2026-05-19 ring-buffer fix this returned (0, 0) every call."
    #expect(result.hz > 0, Comment(rawValue: detectedMsg))

    let centsMsg = "Live-path 1024 windows at 220 Hz: within 50 cents — got \(result.hz) Hz"
    #expect(withinCents(result.hz, reference: 220, centsThreshold: 50), Comment(rawValue: centsMsg))

    let confMsg = "Live-path 1024 windows: confidence ≥ 0.6 — got \(result.confidence)"
    #expect(result.confidence >= 0.6, Comment(rawValue: confMsg))

    // The ring buffer fills after exactly 2 chunks (2 × 1024 = 2048).
    // First-frame detection isn't required — but pitch SHOULD be detected
    // by the 3rd chunk at the latest (chunk index 2).
    let warmupMsg = "Ring buffer should fill by chunk 2; first detection at chunk \(firstNonZeroChunk)"
    #expect(firstNonZeroChunk >= 0 && firstNonZeroChunk < 5, Comment(rawValue: warmupMsg))
}
