// UMABufferTests — Verifies zero-copy UMA sharing between CPU and GPU,
// ring buffer behavior, and struct layout for GPU consumption.

import Testing
import Metal
@testable import Shared

// MARK: - Zero-Copy Verification

@Test func umaBufferZeroCopyCPUToGPU() async throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw TestError.noMetalDevice
    }

    let count = 256
    let input = try UMABuffer<Float>(device: device, capacity: count)
    let output = try UMABuffer<Float>(device: device, capacity: count)

    // CPU writes a known pattern.
    for i in 0..<count {
        input[i] = Float(i) * 2.0
    }

    // GPU reads input, doubles each value, writes to output — all zero-copy.
    let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;
    kernel void doubleValues(
        device const float* input  [[buffer(0)]],
        device float*       output [[buffer(1)]],
        uint id [[thread_position_in_grid]]
    ) {
        output[id] = input[id] * 2.0;
    }
    """

    let library = try await device.makeLibrary(source: shaderSource, options: nil)
    guard let function = library.makeFunction(name: "doubleValues") else {
        throw TestError.shaderCompilationFailed
    }
    let pipeline = try await device.makeComputePipelineState(function: function)
    guard let queue = device.makeCommandQueue(),
          let cmdBuf = queue.makeCommandBuffer(),
          let encoder = cmdBuf.makeComputeCommandEncoder() else {
        throw TestError.commandEncodingFailed
    }

    encoder.setComputePipelineState(pipeline)
    encoder.setBuffer(input.buffer, offset: 0, index: 0)
    encoder.setBuffer(output.buffer, offset: 0, index: 1)

    let threadsPerGroup = min(pipeline.maxTotalThreadsPerThreadgroup, count)
    encoder.dispatchThreads(
        MTLSize(width: count, height: 1, depth: 1),
        threadsPerThreadgroup: MTLSize(width: threadsPerGroup, height: 1, depth: 1)
    )
    encoder.endEncoding()
    cmdBuf.commit()
    await cmdBuf.completed()

    // CPU reads GPU-written output — same physical memory, no copy.
    for i in 0..<count {
        let expected = Float(i) * 4.0
        #expect(output[i] == expected, "Mismatch at index \(i): got \(output[i]), expected \(expected)")
    }
}

// MARK: - UMABuffer Basics

@Test func umaBufferWriteAndRead() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw TestError.noMetalDevice
    }

    let buf = try UMABuffer<UInt32>(device: device, capacity: 4)
    buf[0] = 10
    buf[1] = 20
    buf[2] = 30
    buf[3] = 40

    #expect(buf[0] == 10)
    #expect(buf[3] == 40)
    #expect(buf.capacity == 4)
    #expect(buf.byteLength == 4 * MemoryLayout<UInt32>.stride)
}

@Test func umaBufferBulkWrite() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw TestError.noMetalDevice
    }

    let buf = try UMABuffer<Float>(device: device, capacity: 8)
    buf.write([1.0, 2.0, 3.0, 4.0])
    buf.write([5.0, 6.0], offset: 4)

    #expect(buf[0] == 1.0)
    #expect(buf[3] == 4.0)
    #expect(buf[4] == 5.0)
    #expect(buf[5] == 6.0)
}

// MARK: - Ring Buffer

@Test func ringBufferBasicWriteRead() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw TestError.noMetalDevice
    }

    let ring = try UMARingBuffer<Float>(device: device, capacity: 4)
    #expect(ring.isEmpty)
    #expect(!ring.isFull)

    ring.write(1.0)
    ring.write(2.0)
    ring.write(3.0)

    #expect(ring.count == 3)
    #expect(ring.read(at: 0) == 1.0)  // oldest
    #expect(ring.read(at: 2) == 3.0)  // newest
}

@Test func ringBufferOverwrite() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw TestError.noMetalDevice
    }

    let ring = try UMARingBuffer<Float>(device: device, capacity: 4)

    // Fill completely.
    ring.write(contentsOf: [10, 20, 30, 40])
    #expect(ring.isFull)
    #expect(ring.count == 4)
    #expect(ring.read(at: 0) == 10)  // oldest
    #expect(ring.read(at: 3) == 40)  // newest

    // Overwrite oldest two.
    ring.write(50)
    ring.write(60)

    #expect(ring.count == 4)
    #expect(ring.read(at: 0) == 30)  // 10 and 20 were overwritten
    #expect(ring.read(at: 1) == 40)
    #expect(ring.read(at: 2) == 50)
    #expect(ring.read(at: 3) == 60)  // newest
}

@Test func ringBufferReset() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw TestError.noMetalDevice
    }

    let ring = try UMARingBuffer<Float>(device: device, capacity: 4)
    ring.write(contentsOf: [1, 2, 3])
    ring.reset()

    #expect(ring.isEmpty)
    #expect(ring.count == 0)
    #expect(ring.head == 0)
}

// MARK: - FeatureVector GPU Layout

@Test func featureVectorSizeAndAlignment() {
    // 32 floats × 4 bytes = 128 bytes after Increment 3.15, 16-byte aligned for GPU uniforms.
    #expect(MemoryLayout<FeatureVector>.size == 128)
    #expect(MemoryLayout<FeatureVector>.stride % 16 == 0)
}

@Test func featureVectorGPUUpload() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw TestError.noMetalDevice
    }

    let buf = try UMABuffer<FeatureVector>(device: device, capacity: 1)
    buf[0] = FeatureVector(bass: 0.8, mid: 0.5, treble: 0.3, time: 1.5)

    // Read back via raw float pointer to verify memory layout matches
    // what a Metal shader would see.
    let floatPtr = buf.buffer.contents().bindMemory(to: Float.self, capacity: 24)
    #expect(floatPtr[0] == 0.8)   // bass
    #expect(floatPtr[1] == 0.5)   // mid
    #expect(floatPtr[2] == 0.3)   // treble
    #expect(floatPtr[20] == 1.5)  // time (index 20 in the 24-float layout)
}

@Test func audioFrameLayout() {
    // AudioFrame: Double(8) + Float(4) + UInt32(4) + UInt32(4) + UInt32(4) = 24 bytes.
    #expect(MemoryLayout<AudioFrame>.size == 24)
}

@Test func fftResultLayout() {
    // FFTResult: UInt32(4) + Float(4) + Float(4) + Float(4) = 16 bytes.
    #expect(MemoryLayout<FFTResult>.size == 16)
    #expect(MemoryLayout<FFTResult>.stride % 4 == 0)
}

// MARK: - Helpers

enum TestError: Error {
    case noMetalDevice
    case shaderCompilationFailed
    case commandEncodingFailed
}
