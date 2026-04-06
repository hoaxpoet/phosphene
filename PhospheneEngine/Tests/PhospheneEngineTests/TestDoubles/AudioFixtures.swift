// AudioFixtures — Deterministic audio test data generators.
// All functions produce repeatable output suitable for unit tests.

import Foundation

enum AudioFixtures {

    /// Generate a sine wave at the given frequency.
    ///
    /// - Parameters:
    ///   - frequency: Frequency in Hz.
    ///   - sampleRate: Sample rate in Hz (default 48000).
    ///   - duration: Duration in seconds.
    /// - Returns: Array of float samples in the range [-1, 1].
    static func sineWave(frequency: Float, sampleRate: Float = 48000, duration: Float) -> [Float] {
        let sampleCount = Int(sampleRate * duration)
        let angularFrequency = 2.0 * Float.pi * frequency / sampleRate
        return (0..<sampleCount).map { i in
            sinf(angularFrequency * Float(i))
        }
    }

    /// Generate a buffer of silence (all zeros).
    ///
    /// - Parameter sampleCount: Number of zero samples.
    /// - Returns: Array of zeros.
    static func silence(sampleCount: Int) -> [Float] {
        [Float](repeating: 0, count: sampleCount)
    }

    /// Generate deterministic white noise using a seeded PRNG.
    ///
    /// Uses a simple xorshift64 for reproducibility across platforms.
    ///
    /// - Parameters:
    ///   - sampleCount: Number of noise samples.
    ///   - seed: PRNG seed (default 42).
    /// - Returns: Array of float samples roughly in [-1, 1].
    static func whiteNoise(sampleCount: Int, seed: UInt64 = 42) -> [Float] {
        var state = seed == 0 ? 1 : seed  // xorshift can't start at 0
        return (0..<sampleCount).map { _ in
            // xorshift64
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            // Map to [-1, 1]
            let normalized = Float(Int64(bitPattern: state)) / Float(Int64.max)
            return normalized
        }
    }

    /// Generate a single impulse (Dirac delta) at the given position.
    ///
    /// - Parameters:
    ///   - sampleCount: Total buffer length.
    ///   - position: Index of the non-zero sample.
    /// - Returns: Array with exactly one sample at 1.0, rest zeros.
    static func impulse(sampleCount: Int, position: Int) -> [Float] {
        var buffer = [Float](repeating: 0, count: sampleCount)
        if position >= 0 && position < sampleCount {
            buffer[position] = 1.0
        }
        return buffer
    }

    /// Interleave two mono channels into stereo (L, R, L, R, ...).
    ///
    /// - Parameters:
    ///   - left: Left channel samples.
    ///   - right: Right channel samples.
    /// - Returns: Interleaved stereo array with length 2 × min(left.count, right.count).
    static func mixStereo(left: [Float], right: [Float]) -> [Float] {
        let frameCount = min(left.count, right.count)
        var interleaved = [Float](repeating: 0, count: frameCount * 2)
        for i in 0..<frameCount {
            interleaved[i * 2] = left[i]
            interleaved[i * 2 + 1] = right[i]
        }
        return interleaved
    }
}
