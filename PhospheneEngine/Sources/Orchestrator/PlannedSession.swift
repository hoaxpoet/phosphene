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

// MARK: - SegmentTerminationReason

/// Why a `PlannedPresetSegment` terminates (V.7.6.2, ARACHNE_V8_DESIGN.md §3.2).
///
/// Computed by `DefaultSessionPlanner` and surfaced for inspection by the live
/// adapter, the plan-preview UI, and golden-session tests.
public enum SegmentTerminationReason: String, Sendable, Hashable, Codable, CaseIterable {
    /// Last segment of the track — runs to `track.plannedEndTime`.
    case trackEnded
    /// Aligned to a structural section boundary within the track.
    case sectionBoundary
    /// Capped by `PresetDescriptor.maxDuration(forSection:)` (§5).
    case maxDurationReached
    /// Preset emitted a `PresetSignaling.presetCompletionEvent`.
    case completionSignal
}

// MARK: - PlannedPresetSegment

/// One preset slot inside a `PlannedTrack` (V.7.6.2, ARACHNE_V8_DESIGN.md §3.2).
///
/// A track is now an ordered list of segments. A "single-segment" track behaves
/// identically to the pre-V.7.6.2 `PlannedTrack` — the track-level `preset` /
/// `presetScore` / `scoreBreakdown` / `incomingTransition` accessors below
/// transparently forward to `segments[0]`.
public struct PlannedPresetSegment: Sendable {
    /// The preset selected for this segment.
    public let preset: PresetDescriptor
    /// The combined score from `DefaultPresetScorer` (0–1).
    public let presetScore: Float
    /// Sub-score breakdown for full inspection.
    public let scoreBreakdown: PresetScoreBreakdown
    /// Session time (seconds from session start) when this segment begins.
    public let plannedStartTime: TimeInterval
    /// Session time when this segment ends.
    public let plannedEndTime: TimeInterval
    /// How to transition *into* this segment. Nil for the first segment of the
    /// first track in the session; non-nil for every other segment.
    public let incomingTransition: PlannedTransition?
    /// Why this segment ends.
    public let terminationReason: SegmentTerminationReason

    public init(
        preset: PresetDescriptor,
        presetScore: Float,
        scoreBreakdown: PresetScoreBreakdown,
        plannedStartTime: TimeInterval,
        plannedEndTime: TimeInterval,
        incomingTransition: PlannedTransition?,
        terminationReason: SegmentTerminationReason
    ) {
        self.preset = preset
        self.presetScore = presetScore
        self.scoreBreakdown = scoreBreakdown
        self.plannedStartTime = plannedStartTime
        self.plannedEndTime = plannedEndTime
        self.incomingTransition = incomingTransition
        self.terminationReason = terminationReason
    }
}

// MARK: - PlannedTrack

/// One entry in a `PlannedSession`: a track paired with one or more preset segments
/// (V.7.6.2 — was: single preset).
///
/// Backward-compat accessors (`preset`, `presetScore`, `scoreBreakdown`,
/// `incomingTransition`) forward to `segments[0]` so existing callers keep working.
/// Multi-segment-aware callers should iterate `segments` directly.
public struct PlannedTrack: Sendable {

    /// The track this entry is for.
    public let track: TrackIdentity
    /// The MIR profile used for scoring.
    public let trackProfile: TrackProfile
    /// Ordered preset segments covering this track. Always non-empty.
    public let segments: [PlannedPresetSegment]
    /// Session time (seconds from session start) when this track begins.
    public let plannedStartTime: TimeInterval
    /// Session time when this track ends (`plannedStartTime + track duration`).
    public let plannedEndTime: TimeInterval

    /// V.7.6.2 multi-segment init.
    public init(
        track: TrackIdentity,
        trackProfile: TrackProfile,
        segments: [PlannedPresetSegment],
        plannedStartTime: TimeInterval,
        plannedEndTime: TimeInterval
    ) {
        precondition(!segments.isEmpty, "PlannedTrack must have at least one segment")
        self.track = track
        self.trackProfile = trackProfile
        self.segments = segments
        self.plannedStartTime = plannedStartTime
        self.plannedEndTime = plannedEndTime
    }

    /// Backward-compat init: single-segment construction matches the pre-V.7.6.2 shape.
    /// Used by `LiveAdapter+Patching.swift` and any caller that has a single preset.
    public init(
        track: TrackIdentity,
        trackProfile: TrackProfile,
        preset: PresetDescriptor,
        presetScore: Float,
        scoreBreakdown: PresetScoreBreakdown,
        plannedStartTime: TimeInterval,
        plannedEndTime: TimeInterval,
        incomingTransition: PlannedTransition?
    ) {
        let segment = PlannedPresetSegment(
            preset: preset,
            presetScore: presetScore,
            scoreBreakdown: scoreBreakdown,
            plannedStartTime: plannedStartTime,
            plannedEndTime: plannedEndTime,
            incomingTransition: incomingTransition,
            terminationReason: .trackEnded
        )
        self.init(
            track: track,
            trackProfile: trackProfile,
            segments: [segment],
            plannedStartTime: plannedStartTime,
            plannedEndTime: plannedEndTime
        )
    }

    // MARK: - Backward-compat accessors (forward to segments[0])

    /// The first segment's preset. Equivalent to `segments[0].preset`.
    public var preset: PresetDescriptor { segments[0].preset }
    /// The first segment's score. Equivalent to `segments[0].presetScore`.
    public var presetScore: Float { segments[0].presetScore }
    /// The first segment's score breakdown.
    public var scoreBreakdown: PresetScoreBreakdown { segments[0].scoreBreakdown }
    /// The first segment's incoming transition.
    public var incomingTransition: PlannedTransition? { segments[0].incomingTransition }
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

    /// Resolve the canonical `TrackIdentity` for a streaming-metadata
    /// observation that only carries `title` + `artist`.
    ///
    /// Streaming sources (Apple Music / Spotify Now Playing AppleScript) do
    /// not deliver `duration` or catalog IDs. The plan was constructed from
    /// full identities (Spotify Web API or pre-fetched), so the cache key
    /// `SessionPreparer.store(_:for:)` used differs from any partial identity
    /// the audio path might construct. Searching the plan by title+artist and
    /// returning the planned identity gives downstream cache lookups the
    /// correct hash key.
    ///
    /// Returns `nil` when no track matches or when more than one matches
    /// (ambiguity — caller falls back to the partial identity rather than
    /// risk pinning the wrong cache entry). (BUG-006.2)
    public func canonicalIdentity(matchingTitle title: String, artist: String) -> TrackIdentity? {
        let matches = tracks.filter {
            $0.track.title == title && $0.track.artist == artist
        }
        guard matches.count == 1 else { return nil }
        return matches[0].track
    }

    /// Returns the `PlannedTrack` that is active at the given session time.
    ///
    /// A track is active when `sessionTime ∈ [plannedStartTime, plannedEndTime)`.
    /// Returns nil when `sessionTime` is past the end of the last track or before 0.
    public func track(at sessionTime: TimeInterval) -> PlannedTrack? {
        tracks.first {
            sessionTime >= $0.plannedStartTime && sessionTime < $0.plannedEndTime
        }
    }

    /// Returns the `PlannedPresetSegment` active at the given session time, or nil.
    ///
    /// Walks each `PlannedTrack`'s `segments` in order. A segment is active when
    /// `sessionTime ∈ [plannedStartTime, plannedEndTime)`.
    public func segment(at sessionTime: TimeInterval) -> PlannedPresetSegment? {
        for trackEntry in tracks {
            for seg in trackEntry.segments {
                if sessionTime >= seg.plannedStartTime && sessionTime < seg.plannedEndTime {
                    return seg
                }
            }
        }
        return nil
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
        // Walk every segment's incomingTransition (V.7.6.2 — was tracks-only).
        // Multi-segment tracks expose mid-track transitions here.
        for trackEntry in tracks {
            for seg in trackEntry.segments {
                if let transition = seg.incomingTransition,
                   abs(transition.scheduledAt - sessionTime) <= tolerance {
                    return transition
                }
            }
        }
        return nil
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
