// ChromaExtractor — 12-bin chroma vector extraction and key estimation.
// Maps FFT magnitude bins to pitch classes and estimates musical key via
// Krumhansl-Schmuckler profile correlation. All allocations at init time.

import Foundation
import Accelerate
import os.log

private let logger = Logger(subsystem: "com.phosphene.dsp", category: "ChromaExtractor")

// MARK: - ChromaExtractor

/// Extracts a 12-bin chroma vector from FFT magnitudes and estimates musical key.
///
/// Each FFT bin is mapped to a pitch class (C=0, C#=1, ..., B=11) based on
/// its frequency. Bins below 65 Hz (C2) are skipped due to poor pitch resolution
/// at the default 46.875 Hz bin resolution.
///
/// Key estimation uses the Krumhansl-Schmuckler algorithm: Pearson correlation
/// of the chroma vector against 24 key profiles (12 major + 12 minor).
public final class ChromaExtractor: @unchecked Sendable {

    // MARK: - Result

    /// Chroma analysis output for a single frame.
    public struct Result: Sendable {
        /// 12-element instantaneous chroma vector (C, C#, D, D#, E, F, F#, G, G#, A, A#, B).
        /// Normalized so the largest bin = 1.0. All zeros for silence.
        public var chroma: [Float]
        /// EMA-accumulated chroma for stable analysis (12 elements).
        public var stableChroma: [Float]
        /// Estimated musical key from instantaneous chroma, or nil if confidence is too low.
        public var estimatedKey: String?
        /// Hysteresis-filtered stable key, or nil if not yet stable.
        public var stableKey: String?
        /// Confidence of key estimation, 0–1.
        public var keyConfidence: Float
        /// Best Pearson correlation with any major key profile, 0–1 (from accumulated chroma).
        public var majorKeyCorrelation: Float
        /// Best Pearson correlation with any minor key profile, 0–1 (from accumulated chroma).
        public var minorKeyCorrelation: Float
    }

    // MARK: - Constants

    /// Pitch class names for display.
    private static let pitchNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    /// Krumhansl major key profile (C major reference).
    private static let majorProfile: [Float] = [
        6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88
    ]

    /// Krumhansl minor key profile (C minor reference).
    private static let minorProfile: [Float] = [
        6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17
    ]

    /// Minimum frequency for chroma mapping.
    /// Set to 500 Hz (≈B4) to avoid low-resolution bins where 46.875 Hz spacing
    /// causes systematic pitch class bias (e.g., bins 2, 5, 10 all map to F#).
    /// Higher harmonics carry accurate pitch information.
    private static let minFrequency: Float = 500.0

    /// Minimum key confidence to report a key.
    private static let minKeyConfidence: Float = 0.3

    // MARK: - Configuration

    public let binCount: Int
    public let sampleRate: Float

    /// Precomputed pitch class for each bin. -1 means skip (below minFrequency).
    private let binPitchClass: [Int]

    /// Precomputed 24 key profiles: [0..11] = major, [12..23] = minor.
    /// Each profile is rotated to its root pitch class.
    private let keyProfiles: [[Float]]

    /// Thread safety.
    private let lock = NSLock()

    /// Accumulated chroma for stable key estimation (EMA-smoothed).
    private var accumulatedChroma = [Float](repeating: 0, count: 12)

    /// EMA alpha for chroma accumulation. 0.08 = ~4s effective window.
    /// Update: new = (1 - alpha) * old + alpha * current.
    private static let chromaEmaAlpha: Float = 0.08

    // MARK: - Key Hysteresis State

    /// Hysteresis-filtered stable key.
    private var stableKey: String?

    /// Key candidate being validated.
    private var candidateKey: String?

    /// How long the candidate key has been the top result (seconds).
    private var candidateKeyDuration: Float = 0

    /// Correlation score of the candidate key.
    private var candidateKeyCorrelation: Float = 0

    /// Correlation score of the current stable key.
    private var stableKeyCorrelation: Float = 0

    // MARK: - Init

    /// Create a chroma extractor.
    ///
    /// - Parameters:
    ///   - binCount: Number of FFT magnitude bins (default 512).
    ///   - sampleRate: Sample rate in Hz (default 48000).
    ///   - fftSize: FFT size (default 1024).
    ///   - referenceA4: Reference frequency for A4 (default 440 Hz).
    public init(
        binCount: Int = 512,
        sampleRate: Float = 48000,
        fftSize: Int = 1024,
        referenceA4: Float = 440
    ) {
        self.binCount = binCount
        self.sampleRate = sampleRate

        let binResolution = sampleRate / Float(fftSize)

        // Map each bin to a pitch class.
        self.binPitchClass = (0..<binCount).map { i in
            let freq = Float(i) * binResolution
            guard freq >= Self.minFrequency else { return -1 }

            // MIDI note number: 69 = A4 = 440 Hz
            let midiNote = 69.0 + 12.0 * log2f(freq / referenceA4)
            // Pitch class: 0=C, 1=C#, ..., 11=B
            // MIDI note 60 = C4, so pitchClass = midiNote % 12
            let pitchClass = Int(roundf(midiNote)) % 12
            return pitchClass < 0 ? pitchClass + 12 : pitchClass
        }

        // Precompute all 24 key profiles (12 major rotations + 12 minor rotations).
        var profiles = [[Float]]()
        for root in 0..<12 {
            profiles.append(Self.rotateProfile(Self.majorProfile, by: root))
        }
        for root in 0..<12 {
            profiles.append(Self.rotateProfile(Self.minorProfile, by: root))
        }
        self.keyProfiles = profiles

        logger.info("ChromaExtractor created: \(binCount) bins, reference A4=\(referenceA4) Hz")
    }

    // MARK: - Processing

    /// Extract chroma vector and estimate key from FFT magnitudes.
    ///
    /// - Parameter magnitudes: FFT magnitude array (should have `binCount` elements).
    /// - Returns: 12-bin chroma vector, estimated key, and confidence.
    public func process(magnitudes: [Float]) -> Result {
        lock.lock()
        defer { lock.unlock() }

        let count = min(magnitudes.count, binCount)
        guard count > 0 else {
            return Result(
                chroma: [Float](repeating: 0, count: 12),
                stableChroma: [Float](repeating: 0, count: 12),
                estimatedKey: nil,
                stableKey: nil,
                keyConfidence: 0,
                majorKeyCorrelation: 0,
                minorKeyCorrelation: 0
            )
        }

        // Accumulate energy into 12 pitch classes.
        var chroma = [Float](repeating: 0, count: 12)
        for i in 0..<count {
            let pc = binPitchClass[i]
            guard pc >= 0 else { continue }
            chroma[pc] += magnitudes[i]
        }

        // Normalize: divide by max so loudest pitch class = 1.0.
        var maxVal: Float = 0
        vDSP_maxv(chroma, 1, &maxVal, vDSP_Length(12))

        if maxVal > 1e-10 {
            var scale = 1.0 / maxVal
            vDSP_vsmul(chroma, 1, &scale, &chroma, 1, vDSP_Length(12))
        }

        // EMA-accumulate chroma for stable key estimation.
        let alpha = Self.chromaEmaAlpha
        for i in 0..<12 {
            accumulatedChroma[i] = (1 - alpha) * accumulatedChroma[i] + alpha * chroma[i]
        }

        // Key estimation via Krumhansl-Schmuckler on accumulated chroma.
        let keyEst = estimateKey(chroma: accumulatedChroma)
        let estimatedKeyName: String? = keyEst.confidence >= Self.minKeyConfidence ? keyEst.key : nil

        // Key hysteresis: require 3 seconds of agreement before updating stableKey.
        let frameDelta: Float = 1.0 / 60.0  // approximate frame time
        if estimatedKeyName == candidateKey {
            candidateKeyDuration += frameDelta
            candidateKeyCorrelation = keyEst.confidence
        } else {
            candidateKey = estimatedKeyName
            candidateKeyDuration = 0
            candidateKeyCorrelation = keyEst.confidence
        }

        // First key: accept after 3s of agreement with no margin.
        // Subsequent key changes: require 5s AND 0.05 correlation margin.
        let isFirstKey = stableKey == nil
        let durationThreshold: Float = isFirstKey ? 3.0 : 5.0
        let marginThreshold: Float = isFirstKey ? 0.0 : 0.05

        if candidateKeyDuration > durationThreshold
            && candidateKeyCorrelation > stableKeyCorrelation + marginThreshold {
            stableKey = candidateKey
            stableKeyCorrelation = candidateKeyCorrelation
        }

        // Copy accumulated chroma for result.
        let stableChromaCopy = accumulatedChroma

        return Result(
            chroma: chroma,
            stableChroma: stableChromaCopy,
            estimatedKey: estimatedKeyName,
            stableKey: stableKey,
            keyConfidence: keyEst.confidence,
            majorKeyCorrelation: keyEst.majorCorrelation,
            minorKeyCorrelation: keyEst.minorCorrelation
        )
    }

    // MARK: - Reset

    /// Reset accumulated chroma and key hysteresis state.
    public func resetAccumulators() {
        lock.lock()
        defer { lock.unlock() }

        accumulatedChroma = [Float](repeating: 0, count: 12)
        stableKey = nil
        candidateKey = nil
        candidateKeyDuration = 0
        candidateKeyCorrelation = 0
        stableKeyCorrelation = 0
    }

    // MARK: - Key Estimation

    /// Key estimation result (internal, avoids large tuple).
    private struct KeyEstimation {
        var key: String
        var confidence: Float
        var majorCorrelation: Float
        var minorCorrelation: Float
    }

    /// Estimate key by correlating chroma with all 24 key profiles.
    private func estimateKey(chroma: [Float]) -> KeyEstimation {
        var bestCorrelation: Float = -2
        var bestIndex = 0
        var bestMajor: Float = -2
        var bestMinor: Float = -2

        for i in 0..<24 {
            let corr = pearsonCorrelation(chroma, keyProfiles[i])
            if corr > bestCorrelation {
                bestCorrelation = corr
                bestIndex = i
            }
            if i < 12 {
                bestMajor = max(bestMajor, corr)
            } else {
                bestMinor = max(bestMinor, corr)
            }
        }

        let root = bestIndex % 12
        let isMajor = bestIndex < 12
        let keyName = "\(Self.pitchNames[root]) \(isMajor ? "major" : "minor")"

        // Confidence is the absolute correlation, clamped to 0-1.
        let confidence = min(max(bestCorrelation, 0), 1)
        let majorClamped = min(max(bestMajor, 0), 1)
        let minorClamped = min(max(bestMinor, 0), 1)

        return KeyEstimation(
            key: keyName,
            confidence: confidence,
            majorCorrelation: majorClamped,
            minorCorrelation: minorClamped
        )
    }

    /// Pearson correlation coefficient between two 12-element arrays.
    private func pearsonCorrelation(_ x: [Float], _ y: [Float]) -> Float {
        let count = Float(12)

        var sumX: Float = 0
        var sumY: Float = 0
        vDSP_sve(x, 1, &sumX, vDSP_Length(12))
        vDSP_sve(y, 1, &sumY, vDSP_Length(12))

        let meanX = sumX / count
        let meanY = sumY / count

        var covSum: Float = 0
        var varXSum: Float = 0
        var varYSum: Float = 0

        for i in 0..<12 {
            let dx = x[i] - meanX
            let dy = y[i] - meanY
            covSum += dx * dy
            varXSum += dx * dx
            varYSum += dy * dy
        }

        let denom = sqrtf(varXSum * varYSum)
        guard denom > 1e-10 else { return 0 }

        return covSum / denom
    }

    // MARK: - Helpers

    /// Rotate a 12-element profile array by `steps` positions.
    /// rotate([a,b,c,d], by: 1) → [d,a,b,c] (shift right = transpose up).
    private static func rotateProfile(_ profile: [Float], by steps: Int) -> [Float] {
        let size = profile.count
        return (0..<size).map { i in
            profile[(i - steps + size) % size]
        }
    }
}
