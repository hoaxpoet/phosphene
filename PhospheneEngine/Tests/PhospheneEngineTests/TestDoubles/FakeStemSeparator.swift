// FakeStemSeparator — Test double for StemSeparating protocol.
// Returns canned stem data: copies input to drums stem, zeros others.
// Configurable via cannedStemData for custom test scenarios.

import Foundation
import Metal
@testable import Audio
@testable import Shared

@available(macOS 14.2, *)
final class FakeStemSeparator: StemSeparating, @unchecked Sendable {

    // MARK: - Tracking

    /// Number of times separate() was called.
    private(set) var separateCallCount = 0

    /// Last audio input received.
    private(set) var lastInputSampleCount = 0

    // MARK: - Configurable Output

    /// If set, separate() returns this instead of the default behavior.
    var cannedResult: StemSeparationResult?

    // MARK: - StemSeparating

    let stemLabels: [String] = ["vocals", "drums", "bass", "other"]
    let stemBuffers: [UMABuffer<Float>]

    init(device: MTLDevice, bufferCapacity: Int = 44100) throws {
        var buffers = [UMABuffer<Float>]()
        for _ in 0..<4 {
            buffers.append(try UMABuffer<Float>(device: device, capacity: bufferCapacity))
        }
        self.stemBuffers = buffers
    }

    func separate(audio: [Float], channelCount: Int, sampleRate: Float) throws -> StemSeparationResult {
        separateCallCount += 1
        lastInputSampleCount = audio.count

        if let canned = cannedResult {
            return canned
        }

        // Default behavior: mix to mono, put in drums stem (index 1), zero others.
        let frameCount: Int
        if channelCount >= 2 {
            frameCount = audio.count / channelCount
        } else {
            frameCount = audio.count
        }

        let monoCount = min(frameCount, stemBuffers[0].capacity)

        // Zero all buffers.
        for buf in stemBuffers {
            buf.write([Float](repeating: 0, count: monoCount))
        }

        // Copy mono-mixed audio to drums stem (index 1).
        if channelCount >= 2 {
            var mono = [Float](repeating: 0, count: monoCount)
            for i in 0..<monoCount {
                mono[i] = (audio[i * channelCount] + audio[i * channelCount + 1]) * 0.5
            }
            stemBuffers[1].write(mono)
        } else {
            stemBuffers[1].write(Array(audio.prefix(monoCount)))
        }

        let stemData = StemData(
            vocals: AudioFrame(sampleRate: sampleRate, sampleCount: UInt32(monoCount), channelCount: 1),
            drums: AudioFrame(sampleRate: sampleRate, sampleCount: UInt32(monoCount), channelCount: 1),
            bass: AudioFrame(sampleRate: sampleRate, sampleCount: UInt32(monoCount), channelCount: 1),
            other: AudioFrame(sampleRate: sampleRate, sampleCount: UInt32(monoCount), channelCount: 1)
        )

        return StemSeparationResult(stemData: stemData, sampleCount: monoCount)
    }
}
