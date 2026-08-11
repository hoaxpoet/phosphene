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
// parameters (means and stds) are hardcoded and MUST match
// `tools/data/mood_scaler.json`. Feature [7] (flux) is fitted on the 27,638-track
// corpus rather than the training set — see the §Z-Score Normalization note.
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

    /// Output smoothing time constant, in SECONDS (DYN.7).
    ///
    /// Was `emaAlpha = 0.1` applied per CALL, so the window it produced depended on how
    /// often the caller called: **1.01 s live** (every analysis frame at the measured
    /// 9.9 Hz) against **6.96 s offline** (every 30th frame at 43.07 Hz) — a 7× disagreement
    /// between the mood a track was PREPARED with and the mood it PLAYED with, with the
    /// OFFLINE side the one far from intent. The 0.7 s here is the
    /// figure that alpha's own comment always claimed; only the per-call form was wrong.
    public static let outputTau: Float = 0.7

    // MARK: - Z-Score Normalization (from tools/data/mood_scaler.json)
    //
    // FEATURE [7] (flux) IS FITTED ON A DIFFERENT POPULATION FROM THE OTHER NINE, and that
    // is deliberate (DYN.6.2, Matt's call). Features 0–6 and 8–9 come from the 818-track
    // live-annotated training set, where they are well calibrated: the corpus census
    // (n = 27,638) measured their z(median) between −0.45 and +0.21, with ≤ 4.7 % of tracks
    // beyond |z| > 2.
    //
    // Flux was not. Against the training fit (mean 0.25158, std 0.20444) the corpus sat at
    // z(median) +1.01 with **33.8 % beyond |z| > 2** and 22.2 % beyond |z| > 3. The scaler
    // was never stale — it reproduces the training set to five decimals — the training set
    // simply never covered material this dense: its maximum flux is 1.0167 and **15.3 % of
    // the corpus exceeds that outright**, so the model extrapolated on feature [7] for a
    // large minority of the library. Refitting the pair to corpus statistics is the
    // narrowest available fix; retraining on a broader annotated set is the real one.
    //
    // Accepted on the objective corpus A/B (`MoodScalerRefitABTests`, n = 21,037), the same
    // form of evidence BUG-066 was accepted on: arousal mean +0.378 → +0.229 with its spread
    // intact (sd 0.330 → 0.331), railed readings 0.5 % → 0.0 %, 41.3 % of tracks changing
    // valence/arousal quadrant. **What that A/B cannot show is that the new readings are
    // RIGHT** — nobody has labelled these tracks, so it establishes the change is real,
    // bounded and non-degenerate, not that it is an improvement.

    /// Per-feature means. [7] = flux, corpus-fitted (DYN.6.2); the rest, training-fitted.
    private static let scalerMeans: [Float] = [
        0.12720, 0.20594, 0.12509, 0.03842, 0.01068, 0.00502,
        0.11827, 0.56498, 0.53073, 0.50940
    ]

    /// Read-only view of the scaler for calibration diagnostics (DYN.6). The z-score is
    /// where a feature-scale error shows up, so a test must be able to compute it from the
    /// SAME numbers inference uses rather than a transcribed copy.
    public static var scalerMeansForTesting: [Float] { scalerMeans }
    public static var scalerStdsForTesting: [Float] { scalerStds }

    /// Per-feature standard deviations. [7] = flux, corpus-fitted (DYN.6.2).
    private static let scalerStds: [Float] = [
        0.12225, 0.13055, 0.08257, 0.03043, 0.01463, 0.01376,
        0.07421, 0.43400, 0.15677, 0.12204
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
    /// - Parameter deltaTime: seconds since the previous `classify` call on this instance.
    ///   Required (DYN.7): the output window is wall-clock, so a caller that classifies
    ///   every 30th frame and one that classifies every frame reach the same reading.
    public func classify(features: [Float], deltaTime: Float) throws -> EmotionalState {
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
        let alpha = LoudnessProfile.emaAlpha(deltaTime: deltaTime, tau: Self.outputTau)
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
