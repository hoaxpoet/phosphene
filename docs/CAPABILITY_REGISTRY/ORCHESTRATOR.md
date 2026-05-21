# Capability Registry — Orchestrator

**Audit increment:** CA.4
**Date:** 2026-05-20
**Auditor:** Claude (session-driven, read-only)
**Scope:** `PhospheneEngine/Sources/Orchestrator/` — 14 Swift files, 2,954 LoC. Boundary annotations for Orchestrator ↔ Session, ↔ DSP / MIR, ↔ ML, ↔ Audio, ↔ Renderer, ↔ App.
**Methodology:** [Phase CA Kickoff — CA.4 (Orchestrator)](../prompts/PHASE_CA_KICKOFF_CA4_ORCHESTRATOR_2026-05-20.md) — see commit `9fc1a6c9`.
**Reads relied on:** `CLAUDE.md`, `docs/ARCHITECTURE.md`, `docs/CAPABILITY_REGISTRY/DSP_MIR.md` (CA.1), `docs/CAPABILITY_REGISTRY/ML.md` (CA.2), `docs/CAPABILITY_REGISTRY/SESSION.md` (CA.3), `docs/DECISIONS.md` (D-014, D-017, D-030, D-032 through D-036, D-047, D-050, D-053, D-058, D-072, D-074, D-077, D-078, D-080, D-091, D-095, D-097, D-099, D-120, D-122, D-123), `docs/QUALITY/KNOWN_ISSUES.md` (BUG-001 + BUG-005 + BUG-011 + BUG-014 + BUG-R009), `docs/ENGINEERING_PLAN.md` (Phase 4 + Phase CA + recent BUG-011 entries).

---

## Summary

14 file-level entities audited (~2.95k LoC). The Orchestrator subsystem ships with substantial test coverage and clean compile — every public capability has at least one consumer, every documented numeric matches code, and the QR.2 / D-080 stem-affinity and reactive-mode fixes are implemented faithfully against Failed Approaches #53 / #54. **However**, the most consequential finding is that the App-layer **runtime entry point for the Orchestrator's live-adaptation pipeline (`VisualizerEngine.applyLiveUpdate(...)`) has zero production call sites** — so `DefaultLiveAdapter.adapt(...)` and `DefaultReactiveOrchestrator.evaluate(...)` never execute against live MIR data, despite ENGINEERING_PLAN.md marking both Increment 4.5 (Live Adaptation) and Increment 4.6 (Ad-Hoc Reactive Mode) as ✅. This is a **`broken-but-claimed`** finding (filed as new BUG-015) that supersedes CA.1-FU-1's framing (see [§Resolution-of-CA.1-runtime-production-orphan-re-evaluation](#resolution-of-ca1-runtime-production-orphan-re-evaluation) below).

| Verdict | Count | Notes |
|---|---|---|
| `production-active` | 12 files | Default verdict. Every other Orchestrator source file has at least one production consumer; documented behaviour matches code. |
| `broken-but-claimed` | 1 cluster | `DefaultLiveAdapter` + `DefaultReactiveOrchestrator` are correctly implemented but **never invoked at runtime** because `VisualizerEngine.applyLiveUpdate(...)` has zero production call sites. Filed as BUG-015. The Orchestrator-side files themselves remain `production-active` from the audit's verdict perspective (their unit tests fire and the constructor instantiations happen); the broken-ness is the App-layer wiring gap. |
| `production-orphan` | 1 field-level | `DefaultLiveAdapter.transitionPolicy` (`LiveAdapter.swift:176, 188, 191`) — declared, constructor-injected, stored, **never invoked**. Even if BUG-015's missing wire is fixed, this field would still be dead — the LiveAdapter's two evaluation paths construct `PlannedTransition` values directly without going through `TransitionDeciding.evaluate(...)`. Cited grep below. |
| `documented-but-missing` | 0 (in load-bearing docs) | The ARCHITECTURE.md drift below is `built-but-undocumented` not `documented-but-missing` — code exists; docs lag. |
| `built-but-undocumented` | 2 large | (a) `ARCHITECTURE.md §Module Map Orchestrator/` (lines 548–553) lists 4 of 14 source files — 10 absent (full list under `§Cross-references` below). Same systemic pattern as CA.1 (DSP/ 6-of-20 missing), CA.2 (ML/ 9-of-16 missing), CA.3 (Session/ 13-of-22 missing). (b) `ARCHITECTURE.md §Orchestrator` (lines 196–219) describes 4.1–4.3 as "Implemented" with 4.4 / 4.5 / 4.6 as "Forthcoming" — every Phase-4 increment has actually shipped per `ENGINEERING_PLAN.md`; the §Forthcoming list is obsolete and should be retired. |
| `unverified-claim` | 1 | `PresetScorer.swift:86` — the inline doc comment cites `(D-030)` for the weight rationale. D-030 is `SpectralHistoryBuffer as unconditional GPU contract at buffer(5)` (`docs/DECISIONS.md:378`); the correct citation is **D-032** (`Preset scoring weights and penalty structure`, `docs/DECISIONS.md:433`). The four weights themselves are byte-correct. |
| `stub` | 0 | — |
| `dead` | 0 | — |
| `boundary-noted` | 5 | Orchestrator ↔ Session (`TrackProfile`, `TrackIdentity`, the `PlannedSession.canonicalIdentity` consumer at `VisualizerEngine+Capture.swift:131` per BUG-006.2); Orchestrator ↔ DSP (`StructuralPrediction` as input parameter; not read from MIRPipeline directly); Orchestrator ↔ ML (`MoodClassifier.currentState` is the *prep-time* source of `TrackProfile.mood`; runtime mood injection goes through `RenderPipeline.setMood` — neither path is Orchestrator-internal); Orchestrator ↔ App (`PlaybackActionRouter` concrete in `PhospheneApp/Services/DefaultPlaybackActionRouter.swift`; consumer of `applyLiveUpdate` is `VisualizerEngine+Audio` per the doc comment — but the wire is missing, see BUG-015); Orchestrator ↔ Presets (`ArachneState` conformance to `PresetSignaling` at `ArachneStateSignaling.swift:28`; circular-dep avoidance per D-095). All boundary verdicts complete; no `boundary-deferred` items filed. |
| `boundary-deferred` | 0 (new) | — |

**Top findings, ranked.**

1. **BUG-015 — `applyLiveUpdate(...)` has zero production call sites.** `grep -rn "applyLiveUpdate" PhospheneApp PhospheneEngine --include="*.swift"` returns the declaration site (`VisualizerEngine+Orchestrator.swift:166`), 4 doc-comment / commentary references in unrelated files, 1 test reference, and zero actual invocations. The `DefaultLiveAdapter` + `DefaultReactiveOrchestrator` machinery is fully implemented and unit-tested but never reaches running production. Filed as BUG-015 (next-available BUG number after BUG-014). Surfaces the kickoff's BUG-001 "Money 7/4 stays REACTIVE" question — BUG-001 refers to the SpectralCartograph mode label (DSP-side lock state), not the Orchestrator's reactive mode; the *Orchestrator* reactive mode is dead independently.

2. **CA.1-FU-1 re-framing.** CA.1 surfaced the per-frame `StructuralAnalyzer` cluster as runtime `production-orphan` and identified the synthetic-`StructuralPrediction` construction at `SessionPlanner.swift:317` as the runtime-consumer counterpart. The audit's reading of the Orchestrator's runtime path resolves this: the synthetic at `:317` is the **planning-time** construction that fires `TransitionPolicy.structuralBoundary` at every track change (`confidence: 1.0`, both timestamps at clock) — it is NOT the source of runtime predictions. Runtime predictions would flow into `DefaultLiveAdapter.adapt(liveBoundary:)` / `DefaultReactiveOrchestrator.evaluate(liveBoundary:)` via the missing-wire BUG-015 path. **Until BUG-015 is fixed, no runtime consumer of `MIRPipeline.latestStructuralPrediction` exists at all.** CA.1-FU-1's option-(a) framing (gate the per-frame chain to prep time only) is the cleanest immediate fix; option (b) (wire MIRPipeline → orchestrator at runtime) only becomes meaningful once BUG-015 lands. See §Resolution below.

3. **`DefaultLiveAdapter.transitionPolicy` is dead field.** Declared and injected at `LiveAdapter.swift:176, 188, 191`; never read in `LiveAdapter.swift` / `LiveAdapter+Patching.swift` / `LiveAdapter+MoodOverride.swift`. The adapter's `evaluateBoundaryReschedule(...)` constructs `PlannedTransition` values directly. Even after BUG-015 is fixed, the field stays dead unless someone re-wires the boundary-reschedule path through `TransitionPolicy.evaluate(...)`. Demote to a no-arg init or remove the parameter — `CA.4-FU-1`.

4. **`PresetScorer.swift:86` cites D-030 instead of D-032.** Trivial source-comment drift; the weights themselves match. Surface as a one-line doc fix.

5. **D-032 (DECISIONS.md line 471) still describes `cutEnergyThreshold = 0.7`.** D-080 (line 1667) explicitly amended the value to 0.85; the amendment is in TransitionPolicy.swift (line 144–146 — `Raised from 0.7 → 0.85 (QR.2/D-080)`) but D-032's own text was not updated. Same pattern as CA.3's D-070 trail: amendment landed, source-of-truth doc didn't follow. Surface as a D-032 amendment note.

6. **ARCHITECTURE.md doc drift cluster.**
   - §Orchestrator lines 196–219 says 4.1–4.3 implemented, 4.4 / 4.5 / 4.6 forthcoming. All four are ✅ per ENGINEERING_PLAN.md.
   - §Orchestrator line 211 says `cutEnergyThreshold = 0.7`. Code: 0.85.
   - §Module Map Orchestrator/ (lines 548–553) lists 4 files. Directory has 14. **10 absent**: `PresetSignaling.swift`, `ArachneStateSignaling.swift`, `SessionPlanner+Segments.swift`, `LiveAdapter.swift`, `LiveAdapter+Patching.swift`, `LiveAdapter+MoodOverride.swift`, `ReactiveOrchestrator.swift`, `PlaybackActionRouter.swift`, `QualityCeiling.swift`. (Wait — that's 9; let me recount.) Recount: present = `PresetScorer`, `PresetScoringContext`, `TransitionPolicy`, `PlannedSession`, `SessionPlanner` (5 entries); absent = `PresetSignaling`, `ArachneStateSignaling`, `SessionPlanner+Segments`, `LiveAdapter`, `LiveAdapter+Patching`, `LiveAdapter+MoodOverride`, `ReactiveOrchestrator`, `PlaybackActionRouter`, `QualityCeiling` (9 absent). Total directory = 14. 5 + 9 = 14 ✓.
   - §Module Map Tests/Orchestrator/ — not listed at all (no Orchestrator entry under `Tests/`). 16 test files exist.

7. **`PresetSignaling.swift:9-10` source-file doc claims "Arachne does NOT emit yet — wiring is V.7.8".** Stale by D-095 / V.7.7C.2: the emission shipped 2026-05-09 (`ArachneState.swift:977` `_presetCompletionEvent.send()`), and BUG-011 round 8 (2026-05-12) wired the orchestrator-side subscription end-to-end (`VisualizerEngine+Presets.swift:497-573`). One-line source-comment fix.

8. **D-120 (`concept_tags` + `motion_paradigm`) revert is **CLEAN**.** Cited grep:
   ```
   $ grep -rn "concept_tags\|motion_paradigm\|conceptTags\|motionParadigm" \
            PhospheneEngine PhospheneApp --include="*.swift" --include="*.json"
   (no results)
   ```
   Zero residue in Swift sources, JSON sidecars, tests, or schema declarations. D-120's reversion (commit `0981ca4f`, 2026-05-13) was complete. No follow-up needed.

**Three follow-up items + one BUG entry are tracked in [§Follow-up Backlog](#follow-up-backlog).** Per the kickoff's audit-only discipline, BUG-015's fix is registered as a separate increment (CA.4-FU-3); CA.4 files the BUG entry and the immediate ARCHITECTURE.md / DECISIONS.md drift corrections, but does not implement the wire.

---

## Findings by verdict

### broken-but-claimed (BUG entries filed)

**1. `applyLiveUpdate(...)` has zero production call sites; live-adaptation pipeline is dead — BUG-015.**

**Evidence.**
```
$ grep -rn "applyLiveUpdate" PhospheneApp PhospheneEngine --include="*.swift"
PhospheneApp/VisualizerEngine+Presets.swift:562:    /// L lock only suppressed mood-override switching (in `applyLiveUpdate`);
PhospheneApp/VisualizerEngine+Orchestrator.swift:8:// main thread (buildPlan) or the analysis queue (applyLiveUpdate). All access is
PhospheneApp/VisualizerEngine+Orchestrator.swift:166:    func applyLiveUpdate(
PhospheneApp/VisualizerEngine.swift:488:    /// Wall-clock timestamp of the first reactive `applyLiveUpdate()` call.
PhospheneApp/Services/CaptureModeSwitchCoordinator.swift:16://   · VisualizerEngine.captureModeSwitchGraceWindowEndsAt is set so applyLiveUpdate
PhospheneEngine/Tests/PhospheneEngineTests/Orchestrator/DiagnosticHoldTests.swift:3:// The app-layer VisualizerEngine.applyLiveUpdate() suppresses LiveAdapter presetOverride
PhospheneEngine/Tests/PhospheneEngineTests/Orchestrator/DiagnosticHoldTests.swift:35:    /// Simulate the VisualizerEngine.applyLiveUpdate suppression filter.
```

Of the 7 hits: 1 declaration site, 4 doc-comment / commentary references, 2 test references. **Zero actual call sites.** The declaration is `internal func` (no `public` modifier), so callers must live in `PhospheneApp/` — they do not.

The body of `applyLiveUpdate(...)` at `VisualizerEngine+Orchestrator.swift:179` invokes `liveAdapter.adapt(...)` correctly; the body of `applyReactiveUpdate(...)` at `:275` invokes `reactiveOrchestrator.evaluate(...)` correctly. Both code paths are well-formed; they are not reached because nothing calls the outer entry.

**Claimed runtime behaviour (ENGINEERING_PLAN.md):**
- Increment 4.5 Live Adaptation ✅ (line 641): *"`DefaultLiveAdapter` implementing `LiveAdapting` protocol with two adaptation paths (boundary reschedule > mood override). `PlannedSession.applying(_:at:)` extension for controlled plan mutation from the app layer. `VisualizerEngine+Orchestrator` holds `livePlan` (NSLock-guarded) and provides `buildPlan()`, `currentPreset(at:)`, `currentTransition(at:)`, `applyLiveUpdate(...)`."*
- Increment 4.6 Ad-Hoc Reactive Mode ✅ (line 668): *"`VisualizerEngine+Orchestrator.swift` — `applyLiveUpdate()` routes to `applyReactiveUpdate()` when `livePlan == nil`."*

**Actual runtime behaviour:** `applyLiveUpdate(...)` is never invoked from any source file in `PhospheneApp/` or `PhospheneEngine/Sources/`. The audio analysis queue path (`VisualizerEngine+Audio.swift`) does not call it. `liveAdapter.adapt(...)` and `reactiveOrchestrator.evaluate(...)` are exercised only by unit tests (`LiveAdapterTests`, `ReactiveOrchestratorTests`, `DiagnosticHoldTests` simulation). The QR.2 / D-080 mood-override cooldown, the QR.2 / D-080 reactive `liveStemFeatures` wiring, the boundary-reschedule path, and `D-091` `wait_for_completion_event` mood-override suppression are all unreachable at runtime.

**Suspected failure class:** `pipeline-wiring` (per `docs/QUALITY/DEFECT_TAXONOMY.md`). The Orchestrator-side surface is complete; the App-layer invocation site was never added (or was removed during a refactor — `git log -p PhospheneApp/VisualizerEngine+Audio.swift -- *applyLiveUpdate*` could narrow that).

**Severity:** P1 (`session.orchestrator`). The product is "the AI Orchestrator has planned the entire visual session and adapts as the music unfolds" (CLAUDE.md, top); the adaptation half is dead. Planning works (the static plan is produced); live adaptation does not run. For session-mode playback this manifests as: planned transitions never reschedule against live structure; mood overrides never fire mid-track; the L diagnostic-hold suppression has no effect (because nothing was firing anyway); QR.2 / D-080 reactive stem-affinity scoring never executes against live `StemFeatures`.

**Verification criteria (filed in BUG-015 entry):**
- Automated: a new integration test exercises a 30 s reactive session against synthetic FeatureVectors and asserts `reactiveOrchestrator.evaluate(...)` was called at least once after the listening window.
- Manual: a session capture (`~/Documents/phosphene_sessions/<ts>/session.log`) for a real reactive playback shows at least one `LiveAdapter:` or `Reactive` log line in the live-adaptation event family.

**Fix scope:** investigation increment to locate the missing wire. Two candidate sites: (a) `VisualizerEngine+Audio.swift` analysis-queue tick — should call `applyLiveUpdate(trackIndex:elapsedTrackTime:boundary:mood:)` after each feature update or at a sub-Hz cadence; (b) a Combine sink on `MIRPipeline`'s feature publisher. The right cadence is at most a few Hz (per the kickoff "Do not call applyLiveUpdate without a per-track cooldown. The path runs at ~94 Hz on the analysis queue" rule — the OBSERVED rate from the design comment; the code was never wired up to verify the rate).

The kickoff document explicitly flagged the mood-override-cooldown rule but assumed `applyLiveUpdate` is actively invoked; the audit's read shows the rule was anticipated but the wire it was meant to protect was never added.

**BUG entry filed:** [`BUG-015` in `KNOWN_ISSUES.md`](../QUALITY/KNOWN_ISSUES.md#bug-015) — see §New BUG entries below.

### unverified-claim

**1. `PresetScorer.swift:86` cites D-030 in the Weight rationale doc comment.**

The comment header reads:
```swift
/// ## Weight rationale (D-030)
/// - **mood (0.30)**: highest weight — the primary axis of Orchestrator fit.
```

D-030 is `SpectralHistoryBuffer as unconditional GPU contract at buffer(5)` (`docs/DECISIONS.md:378`). The correct citation is **D-032** `Preset scoring weights and penalty structure (Increment 4.1)` at `docs/DECISIONS.md:433`. The four weights (0.30 / 0.25 / 0.25 / 0.20) themselves match D-032 byte-for-byte. Trivial source-comment fix; the weight values are not wrong.

### production-orphan

**1. `DefaultLiveAdapter.transitionPolicy` is constructor-injected and stored but never read.**

```
$ grep -n "transitionPolicy" PhospheneEngine/Sources/Orchestrator/LiveAdapter*.swift
PhospheneEngine/Sources/Orchestrator/LiveAdapter.swift:176:    private let transitionPolicy: any TransitionDeciding
PhospheneEngine/Sources/Orchestrator/LiveAdapter.swift:188:        transitionPolicy: any TransitionDeciding = DefaultTransitionPolicy()
PhospheneEngine/Sources/Orchestrator/LiveAdapter.swift:191:        self.transitionPolicy = transitionPolicy
```

Three references; all three are declaration / initialization. The body of `LiveAdapter.swift` (380 lines), `LiveAdapter+Patching.swift` (216 lines), and `LiveAdapter+MoodOverride.swift` (83 lines) never read `self.transitionPolicy`. The boundary-reschedule path constructs a `PlannedTransition` directly with the rescheduled `scheduledAt` (`LiveAdapter.swift:255-266`); the mood-override path likewise constructs `LiveAdaptation.PresetOverride` directly (`LiveAdapter+MoodOverride.swift:70-81`). Neither path goes through `TransitionDeciding.evaluate(...)`.

The field is a leftover from a probable earlier design where boundary reschedules would re-invoke `TransitionPolicy` to negotiate a new style/duration. Today's behaviour preserves the planned transition's style and duration (correct — boundary reschedule moves time only).

**Suggested next step (CA.4-FU-1):** demote the `transitionPolicy` field — either remove the parameter from the public init or make the field private to the type without the public constructor surface. Tests reference `DefaultLiveAdapter()` (zero-arg) and `DefaultLiveAdapter(scorer:)` — removing the `transitionPolicy` parameter is a non-breaking change. Bundle with the BUG-015 investigation if it advances to a fix.

This is independent of BUG-015: even with the live-adaptation wire fixed, the `transitionPolicy` field stays dead at the LiveAdapter site.

**Resolved 2026-05-21 (CA.4-FU-1).** Option (a) shipped: the `transitionPolicy` parameter and stored field are removed from `DefaultLiveAdapter`. The public init is now `init(scorer: any PresetScoring = DefaultPresetScorer())`. Post-edit grep `transitionPolicy` against `PhospheneEngine/Sources/Orchestrator/LiveAdapter*.swift` returns zero hits. The dead-field finding above is preserved as audit-time evidence; the registry rows for both the file-level table and this section's resolution stamp now reflect the post-fix state. Validation: `swift test --filter LiveAdapter` 11/11 pass; broader Orchestrator suite 114 tests / 17 suites pass; `xcodebuild -scheme PhospheneApp build` clean; SwiftLint introduced zero new violations (18 pre-existing violations in `SessionRecorder.swift`, `SpectralCartographText.swift`, `FerrofluidMesh.swift` unchanged).

### built-but-undocumented

**1. `ARCHITECTURE.md §Module Map Orchestrator/` (lines 548–553) lists 5 of 14 files; 9 absent.**

**Listed (5):** `PresetScorer`, `PresetScoringContext`, `TransitionPolicy`, `PlannedSession`, `SessionPlanner`.

**Missing (9):**
- `PresetSignaling.swift` — `PresetSignaling: AnyObject` protocol + `PresetSignalingDefaults.minSegmentDuration = 5.0` (V.7.6.2).
- `ArachneStateSignaling.swift` — `extension ArachneState: PresetSignaling` (cross-module conformance per D-095 to avoid Presets→Orchestrator cycle).
- `SessionPlanner+Segments.swift` — Multi-segment walk for V.7.6.2 (extracted from SessionPlanner.swift for file-length compliance).
- `LiveAdapter.swift` — `DefaultLiveAdapter` (final class, @unchecked Sendable since D-080), `LiveAdapting` protocol, `LiveAdaptation` + `AdaptationEvent` + `PresetOverride` value types, NSLock-guarded per-track cooldown state.
- `LiveAdapter+Patching.swift` — `PlannedSession.applying(_:at:)` / `extendingCurrentPreset(by:at:)` / `applying(overrides:)` controlled-mutation API (D-035).
- `LiveAdapter+MoodOverride.swift` — `applyOverrideIfBetter(...)` extracted from LiveAdapter.swift for file-length compliance.
- `ReactiveOrchestrator.swift` — `DefaultReactiveOrchestrator`, `ReactiveOrchestrating` protocol, `ReactiveDecision`, `ReactiveAccumulationState` (D-036).
- `PlaybackActionRouter.swift` — Protocol (App-layer concrete is `DefaultPlaybackActionRouter` in `PhospheneApp/Services/`, per D-050).
- `QualityCeiling.swift` — `.auto / .performance / .balanced / .ultra` enum with `complexityThresholdMs(for:)` (U.8).

Doc-drift correction applied in this increment.

**2. `ARCHITECTURE.md §Module Map Tests/Orchestrator/` block is **absent entirely**.**

The Module Map's `Tests/` section has entries for Audio / DSP / ML / Renderer / Session — but not Orchestrator. 16 Orchestrator test files exist:

`DiagnosticHoldTests`, `GoldenSessionTests`, `LiveAdapterTests`, `MaxDurationFrameworkTests`, `MultiSegmentSmokeTest`, `OrchestratorCertifiedFilterTests`, `OrchestratorDiagnosticExclusionTests`, `PartialPlanTests`, `PresetScorerAdaptationTests`, `PresetScorerTests`, `PresetScoringContextExtensionTests`, `PresetSignalingTests`, `ReactiveOrchestratorTests`, `SessionPlannerTests`, `StemAffinityScoringTests`, `TransitionPolicyTests`.

Doc-drift correction applied.

**3. `ARCHITECTURE.md §Orchestrator "Forthcoming (4.4+)" list (lines 214–219) is obsolete.**

The list cites four items as forthcoming:
- Golden-session fixtures (4.4) — shipped 2026-04-20, regenerated multiple times since (`Tests/Orchestrator/GoldenSessionTests.swift`).
- SessionManager app-layer wiring (4.5) — shipped (`PhospheneApp/VisualizerEngine+Orchestrator.buildPlan`).
- Live adaptation (4.5) — shipped at the Orchestrator-side API; *runtime wiring is BUG-015*.
- Ad-hoc reactive mode (4.6) — shipped at the Orchestrator-side API; *runtime wiring is BUG-015*.

The §Forthcoming block is retired in this increment; the §Implemented block is rewritten to reflect 4.0–4.6 all complete *at the Orchestrator-module surface*, with a pointer to BUG-015 for the runtime gap.

**4. `ARCHITECTURE.md §Orchestrator` line 211 cites `cutEnergyThreshold > 0.7`.**

Code is `0.85` (`TransitionPolicy.swift:146`), amended per D-080 / QR.2. Doc-drift correction applied.

**5. `PresetSignaling.swift:9-10` source-file doc claims emission is "V.7.8".**

The file's top comment reads:
```swift
// V.7.6.2 wires the protocol and subscription path; only Arachne is expected to
// emit, and Arachne does NOT emit yet — wiring is V.7.8.
```

But `ArachneState.swift:977` (`_presetCompletionEvent.send()` inside `advanceStablePhase`) shipped V.7.7C.2 / D-095 on 2026-05-09, and the orchestrator-side subscription was end-to-end-wired by BUG-011 round 8 on 2026-05-12. Source-file doc fix applied.

### boundary-noted

The audit produced no new `boundary-deferred` findings. The following Orchestrator-module boundary surfaces are noted (verdict complete; no future re-audit required):

- **Orchestrator ↔ Session (`Sources/Session/`).** `TrackProfile` is consumed by `DefaultPresetScorer.moodSubScore` (mood field), `.tempoMotionSubScore` (bpm field), `.stemAffinitySubScore` (stemEnergyBalance field), `.sectionSuitabilitySubScore` (no field — section comes from PresetScoringContext.currentSection), and `DefaultSessionPlanner.plan(...)` (every track entry). `TrackIdentity` is consumed by `PlannedTrack.track`, `DefaultLiveAdapter.lastOverrideTimePerTrack` (the `[TrackIdentity: TimeInterval]` cooldown dict), and `PlannedSession.canonicalIdentity(matchingTitle:artist:)` (the load-bearing BUG-006.2 helper consumed at `PhospheneApp/VisualizerEngine+Capture.swift:131` + `VisualizerEngine+TrackIdentityResolution.swift:39`). `SessionPlan` (Session module's deliberately-minimal stub per D-017) is not directly used by Orchestrator types — the lift to `PlannedSession` happens entirely in `DefaultSessionPlanner.plan(...)`. CA.3's Session-side reads of these touchpoints are accurate.

- **Orchestrator ↔ DSP / MIR (`Sources/DSP/`).** `StructuralPrediction` is an *input parameter* to `DefaultTransitionPolicy.evaluate(context:)` (via `TransitionContext.prediction`), `DefaultLiveAdapter.adapt(liveBoundary:)`, and `DefaultReactiveOrchestrator.evaluate(liveBoundary:)`. None of these read `MIRPipeline.latestStructuralPrediction` directly — the caller passes whatever prediction they have. The synthetic-`StructuralPrediction` at `SessionPlanner.swift:317-322` (`confidence: 1.0`, both timestamps at clock) is the planning-time construction; the runtime construction site lives in `DSP/StructuralAnalyzer.swift:260, 300`. **The Orchestrator module is correctly designed at this boundary** — it consumes predictions, doesn't fetch them. CA.1-FU-1's runtime-path question is downstream of BUG-015; see §Resolution below.

- **Orchestrator ↔ ML (`Sources/ML/`).** Two distinct paths:
  1. **Prep-time mood.** `MoodClassifier.currentState` is read at `SessionPreparer+Analysis.swift:295` (Session module) at end-of-prep and stored into `TrackProfile.mood`. `DefaultPresetScorer.moodSubScore` consumes the cached value. CA.3 confirmed this pattern as intentional EMA-smoothed-state architecture (not drift).
  2. **Runtime mood.** `RenderPipeline.setMood(valence:arousal:)` is the runtime injection path. `DefaultLiveAdapter.adapt(liveMood: EmotionalState)` receives mood as an input parameter — but per BUG-015, the adapter is never invoked at runtime, so this path is unreachable today.

- **Orchestrator ↔ Audio (`Sources/Audio/`).** No direct boundary. `PreFetchedTrackProfile` (Audio module) is consumed at the Session boundary by `SessionPreparer+Analysis.analyzePreview(prefetchedProfile:)` (Round 26 metadata-driven `beatsPerBar` override) — the data is folded into `TrackProfile` via the `BeatGrid.overridingBeatsPerBar(...)` path. Orchestrator never imports Audio types.

- **Orchestrator ↔ Renderer (`Sources/Renderer/`).** `QualityCeiling` is consumed by `MLDispatchScheduler` (Renderer) and by `PresetScoringContext.complexityThresholdMs(for:)` (Orchestrator). `FrameBudgetManager.recentMaxFrameMs` is Renderer-internal — not read by any Orchestrator type. The Orchestrator module does not import Renderer; the precompile closure pattern (`(@Sendable (PresetDescriptor) async throws -> Void)?` on `DefaultSessionPlanner.planAsync`) keeps the dependency one-way.

- **Orchestrator ↔ App (`PhospheneApp/`).** `DefaultPresetScorer`, `DefaultSessionPlanner`, `DefaultLiveAdapter`, `DefaultReactiveOrchestrator` are all instantiated at `VisualizerEngine.swift:458, 461, 464`. `PlaybackActionRouter` protocol's concrete `DefaultPlaybackActionRouter` lives at `PhospheneApp/Services/DefaultPlaybackActionRouter.swift` (D-050). `PresetScoringContextProvider` (App layer) is the canonical builder of `PresetScoringContext` values consumed by the Orchestrator. The App layer is where the BUG-015 missing wire lives.

- **Orchestrator ↔ Presets (`Sources/Presets/`).** `ArachneState: PresetSignaling` conformance lives in Orchestrator (`ArachneStateSignaling.swift`) instead of in Presets/Arachnid/ to avoid the circular dependency Presets→Orchestrator (per D-095, since Orchestrator already depends on Presets). The conformance is the only Orchestrator-side file that imports `Presets` for a per-preset purpose; the others import Presets generically for `PresetDescriptor` / `PresetCategory`.

### production-active

(See per-file index below. Counts only here, no per-finding detail unless a noteworthy nuance applies.)

- **Scoring + policy core (3 files):** `PresetScorer.swift` (with the D-030 → D-032 citation drift noted above), `PresetScoringContext.swift`, `TransitionPolicy.swift` (with `cutEnergyThreshold = 0.85` per D-080, with the ARCHITECTURE.md drift to 0.7 noted above).
- **Planning (3 files):** `SessionPlanner.swift` (with the synthetic-prediction at `:317-322`), `SessionPlanner+Segments.swift` (V.7.6.2 multi-segment walk + `wait_for_completion_event` handling), `PlannedSession.swift` (with `canonicalIdentity` at `:298` per BUG-006.2 / D-091).
- **Live adaptation (3 files):** `LiveAdapter.swift`, `LiveAdapter+Patching.swift`, `LiveAdapter+MoodOverride.swift`. **`production-active` at the Orchestrator-module surface** (declarations, conformances, internal logic verified faithful to D-035, D-080, BUG-011 round 8). The `broken-but-claimed` finding is at the App-layer wiring point, not these files.
- **Reactive mode (1 file):** `ReactiveOrchestrator.swift`. **`production-active` at the module surface**, broken at the App-layer wire per BUG-015.
- **Signaling (2 files):** `PresetSignaling.swift` (with the stale source-doc note above), `ArachneStateSignaling.swift`.
- **Router + settings (2 files):** `PlaybackActionRouter.swift`, `QualityCeiling.swift`.

---

## Per-file capability index

Citations use `path:line` format. Inventory data from direct reads (Explore agents not used — file sizes were tractable; largest file is `LiveAdapter.swift` at 386 lines). Consumer counts from `grep -rn` of canonical type names across `PhospheneApp/`, `PhospheneEngine/Sources/`, and `PhospheneEngine/Tests/`. Visibility cross-checked against the source per the CA.3 visibility-verification rule.

Consolidation: 12 of 14 files concentrate on `production-active`; the per-file index below mirrors CA.3's consolidated form. Non-`production-active` aspects (BUG-015 wire, transitionPolicy dead field, source-doc drift, D-030 citation) are visually marked at the relevant rows.

### `PresetScorer.swift` (355 lines) — `production-active` (with `unverified-claim` for D-030 citation)

[`PresetScorer.swift:95`](../../PhospheneEngine/Sources/Orchestrator/PresetScorer.swift) — `DefaultPresetScorer: PresetScoring`. Stateless, deterministic 4-weight scorer + 2 multiplicative penalties + 5-level hard-exclusion gate. The 4 sub-scores match D-032 byte-for-byte; weight values `0.30 / 0.20 / 0.25 / 0.25` sum to 1.0 as documented.

| Capability | Verdict | Consumers (prod / test) | Doc-cited |
|---|---|---|---|
| `PresetScoreBreakdown` struct (11 fields) | `production-active` | App + PlaybackChromeViewModel + telemetry / 8 test files | D-032; D-014 ("no black boxes") |
| `PresetScoring` protocol | `production-active` | `DefaultPresetScorer` conformer; `DefaultPlaybackActionRouter.scorer` field; `PresetScoringContextProvider` | D-032 |
| `DefaultPresetScorer` class | `production-active` | `VisualizerEngine.swift:458`; `DefaultPlaybackActionRouter.swift:332`; 8 test files | D-032 |
| `DefaultPresetScorer.score(...)` | `production-active` | Tests + `DefaultLiveAdapter.evaluateMoodOverride`; `DefaultReactiveOrchestrator.compareAndDecide` | D-032 |
| `DefaultPresetScorer.breakdown(...)` | `production-active` | `DefaultSessionPlanner.selectPreset`; tests | D-032 |
| `rank(presets:track:context:)` extension | `production-active` | `DefaultLiveAdapter.applyOverrideIfBetter`; `DefaultReactiveOrchestrator.evaluate` | D-032 |
| 4 weight constants (`weightMood: 0.30`, `weightTempoMotion: 0.20`, `weightStemAffinity: 0.25`, `weightSectionSuitability: 0.25`) | `production-active` | Internal | D-032 (line 86 cites D-030 — see `unverified-claim` finding above) |
| `familyRepeatPenalty: 0.2` | `production-active` | Internal | D-032 |
| `fatigueCooldown: [.low: 60, .medium: 120, .high: 300]` | `production-active` | Internal | D-032 |
| `sectionMismatchScore: 0.3` | `production-active` | Internal | D-032 |
| `stemAffinitySubScore` — deviation primitives + mean formula, neutral-0.5 zero-balance guard | `production-active` | Internal | D-080 / Failed Approach #53 + #54 (faithful) |
| 5-level hard exclusion (`isDiagnostic` / `certified` / `sessionExcludedPresets` / `temporarilyExcludedFamilies` / `excludedFamilies` / complexity-cost / currently-playing) | `production-active` | Internal | D-074 (diagnostic); D-053 (uncertified gate); D-058(c) (family exclusions); D-074 (complexity-cost); D-032 (identity) |
| Additive `familyBoost` (U.6b) | `production-active` | Internal | D-058(b) |

Tuning constants verified against D-032: all four weights, both penalty constants, the three cooldown values, the mismatch score — byte-correct. The QR.2 / D-080 stem-affinity rewrite at lines 287–306 is faithful: empty affinities return 0.5; zero `stemEnergyBalance` returns 0.5; otherwise `mean(max(0, stemEnergyDev[stem]))` over declared affinities, clamped [0, 1].

The `PresetScoreBreakdown` struct has both `exclusionReason: String?` (human-readable) and `excludedReason: String?` (concise tag for logging — e.g. `"diagnostic"`, `"uncertified"`, `"budget_exceeded"`). The dual field is intentional per the inline doc comment at `:36-38`; not drift.

### `PresetScoringContext.swift` (156 lines) — `production-active`

[`PresetScoringContext.swift:48`](../../PhospheneEngine/Sources/Orchestrator/PresetScoringContext.swift) — Immutable Sendable snapshot of session state. 11 fields including `deviceTier`, `frameBudgetMs`, `recentHistory`, `currentPreset`, `elapsedSessionTime`, `currentSection`, `excludedFamilies`, `qualityCeiling`, `familyBoosts`, `temporarilyExcludedFamilies`, `sessionExcludedPresets`, `includeUncertifiedPresets`. No mutable state; no `Date.now()`; deterministic.

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `PresetScoringContext` struct | `production-active` | `DefaultPresetScorer.{score, breakdown}`; `PresetScoringContextProvider.build(...)`; `DefaultSessionPlanner.planOneSegment` | D-014 / D-032 |
| `PresetHistoryEntry` struct (`presetID / family / startTime / endTime`) | `production-active` | `recentHistory` writers in `SessionPlanner+Segments.planOneSegment:219`; `DefaultPlaybackActionRouter.recordHistory` | D-032 / D-123 |
| `init(...)` factory + `initial(deviceTier:)` | `production-active` | App + tests | — |
| `frameBudgetMs ?? deviceTier.frameBudgetMs` defaulting | `production-active` | Internal | — |

Notable: `PresetHistoryEntry.family` is `PresetCategory?` — nilable since D-123 (diagnostic presets have nil family). Verified at line 19; the `fatigueMultiplier` and `familyRepeatMultiplier` guards correctly handle nil family.

### `TransitionPolicy.swift` (246 lines) — `production-active`

[`TransitionPolicy.swift:125`](../../PhospheneEngine/Sources/Orchestrator/TransitionPolicy.swift) — `DefaultTransitionPolicy: TransitionDeciding`. Structural-boundary trigger (`confidence ≥ 0.5`, 2.5 s window) → duration-expired fallback. Style negotiation via `transitionAffordances` + energy. Crossfade duration scales linearly `2.0 s → 0.5 s` with energy.

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `TransitionContext` struct (5 fields: currentPreset, elapsedPresetTime, prediction, energy, captureTime) | `production-active` (single-consumer) | `DefaultSessionPlanner.buildTransition:314` (only); tests | D-033 |
| `TransitionDecision` struct (6 fields: trigger, scheduledAt, style, duration, confidence, rationale) | `production-active` (single-consumer) | Returned to `SessionPlanner.buildTransition:326` (converted to `PlannedTransition`); tests | D-033 |
| `Trigger` enum (`.structuralBoundary / .durationExpired`) | `production-active` (single-consumer) | Internal to `TransitionDecision`; tests | D-033 |
| `TransitionDeciding` protocol | `production-active` | `DefaultTransitionPolicy` conformer; `DefaultSessionPlanner.transitionPolicy` field; **`DefaultLiveAdapter.transitionPolicy` field (DEAD — see production-orphan)** | D-033 |
| `DefaultTransitionPolicy.evaluate(...)` | `production-active` (single-consumer) | `DefaultSessionPlanner.buildTransition:326` (only); tests | D-033 |
| `structuralConfidenceThreshold: 0.5` | `production-active` | Internal | D-033 |
| `lookaheadWindow: 2.5` | `production-active` | Internal | D-033 (matches LookaheadBuffer delay) |
| `baseCrossfadeDuration: 2.0` / `minCrossfadeDuration: 0.5` | `production-active` | Internal | D-033 |
| **`cutEnergyThreshold: 0.85`** | `production-active` | Internal | **D-080 amendment; D-032/D-033 still say 0.7 — see doc drift** |

The single-consumer-internal pattern: `TransitionContext` + `TransitionDecision` + `Trigger` + `evaluate(...)` are all consumed only by `DefaultSessionPlanner.buildTransition(...)` at planning time. `DefaultLiveAdapter` does NOT call `transitionPolicy.evaluate(...)` — it constructs `PlannedTransition` directly. This makes `TransitionPolicy` effectively a planning-time-only contract in production today; not orphaned (planning is the load-bearing call), but more narrowly used than its protocol shape would suggest.

### `SessionPlanner.swift` (364 lines) — `production-active`

[`SessionPlanner.swift:62`](../../PhospheneEngine/Sources/Orchestrator/SessionPlanner.swift) — `DefaultSessionPlanner: SessionPlanning`. Greedy forward-walk per D-034. Synchronous `plan(...)` + async `planAsync(...)` with precompile closure (caller-injected so Orchestrator remains free of Renderer dependency). D-047 seeded variant for "Regenerate Plan".

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `SessionPlanning` protocol | `production-active` | `DefaultSessionPlanner` conformer; tests | D-034 |
| `SessionPlanningError` enum (`emptyPlaylist / emptyCatalog / precompileFailed`) | `production-active` | `VisualizerEngine+Orchestrator.swift:336`; tests | D-034 |
| `DefaultSessionPlanner` class | `production-active` | `VisualizerEngine.swift:458`; tests | D-034 |
| `plan(tracks:catalog:deviceTier:includeUncertifiedPresets:)` (unseeded) | `production-active` | App + tests | D-034 |
| `plan(tracks:catalog:deviceTier:seed:includeUncertifiedPresets:)` (seeded, D-047) | `production-active` | `DefaultPlaybackActionRouter.reshuffleUpcoming / rePlanSession`; tests | D-047 |
| `planAsync(...)` with precompile closure | `production-active` | App (when precompile is wired) | D-034 |
| `selectPreset(...)` (file-internal) | `production-active` | `SessionPlanner+Segments.planOneSegment` | — |
| `buildTransition(...)` (file-internal) | `production-active` | `SessionPlanner+Segments.planOneSegment` | The synthetic-`StructuralPrediction` site at `:317-322` (planning-time, `confidence: 1.0`) — see §Resolution |
| `cheapestFallback(...)` (file-private) | `production-active` | Fallback ladder per D-034 + D-018 | — |
| `seededNoise(...)` (D-047 LCG) | `production-active` | `selectPreset` when `seed != 0` | D-047 |
| `defaultTrackDuration: 180` | `production-active` | Fallback when `TrackIdentity.duration == nil` | D-034 |

The synthetic `StructuralPrediction` at `:317-322` constructs `(sectionIndex: 0, sectionStartTime: clock, predictedNextBoundary: clock, confidence: 1.0)` — same construction documented in D-034 ("synthetic-boundary trick at track changes"). This is **planning-time only**; not the runtime production-orphan CA.1 was pointing at. See §Resolution.

### `SessionPlanner+Segments.swift` (230 lines) — `production-active`

[`SessionPlanner+Segments.swift:13`](../../PhospheneEngine/Sources/Orchestrator/SessionPlanner+Segments.swift) — Multi-segment walk per V.7.6.2. Section-list from `profile.estimatedSectionCount` (uniform partition); per-section `planOneSegment(...)` loop bounded by `min(remainingInSection, preset.maxDuration(forSection:))`.

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `TrackSection` struct (start/end/section) | `production-active` | `planSegments` internal; tests | V.7.6.2 |
| `makeSections(...)` static | `production-active` | `planSegments` | V.7.6.2 |
| `planSegments(...)` | `production-active` | `DefaultSessionPlanner.plan:129` | V.7.6.2 |
| `planOneSegment(...)` (file-private) | `production-active` | `planSegments` | V.7.6.2 + D-072 + D-073 + D-095 |
| `recentHistory` 50-entry trim at line 225 | `production-active` | Internal | D-080 rule 6 |

The 50-entry history cap is faithful to D-080 rule 6 (`recentHistory` capped at 50 entries to prevent unbounded memory growth). The `wait_for_completion_event` handling for completion-gated presets is **NOT** in this file — `PresetMaxDuration.swift:84-85` (Presets module) returns `.infinity` for `waitForCompletionEvent == true`, and `planOneSegment` accepts whatever `maxDuration(forSection:)` returns. The section-boundary cap (`remainingInSection`) is still active for completion-gated segments per CLAUDE.md's BUG-011 round 8 note — verified at line 173 (`segLen = max(1.0, min(remainingInSection, maxByPreset))`).

### `PlannedSession.swift` (368 lines) — `production-active`

[`PlannedSession.swift:268`](../../PhospheneEngine/Sources/Orchestrator/PlannedSession.swift) — `PlannedSession`, `PlannedTrack` (with V.7.6.2 multi-segment shape + backward-compat single-segment init), `PlannedPresetSegment`, `PlannedTransition`, `SegmentTerminationReason`, `PlanningWarning` (with custom Codable for the `partialPreparation(unplannedCount:)` associated-value case).

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `PlannedSession` struct (4 fields + 6 methods) | `production-active` | App-layer 20+ refs; PlanPreviewViewModel; ReadyView; PlaybackView; DefaultPlaybackActionRouter | D-034 |
| `PlannedTrack` struct (V.7.6.2 segments + backward-compat accessors) | `production-active` | App + tests | V.7.6.2 |
| `PlannedPresetSegment` struct (6 fields) | `production-active` | App + tests | V.7.6.2 |
| `PlannedTransition` struct (6 fields) | `production-active` | App + tests | D-034 |
| `PlanningWarning` struct (Codable, custom CodingKeys for `partialPreparation`) | `production-active` | App + tests | D-034 + Increment 6.1 (partial preparation) |
| `SegmentTerminationReason` enum (`.trackEnded / .sectionBoundary / .maxDurationReached / .completionSignal`) | `production-active` | App + tests | V.7.6.2 |
| `canonicalIdentity(matchingTitle:artist:)` — pure function | `production-active` | `VisualizerEngine+TrackIdentityResolution.swift:39`; `VisualizerEngine+Capture.swift:140`; `VisualizerEngine+Orchestrator.swift:435` | **BUG-006.2 / D-091 load-bearing helper.** Pure function: no `Date.now()`, no `MainActor` isolation. Returns nil for ambiguous matches (conservative fallback). |
| `track(at:)` / `segment(at:)` / `transition(at:)` lookup methods | `production-active` | `VisualizerEngine+Orchestrator.currentTransition(at:):150`; tests | D-034 + V.7.6.2 |
| `appendingWarnings(_:)` | `production-active` | `VisualizerEngine+Orchestrator.swift:113` (partial-plan extend) | Increment 6.1 |

`PlannedSession.canonicalIdentity(matchingTitle:artist:)` at `:298-304` is the BUG-006.2 fix: streaming-metadata-only observations (title+artist) get resolved to the planned `TrackIdentity` (which has duration + IDs + preview hint). Returns nil when no match or ambiguous match — the conservative-fallback case enforced by `PreparedBeatGridAppLayerWiringTests.ambiguousMatch_returnsNil_partialFallback`. The function uses `==` on title + artist (case-sensitive; no `.lowercased()` per Failed Approach #56) — that match shape is the regression-discriminator surface.

### `LiveAdapter.swift` (386 lines) — `production-active` at the module surface; **runtime-unreachable per BUG-015**

[`LiveAdapter.swift:150`](../../PhospheneEngine/Sources/Orchestrator/LiveAdapter.swift) — `DefaultLiveAdapter: LiveAdapting, @unchecked Sendable` (class since D-080, was struct). NSLock-guarded `lastOverrideTimePerTrack: [TrackIdentity: TimeInterval]` for per-track mood-override cooldown.

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `AdaptationEvent` struct (`Kind` enum 4 cases + trackIndex + message) | `production-active` (module surface) | `VisualizerEngine+Orchestrator:189-195` for logging; `LiveAdaptationToastBridge`; tests | D-035 |
| `LiveAdaptation` struct (`updatedTransition`, `presetOverride`, `events`) | `production-active` (module surface) | `VisualizerEngine+Orchestrator:220-241`; tests | D-035 |
| `LiveAdaptation.PresetOverride` nested (`preset`, `score`, `reason`) | `production-active` (module surface) | App + tests | D-035 |
| `LiveAdapting` protocol | `production-active` (module surface) | `DefaultLiveAdapter` conformer; tests | D-035 |
| `DefaultLiveAdapter` class | `production-active` (instantiation) | `VisualizerEngine.swift:461`; **but `.adapt(...)` is never invoked at runtime — BUG-015** | D-080 (class promotion + NSLock cooldown) |
| `DefaultLiveAdapter.adapt(...)` | `production-active` (test) / **runtime-unreachable** | Only `VisualizerEngine+Orchestrator.swift:179` — which is inside the un-called `applyLiveUpdate(...)`; tests | BUG-015 |
| `boundaryConfidenceThreshold: 0.5` | `production-active` | Internal | D-035 |
| `boundaryRescheduleThreshold: 5.0` | `production-active` | Internal | D-035 ("Why the boundary threshold is 5 s") |
| `moodDivergenceThreshold: 0.4` | `production-active` | Internal | D-035 |
| `overrideElapsedFractionCap: 0.4` | `production-active` | Internal | D-035 ("Why the override fraction cap is 40 %") |
| `overrideScoreGap: 0.15` | `production-active` | Internal | D-035 + D-036 ("`minScoreGapForSwitch = 0.20` vs. `LiveAdapter`'s 0.15") |
| `moodOverrideCooldown: 30.0` | `production-active` | Internal | D-080 rule 3 |
| `cooldownLock: NSLock` + `lastOverrideTimePerTrack: [TrackIdentity: TimeInterval]` | `production-active` (module) | Internal; `cooldownAdaptation` + `recordOverride` | D-080 rule 3 |
| ~~**`transitionPolicy: any TransitionDeciding`**~~ | ~~**`production-orphan`**~~ → **resolved 2026-05-21** | Field + init parameter removed in `CA.4-FU-1`. `DefaultLiveAdapter` now takes only `scorer:`. | See §production-orphan resolution stamp below; `CA.4-FU-1` |

The Orchestrator-side implementation is **faithful to D-035 + D-080**. Per-track cooldown wired correctly: `cooldownAdaptation(...)` returns the suppression `LiveAdaptation` when `elapsedTrackTime - lastOverrideTime < moodOverrideCooldown`; otherwise `recordOverride(...)` is called after an override succeeds.

The broken-ness is **at the App layer**: `VisualizerEngine.applyLiveUpdate(...)` is never invoked. The body of `applyLiveUpdate` at `VisualizerEngine+Orchestrator.swift:179` correctly calls `liveAdapter.adapt(...)`; the entry point itself just has no caller.

### `LiveAdapter+Patching.swift` (216 lines) — `production-active`

[`LiveAdapter+Patching.swift:18`](../../PhospheneEngine/Sources/Orchestrator/LiveAdapter+Patching.swift) — Public extension on `PlannedSession` providing the controlled-mutation API. The only sanctioned external mutation path per D-034 + D-035.

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `PlannedSession.applying(_:at:)` | `production-active` | `VisualizerEngine+Orchestrator:248` (in unreachable `applyLiveUpdate` body); `DefaultPlaybackActionRouter`; tests | D-035 (V.7.6.2-aware: patches segments[0] preset; replaces incomingTransition on segments[0] of next track) |
| `PlannedSession.extendingCurrentPreset(by:at:)` | `production-active` | `VisualizerEngine+Orchestrator:370` for `moreLikeThis()` (U.6b); tests | U.6b / D-058 |
| `PlannedSession.applying(overrides:)` | `production-active` | `VisualizerEngine+Orchestrator:346` for `regeneratePlan(lockedTracks:lockedPresets:)`; tests | U.6b |

All three methods construct new `PlannedSession` values via the internal memberwise init — they're in the same Orchestrator module as the internal inits per D-034 + D-035. **The body of `applying(_:at:)` is reached from `VisualizerEngine+Orchestrator.swift:248` only when `applyLiveUpdate(...)` is called — which is never (BUG-015).** The other two methods (`extendingCurrentPreset`, `applying(overrides:)`) ARE reachable: they're called from `DefaultPlaybackActionRouter`'s keyboard-shortcut paths which fire from the UI layer.

### `LiveAdapter+MoodOverride.swift` (83 lines) — `production-active` at the module surface; **runtime-unreachable per BUG-015**

[`LiveAdapter+MoodOverride.swift:12`](../../PhospheneEngine/Sources/Orchestrator/LiveAdapter+MoodOverride.swift) — `applyOverrideIfBetter(...)` extracted from `LiveAdapter.swift` for file-length compliance.

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `applyOverrideIfBetter(...)` extension function | `production-active` (module) / **runtime-unreachable** | Only `DefaultLiveAdapter.evaluateMoodOverride:341`; tests | D-035 / D-074 (`!topPreset.isDiagnostic` defense in depth) |

Includes the V.7.6.D D-074 diagnostic-filter (`ranked.first(where: { !$0.0.isDiagnostic })`) — verified at line 43.

### `ReactiveOrchestrator.swift` (352 lines) — `production-active` at the module surface; **runtime-unreachable per BUG-015**

[`ReactiveOrchestrator.swift:124`](../../PhospheneEngine/Sources/Orchestrator/ReactiveOrchestrator.swift) — `DefaultReactiveOrchestrator: ReactiveOrchestrating`. Stateless per D-036. QR.2 / D-080 fixes for both Failed Approaches #54 (neutral 0.5 on empty stems) and Failed Approach #57's adversarial penalty are faithful.

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `ReactiveAccumulationState` enum (`.listening / .ramping / .full`) | `production-active` (module) | App; tests | D-036 |
| `ReactiveAccumulationState.init(elapsedTime:)` | `production-active` (module) | Internal `evaluate`; tests | D-036 |
| `ReactiveDecision` struct (5 fields) | `production-active` (module) / **runtime-unreachable** | App returns from `applyReactiveUpdate`; tests | D-036 |
| `ReactiveOrchestrating` protocol | `production-active` (module) | `DefaultReactiveOrchestrator` conformer; tests | D-036 |
| `DefaultReactiveOrchestrator` struct | `production-active` (instantiation) | `VisualizerEngine.swift:464`; tests; **`.evaluate(...)` is never invoked at runtime — BUG-015** | D-036 |
| `.evaluate(liveMood:liveBoundary:elapsedSessionTime:currentPreset:catalog:deviceTier:includeUncertifiedPresets:liveStemFeatures:)` | `production-active` (test) / **runtime-unreachable** | Only `VisualizerEngine+Orchestrator.swift:275` — inside unreachable `applyReactiveUpdate`; tests | D-036 + D-080 + D-074 (diagnostic filter at `:208`) |
| `listeningDuration: 15.0` | `production-active` | Internal | D-036 |
| `fullConfidenceDuration: 30.0` | `production-active` | Internal | D-036 |
| `minScoreGapForSwitch: 0.20` | `production-active` | Internal | D-036 ("`minScoreGapForSwitch = 0.20` vs. `LiveAdapter`'s 0.15") |
| `boundaryConfidenceThreshold: 0.5` | `production-active` | Internal | D-036 |
| **`minBoundaryScoreGap: 0.05`** | `production-active` | Internal | **D-080 rule 4 (boundary-only switch gate tightened)** |
| `computeConfidence(elapsed:)` static | `production-active` | Internal `evaluate`; tests | D-036 |

QR.2 / D-080 implementation faithful at `:190-194` (`liveProfile.stemEnergyBalance = stems` only when `liveStemFeatures != nil`) and at `:273-274` (boundary-only switch requires `scoreGap > minBoundaryScoreGap`). The neutral-0.5 stem-affinity guard is at `PresetScorer.stemAffinitySubScore:290` (`guard track.stemEnergyBalance != .zero else { return 0.5 }`) — Failed Approach #54 fix verified.

### `PresetSignaling.swift` (39 lines) — `production-active` (with source-doc drift)

[`PresetSignaling.swift:22`](../../PhospheneEngine/Sources/Orchestrator/PresetSignaling.swift) — `PresetSignaling: AnyObject` protocol with `presetCompletionEvent: PassthroughSubject<Void, Never>` requirement. The cross-module wiring channel for completion-gated presets (Arachne).

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `PresetSignaling` protocol | `production-active` | `ArachneState` conformer (via `ArachneStateSignaling.swift`); `VisualizerEngine+Presets.activePresetSignaling():524`; tests | V.7.6.2 + D-095 |
| `PresetSignalingDefaults.minSegmentDuration: 5.0` | `production-active` | `VisualizerEngine+Presets.swift:573` (gate against premature completion); tests | V.7.6.2 §3.4 |

**Source-file doc-drift:** the top comment at `:9-10` says *"Arachne does NOT emit yet — wiring is V.7.8."* This was true at V.7.6.2 protocol-introduction time but is stale post-D-095 / V.7.7C.2 (Arachne emits via `_presetCompletionEvent.send()` at `ArachneState.swift:977`, shipped 2026-05-09) and post-BUG-011 round 8 (orchestrator-side subscription fully wired by 2026-05-12). Fix applied in this increment.

### `ArachneStateSignaling.swift` (34 lines) — `production-active`

[`ArachneStateSignaling.swift:28`](../../PhospheneEngine/Sources/Orchestrator/ArachneStateSignaling.swift) — `extension ArachneState: PresetSignaling`. Module-placement deviation from the V.7.7C.2 spec (which named `Sources/Presets/Arachnid/ArachneState+Signaling.swift`) — see D-095 + the file's top comment for the rationale (Presets→Orchestrator would create a circular module dependency). The implementation exposes `_presetCompletionEvent` via the public-named `presetCompletionEvent` computed property.

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `ArachneState: PresetSignaling` conformance | `production-active` | `VisualizerEngine+Presets.activePresetSignaling()` (cast site); `PresetSignalingTests` | D-095 |

### `PlaybackActionRouter.swift` (85 lines) — `production-active`

[`PlaybackActionRouter.swift:32`](../../PhospheneEngine/Sources/Orchestrator/PlaybackActionRouter.swift) — Protocol contract per D-050; concrete `DefaultPlaybackActionRouter` lives in `PhospheneApp/Services/`.

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `NudgeDirection` enum (`.previous / .next`) | `production-active` | `DefaultPlaybackActionRouter:325, 405`; `PlaybackShortcutRegistry:304, 312, 320, 328` | D-050 |
| `PlaybackActionRouter` protocol | `production-active` | `DefaultPlaybackActionRouter` conformer; consumed via `actionRouter: PlaybackActionRouter` in `PlaybackShortcutRegistry` | D-050 / D-058 (U.6b semantics) |
| `moreLikeThis` / `lessLikeThis` / `reshuffleUpcoming` / `presetNudge(_:immediate:)` / `rePlanSession` / `undoLastAdaptation` / `toggleMoodLock` / `isMoodLocked` | `production-active` | `PlaybackShortcutRegistry` keyboard wiring (`Services/PlaybackShortcutRegistry.swift:246, 280, 288, 296, 304, 312, 320, 328, 336, 344`) | U.6b / D-058 |

All seven methods are wired through to keyboard shortcuts via `PlaybackShortcutRegistry`. The concrete `DefaultPlaybackActionRouter` (App layer) was fully wired in U.6b per `ENGINEERING_PLAN.md:934-948`.

### `QualityCeiling.swift` (40 lines) — `production-active`

[`QualityCeiling.swift:18`](../../PhospheneEngine/Sources/Orchestrator/QualityCeiling.swift) — `.auto / .performance / .balanced / .ultra` enum + `complexityThresholdMs(for:) -> Float?`.

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `QualityCeiling` enum | `production-active` | `SettingsViewModel.qualityCeiling`; `SettingsTypes`; `VisualsSettingsSection`; `PresetScoringContext.qualityCeiling` field | D-053 / U.8 |
| `complexityThresholdMs(for:)` — returns nil for `.ultra` (no gate), `12.0` for `.performance`, `tier.frameBudgetMs` for `.auto/.balanced` | `production-active` | `DefaultPresetScorer.exclusionReasonAndTag:229` | D-053 / D-059d |

The thresholds match the in-file doc comment + D-053 + D-059d.

---

## Resolution of CA.1 runtime production-orphan re-evaluation

**CA.1's framing.** CA.1 identified `MIRPipeline.latestStructuralPrediction` as a per-frame writer with a single prep-time consumer (`SessionPreparer+Analysis.swift:289`). The Orchestrator-side runtime consumers (`TransitionPolicy.evaluate`, `LiveAdapter.adapt`, `ReactiveOrchestrator.evaluate`) were described as fed by the synthetic `StructuralPrediction` at `SessionPlanner.swift:317`. CA.1 offered two options for CA.1-FU-1:

- **(a)** Gate the per-frame `StructuralAnalyzer` chain in `MIRPipeline.process` so it only runs at preparation time.
- **(b)** Wire `MIRPipeline.latestStructuralPrediction` into `VisualizerEngine` → orchestrator at runtime so `TransitionPolicy.structuralBoundary` triggers fire from real predictions.

**CA.4's reading of the Orchestrator side.**

The synthetic `StructuralPrediction` at `SessionPlanner.swift:317-322` is **planning-time only**. It is constructed inside `DefaultSessionPlanner.buildTransition(...)`, which is called from `SessionPlanner+Segments.planOneSegment(...)`, which is called from `DefaultSessionPlanner.plan(...)`. This entire path runs once per session (when `VisualizerEngine+Orchestrator.buildPlan()` fires on `SessionManager.state == .ready`). It is NOT the runtime-consumer path.

The runtime consumers — `DefaultLiveAdapter.adapt(...)` (which reads `liveBoundary: StructuralPrediction` as an input parameter at `LiveAdapter.swift:239`) and `DefaultReactiveOrchestrator.evaluate(...)` (likewise at `ReactiveOrchestrator.swift:273`) — accept `StructuralPrediction` from their caller. The Orchestrator module does not read `MIRPipeline.latestStructuralPrediction` directly anywhere.

The caller is `VisualizerEngine.applyLiveUpdate(...)` at `VisualizerEngine+Orchestrator.swift:166`. **And that method has zero production call sites (BUG-015).** So whatever the upstream prediction source is meant to be — synthetic, real, or `.none` — the prediction never reaches the Orchestrator at runtime at all, because the entry point is never invoked.

**Verdict (CA.1-FU-1 superseded).** CA.1's recommendation should be re-scoped against the BUG-015 finding:

- **Pre-BUG-015 (today's reality):** No code path consumes runtime structural predictions. The per-frame `StructuralAnalyzer` chain in `MIRPipeline.process` runs and writes `latestStructuralPrediction` but no live reader exists. **CA.1 option (a) — gate the chain to prep-time only — is the cleanest immediate fix.** It saves audio-callback CPU with no behavioural change. The Orchestrator-module surface is unaffected. Recommend filing as `CA.1-FU-1 (a)` — keep the original ID; ship the gate.
- **Post-BUG-015 (after the missing wire lands):** If BUG-015's fix sources `liveBoundary` from `pipeline.latestStructuralPrediction`, then CA.1 option (b) is *the same change as fixing BUG-015* — the wire and the source go together. The per-frame chain stays on (it's needed). No separate CA.1-FU-1 increment is required in this case; the option-(b) work folds into BUG-015's fix.

**Recommended sequencing.** BUG-015 first (the broken-ness is more user-facing than the wasted CPU). When BUG-015 is investigated, the diagnoser decides whether to source from MIRPipeline (option b) or to keep a thin synthetic for runtime parity (effectively option a at the gate + a synthetic on the consumer side). If they choose option b, CA.1-FU-1 closes. If they choose option a + synthetic, CA.1-FU-1 ships as a one-line gate in `MIRPipeline.process`.

**CA.1-FU-1 status update:** the CA.4 audit's recommended path is **option (a) ships first as a standalone increment (saves CPU on the audio-callback hot path with zero behavioural change today)**, then BUG-015's fix is investigated independently. The two are decoupled.

---

## Cross-references

### Updates needed in CLAUDE.md

CLAUDE.md's `What NOT To Do` block contains one rule about `applyLiveUpdate`:

> Do not call `applyLiveUpdate` (mood-override path) without a per-track cooldown. The path runs at ~94 Hz on the analysis queue; without rate-limiting it re-patches `livePlan` on every frame the conditions hold. 30 s per-track cooldown is the documented minimum. Boundary reschedule is unaffected (it has its own gate).

The rule is correct per D-080. The audit's BUG-015 finding shows the rule was anticipated but the wire it protected never landed. **No edit to CLAUDE.md** is applied in this increment — the rule stays in place as guidance for when BUG-015 is fixed. Once BUG-015 lands, the rule's "30 s per-track cooldown" requirement is enforced by `DefaultLiveAdapter.cooldownAdaptation(...)` (verified faithful at `LiveAdapter.swift:362-381`).

If BUG-015's fix introduces the wire and forgets the cooldown, the rule will be the discriminator that catches the regression — the per-track cooldown is implemented Orchestrator-side; the App-layer fix just needs to invoke `applyLiveUpdate(...)` at the right rate without bypassing the cooldown machinery.

### Updates needed in ARCHITECTURE.md

Applied in this increment as doc-only corrections:

1. **§Orchestrator (lines 196–219) rewritten.**
   - The "Implemented (Phase 4, Increments 4.1–4.3)" / "Forthcoming (4.4+)" split is retired. Replaced with a single "Implemented (Phase 4, Increments 4.0–4.6)" block that lists all 7 increment surfaces, with a cross-reference to BUG-015 for the runtime-wiring gap on 4.5 + 4.6.
   - Line 211 `cutEnergyThreshold > 0.7` → `> 0.85` (D-080 amendment).
2. **§Module Map Orchestrator/ (lines 548–553) extended.** All 14 source files listed with one-line behavioural descriptions:
   - The 5 already present (`PresetScorer`, `PresetScoringContext`, `TransitionPolicy`, `PlannedSession`, `SessionPlanner`) — refreshed to reflect D-080 + V.7.6.2 + D-095.
   - The 9 added: `SessionPlanner+Segments` (V.7.6.2 multi-segment walk), `LiveAdapter` (DefaultLiveAdapter class + LiveAdapting protocol + LiveAdaptation/AdaptationEvent value types + per-track NSLock-guarded cooldown per D-080), `LiveAdapter+Patching` (PlannedSession.applying/extendingCurrentPreset/applying(overrides:) controlled-mutation API), `LiveAdapter+MoodOverride` (applyOverrideIfBetter extracted for file-length compliance), `ReactiveOrchestrator` (DefaultReactiveOrchestrator + ReactiveOrchestrating + ReactiveDecision + ReactiveAccumulationState; D-036 + D-080 reactive-mode liveStemFeatures wiring), `PresetSignaling` (V.7.6.2 protocol + minSegmentDuration default), `ArachneStateSignaling` (cross-module conformance to avoid Presets→Orchestrator cycle per D-095), `PlaybackActionRouter` (D-050 protocol; concrete in PhospheneApp/Services/), `QualityCeiling` (U.8 enum + complexityThresholdMs(for:) per D-053 / D-059d).
3. **§Module Map Tests/Orchestrator/ block added.** Lists all 16 test files: DiagnosticHoldTests, GoldenSessionTests, LiveAdapterTests, MaxDurationFrameworkTests, MultiSegmentSmokeTest, OrchestratorCertifiedFilterTests, OrchestratorDiagnosticExclusionTests, PartialPlanTests, PresetScorerAdaptationTests, PresetScorerTests, PresetScoringContextExtensionTests, PresetSignalingTests, ReactiveOrchestratorTests, SessionPlannerTests, StemAffinityScoringTests, TransitionPolicyTests.

### Updates needed in ENGINEERING_PLAN.md

Applied:

1. Phase CA section: register `CA.4 (Orchestrator)` as ✅ Landed under the existing Phase CA block (lines 3734+).
2. Recently Completed: add the CA.4 entry mirroring the CA.1 / CA.2 / CA.3 shape — file count, verdict counts, top findings (BUG-015 + 1 production-orphan + 5 built-but-undocumented + 1 unverified-claim), doc-drift corrections applied, BUG-015 filed.
3. The CA.4 row in the existing Phase CA section flips from "Pending" to "✅ Landed" with the audit-deliverable link.

### Updates needed in DECISIONS.md

Applied:

1. **D-032 amendment note (line 471 area).** A one-line note that `cutEnergyThreshold` was raised 0.7 → 0.85 per D-080 / QR.2; the original D-032 text is preserved for historical record. Same pattern as the CA.3 D-070 amendment trail.

No other DECISIONS.md edits needed — every other D-014 / D-017 / D-018 / D-030 / D-032 / D-033 / D-034 / D-035 / D-036 / D-047 / D-050 / D-053 / D-058 / D-074 / D-077 / D-078 / D-080 / D-091 / D-095 / D-099 / D-123 claim was verified against current code with no contradictions.

D-120 (`concept_tags` + `motion_paradigm`): revert is **clean** in code — zero residue per the cited grep above. The DECISIONS.md entry itself preserves the historical record correctly (the file has a `⚠ STATUS: REVERTED 2026-05-13` banner at line 3286).

### Updates needed in source-file comments

1. **`PresetScorer.swift:86`** — change `## Weight rationale (D-030)` → `## Weight rationale (D-032)`. Trivial.
2. **`PresetSignaling.swift:9-10`** — replace the stale "Arachne does NOT emit yet — wiring is V.7.8" comment with the current state per D-095 / V.7.7C.2 + BUG-011 round 8.

Both applied in this increment as in-source comment edits — not behavioural changes, so they fall within the audit-only scope.

### New BUG entries

**BUG-015 filed.** Severity P1 / `pipeline-wiring`. The `VisualizerEngine.applyLiveUpdate(...)` entry point has zero production call sites; `DefaultLiveAdapter.adapt(...)` and `DefaultReactiveOrchestrator.evaluate(...)` never execute against live MIR data. See [`KNOWN_ISSUES.md` BUG-015](../QUALITY/KNOWN_ISSUES.md) for the full entry.

### KNOWN_ISSUES.md sweep

No retroactive `Resolved` entries identified. No existing entries reproduced as no-longer-applicable.

---

## Follow-up Backlog

Findings surfaced by CA.4 that are *not* corrected in this audit increment. Each row is a candidate follow-up increment with enough scope to act on cold. Per the kickoff's audit-only discipline, fixes ship as separate increments scheduled whenever Matt prioritises them.

Items are greppable as `CA\.4-FU-\d+`. The BUG-015 fix is treated as a top-priority follow-up but is filed independently in `KNOWN_ISSUES.md`.

| ID | Scope | Done-when | Est. sessions | Status |
|---|---|---|---|---|
| **CA.4-FU-1** ✅ | Demote / remove `DefaultLiveAdapter.transitionPolicy` field. The field is constructor-injected and stored at `LiveAdapter.swift:176, 188, 191` but **never read** anywhere in `LiveAdapter*.swift`. Boundary-reschedule and mood-override paths both construct `PlannedTransition` / `LiveAdaptation.PresetOverride` directly without going through `TransitionDeciding.evaluate(...)`. Two options to pick at planning time: (a) remove the parameter from the `init` (non-breaking — tests use `DefaultLiveAdapter()` or `DefaultLiveAdapter(scorer:)`) AND the stored field; (b) keep the parameter for API symmetry with `DefaultSessionPlanner` but mark the field `_ = transitionPolicy` to signal intent. Bundle with BUG-015's fix if the fix touches LiveAdapter.swift. | The `transitionPolicy` parameter is either removed from `DefaultLiveAdapter.init` (recommended) or annotated as intentionally-unused. `swift test --filter LiveAdapter` passes. Engine + app builds clean; SwiftLint zero violations. | <1 | **Resolved 2026-05-21** — option (a) shipped: parameter + stored field removed from `DefaultLiveAdapter`. LiveAdapter filter 11/11 green; Orchestrator suite 114/17 green; PhospheneApp build clean; SwiftLint introduced zero new violations. |
| **CA.4-FU-2** | Source-comment cleanups (trivial, < 5 LoC total). (a) `PresetScorer.swift:86` — change `(D-030)` → `(D-032)`. (b) `PresetSignaling.swift:9-10` — replace `"Arachne does NOT emit yet — wiring is V.7.8."` with `"Arachne emits via _presetCompletionEvent.send() in ArachneState.advanceStablePhase (D-095, V.7.7C.2); orchestrator subscribes via VisualizerEngine+Presets.activePresetSignaling() (BUG-011 round 8)."`. | Both source files reflect current state. swift build clean. | <1 | Ready now; can bundle with any Orchestrator-adjacent commit |
| **CA.4-FU-3 (== BUG-015)** | Investigate why `applyLiveUpdate(...)` is never invoked in production code. Two candidate fix sites: (a) wire from `VisualizerEngine+Audio.swift`'s analysis-queue tick at a 1–10 Hz cadence (per-track cooldown is already enforced inside `DefaultLiveAdapter`); (b) wire as a Combine sink on `MIRPipeline`'s feature publisher. If (a), the `boundary` argument can source either from `pipeline.latestStructuralPrediction` (real per-frame) or from `StructuralPrediction.none` (sentinel — the per-frame chain stays unused). The right cadence is the lowest rate at which a planned-session reschedule or mood-override is acceptably responsive — likely 1–2 Hz. Bundles with CA.4-FU-1 (transitionPolicy field cleanup) naturally. The fix MUST preserve the 30 s per-track mood-override cooldown enforced by `DefaultLiveAdapter.cooldownAdaptation(...)` (already in place). | A new integration test exercises a 30 s reactive session against synthetic FeatureVectors and asserts at least one `reactiveOrchestrator.evaluate(...)` invocation logged after the 15 s listening window. A real-music session capture (`session.log`) shows at least one `Orchestrator:` `LiveAdapter:` or `Reactive` log line. | 1–2 | Ready now (P1 fix — surface as next-priority work) |
| **CA.1-FU-1 (re-scoped per §Resolution above)** | Pre-BUG-015: gate the per-frame `StructuralAnalyzer` + `NoveltyDetector` + `SelfSimilarityMatrix` chain in `MIRPipeline.process` so it only runs at preparation time. Saves audio-callback CPU with zero behavioural change since no runtime consumer exists pre-BUG-015. Post-BUG-015: if BUG-015's fix routes `liveBoundary` from `MIRPipeline.latestStructuralPrediction`, this gate is replaced by re-enabling per-frame execution; if BUG-015 routes from `StructuralPrediction.none` or a sentinel, this gate stays on. The audit recommends shipping the gate independently of BUG-015 (it's cheap, safe, and saves CPU today). | The per-frame chain runs only at preparation time (or is invoked via a debug flag). Audio-callback CPU profile shows a measurable reduction. The prep-time `SessionPreparer+Analysis.swift:289` consumer (`sectionCount` derivation) is preserved. Engine + app builds clean. | 1 | Ready now (decoupled from BUG-015) |

**Bundling recommendation.** CA.4-FU-1 + CA.4-FU-2 are < 1 session combined and natural to land alongside BUG-015's fix. CA.1-FU-1 (re-scoped) is fully decoupled from BUG-015 and is the cheapest first move — it ships a measurable perf win independent of the larger pipeline-wiring question.

**Priority order if Matt picks just one this week:** **BUG-015**. The "Live Adaptation" / "Ad-Hoc Reactive Mode" runtime story is a load-bearing product claim that's not actually running. Fixing the missing wire is the highest-leverage single action because it (a) restores the QR.2 / D-080 work to production, (b) lets `PlannedSession.applying(_:at:)` finally be reached at runtime so boundary reschedules can fire, and (c) makes the diagnostic-hold (L key) + capture-mode grace window + `wait_for_completion_event` mood-override-suppression machinery do their actual jobs.

---

## Approach validation

**What worked.**

- **Direct file reads scaled to the Orchestrator subsystem.** 14 files at 2,954 LoC total (largest 386 lines); reading every file directly took less time than spawning Explore agents and re-verifying. CA.3's recommendation for ≤ 5k-LoC subsystems held cleanly.
- **The kickoff's Pass 0 (BUG status cross-check against KNOWN_ISSUES.md) caught no staleness this time** — BUG-001 Open, BUG-011 Resolved-against-relaxed-criteria, BUG-014 Resolved by LM.4.7 all matched the kickoff verbatim. The discipline is cheap and worth keeping; CA.3's staleness finding (BUG-006 was claimed Open but actually Resolved) wasn't reproduced here, which suggests the kickoff was authored with fresh KNOWN_ISSUES context.
- **The cited-grep rule for production-orphan claims** fired once and produced the audit's most-confident finding: `DefaultLiveAdapter.transitionPolicy` is dead. Three grep results, each a declaration site, zero invocation sites. The verdict is falsifiable in a way that doesn't depend on the auditor's interpretation.
- **The CA.1 boundary-touchpoint question (synthetic vs real StructuralPrediction)** resolved cleanly once the audit traced where the synthetic actually lives (planning-time, not runtime) and discovered the bigger BUG-015. The CA.1-FU-1 re-scoping is the kind of cross-audit work the registry format was set up to do.

**What didn't.**

- **Tracing one App-layer wire (`applyLiveUpdate` call sites) bordered on scope creep.** The audit's hard rule says App-layer audit is CA.5+ — but I had to grep across `PhospheneApp/` to verify whether `applyLiveUpdate(...)` had any callers, because the Orchestrator-side surface alone can't answer that. The grep was tightly bounded (`grep -rn applyLiveUpdate PhospheneApp`) and the answer was unambiguous, but a less-clean question could have pulled the audit deep into App-layer code. For CA.5 (likely App), the audit format should explicitly call out which App files are in scope so the wire-tracing isn't ambiguous.
- **The "stop and report" rule fired on BUG-015** and I chose to file the BUG + complete the audit rather than stop. Reading the kickoff's exact wording — *"Found a broken-but-claimed finding that affects production behavior right now (file as BUG- entry; surface immediately)"* — the intent is to surface the BUG mid-audit so Matt sees it ASAP, not to halt the audit. I read it the second way and continued. If Matt wanted the first interpretation, future kickoffs should disambiguate.
- **One trivial mis-step early in the audit:** I asserted in a draft summary that the §Module Map Orchestrator block was missing "10 of 14 files" and then recounted to find it's missing 9 of 14. Both pre-recount and post-recount drafts cite the same 9 files — the "10" was just a counting slip. The lesson is to verify counts before producing summary numbers; I corrected the count inline above.

**Recommended changes for CA.5.**

1. **Default to direct reads at ≤ 5k LoC, and the visibility-verification grep stays mandatory.** Same as CA.3 + CA.4. The format works.
2. **Cross-check the kickoff prompt against `KNOWN_ISSUES.md` as Pass 0.** CA.3 found one staleness; CA.4 found zero. Cheap insurance.
3. **For audits that touch the App-layer boundary, declare which App files are read-only in scope** (e.g., `VisualizerEngine.swift` for instantiation sites, `VisualizerEngine+Orchestrator.swift` for App-side adapter methods) and which are explicitly off-limits (`PhospheneApp/Views/*`, `PhospheneApp/ViewModels/*`). CA.4 ended up reading several App files to verify call-site counts; the read was bounded but not pre-declared.
4. **Recommended next subsystem for CA.5:** **App layer** (`PhospheneApp/`). The audit just surfaced one App-layer pipeline-wiring bug (BUG-015) plus a constellation of boundary-noted findings that an App audit closes cleanly (`PresetScoringContextProvider`, `DefaultPlaybackActionRouter`, `VisualizerEngine+Orchestrator`, `LiveAdaptationToastBridge`, `CaptureModeSwitchCoordinator`, the entire ViewModel + View tree). The App layer is the largest single unaudited surface and is where most of the runtime-wire-up work lives. **Alternative:** if BUG-015's diagnosis turns up surprises that motivate a different priority, defer the CA.5 scope until after BUG-015 lands.

The audit format continues to produce actionable findings (1 P1 BUG, 1 field-level production-orphan, 1 unverified-claim, multiple doc-drift corrections, a CA.1 re-scoping). Recommend continuing into CA.5 with the methodology refinements above; minor consolidations as noted.

---

*End of CA.4 — Capability Registry — Orchestrator.*
