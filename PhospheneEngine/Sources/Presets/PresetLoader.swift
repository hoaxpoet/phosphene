// PresetLoader — Discovers .metal preset shaders, compiles pipeline states, and hot-reloads.
// Each .metal file is compiled independently with a common preamble prepended.
// Optional JSON sidecars provide metadata (name, family, feedback params).
// Hot-reload watches an external directory via DispatchSource.FileSystemObject.
// swiftlint:disable file_length

import Foundation
import Metal
import os.log

private let logger = Logger(subsystem: "com.phosphene.presets", category: "PresetLoader")

// swiftlint:disable:next type_body_length
public final class PresetLoader: @unchecked Sendable {

    // MARK: - Public State

    /// All loaded presets, sorted by name.
    public private(set) var presets: [LoadedPreset] = []

    /// Index of the currently active preset.
    public private(set) var currentIndex: Int = 0

    /// Fires on the main queue when presets are reloaded (hot-reload).
    public var onPresetsReloaded: (() -> Void)?

    // MARK: - Types

    /// A preset with its compiled pipeline state ready for rendering.
    public struct LoadedPreset: Sendable {
        public let descriptor: PresetDescriptor
        public let pipelineState: MTLRenderPipelineState
        /// Additive-blended pipeline state for feedback composite pass. Nil for non-feedback presets.
        public let feedbackPipelineState: MTLRenderPipelineState?
        /// G-buffer pipeline state for ray march presets (3 color attachments). Nil for non-ray-march presets.
        public let rayMarchPipelineState: MTLRenderPipelineState?
    }

    // MARK: - Private State

    let device: MTLDevice
    let pixelFormat: MTLPixelFormat
    private let lock = NSLock()
    private var watchSource: DispatchSourceFileSystemObject?
    private var watchedDirectoryFD: Int32 = -1

    /// File names in the Shaders/ directory that are utility libraries, not presets.
    /// These are included in the preamble and skipped during preset discovery.
    private static let utilityFileNames: Set<String> = ["ShaderUtilities.metal"]

    // MARK: - Init

    /// Create a preset loader that discovers shaders from bundle resources
    /// and optionally watches an external directory for hot-reload.
    ///
    /// - Parameters:
    ///   - device: Metal device for shader compilation.
    ///   - pixelFormat: Output pixel format for pipeline state creation.
    ///   - watchDirectory: Optional path to watch for .metal file changes (hot-reload).
    ///   - loadBuiltIn: Whether to load built-in presets from the bundle. Defaults to true.
    ///     Pass false in tests to isolate test shaders from bundle resources.
    public init(
        device: MTLDevice,
        pixelFormat: MTLPixelFormat,
        watchDirectory: URL? = nil,
        loadBuiltIn: Bool = true
    ) {
        self.device = device
        self.pixelFormat = pixelFormat

        // Load built-in presets from bundle resources.
        if loadBuiltIn {
            loadFromBundle()
        }

        // Load from external directory if provided (additive).
        if let dir = watchDirectory {
            loadFromDirectory(dir)
            startWatching(directory: dir)
        }

        logger.info("PresetLoader initialized with \(self.presets.count) preset(s)")
    }

    deinit {
        stopWatching()
    }

    // MARK: - Preset Navigation

    /// The currently active preset.
    public var currentPreset: LoadedPreset? {
        lock.withLock {
            guard !presets.isEmpty else { return nil }
            return presets[currentIndex]
        }
    }

    /// Advance to the next preset, wrapping around.
    @discardableResult
    public func nextPreset() -> LoadedPreset? {
        lock.withLock {
            guard !presets.isEmpty else { return nil }
            currentIndex = (currentIndex + 1) % presets.count
            let preset = presets[currentIndex]
            logger.info("Switched to preset: \(preset.descriptor.name) [\(self.currentIndex + 1)/\(self.presets.count)]")
            return preset
        }
    }

    /// Go to the previous preset, wrapping around.
    @discardableResult
    public func previousPreset() -> LoadedPreset? {
        lock.withLock {
            guard !presets.isEmpty else { return nil }
            currentIndex = (currentIndex - 1 + presets.count) % presets.count
            let preset = presets[currentIndex]
            logger.info("Switched to preset: \(preset.descriptor.name) [\(self.currentIndex + 1)/\(self.presets.count)]")
            return preset
        }
    }

    /// Select a preset by name. Returns the index if found, nil otherwise.
    @discardableResult
    public func selectPreset(named name: String) -> Int? {
        lock.withLock {
            guard let index = presets.firstIndex(where: { $0.descriptor.name == name }) else {
                return nil
            }
            currentIndex = index
            return index
        }
    }

    // MARK: - Loading

    private func loadFromBundle() {
        guard let shadersURL = Bundle.module.url(forResource: "Shaders", withExtension: nil) else {
            logger.warning("No Shaders/ resource directory found in Presets bundle")
            return
        }
        loadFromDirectory(shadersURL)
    }

    private func loadFromDirectory(_ directory: URL) {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else {
            logger.warning("Could not read directory: \(directory.path)")
            return
        }

        let metalFiles = contents
            .filter { $0.pathExtension == "metal" }
            .filter { !Self.utilityFileNames.contains($0.lastPathComponent) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        for metalFile in metalFiles {
            let baseName = metalFile.deletingPathExtension().lastPathComponent

            // Load JSON sidecar if it exists.
            let jsonURL = metalFile.deletingPathExtension().appendingPathExtension("json")
            var descriptor = loadDescriptor(from: jsonURL, fallbackName: baseName)
            descriptor.shaderFileName = metalFile.lastPathComponent

            // Compile the shader.
            guard let pipelines = compileShader(at: metalFile, descriptor: descriptor) else {
                continue
            }

            let loaded = LoadedPreset(
                descriptor: descriptor,
                pipelineState: pipelines.standard,
                feedbackPipelineState: pipelines.feedback,
                rayMarchPipelineState: pipelines.rayMarch
            )

            lock.withLock {
                // Replace existing preset with same name, or append.
                if let existingIndex = presets.firstIndex(where: { $0.descriptor.name == descriptor.name }) {
                    presets[existingIndex] = loaded
                    logger.info("Reloaded preset: \(descriptor.name)")
                } else {
                    presets.append(loaded)
                    logger.info("Loaded preset: \(descriptor.name)")
                }
            }
        }

        // Sort by name for stable ordering.
        lock.withLock {
            presets.sort { $0.descriptor.name < $1.descriptor.name }
        }
    }

    private func loadDescriptor(from jsonURL: URL, fallbackName: String) -> PresetDescriptor {
        guard FileManager.default.fileExists(atPath: jsonURL.path),
              let data = try? Data(contentsOf: jsonURL),
              let descriptor = try? JSONDecoder().decode(PresetDescriptor.self, from: data)
        else {
            // No sidecar — create a default descriptor from the file name.
            logger.info("No JSON sidecar for \(fallbackName), using defaults")
            let json = """
            {"name": "\(fallbackName)"}
            """
            return (try? JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8)))
                ?? PresetDescriptor.fallback(name: fallbackName)
        }
        return descriptor
    }

    // MARK: - Shader Compilation

    /// Result of compiling a preset shader: the primary state plus optional specialised states.
    struct CompiledShader {
        let standard: MTLRenderPipelineState
        let feedback: MTLRenderPipelineState?
        let rayMarch: MTLRenderPipelineState?

        init(standard: MTLRenderPipelineState,
             feedback: MTLRenderPipelineState? = nil,
             rayMarch: MTLRenderPipelineState? = nil) {
            self.standard  = standard
            self.feedback  = feedback
            self.rayMarch  = rayMarch
        }
    }

    private func compileShader(at url: URL, descriptor: PresetDescriptor) -> CompiledShader? {
        // Branch to mesh pipeline compilation for mesh shader presets.
        if descriptor.useMeshShader {
            guard let result = compileMeshShader(at: url, descriptor: descriptor) else { return nil }
            return CompiledShader(standard: result.standard, feedback: result.feedback)
        }
        // Branch to ray march G-buffer pipeline for ray march presets.
        if descriptor.useRayMarch {
            return compileRayMarchShader(at: url, descriptor: descriptor)
        }
        guard let result = compileStandardShader(at: url, descriptor: descriptor) else { return nil }
        return CompiledShader(standard: result.standard, feedback: result.feedback)
    }

    /// Compile a standard (non-mesh, non-ray-march) preset shader.
    private func compileStandardShader(
        at url: URL, descriptor: PresetDescriptor
    ) -> CompiledShader? {
        guard let fragmentSource = try? String(contentsOf: url, encoding: .utf8) else {
            logger.error("Could not read shader file: \(url.lastPathComponent)")
            return nil
        }

        // Prepend the common preamble (shared structs, vertex shader, utilities).
        let fullSource = Self.shaderPreamble + "\n\n" + fragmentSource

        let options = MTLCompileOptions()
        options.fastMathEnabled = true
        options.languageVersion = .version3_1

        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: fullSource, options: options)
        } catch {
            logger.error("Shader compilation failed for \(url.lastPathComponent): \(error)")
            return nil
        }

        let vertexName = descriptor.vertexFunction
        let fragmentName = descriptor.fragmentFunction

        guard let vertexFn = library.makeFunction(name: vertexName) else {
            logger.error("Vertex function '\(vertexName)' not found in \(url.lastPathComponent)")
            return nil
        }
        guard let fragmentFn = library.makeFunction(name: fragmentName) else {
            logger.error("Fragment function '\(fragmentName)' not found in \(url.lastPathComponent)")
            return nil
        }

        // Standard pipeline (no blending — used for non-feedback presets and tests).
        // Post-process presets render into an HDR scene texture (.rgba16Float) before
        // the bloom/ACES chain, so their pipeline must match that format — not the
        // drawable's .bgra8Unorm_srgb.
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFn
        pipelineDescriptor.fragmentFunction = fragmentFn
        pipelineDescriptor.colorAttachments[0].pixelFormat = descriptor.usePostProcess
            ? .rgba16Float : pixelFormat

        let standardState: MTLRenderPipelineState
        do {
            standardState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            logger.error("Pipeline state creation failed for \(url.lastPathComponent): \(error)")
            return nil
        }

        // Feedback pipeline (source-alpha blending — used for feedback composite pass).
        // The shader outputs (rgb, alpha) where alpha controls how much the new
        // frame replaces the warped/decayed history: alpha=1 fully replaces,
        // alpha=0.3 blends 30% new with 70% history. RGB uses standard alpha
        // compositing; alpha channel accumulates so the feedback texture stays
        // opaque for the drawable blit.
        var feedbackState: MTLRenderPipelineState?
        if descriptor.useFeedback {
            pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
            pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
            pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .one
            do {
                feedbackState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
                logger.info("Created feedback pipeline for \(descriptor.name)")
            } catch {
                logger.error("Feedback pipeline creation failed for \(url.lastPathComponent): \(error)")
            }
        }

        return CompiledShader(standard: standardState, feedback: feedbackState)
    }

    /// Compile a ray march preset: produces a G-buffer pipeline state (3 color attachments)
    /// using `raymarch_gbuffer_fragment` from the preamble plus the preset's `sceneSDF`
    /// and `sceneMaterial` definitions.  Also compiles a standard single-attachment state
    /// (used as a fallback or for compatibility if needed).
    private func compileRayMarchShader(
        at url: URL, descriptor: PresetDescriptor
    ) -> CompiledShader? {
        guard let fragmentSource = try? String(contentsOf: url, encoding: .utf8) else {
            logger.error("Could not read ray march shader file: \(url.lastPathComponent)")
            return nil
        }

        // Full source: standard preamble + ray march G-buffer preamble + preset SDF.
        // rayMarchGBufferPreamble adds SceneUniforms, GBufferOutput, forward declarations,
        // and raymarch_gbuffer_fragment (which calls preset-defined sceneSDF/sceneMaterial).
        let fullSource = Self.shaderPreamble + "\n\n" + Self.rayMarchGBufferPreamble + "\n\n" + fragmentSource

        let options = MTLCompileOptions()
        options.fastMathEnabled = true
        options.languageVersion = .version3_1

        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: fullSource, options: options)
        } catch {
            logger.error("Ray march shader compilation failed for \(url.lastPathComponent): \(error)")
            return nil
        }

        guard let vertexFn = library.makeFunction(name: descriptor.vertexFunction) else {
            logger.error("Vertex function '\(descriptor.vertexFunction)' not found in \(url.lastPathComponent)")
            return nil
        }
        guard let gbufferFn = library.makeFunction(name: "raymarch_gbuffer_fragment") else {
            logger.error("'raymarch_gbuffer_fragment' not found — ensure preamble is correctly prepended")
            return nil
        }

        // G-buffer pipeline: 3 simultaneous color attachments.
        //   attachment[0]  .rg16Float    — depth (R) + unused (G)
        //   attachment[1]  .rgba8Snorm   — world-space normal (RGB) + AO (A)
        //   attachment[2]  .rgba8Unorm   — albedo (RGB) + packed roughness/metallic (A)
        let gbufferDesc = MTLRenderPipelineDescriptor()
        gbufferDesc.vertexFunction = vertexFn
        gbufferDesc.fragmentFunction = gbufferFn
        gbufferDesc.colorAttachments[0].pixelFormat = .rg16Float
        gbufferDesc.colorAttachments[1].pixelFormat = .rgba8Snorm
        gbufferDesc.colorAttachments[2].pixelFormat = .rgba8Unorm

        let gbufferState: MTLRenderPipelineState
        do {
            gbufferState = try device.makeRenderPipelineState(descriptor: gbufferDesc)
            logger.info("Compiled ray march G-buffer pipeline for \(descriptor.name)")
        } catch {
            logger.error("Ray march G-buffer pipeline creation failed for \(url.lastPathComponent): \(error)")
            return nil
        }

        // Standard single-attachment pipeline (fallback / reuse of pipelineState slot).
        // Uses a fragment function named after the preset file if present; otherwise
        // falls back to a no-op by reusing the G-buffer state as standard.
        // For ray march presets, the G-buffer state is what matters — standard is
        // a placeholder so LoadedPreset.pipelineState is always non-nil.
        let placeholderDesc = MTLRenderPipelineDescriptor()
        placeholderDesc.vertexFunction = vertexFn
        placeholderDesc.fragmentFunction = gbufferFn
        // Single attachment in drawable format to satisfy the non-nil requirement.
        placeholderDesc.colorAttachments[0].pixelFormat = pixelFormat

        // We need a valid single-attachment pipeline — recompile with 1 attachment.
        // If that fails (e.g., format mismatch), fall back to the G-buffer state cast.
        // In practice the G-buffer fragment only writes GBufferOutput (3 attachments),
        // so this won't compile cleanly. Use a minimal passthrough instead: if a
        // preset-defined fragment (named e.g. "sphere_preview_fragment") exists, use it;
        // otherwise just use the G-buffer pipeline state as the placeholder standard.
        let standardState: MTLRenderPipelineState
        if let previewFn = library.makeFunction(name: descriptor.fragmentFunction),
           descriptor.fragmentFunction != "preset_fragment" {
            let previewDesc = MTLRenderPipelineDescriptor()
            previewDesc.vertexFunction = vertexFn
            previewDesc.fragmentFunction = previewFn
            previewDesc.colorAttachments[0].pixelFormat = pixelFormat
            standardState = (try? device.makeRenderPipelineState(descriptor: previewDesc)) ?? gbufferState
        } else {
            // No separate preview function — use the G-buffer state as the placeholder.
            standardState = gbufferState
        }

        return CompiledShader(standard: standardState, rayMarch: gbufferState)
    }

    // MARK: - Hot Reload

    /// Watch a directory for file system changes and reload presets.
    private func startWatching(directory: URL) {
        let fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else {
            logger.warning("Could not open directory for watching: \(directory.path)")
            return
        }
        watchedDirectoryFD = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: DispatchQueue.global(qos: .utility)
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }
            logger.info("Preset directory changed — reloading")

            // Small delay to let file writes complete.
            Thread.sleep(forTimeInterval: 0.2)

            // Reload all presets from the watched directory.
            self.loadFromDirectory(directory)

            // Clamp current index.
            self.lock.withLock {
                if self.currentIndex >= self.presets.count {
                    self.currentIndex = max(0, self.presets.count - 1)
                }
            }

            // Notify on main queue.
            DispatchQueue.main.async {
                self.onPresetsReloaded?()
            }
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        self.watchSource = source

        logger.info("Watching for preset changes: \(directory.path)")
    }

    private func stopWatching() {
        watchSource?.cancel()
        watchSource = nil
    }
}

// MARK: - PresetDescriptor Fallback

extension PresetDescriptor {
    static func fallback(name: String) -> PresetDescriptor {
        let json = """
        {"name": "\(name)", "family": "waveform"}
        """
        do {
            return try JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
        } catch {
            // This should never fail — the JSON template is compile-time constant.
            fatalError("PresetDescriptor fallback JSON decode failed: \(error)")
        }
    }
}
