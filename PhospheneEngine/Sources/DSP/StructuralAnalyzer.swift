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

    /// Emitted decimated-frame count since start/reset (one per `bucketPeriod`).
    /// Drives the detection cadence — NOT the raw per-call count (BUG-042).
    private var structuralFrameCount: Int = 0

    /// Current timestamp (updated each raw frame).
    private var currentTime: Float = 0

    /// Section-scale decimation period (BUG-042). Incoming raw frames (~94 Hz)
    /// are averaged into one structural frame every `bucketPeriod` seconds before
    /// they reach the similarity matrix, so the fixed frame-denominated geometry
    /// (600-frame ring, 8-frame checkerboard) lands at SECTION scale (5 min / 4 s)
    /// instead of NOTE scale (6.4 s / 85 ms). The decimated stream is exactly
    /// `1/bucketPeriod` Hz, so timestamp conversion uses that rate, not an estimate.
    private let bucketPeriod: Float

    /// Running sum of raw frames in the current decimation bucket.
    private var bucketSum: [Float]

    /// Raw frames accumulated in the current bucket.
    private var bucketFrameCount: Int = 0

    /// Analyzer-clock time the last bucket was emitted.
    private var lastBucketEmitTime: Float = 0

    /// Pre-allocated buffer for the decimated (bucket-mean) frame.
    private var decimatedBuffer: [Float]

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
    ///   - maxHistory: Maximum DECIMATED-frame history for the similarity matrix
    ///     (default 600 ≈ 5 min at the 2 Hz decimated rate).
    ///   - featureDim: Feature vector dimension (default 16: 12 chroma + 4 spectral).
    ///   - detectionInterval: Run novelty detection every N decimated frames
    ///     (default 2 ≈ 1 s at the 2 Hz decimated rate).
    ///   - bucketPeriod: Decimation window in seconds (default 0.5 → 2 Hz). Raw
    ///     ~94 Hz frames are mean-aggregated per bucket before the SSM (BUG-042).
    public init(
        maxHistory: Int = 600,
        featureDim: Int = 16,
        detectionInterval: Int = 2,
        bucketPeriod: Float = 0.5
    ) {
        self.featureDim = featureDim
        self.detectionInterval = detectionInterval
        self.bucketPeriod = bucketPeriod
        self.similarityMatrix = SelfSimilarityMatrix(
            maxHistory: maxHistory, featureDim: featureDim
        )
        self.noveltyDetector = NoveltyDetector(maxHistory: maxHistory)
        self.featureBuffer = [Float](repeating: 0, count: featureDim)
        self.decimatedBuffer = [Float](repeating: 0, count: featureDim)
        self.currentSectionSum = [Float](repeating: 0, count: featureDim)
        self.bucketSum = [Float](repeating: 0, count: featureDim)

        logger.info(
            """
            StructuralAnalyzer created: maxHistory=\(maxHistory), \
            featureDim=\(featureDim), detectionInterval=\(detectionInterval), \
            bucketPeriod=\(bucketPeriod)s
            """
        )
    }

    // MARK: - Processing

    /// Feed one frame of features and return the current structural prediction.
    ///
    /// 4-scalar spectral summary fed alongside chroma into the structural feature vector.
    public struct SpectralSummary: Sendable {
        public let centroid: Float
        public let flux: Float
        public let rolloff: Float
        public let energy: Float

        public init(centroid: Float, flux: Float, rolloff: Float, energy: Float) {
            self.centroid = centroid
            self.flux = flux
            self.rolloff = rolloff
            self.energy = energy
        }
    }

    /// Called every frame from MIRPipeline. The expensive novelty detection
    /// runs only every `detectionInterval` frames.
    ///
    /// - Parameters:
    ///   - chroma: 12-float chroma vector from ChromaExtractor.
    ///   - spectral: Centroid/flux/rolloff/energy summary, all normalized (0–1).
    ///   - time: Seconds since capture start.
    /// - Returns: Current structural prediction.
    public func process(
        chroma: [Float],
        spectral: SpectralSummary,
        time: Float
    ) -> StructuralPrediction {
        lock.lock()
        defer { lock.unlock() }

        currentTime = time

        // Pack feature vector: 12 chroma + 4 spectral summary.
        let chromaCount = min(chroma.count, 12)
        for i in 0..<chromaCount { featureBuffer[i] = chroma[i] }
        for i in chromaCount..<12 { featureBuffer[i] = 0 }
        featureBuffer[12] = spectral.centroid
        featureBuffer[13] = spectral.flux
        featureBuffer[14] = spectral.rolloff
        featureBuffer[15] = spectral.energy

        // BUG-042: accumulate into the current decimation bucket. The SSM insert
        // and the expensive novelty detection run on the bucket MEAN, not every
        // raw frame, so the geometry operates at section scale.
        for i in 0..<featureDim { bucketSum[i] += featureBuffer[i] }
        bucketFrameCount += 1

        // Emit one decimated frame per `bucketPeriod` of analyzer-clock time.
        if bucketFrameCount > 0, time - lastBucketEmitTime >= bucketPeriod {
            emitDecimatedFrame(at: time)
        }

        return computePrediction()
    }

    /// Average the current bucket into one structural frame and push it through
    /// the similarity matrix + periodic novelty detection (BUG-042 decimation).
    private func emitDecimatedFrame(at time: Float) {
        let inv = 1.0 / Float(bucketFrameCount)
        for i in 0..<featureDim {
            decimatedBuffer[i] = bucketSum[i] * inv
            bucketSum[i] = 0
        }
        bucketFrameCount = 0
        lastBucketEmitTime = time

        // Add the decimated frame to the similarity matrix.
        similarityMatrix.addFrame(decimatedBuffer)

        // Accumulate the current section average over DECIMATED frames.
        for i in 0..<featureDim { currentSectionSum[i] += decimatedBuffer[i] }
        currentSectionFrameCount += 1

        structuralFrameCount += 1

        // Run novelty detection periodically. The decimated stream is exactly
        // `1/bucketPeriod` Hz, so that fixed rate converts frame indices to
        // timestamps (no FPS estimate needed).
        if structuralFrameCount % detectionInterval == 0 {
            let newBoundaries = noveltyDetector.detect(
                similarityMatrix: similarityMatrix,
                currentTime: time,
                fps: 1.0 / bucketPeriod
            )
            for boundary in newBoundaries {
                registerBoundary(at: boundary.timestamp)
            }
        }
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
        structuralFrameCount = 0
        currentTime = 0
        bucketFrameCount = 0
        lastBucketEmitTime = 0
        for i in 0..<featureDim { bucketSum[i] = 0 }
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

        let total = self.sectionBoundaries.count
        logger.debug(
            "Section boundary detected at \(timestamp, format: .fixed(precision: 2))s (total: \(total))"
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
