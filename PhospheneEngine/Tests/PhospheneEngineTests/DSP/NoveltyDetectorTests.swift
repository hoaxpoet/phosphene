// NoveltyDetectorTests — Unit tests for section boundary detection.
// Uses synthetic similarity matrices with known section structure.

import Testing
import Foundation
@testable import DSP

// MARK: - No Change

@Test func noveltyDetect_noChange_noPeaks() {
    let matrix = SelfSimilarityMatrix(maxHistory: 200, featureDim: 4)
    let detector = NoveltyDetector(
        maxHistory: 200, kernelHalfWidth: 8,
        minPeakDistance: 30, thresholdMultiplier: 1.5
    )

    // Feed 200 identical frames — no section change.
    let vec: [Float] = [0.5, 0.3, 0.8, 0.1]
    for _ in 0..<200 {
        matrix.addFrame(vec)
    }

    let boundaries = detector.detect(
        similarityMatrix: matrix, currentTime: 3.33, fps: 60
    )
    #expect(boundaries.isEmpty,
            "Constant features should produce no boundaries, got \(boundaries.count)")
}

// MARK: - Abrupt Change

@Test func noveltyDetect_abruptChange_peakDetected() {
    let matrix = SelfSimilarityMatrix(maxHistory: 200, featureDim: 4)
    let detector = NoveltyDetector(
        maxHistory: 200, kernelHalfWidth: 8,
        minPeakDistance: 30, thresholdMultiplier: 1.0
    )

    // Section A: 100 frames.
    let vecA: [Float] = [1, 0, 0, 0]
    for _ in 0..<100 {
        matrix.addFrame(vecA)
    }

    // Section B: 100 frames (orthogonal to A).
    let vecB: [Float] = [0, 1, 0, 0]
    for _ in 0..<100 {
        matrix.addFrame(vecB)
    }

    let boundaries = detector.detect(
        similarityMatrix: matrix, currentTime: 3.33, fps: 60
    )
    #expect(!boundaries.isEmpty,
            "Sharp A→B transition should produce at least 1 boundary")

    // The boundary should be near frame 100.
    if let boundary = boundaries.first {
        let distance = abs(boundary.frameIndex - 100)
        #expect(distance < 15,
                "Boundary should be near frame 100, got frame \(boundary.frameIndex)")
    }
}

// MARK: - Gradual Change

@Test func noveltyDetect_gradualChange_noPeak() {
    let matrix = SelfSimilarityMatrix(maxHistory: 200, featureDim: 4)
    let detector = NoveltyDetector(
        maxHistory: 200, kernelHalfWidth: 8,
        minPeakDistance: 30, thresholdMultiplier: 1.5
    )

    // Linear interpolation from A to B over 200 frames.
    for i in 0..<200 {
        let t = Float(i) / 199.0
        let vec: [Float] = [1.0 - t, t, 0, 0]
        matrix.addFrame(vec)
    }

    let boundaries = detector.detect(
        similarityMatrix: matrix, currentTime: 3.33, fps: 60
    )
    #expect(boundaries.isEmpty,
            "Gradual transition should not produce sharp boundaries, got \(boundaries.count)")
}

// MARK: - Adaptive Threshold

@Test func noveltyDetect_adaptiveThreshold_ignoresMinorFluctuations() {
    let matrix = SelfSimilarityMatrix(maxHistory: 200, featureDim: 4)
    let detector = NoveltyDetector(
        maxHistory: 200, kernelHalfWidth: 8,
        minPeakDistance: 30, thresholdMultiplier: 1.5
    )

    // Mostly constant with tiny perturbations that don't create periodic structure.
    for i in 0..<200 {
        let noise = sinf(Float(i) * 0.1) * 0.005  // Very small smooth wobble.
        let vec: [Float] = [0.5 + noise, 0.3 - noise, 0.8, 0.1]
        matrix.addFrame(vec)
    }

    let boundaries = detector.detect(
        similarityMatrix: matrix, currentTime: 3.33, fps: 60
    )
    #expect(boundaries.isEmpty,
            "Minor fluctuations should not trigger boundaries, got \(boundaries.count)")
}

// MARK: - Determinism

@Test func noveltyDetect_deterministic() {
    func runDetection() -> [NoveltyDetector.Boundary] {
        let matrix = SelfSimilarityMatrix(maxHistory: 200, featureDim: 4)
        let detector = NoveltyDetector(
            maxHistory: 200, kernelHalfWidth: 8,
            minPeakDistance: 30, thresholdMultiplier: 1.0
        )

        let vecA: [Float] = [1, 0, 0, 0]
        let vecB: [Float] = [0, 0, 1, 0]
        for _ in 0..<100 { matrix.addFrame(vecA) }
        for _ in 0..<100 { matrix.addFrame(vecB) }

        return detector.detect(
            similarityMatrix: matrix, currentTime: 3.33, fps: 60
        )
    }

    let run1 = runDetection()
    let run2 = runDetection()

    #expect(run1.count == run2.count,
            "Same input should produce same boundary count: \(run1.count) vs \(run2.count)")

    for i in 0..<min(run1.count, run2.count) {
        #expect(run1[i].frameIndex == run2[i].frameIndex,
                "Boundary \(i) frame should match: \(run1[i].frameIndex) vs \(run2[i].frameIndex)")
        #expect(abs(run1[i].noveltyScore - run2[i].noveltyScore) < 1e-6,
                "Boundary \(i) score should match")
    }
}
