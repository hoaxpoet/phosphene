// RubricResult — Value types for the V.6 fidelity rubric evaluation.
// All types are Codable and Sendable so they round-trip through reports and
// can be passed across actor boundaries without copying.
//
// Rubric structure per SHADER_CRAFT.md §12:
//   Full profile:        7 mandatory + 4 expected + 4 preferred = 15 possible
//   Lightweight profile: 4 items (L1–L4) = 4 possible
//
// Minimum certified score (full):       10/15, all 7 mandatory passing
// Minimum certified score (lightweight): 4/4  (L4 is manual)

import Foundation

// MARK: - RubricCategory

/// Which tier of the rubric an item belongs to.
public enum RubricCategory: String, Codable, Sendable, Equatable {
    case mandatory
    case expected
    case preferred
}

// MARK: - RubricItemStatus

/// Outcome of a single rubric item evaluation.
public enum RubricItemStatus: String, Codable, Sendable, Equatable {
    /// Automated check passed, or author-asserted hint says yes.
    case pass
    /// Automated check failed.
    case fail
    /// This item is not applicable for the preset's profile (e.g. lightweight presets
    /// are exempt from detail-cascade / material-count requirements).
    case exempt
    /// Automation cannot determine this; falls to Matt's `certified` flag. Item M7 only.
    case manual
}

// MARK: - RubricItem

/// The result of evaluating a single rubric criterion.
public struct RubricItem: Codable, Sendable, Equatable {
    /// Stable identifier, e.g. `"M1_detail_cascade"`, `"E2_detail_normals"`.
    public let id: String
    /// Short human-readable label.
    public let label: String
    /// Which tier this item belongs to.
    public let category: RubricCategory
    /// Pass / fail / exempt / manual outcome.
    public let status: RubricItemStatus
    /// One-line explanation: count found, callsite name, or reason for failure.
    public let detail: String

    public init(
        id: String,
        label: String,
        category: RubricCategory,
        status: RubricItemStatus,
        detail: String
    ) {
        self.id = id
        self.label = label
        self.category = category
        self.status = status
        self.detail = detail
    }
}

// MARK: - RubricResult

/// Complete rubric evaluation for one preset.
///
/// The `meetsAutomatedGate` boolean reflects all automatable criteria.
/// The `certified` field is the value from the JSON sidecar — it is only `true`
/// after Matt has performed a visual reference-frame match per SHADER_CRAFT.md §12.1.
///
/// Final certification = `meetsAutomatedGate && certified`.
public struct RubricResult: Codable, Sendable {
    /// Preset identifier (matches `PresetDescriptor.id`).
    public let presetID: String
    /// Which rubric ladder was applied.
    public let profile: RubricProfile
    /// All evaluated items, in rubric order.
    public let items: [RubricItem]

    // MARK: Aggregate counts

    /// Number of mandatory items that passed.
    /// Full: out of 7. Lightweight: out of 4 (L4 is manual, so automated max is 3).
    public let mandatoryPassCount: Int
    /// Number of expected items that passed (0 for lightweight).
    public let expectedPassCount: Int
    /// Number of preferred items that passed (0 for lightweight).
    public let preferredPassCount: Int
    /// Sum of all passing items across categories.
    public let totalScore: Int
    /// Maximum possible score for this profile (15 for full, 4 for lightweight).
    public let maxScore: Int

    // MARK: Gates

    /// `true` when all automatable criteria are satisfied:
    /// - Full: M1–M6 all pass, ≥2 expected pass, ≥1 preferred passes.
    /// - Lightweight: L1–L3 all pass (L4 is always manual).
    public let meetsAutomatedGate: Bool

    /// The raw value of the `certified` field in the JSON sidecar.
    /// Only `true` after Matt has reviewed and approved a reference-frame match.
    ///
    /// This field is *not* computed by the rubric analyzer — it is read from the
    /// descriptor and reported here for caller convenience.
    public let certified: Bool

    public init(
        presetID: String,
        profile: RubricProfile,
        items: [RubricItem],
        mandatoryPassCount: Int,
        expectedPassCount: Int,
        preferredPassCount: Int,
        totalScore: Int,
        maxScore: Int,
        meetsAutomatedGate: Bool,
        certified: Bool
    ) {
        self.presetID = presetID
        self.profile = profile
        self.items = items
        self.mandatoryPassCount = mandatoryPassCount
        self.expectedPassCount = expectedPassCount
        self.preferredPassCount = preferredPassCount
        self.totalScore = totalScore
        self.maxScore = maxScore
        self.meetsAutomatedGate = meetsAutomatedGate
        self.certified = certified
    }

    // MARK: Convenience

    /// Lookup a specific item by its stable ID.
    public func item(id: String) -> RubricItem? {
        items.first { $0.id == id }
    }

    /// Final certification status: automated gate met AND Matt has approved.
    public var isCertified: Bool { meetsAutomatedGate && certified }
}

// MARK: - RuntimeCheckResults

/// Results of GPU runtime checks required by rubric items M5 (silence fallback) and M6 (perf).
///
/// Supplied by test harnesses or the certification store; the `DefaultFidelityRubric`
/// analyzer itself is pure and does not perform rendering or timing.
public struct RuntimeCheckResults: Sendable {
    /// True when the preset renders a non-black frame at silence (all-zero FeatureVector).
    /// From Increment 5.2's "Preset produces non-black output" invariant.
    public let silenceNonBlack: Bool
    /// Estimated p95 frame time in ms, read from the descriptor's `complexityCost` field
    /// or measured directly. The rubric compares this against `DeviceTier.frameBudgetMs`.
    public let p95FrameTimeMs: Float

    public init(silenceNonBlack: Bool, p95FrameTimeMs: Float) {
        self.silenceNonBlack = silenceNonBlack
        self.p95FrameTimeMs = p95FrameTimeMs
    }
}
