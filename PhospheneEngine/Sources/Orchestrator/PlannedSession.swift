// PlannedSession — Output types for the SessionPlanner (Increment 4.3).
// Produced by DefaultSessionPlanner.plan(tracks:catalog:deviceTier:) before
// playback begins. Every selection carries its score breakdown and the
// transition decision that precedes it — fully inspectable, per D-014.
//
// Lives in the Orchestrator module, NOT in Session/SessionTypes.swift (D-017).

import Foundation
import Shared
import Presets
import Session

// MARK: - PlanningWarning

/// A soft failure that occurred while building the plan.
///
/// Plans are always producible from a non-empty catalog (degradation principle,
/// D-018). Warnings surface cases where the planner had to compromise.
public struct PlanningWarning: Sendable, Hashable, Codable {

    /// What went wrong.
    public let kind: Kind
    /// 0-based position of the affected track in the plan.
    public let trackIndex: Int
    /// Human-readable explanation for logging and debugging.
    public let message: String

    /// Categories of soft failure.
    ///
    /// Note: `CaseIterable` and `String` raw values are absent — `partialPreparation`
    /// carries an associated value, which is incompatible with both conformances.
    /// Custom `Codable` is implemented in the extension below.
    public enum Kind: Sendable, Hashable {
        /// All catalog presets were excluded (budget + identity gate) for this track.
        case noEligiblePresets
        /// The only available option shared a family with the previous preset.
        case forcedFamilyRepeat
        /// No preset fits within the device tier's frame budget; cheapest selected anyway.
        case budgetExceeded
        /// Section boundary data unavailable for this track.
        case missingSectionData
        /// One or more tracks had not finished preparing when this partial plan was built.
        case partialPreparation(unplannedCount: Int)
    }

    public init(kind: Kind, trackIndex: Int, message: String) {
        self.kind = kind
        self.trackIndex = trackIndex
        self.message = message
    }
}

// MARK: - PlanningWarning.Kind Codable

extension PlanningWarning.Kind: Codable {

    private enum CodingKeys: String, CodingKey { case caseName, unplannedCount }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decode(String.self, forKey: .caseName)
        switch name {
        case "noEligiblePresets":  self = .noEligiblePresets
        case "forcedFamilyRepeat": self = .forcedFamilyRepeat
        case "budgetExceeded":     self = .budgetExceeded
        case "missingSectionData": self = .missingSectionData
        case "partialPreparation":
            let count = try container.decode(Int.self, forKey: .unplannedCount)
            self = .partialPreparation(unplannedCount: count)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .caseName,
                in: container,
                debugDescription: "Unknown PlanningWarning.Kind: \(name)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .noEligiblePresets:  try container.encode("noEligiblePresets", forKey: .caseName)
        case .forcedFamilyRepeat: try container.encode("forcedFamilyRepeat", forKey: .caseName)
        case .budgetExceeded:     try container.encode("budgetExceeded", forKey: .caseName)
        case .missingSectionData: try container.encode("missingSectionData", forKey: .caseName)
        case .partialPreparation(let count):
            try container.encode("partialPreparation", forKey: .caseName)
            try container.encode(count, forKey: .unplannedCount)
        }
    }
}

// MARK: - PlannedTransition

/// An immutable record of a transition decision between two presets.
///
/// Produced by `DefaultTransitionPolicy` during planning. At track changes the
/// boundary is always synthetic (confidence=1.0), so `style` and `duration` are
/// driven purely by the previous track's energy estimate and preset affordances.
public struct PlannedTransition: Sendable {

    /// The preset that was playing before the transition.
    public let fromPreset: PresetDescriptor
    /// The preset that will begin playing after the transition.
    public let toPreset: PresetDescriptor
    /// The visual transition style selected from the outgoing preset's affordances.
    public let style: TransitionAffordance
    /// Duration of the transition in seconds. Always 0 for `.cut`.
    public let duration: TimeInterval
    /// Session time (seconds from session start) at which the transition begins.
    public let scheduledAt: TimeInterval
    /// Human-readable rationale forwarded from `TransitionDecision.rationale`.
    public let reason: String
}

// MARK: - PlannedTrack

/// One entry in a `PlannedSession`: a track paired with its selected preset
/// and the transition that leads into it.
///
/// `scoreBreakdown` carries the full sub-score breakdown from `DefaultPresetScorer`
/// so callers can inspect why a preset was chosen (D-014, D-032).
public struct PlannedTrack: Sendable {

    /// The track this entry is for.
    public let track: TrackIdentity
    /// The MIR profile used for scoring.
    public let trackProfile: TrackProfile
    /// The preset selected for this track.
    public let preset: PresetDescriptor
    /// The combined score from `DefaultPresetScorer` (0–1).
    public let presetScore: Float
    /// Sub-score breakdown for full inspection.
    public let scoreBreakdown: PresetScoreBreakdown
    /// Session time (seconds from session start) when this track begins.
    public let plannedStartTime: TimeInterval
    /// Session time when this track ends (`plannedStartTime + track duration`).
    public let plannedEndTime: TimeInterval
    /// How to transition *into* this track. Nil for the first track.
    public let incomingTransition: PlannedTransition?
}

// MARK: - PlannedSession

/// A fully pre-planned visual session for an ordered playlist.
///
/// Produced by `DefaultSessionPlanner` before playback begins. Consumption by
/// the render loop is deferred to Increment 4.5 (live adaptation).
///
/// ## Determinism
///
/// Given the same `(tracks, catalog, deviceTier)` input,
/// `DefaultSessionPlanner.plan` always produces a `PlannedSession` whose
/// `tracks` and `warnings` arrays are byte-identical.
public struct PlannedSession: Sendable {

    /// The device tier used when this plan was built.
    public let deviceTier: DeviceTier
    /// Ordered list of planned track entries.
    public let tracks: [PlannedTrack]
    /// Sum of all planned track durations.
    public let totalDuration: TimeInterval
    /// Soft failures that occurred during planning (insertions order = playlist order).
    public let warnings: [PlanningWarning]

    // MARK: - Convenience

    /// True when the plan contains no tracks.
    public var isEmpty: Bool { tracks.isEmpty }

    /// Returns the `PlannedTrack` that is active at the given session time.
    ///
    /// A track is active when `sessionTime ∈ [plannedStartTime, plannedEndTime)`.
    /// Returns nil when `sessionTime` is past the end of the last track or before 0.
    public func track(at sessionTime: TimeInterval) -> PlannedTrack? {
        tracks.first {
            sessionTime >= $0.plannedStartTime && sessionTime < $0.plannedEndTime
        }
    }

    /// Returns the `PlannedTransition` whose `scheduledAt` is within `tolerance` of
    /// the given session time.
    ///
    /// - Parameters:
    ///   - sessionTime: Session time in seconds.
    ///   - tolerance: Maximum deviation from `scheduledAt` (default 0.5 s).
    /// - Returns: The first matching transition, or nil if none fall within the window.
    public func transition(
        at sessionTime: TimeInterval,
        tolerance: TimeInterval = 0.5
    ) -> PlannedTransition? {
        tracks.compactMap(\.incomingTransition).first {
            abs($0.scheduledAt - sessionTime) <= tolerance
        }
    }

    /// Returns a copy of this plan with additional warnings appended.
    ///
    /// Used by `VisualizerEngine.extendPlan()` to attach `.partialPreparation`
    /// warnings when the plan covers fewer tracks than the full session.
    public func appendingWarnings(_ newWarnings: [PlanningWarning]) -> PlannedSession {
        guard !newWarnings.isEmpty else { return self }
        return PlannedSession(
            deviceTier: deviceTier,
            tracks: tracks,
            totalDuration: totalDuration,
            warnings: warnings + newWarnings
        )
    }
}
