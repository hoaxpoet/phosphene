// MoodClassifier — CoreML-powered valence/arousal classification for music.
// Takes 10 audio features per frame (from MIRPipeline) and outputs continuous
// emotional coordinates in [-1, 1], smoothed with exponential moving average.
//
// The model is a 3-layer MLP (10 → 64 → 32 → 16 → 2) trained on live
// Phosphene pipeline features annotated by the user, deployed on ANE.
//
// Input features require z-score normalization before inference. The scaler
// parameters (means and stds) are hardcoded from the training pipeline and
// MUST match `tools/data/mood_scaler.json`.
//
// Input features (10 floats, pre-normalization):
//   [0-5]:  6-band energy (subBass, lowBass, lowMid, midHigh, highMid, high)
//   [6]:    spectralCentroid (normalized 0-1 by Nyquist)
//   [7]:    spectralFlux (raw sum, NOT normalized)
//   [8]:    majorKeyCorrelation (best Pearson r with K-S major profiles, 0-1)
//   [9]:    minorKeyCorrelation (best Pearson r with K-S minor profiles, 0-1)

import Foundation
import CoreML
import Shared
import Audio
import os.log

private let logger = Logger(subsystem: "com.phosphene.ml", category: "MoodClassifier")

// MARK: - MoodClassifier

/// Classifies audio mood as continuous valence/arousal using CoreML and the Neural Engine.
///
/// Thread-safe. Each call to `classify(features:)` applies z-score normalization,
/// runs CoreML inference, applies EMA smoothing, and updates `currentState`.
public final class MoodClassifier: MoodClassifying, @unchecked Sendable {

    // MARK: - Constants

    /// Expected number of input features.
    public static let featureCount = 10

    /// EMA smoothing factor. At ~94 callbacks/s, alpha=0.1 gives ~0.7s time constant.
    public static let emaAlpha: Float = 0.1

    // MARK: - Z-Score Normalization (from tools/data/mood_scaler.json)

    /// Per-feature means from live-pipeline annotated training set.
    private static let scalerMeans: [Float] = [
        0.12720, 0.20594, 0.12509, 0.03842, 0.01068, 0.00502,
        0.11827, 0.25158, 0.53073, 0.50940
    ]

    /// Per-feature standard deviations from live-pipeline annotated training set.
    private static let scalerStds: [Float] = [
        0.12225, 0.13055, 0.08257, 0.03043, 0.01463, 0.01376,
        0.07421, 0.20444, 0.15677, 0.12204
    ]

    // MARK: - Model

    /// The loaded CoreML model.
    private let model: MLModel

    /// The compute unit configuration used to load the model.
    public let computeUnits: MLComputeUnits

    // MARK: - State

    /// Latest smoothed emotional state.
    public private(set) var currentState: EmotionalState = .neutral

    /// Thread safety.
    private let lock = NSLock()

    // MARK: - Init

    /// Create a mood classifier backed by the DEAM-trained CoreML model.
    ///
    /// - Throws: `MoodClassificationError` if model loading fails.
    public init() throws {
        guard let modelURL = Bundle.module.url(
            forResource: "MoodClassifier",
            withExtension: "mlpackage",
            subdirectory: "Models"
        ) else {
            throw MoodClassificationError.modelNotFound
        }

        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndNeuralEngine
        self.computeUnits = config.computeUnits

        do {
            self.model = try MLModel(
                contentsOf: MLModel.compileModel(at: modelURL),
                configuration: config
            )
        } catch {
            throw MoodClassificationError.modelLoadFailed(error.localizedDescription)
        }

        logger.info("MoodClassifier loaded: \(Self.featureCount) features, DEAM-trained, ANE")
    }

    // MARK: - Classification

    /// Classify mood from audio features.
    ///
    /// Applies z-score normalization and EMA smoothing. Call once per frame.
    ///
    /// - Parameter features: Array of exactly 10 floats (see class-level docs).
    /// - Returns: Smoothed `EmotionalState` with valence and arousal in [-1, 1].
    public func classify(features: [Float]) throws -> EmotionalState {
        guard features.count == Self.featureCount else {
            throw MoodClassificationError.invalidFeatureCount(features.count)
        }

        // Z-score normalize: (feature - mean) / std.
        var normalized = [Float](repeating: 0, count: Self.featureCount)
        for idx in 0..<Self.featureCount {
            let std = Self.scalerStds[idx]
            normalized[idx] = std > 1e-10
                ? (features[idx] - Self.scalerMeans[idx]) / std
                : 0
        }

        // Pack input as MLShapedArray [1, 10].
        let inputArray = MLShapedArray<Float>(
            scalars: normalized, shape: [1, Self.featureCount]
        )
        let inputMultiArray = MLMultiArray(inputArray)
        let provider = try MLDictionaryFeatureProvider(
            dictionary: ["features": MLFeatureValue(multiArray: inputMultiArray)]
        )

        // Run prediction.
        let prediction: MLFeatureProvider
        do {
            prediction = try model.prediction(from: provider)
        } catch {
            throw MoodClassificationError.predictionFailed(error.localizedDescription)
        }

        // Extract output [1, 2].
        guard let outputValue = prediction.featureValue(for: "mood"),
              let outputMultiArray = outputValue.multiArrayValue else {
            throw MoodClassificationError.predictionFailed("Missing 'mood' output")
        }

        // ANE may output Float16 — use subscript for safe extraction.
        var rawValence: Float = 0
        var rawArousal: Float = 0
        if outputMultiArray.count >= 2 {
            rawValence = outputMultiArray[0].floatValue
            rawArousal = outputMultiArray[1].floatValue
        }

        // Clamp to [-1, 1].
        let clampedValence = min(max(rawValence, -1), 1)
        let clampedArousal = min(max(rawArousal, -1), 1)

        // Apply EMA smoothing.
        lock.lock()
        let alpha = Self.emaAlpha
        let smoothedValence = alpha * clampedValence + (1 - alpha) * currentState.valence
        let smoothedArousal = alpha * clampedArousal + (1 - alpha) * currentState.arousal
        let state = EmotionalState(valence: smoothedValence, arousal: smoothedArousal)
        currentState = state
        lock.unlock()

        return state
    }
}
