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

        // Build the four stems: drums (index 1) = mono mix, others silent.
        var waveforms = [[Float]](repeating: [Float](repeating: 0, count: monoCount), count: 4)
        if channelCount >= 2 {
            var mono = [Float](repeating: 0, count: monoCount)
            for i in 0..<monoCount {
                mono[i] = (audio[i * channelCount] + audio[i * channelCount + 1]) * 0.5
            }
            waveforms[1] = mono
        } else {
            waveforms[1] = Array(audio.prefix(monoCount))
        }

        // Keep `stemBuffers` populated for buffer-reading tests; CLEAN.1.2 callers
        // read `stemWaveforms` by value instead.
        for (i, w) in waveforms.enumerated() {
            stemBuffers[i].write(w)
        }

        let stemData = StemData(
            vocals: AudioFrame(sampleRate: sampleRate, sampleCount: UInt32(monoCount), channelCount: 1),
            drums: AudioFrame(sampleRate: sampleRate, sampleCount: UInt32(monoCount), channelCount: 1),
            bass: AudioFrame(sampleRate: sampleRate, sampleCount: UInt32(monoCount), channelCount: 1),
            other: AudioFrame(sampleRate: sampleRate, sampleCount: UInt32(monoCount), channelCount: 1)
        )

        return StemSeparationResult(stemData: stemData, sampleCount: monoCount, stemWaveforms: waveforms)
    }
}
