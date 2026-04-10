// MoodClassifier — Pure Accelerate valence/arousal classification for music.
// Takes 10 audio features per frame (from MIRPipeline) and outputs continuous
// emotional coordinates in [-1, 1], smoothed with exponential moving average.
//
// The model is a 4-layer MLP (10 → 64 → 32 → 16 → 2) with ReLU activations
// and tanh output, implemented via vDSP matrix operations. Weights were
// extracted from the DEAM-trained CoreML model and hardcoded as static arrays
// in MoodClassifier+Weights.swift.
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
import Accelerate
import Shared
import Audio
import os.log

private let logger = Logger(subsystem: "com.phosphene.ml", category: "MoodClassifier")

// MARK: - MoodClassifier

/// Classifies audio mood as continuous valence/arousal using Accelerate/vDSP.
///
/// Thread-safe. Each call to `classify(features:)` applies z-score normalization,
/// runs MLP inference via vDSP matrix operations, applies EMA smoothing, and
/// updates `currentState`.
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

    // MARK: - State

    /// Latest smoothed emotional state.
    public private(set) var currentState: EmotionalState = .neutral

    /// Thread safety.
    private let lock = NSLock()

    // MARK: - Init

    /// Create a mood classifier with hardcoded Accelerate-based MLP weights.
    public init() {
        logger.info("MoodClassifier loaded: \(Self.featureCount) features, Accelerate MLP")
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

        // Forward pass: 4-layer MLP via vDSP.
        let layer1 = Self.linearReLU(normalized, Self.w0, Self.b0, 64, Self.featureCount)
        let layer2 = Self.linearReLU(layer1, Self.w1, Self.b1, 32, 64)
        let layer3 = Self.linearReLU(layer2, Self.w2, Self.b2, 16, 32)
        let output = Self.linearTanh(layer3, Self.w3, Self.b3, 2, 16)

        // Clamp to [-1, 1].
        let clampedValence = min(max(output[0], -1), 1)
        let clampedArousal = min(max(output[1], -1), 1)

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

    // MARK: - MLP Helpers

    /// Linear layer + ReLU: output = max(0, W * input + bias).
    private static func linearReLU(
        _ input: [Float], _ weight: [Float], _ bias: [Float],
        _ outSize: Int, _ inSize: Int
    ) -> [Float] {
        var result = [Float](repeating: 0, count: outSize)
        let rows = vDSP_Length(outSize)
        let cols = vDSP_Length(inSize)
        vDSP_mmul(weight, 1, input, 1, &result, 1, rows, 1, cols)
        vDSP_vadd(result, 1, bias, 1, &result, 1, vDSP_Length(outSize))
        var zeros = [Float](repeating: 0, count: outSize)
        vDSP_vmax(result, 1, &zeros, 1, &result, 1, vDSP_Length(outSize))
        return result
    }

    /// Linear layer + tanh: output = tanh(W * input + bias).
    private static func linearTanh(
        _ input: [Float], _ weight: [Float], _ bias: [Float],
        _ outSize: Int, _ inSize: Int
    ) -> [Float] {
        var result = [Float](repeating: 0, count: outSize)
        let rows = vDSP_Length(outSize)
        let cols = vDSP_Length(inSize)
        vDSP_mmul(weight, 1, input, 1, &result, 1, rows, 1, cols)
        vDSP_vadd(result, 1, bias, 1, &result, 1, vDSP_Length(outSize))
        var count = Int32(outSize)
        vvtanhf(&result, result, &count)
        return result
    }
}
