// PresetStage — One stage in a `.staged` preset's composition graph (V.ENGINE.1).
//
// A staged preset declares an ordered `stages: [...]` array on its JSON sidecar.
// Each stage names a fragment function and an optional list of earlier stages
// whose outputs it samples as fragment textures starting at `[[texture(13)]]`.
// Non-final stages render to per-stage `.rgba16Float` offscreen textures; the
// final stage writes to the drawable.
//
// See `docs/ENGINE/RENDER_CAPABILITY_REGISTRY.md` and the `StagedSandbox`
// diagnostic preset for the canonical authoring pattern.

import Foundation

// MARK: - PresetStage

/// One stage in a staged-composition preset.
public struct PresetStage: Sendable, Codable, Equatable {

    /// Stage identifier — must be unique within the preset.
    /// Used as the texture key when later stages sample this stage's output.
    public let name: String

    /// Metal fragment function name. Defined in the preset's `.metal` source and
    /// compiled by `PresetLoader` against the standard preamble.
    public let fragmentFunction: String

    /// Names of earlier stages whose outputs this stage samples.
    ///
    /// Bound at fragment textures `[[texture(13)]]`, `[[texture(14)]]`, ... in the
    /// order listed. Empty / omitted = no earlier-stage inputs (typical for the
    /// first stage).
    public let samples: [String]

    public init(
        name: String,
        fragmentFunction: String,
        samples: [String] = []
    ) {
        self.name = name
        self.fragmentFunction = fragmentFunction
        self.samples = samples
    }

    enum CodingKeys: String, CodingKey {
        case name
        case fragmentFunction = "fragment_function"
        case samples
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.fragmentFunction = try container.decode(String.self, forKey: .fragmentFunction)
        self.samples = try container.decodeIfPresent([String].self, forKey: .samples) ?? []
    }
}
