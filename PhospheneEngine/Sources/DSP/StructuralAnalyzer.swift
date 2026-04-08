// StructuralAnalyzer — Real-time progressive structural analysis.
// Builds a self-similarity matrix from chroma + spectral features, detects
// section boundaries via novelty detection, and predicts the next boundary
// once 2+ boundaries are observed.

import Foundation
import Accelerate
import Shared
import os.log

private let logger = Logger(subsystem: "com.phosphene.dsp", category: "StructuralAnalyzer")

// MARK: - StructuralAnalyzer

/// Progressive structural analysis coordinator.
///
/// Feeds per-frame features into a self-similarity matrix, runs novelty
/// detection periodically, maintains a list of detected section boundaries,
/// and predicts when the next boundary will occur.
///
/// The prediction is CPU-side only (not in FeatureVector). It flows through
/// `AnalyzedFrame.structuralPrediction` for the Orchestrator to consume.
///
/// Usage:
/// ```swift
/// let analyzer = StructuralAnalyzer()
/// // Each frame:
/// let prediction = analyzer.process(
///     chroma: chroma12, spectralCentroid: 0.5,
///     spectralFlux: 0.3, spectralRolloff: 0.7,
///     energy: 0.6, time: elapsed
/// )
/// // prediction.confidence > 0 means a boundary prediction is available.
/// ```
public final class StructuralAnalyzer: @unchecked Sendable {

    // MARK: - Properties

    /// Self-similarity matrix for feature storage and similarity queries.
    private let similarityMatrix: SelfSimilarityMatrix

    /// Novelty detector for section boundary detection.
    private let noveltyDetector: NoveltyDetector

    /// Feature vector dimension.
    private let featureDim: Int

    /// How often to run novelty detection (every N frames).
    private let detectionInterval: Int

    /// Current frame count since start/reset.
    private var frameCount: Int = 0

    /// Current timestamp (updated each frame).
    private var currentTime: Float = 0

    /// Current assumed FPS (updated from deltaTime).
    private var currentFPS: Float = 60

    /// Detected section boundaries as timestamps.
    private var sectionBoundaries: [Float] = []

    /// Average feature vector per section (for repetition detection).
    private var sectionFeatureSums: [[Float]] = []

    /// Frame count per section (for computing averages).
    private var sectionFrameCounts: [Int] = []

    /// Running sum of features for the current (latest) section.
    private var currentSectionSum: [Float]

    /// Frame count for the current section.
    private var currentSectionFrameCount: Int = 0

    /// Pre-allocated feature buffer for packing chroma + spectral.
    private var featureBuffer: [Float]

    /// Thread safety.
    private let lock = NSLock()

    // MARK: - Init

    /// Create a structural analyzer.
    ///
    /// - Parameters:
    ///   - maxHistory: Maximum frame history for the similarity matrix (default 600).
    ///   - featureDim: Feature vector dimension (default 16: 12 chroma + 4 spectral).
    ///   - detectionInterval: Run novelty detection every N frames (default 30 ≈ 0.5s at 60fps).
    public init(
        maxHistory: Int = 600,
        featureDim: Int = 16,
        detectionInterval: Int = 30
    ) {
        self.featureDim = featureDim
        self.detectionInterval = detectionInterval
        self.similarityMatrix = SelfSimilarityMatrix(
            maxHistory: maxHistory, featureDim: featureDim
        )
        self.noveltyDetector = NoveltyDetector(maxHistory: maxHistory)
        self.featureBuffer = [Float](repeating: 0, count: featureDim)
        self.currentSectionSum = [Float](repeating: 0, count: featureDim)

        logger.info(
            "StructuralAnalyzer created: maxHistory=\(maxHistory), featureDim=\(featureDim), detectionInterval=\(detectionInterval)"
        )
    }

    // MARK: - Processing

    /// Feed one frame of features and return the current structural prediction.
    ///
    /// Called every frame from MIRPipeline. The expensive novelty detection
    /// runs only every `detectionInterval` frames.
    ///
    /// - Parameters:
    ///   - chroma: 12-float chroma vector from ChromaExtractor.
    ///   - spectralCentroid: Normalized spectral centroid (0–1).
    ///   - spectralFlux: Normalized spectral flux (0–1).
    ///   - spectralRolloff: Normalized spectral rolloff (0–1).
    ///   - energy: Total energy (0–1).
    ///   - time: Seconds since capture start.
    /// - Returns: Current structural prediction.
    public func process(
        chroma: [Float],
        spectralCentroid: Float,
        spectralFlux: Float,
        spectralRolloff: Float,
        energy: Float,
        time: Float
    ) -> StructuralPrediction {
        lock.lock()
        defer { lock.unlock() }

        currentTime = time

        // Pack feature vector: 12 chroma + 4 spectral summary.
        let chromaCount = min(chroma.count, 12)
        for i in 0..<chromaCount { featureBuffer[i] = chroma[i] }
        for i in chromaCount..<12 { featureBuffer[i] = 0 }
        featureBuffer[12] = spectralCentroid
        featureBuffer[13] = spectralFlux
        featureBuffer[14] = spectralRolloff
        featureBuffer[15] = energy

        // Add to similarity matrix.
        similarityMatrix.addFrame(featureBuffer)

        // Accumulate features for current section average.
        for i in 0..<featureDim {
            currentSectionSum[i] += featureBuffer[i]
        }
        currentSectionFrameCount += 1

        frameCount += 1

        // Estimate FPS from time progression.
        if frameCount > 1, time > 0 {
            currentFPS = Float(frameCount) / time
        }

        // Run novelty detection periodically.
        if frameCount % detectionInterval == 0 {
            let newBoundaries = noveltyDetector.detect(
                similarityMatrix: similarityMatrix,
                currentTime: time,
                fps: currentFPS
            )
            for boundary in newBoundaries {
                registerBoundary(at: boundary.timestamp)
            }
        }

        return computePrediction()
    }

    // MARK: - Public Accessors

    /// Number of detected section boundaries.
    public var boundaryCount: Int {
        lock.lock()
        let count = sectionBoundaries.count
        lock.unlock()
        return count
    }

    /// All detected boundary timestamps.
    public var boundaryTimestamps: [Float] {
        lock.lock()
        let timestamps = sectionBoundaries
        lock.unlock()
        return timestamps
    }

    // MARK: - Reset

    /// Clear all state (call on track change).
    public func reset() {
        lock.lock()
        similarityMatrix.reset()
        noveltyDetector.reset()
        frameCount = 0
        currentTime = 0
        currentFPS = 60
        sectionBoundaries.removeAll()
        sectionFeatureSums.removeAll()
        sectionFrameCounts.removeAll()
        currentSectionSum = [Float](repeating: 0, count: featureDim)
        currentSectionFrameCount = 0
        lock.unlock()

        logger.info("StructuralAnalyzer reset")
    }

    // MARK: - Private

    /// Register a new section boundary.
    private func registerBoundary(at timestamp: Float) {
        // Finalize current section's average features.
        if currentSectionFrameCount > 0 {
            var avg = [Float](repeating: 0, count: featureDim)
            let invCount = 1.0 / Float(currentSectionFrameCount)
            for i in 0..<featureDim {
                avg[i] = currentSectionSum[i] * invCount
            }
            sectionFeatureSums.append(avg)
            sectionFrameCounts.append(currentSectionFrameCount)
        }

        sectionBoundaries.append(timestamp)

        // Reset current section accumulator.
        for i in 0..<featureDim { currentSectionSum[i] = 0 }
        currentSectionFrameCount = 0

        logger.debug(
            "Section boundary detected at \(timestamp, format: .fixed(precision: 2))s (total: \(self.sectionBoundaries.count))"
        )
    }

    /// Compute the current structural prediction.
    private func computePrediction() -> StructuralPrediction {
        let sectionIndex = UInt32(sectionBoundaries.count)
        let sectionStart = sectionBoundaries.last ?? 0

        // Need at least 2 boundaries to predict the next one.
        guard sectionBoundaries.count >= 2 else {
            return StructuralPrediction(
                sectionIndex: sectionIndex,
                sectionStartTime: sectionStart,
                predictedNextBoundary: 0,
                confidence: 0
            )
        }

        // Compute section durations.
        var durations: [Float] = []
        for i in 1..<sectionBoundaries.count {
            durations.append(sectionBoundaries[i] - sectionBoundaries[i - 1])
        }

        // Average duration and consistency.
        let avgDuration = durations.reduce(0, +) / Float(durations.count)
        let durationVariance: Float
        if durations.count > 1 {
            let sumSqDiff = durations.reduce(Float(0)) { acc, dur in
                let diff = dur - avgDuration
                return acc + diff * diff
            }
            durationVariance = sumSqDiff / Float(durations.count)
        } else {
            durationVariance = 0
        }
        let durationStdDev = sqrtf(max(durationVariance, 0))
        let durationConsistency: Float = avgDuration > 0
            ? max(0, 1.0 - durationStdDev / avgDuration)
            : 0

        // Repetition detection: check if any pair of sections are similar.
        let repetitionBonus = computeRepetitionBonus()

        // Confidence: weighted combination of duration consistency and repetition.
        let confidence = min(durationConsistency * 0.7 + repetitionBonus * 0.3, 1.0)

        // Predicted next boundary.
        let predictedNext = sectionStart + avgDuration

        return StructuralPrediction(
            sectionIndex: sectionIndex,
            sectionStartTime: sectionStart,
            predictedNextBoundary: predictedNext,
            confidence: confidence
        )
    }

    /// Compute a repetition bonus (0–1) based on section similarity.
    ///
    /// If any non-adjacent section pair has cosine similarity > 0.8,
    /// it indicates structural repetition (e.g., ABAB pattern).
    private func computeRepetitionBonus() -> Float {
        let sectionCount = sectionFeatureSums.count
        guard sectionCount >= 2 else { return 0 }

        var maxSim: Float = 0
        for i in 0..<sectionCount {
            guard i + 2 < sectionCount else { continue }
            for j in (i + 2)..<sectionCount {
                // Compare non-adjacent sections (skip consecutive pairs).
                let sim = cosineSimilarity(sectionFeatureSums[i], sectionFeatureSums[j])
                maxSim = max(maxSim, sim)
            }
        }

        // Scale: 0 below 0.6, ramps to 1.0 at 0.9.
        return max(0, min((maxSim - 0.6) / 0.3, 1.0))
    }

    /// Cosine similarity between two feature vectors.
    private func cosineSimilarity(_ vectorA: [Float], _ vectorB: [Float]) -> Float {
        guard vectorA.count == vectorB.count, !vectorA.isEmpty else { return 0 }
        let count = vectorA.count

        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        vDSP_dotpr(vectorA, 1, vectorB, 1, &dot, vDSP_Length(count))
        vDSP_svesq(vectorA, 1, &normA, vDSP_Length(count))
        vDSP_svesq(vectorB, 1, &normB, vDSP_Length(count))

        let denom = sqrtf(normA * normB)
        return denom > 1e-10 ? dot / denom : 0
    }
}
