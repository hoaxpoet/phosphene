// MetalContext — MTLDevice, MTLCommandQueue, pixel format selection, triple-buffered semaphore.
// All shared buffers use .storageModeShared (UMA zero-copy on Apple Silicon).

import Metal
import MetalKit

public final class MetalContext: Sendable {
    public let device: MTLDevice
    public let commandQueue: MTLCommandQueue
    public let pixelFormat: MTLPixelFormat

    /// Triple-buffered semaphore — allows up to 3 frames in flight
    /// before blocking the CPU, keeping the GPU pipeline saturated.
    public let inflightSemaphore = DispatchSemaphore(value: 3)

    public init() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw MetalContextError.noDevice
        }
        self.device = device

        guard let queue = device.makeCommandQueue() else {
            throw MetalContextError.noCommandQueue
        }
        self.commandQueue = queue

        // BGRa8 is the native CAMetalLayer format on macOS.
        // HDR (EDR) output will use .rgba16Float in a later increment.
        self.pixelFormat = .bgra8Unorm_srgb
    }

    /// Create a shared-mode buffer (UMA zero-copy). Never use .storageModeManaged.
    public func makeSharedBuffer(length: Int) -> MTLBuffer? {
        device.makeBuffer(length: length, options: .storageModeShared)
    }
}

public enum MetalContextError: Error, Sendable {
    case noDevice
    case noCommandQueue
}
