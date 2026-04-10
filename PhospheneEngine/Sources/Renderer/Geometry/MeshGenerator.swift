// MeshGenerator — Mesh shader pipeline state management for Increment 3.2.
//
// Owns both the native Metal mesh shader pipeline (M3+, apple8 family) and
// the standard vertex shader fallback (M1/M2).  Detects hardware capability
// at init time and selects the appropriate pipeline transparently, so presets
// never need to branch on hardware tier.
//
// Usage:
//   let gen = try MeshGenerator(device: ctx.device, library: shaderLib.library,
//                               pixelFormat: ctx.pixelFormat)
//   // Each frame inside a render pass:
//   gen.draw(encoder: encoder, features: currentFeatures)

import Metal
import Shared
import os.log

private let logger = Logger(subsystem: "com.phosphene.renderer", category: "MeshGenerator")

// MARK: - MeshGeneratorConfiguration

/// CPU-side configuration for the mesh generator.
///
/// `maxVerticesPerMeshlet` and `maxPrimitivesPerMeshlet` are the per-meshlet
/// upper bounds that preset authors should use when declaring their MSL
/// `mesh<>` template parameters.  MeshGenerator's built-in infrastructure
/// shader uses a smaller triangle (3V, 1P) for testing; these constants govern
/// production preset geometry.
public struct MeshGeneratorConfiguration: Sendable {
    /// Maximum vertices per meshlet — must match the MSL `mesh<>` first template parameter.
    public let maxVerticesPerMeshlet: Int
    /// Maximum primitives per meshlet — must match the MSL `mesh<>` second template parameter.
    public let maxPrimitivesPerMeshlet: Int

    public init(maxVerticesPerMeshlet: Int = 256, maxPrimitivesPerMeshlet: Int = 512) {
        self.maxVerticesPerMeshlet  = maxVerticesPerMeshlet
        self.maxPrimitivesPerMeshlet = maxPrimitivesPerMeshlet
    }
}

// MARK: - MeshGenerator

/// Manages the mesh shader pipeline and dispatches draw calls.
///
/// On M3+ (`device.supportsFamily(.apple8)`), a `MTLMeshRenderPipelineDescriptor`
/// is compiled using `mesh_object_shader` + `mesh_shader` + `mesh_fragment`.
/// On M1/M2, a standard `MTLRenderPipelineDescriptor` using
/// `mesh_fallback_vertex` + `mesh_fragment` is compiled instead — the
/// draw call falls back to `drawPrimitives` automatically.
///
/// Both paths produce a single `MTLRenderPipelineState` stored in
/// `pipelineState`.  The `draw(encoder:features:)` method selects the
/// appropriate GPU command based on `usesMeshShaderPath`.
public final class MeshGenerator: @unchecked Sendable {

    // MARK: - Public Properties

    /// Active configuration (maxVerticesPerMeshlet, maxPrimitivesPerMeshlet).
    public let configuration: MeshGeneratorConfiguration

    /// `true` when the hardware supports native mesh shaders (apple8 family, M3+).
    /// `false` on M1/M2, where the vertex fallback pipeline is used.
    public let usesMeshShaderPath: Bool

    /// Compiled render pipeline state — either a mesh pipeline (M3+) or a
    /// standard vertex+fragment pipeline (M1/M2 fallback).
    public let pipelineState: MTLRenderPipelineState

    // MARK: - Private

    private let device: MTLDevice

    // MARK: - Init

    /// Create a mesh generator, selecting the appropriate pipeline for the hardware.
    ///
    /// - Parameters:
    ///   - device: Metal device for pipeline and buffer creation.
    ///   - library: Compiled Metal library containing the mesh shader functions
    ///     (`mesh_object_shader`, `mesh_shader`, `mesh_fragment`,
    ///     `mesh_fallback_vertex`).
    ///   - pixelFormat: Output pixel format for pipeline state creation.
    ///   - configuration: Per-meshlet vertex/primitive limits. Defaults to 256V/512P.
    public init(
        device: MTLDevice,
        library: MTLLibrary,
        pixelFormat: MTLPixelFormat,
        configuration: MeshGeneratorConfiguration = .init()
    ) throws {
        self.device        = device
        self.configuration = configuration

        let supportsMesh = device.supportsFamily(.apple8)
        self.usesMeshShaderPath = supportsMesh

        if supportsMesh {
            self.pipelineState = try Self.compileMeshPipeline(
                device: device, library: library, pixelFormat: pixelFormat
            )
            logger.info("MeshGenerator: native mesh shader path (apple8+)")
        } else {
            self.pipelineState = try Self.compileFallbackPipeline(
                device: device, library: library, pixelFormat: pixelFormat
            )
            logger.info("MeshGenerator: vertex fallback path (pre-apple8)")
        }
    }

    // MARK: - Draw

    /// Encode a mesh draw command into the given render encoder.
    ///
    /// Sets the pipeline state and dispatches geometry.  On M3+ this calls
    /// `drawMeshThreadgroups` (object → mesh → fragment); on M1/M2 this calls
    /// `drawPrimitives(.triangle)` with the fallback vertex shader.
    ///
    /// The encoder must already have a valid render pass active.
    ///
    /// - Parameters:
    ///   - encoder: Active render command encoder.
    ///   - features: Current audio feature vector — bound at fragment buffer(0).
    public func draw(encoder: MTLRenderCommandEncoder, features: FeatureVector) {
        encoder.setRenderPipelineState(pipelineState)
        var feat = features
        encoder.setFragmentBytes(&feat, length: MemoryLayout<FeatureVector>.stride, index: 0)

        if usesMeshShaderPath {
            // Native mesh dispatch: 1 object threadgroup → 1 mesh threadgroup of 3 threads.
            // The mesh shader (mesh_shader) runs 3 threads, one per vertex of the
            // infrastructure triangle.  Production presets scale this to fill meshlets.
            encoder.drawMeshThreadgroups(
                MTLSize(width: 1, height: 1, depth: 1),
                threadsPerObjectThreadgroup: MTLSize(width: 1, height: 1, depth: 1),
                threadsPerMeshThreadgroup:   MTLSize(width: 3, height: 1, depth: 1)
            )
        } else {
            // Vertex fallback: fullscreen triangle, 3 vertices.
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }
    }

    // MARK: - Private Pipeline Compilation

    /// Compile the native mesh render pipeline (M3+).
    private static func compileMeshPipeline(
        device: MTLDevice,
        library: MTLLibrary,
        pixelFormat: MTLPixelFormat
    ) throws -> MTLRenderPipelineState {
        guard let meshFn = library.makeFunction(name: "mesh_shader") else {
            throw MeshGeneratorError.functionNotFound("mesh_shader")
        }
        guard let fragmentFn = library.makeFunction(name: "mesh_fragment") else {
            throw MeshGeneratorError.functionNotFound("mesh_fragment")
        }
        // Object shader is optional; nil skips the object stage.
        let objectFn = library.makeFunction(name: "mesh_object_shader")

        let descriptor = MTLMeshRenderPipelineDescriptor()
        descriptor.objectFunction   = objectFn
        descriptor.meshFunction     = meshFn
        descriptor.fragmentFunction = fragmentFn
        descriptor.colorAttachments[0].pixelFormat = pixelFormat

        let (state, _) = try device.makeRenderPipelineState(descriptor: descriptor, options: [])
        return state
    }

    /// Compile the vertex-shader fallback pipeline (M1/M2).
    private static func compileFallbackPipeline(
        device: MTLDevice,
        library: MTLLibrary,
        pixelFormat: MTLPixelFormat
    ) throws -> MTLRenderPipelineState {
        guard let vertexFn = library.makeFunction(name: "mesh_fallback_vertex") else {
            throw MeshGeneratorError.functionNotFound("mesh_fallback_vertex")
        }
        guard let fragmentFn = library.makeFunction(name: "mesh_fragment") else {
            throw MeshGeneratorError.functionNotFound("mesh_fragment")
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction   = vertexFn
        descriptor.fragmentFunction = fragmentFn
        descriptor.colorAttachments[0].pixelFormat = pixelFormat

        return try device.makeRenderPipelineState(descriptor: descriptor)
    }
}

// MARK: - Errors

/// Errors thrown by `MeshGenerator.init`.
public enum MeshGeneratorError: Error, Sendable {
    /// A required Metal function was not found in the shader library.
    case functionNotFound(String)
    /// Pipeline state creation failed (Metal validation error details in associated value).
    case pipelineCreationFailed(String)
}
