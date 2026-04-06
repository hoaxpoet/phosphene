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
        /// 12-element chroma vector (C, C#, D, D#, E, F, F#, G, G#, A, A#, B).
        /// Normalized so the largest bin = 1.0. All zeros for silence.
        public var chroma: [Float]
        /// Estimated musical key (e.g. "C major", "A minor"), or nil if confidence is too low.
        public var estimatedKey: String?
        /// Confidence of key estimation, 0–1.
        public var keyConfidence: Float
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

    /// Minimum frequency for chroma mapping (C2 ≈ 65.4 Hz).
    private static let minFrequency: Float = 65.0

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
            return Result(chroma: [Float](repeating: 0, count: 12), estimatedKey: nil, keyConfidence: 0)
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

        // Key estimation via Krumhansl-Schmuckler.
        let (key, confidence) = estimateKey(chroma: chroma)

        return Result(
            chroma: chroma,
            estimatedKey: confidence >= Self.minKeyConfidence ? key : nil,
            keyConfidence: confidence
        )
    }

    // MARK: - Key Estimation

    /// Estimate key by correlating chroma with all 24 key profiles.
    private func estimateKey(chroma: [Float]) -> (key: String, confidence: Float) {
        var bestCorrelation: Float = -2
        var bestIndex = 0

        for i in 0..<24 {
            let r = pearsonCorrelation(chroma, keyProfiles[i])
            if r > bestCorrelation {
                bestCorrelation = r
                bestIndex = i
            }
        }

        let root = bestIndex % 12
        let isMajor = bestIndex < 12
        let keyName = "\(Self.pitchNames[root]) \(isMajor ? "major" : "minor")"

        // Confidence is the absolute correlation, clamped to 0-1.
        let confidence = min(max(bestCorrelation, 0), 1)

        return (keyName, confidence)
    }

    /// Pearson correlation coefficient between two 12-element arrays.
    private func pearsonCorrelation(_ x: [Float], _ y: [Float]) -> Float {
        let n = Float(12)

        var sumX: Float = 0
        var sumY: Float = 0
        vDSP_sve(x, 1, &sumX, vDSP_Length(12))
        vDSP_sve(y, 1, &sumY, vDSP_Length(12))

        let meanX = sumX / n
        let meanY = sumY / n

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
        let n = profile.count
        return (0..<n).map { i in
            profile[(i - steps + n) % n]
        }
    }
}
