// ProceduralGeometry — GPU compute pipeline for audio-reactive particle systems.
// Manages a UMA particle buffer and dispatches a Metal compute shader each frame.
// Drum stem onset triggers bursts; continuous energy drives ambient motion.

import Metal
import Shared
import os.log

private let logger = Logger(subsystem: "com.phosphene.renderer", category: "ProceduralGeometry")

// MARK: - Particle

/// Per-particle state, matching the MSL `Particle` struct layout (64 bytes).
///
/// Uses scalar floats (not SIMD) to match Metal's `packed_float3`/`packed_float4`
/// layout exactly — no alignment padding between fields.
@frozen
public struct Particle: Sendable {
    public var positionX: Float
    public var positionY: Float
    public var positionZ: Float
    public var life: Float
    public var velocityX: Float
    public var velocityY: Float
    public var velocityZ: Float
    public var size: Float
    public var colorR: Float
    public var colorG: Float
    public var colorB: Float
    public var colorA: Float
    public var seed: Float
    public var age: Float
    // swiftlint:disable:next identifier_name
    public var _pad0: Float
    // swiftlint:disable:next identifier_name
    public var _pad1: Float

    public init(
        positionX: Float = 0, positionY: Float = 0, positionZ: Float = 0,
        life: Float = 0,
        velocityX: Float = 0, velocityY: Float = 0, velocityZ: Float = 0,
        size: Float = 1,
        colorR: Float = 0, colorG: Float = 0, colorB: Float = 0, colorA: Float = 1,
        seed: Float = 0, age: Float = 0
    ) {
        self.positionX = positionX
        self.positionY = positionY
        self.positionZ = positionZ
        self.life = life
        self.velocityX = velocityX
        self.velocityY = velocityY
        self.velocityZ = velocityZ
        self.size = size
        self.colorR = colorR
        self.colorG = colorG
        self.colorB = colorB
        self.colorA = colorA
        self.seed = seed
        self.age = age
        self._pad0 = 0
        self._pad1 = 0
    }
}

// MARK: - ParticleConfiguration

/// CPU-side configuration for the particle system.
public struct ParticleConfiguration: Sendable {
    /// Number of particles in the buffer.
    public var particleCount: Int
    /// Life decay per second. Higher = shorter particle lifetime.
    public var decayRate: Float
    /// Minimum beat strength (0–1) to trigger particle respawning.
    public var burstThreshold: Float
    /// Base velocity magnitude on spawn.
    public var burstVelocity: Float
    /// Velocity damping per second (0 = no drag).
    public var drag: Float

    public init(
        particleCount: Int = 65_536,
        decayRate: Float = 1.8,
        burstThreshold: Float = 0.15,
        burstVelocity: Float = 3.5,
        drag: Float = 2.5
    ) {
        self.particleCount = particleCount
        self.decayRate = decayRate
        self.burstThreshold = burstThreshold
        self.burstVelocity = burstVelocity
        self.drag = drag
    }
}

// MARK: - ParticleConfig (Metal-side)

/// GPU-side configuration struct matching MSL `ParticleConfig` layout (32 bytes).
struct ParticleConfig {
    var particleCount: UInt32
    var decayRate: Float
    var burstThreshold: Float
    var burstVelocity: Float
    var drag: Float
    var time: Float
    // swiftlint:disable:next identifier_name
    var _pad0: Float
    // swiftlint:disable:next identifier_name
    var _pad1: Float
}

// MARK: - ProceduralGeometry

/// GPU compute pipeline for audio-reactive particles.
///
/// Allocates a `.storageModeShared` particle buffer (UMA zero-copy)
/// and dispatches the `particle_update` compute kernel each frame.
///
/// Usage:
/// ```swift
/// let geometry = try ProceduralGeometry(device: ctx.device, library: shaderLib.library,
///                                       configuration: .init(particleCount: 1_000_000))
/// // Each frame:
/// geometry.update(features: currentFeatures, commandBuffer: cmdBuf)
/// ```
public final class ProceduralGeometry: @unchecked Sendable {

    // MARK: - Properties

    /// UMA particle buffer — written by compute shader, readable by CPU and render shaders.
    public let particleBuffer: MTLBuffer

    /// Active configuration.
    public let configuration: ParticleConfiguration

    /// Compiled compute pipeline state for the particle update kernel.
    private let computePipelineState: MTLComputePipelineState

    /// Compiled render pipeline state for particle point-sprite drawing (additive blend).
    /// Nil when created without a pixelFormat (compute-only mode, e.g. tests).
    private let renderPipelineState: MTLRenderPipelineState?

    /// Metal device reference.
    private let device: MTLDevice

    // MARK: - Init

    /// Create a particle system with the given configuration.
    ///
    /// - Parameters:
    ///   - device: Metal device for buffer and pipeline creation.
    ///   - library: Compiled Metal library containing `particle_update`, `particle_vertex`, `particle_fragment`.
    ///   - configuration: Particle count and behavior parameters.
    ///   - pixelFormat: Output pixel format for the render pipeline. Pass `nil` for compute-only mode (tests).
    public init(
        device: MTLDevice,
        library: MTLLibrary,
        configuration: ParticleConfiguration,
        pixelFormat: MTLPixelFormat? = nil
    ) throws {
        self.device = device
        self.configuration = configuration

        // Allocate particle buffer — .storageModeShared for UMA zero-copy.
        let stride = MemoryLayout<Particle>.stride
        let bufferSize = configuration.particleCount * stride
        guard let buffer = device.makeBuffer(length: bufferSize, options: .storageModeShared) else {
            throw ProceduralGeometryError.bufferAllocationFailed
        }
        self.particleBuffer = buffer

        // Initialize particles with unique seeds, spread in a cloud around the origin.
        // This gives the flock a visible starting shape rather than all at (0,0,0).
        let ptr = buffer.contents().bindMemory(to: Particle.self, capacity: configuration.particleCount)
        let count = Float(configuration.particleCount)
        for i in 0..<configuration.particleCount {
            let seed = Float(i) / count
            // Spread particles in a disk using golden-angle distribution.
            let angle = seed * Float.pi * 2.0 * 137.508  // Golden angle spiral.
            let radius = sqrt(seed) * 1.5  // Uniform disk distribution.
            var particle = Particle(
                positionX: cos(angle) * radius,
                positionY: sin(angle) * radius,
                positionZ: 0,
                life: 1.0,  // Start alive.
                seed: seed
            )
            // Give initial tangential velocity so the flock is already swirling.
            let tangentX = -sin(angle) * 0.5
            let tangentY = cos(angle) * 0.5
            particle.velocityX = tangentX
            particle.velocityY = tangentY
            ptr[i] = particle
        }

        // Create compute pipeline from the particle_update kernel.
        guard let computeFn = library.makeFunction(name: "particle_update") else {
            throw ProceduralGeometryError.functionNotFound("particle_update")
        }
        self.computePipelineState = try device.makeComputePipelineState(function: computeFn)

        // Create render pipeline with additive blending (if pixelFormat provided).
        if let pixelFormat {
            guard let vertexFn = library.makeFunction(name: "particle_vertex"),
                  let fragmentFn = library.makeFunction(name: "particle_fragment") else {
                throw ProceduralGeometryError.functionNotFound("particle_vertex/particle_fragment")
            }

            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertexFn
            descriptor.fragmentFunction = fragmentFn
            descriptor.colorAttachments[0].pixelFormat = pixelFormat

            // Standard alpha blending — birds are dark silhouettes over the sky.
            descriptor.colorAttachments[0].isBlendingEnabled = true
            descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            descriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
            descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

            self.renderPipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
        } else {
            self.renderPipelineState = nil
        }

        logger.info("ProceduralGeometry initialized: \(configuration.particleCount) particles, \(bufferSize) bytes")
    }

    // MARK: - Update

    /// Dispatch the particle compute shader for one frame.
    ///
    /// Encodes a compute command into the provided command buffer.
    /// The caller is responsible for committing the command buffer.
    ///
    /// - Parameters:
    ///   - features: Current audio feature vector.
    ///   - commandBuffer: Active command buffer to encode into.
    public func update(features: FeatureVector, commandBuffer: MTLCommandBuffer) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            logger.error("Failed to create compute command encoder")
            return
        }

        var config = ParticleConfig(
            particleCount: UInt32(configuration.particleCount),
            decayRate: configuration.decayRate,
            burstThreshold: configuration.burstThreshold,
            burstVelocity: configuration.burstVelocity,
            drag: configuration.drag,
            time: features.time,
            _pad0: 0,
            _pad1: 0
        )
        var feat = features

        encoder.setComputePipelineState(computePipelineState)
        encoder.setBuffer(particleBuffer, offset: 0, index: 0)
        encoder.setBytes(&feat, length: MemoryLayout<FeatureVector>.stride, index: 1)
        encoder.setBytes(&config, length: MemoryLayout<ParticleConfig>.stride, index: 2)

        // Dispatch one thread per particle.
        let threadgroupSize = min(computePipelineState.maxTotalThreadsPerThreadgroup, 256)
        let threadgroupCount = (configuration.particleCount + threadgroupSize - 1) / threadgroupSize

        encoder.dispatchThreadgroups(
            MTLSize(width: threadgroupCount, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: threadgroupSize, height: 1, depth: 1)
        )

        encoder.endEncoding()
    }

    // MARK: - Render

    /// Draw all particles as point sprites using the render command encoder.
    ///
    /// Call this AFTER `update(features:commandBuffer:)` within the same command buffer.
    /// The render encoder must already have a render pass descriptor configured.
    /// Additive blending is baked into the render pipeline state.
    ///
    /// - Parameters:
    ///   - encoder: Active render command encoder.
    ///   - features: Current audio feature vector (for vertex shader access).
    public func render(encoder: MTLRenderCommandEncoder, features: FeatureVector) {
        guard let renderState = renderPipelineState else {
            logger.warning("render() called without render pipeline state (compute-only mode)")
            return
        }

        var feat = features
        encoder.setRenderPipelineState(renderState)
        encoder.setVertexBuffer(particleBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&feat, length: MemoryLayout<FeatureVector>.stride, index: 1)
        encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: configuration.particleCount)
    }
}

// MARK: - Errors

public enum ProceduralGeometryError: Error, Sendable {
    /// Metal buffer allocation failed (likely out of memory).
    case bufferAllocationFailed
    /// Named compute kernel not found in the shader library.
    case functionNotFound(String)
}
