// NoveltyDetector — Section boundary detection via checkerboard kernel convolution.
// Convolves a checkerboard kernel along the self-similarity matrix diagonal to
// produce a novelty curve, then peak-picks with an adaptive threshold.

import Foundation
import Accelerate
import os.log

private let logger = Logger(subsystem: "com.phosphene.dsp", category: "NoveltyDetector")

// MARK: - NoveltyDetector

/// Detects section boundaries from a self-similarity matrix.
///
/// Algorithm:
/// 1. For each frame, compute a checkerboard kernel response along the diagonal
///    of the similarity matrix: `novelty = avg(within-section) - avg(cross-section)`.
/// 2. Peak-pick with adaptive threshold (mean + k × stddev).
/// 3. Enforce minimum peak distance to avoid spurious detections.
///
/// Usage:
/// ```swift
/// let detector = NoveltyDetector()
/// let newBoundaries = detector.detect(similarityMatrix: matrix, currentTime: t, fps: 60)
/// let allBoundaries = detector.boundaries
/// ```
public final class NoveltyDetector: @unchecked Sendable {

    // MARK: - Boundary

    /// A detected section boundary.
    public struct Boundary: Sendable, Equatable {
        /// Logical frame index in the similarity matrix where the boundary was detected.
        public var frameIndex: Int
        /// Timestamp in seconds since capture start.
        public var timestamp: Float
        /// Novelty score at this boundary (higher = sharper transition).
        public var noveltyScore: Float
    }

    // MARK: - Properties

    /// Half-width of the checkerboard kernel (full kernel = 2W × 2W).
    private let kernelHalfWidth: Int

    /// Minimum frames between detected peaks.
    private let minPeakDistance: Int

    /// Threshold multiplier: peaks must exceed mean + k × stddev.
    private let thresholdMultiplier: Float

    /// Maximum history for novelty curve allocation.
    private let maxHistory: Int

    /// Pre-allocated novelty curve buffer.
    private var noveltyCurve: [Float]

    /// All detected boundaries so far.
    private var detectedBoundaries: [Boundary] = []

    /// Number of boundaries already reported (for incremental detection).
    private var reportedCount: Int = 0

    /// Thread safety.
    private let lock = NSLock()

    // MARK: - Init

    /// Create a novelty detector.
    ///
    /// - Parameters:
    ///   - maxHistory: Maximum frame history (matches SelfSimilarityMatrix).
    ///   - kernelHalfWidth: Half-width of checkerboard kernel (default 8).
    ///   - minPeakDistance: Minimum frames between peaks (default 120 ≈ 2s at 60fps).
    ///   - thresholdMultiplier: Adaptive threshold multiplier (default 1.5).
    public init(
        maxHistory: Int = 600,
        kernelHalfWidth: Int = 8,
        minPeakDistance: Int = 120,
        thresholdMultiplier: Float = 1.5
    ) {
        self.maxHistory = maxHistory
        self.kernelHalfWidth = kernelHalfWidth
        self.minPeakDistance = minPeakDistance
        self.thresholdMultiplier = thresholdMultiplier
        self.noveltyCurve = [Float](repeating: 0, count: maxHistory)

        logger.info(
            """
            NoveltyDetector created: kernelHalfWidth=\(kernelHalfWidth), \
            minPeakDistance=\(minPeakDistance), threshold=\(thresholdMultiplier)
            """
        )
    }

    // MARK: - Detection

    /// Compute novelty curve and detect new boundaries.
    ///
    /// This is the expensive operation — call it periodically (every ~30 frames),
    /// not every frame.
    ///
    /// - Parameters:
    ///   - similarityMatrix: The self-similarity matrix to analyze.
    ///   - currentTime: Current timestamp for converting frame indices to seconds.
    ///   - fps: Current frame rate for timestamp conversion.
    /// - Returns: Newly detected boundaries since the last call.
    public func detect(
        similarityMatrix: SelfSimilarityMatrix,
        currentTime: Float,
        fps: Float
    ) -> [Boundary] {
        lock.lock()
        defer { lock.unlock() }

        let frameCount = similarityMatrix.frameCount
        let halfW = kernelHalfWidth

        // Need at least 2 × kernelHalfWidth frames for meaningful detection.
        guard frameCount >= halfW * 2 else { return [] }

        // Compute novelty curve via checkerboard kernel.
        let validRange = halfW..<(frameCount - halfW)
        for i in validRange {
            noveltyCurve[i] = checkerboardResponse(
                matrix: similarityMatrix, center: i, halfWidth: halfW
            )
        }

        // Compute adaptive threshold: mean + k × stddev over valid range.
        let validCount = validRange.count
        guard validCount > 0 else { return [] }

        var sum: Float = 0
        var sumSq: Float = 0
        for i in validRange {
            sum += noveltyCurve[i]
            sumSq += noveltyCurve[i] * noveltyCurve[i]
        }
        let mean = sum / Float(validCount)
        let variance = sumSq / Float(validCount) - mean * mean
        let stddev = sqrtf(max(variance, 0))
        let threshold = mean + thresholdMultiplier * stddev

        // Peak-picking: find local maxima above threshold with minimum distance.
        var peaks: [Boundary] = []
        for i in validRange {
            let val = noveltyCurve[i]
            guard val > threshold else { continue }

            // Local maximum check (must be greater than both neighbors).
            let prev = i > validRange.lowerBound ? noveltyCurve[i - 1] : 0
            let next = i < validRange.upperBound - 1 ? noveltyCurve[i + 1] : 0
            guard val >= prev, val >= next else { continue }

            // Minimum distance from last peak.
            if let lastPeak = peaks.last, i - lastPeak.frameIndex < minPeakDistance {
                // Keep the stronger peak.
                if val > lastPeak.noveltyScore {
                    peaks[peaks.count - 1] = Boundary(
                        frameIndex: i,
                        timestamp: timestampForFrame(
                            i,
                            currentTime: currentTime,
                            totalFrames: frameCount,
                            fps: fps
                        ),
                        noveltyScore: val
                    )
                }
                continue
            }

            // Minimum distance from previously detected boundaries.
            let tooCloseToExisting = detectedBoundaries.contains { existing in
                abs(existing.frameIndex - i) < minPeakDistance
            }
            if tooCloseToExisting { continue }

            peaks.append(Boundary(
                frameIndex: i,
                timestamp: timestampForFrame(
                    i,
                    currentTime: currentTime,
                    totalFrames: frameCount,
                    fps: fps
                ),
                noveltyScore: val
            ))
        }

        // Add new peaks to detected boundaries.
        detectedBoundaries.append(contentsOf: peaks)
        detectedBoundaries.sort { $0.frameIndex < $1.frameIndex }

        // Return only newly detected boundaries.
        let newBoundaries = Array(detectedBoundaries[reportedCount...])
        reportedCount = detectedBoundaries.count
        return newBoundaries
    }

    /// All detected boundaries so far, sorted by frame index.
    public var boundaries: [Boundary] {
        lock.lock()
        let result = detectedBoundaries
        lock.unlock()
        return result
    }

    /// Reset all state.
    public func reset() {
        lock.lock()
        detectedBoundaries.removeAll()
        reportedCount = 0
        for i in 0..<noveltyCurve.count { noveltyCurve[i] = 0 }
        lock.unlock()
    }

    // MARK: - Private

    /// Checkerboard kernel response at a given center frame.
    ///
    /// Computes: avg(top-left + bottom-right) - avg(top-right + bottom-left)
    /// where top-left and bottom-right are within-section blocks and
    /// top-right and bottom-left are cross-section blocks.
    private func checkerboardResponse(
        matrix: SelfSimilarityMatrix,
        center: Int,
        halfWidth: Int
    ) -> Float {
        var withinSum: Float = 0
        var crossSum: Float = 0
        var pairCount: Float = 0

        // Top-left block: [center-halfWidth, center-1] × [center-halfWidth, center-1]
        // Bottom-right block: [center, center+halfWidth-1] × [center, center+halfWidth-1]
        // These are "within-section" blocks.
        for di in 0..<halfWidth {
            for dj in 0..<halfWidth {
                // Top-left (same section before boundary).
                withinSum += matrix.similarity(
                    frameA: center - halfWidth + di,
                    frameB: center - halfWidth + dj
                )
                // Bottom-right (same section after boundary).
                withinSum += matrix.similarity(
                    frameA: center + di,
                    frameB: center + dj
                )
                // Top-right (cross-section).
                crossSum += matrix.similarity(
                    frameA: center - halfWidth + di,
                    frameB: center + dj
                )
                // Bottom-left (cross-section).
                crossSum += matrix.similarity(
                    frameA: center + di,
                    frameB: center - halfWidth + dj
                )
                pairCount += 1
            }
        }

        guard pairCount > 0 else { return 0 }
        return (withinSum - crossSum) / (pairCount * 2)
    }

    /// Convert a logical frame index to a timestamp.
    private func timestampForFrame(
        _ frameIndex: Int,
        currentTime: Float,
        totalFrames: Int,
        fps: Float
    ) -> Float {
        guard fps > 0, totalFrames > 0 else { return 0 }
        let framesFromEnd = totalFrames - 1 - frameIndex
        return currentTime - Float(framesFromEnd) / fps
    }
}
