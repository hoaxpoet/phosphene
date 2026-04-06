// MockAudioCapture — Test double for AudioCapturing protocol.
// Stores canned audio data and delivers it immediately on start().

import Foundation
@testable import Audio

@available(macOS 14.2, *)
final class MockAudioCapture: AudioCapturing, @unchecked Sendable {

    // MARK: - Canned Data

    /// The samples that will be delivered when startCapture() is called.
    var cannedSamples: [Float] = []

    // MARK: - Call Tracking

    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var lastCaptureMode: CaptureMode?

    // MARK: - AudioCapturing

    var onAudioBuffer: ((_ samples: UnsafePointer<Float>, _ sampleCount: Int,
                         _ sampleRate: Float, _ channelCount: UInt32) -> Void)?

    private(set) var isCapturing = false
    let sampleRate: Float = 48000
    let channelCount: UInt32 = 2

    func startCapture(mode: CaptureMode) throws {
        startCallCount += 1
        lastCaptureMode = mode
        isCapturing = true

        // Immediately deliver canned samples if available.
        if !cannedSamples.isEmpty {
            cannedSamples.withUnsafeBufferPointer { ptr in
                onAudioBuffer?(ptr.baseAddress!, ptr.count, sampleRate, channelCount)
            }
        }
    }

    func stopCapture() {
        stopCallCount += 1
        isCapturing = false
    }
}
