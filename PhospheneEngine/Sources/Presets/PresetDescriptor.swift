// PresetDescriptor — Metadata for a single visual preset.
// Loaded from JSON sidecar files that accompany each .metal shader.
// See CLAUDE.md "Scene Metadata Format" for field documentation.

import Foundation
import Shared
import simd
import os.log

// MARK: - Scene Configuration Types

/// Camera configuration declared in a ray march preset's JSON sidecar.
///
/// `position` and `target` are in world-space; `fov` is the vertical field of view in **degrees**
/// (e.g. 65). `makeSceneUniforms(from:)` converts to radians before uploading to the GPU.
/// These are used to populate `SceneUniforms` when the preset is activated.
public struct SceneCamera: Sendable, Codable, Equatable {
    /// World-space camera position.
    public var position: SIMD3<Float>
    /// World-space point the camera looks toward.
    public var target: SIMD3<Float>
    /// Vertical field of view in **degrees** (e.g. 65). Converted to radians in makeSceneUniforms.
    public var fov: Float

    public init(
        position: SIMD3<Float> = SIMD3(0, 0, -5),
        target: SIMD3<Float> = .zero,
        fov: Float = 65.0
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
///
/// ## Render Graph
///
/// The `passes` array declares which render capabilities this preset uses:
///
/// ```json
/// { "passes": ["feedback", "particles"] }
/// ```
///
/// If the JSON uses the legacy `use_feedback` / `use_mesh_shader` / `use_post_process` /
/// `use_ray_march` / `use_particles` boolean flags instead of `"passes"`, the decoder
/// synthesises the `passes` array automatically for backward compatibility.
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

    // MARK: - Render Graph (Increment 3.6)

    /// Ordered render passes declared by this preset.
    ///
    /// Replaces the legacy `use_feedback`, `use_particles`, `use_mesh_shader`,
    /// `use_post_process`, and `use_ray_march` boolean flags.
    /// `RenderPipeline.renderFrame` walks this array and executes the first pass
    /// whose required subsystem is available, falling back to `.direct`.
    public let passes: [RenderPass]

    // MARK: - Capability Accessors (computed from passes)

    /// Whether this preset uses the Milkdrop-style feedback loop.
    public var useFeedback: Bool { passes.contains(.feedback) }
    /// Whether this preset attaches GPU compute particles.
    public var useParticles: Bool { passes.contains(.particles) }
    /// Whether this preset uses the Metal mesh shader pipeline.
    public var useMeshShader: Bool { passes.contains(.meshShader) }
    /// Whether this preset uses the HDR post-process chain.
    public var usePostProcess: Bool { passes.contains(.postProcess) }
    /// Whether this preset uses the deferred ray march pipeline.
    public var useRayMarch: Bool { passes.contains(.rayMarch) }
    /// Whether this preset uses the SSGI indirect illumination pass (Increment 3.17).
    /// Only meaningful when `useRayMarch` is also true.
    public var useSSGI: Bool { passes.contains(.ssgi) }

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

    /// Ray march far plane distance in world units. Rays that travel this far without
    /// hitting geometry are treated as sky misses. Default 30. Increase for deep corridors
    /// or open scenes; decrease for tight interior scenes to recover march step budget.
    public let sceneFarPlane: Float

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

    // MARK: - Orchestrator Scoring Metadata (Increment 4.0)

    /// 0 = sparse/minimal, 1 = packed/busy. Low-arousal tracks prefer low density.
    public let visualDensity: Float

    /// 0 = static/slow, 1 = fast/kinetic. Informs tempo match during scoring.
    public let motionIntensity: Float

    /// `[cool, warm]`, each 0–1. 0 = cold blue, 1 = hot orange.
    /// The Orchestrator intersects this range with the mood-derived target range.
    public let colorTemperatureRange: SIMD2<Float>

    /// Controls the cooldown penalty between consecutive reuses of this preset.
    public let fatigueRisk: FatigueRisk

    /// Transition styles this preset tolerates as an incoming or outgoing transition.
    public let transitionAffordances: [TransitionAffordance]

    /// Which song sections this preset suits. Default = all (no suitability penalty).
    public let sectionSuitability: [SongSection]

    /// Estimated render cost in ms at 1080p per device tier.
    public let complexityCost: ComplexityCost

    /// Maps stem names ("vocals", "drums", "bass", "other") to visual parameter descriptors.
    ///
    /// Presence of a key signals that this preset responds to that stem.
    /// The string value (e.g. "terrain_height_adaptive") is a hint for the Orchestrator
    /// visual-wiring layer; the scorer only checks key membership.
    public let stemAffinity: [String: String]

    // MARK: - CodingKeys

    /// Keys for all stored properties — used by both `init(from:)` and `encode(to:)`.
    enum CodingKeys: String, CodingKey {
        case name, family, duration, description, author
        case beatSource = "beat_source"
        case beatZoom = "beat_zoom"
        case beatRot = "beat_rot"
        case baseZoom = "base_zoom"
        case baseRot = "base_rot"
        case decay
        case beatSensitivity = "beat_sensitivity"
        case passes
        case meshThreadCount = "mesh_thread_count"
        case sceneCamera = "scene_camera"
        case sceneLights = "scene_lights"
        case sceneFog = "scene_fog"
        case sceneAmbient = "scene_ambient"
        case sceneFarPlane = "scene_far_plane"
        case fragmentFunction = "fragment_function"
        case vertexFunction = "vertex_function"
        case shaderFileName = "shader_file"
        case visualDensity = "visual_density"
        case motionIntensity = "motion_intensity"
        case colorTemperatureRange = "color_temperature_range"
        case fatigueRisk = "fatigue_risk"
        case transitionAffordances = "transition_affordances"
        case sectionSuitability = "section_suitability"
        case complexityCost = "complexity_cost"
        case stemAffinity = "stem_affinity"
    }

    /// Keys for legacy boolean flags — decode-only, not stored as properties.
    /// Used in `synthesizePasses(from:)` for backward-compatible JSON parsing.
    private enum LegacyCodingKeys: String, CodingKey {
        case useFeedback    = "use_feedback"
        case useMeshShader  = "use_mesh_shader"
        case useParticles   = "use_particles"
        case usePostProcess = "use_post_process"
        case useRayMarch    = "use_ray_march"
    }

    // MARK: - Decoding

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name             = try container.decode(String.self, forKey: .name)
        family           = try container.decodeIfPresent(PresetCategory.self, forKey: .family) ?? .waveform
        duration         = try container.decodeIfPresent(Int.self, forKey: .duration) ?? 30
        description      = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        author           = try container.decodeIfPresent(String.self, forKey: .author) ?? ""
        beatSource       = try container.decodeIfPresent(BeatSource.self, forKey: .beatSource) ?? .bass
        beatZoom         = try container.decodeIfPresent(Float.self, forKey: .beatZoom) ?? 0.03
        beatRot          = try container.decodeIfPresent(Float.self, forKey: .beatRot) ?? 0.01
        baseZoom         = try container.decodeIfPresent(Float.self, forKey: .baseZoom) ?? 0.12
        baseRot          = try container.decodeIfPresent(Float.self, forKey: .baseRot) ?? 0.03
        decay            = try container.decodeIfPresent(Float.self, forKey: .decay) ?? 0.955
        beatSensitivity  = try container.decodeIfPresent(Float.self, forKey: .beatSensitivity) ?? 1.0
        meshThreadCount  = try container.decodeIfPresent(Int.self, forKey: .meshThreadCount) ?? 64
        sceneCamera      = try container.decodeIfPresent(SceneCamera.self, forKey: .sceneCamera)
        sceneLights      = try container.decodeIfPresent([SceneLight].self, forKey: .sceneLights) ?? []
        sceneFog         = try container.decodeIfPresent(Float.self, forKey: .sceneFog) ?? 0
        sceneAmbient     = try container.decodeIfPresent(Float.self, forKey: .sceneAmbient) ?? 0.1
        sceneFarPlane    = try container.decodeIfPresent(Float.self, forKey: .sceneFarPlane) ?? 30.0
        fragmentFunction = try container.decodeIfPresent(String.self, forKey: .fragmentFunction) ?? "preset_fragment"
        vertexFunction   = try container.decodeIfPresent(String.self, forKey: .vertexFunction) ?? "fullscreen_vertex"
        shaderFileName   = try container.decodeIfPresent(String.self, forKey: .shaderFileName) ?? ""

        // Render graph: prefer the new "passes" key; fall back to legacy boolean flags.
        if let decoded = try container.decodeIfPresent([RenderPass].self, forKey: .passes) {
            passes = decoded
        } else {
            passes = try Self.synthesizePasses(from: decoder)
        }

        // MARK: Orchestrator Scoring Metadata (Increment 4.0)
        visualDensity = try container.decodeIfPresent(Float.self, forKey: .visualDensity) ?? 0.5
        motionIntensity = try container.decodeIfPresent(Float.self, forKey: .motionIntensity) ?? 0.5
        colorTemperatureRange = try container.decodeIfPresent(
            SIMD2<Float>.self, forKey: .colorTemperatureRange) ?? SIMD2(0.3, 0.7)

        // Decode fatigue_risk as a raw String so an unrecognised value logs a warning
        // and falls back to .medium rather than throwing and rejecting the whole preset.
        if let rawRisk = try container.decodeIfPresent(String.self, forKey: .fatigueRisk) {
            if let parsed = FatigueRisk(rawValue: rawRisk) {
                fatigueRisk = parsed
            } else {
                // Capture name as a local to avoid "escaping autoclosure captures mutating self" error.
                let presetName = name
                Logging.renderer.warning(
                    "PresetDescriptor '\(presetName)': unknown fatigue_risk '\(rawRisk)' — using .medium")
                fatigueRisk = .medium
            }
        } else {
            fatigueRisk = .medium
        }

        transitionAffordances = try container.decodeIfPresent(
            [TransitionAffordance].self, forKey: .transitionAffordances) ?? [.crossfade]
        sectionSuitability = try container.decodeIfPresent(
            [SongSection].self, forKey: .sectionSuitability) ?? SongSection.allCases
        complexityCost = try container.decodeIfPresent(
            ComplexityCost.self, forKey: .complexityCost) ?? ComplexityCost()
        stemAffinity = try container.decodeIfPresent(
            [String: String].self, forKey: .stemAffinity) ?? [:]
    }

    /// Synthesise a `passes` array from legacy boolean flags.
    /// Used when JSON predates the `"passes"` key (Increment 3.6).
    private static func synthesizePasses(from decoder: any Decoder) throws -> [RenderPass] {
        let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
        // Use optional-chaining to silently ignore missing or malformed keys.
        let hasMesh      = (try? legacy.decodeIfPresent(Bool.self, forKey: .useMeshShader)) == .some(true)
        let hasRayMarch  = (try? legacy.decodeIfPresent(Bool.self, forKey: .useRayMarch)) == .some(true)
        let hasPostProc  = (try? legacy.decodeIfPresent(Bool.self, forKey: .usePostProcess)) == .some(true)
        let hasFeedback  = (try? legacy.decodeIfPresent(Bool.self, forKey: .useFeedback)) == .some(true)
        let hasParticles = (try? legacy.decodeIfPresent(Bool.self, forKey: .useParticles)) == .some(true)

        if hasMesh {
            return [.meshShader]
        }
        if hasRayMarch {
            return hasPostProc ? [.rayMarch, .postProcess] : [.rayMarch]
        }
        if hasPostProc {
            return [.postProcess]
        }
        if hasFeedback {
            return hasParticles ? [.feedback, .particles] : [.feedback]
        }
        return [.direct]
    }
}
