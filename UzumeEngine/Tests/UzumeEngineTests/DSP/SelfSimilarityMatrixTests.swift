// SelfSimilarityMatrixTests — Unit tests for the cosine similarity ring buffer.
// Uses synthetic feature vectors with known similarity properties.

import Testing
import Foundation
@testable import DSP

// MARK: - Frame Management

@Test func selfSimilarity_addFrame_matrixGrows() {
    let matrix = SelfSimilarityMatrix(maxHistory: 10, featureDim: 4)
    #expect(matrix.frameCount == 0, "Fresh matrix should have 0 frames")

    matrix.addFrame([1, 0, 0, 0])
    #expect(matrix.frameCount == 1)

    matrix.addFrame([0, 1, 0, 0])
    matrix.addFrame([0, 0, 1, 0])
    matrix.addFrame([0, 0, 0, 1])
    matrix.addFrame([1, 1, 0, 0])
    #expect(matrix.frameCount == 5, "After 5 adds, frameCount should be 5")
}

// MARK: - Similarity

@Test func selfSimilarity_identicalFrames_is1() {
    let matrix = SelfSimilarityMatrix(maxHistory: 10, featureDim: 4)
    let vec: [Float] = [0.5, 0.3, 0.8, 0.1]

    matrix.addFrame(vec)
    matrix.addFrame(vec)

    let sim = matrix.similarity(frameA: 0, frameB: 1)
    #expect(abs(sim - 1.0) < 1e-5,
            "Cosine similarity of identical vectors should be 1.0, got \(sim)")
}

@Test func selfSimilarity_orthogonalFrames_isNear0() {
    let matrix = SelfSimilarityMatrix(maxHistory: 10, featureDim: 4)

    matrix.addFrame([1, 0, 0, 0])
    matrix.addFrame([0, 1, 0, 0])

    let sim = matrix.similarity(frameA: 0, frameB: 1)
    #expect(abs(sim) < 1e-5,
            "Cosine similarity of orthogonal vectors should be ~0, got \(sim)")
}

// MARK: - Ring Buffer

@Test func selfSimilarity_ringBuffer_capsAtMaxHistory() {
    let matrix = SelfSimilarityMatrix(maxHistory: 10, featureDim: 4)

    // Add 15 frames — should cap at 10.
    for i in 0..<15 {
        // Each frame is unique: [i, 0, 0, 0].
        matrix.addFrame([Float(i), 0, 0, 0])
    }

    #expect(matrix.frameCount == 10,
            "After 15 adds with maxHistory=10, frameCount should be 10")

    // Frame 0 (oldest) should now be what was originally frame 5
    // (frames 0–4 were overwritten). Verify by checking the feature vector.
    if let oldest = matrix.featureVector(at: 0) {
        #expect(oldest[0] == 5.0,
                "Oldest frame should be from the 6th add (value 5), got \(oldest[0])")
    }
}

// MARK: - Manual Calculation Verification

@Test func selfSimilarity_cosineSimilarity_matchesManualCalculation() {
    let matrix = SelfSimilarityMatrix(maxHistory: 10, featureDim: 3)

    let vecA: [Float] = [3, 4, 0]
    let vecB: [Float] = [4, 3, 0]
    matrix.addFrame(vecA)
    matrix.addFrame(vecB)

    // Manual: dot = 3*4 + 4*3 + 0 = 24
    // normA = sqrt(9 + 16 + 0) = 5
    // normB = sqrt(16 + 9 + 0) = 5
    // cosine = 24 / (5 * 5) = 0.96
    let expected: Float = 24.0 / 25.0
    let sim = matrix.similarity(frameA: 0, frameB: 1)

    #expect(abs(sim - expected) < 1e-5,
            "Cosine similarity should be \(expected), got \(sim)")
}
