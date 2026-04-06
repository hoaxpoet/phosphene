// PresetDescriptor — Metadata for a single visual preset.
// Loaded from JSON sidecar files that accompany each .metal shader.
// See CLAUDE.md "Scene Metadata Format" for field documentation.

import Foundation

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

    // MARK: - Shader Function Names

    /// Fragment function name in the .metal file. Defaults to "<lowercaseName>_fragment".
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
        fragmentFunction = try container.decodeIfPresent(String.self, forKey: .fragmentFunction) ?? "preset_fragment"
        vertexFunction = try container.decodeIfPresent(String.self, forKey: .vertexFunction) ?? "fullscreen_vertex"
        shaderFileName = try container.decodeIfPresent(String.self, forKey: .shaderFileName) ?? ""
    }
}
