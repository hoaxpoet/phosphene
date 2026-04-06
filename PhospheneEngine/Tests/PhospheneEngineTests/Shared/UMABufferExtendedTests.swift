// UMABufferExtendedTests — Additional unit tests for UMABuffer and UMARingBuffer.
// Complements UMABufferTests.swift with capacity, alignment, storage mode, and concurrency tests.

import Testing
import Metal
@testable import Shared

@Test func test_init_withCapacity_allocatesCorrectByteCount() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw UMAExtendedTestError.noMetalDevice
    }

    let capacity = 256
    let buf = try UMABuffer<Float>(device: device, capacity: capacity)

    #expect(buf.capacity == capacity)
    #expect(buf.byteLength == capacity * MemoryLayout<Float>.stride)
    #expect(buf.buffer.length == capacity * MemoryLayout<Float>.stride)
}

@Test func test_storageMode_isShared() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw UMAExtendedTestError.noMetalDevice
    }

    let buf = try UMABuffer<Float>(device: device, capacity: 64)

    // UMA zero-copy requires .storageModeShared — never .managed or .private.
    #expect(buf.buffer.resourceOptions.contains(.storageModeShared),
            "UMABuffer must use .storageModeShared for zero-copy UMA access")
}

@Test func test_write_readBack_valuesMatch() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw UMAExtendedTestError.noMetalDevice
    }

    let buf = try UMABuffer<Float>(device: device, capacity: 8)
    let values: [Float] = [1.1, 2.2, 3.3, 4.4, 5.5, 6.6, 7.7, 8.8]
    buf.write(values)

    for i in 0..<values.count {
        #expect(buf[i] == values[i], "Mismatch at index \(i): got \(buf[i]), expected \(values[i])")
    }
}

@Test func test_write_gpuRead_valuesMatch() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw UMAExtendedTestError.noMetalDevice
    }

    let buf = try UMABuffer<Float>(device: device, capacity: 4)
    buf.write([10.0, 20.0, 30.0, 40.0])

    // Read through the raw buffer pointer (same path GPU would use).
    let rawPtr = buf.buffer.contents().bindMemory(to: Float.self, capacity: 4)
    #expect(rawPtr[0] == 10.0)
    #expect(rawPtr[1] == 20.0)
    #expect(rawPtr[2] == 30.0)
    #expect(rawPtr[3] == 40.0)
}

@Test func test_ringBuffer_overwrite_oldDataOverwritten() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw UMAExtendedTestError.noMetalDevice
    }

    let ring = try UMARingBuffer<Float>(device: device, capacity: 3)
    ring.write(contentsOf: [1.0, 2.0, 3.0])
    #expect(ring.isFull)

    // Writing one more should overwrite the oldest (1.0).
    ring.write(4.0)
    #expect(ring.read(at: 0) == 2.0, "Oldest should now be 2.0")
    #expect(ring.read(at: 2) == 4.0, "Newest should be 4.0")
}

@Test func test_ringBuffer_readLatest_returnsNewestSamples() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw UMAExtendedTestError.noMetalDevice
    }

    let ring = try UMARingBuffer<Float>(device: device, capacity: 8)
    ring.write(contentsOf: [10, 20, 30, 40, 50])

    // Newest is the last written value.
    #expect(ring.read(at: ring.count - 1) == 50, "Newest sample should be 50")
    #expect(ring.read(at: 0) == 10, "Oldest sample should be 10")
}

@Test func test_ringBuffer_capacity_neverExceeded() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw UMAExtendedTestError.noMetalDevice
    }

    let cap = 5
    let ring = try UMARingBuffer<Float>(device: device, capacity: cap)

    // Write way more than capacity.
    for i in 0..<100 {
        ring.write(Float(i))
        #expect(ring.count <= cap, "Count should never exceed capacity")
    }
    #expect(ring.count == cap)
}

@Test func test_typedPointer_alignment_isSIMDAligned() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw UMAExtendedTestError.noMetalDevice
    }

    let buf = try UMABuffer<Float>(device: device, capacity: 256)

    // Metal buffers are page-aligned on Apple Silicon (at least 16-byte aligned).
    let addr = UInt(bitPattern: buf.pointer.baseAddress!)
    #expect(addr % 16 == 0, "UMABuffer pointer should be at least 16-byte aligned for SIMD, got alignment \(addr % 16)")
}

@Test func test_reset_clearsAllData() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw UMAExtendedTestError.noMetalDevice
    }

    let ring = try UMARingBuffer<Float>(device: device, capacity: 8)
    ring.write(contentsOf: [1, 2, 3, 4, 5])

    #expect(ring.count == 5)
    ring.reset()

    #expect(ring.count == 0)
    #expect(ring.head == 0)
    #expect(ring.isEmpty)
}

@Test func test_concurrentWriteRead_noDataRace() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw UMAExtendedTestError.noMetalDevice
    }

    let buf = try UMABuffer<Float>(device: device, capacity: 1024)

    // Dispatch concurrent writes and reads — should not crash.
    // This is a smoke test; true race detection requires TSan.
    let group = DispatchGroup()
    let writeQueue = DispatchQueue(label: "test.write", attributes: .concurrent)
    let readQueue = DispatchQueue(label: "test.read", attributes: .concurrent)

    for i in 0..<100 {
        group.enter()
        writeQueue.async {
            buf[i % 1024] = Float(i)
            group.leave()
        }
    }

    for i in 0..<100 {
        group.enter()
        readQueue.async {
            _ = buf[i % 1024]
            group.leave()
        }
    }

    let result = group.wait(timeout: .now() + 5)
    #expect(result == .success, "Concurrent access should complete without deadlock")
}

enum UMAExtendedTestError: Error {
    case noMetalDevice
}
