// MetalContextTests — Unit tests for MetalContext initialization and configuration.

import Testing
import Metal
@testable import Renderer

@Test func test_init_createsDevice_deviceIsNotNil() throws {
    let ctx = try MetalContext()
    #expect(ctx.device.name.isEmpty == false, "Device should have a name")
}

@Test func test_init_createsCommandQueue_queueIsNotNil() throws {
    let ctx = try MetalContext()
    // CommandQueue is non-optional after init, but verify it can create command buffers.
    let cmdBuf = ctx.commandQueue.makeCommandBuffer()
    #expect(cmdBuf != nil, "CommandQueue should produce command buffers")
}

@Test func test_pixelFormat_defaultsBGRA8Unorm() throws {
    let ctx = try MetalContext()
    #expect(ctx.pixelFormat == .bgra8Unorm_srgb,
            "Default pixel format should be .bgra8Unorm_srgb, got \(ctx.pixelFormat)")
}

@Test func test_semaphore_tripleBuffered_maxConcurrentFramesIs3() throws {
    let ctx = try MetalContext()

    // The semaphore is initialized with value 3 (triple buffering).
    // We should be able to wait() 3 times without blocking.
    // Use a short timeout to avoid hanging if this fails.
    var acquired = 0
    for _ in 0..<3 {
        let result = ctx.inflightSemaphore.wait(timeout: .now())
        if result == .success {
            acquired += 1
        }
    }
    #expect(acquired == 3, "Should acquire 3 semaphore slots (triple buffering), got \(acquired)")

    // A 4th wait should time out.
    let result = ctx.inflightSemaphore.wait(timeout: .now())
    #expect(result == .timedOut, "4th wait should time out (only 3 slots)")

    // Release all 3 so we don't leave state dirty.
    for _ in 0..<3 {
        ctx.inflightSemaphore.signal()
    }
}
