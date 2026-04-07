// MoodClassifier — Direct heuristic valence/arousal classification for music.
// Takes 10 audio features per frame (from MIRPipeline) and outputs continuous
// emotional coordinates in [-1, 1], smoothed with exponential moving average.
//
// Uses direct computation instead of CoreML — calibrated against real Core Audio
// tap output. Will be replaced with a trained ML model once calibration data
// is collected from diverse genres.
//
// Input features (10 floats):
//   [0-5]:  6-band energy (subBass, lowBass, lowMid, midHigh, highMid, high)
//   [6]:    spectralCentroid (normalized 0-1 by Nyquist)
//   [7]:    spectralFlux (normalized 0-1 via running max)
//   [8]:    majorKeyCorrelation (best Pearson r with K-S major profiles, 0-1)
//   [9]:    minorKeyCorrelation (best Pearson r with K-S minor profiles, 0-1)

import Foundation
import Shared
import Audio
import os.log

private let logger = Logger(subsystem: "com.phosphene.ml", category: "MoodClassifier")

// MARK: - MoodClassifier

/// Classifies audio mood as continuous valence/arousal using direct heuristics.
///
/// Thread-safe. Each call to `classify(features:)` applies EMA smoothing to the
/// raw heuristic output and updates `currentState`.
public final class MoodClassifier: MoodClassifying, @unchecked Sendable {

    // MARK: - Constants

    /// Expected number of input features.
    public static let featureCount = 10

    /// EMA smoothing factor. At ~94 callbacks/s, alpha=0.02 gives ~3s time constant.
    /// Mood should be stable within a song section, not jittery per-frame.
    public static let emaAlpha: Float = 0.02

    // MARK: - State

    /// Latest smoothed emotional state.
    public private(set) var currentState: EmotionalState = .neutral

    /// Thread safety.
    private let lock = NSLock()

    // MARK: - Init

    /// Create a mood classifier using direct heuristics.
    public init() throws {
        logger.info("MoodClassifier loaded: \(Self.featureCount) features, heuristic mode")
    }

    // MARK: - Classification

    /// Classify mood from audio features using direct heuristics.
    ///
    /// Applies EMA smoothing to the raw output. Call once per frame.
    ///
    /// - Parameter features: Array of exactly 10 floats (see class-level docs).
    /// - Returns: Smoothed `EmotionalState` with valence and arousal in [-1, 1].
    public func classify(features: [Float]) throws -> EmotionalState {
        guard features.count == Self.featureCount else {
            throw MoodClassificationError.invalidFeatureCount(features.count)
        }

        let subBass = features[0]
        let lowBass = features[1]
        let lowMid = features[2]
        let midHigh = features[3]
        let highMid = features[4]
        let high = features[5]
        let centroid = features[6]
        let flux = features[7]
        let majorCorr = features[8]
        let minorCorr = features[9]

        // --- Arousal: energy + flux driven ---
        // Bass weight: sub_bass and low_bass carry the physical energy feel.
        let bassEnergy = (subBass + lowBass) * 0.5
        // Total across all bands.
        let totalEnergy = (subBass + lowBass + lowMid + midHigh + highMid + high) / 6.0
        // Weighted blend: bass matters more for perceived energy.
        let weightedEnergy = totalEnergy * 0.3 + bassEnergy * 0.7
        // Map to arousal. Calibrated: 0.05 = quiet, 0.15 = moderate, 0.25 = loud.
        var rawArousal = (weightedEnergy - 0.08) * 7.0
        // Flux adds excitement (timbral change = energy).
        rawArousal += flux * 1.5
        // Centroid adds slight arousal (brighter = more energetic).
        rawArousal += (centroid - 0.10) * 0.5
        rawArousal = min(max(rawArousal, -1), 1)

        // --- Valence: key mode + timbral character ---
        // Major key → positive, minor key → negative.
        let modeDiff = majorCorr - minorCorr
        let confidence = max(majorCorr, minorCorr)
        var rawValence = modeDiff * confidence * 3.0

        // Key ambiguity: when both correlations are close, the music is
        // likely dissonant (power chords, distortion, atonal). Bias negative.
        let keyAmbiguity = 1.0 - abs(modeDiff) / (confidence + 1e-6)
        rawValence -= keyAmbiguity * 0.3

        // Aggression detector: high energy + high flux + low centroid = dark,
        // loud, rapidly changing timbre → angry/aggressive → negative valence.
        let aggressionSignal = weightedEnergy * flux * (1.0 - centroid)
        rawValence -= aggressionSignal * 4.0

        // Brightness adds slight positive bias (bright = happier).
        rawValence += (centroid - 0.15) * 0.3
        rawValence = min(max(rawValence, -1), 1)

        // Apply EMA smoothing.
        lock.lock()
        let alpha = Self.emaAlpha
        let smoothedValence = alpha * rawValence + (1 - alpha) * currentState.valence
        let smoothedArousal = alpha * rawArousal + (1 - alpha) * currentState.arousal
        let state = EmotionalState(valence: smoothedValence, arousal: smoothedArousal)
        currentState = state
        lock.unlock()

        return state
    }
}
