// DiagnosticHoldTests — Verifies the diagnostic-hold override suppression logic (DSP.3.1).
//
// The app-layer VisualizerEngine.applyLiveUpdate() suppresses LiveAdapter presetOverride
// events when diagnosticPresetLocked is true.  This test verifies the suppression logic
// at the LiveAdaptation struct level — independent of Metal and the full engine stack.

import Foundation
import Testing
@testable import Orchestrator
import Presets
import Session
import Shared

// MARK: - DiagnosticHoldTests

@Suite("DiagnosticHold — preset override suppression (DSP.3.1)")
struct DiagnosticHoldTests {

    // MARK: - Helpers

    /// Make a minimal PresetDescriptor for use as the override target.
    private func makeDescriptor(name: String) -> PresetDescriptor {
        let json = """
        {
            "name": "\(name)",
            "family":"geometric",
            "certified": true,
            "complexity_cost": {"tier1": 1.0, "tier2": 1.0}
        }
        """
        // swiftlint:disable:next force_try
        return try! JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
    }

    /// Simulate the VisualizerEngine.applyLiveUpdate suppression filter.
    /// Returns the effective adaptation after applying the diagnostic-hold guard.
    private func applyDiagnosticHoldFilter(
        adaptation: LiveAdaptation,
        diagnosticPresetLocked: Bool
    ) -> LiveAdaptation {
        guard diagnosticPresetLocked, adaptation.presetOverride != nil else {
            return adaptation
        }
        return LiveAdaptation(
            updatedTransition: adaptation.updatedTransition,
            presetOverride: nil,
            events: adaptation.events.filter { $0.kind != .presetOverrideTriggered }
        )
    }

    // MARK: - Tests

    @Test("presetOverride is nil in effective adaptation when diagnosticPresetLocked is true")
    func diagnosticHold_suppressesPresetOverride() {
        let overrideDesc = makeDescriptor(name: "Nebula")
        let override = LiveAdaptation.PresetOverride(
            preset: overrideDesc,
            score: 0.8,
            reason: "mood divergence"
        )
        let adaptation = LiveAdaptation(
            presetOverride: override,
            events: [AdaptationEvent(kind: .presetOverrideTriggered, trackIndex: 0, message: "test")]
        )

        let effective = applyDiagnosticHoldFilter(adaptation: adaptation, diagnosticPresetLocked: true)

        #expect(effective.presetOverride == nil,
                "presetOverride must be nil when diagnosticPresetLocked is true")
        #expect(!effective.events.contains { $0.kind == .presetOverrideTriggered },
                "presetOverrideTriggered event must be stripped when hold is active")
    }

    @Test("presetOverride passes through when diagnosticPresetLocked is false")
    func diagnosticHold_allowsPresetOverrideWhenUnlocked() {
        let overrideDesc = makeDescriptor(name: "Nebula")
        let override = LiveAdaptation.PresetOverride(
            preset: overrideDesc,
            score: 0.8,
            reason: "mood divergence"
        )
        let adaptation = LiveAdaptation(
            presetOverride: override,
            events: [AdaptationEvent(kind: .presetOverrideTriggered, trackIndex: 0, message: "test")]
        )

        let effective = applyDiagnosticHoldFilter(adaptation: adaptation, diagnosticPresetLocked: false)

        #expect(effective.presetOverride != nil,
                "presetOverride must pass through when diagnosticPresetLocked is false")
    }

    @Test("updatedTransition still passes through when diagnosticPresetLocked is true")
    func diagnosticHold_allowsBoundaryReschedule() {
        let plan = PlannedTransition(
            fromPreset: makeDescriptor(name: "Plasma"),
            toPreset: makeDescriptor(name: "Nebula"),
            style: .crossfade,
            duration: 2.0,
            scheduledAt: 60.0,
            reason: "structural boundary"
        )
        let overrideDesc = makeDescriptor(name: "Nebula")
        let override = LiveAdaptation.PresetOverride(
            preset: overrideDesc,
            score: 0.8,
            reason: "mood divergence"
        )
        let adaptation = LiveAdaptation(
            updatedTransition: plan,
            presetOverride: override,
            events: [
                AdaptationEvent(kind: .boundaryRescheduled, trackIndex: 0, message: "reschedule"),
                AdaptationEvent(kind: .presetOverrideTriggered, trackIndex: 0, message: "override")
            ]
        )

        let effective = applyDiagnosticHoldFilter(adaptation: adaptation, diagnosticPresetLocked: true)

        #expect(effective.updatedTransition != nil,
                "updatedTransition (boundary reschedule) must survive diagnostic hold")
        #expect(effective.presetOverride == nil,
                "presetOverride must be stripped by diagnostic hold")
    }
}
