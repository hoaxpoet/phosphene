// PresetLoader+Mesh — Mesh shader preset compilation for Increment 3.2.
//
// Extracted from PresetLoader.swift to keep that file within SwiftLint's
// file_length limit. Contains the compileMeshShader method and its helpers.

import Metal
import os.log

private let meshLogger = Logger(subsystem: "com.phosphene.presets", category: "PresetLoader")

extension PresetLoader {

    /// Compile a mesh shader preset.
    ///
    /// On M3+ (`device.supportsFamily(.apple8)`), uses `MTLMeshRenderPipelineDescriptor`
    /// with the object, mesh, and fragment functions derived by convention from the
    /// preset's fragment function name (replacing the `_fragment` suffix with
    /// `_object_shader`, `_mesh_shader`).
    ///
    /// On M1/M2, falls back to a standard vertex+fragment pipeline using
    /// `descriptor.vertexFunction` + `descriptor.fragmentFunction` so the preset
    /// degrades gracefully without crashing.
    func compileMeshShader(
        at url: URL, descriptor: PresetDescriptor
    ) -> (standard: MTLRenderPipelineState, feedback: MTLRenderPipelineState?)? {
        guard let fragmentSource = try? String(contentsOf: url, encoding: .utf8) else {
            meshLogger.error("Could not read shader file: \(url.lastPathComponent)")
            return nil
        }

        let fullSource = Self.shaderPreamble + "\n\n" + fragmentSource
        let options = MTLCompileOptions()
        options.fastMathEnabled = true
        options.languageVersion = .version3_1

        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: fullSource, options: options)
        } catch {
            meshLogger.error("Mesh shader compilation failed for \(url.lastPathComponent): \(error)")
            return nil
        }

        let fragmentName = descriptor.fragmentFunction
        let meshName = fragmentName.replacingOccurrences(of: "_fragment", with: "_mesh_shader")
        let objectName = fragmentName.replacingOccurrences(of: "_fragment", with: "_object_shader")

        guard let fragmentFn = library.makeFunction(name: fragmentName) else {
            meshLogger.error("Fragment function '\(fragmentName)' not found in \(url.lastPathComponent)")
            return nil
        }
        guard let meshFn = library.makeFunction(name: meshName) else {
            meshLogger.error("Mesh function '\(meshName)' not found in \(url.lastPathComponent)")
            return nil
        }
        let objectFn = library.makeFunction(name: objectName) // optional

        let state: MTLRenderPipelineState
        if device.supportsFamily(.apple8) {
            guard let pipelineState = compileMeshPipelineNative(
                fragmentFn: fragmentFn,
                meshFn: meshFn,
                objectFn: objectFn,
                descriptor: descriptor,
                url: url
            ) else { return nil }
            state = pipelineState
        } else {
            guard let fallbackState = compileMeshPipelineFallback(
                library: library,
                fragmentFn: fragmentFn,
                descriptor: descriptor,
                url: url
            ) else { return nil }
            state = fallbackState
        }

        // Mesh presets do not support feedback compositing in this increment.
        return (standard: state, feedback: nil)
    }

    // MARK: - Private Helpers

    /// Build a native MTLMeshRenderPipelineDescriptor (M3+).
    private func compileMeshPipelineNative(
        fragmentFn: MTLFunction,
        meshFn: MTLFunction,
        objectFn: MTLFunction?,
        descriptor: PresetDescriptor,
        url: URL
    ) -> MTLRenderPipelineState? {
        let meshDesc = MTLMeshRenderPipelineDescriptor()
        meshDesc.objectFunction = objectFn
        meshDesc.meshFunction = meshFn
        meshDesc.fragmentFunction = fragmentFn
        meshDesc.colorAttachments[0].pixelFormat = pixelFormat
        do {
            let (pipelineState, _) = try device.makeRenderPipelineState(descriptor: meshDesc, options: [])
            meshLogger.info("Created mesh pipeline (native) for \(descriptor.name)")
            return pipelineState
        } catch {
            meshLogger.error("Mesh pipeline creation failed for \(url.lastPathComponent): \(error)")
            return nil
        }
    }

    /// Build a standard vertex+fragment fallback pipeline (M1/M2).
    private func compileMeshPipelineFallback(
        library: MTLLibrary,
        fragmentFn: MTLFunction,
        descriptor: PresetDescriptor,
        url: URL
    ) -> MTLRenderPipelineState? {
        guard let vertexFn = library.makeFunction(name: descriptor.vertexFunction) else {
            meshLogger.error("Fallback vertex '\(descriptor.vertexFunction)' not found in \(url.lastPathComponent)")
            return nil
        }
        let fallbackDesc = MTLRenderPipelineDescriptor()
        fallbackDesc.vertexFunction = vertexFn
        fallbackDesc.fragmentFunction = fragmentFn
        fallbackDesc.colorAttachments[0].pixelFormat = pixelFormat
        do {
            let state = try device.makeRenderPipelineState(descriptor: fallbackDesc)
            meshLogger.info("Created mesh pipeline (vertex fallback) for \(descriptor.name)")
            return state
        } catch {
            meshLogger.error("Fallback pipeline creation failed for \(url.lastPathComponent): \(error)")
            return nil
        }
    }
}
