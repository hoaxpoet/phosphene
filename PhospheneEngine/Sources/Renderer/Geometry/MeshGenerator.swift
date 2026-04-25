// MeshGenerator — Mesh shader pipeline state management for Increment 3.2.
//
// Owns both the native Metal mesh shader pipeline (M3+, apple8 family) and
// the standard vertex shader fallback (M1/M2).  Detects hardware capability
// at init time and selects the appropriate pipeline transparently, so presets
// never need to branch on hardware tier.
//
// Usage (infrastructure shader):
//   let gen = try MeshGenerator(device: ctx.device, library: shaderLib.library,
//                               pixelFormat: ctx.pixelFormat)
//
// Usage (preset shader compiled by PresetLoader):
//   let gen = MeshGenerator(device: ctx.device, pipelineState: preset.pipelineState,
//                           configuration: .init(meshThreadCount: 64))
//
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
///
/// `meshThreadCount` must match the `max_total_threads_per_threadgroup` attribute
/// on the preset's `[[mesh]]` function.  `objectThreadCount` must match the
/// `max_total_threads_per_threadgroup` attribute on the `[[object]]` function.
public struct MeshGeneratorConfiguration: Sendable {
    /// Maximum vertices per meshlet — must match the MSL `mesh<>` first template parameter.
    public let maxVerticesPerMeshlet: Int
    /// Maximum primitives per meshlet — must match the MSL `mesh<>` second template parameter.
    public let maxPrimitivesPerMeshlet: Int
    /// Threads per mesh threadgroup — must match `[[mesh, max_total_threads_per_threadgroup(N)]]`.
    /// Default 3 matches the infrastructure test triangle shader.
    public let meshThreadCount: Int
    /// Threads per object threadgroup — must match `[[object, max_total_threads_per_threadgroup(N)]]`.
    /// Default 1 is correct for all current preset object shaders.
    public let objectThreadCount: Int

    public init(
        maxVerticesPerMeshlet: Int = 256,
        maxPrimitivesPerMeshlet: Int = 512,
        meshThreadCount: Int = 3,
        objectThreadCount: Int = 1
    ) {
        self.maxVerticesPerMeshlet  = maxVerticesPerMeshlet
        self.maxPrimitivesPerMeshlet = maxPrimitivesPerMeshlet
        self.meshThreadCount        = meshThreadCount
        self.objectThreadCount      = objectThreadCount
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

    /// Active configuration (maxVerticesPerMeshlet, maxPrimitivesPerMeshlet, thread counts).
    public let configuration: MeshGeneratorConfiguration

    /// `true` when the hardware supports native mesh shaders (apple8 family, M3+).
    /// `false` on M1/M2, where the vertex fallback pipeline is used.
    public let usesMeshShaderPath: Bool

    /// Compiled render pipeline state — either a mesh pipeline (M3+) or a
    /// standard vertex+fragment pipeline (M1/M2 fallback).
    public let pipelineState: MTLRenderPipelineState

    // MARK: - Frame Budget Governor Gate (D-057)

    /// Mesh density multiplier for the frame-budget governor.
    /// Default `1.0` = full geometry. `0.5` = reduced density.
    ///
    /// On M3+ (native mesh shader path), this value is passed to the object and
    /// mesh stages via `setObjectBytes`/`setMeshBytes` at buffer index 1 so
    /// preset shaders can opt-in to read it and adjust their geometry emission.
    /// On M1/M2 (vertex fallback: fullscreen triangle), this flag is a documented
    /// no-op — the triangle vertex count is fixed. Set by `RenderPipeline.applyQualityLevel`.
    /// See D-057(e) for rationale on why the M1/M2 path is accepted as a no-op.
    public var densityMultiplier: Float = 1.0

    // MARK: - Private

    private let device: MTLDevice

    // MARK: - Init (infrastructure shader)

    /// Create a mesh generator, selecting the appropriate pipeline for the hardware.
    ///
    /// Compiles the infrastructure mesh shader from the provided `library`
    /// (`mesh_object_shader`, `mesh_shader`, `mesh_fragment`, `mesh_fallback_vertex`).
    /// Use the `init(device:pipelineState:configuration:)` overload for preset shaders
    /// already compiled by `PresetLoader`.
    ///
    /// - Parameters:
    ///   - device: Metal device for pipeline and buffer creation.
    ///   - library: Compiled Metal library containing the infrastructure mesh functions.
    ///   - pixelFormat: Output pixel format for pipeline state creation.
    ///   - configuration: Per-meshlet vertex/primitive limits. Defaults to 256V/512P/3T.
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

    // MARK: - Init (preset shader — pre-compiled by PresetLoader)

    /// Create a mesh generator wrapping a pre-compiled pipeline state.
    ///
    /// Use this initialiser for preset shaders that were already compiled by
    /// `PresetLoader.compileMeshShader`.  The pipeline state contains the correct
    /// shader functions for the current hardware tier (mesh on M3+, vertex fallback
    /// on M1/M2) — `MeshGenerator` simply wraps it and drives the draw dispatch.
    ///
    /// - Parameters:
    ///   - device: Metal device (used to detect hardware tier for dispatch selection).
    ///   - pipelineState: Pre-compiled pipeline state from `PresetLoader`.
    ///   - configuration: Per-meshlet limits and thread counts.  `meshThreadCount` must
    ///     match the preset's `[[mesh, max_total_threads_per_threadgroup(N)]]` attribute.
    public init(
        device: MTLDevice,
        pipelineState: MTLRenderPipelineState,
        configuration: MeshGeneratorConfiguration = .init()
    ) {
        self.device             = device
        self.configuration      = configuration
        self.usesMeshShaderPath = device.supportsFamily(.apple8)
        self.pipelineState      = pipelineState
        logger.info("MeshGenerator: wrapped preset pipeline (mesh path: \(device.supportsFamily(.apple8)))")
    }

    // MARK: - Draw

    /// Encode a mesh draw command into the given render encoder.
    ///
    /// Sets the pipeline state and dispatches geometry.  On M3+ this calls
    /// `drawMeshThreadgroups` (object → mesh → fragment) using thread counts from
    /// `configuration`; on M1/M2 this calls `drawPrimitives(.triangle)` with the
    /// fallback vertex shader.
    ///
    /// On M3+, `FeatureVector` is bound at buffer(0) for all three shader stages
    /// (object, mesh, fragment) so preset shaders can read audio data at any stage.
    /// On M1/M2, only the fragment stage binding is set (object/mesh stages are not
    /// active with the vertex fallback pipeline).
    ///
    /// The encoder must already have a valid render pass active.
    ///
    /// - Parameters:
    ///   - encoder: Active render command encoder.
    ///   - features: Current audio feature vector — bound at buffer(0) for all stages.
    public func draw(encoder: MTLRenderCommandEncoder, features: FeatureVector) {
        encoder.setRenderPipelineState(pipelineState)
        var feat = features

        if usesMeshShaderPath {
            // Bind features to all mesh-pipeline stages so preset shaders can read
            // audio data from the object, mesh, or fragment stage as needed.
            encoder.setObjectBytes(&feat, length: MemoryLayout<FeatureVector>.stride, index: 0)
            encoder.setMeshBytes(&feat, length: MemoryLayout<FeatureVector>.stride, index: 0)
            // Pass density multiplier at buffer(1) so preset mesh shaders can
            // opt-in to reduce geometry emission. D-057.
            var density = densityMultiplier
            encoder.setObjectBytes(&density, length: MemoryLayout<Float>.stride, index: 1)
            encoder.setMeshBytes(&density, length: MemoryLayout<Float>.stride, index: 1)
        }
        encoder.setFragmentBytes(&feat, length: MemoryLayout<FeatureVector>.stride, index: 0)

        if usesMeshShaderPath {
            // Native mesh dispatch using per-preset thread counts from configuration.
            encoder.drawMeshThreadgroups(
                MTLSize(width: 1, height: 1, depth: 1),
                threadsPerObjectThreadgroup: MTLSize(
                    width: configuration.objectThreadCount, height: 1, depth: 1
                ),
                threadsPerMeshThreadgroup: MTLSize(
                    width: configuration.meshThreadCount, height: 1, depth: 1
                )
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
