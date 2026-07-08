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

    /// Resource URL of the bundled `Shaders/` directory in the Presets module.
    /// Public so harness tests in other modules (e.g. `PresetVisualReviewTests`) can
    /// reach the shader sources via the same lookup the loader uses internally
    /// — `Bundle.module` resolves to the test target's bundle when called from
    /// outside this module, which has no `Shaders` resource. BUG-002.
    public static var bundledShadersURL: URL? {
        Bundle.module.url(forResource: "Shaders", withExtension: nil)
    }

    /// Index of the currently active preset.
    public private(set) var currentIndex: Int = 0

    /// Fires on the main queue when presets are reloaded (hot-reload).
    public var onPresetsReloaded: (() -> Void)?

    // MARK: - Types

    /// Compiled pipeline states for the mv_warp pass (MV-2, D-027).
    ///
    /// Built by PresetLoader at compile time from the preset's library (which includes
    /// the mvWarpPreamble with `mvWarp_vertex` calling the preset's `mvWarpPerFrame` /
    /// `mvWarpPerVertex`).  The app layer bridges these into `MVWarpPipelineBundle` for
    /// the Renderer module.
    public struct MVWarpCompiledPipelines: Sendable {
        /// Warp pipeline: `mvWarp_vertex` (32×24 grid) + `mvWarp_fragment`.
        public let warpState: MTLRenderPipelineState
        /// Compose pipeline: `fullscreen_vertex` + `mvWarp_compose_fragment` (alpha blend).
        public let composeState: MTLRenderPipelineState
        /// Blit pipeline: `fullscreen_vertex` + `mvWarp_blit_fragment`.
        public let blitState: MTLRenderPipelineState
        /// Optional additive scene-geometry pipeline drawn into the scene texture
        /// AFTER the fullscreen background fragment (Dragon Bloom L1: the 3 spectral
        /// strands, `dragon_bloom_strand_vertex`/`_fragment`). nil for presets that
        /// don't define the strand functions. D-137.
        public let sceneGeometryState: MTLRenderPipelineState?
        /// Optional blur-of-previous-frame pipeline (`<prefix>_blur_fragment`), the
        /// butterchurn `blur1` approximation Fata Morgana's custom warp reads. nil for
        /// presets that don't define a blur fragment (Dragon Bloom, default). D-139.
        public let blurState: MTLRenderPipelineState?
        /// Optional Fata Morgana custom-shape pipelines (FM.L2): the additive (neon
        /// blobs) and normal-blend (textured echo) variants of `fata_shape_vertex` /
        /// `fata_shape_fragment`, drawn on top of the warp target. nil unless the
        /// preset library defines the shape functions. D-139.
        public let shapeAdditiveState: MTLRenderPipelineState?
        public let shapeNormalState: MTLRenderPipelineState?

        public init(
            warpState: MTLRenderPipelineState,
            composeState: MTLRenderPipelineState,
            blitState: MTLRenderPipelineState,
            sceneGeometryState: MTLRenderPipelineState? = nil,
            blurState: MTLRenderPipelineState? = nil,
            shapeAdditiveState: MTLRenderPipelineState? = nil,
            shapeNormalState: MTLRenderPipelineState? = nil
        ) {
            self.warpState = warpState
            self.composeState = composeState
            self.blitState = blitState
            self.sceneGeometryState = sceneGeometryState
            self.blurState = blurState
            self.shapeAdditiveState = shapeAdditiveState
            self.shapeNormalState = shapeNormalState
        }
    }

    /// One compiled stage of a staged-composition preset (V.ENGINE.1).
    public struct LoadedStage: Sendable {
        /// Stage identifier (matches `PresetStage.name`).
        public let name: String
        /// Compiled fragment pipeline. Non-final stages target `.rgba16Float`; the
        /// final stage targets the drawable pixel format.
        public let pipelineState: MTLRenderPipelineState
        /// Names of earlier stages whose outputs this stage samples (texture(13)+).
        public let samples: [String]
        /// True if this stage's color attachment is the drawable pixel format.
        /// False if it targets `.rgba16Float` (intermediate pass).
        public let writesToDrawable: Bool

        public init(
            name: String,
            pipelineState: MTLRenderPipelineState,
            samples: [String],
            writesToDrawable: Bool
        ) {
            self.name = name
            self.pipelineState = pipelineState
            self.samples = samples
            self.writesToDrawable = writesToDrawable
        }
    }

    /// A preset with its compiled pipeline state ready for rendering.
    public struct LoadedPreset: Sendable {
        public let descriptor: PresetDescriptor
        public let pipelineState: MTLRenderPipelineState
        /// Additive-blended pipeline state for feedback composite pass. Nil for non-feedback presets.
        public let feedbackPipelineState: MTLRenderPipelineState?
        /// G-buffer pipeline state for ray march presets (3 color attachments). Nil for non-ray-march presets.
        public let rayMarchPipelineState: MTLRenderPipelineState?
        /// Per-vertex warp pipeline states (MV-2). Nil for non-mv_warp presets.
        public let mvWarpPipelines: MVWarpCompiledPipelines?
        /// Ordered staged-composition pipelines (V.ENGINE.1). Empty for non-staged presets.
        public let stages: [LoadedStage]

        public init(
            descriptor: PresetDescriptor,
            pipelineState: MTLRenderPipelineState,
            feedbackPipelineState: MTLRenderPipelineState? = nil,
            rayMarchPipelineState: MTLRenderPipelineState? = nil,
            mvWarpPipelines: MVWarpCompiledPipelines? = nil,
            stages: [LoadedStage] = []
        ) {
            self.descriptor = descriptor
            self.pipelineState = pipelineState
            self.feedbackPipelineState = feedbackPipelineState
            self.rayMarchPipelineState = rayMarchPipelineState
            self.mvWarpPipelines = mvWarpPipelines
            self.stages = stages
        }
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
                rayMarchPipelineState: pipelines.rayMarch,
                mvWarpPipelines: pipelines.mvWarp,
                stages: pipelines.stages
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

        loadShaderReusePresets(contents: contents, metalFiles: metalFiles, directory: directory, fm: fm)

        // Sort by name for stable ordering.
        lock.withLock {
            presets.sort { $0.descriptor.name < $1.descriptor.name }
        }
    }

    /// RICERCAR-RW: a JSON with NO sibling `.metal` but an explicit `shader_file` REUSES another
    /// preset's shader (Ricercar reuses Skein's painter shader — it differs only in its family-mode
    /// SkeinState + palette, not the marks shader). Compile the referenced `.metal` with the orphan
    /// descriptor. Keeps one shader backing multiple presets (no verbatim duplication) inside the
    /// per-file compile architecture; a hot-reload of the shared `.metal` re-runs this pass too.
    private func loadShaderReusePresets(
        contents: [URL], metalFiles: [URL], directory: URL, fm: FileManager
    ) {
        let metalBaseNames = Set(metalFiles.map { $0.deletingPathExtension().lastPathComponent })
        let orphanJSONs = contents
            .filter { $0.pathExtension == "json" }
            .filter { !metalBaseNames.contains($0.deletingPathExtension().lastPathComponent) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for jsonURL in orphanJSONs {
            let baseName = jsonURL.deletingPathExtension().lastPathComponent
            let descriptor = loadDescriptor(from: jsonURL, fallbackName: baseName)
            guard !descriptor.shaderFileName.isEmpty else { continue }   // no `shader_file` → not a redirect
            let targetMetal = directory.appendingPathComponent(descriptor.shaderFileName)
            guard fm.fileExists(atPath: targetMetal.path) else {
                logger.warning("Preset '\(descriptor.name)': shader_file '\(descriptor.shaderFileName)' not found")
                continue
            }
            guard let pipelines = compileShader(at: targetMetal, descriptor: descriptor) else { continue }
            let loaded = LoadedPreset(
                descriptor: descriptor,
                pipelineState: pipelines.standard,
                feedbackPipelineState: pipelines.feedback,
                rayMarchPipelineState: pipelines.rayMarch,
                mvWarpPipelines: pipelines.mvWarp,
                stages: pipelines.stages
            )
            lock.withLock {
                if let existingIndex = presets.firstIndex(where: { $0.descriptor.name == descriptor.name }) {
                    presets[existingIndex] = loaded
                } else {
                    presets.append(loaded)
                    logger.info("Loaded preset: \(descriptor.name) (shader_file → \(descriptor.shaderFileName))")
                }
            }
        }
    }

    /// Decode a preset's JSON sidecar.
    ///
    /// - Returns `nil` when no sidecar file exists — benign; the caller substitutes a
    ///   name-only default (presets without a sidecar use defaults by design).
    /// - Throws when a sidecar exists but is unreadable or malformed — the caller logs
    ///   loudly and still degrades to the name-only default, so a typo'd sidecar can't
    ///   *silently* demote a preset to the wrong family/feedback params (CLEAN.3.1).
    static func decodeSidecar(at jsonURL: URL) throws -> PresetDescriptor? {
        guard FileManager.default.fileExists(atPath: jsonURL.path) else { return nil }
        let data = try Data(contentsOf: jsonURL)
        return try JSONDecoder().decode(PresetDescriptor.self, from: data)
    }

    private func loadDescriptor(from jsonURL: URL, fallbackName: String) -> PresetDescriptor {
        do {
            if let descriptor = try Self.decodeSidecar(at: jsonURL) {
                return descriptor
            }
            // No sidecar at all — benign.
            logger.info("No JSON sidecar for \(fallbackName), using defaults")
        } catch {
            // Sidecar present but malformed/unreadable: surface it loudly, then degrade.
            // Before CLEAN.3.1 this fell into the same `.info` "no sidecar" branch as a
            // genuinely-absent file, so a typo'd sidecar silently dropped the preset to
            // default family/feedback params with no on-disk signal.
            logger.error("""
                Malformed JSON sidecar for \(fallbackName): \(error) — \
                degrading to default descriptor (default family/feedback params).
                """)
        }
        return defaultDescriptor(name: fallbackName)
    }

    /// Name-only default for a preset whose sidecar is absent or unusable. Mirrors a
    /// bare `{"name": "X"}` decode — `family` stays `nil` (a defaulted preset claims no
    /// aesthetic family rather than being mis-sorted into `waveform`).
    private func defaultDescriptor(name: String) -> PresetDescriptor {
        let json = """
        {"name": "\(name)"}
        """
        return (try? JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8)))
            ?? PresetDescriptor.fallback(name: name)
    }

    // MARK: - Shader Compilation

    /// Result of compiling a preset shader: the primary state plus optional specialised states.
    struct CompiledShader {
        let standard: MTLRenderPipelineState
        let feedback: MTLRenderPipelineState?
        let rayMarch: MTLRenderPipelineState?
        let mvWarp: MVWarpCompiledPipelines?
        let stages: [LoadedStage]

        init(standard: MTLRenderPipelineState,
             feedback: MTLRenderPipelineState? = nil,
             rayMarch: MTLRenderPipelineState? = nil,
             mvWarp: MVWarpCompiledPipelines? = nil,
             stages: [LoadedStage] = []) {
            self.standard  = standard
            self.feedback  = feedback
            self.rayMarch  = rayMarch
            self.mvWarp    = mvWarp
            self.stages    = stages
        }
    }

    private func compileShader(at url: URL, descriptor: PresetDescriptor) -> CompiledShader? {
        // Route to the compilation path that matches the preset's declared passes.
        if descriptor.passes.contains(.meshShader) {
            guard let result = compileMeshShader(at: url, descriptor: descriptor) else { return nil }
            return CompiledShader(standard: result.standard, feedback: result.feedback)
        }
        if descriptor.passes.contains(.mvWarp) {
            // MV-2: mv_warp presets compile via the ray march path (for ray-march presets)
            // or a new combined path.  All mv_warp presets also get the warp pipeline states.
            return compileMVWarpShader(at: url, descriptor: descriptor)
        }
        if descriptor.passes.contains(.rayMarch) {
            return compileRayMarchShader(at: url, descriptor: descriptor)
        }
        if descriptor.passes.contains(.staged) {
            return compileStagedShader(at: url, descriptor: descriptor)
        }
        guard let result = compileStandardShader(at: url, descriptor: descriptor) else { return nil }
        return CompiledShader(standard: result.standard, feedback: result.feedback)
    }

    /// Compile a staged-composition preset (V.ENGINE.1). The preset declares an
    /// ordered `stages: [...]` array; one fragment pipeline state is built per stage.
    /// Non-final stages target `.rgba16Float`; the final stage targets the drawable
    /// pixel format. The first stage's pipeline is also returned as the LoadedPreset
    /// `pipelineState` so any code path that expects a non-nil primary state still works.
    private func compileStagedShader(
        at url: URL, descriptor: PresetDescriptor
    ) -> CompiledShader? {
        guard !descriptor.stages.isEmpty else {
            logger.error("Staged preset '\(descriptor.name)' has no `stages` array — skipping")
            return nil
        }
        guard let fragmentSource = try? String(contentsOf: url, encoding: .utf8) else {
            logger.error("Could not read staged shader file: \(url.lastPathComponent)")
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
            logger.error("Staged shader compilation failed for \(url.lastPathComponent): \(error)")
            return nil
        }

        guard let vertexFn = library.makeFunction(name: descriptor.vertexFunction) else {
            logger.error("Vertex function '\(descriptor.vertexFunction)' not found in \(url.lastPathComponent)")
            return nil
        }

        let lastIndex = descriptor.stages.count - 1
        var loaded: [LoadedStage] = []
        loaded.reserveCapacity(descriptor.stages.count)

        for (index, stage) in descriptor.stages.enumerated() {
            guard let fragmentFn = library.makeFunction(name: stage.fragmentFunction) else {
                logger.error("""
                    Stage '\(stage.name)' fragment function '\(stage.fragmentFunction)' \
                    not found in \(url.lastPathComponent)
                    """)
                return nil
            }
            let isFinal = (index == lastIndex)
            let pipelineDescriptor = MTLRenderPipelineDescriptor()
            pipelineDescriptor.vertexFunction = vertexFn
            pipelineDescriptor.fragmentFunction = fragmentFn
            pipelineDescriptor.colorAttachments[0].pixelFormat = isFinal ? pixelFormat : .rgba16Float

            do {
                let state = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
                loaded.append(LoadedStage(
                    name: stage.name,
                    pipelineState: state,
                    samples: stage.samples,
                    writesToDrawable: isFinal
                ))
            } catch {
                logger.error("Stage '\(stage.name)' pipeline creation failed for \(url.lastPathComponent): \(error)")
                return nil
            }
        }

        // Use the final stage's pipeline as the primary `pipelineState` so any code
        // path that expects a single non-nil state still has one.
        guard let primary = loaded.last?.pipelineState else { return nil }
        logger.info("Compiled staged preset '\(descriptor.name)' with \(loaded.count) stage(s)")
        return CompiledShader(standard: primary, stages: loaded)
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
        pipelineDescriptor.colorAttachments[0].pixelFormat = descriptor.passes.contains(.postProcess)
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
        if descriptor.passes.contains(.feedback) {
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

    /// Compile an mv_warp preset: injects `shaderPreamble + rayMarchGBufferPreamble +
    /// mvWarpPreamble` so the preset's `mvWarpPerFrame` / `mvWarpPerVertex` are compiled
    /// alongside `mvWarp_vertex`, the 3 fixed fragment functions, and (for ray-march
    /// presets) `sceneSDF` / `sceneMaterial`.
    ///
    /// Produces:
    /// - `standard`  — G-buffer state (ray march) or direct state (direct presets).
    /// - `rayMarch`  — G-buffer state (nil for direct presets).
    /// - `mvWarp`    — Three warp pipeline states.
    private func compileMVWarpShader(
        at url: URL, descriptor: PresetDescriptor
    ) -> CompiledShader? {
        guard let fragmentSource = try? String(contentsOf: url, encoding: .utf8) else {
            logger.error("Could not read mv_warp shader file: \(url.lastPathComponent)")
            return nil
        }
        let isRayMarch = descriptor.passes.contains(.rayMarch)
        let fullSource = buildMVWarpSource(fragmentSource: fragmentSource, isRayMarch: isRayMarch)
        let options = MTLCompileOptions()
        options.fastMathEnabled = true
        options.languageVersion = .version3_1
        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: fullSource, options: options)
        } catch {
            logger.error("mv_warp shader compilation failed for \(url.lastPathComponent): \(error)")
            return nil
        }
        guard let warpPipelines = makeWarpPipelines(library: library, url: url, descriptor: descriptor)
        else { return nil }
        if isRayMarch {
            return makeRayMarchPrimaryPipeline(
                library: library, descriptor: descriptor, url: url, warpPipelines: warpPipelines)
        } else {
            return makeDirectPrimaryPipeline(
                library: library, descriptor: descriptor, url: url, warpPipelines: warpPipelines)
        }
    }

    private func buildMVWarpSource(fragmentSource: String, isRayMarch: Bool) -> String {
        if isRayMarch {
            return Self.shaderPreamble
                + "\n\n" + Self.rayMarchGBufferPreamble
                + "\n\n" + Self.mvWarpPreamble
                + "\n\n" + fragmentSource
        } else {
            return Self.shaderPreamble
                + "\n\n" + Self.mvWarpPreamble
                + "\n\n" + fragmentSource
        }
    }

    /// Feedback-buffer pixel format for an mv_warp preset. Always the drawable
    /// (8-bit) format — matching butterchurn/Milkdrop, which use UNSIGNED_BYTE RGBA
    /// for the feedback textures. The 8-bit per-frame CLAMP is load-bearing for
    /// Dragon Bloom (D-137): with the faithful no-decay warp, the clamp holds the
    /// field at a saturated equilibrium; a float buffer instead over-accumulates to
    /// pale near-white (verified). (Earlier this returned rgba16f for DB — that was
    /// wrong; reverted once the no-decay loop was matched to the source.)
    func feedbackFormat(_ descriptor: PresetDescriptor) -> MTLPixelFormat {
        // Fata Morgana (D-139): butterchurn's feedback is LINEAR 8-bit (gl.RGBA /
        // UNSIGNED_BYTE), not sRGB. Phosphene's drawable is `.bgra8Unorm_srgb`, so
        // using it for the feedback accumulated the decay + additive blobs in sRGB
        // space — a divergence from the source. Use the non-sRGB `.bgra8Unorm` for the
        // feedback textures (the blit still targets the sRGB drawable for display).
        if descriptor.name == "Fata Morgana" { return .bgra8Unorm }
        // Nacre (NACRE.2): HDR float feedback so the iridescent rims + luminous core
        // accumulate unclamped (real bloom; no banding in the slow palette rotation).
        // Safe here — unlike Dragon Bloom's no-decay loop (which over-accumulated to
        // pale white on a float buffer, per above), Nacre uses DECAY feedback
        // (kNacreDecay 0.94), which bounds the accumulation.
        if descriptor.name == "Nacre" { return .rgba16Float }
        // Floret (FLORET.2a): HDR float feedback — same register as Nacre (decay-bounded),
        // headroom for the FLORET.3 iridescence uplift. The custom warp clamps [0,1] today.
        if descriptor.name == "Floret" { return .rgba16Float }
        // Glaze (GLAZE.2a): HDR float feedback (headroom for the greenlit uplift B glossy
        // bloom). Safe — Glaze uses DECAY feedback (kGlazeDecay 0.94) which bounds the
        // accumulation (the base clamps to [0,1]; uplift B re-unclamps with a bloom).
        if descriptor.name == "Glaze" { return .rgba16Float }
        return pixelFormat
    }

    private func makeWarpPipelines(
        library: MTLLibrary, url: URL, descriptor: PresetDescriptor
    ) -> MVWarpCompiledPipelines? {
        // Preset-overridable warp/comp/blur fragments (D-139). A preset whose
        // fragment_function is `<prefix>_fragment` may compile `<prefix>_warp_fragment`
        // / `<prefix>_comp_fragment` / `<prefix>_blur_fragment` to replace the shared
        // mv_warp defaults — used by Fata Morgana's custom feedback warp + procedural
        // mirage comp + blur-of-prev. Every OTHER preset's library lacks those symbols,
        // so it falls back to the shared mvWarp_* defaults (byte-identical, gated
        // structurally — PresetRegression).
        let prefix = descriptor.fragmentFunction.hasSuffix("_fragment")
            ? String(descriptor.fragmentFunction.dropLast("_fragment".count))
            : descriptor.fragmentFunction
        let warpFn = library.makeFunction(name: "\(prefix)_warp_fragment")
            ?? library.makeFunction(name: "mvWarp_fragment")
        let blitFn = library.makeFunction(name: "\(prefix)_comp_fragment")
            ?? library.makeFunction(name: "mvWarp_blit_fragment")
        let blurFn = library.makeFunction(name: "\(prefix)_blur_fragment")

        guard let warpVertexFn  = library.makeFunction(name: "mvWarp_vertex"),
              let warpFragFn    = warpFn,
              let composeFn     = library.makeFunction(name: "mvWarp_compose_fragment"),
              let blitFragFn    = blitFn,
              let fullscreenVtx = library.makeFunction(name: "fullscreen_vertex")
        else {
            logger.error("mv_warp functions not found in compiled library for \(url.lastPathComponent)")
            return nil
        }
        // Warp + compose render INTO the feedback textures → feedbackFormat (float
        // for Dragon Bloom). The blit renders to the DRAWABLE → drawable pixelFormat.
        let fbFormat = feedbackFormat(descriptor)
        let warpDesc = MTLRenderPipelineDescriptor()
        warpDesc.vertexFunction = warpVertexFn
        warpDesc.fragmentFunction = warpFragFn
        warpDesc.colorAttachments[0].pixelFormat = fbFormat
        let composeDesc = MTLRenderPipelineDescriptor()
        composeDesc.vertexFunction = fullscreenVtx
        composeDesc.fragmentFunction = composeFn
        composeDesc.colorAttachments[0].pixelFormat = fbFormat
        composeDesc.colorAttachments[0].isBlendingEnabled = true
        composeDesc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        composeDesc.colorAttachments[0].destinationRGBBlendFactor = .one
        composeDesc.colorAttachments[0].sourceAlphaBlendFactor = .zero
        composeDesc.colorAttachments[0].destinationAlphaBlendFactor = .one
        let blitDesc = MTLRenderPipelineDescriptor()
        blitDesc.vertexFunction = fullscreenVtx
        blitDesc.fragmentFunction = blitFragFn
        blitDesc.colorAttachments[0].pixelFormat = pixelFormat
        do {
            let warpState    = try device.makeRenderPipelineState(descriptor: warpDesc)
            let composeState = try device.makeRenderPipelineState(descriptor: composeDesc)
            let blitState    = try device.makeRenderPipelineState(descriptor: blitDesc)
            // Optional Fata Morgana aux pipelines (D-139): blur-of-prev + the two
            // custom-shape blend variants. (nil for every other mv_warp preset.)
            let blurState = try blurFn.map { fn -> MTLRenderPipelineState in
                let bd = MTLRenderPipelineDescriptor()
                bd.vertexFunction = fullscreenVtx; bd.fragmentFunction = fn
                bd.colorAttachments[0].pixelFormat = fbFormat
                return try device.makeRenderPipelineState(descriptor: bd)
            }
            let (shapeAdd, shapeNorm) = try makeFataShapeStates(library: library, fbFormat: fbFormat)
            return MVWarpCompiledPipelines(
                warpState: warpState,
                composeState: composeState,
                blitState: blitState,
                blurState: blurState,
                shapeAdditiveState: shapeAdd,
                shapeNormalState: shapeNorm
            )
        } catch {
            logger.error("mv_warp pipeline creation failed for \(url.lastPathComponent): \(error)")
            return nil
        }
    }

    /// Build the optional Fata Morgana custom-shape pipelines (FM.L2, D-139) — additive
    /// (neon blobs) + normal-blend (textured echo). Both use `fata_shape_vertex` /
    /// `fata_shape_fragment` rendering into the feedback target; they differ only in
    /// blend. Returns (nil, nil) when the preset library lacks the shape functions.
    private func makeFataShapeStates(
        library: MTLLibrary, fbFormat: MTLPixelFormat
    ) throws -> (MTLRenderPipelineState?, MTLRenderPipelineState?) {
        guard let shapeVtx = library.makeFunction(name: "fata_shape_vertex"),
              let shapeFrag = library.makeFunction(name: "fata_shape_fragment")
        else { return (nil, nil) }
        func state(additive: Bool) throws -> MTLRenderPipelineState {
            let sd = MTLRenderPipelineDescriptor()
            sd.vertexFunction = shapeVtx
            sd.fragmentFunction = shapeFrag
            sd.colorAttachments[0].pixelFormat = fbFormat
            sd.colorAttachments[0].isBlendingEnabled = true
            sd.colorAttachments[0].rgbBlendOperation = .add
            sd.colorAttachments[0].alphaBlendOperation = .add
            sd.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            sd.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
            sd.colorAttachments[0].destinationRGBBlendFactor = additive ? .one : .oneMinusSourceAlpha
            sd.colorAttachments[0].destinationAlphaBlendFactor = additive ? .one : .oneMinusSourceAlpha
            return try device.makeRenderPipelineState(descriptor: sd)
        }
        return (try state(additive: true), try state(additive: false))
    }

    private func makeRayMarchPrimaryPipeline(
        library: MTLLibrary,
        descriptor: PresetDescriptor,
        url: URL,
        warpPipelines: MVWarpCompiledPipelines
    ) -> CompiledShader? {
        guard let vertexFn  = library.makeFunction(name: descriptor.vertexFunction),
              let gbufferFn = library.makeFunction(name: "raymarch_gbuffer_fragment")
        else {
            logger.error("Ray march functions not found for mv_warp preset \(url.lastPathComponent)")
            return nil
        }
        let gbufDesc = MTLRenderPipelineDescriptor()
        gbufDesc.vertexFunction = vertexFn
        gbufDesc.fragmentFunction = gbufferFn
        gbufDesc.colorAttachments[0].pixelFormat = .rg16Float
        gbufDesc.colorAttachments[1].pixelFormat = .rgba8Snorm
        gbufDesc.colorAttachments[2].pixelFormat = .rgba8Unorm
        do {
            let state = try device.makeRenderPipelineState(descriptor: gbufDesc)
            return CompiledShader(standard: state, rayMarch: state, mvWarp: warpPipelines)
        } catch {
            logger.error("G-buffer pipeline failed for mv_warp preset \(url.lastPathComponent): \(error)")
            return nil
        }
    }

    private func makeDirectPrimaryPipeline(
        library: MTLLibrary,
        descriptor: PresetDescriptor,
        url: URL,
        warpPipelines: MVWarpCompiledPipelines
    ) -> CompiledShader? {
        guard let vertexFn   = library.makeFunction(name: descriptor.vertexFunction),
              let fragmentFn = library.makeFunction(name: descriptor.fragmentFunction)
        else {
            logger.error("Fragment functions not found for direct mv_warp preset \(url.lastPathComponent)")
            return nil
        }
        let stdDesc = MTLRenderPipelineDescriptor()
        stdDesc.vertexFunction = vertexFn
        stdDesc.fragmentFunction = fragmentFn
        // The direct fragment renders INTO the mv_warp scene texture → feedbackFormat.
        stdDesc.colorAttachments[0].pixelFormat = feedbackFormat(descriptor)
        do {
            let state = try device.makeRenderPipelineState(descriptor: stdDesc)
            // Optional additive scene-geometry pipeline (Dragon Bloom strands, D-137).
            // Built only if the preset library defines the strand functions; folded
            // into the warp pipelines so the app can wire it via setSceneGeometry.
            let strand = makeSceneGeometryPipeline(library: library, descriptor: descriptor)
            let warp = MVWarpCompiledPipelines(
                warpState: warpPipelines.warpState,
                composeState: warpPipelines.composeState,
                blitState: warpPipelines.blitState,
                sceneGeometryState: strand,
                blurState: warpPipelines.blurState,
                shapeAdditiveState: warpPipelines.shapeAdditiveState,
                shapeNormalState: warpPipelines.shapeNormalState
            )
            return CompiledShader(standard: state, mvWarp: warp)
        } catch {
            logger.error("Standard pipeline failed for direct mv_warp preset \(url.lastPathComponent): \(error)")
            return nil
        }
    }

    /// Build the optional scene-geometry overlay pipeline for direct mv_warp presets
    /// that draw "marks on top" of the held/warped frame (D-138; generalised per-preset
    /// in Skein.ENGINE.1.1, D-143). NORMAL alpha blend (SRC_ALPHA, ONE_MINUS_SRC_ALPHA)
    /// so marks paint over the canvas (NOT additive — the per-draw primitive type +
    /// vertex/instance counts are supplied by the app via `setSceneGeometry` from the
    /// preset's `marks` descriptor block). Returns nil if the preset library defines no
    /// overlay functions.
    ///
    /// Per-preset lookup mirrors the `<prefix>_warp_fragment` precedent in
    /// `makeWarpPipelines` (D-139): a preset whose `fragment_function` is
    /// `<prefix>_fragment` declares `<prefix>_geometry_vertex` / `<prefix>_geometry_fragment`
    /// (e.g. Skein → `skein_geometry_*`). Dragon Bloom keeps its original
    /// `dragon_bloom_strand_*` names via the legacy fallback — its library is the only one
    /// that defines those symbols, so it resolves byte-identically and every other preset
    /// without overlay functions still gets nil.
    private func makeSceneGeometryPipeline(
        library: MTLLibrary, descriptor: PresetDescriptor
    ) -> MTLRenderPipelineState? {
        let prefix = descriptor.fragmentFunction.hasSuffix("_fragment")
            ? String(descriptor.fragmentFunction.dropLast("_fragment".count))
            : descriptor.fragmentFunction
        let vtxFn = library.makeFunction(name: "\(prefix)_geometry_vertex")
            ?? library.makeFunction(name: "dragon_bloom_strand_vertex")
        let fragFn = library.makeFunction(name: "\(prefix)_geometry_fragment")
            ?? library.makeFunction(name: "dragon_bloom_strand_fragment")
        guard let vtx = vtxFn, let frag = fragFn else { return nil }
        let geoDesc = MTLRenderPipelineDescriptor()
        geoDesc.vertexFunction = vtx
        geoDesc.fragmentFunction = frag
        // Overlay renders INTO the mv_warp scene/compose texture → feedbackFormat
        // (float for Dragon Bloom; sRGB drawable format for Skein).
        geoDesc.colorAttachments[0].pixelFormat = feedbackFormat(descriptor)
        // NORMAL alpha blend (SRC_ALPHA, ONE_MINUS_SRC_ALPHA) — butterchurn's
        // drawCustomWaveform path for waves with bAdditive=0 (the preset's
        // wavecode_*_bAdditive=0; the global bAdditiveWaves=1 is for the built-in
        // waveform only). Additive piled the centre-converging strands into an
        // over-saturated white core (→ black after the comp invert); normal-alpha
        // compositing matches the source and keeps the centre a flame, not a blob.
        geoDesc.colorAttachments[0].isBlendingEnabled = true
        geoDesc.colorAttachments[0].rgbBlendOperation = .add
        geoDesc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        geoDesc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        geoDesc.colorAttachments[0].alphaBlendOperation = .add
        geoDesc.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        geoDesc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        return try? device.makeRenderPipelineState(descriptor: geoDesc)
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
