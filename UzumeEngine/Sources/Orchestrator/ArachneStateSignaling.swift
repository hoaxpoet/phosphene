// ArachneStateSignaling — V.7.7C.2 PresetSignaling conformance for ArachneState
// (D-095).
//
// Per V.7.6.2 the orchestrator subscribes to
// `PresetSignaling.presetCompletionEvent` via the `as? PresetSignaling` cast
// in `VisualizerEngine+Presets.activePresetSignaling()`. Commit 1 of V.7.7C.2
// (`38d1bfab`) wired the subscription and waited for a conforming source;
// this file lights the wire by attaching the conformance to `ArachneState`.
//
// **Module placement note** (D-095). The V.7.7C.2 prompt names this file
// `ArachneState+Signaling.swift` under `Sources/Presets/Arachnid/`, but
// `PresetSignaling` lives in `Orchestrator` and `Presets` does not (and
// must not) depend on `Orchestrator` — that would create a circular module
// dependency since `Orchestrator` already depends on `Presets`. The only
// place both `ArachneState` (Presets) and `PresetSignaling` (Orchestrator)
// are visible without inverting that arrow is the `Orchestrator` module
// itself, which is where this conformance lives. The behavioural contract
// is identical to the prompt's stated form.
//
// The completion event fires exactly once when `BuildState.stage` transitions
// into `.stable` (handled in `advanceStablePhase` in `ArachneState.swift`).
// `BuildState.completionEmitted` guards against double-fire across ticks and
// is reset only by `ArachneState.reset()` on cycle restart.

import Combine
import Presets

extension ArachneState: PresetSignaling {

    /// Public access to the completion event; the orchestrator subscribes here.
    public var presetCompletionEvent: PassthroughSubject<Void, Never> {
        return _presetCompletionEvent
    }
}
