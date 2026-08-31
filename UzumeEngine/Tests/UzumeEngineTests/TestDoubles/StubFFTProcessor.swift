// StubFFTProcessor — Test double for FFTProcessing protocol.
// Returns pre-configured magnitude data without performing actual FFT.

import Foundation
import Metal
@testable import Audio
@testable import Shared

@available(macOS 14.2, *)
final class StubFFTProcessor: FFTProcessing, @unchecked Sendable {

    // MARK: - Configurable Output

    /// Pre-configured magnitudes returned by process(). Set before calling.
    var stubbedMagnitudes: [Float] = [Float](repeating: 0, count: 512)

    /// Pre-configured FFT result metadata.
    var stubbedResult = FFTResult()

    // MARK: - FFTProcessing

    let magnitudeBuffer: UMABuffer<Float>
    private(set) var latestResult = FFTResult()

    init(device: MTLDevice) throws {
        self.magnitudeBuffer = try UMABuffer<Float>(device: device, capacity: 512)
    }

    @discardableResult
    func process(samples: [Float], sampleRate: Float) -> FFTResult {
        magnitudeBuffer.write(stubbedMagnitudes)
        latestResult = stubbedResult
        return stubbedResult
    }

    @discardableResult
    func processStereo(interleavedSamples: [Float], sampleRate: Float) -> FFTResult {
        magnitudeBuffer.write(stubbedMagnitudes)
        latestResult = stubbedResult
        return stubbedResult
    }
}
