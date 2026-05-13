// PresetDescriptor — Metadata for a single visual preset.
// Loaded from JSON sidecar files that accompany each .metal shader.
// See CLAUDE.md "Scene Metadata Format" for field documentation.
// swiftlint:disable file_length

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

/// `SHADER_CRAFT.md §5.8` stage-rig configuration block declared in a ray-march
/// preset's JSON sidecar. Implementation contract authoritative in D-125(e);
/// the §5.8 spec text is illustrative.
///
/// Presence of this block in the JSON sidecar signals that the preset adopts
/// the §5.8 lighting recipe — `sceneMaterial` is expected to emit `matID == 2`
/// from `outMatID` so the `raymarch_lighting_fragment` dispatches through the
/// stage-rig path (slot-9 buffer + per-light Cook-Torrance loop). The CPU side
/// instantiates a per-preset stage-rig class (e.g. `FerrofluidStageRig`) that
/// owns the slot-9 UMA buffer carrying `StageRigState`.
///
/// All fields decode with sensible defaults so a partial JSON block still
/// produces a valid `StageRig` value — a deliberate choice so future presets
/// can override only the parameters that differ from the §5.8 baseline.
public struct StageRig: Sendable, Codable, Equatable {
    /// Number of active lights. Clamped to `[3, 6]` at decode time; out-of-range
    /// values log a warning and fall back to 4 per D-125(e).
    public var lightCount: Int
    /// World-space Y of the orbital plane (above the scene's center).
    public var orbitAltitude: Float
    /// World-space radius of the orbital circle (around the scene's forward focus).
    public var orbitRadius: Float
    /// Baseline angular velocity at neutral arousal (rad/sec). §5.8 spec value: 0.05.
    public var orbitSpeedBaseline: Float
    /// Per-`arousal` coefficient on top of the baseline (rad/sec at `arousal = +1`).
    /// §5.8 spec value: 0.15. Combined formula: `baseline + smoothstep(-0.5, 0.5, arousal) * coef`.
    public var orbitSpeedArousalCoef: Float
    /// Per-light palette phase offset (normalised `[0, 1]` cycle position). Length
    /// must equal `lightCount`; mismatches are truncated/padded with a warning.
    public var palettePhaseOffsets: [Float]
    /// Baseline intensity scalar (linear). §5.8 spec value: 5.0. Per-frame intensity
    /// is `baseline * (floor_coef + swing_coef * drums_energy_dev_smoothed)`.
    public var intensityBaseline: Float
    /// Floor coefficient — preserves visible beam presence at silence per D-019.
    /// §5.8 spec value: 0.4. Combined with the baseline gives `2.0` at zero-drum.
    public var intensityFloorCoef: Float
    /// Swing coefficient on top of the floor. §5.8 spec value: 0.6 → `intensity` rises
    /// to `baseline * (floor + swing) = 5.0 * 1.0 = 5.0` at `drums_energy_dev = 1.0`.
    public var intensitySwingCoef: Float
    /// Time constant for the `drums_energy_dev` envelope (milliseconds). §5.8 spec
    /// value: 150 ms. Prevents per-frame jitter on onset variation while preserving
    /// continuous response to envelope changes.
    public var intensitySmoothingTauMs: Float

    public init(
        lightCount: Int = 4,
        orbitAltitude: Float = 6.0,
        orbitRadius: Float = 4.0,
        orbitSpeedBaseline: Float = 0.05,
        orbitSpeedArousalCoef: Float = 0.15,
        palettePhaseOffsets: [Float] = [0.0, 0.33, 0.67, 0.17],
        intensityBaseline: Float = 5.0,
        intensityFloorCoef: Float = 0.4,
        intensitySwingCoef: Float = 0.6,
        intensitySmoothingTauMs: Float = 150
    ) {
        self.lightCount = lightCount
        self.orbitAltitude = orbitAltitude
        self.orbitRadius = orbitRadius
        self.orbitSpeedBaseline = orbitSpeedBaseline
        self.orbitSpeedArousalCoef = orbitSpeedArousalCoef
        self.palettePhaseOffsets = palettePhaseOffsets
        self.intensityBaseline = intensityBaseline
        self.intensityFloorCoef = intensityFloorCoef
        self.intensitySwingCoef = intensitySwingCoef
        self.intensitySmoothingTauMs = intensitySmoothingTauMs
    }

    enum CodingKeys: String, CodingKey {
        case lightCount = "light_count"
        case orbitAltitude = "orbit_altitude"
        case orbitRadius = "orbit_radius"
        case orbitSpeedBaseline = "orbit_speed_baseline"
        case orbitSpeedArousalCoef = "orbit_speed_arousal_coef"
        case palettePhaseOffsets = "palette_phase_offsets"
        case intensityBaseline = "intensity_baseline"
        case intensityFloorCoef = "intensity_floor_coef"
        case intensitySwingCoef = "intensity_swing_coef"
        case intensitySmoothingTauMs = "intensity_smoothing_tau_ms"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawCount = try container.decodeIfPresent(Int.self, forKey: .lightCount) ?? 4
        // Clamp `light_count` to [3, 6] per D-125(e) with a warning + fallback.
        let count: Int
        if rawCount < 3 || rawCount > 6 {
            Logging.renderer.warning(
                "PresetDescriptor.StageRig: light_count \(rawCount) out of range [3, 6] — using 4")
            count = 4
        } else {
            count = rawCount
        }
        self.lightCount = count
        self.orbitAltitude = try container.decodeIfPresent(Float.self, forKey: .orbitAltitude) ?? 6.0
        self.orbitRadius = try container.decodeIfPresent(Float.self, forKey: .orbitRadius) ?? 4.0
        self.orbitSpeedBaseline = try container.decodeIfPresent(
            Float.self, forKey: .orbitSpeedBaseline) ?? 0.05
        self.orbitSpeedArousalCoef = try container.decodeIfPresent(
            Float.self, forKey: .orbitSpeedArousalCoef) ?? 0.15

        // palette_phase_offsets length must equal light_count. Truncate / pad with
        // a warning per D-125(e). Padding uses evenly-spaced offsets (0, 1/n, 2/n,
        // …) so the visual character is at least chromatically varied rather than
        // collapsing to all-lights-at-phase-0.
        var offsets = try container.decodeIfPresent(
            [Float].self, forKey: .palettePhaseOffsets) ?? []
        if offsets.count != count {
            let actual = offsets.count
            Logging.renderer.warning(
                "PresetDescriptor.StageRig: palette_phase_offsets count \(actual) != light_count \(count) — adjusting")
            if offsets.count > count {
                offsets = Array(offsets.prefix(count))
            } else {
                let missing = count - offsets.count
                for i in 0 ..< missing {
                    offsets.append(Float(offsets.count + i) / Float(count))
                }
            }
        }
        self.palettePhaseOffsets = offsets

        self.intensityBaseline = try container.decodeIfPresent(
            Float.self, forKey: .intensityBaseline) ?? 5.0
        self.intensityFloorCoef = try container.decodeIfPresent(
            Float.self, forKey: .intensityFloorCoef) ?? 0.4
        self.intensitySwingCoef = try container.decodeIfPresent(
            Float.self, forKey: .intensitySwingCoef) ?? 0.6
        self.intensitySmoothingTauMs = try container.decodeIfPresent(
            Float.self, forKey: .intensitySmoothingTauMs) ?? 150
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
    /// Aesthetic family from cream-of-crop's 10-theme taxonomy + transition (D-123).
    /// Nil for diagnostic presets (`is_diagnostic: true`) — those are tools, not
    /// aesthetic content, so they don't belong in any aesthetic family.
    public let family: PresetCategory?
    /// Preferred segment-length **hint** in seconds (V.7.6.2: was "preferred duration").
    ///
    /// Informs the orchestrator's scoring heuristics. The hard ceiling on segment
    /// length is `maxDuration(forSection:)` (V.7.6.2 §5), not this field.
    public let duration: Int
    /// Natural cycle length in seconds, when this preset has a fixed visual cycle
    /// (V.7.6.2 §5). Optional — only set for presets like Arachne whose visual
    /// cycle (e.g. 60-second build sequence) is more authoritative than the
    /// formula-computed `maxDuration`. When set, caps `maxDuration(forSection:)`.
    public let naturalCycleSeconds: Float?
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

    /// When true, the mesh pipeline uses additive blending (src=one, dst=one).
    /// Used by presets with emissive overlapping geometry (e.g. Arachne bioluminescent strands).
    /// Defaults to false (no blending).
    public let meshAdditiveBlend: Bool

    // MARK: - Scene Configuration (Ray March Presets)

    /// Camera configuration for ray march presets. Nil uses `SceneUniforms` defaults.
    public let sceneCamera: SceneCamera?

    /// Light sources for ray march presets. The first entry maps to the primary
    /// `SceneUniforms` light; additional lights are ignored until the lighting pass
    /// supports multiple lights. Empty uses `SceneUniforms` defaults.
    public let sceneLights: [SceneLight]

    /// `SHADER_CRAFT.md §5.8` stage-rig configuration (V.9 Session 3 / D-125).
    ///
    /// When non-nil, the preset adopts the §5.8 multi-light orbital recipe:
    /// `sceneMaterial` emits `matID == 2` and the engine instantiates a
    /// per-preset stage-rig class whose CPU-driven `StageRigState` is bound at
    /// fragment slot 9 of the ray-march pipeline. Nil for presets that retain
    /// the single-light `SceneUniforms` path (matID == 0 / matID == 3). See
    /// D-125(e) for the canonical JSON schema. First consumer: Ferrofluid Ocean.
    public let stageRig: StageRig?

    /// Fog density for ray march presets (0 = no fog; 0.05 ≈ heavy fog).
    /// Maps `fogFar = max(1, 1/sceneFog)` and is stored in `sceneParamsB.y`.
    public let sceneFog: Float

    /// Fog start distance in world units. Stored in `sceneParamsB.x`. Default 20.0
    /// matches the historical `SceneUniforms()` initializer hard-coded value, so
    /// presets that omit `scene_fog_near` keep their previous fog behaviour. Set
    /// to a smaller value for close-framed scenes (e.g. Ferrofluid Ocean's ocean
    /// camera at ~4–14 m surface depth uses 0 so the fog band covers the visible
    /// surface). Failed Approach #-related: see V.9 Session 2 carry-forward note
    /// — the previous hard-coded default put the fog band entirely behind the
    /// visible surface for any close-framed preset.
    public let sceneFogNear: Float

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

    // MARK: - V.6 Certification Metadata

    /// V.6 certification flag. Set to `true` only after Matt has performed a visual
    /// reference-frame match against `docs/VISUAL_REFERENCES/<preset>/`.
    ///
    /// The Orchestrator excludes uncertified presets from session planning unless the
    /// user enables "Show uncertified presets" in Settings → Visuals. Defaults to `false`.
    public let certified: Bool

    /// Which rubric ladder this preset is evaluated against (full vs. lightweight).
    ///
    /// Lightweight presets (Plasma, Waveform, Nebula, SpectralCartograph) are evaluated
    /// against a 4-item stylization contract instead of the full 15-item rubric. Per D-064.
    /// Defaults to `.full`.
    public let rubricProfile: RubricProfile

    /// Author-asserted rubric hints for items P1 (hero specular) and P3 (dust motes).
    ///
    /// Static analysis cannot determine these; the preset author sets them in the sidecar.
    /// Defaults to `.allFalse`.
    public let rubricHints: RubricHints

    // MARK: - V.7.6.C Diagnostic Class

    /// Diagnostic presets are exempt from automatic segment scheduling. When `true`,
    /// `maxDuration(forSection:)` returns `.infinity` so SessionPlanner never inserts a
    /// boundary, and (per the V.7.6.D follow-up scope) the Orchestrator excludes the
    /// preset from automatic selection entirely — diagnostics are manual-switch only.
    /// Defaults to `false`.
    public let isDiagnostic: Bool

    // MARK: - BUG-011 round 8: Completion-Gated Transitions

    /// When `true`, the preset is allowed to run until it emits a
    /// `PresetSignaling.presetCompletionEvent` rather than being timed out by the
    /// orchestrator. `maxDuration(forSection:)` returns `.infinity` so SessionPlanner's
    /// motion-intensity / fatigue / linger formula doesn't cap the segment, and
    /// `applyLiveUpdate` suppresses mood-derived preset overrides while the preset
    /// is active. Section boundaries still terminate segments (the planner's
    /// `remainingInSection` cap is unchanged) and the runtime completion event
    /// continues to trigger `nextPreset()` via the existing `wirePresetCompletionSubscription`
    /// wiring. Reserved for presets whose visual contract has a definite end state
    /// (Arachne's build cycle is the canonical case). Defaults to `false`.
    public let waitForCompletionEvent: Bool

    // MARK: - Text Overlay

    /// When `true`, the engine creates a `DynamicTextOverlay` for this preset and binds
    /// it at fragment texture(12). The fragment shader is expected to declare
    /// `texture2d<float, access::sample> textOverlay [[texture(12)]]` and blend it
    /// over the visualization output using flipped-Y sampling.
    /// Defaults to `false`.
    public let textOverlay: Bool

    // MARK: - Staged Composition (V.ENGINE.1)

    /// Ordered stages for `.staged` presets. Empty for non-staged presets.
    ///
    /// When `passes` contains `.staged`, `PresetLoader` compiles one pipeline state
    /// per stage; `RenderPipeline` walks the stages each frame, rendering non-final
    /// stages into per-stage `.rgba16Float` offscreen textures and the final stage
    /// into the drawable. Each stage's `samples` array names earlier stages whose
    /// outputs are bound at fragment textures starting at `[[texture(13)]]`.
    public let stages: [PresetStage]

    // MARK: - CodingKeys

    /// Keys for all stored properties — used by both `init(from:)` and `encode(to:)`.
    enum CodingKeys: String, CodingKey {
        case name, family, duration, description, author
        case naturalCycleSeconds = "natural_cycle_seconds"
        case beatSource = "beat_source"
        case beatZoom = "beat_zoom"
        case beatRot = "beat_rot"
        case baseZoom = "base_zoom"
        case baseRot = "base_rot"
        case decay
        case beatSensitivity = "beat_sensitivity"
        case passes
        case meshThreadCount = "mesh_thread_count"
        case meshAdditiveBlend = "additive_blend"
        case sceneCamera = "scene_camera"
        case sceneLights = "scene_lights"
        case stageRig = "stage_rig"
        case sceneFog = "scene_fog"
        case sceneFogNear = "scene_fog_near"
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
        case certified
        case rubricProfile = "rubric_profile"
        case rubricHints = "rubric_hints"
        case isDiagnostic = "is_diagnostic"
        case waitForCompletionEvent = "wait_for_completion_event"
        case textOverlay  = "text_overlay"
        case stages
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

    public init(from decoder: Decoder) throws { // swiftlint:disable:this function_body_length
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name             = try container.decode(String.self, forKey: .name)
        family           = try container.decodeIfPresent(PresetCategory.self, forKey: .family)
        duration         = try container.decodeIfPresent(Int.self, forKey: .duration) ?? 30
        naturalCycleSeconds = try container.decodeIfPresent(Float.self, forKey: .naturalCycleSeconds)
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
        meshAdditiveBlend = try container.decodeIfPresent(Bool.self, forKey: .meshAdditiveBlend) ?? false
        sceneCamera      = try container.decodeIfPresent(SceneCamera.self, forKey: .sceneCamera)
        sceneLights      = try container.decodeIfPresent([SceneLight].self, forKey: .sceneLights) ?? []
        stageRig         = try container.decodeIfPresent(StageRig.self, forKey: .stageRig)
        sceneFog         = try container.decodeIfPresent(Float.self, forKey: .sceneFog) ?? 0
        sceneFogNear     = try container.decodeIfPresent(Float.self, forKey: .sceneFogNear) ?? 20.0
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

        // MARK: V.6 Certification Fields
        certified = try container.decodeIfPresent(Bool.self, forKey: .certified) ?? false

        if let rawProfile = try container.decodeIfPresent(String.self, forKey: .rubricProfile) {
            if let parsed = RubricProfile(rawValue: rawProfile) {
                rubricProfile = parsed
            } else {
                let presetName = name
                Logging.renderer.warning(
                    "PresetDescriptor '\(presetName)': unknown rubric_profile '\(rawProfile)' — using .full")
                rubricProfile = .full
            }
        } else {
            rubricProfile = .full
        }

        rubricHints = (try? container.decodeIfPresent(RubricHints.self, forKey: .rubricHints)) ?? .allFalse

        // MARK: V.7.6.C Diagnostic Class
        isDiagnostic = try container.decodeIfPresent(Bool.self, forKey: .isDiagnostic) ?? false

        // MARK: BUG-011 round 8 — Completion-gated transitions
        waitForCompletionEvent = try container.decodeIfPresent(
            Bool.self, forKey: .waitForCompletionEvent) ?? false

        // MARK: Text Overlay
        textOverlay = try container.decodeIfPresent(Bool.self, forKey: .textOverlay) ?? false

        // MARK: Staged Composition (V.ENGINE.1)
        stages = try container.decodeIfPresent([PresetStage].self, forKey: .stages) ?? []
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
