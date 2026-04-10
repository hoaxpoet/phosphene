// BVHBuilder — Builds MTLPrimitiveAccelerationStructure (BVH) from triangle geometry.
//
// Provides two build paths:
//
//   build(triangles:)
//     Synchronous convenience for tests and initial one-off loads.
//     Blocks the calling thread until the GPU finishes.
//
//   encodeBuild(triangles:into:)
//     Encodes the BVH build into a caller-provided command buffer without
//     waiting.  Use this from render-loop callbacks when geometry changes per
//     frame in response to audio (stems, beats, FFT).  Encode the build first,
//     then encode RayIntersector.encodeNearestHit / encodeShadow in the SAME
//     command buffer — Metal serialises within a single command buffer, so no
//     explicit event synchronisation is needed.
//
// All GPU buffers use .storageModeShared (UMA zero-copy on Apple Silicon).
// The scratch buffer used during build is .storageModePrivate (GPU-only).
//
// Requires device.supportsRaytracing (true on all Apple Silicon running macOS 11+).

import Metal
import os.log

private let logger = Logger(subsystem: "com.phosphene.renderer", category: "BVHBuilder")

// MARK: - BVHBuilderError

/// Errors thrown by ``BVHBuilder``.
public enum BVHBuilderError: Error, Sendable {
    /// The device does not support Metal ray tracing.
    case raytracingNotSupported
    /// Vertex buffer allocation failed.
    case vertexBufferAllocationFailed
    /// Scratch buffer allocation failed.
    case scratchBufferAllocationFailed
    /// Acceleration structure allocation failed.
    case accelerationStructureAllocationFailed
    /// Failed to create an internal command buffer.
    case commandBufferCreationFailed
}

// MARK: - BVHBuilder

/// Builds and maintains a Metal primitive acceleration structure from triangle geometry.
///
/// ## Dynamic geometry
/// For audio-reactive geometry that changes each render frame, call
/// ``encodeBuild(triangles:into:)`` at the top of the frame's command buffer,
/// then encode intersection work in the same command buffer.  This keeps the
/// BVH rebuild on the GPU timeline with no CPU-GPU synchronisation stall.
///
/// ## Static / infrequent updates
/// Call the blocking ``build(triangles:)`` convenience wrapper.  It submits
/// the build to an internal command queue and waits for completion — not suitable
/// for per-frame use at 60fps.
///
/// Thread-safe: all mutation is guarded by an internal lock.
public final class BVHBuilder: @unchecked Sendable {

    // MARK: - Types

    /// A single triangle defined by three world-space vertex positions.
    public struct Triangle: Sendable {
        /// First vertex position.
        public let v0: SIMD3<Float>
        /// Second vertex position.
        public let v1: SIMD3<Float>
        /// Third vertex position.
        public let v2: SIMD3<Float>

        /// Create a triangle from three world-space vertex positions.
        public init(v0: SIMD3<Float>, v1: SIMD3<Float>, v2: SIMD3<Float>) {
            self.v0 = v0
            self.v1 = v1
            self.v2 = v2
        }
    }

    // MARK: - Properties

    /// The Metal device used for buffer and structure creation.
    public let device: MTLDevice

    /// The most recently built acceleration structure, or `nil` if the geometry was
    /// empty or a build has not yet completed.
    ///
    /// After ``build(triangles:)`` this is immediately valid.
    /// After ``encodeBuild(triangles:into:)`` it is valid once the caller's command
    /// buffer has completed on the GPU.
    public private(set) var accelerationStructure: MTLAccelerationStructure?

    /// Number of triangles in the most recently built structure. 0 if none.
    public private(set) var triangleCount: Int = 0

    private let internalCommandQueue: MTLCommandQueue
    private let lock = NSLock()

    // MARK: - Initialization

    /// Create a BVH builder.
    ///
    /// - Parameter device: Metal device on which BVH builds will execute.
    /// - Throws: ``BVHBuilderError/raytracingNotSupported`` if the device does not
    ///   support Metal ray tracing.
    public init(device: MTLDevice) throws {
        guard device.supportsRaytracing else {
            throw BVHBuilderError.raytracingNotSupported
        }
        self.device = device
        // Internal queue for the blocking build() convenience path only.
        self.internalCommandQueue = try Self.makeCommandQueue(device: device)
    }

    private static func makeCommandQueue(device: MTLDevice) throws -> MTLCommandQueue {
        guard let queue = device.makeCommandQueue() else {
            throw BVHBuilderError.commandBufferCreationFailed
        }
        return queue
    }

    // MARK: - Synchronous Build (tests / initial loads)

    /// Build a BVH from the given triangles, blocking until the GPU finishes.
    ///
    /// Suitable for initial scene setup or infrequent updates.  Not suitable for
    /// per-frame dynamic geometry — use ``encodeBuild(triangles:into:)`` instead.
    ///
    /// Empty geometry is handled gracefully — ``accelerationStructure`` is set to `nil`.
    ///
    /// - Parameter triangles: World-space triangles to include in the BVH.
    public func build(triangles: [Triangle]) {
        lock.withLock {
            guard !triangles.isEmpty else {
                accelerationStructure = nil
                triangleCount = 0
                logger.debug("BVHBuilder.build: empty geometry — accelerationStructure set to nil")
                return
            }

            guard let cmdBuf = internalCommandQueue.makeCommandBuffer() else {
                logger.error("BVHBuilder.build: failed to create internal command buffer")
                return
            }

            if encodeInternal(triangles: triangles, into: cmdBuf) {
                cmdBuf.commit()
                cmdBuf.waitUntilCompleted()
                if let err = cmdBuf.error {
                    logger.error("BVHBuilder.build: GPU error — \(err.localizedDescription)")
                }
            }
        }
    }

    /// Rebuild the BVH with new geometry, replacing the previous structure.
    ///
    /// Convenience alias for ``build(triangles:)``.
    ///
    /// - Parameter triangles: New triangle geometry.
    public func rebuild(triangles: [Triangle]) {
        build(triangles: triangles)
    }

    // MARK: - Async Encode (render-loop / dynamic geometry)

    /// Encode a BVH build into a caller-provided command buffer without blocking.
    ///
    /// The new ``accelerationStructure`` is valid for binding once the command buffer
    /// completes on the GPU.  Encode all intersection work that depends on this BVH
    /// **in the same command buffer** — Metal serialises within a single command buffer,
    /// so no explicit event or fence is needed.
    ///
    /// Typical render-loop usage:
    /// ```swift
    /// let cmdBuf = commandQueue.makeCommandBuffer()!
    /// bvhBuilder.encodeBuild(triangles: audioGeometry, into: cmdBuf)
    /// rayIntersector.encodeShadow(..., into: cmdBuf)
    /// // ... render pass ...
    /// cmdBuf.commit()
    /// ```
    ///
    /// - Parameters:
    ///   - triangles: World-space triangles for the new BVH.
    ///   - commandBuffer: The command buffer to encode into.
    /// - Returns: `true` if encoding succeeded; `false` if buffer allocation failed.
    @discardableResult
    public func encodeBuild(triangles: [Triangle], into commandBuffer: MTLCommandBuffer) -> Bool {
        lock.withLock {
            guard !triangles.isEmpty else {
                accelerationStructure = nil
                triangleCount = 0
                return true
            }
            return encodeInternal(triangles: triangles, into: commandBuffer)
        }
    }

    // MARK: - Private

    /// Core build encoder shared by both the synchronous and async paths.
    /// Must be called under `lock`.
    @discardableResult
    private func encodeInternal(triangles: [Triangle], into cmdBuf: MTLCommandBuffer) -> Bool {
        // Pack vertices as tightly-packed float3 (12 bytes per vertex).
        // Swift's SIMD3<Float> is 16 bytes (aligned), so unpack to bare Floats.
        var packed = [Float]()
        packed.reserveCapacity(triangles.count * 9)
        for tri in triangles {
            packed += [tri.v0.x, tri.v0.y, tri.v0.z,
                       tri.v1.x, tri.v1.y, tri.v1.z,
                       tri.v2.x, tri.v2.y, tri.v2.z]
        }

        let vBufLen = packed.count * MemoryLayout<Float>.stride
        guard let vertexBuffer = device.makeBuffer(
            bytes: packed, length: vBufLen, options: .storageModeShared
        ) else {
            logger.error("BVHBuilder: vertex buffer allocation failed (\(vBufLen) bytes)")
            return false
        }

        // Describe the triangle geometry.
        let geomDesc = MTLAccelerationStructureTriangleGeometryDescriptor()
        geomDesc.vertexBuffer = vertexBuffer
        geomDesc.vertexStride = 3 * MemoryLayout<Float>.stride  // 12 bytes (packed float3)
        geomDesc.triangleCount = triangles.count

        let primDesc = MTLPrimitiveAccelerationStructureDescriptor()
        primDesc.geometryDescriptors = [geomDesc]

        // Query sizes from Metal.
        let sizes = device.accelerationStructureSizes(descriptor: primDesc)

        guard let structure: MTLAccelerationStructure = device.makeAccelerationStructure(
            size: sizes.accelerationStructureSize
        ) else {
            let bytes = sizes.accelerationStructureSize
            logger.error("BVHBuilder: acceleration structure allocation failed (\(bytes) bytes)")
            return false
        }

        // Scratch buffer is GPU-only during build — discard afterwards.
        guard let scratch = device.makeBuffer(
            length: sizes.buildScratchBufferSize, options: .storageModePrivate
        ) else {
            logger.error("BVHBuilder: scratch buffer allocation failed (\(sizes.buildScratchBufferSize) bytes)")
            return false
        }

        guard let encoder = cmdBuf.makeAccelerationStructureCommandEncoder() else {
            logger.error("BVHBuilder: failed to create acceleration structure command encoder")
            return false
        }

        encoder.build(
            accelerationStructure: structure,
            descriptor: primDesc,
            scratchBuffer: scratch,
            scratchBufferOffset: 0
        )
        encoder.endEncoding()

        accelerationStructure = structure
        triangleCount = triangles.count
        logger.info("BVHBuilder: encoded BVH build — \(triangles.count) triangle(s)")
        return true
    }
}
