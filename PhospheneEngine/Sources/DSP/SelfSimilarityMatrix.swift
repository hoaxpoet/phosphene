// SelfSimilarityMatrix — Ring buffer of feature vectors with cosine similarity.
// Maintains a fixed-capacity history of per-frame features and computes pairwise
// cosine similarity via vDSP. Used by NoveltyDetector for section boundary detection.

import Foundation
import Accelerate
import os.log

private let logger = Logger(subsystem: "com.phosphene.dsp", category: "SelfSimilarityMatrix")

// MARK: - SelfSimilarityMatrix

/// Ring buffer of feature vectors supporting cosine similarity queries.
///
/// Stores up to `maxHistory` frames of `featureDim`-dimensional feature vectors
/// (typically 12 chroma + 4 spectral summary = 16). All similarity computations
/// use vDSP for vectorized dot products.
///
/// Usage:
/// ```swift
/// let matrix = SelfSimilarityMatrix()
/// matrix.addFrame(chromaAndSpectral)  // 16-float vector
/// let sim = matrix.similarity(frameA: 0, frameB: 1)  // cosine similarity
/// ```
public final class SelfSimilarityMatrix: @unchecked Sendable {

    // MARK: - Properties

    /// Maximum number of frames stored before ring buffer wraps.
    public let maxHistory: Int

    /// Dimensionality of each feature vector.
    public let featureDim: Int

    /// Flat ring buffer: `maxHistory * featureDim` floats.
    private var buffer: [Float]

    /// Next write position in the ring buffer (0..<maxHistory).
    private var head: Int = 0

    /// Number of frames stored (0...maxHistory).
    private var storedCount: Int = 0

    /// Pre-allocated scratch for similarity computation.
    private var scratchA: [Float]
    private var scratchB: [Float]

    /// Thread safety.
    private let lock = NSLock()

    // MARK: - Init

    /// Create a self-similarity matrix with the given capacity and feature dimension.
    ///
    /// - Parameters:
    ///   - maxHistory: Maximum frames to store (default 600 ≈ 10s at 60fps).
    ///   - featureDim: Dimension of each feature vector (default 16).
    public init(maxHistory: Int = 600, featureDim: Int = 16) {
        self.maxHistory = maxHistory
        self.featureDim = featureDim
        self.buffer = [Float](repeating: 0, count: maxHistory * featureDim)
        self.scratchA = [Float](repeating: 0, count: featureDim)
        self.scratchB = [Float](repeating: 0, count: featureDim)

        logger.info("SelfSimilarityMatrix created: maxHistory=\(maxHistory), featureDim=\(featureDim)")
    }

    // MARK: - Frame Management

    /// Add a feature vector to the ring buffer.
    ///
    /// - Parameter features: Feature vector of length `featureDim`.
    ///   Silently ignored if length does not match.
    public func addFrame(_ features: [Float]) {
        guard features.count == featureDim else { return }

        lock.lock()
        let offset = head * featureDim
        for i in 0..<featureDim {
            buffer[offset + i] = features[i]
        }
        head = (head + 1) % maxHistory
        if storedCount < maxHistory {
            storedCount += 1
        }
        lock.unlock()
    }

    /// Number of frames currently stored.
    public var frameCount: Int {
        lock.lock()
        let count = storedCount
        lock.unlock()
        return count
    }

    // MARK: - Similarity

    /// Cosine similarity between two frames by logical index.
    ///
    /// Index 0 is the oldest stored frame, `frameCount - 1` is the newest.
    /// Returns 0 if either index is out of range.
    ///
    /// - Parameters:
    ///   - frameA: Logical index of first frame.
    ///   - frameB: Logical index of second frame.
    /// - Returns: Cosine similarity in range [-1, 1], or 0 if invalid.
    public func similarity(frameA: Int, frameB: Int) -> Float {
        lock.lock()
        defer { lock.unlock() }

        guard frameA >= 0, frameA < storedCount,
              frameB >= 0, frameB < storedCount else {
            return 0
        }

        let physA = physicalIndex(for: frameA)
        let physB = physicalIndex(for: frameB)
        let offsetA = physA * featureDim
        let offsetB = physB * featureDim

        return cosineSimilarity(
            buffer,
            offsetA: offsetA,
            buffer,
            offsetB: offsetB,
            count: featureDim
        )
    }

    /// Compute similarity between a logical frame index and a raw feature vector.
    ///
    /// - Parameters:
    ///   - frameIndex: Logical index (0 = oldest).
    ///   - features: Feature vector of length `featureDim`.
    /// - Returns: Cosine similarity, or 0 if invalid.
    public func similarityWithVector(frameIndex: Int, features: [Float]) -> Float {
        lock.lock()
        defer { lock.unlock() }

        guard frameIndex >= 0, frameIndex < storedCount,
              features.count == featureDim else {
            return 0
        }

        let phys = physicalIndex(for: frameIndex)
        let offset = phys * featureDim

        // Copy features into scratch to avoid aliasing issues.
        for i in 0..<featureDim { scratchA[i] = features[i] }

        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0

        buffer.withUnsafeBufferPointer { ptr in
            guard let bufferBase = ptr.baseAddress else { return }
            let base = bufferBase + offset
            vDSP_dotpr(base, 1, scratchA, 1, &dot, vDSP_Length(featureDim))
            vDSP_svesq(base, 1, &normA, vDSP_Length(featureDim))
        }
        vDSP_svesq(scratchA, 1, &normB, vDSP_Length(featureDim))

        let denom = sqrtf(normA * normB)
        return denom > 1e-10 ? dot / denom : 0
    }

    /// Get the feature vector at a logical frame index.
    ///
    /// - Parameter frameIndex: Logical index (0 = oldest, frameCount-1 = newest).
    /// - Returns: Feature vector copy, or nil if index is out of range.
    public func featureVector(at frameIndex: Int) -> [Float]? {
        lock.lock()
        defer { lock.unlock() }

        guard frameIndex >= 0, frameIndex < storedCount else { return nil }

        let phys = physicalIndex(for: frameIndex)
        let offset = phys * featureDim
        return Array(buffer[offset..<(offset + featureDim)])
    }

    // MARK: - Reset

    /// Clear all stored frames.
    public func reset() {
        lock.lock()
        head = 0
        storedCount = 0
        // Zero out buffer for clean state.
        for i in 0..<buffer.count { buffer[i] = 0 }
        lock.unlock()
    }

    // MARK: - Private

    /// Convert a logical index (0 = oldest) to a physical ring buffer index.
    private func physicalIndex(for logicalIndex: Int) -> Int {
        if storedCount < maxHistory {
            return logicalIndex
        }
        return (head + logicalIndex) % maxHistory
    }

    /// Cosine similarity between two vectors stored in arrays at given offsets.
    private func cosineSimilarity(
        _ bufA: [Float], offsetA: Int,
        _ bufB: [Float], offsetB: Int,
        count: Int
    ) -> Float {
        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0

        bufA.withUnsafeBufferPointer { ptrA in
            bufB.withUnsafeBufferPointer { ptrB in
                guard let aBase = ptrA.baseAddress, let bBase = ptrB.baseAddress else { return }
                let baseA = aBase + offsetA
                let baseB = bBase + offsetB
                vDSP_dotpr(baseA, 1, baseB, 1, &dot, vDSP_Length(count))
                vDSP_svesq(baseA, 1, &normA, vDSP_Length(count))
                vDSP_svesq(baseB, 1, &normB, vDSP_Length(count))
            }
        }

        let denom = sqrtf(normA * normB)
        return denom > 1e-10 ? dot / denom : 0
    }
}
