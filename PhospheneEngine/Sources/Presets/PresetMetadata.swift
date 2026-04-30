// PresetMetadata — Enums and value types for Orchestrator-facing preset scoring metadata.
// All types are String-raw so they round-trip through JSON sidecars transparently.
// See PresetDescriptor for how these are decoded (fallback-on-missing, warn-on-malformed).

import Foundation
import Shared

// MARK: - RubricProfile

/// Which fidelity rubric ladder a preset is evaluated against (V.6, D-###).
///
/// Four stylized-2D / diagnostic presets (Plasma, Waveform, Nebula, SpectralCartograph)
/// use `.lightweight` — they are exempt from the full detail-cascade and material-count
/// requirements. All other presets use `.full`.
public enum RubricProfile: String, Sendable, Codable, Hashable {
    /// 7 mandatory + 4 expected + 4 preferred = 15 items.
    case full
    /// 4-item stylization contract (silence, deviation, perf, frame-match).
    case lightweight
}

// MARK: - RubricHints

/// Author-asserted rubric flags for items that cannot be statically detected.
///
/// Set these in the JSON sidecar's `"rubric_hints"` object when the preset meets
/// the criterion but the static analyzer cannot confirm it from source alone.
public struct RubricHints: Sendable, Codable, Equatable {
    /// P1: a distinct hero specular highlight is visible in ≥60% of frames.
    public let heroSpecular: Bool
    /// P3: volumetric light shafts or dust motes are present.
    public let dustMotes: Bool

    public init(heroSpecular: Bool = false, dustMotes: Bool = false) {
        self.heroSpecular = heroSpecular
        self.dustMotes = dustMotes
    }

    /// Default: all hints false (no author assertions).
    public static let allFalse = RubricHints()

    private enum CodingKeys: String, CodingKey {
        case heroSpecular = "hero_specular"
        case dustMotes    = "dust_motes"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        heroSpecular = try c.decodeIfPresent(Bool.self, forKey: .heroSpecular) ?? false
        dustMotes    = try c.decodeIfPresent(Bool.self, forKey: .dustMotes)    ?? false
    }
}

// MARK: - FatigueRisk

/// How visually fatiguing this preset is over extended viewing.
///
/// The Orchestrator applies a cooldown penalty between consecutive reuses
/// proportional to the risk level — `high` presets are held out longer
/// after each appearance to prevent viewer fatigue.
public enum FatigueRisk: String, Sendable, Codable, Hashable, CaseIterable {
    case low
    case medium
    case high
}

// MARK: - TransitionAffordance

/// Transition styles this preset tolerates as an incoming or outgoing transition.
///
/// The Orchestrator only schedules a transition type if both the outgoing
/// and incoming preset declare it in their `transitionAffordances`.
public enum TransitionAffordance: String, Sendable, Codable, Hashable, CaseIterable {
    case crossfade
    case cut
    case morph
}

// MARK: - SongSection

/// Musical section types this preset is suited for.
///
/// The Orchestrator cross-references detected or predicted section boundaries
/// against each candidate preset's `sectionSuitability` when building a
/// visual session plan. A preset that omits a section type receives a
/// suitability penalty for that section — it is not excluded entirely.
public enum SongSection: String, Sendable, Codable, Hashable, CaseIterable {
    case ambient
    case buildup
    case peak
    case bridge
    case comedown
}

// MARK: - ComplexityCost

/// Estimated render cost in milliseconds at 1080p, per device tier.
///
/// `tier1` covers M1/M2; `tier2` covers M3+. The Orchestrator uses these
/// values to avoid scheduling presets that would exceed the frame budget
/// (~8.3 ms for 120 fps, ~16.7 ms for 60 fps) on the active device.
///
/// ## JSON encoding
/// Accepts either a scalar (applied to both tiers):
/// ```json
/// "complexity_cost": 1.5
/// ```
/// or a nested object:
/// ```json
/// "complexity_cost": { "tier1": 2.1, "tier2": 0.9 }
/// ```
public struct ComplexityCost: Sendable, Equatable {
    /// Estimated ms on M1/M2.
    public var tier1: Float
    /// Estimated ms on M3+.
    public var tier2: Float

    public init(tier1: Float = 1.0, tier2: Float = 1.0) {
        self.tier1 = tier1
        self.tier2 = tier2
    }

    /// Estimated render cost in ms for the given device tier.
    public func cost(for tier: DeviceTier) -> Float {
        switch tier {
        case .tier1: return tier1
        case .tier2: return tier2
        }
    }
}

// MARK: ComplexityCost + Codable

extension ComplexityCost: Codable {
    private enum CodingKeys: String, CodingKey {
        case tier1, tier2
    }

    public init(from decoder: Decoder) throws {
        // Accept a bare scalar float (applied to both tiers) or a {"tier1":, "tier2":} object.
        if let scalar = try? decoder.singleValueContainer().decode(Float.self) {
            tier1 = scalar
            tier2 = scalar
        } else {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            tier1 = try container.decodeIfPresent(Float.self, forKey: .tier1) ?? 1.0
            tier2 = try container.decodeIfPresent(Float.self, forKey: .tier2) ?? 1.0
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(tier1, forKey: .tier1)
        try container.encode(tier2, forKey: .tier2)
    }
}
