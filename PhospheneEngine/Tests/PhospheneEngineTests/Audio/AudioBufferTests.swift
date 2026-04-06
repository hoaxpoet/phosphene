// AudioBufferTests — Unit tests for AudioBuffer ring buffer behavior.
// Split from AudioTests.swift for better organization.

import Testing
import Metal
@testable import Audio
@testable import Shared

// MARK: - AudioBuffer Tests

@Test func audioBufferWriteAndReadBack() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw AudioBufferTestError.noMetalDevice
    }

    let buffer = try AudioBuffer(device: device, capacity: 16)

    let samples: [Float] = [0.1, -0.2, 0.3, -0.4, 0.5, -0.6, 0.7, -0.8]
    let written = buffer.write(samples: samples)

    #expect(written == 8)
    #expect(buffer.sampleCount == 8)
    #expect(buffer.totalWritten == 8)
}

@Test func audioBufferRMSComputation() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw AudioBufferTestError.noMetalDevice
    }

    let buffer = try AudioBuffer(device: device, capacity: 16)

    // Write silence — RMS should be 0.
    buffer.write(samples: [0, 0, 0, 0])
    #expect(buffer.currentRMS == 0)

    // Write a known signal — all 0.5.
    buffer.write(samples: [0.5, 0.5, 0.5, 0.5])
    #expect(buffer.currentRMS == 0.5)
}

@Test func audioBufferLatestSamplesExtraction() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw AudioBufferTestError.noMetalDevice
    }

    let buffer = try AudioBuffer(device: device, capacity: 8)

    buffer.write(samples: [1, 2, 3, 4, 5, 6, 7, 8])

    // Extract last 4 samples.
    let latest = buffer.latestSamples(count: 4)
    #expect(latest.count == 4)
    #expect(latest == [5, 6, 7, 8])
}

@Test func audioBufferRingOverwrite() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw AudioBufferTestError.noMetalDevice
    }

    // Capacity 4 — writes beyond this overwrite oldest.
    let buffer = try AudioBuffer(device: device, capacity: 4)

    buffer.write(samples: [1, 2, 3, 4])
    buffer.write(samples: [5, 6])

    // Ring should now contain [5, 6, 3, 4] with head at 2,
    // but logical oldest→newest is [3, 4, 5, 6].
    let latest = buffer.latestSamples(count: 4)
    #expect(latest == [3, 4, 5, 6])
}

@Test func audioBufferReset() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw AudioBufferTestError.noMetalDevice
    }

    let buffer = try AudioBuffer(device: device, capacity: 16)
    buffer.write(samples: [1, 2, 3])
    buffer.reset()

    #expect(buffer.sampleCount == 0)
    #expect(buffer.totalWritten == 0)
    #expect(buffer.currentRMS == 0)
}

@Test func audioBufferMetalBufferBinding() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw AudioBufferTestError.noMetalDevice
    }

    let buffer = try AudioBuffer(device: device, capacity: 8)
    buffer.write(samples: [0.1, 0.2, 0.3, 0.4])

    // The metal buffer should be non-nil and have the right length.
    let mtlBuffer = buffer.metalBuffer
    #expect(mtlBuffer.length == 8 * MemoryLayout<Float>.stride)
}

// MARK: - Helpers

enum AudioBufferTestError: Error {
    case noMetalDevice
}
