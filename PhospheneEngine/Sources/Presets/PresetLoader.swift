// PresetLoader — Discovers .metal preset shaders, compiles pipeline states, and hot-reloads.
// Each .metal file is compiled independently with a common preamble prepended.
// Optional JSON sidecars provide metadata (name, family, feedback params).
// Hot-reload watches an external directory via DispatchSource.FileSystemObject.

import Foundation
import Metal
import os.log

private let logger = Logger(subsystem: "com.phosphene.presets", category: "PresetLoader")

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
    }

    // MARK: - Private State

    private let device: MTLDevice
    private let pixelFormat: MTLPixelFormat
    private let lock = NSLock()
    private var watchSource: DispatchSourceFileSystemObject?
    private var watchedDirectoryFD: Int32 = -1

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
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        for metalFile in metalFiles {
            let baseName = metalFile.deletingPathExtension().lastPathComponent

            // Load JSON sidecar if it exists.
            let jsonURL = metalFile.deletingPathExtension().appendingPathExtension("json")
            var descriptor = loadDescriptor(from: jsonURL, fallbackName: baseName)
            descriptor.shaderFileName = metalFile.lastPathComponent

            // Compile the shader.
            guard let pipelineState = compileShader(at: metalFile, descriptor: descriptor) else {
                continue
            }

            let loaded = LoadedPreset(descriptor: descriptor, pipelineState: pipelineState)

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

    private func compileShader(at url: URL, descriptor: PresetDescriptor) -> MTLRenderPipelineState? {
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

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFn
        pipelineDescriptor.fragmentFunction = fragmentFn
        pipelineDescriptor.colorAttachments[0].pixelFormat = pixelFormat

        do {
            return try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            logger.error("Pipeline state creation failed for \(url.lastPathComponent): \(error)")
            return nil
        }
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

    // MARK: - Common Shader Preamble

    /// Shared Metal code prepended to every preset shader.
    /// Contains FeatureVector struct, VertexOut, fullscreen_vertex, and color utilities.
    private static let shaderPreamble = """
    #include <metal_stdlib>
    using namespace metal;

    #define FFT_BIN_COUNT 512
    #define WAVEFORM_CAPACITY 2048

    // Matches Swift FeatureVector layout (24 floats = 96 bytes).
    struct FeatureVector {
        float bass, mid, treble;
        float bass_att, mid_att, treb_att;
        float sub_bass, low_bass, low_mid, mid_high, high_mid, high_freq;
        float beat_bass, beat_mid, beat_treble, beat_composite;
        float spectral_centroid, spectral_flux;
        float valence, arousal;
        float time, delta_time;
        float _pad0, _pad1;
    };

    struct VertexOut {
        float4 position [[position]];
        float2 uv;
    };

    // Full-screen triangle: 3 vertices, no vertex buffer needed.
    vertex VertexOut fullscreen_vertex(uint vid [[vertex_id]]) {
        VertexOut out;
        out.uv = float2((vid << 1) & 2, vid & 2);
        out.position = float4(out.uv * 2.0 - 1.0, 0.0, 1.0);
        out.uv.y = 1.0 - out.uv.y;
        return out;
    }

    // HSV to RGB conversion.
    float3 hsv2rgb(float3 c) {
        float3 p = abs(fract(float3(c.x) + float3(1.0, 2.0/3.0, 1.0/3.0)) * 6.0 - 3.0);
        return c.z * mix(float3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
    }
    """
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
