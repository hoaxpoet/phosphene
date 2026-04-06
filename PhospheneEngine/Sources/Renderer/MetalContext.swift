// MetalContext — MTLDevice, MTLCommandQueue, pixel format selection, triple-buffered semaphore.
// All shared buffers use .storageModeShared (UMA zero-copy on Apple Silicon).

import Metal
import MetalKit
import os.log

private let logger = Logger(subsystem: "com.phosphene.renderer", category: "MetalContext")

// MARK: - MetalContext

/// Core Metal state shared across the rendering pipeline.
///
/// Holds the device, command queue, pixel format, and triple-buffered
/// semaphore. All buffer allocations use `.storageModeShared` for UMA
/// zero-copy on Apple Silicon.
public final class MetalContext: Sendable {

    // MARK: - Properties

    /// The system default Metal device.
    public let device: MTLDevice

    /// Serial command queue for submitting render work.
    public let commandQueue: MTLCommandQueue

    /// Output pixel format for all render targets.
    public let pixelFormat: MTLPixelFormat

    /// Maximum number of frames the CPU can prepare ahead of the GPU.
    private static let maxFramesInFlight = 3

    /// Triple-buffered semaphore — allows up to 3 frames in flight
    /// before blocking the CPU, keeping the GPU pipeline saturated.
    public let inflightSemaphore = DispatchSemaphore(value: maxFramesInFlight)

    // MARK: - Initialization

    /// Create a MetalContext using the system default GPU.
    ///
    /// - Throws: ``MetalContextError`` if no Metal device or command queue is available.
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

        logger.info("MetalContext initialized: \(device.name)")
    }

    // MARK: - Public API

    /// Create a shared-mode buffer (UMA zero-copy). Never use .storageModeManaged.
    ///
    /// - Parameter length: Buffer size in bytes.
    /// - Returns: A new shared-mode buffer, or nil if allocation fails.
    public func makeSharedBuffer(length: Int) -> MTLBuffer? {
        device.makeBuffer(length: length, options: .storageModeShared)
    }
}

// MARK: - MetalContextError

/// Errors during Metal initialization.
public enum MetalContextError: Error, Sendable {
    /// No Metal-capable GPU found on this system.
    case noDevice
    /// Failed to create a command queue from the device.
    case noCommandQueue
}
