// PresetDescriptor — Metadata for a single visual preset.
// Loaded from JSON sidecar files that accompany each .metal shader.
// See CLAUDE.md "Scene Metadata Format" for field documentation.

import Foundation
import simd

// MARK: - Scene Configuration Types

/// Camera configuration declared in a ray march preset's JSON sidecar.
///
/// `position` and `target` are in world-space; `fov` is the vertical field of view in radians.
/// These are used to populate `SceneUniforms` when the preset is activated.
public struct SceneCamera: Sendable, Codable, Equatable {
    /// World-space camera position.
    public var position: SIMD3<Float>
    /// World-space point the camera looks toward.
    public var target: SIMD3<Float>
    /// Vertical field of view in radians.
    public var fov: Float

    public init(
        position: SIMD3<Float> = SIMD3(0, 0, -5),
        target: SIMD3<Float> = .zero,
        fov: Float = .pi / 4.0
    ) {
        self.position = position
        self.target = target
        self.fov = fov
    }
}

/// A single scene light declared in a ray march preset's JSON sidecar.
public struct SceneLight: Sendable, Codable, Equatable {
    /// World-space light position.
    public var position: SIMD3<Float>
    /// Linear-RGB light colour (each component 0–1).
    public var color: SIMD3<Float>
    /// Intensity multiplier.
    public var intensity: Float

    public init(
        position: SIMD3<Float> = SIMD3(3, 8, -3),
        color: SIMD3<Float> = SIMD3(1, 1, 1),
        intensity: Float = 5.0
    ) {
        self.position = position
        self.color = color
        self.intensity = intensity
    }
}

// MARK: - PresetDescriptor

/// Metadata for a single visual preset, loaded from a JSON sidecar file.
///
/// Each `.metal` shader file may have an accompanying `.json` file defining
/// feedback parameters, audio routing, and display metadata. Missing fields
/// use sensible defaults (see `init(from:)`).
public struct PresetDescriptor: Sendable, Codable, Identifiable {
    public var id: String { name }

    /// Display name.
    public let name: String
    /// Aesthetic family: "waveform", "geometric", "fractal", etc.
    public let family: PresetCategory
    /// Preferred scene duration in seconds.
    public let duration: Int
    /// Human-readable description.
    public let description: String
    /// Preset author.
    public let author: String

    // MARK: - Audio Routing

    /// Which onset drives the beat uniform: "bass", "mid", "treble", "composite".
    public let beatSource: BeatSource

    // MARK: - Feedback Parameters

    /// Beat accent zoom (keep smaller than baseZoom).
    public let beatZoom: Float
    /// Beat accent rotation.
    public let beatRot: Float
    /// Continuous energy zoom (primary driver).
    public let baseZoom: Float
    /// Continuous energy rotation (primary driver).
    public let baseRot: Float
    /// Feedback decay per frame. 0.85 = short trails, 0.95 = long trails.
    public let decay: Float
    /// Beat pulse multiplier. 0.0 = ignore beats. Range 0–3.0.
    public let beatSensitivity: Float

    // MARK: - Feedback

    /// Whether this preset uses the feedback texture loop (Milkdrop-style trails).
    /// When true, the RenderPipeline wraps this preset in a two-pass feedback architecture.
    public let useFeedback: Bool

    /// Whether this preset uses the Metal mesh shader pipeline.
    ///
    /// When true, `PresetLoader` compiles a `MTLMeshRenderPipelineDescriptor` on M3+
    /// (`device.supportsFamily(.apple8)`) or falls back to a standard vertex+fragment
    /// pipeline on M1/M2.  The RenderPipeline routes through `drawWithMeshShader`
    /// instead of `drawDirect` or `drawWithFeedback`. Defaults to `false`.
    public let useMeshShader: Bool

    /// Whether this preset uses the GPU compute particle system.
    /// When true, `ProceduralGeometry` is attached and particles are rendered on top
    /// of the preset fragment shader. Defaults to false so presets that don't need
    /// particles (e.g. surface-based feedback presets) don't pay the cost or get the
    /// visual overlay.
    public let useParticles: Bool

    /// Whether this preset uses the HDR post-process chain (bloom + ACES tone mapping).
    /// When true, the scene is rendered to a `.rgba16Float` HDR texture, followed by
    /// a bright pass, separable Gaussian bloom blur, and ACES composite to the drawable.
    /// Defaults to `false` — existing presets are unaffected.
    public let usePostProcess: Bool

    /// Whether this preset uses the deferred ray march pipeline (Increment 3.14).
    ///
    /// When true, `PresetLoader` compiles a G-buffer pipeline state with 3 color attachments
    /// (`.rg16Float`, `.rgba8Snorm`, `.rgba8Unorm`) using `raymarch_gbuffer_fragment` as
    /// the fragment function.  The preset source must define `sceneSDF()` and `sceneMaterial()`.
    /// The `RenderPipeline` routes through `drawWithRayMarch` instead of `drawDirect`
    /// or `drawWithFeedback`.  Defaults to `false`.
    public let useRayMarch: Bool

    // MARK: - Mesh Shader Configuration

    /// Mesh threadgroup size — must match `[[mesh, max_total_threads_per_threadgroup(N)]]`
    /// in the preset's mesh shader function.  Only relevant when `useMeshShader == true`.
    /// Defaults to 64 (the standard threadgroup size for production preset mesh shaders).
    public let meshThreadCount: Int

    // MARK: - Scene Configuration (Ray March Presets)

    /// Camera configuration for ray march presets. Nil uses `SceneUniforms` defaults.
    public let sceneCamera: SceneCamera?

    /// Light sources for ray march presets. The first entry maps to the primary
    /// `SceneUniforms` light; additional lights are ignored until the lighting pass
    /// supports multiple lights. Empty uses `SceneUniforms` defaults.
    public let sceneLights: [SceneLight]

    /// Fog density for ray march presets (0 = no fog; 0.05 ≈ heavy fog).
    /// Stored in `sceneParamsB.x`; far-plane fog maps `fogFar = max(1, 1/sceneFog)`.
    public let sceneFog: Float

    /// Ambient light intensity multiplier for ray march presets (0–1).
    /// Stored in `sceneParamsB.z`.
    public let sceneAmbient: Float

    // MARK: - Shader Function Names

    /// Fragment function name in the .metal file. Defaults to "preset_fragment".
    public let fragmentFunction: String
    /// Vertex function name. Defaults to "fullscreen_vertex".
    public let vertexFunction: String

    // MARK: - Internal

    /// Source .metal file name (populated by PresetLoader, not from JSON).
    public var shaderFileName: String = ""

    public enum BeatSource: String, Sendable, Codable {
        case bass
        case mid
        case treble
        case composite
    }

    enum CodingKeys: String, CodingKey {
        case name, family, duration, description, author
        case beatSource = "beat_source"
        case beatZoom = "beat_zoom"
        case beatRot = "beat_rot"
        case baseZoom = "base_zoom"
        case baseRot = "base_rot"
        case decay
        case beatSensitivity = "beat_sensitivity"
        case useFeedback = "use_feedback"
        case useMeshShader = "use_mesh_shader"
        case useParticles = "use_particles"
        case usePostProcess = "use_post_process"
        case useRayMarch = "use_ray_march"
        case meshThreadCount = "mesh_thread_count"
        case sceneCamera = "scene_camera"
        case sceneLights = "scene_lights"
        case sceneFog = "scene_fog"
        case sceneAmbient = "scene_ambient"
        case fragmentFunction = "fragment_function"
        case vertexFunction = "vertex_function"
        case shaderFileName = "shader_file"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        family = try container.decodeIfPresent(PresetCategory.self, forKey: .family) ?? .waveform
        duration = try container.decodeIfPresent(Int.self, forKey: .duration) ?? 30
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        author = try container.decodeIfPresent(String.self, forKey: .author) ?? ""
        beatSource = try container.decodeIfPresent(BeatSource.self, forKey: .beatSource) ?? .bass
        beatZoom = try container.decodeIfPresent(Float.self, forKey: .beatZoom) ?? 0.03
        beatRot = try container.decodeIfPresent(Float.self, forKey: .beatRot) ?? 0.01
        baseZoom = try container.decodeIfPresent(Float.self, forKey: .baseZoom) ?? 0.12
        baseRot = try container.decodeIfPresent(Float.self, forKey: .baseRot) ?? 0.03
        decay = try container.decodeIfPresent(Float.self, forKey: .decay) ?? 0.955
        beatSensitivity = try container.decodeIfPresent(Float.self, forKey: .beatSensitivity) ?? 1.0
        useFeedback = try container.decodeIfPresent(Bool.self, forKey: .useFeedback) ?? false
        useMeshShader = try container.decodeIfPresent(Bool.self, forKey: .useMeshShader) ?? false
        useParticles = try container.decodeIfPresent(Bool.self, forKey: .useParticles) ?? false
        usePostProcess = try container.decodeIfPresent(Bool.self, forKey: .usePostProcess) ?? false
        useRayMarch = try container.decodeIfPresent(Bool.self, forKey: .useRayMarch) ?? false
        meshThreadCount = try container.decodeIfPresent(Int.self, forKey: .meshThreadCount) ?? 64
        sceneCamera = try container.decodeIfPresent(SceneCamera.self, forKey: .sceneCamera)
        sceneLights = try container.decodeIfPresent([SceneLight].self, forKey: .sceneLights) ?? []
        sceneFog = try container.decodeIfPresent(Float.self, forKey: .sceneFog) ?? 0
        sceneAmbient = try container.decodeIfPresent(Float.self, forKey: .sceneAmbient) ?? 0.1
        fragmentFunction = try container.decodeIfPresent(String.self, forKey: .fragmentFunction) ?? "preset_fragment"
        vertexFunction = try container.decodeIfPresent(String.self, forKey: .vertexFunction) ?? "fullscreen_vertex"
        shaderFileName = try container.decodeIfPresent(String.self, forKey: .shaderFileName) ?? ""
    }
}
