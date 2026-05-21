// PresetSignaling — Channel for presets to request immediate transition (V.7.6.2).
//
// A preset that has a natural completion point (Arachne's 60-second build cycle is
// the canonical case) emits on `presetCompletionEvent`. The orchestrator subscribes
// per active preset; on event, it advances to the next planned segment if the
// `minSegmentDuration` floor has elapsed, otherwise queues the event until the
// floor is reached.
//
// V.7.6.2 wires the protocol and subscription path. ArachneState conforms via
// `Sources/Orchestrator/ArachneStateSignaling.swift` (cross-module placement
// per D-095 to avoid a Presets→Orchestrator dependency cycle). Arachne emits
// from `advanceStablePhase` in `ArachneState.swift:977` once the build cycle
// reaches `.stable` (shipped V.7.7C.2, 2026-05-09). The orchestrator-side
// subscription is wired end-to-end at `VisualizerEngine+Presets.swift:497-573`
// (BUG-011 round 8, 2026-05-12). Most presets do NOT emit; only those with a
// finite construction or build sequence opt in.

import Combine
import Foundation

// MARK: - PresetSignaling

/// Conformance signals that the preset can request immediate transition to the
/// next planned segment.
///
/// Most presets are cyclical and never emit; only those with a finite construction
/// or build sequence (Arachne) opt in.
public protocol PresetSignaling: AnyObject {
    /// Fires once when the preset reaches its natural completion point.
    ///
    /// The orchestrator may honour or defer the event based on the
    /// `minSegmentDuration` floor — preset authors should treat the event as a
    /// *request*, not a guaranteed transition.
    var presetCompletionEvent: PassthroughSubject<Void, Never> { get }
}

// MARK: - Tunables

/// Lower bound on segment time-on-screen before a `presetCompletionEvent` is honoured.
///
/// Floor exists so a preset that emits its completion signal almost immediately
/// (tested or buggy authoring) cannot starve the planner. Default 5 s per V.7.6.2 §3.4.
public enum PresetSignalingDefaults {
    public static let minSegmentDuration: TimeInterval = 5.0
}
