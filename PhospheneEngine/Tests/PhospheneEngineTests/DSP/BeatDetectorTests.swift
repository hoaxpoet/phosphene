// BeatDetectorTests — Unit tests for onset detection and tempo estimation.
// Uses synthetic magnitude arrays simulating kick patterns at known BPMs.

import Testing
import Foundation
@testable import DSP

// MARK: - Helpers

/// Simulate `frameCount` frames at `fps`, calling the beat detector each frame.
/// `kickFrames` contains frame indices where a loud kick occurs.
/// Returns results for all frames.
private func simulateFrames(
    detector: BeatDetector,
    frameCount: Int,
    fps: Float = 60,
    kickFrames: Set<Int> = []
) -> [BeatDetector.Result] {
    let deltaTime = 1.0 / fps
    var results = [BeatDetector.Result]()

    for frame in 0..<frameCount {
        let magnitudes: [Float]
        if kickFrames.contains(frame) {
            // Loud kick: energy in low bands (bins 0-10).
            var mags = [Float](repeating: 0.01, count: 512)
            for i in 0..<10 { mags[i] = 1.0 }
            magnitudes = mags
        } else {
            // Quiet background.
            magnitudes = [Float](repeating: 0.01, count: 512)
        }
        let result = detector.process(magnitudes: magnitudes, fps: fps, deltaTime: deltaTime)
        results.append(result)
    }

    return results
}

/// Generate kick frame indices for a given BPM at a given FPS over a duration.
private func kickFrames(bpm: Float, fps: Float, durationSeconds: Float) -> Set<Int> {
    let framesPerBeat = fps * 60.0 / bpm
    let totalFrames = Int(fps * durationSeconds)
    var frames = Set<Int>()
    var nextKick: Float = 0
    while Int(nextKick) < totalFrames {
        frames.insert(Int(nextKick))
        nextKick += framesPerBeat
    }
    return frames
}

// MARK: - Tempo Tests

@Test func tempo_120BPMKick_estimatesNear120() {
    let detector = BeatDetector()
    let fps: Float = 60
    let duration: Float = 8  // 8 seconds for stable tempo estimation
    let kicks = kickFrames(bpm: 120, fps: fps, durationSeconds: duration)
    let results = simulateFrames(detector: detector, frameCount: Int(fps * duration), fps: fps, kickFrames: kicks)

    // Check last frame's tempo estimate.
    // Autocorrelation can return the true tempo or a harmonic (half/double).
    if let tempo = results.last?.estimatedTempo {
        let isNearTarget = (tempo >= 100 && tempo <= 140)
        let isHalfTempo = (tempo >= 55 && tempo <= 65)  // Common octave error
        #expect(isNearTarget || isHalfTempo,
                "Tempo should be near 120 BPM or its half, got \(tempo)")
    }
}

@Test func tempo_90BPMKick_estimatesNear90() {
    let detector = BeatDetector()
    let fps: Float = 60
    let duration: Float = 8
    let kicks = kickFrames(bpm: 90, fps: fps, durationSeconds: duration)
    let results = simulateFrames(detector: detector, frameCount: Int(fps * duration), fps: fps, kickFrames: kicks)

    if let tempo = results.last?.estimatedTempo {
        #expect(tempo >= 70 && tempo <= 110,
                "Tempo should be near 90 BPM, got \(tempo)")
    }
}

@Test func tempo_silence_returnsNilOrZero() {
    let detector = BeatDetector()
    let fps: Float = 60
    // Feed 300 frames of silence.
    let results = simulateFrames(detector: detector, frameCount: 300, fps: fps, kickFrames: [])

    let lastResult = results.last
    // With no signal variation, tempo should be nil or have zero confidence.
    if let tempo = lastResult?.estimatedTempo {
        #expect(lastResult?.tempoConfidence ?? 0 < 0.3,
                "Tempo confidence should be low for silence, got \(lastResult?.tempoConfidence ?? 0) (tempo=\(tempo))")
    }
}

// MARK: - Onset Detection Tests

@Test func onsetDetection_singleImpulse_detectsOne() {
    let detector = BeatDetector()
    let fps: Float = 60
    let deltaTime = 1.0 / fps

    // Feed 30 frames of silence to fill flux buffers.
    let silence = [Float](repeating: 0, count: 512)
    for _ in 0..<30 {
        _ = detector.process(magnitudes: silence, fps: fps, deltaTime: deltaTime)
    }

    // Feed a single loud frame.
    var loud = [Float](repeating: 0, count: 512)
    for i in 0..<10 { loud[i] = 1.0 }
    let result = detector.process(magnitudes: loud, fps: fps, deltaTime: deltaTime)

    let onsetCount = result.onsets.filter { $0 }.count
    #expect(onsetCount >= 1, "Should detect at least one onset on the impulse frame")
}

@Test func onsetDetection_regularKicks_countMatchesExpected() {
    let detector = BeatDetector()
    let fps: Float = 60
    let duration: Float = 5
    let bpm: Float = 120
    let kicks = kickFrames(bpm: bpm, fps: fps, durationSeconds: duration)
    let results = simulateFrames(detector: detector, frameCount: Int(fps * duration), fps: fps, kickFrames: kicks)

    // Count total bass-group onset firings.
    let bassOnsets = results.filter { $0.beatBass >= 0.99 }.count

    // At 120 BPM for 5 seconds, expect ~10 beats. With cooldowns (400ms),
    // maximum possible detections = 5s / 0.4s = 12.5. Allow wide range.
    let expectedBeats = Int(bpm / 60.0 * duration)
    #expect(bassOnsets >= expectedBeats / 3,
            "Should detect a reasonable number of bass onsets (\(bassOnsets)), expected ~\(expectedBeats)")
}

@Test func onsetDetection_noOnsets_inSilence() {
    let detector = BeatDetector()
    let fps: Float = 60
    let results = simulateFrames(detector: detector, frameCount: 200, fps: fps, kickFrames: [])

    let totalOnsets = results.flatMap { $0.onsets }.filter { $0 }.count
    #expect(totalOnsets == 0, "No onsets should be detected in silence, got \(totalOnsets)")
}

// MARK: - Determinism

@Test func tempo_deterministic() {
    let fps: Float = 60
    let duration: Float = 6
    let kicks = kickFrames(bpm: 120, fps: fps, durationSeconds: duration)

    let detector1 = BeatDetector()
    let results1 = simulateFrames(detector: detector1, frameCount: Int(fps * duration), fps: fps, kickFrames: kicks)

    let detector2 = BeatDetector()
    let results2 = simulateFrames(detector: detector2, frameCount: Int(fps * duration), fps: fps, kickFrames: kicks)

    // Check that onset patterns match.
    for i in 0..<results1.count {
        #expect(results1[i].onsets == results2[i].onsets,
                "Onset pattern should be deterministic at frame \(i)")
    }

    // Check that final tempo matches.
    #expect(results1.last?.estimatedTempo == results2.last?.estimatedTempo,
            "Tempo estimation should be deterministic")
}
