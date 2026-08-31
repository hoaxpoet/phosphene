// MARK: - FTR.28 pipeline compilation, relocated

// Moved out of `MeshGenerator.swift` at FTR.28 for the same reason `+Blend` and the `Result` split
// happened elsewhere: that file sits at its 400-line lint cap, and the gait needed four lines of
// state and a call site there. Compilation is the part with no relationship to per-frame drawing,
// so it is the right part to move.

import Foundation
import Metal
import Shared

extension MeshGenerator {

    // MARK: - Private Pipeline Compilation

    /// Compile the native mesh render pipeline (M3+).
    static func compileMeshPipeline(
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
    static func compileFallbackPipeline(
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
