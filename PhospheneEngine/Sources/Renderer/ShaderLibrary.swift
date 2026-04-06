// ShaderLibrary — Compiles .metal shader sources from the bundle and manages pipeline states.
// Auto-discovers all .metal files in the Shaders/ resource directory (no manual registration).

import Metal
import os.log

private let logger = Logger(subsystem: "com.phosphene.renderer", category: "ShaderLibrary")

public final class ShaderLibrary: @unchecked Sendable {

    // MARK: - Storage

    /// Compiled Metal library containing all shader functions.
    public let library: MTLLibrary

    /// Cached render pipeline states, keyed by name.
    private var pipelineStates: [String: MTLRenderPipelineState] = [:]
    private let lock = NSLock()

    // MARK: - Init

    /// Compile all .metal shader sources found in the Renderer module's bundle.
    ///
    /// - Parameter context: Metal context providing the device.
    public init(context: MetalContext) throws {
        let device = context.device

        // Discover .metal source files in the Shaders/ resource directory.
        guard let shadersURL = Bundle.module.url(forResource: "Shaders", withExtension: nil) else {
            throw ShaderLibraryError.shaderDirectoryNotFound
        }

        let fileManager = FileManager.default
        let contents = try fileManager.contentsOfDirectory(
            at: shadersURL,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        )
        let metalFiles = contents.filter { $0.pathExtension == "metal" }

        guard !metalFiles.isEmpty else {
            throw ShaderLibraryError.noShadersFound
        }

        // Concatenate all shader sources into a single compilation unit.
        var combinedSource = ""
        for file in metalFiles.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let source = try String(contentsOf: file, encoding: .utf8)
            combinedSource += "// --- \(file.lastPathComponent) ---\n"
            combinedSource += source
            combinedSource += "\n\n"
            logger.info("Loaded shader source: \(file.lastPathComponent)")
        }

        // Compile to a Metal library.
        let options = MTLCompileOptions()
        options.fastMathEnabled = true
        options.languageVersion = .version3_1

        self.library = try device.makeLibrary(source: combinedSource, options: options)
        logger.info("Compiled shader library with \(metalFiles.count) source file(s)")
    }

    // MARK: - Function Access

    /// Look up a compiled Metal function by name.
    public func function(named name: String) -> MTLFunction? {
        library.makeFunction(name: name)
    }

    // MARK: - Pipeline State Management

    /// Get or create a render pipeline state for the given vertex/fragment pair.
    ///
    /// Pipeline states are cached by name for reuse across frames.
    ///
    /// - Parameters:
    ///   - name: Cache key for the pipeline.
    ///   - vertexFunction: Name of the vertex function in the shader library.
    ///   - fragmentFunction: Name of the fragment function in the shader library.
    ///   - pixelFormat: Output pixel format (from MetalContext).
    ///   - device: Metal device for pipeline creation.
    /// - Returns: A compiled render pipeline state.
    public func renderPipelineState(
        named name: String,
        vertexFunction: String,
        fragmentFunction: String,
        pixelFormat: MTLPixelFormat,
        device: MTLDevice
    ) throws -> MTLRenderPipelineState {
        lock.lock()
        if let cached = pipelineStates[name] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        guard let vertexFn = library.makeFunction(name: vertexFunction) else {
            throw ShaderLibraryError.functionNotFound(vertexFunction)
        }
        guard let fragmentFn = library.makeFunction(name: fragmentFunction) else {
            throw ShaderLibraryError.functionNotFound(fragmentFunction)
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFn
        descriptor.fragmentFunction = fragmentFn
        descriptor.colorAttachments[0].pixelFormat = pixelFormat

        let state = try device.makeRenderPipelineState(descriptor: descriptor)

        lock.lock()
        pipelineStates[name] = state
        lock.unlock()

        logger.info("Created pipeline state '\(name)': \(vertexFunction) → \(fragmentFunction)")
        return state
    }
}

// MARK: - Errors

public enum ShaderLibraryError: Error, Sendable {
    case shaderDirectoryNotFound
    case noShadersFound
    case functionNotFound(String)
}
